#!/usr/bin/env bash
# Packages a built Linux bundle as NextBrain-<version>-<build>-x64.tar.gz and .deb (D-144: the Codemagic workflow
# linux-website). The same packaging as build_linux.sh (D-137, which builds on our own server and publishes into the
# releases folder); keep the two in step when one changes.
#
#   scripts/release/package_linux.sh <bundle dir> <out dir> <version> <build>
#
# <bundle dir> is build/linux/x64/release/bundle (holding the `nextbrain` binary); needs dpkg-deb, ldd, dpkg -S.
set -euo pipefail

BUNDLE="${1:?usage: $0 <bundle dir> <out dir> <version> <build>}"
OUT="${2:?out dir}"
VERSION="${3:?version}"
BUILD="${4:?build number}"
BUNDLE="$(cd "$BUNDLE" && pwd)"
[ -x "$BUNDLE/nextbrain" ] || { echo "no binary at $BUNDLE/nextbrain" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="NextBrain-${VERSION}-${BUILD}-x64"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ICON="$SRC/assets/images/app_icon.png"
[ -f "$ICON" ] || ICON="$SRC/web/icons/Icon-512.png"
DESKTOP="[Desktop Entry]
Type=Application
Name=NextBrain
Comment=NextBrain learning platform
Exec=/opt/nextbrain/nextbrain %U
Icon=nextbrain
Terminal=false
Categories=Education;
StartupWMClass=com.doubley.nextbrain"

echo "==> ${NAME}.tar.gz"
mkdir -p "$STAGE/tar/nextbrain"
cp -a "$BUNDLE/." "$STAGE/tar/nextbrain/"
cp "$ICON" "$STAGE/tar/nextbrain/nextbrain.png"
printf '%s\n' "${DESKTOP//\/opt\/nextbrain\/nextbrain/nextbrain}" > "$STAGE/tar/nextbrain/nextbrain.desktop"
tar -C "$STAGE/tar" -czf "$OUT/${NAME}.tar.gz" nextbrain

echo "==> ${NAME}.deb"
D="$STAGE/deb"
mkdir -p "$D/DEBIAN" "$D/opt/nextbrain" "$D/usr/bin" "$D/usr/share/applications" "$D/usr/share/icons/hicolor/512x512/apps"
cp -a "$BUNDLE/." "$D/opt/nextbrain/"
ln -s /opt/nextbrain/nextbrain "$D/usr/bin/nextbrain"
printf '%s\n' "$DESKTOP" > "$D/usr/share/applications/com.doubley.nextbrain.desktop"
cp "$ICON" "$D/usr/share/icons/hicolor/512x512/apps/nextbrain.png"
# Depends: the packages that own the system libraries the binary and the bundled .so files load
libs="$( { ldd "$BUNDLE/nextbrain"; find "$BUNDLE/lib" -name '*.so*' -exec ldd {} \; ; } 2>/dev/null | awk '/=> \//{print $3}' | { grep -v "^$BUNDLE" || true; } | sort -u)"
deps="libc6, libstdc++6"
for lib in $libs; do
  owner="$(dpkg -S "$(readlink -f "$lib")" 2>/dev/null || dpkg -S "$lib" 2>/dev/null || true)"
  pkg="${owner%%:*}"
  case "$pkg" in ""|libc6|libgcc-s1|"libstdc++6") ;; *) case ", $deps," in *", $pkg,"*) ;; *) deps="$deps, $pkg" ;; esac ;; esac
done
size_kb="$(du -sk "$D/opt" | cut -f1)"
cat > "$D/DEBIAN/control" <<EOF
Package: nextbrain
Version: ${VERSION}+${BUILD}
Section: education
Priority: optional
Architecture: amd64
Maintainer: DoubleY <noreply@nextbrain.site>
Installed-Size: ${size_kb}
Depends: ${deps}
Homepage: https://nextbrain.site
Description: NextBrain learning platform (desktop preview)
 Courses, live classes and exams. Recorded lessons play in the web version for now.
EOF
echo "Depends: ${deps}"
dpkg-deb --root-owner-group --build "$D" "$OUT/${NAME}.deb" >/dev/null
dpkg-deb --info "$OUT/${NAME}.deb" | sed -n '1,4p'
ls -la "$OUT"
