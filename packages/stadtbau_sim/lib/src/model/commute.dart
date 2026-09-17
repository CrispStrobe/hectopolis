// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../params.dart';
import '../tile_type.dart';
import '../world.dart';

/// Commuting model (docs/model/commute.md).
///
/// Workers of every residential cell are distributed to job cells with a
/// gravity kernel exp(-d / jobDecayM). Jobs that residents cannot fill are
/// taken by in-commuters from outside the map; workers without local jobs
/// commute out. Car trips enter the road network at the nearest main road of
/// origin and destination and are routed along the shortest road path
/// (breadth-first over 4-connected road cells). External trips leave through
/// the nearest road cell on the map border.
void computeCommute(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final cp = p.commute;

  final network = _networkFor(w, cp.roadSearchRadiusTiles);
  final tables = _tablesFor(w, p);
  final decay = tables.decay;
  final roadCount = network.roads.length;
  final nearestRoadIdx = network.nearestRoadIdx;

  // Job cells, with their coordinates and access road resolved once.
  final jobCellList = <int>[];
  var jobsCapacity = 0.0;
  for (var i = 0; i < n; i++) {
    if (p.tile(w.tiles[i]).jobsPerHa.value > 0) jobCellList.add(i);
  }
  final jobCount = jobCellList.length;
  final jobCells = Int32List(jobCount);
  final jobX = Int32List(jobCount);
  final jobY = Int32List(jobCount);
  final jobRoad = Int32List(jobCount);
  final jobCounts = Float64List(jobCount);
  for (var k = 0; k < jobCount; k++) {
    final i = jobCellList[k];
    jobCells[k] = i;
    jobX[k] = i % width;
    jobY[k] = i ~/ width;
    jobRoad[k] = nearestRoadIdx[i];
    jobCounts[k] = p.tile(w.tiles[i]).jobsPerHa.value;
    jobsCapacity += jobCounts[k];
  }

  var workers = 0.0;
  for (var i = 0; i < n; i++) {
    workers += w.population[i] * cp.labourParticipation;
  }

  final localFraction = workers > 0
      ? math.min(1.0, jobsCapacity / workers)
      : 0.0;
  final inCommuters = math.max(0.0, jobsCapacity - workers);
  final outCommuters = workers * (1 - localFraction);

  _computeAccess(w, p, f);

  final traffic = f.traffic;
  for (var i = 0; i < n; i++) {
    traffic[i] = w.tiles[i] == TileType.road
        ? p.noise.baselineThroughTraffic
        : 0.0;
    f.meanCommuteKm[i] = 0;
    f.carShare[i] = 0;
    f.connected[i] = network.nearestRoad[i] >= 0 ? 1 : 0;
  }

  var totalCarKm = 0.0;

  // Trips aggregated per (origin road, destination road) before routing, as a
  // dense road × road matrix: a hash map keyed by cell pairs dominated the
  // tick on dense maps.
  final pairTrips = network.pairTrips;
  final externalTrips = network.externalTrips..fillRange(0, roadCount, 0);

  final weights = Float64List(jobCount);
  final dist2 = Int32List(jobCount);
  final kmTable = tables.km;
  final carShareTable = tables.carShare;
  for (var i = 0; i < n; i++) {
    final pop = w.population[i];
    if (pop <= 0) continue;
    final cellWorkers = pop * cp.labourParticipation;
    final x = i % width;
    final y = i ~/ width;
    var wsum = 0.0;
    for (var k = 0; k < jobCount; k++) {
      final dx = jobX[k] - x;
      final dy = jobY[k] - y;
      final d2 = dx * dx + dy * dy;
      dist2[k] = d2;
      final wk = jobCounts[k] * decay[d2];
      weights[k] = wk;
      wsum += wk;
    }
    var meanKm = 0.0;
    var carTrips = 0.0;
    final localWorkers = wsum > 0 ? cellWorkers * localFraction : 0.0;
    if (localWorkers > 0) {
      final ro = nearestRoadIdx[i];
      final roRow = ro >= 0 ? ro * roadCount : -1;
      for (var k = 0; k < jobCount; k++) {
        final weight = weights[k];
        if (weight <= 0) continue;
        final share = weight / wsum;
        final d2 = dist2[k];
        final km = kmTable[d2];
        final commuters = localWorkers * share;
        meanKm += share * km;
        final cars =
            commuters *
            carShareTable[d2] *
            _modeFactor(p, f, i, jobCells[k], km);
        carTrips += cars;
        totalCarKm += cars * km * 2;
        final rd = jobRoad[k];
        if (ro >= 0) {
          pairTrips[roRow + (rd >= 0 ? rd : ro)] += cars * 2;
        } else if (rd >= 0) {
          pairTrips[rd * roadCount + rd] += cars * 2;
        }
      }
    }
    final external = cellWorkers - localWorkers;
    if (external > 0) {
      // A stop serves a trip out of town too; a cycle route does not, since
      // the external commute is far beyond the competitive distance.
      final cars =
          external *
          cp.externalCarShare *
          _shiftFactor(p, f.transitAccess[i] * cp.transitCarReduction);
      carTrips += cars;
      totalCarKm += cars * cp.externalCommuteKm * 2;
      final r = nearestRoadIdx[i];
      if (r >= 0) externalTrips[r] += cars * 2;
    }
    final fLocal = cellWorkers > 0 ? localWorkers / cellWorkers : 0.0;
    f.meanCommuteKm[i] = fLocal * meanKm + (1 - fLocal) * cp.externalCommuteKm;
    f.carShare[i] = cellWorkers > 0 ? carTrips / cellWorkers : 0.0;
  }

  // In-commuters from outside fill the remaining jobs and arrive by road.
  if (inCommuters > 0 && jobsCapacity > 0) {
    for (var k = 0; k < jobCount; k++) {
      final share = jobCounts[k] / jobsCapacity;
      final cars = inCommuters * share * cp.externalCarShare;
      totalCarKm += cars * cp.externalCommuteKm * 2;
      final r = jobRoad[k];
      if (r >= 0) externalTrips[r] += cars * 2;
    }
  }

  network.assignPairTrips(traffic);
  for (var r = 0; r < roadCount; r++) {
    if (externalTrips[r] > 0) {
      network.assignExternalRoad(traffic, r, externalTrips[r]);
    }
  }

  f.totalCarKmPerDay = totalCarKm;
  f.workers = workers;
  f.jobsCapacity = jobsCapacity;
  f.inCommuters = inCommuters;
  f.outCommuters = outCommuters;
}

/// How much of a cell's car traffic public transport and cycling take away.
///
/// The model has no public-transport mode of its own -- the mode share bins
/// are walk, bike and car, and the car share absorbs what would be transit --
/// so a stop and a route act as a substitution away from the car rather than
/// as a fourth mode. That keeps the change to one multiplier and keeps the
/// traffic, noise and air chain downstream of it untouched.
///
/// A trip needs the infrastructure at both ends, so the origin and destination
/// reach are averaged. Cycling only competes below `cycleCompetitiveKm`.
double _modeFactor(
  SimParams p,
  Fields f,
  int origin,
  int destination,
  double km,
) {
  final cp = p.commute;
  final transit =
      0.5 *
      (f.transitAccess[origin] + f.transitAccess[destination]) *
      cp.transitCarReduction;
  var cycle =
      0.5 *
      (f.cycleAccess[origin] + f.cycleAccess[destination]) *
      cp.cycleCarReduction;
  if (km > cp.cycleCompetitiveKm) {
    cycle = 0;
  }
  return _shiftFactor(p, transit + cycle);
}

/// Turn a shift share into a multiplier on car trips, with the floor applied.
double _shiftFactor(SimParams p, double shift) =>
    math.max(p.commute.minCarShareFactor, 1 - shift);

/// Reach of a tram stop and of a cycle route per cell, 1 on the tile itself
/// and falling linearly to 0 at the radius.
void _computeAccess(WorldState w, SimParams p, Fields f) {
  final cp = p.commute;
  _reach(w, f.transitAccess, TileType.tramStop, cp.transitWalkRadiusTiles);
  _reach(w, f.cycleAccess, TileType.cyclePath, cp.cyclePathRadiusTiles);
}

void _reach(WorldState w, Float64List out, TileType source, int radius) {
  final n = w.cellCount;
  final width = w.width;
  final height = w.height;
  out.fillRange(0, n, 0);
  final offsets = Offsets.radius(radius);
  for (var s = 0; s < n; s++) {
    if (w.tiles[s] != source) continue;
    out[s] = 1;
    final sx = s % width;
    final sy = s ~/ width;
    for (var k = 0; k < offsets.length; k++) {
      final rx = sx + offsets.dx[k];
      if (rx < 0 || rx >= width) continue;
      final ry = sy + offsets.dy[k];
      if (ry < 0 || ry >= height) continue;
      final value = 1 - offsets.dist[k] / radius;
      final j = ry * width + rx;
      if (value > out[j]) {
        out[j] = value;
      }
    }
  }
}

/// Distance-indexed lookup tables shared by every cell of a tick. Depend only
/// on the grid size and the parameters, so they are rebuilt only when those
/// change.
class _CommuteTables {
  _CommuteTables(WorldState w, SimParams p)
    : params = p,
      maxDist2 = w.width * w.width + w.height * w.height,
      decay = DecayTable(
        maxDist2: w.width * w.width + w.height * w.height,
        cellSizeM: p.cellSizeM,
        decayM: p.access.jobDecayM,
      ),
      km = Float64List(w.width * w.width + w.height * w.height + 1),
      carShare = Float64List(w.width * w.width + w.height * w.height + 1) {
    final cellKm = p.cellSizeM / 1000.0;
    for (var d2 = 0; d2 <= maxDist2; d2++) {
      final value = math.max(0.5, math.sqrt(d2.toDouble()) * cellKm);
      km[d2] = value;
      carShare[d2] = p.commute.carShare(value);
    }
  }

  final SimParams params;
  final int maxDist2;
  final DecayTable decay;

  /// One-way commute distance in km for a squared tile distance.
  final Float64List km;

  /// Car mode share for that distance.
  final Float64List carShare;
}

_CommuteTables? _tables;

_CommuteTables _tablesFor(WorldState w, SimParams p) {
  final cached = _tables;
  final maxDist2 = w.width * w.width + w.height * w.height;
  if (cached != null &&
      identical(cached.params, p) &&
      cached.maxDist2 == maxDist2) {
    return cached;
  }
  return _tables = _CommuteTables(w, p);
}

/// One cached road network per world state. The network depends only on the
/// road layout, which changes on placement, not on every tick.
final Expando<_RoadNetwork> _networkCache = Expando<_RoadNetwork>();

_RoadNetwork _networkFor(WorldState w, int searchRadius) {
  final cached = _networkCache[w];
  if (cached != null && cached.matches(w, searchRadius)) return cached;
  final built = _RoadNetwork(w, searchRadius);
  _networkCache[w] = built;
  return built;
}

/// Offer [from]'s cached road network to [to], which is about to become a copy
/// of it.
///
/// A snapshot starts with the same roads, so without this every copy would pay
/// for a fresh network and a fresh breadth-first tree per road cell — the bulk
/// of a placement forecast. The network is still validated against [to]'s own
/// tiles before it is used, so an unrelated state simply rebuilds.
///
/// The network's scratch buffers are shared along with it. Every kernel runs
/// synchronously and leaves them zeroed, so two simulations may hold the same
/// network, but nothing may hold one across a suspension point.
void shareRoadNetwork(WorldState from, WorldState to) {
  final cached = _networkCache[from];
  if (cached != null) _networkCache[to] = cached;
}

/// A breadth-first tree over the road graph: [parent] per cell (-1 at the
/// root, -2 unvisited) and the reachable road cells in visit order.
class _Tree {
  _Tree(this.parent, this.order);

  final Int32List parent;
  final Int32List order;
}

/// Road cells as a 4-connected graph with shortest-path trees from every road
/// cell. Sized for a few hundred road cells.
class _RoadNetwork {
  _RoadNetwork(WorldState w, this.searchRadius)
    : n = w.cellCount,
      width = w.width,
      height = w.height,
      nearestRoad = Int32List(w.cellCount),
      nearestRoadIdx = Int32List(w.cellCount),
      roadMask = Uint8List(w.cellCount) {
    for (var i = 0; i < n; i++) {
      if (w.tiles[i] == TileType.road) {
        roadMask[i] = 1;
        roadIndex[i] = roads.length;
        roads.add(i);
      }
    }
    final offsets = Offsets.radius(searchRadius);
    for (var i = 0; i < n; i++) {
      if (roadMask[i] == 1) {
        nearestRoad[i] = i;
        nearestRoadIdx[i] = roadIndex[i]!;
        continue;
      }
      nearestRoad[i] = -1;
      nearestRoadIdx[i] = -1;
      final x = i % width;
      final y = i ~/ width;
      var best = double.infinity;
      for (var k = 0; k < offsets.length; k++) {
        final nx = x + offsets.dx[k];
        final ny = y + offsets.dy[k];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final j = ny * width + nx;
        if (roadMask[j] == 1 && offsets.dist[k] < best) {
          best = offsets.dist[k];
          nearestRoad[i] = j;
          nearestRoadIdx[i] = roadIndex[j]!;
        }
      }
    }
    // BFS trees from every road cell (lazy, cached).
    _trees = List<_Tree?>.filled(roads.length, null);
    pairTrips = Float64List(roads.length * roads.length);
    externalTrips = Float64List(roads.length);
    _accumulator = Float64List(roads.length);
    for (final r in roads) {
      final x = r % width;
      final y = r ~/ width;
      if (x == 0 || y == 0 || x == width - 1 || y == height - 1) exits.add(r);
    }
  }

  final int searchRadius;
  final int n;
  final int width;
  final int height;
  final Int32List nearestRoad;

  /// Index into [roads] of [nearestRoad], or -1 where there is no road in
  /// reach.
  final Int32List nearestRoadIdx;
  final Uint8List roadMask;
  final List<int> roads = [];
  final Map<int, int> roadIndex = {};
  final List<int> exits = [];
  late final List<_Tree?> _trees;

  /// Trips per (origin road, destination road), row-major over [roads].
  /// Owned by the network so it is allocated once, and left zeroed after
  /// every [assignPairTrips].
  late final Float64List pairTrips;

  /// Trips entering or leaving the map at each road cell.
  late final Float64List externalTrips;

  late final Float64List _accumulator;

  /// Whether this network still describes [state]'s road layout.
  bool matches(WorldState state, int radius) {
    if (radius != searchRadius || state.cellCount != n) return false;
    final tiles = state.tiles;
    for (var i = 0; i < n; i++) {
      if ((tiles[i] == TileType.road ? 1 : 0) != roadMask[i]) return false;
    }
    return true;
  }

  _Tree _tree(int root) {
    final ri = roadIndex[root]!;
    final cached = _trees[ri];
    if (cached != null) return cached;
    final parent = Int32List(n)..fillRange(0, n, -2); // -2 = unvisited
    final order = Int32List(roads.length);
    var count = 0;
    parent[root] = -1;
    order[count++] = root;
    final queue = Queue<int>()..add(root);
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      final x = c % width;
      final y = c ~/ width;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final j = ny * width + nx;
        if (roadMask[j] != 1 || parent[j] != -2) continue;
        parent[j] = c;
        order[count++] = j;
        queue.add(j);
      }
    }
    final tree = _Tree(parent, Int32List.sublistView(order, 0, count));
    _trees[ri] = tree;
    return tree;
  }

  /// Load every road cell on the shortest path of each non-zero entry in
  /// [pairTrips], then reset it to zero.
  ///
  /// Walking each origin-destination pair separately repeats the shared head
  /// of the paths, so instead each origin's trips are accumulated at their
  /// destinations and summed up its BFS tree: a cell's load is the total of
  /// its subtree, which is exactly the trips whose path passes through it.
  void assignPairTrips(Float64List traffic) {
    final r = roads.length;
    final acc = _accumulator;
    for (var a = 0; a < r; a++) {
      final base = a * r;
      var used = false;
      for (var b = 0; b < r; b++) {
        if (pairTrips[base + b] != 0) {
          used = true;
          break;
        }
      }
      if (!used) continue;
      final root = roads[a];
      final tree = _tree(root);
      final parent = tree.parent;
      acc.fillRange(0, r, 0);
      for (var b = 0; b < r; b++) {
        final trips = pairTrips[base + b];
        if (trips == 0) continue;
        pairTrips[base + b] = 0;
        final dest = roads[b];
        if (parent[dest] == -2) {
          // Unreachable by road: load only the two access cells.
          traffic[root] += trips;
          traffic[dest] += trips;
          continue;
        }
        acc[b] += trips;
      }
      final order = tree.order;
      for (var k = order.length - 1; k >= 0; k--) {
        final cell = order[k];
        // nearestRoadIdx is the road index itself for road cells.
        final load = acc[nearestRoadIdx[cell]];
        if (load == 0) continue;
        traffic[cell] += load;
        final up = parent[cell];
        if (up >= 0) acc[nearestRoadIdx[up]] += load;
      }
    }
  }

  /// Trips that leave or enter the map at road cell index [r]: routed to the
  /// nearest border road.
  void assignExternalRoad(Float64List traffic, int r, double trips) {
    if (trips <= 0) return;
    final cell = roads[r];
    if (exits.isEmpty) {
      traffic[cell] += trips;
      return;
    }
    final parent = _tree(cell).parent;
    var best = -1;
    var bestLen = 1 << 30;
    for (final e in exits) {
      if (parent[e] == -2) continue;
      var len = 0;
      var c = e;
      while (c != -1 && len < bestLen) {
        len++;
        c = parent[c];
      }
      if (len < bestLen) {
        bestLen = len;
        best = e;
      }
    }
    if (best < 0) {
      traffic[cell] += trips;
      return;
    }
    var c = best;
    while (c != -1) {
      traffic[c] += trips;
      c = parent[c];
    }
  }
}
