# Export Studio + Certificate Studio — job tracker

Started 2026-10-31 on `feature/live-hardening` in both repos (owner's choice: same tree and branch, peer sessions
share it — commit only this job's files with `git commit --only`). Decisions D-130 – D-134 (`docs/DECISIONS.md`),
migrations `0032` – `0034` in `../back` chained from `0030` (the roadmap worktree holds `0031`: a merge revision is
needed when both land).

Kill-switch keys (catalog `../back/services/feature_catalog.py`): `certificates.standalone`, `export.studio`,
`export.schedules`, `export.share_links`, `admin.export_log`.

## Audit (step 0) — done

- Certificate designs are server-rendered PNGs (Pillow, `certificate_design_renderer.py`); one row holds both
  languages: `fields` = Arabic layout, `fields_en` = English; background / logo / signature / theme / orientation are
  shared. One logo / one signature = single columns, the renderer pastes the same image for every logo field.
- Exports: client-side writers (`lib/design/export/`, `lib/design/export_hub/` with a fractional-block designer,
  `ExportDesign.version = 2`), templates in `org_export_templates` (org-scoped, governance). No server job / link /
  export log for exports. `helpers/xlsx_safe.py`, `send_email_with_attachments`, `privacy_export_service` (job
  pattern), `data_lab_import.parse_upload` exist.
- Issuing is course-bound (`CertificateIssuance.course_id/student_id` NOT NULL); serial `EF-…` is computed, never
  stored; no verify route / QR / ZIP.

## Arabic save error — root cause (fixed, stage 1)

1. `certificate_design_service.FONT_KEYS` listed 8 of the renderer's 28 fonts: every save reset Cairo, El Messiri,
   Reem Kufi, Aref Ruqaa, Scheherazade, Markazi (and 8 Latin fonts) to Tajawal, and the canvas reloaded the server
   copy — the Arabic design "did not save". Now imported from the renderer.
2. The designer's `_toast` ignored `error:` — "Saved" itself was shown as a red error notice.
3. `CertificateFieldIn` lacked `shape` (photo `rounded` came back `circle`).
4. Text boxes had no limit; > 1000 characters → 422 shown as a generic failure. Now `maxLength` + the server's text.
Regression: `../back/tests/org_v2/cert_langs.py` (fails on the old list).

## Stages

| # | Stage | Owner | State |
|---|---|---|---|
| 1 | Arabic save fix + regression test | lead | done |
| 2a | Cert design v2 backend: per-language assets, `langs`, multi logos / signatures (`src`, name, title), QR kind, `design_spec` | agent | done (`cert_design_v2.py`), reviewed + fixed |
| 2b | Standalone issuing backend (tables, parse, match, batch job, ZIP / merged PDF, verify, history, saved lists) | agent | done (`e2e_cert_standalone.py`, 70 checks), reviewed + fixed |
| 3 | Shared studio engine `lib/design/studio/` (controller, canvas, toolbar, panel) | agent | done (54 tests) |
| 4 | Export platform backend (templates per user / org + versions, export log, datasets, server render, schedules, links) | agent | done (`e2e_export_platform.py`, 244 checks), reviewed + fixed |
| 5 | Certificate designer on the engine + v2 UI (per-language, logos, signatures, langs, QR, custom fields) | agent | done (20 unit + 16 layout tests); follow-up: `inherit_en`, English generated background, unsaved-theme preview |
| 6 | Standalone issuing UI + `/verify/<token>` page (`lib/features/shared/certificates_issue/`) | agent | done (18 unit + 9 layout tests; app links: Android manifest + AASA `/verify/*`); real-app check owed |
| 7 | Export Studio UI on the engine (flow, field picker, Excel studio, rules, themes, templates, log / schedules / links) | agent | done (export suite 109 + 19 unit + 10 layout); entries: admin services hub, org Settings › Exports |
| 8 | QA + adversarial review, features guide, docs | lead | done: features guide (5 entries + designer updated); real-app QA in a web build on the local stack (designer, standalone issuing, Export Studio, layout 390 / 1440 ar / en) found 9 bugs; front review 11 findings — all fixed with a test each |

Lead wiring done: routers in `main.py`, models in `migrations/env.py`, verify route open past the paywall / device
guard, `FLUTTER_API_CHANGES.md`, contract snapshots regenerated, Alembic single head `0034`.
Reviews (2026-10-31): export backend 9 findings (column leak via group_by / hide, upload links ignoring columns,
PDF markup injection, control characters, owner keeps access after losing rights, …) and certificate backends 11
(course-mode issuing by non-teachers, signature reuse via duplicate, xlsx dimension bomb, quadratic merged PDF,
double re-issue, ex-staff power, stuck batches, e-mail quota, …) — all fixed with a regression check each
(export 301 checks, standalone 96). `cert_batch_tick` (5 min) resumes / fails stale batches. Milestone run green:
cert_langs, cert_design_v2, e2e_cert_standalone, e2e_export_platform, e2e_governance, e2e_course_profile,
cert_round6, g3_image_urls, e2e_security_p10, e2e_reports, e2e_org_v2.
Alembic: 0032 revises 0030 like the roadmap branch's 0031 → add a merge revision when that branch lands.

Course certificates (issue, issue-all, auto-issue, request approval, Data Lab send) now carry a stable verify token
(`CertificateService.attach_verification`; e2e_cert_standalone 104 checks). Designer follow-up landed server-side:
`inherit_en`, English generated background (`draft lang`), unsaved-theme preview.
Known gap: server renders run inline in the tick (45 min cap, 3 runs in flight per user).

Real-app QA (2026-10-31) fixes: default design name localized (no English title on an Arabic certificate); the
filled sample's example row is no longer issued; Excel `rightToLeft` moved off `<workbookView>` (invalid OOXML) in
both writers; file names / sizes LTR in Arabic (`exportLtr`); the English file of a "Both" export stamps in English
(`inExportLang`); PDF Latin text no longer word-reversed (`exportPdfTextDir`); the assistant hidden over the studios;
org context for schedules / links (`exportContextOrg`) and `orgMembersExport` → server dataset `org.people`; shared
files keep their name (`GET /exports/links/{token}/info`). Front review: grouping clear, `rules_invalid` on template
save, stored rules while `export.studio` is off, the "Both" default, signed-out `/e/` link, stale ambiguous-row
candidates, course-mode `certificate_id` / `replace_existing`, edits lost during save, duplicate field limit,
double-decoded verify token, stuck search tick. App links: Android + AASA `/e/*`.

Follow-up (2026-10-31): every table export is built once per language (`bilingualExport`), so English / Both
files print English headers, titles and status texts; `exportPagedList` no longer drops `orgId` / `serverDataset`
(Schedule / Share link on org members); the schedule form picks roles (chips), status / language (dropdowns) and
yes / no options (switches) instead of raw text; `video_protection.js` loads after `<base>`.

Known gaps (not blocking): `package:pdf` drops the space at some Arabic / number and Arabic / Arabic word boundaries
(reproduced: "أكتوبر2026", "علومالحاسب"; NBSP does not help, LRM / RLM fix the order but neither Tajawal nor
IBM Plex Sans Arabic has a glyph for them, so a box is drawn) — needs a package upgrade or the server renderer;
row values a table maps itself (role names, …) stay in the app language; members export has no courses count (the
people API lacks it); dark mode not checked in the real app; the certificate renderer logs (does not show) a QR
skipped for a missing `segno` — the dev api image needs a rebuild.
