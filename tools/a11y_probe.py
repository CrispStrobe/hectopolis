#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Read the app's accessibility tree the way a screen reader does (T-701).

    tools/a11y_probe.py --bundle app/build/linux/x64/debug/bundle/hectopolis

Every other accessibility test in this repo asserts Flutter's *own* semantics
tree, from inside the process. That is worth doing and it is not the same
claim: it cannot tell you whether any of it survives the journey out through
GTK's ATK bridge and onto the AT-SPI bus, which is where a real screen reader
reads from. This drives that journey -- private D-Bus session, AT-SPI bus,
Xvfb, the real Linux build -- and reports the tree an assistive technology is
actually handed.

**Walk by index, not by GetChildren.** GTK's bridge answers
`org.a11y.atspi.Accessible.GetChildren` with an empty list while reporting a
correct `ChildCount`, so a client that trusts `GetChildren` sees a window with
nothing in it. That cost an afternoon and a wrong conclusion ("Flutter is not
publishing semantics"); the tree was there the whole time. Real clients use
`GetChildAtIndex`, and so does this.

Needs `jeepney`, `Xvfb`, `dbus-launch` and `at-spi-bus-launcher`
(`at-spi2-core`). Exits non-zero if the tree cannot be read or if it is
missing the labels asked for with --expect.
"""
import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

try:
    from jeepney import DBusAddress, MessageType, new_method_call
    from jeepney.io.blocking import open_dbus_connection
except ImportError:
    sys.exit("pip install jeepney")

AC = "org.a11y.atspi.Accessible"
BUS_LAUNCHERS = [
    "/usr/libexec/at-spi-bus-launcher",
    "/usr/lib/at-spi2-core/at-spi-bus-launcher",
    "/usr/lib/x86_64-linux-gnu/at-spi2-core/at-spi-bus-launcher",
]


class Tree:
    def __init__(self, address):
        self.conn = open_dbus_connection(address)

    def call(self, ref, member, sig=None, body=(), iface=AC):
        dest, path = ref
        msg = new_method_call(
            DBusAddress(path, bus_name=dest, interface=iface), member, sig, body
        )
        reply = self.conn.send_and_get_reply(msg)
        if reply.header.message_type is MessageType.error:
            raise RuntimeError(f"{member}: {reply.header.fields.get(4)}")
        return reply.body

    def prop(self, ref, name):
        return self.call(
            ref, "Get", "ss", (AC, name), iface="org.freedesktop.DBus.Properties"
        )[0][1]

    def walk(self, ref, depth=0, limit=400, out=None, seen=None):
        """Depth-first by index. Returns [(depth, role, name, description)]."""
        out = [] if out is None else out
        seen = set() if seen is None else seen
        if len(out) >= limit or depth > 16 or ref[1].endswith("/null"):
            return out
        if ref in seen:
            return out
        seen.add(ref)
        try:
            role = self.call(ref, "GetRoleName")[0]
            name = self.prop(ref, "Name")
            desc = self.prop(ref, "Description")
            count = self.prop(ref, "ChildCount")
        except Exception:
            return out
        out.append((depth, role, name, desc))
        for i in range(count):
            try:
                child = self.call(ref, "GetChildAtIndex", "i", (i,))[0]
            except Exception:
                continue
            self.walk(child, depth + 1, limit, out, seen)
        return out


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--bundle", default="app/build/linux/x64/debug/bundle/hectopolis")
    p.add_argument("--display", default=":97")
    p.add_argument("--settle", type=float, default=20, help="seconds before reading")
    p.add_argument("--limit", type=int, default=400)
    p.add_argument(
        "--expect",
        action="append",
        default=[],
        help="a label the tree must contain; repeatable. Alternatives are "
             "separated by '|' and any one of them satisfies it, which is how "
             "a bilingual app is checked without pinning a locale.",
    )
    p.add_argument("--min-nodes", type=int, default=10)
    args = p.parse_args()

    if not os.path.isfile(args.bundle):
        sys.exit(f"{args.bundle} not found; run: flutter build linux --debug")
    launcher = next((b for b in BUS_LAUNCHERS if os.path.exists(b)), None)
    if not launcher:
        sys.exit("at-spi-bus-launcher not found; install at-spi2-core")
    if not shutil.which("Xvfb") or not shutil.which("dbus-launch"):
        sys.exit("Xvfb and dbus-launch are required")

    # A writable place for the a11y bus socket. The default is under $HOME,
    # and a home directory on a network filesystem cannot host a unix socket:
    # the bus then dies with "Failed to bind socket ... Input/output error".
    work = tempfile.mkdtemp(prefix="a11y-probe-")
    env = dict(os.environ)
    env["XDG_CACHE_HOME"] = os.path.join(work, "cache")
    os.makedirs(env["XDG_CACHE_HOME"], exist_ok=True)
    # XDG_RUNTIME_DIR is deliberately left alone. Pointing it into our scratch
    # directory looks tidier and is not: a document portal fuse-mounts
    # `run/doc/by-app` inside it, which this process may not unmount, so every
    # run then leaves a directory behind that even `rm -rf` cannot clear.

    procs = []
    bus_pid = [None]
    try:
        out = sh("dbus-launch --sh-syntax", env=env).stdout
        for line in out.splitlines():
            if line.startswith("DBUS_SESSION_BUS_ADDRESS="):
                env["DBUS_SESSION_BUS_ADDRESS"] = line.split("=", 1)[1].strip("';")
            elif line.startswith("DBUS_SESSION_BUS_PID="):
                # dbus-launch forks and detaches, so the daemon is not a child
                # and killing the processes we started does not reach it. It
                # prints its pid for exactly this reason; without taking it,
                # every run of this tool leaks a bus daemon and its socket.
                bus_pid[0] = int(line.split("=", 1)[1].strip("';"))
        if "DBUS_SESSION_BUS_ADDRESS" not in env:
            sys.exit("dbus-launch produced no session bus")

        procs.append(subprocess.Popen(
            [launcher, "--launch-immediately"], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(4)

        addr = sh(
            "gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus "
            "--method org.a11y.Bus.GetAddress", env=env
        ).stdout.strip()
        addr = addr.removeprefix("('").removesuffix("',)")
        if not addr.startswith("unix:"):
            sys.exit(f"no accessibility bus address: {addr!r}")

        procs.append(subprocess.Popen(
            ["Xvfb", args.display, "-screen", "0", "1400x900x24"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(2)

        app_env = dict(env)
        app_env.update({
            "DISPLAY": args.display,
            "AT_SPI_BUS_ADDRESS": addr,
            "GTK_MODULES": "gail:atk-bridge",
            # No desktop portals. The app has no use for them here, and the
            # document portal fuse-mounts `doc/` inside whichever XDG
            # directory we point at, which this process may not unmount --
            # leaving a directory behind that even `rm -rf` cannot clear.
            "GTK_USE_PORTAL": "0",
            "GIO_USE_PORTALS": "0",
            "GNOME_ACCESSIBILITY": "1",
            "NO_AT_BRIDGE": "0",
        })
        app_log = open(os.path.join(work, "app.log"), "w+")
        procs.append(subprocess.Popen(
            [os.path.abspath(args.bundle)], env=app_env,
            stdout=app_log, stderr=subprocess.STDOUT))
        time.sleep(args.settle)

        tree = Tree(addr)
        registry = ("org.a11y.atspi.Registry", "/org/a11y/atspi/accessible/root")
        apps = tree.call(registry, "GetChildren")[0]
        nodes = []
        for app in apps:
            nodes.extend(tree.walk(app, limit=args.limit))
    finally:
        for proc in reversed(procs):
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        if bus_pid[0]:
            try:
                os.kill(bus_pid[0], signal.SIGTERM)
            except ProcessLookupError:
                pass
        # Belt and braces: if a portal mounted anyway, unmount before
        # removing, or the directory survives and accumulates run on run.
        for mount in (os.path.join(env["XDG_CACHE_HOME"], "doc"),):
            if os.path.ismount(mount):
                subprocess.run(["fusermount", "-u", mount],
                               capture_output=True)
        shutil.rmtree(work, ignore_errors=True)

    for depth, role, name, desc in nodes:
        line = "  " * depth + role
        if name:
            line += f": {name[:100]!r}"
        if desc:
            line += f"  desc={desc[:60]!r}"
        print(line)

    labels = {name for _, _, name, _ in nodes if name}
    labels |= {desc for _, _, _, desc in nodes if desc}
    print(f"\n{len(nodes)} node(s), {len(labels)} labelled")

    failures = []
    if len(nodes) < args.min_nodes:
        failures.append(
            f"only {len(nodes)} node(s); the bridge exposed a window but "
            f"little inside it (expected at least {args.min_nodes})"
        )
    for wanted in args.expect:
        # The app follows the platform locale, and a CI runner's is not the
        # developer's: this passed locally in English and failed on GitHub,
        # which starts it in German. Rather than pin a locale -- which needs
        # one generated on the machine and would stop testing what a real
        # user sees -- any listed alternative satisfies the expectation.
        alternatives = [w.strip() for w in wanted.split("|") if w.strip()]
        if not any(
            alt.lower() in label.lower()
            for alt in alternatives
            for label in labels
        ):
            failures.append(
                f"no node announces any of {alternatives!r}"
            )
    if failures:
        for f in failures:
            print(f"a11y probe: {f}")
        return 1
    print("a11y probe: ok — a real AT-SPI client read the tree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
