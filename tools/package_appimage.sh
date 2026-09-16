#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Packages the Linux desktop bundle as an AppImage (task T-404).
#
# Usage: tools/package_appimage.sh [OUT]           (from anywhere)
#   OUT              where to write the .AppImage (default dist/)
#   APPIMAGETOOL     an appimagetool binary to use; downloaded if unset
#
# Run `flutter build linux --release` first. The AppImage is what a Linux user
# can download and run without installing anything, so the desktop entry and
# icon that distributions and app menus read are part of the deliverable, not
# an afterthought: they live in app/linux/packaging and are copied in here.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID=com.crispstrobe.hectopolis
BUNDLE=app/build/linux/x64/release/bundle
OUT=${1:-dist}

[ -x "$BUNDLE/hectopolis" ] || {
  echo "no Linux bundle at $BUNDLE; run: cd app && flutter build linux --release" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
appdir=$work/AppDir

# Flutter's bundle expects data/ and lib/ beside the executable, so the whole
# bundle moves as a unit and AppRun points the loader at its lib/.
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
         "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -r "$BUNDLE/." "$appdir/usr/bin/"

cp app/linux/packaging/hectopolis.desktop "$appdir/usr/share/applications/$APP_ID.desktop"
cp app/linux/packaging/hectopolis.desktop "$appdir/$APP_ID.desktop"

# AppImage wants the icon at the top of the AppDir under the Icon= name, and
# again in the hicolor theme for desktops that install the AppImage.
if command -v convert >/dev/null 2>&1; then
  convert app/assets/icon/icon-1024.png -resize 512x512 "$appdir/$APP_ID.png"
else
  cp app/assets/icon/icon-1024.png "$appdir/$APP_ID.png"
fi
cp "$appdir/$APP_ID.png" "$appdir/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$HERE/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/hectopolis" "$@"
RUN
chmod +x "$appdir/AppRun"

tool=${APPIMAGETOOL:-}
if [ -z "$tool" ]; then
  tool=$work/appimagetool
  echo "downloading appimagetool"
  curl -sSL -o "$tool" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$tool"
fi

# appimagetool ships as an AppImage itself and needs FUSE to self-mount, which
# containers and CI runners often lack; extracting it sidesteps that.
if ! "$tool" --version >/dev/null 2>&1; then
  echo "appimagetool cannot run directly (no FUSE?); extracting it"
  ( cd "$work" && "$tool" --appimage-extract >/dev/null )
  tool=$work/squashfs-root/AppRun
fi

mkdir -p "$OUT"
out=$(cd "$OUT" && pwd)/Hectopolis-x86_64.AppImage
# ARCH is not inferable from a bare AppDir.
ARCH=x86_64 "$tool" --no-appstream "$appdir" "$out"
echo "wrote $out ($(du -h "$out" | cut -f1))"
