#!/usr/bin/env python3
"""Generate every brand image NextBrain has and Alfaheem has no hand-made version of (sync/brand_assets.txt),
from Alfaheem's own images: assets/images/logo.png (the mark alone) and assets/images/app_icon.png.

The originals are never changed (assets/images/splash.png, the picture with words in it, stays in the repo unused,
A-003). Run after a sync that adds a brand image, then `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create` (sync/README.md). Needs Pillow (py -3.12 -m pip install pillow).

Usage: py -3.12 sync/gen_brand_assets.py
"""
from __future__ import annotations

import base64
import io
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
IMG = ROOT / 'assets/images'


def env() -> dict[str, str]:
    out = {}
    for line in (ROOT / 'sync/identity.env').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out


E = env()


def rgb(hex_: str) -> tuple[int, int, int]:
    h = hex_.lstrip('#')
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


LIGHT = rgb(E['SPLASH_COLOR'])
NAVY = rgb(E['SPLASH_COLOR_DARK'])

LOGO = Image.open(IMG / 'logo.png').convert('RGBA')
LOGO = LOGO.crop(LOGO.getbbox())  # the mark alone, no transparent margin
APP_ICON = Image.open(IMG / 'app_icon.png').convert('RGB')
FONT = ROOT / 'assets/fonts/tajawal/Tajawal-Bold.ttf'

# "الفهيم" in presentation forms, visual (left-to-right) order: Pillow here has no text shaping (no raqm).
# meem final, yeh medial, heh medial, feh medial, lam initial, alef (plain: Tajawal has no isolated-alef glyph).
NAME_AR_VISUAL = ''.join(chr(c) for c in (0xFEE2, 0xFEF4, 0xFEEC, 0xFED4, 0xFEDF, 0x0627))


def fit(img: Image.Image, w: int, h: int) -> Image.Image:
    s = min(w / img.width, h / img.height)
    return img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)


def paste_center(canvas: Image.Image, img: Image.Image, cx: int, cy: int) -> None:
    canvas.alpha_composite(img, (cx - img.width // 2, cy - img.height // 2)) if canvas.mode == 'RGBA' else \
        canvas.paste(img, (cx - img.width // 2, cy - img.height // 2), img)


def save(img: Image.Image, rel: str, **kw) -> None:
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p, optimize=True, **kw)
    print('wrote', rel, img.size)


def splash_art() -> Image.Image:
    """1040 x 1000, transparent: the mark on a white disc (legible on the light AND the navy splash), centred where
    BootSplash expects it (the visible mark spans ~32-68 % of the height; the name is drawn as text below it)."""
    art = Image.new('RGBA', (1040, 1000), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    r = 210
    d.ellipse((520 - r, 500 - r, 520 + r, 500 + r), fill=(255, 255, 255, 255))
    paste_center(art, fit(LOGO, 300, 270), 520, 505)
    return art


def icon_square(size: int) -> Image.Image:
    return APP_ICON.resize((size, size), Image.LANCZOS)


def web_ios_splash(w: int, h: int, art: Image.Image) -> Image.Image:
    """The PWA start-up image (web/splash/ios): the splash art at the device's scale on the light colour."""
    scale = 3 if 1080 <= min(w, h) <= 1320 else 2
    canvas = Image.new('RGB', (w, h), LIGHT)
    a = art.resize((260 * scale, 250 * scale), Image.LANCZOS)
    canvas.paste(a, ((w - a.width) // 2, (h - a.height) // 2), a)
    return canvas


def og_image() -> Image.Image:
    """1200 x 630 social preview: the mark and the name in both languages."""
    canvas = Image.new('RGB', (1200, 630), LIGHT)
    d = ImageDraw.Draw(canvas)
    d.ellipse((90, 105, 510, 525), fill=(255, 255, 255))
    mark = fit(LOGO, 300, 270)
    canvas.paste(mark, (300 - mark.width // 2, 318 - mark.height // 2), mark)
    ar = ImageFont.truetype(str(FONT), 150)
    en = ImageFont.truetype(str(FONT), 64)
    small = ImageFont.truetype(str(FONT), 34)
    d.text((880, 250), NAME_AR_VISUAL, font=ar, fill=NAVY, anchor='mm')
    d.text((880, 380), E['APP_NAME_EN'], font=en, fill=NAVY, anchor='mm')
    d.text((880, 450), f"by {E['COMPANY_NAME']}", font=small, fill=(90, 110, 140), anchor='mm')
    return canvas


def favicon_svg(png: Image.Image) -> str:
    buf = io.BytesIO()
    png.save(buf, format='PNG', optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()
    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 64 64">'
            f'<image width="64" height="64" href="data:image/png;base64,{b64}"/></svg>\n')


def offline_logo_data_uri() -> str:
    img = Image.new('RGBA', (144, 144), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, 143, 143), fill=(255, 255, 255, 255))
    paste_center(img, fit(LOGO, 104, 94), 72, 74)
    buf = io.BytesIO()
    img.save(buf, format='PNG', optimize=True)
    return 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()


def main() -> None:
    art = splash_art()
    save(art, 'assets/images/splash_alfaheem.png')
    save(icon_square(1024), 'assets/icon/icon.png')
    save(Image.open(IMG / 'adaptive_icon_foreground.png').convert('RGBA'), 'assets/icon/adaptive_icon_foreground.png')
    mark = fit(LOGO, 540, 301)
    save(mark, 'assets/images/logo_mark.png')
    save(fit(LOGO, 270, 151), 'landing/src/assets/logo_mark.png')
    save(icon_square(180), 'web/icons/Icon-180.png')
    for p in sorted((ROOT / 'web/splash/ios').glob('apple-splash-*.png')):
        m = re.match(r'apple-splash-(\d+)-(\d+)\.png', p.name)
        if m:
            save(web_ios_splash(int(m.group(1)), int(m.group(2)), art), f'web/splash/ios/{p.name}')
    # NextBrain's unused mipmap-*/launcher_icon.png (the manifest uses ic_launcher): the Alfaheem icon at that size.
    for p in sorted((ROOT / 'android/app/src/main/res').glob('mipmap-*/launcher_icon.png')):
        size = Image.open(p).size
        save(icon_square(size[0]).resize(size, Image.LANCZOS), str(p.relative_to(ROOT)).replace('\\', '/'))
    # landing/public
    save(icon_square(180), 'landing/public/apple-touch-icon.png')
    save(icon_square(32), 'landing/public/favicon-32.png')
    icon_square(48).save(ROOT / 'landing/public/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])
    print('wrote landing/public/favicon.ico')
    (ROOT / 'landing/public/favicon.svg').write_text(favicon_svg(icon_square(64)), encoding='utf-8')
    print('wrote landing/public/favicon.svg')
    logo512 = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    paste_center(logo512, fit(LOGO, 460, 420), 256, 256)
    save(logo512, 'landing/public/logo-512.png')
    save(og_image(), 'landing/public/og.png')
    # web/offline.html carries its logo inline (no network when it shows).
    off = ROOT / 'web/offline.html'
    if off.exists():
        t = off.read_bytes().decode('utf-8')
        n = re.sub(r'(<img alt="[^"]*" src=")data:image/png;base64,[A-Za-z0-9+/=]+', lambda m: m.group(1) + offline_logo_data_uri(), t)
        if n != t:
            off.write_bytes(n.encode('utf-8'))
            print('wrote web/offline.html (inline logo)')


if __name__ == '__main__':
    main()
