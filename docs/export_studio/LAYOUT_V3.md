# Export layout v3 (D-142) — the shared contract

One JSON document describes an exported list file. The Flutter studio edits it; the SERVER renders it
(PDF, Word, Excel) and also renders the preview pages, so the preview IS the file. Both repos hold this file
(front `docs/export_studio/LAYOUT_V3.md`, back `docs/export_layout_v3.md`); change both together.

## Why (root causes of the old studio, 2026-11-01 audit)
1. The "Standard" preview was an imitation drawn by one code path while the file came from separate table writers.
2. Word merged positioned blocks into bands (y gaps → spacing, overlaps and fixed heights lost).
3. Excel printed only text blocks as lines above the table (logos, signatures, positions dropped silently).
4. PDF block heights were only minimums (text grew instead of clipping like the canvas).
5. The export-time font silently replaced the design's font.
6. Two unit systems (content-box fractions vs 1000-unit cert space vs mm in the studio).
v3: one model, mm everywhere, one renderer (server), preview = rendered pages, explicit "can't do in Excel" notes.

## Units and coordinates
All lengths in millimetres (floats). Element x/y are from the TOP-LEFT of their band (physical left, also in
RTL designs: each language has its own design, the designer mirrors the starter for Arabic). Font size in pt.
Colours `#RRGGBB` (or `#AARRGGBB`). A band's width is the page content width (page width − margins).

## Document
```json
{
  "schema_version": 3,
  "format": "pdf | docx | xlsx",
  "languages": ["ar"] | ["en"] | ["ar","en"],          // "both" = two files (zip) or two sheets
  "designs": { "ar": Design, "en": Design },           // independent per language
  "source": { "dataset": "course.students", "params": {...} }   // or {"rows_upload": "<upload id>"}
}
```

## Design
```json
{
  "page": {"size": "A4|A3|Letter", "orientation": "portrait|landscape",
           "margins": {"top":15,"right":12,"bottom":15,"left":12}, "rtl": true,
           "font": "<catalog font id>", "font_size": 10, "background": null},
  "mode": "list | table | custom",
  "header": Band,          // placement: "first_page" | "every_page"
  "footer": Band,          // placement: "after_items" | "every_page"
  "before_items": Band?,   // flows once, right before the items (titles, filters used)
  "after_items": Band?,    // flows once, after the items (signatures, totals text, stamps)
  "list":  {"fields": [FieldRef], "separator": " · ", "numbered": true, "style": Style},
  "table": {"columns": [{"field": FieldRef, "width": 30, "align": "start|center|end", "style": Style}],
            "header_style": Style, "zebra": "#F3F6F9", "borders": Border, "repeat_header": true},
  "row":   RowTemplate,    // mode = custom
  "sort":  [{"field": "name", "dir": "asc|desc"}],
  "group": {"field": "class", "header": Band?} ,       // optional; header band repeats per group ({{group}} var)
  "totals": [{"field": "score", "fn": "sum|avg|count|min|max", "label": "Total"}],
  "watermark": {"text": "...", "opacity": 0.08, "angle": 45, "font_size": 60} ,
  "frame": Border?         // page border
}
```

## Band
`{"height": 30, "placement": "...", "elements": [Element], "background": null}`

## RowTemplate (custom mode: ONE item's block, repeated)
```json
{"height": 22, "per_line": 1 | 2 | 3, "gap": 3,             // cards per line, gap between cards (mm)
 "elements": [Element], "zebra": "#F7F9FB"?, "separator": Border?, "background": null,
 "border": Border?, "radius": 2, "keep_together": true}
```
Card width = (content width − gap·(per_line−1)) / per_line. Elements are placed inside one card.

## Element
```json
{"id": "e1", "kind": "text | field | image | line | rect | badge | qr | page_number | signature",
 "x": 0, "y": 0, "w": 40, "h": 8, "rotation": 0, "locked": false, "name": "Student name",
 "value": "Name:",                              // static text / image upload id / qr text (vars allowed)
 "bind":  {"field": "name", "format": "text|upper|lower|title|number|integer|percent|currency|date|datetime",
           "decimals": 2, "currency": "EGP", "date_pattern": "yyyy-MM-dd",
           "prefix": "", "suffix": "", "empty": "—"},          // kind=field (dynamic)
 "computed": {"op": "index | concat", "fields": ["first","last"], "sep": " "},   // optional
 "rules": [ {"when": [{"field": "score", "op": ">=", "value": 50}], "match": "all|any",
             "then": {"show": true, "text": "Pass", "color": "#1B7F3A", "bg": "#E5F5EA", "icon": "check"}} ],
 "else":  {"show": true, "text": "Fail", "color": "#B42318", "bg": "#FDECEA"},
 "style": Style}
```
- Element types (the studio's switch): STATIC = text/image/line/rect with `value`; DYNAMIC = `kind:"field"` with `bind`;
  CONDITIONAL = any element with `rules` (+ `else`); COMPUTED = `computed`.
- Rule ops: `= != > >= < <= contains not_contains empty not_empty in`. Rules are evaluated per item ON THE SERVER,
  first match wins, `else` when none matches; `show:false` hides the element (not the row).
- Variables in any text: `{{date}} {{exporter}} {{org_name}} {{total}} {{page}} {{pages}} {{title}} {{filters}} {{group}}`.
- `signature`: `value` = image upload id, plus `style` name/title lines in `sig_name`, `sig_title`.
- Images: upload ids from `POST /api/v1/exports/layout/assets` (PNG/JPEG ≤ 2 MB), `fit: contain|cover|fill`.

## Style
`{"font": null, "size": 10, "weight": 400|700, "italic": false, "color": "#1A1A1A", "bg": null,
  "align": "start|center|end", "valign": "top|middle|bottom", "padding": 1, "border": Border?, "radius": 0,
  "wrap": true, "max_lines": 0, "dir": "auto|rtl|ltr"}`  — text that does not fit is CLIPPED to the box
(ellipsis when max_lines is set), exactly as the canvas shows it. `font: null` = the page font. The
design's fonts are used as-is: the export never substitutes a different font.
`Border = {"width": 0.3, "color": "#D0D5DD", "style": "solid|dashed"}`.

## Rendering rules per format
- PDF (reportlab): absolute placement of every band and element, Arabic shaped (arabic_reshaper + bidi), fonts
  embedded, keep_together moves a row/card to the next page, header/footer every_page repeat, pages N/M.
- Word (hand-written WordprocessingML): a band or row card becomes a fixed-layout table built from the CUT GRID:
  every distinct x edge of the elements makes a column, every distinct y edge a row; an element spans the cells it
  covers (gridSpan / vMerge) and exact heights are kept (`w:trHeight hRule=exact`). every_page bands go into the
  header/footer parts. Overlapping elements cannot be represented: the later one moves under the earlier one and the
  studio warns ("overlaps are kept in PDF only").
- Excel (openpyxl, write-only): list/table → one column per field. Custom → the same cut grid per row block: grid
  columns become sheet columns (width from mm), each item takes the grid's rows, elements become merged cells with
  their style; conditional styles applied per cell; RTL sheet for Arabic; frozen header; images only in header
  (logos). Not representable in Excel (the studio shows these in a note with the closest alternative): rotation,
  overlaps, per_line > 1 (becomes 1 card per line), watermark (becomes header text), qr (becomes its text),
  every_page footer elements other than text (become sheet footer text).
- Every text cell is formula-safe (helpers/xlsx_safe.is_risky → quote prefix). Control characters are stripped.

## Server API (all under /api/v1/exports/layout, auth required)
- `POST /validate` {document} → {ok, issues:[{code, element, format, message_ar, message_en}]} (incl. Excel notes)
- `POST /preview` {document, lang, pages:"first,middle,last", sample:200} → {pages:[{index, total, png_b64}], issues}
- `POST /rows` (multipart / JSON, ≤ 50 000 rows, ≤ 20 MB) → {upload_id}  — rows of an app table with no server dataset
- `POST /assets` (image) → {asset_id}
- `POST /runs` {document, name} → 202 {run_id} — background job (ExportRun), streams rows, progress
- `GET /runs/{id}` → {status, progress (0-100), rows, error}; `GET /runs/{id}/download`; `POST /runs/{id}/cancel`
- Templates reuse `/api/v1/exports/templates` with `schema_version: 3` and `design` = the whole document minus `source`.
Permissions: a dataset source runs the dataset's own check (services/export_datasets); an uploaded rows source
belongs to its uploader only (owner check on every use, expires after 24 h).

## Studio interaction (both studios, shared engine lib/design/studio/)
Single click = select + properties in the docked side panel (bottom sheet on phones, non-blocking). Double click
(web/desktop) or long-press (touch) on text = inline edit on the canvas; Enter / click outside confirms, Esc cancels.
Drag, 8 handles, arrows nudge (shift ×10), snap guides, multi-select (shift/ctrl click, marquee), copy/paste/duplicate,
Delete, undo/redo, zoom, right-click menu (duplicate, delete, bring forward/back, lock).

## Server notes and clarifications (back implementation, 2026-11-01)
Filled in by the server where the contract above was silent; the app should follow them (copy to the front file).
- **FieldRef** = `"key"` or `{"field": "key", "label": "…"?, + the Bind format keys}` (`format`, `decimals`, `currency`,
  `date_pattern`, `prefix`, `suffix`, `empty`). A list field with a `label` prints `label: value`.
- **Fixed heights** (nothing grows; this is what makes page N/M and Word's exact rows possible): optional
  `list.row_height`, `table.row_height`, `table.header_height` (mm); default = font size × 1.3 × (max_lines or 1) +
  2 × padding. Group header without a band: one bold 8 mm line with the value. Totals: table → a row under the
  columns (the first label in the first column that has no total); list / custom → one line `Label: value · …`.
  `{{total}}` = the number of items.
- **Directions:** table columns are in READING order (a right-to-left page puts the first column on the right; Word
  `bidiVisual`, Excel RTL sheet); custom cards fill a line from the right in a right-to-left page. Element x / y stay
  physical. Style `align` start / end resolve by the page direction (as the canvas' Directionality), `dir: auto`
  sets only the bidi base: left-to-right for text with no Arabic, right-to-left for Arabic text on an RTL page.
- **Fonts:** the catalog leaves out Scheherazade New, Reem Kufi and Aref Ruqaa (their files carry no Arabic
  presentation forms and the renderer has no OpenType shaping). A glyph the design's font lacks (Arabic in a Latin
  font) is drawn with Amiri, run by run, and validate() says so (`font_no_arabic`). Word names the fonts (no
  embedding: `fonts_named` note); Excel names them.
- **Elements:** a `line` is drawn through the middle of its box, horizontal when w ≥ h (Word / Excel: the cell's top
  or left border). `fit`, `sig_name`, `sig_title` are element keys. `else` applies only to an element with `rules`.
  Rule `then` may also carry `bold`. `watermark.color` (default #808080).
- **keep_together: false** splits a card line across the page break (PDF, each part clipped); Word lets the rows split.
- **Excel images:** bands may hold images (anchored to their merged cell); per-item images are dropped (`image_rows`).
- **Assets:** the uploader owns them; a design naming an asset id renders it for whoever renders that design (the id
  is a random 128-bit token), so organization templates keep their logo.
- **Documents may carry `name`** (the run's file name). Runs: status `canceled` added; `progress` 0-100.
- Response shapes and codes: back `FLUTTER_API_CHANGES.md` ("Export layout v3").
