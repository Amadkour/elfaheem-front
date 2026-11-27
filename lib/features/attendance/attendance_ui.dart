/// features/attendance/attendance_ui.dart
///
/// The attendance screens' own small visual pieces on top of the kit (Warm Editorial, D-610 – D-629):
///   [AttSheetHeader]  the sheets' masthead: a tinted mark, the editorial title, one line under it, close
///   [AttNotice]       a one-line status on the tone's opaque tint (offline, closed, blocked permissions …)
///   [AttRouteLine]    one line of the "how your check-in travels" block (icon in the block's accent ink)
///   [AttChoice]       an option chip: paper with a hairline, solid emerald when chosen (48 px target)
///   [AttLiveDot]      the "open right now" dot with one soft ring that breathes (parks under Reduce motion)
///   [AttIconWell]     a rounded square holding an icon on a tint (or a solid fill)
///
/// Visual only: no state, no API.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';

/// A rounded square holding [icon]: the tone's opaque tint with the tone as ink, or a solid [fill] with the ink that
/// reads on it.
class AttIconWell extends StatelessWidget {
  const AttIconWell({super.key, required this.icon, required this.color, this.fill = false, this.size = AppTouch.min});

  final IconData icon;
  final Color color;
  final bool fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = fill ? color : appTintOn(context, color);
    final ink = fill ? appInkOnFill(context, color) : appInkOn(context, color, bg);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.controlAll),
      child: Icon(icon, size: size >= AppTouch.min ? AppIconSize.lg : AppIconSize.md, color: ink),
    );
  }
}

/// The masthead of the student and teacher sheets: the mark, the title in the editorial page-title role, one quiet
/// line under it, and a 48 px close button (left out in the side panel, whose own bar closes it).
class AttSheetHeader extends StatelessWidget {
  const AttSheetHeader({super.key, required this.icon, required this.title, this.subtitle, this.color});

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The mark's tone (the primary by default).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final side = appSheetIsSide(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(AppSpace.lg, side ? AppSpace.xs : AppSpace.lg, AppSpace.sm, AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AttIconWell(icon: icon, color: color ?? c.primary),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(subtitle!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
          ]),
        ),
        if (!side) ...[
          AppSpace.gapXs,
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            style: IconButton.styleFrom(backgroundColor: c.inputBg),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: c.textMedium, size: AppIconSize.md),
          ),
        ],
      ]),
    );
  }
}

/// One status line on the tone's opaque tint: the icon in the tone, the text in the tone darkened to AA.
class AttNotice extends StatelessWidget {
  const AttNotice({super.key, required this.icon, required this.text, required this.color, this.action});

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tint = appTintOn(context, color);
    final ink = appInkOn(context, color, tint);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.xs),
      decoration: BoxDecoration(color: tint, borderRadius: AppRadius.controlAll),
      child: Row(children: [
        Icon(icon, size: AppIconSize.sm, color: ink),
        AppSpace.gapXs,
        Expanded(child: Text(text, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600))),
        ?action,
      ]),
    );
  }
}

/// One line inside an [AppBlock]: the icon in [color] made legible on the block, the text in the block's ink.
class AttRouteLine extends StatelessWidget {
  const AttRouteLine({super.key, required this.icon, required this.text, required this.color, this.strong = false});

  final IconData icon;
  final String text;
  final Color color;

  /// The block's lead line (the route itself): the row role instead of the label role.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
          child: Icon(icon, size: AppIconSize.md, color: b.accentInk(color)),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Text(text,
              style: (strong ? AppType.row(context) : AppType.label(context)).copyWith(color: strong ? b.ink : b.muted)),
        ),
      ]),
    );
  }
}

/// An option chip: paper with a warm hairline, the solid primary with the on-fill ink when [selected]. 40 px tall
/// inside a 48 px target; the label flexes.
class AttChoice extends StatelessWidget {
  const AttChoice({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? appInkOnFill(context, c.primary) : c.textDark;
    return Semantics(
      button: true,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
        child: Center(
          widthFactor: 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.chipAll,
              child: AnimatedContainer(
                duration: AppMotion.of(context).fast,
                curve: AppMotion.curve,
                constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs, minWidth: AppTouch.min),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.primary : c.cardBg,
                  borderRadius: AppRadius.chipAll,
                  border: Border.all(color: selected ? c.primary : c.divider, width: AppBorder.hairline),
                ),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Open right now": a solid dot in [color] with one soft ring that breathes out and fades (2.4 s). A loop with a
/// meaning — attendance is being taken this minute — so it stays; Reduce motion parks it as a still dot.
class AttLiveDot extends StatefulWidget {
  const AttLiveDot({super.key, required this.color, this.size = AppSpace.xs});

  final Color color;
  final double size;

  @override
  State<AttLiveDot> createState() => _AttLiveDotState();
}

class _AttLiveDotState extends State<AttLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c, rest: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.5,
      height: s * 2.5,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(alignment: Alignment.center, children: [
            if (_c.isAnimating)
              Container(
                width: s + s * 1.5 * t,
                height: s + s * 1.5 * t,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - t))),
              ),
            Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]);
        },
      ),
    );
  }
}

/// How the teacher shows the open window: the 6-digit code (the projector's big code), the QR of the same code, or
/// the manual register (its own page, never part of the window's screens). The app-wide window is one: the sheet,
/// the projector screen and the QR card all read [attViewMode].
enum AttView { code, qr, manual }

/// The view the teacher chose for the window that is open now (set when the sheet opens; the projector reads it).
final ValueNotifier<AttView> attViewMode = ValueNotifier<AttView>(AttView.code);
