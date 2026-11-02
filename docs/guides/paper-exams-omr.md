# Paper exams with bubble sheets (OMR)

The engineer's map of the paper-exam flow: identifiers, setup, bubble-sheet types, printing, scanning, review,
results, and the model hub behind the readers. The decisions are D-150 – D-160 in `../back/docs/DECISIONS.md`
(this repo's `docs/DECISIONS.md` has no entries of its own for them); the routes and payloads are in
`../back/FLUTTER_API_CHANGES.md`; the backend notes are the "Exam identifiers", "Paper exams / OMR" and
"Model hub" bullets of `../back/CLAUDE.md`. What users read about it is in `../back/data/app_features_guide.json`
(`exam_paper_setup`, `exam_identifier_request`, `omr_sheet_types`, `omr_custom_layout`, `omr_print_sheets`,
`omr_scan_sheets`, `omr_review_queue`, `omr_paper_results`, `admin_ai_models`). Keep this file in step with the code;
when they disagree, the code wins.

## The flow, end to end

Every engine path below is under `/api/v1/exam`; "exam" = `/api/v1/exam/exams/{id}`. All files are under
`lib/features/shared/exam_engine/paper/` unless a path says otherwise.

| Step | Screen (file) | Opened from | Server | Backend code |
|---|---|---|---|---|
| Setup | `ExamSetupWizard` (`exam_setup_wizard.dart`, route name `/exam-setup`) | the editor's app-bar icon "Paper exam setup" (`exam_authoring_screen.dart`, exam linked to a course); `openQuickExam` after an Offline quick exam with a course (`exam_quick_screen.dart`); a duplicate-identifier push (`AppNavigator` module `exam_identifiers` → the students step) | `GET / PUT exam/setup`, `GET exam/identifiers`, `POST exam/identifiers/request \| remind`, `GET / PUT exam/forms`, `GET /omr/templates`; core `GET /api/v1/identity-fields` | `exam_engine/services/omr_setup.py`; core `services/identity_service.py` |
| Student's identifier | `IdentityRequestGate` (`lib/features/shared/identity/identity_request_gate.dart`, inside the student dashboard next to `DataLabGate`) | app open / resume; push module `identity_requests` | core `GET /api/v1/me/identity-requests`, `POST …/{id}` | `services/identity_service.py`, `routers/identity_router.py` |
| Sheet types | `OmrTemplateLibraryPage` (`templates/omr_template_library.dart`); `OmrTemplateLearnPage` (`templates/omr_template_learn.dart`) | services hub tile "Bubble sheet types" (super admin); the library's "New bubble sheet type"; the wizard's "Upload a custom layout" (teacher) | `POST /omr/templates/learn` (202) → `/steps`, `PUT /boxes`, `/confirm`, `/validate`, `/submit`, `/versions`, `/publish`, `/reject`; `GET / PUT /admin/omr/settings` | `omr_templates.py` + `mlkit/omr/learn.py` (job `omr_learn`) |
| Print | `showOmrSheetsSheet` (`scan/omr_sheets_sheet.dart`) | `OmrScanSection` "Print bubble sheets" | `GET / POST exam/omr/sheets` (PDF) | `omr_sheets.py`, `mlkit/omr/sheets.py` (signed QR `NBO1`) |
| Scan | `OmrScannerScreen` (`scan/omr_scanner_screen.dart`, camera behind `OmrCamera`); `startOmrUpload` → `OmrUploadScreen` / `OmrScanProgressScreen` (`scan/omr_upload_screen.dart`) | `OmrScanSection` "Scan with camera" / "Upload images / PDF" / a latest batch | `POST exam/omr/live-hint` (one small frame), `POST exam/omr/capture`, `POST exam/scans`, `GET exam/omr/batches[/{id}]` | `omr_camera.py` (gate on the request thread, D-159), `scans.py` → one `omr_page` job per page → `omr_scan.run_page_job` (`mlkit/omr/read.read_sheet`) |
| Review | `OmrReviewPage` (`review/omr_review_page.dart`) | `OmrScanSection` "Review" through `OmrRoutes.review`; "Review N" on the progress screen | `GET exam/review-items`, `GET exam/review-items/{item}`, `POST …/resolve`, `GET exam/omr/pages/{page}`, `GET exam/omr/changes`, images `GET /omr/images/{crop\|page}/{id}?exp=&sig=` | `omr_review.py` |
| Results | `OmrResultsPage` (`review/omr_results_page.dart`) | `OmrScanSection` "Results" (`OmrRoutes.results`); the review page's Results icon | `GET exam/omr/results`, `POST exam/omr/results/publish {graded_only?}` | `omr_results.py` |
| Models | `AiModelsPage` (`lib/features/admin/models/`), `ModelDownloadsHost` in the `MaterialApp.builder` stack | services hub tile "AI Models" (super admin); a tap on the floating bar | `/api/v1/models/…` (nginx → the hub, :8003) | `../back/modelhub/` |

`OmrScanSection` (`scan/omr_scan_section.dart`) is the bubble part of `ExamScansScreen` ("Scanned pages",
`exam_scan_review.dart`, reached from Review marking's Scanned pages icon); it shows only when the exam's
`paper_format` is bubble / both and `exam.omr` is on, and folds the older written-answer tools (QR answer sheets,
mapping, marks import) below it. The engine side of a page: quality gate → corner marks → homography → form →
identifier → answers (`mlkit/omr/read.py`), then `omr_scan.apply_page` turns the immutable reading plus the resolved
review items into the paper attempt; it runs again after every human decision, so it is idempotent. Pages and
template learning run on `python -m exam_engine.omr_worker` (compose `exam-omr-worker`, low priority, cores − 2
processes), never on the grading worker (`GRADER_SKIP_KINDS=omr_page,omr_learn`).

Pattern (as in the rest of the folder): a pure, unit-tested file per part (`exam_setup.dart`, `scan/omr_scan.dart`,
`templates/omr_templates.dart`, `review/omr_review.dart`: models, request bodies, server codes in plain words, the
calls) next to screens whose bodies are plain-value widgets the layout harness pumps. The camera is `OmrCamera`
(`scan/omr_camera.dart`): flutter_webrtc on Android / iOS, `package:web` getUserMedia on the web — no camera package.

## Never guess: what is final and what goes to review

The app never decides a grade; it draws what the engine answered. The engine's rules:

- **Image quality.** The gate (`mlkit/omr/quality.py`) rejects with an issue code and the exact instruction in both
  languages (too dark / bright, glare, shadow, blurry, page not found, a corner mark missing, low resolution, …). A
  rejected camera capture stores nothing but an audit row ("Retake"); a rejected uploaded page is kept as `rejected`,
  never graded, and listed under "Pages that need a clearer image" with "Replace this page".
- **Answers.** `clear` → graded with the confirmed form's key. `blank` → the exam's policy `zero` | `review`.
  `multiple` → `wrong` | `review`. `uncertain` → ALWAYS review; the server refuses a policy for it (422
  `policy_uncertain_fixed`), so the wizard shows it as a fact, not a choice.
- **Student ID.** Matched exactly against the audience's normalised values (`exam_engine/identities.py` over the core);
  no match, several matches, an unread ID, or a per-student QR that disagrees with the shaded ID → review.
  Handwritten digits are read by the hub's `digits` role (`digits-cnn@v2-5c5131b9`, served through
  `mlkit.digits.DigitReader`; a super admin activates it on the AI Models page). A handwritten ID is linked only when
  every box is ≥ max(0.999, the model's `auto_accept`), exactly one audience member matches, and no other member's ID
  is one digit away; otherwise review, pre-filled with the reading and the closest candidates (`identifier_unclear`,
  `identifier_neighbour`). With no digits reader (no hub, no active model) every handwritten ID goes to review. In a
  class with sequential numbers almost every handwritten ID is a one-tap confirm; shaded ID grids link by themselves.
- **Form (model A / B / …).** Confirmed when at least one configured marker is read and every read marker agrees;
  two that differ, or none read → "Model could not be confirmed" and nothing on the page is graded (D-156).
- **Handwritten answers (D-160).** Suggestions for the teacher, except a handwritten English completion that matches
  an accepted answer exactly with TrOCR confidence ≥ 0.861 AND the same text from the PP-OCRv5 English recogniser.
  Every Arabic handwritten answer and every short answer goes to the teacher.
- **Publishing.** With open review items the server answers 409 `review_items_open`; only then does the results page
  offer `graded_only` behind a confirmation. A student sees only their own result, once graded and published.
- **History.** `omr_readings` and `manual_changes` are append-only (SQLAlchemy and PostgreSQL triggers refuse an
  UPDATE, D-158); the retention purge (`omr.retention_days`) is the only path that deletes readings.

## Thresholds: where they live, how they were measured

- `../back/mlkit/omr/thresholds.json` — bubbles (`answers`, `identifier`, `form_bubbles`: lo 0.03, hi 0.39,
  dlo 0.02, cmin 0.75), the printed form letter (`printed`: min score 0.544, min margin 0.242), the quality gate
  (`quality`, each edge the midpoint between the good and the bad population, listed in `_gate_tuning`), the camera
  hints (`live`) and `digits`. Tuned by `bench/omr/run.py --tune` on a tuning split for zero wrong auto-grades with a
  ±0.05 margin, then reported by `--report` on a separate split: per `bench/omr/README.md` (2026-11-02, 810 sheets
  with the two framing conditions), 0 wrong of 35 125 auto-graded questions, 13.27 % sent to review overall (6.6 –
  8.2 % on ordinary scans and photos), 270 of 270 bad images rejected, 0 of 540 good ones refused. The set is
  SYNTHETIC (rendered sheets, simulated marks and capture): re-tune on photographed sheets before trusting the review
  rate in the field. `live` and `digits` are not tuned (no camera-frame or handwriting data).
- **Camera framing (bug B5, 2026-11-02).** The live hint works in any frame orientation: the server sizes the app's
  frame (long side 640, unchanged) by its SHORT side, so a sheet held upright in front of a 16:9 web camera is found
  (it used to answer "Fit the whole sheet inside the frame" with the whole sheet in view). "Move closer" is judged on
  how far the corner marks span the frame along its tighter axis (`page_fill`), and the capture says "Move closer"
  only when moving closer can reach the resolution, else "Resolution too low". With a 1920 x 1080 camera and the
  sheet upright, the sheet must fill at least ~84 % of the frame's height to pass the capture gate (3.05 px/mm).
  Numbers: `bench/omr/README.md` "Live hint"; tests `../back/tests/omr/live_hint_camera_unit.py` (the e2e camera frames).
- `../back/mlkit/ocr/handwriting_thresholds.json` — handwriting acceptance per language / engine / unit and
  `completion_final` (the D-160 rule above), calibrated on the datasets' validation split and reported on test by
  `bench/handwriting` (its README holds the numbers).
- `../back/exam_engine/grading/paper_similarity.json` — the cosine rescale that lets short-answer similarity be read
  against the 0.45 / 0.80 bands (`bench/handwriting/short_answer_calib.py`).
- The app's own limits only mirror the server so a person is told at once (`OmrLimits` in `scan/omr_scan.dart`: 50
  files, 25 MB a file, 300 pages, …); the server's are the `OMR_*` settings in `../back/exam_engine/settings.py`.

## Live updates

Nothing polls on a bare timer: every screen waits through `EventOrPoll` (`lib/core/live/event_wait.dart`) with a slow
poll as the fallback.

- `exam_identifiers` (core → the teacher who asked): the wizard's students step (who is ready / missing).
- `job_updated {kind: omr_scan, id: batch, exam_id, …}` (after every page): the progress screen, the review queue,
  the results.
- `job_updated {kind: omr_template, id}`: the learning flow ("Reading your sheet…").
- `model_download`, `model_changed`, `model_alert`: `ModelDownloads.instance` (the floating bar) and the AI Models page.

## Kill switches and settings

- `exam.omr` — every bubble-sheet part: the wizard's bubble choices and sheet step, `OmrScanSection`, the review and
  results pages, the "Bubble sheet types" tile.
- `exam.identifiers` — the wizard's first step and the student's dialog.
- `models.admin` — the "AI Models" tile and the floating download bar.
- Engine settings, not switches: `omr.require_approval` (default on, D-155; the library's "Teachers' sheet types need
  my approval") and `omr.retention_days` (default `OMR_RETENTION_DAYS`, 365; `GET / PUT /api/v1/exam/admin/omr/retention`,
  no app page).
- `MODELHUB_URL` unset on the backend = the readers load in-process as before the hub.

## Tests

- App: `test/org/exam_setup_model_test.dart`, `exam_setup_wizard_test.dart`, `identity_request_model_test.dart`,
  `identity_request_gate_test.dart`, `omr_templates_test.dart`, `omr_template_learn_test.dart`,
  `omr_scan_model_test.dart`, `omr_scanner_test.dart`, `omr_review_test.dart`; layout `test/ui/exam_setup_layout_test.dart`,
  `omr_templates_layout_test.dart`, `omr_scan_layout_test.dart`, `models_hub_layout_test.dart`,
  `models_hub_flow_test.dart`; parsers against recorded replies `test/contract/models_hub_payloads_test.dart` and the
  fixtures in `test/fixtures/payloads/omr_review/`, `omr_templates/`, `models_hub/`; renders (tag `visual`)
  `test/visual/omr_*_golden_test.dart`, `models_hub_golden_test.dart`.
- Backend: `tests/omr/`, `tests/handwriting/`, `tests/modelhub/`, `tests/exam_engine/e2e_omr_*.py`,
  `tests/org_v2/e2e_identity_requests.py`; benches `bench/omr`, `bench/handwriting`.
