#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Hectopolis — archive, sign, export, validate and (optionally) upload the iOS
# App Store build. This is the single implementation of the build recipe: the
# GitHub Actions workflow (.github/workflows/ios-release.yml) calls this script
# so that CI and a local Mac run exactly the same steps.
#
# Requires macOS with Xcode and CocoaPods. It does NOT install signing
# credentials — the Apple Distribution identity must already be in a keychain on
# the search list and the "Hectopolis AppStore CI" provisioning profile must
# already be installed (CI does both before calling this; on a developer Mac
# they are installed once, see docs/release/ios.md).
#
# Usage:
#   tools/ios/build-ios-appstore.sh [options]
#
#     (no options)     archive + export + validate + UPLOAD to App Store Connect
#     --no-upload      archive + export + validate, stop before uploading
#     --upload-only    skip the build; upload the .ipa already in the export dir
#     --no-validate    skip the advisory `altool --validate-app` pre-check
#     -h | --help      this text
#
# Environment (only needed for --validate / upload):
#   ASC_KEY_ID     App Store Connect API key id, e.g. 9RMU3C7422. The matching
#                  private key must be at
#                  ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#   ASC_ISSUER_ID  App Store Connect issuer id (UUID)
#   ASC_APP_ID     numeric Apple ID of the app record (altool cannot resolve it
#                  from the bundle id: "Cannot determine the Apple ID from
#                  Bundle ID")
#
# Deliberately NOT used anywhere in here:
#   * `flutter build ipa`  — forces *automatic* signing, which needs an Xcode
#     account the runner does not have.
#   * `-allowProvisioningUpdates` — on CI it mints a Development certificate and
#     revokes the shared Distribution certificate for the whole account.

set -euo pipefail

BUNDLE_ID="com.crispstrobe.hectopolis"
SCHEME="Runner"

DO_BUILD=1
DO_VALIDATE=1
DO_UPLOAD=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-upload)   DO_UPLOAD=0 ;;
    --upload-only) DO_BUILD=0; DO_VALIDATE=0; DO_UPLOAD=1 ;;
    --no-validate) DO_VALIDATE=0 ;;
    -h|--help)     awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"
IOS_DIR="$APP_DIR/ios"
ARCHIVE="$APP_DIR/build/ios/archive/Runner.xcarchive"
EXPORT_DIR="$APP_DIR/build/ios/ipa"
EXPORT_OPTIONS="$IOS_DIR/ExportOptions.plist"

# `version: X.Y.Z+BUILD` from app/pubspec.yaml. Apple rejects a duplicate
# CFBundleVersion, and once a marketing version is approved the next binary
# needs a strictly higher X.Y.Z (ITMS-90062) — see docs/release/ios.md.
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+]*\)+.*$/\1/p' "$APP_DIR/pubspec.yaml" | head -1)"
BUILD_NUMBER="$(sed -n 's/^version:[[:space:]]*[^+]*+\(.*\)$/\1/p' "$APP_DIR/pubspec.yaml" | head -1)"
if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "ERROR: could not parse 'version: X.Y.Z+BUILD' from $APP_DIR/pubspec.yaml" >&2
  exit 1
fi

echo "=============================================================="
echo " Hectopolis iOS App Store build"
echo "   bundle id     $BUNDLE_ID"
echo "   version       $VERSION (build $BUILD_NUMBER)"
if [ "$DO_BUILD" = 1 ]; then
  echo "   mode          archive + export$([ "$DO_VALIDATE" = 1 ] && echo " + validate")$([ "$DO_UPLOAD" = 1 ] && echo " + UPLOAD" || echo " (no upload)")"
else
  echo "   mode          UPLOAD ONLY (reusing $EXPORT_DIR)"
fi
echo "=============================================================="

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: this script needs macOS with Xcode; uname is $(uname -s)." >&2
  exit 1
fi

# --------------------------------------------------------------------------
# Archive + export
# --------------------------------------------------------------------------
if [ "$DO_BUILD" = 1 ]; then
  # Flutter 3.44 defaults plugins to a local Swift Package while the Podfile
  # still installs the same plugins, so a bare `xcodebuild archive` dies with
  # `error: redefinition of '<plugin symbol>'`. The pbxproj has the SPM
  # references stripped; this keeps the toolchain from adding them back.
  flutter config --no-enable-swift-package-manager

  # Pub workspace: resolve from the repo root, then generate the ARB-backed
  # localisations that app/lib imports.
  ( cd "$REPO_ROOT" && flutter pub get )
  ( cd "$APP_DIR" && flutter gen-l10n )

  # --config-only writes Generated.xcconfig and the CocoaPods integration
  # (Flutter.framework search paths a bare xcodebuild would otherwise miss)
  # without building or signing anything.
  # App Store builds leave relay play out for now (app/lib/game/build_features.dart);
  # --config-only writes the define into Generated.xcconfig, where the archive's
  # Dart build picks it up. tools/check.sh store-flags checks it stays here.
  ( cd "$APP_DIR" && PATH="/usr/bin:$PATH" flutter build ios --release --config-only --no-codesign --dart-define=HECTOPOLIS_RELAY=false )

  # `env -u GEM_HOME -u GEM_PATH -u RUBYOPT`: the runner (and Homebrew Macs)
  # export a Ruby environment that the system CocoaPods refuses to load.
  ( cd "$APP_DIR" && PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
      pod install --project-directory=ios )

  # ARCHIVE UNSIGNED. A bare `xcodebuild archive` otherwise insists on an iOS
  # *Development* profile for on-device signing, which CI cannot have (only the
  # Distribution key is present). Signing is applied at -exportArchive from
  # ExportOptions.plist. The signing settings stay in the pbxproj / export
  # options — passing them as global `xcodebuild` build settings would force a
  # provisioning profile onto every Pod framework
  # ("<plugin> does not support provisioning profiles").
  rm -rf "$ARCHIVE" "$EXPORT_DIR"
  ( cd "$APP_DIR" && PATH="/usr/bin:$PATH" xcodebuild \
      -workspace ios/Runner.xcworkspace \
      -scheme "$SCHEME" \
      -configuration Release \
      -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      -archivePath "$ARCHIVE" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      clean archive )

  # The archived .app is named after PRODUCT_NAME, which need not be "Runner"
  # (that is also why the exported .ipa below has to be globbed).
  if [ -z "$(ls -d "$ARCHIVE"/Products/Applications/*.app 2>/dev/null | head -1 || true)" ]; then
    echo "ERROR: archive produced no .app at $ARCHIVE" >&2
    exit 1
  fi

  ( cd "$APP_DIR" && PATH="/usr/bin:$PATH" xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportPath "$EXPORT_DIR" \
      -exportOptionsPlist "$EXPORT_OPTIONS" )
fi

# xcodebuild names the exported .ipa after PRODUCT_NAME, not after the scheme —
# it is `Runner.ipa` only by coincidence. Glob for it.
IPA="$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1 || true)"
if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
  echo "ERROR: no .ipa in $EXPORT_DIR — export failed, nothing to upload." >&2
  ls -la "$EXPORT_DIR" 2>/dev/null || true
  exit 1
fi
echo "IPA: $IPA"
shasum -a 256 "$IPA"

if [ "$DO_BUILD" = 1 ]; then
  # Prove the export really signed the bundle; an unsigned .ipa uploads and is
  # then rejected asynchronously, which is a much slower way to learn this.
  VERIFY_DIR="$(mktemp -d)"
  unzip -qo "$IPA" -d "$VERIFY_DIR"
  # The .app inside Payload/ is named after PRODUCT_NAME, like the .ipa — glob.
  APP="$(ls -d "$VERIFY_DIR"/Payload/*.app 2>/dev/null | head -1 || true)"
  [ -n "$APP" ] || { echo "ERROR: no .app inside $IPA" >&2; exit 1; }
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign -dvv "$APP" 2>&1 | grep -i 'Authority=Apple Distribution' \
    || { echo "ERROR: $(basename "$APP") is not signed by an Apple Distribution certificate." >&2; exit 1; }
  rm -rf "$VERIFY_DIR"
fi

# Write the path out for a caller (GitHub Actions reads $GITHUB_ENV).
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "IPA_PATH=$IPA" >> "$GITHUB_ENV"
fi

if [ "$DO_VALIDATE" = 0 ] && [ "$DO_UPLOAD" = 0 ]; then
  echo "Done (build only)."
  exit 0
fi

# --------------------------------------------------------------------------
# altool — validate and upload
# --------------------------------------------------------------------------
: "${ASC_KEY_ID:?ASC_KEY_ID must be set for validate/upload}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID must be set for validate/upload}"
: "${ASC_APP_ID:?ASC_APP_ID must be set for validate/upload}"

KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [ ! -f "$KEY_FILE" ]; then
  echo "ERROR: App Store Connect API key not found at $KEY_FILE" >&2
  echo "       (write it from the ASC_API_KEY_P8_BASE64 secret, see docs/release/ios.md)" >&2
  exit 1
fi

if [ "$DO_VALIDATE" = 1 ]; then
  # Advisory only: the upload re-validates server-side and is the real gate, so
  # a validate hiccup must not block a correct build. A failure is reported,
  # never swallowed.
  echo "--- altool --validate-app (advisory) ---"
  if ! xcrun altool --validate-app \
      -f "$IPA" \
      --type ios \
      --apple-id "$ASC_APP_ID" \
      --api-key "$ASC_KEY_ID" \
      --api-issuer "$ASC_ISSUER_ID"; then
    echo "WARNING: --validate-app failed. This is advisory; the upload below is the real gate." >&2
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "- :warning: \`altool --validate-app\` failed (advisory)." >> "$GITHUB_STEP_SUMMARY"
    fi
  fi
fi

if [ "$DO_UPLOAD" = 1 ]; then
  echo "--- altool --upload-package ---"
  # Proven flag set (CrisperWeaver build 75, appstore.md): --upload-package
  # with the numeric Apple ID, bundle id and both version strings.
  xcrun altool --upload-package "$IPA" \
    --type ios \
    --apple-id "$ASC_APP_ID" \
    --bundle-id "$BUNDLE_ID" \
    --bundle-version "$BUILD_NUMBER" \
    --bundle-short-version-string "$VERSION" \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID"
  echo "Uploaded $VERSION (build $BUILD_NUMBER). Apple needs a few minutes to"
  echo "process it before it shows up in App Store Connect / TestFlight."
fi
