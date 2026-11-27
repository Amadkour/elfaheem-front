"""The one-line hooks Alfaheem keeps in shared upstream files (the mechanism of A-007, docs/DECISIONS_ALFAHEEM.md; no hook
is in use since A-007 moved into NextBrain as its D-949).

Alfaheem's own code lives in kept files (sync/keep_paths.txt); a shared file only carries a short hook that calls it.
A sync takes the upstream version of every shared file, so the hooks are written again by sync/apply_identity.py
(`apply_hooks`) and sync/check_identity.py fails when one is missing (`missing_hooks`).

Each hook: (file, upstream text, Alfaheem text). The upstream text must appear exactly once; the Alfaheem text
carries the marker `Alfaheem A-nnn` so a re-run sees it is already there (idempotent).
"""
from __future__ import annotations

import re

HOOKS: list[tuple[str, str, str]] = [
    # none at the moment: A-007 (the page canvas and the landing's live theme) is NextBrain's own code since its D-949.
    # A hook is (file, upstream text, Alfaheem text with the marker `Alfaheem A-nnn`).
    # A-008: two upstream checks name its brand green's hue; Alfaheem's blocks follow its own kit roles.
    ('test/ui/app_blocks_test.dart',
     "expect(forest.hue, closeTo(162, 6), reason: 'about #0E3B2E');",
     "expect(forest.hue, closeTo(HSLColor.fromColor(kKitPaletteDefaults.brand.ink).hue, 6), "
     "reason: 'Alfaheem A-008: the hue of the kit ink');"),
    ('test/ui/app_blocks_test.dart',
     "expect(sage.hue, inInclusiveRange(90, 160)); // the kit green is hue 156",
     "expect(sage.hue, closeTo(HSLColor.fromColor(kKitPaletteDefaults.brand.primaryTint).hue, 15)); "
     "// Alfaheem A-008: the kit primary tint's hue"),
    ('test/ui/theme_contrast_test.dart', 'inInclusiveRange(140, 170), reason: _hex(c));',
     'inInclusiveRange(205, 240), reason: _hex(c)); /* Alfaheem A-008: the kit muted navy-grey, hue 222 */'),
    ('test/ui/brand_layer_test.dart', "inInclusiveRange(140, 180), reason: 'the green stop');",
     "inInclusiveRange(name == 'built-in' ? 180 : 140, name == 'built-in' ? 230 : 180), "
     "reason: 'Alfaheem A-008: the built-in stop is blue (primary hue 206), a green server palette stays green');"),
    ('test/ui/brand_layer_test.dart', "inInclusiveRange(140, 180), reason: 'the end stays green');",
     "inInclusiveRange(name == 'built-in' ? 180 : 140, name == 'built-in' ? 230 : 180), "
     "reason: 'Alfaheem A-008: the end stays on the palette hue (built-in: partner 194)');"),
    # Two shared-widget hits that upstream's palette clears by a hair (the a11y header says: blocked, with a reason)
    ('test/ui/a11y_guidelines_test.dart',
     'final _blocked = <(String, String, bool Function(String label), String)>[\n',
     'final _blocked = <(String, String, bool Function(String label), String)>[\n'
     "  // Alfaheem A-008: HomeFactChip's appInk(success) sits on its oklab threshold with this palette's derived canvas\n"
     "  ('teacher', 'text contrast', (l) => l.contains('3'), 'Alfaheem A-008: HomeFactChip success ink 4.39:1, shared widget'),\n"
     "  // Alfaheem A-008: a primary-filled bar under the subhead's rect in dark mode (the guideline samples it)\n"
     "  ('adv director aggregate', 'text contrast', (l) => l == 'Most loaded', 'Alfaheem A-008: sampled bar, shared widget'),\n"),
]

def apply_hooks(rel: str, text: str) -> str:
    """Write every hook of [rel] into [text] (LF line ends). Unknown anchors are reported by missing_hooks."""
    text = apply_landing_rules(rel, text)
    for f, old, new in HOOKS:
        if f != rel or new in text:
            continue
        if text.count(old) == 1:
            text = text.replace(old, new)
        else:
            print(f'  ! {rel}: the upstream text of an Alfaheem hook moved ({old.strip()[:70]}); update sync/hooks.py')
    return text


def hook_files() -> list[str]:
    return sorted({f for f, _, _ in HOOKS} | set(LANDING_COLOUR_FILES))


def missing_hooks(read) -> list[str]:
    """[read](rel) -> the file's text (LF). The hooks not in place, as gate lines."""
    out = []
    for f, _, new in HOOKS:
        text = read(f)
        if text is None or new not in text:
            out.append(f'{f}: Alfaheem hook missing ({new.strip()[:90]}); run py -3.12 sync/apply_identity.py')
    return out


# The landing's fixed upstream colours outside its :root variables, routed through variables that
# landing/src/theme/theme-runtime.js sets from the live theme. Text rules: (files, regex, replacement), applied in
# order; after a run none of the patterns is left, so a re-run changes nothing.
LANDING_COLOUR_FILES: list[str] = []  # none since NextBrain's D-949 routes the landing's colours through variables
LANDING_RULES: list[tuple[str, str]] = []
# The upstream palette: none of it may be left in the landing outside global.css's own :root variable lines (which
# the theme overrides, see landing_leftovers).
UPSTREAM_PALETTE = re.compile(
    r'(?i)#(0f7b5f|0a5642|34a883|f3e6c4|c98a3d|fbf7ec|f1ecda|14201a|46544d|e4ebe5|0c684f|e3f3ec|8a5a1c|0c1511|121d18|'
    r'1a2822|f2f7f4|a7b5ad|2e3f37|5fd1aa|08130f|43b85a|0a3b2d|fbf1d9|c9d3cd)\b|rgba\((10, 86, 66|243, 230, 196),')


def apply_landing_rules(rel: str, text: str) -> str:
    if rel not in LANDING_COLOUR_FILES:
        return text
    for rx, repl in LANDING_RULES:
        text = re.sub(rx, repl, text)
    return text


def landing_leftovers(read, files: list[str]) -> list[str]:
    """Upstream colours still fixed in the landing, and :root variables of global.css the theme does not set."""
    out = []
    runtime = read('landing/src/theme/theme-runtime.js') or ''
    for rel in files:
        if not rel.startswith('landing/src/') or rel.startswith('landing/src/theme/') or not rel.endswith(('.css', '.astro', '.ts', '.js', '.mjs')):
            continue
        text = read(rel)
        if text is None:
            continue
        for n, line in enumerate(text.split(chr(10)), 1):
            var = re.match(r'\s*(--[\w-]+):\s*#[0-9a-fA-F]{3,8};', line) if rel == 'landing/src/styles/global.css' else None
            if var:
                if f"'{var.group(1)}'" not in runtime:
                    out.append(f'{rel}:{n}: {var.group(1)} is not set by landing/src/theme/theme-runtime.js (D-949)')
                continue
            if UPSTREAM_PALETTE.search(line):
                out.append(f'{rel}:{n}: a fixed upstream colour in the landing (the landing wears the live theme, NextBrain D-949; extend LANDING_RULES in sync/hooks.py): {line.strip()[:100]}')
    return out
