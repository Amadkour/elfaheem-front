# Design engine (D-164 / D-165) — job tracker

Branch `feat/design-engine` in both repos (worktrees `D:/platform/nextbrain/wt-front-engine2`, `wt-back-engine2`),
from `organizations` d6d6668 / d0f253e. Contract: `ENGINE.md` (= back `docs/design_engine.md`). Audit: `AUDIT.md`.
Agent branches `de/<id>` in worktrees `D:/platform/nextbrain/wt-de-<id>`, merged into `feat/design-engine` by the lead.

| # | Stage | Owner | Files | State |
|---|---|---|---|---|
| 0 | Audit | lead + 3 read-only agents | `AUDIT.md` | done |
| 1 | Contract v4 + models (server clean, computed evaluator, Dart model, parity fixture) | lead | `model.py`, `computed.py`, `remote_images.py` (stub), `layout_model.dart` | done (layout e2e 1 940 ✓, front layout tests 42 ✓) |
| 2 | Computed pre-pass, `{{key}}` item text, image store, `engine.py`, preview cache | BA1 | `values/rows/render/service/engine.py` | running |
| 3 | Renderers: page mode, list columns, grids, page breaks, ellipse, opacity, shapes, text styles | BA2 | `flow/pdf/docx/xlsx/grid/validate/fonts.py` | running |
| 4 | Certificates backend: `document` column (0043), bridge, endpoints + 409, starters, draft-commit fix, migration script | BB | cert services, router, schemas, models | running |
| 5 | Computed fields evaluator mirror + visual rule builder | FA | `layout_computed*.dart`, `layout_logic.dart` | running |
| 6 | Canvas: layers, rotation, match size / distribute, perf, v4 drawing + props | FB | `lib/design/studio/*`, `layout_canvas/element_view/props.dart` | running |
| 7 | Export flow: quick path, layout presets, live preview, computed entry, Excel note, bugs, `design_engine.dart` | FC | `layout_page/steps/flow_controller/api.dart` | running |
| 8 | Certificate Studio on the engine (kill switch `certificates.engine`) | FD | `lib/features/teacher/certificates/studio/` | running |
| 9 | Merge + integration (snapshots, features guide, docs) | lead | — | pending |
| 10 | Independent review (correctness, security, tenant isolation) | reviewer agent | — | pending |
| 11 | Merge → organizations → production, deploy, smoke | lead | — | pending (wave 2: after sessions 1, 2, 3, 5) |
