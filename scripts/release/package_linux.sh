#!/usr/bin/env bash
# Packages a built Linux bundle as NextBrain-<version>-<build>-x64.tar.gz and .deb (D-144: the Codemagic workflow
# linux-website). The same packaging as build_linux.sh (D-137, which builds on our own server and publishes into the
# releases folder); keep the two in step when one changes.
#
#   scripts/release/package_linux.sh <bundle dir> <out dir> <version> <build>
#
# <bundle dir> is build/linux/x64/release/bundle (holding the `nextbrain` binary); needs dpkg-deb, ldd, dpkg -S.
#
# NB_APPIMAGE=1 also makes NextBrain-<version>-<build>-x86_64.AppImage (Learning Hub Phase 8, docs/release/LINUX.md):
# the same bundle, desktop file and icon, plus libsqlite3 (sqflite_common_ffi's offline database). Off by default, so
# the linux-website workflow uploads only the .deb and .tar.gz until the server accepts the new file (Phase 9).
#   NB_APPIMAGETOOL=<path>   the appimagetool to use; else the pinned release below is downloaded (its SHA-256 printed)
#   NB_APPIMAGE_DRY_RUN=1    build and check the AppDir, print the appimagetool command, do not run it
# The SHA-256 of every file made is printed at the end.
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

APPIMAGE=""
if [ "${NB_APPIMAGE:-}" = "1" ]; then
  APPIMAGE="NextBrain-${VERSION}-${BUILD}-x86_64.AppImage"
  echo "==> ${APPIMAGE}"
  A="$STAGE/NextBrain.AppDir"
  L="$A/opt/nextbrain/lib"
  # the bundle stays whole in one folder: the Flutter binary finds data/ and lib/ next to itself (/proc/self/exe)
  mkdir -p "$A/opt/nextbrain" "$A/usr/share/applications" "$A/usr/share/icons/hicolor/512x512/apps"
  cp -a "$BUNDLE/." "$A/opt/nextbrain/"
  # the offline database: sqlite3's build hook puts libsqlite3.so into bundle/lib; a build without it opens the
  # system's libsqlite3.so.0 by name, which a minimal distribution may lack, so it is then bundled from the build host
  hook_sqlite="$(find "$L" -maxdepth 1 -name 'libsqlite3*' -printf '%f ' 2>/dev/null || true)"
  if [ -n "$hook_sqlite" ]; then
    echo "libsqlite3: from the build hook ($hook_sqlite)"
  else
    sys_sqlite="$(ldconfig -p 2>/dev/null | awk '/libsqlite3\.so\.0 .*x86-64/{print $NF; exit}')"
    if [ -z "$sys_sqlite" ] || [ ! -f "$sys_sqlite" ]; then
      echo "no libsqlite3 in the bundle and none on this host (apt-get install libsqlite3-0)" >&2
      exit 1
    fi
    cp -L "$sys_sqlite" "$L/libsqlite3.so.0"
    echo "libsqlite3: bundled from the host ($sys_sqlite)"
  fi
  # every library the binary and the bundled .so files need must resolve (the system ones come from the user's distro)
  unresolved="$( { LD_LIBRARY_PATH="$L" ldd "$A/opt/nextbrain/nextbrain"
    find "$L" -name '*.so*' -exec env LD_LIBRARY_PATH="$L" ldd {} \; ; } 2>/dev/null | grep 'not found' | sort -u || true)"
  if [ -n "$unresolved" ]; then
    printf 'unresolved libraries:\n%s\n' "$unresolved" >&2
    exit 1
  fi
  cat > "$A/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/opt/nextbrain/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/opt/nextbrain/nextbrain" "$@"
EOF
  chmod 755 "$A/AppRun"
  printf '%s\n' "${DESKTOP//\/opt\/nextbrain\/nextbrain/nextbrain}" > "$A/com.doubley.nextbrain.desktop"
  cp "$A/com.doubley.nextbrain.desktop" "$A/usr/share/applications/"
  cp "$ICON" "$A/nextbrain.png"
  cp "$ICON" "$A/usr/share/icons/hicolor/512x512/apps/nextbrain.png"
  ln -s nextbrain.png "$A/.DirIcon"
  if command -v desktop-file-validate >/dev/null; then desktop-file-validate "$A/com.doubley.nextbrain.desktop"; fi

  tool="${NB_APPIMAGETOOL:-}"
  # pinned: https://github.com/AppImage/appimagetool/releases (1.9.0); it fetches the type-2 runtime it embeds
  tool_url="https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage"
  if [ "${NB_APPIMAGE_DRY_RUN:-}" = "1" ]; then
    echo "dry run: AppDir ok ($(du -sh "$A" | cut -f1)); would run:"
    echo "  ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 ${tool:-$tool_url} --no-appstream $A $OUT/$APPIMAGE"
    APPIMAGE=""
  else
    if [ -z "$tool" ]; then
      tool="$STAGE/appimagetool"
      curl -fsSL -o "$tool" "$tool_url"
      chmod 755 "$tool"
      echo "appimagetool 1.9.0 sha256 $(sha256sum "$tool" | cut -d' ' -f1)"
    fi
    # APPIMAGE_EXTRACT_AND_RUN: no FUSE needed (containers, CI)
    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$A" "$OUT/$APPIMAGE"
    chmod 755 "$OUT/$APPIMAGE"
  fi
fi

(cd "$OUT" && for f in "${NAME}.tar.gz" "${NAME}.deb" ${APPIMAGE:+"$APPIMAGE"}; do
  # printed, not written beside them: upload_artifacts.sh sends every file in the folder
  sha256sum "$f"
done)
ls -la "$OUT"
