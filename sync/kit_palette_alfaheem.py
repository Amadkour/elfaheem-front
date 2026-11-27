#!/usr/bin/env python3
"""sync/kit_palette_alfaheem.py - Alfaheem's redesign kit palette (A-008), built by the upstream rules.

The upstream script (tool/redesign/kit_palette.py, NextBrain's D-1810) derives NextBrain's palette from its logo seeds.
Alfaheem keeps the reference design's own values (docs/redesign/KIT_PALETTE_DOWNSTREAM.md, the same data as
tool/redesign/kit_palette_ref.json). This script takes those values, derives what the reference does not give (the dark
tints and inks, the role sets, subjects, status) with the upstream functions, and fixes only the pairs that fail the
upstream contrast checks (`checks()`, floor 4.5), the same way upstream does (darken_until / lighten_until, dark text
on the light warm buttons). Every fix is listed in FIXES and in KIT_PALETTE_DOWNSTREAM.md.

    py -3.12 sync/kit_palette_alfaheem.py            # the fixes and the contrast summary
    py -3.12 sync/kit_palette_alfaheem.py --json     # the whole `kit` map (theme field names) on stdout
    py -3.12 sync/kit_palette_alfaheem.py --check    # exit 1 when a pair is under its floor

sync/apply_identity.py imports build() and writes the result into tool/redesign/kit_palette.json,
lib/config/theme/kit_palette_defaults.dart and lib/config/theme/app_theme.dart; the backend's identity step reads the
copy in its own sync/kit_palette_alfaheem.json (written here with --write-back <path>).
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF_PATH = ROOT / 'tool/redesign/kit_palette_ref.json'


def _upstream():
    spec = importlib.util.spec_from_file_location('kit_palette_upstream', ROOT / 'tool/redesign/kit_palette.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


U = _upstream()
WHITE, AA = U.WHITE, U.AA
FIXES: list[tuple[str, str, str, str]] = []   # (what, reference value, used value, why)
PRIMARY_HEADROOM = 6.0   # white on `primary`: the derived theme stops stay at AA (upstream's is 6.75)
TINT_SATURATION = 0.85   # ThemeConfigProvider.blockSurface's clamp


def _fix(what: str, old: str, new: str, why: str) -> str:
    if old.upper() != new.upper():
        FIXES.append((what, old.upper(), new.upper(), why))
    return new.upper()


def _white_ok(c: str) -> bool:
    return U.cr(WHITE, c) >= AA


def _warm(c: str) -> bool:
    """Orange / coral / red (hue 340 - 50): darkened to 4.6 for white it turns brown."""
    h = U.hue(c)
    return h >= 340 or h <= 50


def _buttons(name: str, s: dict, fg_dark: str) -> None:
    """A filled button's text reads on both stops (P10): white on stops darkened to 4.6:1; when white would need the
    warm stops darkened into brown (orange / coral: luminance above 0.3), the dark ink instead, as upstream does
    for its gold forward button (P4)."""
    a, b, fg = s['btn_a'], s['btn_b'], s['btn_fg']
    if U.cr(fg, a) >= AA and U.cr(fg, b) >= AA:
        return
    if fg.upper() == WHITE:
        if all(U.cr(fg_dark, x) >= AA for x in (a, b)) and all(_warm(x) for x in (a, b)):
            s['btn_fg'] = _fix(f'{name} btn_fg', fg, fg_dark, 'white under 4.5 on the warm stops: the dark ink, as upstream P4')
            return
        s['btn_a'] = _fix(f'{name} btn_a', a, U.darken_until(a, [WHITE]), 'white under 4.5: darkened to 4.6 (P10)')
        s['btn_b'] = _fix(f'{name} btn_b', b, U.darken_until(b, [WHITE]), 'white under 4.5: darkened to 4.6 (P10)')
    else:
        if U.cr(fg, a) < AA:
            s['btn_a'] = _fix(f'{name} btn_a', a, U.lighten_until(a, [fg]), 'dark text under 4.5: lightened (P10)')
        if U.cr(fg, b) < AA:
            s['btn_b'] = _fix(f'{name} btn_b', b, U.lighten_until(b, [fg]), 'dark text under 4.5: lightened (P10)')


def build() -> dict:
    FIXES.clear()
    U.FIXED.clear()
    ref = json.loads(REF_PATH.read_text(encoding='utf-8'))
    br = {k: v.upper() for k, v in ref['brand'].items()}
    # The theme layer derives lighter stops and tinted chips from `primary` (sidebar radial fill, count chips, tab
    # labels on a primary tint) and is built for upstream's headroom (white on its primary 6.75:1). The reference's
    # bright blue is 4.62:1, so every derived surface fell under 4.5: `primary` is the reference's own blue ink
    # (upstream P2: primary_ink = primary); the bright blue stays the home area's colour and hero.
    if U.cr(WHITE, br['primary']) < PRIMARY_HEADROOM:
        new = br['primary_ink'] if U.cr(WHITE, br['primary_ink']) >= PRIMARY_HEADROOM else U.darken_until(
            br['primary'], [WHITE], PRIMARY_HEADROOM + 0.1)
        br['primary'] = _fix('brand primary', br['primary'], new,
                             f'white {U.cr(WHITE, br["primary"]):.2f}:1, the theme layer needs {PRIMARY_HEADROOM}:1: the reference blue ink')
    # blockSurface (theme_config_provider) clamps a block's saturation to 0.85: a tint above it is not drawn as given
    for k in ('primary_tint', 'partner_tint', 'warm_tint', 'hot_tint'):
        h, l, s = U.hls(br[k])
        if s > TINT_SATURATION:
            br[k] = _fix(f'brand {k}', br[k], U.from_hls(h, l, TINT_SATURATION),
                         f'saturation {s:.2f} > {TINT_SATURATION} (the block surface clamp)')
    for k in ('primary', 'partner', 'warm', 'hot'):
        t = U.triple(br[k], (br[k + '_tint'], br[k + '_ink']), f'brand {k}')
        br[k + '_ink'] = t['ink'].upper()
        br[k + '_tint_dark'], br[k + '_ink_dark'] = t['tint_dark'], t['ink_dark']
    # `hot` carries white text (upstream check "white on hot"); its tint, ink and the forward button keep their values
    if not _white_ok(br['hot']):
        br['hot'] = _fix('brand hot', br['hot'], U.darken_until(br['hot'], [WHITE]), 'white on hot under 4.5: darkened to 4.6')
    # the forward button: white on apricot / coral is 2.0 / 3.4, so its text is the deep navy (upstream P4)
    if min(U.cr(br['hot_fg'], br['hot_a']), U.cr(br['hot_fg'], br['hot_b'])) < AA:
        br['hot_fg'] = _fix('brand hot_fg', br['hot_fg'], br['deep'], 'white under 4.5 on hot_a / hot_b: the deep ink (P4)')

    acc = dict(U.ACCENTS)               # mint stays at its design value #19C29B in this product (not moved)
    accents = {k: U.triple(v, U.ACCENT_GIVEN[k], f'accent {k}') for k, v in acc.items()}

    areas = {}
    for n, a in ref['areas'].items():
        s = {k: v.upper() for k, v in a.items()}
        t = U.triple(s['a'], (s['tint'], s['ink']), f'area {n}')
        s['ink'] = t['ink'].upper()
        s['tint_dark'], s['ink_dark'] = t['tint_dark'], t['ink_dark']
        if not _white_ok(s['hero_mid']):
            s['hero_mid'] = _fix(f'area {n} hero_mid', s['hero_mid'], U.darken_until(s['hero_mid'], [WHITE]), 'white under 4.5')
        _buttons(f'area {n}', s, br['ink'])
        areas[n] = {k: s[k] for k in ('a', 'b', 'hero_a', 'hero_mid', 'tint', 'ink', 'tint_dark', 'ink_dark', 'btn_a',
                                      'btn_b', 'btn_fg')}

    roles = {}
    for n, r in ref['roles'].items():
        s = U.accent_set(r['a'].upper(), r['b'].upper(), br, yellow=(n == 'super'))
        roles[n] = s

    # The kicker on a primary surface is large-text at least (the backend's theme_kit_unit floor 3.0): the apricot
    # (2.3:1 on the blue) is lightened just enough, the way upstream derives its own warm_on_dark (lighten_until).
    # Measured on the reference's bright blue (the home area colour), not the darker `primary` above.
    bright = ref['brand']['primary'].upper()
    if U.cr(br['warm_on_dark'], bright) < 3.0:
        br['warm_on_dark'] = _fix('brand warm_on_dark', br['warm_on_dark'],
                                  U.lighten_until(br['warm_on_dark'], [bright, br['primary']], 3.0 + 0.05),
                                  'under 3.0 (large text) on the bright blue: lightened toward white')
    # The gold kicker (warm_on_dark) is drawn only where it reads at 4.5 on every stop of the hero (AppHero.kickerInk);
    # upstream's test requires it on the home, me, admin and teacher heroes. The reference's apricot reads on the
    # navy stops but not on the bright blue / violet starts, so those heroes start one step deeper (hero_a = the
    # colour darkened until the kicker reads), the way upstream starts them on the logo green instead of the partner.
    for grp, n in U.GOLD_KICKER_HEROES:
        s = (areas if grp == 'areas' else roles)[n]
        if U.cr(br['warm_on_dark'], s['hero_a']) < AA:
            s['hero_a'] = _fix(f'{grp[:-1]} {n} hero_a', s['hero_a'], U.darken_until(s['hero_a'], [br['warm_on_dark']], AA),
                               'the apricot kicker under 4.5 on the start stop: started deeper')
        if U.cr(br['warm_on_dark'], s['hero_mid']) < AA:
            s['hero_mid'] = _fix(f'{grp[:-1]} {n} hero_mid', s['hero_mid'],
                                 U.darken_until(s['hero_mid'], [br['warm_on_dark']], AA), 'the apricot kicker under 4.5')

    subjects = {}
    for k, c in U.SUBJECTS.items():
        t = U.triple(c, U.SUBJECT_GIVEN.get(k), f'subject {k}')
        t['fg'] = WHITE if U.cr(c, WHITE) >= 3 else br['deep']
        subjects[k] = t
    live_t = U.triple(U.LIVE, U.LIVE_GIVEN, 'status live')
    ok, warn = accents['mint'], accents['sun']
    err = U.triple(U.ERROR)
    status = {
        'live': U.LIVE, 'live_fill': U.darken_until(U.LIVE, [WHITE]), 'live_tint': live_t['tint'], 'live_ink': live_t['ink'],
        'live_tint_dark': live_t['tint_dark'], 'live_ink_dark': live_t['ink_dark'],
        'ok': acc['mint'], 'ok_tint': ok['tint'], 'ok_ink': ok['ink'], 'ok_tint_dark': ok['tint_dark'],
        'ok_ink_dark': ok['ink_dark'],
        'warn': acc['sun'], 'warn_tint': warn['tint'], 'warn_ink': warn['ink'], 'warn_tint_dark': warn['tint_dark'],
        'warn_ink_dark': warn['ink_dark'],
        'lock': U.LOCK, 'lock_ink': U.darken_until('#7C8CA3', [WHITE, U.mix(U.LOCK, WHITE, 0.6)]),
        'lock_dark': '#3A4046', 'lock_ink_dark': '#A9B4C2',
        'error': U.ERROR, 'error_ink': err['ink'], 'error_tint': err['tint'], 'error_tint_dark': err['tint_dark'],
        'error_ink_dark': err['ink_dark'],
    }
    for what, old, new in U.FIXED:
        FIXES.append((what + ' ink', old.upper(), new.upper(), 'ink under 4.5 on its tint: darkened (upstream triple)'))
    brand_keys = list(U.build()['brand'].keys())   # upstream's key order
    U.FIXED.clear()
    brand = {k: br[k] for k in brand_keys}
    return {'v': 1, 'brand': brand, 'accents': accents, 'status': status, 'areas': areas, 'roles': roles,
            'subjects': subjects}


# Upstream pairs held to a lower floor here: upstream's green heroes start on `primary`, so it checks the small kicker
# there at 4.5; here every hero that draws the kicker starts deeper (above) and kickerInk draws the on-hero ink on any
# other hero, so on primary the kicker is large text at most: the backend's floor, 3.0.
LARGE_ONLY = {'warm_on_dark on primary': 3.0}


def second_text(k: dict) -> str:
    """The theme's secondText / textLight (app_theme.dart, the kit_default preset's text_light / second_text): the
    lightest shade of the muted role that still reads at 4.5 on every light surface and block (page, card, well, the
    two tints), so it stays quieter than text_medium (= muted; theme_contrast_unit checks the order)."""
    b = k['brand']
    on = [WHITE, b['page'], b['well'], b['warm_tint'], b['primary_tint']]
    best, t = b['muted'], 0.0
    while t < 1:
        t += 0.01
        c = U.mix(b['muted'], WHITE, t)
        if min(U.cr(c, x) for x in on) < AA + 0.05:
            break
        best = c
    return best.upper()


def under(k: dict) -> list:
    return [(l, fg, bg, U.cr(fg, bg), LARGE_ONLY.get(l, fl)) for l, fg, bg, fl in U.checks(k)
            if U.cr(fg, bg) < LARGE_ONLY.get(l, fl)]


def main() -> int:
    sys.stdout.reconfigure(encoding='utf-8')
    k = build()
    if '--json' in sys.argv:
        print(json.dumps(k, indent=2))
        return 0
    if '--write-back' in sys.argv:
        out = Path(sys.argv[sys.argv.index('--write-back') + 1])
        data = {'_doc': 'Generated by the front repo: py -3.12 sync/kit_palette_alfaheem.py --write-back <this file> (A-008)',
                'second_text': second_text(k), 'kit': k}
        out.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8', newline='\n')
        print(out)
    bad = under(k)
    if '--check' not in sys.argv:
        for what, old, new, why in FIXES:
            print(f'fix {what}: {old} -> {new} ({why})')
    for row in bad:
        print('FAIL %s: %s on %s = %.2f (< %s)' % row)
    print(f'{len(U.checks(k))} pairs checked, {len(bad)} under the floor')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
