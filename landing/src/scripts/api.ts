// The landing's one fetch helper: plain fetch, a 4 s timeout, fails soft (null). After a 429 no call is made until
// Retry-After has passed (default 60 s, at most 300 s), so a rate-limited page keeps its defaults and never loops.
export type GetJson = <T>(path: string) => Promise<T | null>;

export function makeApi(base: string): { getJson: GetJson; blocked: () => boolean } {
  let blockedUntil = 0;
  const getJson = async <T>(path: string): Promise<T | null> => {
    if (Date.now() < blockedUntil) return null;
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 4000);
    try {
      const r = await fetch(base + path, { signal: ctl.signal, headers: { Accept: 'application/json' } });
      if (r.status === 429) {
        const s = parseInt(r.headers.get('Retry-After') || '', 10);
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
  return { getJson, blocked: () => Date.now() < blockedUntil };
}
