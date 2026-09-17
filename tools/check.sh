#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Runs everything CI runs: params mirror, analyze, tests, i18n lint, license audit.
# Usage: tools/check.sh   (from anywhere)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /mnt/volume1/toolchain/flutter/bin ]; then
  export PATH="/mnt/volume1/toolchain/flutter/bin:$PATH"
  export PUB_CACHE="${PUB_CACHE:-/mnt/volume1/pub-cache}"
fi

echo "== params mirror"
dart run tools/gen_params.dart
if ! git diff --quiet -- packages/stadtbau_sim/lib/src/generated/default_params.dart 2>/dev/null; then
  echo "note: generated params changed; commit packages/stadtbau_sim/lib/src/generated/default_params.dart"
fi

echo "== bundled license assets"
cmp -s LICENSE app/assets/licenses/AGPL-3.0.txt || { echo "app/assets/licenses/AGPL-3.0.txt differs from LICENSE; copy it"; exit 1; }
cmp -s LICENSE-EXCEPTION.md app/assets/licenses/APP-STORE-EXCEPTION.md || { echo "app/assets/licenses/APP-STORE-EXCEPTION.md differs from LICENSE-EXCEPTION.md; copy it"; exit 1; }

echo "== l10n"
(cd app && flutter gen-l10n)

echo "== analyze"
(cd packages/stadtbau_sim && dart analyze --fatal-infos)
(cd app && flutter analyze --fatal-infos)

echo "== test"
(cd packages/stadtbau_sim && dart test)
(cd app && flutter test)

echo "== i18n lint"
dart run tools/i18n_lint.dart

echo "== docs site"
dart run tools/build_docs_site.dart --check

echo "== license audit"
tools/license_audit.sh

echo "== privacy audit"
tools/privacy_audit.sh

echo "all checks passed"
