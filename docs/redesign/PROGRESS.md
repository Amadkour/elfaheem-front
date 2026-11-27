# Redesign progress

Statuses: todo / doing / done / verified. On a resume, continue from the first line that is not done.

| # | Task | Status |
|---|---|---|
| 0.1 | PARITY_TABLE.md built from routes, features, features guide, kill switches and SCREENS.md | done |
| 0.2 | Design screens mapped to Flutter files and routes (SCREEN_MAP.md; groups and order in PHASE_PLAN.md) | done |
| 0.3 | BACKEND.md items checked against ../back (BACKEND_STATUS.md) | done |
| 0.4 | Sync decision: built in NextBrain, synced downstream, palette per product (D-1810 here, and in the downstream repository) | done |
| 0.6 | Phase 0 docs ported to NextBrain (brand-neutral), BRANDS.md (NextBrain palette from the logo) | done |
| 0.5 | Reference screenshots (D:/platform/redesign-ref/ref/, 1140 PNGs, 0 failures; rerun: tool/redesign/ref_shots.mjs) | done |
| 1a | Kit spec (KIT_SPEC.md, palette from the logo, contrast table) | done |
| 1b | Kit build (rd/kit + rd/kit-shell + rd/kit-back 0135: tokens, theme seed, motion M1-M16, components, shells, gallery, tests) | done (merged) |
| B1 | Backend WP5 international + WP7 child code (0130, 0131) | done (merged back feature/redesign) |
| B2 | Backend WP6 booking/groups + WP12 centres (0140) | done (merged) |
| B3 | Backend WP1-3 privacy (live room, payloads, course chat; D-1950) | done (merged) |
| B4 | Backend WP4 nicknames, WP10 notebook, WP11 meetings/bot (0150, 0151) | done (merged) |
| B5 | Backend WP8 payments per country + WP9 teacher demand (0160-0162) | done (merged; head 0162; 6 suites = 688 checks green) |
| B6 | Demand card subject keys + front contract snapshot refresh (rd/demand-key) | done |
| 2 | Student | doing: S-A, S-B, S-C, S-D merged. Owed: S-A bodies of categories/journey/recs/guest search/guest live/legal; back `price_label`/`outcomes` on /public/share; guide entry n_notebook (course.notebook) |
| 3 | Booking and subject flow | done (rd/bk merged). Owner Qs: a booking does not enrol in the course; bank transfer hidden in booking; no map picker; no OTP sign-in in 4ب |
| 4 | Parent (incl. child code login) | done (rd/pa merged). Owed: WP13 parent payments/invoices per child (backend), parent booking for a child (owner Q), calendar filter by child |
| 5 | Teacher | done (T1, T2, T2b merged). Owner Qs: QR scan by students; "أضف مواد للحصة" route; no assistant-add API |
| 6 | Admin and super admin | done (A1, A2 merged). Owner Qs: publish queue, audit log, roles editor (no backend) |
| 7 | Landing (persona pages; rd/landing merged) | done (visual verify in phase 9) |
| 8 | International pass | todo |
| 9 | Final check and REPORT.md | todo |
