// lib/features/shared/session/material/components/material_tile_parts.dart — plain-value parts of a session
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

import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../core/display/app_fonts.dart';
import '../../../../../design/app_tokens.dart';
import '../../../../admin/admin_common.dart' show t;

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

/// The ⋯ on a teacher's material card.
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
          radius: 22,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: c.inputBg, shape: BoxShape.circle, border: Border.all(color: c.divider)),
                child: Icon(Icons.more_horiz_rounded, size: 20, color: c.textMedium),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small number on the corner of a card's type tile.
class MaterialIndexBadge extends StatelessWidget {
  const MaterialIndexBadge({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        index.toString().padLeft(2, '0'),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontFamily: AppFonts.family, fontSize: 10, height: 1.2, fontWeight: FontWeight.w800, color: c.textDark),
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
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── the material ──
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                borderRadius: AppRadius.cardAll,
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.04)],
                ),
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Row(children: [
                icon,
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 15, fontWeight: FontWeight.w700, color: c.textDark)),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_isolated(facts).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium)),
                    ],
                  ]),
                ),
                IconButton(
                  tooltip: t('إغلاق', 'Close'),
                  style: IconButton.styleFrom(backgroundColor: c.cardBg),
                  onPressed: () => pop(),
                  icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20),
                ),
              ]),
            ),
            for (final g in groups)
              if (g.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                _Group(children: [for (final o in g) _Row(option: o, onTap: () => pop(o.id))]),
              ],
            if (danger != null) ...[
              const SizedBox(height: AppSpace.sm),
              _Group(children: [_Row(option: danger!, onTap: () => pop(danger!.id))]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.inputBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, indent: 60, color: c.divider),
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
    final tint = o.danger ? c.danger : c.primary;
    return InkWell(
      key: ValueKey('material.option.${o.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.primary),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs + 2),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(o.icon, size: 20, color: o.danger ? c.danger : c.textDark), // primary on its own tint vanishes in dark mode
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(o.label,
                    style: TextStyle(
                        fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w700, color: o.danger ? c.danger : c.textDark)),
                if (o.hint != null)
                  Text(o.hint!, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, height: 1.35, color: c.textMedium)),
              ]),
            ),
            if (!o.danger) ...[
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.textLight),
            ],
          ]),
        ),
      ),
    );
  }
}
