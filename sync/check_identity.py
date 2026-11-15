#!/usr/bin/env python3
"""The identity gate: fails (exit 1) when NextBrain's identity is still in the Alfaheem tree.

  1. text: NextBrain / نكست برين / nextbrain.site / com.doubley.nextbrain / nextbrain-2y / "مركز الفهيم" outside
     the allow-list (sync/check_allow.txt: `path-regex<TAB>line-regex<TAB>reason`);
  2. NextBrain's certificate pin and App Links fingerprint (they must never ship), and any Firebase id of NextBrain's
     nextbrain-2y or the old elfaheem project (A-006); the kept Firebase files must name FIREBASE_PROJECT_ID;
  3. images: every tracked image outside test/ and docs/ must be in sync/keep_paths.txt or sync/brand_assets.txt,
     and none of those may still be byte-identical to NextBrain's file at the same path (remote `nextbrain`);
  4. Alfaheem's hooks in shared files (sync/hooks.py, A-007) are all in place, and the landing has no fixed upstream
     colour left (every one is a variable the live theme sets).

Usage: py -3.12 sync/check_identity.py [--ref nextbrain/production] [--verbose]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hooks import landing_leftovers, missing_hooks  # noqa: E402  (A-007)

ROOT = Path(__file__).resolve().parent.parent
VERBOSE = '--verbose' in sys.argv
REF = sys.argv[sys.argv.index('--ref') + 1] if '--ref' in sys.argv else 'nextbrain/production'

PATTERN = re.compile(r'NextBrain|نكست برين|(?i:nextbrain\.site)|com\.doubley\.nextbrain|nextbrain-2y|nextbrain\.2y@|مركز الفهيم')
FORBIDDEN = {
    '5sI/tocMhHnqTPDXhhj4nfWavN+crxuYvDX13koLqDM=': "NextBrain's SPKI pin (nextbrain.site)",
    '93d682e09f1a3f195d50f3ed70e80c4c45206e527f332d7bd36ea03045141402': "NextBrain's legacy certificate pin",
    '74:2C:D5:76:FF:D6:47:DC:57:A1:2D:6A:5F:EC:65:9F:43:2E:4F:08:97:EF:7B:C1:36:31:25:C5:04:11:48:A2':
        "NextBrain's Android signing fingerprint",
}
# Firebase ids that must never ship (A-006): NextBrain's nextbrain-2y (project number 647242717565) and the old
# elfaheem project (520907928286), plus NextBrain's web-push key. Matched outside test/ and docs/ (except docs/guides).
FIREBASE_FORBIDDEN = [
    (re.compile(r'\b(647242717565|520907928286)\b'), "a Firebase id of nextbrain-2y / the old elfaheem project"),
    (re.compile(r'elfaheem\.(firebaseapp\.com|firebasestorage\.app|appspot\.com|firebaseio\.com)'),
     'the old elfaheem Firebase project'),
    (re.compile(r"""(project_?[Ii][Dd]|"default")["']?\s*:\s*["']elfaheem["']|<string>elfaheem</string>"""),
     'the old elfaheem Firebase project'),
    (re.compile(r'BMbmlTUe7ISZTKD-qlNpxHGOZiS4TQ4_OAUi4_pAIjtHB2iQCIICTh0j6vVdZylU3mTbgYPMKdElK55jACSqAR0'),
     "NextBrain's web-push (VAPID) key"),
]
# The kept Firebase files (sync/keep_paths.txt) must belong to Alfaheem's project.
FIREBASE_FILES = ['.firebaserc', 'android/app/google-services.json', 'ios/Runner/GoogleService-Info.plist',
                  'macos/Runner/GoogleService-Info.plist', 'lib/firebase_options.dart', 'web/firebase-messaging-sw.js',
                  'firebase.json']
IMAGE = re.compile(r'\.(png|jpe?g|webp|ico|gif|svg)$', re.I)
SKIP = re.compile(r'^(sync/|landing/node_modules/|build/)')


def git(*args: str) -> str:
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, check=True).stdout.decode('utf-8', 'replace')


def files() -> list[str]:
    out = git('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    return sorted({f for f in out.split('\0') if f and not SKIP.search(f) and (ROOT / f).is_file()})


def allow_rules() -> list[tuple[re.Pattern, re.Pattern, str]]:
    rules = []
    for line in (ROOT / 'sync/check_allow.txt').read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) < 3:
            raise SystemExit(f'check_allow.txt: need path-regex<TAB>line-regex<TAB>reason: {line!r}')
        rules.append((re.compile(parts[0]), re.compile(parts[1]), parts[2]))
    return rules


def listed(name: str) -> set[str]:
    out = set()
    for line in (ROOT / 'sync' / name).read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            out.add(line)
    return out


def identity_env() -> dict[str, str]:
    out = {}
    for line in (ROOT / 'sync/identity.env').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out


def firebase_files(bad: list[str]) -> None:
    env = identity_env()
    project = env.get('FIREBASE_PROJECT_ID', '')
    if not project:
        bad.append('sync/identity.env: FIREBASE_PROJECT_ID is missing')
        return
    for rel in FIREBASE_FILES:
        p = ROOT / rel
        if not p.is_file():
            bad.append(f'{rel}: missing (a Firebase file of {project})')
        elif project not in p.read_text(encoding='utf-8'):
            bad.append(f'{rel}: does not name the Firebase project {project}')
    vapid = env.get('FIREBASE_WEB_VAPID_KEY', '')
    svc = (ROOT / 'lib/features/messaging/notification/notification_service.dart').read_text(encoding='utf-8')
    if not re.search(r"static const webPushVapidKey =\s*'" + re.escape(vapid) + "'", svc):
        bad.append('notification_service.dart: webPushVapidKey is not FIREBASE_WEB_VAPID_KEY (run sync/apply_identity.py)')
    elif not vapid and 'webPushVapidKey.isEmpty' not in svc:
        bad.append('notification_service.dart: no guard for an empty VAPID key (run sync/apply_identity.py)')


def _read_lf(rel: str) -> str | None:
    p = ROOT / rel
    return p.read_bytes().decode('utf-8').replace(chr(13) + chr(10), chr(10)) if p.exists() else None


def main() -> int:
    rules = allow_rules()
    used = [0] * len(rules)
    bad: list[str] = []
    allowed = 0
    all_files = files()
    for rel in all_files:
        if IMAGE.search(rel) and not rel.endswith('.svg'):
            continue
        try:
            text = (ROOT / rel).read_bytes().decode('utf-8')
        except UnicodeDecodeError:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            for needle, why in FORBIDDEN.items():
                if needle in line and not re.match(r'^(test/|docs/(?!guides/))', rel):  # test data, history
                    bad.append(f'{rel}:{n}: {why}')
            for rx, why in FIREBASE_FORBIDDEN:
                if rx.search(line) and not re.match(r'^(test/|docs/(?!guides/))', rel):
                    bad.append(f'{rel}:{n}: {why}')
            if not PATTERN.search(line):
                continue
            hit = next((i for i, (p, l, _) in enumerate(rules) if p.search(rel) and l.search(line)), None)
            if hit is None:
                bad.append(f'{rel}:{n}: {line.strip()[:160]}')
            else:
                used[hit] += 1
                allowed += 1

    firebase_files(bad)
    bad.extend(missing_hooks(_read_lf))
    bad.extend(landing_leftovers(_read_lf, all_files))
    keep, brand = listed('keep_paths.txt'), listed('brand_assets.txt')
    images = [f for f in all_files if IMAGE.search(f) and not re.match(r'^(test|docs)/', f)]
    try:
        theirs = dict(line.split('\t', 1)[::-1] for line in git('ls-tree', '-r', REF).splitlines() if '\t' in line)
        theirs = {path: meta.split()[2] for path, meta in theirs.items()}
    except subprocess.CalledProcessError:
        theirs = {}
        print(f'(no {REF}: the byte-identical image check is skipped)')
    for f in images:
        if f not in keep and f not in brand:
            bad.append(f'{f}: an image in neither sync/keep_paths.txt nor sync/brand_assets.txt (a new NextBrain brand '
                       f'image? generate it from the Alfaheem logo, then list it)')
        elif f in theirs and git('hash-object', f).strip() == theirs[f]:
            bad.append(f"{f}: still NextBrain's image (byte-identical to {REF})")

    if VERBOSE:
        for (p, l, why), n in zip(rules, used):
            print(f'{n:5d}  {p.pattern}  {l.pattern}  ({why})')
    for (p, l, why), n in zip(rules, used):
        if n == 0:
            print(f'note: allow rule no longer needed: {p.pattern}\t{l.pattern}')
    for b in bad:
        print('FAIL', b)
    print(f'{len(bad)} problem(s); {allowed} allowed line(s); {len(images)} image(s) checked')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
