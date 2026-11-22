#!/usr/bin/env python3
"""The releases manifest tool (D-137): writes <root>/releases.json, which the web banner and the native apps read.

Standard library only: it runs on the server (python3), where the files are, so the size and SHA-256 written into the
manifest are those of the files nginx actually serves. publish_release.py uploads it next to the files and calls it;
the Linux build script on the server calls it too.

  release_manifest.py init  --root /root/elfaheem/releases
      creates releases.json if missing: iPhone / iPad, Windows and Mac offer the web app ("pwa": true)
  release_manifest.py set   --root R --base-url https://alfheemacademy.com/releases --platform android
                            --version 1.0.0 --build 1 [--min-build 1] [--min-os "Android 7.0"]
                            [--notes-en ...] [--notes-ar ...] [--primary arm64-v8a | pwa] [--pwa | --no-pwa]
                            --file ARCH:KIND:REL_PATH [--file ...] [--expect-sha REL_PATH=HEX ...]
                            [--latest REL_LINK=REL_TARGET ...]
      replaces that platform's entry (other platforms untouched); --latest moves an "Alfaheem-latest…" symlink
  release_manifest.py show  --root R

File kinds (KINDS below, mirrored by kInstallerKinds in lib/core/get_app/releases_manifest.dart): android apk + aab,
windows exe (the Inno Setup installer Alfaheem-<version>-windows-x64-setup.exe) + msix + zip, macos dmg + zip, linux
AppImage + deb + tar.gz. A kind outside that list, or on the wrong platform, stops the write. An `aab` (the Play
upload) is recorded with "listed": false: the site and the apps never offer it for download, and it can be neither
--primary nor a --latest target.

Every write: the previous manifest is copied to releases.json.bak-<UTC time> (the newest 10 are kept), the new one is
written to a temporary file and renamed over the old (a reader never sees half a file). A file that is missing, is
outside the root, or whose SHA-256 differs from --expect-sha stops everything before the manifest changes.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

PLATFORMS = ("android", "ios", "windows", "macos", "linux")
# kind -> platforms it may be published for; installer order per platform lives in the Dart reader
KINDS = {
    "apk": ("android",),
    "aab": ("android",),
    "exe": ("windows",),
    "msix": ("windows",),
    "zip": ("windows", "macos"),
    "dmg": ("macos",),
    "AppImage": ("linux",),
    "deb": ("linux",),
    "tar.gz": ("linux",),
}
UNLISTED_KINDS = ("aab",)  # published next to the others, never shown for download
MANIFEST = "releases.json"
KEEP_BACKUPS = 10


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _load(root: Path) -> dict:
    p = root / MANIFEST
    if not p.exists():
        return {"schema": 1, "updated_at": _now(), "platforms": {}}
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("platforms"), dict):
        raise SystemExit(f"{p} is not a releases manifest")
    return data


def _save(root: Path, data: dict) -> None:
    p = root / MANIFEST
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    if p.exists():
        shutil.copy2(p, root / f"{MANIFEST}.bak-{stamp}")
        backups = sorted(root.glob(f"{MANIFEST}.bak-*"))
        for old in backups[:-KEEP_BACKUPS]:
            old.unlink()
    data["schema"] = 1
    data["updated_at"] = _now()
    tmp = root / f".{MANIFEST}.tmp"
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o644)
    os.replace(tmp, p)


def _inside(root: Path, rel: str) -> Path:
    p = (root / rel).resolve()
    if root.resolve() not in p.parents:
        raise SystemExit(f"{rel}: outside {root}")
    return p


def _sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_init(a) -> None:
    root = Path(a.root)
    root.mkdir(parents=True, exist_ok=True)
    data = _load(root)
    changed = False
    for key in ("ios", "windows", "macos"):
        if key not in data["platforms"]:
            data["platforms"][key] = {"pwa": True}
            changed = True
    if changed or not (root / MANIFEST).exists():
        _save(root, data)
        print(f"initialised {root / MANIFEST}")
    else:
        print(f"{root / MANIFEST} already initialised")


def cmd_set(a) -> None:
    root = Path(a.root)
    if a.platform not in PLATFORMS:
        raise SystemExit(f"unknown platform {a.platform}")
    expect = {}
    for e in a.expect_sha or []:
        rel, _, hexd = e.partition("=")
        expect[rel] = hexd.strip().lower()
    files = []
    for spec in a.file or []:
        parts = spec.split(":", 2)
        if len(parts) != 3:
            raise SystemExit(f"--file wants ARCH:KIND:REL_PATH, got {spec}")
        arch, kind, rel = parts
        if kind not in KINDS:
            raise SystemExit(f"{spec}: unknown kind {kind} (one of {', '.join(KINDS)})")
        if a.platform not in KINDS[kind]:
            raise SystemExit(f"{spec}: a {kind} is not a {a.platform} file")
        p = _inside(root, rel)
        if not p.is_file():
            raise SystemExit(f"{rel}: no such file under {root}")
        sha = _sha256(p)
        if rel in expect and expect[rel] != sha:
            raise SystemExit(f"{rel}: SHA-256 here {sha} differs from the built file's {expect[rel]} (damaged upload?)")
        os.chmod(p, 0o644)
        item = {
            "arch": arch,
            "kind": kind,
            "url": f"{a.base_url.rstrip('/')}/{rel}",
            "size": p.stat().st_size,
            "sha256": sha,
        }
        if kind in UNLISTED_KINDS:
            item["listed"] = False
        files.append(item)
    listed = [f for f in files if f.get("listed", True)]
    if a.primary and a.primary != "pwa" and files and not any(f["arch"] == a.primary for f in listed):
        raise SystemExit(f"--primary {a.primary}: no downloadable file has that arch")
    links = []
    for spec in a.latest or []:
        link, _, target = spec.partition("=")
        lp, tp = _inside(root, link), _inside(root, target)
        if not tp.is_file():
            raise SystemExit(f"--latest target {target} is missing")
        if any(target.endswith("." + k) for k in UNLISTED_KINDS):
            raise SystemExit(f"--latest {target}: an unlisted file never gets a public 'latest' link")
        links.append((lp, tp))
    if not listed and not a.pwa:
        raise SystemExit("nothing to publish: give --file and/or --pwa")
    data = _load(root)
    entry = {
        "version": a.version,
        "build": int(a.build),
        "min_build": int(a.min_build or 0),
        "released_at": dt.date.today().isoformat(),
        "min_os": a.min_os or "",
        "notes": {"ar": a.notes_ar or "", "en": a.notes_en or ""},
        "primary": a.primary or "",
        "files": files,
        "pwa": bool(a.pwa),
    }
    old = data["platforms"].get(a.platform) or {}
    if old.get("build") and int(old["build"]) > entry["build"] and not a.allow_older:
        raise SystemExit(f"{a.platform}: build {entry['build']} is older than the published {old['build']} (--allow-older)")
    data["platforms"][a.platform] = entry
    for lp, tp in links:  # relative symlink, swapped atomically
        tmp = lp.with_name(f".{lp.name}.tmp")
        if tmp.is_symlink() or tmp.exists():
            tmp.unlink()
        os.symlink(os.path.relpath(tp, lp.parent), tmp)
        os.replace(tmp, lp)
    _save(root, data)
    print(json.dumps(entry, ensure_ascii=False, indent=2))


def cmd_show(a) -> None:
    print(json.dumps(_load(Path(a.root)), ensure_ascii=False, indent=2))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_init = sub.add_parser("init")
    p_init.add_argument("--root", required=True)
    p_show = sub.add_parser("show")
    p_show.add_argument("--root", required=True)
    p_set = sub.add_parser("set")
    p_set.add_argument("--root", required=True)
    p_set.add_argument("--base-url", required=True)
    p_set.add_argument("--platform", required=True)
    p_set.add_argument("--version", required=True)
    p_set.add_argument("--build", required=True, type=int)
    p_set.add_argument("--min-build", type=int, default=0)
    p_set.add_argument("--min-os", default="")
    p_set.add_argument("--notes-en", default="")
    p_set.add_argument("--notes-ar", default="")
    p_set.add_argument("--primary", default="")
    p_set.add_argument("--pwa", action=argparse.BooleanOptionalAction, default=False)
    p_set.add_argument("--file", action="append")
    p_set.add_argument("--expect-sha", action="append")
    p_set.add_argument("--latest", action="append")
    p_set.add_argument("--allow-older", action="store_true")
    a = ap.parse_args(argv)
    {"init": cmd_init, "set": cmd_set, "show": cmd_show}[a.cmd](a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
