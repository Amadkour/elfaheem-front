# NextBrain for Windows: the installer

Learning Hub Phase 8, N2. The Windows app ships as an **Inno Setup installer** beside the zip of the release folder
(the zip is what `windows-website` uploaded before). Decision: D-1361 (unsigned for now).

| File | What it is |
|---|---|
| `NextBrain-<x.y.z>-<n>-windows-x64-setup.exe` | the installer: what the download banner and the update dialog open (the server's `best_file` for Windows is the first file by name, and `-setup.exe` sorts before `.zip`) |
| `NextBrain-<x.y.z>-<n>-windows-x64.zip` | the release folder as a zip: unzip anywhere and run `nextbrain.exe` (no install, no uninstaller) |
| `*.sha256`, `SHA256SUMS.txt` | the SHA-256 of each file (local output only, never uploaded) |

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release/package_windows.ps1            # pubspec's version
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release/package_windows.ps1 -BuildName 1.2.0 -BuildNumber 7
```

- `flutter build windows --release --obfuscate --split-debug-info=build/debug-info/<x.y.z>+<n>/windows/` (the flags of
  `scripts/build_release.sh`), symbols also zipped to `build/debug-info-<x.y.z>+<n>-windows.zip`. **Keep them**:
  `flutter symbolize -i trace.txt -d build/debug-info/<x.y.z>+<n>/windows/app.windows-x64.symbols` is the only way to
  read a stack trace of that build.
- Output in `build/releases/<x.y.z>-<n>/` (gitignored), the same folder `publish_release.py` uses for Android.
- `-UploadDir build/nb-upload` also copies the installer and the zip there: that is how `windows-website`
  (`codemagic.yaml`) calls it, on Codemagic and on the owner's runner (`tools/runner/`, D-146) alike.
- `-SkipBuild` packages an existing `build/windows/x64/runner/Release/`.
- `-TestApi http://localhost:41080/api` makes a TEST package against a local stack: a `--profile` build (a release
  build accepts only an `https://` API, `resolveApiBaseUrl`), named `…-TEST-setup.exe`, written to
  `build/windows-test/`, never to `build/releases/` and never uploaded. Same AppId, so it installs over a real one.
- **The device database (D-1353).** `sqflite_common_ffi` opens `sqlite3.dll`, which the `sqlite3` package's build hook
  puts next to `nextbrain.exe`. The script refuses to package a folder without it.

**Inno Setup 6.** The script finds `ISCC.exe` through `ISCC`, PATH, `%LOCALAPPDATA%\Programs\Inno Setup 6` or
Program Files; when it is missing it runs `winget install JRSoftware.InnoSetup --scope user`, else
`choco install innosetup` (Codemagic's Windows image has Chocolatey). No Codemagic-only tool is involved (D-146).
`nextbrain_runner.py --check` reports a missing Inno Setup on a Windows runner. Version used for the first build:
**6.7.3** (winget).

## What the installer does (`windows/installer/nextbrain.iss`)

- **Per user, no admin prompt**: installs to `%LOCALAPPDATA%\Programs\NextBrain`. "Install for all users" stays
  possible from the privileges dialog or `/ALLUSERS` (then Program Files, with the admin prompt).
- **Fixed AppId** `{CFB932BC-74BD-4AD0-856E-030D692F6CD5}`: a new version upgrades the old one in place (the running app
  is closed first). **Never change it**, or the next version installs beside the old one.
- Arabic and English wizard, picked from the Windows display language (Arabic when it is neither).
- The name, publisher (DoubleY) and icon (`windows/runner/resources/app_icon.ico`) of the app; a Start-menu entry; an
  optional desktop icon; "Launch NextBrain" at the end; an uninstaller in Settings › Apps.
- Windows 10 or newer, x64.

**Uninstall and the app's data.** The app folder always goes. The data folder,
`%APPDATA%\DoubleY\NextBrain` (path_provider's support folder: the device database `nb_local_v1.db` with the outbox
and the read cache, settings, the sign-in), is **kept unless the person answers Yes** to "Also delete NextBrain's data
on this computer?" (default No: progress not synced yet would be lost). A silent uninstall (`/SILENT`, `/VERYSILENT`)
always keeps it. Reinstalling after a "keep" signs the person back in with their offline progress intact.

## For the person installing: SmartScreen

The installer is not signed yet, so Windows shows a warning the first time:

1. Download `NextBrain-…-windows-x64-setup.exe` from nextbrain.site. If the browser says the file "isn't commonly
   downloaded", choose **Keep** (Edge: `…` › Keep › Show more › Keep anyway).
2. Open it. Windows shows **"Windows protected your PC"**. Click **More info**, check that the app is
   `NextBrain-…-setup.exe`, then **Run anyway**.
3. The installer opens in your language. No administrator password is asked. Finish, and NextBrain opens.

Updates install the same way and replace the old version. To remove it: Settings › Apps › NextBrain › Uninstall.

## What a code-signing certificate would change

- **OV certificate** (organisation validated, about 200 – 400 USD a year, a hardware token or a cloud HSM since 2023):
  the warning names "DoubleY" as the publisher instead of "Unknown publisher", and SmartScreen stops warning once the
  certificate has built a reputation (downloads over weeks).
- **EV certificate** (or Microsoft's **Azure Trusted Signing**, about 10 USD a month, for a company with three years of
  history): no SmartScreen warning from the first download.
- What changes in the repo: one signing step in `package_windows.ps1` (`signtool sign /fd sha256 /tr <timestamp url>`
  on `nextbrain.exe` before packaging, and `SignTool=` in `nextbrain.iss` for the installer and the uninstaller),
  the certificate's secret in Codemagic's encrypted variables / the runner's `runner.env`, never in the repo. Nothing
  else: the AppId, the file names and the upgrade path stay the same.
- An MSIX for the Microsoft Store is the other route (the store signs it); the server already accepts `.msix` for
  Windows.

## Building on Visual Studio 2026

MSVC 14.5x stops `bluetooth_low_energy_windows`, `permission_handler_windows` and `local_auth_windows` (built with
`/await`) on error STL1011. `windows/CMakeLists.txt` defines `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`
for every target, so no environment variable is needed (VS 2022 ignores it). Two other things seen on the first build:
the Firebase C++ SDK download (`build/windows/x64/firebase_cpp_sdk_windows_14.0.0.zip`, about 960 MB) can stall; a
complete copy from another checkout's `build/windows/x64/` can be dropped in. A build killed during the first CMake
configure leaves `CMAKE_INSTALL_PREFIX=C:/Program Files/nextbrain` in `CMakeCache.txt` and the INSTALL step then fails
(MSB3073, "cannot create directory"): delete `build/windows/x64/CMakeCache.txt` and build again.

## First run (2026-11-21, this PC, Inno Setup 6.7.3, VS 2026)

| File (1.0.0+1) | Bytes | SHA-256 |
|---|---|---|
| `NextBrain-1.0.0-1-windows-x64-setup.exe` | 39,061,784 | `fe8f30f0223a6c5ef833cc9726e6c344537f7017dc3e86554e19a410e8feee18` |
| `NextBrain-1.0.0-1-windows-x64.zip` | 54,544,753 | `e654b1f393912f4ceb040f650e53ca19d974c605b240f5ccdf6df98cc9b4b255` |

- **Install** (`/VERYSILENT`): no admin prompt, `%LOCALAPPDATA%\Programs\NextBrain`, Start-menu entry, one uninstall
  entry (`{CFB932BC-…}_is1`, NextBrain 1.0.0). `sqlite3.dll` is in the release folder and in the installed app.
- **Run** (release, production API): opens on the sign-in page; the process loads `sqlite3.dll` from the install
  folder and `%APPDATA%\DoubleY\NextBrain\nb_local_v1.db` is created (the device database opens).
- **Upgrade**: the TEST installer over the release one replaced it in place (still one uninstall entry).
- **Uninstall** (interactive): "Are you sure" → Yes, the data question → **No**: the app folder, the uninstall entry
  and the Start-menu entry are gone, `%APPDATA%\DoubleY\NextBrain` (with `nb_local_v1.db`) is kept.
- **The offline / sync run (sign in, play a game offline, reconnect, see it sync) was NOT done.** Gaps:
  1. A release build refuses an `http://` API (`resolveApiBaseUrl`), so the local stack needs the `--profile` TEST
     package. Installed, it starts, reaches the local stack (theme + disable list load, `sqlite3.dll` loaded) but its
     window stays **white** on this PC (Impeller logs `SetInheritedOpacity` validation errors; the same with
     `enable-impeller=false`), while the release build paints normally. Not diagnosed further.
  2. The app exposes no UI Automation tree (one `FLUTTERVIEW` pane), so the flow could only be driven with the real
     mouse and keyboard on the owner's active desktop, which was not done.
  To close it: on a free desktop, run the installed release build against an `https://` stack (or diagnose the
  profile window), sign in as `market.student@example.test`, open Games, cut the network, finish a game, reconnect,
  and check a `game_play` row in `sync_ops` for that user.
