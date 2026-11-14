#!/usr/bin/env bash
# Packages a built Linux bundle as Alfaheem-<version>-<build>-x64.tar.gz and .deb (D-144: the Codemagic workflow
# linux-website). The same packaging as build_linux.sh (D-137, which builds on our own server and publishes into the
# releases folder); keep the two in step when one changes.
#
#   scripts/release/package_linux.sh <bundle dir> <out dir> <version> <build>
#
# <bundle dir> is build/linux/x64/release/bundle (holding the `alfaheem` binary); needs dpkg-deb, ldd, dpkg -S.
set -euo pipefail

BUNDLE="${1:?usage: $0 <bundle dir> <out dir> <version> <build>}"
OUT="${2:?out dir}"
VERSION="${3:?version}"
BUILD="${4:?build number}"
BUNDLE="$(cd "$BUNDLE" && pwd)"
[ -x "$BUNDLE/alfaheem" ] || { echo "no binary at $BUNDLE/alfaheem" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="Alfaheem-${VERSION}-${BUILD}-x64"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ICON="$SRC/assets/images/app_icon.png"
[ -f "$ICON" ] || ICON="$SRC/web/icons/Icon-512.png"
DESKTOP="[Desktop Entry]
Type=Application
Name=Alfaheem
Comment=Alfaheem learning platform
Exec=/opt/alfaheem/alfaheem %U
Icon=alfaheem
Terminal=false
Categories=Education;
StartupWMClass=com.doubley.alfaheem"

echo "==> ${NAME}.tar.gz"
mkdir -p "$STAGE/tar/alfaheem"
cp -a "$BUNDLE/." "$STAGE/tar/alfaheem/"
cp "$ICON" "$STAGE/tar/alfaheem/alfaheem.png"
printf '%s\n' "${DESKTOP//\/opt\/alfaheem\/alfaheem/alfaheem}" > "$STAGE/tar/alfaheem/alfaheem.desktop"
tar -C "$STAGE/tar" -czf "$OUT/${NAME}.tar.gz" alfaheem

echo "==> ${NAME}.deb"
D="$STAGE/deb"
mkdir -p "$D/DEBIAN" "$D/opt/alfaheem" "$D/usr/bin" "$D/usr/share/applications" "$D/usr/share/icons/hicolor/512x512/apps"
cp -a "$BUNDLE/." "$D/opt/alfaheem/"
ln -s /opt/alfaheem/alfaheem "$D/usr/bin/alfaheem"
printf '%s\n' "$DESKTOP" > "$D/usr/share/applications/com.doubley.alfaheem.desktop"
cp "$ICON" "$D/usr/share/icons/hicolor/512x512/apps/alfaheem.png"
# Depends: the packages that own the system libraries the binary and the bundled .so files load
libs="$( { ldd "$BUNDLE/alfaheem"; find "$BUNDLE/lib" -name '*.so*' -exec ldd {} \; ; } 2>/dev/null | awk '/=> \//{print $3}' | { grep -v "^$BUNDLE" || true; } | sort -u)"
deps="libc6, libstdc++6"
for lib in $libs; do
  owner="$(dpkg -S "$(readlink -f "$lib")" 2>/dev/null || dpkg -S "$lib" 2>/dev/null || true)"
  pkg="${owner%%:*}"
  case "$pkg" in ""|libc6|libgcc-s1|"libstdc++6") ;; *) case ", $deps," in *", $pkg,"*) ;; *) deps="$deps, $pkg" ;; esac ;; esac
done
size_kb="$(du -sk "$D/opt" | cut -f1)"
cat > "$D/DEBIAN/control" <<EOF
Package: alfaheem
Version: ${VERSION}+${BUILD}
Section: education
Priority: optional
Architecture: amd64
Maintainer: DoubleY <noreply@alfaheem.site>
Installed-Size: ${size_kb}
Depends: ${deps}
Homepage: https://alfaheem.site
Description: Alfaheem learning platform (desktop preview)
 Courses, live classes and exams. Recorded lessons play in the web version for now.
EOF
echo "Depends: ${deps}"
dpkg-deb --root-owner-group --build "$D" "$OUT/${NAME}.deb" >/dev/null
dpkg-deb --info "$OUT/${NAME}.deb" | sed -n '1,4p'
ls -la "$OUT"
