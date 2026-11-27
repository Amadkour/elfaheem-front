// lib/features/booking/booking_parts.dart
//
// The pieces of the booking flow (BookFlow): plain values only, no provider and no API. The option card, the picked
// chips, a group card with its seat level (never a count, never a name: privacy), a day row of slot times, the
// review rows, a payment method, the first-class ticket and the step bar.
//
// Motion (DESIGN_SYSTEM §1.3, booking): M3 on a selected option's mark, M9 on every option (AppJelly through the
// tile), M10 on the price (AppOdometer), M2 + M11 on the done step (the page), M6 between steps (the page).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Text helpers
// ═════════════════════════════════════════════════════════════════════════════

/// [key] translated with `{name}` placeholders filled.
String bkFill(String key, Map<String, Object> values) {
  var s = key.tr;
  values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// A Python weekday (Monday 0 … Sunday 6) → its name in the app language ("الأحد").
String bkWeekdayName(int pyWeekday) => AppTime.wall(DateTime(2024, 1, 1 + (pyWeekday % 7)), pattern: 'EEEE');

/// The order a week is listed in: Sunday first (a display order only, never a weekend rule).
int bkWeekdayOrder(int pyWeekday) => (pyWeekday + 1) % 7;

/// "الأحد والثلاثاء" / "Sunday and Tuesday".
String bkJoinDays(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (AppConfig.lang == 'ar') return names.first + names.skip(1).map((n) => ' و$n').join();
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}

/// The weekly instants' days in the viewer's zone, Sunday first: "الأحد والثلاثاء".
String bkDaysOf(List<DateTime> times) {
  final local = [for (final t in times) AppTime.toZone(t)]..sort((a, b) => (a.weekday % 7).compareTo(b.weekday % 7));
  final seen = <int>{};
  return bkJoinDays([
    for (final d in local)
      if (seen.add(d.weekday)) AppTime.wall(d, pattern: 'EEEE'),
  ]);
}

/// "7:30 إلى 8:20 م" in the viewer's zone: the first mark is dropped when both ends share it.
String bkTimeRange(DateTime utc, int minutes) {
  final a = AppTime.time(utc), b = AppTime.time(utc.add(Duration(minutes: minutes)));
  final pa = a.split(' '), pb = b.split(' ');
  final from = pa.length == 2 && pb.length == 2 && pa[1] == pb[1] ? pa[0] : a;
  return appDigits(bkFill('bk_time_range', {'from': from, 'to': b}));
}

/// "1 ديسمبر" in the viewer's zone.
String bkDay(DateTime utc) => appDigits(AppTime.date(utc, pattern: 'd MMMM'));

/// "مجموعة أ" / "Group A".
String bkGroupName(String label) => bkFill('bk_group_named', {'label': label});

/// The kit tone of the n-th group's label box (sky, grape, mint, then the warm tone).
KitTone bkGroupTone(BuildContext context, int index) {
  final kit = context.colors.kit;
  return switch (index % 4) {
    0 => kit.accent(AppAccent.sky),
    1 => kit.accent(AppAccent.grape),
    2 => kit.accent(AppAccent.mint),
    _ => kit.warmTone,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// Marks
// ═════════════════════════════════════════════════════════════════════════════

/// The round mark at the end of an option: an empty ring, or the hot disc with a tick (M3 when it turns on).
class BkCheckMark extends StatelessWidget {
  const BkCheckMark({super.key, required this.selected, this.dot = false});

  final bool selected;

  /// A radio dot instead of a tick (payment methods).
  final bool dot;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    if (!selected) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kit.fieldEdge, width: AppBorder.strong)),
      );
    }
    return AppPop(
      trigger: selected,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: kit.hotButton),
        child: dot
            ? Container(
                width: AppSpace.xs,
                height: AppSpace.xs,
                decoration: BoxDecoration(shape: BoxShape.circle, color: kit.hotFg),
              )
            : Icon(Icons.check_rounded, size: AppIconSize.sm, color: kit.hotFg),
      ),
    );
  }
}

/// The selected / plain frame every choice card shares: a well with a hairline, or the warm edge with a soft
/// glow and the tint fading in from the end.
class BkChoiceFrame extends StatelessWidget {
  const BkChoiceFrame({super.key, required this.child, required this.selected, this.onTap, this.dim = false, this.semantics});

  final Widget child;
  final bool selected, dim;
  final VoidCallback? onTap;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final warm = kit.warmTone;
    final radius = BorderRadius.circular(AppRadius.tile);
    final box = AnimatedContainer(
      duration: AppMotion.of(context).fast,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: dim ? kit.well : c.cardBg,
        gradient: selected
            ? LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [c.cardBg, warm.tint],
              )
            : null,
        border: Border.all(color: selected ? warm.color : kit.line, width: selected ? AppBorder.focus : AppBorder.strong),
        boxShadow: selected ? AppElevation.of(context, 2) : null,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: child,
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semantics,
      child: AppJelly(
        wide: true,
        enabled: onTap != null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap, borderRadius: radius, child: box),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Option card (mode, kind)
// ═════════════════════════════════════════════════════════════════════════════

/// "عن بعد" / "حضوري" / "مع مجموعة" / "فردي مع المعلم": icon box, title, one line, an optional price and a
/// meta pill, the check mark at the end.
class BkOptionCard extends StatelessWidget {
  const BkOptionCard({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.text,
    required this.selected,
    required this.onTap,
    this.price,
    this.priceNote,
    this.meta,
    this.stacked = false,
  });

  final IconData icon;
  final KitTone tone;
  final String title, text;
  final bool selected;
  final VoidCallback onTap;
  final String? price, priceNote, meta;

  /// Web, side by side: the icon over the title (BookW1).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = AppIconBox(icon: icon, tone: tone, size: AppDashSize.glyph + AppSpace.xs);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppType.tileTitle(context).copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xxs),
        Text(text, style: AppType.body(context).copyWith(color: c.textMedium)),
        if (price != null) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: AppSpace.xs, children: [
            Text(price!, style: AppType.figureLarge(context).copyWith(color: c.textDark)),
            if (priceNote != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                child: Text(priceNote!, style: AppType.body(context).copyWith(color: c.textMedium)),
              ),
          ]),
        ],
        if (meta != null) ...[
          const SizedBox(height: AppSpace.xs),
          BkMetaPill(icon: Icons.schedule_rounded, label: meta!),
        ],
      ],
    );
    return BkChoiceFrame(
      selected: selected,
      onTap: onTap,
      semantics: title,
      child: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                BkCheckMark(selected: selected),
                const Spacer(),
                box,
              ]),
              const SizedBox(height: AppSpace.sm),
              Align(alignment: AlignmentDirectional.centerEnd, child: words),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              box,
              const SizedBox(width: AppSpace.md),
              Expanded(child: words),
              const SizedBox(width: AppSpace.sm),
              BkCheckMark(selected: selected),
            ]),
    );
  }
}

/// A small pill on the well: "الحصة ٥٠ دقيقة".
class BkMetaPill extends StatelessWidget {
  const BkMetaPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: c.kit.well, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.sm, color: c.textMedium), const SizedBox(width: AppSpace.xxs)],
        Flexible(child: Text(label, style: AppType.label(context).copyWith(color: c.textMedium))),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// "اخترت": the earlier answers, each one tap from its step
// ═════════════════════════════════════════════════════════════════════════════

class BkPicked {
  const BkPicked({required this.icon, required this.label, required this.onEdit, required this.editLabel});

  final IconData icon;
  final String label, editLabel;
  final VoidCallback onEdit;
}

class BkPickedRow extends StatelessWidget {
  const BkPickedRow({super.key, required this.items});

  final List<BkPicked> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final warm = c.kit.warmTone;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('bk_picked'.tr, style: AppType.label(context).copyWith(color: c.textMedium)),
        for (final p in items)
          Semantics(
            button: true,
            label: p.editLabel,
            child: AppJelly(
              child: InkWell(
                onTap: p.onEdit,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: CustomPaint(
                  painter: _DashedPill(color: warm.color.withValues(alpha: .55)),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: AppTouch.min - AppSpace.sm,
                        height: AppTouch.min - AppSpace.sm,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: warm.tint),
                        child: Icon(p.icon, size: AppIconSize.md, color: warm.ink),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(child: Text(p.label, style: AppType.bodyStrong(context).copyWith(color: warm.ink))),
                      const SizedBox(width: AppSpace.xs),
                      Icon(Icons.edit_outlined, size: AppIconSize.sm, color: warm.ink),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DashedPill extends CustomPainter {
  _DashedPill({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(AppRadius.pill).clamp(minimum: Radius.zero, maximum: Radius.circular(size.shortestSide * .5)));
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.strong;
    const dash = AppSpace.xxs + 2, gap = AppSpace.xxs;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill old) => old.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// Groups
// ═════════════════════════════════════════════════════════════════════════════

/// The seat level of a group: three segments and a word. Privacy: a level, never a count.
class BkSeatLevel extends StatelessWidget {
  const BkSeatLevel({super.key, required this.availability, required this.tone, this.onHero = false, this.label});

  /// open | few | full
  final String availability;
  final KitTone tone;
  final bool onHero;

  /// Replaces the level's word (the full group's "نبّهني" line).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final filled = switch (availability) { 'full' => 3, 'few' => 2, _ => 1 };
    final full = availability == 'full';
    final on = onHero ? c.onHero : (full ? kit.warmTone.color : tone.color);
    final off = onHero ? c.heroGlass : kit.track;
    final ink = onHero
        ? kit.warmOnDark
        : full
            ? c.textMedium
            : availability == 'few'
                ? kit.error.color
                : kit.ok.ink;
    final word = label ??
        switch (availability) {
          'full' => 'bk_seats_full'.tr,
          'few' => 'bk_seats_few'.tr,
          _ => 'bk_seats_open'.tr,
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpace.xl * 3 + AppSpace.xs),
        child: Row(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xxs),
            Expanded(
              child: Container(
                height: AppSpace.xs,
                decoration: BoxDecoration(color: i < filled ? on : off, borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: AppSpace.xxs),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (full && !onHero) ...[
          Icon(Icons.notifications_none_rounded, size: AppIconSize.sm, color: ink),
          const SizedBox(width: AppSpace.xxs),
        ],
        Flexible(child: Text(word, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600))),
      ]),
    ]);
  }
}

/// The label box of a group: "مجموعة" over the letter, in the group's tone.
class BkGroupBadge extends StatelessWidget {
  const BkGroupBadge({super.key, required this.label, required this.tone, this.onHero = false});

  final String label;
  final KitTone tone;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = onHero ? c.onHero : tone.ink;
    return Container(
      width: AppDashSize.disc + AppSpace.sm,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: onHero ? c.heroGlass : tone.tint,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('bk_group'.tr, style: AppType.meta(context).copyWith(color: ink)),
        Text(label, style: AppType.section(context).copyWith(color: ink)),
      ]),
    );
  }
}

/// One group of "اختر مجموعتك": its days, time and teacher, the first class, the seat level, the mark.
class BkGroupCard extends StatelessWidget {
  const BkGroupCard({
    super.key,
    required this.label,
    required this.days,
    required this.time,
    required this.tone,
    required this.availability,
    required this.selected,
    this.teacher,
    this.starts,
    this.onTap,
    this.onNotify,
    this.notified = false,
  });

  final String label, days, time, availability;
  final String? teacher, starts;
  final KitTone tone;
  final bool selected, notified;
  final VoidCallback? onTap;

  /// A full group: "نبّهني إذا فضى مقعد".
  final VoidCallback? onNotify;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final full = availability == 'full';
    final muted = full ? c.textLight : c.textMedium;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(days, style: AppType.tileTitle(context).copyWith(color: full ? c.textMedium : c.textDark, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
          Text(time, style: AppType.body(context).copyWith(color: muted)),
          if (teacher != null) Text(teacher!, style: AppType.body(context).copyWith(color: muted)),
        ]),
        if (starts != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(starts!, style: AppType.body(context).copyWith(color: muted)),
        ],
        const SizedBox(height: AppSpace.sm),
        if (full && onNotify != null)
          InkWell(
            onTap: notified ? null : onNotify,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: BkSeatLevel(
                availability: availability,
                tone: tone,
                label: notified ? 'bk_seats_notified'.tr : 'bk_seats_full_notify'.tr,
              ),
            ),
          )
        else
          BkSeatLevel(availability: availability, tone: tone),
      ],
    );
    return BkChoiceFrame(
      selected: selected,
      dim: full,
      onTap: full ? null : onTap,
      semantics: '${bkGroupName(label)}، $days، $time',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BkGroupBadge(label: label, tone: tone),
        const SizedBox(width: AppSpace.md),
        Expanded(child: info),
        const SizedBox(width: AppSpace.sm),
        BkCheckMark(selected: selected),
      ]),
    );
  }
}

/// "هذا موعد المجموعة": the one group on the area's dark card.
class BkOneGroupCard extends StatelessWidget {
  const BkOneGroupCard({
    super.key,
    required this.label,
    required this.days,
    required this.time,
    required this.availability,
    this.teacher,
    this.starts,
    this.mode,
  });

  final String label, days, time, availability;
  final String? teacher, starts, mode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = AppType.body(context).copyWith(color: c.onHeroMuted);
    return AppCard(
      variant: AppCardVariant.dark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BkGroupBadge(label: label, tone: c.kit.warmTone, onHero: true),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(days, style: AppType.headline(context).copyWith(color: c.onHero)),
              const SizedBox(height: AppSpace.xxs),
              Text(time, style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.xs, children: [
          if (teacher != null) Text(teacher!, style: meta),
          if (starts != null) Text(starts!, style: meta),
          if (mode != null) Text(mode!, style: meta),
        ]),
        const SizedBox(height: AppSpace.md),
        BkSeatLevel(availability: availability, tone: c.kit.warmTone, onHero: true),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Individual: a day's free times
// ═════════════════════════════════════════════════════════════════════════════

class BkTimeOption {
  const BkTimeOption({required this.id, required this.label, required this.selected, this.blocked = false});

  final int id;
  final String label;
  final bool selected;

  /// Another time of the same day is picked: drawn faint, a tap moves the pick here.
  final bool blocked;
}

class BkDayRow extends StatelessWidget {
  const BkDayRow({super.key, required this.day, required this.times, required this.onPick});

  final String day;
  final List<BkTimeOption> times;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: kit.line, width: AppBorder.strong),
      ),
      child: Row(children: [
        SizedBox(
          width: AppDashSize.courseTile / 2.5,
          child: Text(day, style: AppType.bodyStrong(context)),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            for (final t in times) _TimeChip(option: t, onTap: () => onPick(t.id)),
          ]),
        ),
      ]),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.option, required this.onTap});

  final BkTimeOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final on = option.selected;
    final chip = AnimatedContainer(
      duration: AppMotion.of(context).fast,
      constraints: const BoxConstraints(minWidth: AppDashSize.disc, minHeight: AppTouch.min - AppSpace.xxs),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      decoration: BoxDecoration(
        gradient: on ? kit.hotButton : null,
        color: on ? null : (option.blocked ? kit.well : c.cardBg),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: on ? null : Border.all(color: kit.line, width: AppBorder.strong),
        boxShadow: on ? AppElevation.of(context, 2) : null,
      ),
      child: Text(
        option.label,
        style: AppType.bodyStrong(context).copyWith(
          color: on ? kit.hotFg : (option.blocked ? c.textLight : c.textDark),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: on,
      child: AppJelly(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: on ? AppPop(trigger: on, child: chip) : chip,
        ),
      ),
    );
  }
}

/// A chip of the proposal's days / periods ("الأحد", "العصر ٣ إلى ٥"): the ink pill when picked.
class BkPickChip extends StatelessWidget {
  const BkPickChip({super.key, required this.label, required this.selected, required this.onTap, this.note});

  final String label;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final fg = selected ? c.onHero : c.textDark;
    final chip = AnimatedContainer(
      duration: AppMotion.of(context).fast,
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs),
      decoration: BoxDecoration(
        color: selected ? kit.ink : c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: selected ? kit.ink : kit.line, width: AppBorder.strong),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, style: AppType.bodyStrong(context).copyWith(color: fg))),
        if (note != null) ...[
          const SizedBox(width: AppSpace.sm),
          Flexible(child: Text(note!, style: AppType.label(context).copyWith(color: selected ? c.onHeroMuted : c.textMedium))),
        ],
      ]),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: AppJelly(
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadius.pill), child: chip),
      ),
    );
  }
}

/// A titled well that holds a set of chips ("الأيام", "الفترة", "المنطقة").
class BkWell extends StatelessWidget {
  const BkWell({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: kit.line, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: AppType.bodyStrong(context))),
          ?trailing,
        ]),
        const SizedBox(height: AppSpace.sm),
        child,
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Review
// ═════════════════════════════════════════════════════════════════════════════

class BkReviewRow {
  const BkReviewRow({required this.label, required this.value, this.onEdit, this.editLabel});

  final String label, value;
  final VoidCallback? onEdit;
  final String? editLabel;
}

/// "راجع حجزك": label · value · تعديل rows, then the monthly amount under a dashed rule.
class BkReviewTable extends StatelessWidget {
  const BkReviewTable({super.key, required this.rows, required this.totalLabel, required this.total, this.note});

  final List<BkReviewRow> rows;
  final String totalLabel;
  final String total;

  /// Under the total: "≈ 1,320 جنيه" and the charge note, the VAT line.
  final List<String>? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final warm = kit.warmTone;
    Widget row(BkReviewRow r) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Flexible(
              flex: 2,
              child: Text(r.label, style: AppType.body(context).copyWith(color: c.textMedium)),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(flex: 4, child: Text(r.value, style: AppType.bodyStrong(context))),
            if (r.onEdit != null) ...[
              const SizedBox(width: AppSpace.sm),
              Semantics(
                button: true,
                label: r.editLabel,
                child: InkWell(
                  onTap: r.onEdit,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.sm),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                    decoration: BoxDecoration(color: warm.tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: ExcludeSemantics(
                      child: Text('bk_edit'.tr, style: AppType.label(context).copyWith(color: warm.ink, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        );
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: kit.line, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: kit.line),
          row(r),
        ],
        CustomPaint(painter: _DashRule(color: kit.fieldEdge), child: const SizedBox(height: AppBorder.strong)),
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Flexible(
              flex: 2,
              child: Text(totalLabel, style: AppType.body(context).copyWith(color: c.textMedium)),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AppOdometer(total, style: AppType.figureLarge(context).copyWith(color: c.textDark)),
                ),
                for (final n in note ?? const <String>[])
                  Text(n, style: AppType.meta(context)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _DashRule extends CustomPainter {
  _DashRule({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = AppBorder.hairline;
    const dash = AppSpace.xxs + 2, gap = AppSpace.xxs;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + dash, size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(_DashRule old) => old.color != color;
}

/// One payment method: its brand plate, its name, the radio. The list is the server's, by country.
class BkPayMethodTile extends StatelessWidget {
  const BkPayMethodTile({super.key, required this.label, required this.brand, required this.selected, required this.onTap, this.tone});

  final String label, brand;
  final bool selected;
  final VoidCallback onTap;
  final KitTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tone ?? c.kit.primaryTone;
    return BkChoiceFrame(
      selected: selected,
      onTap: onTap,
      semantics: label,
      child: Row(children: [
        Container(
          constraints: const BoxConstraints(minWidth: AppDashSize.disc + AppSpace.md, minHeight: AppTouch.min - AppSpace.xs),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          decoration: BoxDecoration(color: t.tint, borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Text(brand, style: AppType.label(context).copyWith(color: t.ink, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(child: Text(label, style: AppType.tileTitle(context))),
        BkCheckMark(selected: selected, dot: true),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Done: the first class's ticket
// ═════════════════════════════════════════════════════════════════════════════

class BkTicket extends StatelessWidget {
  const BkTicket({
    super.key,
    required this.label,
    required this.time,
    required this.teacher,
    required this.meta,
    this.month,
    this.day,
    this.weekday,
  });

  final String label, time, teacher, meta;

  /// The date stub; all null for a proposal (its days are not fixed yet).
  final String? month, day, weekday;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final warm = kit.warmTone;
    final body = Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppType.label(context).copyWith(color: warm.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.xs),
        Text(time, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          _Initial(name: teacher),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(teacher, style: AppType.body(context).copyWith(color: c.textMedium))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(meta, style: AppType.meta(context)),
      ]),
    );
    final stub = month == null
        ? null
        : SizedBox(
            width: AppDashSize.courseTile / 2,
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                decoration: BoxDecoration(gradient: kit.hotButton),
                child: Text(month!, textAlign: TextAlign.center,
                    style: AppType.label(context).copyWith(color: kit.hotFg, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: warm.tint,
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(day ?? '', style: AppType.display(context).copyWith(color: c.textDark)),
                    if (weekday != null)
                      Text(weekday!, style: AppType.label(context).copyWith(color: warm.ink, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile + AppSpace.xxs),
        border: Border.all(color: Color.lerp(warm.tint, warm.color, .35)!, width: AppBorder.strong),
        boxShadow: AppElevation.of(context, 2),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: body),
          ?stub,
        ]),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final clean = name.replaceFirst(RegExp(r'^(أ\.|د\.|Mr\.?|Ms\.?|Dr\.?)\s*'), '').trim();
    return Container(
      width: AppIconSize.xl,
      height: AppIconSize.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: kit.hotButton),
      child: Text(clean.isEmpty ? '' : clean.characters.first,
          style: AppType.label(context).copyWith(color: kit.hotFg, fontWeight: FontWeight.w700)),
    );
  }
}

/// A line of the done step: an icon box and a few words ("إيصال الدفع وصل جوالك").
class BkPerk extends StatelessWidget {
  const BkPerk({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        AppIconBox(icon: icon, tone: context.colors.kit.warmTone),
        const SizedBox(width: AppSpace.md),
        Expanded(child: Text(text, style: AppType.bodyStrong(context))),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
// Hero pieces
// ═════════════════════════════════════════════════════════════════════════════

/// The small book of the hero in the subject's colour.
class BkMiniBook extends StatelessWidget {
  const BkMiniBook({super.key, this.subject});

  final String? subject;

  static const Size size = Size(AppDashSize.disc + AppSpace.xxs, AppDashSize.ring + AppSpace.xs);

  @override
  Widget build(BuildContext context) {
    final s = subjectColors(context, subject);
    final c = context.colors;
    return Transform.rotate(
      angle: Directionality.of(context) == TextDirection.rtl ? 0.06 : -0.06,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(s.tone.color, c.onHero, .18)!, s.tone.color],
          ),
          borderRadius: BorderRadius.circular(AppRadius.glyph),
          boxShadow: AppElevation.of(context, 2),
        ),
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final w in const [1.0, .7])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: AppSpace.xxs,
                  decoration: BoxDecoration(color: s.fg.withValues(alpha: .7), borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Four segments; the current one fills from the start, the done ones are full. Web adds the step names.
class BkStepBar extends StatelessWidget {
  const BkStepBar({super.key, required this.step, required this.total, this.labels});

  /// 1-based; above [total] = all done.
  final int step, total;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final grad = LinearGradient(
      begin: AlignmentDirectional.centerEnd,
      end: AlignmentDirectional.centerStart,
      colors: [kit.hotA, c.onHero],
    );
    Widget seg(int i) {
      final n = i + 1;
      final fill = n < step ? 1.0 : (n == step ? .4 : 0.0);
      return Container(
        height: AppSpace.xs,
        decoration: BoxDecoration(color: c.onHero.withValues(alpha: .22), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: fill,
          child: Container(decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(AppRadius.pill))),
        ),
      );
    }

    return Semantics(
      label: bkFill('bk_step_of', {'n': appDigits('${step.clamp(1, total)}'), 'total': appDigits('$total')}),
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                seg(i),
                if (labels != null && i < labels!.length) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    '${appDigits('${i + 1}')}. ${labels![i]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(
                      color: i + 1 <= step ? c.onHero : c.onHeroMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
