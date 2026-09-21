#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Runs everything CI runs: params mirror, analyze, tests, i18n lint, license audit.
#
# Usage:
#   tools/check.sh                 every stage, in order
#   tools/check.sh --list          the stage names
#   tools/check.sh test-sim i18n   only those stages, in the order given
#
# Why stages exist: a full run needs three analysis servers and three test
# runners, and on a loaded 4-core box with a couple of gigabytes free the
# kernel picks one of them off — the run dies with no output and the failure
# looks like a test failure. Naming a stage lets a session work through the
# list at whatever size the machine can hold. CHECK_JOBS caps test concurrency
# (default 2; `dart test` otherwise takes half the cores, and each isolate is
# a process).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /mnt/volume1/toolchain/flutter/bin ]; then
  export PATH="/mnt/volume1/toolchain/flutter/bin:$PATH"
  export PUB_CACHE="${PUB_CACHE:-/mnt/volume1/pub-cache}"
fi

JOBS="${CHECK_JOBS:-2}"

STAGES=(params licenses fonts l10n analyze-sim analyze-net analyze-app \
        test-sim test-net test-app i18n learning docs license privacy)
# Not in STAGES: it needs `flutter build web` first and a Chrome, so it is run
# by name (tools/check.sh origin) and in CI after the web build.
EXTRA_STAGES=(origin a11y)

# Memory available to a new process: free RAM plus free swap, in MiB.
headroom_mib() {
  awk '/^MemAvailable:/ {a=$2} /^SwapFree:/ {s=$2} END {print int((a+s)/1024)}' \
    /proc/meminfo 2>/dev/null || echo ""
}

announce() {
  local mib
  mib="$(headroom_mib)"
  if [ -n "$mib" ]; then
    echo "== $1 (${mib} MiB headroom)"
  else
    echo "== $1"
  fi
}

run_stage() {
  announce "$1"
  case "$1" in
    params)
      dart run tools/gen_params.dart
      if ! git diff --quiet -- packages/stadtbau_sim/lib/src/generated/default_params.dart 2>/dev/null; then
        echo "note: generated params changed; commit packages/stadtbau_sim/lib/src/generated/default_params.dart"
      fi
      ;;
    licenses)
      cmp -s LICENSE app/assets/licenses/AGPL-3.0.txt || { echo "app/assets/licenses/AGPL-3.0.txt differs from LICENSE; copy it"; exit 1; }
      cmp -s LICENSE-EXCEPTION.md app/assets/licenses/APP-STORE-EXCEPTION.md || { echo "app/assets/licenses/APP-STORE-EXCEPTION.md differs from LICENSE-EXCEPTION.md; copy it"; exit 1; }
      ;;
    # The bundled Roboto is subset to the characters the app can display. A
    # glyph it lacks is not a blank on screen: CanvasKit fetches a fallback
    # font for it from Google, which is what the origin stage checks.
    fonts)       python3 tools/subset_fonts.py --check ;;
    l10n)        (cd app && flutter gen-l10n) ;;
    analyze-sim) (cd packages/stadtbau_sim && dart analyze --fatal-infos) ;;
    analyze-net) (cd packages/stadtbau_net && dart analyze --fatal-infos) ;;
    analyze-app) (cd app && flutter analyze --fatal-infos) ;;
    test-sim)    (cd packages/stadtbau_sim && dart test -j "$JOBS") ;;
    test-net)    (cd packages/stadtbau_net && dart test -j "$JOBS") ;;
    test-app)    (cd app && flutter test --concurrency "$JOBS") ;;
    i18n)        dart run tools/i18n_lint.dart ;;
    # The i18n lint checks that both ARB files carry the same keys. It cannot
    # see inside an ICU `select`, where a missing branch renders the generic
    # wording instead of failing, so a German build can fall back where the
    # English one does not. Few paths here: the copy half is deterministic and
    # the reachability half only reports notes.
    learning)    (cd packages/stadtbau_sim && dart run tool/learning_audit.dart --paths "${CHECK_LEARNING_PATHS:-8}") ;;
    docs)        dart run tools/build_docs_site.dart --check ;;
    license)     tools/license_audit.sh ;;
    privacy)     tools/privacy_audit.sh ;;
    origin)      python3 tools/web_origin_check.py --build app/build/web ;;
    # Needs a Linux build (flutter build linux --debug) and at-spi2-core.
    # Reads the app the way a screen reader does; see docs/accessibility.md.
    a11y)        python3 tools/a11y_probe.py \
                   --expect "How Hectopolis works" --expect "Skip" \
                   --expect "Next" --min-nodes 15 ;;
    *)           echo "unknown stage: $1" >&2; echo "stages: ${STAGES[*]}" >&2; exit 2 ;;
  esac
}

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' "${STAGES[@]}"
  printf '%s (needs a web or linux build)\n' "${EXTRA_STAGES[@]}"
  exit 0
fi

if [ "$#" -gt 0 ]; then
  for stage in "$@"; do run_stage "$stage"; done
  echo "stages passed: $*"
  exit 0
fi

for stage in "${STAGES[@]}"; do run_stage "$stage"; done
echo "all checks passed"
