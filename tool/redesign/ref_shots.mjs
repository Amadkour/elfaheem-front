// Usage: serve docs/redesign/design on :8765, then `node tool/redesign/ref_shots.mjs`
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const md = fs.readFileSync(path.join(root, 'docs/redesign/SCREENS.md'), 'utf8');
const out = path.join(root, 'docs/redesign/ref');
const BASE = process.env.BASE || 'http://localhost:8765/';
const CONC = 5;

const rows = [];
let section = '', secIdx = 0;
for (const line of md.split(/\r?\n/)) {
  if (line.startsWith('## ')) {
    section = line.slice(3).trim(); secIdx++;
    continue;
  }
  const m = line.match(/^\|\s*(\d+)\s*\|(.*)\|\s*`([^`]+\.html[^`]*)`\s*\|\s*$/);
  if (!m) continue;
  const slugMatch = section.match(/\(([a-z0-9_-]+)\)\s*$/i);
  const slug = slugMatch ? slugMatch[1].toLowerCase() : 'sec' + secIdx;
  const url = m[3];
  const [file, query = ''] = url.split('?');
  const base = file.replace(/\.dc\.html$/, '').replace(/\.html$/, '').replace(/[^A-Za-z0-9_-]/g, '_');
  const props = query.replace(/[^A-Za-z0-9=&_-]/g, '').replace(/[=&]/g, '-').replace(/-+/g, '-');
  const n = String(m[1]).padStart(3, '0');
  const stem = `${n}_${base}${props ? '_' + props : ''}`;
  rows.push({ section, sectionSlug: slug, number: +m[1], title: m[2].trim(), url,
    phone: `${slug}/${stem}.phone.png`, web: `${slug}/${stem}.web.png` });
}
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'index.json'), JSON.stringify(rows, null, 1));
console.log('rows', rows.length);

const sizes = [
  ['phone', { width: 390, height: 844 }, 2],
  ['web', { width: 1360, height: 900 }, 1],
];
const failures = [];
let done = 0, written = 0;
const jobs = [];
for (const r of rows) for (const [k] of sizes) jobs.push([r, k]);

const browser = await chromium.launch();
const ctxs = {};
for (const [k, vp, dsf] of sizes) ctxs[k] = await browser.newContext({ viewport: vp, deviceScaleFactor: dsf });

async function worker() {
  const pages = {};
  for (const [k] of sizes) pages[k] = await ctxs[k].newPage();
  while (jobs.length) {
    const [r, k] = jobs.shift();
    const file = path.join(out, r[k]);
    done++;
    if (fs.existsSync(file)) continue;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const page = pages[k];
    try {
      await page.goto(BASE + r.url, { waitUntil: 'networkidle', timeout: 30000 });
      await page.evaluate(() => document.fonts && document.fonts.ready);
      await page.waitForTimeout(1200);
      await page.screenshot({ path: file });
      written++;
    } catch (e) {
      failures.push(`${r.url} [${k}] ${String(e.message).split('\n')[0]}`);
    }
    if (done % 50 === 0) console.log(done, '/', rows.length * 2);
  }
}
await Promise.all(Array.from({ length: CONC }, worker));
await browser.close();
fs.writeFileSync(path.join(out, 'failures.txt'), failures.join('\n') + (failures.length ? '\n' : ''));
console.log('written', written, 'failures', failures.length);
