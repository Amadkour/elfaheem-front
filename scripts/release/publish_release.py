#!/usr/bin/env python3
"""Publish a release for direct download (D-137): build, check, upload, update the manifest. One command:

    .venv312/Scripts/python scripts/release/publish_release.py --android [--linux] [--notes-en ... --notes-ar ...]

  --android      builds three signed, obfuscated APKs from pubspec's version (arm64-v8a: the banner's button,
                 armeabi-v7a: older 32-bit phones, universal: every device), checks the signer and the versionCode,
                 uploads them (temporary name, then rename) with release_manifest.py next to them, and lets the server
                 write the `android` entry of releases.json from the files it actually holds (size + SHA-256, compared
                 with the local ones). Alfaheem-latest.apk points to the universal APK.
  --linux        runs scripts/release/build_linux.sh on the server (builds, packages .deb + .tar.gz, updates `linux`).
  --no-build     publish the APKs already in build/releases/<version>-<build>/ (made by an earlier run).
  --dry-run      build and check only; print what would be published.
  --min-build N  installed builds below N must update (the app's "Please update to continue").

Nothing else changes: publishing never needs a web build, the banner and the apps read the new manifest at once.
Signing: the release keystore's key.properties, outside the repo (default ~/.alfaheem-keys/key.properties, or
NEXTBRAIN_KEY_PROPERTIES). A debug-signed APK is refused. Server access: the pipeline's SSH helpers
(back/scripts/pipeline/pipeline.py, NEXTBRAIN_PIPELINE to point elsewhere; credentials as for the deploy pipeline).
Debug symbols stay in build/debug-info/<version>/android-<arch>/ (keep them: they are the only way to read a crash).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

FRONT = Path(__file__).resolve().parents[2]
SERVER_ROOT = os.environ.get("NEXTBRAIN_RELEASES_ROOT", "/root/elfaheem/releases")
PUBLIC_URL = os.environ.get("NEXTBRAIN_RELEASES_URL", "https://alfheemacademy.com/releases")
KEY_PROPS = Path(os.environ.get("NEXTBRAIN_KEY_PROPERTIES") or Path.home() / ".alfaheem-keys" / "key.properties")
MIN_OS_ANDROID = "Android 7.0"  # minSdk 24 (flutter.minSdkVersion, checked in the built APK below)

# (manifest arch, flutter --target-platform)
ANDROID_TARGETS = [
    ("arm64-v8a", "android-arm64"),
    ("armeabi-v7a", "android-arm"),
    ("universal", "android-arm,android-arm64,android-x64"),
]
PRIMARY_ANDROID = "arm64-v8a"

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(errors="replace")


def say(msg: str) -> None:
    print(f"\n==> {msg}", flush=True)


def version() -> tuple[str, int]:
    m = re.search(r"^version:\s*([0-9][^+\s]*)\+(\d+)\s*$", (FRONT / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if not m:
        raise SystemExit("pubspec.yaml needs version: X.Y.Z+BUILD")
    return m.group(1), int(m.group(2))


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def flutter() -> str:
    exe = shutil.which("flutter.bat") or shutil.which("flutter")
    if not exe:
        raise SystemExit("flutter is not on PATH")
    return exe


def build_tools() -> Path:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(
        Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "sdk")
    bt = Path(sdk) / "build-tools"
    versions = sorted((d for d in bt.iterdir() if d.is_dir()), key=lambda d: [int(x) if x.isdigit() else 0 for x in d.name.split(".")]) if bt.exists() else []
    if not versions:
        raise SystemExit(f"no Android build-tools under {bt}")
    return versions[-1]


def signing_env() -> dict:
    if not KEY_PROPS.exists():
        raise SystemExit(f"release key not found: {KEY_PROPS} (NEXTBRAIN_KEY_PROPERTIES). Never publish a debug-signed APK.")
    props = {}
    for line in KEY_PROPS.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    env = dict(os.environ)
    env.update({
        "ANDROID_KEYSTORE_PATH": props["storeFile"],
        "ANDROID_KEYSTORE_PASSWORD": props["storePassword"],
        "ANDROID_KEY_ALIAS": props["keyAlias"],
        "ANDROID_KEY_PASSWORD": props["keyPassword"],
    })
    return env


def check_apk(apk: Path, build: int) -> str:
    """The signer is the release key (not Android Debug) and the versionCode is pubspec's build. Returns the signer
    certificate's SHA-256."""
    bt = build_tools()
    signer = bt / ("apksigner.bat" if os.name == "nt" else "apksigner")
    out = subprocess.run([str(signer), "verify", "--print-certs", str(apk)], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"{apk.name}: signature does not verify\n{out.stderr}")
    if "Android Debug" in out.stdout:
        raise SystemExit(f"{apk.name}: signed with the DEBUG key, refusing to publish")
    cert = re.search(r"certificate SHA-256 digest: ([0-9a-f]+)", out.stdout)
    aapt = bt / ("aapt2.exe" if os.name == "nt" else "aapt2")
    badging = subprocess.run([str(aapt), "dump", "badging", str(apk)], capture_output=True, text=True).stdout
    code = re.search(r"versionCode='(\d+)'", badging)
    sdk = re.search(r"minSdkVersion:'(\d+)'", badging)
    if not code or int(code.group(1)) != build:
        raise SystemExit(f"{apk.name}: versionCode {code and code.group(1)} != pubspec build {build}")
    if sdk and int(sdk.group(1)) != 24:
        print(f"   note: minSdk is {sdk.group(1)}; update MIN_OS_ANDROID")
    return cert.group(1) if cert else "?"


def build_android(ver: str, build: int, out_dir: Path) -> None:
    env = signing_env()
    exe = flutter()
    out_dir.mkdir(parents=True, exist_ok=True)
    for arch, target in ANDROID_TARGETS:
        say(f"flutter build apk ({arch})")
        symbols = FRONT / "build" / "debug-info" / f"{ver}+{build}" / f"android-{arch}"
        cmd = [exe, "build", "apk", "--release", "--obfuscate", f"--split-debug-info={symbols}",
               f"--target-platform={target}", "-P", "disable-abi-filtering=true"]  # plugin libs follow (build.gradle.kts)
        if subprocess.run(cmd, cwd=FRONT, env=env).returncode != 0:
            raise SystemExit(f"build failed for {arch}")
        shutil.copy2(FRONT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk",
                     out_dir / f"Alfaheem-{ver}-{build}-{arch}.apk")


def pipeline():
    here = os.environ.get("NEXTBRAIN_PIPELINE")
    candidates = [Path(here)] if here else [FRONT.parent / "back" / "scripts" / "pipeline",
                                            FRONT.parent / "_back_org" / "scripts" / "pipeline"]
    for c in candidates:
        if (c / "pipeline.py").exists():
            sys.path.insert(0, str(c))
            import pipeline as p  # noqa: E402
            return p
    raise SystemExit("pipeline.py not found (NEXTBRAIN_PIPELINE)")


def remote(client, script: str) -> str:
    stdin, stdout, stderr = client.exec_command("bash -s", timeout=None)
    stdin.write(script)
    stdin.channel.shutdown_write()
    out = []
    for line in iter(stdout.readline, ""):
        print("   " + line, end="", flush=True)
        out.append(line)
    code = stdout.channel.recv_exit_status()
    err = stderr.read().decode("utf-8", "replace")
    if code != 0:
        raise SystemExit(f"server step failed ({code}):\n{err[-3000:]}")
    return "".join(out)


def upload(sftp, local: Path, remote_path: str) -> None:
    part = remote_path.rsplit("/", 1)
    tmp = f"{part[0]}/.{part[1]}.part"
    size = local.stat().st_size
    last = [-1]

    def progress(done, total):
        pct = int(done * 100 / max(total, 1))
        if pct // 10 != last[0]:
            last[0] = pct // 10
            print(f"   {local.name}: {pct}%", flush=True)

    sftp.put(str(local), tmp, callback=progress)
    if sftp.stat(tmp).st_size != size:
        raise SystemExit(f"{local.name}: uploaded size differs")
    sftp.posix_rename(tmp, remote_path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--android", action="store_true")
    ap.add_argument("--linux", action="store_true")
    ap.add_argument("--no-build", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--min-build", type=int, default=0)
    ap.add_argument("--notes-en", default="")
    ap.add_argument("--notes-ar", default="")
    a = ap.parse_args()
    if not (a.android or a.linux):
        ap.error("choose --android and/or --linux")

    ver, build = version()
    out_dir = FRONT / "build" / "releases" / f"{ver}-{build}"
    files: list[tuple[str, Path]] = []
    if a.android:
        if not a.no_build:
            build_android(ver, build, out_dir)
        say("check the APKs")
        for arch, _ in ANDROID_TARGETS:
            apk = out_dir / f"Alfaheem-{ver}-{build}-{arch}.apk"
            if not apk.exists():
                raise SystemExit(f"missing {apk} (run without --no-build)")
            cert = check_apk(apk, build)
            print(f"   {apk.name}: {apk.stat().st_size / 1e6:.1f} MB  sha256 {sha256(apk)}  signer {cert[:16]}…")
            files.append((arch, apk))
    if a.dry_run:
        say("dry run: nothing uploaded")
        return 0

    p = pipeline()
    host, port, user, password, key = p.load_target()
    client = p.ssh_connect(host, port, user, password, key)
    try:
        q = shlex.quote
        say(f"server: {SERVER_ROOT}")
        remote(client, f"set -e; mkdir -p {q(SERVER_ROOT)}/.tools {q(SERVER_ROOT)}/android {q(SERVER_ROOT)}/linux; "
                       f"chmod o+x /root /root/elfaheem 2>/dev/null || true; chmod -R o+rX {q(SERVER_ROOT)}")
        sftp = client.open_sftp()
        tool = f"{SERVER_ROOT}/.tools/release_manifest.py"
        upload(sftp, Path(__file__).with_name("release_manifest.py"), tool)
        if files:
            say("upload")
            for _, apk in files:
                upload(sftp, apk, f"{SERVER_ROOT}/android/{apk.name}")
            args = [
                "python3", tool, "set", "--root", SERVER_ROOT, "--base-url", PUBLIC_URL, "--platform", "android",
                "--version", ver, "--build", str(build), "--min-build", str(a.min_build), "--min-os", MIN_OS_ANDROID,
                "--primary", PRIMARY_ANDROID, "--notes-en", a.notes_en, "--notes-ar", a.notes_ar, "--no-pwa",
                "--latest", f"android/Alfaheem-latest.apk=android/Alfaheem-{ver}-{build}-universal.apk",
            ]
            for arch, apk in files:
                rel = f"android/{apk.name}"
                args += ["--file", f"{arch}:apk:{rel}", "--expect-sha", f"{rel}={sha256(apk)}"]
            say("manifest (android)")
            remote(client, "set -e\n"
                           f"python3 {q(tool)} init --root {q(SERVER_ROOT)}\n"
                           + " ".join(q(x) for x in args) + "\n"
                           f"chmod -R o+rX {q(SERVER_ROOT)}\n")
        sftp.close()
        if a.linux:
            say("Linux build on the server")
            script = (Path(__file__).with_name("build_linux.sh")).read_text(encoding="utf-8")
            env = ""
            if a.notes_en:
                env += f"export NB_NOTES_EN={q(a.notes_en)}\n"
            if a.notes_ar:
                env += f"export NB_NOTES_AR={q(a.notes_ar)}\n"
            remote(client, env + script)
    finally:
        client.close()
    say(f"published: {PUBLIC_URL}/releases.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
