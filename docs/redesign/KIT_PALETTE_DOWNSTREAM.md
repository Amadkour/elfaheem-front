# Kit palette: this product's brand values

The kit is built upstream as role-based tokens (upstream `docs/redesign/KIT_SPEC.md`). Upstream holds no colour value of this product (D-1810); they live here. `tool/redesign/kit_palette_ref.json` is the same data, for the upstream script's `--ref` option. The identity step writes these into `lib/config/theme/kit_palette_defaults.dart`, `lib/config/theme/app_theme.dart` and the backend's `theme_kit_defaults.py` / `theme_presets.py`. The shared functional colours (six accents, subjects, status) come from upstream unchanged, mint included at its design value `#19C29B` (upstream moves its own mint; this product does not). Platform setting `digits` = `arabic_indic` in this product's seed.

## Brand roles (`kit.brand.*`)

| Role | Value |
|---|---|
| `ink` | `#00205E` |
| `deep` | `#001440` |
| `primary` | `#1979C1` |
| `primary_tint` | `#E2EFFA` |
| `primary_ink` | `#135F9A` |
| `partner` | `#07B8EE` |
| `partner_tint` | `#DDF6FE` |
| `partner_ink` | `#06678A` |
| `warm` | `#FF9F5A` |
| `warm_tint` | `#FFE8D6` |
| `warm_ink` | `#A3480A` |
| `hot` | `#F2545B` |
| `hot_tint` | `#FFE3E0` |
| `hot_ink` | `#B23A2E` |
| `page` | `#F3F8FD` |
| `text` | `#0E2350` |
| `muted` | `#4A5878` |
| `line` | `#E2EAF4` |
| `well` | `#F8FBFE` |
| `track` | `#EAF0F6` |
| `field_edge` | `#D5E3F2` |
| `top_bar` | `#001A4E` |
| `hot_a` | `#FF9F5A` |
| `hot_b` | `#F2545B` |
| `hot_fg` | `#FFFFFF` |
| `warm_on_dark` | `#FF9F5A` |

Dark-mode tints and inks (`*_tint_dark`, `*_ink_dark`) are derived by the upstream rule: tint = the colour at 18 % over the dark card, ink = the colour lightened to 4.6:1 on it.

## Areas (`kit.areas.*`), hero end stop = `deep`

| | `a` | `b` | `hero_a` | `hero_mid` | `tint` | `ink` | `btn_a` | `btn_b` | `btn_fg` |
|---|---|---|---|---|---|---|---|---|---|
| home | `#1979C1` | `#07B8EE` | `#1979C1` | `#093F81` | `#E2EFFA` | `#135F9A` | `#1979C1` | `#07B8EE` | `#FFFFFF` |
| learn | `#FF9F5A` | `#F2545B` | `#FF8A4C` | `#7A2E5E` | `#FFE8D6` | `#A3480A` | `#FF8A4C` | `#F2545B` | `#FFFFFF` |
| exam | `#7A4DF0` | `#1979C1` | `#7A4DF0` | `#2B3091` | `#ECE5FF` | `#4A28B8` | `#7A4DF0` | `#1979C1` | `#FFFFFF` |
| games | `#7A4DF0` | `#FF5FA2` | `#8E4DF0` | `#3A1F8F` | `#ECE5FF` | `#4A28B8` | `#7A4DF0` | `#E8478C` | `#FFFFFF` |
| store | `#FFC53D` | `#FF9F5A` | `#FF9F5A` | `#8C2F5A` | `#FFF4CC` | `#7A5200` | `#FFC53D` | `#FF9F5A` | `#00205E` |
| quran | `#19C29B` | `#0F6E6D` | `#19C29B` | `#0A5C6E` | `#D9F7EE` | `#0C6B55` | `#0F8F78` | `#0F6E6D` | `#FFFFFF` |
| nahw | `#9BD728` | `#19C29B` | `#8BCB1E` | `#1F6B55` | `#EEF9D2` | `#4C6B05` | `#9BD728` | `#19C29B` | `#00205E` |
| sched | `#3DA5FF` | `#07B8EE` | `#3DA5FF` | `#154F96` | `#E0F0FF` | `#0F5CA8` | `#2A8EF0` | `#07B8EE` | `#FFFFFF` |
| chat | `#FF5FA2` | `#FF9F5A` | `#FF5FA2` | `#6A2E7E` | `#FFE3EF` | `#A81E5E` | `#E8478C` | `#FF7A59` | `#FFFFFF` |
| money | `#FFC53D` | `#19C29B` | `#FFB020` | `#A0442A` | `#FFF4CC` | `#7A5200` | `#FFC53D` | `#19C29B` | `#00205E` |
| me | `#1979C1` | `#7A4DF0` | `#4F6BE8` | `#2E2A8C` | `#E2EFFA` | `#135F9A` | `#1979C1` | `#7A4DF0` | `#FFFFFF` |

## Role accents (`kit.roles.*`)

| Role | `a` | `b` |
|---|---|---|
| teacher | `#5F3DC4` | `#8B6CF0` |
| parent | `#0B8FB8` | `#2FB5A8` |
| admin | `#1979C1` | `#E89B00` |
| super | `#B7791F` | `#F6C453` |

Hero stops, tint, ink and button stops of the four roles are derived by the upstream rule.

## Contrast (WCAG 2.1; floor 4.5)

| Pair | fg | bg | ratio | |
|---|---|---|---|---|
| text on page | `#0E2350` | `#F3F8FD` | 14.30 | ok |
| text on white | `#0E2350` | `#FFFFFF` | 15.27 | ok |
| muted on page | `#4A5878` | `#F3F8FD` | 6.64 | ok |
| muted on white | `#4A5878` | `#FFFFFF` | 7.10 | ok |
| muted on well | `#4A5878` | `#F8FBFE` | 6.84 | ok |
| white on primary | `#FFFFFF` | `#1979C1` | 4.62 | ok |
| white on partner | `#FFFFFF` | `#07B8EE` | 2.31 | UNDER |
| white on ink | `#FFFFFF` | `#00205E` | 15.35 | ok |
| white on deep | `#FFFFFF` | `#001440` | 17.89 | ok |
| white on top_bar | `#FFFFFF` | `#001A4E` | 16.70 | ok |
| hot_fg on hot_a | `#FFFFFF` | `#FF9F5A` | 2.03 | UNDER |
| hot_fg on hot_b | `#FFFFFF` | `#F2545B` | 3.39 | UNDER |
| warm_on_dark on ink | `#FF9F5A` | `#00205E` | 7.57 | ok |
| primary_ink on white | `#135F9A` | `#FFFFFF` | 6.71 | ok |
| primary_ink on primary_tint | `#135F9A` | `#E2EFFA` | 5.74 | ok |
| partner_ink on white | `#06678A` | `#FFFFFF` | 6.34 | ok |
| partner_ink on partner_tint | `#06678A` | `#DDF6FE` | 5.64 | ok |
| warm_ink on white | `#A3480A` | `#FFFFFF` | 6.02 | ok |
| warm_ink on warm_tint | `#A3480A` | `#FFE8D6` | 5.09 | ok |
| hot_ink on white | `#B23A2E` | `#FFFFFF` | 5.94 | ok |
| hot_ink on hot_tint | `#B23A2E` | `#FFE3E0` | 4.89 | ok |
| area home: white on hero_mid | `#FFFFFF` | `#093F81` | 10.30 | ok |
| area home: btn_fg on btn_a | `#FFFFFF` | `#1979C1` | 4.62 | ok |
| area home: btn_fg on btn_b | `#FFFFFF` | `#07B8EE` | 2.31 | UNDER |
| area home: ink on tint | `#135F9A` | `#E2EFFA` | 5.74 | ok |
| area learn: white on hero_mid | `#FFFFFF` | `#7A2E5E` | 8.82 | ok |
| area learn: btn_fg on btn_a | `#FFFFFF` | `#FF8A4C` | 2.34 | UNDER |
| area learn: btn_fg on btn_b | `#FFFFFF` | `#F2545B` | 3.39 | UNDER |
| area learn: ink on tint | `#A3480A` | `#FFE8D6` | 5.09 | ok |
| area exam: white on hero_mid | `#FFFFFF` | `#2B3091` | 10.86 | ok |
| area exam: btn_fg on btn_a | `#FFFFFF` | `#7A4DF0` | 5.06 | ok |
| area exam: btn_fg on btn_b | `#FFFFFF` | `#1979C1` | 4.62 | ok |
| area exam: ink on tint | `#4A28B8` | `#ECE5FF` | 7.53 | ok |
| area games: white on hero_mid | `#FFFFFF` | `#3A1F8F` | 11.85 | ok |
| area games: btn_fg on btn_a | `#FFFFFF` | `#7A4DF0` | 5.06 | ok |
| area games: btn_fg on btn_b | `#FFFFFF` | `#E8478C` | 3.68 | UNDER |
| area games: ink on tint | `#4A28B8` | `#ECE5FF` | 7.53 | ok |
| area store: white on hero_mid | `#FFFFFF` | `#8C2F5A` | 7.87 | ok |
| area store: btn_fg on btn_a | `#00205E` | `#FFC53D` | 9.72 | ok |
| area store: btn_fg on btn_b | `#00205E` | `#FF9F5A` | 7.57 | ok |
| area store: ink on tint | `#7A5200` | `#FFF4CC` | 6.28 | ok |
| area quran: white on hero_mid | `#FFFFFF` | `#0A5C6E` | 7.58 | ok |
| area quran: btn_fg on btn_a | `#FFFFFF` | `#0F8F78` | 4.02 | UNDER |
| area quran: btn_fg on btn_b | `#FFFFFF` | `#0F6E6D` | 6.05 | ok |
| area quran: ink on tint | `#0C6B55` | `#D9F7EE` | 5.69 | ok |
| area nahw: white on hero_mid | `#FFFFFF` | `#1F6B55` | 6.38 | ok |
| area nahw: btn_fg on btn_a | `#00205E` | `#9BD728` | 8.88 | ok |
| area nahw: btn_fg on btn_b | `#00205E` | `#19C29B` | 6.75 | ok |
| area nahw: ink on tint | `#4C6B05` | `#EEF9D2` | 5.60 | ok |
| area sched: white on hero_mid | `#FFFFFF` | `#154F96` | 8.11 | ok |
| area sched: btn_fg on btn_a | `#FFFFFF` | `#2A8EF0` | 3.37 | UNDER |
| area sched: btn_fg on btn_b | `#FFFFFF` | `#07B8EE` | 2.31 | UNDER |
| area sched: ink on tint | `#0F5CA8` | `#E0F0FF` | 5.80 | ok |
| area chat: white on hero_mid | `#FFFFFF` | `#6A2E7E` | 9.11 | ok |
| area chat: btn_fg on btn_a | `#FFFFFF` | `#E8478C` | 3.68 | UNDER |
| area chat: btn_fg on btn_b | `#FFFFFF` | `#FF7A59` | 2.57 | UNDER |
| area chat: ink on tint | `#A81E5E` | `#FFE3EF` | 5.80 | ok |
| area money: white on hero_mid | `#FFFFFF` | `#A0442A` | 6.26 | ok |
| area money: btn_fg on btn_a | `#00205E` | `#FFC53D` | 9.72 | ok |
| area money: btn_fg on btn_b | `#00205E` | `#19C29B` | 6.75 | ok |
| area money: ink on tint | `#7A5200` | `#FFF4CC` | 6.28 | ok |
| area me: white on hero_mid | `#FFFFFF` | `#2E2A8C` | 11.50 | ok |
| area me: btn_fg on btn_a | `#FFFFFF` | `#1979C1` | 4.62 | ok |
| area me: btn_fg on btn_b | `#FFFFFF` | `#7A4DF0` | 5.06 | ok |
| area me: ink on tint | `#135F9A` | `#E2EFFA` | 5.74 | ok |

The table above is the reference as drawn: 12 of 65 pairs are under 4.5 there.

## What ships (2026-11-27, `sync/kit_palette_alfaheem.py`)

The identity step builds the palette from the values above with the upstream rules (`tool/redesign/kit_palette.py`: dark tints and inks, role sets, subjects, status) and fixes only the pairs that fail the upstream contrast checks (the front's and the backend's `theme_kit_unit.py` / `theme_contrast_unit.py`). The result passes all 175 upstream pairs (`py -3.12 sync/kit_palette_alfaheem.py --check`); `sync/check_identity.py` fails when it stops passing or when an upstream brand colour is left in the palette files. Changed for contrast ("reference" = the value above, or the upstream-derived one where the reference gives none):

| What | Reference | Ships | Why |
|---|---|---|---|
| brand primary | `#1979C1` | `#135F9A` | white 4.62:1, the theme layer needs 6.0:1: the reference blue ink |
| brand partner_tint | `#DDF6FE` | `#DFF5FC` | saturation 0.94 > 0.85 (the block surface clamp) |
| brand warm_tint | `#FFE8D6` | `#FCE8D9` | saturation 1.00 > 0.85 (the block surface clamp) |
| brand hot_tint | `#FFE3E0` | `#FDE5E2` | saturation 1.00 > 0.85 (the block surface clamp) |
| brand hot | `#F2545B` | `#CB474C` | white on hot under 4.5: darkened to 4.6 |
| brand hot_fg | `#FFFFFF` | `#001440` | white under 4.5 on hot_a / hot_b: the deep ink (P4) |
| area home btn_b | `#07B8EE` | `#057EA3` | white under 4.5: darkened to 4.6 (P10) |
| area learn btn_fg | `#FFFFFF` | `#00205E` | white under 4.5 on the warm stops: the dark ink, as upstream P4 |
| area games btn_b | `#E8478C` | `#CC3E7B` | white under 4.5: darkened to 4.6 (P10) |
| area quran btn_a | `#0F8F78` | `#0E846F` | white under 4.5: darkened to 4.6 (P10) |
| area sched btn_a | `#2A8EF0` | `#2377CA` | white under 4.5: darkened to 4.6 (P10) |
| area sched btn_b | `#07B8EE` | `#057EA3` | white under 4.5: darkened to 4.6 (P10) |
| area chat btn_a | `#E8478C` | `#CC3E7B` | white under 4.5: darkened to 4.6 (P10) |
| area chat btn_b | `#FF7A59` | `#B95841` | white under 4.5: darkened to 4.6 (P10) |
| brand warm_on_dark | `#FF9F5A` | `#FFC79F` | under 3.0 (large text) on the bright blue: lightened toward white |
| area home hero_a | `#1979C1` | `#135E97` | the apricot kicker under 4.5 on the start stop: started deeper |
| area me hero_a | `#4F6BE8` | `#3D52B3` | the apricot kicker under 4.5 on the start stop: started deeper |
| role admin hero_a | `#1979C1` | `#135E97` | the apricot kicker under 4.5 on the start stop: started deeper |

Notes:
- `primary` is the reference's blue ink `#135F9A` (6.71:1 under white; the reference also uses it as `primary_ink`): the shared theme layer derives the sidebar's radial fill, the count chips and the tab labels on a primary tint from `primary`, and with the bright `#1979C1` (4.62:1) those fell to 3.5 – 4.4:1 (test/ui a11y, brand_layer, app_shell). The bright blue stays the home area's colour, the `me` / `admin` accents and the hero tops.
- Tints above saturation 0.85 (`warm_tint`, `hot_tint`, `partner_tint`) are drawn by the block surface clamped to 0.85, so they ship clamped (a visually identical value) and the blocks are the kit tints as given.
- `test/ui/app_blocks_test.dart` names upstream's green hue for the forest hero and the sage block; `sync/hooks.py` points those two checks at the kit roles instead.
- The gold kicker (`warm_on_dark`) is a lighter apricot `#FFC79F`: the reference's `#FF9F5A` is 2.3:1 on the blue `primary`, under the backend's large-text floor (3.0). It reads at 4.5 or more on every stop of the four heroes that draw it (home, me, admin, teacher: upstream's `GOLD_KICKER_HEROES`); home, me and admin start one step deeper for that (upstream does the same: its heroes start on the logo green, not the partner). Every other hero draws its kicker in the on-hero ink (`AppHero.kickerInk`), so on `primary` itself it is held to the large-text floor only (`LARGE_ONLY`).
- The forward button and the learn button carry the deep navy text instead of white (upstream P4: white on apricot / coral is 2.0 / 3.4); `hot` itself (white text) is the coral darkened to 4.6.
- The other buttons keep white text on stops darkened to 4.6 (upstream P10). `partner` stays a gradient partner and focus ring only, never under text.
- `text_light` / `second_text` (`app_theme.dart` `secondText` / `textLight`, the `kit_default` preset) are `#5C6986`: the lightest shade of `muted` that still reads at 4.5 on every light surface and block, so it stays quieter than `text_medium` (= `muted`).
- The backend gets the same map through `../back/sync/kit_palette_alfaheem.json` (`py -3.12 sync/kit_palette_alfaheem.py --write-back ../back/sync/kit_palette_alfaheem.json` after a change here), and its `sync/alfaheem_seed.py` stores the market defaults (SA, Asia/Riyadh, SAR, Moyasar, `platform.digits` = `arabic_indic`) where unset.
