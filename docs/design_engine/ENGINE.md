# Design engine (layout v4, D-164 / D-165) — the shared contract

ONE design engine for every printed / exported thing: data exports, certificates, exam papers, exam covers,
bubble sheets, the user-guide export. It is the export layout v3 document (`docs/export_studio/LAYOUT_V3.md`,
still valid: v4 only ADDS keys) plus document-level computed fields, a page-per-item mode, list columns, grids,
page breaks and the style keys certificates need. The Flutter editor edits it; the SERVER renders it (PDF, Word,
Excel, PNG) and renders the preview, so the preview IS the file.

Both repos hold this file (front `docs/design_engine/ENGINE.md`, back `docs/design_engine.md`); change both.

## Versions
- `schema_version` 4 = 3 + the keys below. The server accepts 3 and 4 and writes back the version it was sent;
  a v3 document is a v4 document that uses none of the new keys. Older apps keep unknown keys (`extra`), so a
  v4 template survives an edit in an older app.

## Document additions
```json
{
  "schema_version": 4,
  "purpose": "export | certificate | exam_paper | exam_cover | bubble_sheet | guide",   // default "export"
  "computed": [ComputedField]            // ≤ 30, language-independent, evaluated in this order
}
```

### ComputedField — "computed columns" (a visual rule builder, never code)
```json
{"key": "calc.result",                 // must start with "calc." (never collides with a source column)
 "label_ar": "النتيجة", "label_en": "Result",
 "type": "text | number | date",
 "cases": [ {"when": Group, "value": Expr} ],   // ≤ 20, first match wins
 "else": Expr | null}                           // null = empty
```
- `Group = {"match": "all" | "any", "items": [Cond | Group]}` — depth ≤ 3, ≤ 10 items per group. An empty group
  matches everything (`cases: [{"when": {"match":"all","items":[]}, "value": …}]` = "always set").
- `Cond = {"field": "score", "op": "=", "value": 50}` — ops are the rule ops (`= != > >= < <= contains
  not_contains empty not_empty in`; `starts_with`, `ends_with` added in v4). `field` may be a source column or an
  EARLIER computed key (so no cycles). Comparisons: both sides numeric → numbers; both dates (ISO) → dates; else
  case-insensitive text (Arabic letters compared after removing tatweel and diacritics).
- `Expr` is ONE of (depth ≤ 4, ≤ 10 args):
  - `{"text": "Pass"}` — a constant
  - `{"number": 5}`
  - `{"field": "score"}` — a column / earlier computed value
  - `{"concat": [Expr…], "sep": " "}` — empty parts skipped
  - `{"math": "+ | - | * | / | min | max | round | abs | percent", "args": [Expr…]}` — `round` = [x, decimals];
    `percent` = [part, whole] → part ÷ whole × 100; a non-numeric arg or ÷ 0 → empty.
- The value of a computed key is available EVERYWHERE a field is: bind, list fields, table columns, rules, sort,
  group, totals, `{{calc.x}}` in item text. It is NOT a source column: `referenced_fields` reports the source
  columns its conditions / expressions read (what the file may reveal), never the `calc.` key.
- Evaluated on the server per row, before sort / group / totals (`services/export_layout/computed.py`). The app
  mirrors the evaluator for its row preview (`lib/design/export_layout/layout_computed.dart`), checked against the
  server's answers (parity fixture `test/fixtures/design_engine/computed_parity.json`).

## Design additions
```json
{
  "page": {"size": "A4 | A3 | A5 | Letter | custom", "width": 210, "height": 297,   // width/height: custom only
           "background_image": "<asset id | allowed image URL>", "background_fit": "cover | contain | fill"},
  "mode": "list | table | custom | page",
  "list":  {"columns": 1, "column_gap": 6, "items_per_page": 0},
  "table": {"items_per_page": 0},
  "row":   {"per_line": 1, "per_page": 0, "fill_page": false},
  "group": {"page_break": false}
}
```
- **mode `page`** — one page per item (certificates, exam covers, per-student sheets). Uses `row.elements`, placed
  from the top-left of the CONTENT box (page − margins; certificates use margins 0). `row.height` is ignored (the
  card is the content box). Header / footer bands still print on every page; before / after items bands are
  ignored. Word: one page per item (page break). Excel: not offered for `page` (validate: `page_mode_xlsx`).
- **list.columns** 1–4 — newspaper columns: on each page the lines fill column 1 top to bottom, then column 2 …
  (reading order: a right-to-left page starts on the right). `column_gap` mm. Word: a section with N columns.
  Excel: one column per field as before (note `list_columns_xlsx`).
- **items_per_page** (list / table) — 0 = as many as fit; N = a page break after every N items.
- **row.per_line** now 1–4. **row.per_page** — 0 = as many as fit; N = a page break after N cards (2×2 grid =
  per_line 2, per_page 4). **row.fill_page** — the card height is computed so `per_page ÷ per_line` lines fill the
  content height left after the every_page header / footer (`row.height` ignored).
- **group.page_break** — each group after the first starts on a new page.

## Element additions
```json
{"kind": "… | ellipse",
 "opacity": 1.0,                       // 0–1, every kind
 "shape": "rect | rounded | circle",   // image / signature (a photo): the clip
 "bind": {"field": "photo"}            // image: bind to a column holding an asset id / allowed image URL
}
```
- `value` of `image` / `signature` / `page.background_image`: an export asset id (32 hex) OR an image URL the
  server allows (`services/export_layout/remote_images.py`: the platform's own storage only, the same rule as the
  certificate designer's `check_image_urls`; anything else is dropped by `clean_document`). Never fetched from an
  arbitrary host (SSRF).
- In item context (a row / card / page) `{{key}}` in any text is replaced by that item's field value (columns and
  `calc.` keys), formatted as text; the document variables (`date exporter org_name total title filters group`)
  win on a name clash, `{{page}}` / `{{pages}}` always mean the page.

## Style additions
```json
{"letter_spacing": 0,        // pt, −5…50
 "line_height": 1.3,         // × font size, 0.6…3
 "shrink": false,            // text that does not fit shrinks (down to 50 %) instead of being clipped
 "shadow": {"color": "#55000000", "dx": 0.4, "dy": 0.4}   // mm; text and shapes
}
```
Excel ignores shadow / letter_spacing (note); Word keeps letter_spacing (`w:spacing`), drops shadow.

## Server API (the engine's public surface)
Python (`services/export_layout/`):
- `model.clean_document(raw, need_source=False) -> (doc, issues)` — the ONLY way in; renderers read cleaned docs.
- `render.render_document(doc, rows, path, *, fmt, vars_, images, title, tick, cap, deadline)` — a file.
- `engine.render_pages_png(doc, lang, rows, *, dpi, first=0, count=1) -> [png bytes]` — PNG pages (certificates,
  thumbnails, previews).
- `engine.render_pdf_bytes(doc, lang, rows, *, vars_) -> bytes` — a small in-memory PDF (one certificate).
- `computed.apply(row, specs) -> row` — adds the `calc.` values to a row (pure).
- `starters.list_starters(purpose) -> [Starter]` — the built-in professional templates.
HTTP (`/api/v1/exports/layout`, auth): v3 routes plus `GET /starters?purpose=` →
`[{key, purpose, name_ar, name_en, description_ar, description_en, mode, document}]` (document without source).
Templates: `/api/v1/exports/templates` (personal / organization, unchanged) with `schema_version` 3 or 4.

## Certificates on the engine (D-165)
- `certificate_designs.document` (JSON, nullable) + `document_version` (int): a design saved by the engine studio
  holds a v4 document with `purpose: "certificate"`, `mode: "page"`, one design per language (`designs.ar`,
  `designs.en`, `languages` = the design's languages). A design whose `document` is null renders with the legacy
  Pillow renderer exactly as before; a legacy save (old designer) clears `document`. Whatever saved last renders.
- Recipient values are the row: `student_name course_name certificate_title teacher_name date serial verify_url
  photo grade org_name` + the design's custom variables. The legacy `{student_name}` placeholders become
  `{{student_name}}` on conversion.
- `GET /api/v1/certificate-designs/{id}/document` → `{document, version, converted}` — `converted: true` when the
  server built it from the legacy columns (nothing saved yet).
- `PUT /api/v1/certificate-designs/{id}/document` `{document, version}` → `{document, version}`; 409
  `design_conflict` when `version` is not the stored one (another tab / device saved first: nothing is lost
  silently). Assets referenced must pass the same image check as the legacy save.
- `POST /api/v1/certificate-designs/preview-document` `{document, lang, values?}` → `{png_b64}` (one page, sample
  values when none) — never writes.
- Rendering (issue, auto-issue, batch, ZIP, verify, gallery): `cert_bridge.render_certificate(design, lang, values)`
  → PNG (same pixel size as before: 1600 px on the long side ×1.6 logical) / PDF; it picks engine or legacy.
- `scripts/migrate_cert_designs.py [--apply]` — converts every legacy design to a document (dry run by default),
  writes ONLY `document` / `document_version`, keeps every legacy column (rollback = set `document` to null).

## Flutter API (`lib/design/engine/design_engine.dart`)
`DesignEngine.open(context, DesignEngineRequest(...))` — purpose, the field catalog (`LayoutField`s), the data
(`serverDataset` or rows), allowed formats, an optional starting document / template, and `onSaved`. Data exports
keep calling `showAppExportSheet` (it opens the engine); certificates open `CertEngineStudio`. See the header of
`design_engine.dart` for the full table.
