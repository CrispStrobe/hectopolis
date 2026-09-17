#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""T-303: turn an open land-cover extract into a Hectopolis level.

Reads a GeoPackage or GeoJSON of land-cover polygons in a metric CRS, samples
it onto the game's 1 ha grid, maps the source classes to tile types and writes
a level JSON in the T-301 format.

Deliberately stdlib-only for I/O. A GeoPackage is a SQLite database, which
Python reads natively, so no GDAL, fiona or geopandas is needed -- and a
contributor does not have to install a geo stack to build a level. `shapely`
is used when it is importable (much faster point-in-polygon and a spatial
index) and a pure-Python ray-caster stands in when it is not.

The raw data never enters the repository: it belongs in
/mnt/storage/code/stadtbau/data (see CLAUDE.md). What lands in the repo is the
generated level, which carries the attribution the licence requires.

Usage:
  tools/level_from_landcover.py --input <file.gpkg|file.geojson> \
      --origin 32400000,5700000 --size 32x32 --id ruhr \
      [--layer <table>] [--class-field <column>] [--mapping <file.json>] \
      [--samples 5] [--linear-share 0.12] [--out data/levels/NN_id.json] \
      [--preview]

--origin is the south-west corner in the data's own CRS, in metres.
"""
import argparse
import json
import os
import sqlite3
import struct
import sys
from collections import Counter

CELL_M = 100.0  # one tile is one hectare; see docs/model/tiles.md

LEVEL_DART = "packages/stadtbau_sim/lib/src/level.dart"


def read_legend(repo_root):
    """The level map legend, parsed out of level.dart.

    Duplicating the table here would be a second place to forget a tile, and
    the Dart map is the one the game actually reads, so it is the source.
    """
    path = os.path.join(repo_root, LEVEL_DART)
    try:
        src = open(path, encoding="utf-8").read()
    except OSError:
        die(f"cannot read {path}; run this from the repository root")
    start = src.index("const Map<String, TileType> levelMapLegend = {")
    body = src[start:src.index("};", start)]
    legend = {}
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("'"):
            continue
        char = line[1]
        tile = line.split("TileType.")[1].rstrip(",")
        legend[char] = _snake(tile)
    if not legend:
        die("could not parse levelMapLegend out of level.dart")
    return legend


def _snake(camel):
    out = []
    for ch in camel:
        if ch.isupper():
            out.append("_")
            out.append(ch.lower())
        else:
            out.append(ch)
    return "".join(out)

try:
    import shapely
    from shapely import STRtree, from_wkb
    HAVE_SHAPELY = True
except ImportError:  # pragma: no cover - exercised by --no-shapely
    HAVE_SHAPELY = False


def die(msg):
    sys.stderr.write(f"level_from_landcover: {msg}\n")
    sys.exit(1)


# --------------------------------------------------------------------------
# Reading polygons


def read_geopackage(path, layer, fields, bbox):
    """Yields (class value, wkb) for features of `layer` intersecting bbox.

    GeoPackage geometry is a small header (magic, version, flags, srs_id and an
    optional envelope) followed by standard WKB -- see OGC 12-128r19 §2.1.3.
    The envelope in the header is enough to reject most features without
    parsing any geometry at all.
    """
    # nolock: the raw data lives on a CIFS mount (see CLAUDE.md), where
    # SQLite cannot take its usual locks. The file is opened read-only.
    con = sqlite3.connect(f"file:{path}?mode=ro&nolock=1", uri=True)
    con.row_factory = sqlite3.Row
    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM gpkg_contents WHERE data_type='features'")]
    if not tables:
        die(f"{path} has no feature tables")
    if layer is None:
        if len(tables) > 1:
            die(f"{path} has several feature tables, pass --layer: "
                + ", ".join(tables))
        layer = tables[0]
    elif layer not in tables:
        die(f"{path} has no feature table {layer!r}; it has: "
            + ", ".join(tables))

    geom_col = con.execute(
        "SELECT column_name FROM gpkg_geometry_columns WHERE table_name=?",
        (layer,)).fetchone()
    if geom_col is None:
        die(f"{layer} has no geometry column registered")
    geom_col = geom_col[0]

    columns = [r[1] for r in con.execute(f'PRAGMA table_info("{layer}")')]
    if not fields:
        die(f"pass --class-field or --profile; {layer} has: "
            + ", ".join(columns))
    missing = [f for f in fields if f not in columns]
    if missing:
        die(f"{layer} has no column(s) {', '.join(missing)}; it has: "
            + ", ".join(columns))
    select = ", ".join(f't."{f}"' for f in fields)

    minx, miny, maxx, maxy = bbox
    # The r-tree index is optional in a GeoPackage, so fall back to a scan
    # filtered on the geometry header's own envelope.
    rtree = f"rtree_{layer}_{geom_col}"
    has_rtree = con.execute(
        "SELECT 1 FROM sqlite_master WHERE name=?", (rtree,)).fetchone()
    if has_rtree:
        sql = (f'SELECT {select}, t."{geom_col}" AS geom '
               f'FROM "{layer}" t JOIN "{rtree}" r ON r.id = t.rowid '
               f'WHERE r.maxx >= ? AND r.minx <= ? '
               f'AND r.maxy >= ? AND r.miny <= ?')
        rows = con.execute(sql, (minx, maxx, miny, maxy))
    else:
        # A GeoPackage need not carry the index; scan and reject on the
        # geometry header's envelope instead.
        rows = con.execute(
            f'SELECT {select}, t."{geom_col}" AS geom FROM "{layer}" t')

    kept = 0
    for row in rows:
        blob = row["geom"]
        if blob is None:
            continue
        wkb, env = _strip_gpkg_header(blob)
        if env is not None:
            if env[1] < minx or env[0] > maxx or env[3] < miny or env[2] > maxy:
                continue
        yield {f: row[f] for f in fields}, wkb
        kept += 1
    con.close()
    if kept == 0:
        die("no features in that extent -- check --origin and the data's CRS")


def _strip_gpkg_header(blob):
    """Returns (wkb, envelope or None) for a GeoPackage geometry blob."""
    if blob[:2] != b"GP":
        return blob, None  # already plain WKB
    flags = blob[3]
    env_kind = (flags >> 1) & 0x07
    little = flags & 0x01
    n_doubles = {0: 0, 1: 4, 2: 6, 3: 6, 4: 8}.get(env_kind)
    if n_doubles is None:
        die("unknown GeoPackage envelope indicator")
    head = 8 + 8 * n_doubles
    env = None
    if n_doubles:
        fmt = ("<" if little else ">") + "d" * n_doubles
        vals = struct.unpack_from(fmt, blob, 8)
        env = (vals[0], vals[1], vals[2], vals[3])  # minx maxx miny maxy
        env = (env[0], env[2], env[1], env[3])      # -> minx miny maxx maxy
    return blob[head:], env


def read_geojson(path, fields, bbox):
    """Yields (attributes, rings) for polygon features intersecting bbox."""
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    feats = doc.get("features") if isinstance(doc, dict) else None
    if feats is None:
        die(f"{path} is not a GeoJSON FeatureCollection")
    minx, miny, maxx, maxy = bbox
    kept = 0
    for f in feats:
        props = f.get("properties") or {}
        missing = [k for k in fields if k not in props]
        if missing:
            die(f"a feature has no property {', '.join(missing)}; it has: "
                + ", ".join(sorted(props)))
        for rings in _geojson_polygons(f.get("geometry") or {}):
            xs = [p[0] for r in rings for p in r]
            ys = [p[1] for r in rings for p in r]
            if not xs or max(xs) < minx or min(xs) > maxx:
                continue
            if max(ys) < miny or min(ys) > maxy:
                continue
            yield {k: props[k] for k in fields}, rings
            kept += 1
    if kept == 0:
        die("no polygons in that extent -- check --origin and the data's CRS")


def _geojson_polygons(geom):
    kind = geom.get("type")
    if kind == "Polygon":
        yield geom["coordinates"]
    elif kind == "MultiPolygon":
        yield from geom["coordinates"]
    elif kind == "GeometryCollection":
        for g in geom.get("geometries", []):
            yield from _geojson_polygons(g)
    # Points and lines carry no area, so they cannot claim a cell.


# --------------------------------------------------------------------------
# WKB -> rings, and point-in-polygon, for when shapely is not installed


def wkb_polygons(wkb):
    """Minimal WKB reader: polygons and multipolygons, 2D, either byte order."""
    pos = 0

    def take(fmt, size):
        nonlocal pos
        v = struct.unpack_from(fmt, wkb, pos)
        pos += size
        return v

    def geometry():
        nonlocal pos
        order = "<" if wkb[pos] == 1 else ">"
        pos += 1
        (kind,) = take(order + "I", 4)
        dims = 2 + (1 if 1000 <= kind % 4000 < 2000 else 0)  # Z
        base = kind % 1000
        if base == 3:  # polygon
            (n_rings,) = take(order + "I", 4)
            rings = []
            for _ in range(n_rings):
                (n_pts,) = take(order + "I", 4)
                pts = take(order + f"{n_pts * dims}d", 8 * n_pts * dims)
                rings.append([(pts[i * dims], pts[i * dims + 1])
                              for i in range(n_pts)])
            return [rings]
        if base in (6, 7):  # multipolygon, geometrycollection
            (n,) = take(order + "I", 4)
            out = []
            for _ in range(n):
                out.extend(geometry())
            return out
        if base in (1, 2):  # point, linestring: no area
            return []
        die(f"WKB geometry type {kind} is not supported")

    return geometry()


def point_in_rings(x, y, rings):
    """True when (x, y) is inside the outer ring and in none of the holes."""
    if not _ray_cast(x, y, rings[0]):
        return False
    return not any(_ray_cast(x, y, hole) for hole in rings[1:])


def _ray_cast(x, y, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y):
            t = (y - yi) / (yj - yi)
            if x < xi + t * (xj - xi):
                inside = not inside
        j = i
    return inside


# --------------------------------------------------------------------------
# Sampling onto the 1 ha grid


class Sampler:
    """Answers "which feature covers this point?" for many points."""

    def __init__(self, features):
        # features: list of (attributes, geometry). With shapely a geometry is
        # a shapely object in an STRtree; without it, a list of rings.
        self.attrs = [a for a, _ in features]
        if HAVE_SHAPELY:
            self.geoms = [g for _, g in features]
            self.tree = STRtree(self.geoms)
        else:
            self.polys = [g for _, g in features]
            self.boxes = []
            for rings in self.polys:
                xs = [p[0] for p in rings[0]]
                ys = [p[1] for p in rings[0]]
                self.boxes.append((min(xs), min(ys), max(xs), max(ys)))

    def at(self, x, y):
        if HAVE_SHAPELY:
            point = shapely.points(x, y)
            for i in self.tree.query(point):
                if shapely.intersects(self.geoms[i], point):
                    return self.attrs[i]
            return None
        for i, box in enumerate(self.boxes):
            if not (box[0] <= x <= box[2] and box[1] <= y <= box[3]):
                continue
            if point_in_rings(x, y, self.polys[i]):
                return self.attrs[i]
        return None


def build_grid(sampler, origin, width, height, samples, classify,
               linear_share):
    """Returns (rows of legend characters, class histogram, unmapped classes).

    Each cell is decided by the majority of a `samples` x `samples` subgrid,
    not by its centre point: at 100 m a centre sample misses a road almost
    every time, and a city without a connected road network is not a level
    anyone can play.

    Majority alone is still not enough for the two covers whose whole point is
    that they run: a main road is about 20 m wide and a river like the Neckar
    about 30 m, so neither ever wins a hectare on area, and both come out as
    disconnected specks. A cell whose samples are at least `linear_share`
    road, or at least that much water, therefore becomes that tile even when
    something else is the majority. This overstates their area and is the
    right trade: `tiles.road` already models a 100 m segment with its verges,
    a river that does not connect drains nothing, and connectivity is what
    the traffic and runoff models actually read. Road wins over water where
    both qualify -- that is a bridge.
    """
    ox, oy = origin
    rows = []
    hist = Counter()
    unmapped = Counter()
    step = CELL_M / samples
    for row in range(height):
        # Row 0 of a level map is the north edge, so y counts down from the top.
        y0 = oy + (height - 1 - row) * CELL_M
        chars = []
        for col in range(width):
            x0 = ox + col * CELL_M
            found = Counter()
            for j in range(samples):
                for i in range(samples):
                    attrs = sampler.at(x0 + (i + 0.5) * step,
                                       y0 + (j + 0.5) * step)
                    if attrs is None:
                        continue
                    tile = classify(attrs)
                    if tile is None:
                        unmapped[_describe(attrs)] += 1
                    else:
                        found[tile] += 1
            tile = _decide(found, samples * samples, linear_share)
            hist[tile] += 1
            chars.append(TILE_TO_CHAR[tile])
        rows.append("".join(chars))
    return rows, hist, unmapped


def _decide(found, total, linear_share):
    if not found:
        return "meadow"  # nothing covered this cell; meadow is neutral ground
    for tile in ("road", "water"):
        n = found.get(tile, 0)
        if n and n / total >= linear_share:
            return tile
    return found.most_common(1)[0][0]


# --------------------------------------------------------------------------
# Writing the level


def population_goal(rows, params_path):
    """A population target from the housing the extract actually contains.

    The generator cannot invent pedagogy, but it can read the same parameter
    file the simulation reads and state what this place holds today. The
    author then edits the goal set; this is a starting point that is at least
    true of the map.
    """
    with open(params_path, encoding="utf-8") as fh:
        params = json.load(fh)
    # Every parameter in tiles.json is {"value": x, "source": "..."}; the
    # source is what makes the Quellen page possible (T-703).
    per_ha = {}
    for tile, fields in params["tiles"].items():
        entry = fields.get("residentsPerHa")
        per_ha[tile] = (entry or {}).get("value", 0) or 0
    total = 0.0
    for row in rows:
        for ch in row:
            total += per_ha.get(CHAR_TO_TILE[ch], 0)
    return int(round(total * 0.9 / 100.0)) * 100


def write_level(path, level_id, order, rows, attribution, budget, months,
                goal_population, tiles):
    doc = {
        "id": level_id,
        "order": order,
        "budgetKEur": budget,
        "turnLimitMonths": months,
        "attribution": attribution,
        "tiles": {t: None for t in tiles},
        "goals": [{"metric": "population", "min": goal_population}],
        "map": rows,
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return doc


# --------------------------------------------------------------------------
# Profiles: how a dataset's own classes become tile types.
#
# Each profile declares the columns it reads and a function from a feature's
# attributes to a tile id. A flat code -> tile table (--class-field with
# --mapping) covers the simple case; a profile exists because real land-cover
# data carries more than one attribute worth using, and throwing that away
# makes a worse level. Every rule below cites the product documentation.


# CORINE Land Cover level-3 classes -> tile types. German names from the
# LBM-DE2021 documentation, Anlage 2. Classes that do not occur in Germany are
# mapped anyway so an extract elsewhere still works.
CLC_TO_TILE = {
    # 1 Artificial surfaces
    "111": "housing_high",  # durchgängig städtische Prägung
    "112": "housing_low",   # nicht durchgängig städtische Prägung
    "121": "industry",      # Industrie/Gewerbe/öffentliche Einrichtungen
    "122": "road",          # Straßen-, Eisenbahnnetze
    "123": "industry",      # Hafengebiete
    "124": "industry",      # Flughäfen
    "131": "industry",      # Abbauflächen
    "132": "industry",      # Deponien und Abraumhalden
    "133": "meadow",        # Baustellen: bare ground, no tile of its own
    "141": "park",          # städtische Grünflächen
    "142": "park",          # Sport- und Freizeitanlagen
    # 2 Agricultural areas
    "211": "cropland", "212": "cropland", "213": "cropland",
    "221": "cropland", "222": "cropland", "223": "cropland",
    "231": "meadow",        # Wiesen und Weiden
    "241": "cropland", "242": "cropland", "243": "cropland",
    "244": "cropland",
    # 3 Forest and semi-natural areas
    "311": "forest", "312": "forest", "313": "forest",
    "321": "meadow",        # natürliches Grünland
    "322": "meadow",        # Heiden und Moorheiden
    "323": "meadow",        # Hartlaubbewuchs
    "324": "forest",        # Wald-Strauch-Übergangsstadien
    "331": "meadow", "332": "meadow", "333": "meadow", "334": "meadow",
    "335": "meadow",        # Gletscher: nothing in this game models ice
    # 4 Wetlands
    "411": "wetland",       # Sümpfe
    "412": "wetland",       # Torfmoore
    "421": "wetland", "422": "wetland", "423": "wetland",
    # 5 Water bodies
    "511": "water", "512": "water", "521": "water", "522": "water",
    "523": "water",
}

# LBM-DE2021 land-use codes, Anlage 1. CLC 121 lumps industry, retail,
# services and public institutions into one class; LN_AKT separates them, and
# the game has separate tiles, so the finer attribute wins where it exists.
LN_REFINE_121 = {
    "N120": "industry",    # Produktion: Industrie, Energie, Ver-/Entsorgung
    "N121": "commercial",  # Öffentlichkeit: Handel & Dienstleistung, Kultur…
    "N123": "industry",    # Hafen
    "N124": "industry",    # Flugverkehr
    "N131": "industry",    # Abbauflächen
    "N132": "industry",    # Deponien
}

# Above this sealed share, "nicht durchgängig städtische Prägung" is read as
# apartment blocks rather than detached housing. tiles.json puts
# housing_low at 0.45 sealed and housing_high at 0.75, so the midpoint is the
# non-arbitrary place to cut.
SEALING_HIGH_PCT = 60.0


def classify_lbm_de2021(attrs):
    clc = str(attrs.get("CLC21") or "").strip()
    if not clc:
        return None
    # ZUS_AKT lists extra functions, and S is a solar site -- a tile of its
    # own in this game (T-502). The column holds a comma-separated list with a
    # trailing comma ("O,", "F,O,", "M,W,"), so it has to be split: an
    # equality test against "S" matches nothing at all, which is a rule that
    # fails silently and invisibly. The flags in LBM-DE2021 are O (Ortslage),
    # W (Wald), F (Friedhof), M (Militär), S (Solar) and K (künstlich).
    if "S" in {f.strip().upper() for f in
               str(attrs.get("ZUS_AKT") or "").split(",")}:
        return "solar_field"
    tile = CLC_TO_TILE.get(clc)
    if tile is None:
        return None
    ln = str(attrs.get("LN_AKT") or "").strip().upper()
    if clc == "121":
        tile = LN_REFINE_121.get(ln, tile)
    elif clc == "112":
        try:
            sealed = float(attrs.get("SIE_AKT"))
        except (TypeError, ValueError):
            sealed = 0.0
        if sealed >= SEALING_HIGH_PCT:
            tile = "housing_high"
    return tile


PROFILES = {
    "lbm-de2021": {
        "columns": ("CLC21", "LN_AKT", "SIE_AKT", "ZUS_AKT"),
        "classify": classify_lbm_de2021,
        # Nutzungsbedingungen und Quellenvermerk, LBM-DE2021, BKG: CC BY 4.0
        # with a prescribed source notice, and the licence requires a notice
        # of modification -- sampling onto a 1 ha grid of 16 tile types is
        # plainly one, so it is named here rather than implied.
        "attribution": (
            "© BKG ({year}) CC BY 4.0 — Landbedeckungsmodell LBM-DE2021, "
            "sampled onto a 1 ha grid and reduced to 16 tile types by "
            "Hectopolis. Datenquellen: https://sgx.geodatenzentrum.de/"
            "web_public/gdz/datenquellen/datenquellen_lbm-de2021.pdf"),
        "what": "Landbedeckungsmodell für Deutschland (BKG), CLC nomenclature",
    },
}


def _describe(attrs):
    return " ".join(f"{k}={attrs[k]}" for k in sorted(attrs)
                    if attrs[k] not in (None, ""))


def preview(rows):
    """The map as it will be read, plus a legend, for looking at before use."""
    used = sorted({ch for row in rows for ch in row})
    out = ["   " + "".join(str(c % 10) for c in range(len(rows[0])))]
    for i, row in enumerate(rows):
        out.append(f"{i % 100:2d} {row}")
    out.append("")
    out.append("legend: " + "  ".join(f"{ch}={CHAR_TO_TILE[ch]}" for ch in used))
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True,
                    help="GeoPackage (.gpkg) or GeoJSON of land-cover polygons")
    ap.add_argument("--layer", help="feature table, when the file has several")
    ap.add_argument("--profile", choices=sorted(PROFILES),
                    help="built-in classifier for a known dataset")
    ap.add_argument("--class-field",
                    help="attribute holding the class, for --mapping")
    ap.add_argument("--mapping",
                    help="JSON object mapping class value -> tile id")
    ap.add_argument("--origin", required=True,
                    help="south-west corner in the data's CRS: EASTING,NORTHING")
    ap.add_argument("--size", default="32x32", help="grid in cells, WxH")
    ap.add_argument("--samples", type=int, default=5,
                    help="subsamples per cell edge (default 5 = 20 m)")
    ap.add_argument("--linear-share", type=float, default=0.12,
                    help="share of a cell covered by road or water that makes "
                         "it that tile even when it is not the majority "
                         "(default 0.12: a 20 m road or a 30 m river through "
                         "a hectare, neither of which ever wins on area)")
    ap.add_argument("--id", required=True, help="level id")
    ap.add_argument("--order", type=int, default=99)
    ap.add_argument("--budget", type=float, default=20000.0,
                    help="starting budget in k€")
    ap.add_argument("--months", type=int, default=0,
                    help="turn limit; 0 = open-ended")
    ap.add_argument("--attribution",
                    help="source notice; the profile's own is used by default")
    ap.add_argument("--out", help="level JSON to write; default is a preview only")
    ap.add_argument("--preview", action="store_true",
                    help="print the map as ASCII")
    args = ap.parse_args(argv)

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    global CHAR_TO_TILE, TILE_TO_CHAR
    CHAR_TO_TILE = read_legend(repo_root)
    TILE_TO_CHAR = {t: c for c, t in CHAR_TO_TILE.items()}

    if args.profile:
        profile = PROFILES[args.profile]
        fields = profile["columns"]
        classify = profile["classify"]
        attribution = args.attribution or profile["attribution"].format(
            year=2026)
    else:
        if not (args.class_field and args.mapping):
            ap.error("pass --profile, or both --class-field and --mapping")
        with open(args.mapping, encoding="utf-8") as fh:
            table = json.load(fh)
        unknown = sorted(set(table.values()) - set(TILE_TO_CHAR))
        if unknown:
            die("--mapping names tile ids that do not exist: "
                + ", ".join(unknown))
        fields = (args.class_field,)
        field = args.class_field

        def classify(attrs, _t=table, _f=field):
            return _t.get(str(attrs.get(_f)))

        attribution = args.attribution
        if attribution is None:
            die("--attribution is required without a profile: a level built "
                "from someone else's data must carry its source notice")

    try:
        ox, oy = (float(v) for v in args.origin.split(","))
    except ValueError:
        ap.error("--origin must be EASTING,NORTHING in the data's own CRS")
    try:
        width, height = (int(v) for v in args.size.lower().split("x"))
    except ValueError:
        ap.error("--size must be WxH in cells")
    if args.samples < 1:
        ap.error("--samples must be at least 1")

    bbox = (ox, oy, ox + width * CELL_M, oy + height * CELL_M)
    if args.input.endswith(".gpkg"):
        raw = list(read_geopackage(args.input, args.layer, fields, bbox))
        if HAVE_SHAPELY:
            features = [(a, from_wkb(w)) for a, w in raw]
        else:
            features = [(a, rings) for a, w in raw
                        for rings in wkb_polygons(w)]
    else:
        raw = list(read_geojson(args.input, fields, bbox))
        if HAVE_SHAPELY:
            features = [(a, shapely.Polygon(r[0], r[1:])) for a, r in raw]
        else:
            features = list(raw)
    sys.stderr.write(f"{len(features)} features in the extent"
                     f"{'' if HAVE_SHAPELY else ' (no shapely: slower)'}\n")

    rows, hist, unmapped = build_grid(
        Sampler(features), (ox, oy), width, height, args.samples, classify,
        args.linear_share)

    if unmapped:
        sys.stderr.write("these source classes have no tile type:\n")
        for key, n in unmapped.most_common(20):
            sys.stderr.write(f"  {n:7d} samples  {key}\n")
        die("extend the profile or the mapping; a silently dropped class "
            "would become meadow and nobody would see it")

    cells = width * height
    sys.stderr.write("tiles:\n")
    for tile, n in hist.most_common():
        sys.stderr.write(f"  {n:6d} ({100 * n / cells:5.1f} %)  {tile}\n")

    if args.preview or not args.out:
        print(preview(rows))

    if args.out:
        goal = population_goal(
            rows, os.path.join(repo_root, "data/params/tiles.json"))
        tiles = sorted({CHAR_TO_TILE[ch] for row in rows for ch in row}
                       | {"road", "park", "forest", "housing_low"})
        write_level(args.out, args.id, args.order, rows, attribution,
                    args.budget, args.months or None, goal, tiles)
        sys.stderr.write(f"wrote {args.out}\n"
                         f"  attribution: {attribution}\n"
                         f"  population goal: {goal}\n"
                         "  goals, budget and the allowed tiles are a starting "
                         "point; edit them, and add the level's name and "
                         "description to both ARB files.\n")
    return 0


CHAR_TO_TILE = {}
TILE_TO_CHAR = {}

if __name__ == "__main__":
    sys.exit(main())
