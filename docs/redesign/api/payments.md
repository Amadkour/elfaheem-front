# API: payments, VAT, converted amounts, teacher documents, payouts (BACKEND.md §5, RULES.md §2-§3; backend WP8)

Backend branch `rd/be-money`, migrations `0160` (currency rates) and `0161` (document types). Every new request
field is optional and every existing answer keeps its keys: an older app is unchanged.

Market defaults are data (BRANDS.md): nothing below names a product, a country or a gateway in code. NextBrain runs
with nothing set (seller Egypt, gateway Paymob, EGP); the downstream product sets its seller country to SA and its
gateway to Moyasar (SAR) through the same settings.

## 0. Whose country

| Name | Resolved from |
|---|---|
| payer country | `?country=` → the signed-in user's `country_code` (residence, `api/international.md`) → the platform default country |
| seller country | `app_settings` `platform.seller_country` → `platform.default_country` → env `PLATFORM_DEFAULT_COUNTRY` → `EG` |
| charge currency | the active gateway's currency (the course's gateway when `course_id` is sent); never the payer's |

## 1. Payment methods for this payer

### `GET /api/v1/payments/methods?course_id=&country=&amount=&lang=ar|en`

Sign-in optional (the same answer for a visitor, minus the user's country). `amount` (in the charge currency) asks
for the "≈" converted amount.

```json
{
  "provider": "moyasar",
  "charge_currency": "SAR",
  "payer_country": "SA",
  "seller_country": "SA",
  "methods": [
    {"key": "mada", "kind": "card", "flow": "card", "label": "مدى", "brands": ["mada"]},
    {"key": "card", "kind": "card", "flow": "card", "label": "بطاقة ائتمان", "brands": ["visa", "mastercard"]},
    {"key": "apple_pay", "kind": "wallet", "flow": "wallet", "label": "Apple Pay", "brands": []},
    {"key": "stc_pay", "kind": "wallet", "flow": "wallet", "label": "STC Pay", "brands": []},
    {"key": "bank_transfer", "kind": "manual", "flow": "manual", "label": "تحويل بنكي", "brands": []}
  ],
  "bnpl": [{"key": "tabby", "label": "تابي"}],
  "vat": {"applies": true, "percent": 15.0, "included": false, "label": "ضريبة القيمة المضافة ١٥٪"},
  "display": {"currency": "EGP", "rate": 13.2, "amount": 100.0, "approx_amount": 1320.0, "as_of": "2026-11-20T09:00:00",
              "note": "يُخصم المبلغ بالريال السعودي، والقيمة بالجنيه تقريبية."},
  "charge_note": "يُخصم المبلغ بالريال السعودي (SAR)."
}
```

- `methods` lists only what this payer can use now, in display order. A method is listed when ALL hold:
  the catalogue entry is on, the payer's country is in its `countries` (empty = every country), the active gateway
  is in its `providers`, the gateway really supports it (wallets: the provider's configured wallets), and the
  existing admin switch (Admin → Payment methods) is on. Defaults:
  - `mada`, `stc_pay`: payer in SA and gateway Moyasar. `stc_pay` also needs the admin flag
    (catalogue `stc_pay.enabled`, default off: the current Moyasar integration has no STC Pay flow yet).
  - `card` (Visa / Mastercard), `apple_pay`, `google_pay`: every country, every gateway that supports them.
  - `bank_transfer`: every country (the existing manual flow). `instapay`: payer in EG and charge currency EGP.
  - Egypt mobile wallets / Fawry / kiosk: not listed. The current Paymob integration carries only card and
    Apple / Google Pay integration ids, so no such flow exists to send the payer to.
- `flow` tells the app which existing checkout to open: `card` → `POST /payments/create-web-session` (or the SDK
  route the app uses today), `wallet` → `POST /payments/create-wallet-session` (`apple_pay` / `google_pay`),
  `manual` → the transfer-proof flow. Nothing about checkout changes.
- `bnpl` (Tabby / Tamara) is a display flag only: listed when the admin turned it on and the payer is in one of its
  countries (default SA). There is no Tabby / Tamara checkout; the app shows it as "قريباً" or not at all.
- `vat`: see §2. `applies: false` → the app shows no VAT line (and `percent` / `label` are null).
- `display` is present only when `amount` was sent, the payer's local currency differs from `charge_currency`, a
  rate exists in the admin's rates table and it is fresher than `max_age_days` (default 30); otherwise `null`. The
  app shows it as "≈ 1,320 ج.م" next to the real amount and always shows `charge_note`. No live FX call is ever made.
- Kill switches: `payments.approx_amount` off → `display` is always null; `payments.bnpl` off → `bnpl` is `[]`.

### `GET /api/v1/payments/fees/preview` (existing)

Gains `vat_applies` (bool). The VAT amount in the breakdown already follows §2, so with `vat_applies: false` the VAT
line is 0 and the app hides it.

## 2. VAT rule per seller country

Rules are data (`app_settings` `platform.vat_rules`), defaults:

```json
{"SA": {"percent": 15, "scope": "domestic"}, "EG": {"percent": null, "scope": "all"}}
```

- `percent: null` = the existing student VAT setting (Admin → Fees, incl. an organization's override) is used as
  today. A number is the seller's default; a student VAT the admin set explicitly in Admin → Fees (platform or
  organization) still wins.
- `scope: "domestic"` = VAT applies only when the payer's country equals the seller's; `"all"` = every payer.
- A seller country without a rule behaves exactly as today (`percent: null`, `scope: "all"`).
- `applies` = in scope AND the effective percent > 0. When it does not apply, the checkout charges no student VAT
  (the payment's fee snapshot shows VAT 0); teacher VAT is unchanged.
- A payer with no known country counts as domestic.

## 3. Converted amounts (rates table)

Super admin, `GET /api/v1/admin/payments/currency-rates` → `{"rates": [{"base": "SAR", "quote": "EGP", "rate": 13.2,
"updated_at": "…"}], "max_age_days": 30}`.

`PUT /api/v1/admin/payments/currency-rates` body `{"rates": [{"base": "SAR", "quote": "EGP", "rate": 13.2}],
"max_age_days": 30}`: upserts the sent pairs (`rate: null` deletes a pair). 422 `rate_invalid` (codes not ISO-4217
letters, base = quote, rate ≤ 0). A reverse pair is used inverted when the direct pair is missing.

The payer's local currency comes from the country's curriculum row (`edu_countries.currency`), else a built-in
country → currency table.

## 4. Admin: catalogue and VAT rules

- `GET /api/v1/admin/payments/catalog` → `{"methods": [{"key", "kind", "flow", "label_ar", "label_en", "countries",
  "providers", "enabled", "brands"}], "bnpl": [{"key", "label_ar", "label_en", "countries", "enabled"}]}` (built-in
  defaults merged with the stored overrides).
- `PUT /api/v1/admin/payments/catalog` body `{"methods": {"stc_pay": {"enabled": true, "countries": ["SA"]}},
  "bnpl": {"tabby": {"enabled": true}}}`: only `enabled` and `countries` can change. 422 `catalog_invalid`.
- `GET /api/v1/admin/payments/vat-rules` → `{"seller_country": "EG", "rules": {...}}`;
  `PUT` body `{"seller_country"?: "SA", "rules"?: {"SA": {"percent": 15, "scope": "domestic"}}}` (the rules sent
  replace the stored ones). 422 `vat_rule_invalid`.
- All super admin; kill switch `admin.payment_markets` hides the page.

## 5. Teacher identity documents (any country)

Document types (`required_document_types`) gain:

| Field | Meaning |
|---|---|
| `key` | stable seed key or null (`id_passport`, `id_national_id`, `id_iqama`) |
| `group_key` | types sharing a group are "any one of": uploading one fulfils the group (`identity`) |
| `country_codes` | list of ISO-2 residence countries the type is offered to; empty / null = every country |

Seed: passport (every country), national ID (every country), iqama (SA), all in group `identity`, required. A fresh
database gets them active; a database that already has document types gets them inactive, so the admin's list is not
changed behind their back (switch them on in Admin → Required documents).

- `GET /api/v1/teacher-documents/required-types` and `/overview`: each item gains `key`, `group_key`,
  `country_codes`; types whose `country_codes` do not contain the teacher's residence country are left out (no
  country → the platform default country). `all_required_fulfilled` and the finalize check count a group as one
  requirement that any member fulfils; finalize's missing list names a group once.
- The overview gains `groups: [{"key": "identity", "fulfilled": true, "type_ids": [4, 5, 6]}]`.
- Admin create / update of a type accept `group_key` and `country_codes` (422 `country_invalid`).
- The app wording stays neutral: "جواز السفر أو الهوية الوطنية أو الإقامة", never a Saudi-only ID.

## 6. Payout details (any country)

### IBAN rules (shared by payouts and saved bank accounts)

- Spaces are dropped, letters upper-cased. Valid = 2-letter country + 2 check digits + BBAN, the length the country's
  IBAN format fixes (every IBAN country), and the ISO 7064 mod-97 checksum = 1.
- `POST /api/v1/payments/iban/check` (signed in) body `{"iban": "SA03 8000 …"}` →
  `{"valid": true, "iban": "SA0380000000608010167519", "country_code": "SA", "formatted": "SA03 8000 0000 …",
  "code": null}`; when invalid `valid: false` and `code` = `iban_format` | `iban_country` | `iban_length` |
  `iban_checksum`. Never stored, never logged.

### `GET /api/v1/teacher/payout/methods?country=` (teacher)

The payout methods this teacher may use (the existing allowed list) with the fields to ask for, per residence
country (`country` → the teacher's `country_code` → the platform default):

```json
{"country": "AE", "iban_country": true, "iban_length": 23,
 "methods": [{"id": "bank_account", "label_ar": "حساب بنكي (تحويل يدوي)", "label_en": "Bank account (manual)",
              "automatic": false, "currency": null, "configured": true,
              "fields": [{"key": "account_name", "required": true}, {"key": "bank_name", "required": true},
                         {"key": "iban", "required": true}, {"key": "swift_code", "required": false}]}]}
```

- A country without IBAN (e.g. US, EG accounts without one) gets `iban` optional and `account_number` +
  `swift_code` required.
- `moyasar` (automatic, SAR) is offered only to SA IBANs; `paymob` (automatic, EGP wallets / bank) only for EG; both
  only when configured (unchanged rules).

### Account details (`POST/PUT /api/v1/teacher/payout/accounts`, existing)

`bank_account` details gain `country_code` (ISO-2, optional; default = the IBAN's country, else the teacher's
country). Rules:
- with `iban`: the IBAN rules above, and the IBAN's country must equal `country_code` when both are sent;
- without `iban`: `account_number` and `swift_code` (BIC, 8 or 11 characters) are required;
- `swift_code` when sent must be a valid BIC.
- `moyasar`: SA IBAN with a valid checksum.

Errors (HTTP 400, `detail = {code, message, message_en}`): `iban_format`, `iban_country`, `iban_length`,
`iban_checksum`, `iban_country_mismatch`, `swift_required`, `swift_invalid`, `country_invalid`.

`POST /api/v1/payment-methods/bank-account` (saved accounts) now rejects an IBAN with a bad checksum (422).

## 7. Feature keys

`payments.approx_amount`, `payments.bnpl`, `admin.payment_markets` (new, `features/platform/feature_catalog.py`).
