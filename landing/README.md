# NextBrain landing site

The public, static landing site of https://nextbrain.site (Arabic first, English too). It is
**not** Flutter: Astro with static output, no client framework, one small vanilla TypeScript script.
The Flutter web app lives under `/app/`.

## Run

```bash
cd landing
npm ci
npm run dev        # http://localhost:4321/ar/
npm run build      # -> dist/
npm run preview
npm run assets     # regenerates the committed logo / favicon / og.png from ../assets/images (needs sharp)
```

Production build (atomic swap, keeps `dist-prev/` for rollback, uses Docker when node is missing):
`scripts/build_landing.sh`. `LANDING_API_ORIGIN=https://nextbrain.site` bakes the public stats and
subject options in at build time (optional; a failed fetch never fails the build). Without it the
page fetches them in the browser and shows "—" until they arrive.

## URL map (nginx)

| URL | Source |
| --- | --- |
| `/` | `dist/index.html`: language chooser. First forwards legacy app URLs (`#/…` hash, installed PWA) to `/app/`, then redirects to `/ar/` or `/en/` (saved choice, else browser language, else Arabic) |
| `/ar/`, `/en/` | the landing (`src/components/Landing.astro`); the `#/` hash forward is also in their `<head>` |
| `/privacy/`, `/terms/` | the Privacy policy / Terms of service in English (`src/components/LegalPage.astro`, D-308): the URLs given to Google's OAuth verification and the stores, real HTML |
| `/ar/privacy/`, `/en/privacy/`, `/ar/terms/`, `/en/terms/` | the same pages per language. Text: `src/content/legal/*.json`, a copy of the backend's `data/legal/` (`back/scripts/contract/export_legal.py --front <front>`); with `LANDING_API_ORIGIN` the build reads the live, possibly edited text |
| `/ar/download/`, `/en/download/` | the downloads page (`src/components/DownloadPage.astro` + `src/scripts/download.ts`): reads `/releases/releases.json` (the manifest the app reads, D-137) in the browser, recommends this device's file, lists version / size / date / SHA-256 per file, "coming soon" for a platform with no entry, an "unavailable" state when the manifest cannot be read; install guides are static HTML |
| `/sitemap.xml`, `/robots.txt`, `/og.png`, icons | `public/` |
| `/app/…` | the Flutter web build (login, explore, register, start/institution) |
| `/api/api/v1/public/landing/{stats,options,match,highlights}` | backend, same origin, plain `fetch`, 4 s timeout, fails soft. On another host (Firebase Hosting) set `PUBLIC_LANDING_API_BASE=https://nextbrain.site` at build time (absolute origin, no trailing slash) so every landing call goes there; `/app/...` links stay relative |

## Where content lives

- Text: `src/i18n/ar.ts` and `src/i18n/en.ts` (`en.ts` is typed against `ar.ts`, so a missing key fails the build type check).
- Site origin, app path, API prefix: `src/config.ts`. The sitemap is `public/sitemap.xml` (edit by hand if a URL is added).
- Colors, dark theme: CSS custom properties in `src/styles/global.css` (the app theme's palette). Logical properties only, so one stylesheet serves RTL and LTR.
- Fonts are self-hosted through `@fontsource` (IBM Plex Sans Arabic on `/ar/`, Inter on `/en/`), no third-party request.
- Hero sentence, live numbers, sticky CTA and app prefetch: `src/scripts/landing.ts`.

## Testimonials

`src/content/testimonials.json` ships as `[]` and the section is not rendered while it is empty.
Shape of an entry: `{ "name", "role_ar", "role_en", "quote_ar", "quote_en" }`. Add only real,
permitted quotes. See `src/content/README.md`.
