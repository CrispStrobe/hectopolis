# Co-operative play: the protocol

Code: `packages/stadtbau_net`. Task T-601.

Two to four people build one city. Not one city each — **one** city, which is
the only arrangement that makes the subject of this game visible: your
neighbour's industrial estate raises the noise in your housing, and their
motorway carries your commuters.

## Host-authoritative, and why

One participant's simulation is the real one. A client keeps a mirror,
requests actions, and applies what the host says happened. It never decides.

That costs a round trip on every placement. The alternative — every client
runs the simulation and they agree because the simulation is deterministic —
is cheaper and is a trap. The fields are computed from floating-point sums
over neighbourhoods, and "deterministic" here means *the same binary on the
same input gives the same result*, which two builds, two platforms or two
web engines do not guarantee. A shared city that quietly drifts apart is
worse than one that costs 20 ms to place a tile.

So the wire carries **commands, not state**. A placement is about forty bytes;
the fields it changes are hundreds of kilobytes, and every client can
recompute them from the command far faster than it could download them.

## The hash is the safety net

`WorldState.hash()` is an FNV-1a over the state's JSON. Every `applied` and
`ticked` message carries the host's hash after the change. A client compares
it with its own and, on any disagreement, throws its world away and asks for a
snapshot.

This turns the failure that used to be unfixable — a drift that nobody notices
until the two screens show different cities — into one recovered within a
single tick. `SessionClient.resyncCount` counts the repairs; a healthy session
never needs one, and a test asserts exactly that, so a determinism bug becomes
a failing test rather than a bug report nobody can reproduce.

## Messages

JSON, one `type` tag, and `v` on every frame. There is no negotiation: a peer
on another `protocolVersion` is refused at the door with `rejected`, carrying
the host's version so the client can say *which* side needs updating rather
than "connection failed".

| From | Message | Meaning |
|---|---|---|
| client | `hello` | my name |
| host | `welcome` | your id, who is here, the full world, its hash |
| host | `rejected` | version mismatch, session full, already started, name taken |
| host | `lobby` | the player list, districts, ready flags, started |
| client | `ready` | I am (not) ready |
| client | `intent` | please do this command (with my sequence number) |
| host | `applied` | this happened, at this tick, hash after |
| host | `denied` | no, with the reason (and the simulation's own error) |
| host | `ticked` | time is now at this tick, hash after |
| client | `resync` | my hash disagrees, send me the world |
| host | `snapshot` | the world, again |
| host | `left` | someone is gone |

The version is bumped when a field changes meaning. Adding an optional field
does not need a bump; a client ignores frames it cannot parse, which is what
makes an additive change safe.

`intent` carries a client sequence number that comes back on `applied` and
`denied`, so an answer can be matched to a request — and so an optimistic
local preview can be rolled back when the answer is no.

## Who may do what

- **Only the host advances time.** A client's `AdvanceTick` is denied with
  `hostOnly`. The simulation is deterministic per tick, not per second, so
  letting anyone advance would make the number of ticks depend on who clicked.
- **Districts divide the right to build, not the simulation** (T-604). A
  district is a rectangle; a placement outside a player's own is denied with
  `outsideDistrict`. Effects cross borders freely, which is the point.
- A refusal from the simulation itself — no budget, tile exhausted, out of
  bounds — comes back as `denied` with `simulation` and the original
  `CommandError`, so the client can show the same message single-player does.

## No sockets in this package

`Transport` is an interface over "send a string, receive strings, close". The
only implementation here is an in-memory pair, which the tests use to run a
real host and real clients in one isolate.

This is deliberate. Opening a listening socket is the moment the promise on
the About screen — *no network requests while you play* — has to be restated
for an opt-in LAN mode, and `tools/privacy_audit.sh` fails the build if any
first-party code reaches for a networking API. That guard should hold until
the decision is taken in the open, with the About text and the store listings
changed in the same breath. It belongs with discovery (T-602), not smuggled in
under a protocol task.

The audit does now strip line comments before matching, because the claim it
checks is about code, and a guard that fails on the paragraph above would
teach people to delete the paragraph.

## Delivery must be ordered, and is asynchronous

The host's `applied` messages *define* the order commands hit the simulation,
so a transport may not reorder. It may drop: a lost frame shows up as a hash
mismatch and is repaired by a snapshot.

The in-memory transport delivers from a microtask rather than inline. Inline
delivery made the exchange re-entrant — a host broadcast reached a client,
whose hash check answered with a resync request, which the host tried to
answer while its own stream controller was still firing. No socket behaves
that way, and a protocol that only works over a synchronous transport is not a
protocol. `InMemoryTransport.settle()` completes when nothing is in flight, so
tests wait on a condition instead of guessing at a number of pumps.

## What is not here yet

T-602 discovery (mDNS, room code, QR, manual IP), T-603 the lobby UI, T-604
the district rules and per-player tile budgets in the game itself, T-605
reconnect, and T-606 an internet relay.
