# API: international users (BACKEND.md §5, RULES.md §3, BRANDS.md; backend WP5)

Backend branch `rd/be-intl`, migration `0130`. Every new request field is optional: an older app is unchanged.
The app never asks for nationality and never infers it (or the country) from a name, a phone number or a language.

## 1. Market defaults are data

| Setting | Stored in | Fallback |
|---|---|---|
| default country | `app_settings` `platform.default_country` | env `PLATFORM_DEFAULT_COUNTRY`, else `EG` |
| featured countries (the short list on the picker) | `platform.featured_countries` | env `PLATFORM_FEATURED_COUNTRIES` (comma list), else the countries with a curriculum (`edu_countries`, active) |
| platform time zone | `platform.timezone` (existing) | env `PLATFORM_DEFAULT_TIMEZONE`, else `Africa/Cairo` |

NextBrain deploys with nothing set (Egypt, Africa/Cairo); the downstream product sets `PLATFORM_DEFAULT_COUNTRY=SA`,
`PLATFORM_DEFAULT_TIMEZONE=Asia/Riyadh`, `PLATFORM_FEATURED_COUNTRIES=SA,KW,AE,BH,QA`.

- `GET /api/v1/theme/{platform}` → `platform` gains `default_country` (ISO-2) and `featured_countries` (list).
- `GET /api/v1/admin/platform-settings` gains the same two fields; `PUT` accepts them (optional: a body without them
  keeps the stored values). 422 `bad_country` for a code that is not in the world list.

## 2. Countries

### `GET /api/v1/countries?lang=ar|en` (public, no sign-in, same answer signed in)

Every ISO-3166 country people live in (243), for "country of residence" and the phone country-code picker.

```json
{
  "version": 1,
  "default_country": "EG",
  "featured": ["EG", "SA"],
  "countries": [
    {"code": "SA", "name_ar": "المملكة العربية السعودية", "name_en": "Saudi Arabia", "dial_code": "+966",
     "timezone": "Asia/Riyadh", "timezones": ["Asia/Riyadh"], "phone_lengths": [9, 9],
     "default": false, "featured": true, "curriculum": true}
  ]
}
```

- Order: the featured countries first (in `featured` order), then the rest by name in `lang` (default `ar`).
- `timezone` = the zone most people of the country live in, `timezones` = every IANA zone of the country (first =
  `timezone`), empty for a few territories.
- `phone_lengths` = [min, max] digits after the dial code, only where the length is fixed; absent = any E.164 length.
- `curriculum` = the country has a grade / subject catalog (`GET /edu/catalog?country=` answers).
- `Cache-Control: public, max-age=3600` (no-store under the encryption envelope).

### `GET /api/v1/edu/countries` (existing: the curriculum countries)

Each item gains `default` (bool, the platform default) and `timezone`.

## 3. Curriculum, grades, subjects (per country, served from data)

`GET /api/v1/edu/catalog?country=SA` (existing). Changes:
- `country` may be left out: the platform default country (was a hard-coded `EG`).
- every subject gains `exam_prep` (bool). Saudi Arabia's catalog has three exam-prep subjects, `qudurat` (القدرات
  العامة), `tahsili` (التحصيلي) and `step` (اختبار STEP), linked to the secondary grades. They exist only in the SA
  catalog, so they are shown only for the Saudi curriculum, wherever the user lives.
- Saudi secondary grades 2 and 3 carry `tracks`: `general` المسار العام, `cs_eng` علوم الحاسب والهندسة,
  `health_life` الصحة والحياة, `business` إدارة الأعمال, `sharia` المسار الشرعي. Grade 1 is the common year (no track).
- Saudi grades run الصف الأول الابتدائي … الصف الثالث الثانوي (plus KG and university, as before); Egypt's grades are
  unchanged.
- Existing databases get the new tracks and subjects from the seed file (a grade's `tracks` is filled only while it is
  empty; a subject added by the seed is linked to the grades the file lists).

## 4. The user

| Field | Where | Meaning |
|---|---|---|
| `country_code` | `users.country_code` | country of RESIDENCE, ISO-3166 alpha-2 (any of the world list) or null |
| `timezone` | `users.timezone` | IANA zone chosen on the profile, or null (= the device zone) |
| `curriculum_country_code` | `student_study_profiles.country_code` | the curriculum a STUDENT follows (any country with a catalog), independent of residence |

The old free-text `country` stays as it was (never parsed).

- Login / Google / refresh answers: `user` gains `country_code`, `timezone`.
- `GET /api/v1/auth/me` gains `country_code`, `timezone`, `curriculum_country_code` (students; null for others),
  `effective_timezone` (profile zone → residence's primary zone → platform zone; for display only).
- `POST /api/v1/auth/register` takes:
  - `country_code?` — residence. 422 `country_invalid`.
  - `timezone?` — IANA. 422 `timezone_invalid`.
  - `curriculum_country_code?` — students; used as `study_profile.country_code` when that is absent. 422
    `edu_country_unknown` (no catalog).
  - `phone_country?` — ISO-2 of a phone typed without `+` / `00` (default: `country_code`).
  The answer gains `country_code`, `timezone`.
- `PUT /api/v1/auth/me` takes `country_code`, `timezone` (each: sent = set; null or "" = clear; absent = keep) and
  `phone_country?`. The answer (`UserDetailResponse`) carries them.
- `PUT /api/v1/me/study-profile` takes `curriculum_country_code` as an alias of `country_code` (either; equal if both).
  `GET` returns both keys in `profile`.

Nothing in calendars or sessions changes: instants stay UTC and the app formats them in the viewer's zone (`AppTime`).

## 5. Phone numbers (E.164, any country)

- Stored E.164 (`+<dial><number>`), as before.
- A number typed with `+` or `00` is taken as international, whatever the user's country.
- A local number (no `+` / `00`) gets the dial code of `phone_country`, else the account's / body's `country_code`,
  else the server's `OTP_DEFAULT_COUNTRY_CODE`; one leading trunk `0` is dropped (0501234567 + SA → +966501234567).
- The length is checked against the number's country when the world list knows it (`phone_lengths`), else the
  E.164 rule (8 to 15 digits). 400 `INVALID_PHONE` with a neutral message ("include the country code").
- OTP by SMS / WhatsApp, the WhatsApp / Telegram phone link and the study profile's parent phone accept every
  country (no country-specific pattern anywhere in these paths).
- Sign-in by phone: send the number in E.164 (the picker builds it); a local number still uses
  `OTP_DEFAULT_COUNTRY_CODE` there.

## Errors

| HTTP | code | when |
|---|---|---|
| 422 | `country_invalid` | `country_code` / `phone_country` not in the world list |
| 422 | `timezone_invalid` | not an IANA zone |
| 422 | `edu_country_unknown` | `curriculum_country_code` without an active catalog |
| 400 | `INVALID_PHONE` | not a valid number for its country |

Each carries `message` (Arabic) and `message_en`.
