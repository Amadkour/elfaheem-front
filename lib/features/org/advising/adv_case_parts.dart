// lib/features/org/advising/adv_case_parts.dart — the pieces the Phase 4 advising pages share (docs/advising/PHASE4.md):
//   AdvRiskMeter      the 0 – 100 risk score as a calm bar with its band and the top reason
//   AdvPriorityPill   a flag priority (with a count)          AdvFlagStatusPill   a flag's state
//   AdvTypedText      text someone typed, in its own direction (advTextDirection)
//   AdvTypedField     a multi-line field whose direction follows what is typed
//   AdvRestrictedLine "2 items are hidden from you" (sensitive / private rows, only counted)
//   AdvRailRow        one row of a vertical timeline (dot + line)
//   AdvMiniStat       a small labelled figure ("CGPA 1.62")
// Plain values only; sizes from app_tokens.dart, colours from context.colors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'adv_models.dart';
import 'adv_parts.dart' show advTextDirection;

/// Urgent → danger · high → warning · normal → the brand · low → muted.
Color advPriorityColor(BuildContext context, String? p) {
  final c = context.colors;
  return switch (p) {
    'urgent' => c.danger,
    'high' => c.warning,
    'low' => c.textMedium,
    _ => c.primary,
  };
}

/// The colour of a risk score's band: high → danger · watch → warning · steady → success.
Color advRiskColor(BuildContext context, int score) {
  final c = context.colors;
  return switch (advRiskBand(score)) {
    'high' => c.danger,
    'watch' => c.warning,
    _ => c.success,
  };
}

Color advFlagStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'open' => c.danger,
    'acknowledged' => c.warning,
    'contacted' => c.primary,
    'resolved' => c.success,
    _ => c.textMedium,
  };
}

/// "Risk 72 · High risk" over a thin bar, then the top reason. [large]: the 360's header.
class AdvRiskMeter extends StatelessWidget {
  const AdvRiskMeter({super.key, required this.score, this.reason, this.large = false});
  final int score;

  /// The sentence of the top reason (null: none shown).
  final String? reason;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final col = advRiskColor(context, score);
    final ink = appInk(context, col);
    final band = advRiskBandLabel(advRiskBand(score));
    final why = reason;
    return Semantics(
      label: t('درجة الخطر $score من 100، $band', 'Risk score $score of 100, $band') + (why == null ? '' : '. $why'),
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('$score', style: (large ? AppType.figure(context) : AppType.row(context)).copyWith(color: ink, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: AppSpace.xxs),
          Text('/ 100', textDirection: TextDirection.ltr, style: AppType.meta(context)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(band, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        AppProgressBar(value: score.toDouble(), max: 100, color: col, height: large ? 6 : 4),
        if (why != null && why.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(why, maxLines: large ? 3 : 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ],
      ]),
    );
  }
}

/// A flag priority; [count] > 1 adds "· 2".
class AdvPriorityPill extends StatelessWidget {
  const AdvPriorityPill({super.key, required this.priority, this.count = 0});
  final String priority;
  final int count;

  @override
  Widget build(BuildContext context) => AppBadgePill(
        count > 1 ? '${advPriorityLabel(priority)} · $count' : advPriorityLabel(priority),
        color: advPriorityColor(context, priority),
        icon: priority == 'urgent' ? Icons.priority_high_rounded : Icons.flag_rounded,
      );
}

class AdvFlagStatusPill extends StatelessWidget {
  const AdvFlagStatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => AppBadgePill(
        advFlagStatusLabel(status),
        color: advFlagStatusColor(context, status),
        icon: switch (status) {
          'acknowledged' => Icons.visibility_rounded,
          'contacted' => Icons.forum_rounded,
          'resolved' => Icons.check_circle_rounded,
          'dismissed' => Icons.remove_circle_outline_rounded,
          _ => Icons.radio_button_unchecked_rounded,
        },
      );
}

/// Text someone typed (a note, an outcome), laid out in its own direction.
class AdvTypedText extends StatelessWidget {
  const AdvTypedText(this.text, {super.key, this.style, this.maxLines});
  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textDirection: advTextDirection(text),
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: style ?? AppType.body(context).copyWith(color: context.colors.textDark),
      );
}

/// A multi-line field (a note, an outcome) whose direction follows the first strong letter typed, with the kit's
/// field look. [maxLength] shows a counter near the limit.
class AdvTypedField extends StatelessWidget {
  const AdvTypedField({super.key, required this.controller, required this.label, this.hint, this.minLines = 3, this.maxLines = 8, this.maxLength, this.onChanged, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int minLines, maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = AppBorder.hairline]) => OutlineInputBorder(borderRadius: AppRadius.chipAll, borderSide: BorderSide(color: col, width: w));
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final max = maxLength;
        final near = max != null && v.text.length > max * 0.9;
        return TextField(
          controller: controller,
          enabled: enabled,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: onChanged,
          keyboardType: TextInputType.multiline,
          textDirection: v.text.trim().isEmpty ? null : advTextDirection(v.text),
          style: AppType.body(context).copyWith(color: c.textDark),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            alignLabelWithHint: true,
            filled: true,
            fillColor: c.inputBg,
            counterText: near ? '${v.text.length} / $max' : null,
            contentPadding: const EdgeInsets.all(AppSpace.sm),
            border: b(c.divider),
            enabledBorder: b(c.divider),
            focusedBorder: b(c.primary, AppBorder.strong),
          ),
        );
      },
    );
  }
}

/// "2 items are hidden from you" — sensitive or private rows the caller may not read, only counted.
class AdvRestrictedLine extends StatelessWidget {
  const AdvRestrictedLine({super.key, required this.count, this.notes = false});
  final int count;

  /// Notes (private or sensitive) rather than flags (sensitive).
  final bool notes;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = notes
        ? countText(count,
            ar1: 'ملاحظة واحدة خاصة أو حساسة لا تظهر لك', ar2: 'ملاحظتان خاصتان أو حساستان لا تظهران لك', arFew: '$count ملاحظات خاصة أو حساسة لا تظهر لك', arMany: '$count ملاحظة خاصة أو حساسة لا تظهر لك',
            en1: '1 private or sensitive note is hidden from you', en: '$count private or sensitive notes are hidden from you')
        : countText(count,
            ar1: 'تنبيه حساس واحد لا يظهر لك', ar2: 'تنبيهان حساسان لا يظهران لك', arFew: '$count تنبيهات حساسة لا تظهر لك', arMany: '$count تنبيهاً حساساً لا يظهر لك',
            en1: '1 sensitive flag is hidden from you', en: '$count sensitive flags are hidden from you');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(children: [
        ExcludeSemantics(child: Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: context.colors.textMedium)),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: AppType.meta(context))),
      ]),
    );
  }
}

/// One row of a vertical timeline: a dot (filled when [strong]) on a line that runs down to the next row.
class AdvRailRow extends StatelessWidget {
  const AdvRailRow({super.key, required this.child, this.last = false, this.color, this.icon});
  final Widget child;
  final bool last;
  final Color? color;

  /// Drawn in the dot (null: a plain dot).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.textLight;
    final dot = icon == null ? AppSpace.sm - 2 : AppSpace.lg;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: AppSpace.lg,
          child: Column(children: [
            SizedBox(height: icon == null ? AppSpace.xxs + 2 : 0),
            ExcludeSemantics(
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(shape: BoxShape.circle, color: icon == null ? col : col.withValues(alpha: 0.14), border: icon == null ? null : Border.all(color: col.withValues(alpha: 0.4))),
                child: icon == null ? null : Icon(icon, size: AppIconSize.xs, color: appInk(context, col)),
              ),
            ),
            if (!last) Expanded(child: Container(width: AppBorder.hairline, color: c.divider)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: child)),
      ]),
    );
  }
}

/// A small figure with its label under it ("1.62" / "CGPA"); [tone] colours the figure.
class AdvMiniStat extends StatelessWidget {
  const AdvMiniStat({super.key, required this.label, required this.value, this.tone, this.hint});
  final String label, value;
  final Color? tone;

  /// A line under the label ("of 18 credits").
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = value.isEmpty ? '—' : value;
    return Semantics(
      label: '$label: $shown${hint == null ? '' : ', $hint'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: AppType.figure(context).copyWith(color: tone == null ? c.textDark : appInk(context, tone!), fontFeatures: const [FontFeature.tabularFigures()])),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          if (hint != null) Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ]),
      ),
    );
  }
}
