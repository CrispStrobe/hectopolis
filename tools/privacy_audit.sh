#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Checks the promise the About screen makes (task T-702):
#
#   "Hectopolis runs entirely on your device. The only data it stores is your
#    saved game and your best results, in local app storage. There are no
#    accounts, no ads, no analytics and no network requests while you play."
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

echo "== no networking in first-party code"
# url_launcher is the one sanctioned outbound path: it hands a URL to the
# platform browser when the player taps a link on the About screen. It cannot
# fetch anything back into the app, and nothing calls it during play.
net='dart:io|package:http|package:dio|HttpClient|HttpRequest|WebSocket|RawSocket|ServerSocket|Socket\.|InternetAddress|package:web_socket'
if hits=$(grep -nE "$net" $sources 2>/dev/null); then
  echo "$hits" | sed 's/^/  /'
  echo "  a networking API appeared in first-party code"
  failures=$((failures + 1))
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
