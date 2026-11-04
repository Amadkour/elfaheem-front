// Hero "live preview" (real public courses) and the testimonials row, both fed by ONE
// GET /highlights per page view. Fails soft: no data means an abstract illustration and no testimonials.
type Course = {
  id: number;
  title: string;
  title_en?: string | null;
  image: string | null;
  teacher: string | null;
  rating: number | null;
  ratings: number;
  students: number;
  mode: string;
};
type Review = {
  id: number;
  name: string;
  stars: number;
  text: string;
  lang: string;
  kind: string;
  course: string | null;
  teacher: string | null;
  month: string | null;
};
type Highlights = { courses?: Course[]; testimonials?: Review[] };
type Dict = {
  preview: { students: string; online: string; center: string; rating: string };
  quotes: { stars: string };
};
export type HlCtx = {
  root: HTMLElement;
  lang: 'ar' | 'en';
  app: string;
  locale: string;
  dict: Dict;
  getJson: <T>(path: string) => Promise<T | null>;
};

const h = <K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
};

export function initHighlights(ctx: HlCtx) {
  const { root, lang, app, locale, dict, getJson } = ctx;
  const fmt = new Intl.NumberFormat(locale);
  const fill = (s: string, n: string | number) => s.replace('{n}', String(n));

  const stars = (value: number, label: string) => {
    const s = h('span', 'stars', '★★★★★');
    s.style.setProperty('--r', String(Math.max(0, Math.min(5, value))));
    s.setAttribute('role', 'img');
    s.setAttribute('aria-label', label);
    return s;
  };

  // ---- the stat chips copy the numbers of the trust section (baked or fetched)
  const chips = () => {
    root.querySelectorAll<HTMLElement>('[data-chip]').forEach((c) => {
      const src = root.querySelector<HTMLElement>(`[data-stat="${c.dataset.chip}"]`);
      const v = src?.textContent?.trim() || '';
      const label = src?.nextElementSibling?.textContent?.trim() || '';
      if (!v || v === '—') {
        c.hidden = true;
        return;
      }
      c.textContent = '';
      c.append(h('i'), h('b', '', v), h('span', '', label));
      c.hidden = false;
    });
  };

  // ---- hero preview
  const aside = document.getElementById('nb-preview');
  const list = document.getElementById('nb-pv-list');
  const mq = window.matchMedia('(min-width: 1024px)');
  let data: Highlights | null | undefined;

  const courseCard = (c: Course) => {
    const title = (lang === 'en' && c.title_en) || c.title;
    const a = h('a', 'pc');
    a.href = `${app}/courses/${c.id}`;
    const cover = h('span', 'pc__cover');
    if (c.image && /^https:\/\//.test(c.image)) {
      const img = new Image(96, 64);
      img.alt = title;
      img.loading = 'lazy';
      img.decoding = 'async';
      img.src = c.image;
      img.addEventListener('error', () => img.remove());
      cover.append(img);
    }
    const body = h('span', 'pc__body');
    body.append(h('b', 'pc__title', title));
    if (c.teacher) body.append(h('span', 'pc__teacher', c.teacher));
    const meta = h('span', 'pc__meta');
    if (typeof c.rating === 'number') {
      meta.append(stars(c.rating, fill(dict.preview.rating, fmt.format(c.rating))));
      if (c.ratings > 0) meta.append(h('span', '', `(${fmt.format(c.ratings)})`));
    }
    if (c.students > 0) meta.append(h('span', '', fill(dict.preview.students, fmt.format(c.students))));
    meta.append(h('em', 'pc__mode', c.mode === 'center' ? dict.preview.center : dict.preview.online));
    body.append(meta);
    a.append(cover, body);
    return a;
  };

  const paintPreview = () => {
    if (!aside || !list || data === undefined || !mq.matches || aside.dataset.state === 'ready') return;
    const courses = (data?.courses || []).filter((c) => c && c.id != null && c.title).slice(0, 3);
    if (!courses.length) {
      aside.dataset.state = 'empty';
      return;
    }
    list.textContent = '';
    courses.forEach((c) => list.append(courseCard(c)));
    aside.dataset.state = 'ready';
  };
  mq.addEventListener('change', paintPreview);

  // ---- testimonials
  const sec = document.getElementById('nb-quotes') as HTMLElement | null;
  const track = document.getElementById('nb-qtrack');
  const nav = document.getElementById('nb-qnav') as HTMLElement | null;
  const prev = document.getElementById('nb-qprev') as HTMLButtonElement | null;
  const next = document.getElementById('nb-qnext') as HTMLButtonElement | null;
  const rtl = lang === 'ar';

  const initials = (name: string) => {
    const w = name.replace(/[.·]/g, ' ').trim().split(/\s+/).filter(Boolean);
    return (Array.from(w[0] || '')[0] || '') + (w.length > 1 ? Array.from(w[1])[0] : '');
  };

  const reviewCard = (r: Review) => {
    const li = h('li', 'qcard');
    li.append(h('span', 'qmark', '“'));
    li.lastElementChild?.setAttribute('aria-hidden', 'true');
    const n = Math.max(1, Math.min(5, Math.round(r.stars || 5)));
    li.append(stars(n, fill(dict.quotes.stars, n)));
    const bq = h('blockquote');
    bq.dir = r.lang === 'ar' ? 'rtl' : 'ltr';
    bq.append(h('p', '', r.text));
    li.append(bq);
    const who = h('div', 'qwho');
    const av = h('span', 'qav', initials(r.name));
    av.setAttribute('aria-hidden', 'true');
    const nm = h('span', 'qname');
    const nb = h('b', '', r.name);
    nb.dir = 'auto';
    nm.append(nb);
    const sub = r.kind === 'teacher' ? r.teacher : r.course;
    const chipText = [sub, r.kind === 'course' ? r.teacher : null].filter(Boolean).join(' · ');
    if (chipText) {
      const ch = h('span', 'qchip', chipText);
      ch.dir = 'auto';
      nm.append(ch);
    }
    who.append(av, nm);
    li.append(who);
    return li;
  };

  const syncNav = () => {
    if (!track || !nav || !prev || !next) return;
    const max = track.scrollWidth - track.clientWidth;
    nav.hidden = max <= 4;
    const pos = Math.abs(track.scrollLeft);
    prev.disabled = pos <= 2;
    next.disabled = pos >= max - 2;
  };
  let navBound = false;
  const bindNav = () => {
    if (navBound || !track || !prev || !next) return;
    navBound = true;
    const go = (dir: number) =>
      track.scrollBy({
        left: dir * (rtl ? -1 : 1) * track.clientWidth * 0.9,
        behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
      });
    prev.addEventListener('click', () => go(-1));
    next.addEventListener('click', () => go(1));
    track.addEventListener('scroll', syncNav, { passive: true });
    if ('ResizeObserver' in window) new ResizeObserver(syncNav).observe(track);
    else window.addEventListener('resize', syncNav);
  };

  const paintQuotes = () => {
    if (!sec || !track) return;
    const rows = (data?.testimonials || []).filter((r) => r && r.name && r.text);
    rows.forEach((r) => track.append(reviewCard(r)));
    if (track.children.length) {
      sec.hidden = false;
      bindNav();
      syncNav();
    }
  };
  if (sec && !sec.hidden) bindNav();

  // ONE request per page view; null (error, timeout, 429) leaves the defaults.
  getJson<Highlights>('/highlights').then((d) => {
    data = d && typeof d === 'object' ? d : null;
    paintPreview();
    paintQuotes();
  });
  chips();

  return { chips };
}
