#!/usr/bin/env bash
# Builds the Linux desktop app on an Ubuntu / Debian x64 machine (the production server: Flutter in $HOME/flutter/bin)
# and publishes it into the releases folder (D-137): Alfaheem-<version>-<build>-x64.deb and .tar.gz, the
# Alfaheem-latest-x64.* links, and the `linux` entry of releases.json (through release_manifest.py).
#
#   bash build_linux.sh            (publish_release.py --linux pipes it over SSH; it is idempotent)
#
# Environment (all optional):
#   NB_SRC=/root/elfaheem/linux-build   a separate clone, so the web build in /root/elfaheem/front is never touched
#   NB_BRANCH=organizations              the branch built
#   NB_RELEASES=/root/elfaheem/releases NB_RELEASES_URL=https://alfaheem.site/releases
#   NB_SKIP_APT=1                        do not install the build packages (they are listed below)
#   NB_NOTES_EN / NB_NOTES_AR            release notes; NB_PRIMARY=pwa (default: the banner offers the web app first
#                                        on Linux, the packages are listed under it) or x64 (the .deb first)
#
# The Linux app is a PREVIEW: Firebase (push, Crashlytics) and the video_player plugin have no Linux implementation,
# so recorded lessons do not play in it; the web app does everything. See docs/DECISIONS.md D-137.
set -euo pipefail
export PATH="$PATH:$HOME/flutter/bin"
SRC="${NB_SRC:-/root/elfaheem/linux-build}"
BRANCH="${NB_BRANCH:-organizations}"
ROOT="${NB_RELEASES:-/root/elfaheem/releases}"
URL="${NB_RELEASES_URL:-https://alfaheem.site/releases}"
FRONT="${NB_FRONT:-/root/elfaheem/front}"
PRIMARY="${NB_PRIMARY:-pwa}"
NOTES_EN="${NB_NOTES_EN:-Preview of the desktop app. Recorded lessons play in the web version for now.}"
NOTES_AR="${NB_NOTES_AR:-نسخة تجريبية من تطبيق سطح المكتب. الدروس المسجلة تعمل في نسخة الويب حاليًا.}"

say() { printf '\n==> %s\n' "$*"; }

[ "$(uname -m)" = "x86_64" ] || { echo "this script builds x64 only (uname -m = $(uname -m))"; exit 2; }
command -v flutter >/dev/null || { echo "flutter not on PATH ($HOME/flutter/bin)"; exit 2; }

if [ -z "${NB_SKIP_APT:-}" ]; then
  say "build packages"
  pkgs=(clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev libjsoncpp-dev
        dpkg-dev xvfb xauth libasound2-dev libpulse-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev)
  missing=()
  for p in "${pkgs[@]}"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p"); done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "installing: ${missing[*]}"
    # a broken third-party source (e.g. a docker.com list for the wrong distribution) must not stop the build: the
    # install below fails by itself if a package is really unavailable
    DEBIAN_FRONTEND=noninteractive apt-get update -qq || echo "apt-get update reported errors (continuing)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
  else
    echo "all present"
  fi
fi

say "source ($BRANCH) in $SRC"
if [ ! -d "$SRC/.git" ]; then
  git clone --quiet "$(git -C "$FRONT" remote get-url origin)" "$SRC"
fi
git -C "$SRC" fetch --quiet origin "$BRANCH"
git -C "$SRC" checkout --quiet -B "$BRANCH" "origin/$BRANCH"
git -C "$SRC" reset --quiet --hard "origin/$BRANCH"
git -C "$SRC" log --oneline -1
[ -d "$SRC/linux" ] || { echo "no linux/ folder on $BRANCH (merge feature/app-downloads first)"; exit 2; }

cd "$SRC"
full="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${full%%+*}"
BUILD="${full##*+}"
NAME="Alfaheem-${VERSION}-${BUILD}-x64"
say "flutter build linux $VERSION+$BUILD"
flutter config --enable-linux-desktop >/dev/null
flutter pub get >/dev/null
# a configure that failed once (a missing -dev package) leaves CMAKE_INSTALL_PREFIX=/usr/local in the cache, and the
# next build then installs the app into the system: always configure from scratch
rm -rf build/linux
flutter build linux --release --obfuscate --split-debug-info="build/debug-info/${full}/linux"
BUNDLE="$SRC/build/linux/x64/release/bundle"
grep -qx "CMAKE_INSTALL_PREFIX:PATH=$BUNDLE" build/linux/x64/release/CMakeCache.txt || { echo "install prefix is not the bundle: stop"; exit 1; }
[ -x "$BUNDLE/alfaheem" ] || { echo "no binary at $BUNDLE/alfaheem"; exit 1; }

say "smoke test (25 s under a virtual display)"
set +e
timeout 25 xvfb-run -a "$BUNDLE/alfaheem" >/tmp/nb-linux-smoke.log 2>&1
code=$?
set -e
tail -n 25 /tmp/nb-linux-smoke.log || true
if [ "$code" = "124" ]; then echo "smoke: still running after 25 s (ok)"; else echo "smoke: exited with $code (look at the log above)"; fi

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

say "package .tar.gz"
mkdir -p "$STAGE/tar/alfaheem"
cp -a "$BUNDLE/." "$STAGE/tar/alfaheem/"
cp "$ICON" "$STAGE/tar/alfaheem/alfaheem.png"
printf '%s\n' "${DESKTOP//\/opt\/alfaheem\/alfaheem/alfaheem}" > "$STAGE/tar/alfaheem/alfaheem.desktop"
mkdir -p "$ROOT/linux"
tar -C "$STAGE/tar" -czf "$ROOT/linux/.${NAME}.tar.gz.part" alfaheem
mv -f "$ROOT/linux/.${NAME}.tar.gz.part" "$ROOT/linux/${NAME}.tar.gz"

say "package .deb"
D="$STAGE/deb"
mkdir -p "$D/DEBIAN" "$D/opt/alfaheem" "$D/usr/bin" "$D/usr/share/applications" "$D/usr/share/icons/hicolor/512x512/apps"
cp -a "$BUNDLE/." "$D/opt/alfaheem/"
ln -s /opt/alfaheem/alfaheem "$D/usr/bin/alfaheem"
printf '%s\n' "$DESKTOP" > "$D/usr/share/applications/com.doubley.alfaheem.desktop"
cp "$ICON" "$D/usr/share/icons/hicolor/512x512/apps/alfaheem.png"
# Depends: the packages that own the system libraries the binary and the bundled .so files load
libs="$( { ldd "$BUNDLE/alfaheem"; find "$BUNDLE/lib" -name '*.so*' -exec ldd {} \; ; } 2>/dev/null   | awk '/=> \//{print $3}' | { grep -v "^$BUNDLE" || true; } | sort -u)"
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
dpkg-deb --root-owner-group --build "$D" "$ROOT/linux/.${NAME}.deb.part" >/dev/null
mv -f "$ROOT/linux/.${NAME}.deb.part" "$ROOT/linux/${NAME}.deb"
dpkg-deb --info "$ROOT/linux/${NAME}.deb" | sed -n '1,4p'

say "manifest"
TOOL="$SRC/scripts/release/release_manifest.py"
python3 "$TOOL" init --root "$ROOT"
python3 "$TOOL" set --root "$ROOT" --base-url "$URL" --platform linux --version "$VERSION" --build "$BUILD" \
  --min-os "Ubuntu $(. /etc/os-release && echo "$VERSION_ID") (x64)" --primary "$PRIMARY" --pwa \
  --notes-en "$NOTES_EN" --notes-ar "$NOTES_AR" \
  --file "x64:deb:linux/${NAME}.deb" --file "x64:tar.gz:linux/${NAME}.tar.gz" \
  --latest "linux/Alfaheem-latest-x64.deb=linux/${NAME}.deb" \
  --latest "linux/Alfaheem-latest-x64.tar.gz=linux/${NAME}.tar.gz"
chmod -R o+rX "$ROOT"
ls -la "$ROOT/linux"
say "done: $URL/linux/${NAME}.deb"
