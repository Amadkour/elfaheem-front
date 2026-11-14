// The Privacy policy and the Terms of service (D-308) for the /privacy and /terms pages.
//
// The text ships in src/content/legal/<doc>.json — a copy of the backend's data/legal/<doc>.json (refresh it with
// back/scripts/contract/export_legal.py --front <front>). When the build has LANDING_API_ORIGIN, the live document
// (the super admin may have edited it) is fetched from GET /app-content/legal/<doc>?lang=both instead; a failed or
// malformed answer falls back to the bundled copy, so the build never fails on it.
import privacyJson from '../content/legal/privacy.json';
import termsJson from '../content/legal/terms.json';

export type LegalDocId = 'privacy' | 'terms';
type Pair = { ar: string; en: string };
export type LegalDoc = {
  doc: LegalDocId;
  version: string;
  effective_date: string;
  title: Pair;
  intro: Pair;
  highlights: Pair[];
  sections: { id: string; icon: string; title: Pair; body: Pair }[];
};

const BUNDLED: Record<LegalDocId, LegalDoc> = {
  privacy: privacyJson as LegalDoc,
  terms: termsJson as LegalDoc,
};

export const CONTACT_EMAIL = 'nextbrain.2y@gmail.com';

const isPair = (v: unknown): v is Pair =>
  !!v && typeof v === 'object' && typeof (v as Pair).ar === 'string' && typeof (v as Pair).en === 'string';

function valid(d: unknown): d is LegalDoc {
  if (!d || typeof d !== 'object') return false;
  const x = d as LegalDoc;
  return (
    typeof x.version === 'string' &&
    /^\d{4}-\d{2}-\d{2}$/.test(x.effective_date || '') &&
    isPair(x.title) &&
    Array.isArray(x.sections) &&
    x.sections.length > 0 &&
    x.sections.every((s) => s && typeof s.id === 'string' && isPair(s.title) && isPair(s.body))
  );
}

const cache = new Map<LegalDocId, Promise<LegalDoc>>();

export function loadLegal(doc: LegalDocId): Promise<LegalDoc> {
  let p = cache.get(doc);
  if (!p) {
    p = fetchLive(doc).then((live) => live ?? BUNDLED[doc]);
    cache.set(doc, p);
  }
  return p;
}

async function fetchLive(doc: LegalDocId): Promise<LegalDoc | null> {
  const env = (globalThis as { process?: { env: Record<string, string | undefined> } }).process?.env ?? {};
  const origin = (env.LANDING_API_ORIGIN || '').replace(/\/+$/, '');
  if (!origin) return null;
  try {
    const r = await fetch(`${origin}/api/api/v1/app-content/legal/${doc}?lang=both`, { signal: AbortSignal.timeout(8000) });
    if (!r.ok) return null;
    const d = (await r.json()) as unknown;
    if (!valid(d)) return null;
    return { ...d, intro: isPair(d.intro) ? d.intro : { ar: '', en: '' }, highlights: (d.highlights || []).filter(isPair) };
  } catch {
    return null;
  }
}

/** Text in one language, the other one when it is empty. */
export const pick = (p: Pair | undefined, lang: 'ar' | 'en'): string =>
  (lang === 'ar' ? p?.ar || p?.en : p?.en || p?.ar) || '';

/** A section body -> blocks: a blank line starts a paragraph, lines starting with "- " / "•" are list items. */
export type Block = { kind: 'p'; text: string } | { kind: 'ul'; items: string[] };
export function blocks(body: string): Block[] {
  const out: Block[] = [];
  let para: string[] = [];
  let list: string[] = [];
  const flushPara = () => {
    if (para.length) out.push({ kind: 'p', text: para.join(' ') });
    para = [];
  };
  const flushList = () => {
    if (list.length) out.push({ kind: 'ul', items: list });
    list = [];
  };
  for (const raw of body.replace(/\r\n/g, '\n').split('\n')) {
    const line = raw.trim();
    if (!line) {
      flushPara();
      flushList();
      continue;
    }
    const m = /^[-•*·]\s+(.*)$/.exec(line);
    if (m) {
      flushPara();
      list.push(m[1]);
    } else {
      flushList();
      para.push(line);
    }
  }
  flushPara();
  flushList();
  return out;
}

/** Text -> pieces with links: https:// URLs and e-mail addresses become anchors (rendered escaped by Astro). */
export type Piece = { text: string; href?: string };
export function linkify(text: string): Piece[] {
  const re = /(https?:\/\/[^\s)،,]+[^\s)،,.]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})/g;
  const out: Piece[] = [];
  let last = 0;
  for (const m of text.matchAll(re)) {
    const i = m.index ?? 0;
    if (i > last) out.push({ text: text.slice(last, i) });
    const v = m[0];
    out.push({ text: v, href: v.includes('@') && !v.startsWith('http') ? `mailto:${v}` : v });
    last = i + v.length;
  }
  if (last < text.length) out.push({ text: text.slice(last) });
  return out;
}

const AR_MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const EN_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** '2026-11-08' -> '8 November 2026' / '8 نوفمبر 2026' (Latin digits, like the app). */
export function dateLabel(iso: string, lang: 'ar' | 'en'): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return iso;
  const months = lang === 'ar' ? AR_MONTHS : EN_MONTHS;
  return `${Number(m[3])} ${months[Number(m[2]) - 1]} ${m[1]}`;
}
