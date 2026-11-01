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

| # | Task | State | Files | Next |
|---|------|-------|-------|------|
| 1 | Docked properties panel at every width | not started | | |
| 2 | Resize: aspect-lock toggle, handles on phones | not started | | |
| 3 | Text controls (model + panel + renderer) | not started | | |
| 4 | Image fit / crop / rotation; 3 signatures regression | not started | | |
| 5 | Layers: show/hide, lock, rename, reorder | not started | | |
| 6 | Rulers, grid, snap-to-grid; autosave draft | not started | | |
| 7 | Duplicate, default, sample-data preview | not started | | |
| 8 | Page sizes A4 / Letter / custom + orientation | not started | | |
| 9 | 2.1.1 round-trip test (ar + en, every format value) | not started | | |
| 10 | 2.1.4 parity test (server boxes vs Flutter canvas) | not started | | |
| 11 | Template gallery; certificate watermarks | not started | | |
