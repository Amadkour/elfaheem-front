// One-off generator for the committed brand images (run: npm run assets).
// Source: the Flutter app's assets/images. Output is committed, the build does not need it.
import sharp from 'sharp';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = path.resolve(here, '../../assets/images');
const pub = path.resolve(here, '../public');
const assets = path.resolve(here, '../src/assets');
await mkdir(pub, { recursive: true });
await mkdir(assets, { recursive: true });

const png = { compressionLevel: 9, palette: true, quality: 90 };
await sharp(`${src}/logo_mark.png`).resize({ width: 270 }).png(png).toFile(`${assets}/logo_mark.png`);
await sharp(`${src}/logo.png`).resize(512, 512, { fit: 'contain', background: '#ffffff00' }).png(png).toFile(`${pub}/logo-512.png`);

// Favicons from the app icon.
const icon = sharp(`${src}/app_icon.png`);
await icon.clone().resize(32, 32).png(png).toFile(`${pub}/favicon-32.png`);
await icon.clone().resize(180, 180).png(png).toFile(`${pub}/apple-touch-icon.png`);
const ico48 = await icon.clone().resize(48, 48).png().toBuffer();
// Single-image ICO that wraps a PNG.
const head = Buffer.alloc(22);
head.writeUInt16LE(0, 0); head.writeUInt16LE(1, 2); head.writeUInt16LE(1, 4);
head[6] = 48; head[7] = 48; head.writeUInt16LE(1, 10); head.writeUInt16LE(32, 12);
head.writeUInt32LE(ico48.length, 14); head.writeUInt32LE(22, 18);
await writeFile(`${pub}/favicon.ico`, Buffer.concat([head, ico48]));

// Open Graph card 1200x630: brand gradient + logo.
const bg = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0a5642"/><stop offset="1" stop-color="#0f7b5f"/></linearGradient></defs><rect width="1200" height="630" fill="url(#g)"/><circle cx="1050" cy="90" r="220" fill="#34a883" opacity=".25"/><rect x="0" y="600" width="1200" height="30" fill="#c98a3d"/></svg>`,
);
const card = await sharp(`${src}/logo_mark.png`).resize({ width: 520 }).png().toBuffer();
const plate = await sharp({ create: { width: 640, height: 400, channels: 4, background: '#ffffff' } })
  .composite([{ input: card, gravity: 'center' }])
  .png()
  .toBuffer();
await sharp(bg).composite([{ input: plate, gravity: 'center' }]).png({ compressionLevel: 9, palette: true }).toFile(`${pub}/og.png`);
console.log('assets written');
