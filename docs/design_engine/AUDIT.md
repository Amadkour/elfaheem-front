# Design engine — Phase 0 audit (2026-11-04, read-only)

Scope: the Export Studio (front `lib/design/export_layout/`, `lib/design/export_hub/`, `lib/design/export/`, shared
canvas `lib/design/studio/`; server `services/export_layout/`), the Certificate Studio (front
`lib/features/certificates/designer/`; server `certificate_design_*`, `certificate_draft_service.py`), and the
other renderers the engine must serve. Code read on `organizations` @ front d6d6668 / back d0f253e.

## What works (keep)
- **One shared canvas** (`lib/design/studio/`, ~4 100 lines): `StudioController<P>` + per-host `StudioAdapter`, drag,
  8 handles, smart guides, grid snap, align / distribute, marquee, copy / paste, lock, in-place text, undo / redo, zoom,
  rulers, keyboard shortcuts. Used by the export layout editor, the certificate designer and the old export hub.
- **Layout v3 (D-142)**: one mm JSON document, the server renders PDF / Word / Excel AND the preview (no drift);
  list / table / custom cards (1–3 per line), rules with 11 ops, totals, group headers, page header / footer, page N/M,
  QR, images, signatures, watermark, Arabic shaping + font fallback, background runs with progress / cancel,
  streaming row spool, formula-safe Excel, escaped Word XML, no `eval`. 1 940-check e2e.
- **Certificates**: per-language layouts (`fields` / `fields_en`), per-language assets, `langs`, 28 fonts, the
  Arabic save fix of 2026-10-31 (stale 8-font list) holds — front payload keys match the server schema 1:1.

## Problems found

### Flow (Export Studio)
1. Every export walks a 5-step stepper; no quick "just give me the file" path (the old flow had one).
2. The server preview (the truth) appears only at step 5; while designing the user sees an approximation.
3. Every edit marks all languages' previews stale; a language switch recreates the step and its canvas controller
   (undo history lost).
4. Phones (< 720 px) get a reduced form with no canvas.
5. The old flow (`export_hub/`) is still shipped behind the kill switch — two implementations to maintain.

### Layout control for large lists
6. No list-in-columns, no grids beyond 3 cards per line, no page-break control (per group / every N items), no
   page-per-item mode (certificates, covers, per-student sheets).

### Computed columns
7. Only `index` and `concat` exist, and only on ONE element: a computed value cannot be reused by a column, a rule,
   sort, group or totals. Rules are a flat all/any list; no nesting, no arithmetic, no "then set value".

### Bugs (export)
8. `_uploadId` cached per language and never invalidated when rows / fields change (stale preview / export data).
9. `uploadRows` sends every row in one JSON POST: no size guard, no progress.
10. `previewPage` reset to 0 on every refresh.

### Certificate Studio — Arabic vs English saving
11. **HIGH** "Regenerate background" / orientation change call `POST /certificate-designs/draft` with the design id,
    and the server COMMITS theme, logo, signature, orientation (Arabic path) or theme_en / background_en /
    orientation_en / fields_en (English path) to the stored design behind the user's back; the client's base
    timestamp goes stale, so on reopen the unsaved local draft is discarded — the user's edits in the OTHER language
    are silently lost, and "close without saving" still changed the server.
12. **HIGH** the same call replaces the theme dict: the watermark and other theme keys are wiped.
13. **MED** no optimistic concurrency: both languages are always sent in full, so a stale tab / second device
    overwrites the other language's newer edits silently.
14. **MED** local drafts keyed by design id only (not user), dropped without a prompt when the server copy is newer.
15. **LOW** English silently falls back to the Arabic layout where `view('en')` is used and English is empty.
16. **LOW** `orientation_en` always sent explicit: English can never follow Arabic orientation again.

### Certificate Studio — performance
17. Every edit `notifyListeners()` on a 1 200-line provider watched by ~10 panels: the whole designer rebuilds per
    drag frame; `refresh()` rebuilds the full item list; undo snapshots the whole language slice per step.
18. A full-design JSON local draft is encoded on every edit (1.5 s debounce).
19. Background / logo / signature / watermark `Image.network` without `cacheWidth` (1600×1131+ decoded, twice).
20. Server side: sync Pillow render at 1.6× per preview, a background render + upload per draft call.

### Server engine
21. Preview re-renders from scratch on every call (no cache); preview / runs execute in the API process.
22. Assets are fetched by token only (no owner / tenant scope) — acceptable for 128-bit tokens, worth an org scope
    once templates are shared wider.

## Other renderers (consumers of the engine)
- Exam answer sheets `exam_engine/services/sheets.py` (reportlab, mm, one page per student + QR): a natural
  page-mode consumer later. OMR bubble sheets `mlkit/omr/sheets.py`: exact geometry drives the scanner — keep
  separate (or a dedicated element kind later). Exam papers: app-side `exam_paper_pdf.dart` / `_docx.dart`. User guide:
  Markdown only (`feature_guide.render_markdown`). Exam sessions own those migrations; the engine exposes the API.

## Decision
Unify on the layout document (v4 = v3 + additions, D-164) and its server renderer; certificates become page-mode
documents rendered by the same engine, with the legacy renderer kept for designs not yet saved in the new studio
(D-165). Plan and stages: `PROGRESS.md`.
