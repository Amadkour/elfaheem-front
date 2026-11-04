# Design engine (D-164 / D-165) — job tracker

Branch `feat/design-engine` in both repos (worktrees `D:/platform/nextbrain/wt-front-engine2`, `wt-back-engine2`),
from `organizations` d6d6668 / d0f253e. Contract: `ENGINE.md` (= back `docs/design_engine.md`). Audit: `AUDIT.md`.
Agent branches `de/<id>` in worktrees `D:/platform/nextbrain/wt-de-<id>`, merged into `feat/design-engine` by the lead.

| # | Stage | Owner | Files | State |
|---|---|---|---|---|
| 0 | Audit | lead + 3 read-only agents | `AUDIT.md` | done |
| 1 | Contract v4 + models (server clean, computed evaluator, Dart model, parity fixture) | lead | `model.py`, `computed.py`, `remote_images.py` (stub), `layout_model.dart` | done (layout e2e 1 940 ✓, front layout tests 42 ✓) |
| 2 | Computed pre-pass, `{{key}}` item text, image store, `engine.py`, preview cache | BA1 | `values/rows/render/service/engine.py` | done (design_engine_unit 65 ✓, layout e2e 1 952 ✓) |
| 3 | Renderers: page mode, list columns, grids, page breaks, ellipse, opacity, shapes, text styles | BA2 | `flow/pdf/docx/xlsx/grid/validate/fonts.py` | done (design_engine_render 55 ✓) |
| 4 | Certificates backend: `document` column (0043), bridge, endpoints + 409, starters, draft-commit fix, migration script | BB | cert services, router, schemas, models | done (cert_engine 184 ✓; cert_langs / cert_design_v2 / cert_studio / g3_image_urls ✓) |
| 5 | Computed fields evaluator mirror + visual rule builder | FA | `layout_computed*.dart`, `layout_logic.dart` | done (parity fixture ✓, 55 layout tests ✓) |
| 6 | Canvas: layers, rotation, match size / distribute, perf, v4 drawing + props | FB | `lib/design/studio/*`, `layout_canvas/element_view/props.dart` | done (shadow colours fixed to `#AARRGGBB` at merge) |
| 7 | Export flow: quick path, layout presets, live preview, computed entry, Excel note, bugs, `design_engine.dart` | FC | `layout_page/steps/flow_controller/api.dart` + `layout_start/arrange.dart`, `design_engine.dart` | done |
| 8 | Certificate Studio on the engine (kill switch `certificates.engine`) | FD | `lib/features/teacher/certificates/studio/` | done (parity gaps listed below, owner decides) |
| 9 | Merge + integration (snapshots, features guide, docs) | lead | — | done (all 7 branches merged; server suites ✓; front gate running) |
| 10 | Independent review (correctness, security, tenant isolation) | reviewer agent | — | running |
| 11 | Merge → organizations → production, deploy, smoke | lead | — | pending (wave 2: after sessions 1, 2, 3, 5) |

## Certificate studio vs the legacy designer (owner decides; nothing removed)
The legacy designer stays reachable (studio › More › Classic designer; everyone while `certificates.engine` is off).
Ported since (I1): rename, watermark (text / image), signature upload through the signature endpoint with "Clean
signature again" (ink / strength), Generate a background (per language), preview sample values for custom variables;
each language already has its own page (orientation, background).
Ported since (I4): the server template gallery (`GET /certificate-designs/templates`; the gallery shows "Ready-made
designs" above the starters; a pick creates the template's copy with `theme_color`, reads its page for the current
language through the document endpoint, adopts it into the OPEN design, which keeps its id and version, and deletes the
copy), the draft wizard's theme colour (swatches from the app theme + a hex box) and dark flag in "Generate a background"
(and the colour of a template pick), and "Clean signature again" for a signature saved earlier (its image is fetched and
sent through the signature endpoint; the server keeps only the cleaned PNG, so it works on the cleaned image). Nothing is
left that only the legacy designer does, except what the conversion cannot carry:  text underline, shadow blur, the photo's white ring, tiled watermarks.

## Integration notes
- Colours: `#RRGGBB` / `#AARRGGBB` only (FB had `#RRGGBBAA` for shadows; fixed in the app, the contract example too).
- `generate_draft` with a design id no longer saves the design: older apps must save after "regenerate background".
- **Migration number at rebase:** `feat/grading-review` (wave 1) also adds `0043_grade_visibility.py` (revision "0043" ←
  "0042"). When it is on `organizations`, rename ours to `0044_cert_design_document.py` with revision "0044" ←
  "0043" and update the "0043" mentions (D-165, FLUTTER_API_CHANGES.md, this tracker); never two "0043" heads.
