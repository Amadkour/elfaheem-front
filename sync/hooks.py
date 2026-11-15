"""The one-line hooks Alfaheem keeps in shared upstream files (A-007, docs/DECISIONS_ALFAHEEM.md).

Alfaheem's own code lives in kept files (sync/keep_paths.txt); a shared file only carries a short hook that calls it.
A sync takes the upstream version of every shared file, so the hooks are written again by sync/apply_identity.py
(`apply_hooks`) and sync/check_identity.py fails when one is missing (`missing_hooks`).

Each hook: (file, upstream text, Alfaheem text). The upstream text must appear exactly once; the Alfaheem text
carries the marker `Alfaheem A-nnn` so a re-run sees it is already there (idempotent).
"""
from __future__ import annotations

import re

CANVAS_IMPORT = "import 'package:flutter_education_app/design/alfaheem_canvas.dart'; // Alfaheem A-007 (sync/hooks.py)\n"

HOOKS: list[tuple[str, str, str]] = [
    # the page canvas colour (every reader of context.colors.background) and the theme's scaffold colour
    ('lib/config/theme/theme_config_provider.dart',
     "import 'package:flutter_education_app/design/app_contrast.dart';\n",
     "import 'package:flutter_education_app/design/app_contrast.dart';\n" + CANVAS_IMPORT),
    ('lib/config/theme/theme_config_provider.dart',
     '  Color get background => isDark\n',
     '  Color get background => AlfaheemCanvas.tint(this, dark: isDark, base: _nbBackground, paper: _model?.cardBg ?? AppTheme.cardBg); // Alfaheem A-007\n'
     '  Color get _nbBackground => isDark\n'),
    ('lib/config/theme/theme_config_provider.dart',
     '    final bg = dark ? (m?.darkBackground ?? AppTheme.darkBackground) : (m?.background ?? AppTheme.background);\n',
     '    final bg = AlfaheemCanvas.tint(this, dark: dark, base: dark ? (m?.darkBackground ?? AppTheme.darkBackground) : (m?.background ?? AppTheme.background), paper: m?.cardBg ?? AppTheme.cardBg); // Alfaheem A-007\n'),
    # BasePage: transparent Scaffolds over the tinted, latticed canvas
    ('lib/utils/widget/base_page.dart',
     "import 'package:flutter_education_app/config/theme/theme_config_provider.dart';\n",
     "import 'package:flutter_education_app/config/theme/theme_config_provider.dart';\n" + CANVAS_IMPORT),
    ('lib/utils/widget/base_page.dart',
     '    Color bg=background ??(context.colors.background);\n',
     '    Color bg=background ??AlfaheemCanvas.pageFill(context); // Alfaheem A-007\n'),
    ('lib/utils/widget/base_page.dart',
     '      builder: (context, _, _) => _buildPage(context),\n',
     '      builder: (context, _, _) => AlfaheemCanvas.page(context, explicit: background, child: _buildPage(context)), // Alfaheem A-007\n'),
    # the landing wears the app's active theme (landing/src/alfaheem/): the component replaces the fixed theme-color metas
    ('landing/src/layouts/Base.astro',
     "import '../styles/premium.css';\n",
     "import '../styles/premium.css';\nimport AlfaheemTheme from '../alfaheem/AlfaheemTheme.astro'; // Alfaheem A-007 (sync/hooks.py)\n"),
    ('landing/src/layouts/Base.astro',
     '    <meta name="theme-color" content="#0f7b5f" media="(prefers-color-scheme: light)" />\n'
     '    <meta name="theme-color" content="#0c1511" media="(prefers-color-scheme: dark)" />\n',
     '    <AlfaheemTheme /><!-- Alfaheem A-007 (sync/hooks.py): theme-color metas + the live theme -->\n'),
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
# landing/src/alfaheem/theme-runtime.js sets from the live theme. Text rules: (files, regex, replacement), applied in
# order; after a run none of the patterns is left, so a re-run changes nothing.
LANDING_COLOUR_FILES = ['landing/src/styles/global.css', 'landing/src/styles/premium.css', 'landing/src/components/Landing.astro']
LANDING_RULES: list[tuple[str, str]] = [
    (r'fill="#f3e6c4"', 'style="fill:var(--gold-soft)"'),
    (r'fill="#0a3b2d"', 'style="fill:var(--on-gold)"'),
    (r'%230a3b2d', '%231a1a1a'),  # the select arrow (a data URL cannot read a variable): a neutral ink
    (r'(?i)#0a3b2d\b', 'var(--on-gold)'),
    (r'(?i)#fbf1d9\b', 'var(--gold-hover)'),
    (r'(?i)#c9d3cd\b', 'var(--track)'),
    (r'rgba\(10, 86, 66, (0?\.\d+)\)', lambda m: f'color-mix(in srgb, var(--hero-from) {round(float(m.group(1)) * 100)}%, transparent)'),
    (r'rgba\(243, 230, 196, (0?\.\d+)\)', lambda m: f'color-mix(in srgb, var(--gold-soft) {round(float(m.group(1)) * 100)}%, transparent)'),
]
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
    runtime = read('landing/src/alfaheem/theme-runtime.js') or ''
    for rel in files:
        if not rel.startswith('landing/src/') or rel.startswith('landing/src/alfaheem/') or not rel.endswith(('.css', '.astro', '.ts', '.js', '.mjs')):
            continue
        text = read(rel)
        if text is None:
            continue
        for n, line in enumerate(text.split(chr(10)), 1):
            var = re.match(r'\s*(--[\w-]+):\s*#[0-9a-fA-F]{3,8};', line) if rel == 'landing/src/styles/global.css' else None
            if var:
                if f"'{var.group(1)}'" not in runtime:
                    out.append(f'{rel}:{n}: {var.group(1)} is not set by landing/src/alfaheem/theme-runtime.js (A-007)')
                continue
            if UPSTREAM_PALETTE.search(line):
                out.append(f'{rel}:{n}: a fixed upstream colour in the landing (A-007; extend LANDING_RULES in sync/hooks.py): {line.strip()[:100]}')
    return out
