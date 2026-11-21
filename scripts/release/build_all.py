#!/usr/bin/env python3
"""Every release build this machine can make, in one run (Learning Hub Phase 9, N4). Guide: docs/release/BUILD.md.

    .venv312/Scripts/python scripts/release/build_all.py [--only android-apk,windows ...] [--dry-run]

Targets, in order (each one runs only where it can; the others are SKIPPED with the reason):
  android-apk   three signed, obfuscated APKs (arm64-v8a, armeabi-v7a, universal) through publish_release.py's build,
                each checked: release signer, versionCode = pubspec build.        Needs the release key (below).
  android-aab   the Play App Bundle NextBrain-<version>-<build>.aab, signed with the same key. Never offered for
                download: release_manifest.py records it as "listed": false.     Needs the release key.
  windows       scripts/release/package_windows.ps1 (Inno Setup installer NextBrain-<version>-windows-x64-setup.exe
                + the zip) when it exists, else `flutter build windows` + the zip only.          Windows only.
  linux         `flutter build linux` + scripts/release/package_linux.sh (.deb, .tar.gz, AppImage).   Linux only.
  macos         `flutter build macos` + an unsigned .dmg (hdiutil). Signed + notarised builds: Codemagic
                `macos-website` (docs/release/APPLE.md).                                         macOS only.
  ios           `flutter build ipa` (needs the Apple signing set up in Xcode).                   macOS only.
  web           `flutter build web --base-href /app/` + scripts/web/postbuild.dart (build/web, not a release file).

Output: build/releases/<version>-<build>/ (git-ignored; the folder publish_release.py --no-build reads), with
SHA256SUMS (`sha256sum -c` format) and build_all.json (each target: ok | failed | SKIPPED + reason, files, sizes).
Debug symbols: build/debug-info/<version>+<build>/<target>/ (keep them: the only way to read a crash).
Exit code 1 when a target that could run failed; SKIPPED targets never fail the run.

Signing: the release keystore stays OUTSIDE the repo, ~/.nextbrain-keys/ (key.properties next to the .jks, or
NEXTBRAIN_KEY_PROPERTIES). Its values are passed to Gradle through the environment and are never printed or copied.
Nothing is uploaded: publishing is publish_release.py / release_manifest.py.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish_release as pr  # noqa: E402  (version, sha256, flutter, signing, the APK build and checks)

FRONT = pr.FRONT
TARGETS = ("android-apk", "android-aab", "windows", "linux", "macos", "ios", "web")


class Skip(Exception):
    """The target cannot run on this machine; the message is the reason."""


def run(cmd: list[str], env: dict | None = None, cwd: Path = FRONT) -> None:
    print("   $ " + " ".join(str(c) for c in cmd), flush=True)
    if subprocess.run([str(c) for c in cmd], cwd=cwd, env=env).returncode != 0:
        raise RuntimeError(f"command failed: {Path(str(cmd[0])).name} {' '.join(str(c) for c in cmd[1:3])}")


def symbols(ver: str, build: int, name: str) -> Path:
    return FRONT / "build" / "debug-info" / f"{ver}+{build}" / name


def need_flutter() -> str:
    exe = shutil.which("flutter.bat") or shutil.which("flutter")
    if not exe:
        raise Skip("flutter is not on PATH")
    return exe


def need_key() -> dict:
    if not pr.KEY_PROPS.exists():
        raise Skip(f"no release key: {pr.KEY_PROPS} missing (NEXTBRAIN_KEY_PROPERTIES); never built with the debug key")
    env = pr.signing_env()
    if not Path(env["ANDROID_KEYSTORE_PATH"]).is_file():
        raise Skip("the keystore named in key.properties does not exist")
    return env


def need_android_sdk() -> None:
    try:
        pr.build_tools()
    except SystemExit as e:
        raise Skip(str(e)) from None


def need_os(name: str, label: str) -> None:
    if sys.platform != name:
        raise Skip(f"needs {label}; this machine is {sys.platform}")


def zip_dir(src: Path, out: Path, top: str) -> None:
    tmp = out.with_suffix(out.suffix + ".part")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob("*")):
            if f.is_file():
                z.write(f, f"{top}/{f.relative_to(src).as_posix()}")
    os.replace(tmp, out)


# ---- targets: each returns the files it made in the out dir; raises Skip when it cannot run here ----

def t_android_apk(ver: str, build: int, out: Path) -> list[Path]:
    need_flutter()
    need_key()
    need_android_sdk()
    pr.build_android(ver, build, out)
    files = []
    for arch, _ in pr.ANDROID_TARGETS:
        apk = out / f"NextBrain-{ver}-{build}-{arch}.apk"
        pr.check_apk(apk, build)
        files.append(apk)
    return files


def t_android_aab(ver: str, build: int, out: Path) -> list[Path]:
    exe = need_flutter()
    env = need_key()
    run([exe, "build", "appbundle", "--release", "--obfuscate", f"--split-debug-info={symbols(ver, build, 'android-aab')}"],
        env=env)
    aab = out / f"NextBrain-{ver}-{build}.aab"
    shutil.copy2(FRONT / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab", aab)
    jarsigner = shutil.which("jarsigner")
    if jarsigner:  # the signature only; no password is needed to verify
        res = subprocess.run([jarsigner, "-verify", str(aab)], capture_output=True, text=True)
        if res.returncode != 0 or "jar verified" not in res.stdout:
            raise RuntimeError(f"{aab.name}: jarsigner does not verify it")
    else:
        print("   note: jarsigner not on PATH, the AAB signature was not checked")
    return [aab]


def t_windows(ver: str, build: int, out: Path) -> list[Path]:
    need_os("win32", "Windows")
    exe = need_flutter()
    before = set(out.glob("*"))
    script = FRONT / "scripts" / "release" / "package_windows.ps1"
    if script.exists():  # Phase 8 N2: the Inno Setup installer + the zip
        run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script])
        made = FRONT / "build" / "releases" / ver
        for f in list(made.glob("NextBrain-*windows*")) if made.is_dir() and made != out else []:
            shutil.copy2(f, out / f.name)
    else:
        print("   note: scripts/release/package_windows.ps1 is missing (Phase 8 N2): zip only, no installer")
        run([exe, "build", "windows", "--release", "--obfuscate", f"--split-debug-info={symbols(ver, build, 'windows')}"])
        zip_dir(FRONT / "build" / "windows" / "x64" / "runner" / "Release", out / f"NextBrain-{ver}-{build}-windows-x64.zip",
                "NextBrain")
    return sorted(set(out.glob("NextBrain-*windows*")) - before) or sorted(out.glob("NextBrain-*windows*"))


def t_linux(ver: str, build: int, out: Path) -> list[Path]:
    need_os("linux", "a Linux host (the server through publish_release.py --linux, WSL, or Codemagic linux-website)")
    exe = need_flutter()
    run([exe, "build", "linux", "--release", "--obfuscate", f"--split-debug-info={symbols(ver, build, 'linux')}"])
    before = set(out.glob("*"))
    run(["bash", FRONT / "scripts" / "release" / "package_linux.sh", FRONT / "build" / "linux" / "x64" / "release" / "bundle",
         out, ver, str(build)])
    return sorted(set(out.glob("*")) - before)


def t_macos(ver: str, build: int, out: Path) -> list[Path]:
    need_os("darwin", "macOS (Codemagic macos-website builds it, docs/release/APPLE.md)")
    exe = need_flutter()
    if not shutil.which("hdiutil"):
        raise Skip("hdiutil is not on PATH")
    run([exe, "build", "macos", "--release", "--obfuscate", f"--split-debug-info={symbols(ver, build, 'macos')}"])
    apps = sorted((FRONT / "build" / "macos" / "Build" / "Products" / "Release").glob("*.app"))
    if not apps:
        raise RuntimeError("no .app in build/macos/Build/Products/Release")
    dmg = out / f"NextBrain-{ver}-{build}-macos.dmg"
    dmg.unlink(missing_ok=True)
    run(["hdiutil", "create", "-volname", "NextBrain", "-srcfolder", apps[0], "-ov", "-format", "UDZO", dmg])
    return [dmg]


def t_ios(ver: str, build: int, out: Path) -> list[Path]:
    need_os("darwin", "macOS with the Apple signing (Codemagic ios-testflight, docs/release/APPLE.md)")
    exe = need_flutter()
    run([exe, "build", "ipa", "--release", "--obfuscate", f"--split-debug-info={symbols(ver, build, 'ios')}"])
    files = []
    for ipa in (FRONT / "build" / "ios" / "ipa").glob("*.ipa"):
        dst = out / f"NextBrain-{ver}-{build}-ios.ipa"
        shutil.copy2(ipa, dst)
        files.append(dst)
    return files


def t_web(ver: str, build: int, out: Path) -> list[Path]:
    exe = need_flutter()
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    run([exe, "build", "web", "--release", "--base-href", "/app/"], env=env)
    dart = shutil.which("dart.bat") or shutil.which("dart") or "dart"
    run([dart, "run", "scripts/web/postbuild.dart", "build/web"])
    return []  # build/web is deployed by scripts/server/build_web.sh, not published as a file


RUNNERS = {
    "android-apk": t_android_apk,
    "android-aab": t_android_aab,
    "windows": t_windows,
    "linux": t_linux,
    "macos": t_macos,
    "ios": t_ios,
    "web": t_web,
}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help=f"comma list of {', '.join(TARGETS)}")
    ap.add_argument("--skip", default="", help="comma list of targets to leave out")
    ap.add_argument("--dry-run", action="store_true", help="say what would run or be skipped, build nothing")
    a = ap.parse_args(argv)
    only = [t for t in a.only.split(",") if t] or list(TARGETS)
    skip = {t for t in a.skip.split(",") if t}
    for t in [*only, *skip]:
        if t not in TARGETS:
            ap.error(f"unknown target {t}")

    ver, build = pr.version()
    out = FRONT / "build" / "releases" / f"{ver}-{build}"
    out.mkdir(parents=True, exist_ok=True)
    results: dict[str, dict] = {}
    for t in TARGETS:
        if t not in only or t in skip:
            results[t] = {"status": "SKIPPED", "reason": "not asked for (--only / --skip)"}
            continue
        pr.say(f"{t}")
        try:
            if a.dry_run:
                probe = {"android-apk": lambda: (need_flutter(), need_key(), need_android_sdk()),
                         "android-aab": lambda: (need_flutter(), need_key()),
                         "windows": lambda: (need_os("win32", "Windows"), need_flutter()),
                         "linux": lambda: (need_os("linux", "a Linux host"), need_flutter()),
                         "macos": lambda: (need_os("darwin", "macOS"), need_flutter()),
                         "ios": lambda: (need_os("darwin", "macOS"), need_flutter()),
                         "web": need_flutter}[t]
                probe()
                results[t] = {"status": "would run"}
            else:
                files = RUNNERS[t](ver, build, out)
                results[t] = {"status": "ok", "files": [
                    {"name": f.name, "size": f.stat().st_size, "sha256": pr.sha256(f)} for f in files]}
        except Skip as e:
            results[t] = {"status": "SKIPPED", "reason": str(e)}
        except (RuntimeError, SystemExit, OSError) as e:
            results[t] = {"status": "failed", "reason": str(e)}
        print(f"   {results[t]['status']}" + (f": {results[t]['reason']}" if "reason" in results[t] else ""))

    if not a.dry_run:
        sums = sorted((f["sha256"], f["name"]) for r in results.values() for f in r.get("files", []))
        old = {}
        p_sums = out / "SHA256SUMS"
        if p_sums.exists():  # keep the lines of files built by an earlier run that this run did not rebuild
            for line in p_sums.read_text(encoding="utf-8").splitlines():
                h, _, n = line.partition("  ")
                if n and (out / n).exists():
                    old[n] = h
        old.update({n: h for h, n in sums})
        p_sums.write_text("".join(f"{h}  {n}\n" for n, h in sorted(old.items())), encoding="utf-8")
        (out / "build_all.json").write_text(json.dumps(
            {"version": ver, "build": build, "targets": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    pr.say(f"summary ({ver}+{build}, {out})")
    for t, r in results.items():
        line = f"   {t:12} {r['status']}"
        if "reason" in r:
            line += f" ({r['reason']})"
        for f in r.get("files", []):
            line += f"\n      {f['name']}  {f['size'] / 1e6:.1f} MB  {f['sha256']}"
        print(line)
    return 1 if any(r["status"] == "failed" for r in results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
