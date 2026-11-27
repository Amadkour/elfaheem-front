# API: a parent's view of a child's payments and invoices (WP13)

Backend branch `rd/be-wp13`. No migration (the existing `payments` rows; the invoice number is derived from the
payment id). Kill switch `parent.payments` (403 `feature_disabled`). Test `tests/redesign/e2e_parent_payments.py`.
Read only: nothing here moves money. Send `Accept-Language: ar|en` for the course name and the line labels (default
Arabic).

## 1. Who may read

- The caller must be a parent: 403 `ROLE_PARENT_ONLY` otherwise (the student himself, a teacher, an admin).
- The child must be linked to THIS parent with an active link: 403 `child_not_linked` otherwise. A child id that does
  not exist gets the same answer, so nothing leaks.
- A payment id that belongs to another student answers 404 `payment_not_found`, even under the parent's own child.
- No gateway data is ever returned (no `meta_data`, no `transaction_id`).

Errors are `{detail: {code, message, message_en}}`.

## 2. The child's payments

### `GET /api/v1/parent/children/{student_id}/payments?skip=0&limit=20&status=`

`limit` 1..100. `status` = `pending` | `completed` | `failed` | `refunded` (422 `status_invalid`). Newest first.

```json
{
  "child": {"id": 41, "name": "Omar"},
  "items": [
    {"id": 812, "course_id": 9, "course_name": "رياضيات", "amount": 150.0, "currency": "EGP", "status": "completed",
     "method": "card", "paid_at": "2026-11-24T10:02:11", "refunded_at": null, "created_at": "2026-11-24T10:01:40",
     "has_invoice": true, "invoice_number": "INV-2026-000812"}
  ],
  "total": 4
}
```

- `has_invoice` is true for `completed` and `refunded` payments; `invoice_number` is null otherwise.
- Times are naive UTC (format with `AppTime`). Show amounts with the payment's `currency`, never the device's.

## 3. One payment's invoice

### `GET /api/v1/parent/children/{student_id}/payments/{payment_id}/invoice`

```json
{
  "invoice_number": "INV-2026-000812",
  "payment_id": 812,
  "status": "completed",
  "issued_at": "2026-11-24T10:02:11",
  "refunded_at": null,
  "currency": "EGP",
  "seller": {"country": "EG", "tax_number": null},
  "student": {"id": 41, "name": "Omar"},
  "billed_to": {"id": 17, "name": "Mona"},
  "course": {"id": 9, "name": "رياضيات"},
  "method": "card",
  "items": [
    {"key": "course", "label": "رياضيات", "plan": "yearly", "amount": 150.0},
    {"key": "discount", "label": "خصم القسيمة", "amount": -15.0},
    {"key": "platform_fee", "label": "رسوم الخدمة", "amount": 10.0},
    {"key": "gateway_fee", "label": "رسوم الدفع", "amount": 3.6}
  ],
  "subtotal": 148.6,
  "vat": [{"label": "ضريبة القيمة المضافة 14٪", "percent": 14.0, "amount": 1.4}],
  "total": 150.0,
  "total_label": "150 ج.م"
}
```

- The invoice is what the payment stored at checkout: a later price, fee or VAT change never rewrites it.
- `items[].key`: `course` (the course at the plan price before a coupon) · `discount` (a reward coupon, negative) ·
  `platform_fee` · `gateway_fee` · `adjustment` (rare: rounding or a fee rule the snapshot does not spell out). An old
  payment without a fee snapshot has one `course` line at the amount paid. `plan` may be null.
- `subtotal` = the items' sum = `total` − the VAT. `total` is what was charged.
- `vat` is EMPTY when no VAT was charged on that payment (the seller country's VAT rule and the admin's VAT setting
  decided it at checkout; no country is hard-coded). Show the VAT line only when the list has an entry. `percent`
  may be null (then show the label and amount only).
- `seller.tax_number` is set only when the super admin entered one (Admin → Payment markets → VAT rules); otherwise
  null and the app shows no tax-number row.
- `status: "refunded"` → show a "Refunded" mark on the invoice; `refunded_at` carries the time.
- 409 `invoice_not_ready` for a `pending` or `failed` payment.

### `GET /api/v1/parent/children/{student_id}/payments/{payment_id}/invoice/pdf`

The same invoice as `application/pdf` (`Content-Disposition: attachment; filename="invoice-<id>.pdf"`, `no-store`),
Arabic or English by `Accept-Language`, made by the server's Export Studio PDF writer. Same errors as above, plus
503 `invoice_pdf_failed`. Open it with the app's file viewer or share sheet.

## 4. Super admin: the tax number

`GET|PUT /api/v1/admin/payments/vat-rules` (existing, `api/payments.md` §4) gain `tax_number` (string or null).
`PUT` body `{"tax_number": "300123456700003"}`: ≤ 40 printable characters, `""` clears it, absent keeps it
(422 `vat_rule_invalid`).

## 5. The public share card gains a price

`GET /api/v1/public/share/{kind}/{ref}` — for a PUBLIC course card (`course`, `roadmap`, and `material` / `session`
of a public course) the answer gains:

| Field | Example |
|---|---|
| `currency` | `"EGP"` |
| `price_label` | `"150 ج.م"`, `"135 $"`, `"مجاني"` (Arabic) |
| `price_label_en` | `"EGP 150"`, `"$135"`, `"Free"` |

The price is the teacher's default plan after the active discount, written exactly like the app's `coursePriceLabel`.
A card with `public: false` carries none of them. `outcomes` is NOT sent: a course has no outcomes / what-you-learn
data yet (the app shows the description instead).

## 6. Features guide

`data/app_features_guide.json` gains `parent_child_payments` (parent, switch `parent.payments`); the notebook entry
(`student_notebook`, switch `course.notebook`) already existed.
