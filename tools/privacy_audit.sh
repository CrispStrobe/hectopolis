#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Checks the promise the About screen makes (task T-702):
#
#   Hectopolis sends nothing to us or to third parties. An explicitly chosen
#   LAN game exchanges game commands directly between the players' devices.
#
# That is a claim in a user-facing string, and a claim in a string rots. This
# turns it into something CI can fail on.
#
# Usage: tools/privacy_audit.sh   (from anywhere)
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
sources=$(find app/lib packages/*/lib -name '*.dart' \
            -not -path '*/generated/*' -not -path '*/.dart_tool/*')

echo "== networking is confined to the opt-in LAN transport"
# url_launcher is the one sanctioned outbound path: it hands a URL to the
# platform browser when the player taps a link on the About screen. It cannot
# fetch anything back into the app, and nothing calls it during play.
#
# Line comments are stripped before matching, because the claim being checked
# is about code. The two T-602 adapters and the app-side session owner below
# are the only sanctioned network boundary: session rules, the simulation and
# the rest of the app stay free of networking APIs. A new call site fails until
# this list is reviewed.
# The trade is that a networking call written after `//` on the same line as
# code would be missed; nothing in this codebase puts code after a comment.
net='dart:io|package:http|package:dio|HttpClient|HttpRequest|WebSocket|RawSocket|ServerSocket|Socket\.|InternetAddress|package:web_socket'
# `|| true` per file: grep exits 1 when a file is clean, and with `set -e`
# that ended the audit early -- silently reporting success for every check
# after this one.
hits=$(for f in $sources; do
         sed 's|//.*||' "$f" | grep -nE "$net" | sed "s|^|$f:|" || true
       done)
allowed_network_files='packages/stadtbau_net/lib/src/lan_server_io.dart|packages/stadtbau_net/lib/src/websocket_transport.dart|app/lib/game/lan_session.dart'
unexpected=$(echo "$hits" | grep -vE "^($allowed_network_files):" || true)
if [ -n "$unexpected" ]; then
  echo "$unexpected" | sed 's/^/  /'
  echo "  a networking API appeared outside the reviewed LAN adapters"
  failures=$((failures + 1))
else
  echo "  only the two LAN adapters and their app-side session owner"
fi

echo "== no analytics or crash-reporting dependencies"
# Checked against the lock file rather than the manifests, so a transitive
# dependency cannot slip one in.
analytics='firebase|google_analytics|sentry|crashlytics|amplitude|mixpanel|posthog|matomo|segment|appcenter|datadog|bugsnag'
if hits=$(grep -inE "^  ($analytics)" pubspec.lock 2>/dev/null); then
  echo "$hits" | sed 's/^/  /'
  echo "  an analytics or crash-reporting package is in the dependency tree"
  failures=$((failures + 1))
fi

echo "== stored keys are declared"
# Every shared_preferences key the app writes must be listed in
# docs/privacy.md, so the privacy note and the code cannot drift.
keys=$(grep -rhoE "'stadtbau\.[a-zA-Z0-9._]+'" app/lib --include='*.dart' \
         | tr -d "'" | sort -u)
undocumented=0
for key in $keys; do
  if ! grep -q "$key" docs/privacy.md; then
    echo "  $key is written by the app but not documented in docs/privacy.md"
    undocumented=$((undocumented + 1))
    failures=$((failures + 1))
  fi
done
if [ "$undocumented" -eq 0 ]; then
  echo "  $(echo "$keys" | wc -w) keys, all documented"
else
  echo "  $undocumented of $(echo "$keys" | wc -w) keys undocumented"
fi

if [ "$failures" -gt 0 ]; then
  echo "privacy audit: $failures problem(s)"
  exit 1
fi
echo "privacy audit: ok (see docs/privacy.md)"
