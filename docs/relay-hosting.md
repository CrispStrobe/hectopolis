# Hosting a relay

Task T-606. Co-op on the same wifi needs nothing but the devices. To play with
people who are elsewhere, someone runs a **relay**: a small server that pairs a
hosting device with its guests and forwards what they send. There is no relay
run by the project. A school, a club or a player runs their own, and everyone
using it chooses to trust them with the relay's address, not with the game.

## What the relay can and cannot see

Every message between a host and its guests is sealed with ChaCha20-Poly1305
under keys derived from the **room secret** (`docs/multiplayer.md`). The secret
is part of the room code that players hand each other. The relay is never given
it, only a room id derived from it by a one-way hash, which is enough to route
and nothing more.

| The relay operator learns | The relay operator cannot |
|---|---|
| that a room exists, by its id | read a move, a player name or the world |
| how many guests a room has | alter a message without the game noticing |
| when frames pass and how large they are | join a room, or replay a recorded guest into it |
| the IP addresses connecting to it | find out which game a room belongs to |

If the relay drops or reorders a frame, the channel closes, and the game's
reconnect brings the guest back. A relay can stop a game; it cannot forge one.

The relay logs aggregate counts (rooms, guests) every ten minutes and nothing
else: no room ids, no addresses, no frame contents. A reverse proxy in front of
it keeps its own logs; configure them with the same care (see below).

## Running it

The relay is a Dart program in `packages/stadtbau_relay`. It needs only the
Dart SDK, not Flutter.

**With Docker** (the image is built and started in CI on every change):

```bash
docker build -t hectopolis-relay packages/stadtbau_relay
docker run -d --restart unless-stopped -p 127.0.0.1:8080:8080 hectopolis-relay
```

**Without Docker:**

```bash
cd packages/stadtbau_relay
dart pub get
dart compile exe bin/relay.dart -o relay
./relay --address 127.0.0.1 --port 8080
```

Options: `--address` (default `127.0.0.1`), `--port` (default `8080`, or the
`PORT` environment variable), `--max-rooms` (default 200). A room takes at most
six guests (four players plus room for a reconnect), a frame at most 4 MiB,
and a connection at most 6 000 frames a minute; the limits are in
`RelayLimits` if a deployment needs others. `GET /healthz` answers `ok` for a
load balancer.

## TLS is required

The game connects to a relay only over `wss://` (plain `ws://` is accepted
for a relay on the same device, for development). The relay itself speaks
plain WebSocket, so put a proxy in front that terminates TLS. With
[Caddy](https://caddyserver.com), which obtains and renews the certificate
itself, `packages/stadtbau_relay/Caddyfile.example` is the whole configuration:

```
relay.example.org {
	reverse_proxy 127.0.0.1:8080
}
```

nginx works too; it needs the usual `proxy_http_version 1.1` and the `Upgrade`
and `Connection` headers for WebSockets. A relay served under a path is fine
(`wss://example.org/hectopolis`): players type the same address the proxy
serves.

**Logs.** Caddy writes no access log unless one is configured. If the proxy
logs requests, the log holds the connecting addresses and the room ids in the
request paths; keep it short-lived or leave it off. Nothing in a room id leads
back to a game without its room code.

## Playing through it

1. The host opens *Build together*, enters a name and the relay's address
   (`relay.example.org`), and chooses **Host through a relay**. The lobby shows
   a room code such as `wss://relay.example.org/r/3f9c…`.
2. Everyone else enters that code under *Room code or address* and joins, as
   on a LAN. The code is the key to the room: share it the way you would share
   a password.
3. A browser can host and join through a relay. That is the route to
   cross-play between the web build and the apps, which a LAN cannot offer
   (an HTTPS page may not open a plain `ws://` connection).

## Which builds have it

Relay play is a compile-time switch, `HECTOPOLIS_RELAY`, on by default
(`app/lib/game/build_features.dart`). The App Store builds for iOS and macOS
leave it out for now: their build commands pass
`--dart-define=HECTOPOLIS_RELAY=false`, and `tools/check.sh store-flags` fails
if either stops doing so. A build without it carries none of the relay code
(checked on the web build and on an unsigned macOS build: the relay's key
labels are absent from the binary, and present without the switch), shows only
the local-network option, refuses a relay code, and keeps the privacy wording
from before relays existed. The web, Android, Windows and Linux builds include
it.

## Responsibilities

Running a relay for other people is running a service. It processes the IP
addresses of its users, which is personal data under the GDPR, for the purpose
of forwarding their game; keep no more than that needs. The relay stores
nothing on disk. Whether a public relay needs an Impressum or a privacy notice
depends on who runs it and for whom; that is the operator's call, not the
game's.
