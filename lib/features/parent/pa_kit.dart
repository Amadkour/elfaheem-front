// lib/features/parent/pa_kit.dart — the parent's redesign pieces (Pa2*, phase 4), shared by every parent page.
//
//   PaKids          the children the switcher shows and the one picked (null = all). ONE instance lives in the parent
//                   dashboard and follows the Today overview (no request of its own); a pushed page reads it if it
//                   is there and draws nothing otherwise.
//   PaKidSwitcher   the top bar's child chips (AppChip onHero on phones): "الكل" with the count, one chip per child
//                   with a status dot, a dashed "+" (add a child) at the end.
//   PaKidAvatar     a child's initial on the child's own accent (the same child keeps the same colour everywhere).
//   PaHeroPage      the page frame: the switcher band, then AppHero with the body riding up over it (AppHeroOverlap),
//                   pull to refresh. Every parent tab and pushed page is built on it.
//   paRole          wraps a pushed page in the parent's role scope (a pushed route leaves the shell's scope).
//
// Motion: the parent uses M9 (jelly, inside the kit buttons and chips), M10 (numbers), M13 (tabs) and M14 (sheets)
// only; the kit enforces it (AppAreaScope.role is not playful).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;

/// One chip of the switcher.
@immutable
class PaKid {
  const PaKid({required this.id, required this.name, this.status, this.grade = ''});

  final int id;
  final String name;

  /// `on_track` · `watch` · `needs_you` · `quiet` · null (no pulse): the chip's dot.
  final String? status;

  /// The grade's name, when the server sent one.
  final String grade;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;
}

/// The children of the switcher and the one picked (null = all).
class PaKids extends ChangeNotifier {
  List<PaKid> _kids = const [];
  int? _selected;

  List<PaKid> get kids => _kids;
  int? get selected => _selected;

  PaKid? get current {
    for (final k in _kids) {
      if (k.id == _selected) return k;
    }
    return null;
  }

  void setKids(List<PaKid> kids) {
    _kids = kids;
    if (_selected != null && !kids.any((k) => k.id == _selected)) _selected = null;
    notifyListeners();
  }

  void select(int? id) {
    if (id == _selected) return;
    _selected = id;
    notifyListeners();
  }

  /// The dashboard's instance, or null outside it (a test, a page pushed from elsewhere).
  static PaKids? maybeOf(BuildContext context, {bool listen = true}) {
    try {
      return listen ? context.watch<PaKids>() : context.read<PaKids>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

bool paIsAr() => AppConfig.lang.toString().toLowerCase().startsWith('ar');

/// [ar] or [en] in the current language.
String paT(String ar, String en) => paIsAr() ? ar : en;

/// A translated key with `{name}` style placeholders filled.
String paFmt(String key, Map<String, Object?> params) {
  var s = key.tr;
  params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

bool paWide(BuildContext context) => (MediaQuery.maybeSizeOf(context)?.width ?? 0) >= Breakpoints.mobile;

/// The accent a child wears everywhere (by id, so it never moves when the list changes).
KitTone paKidTone(BuildContext context, int id) {
  const order = [AppAccent.sky, AppAccent.pink, AppAccent.grape, AppAccent.mint, AppAccent.sun, AppAccent.lime];
  return context.colors.kit.accent(order[id.abs() % order.length]);
}

/// The status dot's colour, or null (no dot).
Color? paStatusDot(BuildContext context, String? status) {
  final kit = context.colors.kit;
  return switch (status) {
    'on_track' => kit.ok.color,
    'watch' => kit.warn.color,
    'needs_you' => kit.live.color,
    'quiet' => kit.lock,
    _ => null,
  };
}

/// Wraps a pushed page in the parent's accent (the hero, tiles and buttons follow it).
Widget paRole(Widget child) => AppAreaScope.role(role: AppRoleAccent.parent, child: child);

/// A child's initial on the child's accent.
class PaKidAvatar extends StatelessWidget {
  const PaKidAvatar({super.key, required this.id, required this.name, this.size = AppChip.avatar});

  final int id;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = paKidTone(context, id);
    final initial = name.trim().isEmpty ? '' : name.trim().characters.first;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [tone.color, Color.lerp(tone.color, tone.ink, .35)!],
          ),
        ),
        child: Text(
          initial,
          style: appText(size * .42, w: FontWeight.w700, c: context.colors.onHero),
        ),
      ),
    );
  }
}

/// The child chips: "All" (with the count), one per child (status dot), a dashed "+" to add a child.
class PaKidSwitcher extends StatelessWidget {
  const PaKidSwitcher({
    super.key,
    required this.kids,
    required this.selected,
    required this.onSelect,
    this.showAll = true,
    this.onAdd,
    this.onHero = true,
  });

  final List<PaKid> kids;
  final int? selected;
  final ValueChanged<int?> onSelect;

  /// The "All" chip (a page about one child leaves it out).
  final bool showAll;
  final VoidCallback? onAdd;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chips = <Widget>[
      if (showAll)
        AppChip(
          key: const ValueKey('pa.kid.all'),
          label: 'pa_all'.tr,
          onHero: onHero,
          selected: selected == null,
          leading: Container(
            width: AppChip.avatar,
            height: AppChip.avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.kit.role(AppRoleAccent.parent).a),
            child: Text(appDigits('${kids.length}'),
                style: appText(AppIconSize.xs, w: FontWeight.w700, c: c.onHero)),
          ),
          onTap: () => onSelect(null),
        ),
      for (final k in kids)
        Semantics(
          selected: selected == k.id,
          child: AppChip(
            key: ValueKey('pa.kid.${k.id}'),
            label: k.firstName,
            onHero: onHero,
            selected: selected == k.id,
            leading: PaKidAvatar(id: k.id, name: k.name),
            count: null,
            icon: null,
            onTap: () => onSelect(k.id),
          ),
        ),
    ];
    return SizedBox(
      height: AppTouch.min,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final (i, w) in chips.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            _WithDot(dot: i == 0 && showAll ? null : paStatusDot(context, kids[i - (showAll ? 1 : 0)].status), child: w),
          ],
          if (onAdd != null) ...[
            const SizedBox(width: AppSpace.xs),
            _AddChip(onTap: onAdd!, onHero: onHero),
          ],
        ],
      ),
    );
  }
}

/// The status dot at the chip's end edge.
class _WithDot extends StatelessWidget {
  const _WithDot({required this.dot, required this.child});

  final Color? dot;
  final Widget child;

  static const double _size = AppSpace.xs;

  @override
  Widget build(BuildContext context) {
    final d = dot;
    if (d == null) return Center(child: child);
    return Center(
      child: Stack(clipBehavior: Clip.none, children: [
        child,
        PositionedDirectional(
          end: AppSpace.xxs,
          top: AppSpace.xxs,
          child: IgnorePointer(
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: d,
                border: Border.all(color: context.colors.cardBg, width: AppBorder.hairline),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap, required this.onHero});

  final VoidCallback onTap;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = onHero ? c.onHero : c.textMedium;
    return Semantics(
      button: true,
      label: 'pa_add_child'.tr,
      child: Tooltip(
        message: 'pa_add_child'.tr,
        child: InkResponse(
          key: const ValueKey('pa.kid.add'),
          onTap: onTap,
          radius: AppTouch.min / 2,
          child: SizedBox.square(
            dimension: AppTouch.min,
            child: Center(
              child: CustomPaint(
                painter: _DashedCircle(color: onHero ? c.heroGlassBorder : c.kit.line),
                child: SizedBox.square(
                  dimension: AppChip.height,
                  child: Icon(Icons.add_rounded, size: AppIconSize.md, color: ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  const _DashedCircle({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.strong;
    final r = Rect.fromLTWH(0, 0, size.width, size.height).deflate(AppBorder.strong / 2);
    const dashes = 18;
    const sweep = 3.14159265 * 2 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(r, i * sweep, sweep * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// The band under the phone top bar that carries the switcher (the top bar's colour, so both read as one); on a wide
/// screen a plain row above the hero.
class PaSwitcherBand extends StatelessWidget {
  const PaSwitcherBand({super.key, this.showAll = true, this.onAdd, this.onSelect});

  final bool showAll;
  final VoidCallback? onAdd;

  /// Default: picks the child in [PaKids].
  final ValueChanged<int?>? onSelect;

  @override
  Widget build(BuildContext context) {
    final kids = PaKids.maybeOf(context);
    if (kids == null || kids.kids.isEmpty) {
      if (onAdd == null) return const SizedBox.shrink();
    }
    final wide = paWide(context);
    final c = context.colors;
    final row = PaKidSwitcher(
      kids: kids?.kids ?? const [],
      selected: kids?.selected,
      showAll: showAll && (kids?.kids.length ?? 0) > 0,
      onAdd: onAdd,
      onHero: !wide,
      onSelect: onSelect ?? (id) => kids?.select(id),
    );
    if (wide) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm),
        child: row,
      );
    }
    return ColoredBox(
      color: c.kit.topBar,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
        child: row,
      ),
    );
  }
}

/// A parent page: the switcher band, the hero with the body riding up over it, pull to refresh.
class PaHeroPage extends StatelessWidget {
  const PaHeroPage({
    super.key,
    required this.hero,
    required this.body,
    this.band,
    this.onRefresh,
    this.width = AppWidth.content,
  });

  final Widget hero;

  /// The cards under the hero (a Column of them).
  final Widget body;

  /// The switcher band (null = none).
  final Widget? band;
  final Future<void> Function()? onRefresh;
  final AppWidth width;

  @override
  Widget build(BuildContext context) {
    final wide = paWide(context);
    final gutter = wide ? AppSpace.lg : AppSpace.md;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: [
        ?band,
        AppHeroOverlap(
          hero: hero,
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Center(
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width.max), child: body),
            ),
          ),
        ),
      ],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

/// A column of cards with the kit's gap.
class PaStack extends StatelessWidget {
  const PaStack({super.key, required this.children, this.gap = AppSpace.md});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ]);
}

/// Two columns from 1000 px ([start] wider), one under the other below.
class PaColumns extends StatelessWidget {
  const PaColumns({super.key, required this.start, required this.end, this.startFlex = 7, this.endFlex = 4});

  final List<Widget> start, end;
  final int startFlex, endFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < Breakpoints.desktop || end.isEmpty) return PaStack(children: [...start, ...end]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: startFlex, child: PaStack(children: start)),
          const SizedBox(width: AppSpace.lg),
          Expanded(flex: endFlex, child: PaStack(children: end)),
        ]);
      });
}

/// A small numbered step (the empty Today's "how to link").
class PaStep extends StatelessWidget {
  const PaStep({super.key, required this.n, required this.title, required this.text});

  final int n;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: c.kit.line, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [set.btnA, set.btnB])),
          child: Text(appDigits('$n'), style: appText(AppIconSize.sm, w: FontWeight.w700, c: set.btnFg)),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(title, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(text, style: AppType.meta(context)),
      ]),
    );
  }
}

/// A sheet header row: an icon box, the title (and an optional line under it).
class PaSheetHead extends StatelessWidget {
  const PaSheetHead({super.key, required this.icon, required this.title, this.subtitle, this.tone});

  final IconData icon;
  final String title;
  final String? subtitle;
  final KitTone? tone;

  @override
  Widget build(BuildContext context) => Row(children: [
        AppIconBox(icon: icon, tone: tone),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.section(context)),
            if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: AppType.meta(context)),
          ]),
        ),
      ]);
}

/// A soft info line (an icon and a sentence on the well).
class PaNote extends StatelessWidget {
  const PaNote({super.key, required this.text, this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.kit.well, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.md, color: set.ink),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: AppType.meta(context).copyWith(color: c.textMedium))),
      ]),
    );
  }
}
