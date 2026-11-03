#!/usr/bin/env python3
"""`zip` for the build runner on Windows (D-146): Git Bash has none, and the codemagic.yaml workflows call
`zip -qr <archive.zip> <paths…>` (from inside the folder to pack). Only those flags are supported: -q (quiet) and
-r (recurse); a path that is a folder is packed with its contents, relative to the current folder."""
import os
import sys
import zipfile


def main(argv):
    flags, rest = set(), []
    for a in argv:
        if a.startswith("-") and len(a) > 1 and not rest:
            flags.update(a[1:])
        else:
            rest.append(a)
    unknown = flags - {"q", "r"}
    if unknown or len(rest) < 2:
        print(f"zip (runner shim): usage zip -qr <archive.zip> <paths…> (unsupported: {''.join(sorted(unknown))})",
              file=sys.stderr)
        return 2
    dest, paths = rest[0], rest[1:]
    if not dest.lower().endswith(".zip"):
        dest += ".zip"
    dest_abs = os.path.abspath(dest)
    n = 0
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in paths:
            if os.path.isdir(p):
                if "r" not in flags:
                    continue
                for root, dirs, files in os.walk(p):
                    dirs.sort()
                    for f in sorted(files):
                        full = os.path.join(root, f)
                        if os.path.abspath(full) == dest_abs:
                            continue
                        zf.write(full, os.path.normpath(os.path.relpath(full)).replace(os.sep, "/"))
                        n += 1
            elif os.path.isfile(p):
                zf.write(p, os.path.normpath(os.path.relpath(p)).replace(os.sep, "/"))
                n += 1
            else:
                print(f"zip (runner shim): {p} not found", file=sys.stderr)
                return 12
    if "q" not in flags:
        print(f"  {n} files → {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
