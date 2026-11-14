// Optional build-time snapshot of the public numbers. A failure here never fails the build.
export type Stats = { students: number; teachers: number; courses: number };
export type Level = { id: string | number; name_ar: string; name_en: string; courses: number };
export type Subject = Level & { levels: Level[] };
export type Options = { subjects: Subject[] };

async function getJson<T>(url: string): Promise<T | null> {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!r.ok) return null;
    return (await r.json()) as T;
  } catch {
    return null;
  }
}

export async function loadBuildData(): Promise<{ stats: Stats | null; options: Options | null }> {
  // build time (Node): the shell's LANDING_API_ORIGIN, read without pulling in @types/node
  const env = (globalThis as { process?: { env: Record<string, string | undefined> } }).process?.env ?? {};
  const origin = (env.LANDING_API_ORIGIN || '').replace(/\/+$/, '');
  if (!origin) return { stats: null, options: null };
  const base = `${origin}/api/api/v1/public/landing`;
  const [stats, options] = await Promise.all([
    getJson<Stats>(`${base}/stats`),
    getJson<Options>(`${base}/options`),
  ]);
  return { stats, options };
}
