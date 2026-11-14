# Export Studio and certificates

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

**Export Studio and certificates (D-130 – D-134, tracker `docs/export_studio/PROGRESS.md`)** — `showAppExportSheet(context, AppTableExport)` opens the Export Studio flow (`lib/design/export_hub/export_flow*.dart`: format → fields → language ar / en / both → design → export; Quick export repeats the last choices). Build the export inside `bilingualExport(() => …)` (`exportPagedList` does) so English / Both files get English headers, titles and status texts, and pass `orgId` plus, when the server has the same table (`GET /api/v1/exports/datasets`: `course.students`, `org.people`, `org.complaints`, `gov.items`), `serverDataset` + `serverParams` — that is what offers Schedule and Share link. Interactive exports render in the app, scheduled ones on the server (`../back/services/export_render.py`, D-130); share links need sign-in (`/e/<token>`, D-134); the log, schedules and links pages are `lib/features/exports/`. The designers share ONE engine, `lib/design/studio/` (`StudioController` + a `StudioAdapter` per data model: canvas, drag / resize / snap, undo / redo, zoom, properties, D-133): the certificate designer (`lib/features/certificates/designer/`: independent Arabic / English designs, several logos and signatures, QR, D-131) and the export designers. Standalone certificate issuing and the public `/verify/<token>` page: `lib/features/certificates/issue/` (backend `/api/v1/certificate-issuing`, D-132). The server's certificate font list is the renderer's catalog, never a second list (a stale copy was the "Arabic design does not save" bug). Kill switches `export.studio`, `export.schedules`, `export.share_links`, `admin.export_log`, `certificates.standalone`.

**Certificate studio (2026-11-01, `docs/studio_requests/progress_A.md`)** — the field / page keys (text style, box,
shadow, image `fit`, `rotation`, layer `name` / `locked`, `aspect_lock`; `theme.page` A4 / Letter / custom and
`theme.watermark`) are stored inside the existing JSON and sent only when not the default. The canvas lays text out
with the renderer's own rules (`cert_text_layout.dart`: 2 px shrink steps, the font file's ascent + descent × 1.12 /
1.18, bold / italic siblings or faux); `test/org/cert_parity_test.dart` compares it with the server's layout in
`test/fixtures/cert_parity/parity.json` (regenerate with `../back/scripts/contract/dump_cert_parity.py` after a
renderer change). Properties are docked at every width (phone: a non-modal panel under the page); every edit is
autosaved as a local draft (`CertDraftStore`). Template gallery: `GET /certificate-designs/templates`,
`POST /certificate-designs/templates/{key}`.

**Export layout v3 (D-142, contract `docs/export_studio/LAYOUT_V3.md`)** — while the kill switch `export.layout_v3` is not
disabled, `showAppExportSheet` / `showExportFlow` open the full-page flow in `lib/design/export_layout/` instead of the
sheet: `layout_model.dart` (the v3 document, mm, unknown keys kept), `layout_logic.dart` (starters List / Table / Custom
1-2-3 per line, Arabic = the English starter mirrored, the row preview's rule evaluation, the local Excel / Word notes),
`layout_api.dart` (`/api/v1/exports/layout/*`: fonts, validate, preview PNGs, rows upload, assets, runs watched with
JobWatch; v3 templates on `/api/v1/exports/templates` with `schema_version: 3`), `layout_flow_controller.dart` (state,
local draft per page key, last template per page key, source = the page's dataset else the rows uploaded once),
`layout_page.dart` + `layout_steps.dart` (Format & language · How to show · Design the items · Fixed parts · Preview &
export), `layout_canvas.dart` (the row card and each band on the shared studio engine) and `layout_props.dart`
(type Static / Dynamic / Conditional / Computed, field + format, the rule builder). The SERVER renders the preview
pages and the file. Phones get the simple form (starters, field picking, toggles); the canvas needs 720 px. Tests:
`test/export/layout_model_test.dart`, `layout_flow_test.dart` (FakeApi server in `layout_fake.dart`),
`test/ui/layout_flow_layout_test.dart`.

**Export Studio v2 (D-920 – D-925)** — the start screen (`layout_start.dart`) opens on `LayoutExportSummary` (format,
file name, rows · fields · language), then format, language, `LayoutQuickFields` (chips; `LayoutFlowController.toggleField`
ticks a field in every language's design, `layoutRebalanceColumns` re-shares the table width) and the gallery; from
1100 px the live preview pane sits beside it, phones have a Preview button (`layout-start-preview`). Every run state is
one `LayoutStatusCard` (`LayoutRunPanel`: progress, "Your file is ready" with size + Download again, Try again). A dataset
run sends the table's status labels as `value_labels` (`layoutValueLabels`); the server prints coded values and
`{{filters}}` in the file's language. Table rows with no fixed height grow to 3 lines then "…" (`pdf.table_row_measure`,
shared by PDF / Word / Excel); Excel tables get an AutoFilter. Server checks: `../back/tests/org_v2/export_quality.py`.

**Design engine, layout v4 (D-164 / D-165, contract `docs/design_engine/ENGINE.md`, tracker `docs/design_engine/PROGRESS.md`)** —
the layout document is THE engine document for exports and certificates (exam papers / covers, bubble sheets and the
guide export get the API, their sessions migrate them). v4 = v3 + optional keys: document-level computed columns
(`calc.` keys; worked out per row on the server before sort / group / totals, mirrored in `layout_computed.dart` and
checked against `test/fixtures/design_engine/computed_parity.json` — regenerate with
`../back/tests/contract/dump_computed_parity.py`), mode `page`, list columns, cards up to 4 per line with grids,
`items_per_page` / group page breaks, custom page size + background image, ellipse / opacity / photo shapes, letter
spacing / line height / shrink / shadow. Colours are `#RRGGBB` or `#AARRGGBB`, never `#RRGGBBAA`. The visual rule
builder is `showComputedFieldsEditor` (`layout_computed_builder.dart`). The flow opens on a start screen
(`layout_start.dart`: format, language, design gallery from `GET /exports/layout/starters`, Export now) and the
designer has three steps (`layout_arrange.dart`: Layout · Design · Preview, a live preview pane from 1100 px). Other
callers open the engine through `DesignEngine.open` / `DesignEngine.export` (`lib/design/engine/design_engine.dart`).
The canvas engine adds layers, a rotate knob and match size (`studio_layers.dart`). Certificates: the Certificate
studio (`lib/features/certificates/studio/`) saves a v4 page-mode document per language through
`GET` / `PUT /certificate-designs/{id}/document` (PUT sends `version`; 409 `design_conflict` → Reload / Keep mine) and
`POST /certificate-designs/preview-document`; a design with no document still renders and edits with the legacy
designer, reachable from the studio's More › Classic designer and for everyone while the kill switch
`certificates.engine` is disabled. Tests: `test/export/layout_computed_test.dart`, `studio_controller_test.dart`,
`test/ui/layout_computed_builder_layout_test.dart`, `studio_layers_test.dart`, `layout_element_view_test.dart`,
`test/org/cert_engine_studio_test.dart`, `test/ui/cert_engine_studio_layout_test.dart`.

**Certificate fonts (D-380..D-382)** — the studio's font control is `CertFontControl` (`lib/features/certificates/studio/cert_font_picker.dart`), slotted into the shared panel through `LayoutCanvasEditor.fontControl`: the list is the renderer's catalog from `GET /exports/layout/fonts` (grouped Arabic / Latin, each row in its own face with the field's text, search, the selection or every text field). A font the app build does not bundle is fetched from `GET /exports/layout/fonts/{id}/file` and registered with `ExportFonts.addRemote`. On the canvas the italic of Playfair / Cormorant is the renderer's own italic file (`layoutTextStyle`). Since D-410 the catalog also holds server-only fonts (`bundled: false`, `?include=all`): nothing is bundled for them, `ExportFonts.declareRemote` names them when the catalog arrives and `ExportFonts.remoteFetch` / `ensureFace` load a file when a row or the canvas draws it (a new font goes in `../back/services/export_layout/fonts.py` with its files and an OFL file, and the new app side needs no list). Parity: `test/org/cert_font_parity_test.dart` (fixture `test/fixtures/cert_fonts/catalog.json`, regenerate with `../back/scripts/contract/dump_cert_fonts.py`), server side `../back/tests/org_v2/cert_fonts.py`.

**Certificate templates (D-383, D-384)** — the collection is on the server, `../back/services/certificate_templates/` (`art.py` ornament, `designs.py` one painter + Arabic and English layouts per template). The gallery page is `lib/features/certificates/studio/cert_template_gallery.dart`; a new category key goes in `kCertTemplateCategories`. Use only fonts both renderers carry, keep optional values on their own line (`tests/org_v2/cert_templates.py` checks both).


**Student photos on certificates (D-386)** — a design with a student photo needs one for every recipient before issuing (`GET .../columns` says `photo`). The issue flow's Photos step (`cert_issue_photos.dart`, logic in `cert_issue_photo_logic.dart`) is one upload per person through `showAppImageCropper`, or several matched by file name; the server enforces it with 422 `photos_required`. The element's optional setting is `cert_engine_photo_option.dart`.

**Certificate studio workspace (D-387 – D-389)** — `cert_engine_shell.dart` (top bar, rail, panels, the phone's sheet, skeleton, empty page; plain values and slots), `cert_engine_inspector.dart` (the selection's inspector, folding sections, `CertColorWell`, `CertNumberField`), `CertPageControls` and `CertFontControl` in `cert_engine_panels.dart`. The canvas is `LayoutCanvasEditor(canvasOnly: true)`, which hands up a `LayoutEditorHandle` per language. The Templates tab is `CertTemplatesSlot`; the top bar's keyboard button goes in `CertStudioShell.keyboardAction`. Tests: `test/ui/cert_studio_shell_test.dart`; renders: `CERT_SHOTS=<dir> flutter test test/visual/cert_engine_studio_visual_test.dart`.

**Template colours and wordings (D-400 – D-403)** — `cert_template_colours.dart` (`CertPalettePicker`, `CertTemplateColoursPanel`) picks a template's background colours in the gallery's large preview and in the page inspector; the server (`certificate_templates/palette.py`) paints them into the page and fits the inks, and the page's `extra['template']` memory (`certRecolourDesign`, `certTemplateMemory` in `cert_engine_presets.dart`) keeps the person's own edits on a later change. `cert_wordings_panel.dart` is the Wordings rail tab. A non-user batch asks for the instructor (`certTeacherRequired`, `IssueTeacherField`). Tests: `test/ui/cert_template_colours_test.dart`, server `../back/tests/org_v2/cert_modern_templates.py`, `cert_teacher_required.py`.
