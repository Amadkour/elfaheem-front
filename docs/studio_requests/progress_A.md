# Agent A — certificate studio (editor + server renderer)

Branches `feature/studio-cert` in `wt-front-cert` and `wt-back-cert` (from `feature/studio-requests`).
States: done / partial / not started. Each entry: what, files, next.

## Field and design keys (the contract both sides follow)

No column changes. Every new property lives in the existing JSON: a field's keys in `fields` / `fields_en`, a page's in
`theme` / `theme_en`. Every key is optional; its default draws exactly what an old design drew. The app sends a key
only when it is not the default.

Field keys (every kind unless said):

| key | type / range | default | meaning |
|-----|--------------|---------|---------|
| `name` | str ≤ 80 | null | layer name (layers panel) |
| `locked` | bool | false | editor only: cannot be moved / resized / deleted |
| `aspect_lock` | bool | null | editor only: null = per kind (images keep their ratio) |
| `rotation` | -360…360 degrees | 0 | clockwise, about the centre of the field's box |
| `weight` | `normal` / `bold` | normal | text: the font's bold file when the catalog has one (`<key>_bold`, `tajawal_medium` → `tajawal_bold`), else a stroke of `max(1, round(size_px × 0.03))` px |
| `italic` | bool | false | text: `playfair` → `playfair_italic`, `cormorant` → `cormorant_italic`; an italic font stays; else a slant (shear 0.2, top leans to the right, about the block's centre) |
| `underline` | bool | false | text: a bar under each line, thickness `max(1, size × 0.05)`, `0.08 × size` under the baseline |
| `line_height` | 0.8…3.0 | null | text: line advance = size × line_height; null = the old rule (renderer: font ascent + descent × 1.12 / 1.18 Arabic) |
| `direction` | `auto` / `rtl` / `ltr` | auto | text: the paragraph direction (auto = Arabic letters → rtl) |
| `bg_color` | `#RRGGBB` | null | text: box fill |
| `bg_opacity` | 0…1 | 1 | text: box fill opacity (× `opacity`) |
| `border_color` | `#RRGGBB` | null | text: box outline colour (drawn when `border_width` > 0) |
| `border_width` | 0…20 | 0 | text: outline width, logical units, inside the box |
| `radius` | 0…200 | 0 | text: box corner radius |
| `padding` | 0…100 | 0 | text: the text sits `padding` inside the box on every side |
| `shadow_color` | `#RRGGBB` | null | text: drop shadow (null = none) — of the box when it has a fill, else of the glyphs |
| `shadow_blur` | 0…40 | 6 | blur, logical units |
| `shadow_dx`, `shadow_dy` | -50…50 | 0, 3 | offset, logical units |
| `shadow_opacity` | 0…1 | 0.35 | |
| `fit` | `contain` / `cover` / `fill` | contain | logo / signature: how the image fills its w × h box |

Text box: `(x, y)` is the box's top-left, `w` its width; the text is laid out `padding` inside it; the box height is
`2 × padding + lines × line advance` (`h` stays 0). Rotation turns the whole drawn field (box, text, captions).

Theme keys (per language, `theme` / `theme_en`):

```
page:      {"size": "a4" | "letter" | "custom", "w_mm": 50…1000, "h_mm": 50…1000}
           logical long side 1000, short side = round(1000 × short_mm / long_mm) (a4 → 707, letter → 773),
           the short side at least 300; the `orientation` column still says which side is long. Missing = a4.
watermark: {"kind": "text" | "image", "text": str ≤ 200, "src": image URL, "color": "#RRGGBB", "font": font key,
            "opacity": 0…1 (0.12), "rotation": -180…180 (-30), "size": text font size (96) | image width as a
            fraction of the page width (0.5), "position": "center" | "top" | "bottom" | "tile"}
           drawn over the background and under every field.
```

## Tasks

Front `lib/` paths are under `lib/features/certificates/designer/` (D/) unless said; back paths are in
`wt-back-cert`. Back commits afa6081, 3d3ddba, b73b7bb; front ad49988 onwards.

| # | Task | State | Files | Notes / next |
|---|------|-------|-------|--------------|
| 1 | Docked properties panel at every width | done | D/certificate_designer_screen.dart (`_Editor`, `CertDockPanel`) | ≥ 1100 three columns; ≥ 600 page + properties docked on the end side; phone: the page above a NON-modal panel (folds to a 52 px header), selecting an element opens it and `StudioController.reveal` pans the page so the element stays above it. The "works best on a tablet" gate and the modal properties sheet are gone. |
| 2 | Resize: aspect-lock toggle; 8 handles / W×H / min size on phones | done | models (`aspect_lock`, `keepsAspect`), cert_studio_adapter.dart (`certResizeOfField`), D/cert_designer_panels.dart (switch; W/H keep the ratio while locked) | logo / signature unlock → free resize (8 handles where the box is ≥ 72 px on touch). Test "resize on a phone". |
| 3 | Text controls (model + panel + renderer) | done | models, cert_text_layout.dart (new), cert_canvas_item.dart (`CertTextView`), panels (Text style / Box / Shadow sections); back renderer + schemas + sanitize | weight, italic, underline, line height (Auto = the font's own), direction, fill + opacity, border colour / width, radius, padding, shadow (colour, blur, offset, opacity). |
| 4 | Image fit / crop / rotation; 3 signatures | done | panels (fit, Crop), screen (`_cropFieldImage`: the current image → `showAppImageCropper` → uploaded as the field's own), provider `cropFieldImage`; engine rotation (StudioItem.rotation) | Rotation for every kind, editor and renderer. A turned element moves but shows no handles (size via W/H). 3-signature regression: front `cert_studio_test.dart`, back `cert_studio.py` (pixel colour per field). |
| 5 | Layers: show/hide, lock, rename, reorder | done | panels (`CertLayersList` lock button, Layer section: name + lock), adapter (locked items) | Hidden = not drawn (canvas + renderer); locked = no move / resize / delete / nudge. |
| 6 | Rulers, grid, snap-to-grid; autosave | done | lib/design/studio/studio_canvas.dart (`_GridPainter`, `_RulerPainter`), studio_controller.dart (`setGrid`, `showRulers`, `reveal`), CertToolbarRow View menu; provider autosave (`CertDraftStore`, 1.5 s debounce, SharedPreferences) | The draft is restored when the server copy is still the version it was made on, with a "restored" notice + Discard; a save or Discard removes it. |
| 7 | Duplicate, default, sample-data preview | done | D/certificate_designs_screen.dart (Duplicate, Make default, Default + language chips), screen `CertPreviewDialog` + `CertSampleDataForm`; back `assign(apply_all)` clears the scope's other default | |
| 8 | Page A4 / Letter / custom + orientation | done | models (`CertPage`, `certPageLogical`), provider `setPage` (rescales; an English design that follows the Arabic theme follows), panels `CertPaperControl`; back `page_logical`, PNG dpi, PdfStream dpi | |
| 9 | 2.1.1 round trip test | done | front `test/org/cert_studio_test.dart` (2.1.1 group), back `tests/org_v2/cert_studio.py` | |
| 10 | 2.1.4 parity test | done | `test/org/cert_parity_test.dart` over `test/fixtures/cert_parity/parity.json` (back `scripts/contract/dump_cert_parity.py`, run in the API image for Raqm) | The drift it found: the editor drew every line at 1.15 × size, the renderer at the font's ascent + descent × 1.12 / 1.18 (Amiri 1.76, Cairo 1.87 …): Arabic boxes were up to 45 % short, and multi-line text never shrank. Fixed (cert_text_layout.dart). 20/20 elements within tolerance. |
| 11 | Template gallery; certificate watermarks | done | back `certificate_draft_service.py` (5 templates × ar / en), routes `GET /certificate-designs/templates`, `POST …/templates/{key}`; front wizard `_TemplateStrip`, `CertTemplateCard`; watermark `CertWatermark`, `CertWatermarkView`, `CertWatermarkControl` | |

Tests: front `test/org/cert_studio_test.dart`, `test/org/cert_parity_test.dart`, `test/ui/cert_studio_layout_test.dart`
(+ updated `cert_designer_v2_test.dart`); visual `test/visual/cert_designer_golden_test.dart` → `test/visual/goldens/
cert_designer_{page,text}_{390,1440}_{ar,en}_{light,dark}.png`. Back `tests/org_v2/cert_studio.py`.

Known limits: a turned element has no resize handles (W / H in its properties); the canvas underline sits where the
font puts it (the renderer's bar is 0.08 × size under the baseline: a few px apart); image shadows are not offered
(text only); the parity fixture must be regenerated in the API's Docker image after a renderer change.
