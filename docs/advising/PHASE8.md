# Phase 8 — Analytics, reports, outreach, outcomes, compliance, health check: brief and contract

Read `PLAN.md` §3.2 (`adv_outreach`, `adv_outreach_recipients`, `adv_student_stats`, `adv_term_stats`,
`adv_notice_log`), §3.8, §3.9, §4 row "8 Analytics", `PHASE2.md` (common rules unchanged: own worktree only,
`git commit --only`, never push or merge, `-j 2`, the Python venv, Arabic + English, no placeholders, lead-owned files,
report ≤ 15 lines), `PHASE3.md` "Shared rules" (roles, list envelope `{items,total,page,size,pages,facets}`, errors
`{code,message,message_en}`, audit + notices, every route: kill switch → eligibility → enabled, then the role),
`PHASE4.md` "Who sees what" (sensitive categories, `restricted`, public figures), and the Phase 5–7 entries of the
backend `FLUTTER_API_CHANGES.md`. Brief requirements covered: Director / Admin analytics (total students, students per
advisor and load distribution, unassigned, struggling by category and priority, risk trend, GPA distribution and
trend, meetings with completion and no-show rates, advisor response time, complaints and resolution time, request
pipeline and approval rate, advisor activity), every chart drilling down to a permission-scoped student list, PDF /
Excel exports and scheduled e-mailed reports through the EXISTING Export Studio; defaults #10 (student success
outcomes), #19 (group outreach with delivery and read tracking), #25 (compliance report per term), #26 (daily data
health check).

Worktrees: backend `wt-back-adv-p8`, app `wt-front-adv-p8`, branch `feature/academic-advising-p8` (backend holds
Phases 2–7, migrations up to 0056; the app branch holds Phase 4 code only — Phase 5–7 app code merges at the lead's
step, so every app change here is a NEW file or a small, append-only edit).

## Decisions (made here; state them in the report if you deviate)
- **Two analytics tiers.** `manage` (org admin / advising director, `access.roles(...).staff_view`): every figure,
  every drill-down, every dataset. `aggregate` (any live staff member holding the RBAC permission `advising` `view`
  ORG-WIDE through a custom role, e.g. a dean or a quality officer, who is not manage): aggregates only — no drill-down
  (403 `advising_forbidden`), no student names, sensitive categories folded into ONE row (`key: "sensitive"`), and
  **small-group suppression**: every student count of a breakdown cell (category, priority, risk band, GPA band,
  per-advisor student figures, outcome groups) between 1 and 4 is answered `null` (0 stays 0; totals stay). Averages
  and rates over fewer than 5 students are `null` for EVERY tier (meaningless, and identifying). Advisors (no RBAC
  view) and students: 403 `advising_forbidden` on every analytics route. Datasets: student-level ones manage only;
  `adv.advisors` / `adv.compliance` also for holders of `advising` `export` org-wide (aggregate rules applied).
- **Where the numbers come from (scale target 100 k students per organization).**
  State figures (students, load, unassigned, risk bands, open flags, GPA distribution) read `adv_student_stats` joined
  to the live student memberships — one grouped query per section. Flow figures (meetings, alerts, flags opened /
  resolved, replies, complaints, requests decided) are grouped SQL over the source tables in the date range, on new
  org_id-first time indexes (migration below). Response time is stamped ON THE REPLY (`adv_messages.response_minutes`,
  set when a staff message answers the student's earliest unanswered message; the migration backfills old threads), so
  averages are one indexed aggregate. History that cannot be recomputed later is captured by the daily job:
  `adv_daily_snapshots` (risk / assignment state per organization per local day) and `adv_student_terms` (one row per
  student per term: term GPA, change, contacts, support, retention), from which `adv_term_stats` keeps the per-term,
  per-advisor compliance figures (+ the organization row, `advisor_user_id` null). The dashboard body is cached 60 s
  per (organization, tier, filters) in the existing Redis cache (`services/jobs/cache.cached`, fail-open). Every filter
  is SQL; lists page with `page` / `size ≤ 100`.
- **Filters** (every analytics route and the student-level datasets): `from`, `to` (local dates `YYYY-MM-DD`,
  inclusive, org timezone), or `term_id` (= that term's dates); none → the current term (start → today), no current
  term → the last 90 days; > 400 days or `from > to` → 422 `advising_bad_range`. `program_id`, `level`, `cohort` (the
  student's), `advisor_user_id` (= the student's CURRENT primary advisor; on term rows = the primary advisor during that
  term). A student filter turns off what cannot honour it: the snapshot series (`state_series: false`) and satisfaction
  (`null`). Series bucket by local day (range ≤ 31 days), ISO week starting Monday (≤ 210 days) or month, using the
  zone's offset at the range end (an event within an hour of a DST change may land in the neighbouring bucket).
  `previous` figures = the same-length range right before `from`.
- **Bands** (constants in pure `analytics_rules.py`): risk `high` ≥ 60 · `medium` 30–59 · `low` 1–29 · `none` 0 (the
  Phase 4 score; manage reads the full score, the aggregate tier the same full score — it never sees a student);
  "at risk" = high + medium. GPA bands from the organization's grade scale maximum M (registrar rules,
  `max(points)`): `b0` [0, .25M) · `b1` [.25M, .5M) · `b2` [.5M, .625M) · `b3` [.625M, .75M) · `b4` [.75M, .875M) ·
  `b5` [.875M, M] · `none` (no CGPA) — on a 4.0 scale 0 · 1 · 2 · 2.5 · 3 · 3.5 · 4; the probation line
  (`standing.probation_below`) is sent for the chart.
- **Definitions.** Contact = a completed appointment, or a note logging a contact without an appointment (a meeting
  note never counts twice). Active advisor = at least one completed meeting, reply, note or resolved alert in the last
  `activity_days` (policy, default 14). Completion rate = completed / (completed + no-show); no-show rate = the
  complement; cancellations are reported apart. Response = minutes from the student's earliest unanswered message to
  the next staff message in that thread; `sla_met` = that reply came before the thread's `sla_due_at`. Complaint
  resolution = `closed_at − created_at` of complaint threads. Approval rate = approved / (approved + rejected) of
  support requests decided in the range; referrals reported apart (handled / declined).
- **Outcomes (#10)** per term from `adv_student_terms`: `enrolled` = live membership at the term's start;
  `supported` = at least one contact, a resolved alert or an active / completed support plan inside the term;
  `at_risk` = an early-warning alert, or a high / urgent alert opened, inside the term; `term_gpa` through the
  registrar's helpers (`P.term_gpa`, no second formula), `gpa_change` = term GPA − the previous graded term's;
  `retained` = graduated, or the membership was live at the start of the next regular term (today when it has not
  started). Groups: supported / not supported × at risk / all; each average or rate needs n ≥ 5. Default term = the
  latest term that ended with term GPAs present, else the current one.
- **Compliance (#25)** per term and advisor (rows of `adv_term_stats`): advisees (students whose primary advisor
  during the term was this advisor), contacted, coverage %, contacts, contacts per student, completed meetings,
  no-shows, alerts, alerts resolved, average resolution days, average days from term start to the first contact,
  replies, average response hours, at-risk students and how many were contacted, supported GPA change, retention %,
  `meets_target` = coverage ≥ `compliance_target_pct` (80) AND contacts per student ≥ `compliance_min_contacts` (1).
  Exported as PDF and Excel through the Export Studio dataset `adv.compliance` (no new renderer).
- **Exports and scheduled reports**: only Export Studio datasets (`services/export_datasets.register(Dataset…)`):
  runs (`POST /api/v1/exports/runs`), schedules with e-mail (`/api/v1/exports/schedules`: its recipient rule — the
  recipient must pass the dataset's check with the same parameters and see every column), share links, layout v3. The
  renderer's existing formula-injection guard (`helpers/xlsx_safe`) covers every text cell; the e2e test proves a
  student named `=HYPERLINK(...)` exports as text. No CSV is produced.
- **Outreach (#19)**: manage → any audience of the organization; an advisor → only students they actively advise
  (`access.student_scope`), with the public figures for risk / priority and the visibility-aware category filter. The
  audience grammar IS the drill-down grammar (metric + key + filters) or an explicit `member_ids` list (≤ 5 000,
  out-of-scope ids dropped and counted). Preview → `audience_hash` (SHA-256 of the sorted final member ids, 16 hex);
  send recomputes it (changed → 409 `advising_audience_changed`). Caps: ≤ 5 000 recipients (422
  `advising_audience_too_large`), a student gets at most `outreach_weekly_cap` (policy, default 3) outreach messages
  per 7 days (the rest counted `capped`, never sent), 5 sends per hour per sender (throttle scope `adv_outreach`, 429
  `advising_rate_limited`). Idempotent `client_id` (unique per organization and sender). Placeholders
  `{student_name}` `{advisor_name}` `{org_name}` are replaced per recipient by plain string replacement (no format
  evaluation, nothing else is expanded); the stored body keeps the tokens. Plain text, subject ≤ 200, body ≤ 5 000.
  Delivery runs after the commit (BackgroundTasks, own session) in chunks of 100 through `notification_service
  .notify_user` per student (in-app row + push, the platform's e-mail fallback when no device was reached) and, with
  `email: true`, the organization's e-mail channel (`governance.notify.maybe_email`). Each recipient row records
  `status` queued · delivered (in-app row written) · failed, `pushed` (push or e-mail fallback reached them),
  `delivered_at`; `read_at` is set when the student opens the message (member route below). A send left `sending`
  for 10 minutes is resumed by the analytics tick; recipients already delivered are never sent twice. Audit
  `advising.outreach_send` (`meta`: outreach id, recipients, capped, out_of_scope, the audience filter — never the
  body). Lock screens show the subject only.
- **Health check (#26)** — daily by the job and on demand; one `adv_health_checks` row per check (kept 60 per
  organization). Items (`key` · severity rule):
  `unassigned_students` (live students without an active primary; critical when > 5 % of students, else warning) ·
  `advisor_away_students` (primary advisor away; warning) · `advisors_over_capacity` (load > max; warning) ·
  `orphaned_flags` (open alerts whose membership is no longer a live student; warning) · `unowned_flags` (open alerts
  of live students with no owner or an owner who no longer advises the student and is not manage; warning) ·
  `stuck_requests` (submitted requests without an outcome whose current step went overdue more than 7 days ago, or
  waiting for information more than 14 days; critical) · `stale_stats` (live students without a stats row or with one
  older than 24 h; warning when > 1 %, else info) · `overdue_threads` (open threads 48 h past `sla_due_at`; warning) ·
  `pending_handovers` (unacknowledged for 7 days; info) · `advisors_without_hours` (advisors with advisees but no
  availability rule; info) · `students_without_program` (info). Zero → `ok`. The directors get ONE `health_report`
  notice per local day, at the first tick after `digest_hour`, only when an item is critical or the issue count rose
  since the previous check (no student data in the text).
- **Jobs**: one new APScheduler job `org_advising_analytics_tick`, every 15 minutes. Per organization with advising
  on and `org.advising.analytics` on: the daily run (claim `adv_an_daily:{org}:{local date}`, 3 h, once the local hour
  is ≥ 2) = snapshot of today → `adv_student_terms` for the current term and terms that ended in the last 120 days (all
  terms of the last 4 years on the organization's first run) in chunks of 500 students (one query per source per
  chunk, commit per chunk, upsert: idempotent) → `adv_term_stats` for those terms → health check; the health notice
  (claim `adv_health_notice:{org}:{local date}`); outreach sends left `sending` (claim per outreach). Every run is a
  row of `adv_analytics_runs` (kind `daily` · `health`, trigger `tick` · `manual`, counts, duration, error); a
  `running` row older than 3 h is closed `failed` (`stale`). A manual refresh sends `job_updated`
  `{kind: "advising_analytics", id, status, org_id}` to the person who pressed it; an outreach send sends
  `{kind: "advising_outreach", id, status, org_id}` to its sender when it ends.
- **Kill switches** (not org-manageable): `org.advising.analytics` (every `/analytics/*`, `/health-check*` route and
  the `adv.*` datasets except `adv.outreach`) and `org.advising.outreach` (staff outreach routes and `adv.outreach`;
  students keep reading messages already received). Off → 403 `feature_disabled` (+ `feature`), jobs skip that part.
- **Policy keys (additive, Phase 3 `GET|PUT /policy`)**: `activity_days` 14 (1–90), `compliance_target_pct` 80
  (1–100), `compliance_min_contacts` 1 (1–10), `outreach_weekly_cap` 3 (1–20). Organization row only matters for
  the last three (per-student scopes are not consulted for them).

## API (base `/api/v1/org/orgs/{org_id}/advising`; manage = org admin / advising director; aggregate = RBAC
`advising` view org-wide; every route: `org.advising` → eligibility → `advising_disabled` → the phase's kill switch →
the role)

Shared objects: `Term = {"id","label","kind","start","end"}` (label = `year_label`, kind term1 | term2 | summer, dates
`YYYY-MM-DD`); `Range = {"from","to","days","term": Term|null,"interval":"day"|"week"|"month"}`;
`Filters` echo = `{"program_id","level","cohort","advisor_user_id"}`; `Rate = number 0–100 | null` (one decimal);
`Count = int | null` (null = suppressed, aggregate tier, 1–4).

### Options
- `GET /analytics/options` (manage · aggregate) → `{"terms":[Term + "current": bool] (≤ 12 newest),
  "programs":[{"id","name","name_en"}],"levels":[str],"cohorts":[str],"advisors":[{"user_id","name"}] (manage only,
  else []),"categories":[{"id","key","name_ar","name_en","sensitive"}] (aggregate: sensitive ones folded into
  `{"id": null,"key":"sensitive",…}`),"risk_bands":[{"key","min","max"}],"gpa_bands":[{"key","from","to"}],
  "probation_below": float|null,"scale_max": float,"metrics":[{"key","label_ar","label_en","needs_key": bool,
  "needs_term": bool}],"tier":"manage"|"aggregate"}`.

### Dashboard
- `GET /analytics/overview?from&to&term_id&program_id&level&cohort&advisor_user_id` (manage · aggregate) →
  `{"generated_at", "range": Range, "filters": Filters, "viewer": {"tier","drill": bool,"min_group": 5},
    "state_series": bool,
    "kpis": {"students","unassigned","at_risk","meetings_completed","no_show_rate","avg_response_hours",
             "alerts","complaints_open"}  — each {"value": number|null,"previous": number|null},
    "students": {"total","assigned","unassigned","advisor_away","no_contact_term","graduated"},
    "load": {"advisors","active_advisors","avg","max","over","warn","capacity_left",
             "distribution":[{"key":"empty"|"under_50"|"50_79"|"80_99"|"full"|"over","advisors"}],
             "top":[{"user_id","name","load","max_load","load_pct","warn","over"}] (≤ 10, most loaded first)},
    "struggling": {"risk_bands":{"high","medium","low","none"} (Count),
                   "by_priority":{"low","normal","high","urgent"} (students by their highest open alert, Count),
                   "by_category":[{"category":{"id","key","name_ar","name_en","sensitive"},"students": Count,
                                   "flags": Count,"by_priority":{"low","normal","high","urgent"}}] (open alerts)},
    "risk_trend": {"points":[{"date","at_risk": int|null,"high": int|null,"avg_score": float|null,"alerts","opened",
                              "resolved"}]}  (at_risk / high / avg_score from snapshots: null without one or when
                              `state_series` is false),
    "gpa": {"scale_max","probation_below","avg_cgpa","no_gpa","distribution":[{"key","from","to","students": Count}],
            "trend":[{"term": Term,"students","avg_term_gpa": float|null,"below_line": Count}] (≤ 8 terms, oldest
            first)},
    "meetings": {"booked","completed","no_show","cancelled","late_cancelled","upcoming","students_met",
                 "completion_rate": Rate,"no_show_rate": Rate,"by_mode":{"in_person","video","phone","chat"},
                 "points":[{"date","completed","no_show","cancelled"}]},
    "response": {"replies","avg_hours": float|null,"sla_met_pct": Rate,"awaiting_reply",
                 "buckets":{"lt_1h","h1_4","h4_24","d1_3","gt_3d"},"points":[{"date","replies","avg_hours"}]},
    "complaints": {"opened","closed","open_now","escalated","about_advisor","avg_resolution_hours": float|null,
                   "points":[{"date","opened","closed"}]},
    "requests": {"open":{"submitted","needs_info","in_review","at_department_council","at_faculty_council"},
                 "referrals_open","overdue","decided":{"approved","rejected","withdrawn","closed"},
                 "referrals_decided":{"handled","declined","withdrawn","closed"},"approval_rate": Rate,
                 "avg_decision_days": float|null,"by_type":[{"support_type","label_ar","label_en","count"}]},
    "activity": {"window_days","advisors","active","inactive",
                 "actions":{"meetings","replies","notes","alerts_resolved"}},
    "outcomes": Outcomes,
    "satisfaction": {"count","average": float|null,"hidden": bool}|null,
    "health": {"checked_at","issues","critical"}|null (manage only)}`
  `Outcomes = {"term": Term|null,"as_of": iso|null,"enrolled","supported","at_risk","at_risk_supported",
  "meetings_held","alerts_resolved","plans_completed","plans_met",
  "gpa_change":{"supported","not_supported","at_risk_supported","at_risk_not_supported"} each {"n","avg": float|null},
  "retention":{"all","supported","at_risk_supported","at_risk_not_supported"} each {"n","retained": Count,
  "rate": Rate}}` (`as_of` = when `adv_student_terms` was computed; null + zeros before the first daily run).
- `GET /analytics/advisors?<filters>&q&sort=load|name|risk|no_contact|meetings|response|activity&page&size`
  (manage · aggregate) → envelope; items `{"user_id","name","status","away","load","max_load","load_pct","warn","over",
  "students":{"at_risk": Count,"high_risk": Count,"no_contact_term": Count},
  "meetings":{"completed","no_show","cancelled","no_show_rate": Rate},"replies","avg_response_hours": float|null,
  "sla_met_pct": Rate,"notes","alerts_resolved","last_active_at": iso|null,"active": bool,
  "satisfaction":{"count","average": float|null,"hidden": bool}}`; facets `{"active","inactive","over","warn"}`.
  Range figures are the advisor's own actions in the range; student figures are their current primary advisees.
- `GET /analytics/students?metric&key&state&<filters>&q&sort=risk|name|cgpa|contact&page&size` (manage) → the
  Phase 4 workspace envelope and items unchanged (`GET /workspace` shape, facets included) + `"metric":{"key","value",
  "label_ar","label_en"}`. Metrics (`key` = the value the metric needs): `all` · `unassigned` · `advisor_away` ·
  `advisor` (user id: primary advisees) · `risk_band` (high | medium | low | none) · `priority` (highest open alert
  priority) · `category` (category id; optional `priority`) · `gpa_band` (b0–b5 | none) · `no_contact` (no contact
  since the current term began; no term: 30 days) · `met` (completed meeting in range) · `no_show` (in range) ·
  `booked` (an upcoming booked appointment) · `alerted` (an alert fired in range) · `complaint` (a complaint opened in
  range) · `awaiting_reply` (an open thread whose student message is unanswered) · `request_stage` (stage key: an open
  request there) · `graduation` (delayed | at_risk, Phase 6 state) · `supported` · `not_supported` ·
  `at_risk_supported` · `at_risk_not_supported` · `not_retained` (term outcome groups; `term_id` or the outcomes'
  default term) · `unowned_flag` · `stuck_request` · `stale_stats` · `missing_program` (health items) · `outreach`
  (outreach id; `state` = all | unread | read | failed). Unknown metric / missing or bad key → 422
  `advising_bad_metric` (+ `metric`).
- `GET /analytics/compliance?term_id` (manage · aggregate) → `{"term": Term|null,"as_of": iso|null,"pending": bool,
  "targets":{"coverage_pct","min_contacts"},"total": ComplianceRow,"advisors":[ComplianceRow]}`;
  `ComplianceRow = {"user_id": int|null,"name","advisees","contacted","coverage_pct": Rate,"contacts",
  "contacts_per_student": float|null,"meetings_completed","no_shows","no_show_rate": Rate,"alerts","alerts_resolved",
  "avg_resolution_days": float|null,"avg_first_contact_days": float|null,"replies","avg_response_hours": float|null,
  "at_risk","at_risk_contacted","supported_gpa_change": float|null,"retained_pct": Rate,"meets_target": bool|null}`
  (`pending` = no daily run has covered the term yet; aggregate tier: student counts of an advisor row 1–4 → null).
- `POST /analytics/refresh` (manage) → 202 `{"run": AnalyticsRun}` (the daily run now, BackgroundTasks, own session);
  409 `advising_run_busy` (+ `run_id`) while one runs; budget `adv_analytics` (6 / hour per user, shared with the
  health run) → 429 `advising_rate_limited` (+ `retry_after_minutes`). Audit `advising.analytics_refresh`.
- `GET /analytics/runs?kind=daily|health&page&size` (manage) → envelope of `AnalyticsRun = {"id","kind","trigger",
  "status":"running"|"done"|"failed","actor":{"user_id","name"}|null,"counts":{"students","terms","term_rows",
  "advisor_rows","snapshots","health_issues"},"error","started_at","finished_at","duration_ms"}`.

### Health check (#26)
- `GET /health-check` (manage) → `{"checked_at": iso|null,"trigger":"tick"|"manual"|null,"issues","critical",
  "items":[{"key","severity":"ok"|"info"|"warning"|"critical","count","label_ar","label_en","hint_ar","hint_en",
  "drill":{"metric","key"}|null,"action":"distribute"|"rebalance"|"reassign"|"open_alerts"|"open_requests"|
  "open_threads"|"open_handovers"|"open_advisors"|null,"sample":[{"user_id","name","value"}] (≤ 5; advisors only —
  over capacity: load, without hours: advisees)}],"previous":{"checked_at","issues","critical"}|null}`.
- `POST /health-check/run` (manage) → the GET body after checking now (synchronous; budget `adv_analytics`).

### Outreach (#19)
`Audience = {"metric","key","state","program_id","level","cohort","advisor_user_id","category_id","priority",
"from","to","term_id","q","member_ids":[int] ≤ 5000 | null}` (advisors: metrics `all` · `risk_band` · `priority` ·
`category` · `gpa_band` · `no_contact` · `met` · `no_show` · `booked` · `outreach` (their own) — others 403
`advising_forbidden`).
- `POST /outreach/preview` (manage · advisor) `{"audience": Audience}` → `{"count","audience_hash",
  "excluded":{"out_of_scope","capped"},"sample":[{"member_id","name","code"}] (≤ 10),"label":{"ar","en"}}`;
  0 recipients → `count: 0` (no error here).
- `POST /outreach` (manage · advisor) `{"audience","audience_hash","subject","body","template_id": int|null,
  "email": bool,"client_id": str|null}` → 202 `Outreach`; repeated `client_id` → 200 the stored one. Errors: 422
  `advising_audience_empty`, `advising_audience_too_large` (+ `max`), `advising_bad_template` (not an active `outreach`
  template of the organization); 409 `advising_audience_changed` (+ `count`, `audience_hash`); 429
  `advising_rate_limited`.
- `GET /outreach?mine=1&page&size` (manage: all, `mine` optional; advisor: own) → envelope of `Outreach =
  {"id","subject","sender":{"user_id","name"},"label":{"ar","en"},"status":"queued"|"sending"|"sent"|"failed",
  "email","created_at","finished_at","counts":{"recipients","delivered","pushed","read","failed","capped",
  "out_of_scope"},"read_rate": Rate}`.
- `GET /outreach/{id}` (manage · its sender) → `Outreach` + `"body"`, `"audience"` (the stored filter), `"template_id"`.
- `GET /outreach/{id}/recipients?state=all|unread|read|failed&q&page&size` (manage · its sender) → envelope of
  `{"member_id","name","code","status","pushed","delivered_at","read_at"}`; facets `{"unread","read","failed"}`.
  Another organization's / another sender's outreach → 404 `advising_not_found`.
- Templates: Phase 5 `GET /templates?kind=outreach` (unchanged).

### Member routes (base `/api/v1/org/public/{org_id}/advising`, the student, own membership only)
- `GET /outreach?page&size` → envelope of `{"id","subject","body" (placeholders filled),"sender_name","sent_at",
  "read_at"}` newest first (`unread` in the envelope).
- `POST /outreach/{id}/read` → `{"id","read_at"}` (idempotent; not a recipient → 404 `advising_not_found`).
- Hub `GET /me` gains `"outreach":{"unread","latest":[≤ 3 items as above, without body]}`; member `GET /status`
  `me` gains `outreach_unread`.

### Status (Phase 2 staff `GET /status`, additive)
`me` gains `"analytics": "manage"|"aggregate"|null`, `"outreach": bool` (may send), `"health_issues": int` (manage:
latest check, else 0).

### Datasets (Export Studio, `services/organization/advising/export_data.py`, registered on import)
All take `org_id` (+ `lang`); `check` = kill switches → enabled → tier (re-run at every scheduled run); `org_of` =
`org_id`; rows paged by key (500), never one list.
| key | params | who | columns |
|---|---|---|---|
| `adv.students` | metric, key, state, the filters, q | manage | name, code, program, level, cohort, primary advisor, cgpa, last term GPA, absence max %, failed courses, open alerts, highest priority, risk score, risk reasons (text), last contact, meetings this term, graduation |
| `adv.advisors` | the filters | manage · `advising` export | name, status, load, max load, load %, at risk, no contact this term, meetings completed, no-shows, no-show rate, replies, avg response h, SLA met %, notes, alerts resolved, last active, active |
| `adv.flags` | status (open · closed · all), category_id, priority, the filters | manage | student, code, program, category, sensitive, priority, status, source, owner, opened, resolved, resolution h, escalated, overdue — never note texts; sensitive rows → one `advising.sensitive_read` audit row per run (`meta`: dataset, count) |
| `adv.appointments` | status, the filters | manage | student, code, advisor, starts, mode, status, booked by, late cancel, cancelled by, booked at — never reasons |
| `adv.compliance` | term_id | manage · `advising` export | the `ComplianceRow` columns + the total row first |
| `adv.outreach` | outreach_id, state | manage · its sender | student, code, status, pushed, delivered at, read at |
Titles ar + en; column types for the renderer (`int`, `percent`, `datetime`, `bool`, …). Scheduled e-mailed reports
are Export Studio schedules of these datasets (daily · weekly · monthly, recipients checked by the Export Studio).

### Notices, push data, deep links
Templates (ar + en, `notices.TEMPLATES` registered from the new modules): `outreach_message` (the student: title
"رسالة من الإرشاد الأكاديمي" / "Message from academic advising", body = the subject; push data `kind:
org_adv_outreach`, `outreach_id`, `audience: student`; delivery logged in `adv_outreach_recipients`, not
`adv_notice_log`) and `health_report` (directors: "Advising data check: N issues need attention"; `screen: health`,
dedupe `adv_health:{org}:{local date}`). Live events (`services/live_events.py` catalog): `job_updated` kinds
`advising_analytics`, `advising_outreach`. App deep links: `org_adv_outreach` (student → the message sheet; staff →
the tracking page), `screen: health` → the director page's health card.

### New codes (ar + en in `text.py`)
422 `advising_bad_metric`, `advising_audience_empty`, `advising_audience_too_large`; 409 `advising_audience_changed`;
reused: `advising_bad_range`, `advising_run_busy`, `advising_bad_template`, `advising_rate_limited`,
`advising_forbidden`, `advising_not_found`, `feature_disabled`.

## Migration `0057_advising_analytics` (revision "0057", down_revision "0056")
New tables (models in NEW `data/advising_analytics_models.py`, imported next to the other advising model modules;
RLS `tenant_isolation` on each, like 0050; org_id-first indexes):
- `adv_daily_snapshots`: org_id, day Date, data JSON (`students, assigned, unassigned, advisor_away, at_risk, high,
  medium, low, avg_score, open_alerts{low,normal,high,urgent}, no_contact_term`), created_at; unique (org_id, day).
- `adv_student_terms`: org_id, member_id, term_id (FK org_terms CASCADE), primary_advisor_id, term_gpa, prev_term_gpa,
  gpa_change, credits, contacts, first_contact_at, meetings, no_shows, alerts, alerts_resolved, plans_completed,
  plans_met, supported, at_risk, enrolled, retained (nullable), graduated, updated_at; unique (org_id, term_id,
  member_id); index (org_id, term_id, primary_advisor_id).
- `adv_health_checks`: org_id, checked_at, trigger, issues, critical, data JSON; index (org_id, checked_at).
- `adv_analytics_runs`: org_id, kind, trigger, actor_id, status, counts JSON, error, started_at, finished_at; index
  (org_id, started_at).
Columns: `adv_messages` `response_minutes` Integer, `reply_to_at` DateTime, `sla_met` Boolean (backfilled for staff
replies of existing threads: `response_minutes` / `reply_to_at`; `sla_met` stays null for history);
`adv_outreach` `status` String(8) (existing rows `sent`), `template_id` (FK templates SET NULL), `email` Boolean,
`client_id` String(40) + unique (org_id, sender_id, client_id), `audience_hash` String(16), `capped`, `out_of_scope`
Integer, `sending_at`, `finished_at` DateTime; `adv_outreach_recipients` `user_id`, `status` String(8), `pushed`
Boolean, index (outreach_id, status), index (org_id, member_id, outreach_id). Indexes: `adv_messages` (org_id,
created_at); `adv_threads` (org_id, kind, created_at); `adv_flags` (org_id, created_at) and (org_id, resolved_at);
`adv_notes` (org_id, contact_at); `adv_requests` (org_id, outcome_at); `adv_term_stats` partial unique (org_id,
term_id) WHERE advisor_user_id IS NULL. Help: `org.advising` gains sections `analytics`, `outreach`, `reports`,
`health_check` (the 0056 pattern). Idempotent (`migrations/helpers.py`), reversible.

## Backend files (`wt-back-adv-p8`)
New: `data/advising_analytics_models.py`; `services/organization/advising/` `analytics_rules.py` (pure: bands,
ranges, buckets, suppression, rates, outcome / compliance maths, health severity, audience hash, placeholder fill),
`analytics_access.py` (tiers), `analytics_filters.py` (filters + drill metrics → SQL conditions, shared by the drill
list, datasets and outreach), `analytics.py` (overview sections, advisors table, options), `outcomes.py`
(`adv_student_terms` builder), `compliance.py` (`adv_term_stats` rows + read), `snapshots.py`, `health_check.py`,
`analytics_jobs.py` (tick, daily run, stale runs), `outreach.py` (preview, send, delivery, tracking, member list),
`analytics_texts.py` (codes + notice templates registered into `text.MSG` / `notices.TEMPLATES`), `export_data.py`
(the six datasets); router `routers/organization/org_advising_analytics_router.py` (staff + member). Small
append-only edits: `main.py` (two routers), `services/scheduler_service.py` (the job), `services/export_datasets.py`
(one import line at the end so the registry sees the advising datasets), `services/organization/throttle.py`
(`adv_outreach` 5 / hour, `adv_analytics` 6 / hour), `advising/policy.py` (four keys), `advising/threads.py` (one call
stamping the reply in `post`), `advising/workspace.py` (`listing(..., extra=())` conditions), `advising/setup.py`
(status `me` keys), `advising/hub.py` (`outreach` block), `services/live_events.py`, `services/feature_catalog.py`,
`data/app_features_guide.json` (`org_advising_analytics`, `org_advising_outreach`), `data/help_seed.json`,
`FLUTTER_API_CHANGES.md` (top section).
Tests: `tests/org_v2/advising_analytics_unit.py` (every pure function: band edges, GPA bands on 4.0 and 5.0 scales,
range defaults / limits / intervals and DST-day buckets, suppression 0 · 1–4 · 5, rates with zero denominators,
outcome groups and n ≥ 5, compliance row and `meets_target`, health severities, audience hash stability, placeholder
fill never evaluating `{x.__class__}`) and `tests/org_v2/e2e_advising_analytics.py` (seeded organization: every
overview section against hand-counted values, each filter, previous-range KPIs; every drill metric returns exactly the
expected members; aggregate tier: suppressed cells, folded sensitive categories, drill 403; advisors / students 403;
cache hit inside 60 s; datasets: catalog, columns per tier, runs in xlsx + pdf, `adv.compliance` both formats, a
formula-like name exported as text, a schedule with an allowed and a refused recipient, sensitive-read audit row;
response stamping on new replies and the migration backfill; outreach preview → send → idempotent replay → audience
changed 409 → caps (size, weekly cap, rate) → delivery statuses → student list + read → tracking counts and recipients
facets → advisor limited to own advisees → another student's message 404; health check items on planted problems,
the daily notice once and only when worse; refresh 202 + `job_updated` + busy 409 + stale run closed; the daily tick
idempotent (second run changes nothing); kill switches `org.advising.analytics` / `org.advising.outreach`; cross-org
attacks on every route). PG: `tests/org_v2/pg_advising_analytics_perf.py` seeds 100 k students on `nb-pg` database
`adv_mig_p8` and reports p95 of overview (uncached), advisors table, drill pages, compliance, preview. Rerun
`advising_*_unit`, `e2e_advising_*`, `spec_help`, `e2e_org_v2`, `e2e_feature_guide`; migration round trip on SQLite
and on `nb-pg` `adv_mig_p8` (head → 0056 → head).

## App (`wt-front-adv-p8`, `lib/features/org/advising/`; new files)
- `adv_analytics_models.dart` (pure, tolerant of missing keys / older server; `null` counts = "fewer than 5"):
  `AdvAnalyticsOptions`, `AdvOverview` (+ one class per section), `AdvAdvisorStat`, `AdvCompliance` /
  `AdvComplianceRow`, `AdvHealth` / `AdvHealthItem`, `AdvAnalyticsRun`, `AdvOutreach`, `AdvOutreachPreview`,
  `AdvOutreachRecipient`, `AdvStudentMessage`, `AdvAnalyticsFilter` (query map), `AdvAudience`.
- `adv_analytics_api.dart`: `AdvAnalyticsApi(orgId)` (staff routes, through `orgCall`; `orgEndpointMissing` → "needs a
  server update"), static `memberOutreach`, `markOutreachRead`; reports go through `ExportStudioApi.instance`
  (`createRun`, `run`, `downloadRun`, `schedules`, `createSchedule`) — no export code of its own.
- `adv_director_page.dart` (manage · aggregate): ONE filter bar (range / term, program, level, cohort, advisor —
  one sheet), then KPI row (`AppTrendTile` with previous-range deltas, `upIsGood` per metric), Load (`AppBarChart` of
  the distribution + top-loaded list), Struggling (`AppBarChart` by category, `AppDonut` by priority, risk bands),
  Risk trend (`AppBarChart` alerts / opened / resolved + `AppSparkline` of at-risk), GPA (`AppBarChart` bands with the
  probation line named in the caption + term trend `AppSparkline`), Meetings (`AppDonut` statuses + rates), Response
  and complaints, Requests pipeline (`AppBarChart` by stage + approval rate), Activity (`AppDonut` active / inactive →
  the advisors table page), Outcomes (supported vs not supported tiles, n shown, "fewer than 5" text for nulls),
  Satisfaction, Health card, Reports, Outreach entry. Every chart has a tappable breakdown list under it (rows: label,
  count, chevron) that opens `AdvDrillPage(metric, key, filters)` (manage only; hidden for aggregate). Phone: one
  column; desktop: two-column grid; skeletons, empty, error, offline, "Updated …" via `OrgPageRefresh`. Colours from
  `appChartPalette`, status colours only for status.
- `adv_analytics_parts.dart`: presentational widgets on plain values for the layout harness (`AdvKpiRow`,
  `AdvLoadCard`, `AdvStrugglingCard`, `AdvRiskTrendCard`, `AdvGpaCard`, `AdvMeetingsCard`, `AdvResponseCard`,
  `AdvRequestsCard`, `AdvActivityCard`, `AdvOutcomesCard`, `AdvHealthCard`, `AdvComplianceTable`,
  `AdvAdvisorStatRow`, `AdvOutreachCard`, `AdvBreakdownList`).
- `adv_drill_page.dart`: the workspace card list for a metric (reuses the Phase 4 card), sort, search, paging, export
  (`adv.students` through the export sheet: `showAppExportSheet` with `serverDataset: 'adv.students'` and the same
  params), "Message these students" → outreach composer with the same audience.
- `adv_advisors_stats_page.dart`: the advisors table (cards on phones, `AppHScroll` table on desktop), sort, facets.
- `adv_outreach.dart`: composer sheet (audience summary from preview with count / capped / sample, template picker
  from `GET /templates?kind=outreach` with placeholder chips, subject, body, e-mail switch `AppSwitch`, `appConfirm`
  "Send to N students", `client_id` per draft, `advising_audience_changed` → re-preview), outreach list page, tracking
  page (counts, read-rate bar, recipients with state filter, "Message unread" → composer with metric `outreach` +
  `state: unread`), student message sheet + `AdvHubOutreachSection` (standalone; the lead places it in the Phase 5
  hub). Workspace (Phase 4 page): multi-select → "Message selected" (small edit).
- `adv_reports.dart`: compliance card (term picker, `AdvComplianceTable` preview from `GET /analytics/compliance`,
  PDF / Excel buttons → Export Studio run of `adv.compliance` → wait on `job_updated` kind `export` with `JobWatch` →
  save), "Schedule by e-mail" (Export Studio schedule sheet: cadence, hour, recipients), the organization's advising
  schedules (`dataset` starting `adv.` and `params.org_id` = this org) with pause / resume / delete, and quick
  exports of `adv.advisors`, `adv.flags`, `adv.appointments`.
- Edits: `adv_setup_page.dart` (links Analytics — manage · aggregate —, Outreach — manage · advisor —, health badge
  `health_issues`), `adv_wiring.dart` + `app_navigator.dart` (`org_adv_outreach`, `screen: health`), `adv_texts.dart`
  (every new code ar + en; or a new `adv_analytics_texts.dart` merged where `advCodeTexts()` is), `adv_config_page.dart`
  (group "Reports and outreach": activity days, compliance target %, minimum contacts, weekly outreach cap).
- Tests: `test/org/adv_analytics_models_test.dart` (parsing, older server, suppressed nulls, filter query maps),
  `test/ui/adv_analytics_layout_test.dart` (every presentational view, all states — loading, empty, error, offline,
  suppressed, pending compliance —, ar / en, 320 / 1400, textScaler 1.3), a11y entries if a view joins
  `a11y_guidelines_test`, `test/visual/adv_analytics_golden_test.dart` (390×844 and 1440×900, ar / en, light / dark,
  theme `displayTheme(theme.materialTheme(dark: …), const DisplayPrefs())` like `adv_case_golden_test.dart`; scenes:
  director page manage, director page aggregate, drill list, advisors table, outreach composer, tracking page, student
  message, compliance card, health card) — look at the PNGs before reporting. Contract snapshots (`api_paths.json`,
  `feature_keys.json`, payload fixtures) are regenerated by the lead.
