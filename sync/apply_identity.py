#!/usr/bin/env python3
"""Apply the Alfaheem identity (sync/identity.env) over a tree that was just merged from NextBrain.

Idempotent: running it twice changes nothing. Ordered:
  1. ids: com.doubley.nextbrain -> APP_ID everywhere (channels, App Group, Darwin IPC names, bundle ids, Kotlin
     packages), then the Kotlin folder move;
  2. the domain: nextbrain.site -> DOMAIN (calendar UIDs and the pinned-certificate fixtures excepted);
  3. platform display names (launcher label, desktop binary names, web titles);
  4. user-visible names: "NextBrain" / "نكست برين" -> Alfaheem / الفهيم, Arabic inside Arabic text;
  5. one-off blocks: certificate pins, App Links fingerprints, Firebase web worker + firebase.json (Alfaheem's
     project, read from the kept lib/firebase_options.dart), the iOS Firebase URL schemes and the web-push VAPID key
     (FIREBASE_* in sync/identity.env, A-006), splash and launcher settings, CLAUDE.md note;
  6. the redesign kit palette (A-008): Alfaheem's values from sync/kit_palette_alfaheem.py into
     tool/redesign/kit_palette.json, lib/config/theme/kit_palette_defaults.dart and lib/config/theme/app_theme.dart.

What must NOT change (sync/README.md, plan section 4.2) is never matched: the rules only touch the exact tokens above,
so signing labels (nextbrain/biometric-login/v1, ...), storage keys, the reserved username, nextbrain_offline_exam,
and script file names (nextbrain_runner.py) stay as they are. NextBrain's Firebase ids (nextbrain-2y) are rewired by
the Firebase blocks, never renamed by text.

Usage: py -3.12 sync/apply_identity.py [--check]   (--check: print what would change, exit 1 when anything would)
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hooks import apply_hooks, hook_files  # noqa: E402  (Alfaheem's hooks in shared files, sync/hooks.py)

ROOT = Path(__file__).resolve().parent.parent
CHECK = '--check' in sys.argv
changed: list[str] = []


def env() -> dict[str, str]:
    out = {}
    for line in (ROOT / 'sync/identity.env').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        out[k.strip()] = v.strip()
    return out


E = env()
APP_ID = E['APP_ID']
DOMAIN = E['DOMAIN']
NAME_AR, NAME_EN = E['APP_NAME_AR'], E['APP_NAME_EN']
LAUNCHER = E['LAUNCHER_NAME']
BIN = E['BINARY_NAME']
NB_ID = 'com.doubley.nextbrain'
NB_DOMAIN = 'nextbrain.site'

# Where the generic renames run (git-tracked files only).
SCOPES = [
    'lib', 'test', 'assets/translation.json', 'android', 'ios', 'macos', 'windows', 'linux', 'web', 'landing',
    'scripts', 'tools', 'codemagic.yaml', 'README.md', 'CLAUDE.md', 'docs/guides', 'pubspec.yaml', 'firebase.json',
    '.gitleaks.toml', '.interface-design',
]
# Never touched: real server payloads, the certificate fixtures and their test (the fixture leaf IS nextbrain.site),
# the decision history, generated lock files.
EXCLUDE = re.compile(
    r'^(test/fixtures/|docs/DECISIONS|landing/node_modules/|sync/)'
    r'|^test/auth/cert_pin_test\.dart$|^lib/core/cert_pin\.dart$'
)
TEXT_EXT = {
    '.dart', '.json', '.md', '.yaml', '.yml', '.xml', '.plist', '.entitlements', '.swift', '.kt', '.kts', '.gradle',
    '.pbxproj', '.xcconfig', '.toml', '.xcscheme', '.html', '.js', '.mjs', '.ts', '.astro', '.txt', '.sh', '.py', '.cc', '.h',
    '.cpp', '.rc', '.cmake', '.ps1', '.iss', '.example', '.css', '.webmanifest', '.storyboard', '.pro', '.properties', '',
}
NAMED = {'CMakeLists.txt', 'apple-app-site-association', 'robots.txt', 'Podfile'}

# A block the script wrote itself (CLAUDE.md note): never renamed again.
KEEP_BLOCK = re.compile(r'(<!-- alfaheem:begin -->.*?<!-- alfaheem:end -->)', re.S)
ARABIC = re.compile(r'[؀-ۿ]')
LATIN = re.compile(r'[A-Za-z]')
# A Dart / JS / JSON string literal on one line.
LITERAL = re.compile(r"'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\"")


def tracked_files() -> list[Path]:
    out = subprocess.run(['git', 'ls-files', '-z', '--', *SCOPES], cwd=ROOT, capture_output=True, check=True)
    files = []
    for rel in out.stdout.decode('utf-8').split('\0'):
        if not rel or EXCLUDE.search(rel):
            continue
        p = ROOT / rel
        if p.is_file() and (p.suffix in TEXT_EXT or p.name in NAMED):
            files.append(p)
    return files


def arabic_context(line: str, start: int, end: int) -> bool:
    """Is the brand word at line[start:end] part of Arabic text?"""
    for m in LITERAL.finditer(line):
        if m.start() < start and end <= m.end():
            return bool(ARABIC.search(m.group(0)))
    before = line[:start].rstrip()
    after = line[end:].lstrip()
    prev = before.split()[-1] if before.split() else ''
    nxt = after.split()[0] if after.split() else ''
    prev_ar, next_ar = bool(ARABIC.search(prev)), bool(ARABIC.search(nxt))
    if prev_ar and not LATIN.search(nxt):
        return True
    if next_ar and not LATIN.search(prev):
        return True
    return prev_ar and next_ar


def arabic_fixups(text: str) -> str:
    """'بـ الفهيم' -> 'بالفهيم', 'لـ الفهيم' -> 'للفهيم' (NextBrain needed the tatweel, a name with ال does not)."""
    if NAME_AR.startswith('ال'):
        text = text.replace('بـ ' + NAME_AR, 'بال' + NAME_AR[2:]).replace('لـ ' + NAME_AR, 'لل' + NAME_AR[2:])
    if NAME_EN[:1].upper() in 'AEIOU':  # 'a NextBrain code' -> 'an Alfaheem code'
        text = re.sub(r'\b([Aa]) ("?)' + re.escape(NAME_EN) + r'\b', r'\1n \2' + NAME_EN, text)
    return text


def rename_names(text: str) -> str:
    text = text.replace('نكست برين', NAME_AR)
    # The Drive folder keeps one (English) name in both languages.
    text = text.replace('NextBrain recordings', f'{NAME_EN} recordings')
    if 'NextBrain' not in text:
        return arabic_fixups(text)
    lines = text.split('\n')
    for i, line in enumerate(lines):
        if 'NextBrain' not in line:
            continue
        out, pos = [], 0
        for m in re.finditer('NextBrain', line):
            out.append(line[pos:m.start()])
            out.append(NAME_AR if arabic_context(line, m.start(), m.end()) else NAME_EN)
            pos = m.end()
        out.append(line[pos:])
        lines[i] = ''.join(out)
    return arabic_fixups('\n'.join(lines))


def rename_domain(text: str) -> str:
    if NB_DOMAIN not in text.lower():
        return text
    pattern = re.compile(re.escape(NB_DOMAIN), re.I)

    def repl(m: re.Match) -> str:  # keep the case of each label ('NEXTBRAIN.site' tests case-insensitive hosts)
        old_labels, new_labels = m.group(0).split('.'), DOMAIN.split('.')
        if len(old_labels) == len(new_labels):
            return '.'.join(n.upper() if o.isupper() else n for o, n in zip(old_labels, new_labels))
        return DOMAIN

    lines = text.split('\n')
    for i, line in enumerate(lines):
        # Calendar UIDs keep the old host: a changed UID duplicates every imported event (plan 4.2).
        if 'UID:' in line or 'UID=' in line:
            continue
        lines[i] = pattern.sub(repl, line)
    return '\n'.join(lines)


def platform_names(rel: str, text: str) -> str:
    if rel == 'android/app/src/main/AndroidManifest.xml':
        text = re.sub(r'android:label="NextBrain"', f'android:label="{LAUNCHER}"', text)
    if rel == 'ios/Runner/Info.plist':
        text = re.sub(r'(<key>CFBundle(?:Display)?Name</key>\s*<string>)NextBrain(</string>)', rf'\g<1>{LAUNCHER}\g<2>',
                      text)
    if rel == 'ios/Runner.xcodeproj/project.pbxproj':
        text = text.replace('INFOPLIST_KEY_CFBundleDisplayName = NextBrain;',
                            f'INFOPLIST_KEY_CFBundleDisplayName = "{LAUNCHER}";')
    if rel in ('windows/CMakeLists.txt', 'linux/CMakeLists.txt'):
        text = text.replace('project(nextbrain ', f'project({BIN} ').replace('BINARY_NAME "nextbrain"',
                                                                           f'BINARY_NAME "{BIN}"')
    if rel == 'windows/runner/Runner.rc':
        text = text.replace('"InternalName", "nextbrain"', f'"InternalName", "{BIN}"')
        text = text.replace('"nextbrain.exe"', f'"{BIN}.exe"')
    if rel in ('web/index.html', 'web/index2.html'):
        text = re.sub(r'<title>NextBrain</title>', f'<title>{LAUNCHER}</title>', text)
        text = re.sub(r'(name="(?:application-name|apple-mobile-web-app-title)" content=")NextBrain(")',
                      rf'\g<1>{LAUNCHER}\g<2>', text)
    if rel == 'web/manifest.json':
        text = re.sub(r'("(?:short_)?name":\s*")NextBrain(")', rf'\g<1>{LAUNCHER}\g<2>', text)
    if rel in ('web/index.html', 'web/index2.html', 'web/manifest.json', 'web/offline.html'):
        # NextBrain's splash cream / emerald -> Alfaheem's splash colours (they must match the native splash).
        text = re.sub('#FBF7EC', E['SPLASH_COLOR'], text, flags=re.I)
        text = re.sub('#0F7B5F', E['SPLASH_COLOR_DARK'], text, flags=re.I)
    if rel in ('landing/package.json', 'landing/package-lock.json'):
        text = text.replace('"name": "nextbrain-landing"', f'"name": "{BIN}-landing"')
    return text


def write(p: Path, new: str, old: str) -> None:
    if new == old:
        return
    changed.append(str(p.relative_to(ROOT)).replace('\\', '/'))
    if not CHECK:
        p.write_bytes(new.encode('utf-8'))


def generic_pass() -> None:
    for p in tracked_files():
        raw = p.read_bytes()
        try:
            old = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        rel = str(p.relative_to(ROOT)).replace('\\', '/')
        parts = KEEP_BLOCK.split(old)  # odd items are the Alfaheem-owned blocks: left as they are
        for k in range(0, len(parts), 2):
            parts[k] = transform(rel, parts[k])
        write(p, ''.join(parts), old)


SHORT_ID = APP_ID.split('.')[-1]
SERVER_DIR = E.get('SERVER_DIR', '')
# Exact phrases first, where a word-by-word rename would read wrong.
PHRASES = [
    ('نكست برين (NextBrain)', f'{NAME_AR} ({NAME_EN})'),
    ('NextBrain (نكست برين)', f'{NAME_EN} ({NAME_AR})'),
    # "a school, university or centre uses NextBrain": never "مركز الفهيم" (owner rule).
    ('مركز نكست برين', f'مركز تعليمي منصة {NAME_AR}'),
    ('مركز NextBrain', f'أكاديمية {NAME_AR}'),
    ('NextBrain Center', f'{NAME_EN} Academy'),
    # a NextBrain test names a long organization "مركز الفهيم ..." (Alfaheem's old picture text)
    ('مركز الفهيم التعليمي المتكامل', f'أكاديمية {NAME_AR} التعليمية المتكاملة'),
]
LINUX_PACKAGING = ('scripts/release/build_linux.sh', 'scripts/release/package_linux.sh')
# The Windows installer packs the binary windows/CMakeLists.txt names (the .iss file name itself stays).
WINDOWS_PACKAGING = ('scripts/release/package_windows.ps1', 'windows/installer/nextbrain.iss')


def transform(rel: str, text: str) -> str:
    for a, b in PHRASES:
        text = text.replace(a, b)
    if E.get('CONTACT_EMAIL'):  # NextBrain's contact address -> Alfaheem's
        text = text.replace('nextbrain.2y@gmail.com', E['CONTACT_EMAIL'])
    text = text.replace(NB_ID, APP_ID)
    text = text.replace('com/doubley/nextbrain', '/'.join(APP_ID.split('.')))
    text = text.replace('…nextbrain.', f'…{SHORT_ID}.')  # Darwin names in comments ("…nextbrain.frame")
    # The release signing key: an Alfaheem build must never default to NextBrain's keystore.
    text = text.replace('nextbrain-keys', f'{BIN}-keys').replace('nextbrain-release.jks', f'{BIN}-release.jks')
    if rel.startswith('scripts/') and SERVER_DIR:
        text = text.replace('/root/nextbrain', SERVER_DIR)
    if rel in LINUX_PACKAGING:  # the Linux binary / package / icon follow BINARY_NAME (linux/CMakeLists.txt)
        text = re.sub(r'(?<![A-Za-z_])nextbrain(?![A-Za-z_])', BIN, text)
    if rel in WINDOWS_PACKAGING:
        text = text.replace('nextbrain.exe', f'{BIN}.exe')
    text = rename_domain(text)
    text = platform_names(rel, text)
    return rename_names(text)


def move_kotlin() -> None:
    src = ROOT / 'android/app/src/main/kotlin' / Path(*NB_ID.split('.'))
    dst = ROOT / 'android/app/src/main/kotlin' / Path(*APP_ID.split('.'))
    if not src.exists():
        return
    changed.append(f'move {src.relative_to(ROOT)} -> {dst.relative_to(ROOT)}')
    if CHECK:
        return
    dst.mkdir(parents=True, exist_ok=True)
    for f in sorted(src.rglob('*')):
        if f.is_file():
            target = dst / f.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['git', 'mv', '-f', str(f), str(target)], cwd=ROOT, check=True)
    for d in sorted((x for x in src.parent.rglob('*') if x.is_dir()), reverse=True):
        if not any(d.iterdir()):
            d.rmdir()
    if src.exists() and not any(src.iterdir()):
        src.rmdir()


CR, LF = chr(13), chr(10)
CRLF = CR + LF


def edit(rel: str, fn) -> None:
    p = ROOT / rel
    if not p.exists():
        print(f'  ! missing {rel}')
        return
    old = p.read_bytes().decode('utf-8')
    crlf = CRLF in old
    new = fn(old.replace(CRLF, LF))
    write(p, new.replace(LF, CRLF) if crlf else new, old)


def dart_set(values: str) -> str:
    items = [v.strip() for v in values.split(',') if v.strip()]
    return ''.join(f"\n    '{v}'," for v in items) + ('\n  ' if items else '')


def cert_pins(text: str) -> str:
    text = re.sub(r'(static const leafSpkiSha256 = <String>\{)[^}]*(\};)',
                  lambda m: m.group(1) + dart_set(E.get('CERT_PIN_SPKI_SHA256', '')) + m.group(2), text)
    text = re.sub(r'(static const legacyLeafCertSha256 = <String>\{)[^}]*(\};)',
                  lambda m: m.group(1) + dart_set(E.get('CERT_PIN_LEGACY_SHA256', '')) + m.group(2), text)
    note = ('  // ALFAHEEM (sync/identity.env, A-002): the pin sets come from CERT_PIN_SPKI_SHA256 / CERT_PIN_LEGACY_SHA256.\n'
            '  // Both are empty until the alfheemacademy.com certificate exists, so only the Let\'s Encrypt backup rule\n'
            '  // accepts the API host. TODO(owner): add the server key\'s SPKI SHA-256 to identity.env and re-run apply.\n')
    if 'ALFAHEEM (sync/identity.env, A-002)' not in text:
        text = text.replace('  /// SPKI SHA-256 (base64) of the server\'s public key;', note + '  /// SPKI SHA-256 (base64) of the server\'s public key;', 1)
    return text


NB_PINS_TEST = """// ALFAHEEM (A-002): NextBrain's pins, as test data only. The app ships Alfaheem's (sync/identity.env); these
// fixtures are nextbrain.site's real chain, so the mechanism is still tested against them.
const _nbLeafPins = {'5sI/tocMhHnqTPDXhhj4nfWavN+crxuYvDX13koLqDM='};
const _nbLegacyPins = {'93d682e09f1a3f195d50f3ed70e80c4c45206e527f332d7bd36ea03045141402'};

"""


def cert_pin_test(text: str) -> str:
    """The pin test checks the mechanism with nextbrain.site's real certificates: hand it NextBrain's pins
    explicitly, and check instead that they are NOT in the shipped sets."""
    if 'ALFAHEEM (A-002)' in text:
        return text
    text = text.replace('void main() {\n', NB_PINS_TEST + 'void main() {\n', 1)
    text = text.replace('expect(CertPin.leafSpkiSha256, contains(_spkiPin(leaf)));',
                        "expect(CertPin.leafSpkiSha256, isNot(contains(_spkiPin(leaf))), reason: 'A-002');")
    text = text.replace('expect(CertPin.legacyLeafCertSha256, contains(crypto.sha256.convert(leaf).toString()));',
                        "expect(_nbLegacyPins, contains(crypto.sha256.convert(leaf).toString()));\n"
                        "      expect(CertPin.legacyLeafCertSha256, isNot(contains(crypto.sha256.convert(leaf).toString())));")
    text = text.replace('leafPins: noPins ? const {} : null,', 'leafPins: noPins ? const {} : _nbLeafPins,')
    text = text.replace('legacyPins: noPins ? const {} : null);', 'legacyPins: noPins ? const {} : _nbLegacyPins);')
    text = text.replace("apiHost: 'nextbrain.site', now: today, leafPins: const {}),\n          PinVerdict.legacyCert);",
                        "apiHost: 'nextbrain.site', now: today, leafPins: const {}, legacyPins: _nbLegacyPins),\n"
                        "          PinVerdict.legacyCert);")
    return text


def assetlinks(text: str) -> str:
    data = json.loads(text)
    fps = [v.strip() for v in E.get('ANDROID_SHA256_FINGERPRINTS', '').split(',') if v.strip()]
    for entry in data:
        entry['target']['sha256_cert_fingerprints'] = fps
    return json.dumps(data, indent=2, ensure_ascii=False) + '\n'


def firebase_web_options() -> dict[str, str]:
    """The web block of the KEPT Alfaheem lib/firebase_options.dart (the Firebase step rewrites that file)."""
    src = (ROOT / 'lib/firebase_options.dart').read_text(encoding='utf-8')
    m = re.search(r'static const FirebaseOptions web = FirebaseOptions\((.*?)\);', src, re.S)
    return dict(re.findall(r"(\w+): '([^']*)'", m.group(1))) if m else {}


def firebase_sw(text: str) -> str:
    o = firebase_web_options()
    if not o:
        return text
    keys = ['apiKey', 'appId', 'messagingSenderId', 'projectId', 'authDomain', 'storageBucket', 'measurementId']
    body = ''.join(f'  {k}: "{o[k]}",\n' for k in keys if k in o)
    text = re.sub(r'firebase\.initializeApp\(\{\n.*?\n\}\);', lambda _: 'firebase.initializeApp({\n' + body + '});', text,
                  count=1, flags=re.S)
    text = re.sub(r'\(DefaultFirebaseOptions\.web, project [\w-]+, [AD]-\d+\)',
                  f"(DefaultFirebaseOptions.web, project {o.get('projectId', '')}, A-006)", text, count=1)
    return text


def firebase_json(text: str) -> str:
    src = (ROOT / 'lib/firebase_options.dart').read_text(encoding='utf-8')
    ids = dict(re.findall(r"static const FirebaseOptions (\w+) = FirebaseOptions\(.*?appId: '([^']*)'", src, re.S))
    project = (re.findall(r"projectId: '([^']*)'", src) or [''])[0]
    mac = ROOT / 'macos/Runner/GoogleService-Info.plist'
    mac_id = ''
    if mac.exists():
        mm = re.search(r'<key>GOOGLE_APP_ID</key>\s*<string>([^<]*)</string>', mac.read_text(encoding='utf-8'))
        mac_id = mm.group(1) if mm else ''
    data = json.loads(text)
    plat = data.get('flutter', {}).get('platforms', {})
    for name in ('android', 'ios', 'macos'):
        if name in plat:
            app = ids.get(name) or (mac_id if name == 'macos' else '')
            if app:
                plat[name]['default']['projectId'] = project
                plat[name]['default']['appId'] = app
            elif name == 'macos':
                plat.pop('macos')
    dart = plat.get('dart', {}).get('lib/firebase_options.dart')
    if dart:
        dart['projectId'] = project
        dart['configurations'] = {k: v for k, v in {
            'android': ids.get('android'), 'ios': ids.get('ios'), 'macos': ids.get('macos') or None,
            'web': ids.get('web')}.items() if v}
    return json.dumps(data, indent=2, ensure_ascii=False) + '\n'


def ios_url_schemes(text: str) -> str:
    """The Firebase URL schemes of ios/Runner/Info.plist: Firebase Auth returns to the encoded iOS app id, Google
    sign-in to the REVERSED_CLIENT_ID (only when the iOS app has an OAuth client)."""
    app_id = E.get('FIREBASE_IOS_APP_ID', '')
    if not app_id:
        return text
    reversed_id = E.get('FIREBASE_IOS_REVERSED_CLIENT_ID', '')
    m = re.search(r'(<key>CFBundleURLSchemes</key>\n(\s*)<array>\n)((?:(?!</array>).)*?'
                  r'<string>app-1-[^<]*</string>(?:(?!</array>).)*?)(\n\s*</array>)', text, re.S)
    if not m:
        return text
    pad = m.group(2) + '\t'
    body = (f'{pad}<!-- Firebase Auth returns here after "Continue with Google" (the encoded iOS app id of '
            f'{E.get("FIREBASE_PROJECT_ID", "")}, A-006) -->\n'
            f'{pad}<string>app-{app_id.replace(":", "-")}</string>')
    if reversed_id:
        body += f'\n{pad}<string>{reversed_id}</string>'
    return text[:m.start(3)] + body + text[m.end(3):]


VAPID_GUARD = 'webPushVapidKey.isEmpty'


def vapid_key(text: str) -> str:
    """The web-push key comes from FIREBASE_WEB_VAPID_KEY; with none, web push is skipped instead of asking Firebase
    for a token with NextBrain's key (A-006)."""
    key = E.get('FIREBASE_WEB_VAPID_KEY', '')
    project = E.get('FIREBASE_PROJECT_ID', '')
    text = re.sub(r"(static const webPushVapidKey =\s*)'[^']*'", lambda m: m.group(1) + f"'{key}'", text, count=1)
    text = re.sub(r"(/// The Web Push \(VAPID\) public key of the web app's Firebase project )\(`[^`]*`, [AD]-\d+\)",
                  lambda m: m.group(1) + f'(`{project}`, A-006)', text, count=1)
    if VAPID_GUARD in text:
        return text
    reg = '      if (kIsWeb) {\n        token = await _fcm.getToken(vapidKey: webPushVapidKey);\n'
    text = text.replace(reg, (
        '      // ALFAHEEM (sync/identity.env FIREBASE_WEB_VAPID_KEY, A-006): no Web Push certificate yet, so no web token.\n'
        '      if (kIsWeb && webPushVapidKey.isEmpty) {\n'
        "        _fcmLog('[FCM] web push skipped: no VAPID key configured');\n"
        '        return;\n'
        '      }\n' + reg), 1)
    unreg = ('  Future<void> unregisterFromBackend(ApiClient api) async {\n'
             '    final token = await _fcm.getToken();\n')
    text = text.replace(unreg, (
        '  Future<void> unregisterFromBackend(ApiClient api) async {\n'
        '    if (kIsWeb && webPushVapidKey.isEmpty) return; // never registered (A-006)\n'
        '    final token = await _fcm.getToken();\n'), 1)
    return text


def pubspec(text: str) -> str:
    text = re.sub(r'(adaptive_icon_background: )"#[0-9A-Fa-f]{6}"', rf'\1"{E["ADAPTIVE_ICON_BACKGROUND"]}"', text)
    block = re.search(r'^flutter_native_splash:\n(.*?)(?=\n\S)', text, re.S | re.M)
    if block:
        b = block.group(0)
        nb = re.sub(r'(\n  color: )"#[0-9A-Fa-f]{6}"', rf'\1"{E["SPLASH_COLOR"]}"', b)
        nb = re.sub(r'(\n  color_dark: )"#[0-9A-Fa-f]{6}"', rf'\1"{E["SPLASH_COLOR_DARK"]}"', nb)
        nb = re.sub(r'(\n    (?:icon_background_color|icon_background_color_dark): )"#[0-9A-Fa-f]{6}"',
                    r'\1"#FFFFFF"', nb)
        nb = re.sub(r'(\n    color: )"#[0-9A-Fa-f]{6}"', rf'\1"{E["SPLASH_COLOR"]}"', nb)
        nb = re.sub(r'(\n    color_dark: )"#[0-9A-Fa-f]{6}"', rf'\1"{E["SPLASH_COLOR_DARK"]}"', nb)
        nb = re.sub(r'(\n  image(?:_dark)?: )assets/images/splash\.png', r'\1assets/images/splash_alfaheem.png', nb)
        nb = nb.replace('# brand cream  (light)', '# Alfaheem light').replace('# brand emerald (dark)', '# Alfaheem navy (dark)')
        text = text.replace(b, nb)
    return text


def hexcolor(v: str) -> str:
    return '0xFF' + v.lstrip('#').upper()


def boot_splash(text: str) -> str:
    text = text.replace("static const asset = 'assets/images/splash.png';",
                        "static const asset = 'assets/images/splash_alfaheem.png';")
    text = re.sub(r'const splashCream = Color\(0x[0-9A-Fa-f]{8}\);', f'const splashCream = Color({hexcolor(E["SPLASH_COLOR"])});', text)
    text = re.sub(r'const splashEmerald = Color\(0x[0-9A-Fa-f]{8}\);', f'const splashEmerald = Color({hexcolor(E["SPLASH_COLOR_DARK"])});', text)
    # The name is drawn as text under the mark (A-003): a fresh install has no cached identity yet, so fall back to it.
    old = 'final wordmark = s.appName.isNotEmpty ? s.appName : AppIdentity.instance.name;'
    new = (f"final wordmark = s.appName.isNotEmpty ? s.appName : (AppIdentity.instance.name.isNotEmpty "
           f"? AppIdentity.instance.name : (en ? '{NAME_EN}' : '{NAME_AR}'));")
    return text.replace(old, new)


CLAUDE_NOTE = f"""<!-- alfaheem:begin -->
> **Alfaheem fork.** This repository is Alfaheem ({NAME_AR}, by DoubleY), built from NextBrain by `sync/`
> (`sync/README.md`): application id `{APP_ID}`, domain `{DOMAIN}`. Alfaheem-only decisions are in
> `docs/DECISIONS_ALFAHEEM.md` (A-nnn), Firebase project `{E.get('FIREBASE_PROJECT_ID', '')}` (A-006). Text below that
> still names NextBrain-only values (the `D-nnn` history) describes the upstream; Alfaheem's values are in
> `sync/identity.env`.
<!-- alfaheem:end -->

"""


def claude_firebase(text: str) -> str:
    project = E.get('FIREBASE_PROJECT_ID', '')
    if not project:
        return text
    text = re.sub(r'Firebase project `nextbrain-2y` \(the old `elfaheem` stays as the fallback for installed apps, D-145\)',
                  f'Firebase project `{project}` (A-006; the upstream project and the old elfaheem one are not used, no fallback)', text)
    text = re.sub(r"; \.firebaserc still defaults to the old `elfaheem` project, the app itself is on `nextbrain-2y`",
                  f'; .firebaserc defaults to `{project}`', text)
    return text


def claude_md(text: str) -> str:
    text = claude_firebase(text)
    if 'Alfaheem fork.' in text:
        # Refresh a note written by an older version of this script.
        return re.sub(r'<!-- alfaheem:begin -->\n.*?<!-- alfaheem:end -->\n', lambda _: CLAUDE_NOTE.split('\n\n')[0] + '\n',
                      text, count=1, flags=re.S)
    m = re.search(r'\r?\n\r?\n', text)
    if not m:
        return CLAUDE_NOTE + text
    nl = '\r\n' if '\r\n' in m.group(0) else '\n'
    return text[:m.end()] + CLAUDE_NOTE.replace('\n', nl) + text[m.end():]


# ── the redesign kit palette (A-008): Alfaheem's values, built by sync/kit_palette_alfaheem.py ──────────────────────
from kit_palette_alfaheem import build as build_kit  # noqa: E402

KIT = build_kit()


def _snake(name: str) -> str:
    return re.sub(r'([A-Z])', r'_\1', name).lower()


def kit_json(_text: str) -> str:
    return json.dumps(KIT, indent=2) + '\n'


def kit_dart(text: str) -> str:
    """lib/config/theme/kit_palette_defaults.dart: every `field: Color(0x..)` takes the value at its path in KIT
    (section `brand:` / `status:`, or group `areas: {` + key `'home':`), so a new upstream field or key is followed."""
    out, section, group, key = [], None, None, None
    for line in text.split('\n'):
        m = re.match(r'^  (\w+): Kit\w+\($', line)
        if m:
            section, group, key = m.group(1), None, None
        m = re.match(r'^  (\w+): \{$', line)
        if m:
            section, group, key = None, m.group(1), None
        m = re.match(r"^    '(\w+)': Kit\w+\($", line)
        if m and group:
            key = m.group(1)
        m = re.match(r'^(\s+)(\w+): Color\(0x([0-9A-Fa-f]{8})\),$', line)
        if m:
            node = KIT.get(section) if section else (KIT.get(group) or {}).get(key or '')
            value = (node or {}).get(_snake(m.group(2)))
            if value:
                line = f'{m.group(1)}{m.group(2)}: Color(0xFF{value.lstrip("#").upper()}),'
            else:
                print(f'  ! kit_palette_defaults.dart: no Alfaheem value for {section or group}.{key}.{m.group(2)}')
        out.append(line)
    return '\n'.join(out)


def _rgb(role: str) -> str:
    return KIT['brand'][role].lstrip('#').upper()


def _second_text() -> str:
    from kit_palette_alfaheem import second_text  # noqa: PLC0415
    return second_text(KIT).lstrip('#')


# app_theme.dart constants that name a kit role (KIT_SPEC 2.3); the alpha byte of each is kept
APP_THEME_ROLES = {
    'primary': 'primary', 'primaryDark': 'ink', 'primaryLight': 'partner', 'lightPrimary': 'primary',
    'charcoal': 'text', 'charcoalLight': 'muted', 'charcoalDark': 'deep', 'accent': 'warm_tint', 'accent2': 'warm',
    'accent3': 'primary_tint', 'primaryTint': 'primary', 'primaryTintDark': 'primary', 'primaryShadowColor': 'primary',
    'primaryShadowColorDark': 'primary', 'cardShadowColor': 'deep', 'background': 'page', 'textFieldBackground': 'well',
    'inputBg': 'well', 'divider': 'line', 'textDark': 'text', 'textMedium': 'muted', 'textAction': 'primary',
}


def kit_app_theme(text: str) -> str:
    second = _second_text()

    def repl(m: re.Match) -> str:
        name, alpha = m.group(2), m.group(4)
        if name in ('secondText', 'textLight'):
            rgb = second
        elif name in APP_THEME_ROLES:
            rgb = _rgb(APP_THEME_ROLES[name])
        else:
            return m.group(0)
        return f'{m.group(1)}Color(0x{alpha}{rgb})'

    text = re.sub(r'(static const Color (\w+)(\s*)=\s*)Color\(0x([0-9A-Fa-f]{2})[0-9A-Fa-f]{6}\)', repl, text)
    # the warm gradient ends on the forward button's first stop (hot_a)
    return re.sub(r'(colors: \[accent2, )Color\(0xFF[0-9A-Fa-f]{6}\)\]', lambda m: f'{m.group(1)}Color(0xFF{_rgb("hot_a")})]', text)


GITIGNORE_EXTRA = ['docs/redesign/ref/', 'tool/redesign/node_modules/']


def gitignore(text: str) -> str:
    """Alfaheem's local-only folders (the reference screenshots and their playwright install)."""
    missing = [g for g in GITIGNORE_EXTRA if g not in text.split('\n')]
    if not missing:
        return text
    return text.rstrip('\n') + '\n\n# Alfaheem (A-008): reference screenshots and the playwright install of tool/redesign/ref_shots.mjs\n' + '\n'.join(missing) + '\n'


def main() -> int:
    generic_pass()
    move_kotlin()
    edit('lib/core/cert_pin.dart', cert_pins)
    edit('test/auth/cert_pin_test.dart', cert_pin_test)
    edit('web/.well-known/assetlinks.json', assetlinks)
    edit('web/firebase-messaging-sw.js', firebase_sw)
    edit('firebase.json', firebase_json)
    edit('ios/Runner/Info.plist', ios_url_schemes)
    edit('lib/features/messaging/notification/notification_service.dart', vapid_key)
    edit('pubspec.yaml', pubspec)
    edit('lib/design/boot_splash.dart', boot_splash)
    edit('CLAUDE.md', claude_md)
    # A-008: the redesign kit wears Alfaheem's palette (sync/kit_palette_alfaheem.py)
    edit('tool/redesign/kit_palette.json', kit_json)
    edit('lib/config/theme/kit_palette_defaults.dart', kit_dart)
    edit('lib/config/theme/app_theme.dart', kit_app_theme)
    edit('.gitignore', gitignore)
    # Games v4: the sample payload the API test reads carries the server's challenge link; the test asserts the Alfaheem host.
    edit('docs/games-v4/fixtures/learner_extras.json', rename_domain)
    for rel in hook_files():
        edit(rel, lambda text, rel=rel: apply_hooks(rel, text))
    for c in changed:
        print(('would change ' if CHECK else 'changed ') + c)
    print(f'{len(changed)} change(s)')
    return 1 if (CHECK and changed) else 0


if __name__ == '__main__':
    sys.exit(main())
