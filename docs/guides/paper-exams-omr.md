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
| Print | `showOmrSheetsSheet` (`scan/omr_sheets_sheet.dart`; named sheets picked by name with `OmrAudiencePicker`, `scan/omr_audience_picker.dart`) | `OmrScanSection` "Print bubble sheets"; the "Paper exam" card's "Print bubble sheets" | `GET / POST exam/omr/sheets` (PDF), `GET exam/omr/students?q=&limit=50` | `omr_sheets.py`, `mlkit/omr/sheets.py` (signed QR `NBO1`) |
| Scan | `OmrScannerScreen` (`scan/omr_scanner_screen.dart`, camera behind `OmrCamera`); `startOmrUpload` → the source sheet (`scan/scan_sources.dart`) → `OmrScanProgressScreen` (`scan/omr_upload_screen.dart`) | `OmrScanSection` "Scan with camera" / "Upload papers" / a latest batch | `POST exam/omr/live-hint` (one small frame), `POST exam/omr/capture`, `POST exam/scans` (in parts, `batch_id`), `GET exam/omr/batches[/{id}]` | `omr_camera.py` (gate on the request thread, D-159), `scans.py` → one `omr_page` job per page → `omr_scan.run_page_job` (`mlkit/omr/read.read_sheet`) |
| Review | `OmrReviewPage` (`review/omr_review_page.dart`) | `OmrScanSection` "Review" through `OmrRoutes.review` (also for "Exam paper only": the written answers with their crops); the "Paper exam" card's "Review"; Review marking's banner and "Review it on the paper image" on a scanned answer; "Review N" on the progress screen | `GET exam/review-items`, `GET exam/review-items/{item}`, `POST …/resolve`, `GET exam/omr/pages/{page}`, `GET exam/omr/changes`, images `GET /omr/images/{crop\|page}/{id}?exp=&sig=` | `omr_review.py` |
| Results | `OmrResultsPage` (`review/omr_results_page.dart`) | `OmrScanSection` "Results" (`OmrRoutes.results`); the "Paper exam" card's "Results"; the review page's Results icon | `GET exam/omr/results`, `POST exam/omr/results/publish {graded_only?}` | `omr_results.py` |
| Models | `AiModelsPage` (`lib/features/admin/models/`), `ModelDownloadsHost` in the `MaterialApp.builder` stack | services hub tile "AI Models" (super admin); a tap on the floating bar | `/api/v1/models/…` (nginx → the hub, :8003) | `../back/modelhub/` |

Every paper exam (delivery paper, any `paper_format`) carries the "Paper exam" card, `PaperExamEntry`
(`paper/paper_exam_entry.dart`): on top of its results page (`exam_results_screen.dart`), on the editor's Settings and
Publish tabs with an app-bar icon (`exam_authoring_screen.dart`), and as "The paper exam is ready" at the end of the
quick builder once the setup is finished (`openQuickExam`). It opens the paper section and goes straight to print,
review and results, from before the first scan until after the last paper is graded (it never depends on something
waiting). `OmrScanSection` (`scan/omr_scan_section.dart`) is the bubble part of `ExamScansScreen` ("Scanned pages",
`exam_scan_review.dart`, the paper section); it shows when the exam's `paper_format` is bubble / both and `exam.omr`
is on, and folds the older written-answer tools (QR answer sheets, mapping, marks import) below it. For "Exam paper
only" the section keeps those tools on top and adds `OmrScanSection(bubble: false)` ("Written answers": Review and
Results only). The engine side of a page: quality gate → corner marks → homography → form →
identifier → answers (`mlkit/omr/read.py`), then `omr_scan.apply_page` turns the immutable reading plus the resolved
review items into the paper attempt; it runs again after every human decision, so it is idempotent. Pages and
template learning run on `python -m exam_engine.omr_worker` (compose `exam-omr-worker`, low priority, cores − 2
processes), never on the grading worker (`GRADER_SKIP_KINDS=omr_page,omr_learn`).

Pattern (as in the rest of the folder): a pure, unit-tested file per part (`exam_setup.dart`, `scan/omr_scan.dart`,
`templates/omr_templates.dart`, `review/omr_review.dart`: models, request bodies, server codes in plain words, the
calls) next to screens whose bodies are plain-value widgets the layout harness pumps. The camera is `OmrCamera`
(`scan/omr_camera.dart`): flutter_webrtc on Android / iOS, `package:web` getUserMedia on the web — no camera package.

### Smart photos and print modes (the app side)

- Live hints: `blocking: false` on a `live-hint` answer ("Add a little more light", "Hold steady") is drawn as a soft
  tip (`OmrHintTone.gentle`), and such a frame may still be captured by itself (`OmrLiveHint.capturable`: `ready`, or
  non-blocking and not a scene-changing code — no sheet / corners / moving / move closer never capture). An older
  server (no `blocking`) captures on `ready` only.
- The camera asks for an `ideal` 1920 × 1080 stream (what the phone gives, no high-resolution mode); the native
  capture (Android q100 JPEG, iOS PNG) is re-encoded as a JPEG q90, long side ≤ 2560, unless it is already a JPEG
  ≤ 1.5 MB (`omrPhotoPlan` / `omrUploadPhoto`); the browser's canvas JPEG goes as it is.
- Every page's `result` (capture, batch `pages` / `rejected_pages`, page, replace) is `OmrPageResult`; the widgets are
  in `scan/omr_paper_result.dart`: the camera card says "Read successfully" / "Read with 3 questions to review" /
  "Read in part — …" (+ Retake and Carry on: a suggestion, the shutter stays) / "Couldn't read this paper" (+ reason,
  tip, the blocking Retake), with a thumbnail of `preview_url` (loaded by `OmrScanApi.image`, the signed-image call)
  that opens `showOmrPreview` (Retake there; "Replace this page" for a rejected upload). The progress screen lists the
  papers worth a look first and folds those read successfully.
- Print (`scan/omr_sheets_sheet.dart`): only the `modes` the describe lists (Pre-filled · Name only · Blank, one line
  each; Pre-filled missing → one line why: `prefilled_reason`, else from the ID kind), order By name / By student
  number, an Index page switch (on). The ids go as chosen (the server sorts). `mode` / `order` / `index` are sent only
  to a server that listed `modes` (an older one refuses unknown fields). Fixtures:
  `test/org/fixtures/omr_smart_payloads.json` (the contract's fields on recorded replies); tests
  `test/org/omr_smart_photos_test.dart`.

## Getting the pages in: camera, gallery, files, a scanner's folder

Both paper kinds take pages the same way: bubble sheets ("Upload papers" in `OmrScanSection`, and "Upload more" /
the camera's "Upload instead" on the progress screen) and written-answer / QR sheets ("Upload scans" in
`PaperToolsPanel`, `exam_scan_review.dart`). One sheet, `showScanSourceSheet` (`scan/scan_sources.dart`), says where
they come from and offers only what works on the device (`ScanPlatform`, `scanSourcesFor`):

| | Live camera | Photo gallery | Files (images + PDFs, mixed) | A scanner's folder |
|---|---|---|---|---|
| Android app | bubble path | `image_picker` `pickMultiImage` (system Photo Picker, no permission) | `file_picker` | `ScanFolderChannel.kt`: the system folder picker (SAF tree), walked and read through `DocumentsContract`, no storage permission |
| iOS app | bubble path | `image_picker` (PHPicker; HEIC comes back as JPEG) | `file_picker` (Files app) | not offered: no folder access; the sheet says "choose Files, open the folder, tap Select" |
| Phone browser (Android / iOS) | bubble path | `file_picker` `FileType.image` = `<input accept="image/*" multiple>` (the phone offers Photos / Camera) | `file_picker` | not offered (phones' browsers ignore `webkitdirectory`); same hint |
| Computer browser | bubble path | not offered (Files covers it) | `file_picker` | `scan/scan_folder_web.dart`: `<input webkitdirectory multiple>` through `package:web` |
| Desktop app (Windows / macOS / Linux) | bubble path | not offered | `file_picker` | `file_picker` `getDirectoryPath` + a `dart:io` walk (`scan/scan_folder_io.dart`) |

The written path has no live camera (the scanner reads bubble sheets); a phone's gallery covers photos there. A tap
starts the platform dialog inside the tap (a browser opens one only on a user gesture), then the sheet closes. Why
not `getDirectoryPath` + `dart:io` on Android: scoped storage hides another app's files (a scanner app's PDFs) from
`java.io` / `dart:io` without `MANAGE_EXTERNAL_STORAGE`; `getDirectoryPath` without SAF options only returns a path.

What a pick holds is shown before anything is sent (`ScanPickSummary`, `scan/scan_upload_view.dart`): "12 files
found", images / PDFs / skipped, the skipped ones with the reason (not an image or a PDF, an empty file, a PDF over
25 MB). `planScanFiles` (`scan/scan_files.dart`) drops hidden and system files silently (`.DS_Store`, `._x`,
`Thumbs.db`, `desktop.ini`, `~$x`, anything under a dot-folder or `__MACOSX`), refuses a pick over 2000 files whole
(the wrong folder), and sorts in natural file order folder by folder (`page2` before `page10`, a folder's own files
before its sub-folders); a gallery keeps the order the photos were chosen in. Accepted: JPG, PNG, WebP, PDF, and HEIC
/ HEIF / TIFF converted on the device.

Sending (`ScanUploader`): files are read only when their part goes. A part is ≤ 8 MB and ≤ 20 files (production's
nginx took 10 MB on the engine's routes; a larger single file goes alone and needs the scans location below); the
first part's `batch_id` is sent with every later part, so the server adds the pages to that ONE batch (`POST
exam/scans` `batch_id`, the caller's own batch of the same kind, else 404 `batch_not_found`) and the progress screen
follows one "X of N papers processed". "Uploading 3 of 12 files" while it runs. A part refused for one file
(`bad_pdf`, `bad_image`, `image_too_large`, `too_many_pages`, `page_too_large`, `unsupported_file`, 413) is sent again
file by file, so only that file fails; a network / busy failure fails its part and the next parts still go; a stop
failure (no rights, the exam cannot take scans, the batch is gone) ends the run and lists the rest. The failures are
listed with their reason and "Retry N files" (into the same batch). Pages the exam already has are skipped by the
server (sha256) and counted ("N pages were already uploaded and skipped").

Preparing a file (`prepareScanFile`, `scan/scan_prepare.dart`; the bytes are sniffed, not the name): a PDF and a
picture from files / a folder go untouched (the server reads the EXIF orientation: OpenCV's `imdecode` turns the
page); only a picture the server would refuse (over 25 MB or 40 MP) is re-encoded as JPEG with its long side ≤ 3508
px (A4 at 300 dpi). A gallery photo on the apps comes from `image_picker` already scaled to ≤ 3000 px (native, no
48 MP decode in Dart) and is sent as it is when ≤ 3 MB, else re-encoded to ≤ 3000 px. 3000 px keeps ≥ 10 px/mm on an
A4 that fills the photo (the reader measures bubbles at 6 px/mm and cuts ID / handwriting crops at 12; the live
camera sends ≤ 1920 px frames, the server renders PDFs at 2480). A phone browser's gallery photo is sent as the browser
gives it (re-encoding in the page costs seconds per photo). Decoding is the engine's (`instantiateImageCodecWithSize`:
Skia / the browser), which applies the EXIF orientation, so a re-encoded photo is upright with no orientation tag.
HEIC is decoded by the platform (iOS, Android 9+, macOS, Safari); where it cannot be, that file fails with "save it as
JPEG". A TIFF becomes one JPEG per page (`package:image`, in an isolate on the apps). A replacement page ("Replace
this page" on the progress screen and the page view) uses the same sheet in single mode (gallery on a phone, files;
images only).

Gateway: `../back/deploy/nginx/nextbrain.conf.example` has a regex location for `POST exam/exams/{id}/scans` with
`client_max_body_size 52m` (the engine's own cap is 2 × 25 MB); the rest of the engine keeps 10 MB.
`../back/scripts/dev/nginx.dev.conf` does the same.

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
  A shorter value on a shaded grid links whether it is shaded with blank columns around it or zero-padded
  (`0002024003` → `2024003`: shaded readings compare digits without leading zeros, `omr_scan.match_identifier`); two
  students whose values differ only by leading zeros → review `identifier_duplicate`.
- **Does the identifier fit the ID zone?** Checked before printing (`omr_setup.zone_fit`, mirrored by
  `identifierZoneFit` in `exam_setup.dart`) against the shaded columns / handwritten boxes (printed / QR zones are not
  checked). `block` — a name or an e-mail, or the field's shortest allowed length is longer than the zone (a 14-digit
  national ID on the built-ins' 10 columns): the setup still saves, but blank sheets are refused 409
  `identifier_zone_mismatch` and only named sheets per student print (their signed QR identifies the student).
  `warn` — some holders' values are too long / not digits, or missing students may still type one: printing goes on.
  The wizard's `IdZoneFitCard` says so with the fixes under the chosen sheet type, on Students once a sheet is pinned,
  and on Models (the server's `identifier_fit`).
- **Requests before the type.** The wizard asks for missing values on its first step, before the exam is paper; when a
  setup PUT changes `delivery`, the engine has the core update every pending request's `paper` flag (and give a paper
  one without a due date the exam's start), so the student's dialog and reminders say "before exam day".
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

- App: `test/org/exam_setup_model_test.dart`, `exam_setup_wizard_test.dart`, `exam_setup_id_fit_test.dart` (the ID-zone
  check over replies recorded from `e2e_omr_id_fit.py`, `test/org/fixtures/omr_id_fit_payloads.json`), `identity_request_model_test.dart`,
  `identity_request_gate_test.dart`, `omr_templates_test.dart`, `omr_template_learn_test.dart`,
  `omr_scan_model_test.dart`, `omr_scanner_test.dart`, `omr_review_test.dart`, `scan_sources_test.dart` (the source
  sheet per platform, folder plan / order, parts and batch_id, failures and Retry, EXIF turn, HEIC / TIFF, both upload
  screens, layout); layout `test/ui/exam_setup_layout_test.dart`,
  `omr_templates_layout_test.dart`, `omr_scan_layout_test.dart`, `models_hub_layout_test.dart`,
  `models_hub_flow_test.dart`; parsers against recorded replies `test/contract/models_hub_payloads_test.dart` and the
  fixtures in `test/fixtures/payloads/omr_review/`, `omr_templates/`, `models_hub/`; renders (tag `visual`)
  `test/visual/omr_*_golden_test.dart`, `scan_sources_golden_test.dart`, `models_hub_golden_test.dart`.
- Backend: `tests/omr/`, `tests/handwriting/`, `tests/modelhub/`, `tests/exam_engine/e2e_omr_*.py`,
  `tests/exam_engine/e2e_scan_parts.py` (an upload in parts joins one batch),
  `tests/org_v2/e2e_identity_requests.py`; benches `bench/omr`, `bench/handwriting`.
