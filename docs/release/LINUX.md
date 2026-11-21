# Linux builds: `.deb`, `.tar.gz` and AppImage

Learning Hub Phase 8. The Linux app is still the D-137 preview: Firebase and `video_player` have no Linux
implementation, so recorded lessons play in the web app. The offline database (`sqflite_common_ffi`, Phase 7) does
work on Linux.

## Files

`scripts/release/package_linux.sh <bundle> <out> <version> <build>` packages a built bundle
(`build/linux/x64/release/bundle`) as:

| File | For |
|---|---|
| `NextBrain-<v>-<b>-x64.deb` | Ubuntu / Debian: `sudo apt install ./NextBrain-…deb` |
| `NextBrain-<v>-<b>-x64.tar.gz` | any distribution: unpack it and run `nextbrain/nextbrain` |
| `NextBrain-<v>-<b>-x86_64.AppImage` | any distribution, nothing to install (`NB_APPIMAGE=1` only) |

It prints the SHA-256 of each file at the end. It does not write `.sha256` files beside them, because
`upload_artifacts.sh` uploads every file in the folder.

The AppImage is **off by default** (`NB_APPIMAGE=1` turns it on). That way the `linux-website` workflow and
`build_linux.sh` keep uploading only the two files our server knows, until Phase 9 adds the AppImage to the release
manifest and the downloads page.

## The AppImage

- **Layout**: `AppRun` sets `LD_LIBRARY_PATH` to the bundle's `lib/` and starts `opt/nextbrain/nextbrain`. The
  bundle stays whole, because the Flutter binary finds `data/` and `lib/` next to itself. The desktop file is the
  `.deb`'s, with `Exec=nextbrain`, and so is the icon (`assets/images/app_icon.png`).
- **libsqlite3**: the `sqlite3` package's build hook puts `libsqlite3.so` into `bundle/lib`, and the AppImage
  carries it. A build without the hook's library copies the build host's `libsqlite3.so.0` in instead, so the app
  never depends on the user's system for its database. After that, `ldd` must resolve every library of the binary
  and of each bundled `.so`, or the script stops.
- **appimagetool** is pinned to release 1.9.0 (downloaded, its SHA-256 printed), or set `NB_APPIMAGETOOL=<path>`.
  It runs with `APPIMAGE_EXTRACT_AND_RUN=1`, so it needs no FUSE (containers, CI).
- `NB_APPIMAGE_DRY_RUN=1` builds and checks the AppDir and prints the `appimagetool` command without running it.

Running it on a user's machine: `chmod +x NextBrain-…AppImage && ./NextBrain-…AppImage`. On Ubuntu 22.04 and later,
an AppImage needs `libfuse2` (`sudo apt install libfuse2`). Without it, run it with `--appimage-extract-and-run`.

## Building on this PC (Windows): Docker

The WSL distributions here are Rancher Desktop's and Docker Desktop's, with no Ubuntu, so the build runs in an
`ubuntu:22.04` container on the same WSL2 engine. glibc 2.35 is the oldest the files run on.

1. `git -c core.autocrlf=false archive --format=tar -o <dir>/src.tar HEAD`. The working tree has CRLF line
   endings, which bash scripts cannot run with.
2. Run a script in `ubuntu:22.04` with `<dir>` mounted at `/sc`, a volume at `/cache` (the Flutter SDK and the pub
   cache) and `build/releases` at `/out`. The script does the following:
   - installs the `linux-website` packages plus `libsqlite3-0`, `desktop-file-utils`, `xvfb` and `file`;
   - unpacks Flutter 3.47.7;
   - unpacks `src.tar`;
   - runs `flutter build linux --release --obfuscate --split-debug-info=build/debug-info/<version>/linux`;
   - runs `NB_APPIMAGE=1 bash scripts/release/package_linux.sh … /out/<v>-<b>/linux <v> <b>`;
   - copies the symbols to `/out/<v>-<b>/debug-info-linux/`;
   - starts the AppImage under `xvfb-run` for 20 s.

On the server the same packaging runs through `build_linux.sh`. Set `NB_APPIMAGE=1` there once Phase 9 publishes the
file. `build_linux.sh` has its own copy of the `.deb` / `.tar.gz` steps, so the AppImage step would be added to it
then, or `build_linux.sh` would call `package_linux.sh`.

## Phase 8 build (2026-11-21): logged gap, no AppImage built

The real build did not finish on this PC. The container started, but the Rancher Desktop WSL2 disk was too slow
to install the build packages. With `force-unsafe-io`, `apt-get install` of the ~390 build packages had still not
finished after 57 minutes, at about 2 s per package. A DNS failure inside the container also stopped one attempt.
Flutter 3.47.7 (about 2 GB) and the build would have come after that. No `.deb`, `.tar.gz` or AppImage of the real app
exists for this version.

What ran:
- `shellcheck` (koalaman/shellcheck:stable) on `package_linux.sh`: clean.
- A **dry run** in `ubuntu:22.04` on a stand-in bundle (`nextbrain` = `/bin/true`, a stand-in `lib/libsqlite3.so`),
  with `NB_APPIMAGE=1 NB_APPIMAGE_DRY_RUN=1`. The `.tar.gz` and `.deb` were made (`dpkg-deb --info` read), the
  AppDir was built and its `ldd` check passed, and the `appimagetool` command was printed. With no hook library
  and no `libsqlite3.so.0` on the host, the script stopped with the "apt-get install libsqlite3-0" message, as it
  should.

Still owed (the first real AppImage, Phase 9 or on the server). Run on the server, or on a machine with a working
Ubuntu WSL:
- `flutter build linux --release --obfuscate --split-debug-info=build/debug-info/<version>/linux`;
- then `NB_APPIMAGE=1 bash scripts/release/package_linux.sh build/linux/x64/release/bundle build/releases/<v>-<b>/linux <v> <b>`.

Then record here:
- the sizes and SHA-256 it prints;
- whether `bundle/lib` held the hook's `libsqlite3.so`;
- that the AppImage starts (`APPIMAGE_EXTRACT_AND_RUN=1 xvfb-run -a ./NextBrain-…AppImage`) and opens its offline
  database (one game played offline).

An Ubuntu distribution in WSL (`wsl --install -d Ubuntu-22.04`) on a faster disk would make this PC a Linux build
host.
