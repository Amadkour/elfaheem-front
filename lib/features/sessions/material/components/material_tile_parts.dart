// lib/features/sessions/material/components/material_tile_parts.dart — plain-value parts of a session
// material's card (D-316).
//
//   MaterialMoreButton     the ONE ⋯ button on a teacher's material card (it took the place of the Studio · Share ·
//                          Settings · Delete icons)
//   MaterialOptionsSheet   what it opens: the material on top (type tile, name, facts), then the grouped options —
//                          Open in Studio (videos) · Edit details · Share lesson link — and Delete apart, in red
//   MaterialOption         one row of it (icon, label, hint)
//   MaterialIndexBadge     the "01" on the corner of the type tile
//
// Plain values only (no provider, no API): test/ui/material_tile_layout_test.dart pumps them at every size.
import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

/// Each fact in its own direction isolate: "152.4 MB" and "1:02:33" stay whole inside an Arabic line.
List<String> _isolated(List<String> facts) => [for (final f in facts) '${String.fromCharCode(0x2068)}$f${String.fromCharCode(0x2069)}'];

/// One option of [MaterialOptionsSheet].
class MaterialOption {
  const MaterialOption({required this.id, required this.icon, required this.label, this.hint, this.danger = false});

  /// What the sheet pops with: studio · edit · share · delete.
  final String id;
  final IconData icon;
  final String label;
  final String? hint;
  final bool danger;
}

/// The ⋯ on a teacher's material card: a quiet well in a 48 px target.
class MaterialMoreButton extends StatelessWidget {
  const MaterialMoreButton({super.key, required this.onTap});
  final VoidCallback onTap;

  static String get label => t('خيارات المادة', 'Material options');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: AppTouch.min / 2,
          child: SizedBox.square(
            dimension: AppTouch.min,
            child: Center(
              child: Container(
                width: AppSpace.xl + AppSpace.xxs,
                height: AppSpace.xl + AppSpace.xxs,
                decoration: BoxDecoration(color: c.inputBg, shape: BoxShape.circle),
                child: Icon(Icons.more_horiz_rounded, size: AppIconSize.md, color: c.textMedium),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small number on the corner of a card's type tile: a paper chip on a hairline, tabular figures.
class MaterialIndexBadge extends StatelessWidget {
  const MaterialIndexBadge({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: AppSpace.lg - 2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: 1),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.chipAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Text(
        index.toString().padLeft(2, '0'),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: AppType.overline(context).copyWith(height: 1.2, color: c.textDark, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// The options of one material. Pops with the tapped [MaterialOption.id] (null: closed).
class MaterialOptionsSheet extends StatelessWidget {
  const MaterialOptionsSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.facts = const [],
    required this.groups,
    this.danger,
  });

  final String title;

  /// The type tile on top (the card's own).
  final Widget icon;
  final Color color;

  /// Type · size · duration · date.
  final List<String> facts;

  /// Grouped options, one card each.
  final List<List<MaterialOption>> groups;

  /// Delete, apart and last.
  final MaterialOption? danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pop = Navigator.of(context).pop;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── the material: its tile, its name in the editorial face, its facts ──
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: icon),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Text(_isolated(facts).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              IconButton(
                tooltip: t('إغلاق', 'Close'),
                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                style: IconButton.styleFrom(backgroundColor: c.inputBg),
                onPressed: () => pop(),
                icon: Icon(Icons.close_rounded, color: c.textMedium, size: AppIconSize.md),
              ),
            ]),
            const SizedBox(height: AppSpace.md),
            for (final g in groups)
              if (g.isNotEmpty) ...[
                _Group(children: [for (final o in g) _Row(option: o, onTap: () => pop(o.id))]),
                const SizedBox(height: AppSpace.sm),
              ],
            if (danger != null) ...[
              const SizedBox(height: AppSpace.xs),
              _Group(children: [_Row(option: danger!, onTap: () => pop(danger!.id))]),
            ],
          ],
        ),
      ),
    );
  }
}

/// One group of options: a paper card on a warm hairline, its rows parted by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: AppBorder.hairline, indent: AppSpace.xxxl - AppSpace.xxs, color: c.divider),
          children[i],
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.option, required this.onTap});
  final MaterialOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = option;
    final ink = o.danger ? c.blockAccentInk(c.danger, c.cardBg) : c.textDark;
    return InkWell(
      key: ValueKey('material.option.${o.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.primary),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm - 2),
          child: Row(children: [
            Container(
              width: AppSpace.xl + AppSpace.xxs,
              height: AppSpace.xl + AppSpace.xxs,
              decoration: BoxDecoration(color: o.danger ? c.dangerTint : c.inputBg, borderRadius: AppRadius.chipAll),
              child: Icon(o.icon, size: AppIconSize.md, color: ink),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(o.label, style: AppType.bodyStrong(context).copyWith(color: ink)),
                if (o.hint != null) ...[
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(o.hint!, style: AppType.meta(context).copyWith(height: 1.35)),
                ],
              ]),
            ),
            if (!o.danger) ...[
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
            ],
          ]),
        ),
      ),
    );
  }
}
