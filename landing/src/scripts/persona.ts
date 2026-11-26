// Persona pages (redesign phase 7). Every number shown is real or not shown: /stats, /options and /highlights from the
// public landing API, and the teacher-demand endpoint on the teacher page. Every call fails soft and shares the
// 429 back-off of api.ts.
import { makeApi } from './api';

type Lv = { id: string | number; name_ar: string; name_en: string; courses?: number };
type Subj = Lv & { levels?: Lv[] };
type Plural = { one: string; two: string; few: string; many: string; other: string };
type Course = {
  id: number;
  title: string;
  title_en?: string | null;
  image: string | null;
  teacher: string | null;
  rating: number | null;
  students: number;
  mode: string;
};
type Review = { name: string; stars: number; text: string; lang: string; kind: string; course: string | null; teacher: string | null };
type Demand = {
  available?: boolean;
  waiting_students?: number | null;
  booked_classes_30d?: number | null;
  groups_waiting?: number | null;
};

const root = document.getElementById('pp-main') as HTMLElement | null;
if (root) init(root);

function init(root: HTMLElement) {
  const lang = root.dataset.lang === 'en' ? 'en' : 'ar';
  const who = root.dataset.who || 'student';
  const app = root.dataset.app || '/app';
  const demandUrl = root.dataset.demand || '';
  const { getJson } = makeApi(root.dataset.api || '');
  const demandApi = makeApi('');
  const fmt = new Intl.NumberFormat(lang === 'ar' ? 'ar-u-nu-latn' : 'en');
  const plural = new Intl.PluralRules(lang);
  const dict = JSON.parse(root.dataset.dict || '{}') as {
    courses: Plural;
    show: { live: string; students: string; rating: string; online: string; center: string };
    stars: string;
    demand: { waiting: string; booked: string; groups: string };
  };
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T | null;
  const h = <K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const name = (x: Lv) => (lang === 'ar' ? x.name_ar : x.name_en) || x.name_ar || x.name_en || '';
  const countText = (n: number, forms: Plural) =>
    forms[plural.select(n) as keyof Plural].replace('{n}', fmt.format(n));
  const approx = (n: unknown): string => {
    if (typeof n !== 'number' || !isFinite(n) || n <= 0) return '';
    if (n < 10) return fmt.format(n);
    const mag = Math.pow(10, Math.floor(Math.log10(n)) - (n >= 100 ? 1 : 0));
    return fmt.format(Math.floor(n / mag) * mag) + '+';
  };
  const num = (n: unknown) => (typeof n === 'number' && isFinite(n) && n >= 0 ? n : null);

  // ---- numbers: the course count in the hero pill and the stats band
  const live = $('pp-live');
  const liveT = $('pp-live-t');
  const statsSec = $('pp-stats');
  const paintStats = (s: Record<string, number> | null) => {
    if (!s) return;
    const c = num(s.courses);
    if (live && liveT && c && c > 0) {
      // the number is its own LTR island, so '60+' never turns into '+60' in Arabic
      const forms = c < 10 ? dict.courses[plural.select(c) as keyof Plural] : dict.courses.other;
      const [pre, post] = dict.show.live.replace('{courses}', forms).split('{n}');
      liveT.textContent = '';
      if (post === undefined) liveT.textContent = pre; // "one course" has no number in it
      else liveT.append(pre, h('bdi', 'pp-num-ltr', c < 10 ? fmt.format(c) : approx(c)), post);
      live.hidden = false;
    }
    if (!statsSec) return;
    let any = false;
    statsSec.querySelectorAll<HTMLElement>('[data-stat]').forEach((b) => {
      const v = approx(s[b.dataset.stat || '']);
      b.textContent = v;
      (b.parentElement as HTMLElement).hidden = !v;
      any = any || !!v;
    });
    statsSec.hidden = !any;
  };
  getJson<Record<string, number>>('/stats').then(paintStats);

  // ---- options: grade chips (student, parent), subject chips (teacher), the subjects marquee
  const chipsWrap = $('pp-chips-wrap');
  const chips = $('pp-chips');
  const go = $<HTMLAnchorElement>('pp-go');
  let subjects: Subj[] = [];
  let picked = '';

  const levelsOf = () => {
    const seen = new Map<string, Lv & { courses: number }>();
    subjects.forEach((s) =>
      (s.levels || []).forEach((l) => {
        const k = String(l.id);
        const cur = seen.get(k);
        if (cur) cur.courses += l.courses || 0;
        else seen.set(k, { ...l, courses: l.courses || 0 });
      }),
    );
    return Array.from(seen.values());
  };

  const paintChips = (items: Lv[], onPick: (id: string) => void) => {
    if (!chips || !chipsWrap || !items.length) return;
    chips.textContent = '';
    items.forEach((it) => {
      const b = h('button', 'pp-chip m-jelly', name(it));
      b.type = 'button';
      b.setAttribute('role', 'radio');
      b.dataset.id = String(it.id);
      b.addEventListener('click', () => {
        chips.querySelectorAll('[role=radio]').forEach((x) => x.setAttribute('aria-checked', String(x === b)));
        picked = String(it.id);
        onPick(picked);
      });
      chips.append(b);
    });
    // roving arrows inside the radio group
    chips.addEventListener('keydown', (e) => {
      const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'];
      if (!keys.includes(e.key)) return;
      const all = Array.from(chips.querySelectorAll<HTMLButtonElement>('[role=radio]'));
      const i = all.indexOf(document.activeElement as HTMLButtonElement);
      if (i < 0) return;
      e.preventDefault();
      const fwd = e.key === 'ArrowDown' || e.key === (lang === 'ar' ? 'ArrowLeft' : 'ArrowRight');
      const n = all[(i + (fwd ? 1 : -1) + all.length) % all.length];
      n.focus();
      n.click();
    });
    const first = chips.querySelector<HTMLButtonElement>('[role=radio]');
    first?.setAttribute('aria-checked', 'true');
    chips.querySelectorAll('[role=radio]').forEach((x) => x !== first && x.setAttribute('aria-checked', 'false'));
    picked = String(items[0].id);
    chipsWrap.hidden = false;
  };

  // student / parent: the results card for one grade
  const res = $('pp-res');
  const resT = $('pp-res-t');
  const resSubj = $('pp-res-subj');
  const resAll = $<HTMLAnchorElement>('pp-res-all');
  const explore = (p: Record<string, string>) => {
    const u = new URLSearchParams(p);
    u.set('lang', lang);
    return `${app}/explore?${u.toString()}`;
  };
  const showResults = (levelId: string, scroll: boolean) => {
    if (!res || !resT || !resSubj) return;
    const lv = levelsOf().find((l) => String(l.id) === levelId);
    if (!lv) return;
    resT.textContent = name(lv);
    resSubj.textContent = '';
    subjects.forEach((s, i) => {
      const l = (s.levels || []).find((x) => String(x.id) === levelId);
      if (!l) return;
      const a = h('a', `pp-subj pp-sc${i % 7}`);
      a.href = explore({ subject: String(s.id), level: levelId });
      a.append(h('b', '', name(s)));
      if (l.courses && l.courses > 0) a.append(h('span', '', countText(l.courses, dict.courses)));
      resSubj.append(a);
    });
    if (resAll) resAll.href = explore({ level: levelId });
    res.hidden = false;
    res.classList.remove('pp-in');
    void res.offsetWidth;
    res.classList.add('pp-in');
    if (scroll) res.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'nearest' });
  };
  $('pp-res-change')?.addEventListener('click', () => {
    if (res) res.hidden = true;
    chips?.querySelector<HTMLButtonElement>('[aria-checked=true]')?.focus();
  });

  // teacher: the demand card
  const card = $('pp-demand');
  const dK = $('pp-demand-k');
  const dT = $('pp-demand-t');
  const dStats = $('pp-dstats');
  const dNote = $('pp-dnote');
  const form = $('book');
  const joinTitle = dT?.textContent || '';
  let dReq = 0;
  const demand = async (subjectId: string): Promise<boolean> => {
    if (!demandUrl || !card || !dStats) return false;
    const id = ++dReq;
    const p = new URLSearchParams({ subject: subjectId });
    const d = await demandApi.getJson<Demand>(`${demandUrl}?${p.toString()}`);
    if (id !== dReq) return false;
    const rows: [number | null, string, string][] = d && d.available === true
      ? [
          [num(d.waiting_students), dict.demand.waiting, 'a'],
          [num(d.booked_classes_30d), dict.demand.booked, 'b'],
          [num(d.groups_waiting), dict.demand.groups, 'c'],
        ]
      : [];
    const shown = rows.filter((r) => r[0] != null);
    dStats.textContent = '';
    if (!shown.length) {
      dStats.hidden = true;
      if (dNote) dNote.hidden = true;
      if (dK) dK.hidden = true;
      if (dT) dT.textContent = joinTitle;
      return false;
    }
    shown.forEach(([n, label, c]) => {
      const s = h('span', `pp-dstat pp-dstat--${c}`);
      s.setAttribute('role', 'listitem');
      s.append(h('b', '', fmt.format(n as number)), h('span', '', label));
      dStats.append(s);
    });
    const subj = subjects.find((s) => String(s.id) === subjectId);
    if (dT && subj) dT.textContent = name(subj);
    if (dK) dK.hidden = false;
    dStats.hidden = false;
    if (dNote) dNote.hidden = false;
    card.classList.remove('pp-in');
    void card.offsetWidth;
    card.classList.add('pp-in');
    return true;
  };

  const setOptions = (o: { subjects?: Subj[] } | null) => {
    subjects = (o && Array.isArray(o.subjects) ? o.subjects : []).filter((s) => s && s.id != null && name(s));
    if (!subjects.length) return;
    paintMarquee();
    if (who === 'teacher') {
      const top = subjects.slice(0, 8);
      // the picker is offered only when the endpoint answers for the first subject; else the card stays a join card
      demand(String(top[0].id)).then((ok) => {
        if (!ok || !form) return;
        paintChips(top, () => {
          if (dStats) dStats.hidden = true;
          if (dNote) dNote.hidden = true;
        });
        form.hidden = false;
        go?.addEventListener('click', (e) => {
          e.preventDefault();
          if (picked) demand(picked).then(() => card?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'nearest' }));
        });
      });
      return;
    }
    const levels = levelsOf();
    if (!levels.length) return;
    paintChips(levels, () => {
      if (res) res.hidden = true;
    });
    showResults(picked, false);
    go?.addEventListener('click', (e) => {
      e.preventDefault();
      if (picked) showResults(picked, true);
    });
  };

  // the subjects marquee (parent, teacher): real subject names, two rows, duplicated for a seamless loop
  const paintMarquee = () => {
    const sec = $('pp-subjects');
    const m = $('pp-marq');
    if (!sec || !m || subjects.length < 3) return;
    m.textContent = '';
    const list = subjects.slice(0, 14);
    [0, 1].forEach((row) => {
      const rowEl = h('div', `pp-mrow${row ? ' is-rev' : ''}`);
      const items = row ? list.slice().reverse() : list;
      [0, 1].forEach((copy) => {
        items.forEach((s, i) => {
          const a = h('a', `pp-mpill pp-sc${(i + row * 3) % 7}`);
          a.href = explore({ subject: String(s.id) });
          a.textContent = name(s);
          if (copy || row) {
            a.tabIndex = -1;
            a.setAttribute('aria-hidden', 'true');
          }
          rowEl.append(a);
        });
      });
      m.append(rowEl);
    });
    sec.hidden = false;
  };

  const baked = $('pp-options');
  let bakedOpts: { subjects?: Subj[] } | null = null;
  try {
    bakedOpts = baked?.textContent ? JSON.parse(baked.textContent) : null;
  } catch {
    bakedOpts = null;
  }
  if (bakedOpts?.subjects?.length) setOptions(bakedOpts);
  else getJson<{ subjects: Subj[] }>('/options').then((o) => o && setOptions(o));

  // ---- /highlights: the course wave in the hero and the live reviews
  const wave = $('pp-wave');
  const track = $('pp-wave-track');
  const covers = 7;
  const courseCard = (c: Course, j: number, hidden: boolean) => {
    const title = (lang === 'en' && c.title_en) || c.title;
    const item = h('div', 'pp-wv');
    if (hidden) item.setAttribute('aria-hidden', 'true');
    const a = h('a', 'pp-wv__card');
    a.href = `${app}/courses/${c.id}?lang=${lang}`;
    a.style.setProperty('--j', String(j));
    if (hidden) a.tabIndex = -1;
    const inner = h('span', 'pp-wv__in');
    const cov = h('span', `pp-wv__cov pp-cv${c.id % covers}`);
    if (c.image && /^https:\/\//.test(c.image)) {
      const img = new Image(200, 94);
      img.alt = '';
      img.loading = 'lazy';
      img.decoding = 'async';
      img.src = c.image;
      img.addEventListener('error', () => img.remove());
      cov.append(img);
    }
    const mode = h('span', 'pp-wv__cat', c.mode === 'center' ? dict.show.center : dict.show.online);
    cov.append(mode);
    const body = h('span', 'pp-wv__b');
    const tt = h('span', 'pp-wv__t', title);
    tt.dir = 'auto';
    body.append(tt);
    const foot = h('span', 'pp-wv__f');
    if (typeof c.rating === 'number' && c.rating > 0) {
      const r = h('span', 'pp-wv__r');
      r.setAttribute('aria-label', dict.show.rating.replace('{n}', fmt.format(c.rating)));
      r.append(h('i', '', '★'), document.createTextNode(' ' + fmt.format(c.rating)));
      foot.append(r);
    }
    if (c.students > 0) foot.append(h('span', '', dict.show.students.replace('{n}', fmt.format(c.students))));
    body.append(foot);
    if (c.teacher) {
      const m = h('span', 'pp-wv__m', c.teacher);
      m.dir = 'auto';
      body.append(m);
    }
    inner.append(cov, body);
    a.append(inner);
    item.append(a);
    return item;
  };
  const paintWave = (courses: Course[]) => {
    if (!wave || !track) return;
    const list = courses.filter((c) => c && c.id != null && c.title).slice(0, 12);
    if (!list.length) return;
    // at least 12 cards per half so the loop never shows a gap at 1360 px
    const half: Course[] = [];
    while (half.length < 12) half.push(...list);
    half.length = Math.max(12, list.length);
    track.textContent = '';
    [0, 1].forEach((copy) => half.forEach((c, i) => track.append(courseCard(c, copy * half.length + i, copy > 0 || i >= list.length))));
    wave.hidden = false;
  };

  const qSec = $('pp-quotes');
  const qList = $('pp-qlist');
  const paintQuotes = (rows: Review[]) => {
    if (!qSec || !qList) return;
    rows
      .filter((r) => r && r.name && r.text)
      .slice(0, Math.max(0, 6 - qList.children.length))
      .forEach((r) => {
        const li = h('li', `pp-qcard pp-q${qList.children.length % 3}`);
        const mark = h('span', 'pp-qmark', '“');
        mark.setAttribute('aria-hidden', 'true');
        const n = Math.max(1, Math.min(5, Math.round(r.stars || 5)));
        const st = h('span', 'pp-qstars', '★★★★★'.slice(0, n));
        st.setAttribute('role', 'img');
        st.setAttribute('aria-label', dict.stars.replace('{n}', String(n)));
        const bq = h('blockquote');
        bq.dir = r.lang === 'ar' ? 'rtl' : 'ltr';
        bq.append(h('p', '', r.text));
        const sub = r.kind === 'teacher' ? r.teacher : r.course;
        const whoEl = h('span', 'pp-qwho', sub ? `${r.name} · ${sub}` : r.name);
        whoEl.dir = 'auto';
        li.append(mark, st, bq, whoEl);
        qList.append(li);
      });
    if (qList.children.length) qSec.hidden = false;
  };

  getJson<{ courses?: Course[]; testimonials?: Review[] }>('/highlights').then((d) => {
    if (!d || typeof d !== 'object') return;
    paintWave(Array.isArray(d.courses) ? d.courses : []);
    paintQuotes(Array.isArray(d.testimonials) ? d.testimonials : []);
  });
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
