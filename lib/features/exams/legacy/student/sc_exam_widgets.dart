// The student's exam pieces of the redesign (S-C, Stu2Exams): plain values only, so the layout harness and the
// goldens pump them without a provider.
//
//   ScExamCard       one exam on the list: the subject stripe, the icon box, the facts as grey pills, the deadline
//                    line and ONE button (the forward "Continue" is the hot one)
//   ScReviewSummary  "For review": what the student saved and what he got wrong, across every course
//   scFirstName      "Faisal" out of "Faisal Alanazi"
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart' show HomePulseDot;

/// The first word of a person's name, or [fallback].
String scFirstName(String? name, String fallback) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return fallback;
  return n.split(RegExp(r'\s+')).first;
}

/// How the deadline line of a card reads.
enum ScFootTone { live, warn, muted, ok }

/// The button of a card.
enum ScExamAction { hot, ghost, link }

class ScExamCard extends StatelessWidget {
  const ScExamCard({
    super.key,
    required this.title,
    this.subtitle,
    this.subject,
    this.icon = Icons.quiz_rounded,
    this.facts = const [],
    this.foot,
    this.footTone = ScFootTone.muted,
    this.actionLabel,
    this.action = ScExamAction.ghost,
    this.onAction,
    this.onTap,
    this.hot = false,
    this.below,
  });

  final String title;

  /// The course (and the teacher when known); a widget so a caller can pass a tappable course chip.
  final Widget? subtitle;

  /// The subject name or slug, for the stripe and the icon box.
  final String? subject;
  final IconData icon;

  /// Grey pills: "20 minutes", "10 questions", "Attempt 2 of 3".
  final List<String> facts;
  final String? foot;
  final ScFootTone footTone;
  final String? actionLabel;
  final ScExamAction action;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  /// The card the student is in the middle of: a warm wash and a live-tinted edge.
  final bool hot;

  /// Anything under the facts (a best-score bar).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = subjectColors(context, subject);
    final edge = hot ? Color.lerp(c.kit.live.tint, c.kit.live.color, .25)! : c.kit.line;
    final footColor = switch (footTone) {
      ScFootTone.live => c.kit.live.ink,
      ScFootTone.warn => c.kit.warn.ink,
      ScFootTone.ok => c.kit.ok.ink,
      ScFootTone.muted => c.textMedium,
    };
    final button = actionLabel == null
        ? null
        : switch (action) {
            ScExamAction.hot => AppButton.hot(label: actionLabel!, onPressed: onAction, size: AppButtonSize.sm),
            ScExamAction.ghost => AppButton.secondary(label: actionLabel!, onPressed: onAction, size: AppButtonSize.sm),
            ScExamAction.link => AppButton.ghost(label: actionLabel!, onPressed: onAction, size: AppButtonSize.sm),
          };

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppIconBox(icon: icon, tone: sub.tone, solid: true),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.xxs),
              DefaultTextStyle.merge(style: AppType.meta(context), child: subtitle!),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final f in facts) AppStatusBadge(label: appDigits(f)),
              ]),
            ],
          ]),
        ),
      ]),
      if (below != null) ...[const SizedBox(height: AppSpace.sm), below!],
      if (foot != null || button != null) ...[
        const SizedBox(height: AppSpace.sm),
        Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.kit.line),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          final footText = foot == null
              ? null
              : Row(children: [
                  if (footTone == ScFootTone.live) ...[
                    const HomePulseDot(),
                    const SizedBox(width: AppSpace.xs),
                  ],
                  Flexible(
                    child: Text(appDigits(foot!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(color: footColor, fontWeight: FontWeight.w600)),
                  ),
                ]);
          // a narrow card (a small phone, large text): the button goes under the line instead of squeezing it
          if (box.maxWidth < AppTouch.min * 6 && footText != null && button != null) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              footText,
              const SizedBox(height: AppSpace.xs),
              Align(alignment: AlignmentDirectional.centerEnd, child: FittedBox(fit: BoxFit.scaleDown, child: button)),
            ]);
          }
          return Row(children: [
            if (footText != null) Expanded(child: footText) else const Spacer(),
            if (button != null) ...[const SizedBox(width: AppSpace.sm), Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: button))],
          ]);
        }),
      ],
    ]);

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          gradient: hot
              ? LinearGradient(
                  begin: AlignmentDirectional.centerStart.resolve(Directionality.of(context)),
                  end: AlignmentDirectional.centerEnd.resolve(Directionality.of(context)),
                  colors: [c.cardBg, c.cardBg, c.kit.live.tint],
                  stops: const [0, .55, 1])
              : null,
          borderRadius: BorderRadius.circular(AppRadius.cardWide),
          border: Border.all(color: edge, width: AppBorder.strong),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              PositionedDirectional(
                top: 0,
                bottom: 0,
                start: 0,
                width: AppSpace.xxs + AppBorder.hairline,
                child: ColoredBox(color: sub.tone.color),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                child: body,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "For review": two figures (saved by the student, got wrong) and "Open them".
class ScReviewSummary extends StatelessWidget {
  const ScReviewSummary({super.key, required this.saved, required this.wrong, this.onOpen});

  final int saved;
  final int wrong;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final k = context.colors.kit;
    Widget figure(int n, String label, KitTone tone) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppOdometer(appDigits('$n'), memoryKey: 'sc.review.$label', style: AppType.statFigure(context, wide: false).copyWith(color: tone.ink)),
              const SizedBox(height: AppSpace.xxs),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: tone.ink)),
            ]),
          ),
        );
    return AppCard(
      title: 'sc_review_title'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          figure(saved, 'sc_review_saved_self'.tr, k.accent(AppAccent.sun)),
          const SizedBox(width: AppSpace.sm),
          figure(wrong, 'sc_review_got_wrong'.tr, k.accent(AppAccent.grape)),
        ]),
        if (onOpen != null)
          Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: onOpen, child: Text('sc_review_open'.tr))),
      ]),
    );
  }
}
