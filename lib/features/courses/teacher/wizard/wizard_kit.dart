// features/courses/teacher/wizard/wizard_kit.dart — the small pieces the course wizard's steps are drawn with
// (Tea1Wizard.dc.html): a section head, a radio option card, a price-plan card, the six code boxes, the week strip,
// a slot row, a review row, the progress band under the hero and the pinned Back / Next bar. All take plain values.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_steps.dart';

/// A step card's head: the glyph in the area ink, the title, [trailing] at the end.
class WzHead extends StatelessWidget {
  const WzHead({super.key, required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  /// Below this width the trailing piece moves under the title.
  static const double narrow = 340;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    final head = Row(children: [
      Icon(icon, size: AppIconSize.md, color: set.ink),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)))),
    ]);
    final end = trailing;
    if (end == null) return head;
    // the trailing piece (a button, a note) sits at the end of the title's line when it fits, under it when it does not
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          head,
          const SizedBox(height: AppSpace.xs),
          Align(alignment: AlignmentDirectional.centerStart, child: end),
        ]);
      }
      return Row(children: [Expanded(child: head), const SizedBox(width: AppSpace.xs), end]);
    });
  }
}

/// A radio card: a title and one line, the radio at the start, the chosen one on the area tint with the area edge.
/// [child] opens under the text (a private course's code).
class WzOption extends StatelessWidget {
  const WzOption({super.key, required this.selected, required this.title, required this.onTap, this.subtitle, this.icon, this.child});

  final bool selected;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final radius = BorderRadius.circular(AppRadius.tile);
    final body = Padding(
      padding: AppSpace.card,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            size: AppIconSize.lg, color: selected ? set.ink : c.textLight),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: AppIconSize.md, color: c.textDark), const SizedBox(width: AppSpace.xxs)],
              Flexible(child: Text(title, style: AppType.tileTitle(context))),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(subtitle!, style: AppType.meta(context)),
            ],
            if (child != null) ...[const SizedBox(height: AppSpace.sm), child!],
          ]),
        ),
      ]),
    );
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: AnimatedContainer(
        duration: AppMotion.of(context).fast,
        decoration: BoxDecoration(
          color: selected ? set.tint : c.cardBg,
          borderRadius: radius,
          border: Border.all(color: selected ? set.a : c.kit.line, width: selected ? AppBorder.focus : AppBorder.strong),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: radius, onTap: onTap, child: body),
        ),
      ),
    );
  }
}

/// One subscription plan: its name and a tag (Main / Optional), the price field, the per-month line and the "default
/// plan" radio.
class WzPlan extends StatelessWidget {
  const WzPlan({
    super.key,
    required this.title,
    required this.tag,
    required this.field,
    required this.isDefault,
    required this.onDefault,
    this.hint = '',
    this.main = false,
  });

  final String title, tag, hint;
  final bool main, isDefault;
  final Widget field;
  final VoidCallback onDefault;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: isDefault ? set.tint : c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: isDefault ? set.a : c.kit.line, width: isDefault ? AppBorder.focus : AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(title, style: AppType.tileTitle(context))),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(label: tag, tone: main ? AppTone.brand : AppTone.neutral),
        ]),
        const SizedBox(height: AppSpace.sm),
        field,
        if (hint.isNotEmpty) ...[const SizedBox(height: AppSpace.xs), Text(hint, style: AppType.meta(context))],
        const SizedBox(height: AppSpace.xs),
        Semantics(
          button: true,
          selected: isDefault,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: onDefault,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Row(children: [
                Expanded(
                  child: Text('t1_wz_default_plan'.tr,
                      style: AppType.label(context).copyWith(color: isDefault ? set.ink : c.textMedium, fontWeight: FontWeight.w600)),
                ),
                Icon(isDefault ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    size: AppIconSize.lg, color: isDefault ? set.ink : c.textLight),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The six boxes of an entry code (empty boxes while it is shorter).
class WzCodeBoxes extends StatelessWidget {
  const WzCodeBoxes({super.key, required this.code, this.focused = false});

  final String code;
  final bool focused;

  static const int length = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    // boxes read left to right in either language: a code is digits, not text
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xs),
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.85,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: focused && i == code.length ? set.a : c.kit.line, width: AppBorder.strong),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(i < code.length ? code[i] : '', style: AppType.figure(context)),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The seven weekdays in the language's order; a day with a slot is filled and shows its time.
class WzWeekStrip extends StatelessWidget {
  const WzWeekStrip({super.key, required this.days});

  /// (name, time or null) in display order.
  final List<(String, String?)> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Row(children: [
      for (var i = 0; i < days.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpace.xxs),
        Expanded(
          child: Semantics(
            label: days[i].$2 == null ? days[i].$1 : '${days[i].$1} ${days[i].$2}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
              decoration: BoxDecoration(
                gradient: days[i].$2 == null ? null : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [set.a, set.b]),
                color: days[i].$2 == null ? c.cardBg : null,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: days[i].$2 == null ? Border.all(color: c.kit.line, width: AppBorder.strong) : null,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(days[i].$1,
                      maxLines: 1,
                      style: AppType.label(context).copyWith(color: days[i].$2 == null ? c.textMedium : c.onHero, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: AppSpace.xxs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(days[i].$2 ?? ' ', maxLines: 1, style: AppType.meta(context).copyWith(color: c.onHero)),
                ),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// A weekly slot: the day in a tinted box, the range, the length, edit and delete.
class WzSlotRow extends StatelessWidget {
  const WzSlotRow({super.key, required this.day, required this.range, required this.length, required this.onEdit, required this.onDelete});

  final String day, range, length;
  final VoidCallback onEdit, onDelete;

  /// Below this width the buttons drop under the text.
  static const double narrow = 290;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    Widget action(IconData icon, String label, VoidCallback tap, Color color) => Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: tap,
              child: Container(
                width: AppTouch.min,
                height: AppTouch.min,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: c.kit.line, width: AppBorder.strong),
                ),
                child: Icon(icon, size: AppIconSize.md, color: color),
              ),
            ),
          ),
        );
    final dayBox = Container(
      constraints: const BoxConstraints(minWidth: AppTouch.primary + AppSpace.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(color: set.tint, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Text(day, maxLines: 1, textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: set.ink, fontWeight: FontWeight.w600)),
    );
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(range, maxLines: 1, style: AppType.tileTitle(context))),
      Text(length, style: AppType.meta(context)),
    ]);
    final edit = action(Icons.edit_outlined, 't1_wz_edit'.tr, onEdit, c.textMedium);
    final del = action(Icons.delete_outline_rounded, 't1_wz_delete'.tr, onDelete, c.danger);
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: c.kit.line, width: AppBorder.strong),
      ),
      // one line when it fits; on a narrow card the two buttons drop under the text
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [dayBox, const SizedBox(width: AppSpace.sm), Expanded(child: text)]),
            const SizedBox(height: AppSpace.xs),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [edit, const SizedBox(width: AppSpace.xs), del]),
          ]);
        }
        return Row(children: [
          dayBox,
          const SizedBox(width: AppSpace.sm),
          Expanded(child: text),
          const SizedBox(width: AppSpace.xs),
          edit,
          const SizedBox(width: AppSpace.xs),
          del,
        ]);
      }),
    );
  }
}

/// A review row: the step's glyph, its name, what was entered, and "Edit".
class WzSummaryRow extends StatelessWidget {
  const WzSummaryRow({super.key, required this.step, required this.text, required this.onEdit, this.ok});

  final CourseWizardStep step;
  final String text;
  final VoidCallback onEdit;

  /// null: no mark; false: the step still needs something.
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final radius = BorderRadius.circular(AppRadius.tile);
    return Semantics(
      button: true,
      label: '${step.label}: $text. ${'t1_wz_edit'.tr}',
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: ok == false ? c.danger : c.kit.line, width: AppBorder.strong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: AppSpace.card,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppIconBox(icon: step.icon),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(step.label, style: AppType.tileTitle(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Text('t1_wz_edit'.tr, style: AppType.label(context).copyWith(color: set.ink, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The band under the hero's title: "Step 1 of 7: Basics", "Next: Pricing" and the progress bar.
class WzBand extends StatelessWidget {
  const WzBand({super.key, required this.step});

  final CourseWizardStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
        Text(wizardStepLine(step), style: style),
        Text(wizardNextLine(step), style: style.copyWith(color: c.onHero.withValues(alpha: 0.72), fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: AppSpace.xs),
      Semantics(
        label: wizardStepLine(step),
        excludeSemantics: true,
        child: AppProgressBar(value: (step.index + 1).toDouble(), max: CourseWizardStep.values.length.toDouble(), height: AppSpace.xs, color: c.onHero),
      ),
    ]);
  }
}

/// The bar pinned under the scroll: [secondary] buttons then the [primary] one, on paper under a hairline.
class WzBar extends StatelessWidget {
  const WzBar({super.key, required this.primary, this.secondary = const []});

  final Widget primary;
  final List<Widget> secondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm + bottom),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.wide.inside(MediaQuery.of(context).size.width)),
          child: Row(children: [
            for (final s in secondary) ...[s, const SizedBox(width: AppSpace.sm)],
            Expanded(flex: 2, child: primary),
          ]),
        ),
      ),
    );
  }
}
