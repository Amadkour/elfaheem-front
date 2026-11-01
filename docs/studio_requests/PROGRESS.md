# Studio + Requests job — progress (feature/studio-requests, both repos)

Started 2026-11-01 from `organizations` (front aad3f24, back 65e987b). Owner's brief: studio bugs (2.1), editor (2.2),
shared export engine (2.3), requests (3.x), extras (6.x), performance / security (7.x).
States: 1 = done and working · 2 = done, has issues · 3 = partial · 4 = not built.

## Audit (2026-11-01, read-only)

Checks run: `flutter test test/export/ test/org/cert_designer_v2_test.dart` (145 passed);
backend `tests/org_v2/cert_langs.py` (all passed) and `tests/org_v2/e2e_governance.py` (317 checks passed), SQLite.
Paths: F = front `lib/`, B = back.

| # | Item | State | Evidence | Needed |
|---|------|-------|----------|--------|
| 2.1.1 | Arabic design resets on save | 1 | B `services/certificate_design_service.py:42` imports the renderer's 28-key `FONT_KEYS`; Arabic in `fields` and English in `fields_en` (B `data/models.py:1397`); `cert_langs.py` "every catalog font survives a save" passes | Real-app re-check only |
| 2.1.2 | Field editing popup hides the field | 3 | F `features/teacher/certificates/designer/certificate_designer_screen.dart:545` docks the props panel only at width ≥1100; below that `_openPropsSheet` (:636) is a modal `showAppSheet` over the canvas | Non-modal docked sheet on phone/tablet that keeps the field visible |
| 2.1.3 | Field resize | 2 | F `design/studio/studio_model.dart:89` has 8 handles, `minSize`; numeric W/H at `cert_designer_panels.dart:600`; aspect fixed per kind (`cert_studio_adapter.dart:84`) | User aspect-lock toggle for text/boxes |
| 2.1.4 | Editor = preview = saved = export | 2 | Preview and saved file use the same server renderer (`/certificate-designs/{id}/preview`, provider :899); the editor canvas is a separate Flutter painter; no parity test exists | Parity test (canvas vs server PNG); fix the drift it finds |
| 2.1.5 | Only 2 fonts in Word/PDF/Excel | 3 | F `design/export_hub/export_design.dart:32` `exportFontFamilies = ['tajawal','bahij','plex']`; `design/export/table_export_pdf.dart:3` Tajawal/Bahij; Word/Excel hard-code Arial (`table_export_docx.dart:22`, `table_export_xlsx.dart:49`); no Word font embedding. Arabic RTL shaping fixed (be1d277) | Every studio font in export settings, embedded in PDF and Word |
| 2.1.6 | One signature changes all | 2 | Per-field `src` (F `certificate_design_models.dart:211`, provider `_applySignature` :462; B renderer :455 `f.get("src") or design.signature_url`) | Certificates have no Word export (PDF / PNG only) |
| 2.2a | Docked properties panel | 3 | As 2.1.2 | Same fix |
| 2.2b | x/y/w/h, z-order, duplicate, delete, align, distribute, snap, zoom | 2 | F `design/studio/studio_controller.dart:472-726` | Rotation, rulers, visible grid, pan polish missing (no `rotat` in studio/ or the designer) |
| 2.2c | Full text controls | 3 | `CertField` (models:191-218): font, size, colour, letter spacing, opacity, align, max lines, shrink | Weight, italic, underline, line height, direction, background, border, radius, shadow, padding (`studio_props.dart` already has weight / border widgets) |
| 2.2d | Image controls | 3 | Upload / replace (`cert_designer_panels.dart:279,655`), opacity | Fit, crop (`showAppImageCropper`), rotation |
| 2.2e | Undo / redo + shortcuts, autosave | 3 | Ctrl+Z/Y at `design/studio/studio_canvas.dart:477`; no autosave/draft in provider | Local autosave draft |
| 2.2f | Layers panel | 3 | `CertLayersList` reorder (`cert_designer_panels.dart:1031`); engine `locked` (studio_model:59) | Show/hide, lock, rename in the panel |
| 2.2g | Several designs per language, duplicate, default, sample preview | 3 | Several designs per user/org (`certificate_designs_screen.dart`); one ar + one en layout per design; server preview with sample data | Duplicate, set default, variants per language |
| 2.2h | Placeholders incl. QR | 1 | `CertFieldKind.qr` (models:174), custom placeholders (`cert_designer_v2_test.dart` "custom placeholders") | — |
| 2.2i | Page sizes A4 / Letter / custom | 3 | Fixed 1000×707 landscape/portrait only (models:6) | Paper sizes in model, renderer, editor |
| 2.3a | Data export designer | 1 | F `design/export_hub/export_designer.dart` (header/footer, logo, title, columns, table style, page, RTL, watermark) | — |
| 2.3b | Code shared with cert designer | 2 | Both on `design/studio/` (D-133); props panels differ (cert uses its own `cert_designer_panels.dart`) | Move cert props onto `studio_props.dart` |
| 2.3c | Zero drift from preview | 2 | `ExportPagePreview` is a separate painter from the PDF/Word writers; no parity test | Parity tests |
| 2.3d | Every studio font in export | 4 | `exportFontFamilies` = 3 | As 2.1.5 |
| 3.1 | Submit for self / other user / outside person | 3 | Self: B `routers/organization/org_governance_member_router.py:100`; staff on behalf via `source_user_id` (B `org_governance_router.py:398`), but the app's New item never sends it; no outside-person fields | Beneficiary model (user or manual person), UI picker |
| 3.2 | Academic + service departments | 1 | B `data/governance_models.py:62` `ENTITY_KINDS` service / scientific | — |
| 3.3 | Department council path | 1 | `to_council` (member router :49, F `gov_member_pages.dart:287`), `e2e_councils.py` | — |
| 3.4 | Manager submits for self / others | 3 | Backend yes (as 3.1); UI self only | UI |
| 3.5 | List / filter / detail / status | 1 | `GET /items` with filters + paging (router :368), `gov_items_page.dart`, `gov_item_screen.dart`, `gov_filter_test.dart` | — |
| 3.6 | Export one / selected / all-with-filters | 3 | Filtered dataset `GET /export/data` (router :686) → Export Hub; no single-item or selected-ids export | `ids` param + item-screen / selection entry |
| 3.7 | Server permissions (view, create-for-others, status, export) | 2 | `_manages` / `ctx.can("workflow", …)` (router :68-72), `can_export_items` (`export_data.py:87`) | No distinct "create for others" permission; `source_user_id` not checked for org membership |
| 3.8 | Validation, audit, ar/en | 2 | Pydantic limits (member router :43-49), `audit(...)` on create/export; attachments only checked for http(s) URL (`services/organization/forms.py:62`) | Client validation pass; attachment URL must be our storage |
| 6.1 | Ready-made certificate templates | 3 | Draft generator, 3 styles (B `services/certificate_draft_service.py:27`) | Real template gallery ar/en |
| 6.2 | Bulk generation | 1 | `lib/features/shared/certificates_issue/`, B `certificate_issue_service.py`, `e2e_cert_standalone.py` (70 checks; ZIP / merged PDF) | Real-app check (tracker) |
| 6.3 | QR verification page | 1 | B `routers/certificate_issue_router.py:357` public `/verify/{token}`; F `cert_verify_page.dart` | — |
| 6.4 | Watermark everywhere | 3 | Export Hub PDF + Word (`export_docx.dart`, `export_pdf.dart`); Excel none (`export_xlsx.dart:9`); certificates none | Cert watermark; image watermark |
| 6.5 | Request notifications | 1 | B `services/organization/governance/notify.py` (in-app + email `fallback/always`); e2e notifications=54 | — |
| 6.6 | Attachments | 3 | URL list, name ≤200, max 10 (`forms.py:62`); no type/size check, names not verified in exports | Upload validation, preview, names in exports |
| 6.7 | Approval chain manager → council | 2 | route / escalate / decide / reopen (router :453-515, `items.py:506`) | Configurable chain, explicit rejection reason + resubmit flow |
| 7.1 | Lazy fonts | 3 | UI fonts lazy (`FontLoader`), but 27 cert fonts bundled in `pubspec.yaml` | Load cert/export fonts on demand |
| 7.2 | Background exports, progress, cancel | 3 | Batch issuing has progress (`certificate_issue_service.py:89`); app exports run on the UI isolate; no cancel anywhere | Isolate/server job + cancel |
| 7.3 | Paginated request lists | 1 | `page`/`size` ≤100 (router :373-378) | — |
| 7.4 | Server-side permission checks | 1 | As 3.7; `e2e_governance.py` 317 checks | — |
| 7.5 | Upload validation by real type | 3 | Magic-byte checks in some services (`export_jobs.py`, `certificate_issue_service.py`); governance attachments none | Magic-byte check on attachment upload |
| 7.6 | No secrets / PII in logs | 2 | Front `redactForLog` / `logSensitiveKeys` (`core/api_client.dart`); backend not audited for request bodies | Backend log review |

## Tasks per agent

### A — certificate studio UI / editor
- [not started] A1 Docked non-modal properties panel on phone/tablet (2.1.2) — M
- [not started] A2 Aspect-lock toggle (2.1.3) — S
- [not started] A3 Rotation, rulers, grid, pan (2.2b) — M
- [not started] A4 Full text controls on the shared `studio_props.dart` (2.2c) — L (model + server renderer)
- [not started] A5 Image fit / crop / rotation (2.2d) — M
- [not started] A6 Autosave draft (2.2e) — S
- [not started] A7 Layers: show/hide, lock, rename (2.2f) — S
- [not started] A8 Duplicate / set default / per-language variants (2.2g) — M
- [not started] A9 Paper sizes A4 / Letter / custom (2.2i) — M
- [not started] A10 Template gallery ar/en (6.1) — M

### B — export engine
- [not started] B1 One font catalog for exports = studio fonts, embedded in PDF + Word, lazy-loaded (2.1.5, 2.3d, 7.1) — L
- [not started] B2 Parity tests: cert canvas vs server PNG, export preview vs writers (2.1.4, 2.3c) — M
- [not started] B3 Certificate Word export with independent images (2.1.6) — M
- [not started] B4 Watermark: certificates, image watermark (6.4) — M
- [not started] B5 Heavy exports off the UI isolate with progress + cancel (7.2) — M

### C — requests backend
- [not started] C1 Beneficiary: self / system user / manual outside person; membership check; "create for others" permission (3.1, 3.4, 3.7) — M (+ Alembic revision)
- [not started] C2 Export by `ids` (one / selected) (3.6) — S
- [not started] C3 Attachments: own-storage URLs, real-type + size check (6.6, 7.5) — M
- [not started] C4 Configurable approval chain, rejection reason, resubmit (6.7) — L
- [not started] C5 Log review for PII (7.6) — S

### D — requests UI
- [not started] D1 On-behalf picker (user search or manual person) in member and staff forms (3.1, 3.4) — M
- [not started] D2 Export one / selected from list and item screen (3.6) — S
- [not started] D3 Attachment preview / download, names in exports (6.6) — S
- [not started] D4 Approval chain + resubmit UI (6.7) — M

### E — QA
- [not started] E1 Real-app check of cert designer ar/en save, preview, issue (2.1.1, 2.1.4) — S
- [not started] E2 Layout harness for every new widget; e2e for C1–C4 — M
- [done] E3 Render review + adversarial review of A and C (`feature/studio-qa`): designer app bar name in either script
  (font fallback), the selected layer row keeps its name in the 224 px column (lock / delete in a "more" menu), the
  studio toolbar drops its labels where they do not fit and shows a chevron on a cut edge (never clips), requests'
  attachment / chain inks through `appInk` in dark mode; bugs fixed with tests: edits made during an in-flight save
  were never autosaved, attachment upload refusals showed the server's Arabic text in English, the picker offered
  `.zip` (always refused), a picker failure left "uploading" on. Tests: `test/ui/studio_qa_test.dart`, additions to
  `test/org/cert_studio_test.dart` and `test/org/gov_requests_test.dart`.

## Next step
A1 (docked properties panel) and B1 (export font catalog) first, in parallel; then A2, B2, B3.
