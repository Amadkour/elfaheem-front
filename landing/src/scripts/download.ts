// The downloads page script (src/components/DownloadPage.astro): reads the releases manifest the app reads
// (`/releases/releases.json`, schema in lib/core/get_app/releases_manifest.dart), recommends this device's file and
// fills one card per platform. Parsing mirrors parseReleasesManifest: https URLs only (relative ones resolve against
// the manifest's URL), a malformed part is dropped, never a guessed link. Every node is built with textContent.

type Platform = 'android' | 'ios' | 'windows' | 'macos' | 'linux';
const PLATFORMS: Platform[] = ['android', 'ios', 'windows', 'macos', 'linux'];

interface RFile {
  arch: string;
  kind: string;
  url: string;
  size: number | null;
  sha256: string | null;
}
interface Release {
  version: string;
  releasedAt: string;
  minOs: string;
  primary: string;
  files: RFile[];
  pwa: boolean;
}
type Dict = Record<string, string> & { platforms: Record<Platform, string> };

const root = document.getElementById('dl') as HTMLElement | null;
if (root) init(root);

function init(root: HTMLElement) {
  const lang = root.dataset.lang === 'en' ? 'en' : 'ar';
  const manifestUrl = root.dataset.manifest || '/releases/releases.json';
  const app = root.dataset.app || '/app';
  const d = JSON.parse(root.dataset.dict || '{}') as Dict;
  const locale = lang === 'ar' ? 'ar-u-nu-latn' : 'en';
  const rec = document.getElementById('dl-rec') as HTMLElement;
  const fill = (s: string, v: Record<string, string>) => s.replace(/\{(\w)\}/g, (_, k) => v[k] ?? '');

  const el = <K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  };
  const link = (href: string, cls: string, text: string, download = false) => {
    const a = el('a', cls, text);
    a.href = href;
    if (download) a.setAttribute('download', '');
    return a;
  };

  const sizeLabel = (b: number | null) => {
    if (!b) return '';
    const mb = b / (1024 * 1024);
    const n = new Intl.NumberFormat(locale, { maximumFractionDigits: mb < 10 ? 1 : 0 }).format(mb);
    return lang === 'ar' ? `${n} ميجابايت` : `${n} MB`;
  };
  const dateLabel = (iso: string) => {
    const t = Date.parse(iso);
    if (Number.isNaN(t)) return '';
    return new Intl.DateTimeFormat(locale, { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' }).format(t);
  };
  const fileLabel = (f: RFile) => {
    const kind = f.kind ? (f.kind === 'AppImage' || f.kind === 'appimage' ? 'AppImage' : f.kind.toUpperCase()) : '';
    return [kind, f.arch && f.arch !== 'universal' ? f.arch : ''].filter(Boolean).join(' · ') || f.url.split('/').pop() || '';
  };

  // ---- device ----
  async function detect(): Promise<{ platform: Platform | null; arch: string }> {
    const ua = navigator.userAgent;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const uad = (navigator as any).userAgentData as
      | { platform?: string; getHighEntropyValues?: (h: string[]) => Promise<{ architecture?: string; bitness?: string }> }
      | undefined;
    const plat = (uad?.platform || '').toLowerCase();
    let platform: Platform | null = null;
    if (/android/i.test(ua) || plat === 'android') platform = 'android';
    else if (/iphone|ipad|ipod/i.test(ua) || (/macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) platform = 'ios';
    else if (/windows/i.test(ua) || plat === 'windows') platform = 'windows';
    else if (/mac os x|macintosh/i.test(ua) || plat === 'macos') platform = 'macos';
    else if (/cros/i.test(ua) || plat === 'chrome os') platform = null;
    else if (/linux|x11/i.test(ua) || plat === 'linux') platform = 'linux';
    let arch = '';
    try {
      if (uad?.getHighEntropyValues && (platform === 'windows' || platform === 'macos' || platform === 'linux')) {
        const h = await uad.getHighEntropyValues(['architecture', 'bitness']);
        if (h.architecture === 'arm') arch = 'arm64';
        else if (h.architecture === 'x86' && h.bitness === '64') arch = 'x64';
      }
    } catch {
      /* no hint */
    }
    if (!arch && platform === 'linux') arch = /aarch64|arm64/i.test(ua) ? 'arm64' : /x86_64|amd64/i.test(ua) ? 'x64' : '';
    return { platform, arch };
  }

  // ---- manifest ----
  const str = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
  const safeUrl = (raw: string, base: URL): string | null => {
    if (!raw) return null;
    try {
      const u = new URL(raw, base);
      return u.protocol === 'https:' && u.host ? u.toString() : null;
    } catch {
      return null;
    }
  };
  function parse(json: unknown, base: URL): Partial<Record<Platform, Release>> | null {
    if (!json || typeof json !== 'object') return null;
    const plats = (json as { platforms?: unknown }).platforms;
    if (!plats || typeof plats !== 'object') return null;
    const out: Partial<Record<Platform, Release>> = {};
    for (const key of PLATFORMS) {
      const p = (plats as Record<string, unknown>)[key] as Record<string, unknown> | undefined;
      if (!p || typeof p !== 'object') continue;
      const files: RFile[] = [];
      if (Array.isArray(p.files)) {
        for (const f of p.files as Record<string, unknown>[]) {
          if (!f || typeof f !== 'object') continue;
          // A store-only file (the Android App Bundle) is never offered for download.
          if (f.listed === false || str(f.kind).toLowerCase() === 'aab') continue;
          const url = safeUrl(str(f.url), base);
          if (!url) continue;
          const sha = str(f.sha256).toLowerCase();
          const size = Number(f.size);
          files.push({
            arch: str(f.arch) || 'universal',
            kind: str(f.kind),
            url,
            size: Number.isFinite(size) && size > 0 ? size : null,
            sha256: /^[0-9a-f]{64}$/.test(sha) ? sha : null,
          });
        }
      }
      const r: Release = {
        version: str(p.version),
        releasedAt: str(p.released_at),
        minOs: str(p.min_os),
        primary: str(p.primary),
        files,
        pwa: p.pwa === true,
      };
      if (r.files.length || r.pwa) out[key] = r;
    }
    return out;
  }
  function primaryFile(r: Release, archHint: string): RFile | null {
    if (!r.files.length) return null;
    if (archHint) {
      const f = r.files.find((x) => x.arch === archHint);
      if (f) return f;
    }
    return (
      (r.primary && r.files.find((x) => x.arch === r.primary)) || r.files.find((x) => x.arch === 'universal') || r.files[0]
    );
  }
  const pwaFirst = (r: Release) => r.pwa && (!r.files.length || r.primary === 'pwa');

  // ---- drawing ----
  const guideFor: Record<Platform, string> = {
    android: '#guide-android',
    windows: '#guide-windows',
    macos: '#guide-macos',
    linux: '#guide-linux',
    ios: '',
  };

  function shaRow(f: RFile) {
    const row = el('div', 'dl-sha');
    row.append(el('span', '', d.sha));
    if (!f.sha256) {
      row.append(el('span', '', d.noSha));
      return row;
    }
    const code = el('code', '', f.sha256);
    code.dir = 'ltr';
    const btn = el('button', 'dl-copy', d.copy);
    btn.type = 'button';
    btn.setAttribute('aria-label', `${d.copy} ${d.sha}`);
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(f.sha256 || '');
        btn.textContent = d.copied;
        setTimeout(() => (btn.textContent = d.copy), 1600);
      } catch {
        const range = document.createRange();
        range.selectNodeContents(code);
        const sel = getSelection();
        sel?.removeAllRanges();
        sel?.addRange(range);
      }
    });
    row.append(code, btn);
    return row;
  }

  function metaLine(r: Release, f: RFile | null) {
    return [
      r.version ? fill(d.version, { v: r.version }) : '',
      f ? sizeLabel(f.size) : '',
      r.releasedAt ? `${d.released} ${dateLabel(r.releasedAt)}` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  }

  function drawCard(p: Platform, r: Release | undefined, isRec: boolean) {
    const card = document.getElementById(`dl-${p}`);
    if (!card) return;
    card.replaceChildren();
    card.classList.toggle('is-rec', isRec);
    const head = el('header', 'dl-card__head');
    head.append(el('h3', '', d.platforms[p]));
    if (isRec) head.append(el('span', 'dl-chip', d.recommended));
    if (!r) {
      head.append(el('span', 'dl-chip dl-chip--soon', d.soon));
      card.append(head, el('p', 'dl-card__muted', d.soonBody));
      const links = el('div', 'dl-card__links');
      links.append(link(`${app}/`, '', d.openWeb));
      card.append(links);
      return;
    }
    if (r.version) head.append(el('span', 'dl-chip', fill(d.version, { v: r.version })));
    card.append(head);
    const sub = [r.releasedAt ? `${d.released} ${dateLabel(r.releasedAt)}` : '', r.minOs ? fill(d.minOs, { v: r.minOs }) : '']
      .filter(Boolean)
      .join(' · ');
    if (sub) card.append(el('p', 'dl-card__muted', sub));
    if (!r.files.length) card.append(el('p', 'dl-card__muted', d.pwaBody));
    if (r.files.length) {
      const ul = el('ul', 'dl-files');
      ul.setAttribute('aria-label', d.files);
      for (const f of r.files) {
        const li = el('li', 'dl-file');
        const row = el('div', 'dl-file__row');
        const info = el('div');
        info.append(el('div', 'dl-file__name', fileLabel(f)));
        const size = sizeLabel(f.size);
        if (size) info.append(el('div', 'dl-file__meta', `${d.size}: ${size}`));
        const a = link(f.url, 'btn', d.downloadFile, true);
        a.setAttribute('aria-label', `${d.downloadFile} ${d.platforms[p]} ${fileLabel(f)}`);
        row.append(info, a);
        li.append(row, shaRow(f));
        ul.append(li);
      }
      card.append(ul);
    }
    const links = el('div', 'dl-card__links');
    if (r.pwa) links.append(link(`${app}/`, '', r.files.length ? d.pwaAlso : d.openWeb));
    if (r.files.length && guideFor[p]) links.append(link(guideFor[p], '', d.guide));
    if (links.childElementCount) card.append(links);
  }

  function drawRec(platform: Platform | null, arch: string, rels: Partial<Record<Platform, Release>>) {
    rec.replaceChildren();
    const actions = el('div', 'dl-rec__actions');
    if (!platform) {
      rec.append(el('p', 'dl-rec__title', d.pickDevice));
      actions.append(link('#dl-all-t', 'btn', d.files), link(`${app}/`, 'btn btn--ghost', d.openWeb));
      rec.append(actions);
      return;
    }
    const name = d.platforms[platform];
    const r = rels[platform];
    if (!r) {
      rec.append(el('p', 'dl-rec__title', fill(d.soonFor, { p: name })), el('p', 'dl-rec__meta', d.soonBody));
      actions.append(link(`${app}/`, 'btn', d.openWeb), link('#dl-all-t', 'btn btn--ghost', d.files));
      rec.append(actions);
      return;
    }
    if (pwaFirst(r)) {
      rec.append(el('p', 'dl-rec__title', fill(d.pwaTitle, { p: name })), el('p', 'dl-rec__meta', d.pwaBody));
      actions.append(link(`${app}/`, 'btn', d.openWeb));
      rec.append(actions);
      return;
    }
    const f = primaryFile(r, arch)!;
    rec.append(el('p', 'dl-rec__title', fill(d.forDevice, { p: name })));
    const meta = [metaLine(r, f), fileLabel(f)].filter(Boolean).join(' · ');
    if (meta) rec.append(el('p', 'dl-rec__meta', meta));
    const btn = link(f.url, 'btn', fill(d.download, { p: name }), true);
    actions.append(btn);
    if (guideFor[platform]) actions.append(link(guideFor[platform], 'btn btn--ghost', d.guide));
    rec.append(actions);
  }

  function drawUnavailable() {
    rec.replaceChildren();
    rec.append(el('p', 'dl-rec__title', d.unavailableTitle), el('p', 'dl-rec__meta', d.unavailableBody));
    const actions = el('div', 'dl-rec__actions');
    const retry = el('button', 'btn', d.retry);
    retry.type = 'button';
    retry.addEventListener('click', () => void load());
    actions.append(retry, link(`${app}/`, 'btn btn--ghost', d.openWeb));
    rec.append(actions);
    for (const p of PLATFORMS) {
      const card = document.getElementById(`dl-${p}`);
      if (!card) continue;
      card.classList.remove('is-rec');
      card.replaceChildren();
      const head = el('header', 'dl-card__head');
      head.append(el('h3', '', d.platforms[p]));
      card.append(head, el('p', 'dl-card__muted', d.unavailableTitle));
    }
  }

  const device = detect();

  async function load() {
    rec.replaceChildren(el('p', 'dl-rec__status', d.loading));
    let rels: Partial<Record<Platform, Release>> | null = null;
    try {
      const base = new URL(manifestUrl, location.href);
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 6000);
      const res = await fetch(base.toString(), { cache: 'no-cache', signal: ctl.signal, credentials: 'omit' });
      clearTimeout(timer);
      if (res.ok) rels = parse(await res.json(), base);
    } catch {
      rels = null;
    }
    if (!rels) {
      drawUnavailable();
      return;
    }
    const { platform, arch } = await device;
    for (const p of PLATFORMS) drawCard(p, rels[p], p === platform);
    drawRec(platform, arch, rels);
    // the recommended platform first on phones
    if (platform) {
      const card = document.getElementById(`dl-${platform}`);
      card?.parentElement?.prepend(card);
    }
  }

  // an "Install guide" link opens its guide
  const openGuide = () => {
    const g = location.hash && document.getElementById(location.hash.slice(1));
    if (g instanceof HTMLDetailsElement) g.open = true;
  };
  window.addEventListener('hashchange', openGuide);
  openGuide();

  void load();
}
