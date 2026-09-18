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

STAGES=(params licenses l10n analyze-sim analyze-net analyze-app \
        test-sim test-net test-app i18n docs license privacy)

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
    l10n)        (cd app && flutter gen-l10n) ;;
    analyze-sim) (cd packages/stadtbau_sim && dart analyze --fatal-infos) ;;
    analyze-net) (cd packages/stadtbau_net && dart analyze --fatal-infos) ;;
    analyze-app) (cd app && flutter analyze --fatal-infos) ;;
    test-sim)    (cd packages/stadtbau_sim && dart test -j "$JOBS") ;;
    test-net)    (cd packages/stadtbau_net && dart test -j "$JOBS") ;;
    test-app)    (cd app && flutter test --concurrency "$JOBS") ;;
    i18n)        dart run tools/i18n_lint.dart ;;
    docs)        dart run tools/build_docs_site.dart --check ;;
    license)     tools/license_audit.sh ;;
    privacy)     tools/privacy_audit.sh ;;
    *)           echo "unknown stage: $1" >&2; echo "stages: ${STAGES[*]}" >&2; exit 2 ;;
  esac
}

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' "${STAGES[@]}"
  exit 0
fi

if [ "$#" -gt 0 ]; then
  for stage in "$@"; do run_stage "$stage"; done
  echo "stages passed: $*"
  exit 0
fi

for stage in "${STAGES[@]}"; do run_stage "$stage"; done
echo "all checks passed"
