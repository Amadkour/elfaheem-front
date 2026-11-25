# Feature parity: lose nothing, add what is new

The owner's rule: **no good feature of today's app may disappear because the design did not draw it.** Every feature the new design adds is built as well.

## Before writing any UI code (phase 0)

Build `docs/redesign/PARITY_TABLE.md`, one row per feature or screen, from these sources:
- every route in `lib/main.dart` `_router`, and every deep-link target in `AppNavigator`;
- every folder in `lib/features/` (role subfolders included) and every `DashboardItem` of every role's `AppShell`;
- `../back/data/app_features_guide.json`, the server's list of user-facing features;
- the kill-switch keys in `../back/services/feature_catalog.py`;
- the design screens in `SCREENS.md`.

Columns:

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|

Decisions:
- **restyle**: the design has it. Rebuild the UI from the design and keep the behaviour, the API calls and the kill switch.
- **keep + restyle**: the design does not draw it. Keep it, and give it the new tokens, motion and components so it looks like the rest. Place it where the design's navigation would put it, usually the role's "More" area.
- **new**: the design has it and the app does not. Build it, with the server part from BACKEND.md where needed, a kill switch, and an entry in the features guide.
- **replace**: the design changes how it works. Examples: the course group chat becomes a teacher announcements thread; the student no longer sees participants. Keep the old capability for the roles that still need it, such as the teacher.
- **owner**: only when a feature conflicts with RULES.md and cannot be kept. List these for the owner; do not delete them on your own.

## Things the design deliberately does not draw (keep them working, restyled)

- **Organizations** (`lib/features/org/`, the org dashboard, member dashboard, timetables, registrar, governance) were out of scope for the design. Keep all of them. Apply only the new tokens and colours where they come from the shared kit. Do not rebuild their layout.
- Downloads and offline videos, offline attendance relay, paper exams and OMR, the Export Studio, Data Lab, records, the help "i" pages, display and reading settings, keyboard support, the app assistant (RAG), the models hub, version checks, MFA and biometrics, and the course roadmap and recommendations.
- Every admin and super-admin tool that exists today, even when the design shows fewer pages.

## While building

- Each phase ends with its rows marked done in `PARITY_TABLE.md`.
- A pull request that removes a route, a `DashboardItem` or a kill-switch key without a parity row marked `owner` is not done.
