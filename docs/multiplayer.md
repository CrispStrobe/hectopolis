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
| client | `hello` | my name, and a resume token if I have one |
| host | `welcome` | your id, who is here, the full world, its hash, your resume token |
| host | `rejected` | version mismatch, session full, already started, name taken, unknown seat |
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

## Reconnect (T-605)

A dropped connection mid-game is the ordinary case on a phone, not an
exception, so it is not treated as leaving.

Every `welcome` carries a **resume token**. When a connection drops during a
game the host *holds the seat*: the player stays in the list with
`connected: false`, their district stays theirs, and nobody else may build in
it. A later `hello` carrying that token re-seats them — same player id, same
district — and the `welcome` that answers it contains the full world as it now
stands, so they catch up in one message however long they were away.

Three rules that matter more than they look:

- **In the lobby, leaving means leaving.** There is no district to hold and no
  game to return to, so the seat is freed and the token forgotten.
- **A token for a seat that is still occupied is refused** (`unknownSeat`).
  Honouring it would evict the player sitting there, which turns a stale copy
  of a token into a way to take someone's district.
- **The host never expires a seat on its own.** There is no clock in this
  package; `releaseSeat` is explicit, because "how long do we wait for them"
  is a decision for the session UI and would be the wrong thing to hard-code
  three layers down.

A held seat also cannot be ready: someone who is not there has not agreed to
start.

The token is deliberately not part of `PlayerInfo`. The player list goes to
everyone, and a token that reclaims a seat is not lobby information. The
default token factory is a counter, which is fine for the in-memory transport
and is not fine over a network — so it is a named constructor parameter, to be
supplied with something unguessable at the point where a real transport is
introduced, rather than a default that quietly ships.

Adding all of this needed **no protocol bump**: `resumeToken` is optional on
`hello` and `welcome`, an older host ignores it and answers as it always did,
and an older client never sends one. That is the additive-change rule from
above, working as intended.

## The lobby (T-603)

`SessionController` (`app/lib/game/session_controller.dart`) is the one place
that knows both the protocol and Flutter: the package knows nothing about
widgets, the widgets know nothing about the wire format. It exposes plain
lists and flags, so a screen cannot accidentally depend on a message type.

`LobbyScreen` shows who is here, which columns are theirs, who is ready, and
— for the host — a button to divide the map and one to start.

**Districts are vertical strips**, in player order, and the last strip takes
the remainder so no column is left unassigned. Strips rather than quadrants
because every strip then touches both edges of the map: with quadrants the
player in the far corner is shielded from everyone else's noise and traffic,
and a mode whose entire point is that effects cross borders should not hand
anyone a quiet corner.

The screen has **no entry point in the menu yet**, which is deliberate rather
than forgotten. A player reaches a lobby by hosting or joining over a network,
and there is no transport until T-602. It is driven by the in-memory pair in
its tests, so it is verified end to end today and needs no rework when a
socket arrives.

One thing the host needed that the protocol had not provided: `SessionHost`
broadcast to its clients, but the host's *own* screen is not a client, so a
lobby on the hosting device never noticed anyone arrive. `SessionHost.changes`
now fires on every broadcast, which is one place, so a new message type cannot
forget to notify.

### Testing a session in a widget test

Two rules, learned the hard way, both about `flutter_test`'s faked clock:

- **Never wait on a timer.** `Future.delayed`, even with `Duration.zero`, is a
  timer, and a faked clock does not run it unless the test pumps. Everything
  in the in-memory transport defers with a microtask instead, which is also
  the matching primitive, since delivery is scheduled as a microtask.
- **Do not await a session teardown inside a test body.** Close in
  `addTearDown`, where the clock is real. To simulate a drop mid-test, close
  the *transport* — which is what a dropped connection is — and note that a
  close outside message delivery does its work synchronously, so the other
  side has already noticed by the next line.

## What is not here yet

T-602 discovery (mDNS, room code, QR, manual IP), T-603 the lobby UI, T-604
the district rules and per-player tile budgets in the game itself, and T-606
an internet relay. T-605's remaining half is the UI that holds a token across
a reconnect and decides when to give a seat up.
