# RAG client and the app assistant — `lib/features/shared/rag/`

This file is loaded when working in this folder; the app-wide rules are in the root `CLAUDE.md`. The Exam Engine client (incl. generated exam questions): `lib/features/shared/exam_engine/CLAUDE.md`.

**App assistant and the features guide** — `AppAssistantHost` (`lib/features/shared/rag/app_assistant.dart`, in `MaterialApp.builder`) floats the app assistant (`RagChatView(app: true)`) above every signed-in screen (kill switch `rag.app_assistant`; full-screen pages call `AppAssistant.hide()` / `release()`). It answers from the app library: uploaded guides plus the core's terms, about and **features guide** pages — and, while the person is in Organization mode, from that organization's library and synced rules too (`app: true` + `org_id`, `appAssistantOrg`, D-012). Answers come from the server's model pipeline (plan → search → write → verify, `../back/rag_service/pipeline.py`, D-054; by default a LOCAL open-weight model on the server, Qwen3 INT4 on ONNX Runtime, D-055 — answers take ≈ 10–15 s with the default 0.6B build and about a minute with the 1.7B, so the stage trail matters): `RagAnswer` carries `followUps`, `stage` and `generator`; `answerBlocks` renders paragraphs / bullets / numbered steps / **bold**; `RagStageTrail` shows the step while polling. An empty chat shows the server's starter questions (`RagApi.starters` → `GET /api/v1/rag/starters`, built from the headings the asker may read; `ragStartersFrom`), and the built-in `ragStarterPrompts` only when the library has none. The Super Admin's console is `rag_admin_console.dart` (`/api/v1/rag/admin/…`: settings, overview, playground with the trace, questions), opened from the admin services hub; `RagAdminSettings.llmLocal` / `light` (the local model's light profile) hide the effort / model knobs and the external-consent switch and show the model's files status instead. Exam drafts (`exam_generate.dart`) take `difficulty`, `focus`, `lang` and return `review` (what the planner / writer / reviewer agents did; `examGenSummary`). Tests: `test/org/rag_premium_test.dart`. **When you add a user-facing feature, add it to `../back/data/app_features_guide.json`** (group, roles, Arabic + English name, summary, place, steps, the kill-switch keys that hide it — D-052). The super admin manages the guide in `AdminFeatureGuidePage` (`lib/features/admin/admin_feature_guide.dart`, opened from the app assistant dashboard and the Features page): edit / add / delete, and per feature "App" (switches all its kill-switch keys on every platform) and "Assistant" (whether it is explained; a feature hidden in the app never is). **A new kill-switch key** goes into `../back/services/feature_catalog.py`, then regenerate the snapshots (same command as the API contract test): `test/contract/feature_keys_test.dart` fails on a key the catalog lacks, because a super admin could never switch it off.


## Multi-tenant RAG job (D-190 – D-198) — what the app does now
- **Answer payload**: every answer carries `mode` (`generate|retrieval|tool|rule|small_talk`), `chunks`, `actions`, `tool`; older
  servers send none of them, so read each with a default. `retrieval` mode shows the passages (`chunks`, with document / page /
  section) instead of a written text. `GET /queries/{id}/stream` (SSE: `delta`, `done`, `error`) streams the text; fall back to
  polling `GET /queries/{id}` when the stream fails.
- **Action buttons**: an `actions` entry is `{page_id, params, label, org_id?}`; open it ONLY through `AppRoutes.location(page_id,
  params)` (D-170) / `AppNavigator`, never build a route by hand; `org_id` opens it inside that organization; drop an action whose
  `page_id` the app does not know. The old `deep_link` citation still works for servers without actions.
- **Personal questions**: `mode: tool` answers come from the core with the asker's own data; never cache them client-side beyond the
  chat history, and never offer them in a feedback list.
- **Upload screen**: scopes are `app`, `global` ("All students", platform admins only), `org` (+ optional `roles` chips, org roles
  only), `staff`, `course` (teachers keep it). Hint text and limits come from `GET /documents` -> `upload {ocr_scanned, max_doc_mb}`
  or `GET /api/v1/rag/upload-settings` (same block; signed in): say whether scanned PDFs are read and show the size limit.
  Document rows show `progress_done / progress_total` while processing, `warnings` (`partially_scanned` with `pages`), `skipped_pages`
  and `excluded`. Errors: 413 `too_large` (`limit_mb`), 422 `images_not_accepted`, `no_readable_text` (was `no_text:`), `bad_roles`,
  `roles_only_org`, `bad_scope` — each needs a text in the error mapper.
- **Feedback review** (super admin console + org library): `GET /admin/feedback/clusters` / `/orgs/{id}/answers/feedback/clusters`,
  verify with `POST …/clusters/{key}/verify`; course pairs through `/qa` with `scope: course`.
- **Console**: cache card (`GET /admin/cache`, `POST /admin/cache/clear`), settings `answer_mode`, `ocr_scanned`, `max_doc_mb`,
  `cache.*`, `learning.embedder_*`; "Train the search model" = `POST /learning/embedder/train` + `GET /learning/embedder/status`
  (a job: wait with `JobWatch` / `EventOrPoll`, no timer). The writer LoRA is gone from the UI (`lora: {disabled: true}`).
- **Models page**: per-task roles (`generation.chat`, `generation.exam`, `grading`); activating a model answers 202 and downloads first;
  show `GET /models/downloads` progress, then the automatic switch.
- **Info (i) button + help**: `GET /api/v1/help/pages/{page_id}` (cache by `GET /help/version`, ETag), `/help/flows`; kill switches
  `help.info`, `admin.help`. The button attaches to a page by its D-170 id (or `home.<role>/<tab>`).

