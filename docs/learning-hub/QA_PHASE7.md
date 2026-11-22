# Learning Hub Phase 7: offline-first sync, real-app QA (2026-11-21)

## How it was run

Back end:
- `_wt/lh-back` (feature/learning-hub), compose project `lhdev`, gateway :41080, volumes kept.
- The api image was rebuilt. `python -m data.migrate` took the schema 0107 → **0108**.
- The `.env` copy from Phase 5/6 was passed as `DEV_ENV_FILE`, with `MINIO_PUBLIC_URL` :41900 and `APP_URL` :41080.
- **The stack was shared during the walk.**
  - Another session committed `cde295b` "Phase 7 review fixes (7.R)" mid-walk. The api's `--reload` then hung on the `features/sync/` change: the gateway answered 504, and the api needed a restart plus about 40 minutes on a host at 100 % CPU.
  - Someone also started the gateway again at 12:58:55 UTC while I had it stopped.
  - So the Windows walk ran against 0feb28f + cde295b. Every offline step below was re-checked against the gateway logs and redone if the gateway turned out to be up.

Front end:
- `_wt/lh-front` at 48585c0d.
- Web: `flutter build web --profile --dart-define=API_BASE_URL=http://localhost:41080/api --base-href /app/`.
  - Built into `C:/Users/ahmed/AppData/Local/Temp/lhweb7/app` and served at `/app/` on :41500.
  - Driven by playwright-core + headless Chrome, Arabic, at 360×780 and 1366×900.
- Windows: `flutter build windows --profile` with the same define.
  - The first build fails; see W-5. It was built with `CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`.
  - The Flutter view exposes no UI Automation tree, so the app was driven by screen coordinates and SendKeys.
  - Screenshots were taken with System.Drawing (window 2200×1380).
- "Offline" means `docker compose -p lhdev stop gateway`. The PC kept its network link, so connectivity_plus always reported a link.

Accounts and data:
- Student `lh4.stu1` (34, EG prep g2) and teacher `market.teacher` (29); `lh5.stu1` (36) for API probes. All use the demo password.
- `users.device_id` / `user_devices` of 29 and 34 were cleared before each sign-in.
- One store item was added by SQL: `store_items` id 4, "ملخص QA7 للمتجر", a copy of item 1. It gives an unowned item for the web checkout check.

Screenshots: `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase7/`.
- `w*` = web.
- `t*` = web teacher.
- `x*` = Windows.

## Summary

| Area | Result |
|---|---|
| Web: game play, nahw attempt, Quran record, study profile save, store checkout | **Pass.** Every write posts straight to its route. No `/sync/push` is sent on the web. There is exactly one row per action. |
| Web: sync chip | **Pass.** Never shown at 360 or 1366. |
| Web: console | **Pass.** The only errors are `/releases/releases.json` 404 (static server), my own probe of `store/items/2` 404, and the expected 409 `card_unavailable`. |
| Windows: tabs from the cache (games, nahw, Quran, Quran progress, home) | **Pass** (`x20`, `x30`, `x31`, `x42`, `x43`, and after an offline restart `x70`, `x71`). |
| Windows: game play offline → stars at once + "saved on this device" + chip count | **Pass** (`x26`, `x27`). |
| Windows: nahw attempt offline | **Pass** (`x41`, chip 3). |
| Windows: study profile offline | **Pass**: queued, chip 1 (`x60`). |
| Windows: Quran entry offline (teacher) | **FAIL (high)**: W-3. |
| Windows: "needs a connection" on checkout / enrolment | **FAIL**: never shown. W-1, W-4. |
| Windows: drain on reconnect, one row per op, chip hides | **Partial.** Rows and chip pass. The drain happens only after the backoff timer or a manual Retry: W-2. |
| Windows: points cap through the outbox | **Pass.** The two offline plays got +1 and 0 (day total 21 = EG cap). |
| Windows: restart offline with ops queued | **Pass.** The op survived the restart and went out after Retry (`x70` → `x77`). |
| Windows: logout wipes the local DB and cache | **Pass.** 10 `read_cache` rows → 0, `outbox` 0. |
| API probes (`/sync/push`, `/sync/pull`) | **Pass** (details at the end). |

## Findings

### W-1 (high): an outage during a session is never noticed, so the offline guards never fire

Steps:
1. On Windows, sign in as the student and load the tabs.
2. Stop the gateway.
3. Play a game, then open a course from the home and press **انضم الآن** (Join now).

Seen:
- The chip shows a cloud-upload icon with the pending count, never the "offline" state (`x26`, `x41`).
- `offlineBlocked()` returns false, so Join opens the checkout. The checkout then sits on skeleton cards indefinitely, with the button "متابعة" (Continue) greyed out. There is no "needs a connection" text (`x62_join_offline_b`, `x63_continue_offline`).
- The writes still work: the outbox catches transport failures, and `readThrough` falls back to the cache.

Cause: `AppConnectivity.online` turns false only in two cases:
- the theme fetch fails at start-up (`ThemeConfigProvider.serverUnreachable`);
- connectivity_plus reports a link change.

A server that goes away mid-session, or a Wi-Fi with no internet after start-up, leaves `online == true` for the whole session. Every D-1351 guard (`offlineBlocked`, the "offline" chip, the `!offlineReadsOnline().value` branches) depends on that flag.

Likely files:
- `lib/core/offline/app_connectivity.dart`: nothing marks the server unreachable on a transport failure.
- `lib/core/offline/sync/sync_engine.dart` (`_push` catch) and `offline_reads.dart` (`readThrough` catch): a transport failure could call `AppConnectivity.instance.reportServerReachable(false)` and start a probe.

Note: `x48_pay_offline` (Pay opened the Moyasar card form) was taken after someone else had restarted the gateway, so it is not evidence for this finding. `x62`/`x63` are.

### W-2 (high): after an offline start, the app stays offline when the server comes back until the user presses Retry

Steps:
1. With one op queued and the gateway stopped, kill the app and start it again.
   - It starts offline: the banner reads "لا يوجد اتصال بالإنترنت", and the chip shows the cloud-off icon with 1 (`x70`).
2. Start the gateway.
3. Wait 3.5 minutes without touching anything.

Seen:
- The banner and the offline chip stay (`x76_after_reconnect_wait`, 13:24 UTC).
- `sync_ops` has no `study_profile` row.
- Pressing the banner's **إعادة المحاولة** (Retry) drains it within seconds. The banner and chip go, and `sync_ops` gets the row (`x77_after_retry`).

Cause:
- `AppConnectivity.serverProbe` runs only when connectivity_plus reports the link coming back.
- With the link up all along (Wi-Fi up, server or ISP down), nothing re-probes.
- The engine's `_drain` returns early while `online` is false, so the backoff timer never even starts.

For comparison, the mid-session case (W-1, `online` stuck at true) drained on its own through the backoff timer about 2.5 minutes after the server returned (`sync/push` at 13:01:33).

Fix idea: while offline with a non-empty outbox, probe the server on the same backoff (`EventOrPoll` style). Also probe on resume.

### W-3 (high): a teacher cannot record a Quran entry offline

Steps:
1. On Windows, sign in as `market.teacher`.
2. Go to حسابي › تعليم القرآن (Account › Quran teaching) while online (`x83`).
3. Stop the gateway.
4. Open **سجل التسميع** (the record sheet).

Seen:
- Student: "لا طلاب في هذا البرنامج" (No students in this program), plus an English error "No internet connection…" (`x84`).
- Pressing حفظ (Save) answers "اختر الطالب أولاً" (Choose the student first) (`x85`).
- The F13 offline path for Quran entries is therefore unreachable. The only Quran op a device can make is the teacher's, and the teacher cannot pick a student.

Cause: `QuranApi.courseStudents` (`GET /courses/{id}/enrolled-students`) is not wrapped in `readThrough`, and it is not in the F13 cache list.

Likely files: `lib/features/quran/quran_api.dart:169` and `quran_record_sheet.dart`.

Related (web, low): when that request fails or times out online, the sheet also says "No students in this program" instead of offering a retry (seen once on the web teacher under load: `t02_record_sheet_tall`).

### W-4 (medium): "needs a connection" (D-1351) never appears

- In a real offline state (after an offline start, `online == false`), the pages that hold the guarded buttons do not open. Each shows the English "No internet connection…" error instead:
  - course page (`x73_book_offline_b`);
  - store browse (`x44_store_offline`);
  - points wallet (`x75_wallet_offline`).
- In the mid-session state the guard does not fire (W-1).
- So the D-1351 sentence "يحتاج هذا إلى اتصال بالإنترنت…" was never seen on any path.
- Not a money risk: the server refuses anyway. But the designed explanation is dead code in practice.

After W-1 is fixed, re-check that a course page opened before the outage shows the notice on Join, and that the store item page shows it on Buy.

### W-5 (medium): the Windows build fails with the installed Visual Studio 2026 toolset (MSVC 14.52)

Steps: `flutter build windows --profile` in `_wt/lh-front`.

Seen:
- `error C2338 … STL1011: … <experimental/coroutine> … deprecated … REMOVED SOON` in:
  - `bluetooth_low_energy_windows_plugin.vcxproj`;
  - `permission_handler_windows_plugin.vcxproj`.
- "Build process failed" after 78 minutes on a loaded host.
- It builds with `set CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` (log `C:/Users/ahmed/AppData/Local/Temp/lhwin7_build.log` vs `lhwin7_build2.log`).

Phase 8.2 (Windows installer) will hit this. Two options:
- add the define in `windows/CMakeLists.txt` (`add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)`);
- or bump the two plugins.

### W-6 (low): connection errors are English in the Arabic UI

"No internet connection. Please check your network and try again." appears on:
- the home's explore list (`x70`);
- the store (`x44`);
- the course page (`x73_book_offline_b`);
- the wallet (`x75`);
- the record sheet (`x84`).

On the web teacher's Quran hub under a slow server, "The request took too long. Please try again." appears in the same way (seen in the semantics labels just before `t01_quran_hub_tall`).

The offline banner itself is Arabic. Likely file: the transport-error message in `lib/core/api_client.dart` / `api_error_text.dart` (no bilingual text for the connection and timeout cases).

### W-7 (low): the chip is missing from some headers while ops are pending

- It is shown on:
  - the home and Store tab top bar;
  - the game and nahw pages;
  - the checkout header (`x26`, `x41`, `x44`, `x47`).
- With 3 ops pending it was absent on:
  - the حسابي (Account) tab (`x50_account_offline`);
  - بيانات الدراسة (Study details) (`x51`, `x52`);
  - the checkout header after Back (`x49`).
- Later, on the same study page with 1 pending, it was shown (`x60`).
- I could not tie it to a rule. Possibly the chip is not in every `ScreenAppBar` variant, or the count was refreshing. Worth a widget check: every header with tools should show it.

### W-8 (low, outside Phase 7): the card form shows a SAR symbol for an EGP total

The Moyasar card form says "Pay ⃁ 680.80" for a 680.80 ج.م checkout (`x48_pay_offline`, taken online). This predates Phase 7.

## Web walk (online only, as before)

Student `lh4.stu1` at 360×780.

**Game.** `games/5` (سور قصيرة, the short-surahs quiz):
- Result 1 star, "2 / 6 · 33%", "+5 نقطة" (`w05_quiz_result_360`).
- One `POST /games/5/plays`. The other "POST" in the request log was the CORS preflight.
- DB: `game_plays` 5 has 5 points. No `sync_ops` row.

**Nahw.** `nahw/lessons/2`, two full attempts:
- `POST /nahw/lessons/2/attempts` ×2.
- `nahw_attempts` 2 and 3, each 5/8.

**Quran record.** Teacher `market.teacher`, حسابي › تعليم القرآن › سجل التسميع, student طالب المرحلة الرابعة:
- `POST /quran/progress`.
- `quran_progress` 3 (34, surah 1, `client_id` 26b16903…).
- The first opening showed "لا طلاب في هذا البرنامج" while the server was slow (see W-3, related).

**Study profile.** School "مدرسة QA7" → `PUT /me/study-profile` → saved (`w11_study_saved_tall`).

**Store checkout.** Item 4:
- اشترِ الآن (Buy now) → "إتمام الشراء" (checkout) → "ادفع 55.00 EGP" (pay) → `POST /store/orders` 409.
- The UI shows "الدفع بالبطاقة غير متاح حالياً" (card payment is not available right now), as in Phase 5 (`w15_store_pay_360`).

**Chip.** None at 360 (`w01_home_360`) or 1366 (`w16_home_1366`, `w17_game5_1366`).

## Windows walk, in order

1. **Online.** Sign in (`x08`). Games, then "اعرض كل المستويات" (show all levels) (`x10`), game 5 (`x11`), nahw (`x12`), lesson 3 (`x13`), Quran (`x14`), my progress (`x15`). DB baseline:
   - 5 plays;
   - 3 nahw attempts;
   - 0 `sync_ops`;
   - today's points 20 (EG cap 21).
2. **Gateway stopped.**
   - Games tab from the cache (`x20`).
   - Game 5 played twice: stars at once, "حُفظت النتيجة على هذا الجهاز…" (saved on this device), chip 1 then 2 (`x26`, `x27`).
   - Nahw lesson 3: 3/9 with the same note, chip 3 (`x41`).
   - Quran tab and my progress from the cache (`x42`, `x43`).
   - Store browse: error (`x44`).
3. **Not offline.** The gateway was restarted by another session at 12:58:55. The course, checkout and first study save (`x46`–`x55`) ran online.
   - The outbox drained at 13:01:33: `sync_ops` 12, 13 (`game_play`) and 14 (`nahw_attempt`), all `applied`.
   - `game_plays` 17 / 18 got `points_awarded` 1 / 0 with the device times 12:47 / 12:49 as `played_at`.
   - `nahw_attempts` 4 is 3/9.
   - No duplicate `client_id` in either table.
4. **Gateway stopped again at 13:10.**
   - Study details edited to "مدرسة QA7 off2": queued, chip 1 (`x60`).
   - Join → checkout skeleton, no notice (`x61`–`x63`, W-1).
5. **App killed and restarted while offline.**
   - Starts offline with the banner, chip cloud-off 1 (`x70`).
   - Quran tab from the cache (`x71`).
   - Teacher page, Book → course page error (`x72`, `x73`).
   - Wallet error (`x75`).
6. **Gateway started at 13:20:44.**
   - Nothing drains for 3.5 minutes (`x76`, W-2).
   - Retry → drained: `sync_ops` 15 (`study_profile`, `applied`, 13:24:55), profile "مدرسة QA7 off2" (`x77`).
7. **Logout** (`x79`, `x80`).
   - `%APPDATA%/DoubleY/NextBrain/nb_local_v1.db`: `outbox` 0, `read_cache` 10 rows (user 34: home, games list ×2, game 5, nahw lesson 3 + levels, Quran teachers, meta, progress, study profile) → **0 rows**.
   - The cache held no identity-number fields; the profile payload has none.
8. **Teacher** `market.teacher` online → Quran hub (`x83`). Gateway stopped → record sheet without students (`x84`, `x85`, W-3).

## API probes (`lh5.stu1`, back 0feb28f)

- The same op pushed twice → `applied`, then `duplicate` with the first `entity`. The same `client_id` through `POST /games/6/plays` → the same play (`id` 6). One row.
- 101 ops → 422 `sync_too_many`.
- Ten plays in one push → `points_awarded` 5, 5, 5, 1, then 0 ×6. The day total is 21 = EG cap. The cap holds.
- `GET /sync/pull?since=…&kinds=game_progress,user_badges` → only the changed rows, plus `cursor`.
- A `study_profile` op with `base_updated_at` 2020-01-01 → `rejected` `sync_stale`, with the server's profile as `entity`.

## Not walked

- A real link loss (Wi-Fi off / connectivity_plus `none`). The agent's own network could not be cut. W-1 and W-2 may not reproduce when the OS reports the link change, but a server or ISP outage behind a live Wi-Fi does reproduce them.
- The "needs a connection" notice: no path reached it (W-4).
- A Quran entry made offline and synced: blocked by W-3.
- Opening an owned store file offline: the student owns item 1, but the store pages do not open offline (`x44`), and My Library was not reached.
- A `sync_stale` refetch in the app UI: probed by the API only.

## Test notes

- `docker compose -p lhdev` is shared. Another session restarted the gateway and edited `features/sync/`. Check `docker inspect lhdev-gateway-1 --format '{{.State.StartedAt}}'` and the gateway log before trusting an "offline" step.
- The `theme/windows` 422 requests in the gateway log came from another client. This app asks for `theme/android` on Windows.
- Data left in the volumes:
  - `store_items` 4;
  - the plays, attempts and `quran_progress` rows above;
  - `sync_ops` rows 1–15;
  - study profile 34's school "مدرسة QA7 off2";
  - device bindings of 29 / 34 cleared.
