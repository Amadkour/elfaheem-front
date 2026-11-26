# Two products, one design (D-1810)

The redesign is shared code. What differs between the two products is **data**: the theme the server sends
(`GET /api/v1/theme/{platform}`), the theme defaults in the app, and the platform settings (country, currency, payment
gateway, time zone). Widgets read roles from `context.colors` and the area tokens; they never name a product.

## NextBrain palette (from the logo)

Sampled from `assets/images/logo.png` (2026-11-26): the snake and infinity are green `#186848`, the inner arc is gold
`#C08838`. The phase 1 kit derives the full scale from these two seeds and checks contrast (AA for text ≥ 14 px bold
on white and on the tint). Mapping onto the design's roles (DESIGN_SYSTEM.md §1.4):

| Design role (reference value) | NextBrain | Notes |
|---|---|---|
| `--k-navy` text / dark hero base (`ref`) | deep green, derived from `#186848` (about `#0F3F2C`) | text on light, hero base |
| `--k-deep` hero end stop (`ref`) | darkest green (about `#08261A`) | player / exam chrome |
| `--k-blue` primary action (`ref`) | logo green `#186848` (tint and ink derived) | links, primary |
| `--k-cyan` gradient partner (`ref`) | a lighter, fresher green (about `#2FA36B`) | gradients, focus ring |
| `--k-apricot` warm highlight (`ref`) | logo gold `#C08838` | next step, warm highlight |
| `--k-coral` hot end stop (`ref`) | deeper gold / amber (about `#A8691F`) | `.hot` = gold → deep gold |
| page `ref` | a green-tinted off-white (about `#F4F8F5`) | 60 % neutral |

The values marked "about" are starting points; the kit agent fixes the exact hex with a contrast check and writes
them in `lib/design/` defaults AND the backend theme seed. Grades of green and gold only for brand roles.

Shared in both products (functional colours, not brand): the six student area accents (sun, mint, grape, pink, lime,
sky), the subject colours, and the status colours (live coral, success mint, warning sun, locked, error). Where an
area accent clashes with NextBrain's green (mint, lime), the kit may shift it, recording the choice here.

## Downstream product palette

The reference design's own values (DESIGN_SYSTEM.md §1.4). They live only in the downstream repository's theme
defaults and server seed, applied by its sync identity step. Never written here.

## Market data

| | NextBrain default | Downstream default |
|---|---|---|
| Country | Egypt | Saudi Arabia |
| Time zone | Africa/Cairo | Asia/Riyadh |
| Currency | EGP | SAR |
| Gateway | Paymob | Moyasar |

Both accept users from any country (RULES.md §3). Saudi-only items (مدى, STC Pay, قدرات / تحصيلي, ١٥٪ VAT) show
when the country is Saudi Arabia, in either product.

## Copy

The approved Arabic copy is used as written in both products. Owner question (open, REPORT.md): should NextBrain get
an Egyptian-dialect variant? Until answered, the approved copy stands, and dialect-heavy strings are listed in
`docs/redesign/strings/dialect.md` so a variant can be added later without hunting.
