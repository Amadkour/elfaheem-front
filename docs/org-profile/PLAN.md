# Simplify the Organization Profile (org admin) — audit and plan

Branch `feature/org-profile-simplify` (worktree `D:/platform/nextbrain/_wt/orgprof-front`, from `origin/production`
41628edc). Status: **approved 2026-11-19 (Q1–Q3 as recommended), implemented**, decision D-1180.

## 1. Audit

### Where the "Organization Profile" is

An org admin opens the premium workspace (D-1160): tabs **Overview · Management · (Membership) · (Pinned) · Alerts ·
Profile**. The **Profile** tab (`workspace/ws_profile.dart`) is where the overload starts:

| Profile tab group | What it holds |
|---|---|
| Profile card | my name, avatar, "Organization admin · <org>", e-mail, 3 figures |
| Organization (first for admins) | ONE row, "Organization settings", which pushes the D-103 `OrgSettingsPage` |
| Account | Switch account · Personal account |
| My units | a chip per unit |
| Organization pages | **every** sub-page of People / Academics / Timetable / Services (the same pages Management already lists) |
| Workspace preferences | Reset display preferences |

`OrgSettingsPage` (`org_dashboard_settings.dart`, 712 lines) is the real overload: about **40 rows in 8 groups**, plus
sheets:

| Group on the settings page | Rows (each checks its own right) | How often an admin uses it |
|---|---|---|
| Profile card (header) | name · role · e-mail · org chip with **Switch** | glance |
| Shortcut tiles | Certificates · Exports · Notifications · Display | monthly / rare |
| Communication & services | Exams hub; on phones in the D-103 shell also the Services pages | weekly |
| Organization | Messages · Chat settings · **Edit organization** (sheet) · **Join code** (sheet) · Billing · Study system · Department catalog · Councils setup · Setup wizard · New sub-organization · **Switch organization** · Personal account · New organization | setup-time, then rare; join code often at term start |
| Governance | Roles & privileges · Activity log · Terms & regulations · What parents see of grades · Exam policy | rare (roles at setup) |
| App | Language · Assistant · Floating assistant · Dark mode | once |
| Help & legal | Verify a certificate · Get the app · Privacy · Terms | rare |
| Footer | Two-step verification · **Danger zone** (transfer admin seat · close / delete org) · Exit (sign out) · version | rare |

The **Edit organization** sheet itself mixes four topics: names, type, **how people join**, brand colour, logo, about,
official details (licence, e-mail, phone, website, address), and a second **Delete organization** button.

### Pain points

1. **Personal and organization settings are mixed.** Dark mode, language, display and sign out sit beside roles,
   billing and closing the organization. Rows the admin needs for the organization are three levels deep (Profile
   tab → "Organization settings" row → page → sheet).
2. **Duplicates.**
   - Switching appears three times: the card chip, the "Switch organization" row, and the Profile tab's "Switch account" row.
   - Personal account appears twice.
   - Delete organization appears twice (the Edit sheet and the danger zone).
   - The Profile tab's "Organization pages" repeats what Management already lists.
   - There are two profile cards (ProfileHero and OrgProfileCard).
3. **Unclear grouping and labels.** "Organization" holds both identity rows (edit, join code) and structure setup
   (study system, catalog, councils, wizard). Exam policy sits under "Governance", exam feedback under Services. One
   thing has three names: "Settings", "Organization settings" and "More".
4. **Danger next to everyday rows.** Delete hides inside the Edit sheet, one tap from Save.
5. **The identity is invisible.** The admin never sees the organization's own logo, name, colour or contact details;
   they are only in a form.
6. **Mobile.** A 40-row list runs past ten screen heights. The Edit sheet is one long scroll. The sheet uses raw
   `TextStyle`s and hard-coded hex colours, both against the UI-kit rules.

### How the dashboard tabs are built (constraints for the new structure)

- The workspace tabs come from `wsShellItems(ws)` (`workspace/ws_shell.dart`). Each tab is an `OrgShellTab` with a
  `helpPageId: 'home.org/ws_<key>'`, and keys live in `WsTabs`.
- D-1160 caps the phone bar at **5 tabs**; for admins those are Overview · Management · Pinned (once something is
  pinned) · Alerts · Profile.
- D-1170 (yesterday) adds shell pins and tab colours on top, with no new tab.
- The D-103 shell is the kill-switch fallback (`org.teacher_workspace` off). Its Settings tab is the same
  `OrgSettingsPage` and must keep working.

## 2. Information architecture

**The rule: Profile = me; Organization = the organization; Management = the organization's daily work.**

### Tabs for an organization admin (in order)

| # | Tab | Contains | Change |
|---|---|---|---|
| 1 | Overview | as today | – |
| 2 | Management | as today: People · Academics · Timetable · Services, then units; **+ Exams hub** row in Services | small |
| 3 | **Organization** (new, المؤسسة) | the organization's identity card and its settings, grouped (below) | **new** |
| 4 | Alerts | as today | – |
| 5 | Profile | only me: account, my units, my preferences, security, help, sign out | **slimmed** |

Pinned (D-1151) would make a 6th tab on phones; see open question **Q1**.

### New Organization tab (progressive disclosure: an identity card, then short groups, each row opens a page or sheet)

1. **Identity card:** logo, name (ar / en), type, brand colour, status, the official details shown read-only, and
   **Edit details**.
2. **Joining & access:** Join code / QR · How people join (moved out of the Edit sheet) · Roles & privileges.
3. **Structure:** Setup wizard · Study system · Department catalog · Councils · Sub-organizations (+ New).
4. **Policies:** Terms & regulations · Exam policy · What parents see of grades · Chat settings.
5. **Records & billing:** Billing · Activity log · Exports (with the org export log) · Certificate designs.
6. **Danger zone:** collapsed at the bottom: Transfer the admin seat · Close / delete the organization.

### Slimmed Profile tab (admin)

ProfileHero → **Account** (Switch account · Personal account · Messages) → **My units** → **Preferences**
(Notifications for this organization · Display & reading · Language · Dark mode · Assistant · Floating assistant ·
Reset workspace display) → **Security** (Two-step verification) → **Help & legal** → **Sign out** · version.

## 3. Element mapping

| Current element (where) | New home | Reason |
|---|---|---|
| Profile tab card (ProfileHero) | Profile, unchanged | it is me |
| "Organization settings" row (Profile) | removed for admins; a "Go to Organization" link stays for a few weeks | its contents become a tab |
| "Organization pages" group (Profile) | removed **for admins**, kept for non-admins | Management already lists them for admins; teachers have no Management sections (D-1150) |
| Switch account (Profile) | Profile › Account | the one switcher |
| Personal account (Profile and Settings) | Profile › Account, once | duplicate |
| My units | Profile, unchanged | – |
| Reset display preferences | Profile › Preferences | personal |
| OrgProfileCard + Switch chip (Settings) | removed in the workspace (ProfileHero is the card); kept in D-103 | duplicate |
| Shortcut: Certificates | Organization › Records & billing | organization asset |
| Shortcut: Exports | Organization › Records & billing | organization records |
| Shortcut: Notifications | Profile › Preferences | my phone alerts |
| Shortcut: Display | Profile › Preferences | personal |
| Exams hub | Management › Services | daily work, not a setting |
| Messages (ChatEntryTile) | Profile › Account | my inbox (the header icon stays too) |
| Chat settings | Organization › Policies | an organization rule |
| Edit organization (sheet) | Organization › identity card › Edit details | identity |
| …its "How people join" | Organization › Joining & access | access, not identity |
| …its Delete button | removed (the danger zone keeps Close / delete) | duplicate, dangerous next to Save |
| Join code | Organization › Joining & access | access |
| Billing | Organization › Records & billing | – |
| Study system · Department catalog · Councils · Setup wizard | Organization › Structure | setup |
| New sub-organization | Organization › Structure | structure |
| Switch organization (Settings) | removed in the workspace (Profile › Switch account does it) | duplicate |
| New organization | Profile › Account ("Create another organization") | it is about me, not this organization |
| Roles & privileges | Organization › Joining & access | who can do what |
| Activity log | Organization › Records & billing | records |
| Terms & regulations · Exam policy · Parents' grades | Organization › Policies | rules |
| Language · Assistant · Floating assistant · Dark mode | Profile › Preferences | personal |
| Verify a certificate · Get the app · Privacy · Terms | Profile › Help & legal | – |
| Two-step verification | Profile › Security | personal |
| Danger zone | Organization, last, collapsed | organization-level |
| Leave the organization (non-admins) | Profile, before Sign out | personal |
| Sign out · version | Profile, last | – |

Nothing is deleted. Every row keeps its right check (`s.can…`) and its kill-switch key (`featureKey`).

## 4. UX principles applied

- **One topic per group, at most about 6 rows.** Groups have plain headings, each row has one plain line, and the same
  names are used everywhere (one "Switch account", one "Organization").
- **Progressive disclosure.** The identity card shows the essentials; a row opens a page or sheet; the danger zone
  stays collapsed until opened.
- **Sensible defaults.** The tab opens on the identity card; an empty group is hidden, never shown greyed out.
- **Save / cancel.** "Edit details" is a form with Save + Cancel that tells you about unsaved changes. "How people
  join" saves on choice and shows a notice with Undo. Dangerous actions keep the typed-name confirmation.
- **States.** Skeletons while the organization loads; an error card with Retry; logo and description missing →
  "Add a logo" / "Add a description" prompts in the card.
- **Kit rules.** `OrgPageHeader`, `AppSettingsGroup`/`Tile`, tokens, `context.colors`, `t(ar, en)`, RTL;
  `expectNoLayoutErrors` at 320 and 1400 px, Arabic and English, text scale 1.3.

## 5. Navigation flow — nothing feels lost

- Profile keeps a small "Organization settings moved → Organization tab" row for admins for one release (a decision
  to remove it later is noted in DECISIONS).
- Old entries are redirected:
  - `tabs.go('settings')` from the org home's "Settings & roles" link, and a `ws_profile` deep link aimed at
    settings, open the Organization tab for an admin.
  - The command palette lists the Organization rows.
  - The `orgSettings` attention badge moves to the Organization tab.
- Every row's search keywords stay, so the page search finds them.
- Non-admin staff who hold an org-level right (for example `roles`) still reach those rows from Profile, which pushes
  the same Organization page, filtered to their rights.
- The D-103 fallback shell keeps its Settings tab. It is built from the same group builders, so both stay in sync.

## 6. Risks and migration notes

- **Whole-object PUT.** The organization update replaces the whole object, so "How people join" must send every
  field, through ONE body builder shared with Edit details.
- **Phone tab cap.** The new tab makes 6 when Pinned exists (Q1).
- **Help ids.** `home.org/ws_organization` needs a help page in `../back/data/help_seed.json`; then regenerate
  `assets/help/help_index.json` (`test/ui/help_ids_test.dart` fails otherwise).
- **Tests.**
  - `test/org/ws_alerts_test.dart` covers `WsProfileHeader`.
  - The perf budgets (`test/perf/`) must not grow: the identity card reads `OrgSession.current`, so no new request.
- **Data / API.** No server change, no migration. The features guide (`../back/data/app_features_guide.json`) is
  updated: the admin settings entries move from "Profile › Settings" to "Organization".
- **Rights.** The Organization tab shows only for `ws.admin`. Everything else stays where the right allows.

## 7. Implementation steps (each small and testable on its own)

1. **Extract** the settings page's groups into builder functions (`org_settings_groups.dart`), split into org groups
   and personal groups; `OrgSettingsPage` composes them as today. No visible change; the existing tests pass.
2. **Organization tab:** `WsTabs.organization`, `WsOrganizationTab` (identity card + groups) in `wsShellItems` for
   admins; help id + seed; layout harness test.
3. **Slim Profile for admins:** personal groups only; drop the duplicates; the "moved" link row.
4. **Split the Edit sheet:** identity + contact only (no Delete, no join mode); a "How people join" row with the shared
   PUT body; kit styles instead of raw `TextStyle` / hex colours.
5. **Exams hub** row in Management › Services.
6. **Redirects:** the home "Settings & roles" link, the palette, the `orgSettings` badge, `ws_profile` deep links.
7. **Phone tab cap** per Q1.
8. **Tests and docs:** `ws_alerts_test` update, harness for the new tab and the slim Profile, help ids, perf check,
   DECISIONS (D-1180), features guide, `lib/features/org/CLAUDE.md`.

Model split as requested:
- **This model:** the plan, steps 1–2 architecture and the final review.
- **Smaller agents (Sonnet), one short brief each:** steps 3–6 (moves, wiring, redirects) and step 8 (tests, lint, docs).

## 8. Open questions for approval

- **Q1, phone tab cap.** Recommended: on phones the workspace's Pinned tab folds into a strip at the top of Overview
  (the D-1170 pattern), so the bar stays Overview · Management · Organization · Alerts · Profile. Desktop and tablet
  keep Pinned as its own entry.
- **Q2, tab name.** "Organization" (المؤسسة), recommended, or "Settings" (الإعدادات)?
- **Q3, the D-103 fallback Settings tab.** Recommended: same groups, organization first, then personal, so it stays
  identical in content.
