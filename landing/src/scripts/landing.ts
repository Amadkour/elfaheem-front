// Vanilla client script: hero sentence builder, live numbers, sticky CTA, app prefetch.
// Every network call fails soft: the page never depends on the API.
import { initHighlights, type HlCtx } from './highlights';

type Lv = { id: string | number; name_ar: string; name_en: string; courses?: number };
type Subj = Lv & { levels?: Lv[] };
type Plural = { one: string; two: string; few: string; many: string; other: string };

const root = document.getElementById('nb') as HTMLElement | null;
if (root) init(root);

function init(root: HTMLElement) {
  const lang = root.dataset.lang === 'en' ? 'en' : 'ar';
  const api = root.dataset.api || '';
  const app = root.dataset.app || '/app';
  const locale = lang === 'ar' ? 'ar-u-nu-latn' : 'en';
  const fmt = new Intl.NumberFormat(locale);
  const plural = new Intl.PluralRules(lang);
  const dict = JSON.parse(root.dataset.dict || '{}') as {
    courses: Plural;
    teachers: Plural;
    resultLine: string;
    empty: string;
    anyLevel: string;
    anySubject: string;
    preview: HlCtx['dict']['preview'];
    quotes: HlCtx['dict']['quotes'];
  };

  // After a 429 no landing call is made until Retry-After has passed (defaults stay on screen, no retry loop).
  let blockedUntil = 0;
  const getJson = async <T>(path: string): Promise<T | null> => {
    if (Date.now() < blockedUntil) return null;
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 4000);
    try {
      const r = await fetch(api + path, { signal: ctl.signal, headers: { Accept: 'application/json' } });
      if (r.status === 429) {
        const s = parseInt(r.headers.get("Retry-After") || "", 10);
        blockedUntil = Date.now() + (s > 0 ? Math.min(s, 300) : 60) * 1000;
        return null;
      }
      return r.ok ? ((await r.json()) as T) : null;
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
  };

  /** 1234 -> "1,200+", 57 -> "50+", 7 -> "7". */
  const approx = (n: unknown): string => {
    if (typeof n !== 'number' || !isFinite(n) || n <= 0) return dict.empty;
    if (n < 10) return fmt.format(n);
    const mag = Math.pow(10, Math.floor(Math.log10(n)) - (n >= 100 ? 1 : 0));
    return fmt.format(Math.floor(n / mag) * mag) + '+';
  };

  // ---- hero preview + testimonials (one /highlights request)
  const hl = initHighlights({ root, lang, app, locale, dict, getJson });

  // ---- stats
  const statEls = root.querySelectorAll<HTMLElement>('[data-stat]');
  const hasBaked = Array.from(statEls).some((e) => e.dataset.baked === '1');
  if (!hasBaked) {
    getJson<Record<string, number>>('/stats').then((s) => {
      if (!s) return;
      statEls.forEach((e) => (e.textContent = approx(s[e.dataset.stat || ''])));
      hl.chips();
    });
  }

  // ---- hero
  const subjSel = document.getElementById('nb-subject') as HTMLSelectElement | null;
  const levelSel = document.getElementById('nb-level') as HTMLSelectElement | null;
  const levelWrap = document.getElementById('nb-level-wrap') as HTMLElement | null;
  const modeSel = document.getElementById('nb-mode') as HTMLSelectElement | null;
  const cta = document.getElementById('nb-cta') as HTMLAnchorElement | null;
  const stickyCta = document.getElementById('nb-sticky-cta') as HTMLAnchorElement | null;
  const result = document.getElementById('nb-result');
  let subjects: Subj[] = [];

  const name = (x: Lv) => (lang === 'ar' ? x.name_ar : x.name_en) || x.name_ar || x.name_en || '';
  const fill = (sel: HTMLSelectElement, first: string, items: Lv[]) => {
    sel.textContent = '';
    sel.add(new Option(first, ''));
    items.forEach((i) => sel.add(new Option(name(i), String(i.id))));
  };

  const exploreUrl = () => {
    const p = new URLSearchParams();
    if (subjSel?.value) p.set('subject', subjSel.value);
    if (levelSel?.value && !levelWrap?.hidden) p.set('level', levelSel.value);
    if (modeSel?.value && modeSel.value !== 'any') p.set('mode', modeSel.value);
    p.set('lang', lang);
    return `${app}/explore?${p.toString()}`;
  };
  const syncLinks = () => {
    const u = exploreUrl();
    if (cta) cta.href = u;
    if (stickyCta) stickyCta.href = u;
  };

  const countText = (n: number, forms: Plural) =>
    forms[plural.select(n) as keyof Plural].replace('{n}', fmt.format(n));

  let reqId = 0;
  const match = async () => {
    const id = ++reqId;
    const p = new URLSearchParams();
    if (subjSel?.value) p.set('subject', subjSel.value);
    if (levelSel?.value && !levelWrap?.hidden) p.set('level', levelSel.value);
    p.set('mode', modeSel?.value || 'any');
    const m = await getJson<{ courses: number; teachers: number }>('/match?' + p.toString());
    if (id !== reqId || !result) return;
    if (!m || typeof m.courses !== 'number' || typeof m.teachers !== 'number') {
      if (Date.now() < blockedUntil) return; // rate limited: keep what is shown
      result.textContent = dict.empty;
      return;
    }
    result.textContent = dict.resultLine
      .replace('{courses}', countText(m.courses, dict.courses))
      .replace('{teachers}', countText(m.teachers, dict.teachers));
  };
  let timer: number | undefined;
  const changed = () => {
    syncLinks();
    clearTimeout(timer);
    timer = window.setTimeout(match, 250);
  };

  const onSubject = () => {
    const s = subjects.find((x) => String(x.id) === subjSel?.value);
    const lv = s?.levels || [];
    if (levelSel && levelWrap) {
      fill(levelSel, dict.anyLevel, lv);
      levelWrap.hidden = lv.length === 0;
    }
  };

  const setOptions = (o: { subjects?: Subj[] } | null) => {
    subjects = (o && Array.isArray(o.subjects) ? o.subjects : []).filter((s) => s && s.id != null);
    if (!subjSel) return;
    fill(subjSel, dict.anySubject, subjects);
    onSubject();
    syncLinks();
  };

  subjSel?.addEventListener('change', () => {
    onSubject();
    changed();
  });
  levelSel?.addEventListener('change', changed);
  modeSel?.addEventListener('change', changed);

  const baked = document.getElementById('nb-options');
  let bakedOpts: { subjects?: Subj[] } | null = null;
  try {
    bakedOpts = baked?.textContent ? JSON.parse(baked.textContent) : null;
  } catch {
    bakedOpts = null;
  }
  if (bakedOpts?.subjects?.length) setOptions(bakedOpts);
  else getJson<{ subjects: Subj[] }>('/options').then((o) => o && o.subjects?.length && setOptions(o));
  syncLinks();
  match();

  // ---- sticky CTA: hidden while the hero CTA is on screen
  const sticky = document.getElementById('nb-sticky');
  if (sticky && cta && 'IntersectionObserver' in window) {
    new IntersectionObserver(
      (es) => sticky.classList.toggle('is-off', es[es.length - 1].isIntersecting),
      { threshold: 0.1 },
    ).observe(cta);
  }

  // ---- warm the Flutter app after load, on a quiet connection
  type Conn = { saveData?: boolean; effectiveType?: string };
  const conn = (navigator as unknown as { connection?: Conn }).connection;
  const quiet = conn && (conn.saveData || /(^|-)2g$/.test(conn.effectiveType || ''));
  if (!quiet) {
    const add = (f: string) => {
      const l = document.createElement('link');
      l.rel = 'prefetch';
      l.href = `${app}/${f}`;
      document.head.appendChild(l);
    };
    const prefetch = () => {
      // CanvasKit comes from Google's CDN (D-171), so it is not fetched from the app's folder here
      ['assets/FontManifest.json', 'assets/assets/translation.json'].forEach(add);
      // the build's post-processing gives the main script a content hash (main.dart.<hash8>.js, D-171): the
      // bootstrap names it
      fetch(`${app}/flutter_bootstrap.js`)
        .then((r) => (r.ok ? r.text() : ''))
        .then((t) => add(t.match(/main\.dart(\.[0-9a-f]{8})?\.js/)?.[0] ?? 'main.dart.js'))
        .catch(() => {});
    };
    const idle = () =>
      'requestIdleCallback' in window
        ? (window as unknown as { requestIdleCallback: (f: () => void) => void }).requestIdleCallback(prefetch)
        : setTimeout(prefetch, 2000);
    if (document.readyState === 'complete') idle();
    else window.addEventListener('load', idle, { once: true });
  }
}

// ---- remember the language choice
document.querySelectorAll<HTMLAnchorElement>('[data-setlang]').forEach((a) =>
  a.addEventListener('click', () => {
    try {
      localStorage.setItem('nb_lang', a.dataset.setlang || '');
    } catch {
      /* private mode */
    }
  }),
);
