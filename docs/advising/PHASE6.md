# Phase 6 — Early warning: brief and contract

Read `PLAN.md` §3.2 (`adv_risk_rules`, `adv_risk_events`, `adv_notice_log`, `adv_student_stats`), §3.5, §3.8, §4 row
"6 Early warning", `PHASE2.md` (common rules unchanged: own worktree only, `git commit --only`, never push or merge,
`-j 2`, the Python venv, Arabic + English, no placeholders, lead-owned files, report ≤ 15 lines), `PHASE3.md` "Shared
rules" (roles, list envelope `{items,total,page,size,pages,facets}`, error shape `{code,message,message_en}`, audit +
notices, every route: kill switch → eligibility → enabled, then the role) and `PHASE4.md` "Who sees what" (an advisor
asking for a student they don't advise → 404 `advising_not_found`; sensitive categories → owner / primary / manage
only, reads audited). Brief requirements covered: early-warning rules configurable by the organization admin
(thresholds edited without code), alerts with their explanation, the advisor digest option, proactive nudges,
graduation-delay risk, retry-safe observable jobs; defaults #7 (alert lifecycle: rule alerts ARE Phase 4 flags),
#13, #20 and #21 (the risk score) as PLAN §4 assigns them.

Worktrees: backend `wt-back-adv-p6`, app `wt-front-adv-p6`, branch `feature/academic-advising-p6` (runs next to
Phase 5 and Phase 7; the lead merges and rechains the migrations).

## Decisions (made here; state them in the report if you deviate)
- **Rules are org-level rows** (`adv_risk_rules`, seeded in Phase 2). Several rules of one kind are allowed (e.g.
  `gpa_below` 2.00 high + `gpa_below` 1.50 urgent). A rule may be limited to a scope `{program_id, level, cohort}`
  (any field null = any). Seeded (`system`) rules can be edited and switched off, never deleted. At most 50 rules per
  organization. Kinds, parameters and limits come from ONE pure catalog (`risk_rules.KINDS`), served to the app so
  the editor is generated from it (no kind is hard-coded in the app beyond its icon).
- **Kinds and what they read** (all bulk, one query per source per 500 students, never per student):

  | kind | params (default · limits) | fires when | level (higher = worse) | term key |
  |---|---|---|---|---|
  | `gpa_below` | `threshold` 2.00 · 0.50–5.00 | CGPA < threshold | 1 + ⌊(threshold − CGPA) / 0.25⌋ | current term |
  | `gpa_drop` | `drop` 0.50 · 0.10–2.00 | last graded term GPA ≤ CGPA − drop | 1 + ⌊(Δ − drop) / 0.25⌋ | that graded term |
  | `failed_courses` | `count` 2 · 1–20 | courses whose counted attempt is a fail ≥ count | failed − count + 1 | `all` |
  | `repeated_fail` | `count` 2 · 2–5 | one course failed ≥ count times | max fails − count + 1 | `all` |
  | `absence_pct` | `percent` 15 · 1–100 | highest absence % of a current course ≥ percent | 1 + ⌊(abs − percent) / 5⌋ | current term |
  | `absence_count` | `count` 6 · 1–100 | missed sessions in one current course ≥ count | missed − count + 1 | current term |
  | `no_contact` | `days` 45 · 7–365 | days since the last contact (or since the primary assignment began, when never contacted) ≥ days; only students with a primary advisor | ⌊days / threshold⌋ | current term |
  | `graduation_delay` | `terms` 1 · 1–6, `planned_terms` null · 2–20, `min_terms` 2 · 1–10 | projected delay ≥ terms (below) after ≥ min_terms regular terms | delay − terms + 1 | current term |
  | `midterm_fail` | `percent` 50 · 1–100 | a current course's midterm mark < percent | courses below | current term |

  Sources: CGPA / earned credits / stage from `OrgStudentAcademic`; last term GPA, failed counts, repeats from the
  student's approved registrations through the registrar's helpers (`P.Attempt`, `P.counted_attempts`, `P.term_gpa`,
  `P.is_pass` — no second GPA formula, the same as `stats.academic_facts`); absence % = `OrgRegistration.absence_pct`
  (the registrar's hourly attendance pass keeps it); missed sessions = round(absence % × sessions held so far in the
  course this term / 100) (held sessions: one grouped count per run); midterm = `OrgRegistration.interim_percent`
  (new entry routes below); last contact = `adv_student_stats.last_contact_at` merged with the latest contact note
  (Phase 4 rules; completed appointments arrive through the stats row once Phase 5 writes them); "current term" =
  the organization term containing today (org timezone), else the latest one that started; no term → key `0`.
- **Graduation projection** (pure `graduation.py`, shown in the 360 and the graduation list for every student even
  when the rule is off): credit-hour programs with a total (`OrgProgram.total_credits`, else the sum of its
  requirement groups' `min_credits`): `terms_done` = regular terms (term1 / term2) that ended since the student's
  first registration term; the current regular term counts with its registered credits assumed passed;
  `max_load` = the registrar's `load.regular.max`; `projected = terms_done + current + ⌈remaining / max_load⌉`;
  `planned` = the rule's `planned_terms`, else 2 × the organization's level count, else 8; `delay = projected −
  planned` (≥ 0). Status: `graduated` (stage) · `delayed` (delay ≥ 1: on time is impossible even at the maximum
  load) · `at_risk` (needs more than the middle of the regular load band — (min + max) / 2, 15 by default — per
  remaining planned term) · `on_track` · `unknown` (`reason` `no_program` · `no_total` · `no_terms`). Traditional
  (year) programs: level-based — expected level index = ⌊terms_done / 2⌋ (capped at the last level), actual = the
  member's `academic_level`; delay = 2 × (expected − actual) when positive (`basis: "levels"`).
- **Firing, de-duplication, cool-down** (pure `risk_rules.should_fire`): a match fires an alert when there is no
  earlier alert of that rule for that student, OR the cool-down (`cooldown_days`) has passed, OR the new level is
  worse than the last alert's level (a worsening never waits). `dedupe_key = "{org}:{rule}:{member}:{term_key}:{level}"`
  is UNIQUE and inserted with ON CONFLICT DO NOTHING, so a re-run, a retry after a crash, two workers, or "Run now"
  during a tick never create a second alert for the same situation: a persisting situation re-alerts at most once
  per term per level, and only after its cool-down.
- **Alerts are Phase 4 flags.** Each new alert attaches to the student's ONE open rule flag of the rule's category
  (`source="rule"`, statuses open · acknowledged · contacted); none → a new flag (owner = the primary advisor, else
  none; `created_by` null; priority = the alert's). A higher-priority alert raises the flag's priority. The Phase 4
  lifecycle, SLA escalation, review reminders, history and stats apply unchanged; resolving / dismissing the flag
  does not stop a later alert (a new flag opens when the cool-down allows). A rule without a category uses the
  organization's `academic` category. Audit: `advising.flag_create` / `advising.flag_update` with actor null and
  `meta {"via": "rule", "alert_id"}` (structured fields only, like Phase 4).
- **Explanations** are rendered on read from the stored `evidence` by pure `explain.py` (Arabic + English), so wording
  fixes apply to old alerts; evidence keeps the numbers and course codes as they were when the alert fired, e.g.
  `gpa_below` "CGPA 1.62 is below 2.00" / «المعدل التراكمي 1.62 أقل من 2.00»; `gpa_drop` "Last term GPA 1.80 is 0.60
  below the CGPA 2.40 (limit 0.50)"; `absence_pct` "22.5 % absence in CS101 (limit 15 %)"; `no_contact` "No contact
  for 52 days (limit 45)"; `graduation_delay` "45 of 132 credits after 6 terms: graduation needs at least 11 terms,
  3 more than the 8 planned"; `midterm_fail` "Midterm below 50 % in 2 courses: CS101 38 %, MA102 45 %".
- **Who is told** (after the run's flags are committed, from the run's `pending` alerts, so a crash between the two
  is delivered by the next run): urgent → the Phase 4 `flag_urgent` notice (the student's advisors who may read the
  flag + the directors, once per flag). Otherwise each active advisor of the student (only the primary one for a
  sensitive category) whose effective digest is `off` gets ONE notice per run: `warning_alert` naming the student
  when it is one alert, `warning_alerts` with counts when several. Advisors on `daily` / `weekly` get nothing now:
  the alert waits for their digest. Alerts of students without an active advisor → the directors, one grouped
  `warning_unassigned` per run. Each alert records its `delivery`: `urgent` · `single` · `digest` · `none`.
  Notices never carry the rule, the category or a number (a push can show on a locked screen, Phase 4 rule); the
  explanation is read in the app.
- **Digest** (#20): the policy's existing `digest` (off · daily · weekly) is the organization default; each advisor
  may override it for themselves (`adv_alert_prefs`). Sent at `digest_hour` (org local time, default 7) — on
  `digest_weekday` for weekly (default 6 = Sunday) — by the first tick at or after that hour that day (dedupe
  `adv_digest:{user}:{local date}`), only when there is something to say: new alerts of the advisor's current
  students since their last digest, and the count of their students without contact this term.
- **Nudges**: advisors (`nudge_advisors`, default on) — once a week at the digest hour, when the current term is at
  least `nudge_after_days` (default 21) old: "N of your students have had no contact this term" (primary advisees,
  not graduated, last contact before the term started or never); folded into the digest instead when the advisor
  gets one that day. Students (`nudge_students`, default on) — once per term, same day rule: a student with a primary
  advisor and no contact this term is told who their advisor is and how to reach them (office / contact note, Phase 3
  `contact_details`). **Waiting for Phase 5** (its tables are not read here): students' unanswered advisor messages
  and missed appointments (re-book). They plug into `digest.student_nudges` as two more sources at the merge.
- **Risk score** (#21): `score.py` weights and stats stay as Phase 4 built them; rule alerts move the score through
  the open-flag part (they are flags). The score is the comparable index; rules are the configurable triggers.
- **The engine** (`warning_engine.run(db, org, trigger, actor, member_ids=None)`): live, non-graduated students in
  chunks of 500 (member id order): build the facts → evaluate every enabled rule → insert alerts → attach / open
  flags → `stats.refresh` for students whose flags changed → upsert `adv_risk_state` (facts, current hits, graduation)
  → commit per chunk; then deliver. A failed chunk rolls back, the run ends `failed` with an error code, and the next
  run redoes it (idempotent). Observable: one `adv_warning_runs` row per run with its counts and duration, an audit
  summary `advising.warning_run`, and `job_updated` `{kind: "advising_warning", id: run_id, status, org_id}` to the
  person who pressed Run now.
- **Jobs**: one new APScheduler job `org_advising_warning_tick` every 15 minutes. Per organization with advising on
  and `org.advising.warning` on: evaluation when the claim `adv_warn:{org}` (55 min, = hourly) is free and no run is
  going (`adv_warn_run:{org}`, 30 min, released at the end); digests and nudges under `adv_digest:{org}` (14 min). A
  `running` row older than 30 minutes is closed as `failed` (`stale`) by the next run. The registrar's hourly tick
  refreshes absence % on its own schedule; an alert reads data at most an hour old.
- **Midterm marks**: the column exists since Phase 2 but nothing wrote it; this phase adds the entry (instructor of
  the course, or staff with `academic update`) as new registrar routes in their own files. A mark can be set or
  cleared while the course grade is not approved. `midterm_fail` ships ON for new organizations; the migration
  switches it on for existing ones only where it was never edited (`updated_by` null).
- **Kill switch** `org.advising.warning` (not org-manageable): off → every route below 403 `feature_disabled`
  (`feature: org.advising.warning`), the engine, digests and nudges stop; Phase 4 flags keep working.

## API (base `/api/v1/org/orgs/{org_id}/advising`; manage = org admin / advising director; advisor = active assignment)

### Rules (#13)
- `GET /rules` (manage · advisor read-only) → `{"items":[Rule],"kinds":[Kind],"engine":{"enabled": bool,
  "running": Run|null,"last_run": Run|null,"next_run_at": iso|null},"can_edit": bool}`
  - `Rule` = `{"id","key","kind","name_ar","name_en","custom_name": bool,"params":{..},"priority",
    "cooldown_days","enabled","system","category":{"id","key","name_ar","name_en","sensitive"}|null,
    "scope":{"program_id","level","cohort"}|null,"summary":{"ar","en"},"updated_at","updated_by":{"user_id","name"}|null}`
    (`name_*` = the custom name, else the kind's label; `summary` e.g. "CGPA below 2.00").
  - `Kind` = `{"kind","label_ar","label_en","help_ar","help_en","default_priority","default_cooldown_days",
    "params":[{"key","type":"number"|"int","min","max","step","default","nullable": bool,
    "unit":"gpa"|"percent"|"count"|"days"|"terms","label_ar","label_en"}]}`.
- `POST /rules` (manage) `{"kind","params","priority","cooldown_days" 0–365,"enabled","category_id": int|null,
  "scope":{..}|null,"name_ar": str ≤ 120|null,"name_en": str ≤ 120|null}` → 201 `Rule` (key `{kind}_{n}`).
- `PUT /rules/{id}` (manage) whole object, same body without `kind` → `Rule`.
- `DELETE /rules/{id}` (manage) → 204; a system rule → 409 `advising_rule_system` (switch it off instead). Alerts
  keep their evidence (rule link set null; the list shows the evidence's rule name).
- `POST /rules/preview` (manage) `{"kind","params","scope"}` → `{"matches": int,"students": int,
  "evaluated_at": iso|null,"needs_run": bool,"sample":[{"member_id","name","code","explanation":{"ar","en"}}]}`
  (≤ 10) — evaluated over the stored facts of the last run, no write.
- Errors: 422 `advising_bad_rule` (+ `field`, `reason`: unknown kind / param / out of range / bad scope ref),
  422 `advising_bad_category`, 409 `advising_rule_limit` (50), 404 `advising_not_found` (another org's rule),
  429 `advising_rate_limited` (the Phase 4 `adv_write` budget). Every write audited (`advising.rule_create` ·
  `rule_update` · `rule_delete`, before / after).

### Engine runs
- `POST /warning/run` (manage) → 202 `{"run": Run}`; the run continues after the answer (BackgroundTasks, own session).
  409 `advising_run_busy` (+ `run_id`) while one runs; 429 `advising_rate_limited` after 3 manual runs in 10 minutes.
- `GET /warning/runs?kind=evaluate|digest&page=&size=` (manage) → envelope of `Run`; `GET /warning/runs/{id}` → `Run`.
  `Run` = `{"id","kind":"evaluate"|"digest","trigger":"tick"|"manual","status":"running"|"done"|"failed",
  "actor":{"user_id","name"}|null,"counts":{"students","matched","alerts","suppressed","flags_opened",
  "flags_updated","notified","digest_waiting","digests","nudges_advisors","nudges_students"},
  "error": str|null,"started_at","finished_at","duration_ms"}` (counts that do not apply are 0).
- `POST /students/{member_id}/warning/run` (manage · the student's advisor) → the `GET …/warning` body after
  evaluating that student now (synchronous; `adv_write` budget).

### Alerts (#7)
- `GET /alerts?member_id=&rule_id=&priority=&since=&flag=open|closed|all&page=&size=` (manage: org; advisor: own
  students; newest first) → items `{"id","member_id","student":{"name","code"},"rule":{"id": int|null,"key","kind",
  "name_ar","name_en"},"priority","level","category":{..brief..}|null,"evidence":{..},"explanation":{"ar","en"},
  "term":{"id","label","kind"}|null,"fired_at","flag":{"id","status"}|null,"delivery":"urgent"|"single"|"digest"|
  "none"|"pending"}`; facets `{"urgent","high","last_7d"}`; envelope `restricted` = alerts in the caller's scope they
  may not read (sensitive category, not primary / manage). Sensitive alerts returned → one `advising.sensitive_read`.
- `GET /flags/{id}/alerts` → `{"items":[alert items]}` (the flag's readers; [] for a manual flag).
- `GET /alerts/prefs` (manage · advisor) → `{"digest":"inherit"|"off"|"daily"|"weekly","effective":"off"|"daily"|
  "weekly","org_default","digest_hour","digest_weekday","timezone","last_digest_at": iso|null}`;
  `PUT /alerts/prefs` `{"digest"}` → same (audited `advising.alert_prefs`).

### Student 360 and graduation (#20)
- `GET /students/{member_id}/warning` (manage · advisor of the student) → `{"evaluated_at": iso|null,
  "term":{..}|null,"hits":[{"rule":{"id","key","kind","name_ar","name_en"},"priority","level",
  "explanation":{"ar","en"},"evidence":{..},"alert_id": int|null}],"graduation": Graduation|null,
  "recent":[alert items, ≤ 10],"restricted": int,"can":{"run": bool}}` — `hits` = rules matching NOW (also those
  held back by a cool-down); null `evaluated_at` = not evaluated yet.
- `Graduation` = `{"status":"on_track"|"at_risk"|"delayed"|"graduated"|"unknown","basis":"credits"|"levels"|null,
  "reason": null|"no_program"|"no_total"|"no_terms","earned","in_progress","total","terms_done","planned_terms",
  "projected_terms","delay_terms","needed_per_term","max_load","level","expected_level"}` (numbers null when unknown).
- `GET /graduation?status=delayed|at_risk|all&program_id=&level=&q=&page=&size=` (manage: org; advisor: own) →
  items `{"member_id","name","code","program": str|null,"level","primary":{"user_id","name"}|null,
  "graduation": Graduation}`, delay desc then name; facets `{"delayed","at_risk","on_track","unknown"}`.

### Settings (Phase 3 `GET/PUT /policy`, additive fields)
`AdvisingPolicy` gains `digest_hour` 7 (0–23), `digest_weekday` 6 (0 = Monday … 6 = Sunday), `nudge_after_days` 21
(1–120), `nudge_advisors` true, `nudge_students` true (per scope like every field; student nudges read the
student's scope, digests and advisor nudges the organization row). `digest` keeps its meaning (the default).

### Midterm marks (registrar, new files)
- Staff (`academic` view / update): `GET /api/v1/org/orgs/{org_id}/registrar/terms/{tid}/midterm/{cid}`,
  `PUT` same path. Instructor of the course: `GET|PUT /api/v1/org/public/{org_id}/registrar/teach/terms/{tid}/courses/{cid}/midterm`.
- GET → `{"term":{..},"course":{..},"items":[{"registration_id","student":{user brief},"student_code","status",
  "interim_percent": float|null,"interim_at": iso|null,"locked": bool}]}` (registered / completed rows; `locked` =
  final grade approved). PUT `{"items":[{"student_id","interim_percent": float 0–100|null}]}` → `{"saved": n,
  "errors":[{"student_id","code":"not_registered"|"grade_locked"|"bad_percent"}]}` (the registrar's codes; audited
  once per call `registrar.midterm`; self → 403 `self_action` like grades).

### Notices and pushes
Templates (Arabic + English, `adv_notice_log`): `warning_alert` (one alert; extra `member_id`, `alert_id`, `flag_id`,
`action: "propose_meeting"`), `warning_alerts` (several; `screen: "alerts"`, `since`), `warning_unassigned`
(directors; `screen: "alerts"`), `warning_digest` (`screen: "alerts"`, `since`, period daily | weekly),
`nudge_advisor_no_contact` (`screen: "workspace"`, `sort: "contact"`), `nudge_student_no_contact`
(`screen: "advisor"`); urgent reuses `flag_urgent`. Push data = `module: advising`, `template`, `org_id` + the extras.
Deep links (app): `member_id` → the 360 (existing); `screen: alerts` → `AdvAlertsPage(since)`; `workspace` → My
students sorted by contact; `advisor` → the student's advising card (Phase 5's hub once merged).
`propose_meeting` → the 360's booking sheet when Phase 5 is present, else the note composer with "log as contact".

## Migration `0055_advising_warning` (revision "0055", down_revision "0053"; the lead rechains at the merge)
New tables (models in NEW `data/advising_warning_models.py`, imported where advising models are registered):
`adv_risk_state` (org_id, member_id UNIQUE together, term_id, facts JSON, hits JSON, graduation JSON,
graduation_status String(10), evaluated_at; index (org_id, graduation_status)), `adv_warning_runs` (org_id, kind,
trigger, actor_id, status, counts JSON, error, started_at, finished_at; index (org_id, started_at)), `adv_alert_prefs`
(org_id, user_id UNIQUE together, digest null = inherit, last_digest_at, updated_at). Columns: `adv_risk_rules`
`name_ar`, `name_en`, `category_id` (FK categories, SET NULL), `scope` JSON; `adv_risk_events` `priority`,
`category_id`, `level`, `run_id` (FK runs, SET NULL), `delivery`; index (org_id, rule_id, member_id, fired_at) and
(org_id, fired_at). Data: `midterm_fail` on where never edited; organizations already enabled get the new seed rules
(`repeated_fail` count 2 high 60 days; `absence_count` count 6 normal 14 days). RLS `tenant_isolation` on the three
new tables. Help: `org.advising` gains sections `early_warning`, `alerts`, `nudges` (the 0053 pattern). Idempotent,
reversible.

## App (`wt-front-adv-p6`, `lib/features/org/advising/`; new files so Phase 5 / 7 edits don't collide)
- `adv_warning_models.dart` (pure, tolerant of missing keys: `AdvRule`, `AdvRuleKind`, `AdvRuleParam`, `AdvRun`,
  `AdvAlert`, `AdvWarning`, `AdvGraduation`, `AdvAlertPrefs`) · `adv_warning_api.dart` (`AdvWarningApi(orgId)`,
  through `orgCall`; `orgEndpointMissing` → "needs a server update").
- `adv_rules_page.dart` (manage; advisors read-only): rules grouped by kind with their summary, enabled `AppSwitch`,
  priority pill; the edit sheet is generated from `kinds` (number fields with unit, min / max, step), priority,
  cool-down, category (`AppDropdown`), optional scope (program / level / cohort), custom names; Preview ("N students
  match now · as of …" + sample with explanations); engine card: last run, counts, Run now (`appConfirm`, then
  `JobWatch` on `job_updated` kind `advising_warning`, slow poll `GET /warning/runs/{id}` as fallback), run history.
- `adv_alerts_page.dart`: alerts list (one filter control: priority, rule, since; tabs All · Graduation), alert card
  (student, rule name, explanation in the app language, time via `AppTime`, flag status pill, actions "Open student"
  and "Propose a meeting"); the Graduation tab lists `/graduation` with status facets. App-bar action "Alert
  delivery" → `AdvAlertPrefsSheet` (inherit / off / daily / weekly with the org default and the hour shown).
- `adv_warning_section.dart`: the 360's "Early warning" section/tab — current hits with explanations, the graduation
  card (earned / total bar, terms done → projected vs planned, status pill, "needs N credits a term"), recent alerts,
  "Evaluate now"; a rule flag's card links to its alerts (`GET /flags/{id}/alerts`).
- `adv_warning_parts.dart`: presentational widgets on plain values (`AdvRuleCard`, `AdvRuleEditorView`,
  `AdvAlertCard`, `AdvGraduationCard`, `AdvRunCard`, `AdvWarningView`) for the layout harness.
- Edits: `adv_student_page.dart` (section), `adv_setup_page.dart` (links Rules · Alerts for manage, Alerts for
  advisors), `adv_config_page.dart` (group "Alerts and nudges": digest default, hour, weekday, nudge after days,
  two switches), `adv_texts.dart` (every new code + explanation fallbacks), `adv_wiring.dart` + `app_navigator.dart`
  (the `screen` extras), `org_registrar_member.dart` `_GradesScreen` (Final · Midterm toggle on the same roster;
  midterm saves through the new routes; locked rows read-only).
- Tests: `test/org/adv_warning_models_test.dart` (parsing, older server, explanation fallback), `test/ui/
  adv_warning_layout_test.dart` (every presentational view, all states — empty, loading, error, offline, running —
  ar / en, 320 / 1400, textScaler 1.3), a11y entries if a view joins `a11y_guidelines_test`, and
  `test/visual/adv_warning_golden_test.dart` (390×844 and 1440×900, ar / en, light / dark, theme
  `displayTheme(theme.materialTheme(dark: …), const DisplayPrefs())` like `adv_case_golden_test.dart`) — look at the
  PNGs before reporting. Contract snapshots (`api_paths.json`, `feature_keys.json`) are regenerated by the lead.

## Backend files (`wt-back-adv-p6`)
New: `data/advising_warning_models.py`; `services/organization/advising/` `risk_rules.py` (pure catalog, params
validation, evaluation, levels, `should_fire`), `explain.py` (pure), `graduation.py` (pure), `warning_snapshot.py`
(bulk facts), `warning_engine.py`, `warning_rules.py` (CRUD + preview), `alerts.py` (alerts, 360 section, graduation
list, prefs), `digest.py` (digests + nudges), `warning_jobs.py` (tick); `services/organization/registrar/midterm.py`;
routers `routers/organization/org_advising_warning_router.py`, `routers/organization/org_registrar_midterm_router.py`;
`migrations/versions/0055_advising_warning.py`. Small append-only edits: `data/advising_models.py` (the new columns +
import of the new module), `main.py` (two routers), `services/scheduler_service.py` (the job),
`advising/policy.py` (five fields), `advising/seed.py` (rules list), `advising/text.py` and `advising/notices.py`
(codes, templates), `services/live_events.py` (catalog line), `services/feature_catalog.py`, `data/app_features_guide.json`,
`data/help_seed.json`, `FLUTTER_API_CHANGES.md` (top section).
Tests: `tests/org_v2/advising_risk_unit.py` (every kind at and around its threshold, levels, missing data, explanation
texts both languages, graduation projection credit / level / unknown, `should_fire`: first, cool-down, worsening,
dedupe key) and `tests/org_v2/e2e_advising_warning.py` (rules CRUD + validation + system delete 409 + limit; preview;
run idempotent — a second run adds no alert, no flag, no notice; events → one rule flag per category, priority
raised, Phase 4 escalation applies; urgent → advisors + directors once; digest advisor gets no single notice and one
digest at the hour, deduped; unassigned → directors; nudges once per week / per term; manual run 202 + `job_updated`
+ busy 409; stale running row closed; midterm entry (instructor, staff, locked, self) feeding `midterm_fail`;
graduation list and facets; kill switch `org.advising.warning`; cross-org attacks on every route (org B admin, an
advisor on a student they don't advise → 404); students 403 on every route; sensitive-category alerts hidden from a
co-advisor and audited for the primary). Rerun the existing advising suites, `spec_help`, `e2e_org_v2`,
`e2e_registrar`; migration round trip on SQLite and on `nb-pg` database `adv_mig_p6` (head → 0053 → head).
