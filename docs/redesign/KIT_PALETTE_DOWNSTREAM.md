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

12 of 65 pairs are under 4.5 as drawn. Before the identity step ships them: darken the button stops (or use the dark `btn_fg`) the way the upstream script does (`darken_until`), and keep `partner` out from under text.
