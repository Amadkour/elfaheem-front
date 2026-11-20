# Learning Hub Phase 5: digital store, real web build QA (2026-11-20)

How it was run:
- Back: `_wt/lh-back` (feature/learning-hub, 18185ae), compose project `lhdev` (gateway :41080, volumes kept). `python -m data.migrate` took the schema 0104 → **0105**.
- Two stack settings in `.env` pointed at the default dev stack instead of this one. They were overridden for this run only, through a copy of `.env` passed as `DEV_ENV_FILE`; the repo `.env` is unchanged:
  - `MINIO_PUBLIC_URL=http://127.0.0.1:19000` → `:41900`. 19000 is another stack's MinIO, so presigned uploads would have gone there.
  - `APP_URL=http://localhost:18080/api` → `:41080`. The download grant builds its `/store/dl/…` link from it, so the first download opened `localhost:18080` and got 404.
- **Temporary shim (deleted after the run):** `features/platform/module_settings.py` returned `store = {teacher_items: true, points_enabled: true, review_required: true}`. Phase 6's `module_settings` does not exist yet. Without the shim a teacher cannot create items (403), points are off, and publishing never goes to `pending`. There is no UI or API way to turn these on today.
- Front: `_wt/lh-front` (6c4fc456), `flutter build web --profile --dart-define=API_BASE_URL=http://localhost:41080/api --base-href /app/`, served at `/app/` with an SPA fallback on :41500.
- Driver: playwright-core + headless Chrome, Arabic, 360×780 and 1366×900.
- Accounts:
  - teacher `market.teacher`, super admin `superadmin`, admin `admin` (demo password);
  - student A `lh4.stu1` (id 34, EG prep g2);
  - student B `market.student` (id 30, no study profile);
  - `lh5.stu1` (36) only for API checks.
- Items:
  - **1**: "ملخص QA5 كيمياء الصف الثاني الإعدادي", created through the UI, EG, 50 EGP / 500 points;
  - **2**: an API probe, now hidden;
  - **3**: an SA item, 100 SAR / 800 points, created by the super admin through the API.

Screenshots: `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase5/`.

## Summary

| Step | Result |
|---|---|
| 1. Teacher creates PDF + cover item, EG prep g2, EGP, publishes → pending | **Pass**, but the **cover never shows** (high) and the teacher pages' action bars are cut off at 360 px |
| 2. Admin can't see or use the review queue; super admin approves | **Pass in the UI. FAIL in the API: a regular admin can publish a teacher's pending item without review** (high) |
| 3. EG student sees it; net / VAT 14 % / gross; filter bar | **Pass** for the numbers (43.86 + 6.14 = 50.00) and the filters. **The header's library and cart buttons are invisible** (high) |
| 4. Guest → item → Buy → login → back on the item's checkout | **Pass at 1366.** **At 360 px the Buy bar is under the bottom nav: a guest cannot press Buy** (high) |
| 5. Buy with points; card | **Points: pass.** The order is paid, 500 points were taken, the item is in My Library and the order is in Purchases. **Card: not testable locally** (no provider: 409 `card_unavailable`) |
| 6. Download once; reuse fails; no `file_ref` / keys in JSON | **Pass**, after the device fix below. Reuse → 410 `store_link_expired`. The device rule blocks a buyer's download on the device they paid from (medium) |
| 7. A second student cannot download | **Pass** (403 `store_not_owned`; empty library; the item is not owned) |
| 8. SA VAT 15 % on Education levels; SA item numbers | **Pass** (100.00 SAR = 86.96 + 13.04 at 15 %). An EG student opening the SA item is charged EG VAT in SAR (medium) |
| 9. Teacher edits an approved item → pending again | **Pass** ("حُفظ وأُرسل للمراجعة مرة أخرى"; pending; gone from the store; the buyer keeps the item and the download) |

## 1. Teacher creates an item: pass, with bugs

- Walk: حسابي › عناصري في المتجر (`03`) › عنصر جديد (`04`). I entered the AR/EN titles and descriptions and picked:
  - type ملخص (`06`);
  - country مصر, stage الإعدادي, grade الصف الثاني (`10_stage_grade`);
  - subject علوم (`11`);
  - price 50, 500 points (`12`).
- Cover: picked a PNG, went through the cropper and chose "استخدام الصورة" (`14`, `15`). Then حفظ (`16`) and file رفع with a PDF (`17`). The PUT to MinIO and the confirm both returned 200: `file_size=389`, `sha256` set, `has_file=true`.
- Publish: نشر → toast "أُرسل للمراجعة" (`18`). The API status is `pending`, and the list shows بانتظار المراجعة (`19`).
- **BUG (high): the cover never shows, anywhere** (teacher form `15`/`16`, store card `41`, item page `46`, admin lists, library `64`). The cover is stored and served correctly; only the app builds the wrong URL from it.
  - `cover_url` comes back as a relative signed path, `/api/v1/org/files/<token>`.
  - The app loads it against the page origin (`http://localhost:41500/api/v1/org/files/…` → 404, 11 times in the server log). The absolute `<API_BASE_URL>/api/v1/org/files/…` answers 307 to the image.
  - In production the same relative path also misses the `/api/api/v1` prefix.
  - Likely file: `lib/features/store/store_widgets.dart:37-56` (`StoreCover`), plus `StoreCoverThumb` in `lib/features/store/manage/store_manage_views.dart:100`. Pass the URL through `orgFileUrl()` (`lib/features/org/org_ui.dart:577`), or resolve it in the `coverUrl` parse (`store_models.dart:112/387`, `store_manage_api.dart:180`).
- **BUG (medium): the action bars sit at the left edge, and at 360 px they slide under the bottom nav.**
  - In the item form, حفظ / نشر / إخفاء / حذف start at x=0 with no gutter (`17`). After publishing they are half hidden behind the dashboard nav (`18b_bottom_bar`).
  - The list page's "عنصر جديد" and the item cards also touch the left edge (`03`, `19`).
  - Likely file: `lib/features/store/manage/store_manage_pages.dart` (page padding and the bottom bar inside the dashboard shell).
- Minor:
  - Before the first save, the price field has no currency ("السعر"). It becomes "السعر (EGP)" only after saving (`12` vs `16`). Prices show "EGP"/"SAR" everywhere in the store, while the rest of the app writes ج.م.
  - The title stays "عنصر جديد" after the first save (`16`).
  - "Country" is labelled twice in the targeting card ("الدولة / الدولة", `08c`).
  - The file size reads "0 KB" for a 389-byte file (`17`, every list).
  - Changing the stage clears the subject without a word.
  - Stage and subject chips expose no selected state to screen readers (`aria-selected` / `checked` are null).
  - The list shows "1 مبيعات" (`100`). Use `countText`.
  - The page URL stays `/teacher_dashboard/my-profile`, so a reload loses the page.
- A rejection is invisible to the teacher. The super admin's رفض puts the item back to مسودة with no note on the item (`20`, `21`); the note goes only into a notification. Seen by accident: my API probe sent `approve:false` as the super admin. Likely file: back `features/store/store_service.py:564-585` (`review` stores no note), plus the item form.

## 2. Review queue: pass in the UI, FAIL in the API

- Admin (`admin@example.test`), 1366: المالية والطلبات › المتجر الرقمي opens a plain item list with no المراجعة or الطلبات tabs (`32_admin_store_hub`). The API answers 403 `admin_required` on `GET /admin/store/items`, `POST /admin/store/items/1/review` and `GET /admin/store/orders`. **Pass.**
  - Nit: for the admin, the page is titled "عناصري في المتجر" while it lists every seller's items.
- Super admin: the hub has العناصر / المراجعة (1) / الطلبات (`34`). المراجعة shows the card with رفض and موافقة ونشر (`35`). Approving gives toast "نُشر العنصر", an empty queue (`36`), and status `published`. **Pass.**
- **BUG (high, back): a regular admin can still publish a teacher's pending item, bypassing the super admin review** (5.R #5 closed only `/admin/store/*`). Probe on item 2 (teacher's, `pending`), as `admin`:
  1. `POST /store/manage/items/2/publish` → 200 `published`.
  2. `PATCH {status: hidden}`, then `publish` again → `published`.

  Likely file: `features/store/store_service.py:529-539` (`publish`: `"pending" if review_required and not is_admin(user)`), and `managed_item` letting any admin manage another seller's item. Either admins don't publish other sellers' pending/hidden items, or only `is_super_admin` skips review. The UI hides نشر on a pending item, but إخفاء followed by نشر is reachable.
- Minor (review UX): the review card shows no seller name and gives no way to open the file before approving (`35`).

## 3. Student store: pass, with a high UI bug

- Student A at 360: المتجر tab (`41_store_tab_360`). The bar starts on "تصفية · 1" with the chip "صفك الدراسي", the count "عنصر واحد", and the card at 50.00 EGP.
- Item page (`46_item_page_360`): EGP 50.00 الإجمالي شامل الضريبة, السعر قبل الضريبة 43.86, ضريبة القيمة المضافة (14 %) 6.14, أو 500 نقطة. This matches the API (`net 43.86, vat 6.14, gross 50.0, vat_percent 14`). **Pass.**
- Filter sheet (`42`, `43`, `44`, `45`): stage → grades → subject → عرض النتائج gives "تصفية · 2" with removable chips. The API agrees: grade 10 → 1 item, grade 11 → 0, subject 6 → 0, country SA → 0. **Pass.**
- **BUG (high): the header's مكتبتي and السلة buttons are invisible** (`41`, crop `tmp`). They are white icons on the white header card. The buttons are there (48×48 at x 36–132) but nothing is drawn; at 1366 they are faint (`56`).
  - Cause: `Icon(..., color: context.colors.onHero)` on a `ScreenAppBar`.
  - Likely file: `lib/features/store/store_tab.dart:228` and `:237`. Use the app bar's normal icon colour.
- Minor:
  - The item page's header title runs past its card in two clipped lines at 360 (`46`).
  - The filter sheet's subjects ignore the chosen stage and mix SA subjects (لغتي, كفايات لغوية) for an EG student, while the item form filters them by stage (`42` vs `11`).
  - There is no country in the sheet. A student without a profile sees EGP and SAR items mixed (`94`). The same gap was noted for courses in Phase 4.
  - The cart is lost on a reload (`السلة` count gone).

## 4. Guest → Buy → login → checkout

- **BUG (high): at 360 px the item page's Buy / Add-to-cart bar is under the dashboard's bottom nav.**
  - For a guest (whose screen has the extra "أنت تتصفح كضيف" banner) it is fully hidden (`53_guest_item`). Tapping where "اشترِ الآن" sits opened كورساتي (`54_guest_buy_misclick`).
  - For a signed-in student the bar is half hidden (`46`, `95`); I could only hit it at its top edge.
  - Likely file: `lib/features/store/store_item_page.dart` (its bottom bar in the dashboard shell needs the nav's inset, or the page must be pushed above the shell).
- At 1366 (`56`, `57`): اشترِ الآن → the guest sheet (`58`) → تسجيل الدخول.
  - `pending_intent` = `{"v":1,"kind":"buy_store_item","id":"1",…}` (`59`).
  - After signing in as student A, the app opened `/app/store/1` with **إتمام الشراء** already open (`60`, `61`), and the intent was cleared. **Pass.**
- Medium: `/app/store/<id>` and `/app/store/library` are not real routes. Opening a shared item link signed out goes to `/login` (`50`). Reloading `/app/store/3` or `/app/store/library` signed in lands on the dashboard (`112`). Likely file: `lib/main.dart` `_router` (no `/store/…` case) and `AppNavigator`.
- Minor (checkout sheet):
  - The amounts sit mid-sheet instead of at the end edge.
  - At 360, "ضريبة القيمة المضافة (14 %)" breaks before "%)" (`83`).
  - بطاقة is preselected even when no card provider exists, and the error's button reads "أعد المحاولة" (`84`).
  - "رصيد النقاط لا يكفي" offers no way to top up (`85`).
  Likely file: `lib/features/store/store_checkout.dart`.

## 5. Buying

- Points: 2000 points were granted to student A (`POST /admin/points/grant`). In the checkout I chose النقاط (500) → ادفع 500 نقطة → "تم الشراء" (`62`, `63`).
  - DB: `store_orders` 1 is `paid`, `points`, EGP 43.86 / 14.00 / 6.14 / 50.00, `points_spent` 500.
  - `store_library` (34, 1, order 1); balance 2000 → 1500; `sales_count` 1.
  - مكتبتي lists the item (`64`, `110_library_360`), and المشتريات shows "طلب #1 · مدفوع · 500 نقطة · بالنقاط" (`65`, `111_purchases_360`). **Pass.**
- Card: **not testable locally.** No provider keys are set in `.env`. `POST /store/orders {method: card}` → 409 `card_unavailable`, `providers: []`; the UI shows "الدفع بالبطاقة غير متاح حالياً" (`84`).
- Zero balance (student B): 402, with the message "رصيد النقاط لا يكفي: تحتاج 500 ولديك 0" (`85`).

## 6. Download

- **Medium: a buyer can pay on a device where they cannot download.**
  - Student A's account was bound to the Phase 4 device. The purchase went through on this browser, because `/api/v1/store/` skips the device guard, but افتح gave 403 and the toast "لا يمكن التنزيل على هذا الجهاز" (`68`). The API body was `DEVICE_MISMATCH` / `DEVICE_ID_MISSING` (`require_device`).
  - The toast offers nothing to do next, such as the device-switch request.
  - Either check the device before taking the money (`POST /store/orders`), or link the switch request from this toast. Files: back `features/store/api/store_router.py:112`, front `lib/features/store/store_library.dart`.
- After freeing the device slot (DB) and fixing `APP_URL`, افتح worked:
  1. `POST /store/library/1/download` → 200;
  2. a new tab opened `GET /store/dl/<token>` → 302;
  3. `GET 127.0.0.1:41900/edu-private/store/1/file/<uuid>?…response-content-disposition=attachment…` → 200, and the file downloaded.
  The library card then shows "آخر تنزيل" (`110`).
- Reuse: the same `/store/dl/<token>` → **410 `store_link_expired`**, both with no auth and as the owner. In a browser tab the user sees raw JSON (`71_link_reuse_410.png`). Minor: a small HTML page would read better.
- Another user's link: a fresh token of A's, opened with B's bearer → 403. Opened with no auth, it redirects (302): within its 120 s it is a forwardable bearer link (by design, noted).
- JSON inspection: the app's responses are encrypted envelopes (`{"n","ct"}`), so I called every store route in plain JSON with the same accounts and searched the output (`alljson.txt` in the scratchpad). Routes: items, item, quote, orders, order, library, manage list, manage item, admin items, admin orders.
  - No `file_ref`, `preview_ref`, `edu-private` or `store/<id>/file/…` appears in any of them.
  - Only the 302 `Location` carries the signed object URL.
  - Manage, library and download responses carry `sha256`, `file_name` and `file_size` (not keys). **Pass.**

## 7. Second student: pass

Student B (`market.student`), 360:
- the library is empty (`81b_s2_library_empty`);
- the item page offers Buy, not Open (`82`);
- `POST /store/library/1/download` → 403 `store_not_owned`.

## 8. SA VAT

- Super admin › المالية والطلبات › المراحل الدراسية › المملكة العربية السعودية: "SAR · ضريبة 15% · الأسعار شاملة الضريبة". It was already 15. I set 16 through تعديل and saved (`93a_vat_16`), then 15 again (`93_vat_saved_15`). `edu_countries.SA.vat_percent = 15.00`, and `updated_at` changed.
- SA item 3 (100 SAR, inclusive), seen by student B (no profile): SAR 100.00, before VAT 86.96, VAT (15 %) 13.04, or 800 points (`95_sa_item_page`). That is 100 / 1.15 = 86.956 → 86.96. **Pass.**
- **Medium (back, design): an EG-profile student who opens the SA item by link is quoted Egypt's VAT in SAR:** `GET /store/items/3` and `POST /store/quote [3]` → `currency SAR, vat_percent 14, net 87.72, vat 12.28`.
  - `vat_country` (`store_service.py:109-117`) prefers the buyer's country over the item's, whatever the currency.
  - The list hides SA items from EG students, so only deep links reach this.
  - Decide: tax by the item's country, or refuse an item whose currency differs from the buyer's country currency.
- Mixed cart: `POST /store/quote [1, 3]` → 409 `store_mixed_currency` (as designed).
- Minor: on the Education levels page the content touches the sidebar and the left edge (no gutter, `90`).

## 9. Teacher edits an approved item: pass

- Teacher › عناصري في المتجر shows "منشور (1)" (`100`). I opened item 1 (`101`), changed the price 50 → 55 (`102`) and pressed حفظ.
- The toast read "حُفظ وأُرسل للمراجعة مرة أخرى" (`103`). The status is `pending`, and the note under the price is "يدفع الطالب 55 EGP (منها ضريبة 6.75 EGP)", which is correct.
- `GET /store/items` no longer lists it. Student A still has it in `/store/library`, and a download grant still works.

## Network and console

| What | Status | Note |
|---|---|---|
| `GET <origin>/api/v1/org/files/<token>` (store covers) | 404 | the cover bug, step 1 |
| `POST /store/library/1/download` | 403 | device rule, step 6 |
| `GET localhost:18080/api/api/v1/store/dl/…` | 404 | stack `APP_URL`, fixed for the run |
| `POST /store/orders` | 409 / 402 | card unavailable / not enough points, expected |
| `/me/events`, `/me/attention` CORS errors, 503 | | only while I restarted the api |
| 401s | | my own API logins rotated the browser sessions' tokens |
| `releases/releases.json`, `LazyFontManifest.json` | 404 | local serving, as in Phase 4 |

- Console: Flutter's "Null check operator used on a null value" in `SemanticsObject.updateChildren` showed up a few times. It comes from the web engine's semantics tree while the driver forces accessibility on, and no screen broke with it.
- No overflow stripes were seen. RTL was correct except the checkout's wrapped "(14 %)". No untranslated keys appeared on the paths walked.

## Not done

- Card checkout, sandbox return and webhook: no provider keys locally.
- The preview file (معاينة) and the in-app protected reader (`store_reader.dart`): the reader is mobile only; on the web, افتح opens the link.
- Kill switches `student_tab_store`, `store.buy`, `store.points`, `store.manage`, `admin.store`.
- The daily download limit (429).
- A real SA student account: none exists locally. SA numbers were seen as a no-profile student.

## Re-test after the fixes (D-1339, 2026-11-20)

Same stack (`lhdev`, volumes kept), back `_wt/lh-back` with the D-1339 changes (mounted source), a new `--profile`
web build in `C:/Users/ahmed/AppData/Local/Temp/lhweb5/app`, served on :41500. The `.env` copy with `MINIO_PUBLIC_URL`
:41900 and `APP_URL` :41080 was passed as `DEV_ENV_FILE` again. **No shim:** the store now reads the CONTRACT §6
`module_settings` rows itself, so a temporary table with one platform row (`teacher_items`, `points_enabled`,
`review_required` true) stood in for Phase 6; it was dropped after the run (migration 0106 creates it). Screenshots in
`C:/Users/ahmed/AppData/Local/Temp/lhshots/phase5/retest/`. Headless Chrome, Arabic, 360×780.

| Item | Was | Now |
|---|---|---|
| Admin publishes a teacher's item (high) | 200 `published` | **Fixed.** `admin` → `POST /store/manage/items/2/publish` 403 `store_not_owner`; hide item 1 (200 `hidden`) then publish → 403; the teacher re-submits → `pending`; the super admin approves → `published` |
| Covers never load (high) | relative `/api/v1/org/files/…` → 404 | **Fixed.** `POST /store/manage/items/1/cover`: PDF bytes → 422 `store_bad_file_type`; a PNG → 200, `cover_url` `http://127.0.0.1:41900/edu-images/store-covers/1/….png` (GET 200 `image/png`), item back to `pending`; `cover_url: http://evil.test/…` → 422 `store_bad_cover`. The cover shows on the store card (`41_store_tab_360`), item page (`46_item_in_shell_360`), library (`112_library_deeplink`) and teacher list (`03_teacher_store_items`) |
| Header Library / Cart invisible (high) | white on white | **Fixed** (`41_store_tab_360`, `52_guest_store`): dark library icon, the cart greyed while empty, the "i" next to them |
| Buy bar under the bottom nav at 360 (high) | hidden for a guest | **Fixed.** On phones Buy / cart sit in a bar pinned above the shell's nav (`53_guest_item`); the guest's Buy opens the sign-in sheet (`58_guest_buy_sheet`); an owned item shows the "in your library" banner there (`46_item_in_shell_360`) |
| Paid but download refused on another device (medium) | toast "not allowed" | **Explained.** Open → 403 `DEVICE_MISMATCH` → the device dialog with "send a request" (`68_download_tap`); the toast says the purchase is safe in the account. Paying stays allowed (D-1339) |
| `/store/…` links lost on reload (medium) | dashboard | **Fixed.** Reloading `/app/store/3` opens the item, `/app/store/library` My Library (`95_sa_item_deeplink_360`, `112_library_deeplink`); signed out → the login, then back (registry routes `store.item`, `store.library`) |
| EG student quoted EG VAT on an SA item (medium) | 14 % in SAR | **Fixed.** `GET /store/items/3` and `POST /store/quote [3]` as `lh4.stu1` (EG): SAR, 15 %, 86.96 + 13.04 = 100.00 (`95_sa_item_deeplink_360`) |
| Teacher pages touch the edge (medium) | no gutter | **Fixed** (`03_teacher_store_items`, `18b_form_bottom`): page gutter, the form's actions clear of the nav |

Also checked: buyer orders carry `failure_code` and no `failure_reason`. Header title is the item kind now (a long
title no longer breaks the header in two). Not re-walked: card checkout (no provider keys), the phone reader.
