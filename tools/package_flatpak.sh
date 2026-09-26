#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Packages the existing Linux release bundle as a single-file Flatpak (T-404).
#
# Usage: tools/package_flatpak.sh [OUT]
#
# Run `flutter build linux --release` first and install the matching Freedesktop
# runtime and SDK. The output is an installable bundle; the runtime itself is
# fetched from Flathub when a user installs it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID=com.crispstrobe.hectopolis
RUNTIME_VERSION=${FLATPAK_RUNTIME_VERSION:-25.08}
BUNDLE=app/build/linux/x64/release/bundle
OUT=${1:-dist}

command -v flatpak >/dev/null || {
  echo "flatpak is required" >&2
  exit 1
}
[ -x "$BUNDLE/hectopolis" ] || {
  echo "no Linux bundle at $BUNDLE; run: cd app && flutter build linux --release" >&2
  exit 1
}

version=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' app/pubspec.yaml)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
  echo "cannot read a release version from app/pubspec.yaml" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
build=$work/build
repo=$work/repo

flatpak build-init --arch=x86_64 "$build" "$APP_ID" \
  org.freedesktop.Sdk org.freedesktop.Platform "$RUNTIME_VERSION"

# Keep Flutter's executable, data and shared libraries together. The launcher
# sets the same library lookup path as the AppImage package.
mkdir -p "$build/files/bin" "$build/files/lib/hectopolis" \
  "$build/files/share/applications" \
  "$build/files/share/icons/hicolor/512x512/apps" \
  "$build/files/share/metainfo"
cp -a "$BUNDLE/." "$build/files/lib/hectopolis/"
# The variables below belong to the generated launcher and must expand only
# when a user runs the Flatpak, not while this packaging script runs.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'export LD_LIBRARY_PATH="/app/lib/hectopolis/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
  'exec /app/lib/hectopolis/hectopolis "$@"' > "$build/files/bin/hectopolis"
chmod +x "$build/files/bin/hectopolis"

install -m 0644 app/linux/packaging/hectopolis.desktop \
  "$build/files/share/applications/$APP_ID.desktop"
install -m 0644 app/linux/packaging/com.crispstrobe.hectopolis.metainfo.xml \
  "$build/files/share/metainfo/$APP_ID.metainfo.xml"

if command -v convert >/dev/null 2>&1; then
  convert app/assets/icon/icon-1024.png -resize 512x512 \
    "$build/files/share/icons/hicolor/512x512/apps/$APP_ID.png"
else
  install -m 0644 app/assets/icon/icon-1024.png \
    "$build/files/share/icons/hicolor/512x512/apps/$APP_ID.png"
fi

# Flutter needs a display and GPU access. Hectopolis networking is opt-in LAN
# multiplayer; Flatpak exposes networking as one coarse permission, so the
# sandbox cannot grant LAN access without also granting internet access.
flatpak build-finish "$build" \
  --command=hectopolis \
  --share=ipc \
  --share=network \
  --socket=wayland \
  --socket=fallback-x11 \
  --device=dri

flatpak build-export "$repo" "$build" stable
mkdir -p "$OUT"
out=$(cd "$OUT" && pwd)/Hectopolis-$version-x86_64.flatpak
flatpak build-bundle \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$repo" "$out" "$APP_ID" stable

flatpak build-import-bundle "$work/verify-repo" "$out"
echo "wrote $out ($(du -h "$out" | cut -f1))"
