// ALFAHEEM ONLY (A-007, docs/DECISIONS_ALFAHEEM.md). The landing wears the app's active theme.
//
// themeCss(colors) maps the colours of GET /api/v1/theme/web (the payload's `colors`) onto the landing's CSS custom
// properties, light and dark, the way the app derives its own surfaces: the sidebar colour (the primary, darkened until
// the on-hero inks read on it, as lib/design/app_gradients.dart BrandLayer does), the page canvas (a light tint of the
// sidebar's hue, lib/design/alfaheem_canvas.dart), and every text colour checked for contrast on the surfaces it sits on.
//
// This file is plain JavaScript on purpose: AlfaheemTheme.astro runs it at build time (the baked defaults, from
// theme-default.json) AND inlines its text into the page (the runtime update), so the two can never differ. Keep it
// self-contained: no imports, nothing outside the two functions.

/** @param {Record<string, unknown>} c the theme's colours. @returns {{css: string, light: string, dark: string}} */
function themeCss(c) {
  const hex = (v, d) => {
    const s = typeof v === 'string' ? v.trim().replace('#', '') : '';
    if (/^[0-9a-f]{6}$/i.test(s)) return '#' + s.toLowerCase();
    if (/^[0-9a-f]{8}$/i.test(s)) return '#' + s.slice(2).toLowerCase(); // the server's #AARRGGBB, alpha dropped
    return d;
  };
  const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const toHex = (a) => '#' + a.map((x) => Math.round(Math.min(255, Math.max(0, x))).toString(16).padStart(2, '0')).join('');
  const blend = (top, alpha, under) => {
    const t = rgb(top), u = rgb(under);
    return toHex(t.map((x, i) => x * alpha + u[i] * (1 - alpha)));
  };
  const lum = (h) => {
    const [r, g, b] = rgb(h).map((x) => {
      const s = x / 255;
      return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const contrast = (a, b) => {
    const x = lum(a), y = lum(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  };
  const minC = (fg, bgs) => Math.min(...bgs.map((b) => contrast(fg, b)));
  const hsl = (h) => {
    const [r, g, b] = rgb(h).map((x) => x / 255);
    const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
    let hh = 0, s = 0;
    if (d !== 0) {
      s = d / (1 - Math.abs(2 * l - 1));
      if (max === r) hh = 60 * (((g - b) / d) % 6);
      else if (max === g) hh = 60 * ((b - r) / d + 2);
      else hh = 60 * ((r - g) / d + 4);
    }
    return [(hh + 360) % 360, s, l];
  };
  const fromHsl = (hh, s, l) => {
    const ch = (1 - Math.abs(2 * l - 1)) * s, x = ch * (1 - Math.abs(((hh / 60) % 2) - 1)), m = l - ch / 2;
    const [r, g, b] = hh < 60 ? [ch, x, 0] : hh < 120 ? [x, ch, 0] : hh < 180 ? [0, ch, x] : hh < 240 ? [0, x, ch] : hh < 300 ? [x, 0, ch] : [ch, 0, x];
    return toHex([r, g, b].map((v) => (v + m) * 255));
  };
  const darken = (h, f) => {
    const [hh, s, l] = hsl(h);
    return fromHsl(hh, s, Math.min(1, Math.max(0, l * f)));
  };
  const withL = (h, l) => {
    const [hh, s] = hsl(h);
    return fromHsl(hh, s, l);
  };
  // fg moved away from the surfaces (darker on light ones, lighter on dark ones) until it reaches min
  const ensure = (fg, bgs, min) => {
    const light = bgs.reduce((a, b) => a + lum(b), 0) / bgs.length > 0.18;
    let out = fg;
    for (let i = 0; i < 60 && minC(out, bgs) < min; i++) {
      const [hh, s, l] = hsl(out);
      out = fromHsl(hh, s, light ? l * 0.94 : l + (1 - l) * 0.08);
    }
    return out;
  };

  const primary = hex(c.primary, '#24b1b1');
  const primaryLight = hex(c.primary_light, primary);
  const onHero = hex(c.on_hero, hex(c.surface_card, '#ffffff'));
  const cream = hex(c.accent, '#d7c3f1');
  const accent2 = hex(c.accent2, '#7e5cad');

  // the sidebar colour (BrandLayer): the on-hero ink, its glass, hover and person box read on it, the cream on the glass
  const sidebar = (dark) => {
    const reads = (x) => {
      const g = blend(onHero, 0.16, x), u = blend(onHero, 0.1, x), h = blend(onHero, 0.08, x);
      return minC(onHero, [x, g, u, h]) >= 4.6 && contrast(cream, g) >= 4.6 && contrast(blend(onHero, 0.9, u), u) >= 4.6;
    };
    let s = dark ? darken(primary, 0.8) : primary;
    for (let i = 0; i < 200 && !reads(s); i++) s = darken(s, 0.97);
    return s;
  };

  const mode = (dark) => {
    const side = sidebar(dark);
    const paper = dark ? hex(c.dark_card, '#2e2e2e') : hex(c.card_bg, hex(c.surface_card, '#ffffff'));
    const base = dark ? hex(c.dark_background, '#1a1a1a') : paper;
    // the app's canvas (alfaheem_canvas.dart): the sidebar's hue at mid lightness over the paper; a deep tint in dark
    const bg = dark ? blend(side, 0.16, base) : blend(withL(side, 0.42), 0.09, base);
    const bgAlt = dark ? blend(side, 0.26, base) : blend(withL(side, 0.42), 0.16, base);
    const text = dark ? hex(c.dark_text_primary, '#f5f5f5') : hex(c.text_dark, '#1a1a1a');
    const surfaces = [bg, bgAlt, paper];
    const btn = ensure(dark ? primary : primary, [onHero], 4.6);
    const goldHover = dark ? blend(onHero, 0.25, cream) : blend(onHero, 0.4, cream);
    const v = {
      '--primary': btn,
      '--primary-dark': darken(btn, 0.82),
      '--primary-light': primaryLight,
      '--gold-soft': cream,
      '--gold-hover': goldHover,
      '--on-gold': ensure(hex(c.text_dark, '#1a1a1a'), [cream, goldHover], 4.5),
      '--gold': ensure(accent2, surfaces, 3),
      '--success': ensure(hex(c.success, '#34c270'), surfaces, 4.5),
      '--bg': bg,
      '--bg-alt': bgAlt,
      '--surface': paper,
      '--text': ensure(text, surfaces, 7),
      '--muted': ensure(dark ? hex(c.dark_text_muted, '#b0b0b0') : hex(c.text_medium, '#4a4a4a'), surfaces, 4.5),
      '--border': dark ? hex(c.dark_divider, '#3a3a3a') : hex(c.divider, '#e8e8e8'),
      '--link': ensure(dark ? primaryLight : primary, surfaces, 4.5),
      '--btn-bg': btn,
      '--btn-text': onHero,
      '--hero-from': darken(side, dark ? 0.55 : 0.74),
      '--hero-to': side,
      '--on-hero': onHero,
      '--on-hero-muted': blend(onHero, 0.86, side),
      '--focus': dark ? ensure(cream, surfaces, 3) : ensure(accent2, surfaces, 3),
      '--track': blend(text, 0.22, paper),
    };
    return { v, side, bg };
  };

  const l = mode(false), d = mode(true);
  const block = (v) => Object.keys(v).map((k) => k + ':' + v[k]).join(';');
  // :root:root outranks the upstream defaults in global.css whatever order the stylesheets load in
  const css = ':root:root{' + block(l.v) + '}@media (prefers-color-scheme: dark){:root:root{' + block(d.v) + '}}';
  return { css, light: l.side, dark: d.bg };
}

/** Applies the cached theme before the first paint, then fetches the live one (a failure keeps what is on screen). */
function themeBoot(url, key) {
  var style = document.getElementById('alf-theme');
  var put = function (t) {
    if (!t || !t.css || !style) return;
    style.textContent = t.css;
    var metas = document.querySelectorAll('meta[name="theme-color"]');
    if (metas[0]) metas[0].setAttribute('content', t.light);
    if (metas[1]) metas[1].setAttribute('content', t.dark);
  };
  try {
    var cached = localStorage.getItem(key);
    if (cached) put(JSON.parse(cached));
  } catch (e) {}
  try {
    var ctl = typeof AbortController === 'function' ? new AbortController() : null;
    var timer = setTimeout(function () {
      if (ctl) ctl.abort();
    }, 6000);
    fetch(url, { headers: { Accept: 'application/json' }, signal: ctl ? ctl.signal : undefined })
      .then(function (r) {
        return r.ok ? r.json() : null;
      })
      .then(function (j) {
        clearTimeout(timer);
        if (!j || !j.colors) return;
        var t = themeCss(j.colors);
        put(t);
        try {
          localStorage.setItem(key, JSON.stringify(t));
        } catch (e) {}
      })
      .catch(function () {});
  } catch (e) {}
}
