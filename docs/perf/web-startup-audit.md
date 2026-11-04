# Web routing + cold start — audit (2026-11-04, before any change)

Measured on production `https://nextbrain.site/login`, Chrome (playwright), cache disabled, 390×844, from the
dev PC (link ≈ 8–9 Mbit/s to the server). Back-button behaviour on a profile build against the local stack.

## Numbers (before)

| what | value |
|---|---|
| TTFB / HTML splash first paint | 0.74 s / 1.24 s |
| Flutter first frame (`flutter-first-frame`) | **49 s** |
| network idle (real app on screen) | ≈ 58 s |
| requests / bytes | 57 / 24.7 MB |
| `main.dart.js` | 18.2 MB raw, **sent uncompressed**, HTTP/1.1, 17 s; gzip -9 would be 5.1 MB |
| JS parse + start after download | ≈ 6 s (17.4 s → next request at 23.4 s) |
| fonts before the first frame | 3.5 MB, 17 files, uncompressed |
| CanvasKit | gstatic CDN, h2 + brotli, 1.5 MB, finished at 4–7 s (parallel; not the bottleneck) |

## Causes, ranked by impact

1. **No compression for JS / wasm / fonts / JSON** (nginx gzips HTML only). 18.2 MB → ~5 MB gzip / less with brotli.
2. **HTTP/1.1**: ~40 asset requests queue on 6 connections (MaterialIcons waited 23 s). nginx 1.24 needs `http2`.
3. **One 18.2 MB bundle, no deferred parts**: every role downloads and parses admin (1.1 MB), org (2.7 MB), teacher /
   live room (1.4 MB), export studios (0.9 MB), exam authoring … ≈ 6 s of parse/start on top of the download.
   `timezone` embeds every zone (836 KB).
4. **Fonts loaded eagerly**: FontManifest lists PaperPlex 473 KB, bahji 300 KB, tajawal 294 KB, the other language's
   UI family (≈ 800 KB), moyasar's ReadexPro 588 KB (6 weights) — the first frame needs ≈ 1 MB.
5. **No cache headers worth the name**: `main.dart.js` is `no-cache` and not content-hashed; assets have none.
6. **Start-up chain after the first frame**: translation.json (623 KB raw) and sequential init steps (Firebase,
   Remote Config, connectivity) before the real app; the theme call holds the first real frame up to 30 s on a
   first visit (cached palette afterwards).
7. **index.html**: two synchronous scripts in `<head>` before the splash (`video_protection.js`,
   `recorder_compositor.js` 59 KB), a duplicated first-frame listener. The HTML splash itself already exists.

## Routing (before)

- Navigator 1 (`onGenerateRoute` switch, ~30 named routes), path URL strategy already on, 360 anonymous
  `MaterialPageRoute` pushes in 178 files, role tabs with their own navigators (D-081).
- The root `MaterialApp` pins Flutter's **single-entry** browser history: the URL never changes inside a role home,
  `history.length` never grows, and Back = one system back, else leave. Reproduced: teacher → My courses → Add a course
  → Back landed on the Home tab, the next Back left to about:blank.

Fix: D-170 (routing) and the perf work tracked in `docs/perf/deferred-loading.md` and the build / nginx changes.
