# Privacy

Task T-702. What the game stores, where, and what leaves the device — which is
nothing.

`tools/privacy_audit.sh` checks this file against the code on every run of
`tools/check.sh`, so the two cannot drift apart.

## Nothing leaves the device

There is **no analytics, no telemetry, no crash reporting and no account**, and
no code path that sends anything anywhere. Not "off by default": absent.

First-party code contains no networking API at all — no `dart:io`, no HTTP
client, no socket. The audit fails the build if one appears.

The dependency list is short enough to read: `flutter`,
`flutter_localizations`, `intl`, `package_info_plus`, `shared_preferences`,
`url_launcher`, and the game's own `stadtbau_sim`. None of them reports
anything. The audit also checks the **lock file** against a list of known
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

Adding a networking dependency, an analytics package or a new stored key will
fail `tools/privacy_audit.sh` until this file is updated to match. That is the
point: the promise on the About screen is checked, not just written.
