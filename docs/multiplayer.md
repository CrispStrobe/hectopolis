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

**The hash has to be the same on every platform**, because a host and a guest
can be a native app and a browser. Until protocol version 2 (2026-10-26) it
was not: it hashed `toJson().toString()`, where a double such as 1500.0 prints
"1500.0" in the VM and "1500" in JavaScript, and its multiply passed 2^53,
where JavaScript numbers stop being exact. A browser and an app never agreed on
a snapshot, and a guest threw at once. Nobody had seen it, because no web build
had ever been in a session with a native one: the relay is the first route
that allows it. The hash now writes numbers in a form both platforms produce
digit for digit and multiplies in 16-bit halves.
`packages/stadtbau_sim/test/hash_test.dart` pins the values, and CI runs it in
Chrome as well as the VM; it also shows that thirteen months of simulation come
out bit-identical in both, so the platforms' floating-point maths has not
drifted apart. A peer on version 1 is refused with a version error rather than
a mismatch.

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

## The socket boundary (T-602)

`Transport` remains an interface over "send a string, receive strings, close".
The in-memory pair drives protocol tests; `WebSocketTransport` is the real
adapter. Native hosts bind an ephemeral port on IPv4 and expose a room code of
the form `address:port/random-path`. The 128-bit path is the admission secret:
knowing that a device is hosting is not enough to join it.

The first transport is plain `ws://` because devices on an ordinary LAN do
not share a certificate authority and a self-signed `wss://` certificate would
not be trusted by clients. The random path is admission control, not
encryption: use co-op on a network you trust. Android therefore opts into
cleartext traffic, iOS explains the local-network permission and allows local
transport, and sandboxed macOS builds carry both client and server network
entitlements. An internet relay must use `wss://`.

This first reachable slice deliberately does not use mDNS. Nothing announces a
device name to the rest of the wifi; the host shows a code to the people it
wants to invite. Networking APIs are confined to the WebSocket adapter and the
conditionally imported native server, which keeps `dart:io` out of web builds.
The About and privacy copy say exactly what crosses the LAN and, just as
importantly, that nothing goes to us or to a third party.

The privacy audit strips line comments before matching, then rejects a network
API anywhere outside those two adapters and the app-side owner that opens and
closes them.

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

## Turns and allowances (T-604)

Play is turn-based. Turn order is the seating order, host first — the order
everyone already sees in the lobby, so nobody has to be told what it is. An
intent from anyone else is denied with `notYourTurn`.

**Time moves between rounds, not inside them.** When the last player ends
their turn the host advances `roundMonths` (a year by default) and the next
round begins. A year is long enough that a placement has visible consequences
by the time your next turn comes round, and short enough that nobody sits
through a decade of someone else's decisions. Consequences landing between
rounds also means everybody is looking at the same city while they decide.

An end-turn that arrives when it is no longer that player's turn is ignored,
so a tap that lands a moment late cannot skip the person after them.

**The money is shared; the tiles are not.** There is one municipal budget —
that is the subject of the game — so a player's own allowance of tiles is the
only private resource, and it is what makes a district a responsibility rather
than just a patch of map. A player's allowance is checked *before* the
simulation, so running out of parks is reported as running out of parks rather
than as whatever the shared budget happens to say.

Everyone sees everyone's stock. Hiding it would stop people planning together,
which is the mode's entire purpose.

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

## Internet play through a relay (T-606)

A relay is a small server that someone the players trust runs
(`docs/relay-hosting.md`; there is no project relay). The host connects *out*
to it, so hosting works where a LAN listener cannot, a browser included, and
guests connect to it too. The protocol above does not change: the relay only
carries its frames.

**Room code.** `wss://relay.example.org/r/<secret>`, the relay's address and a
fresh 128-bit secret. The `/r/` segment keeps it apart from a LAN code. The
relay is told `relayRoomId(secret)`, a one-way SHA-256 of the secret, and the
endpoints are `/v1/host/<room id>` and `/v1/join/<room id>`. Only `wss://` is
accepted, except for a relay on the device itself.

**The host's one connection carries every guest.** The relay wraps each
guest's frames in an envelope, `{"op": "open" | "data" | "close", "ch": n,
"m": frame}`, and `RelayHostLink` undoes it into one `Transport` per guest, the
same shape `LanServer.connections` gives a LAN host.

**Every channel is sealed end to end** (`SecureChannel`). The guest opens with
a random 32-byte salt in the clear; both ends derive a key per direction from
the secret and that salt with HKDF-SHA256, so every connection has its own
keys. Each message is sealed with ChaCha20-Poly1305 under a 96-bit nonce that
counts up from zero and is never sent. The receiver expects exactly the next
count, so a frame the relay altered, replayed, reordered or dropped does not
open, and the channel closes. The protocol already recovers from a closed
channel by reconnecting (T-605). The host remembers every salt it has
accepted, so a recorded connection cannot be replayed from its first frame.

**Threat model.** The relay operator, and anyone who can watch the relay, can
see that a room exists, how many guests it has, when frames pass and how big
they are, and the addresses connecting. They cannot read or alter a game, join
a room, or tie a room id to a game without its code. They can refuse service:
drop a room, or close channels. Someone holding the room code can join, as on a
LAN; the code is the admission secret.

`test/secure_channel_test.dart` puts a relay in the middle that misbehaves in
exactly one way per test (alters, replays, drops, holds another secret, replays
a whole connection); `test/relay_session_test.dart` plays a real session with
two guests through a real relay over local sockets; and the app's
`relay_session_test.dart` does the same through `LanSession`, with the code
the lobby shows.

## What is not here yet

The app remembers the relay address a host last used successfully
(`stadtbau.relay.v1`, `docs/privacy.md`); the clear button in the field forgets
it. Automatic mDNS discovery is deliberately deferred. Native hosts instead show
one room code per usable IPv4 address as text and a QR code, and guests can
paste or type that code. There is no camera scanner yet. A web build served
over HTTPS generally cannot open the host's plain `ws://` LAN connection due
to browser mixed-content rules, so a LAN game is native to native. Browser
cross-play goes through a relay (below).

The game screen now draws every district, names the active player and round,
uses each player's private stock in the palette, and disables single-player
time and history controls. It retains the resume token in memory after a drop,
shows a reconnect action, and replaces its mirror with the authoritative
snapshot on return. A token is not persisted across an app restart.
