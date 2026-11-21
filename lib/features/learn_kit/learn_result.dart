// lib/features/learn_kit/learn_result.dart — the end screen of a round (D-1346): stars, the score, what was earned
// (badges, points) and the save state of a result the server has not answered yet. Plain values only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/learn_kit/learn_grading.dart';
import 'package:flutter_education_app/features/learn_kit/learn_progress.dart';

/// One thing earned in a round (a badge).
class LearnEarned {
  const LearnEarned({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The headline for [stars] (0–3).
String learnResultTitle(int stars) => switch (stars) {
      3 => _t('ممتاز!', 'Excellent!'),
      2 => _t('أحسنت!', 'Well done!'),
      1 => _t('بداية جيدة', 'Good start'),
      _ => _t('حاول مرة أخرى', 'Try again'),
    };

/// The end screen: the stars, "7 / 8 · 88 %", the badges and points earned, then Play again · Done. While the
/// result is being saved [saving] shows a quiet line; a failed save shows [saveError] with a retry (the result is
/// kept and re-sent with the same id, so it is never counted twice).
class LearnResultView extends StatelessWidget {
  const LearnResultView({
    super.key,
    required this.score,
    required this.max,
    int? stars,
    this.title,
    this.badges = const [],
    this.pointsAwarded = 0,
    this.onReplay,
    this.replayLabel,
    this.onDone,
    this.saving = false,
    this.saveError,
    this.onRetrySave,
    this.note,
  }) : stars = stars ?? -1;

  final int score, max;

  /// -1 = derive from the score ([learnStars]).
  final int stars;
  final String? title;
  final List<LearnEarned> badges;
  final int pointsAwarded;
  final VoidCallback? onReplay, onDone;

  /// The replay button's text; defaults to "Play again" (a lesson says "Practise again").
  final String? replayLabel;
  final bool saving;
  final String? saveError;
  final VoidCallback? onRetrySave;

  /// A line under the score (e.g. "Sign in to keep your stars").
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stars < 0 ? learnStars(score, max) : stars;
    final pct = learnPercent(score, max);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppPopIn(
        child: AppCard(
          highlight: true,
          child: Column(children: [
            const SizedBox(height: AppSpace.xs),
            LearnStars(stars: s, size: AppIconSize.hero),
            const SizedBox(height: AppSpace.sm),
            Semantics(
              container: true,
              header: true,
              headingLevel: 2,
              label: title ?? learnResultTitle(s),
              excludeSemantics: true,
              child: Text(title ?? learnResultTitle(s), textAlign: TextAlign.center, style: AppType.headline(context)),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '$score / $max · $pct%',
              key: const ValueKey('learn.result.score'),
              textDirection: TextDirection.ltr,
              style: AppType.figureLarge(context).copyWith(color: c.primary),
            ),
            if (note != null && note!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(note!, textAlign: TextAlign.center, style: AppType.meta(context)),
            ],
            if (saving) ...[
              const SizedBox(height: AppSpace.sm),
              Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox.square(
                  dimension: AppIconSize.sm,
                  child: CircularProgressIndicator(strokeWidth: AppBorder.strong, color: c.primary),
                ),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: Text(_t('جارٍ حفظ النتيجة…', 'Saving your result…'), style: AppType.meta(context))),
              ]),
            ],
            if (saveError != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(saveError!, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.danger)),
              if (onRetrySave != null) ...[
                const SizedBox(height: AppSpace.xs),
                AppButton.secondary(
                  key: const ValueKey('learn.result.retry'),
                  label: _t('أعد محاولة الحفظ', 'Try saving again'),
                  icon: Icons.refresh_rounded,
                  onPressed: onRetrySave,
                ),
              ],
            ],
            if (pointsAwarded > 0) ...[
              const SizedBox(height: AppSpace.sm),
              AppStatusBadge(
                tone: AppTone.gold,
                label: _t('+$pointsAwarded نقطة', '+$pointsAwarded points'),
              ),
            ],
            const SizedBox(height: AppSpace.xs),
          ]),
        ),
      ),
      if (badges.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        Text(_t('شارات جديدة', 'New badges'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final b in badges) LearnBadgeChip(icon: b.icon, label: b.label, earned: true),
        ]),
      ],
      const SizedBox(height: AppSpace.lg),
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
        if (onReplay != null)
          AppButton.primary(
            key: const ValueKey('learn.result.replay'),
            label: replayLabel ?? _t('العب مرة أخرى', 'Play again'),
            icon: Icons.replay_rounded,
            onPressed: onReplay,
          ),
        if (onDone != null)
          AppButton.secondary(key: const ValueKey('learn.result.done'), label: _t('تم', 'Done'), onPressed: onDone),
      ]),
    ]);
  }
}

/// A badge: an icon well and its name; earned = the gold well, locked = muted with a lock read out.
class LearnBadgeChip extends StatelessWidget {
  const LearnBadgeChip({super.key, required this.icon, required this.label, this.earned = true, this.caption});

  final IconData icon;
  final String label;
  final bool earned;

  /// A second line ("Play 10 rounds", an earned date).
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = appToneColor(context, AppTone.gold);
    final well = earned ? appTintOn(context, gold) : c.inputBg;
    return Semantics(
      label: [label, earned ? _t('حصلت عليها', 'earned') : _t('لم تحصل عليها بعد', 'not earned yet'), ?caption]
          .join(', '),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xs, AppSpace.sm, AppSpace.xs),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: earned ? gold : c.divider, width: AppBorder.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: AppIconSize.xl,
            height: AppIconSize.xl,
            decoration: BoxDecoration(color: well, shape: BoxShape.circle),
            child: Icon(earned ? icon : Icons.lock_outline_rounded,
                size: AppIconSize.sm, color: earned ? appInkOn(context, gold, well) : c.textLight),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: AppType.label(context).copyWith(color: earned ? c.textDark : c.textMedium)),
              if (caption != null && caption!.isNotEmpty) Text(caption!, style: AppType.meta(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}
