# Track F — learning from feedback (chat assistant + exam question generator)

Started 2026-10-28 at the owner's request. Goal: the assistant and the question generator get better from real
use, measurably and safely.

## Principles

1. **Do not fine-tune the generator LLM on the server.** The CPU-only box, a 0.6B / 1.7B model and sparse, noisy thumbs make
   that the riskiest lever with the least measurable gain (the eval shows the model is already the weakest link). A LoRA
   fine-tune stays a documented later phase, offline, only after enough accepted / edited examples, gated by the eval.
2. **Improve what is measurable and reversible:** curated knowledge (Q&A pairs), retrieval (cross-encoder reranker + not-found
   gate thresholds), the evaluation set, and the question generator's exemplars + checker rules.
3. **Human in the loop for anything a user sees:** suggestions are drafts; an admin approves. Nothing is auto-published.
4. **Gated promotion:** every learned artefact (reranker version, thresholds, rules) is proposed → evaluated on the frozen
   eval set + the grown set → promoted only if it does not regress (not-found ≥ 95 %, leaks 0, correctness ≥ current) →
   versioned with one-click rollback.
5. **Tenant isolation:** an organization's feedback improves only that organization (its Q&A suggestions, its exemplars).
   Shared models (reranker) train on app-scope data plus orgs that opted in (`learning.contribute`, default **off**). Question
   text never crosses tenants.
6. **Robust to noise / abuse:** signals are weighted by distinct users, one vote per user per item, rate-limited; suggestions need a
   minimum support (≥ 3 distinct askers or ≥ 2 thumbs-down) before they appear.

## Signals (capture)

| Source | Signal | Exists? |
|---|---|---|
| Chat | thumbs up / down + optional comment | yes (`queries.helpful`, `feedback_comment`) |
| Chat | down-vote **reason** code: `wrong`, `incomplete`, `not_relevant`, `outdated`, `language`, `other` | **new** |
| Chat | implicit: rephrased within 60 s (same conversation), citation opened, deep link followed, "contact support" tapped | **new** |
| Chat | not-found / fallback / low-confidence (already in `trace`) | yes |
| Exam generator | per generated question: `accepted` / `edited` (+ final text, edit distance) / `rejected` + reason (`wrong_answer`, `ambiguous`, `off_topic`, `too_easy`, `too_hard`, `duplicate`, `language`, `other`) | **new** |
| Exam generator | later: item analysis after the exam (p-value, discrimination) from the Exam Engine | **new (read-only join)** |

## Contracts (all agents code against these)

**Tables (migration `rag_0010_learning`, tenant-scoped + RLS like `queries`):**
- `rag.feedback_events(id, created_at, user_id, org_id NULL, scope 'app'|'org'|'course', kind, ref_type 'query'|'exam_item'|'exam_draft', ref_id, value JSON)` — one row per signal; `kind` ∈ `chat_vote`, `chat_reason`, `chat_rephrase`, `chat_citation_open`, `chat_deeplink`, `chat_support`, `exam_item_accept`, `exam_item_edit`, `exam_item_reject`, `exam_item_stats`. Unique (user_id, kind, ref_type, ref_id) for votes.
- `rag.learning_suggestions(id, created_at, org_id NULL, kind 'qa_pair'|'eval_item'|'threshold'|'router_rule'|'exam_exemplar'|'exam_rule', status 'open'|'accepted'|'dismissed', support INT, payload JSON, source_refs JSON, decided_by, decided_at)`.
- `rag.model_versions(id, kind 'reranker'|'thresholds'|'router_rules', version, created_at, metrics JSON, status 'candidate'|'promoted'|'retired', artifact_path, promoted_by, promoted_at)`.

**Routes (RAG service, `/api/v1/rag/learning/…`):**
- `POST /feedback` `{ref_type, ref_id, kind, value}` → 204 (any signed-in user on rows they may see; votes upsert).
- `POST /exam-drafts/{id}/items/{n}/feedback` `{action: accept|edit|reject, reason?, final?: {question, options, answer}}` → 204 (draft owner).
- `GET /suggestions?kind=&status=open&org_id=` · `POST /suggestions/{id}/accept` (qa_pair → creates the Q&A pair via the existing QA code; eval_item → appends to the grown eval set; threshold / router_rule → creates a `model_versions` candidate) · `POST /suggestions/{id}/dismiss`. App scope = platform admins; org scope = org managers.
- `GET /models?kind=` · `POST /models/{id}/promote` · `POST /models/{id}/rollback` (platform admins; promote refuses when the candidate's gate metrics regress).
- `GET /stats?days=` → `{chat: {votes, helpful_rate, reasons{}, rephrase_rate}, exam: {items, accept_rate, edit_rate, reject_rate, reasons{}}, suggestions_open, models: [...]}`.

**Exports for training (files, no API):** `mlops/learning/export_pairs.py` writes JSONL `{"query", "passage", "label" (0/1), "weight", "scope", "org_id"}` from feedback + traces (positives: cited passage of a thumbs-up / accepted answer, passage opened by the user; negatives: retrieved-not-cited passages of thumbs-down `wrong` / `not_relevant`, hard negatives from the reranker's top-k), only app scope + opted-in orgs.

## Jobs (nightly, in the RAG worker's between-jobs tick, idempotent)

1. **Q&A suggestions:** cluster unanswered / thumbs-down questions per scope by embedding (e5, cosine ≥ 0.86, min support), draft an answer from the best extractive passage (or empty), create `qa_pair` suggestions with the cluster's questions as variants.
2. **Eval growth:** thumbs-down + `wrong` / `incomplete` with an admin-accepted correction → `eval_item` suggestion (question, expected keywords, source) → on accept appended to `bench/rag/answer_eval/grown.jsonl` (the frozen 71-q set never changes).
3. **Threshold proposal:** re-run the gate calibration on the eval set + labelled feedback; create a `thresholds` candidate only if it improves found-rate without dropping not-found below 95 %.
4. **Router rules:** frequent questions answered correctly by the same feature-guide entry → `router_rule` suggestion.
5. **Exam exemplars + rules:** accepted / lightly edited questions become few-shot exemplars per (course or org, kind, difficulty, lang), max 3 per prompt, newest high-quality first; frequent reject reasons become checker rules (e.g. `ambiguous` → reject options with overlap; `wrong_answer` → stricter evidence check) proposed as `exam_rule` suggestions.
6. **Reranker retraining (weekly, offline-capable):** when ≥ 500 new labelled pairs: fine-tune mMiniLM cross-encoder (`mlops/learning/train_reranker.py`, torch only in the training env, never in the API image) → ONNX export + INT8 → eval (retrieval@5 on both benches, answer eval with `--generator none`) → `model_versions` candidate with metrics → admin promotes; the worker loads the promoted version.

## Agents

| Id | Scope | Owner files |
|---|---|---|
| F.1 | Capture + learning store + suggestion jobs 1–5 + routes + stats | `rag_service/learning/**` (new), migration `rag_0010`, `models.py` (additive), `examgen.py` (exemplars + rules hook), `routers/learning.py`, `worker.py` (tick, additive), `tests/rag/e2e_rag_learning.py` |
| F.2 | Reranker retraining pipeline + model registry + gated promotion | `mlops/learning/**` (new), `requirements-train.txt`, `bench/rag/**` (eval hooks), docs; runtime loader hook in `mlkit/reranker.py` applied by the coordinator after the CPU-benchmark agent finishes |
| F.3 | App: feedback reasons UI, exam item accept / edit / reject, suggestions inbox, learning stats + model versions page | `lib/features/shared/rag/**` (learning files), `lib/features/shared/exam_engine/exam_generate*.dart`, tests |
