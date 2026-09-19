# Privacy

Tasks T-702 and T-602. What the game stores, where, and what crosses the local
network.

`tools/privacy_audit.sh` checks this file against the code on every run of
`tools/check.sh`, so the two cannot drift apart.

## Nothing is sent to us or to a third party

There is **no analytics, no telemetry, no crash reporting and no account**.
Nothing is sent to the developer or to a third party. Not "off by default":
absent.

Single-player contains no network path. Networking APIs are confined to a
WebSocket client adapter, the native LAN listener and the app-side owner that
opens and closes them. The audit fails if one appears anywhere else.

### Co-op is direct and opt-in

When a player explicitly hosts a co-op game, the native app listens on the
local network. A player who enters the host's room code connects directly to
that device. The messages are player names, game commands, lobby state and the
shared world snapshot described in `docs/multiplayer.md`; they are not routed
through us, stored by us or visible outside that local session.

The room code contains the host's local IP address, port and a random 128-bit
path. It is not an account or a tracking identifier; it exists for one hosted
session and is never sent anywhere automatically. This first discovery slice
does not use mDNS and therefore does not broadcast a device name on the wifi.
The connection is plain WebSocket rather than encrypted WebSocket, because
devices on a local network do not share a trusted TLS certificate. The random
path controls admission but does not prevent someone who can inspect traffic
on that wifi from reading it. Use co-op on a network you trust.

The app dependency list is short enough to read: `flutter`,
`flutter_localizations`, `intl`, `package_info_plus`, `shared_preferences`,
`url_launcher`, and the game's own packages. None of them reports anything.
The network package uses the Dart team's `shelf` and `web_socket_channel` only
for an explicitly chosen LAN session. The audit also checks the **lock file** against a list of known
analytics and crash-reporting packages, so a transitive dependency cannot bring
one in unnoticed.

### The one outbound path, and it is yours

`url_launcher` hands a URL to the platform browser when you tap a link on the
About screen — the source repository, the contact address, the model
documentation. It cannot fetch anything back into the app, and nothing calls it
while you play. Tapping a link is a decision you make.

## The web build serves itself

A browser loading the web build fetches everything from the same origin that
served the page. That is deliberate and it cost something: Flutter's default is
to pull the CanvasKit engine from `gstatic.com`, and its font fallback pulls
Roboto from `fonts.gstatic.com`, so a default build makes **two** requests to
Google before a player has done anything. The build now passes
`--no-web-resources-cdn` and bundles Roboto, which trades about 2.4 MB of our
own bandwidth per first load for a page that phones nobody.

Verified rather than assumed: the build was loaded in a browser with every
external host blocked (`--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE
127.0.0.1"`) and rendered complete, with every request served locally.

## What is stored, and where

Local app storage only — `shared_preferences`, which is `SharedPreferences` on
Android, `NSUserDefaults` on Apple platforms and `localStorage` on the web. It
never leaves the device and is removed when you uninstall the app or clear the
site data.

| Key | What it holds |
|---|---|
| `stadtbau.autosave.v2` | the current game: the map, the tick and the command log |
| `stadtbau.stars.v1` | your best star rating per scenario |
| `stadtbau.medals.v1` | which optional challenge medals you have earned |
| `stadtbau.experience.v1` | your presentation and difficulty settings |
| `stadtbau.onboarding.v1` | whether the first-launch tutorial has been shown |

No identifier is generated, stored or derived. There is no device id, no
install id and no session id, because nothing is ever sent that would need one.

## Local statistics

Your best stars and your medals are the statistics, and they are kept for you
alone: the scenario list reads them to show what you have completed. They are
counted from your own saved results, not collected — nothing is aggregated,
uploaded or compared with anyone else.

## If you change the code

Adding a networking call outside the reviewed LAN boundary, an analytics
package or a new stored key will fail `tools/privacy_audit.sh` until the
implementation and this file are reviewed together. That is the point: the
promise on the About screen is checked, not just written.
