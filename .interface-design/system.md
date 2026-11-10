# NextBrain — "Warm Editorial Blocks" design system (D-610 – D-629)

The locked decisions for the editorial theme overhaul (2026-11-10). Every agent reads this before touching UI and
holds to it. Code is the source of truth for the token VALUES (`lib/design/app_tokens.dart`,
`lib/config/theme/`); this file is the source of truth for the INTENT. When the two disagree, fix the code or
raise it, never drift silently.

## 1. Direction and feel

A premium learning companion: calm paper-warm reading surfaces, confident editorial headlines, and colour used in
*blocks* (whole tinted containers that group a subject) instead of sprinkled accents. One memorable thing per screen
(usually the hero block or a key number); everything around it quiet. Arabic (RTL) first, English equal.

It must NOT read as the generic AI kit: no identical rounded cards with one grey shadow, no ALL-CAPS eyebrow above
every heading, no gradient washes as decoration, no fade-up on every section, no "→" in button text, no emoji as
icons.

## 2. Colour (built-in preset `warm_editorial`, the platform default)

The palette is server-driven (super admin → Theme). The preset below is the new built-in default; widgets read roles
from `context.colors`, never hex values, so other presets keep working.

| Role | Light | Dark | Notes |
|---|---|---|---|
| canvas `background` | `#FBF7F0` warm white | `#15120E` | Scaffold; reduces glare for long reading |
| paper `surface_card` / `card_bg` | `#FFFDF9` | `#241F19` | data cards, lists, forms |
| `dark_surface` | — | `#1C1813` | |
| input `input_bg` | `#F5EFE5` | `#2C261F` | |
| `divider` | `#ECE4D8` | `#3A3229` | warm hairlines |
| ink `text_dark` | `#211D18` deep charcoal (15.4:1 on canvas) | `#F5EFE6` | |
| `text_medium` | `#4D463E` | `#CBBFAE` | |
| `text_light` (captions) | `#6E655A` (≥ 4.5:1 on canvas, peach, sky) | `#A99C8A` | |
| primary (CTA, selection) | `#0B6B4F` deep emerald (white ink 6.5:1) | same family, lifted where needed for AA | `primary_dark #064733` · `primary_light #3E9C78` |
| `success` (completion, correct answer) | `#12805C` | | emerald = "done / right" |
| `accent2` gold (streaks, achievements, top marks) | `#94691A` text-safe | | gold fills use its tint `#F6E7C4` |
| block peach `accent1` | `#FBE2D3` | dark: tinted `#3A2A22` | learning / progress blocks |
| block sky `accent3` (new optional key) | `#DCE7F5` | dark: `#1F2A38` | schedule / information blocks |
| `warning` | `#B7791F` | | |
| `danger` | `#B42E3A` | | |

Rules: emerald and gold are reserved — emerald for the primary action and for success / completion / correct; gold
only for streaks, achievements, top scores. Never use them as decoration. Peach and sky are surfaces, never text.
Every text role keeps ≥ 4.5:1 on every surface it sits on (large display text ≥ 3:1).

## 3. Type

| Role | Face | Size / weight |
|---|---|---|
| `display` | **Markazi Text** (editorial Naskh-inspired serif, Arabic + Latin, OFL) | 32 · 600 |
| `headline` | Markazi Text | 24 · 600 |
| `pageTitle` | Markazi Text | 22 · 600 |
| `section` | Markazi Text | 18 · 600 |

The four editorial sizes are OPTICAL (what the heading reads like beside the UI sans). Markazi's letters are small on
their body (cap height 0.48 em against Inter's 0.73, the Arabic alef 0.53 em against Plex's 0.74), so the face is drawn
at 1.3 × the size in Latin and 1.25 × in Arabic (`AppFonts.editorialScale`; D-611, judged on the home renders).
"Same as text" uses the text font at 28 · 22 · 20 · 16.
| `body`, `row`, `label`, `meta`, `overline` | the person's chosen UI sans (D-072; defaults IBM Plex Sans Arabic / Inter) | unchanged scale |
| `figure`, `figureLarge` | UI sans, tabular digits | unchanged |

`AppFonts.editorial` is the display family; a Display & reading setting "Headings: Editorial / Same as text"
(default Editorial) lets a person turn it off. Never all caps; sentence case everywhere; no single highlighted word in
a headline.

## 4. Space, shape, depth

- **Grid:** 8 pt with a 4 pt half-step (`AppSpace` xxs 4 · xs 8 · sm 12 · md 16 · lg 24 · xl 32 · xxl 48 ·
  new `xxxl` 64). 4 and 12 only inside dense rows / between an icon and its label.
- **Editorial rhythm (asymmetric):** a section heading has more space above it (`xl` 32) than below (`sm` 12); hero
  blocks pad `lg` 24 on the sides, `xl` 32 on top, `lg` 24 at the bottom; list rows `md` 16 vertical rhythm.
- **Radii by hierarchy, never one radius on everything:** chip/pill 10 (full pill for status) · input & button 14 ·
  card 16 · **block 24** (new `AppRadius.block`) · sheet 28 · hero 32.
- **Buttons:** height 48 (`AppTouch.min`), primary 56 on phone hero actions; horizontal padding `lg` 24; label
  `label` role at 15 · 600; icon 20.
- **Depth:** tone first — canvas → paper card → tinted block, separated by warm hairlines (`AppBorder.hairline`).
  Shadows only on things that float (sheets, dialogs, the FAB, a lifted/tilted hero, a dragged item); one soft warm
  shadow tone (`card_shadow_color` = charcoal), never the same grey shadow under every card.

## 5. Blocks

`AppBlock(tone: AppBlockTone.peach | sky | gold | emerald | paper, child:)` — a full-width tinted container (radius
`block`, padding per §4) that groups one subject: today's lesson, your streak, the next session, a category. A screen
uses at most two or three tones; a category keeps its tone everywhere (`AppBlockTone.forKey(key)` is stable).
Category / subject indicators are vector icons (Material rounded / `CupertinoIcons` / a small `CustomPainter`
glyph), never emoji.

## 6. Motion (D-580 kit + D-61x extensions)

- One orchestrated entrance per screen (the hero block and first items), not fade-up on every section.
- Numbers: `AppCountUp`; progress: `AppFill`; charts: `AppDrawIn`; press: `AppPressScale`.
- 3D (extends D-583): `AppTilt` on hero blocks, featured course / image cards and the key KPI; `AppFlip3D` for quiz
  answer reveal and flashcards; `AppParallaxImage` for course covers in lists (shift ≤ 8 px). At rest the transform
  is the identity; touch gets press depth, not a tilt.
- Sheets / expanding cards / feedback panels: rapid ease-out (`AppMotion.curve`, 220–300 ms) or a critically damped
  spring for drag-release; always interruptible (drive from the current value, never restart from 0).
- Everything parks under Reduce motion and the super admin's `app.animations` switch.

## 7. Quality floor (checked before merge)

48 × 48 targets; visible focus ring (`AppBorder.focus`); `expectNoLayoutErrors` at 320 × 640 and 1400 × 900, ar/en,
text × 1.3; no raw numbers for space / radius / font size / colour in screens; `const` wherever possible; badge and
chip labels flex (`Flexible` / `FittedBox` / ellipsis) instead of clipping.
