// lib/features/org/advising/adv_survey_sheet.dart — the anonymous survey after an advising meeting (docs/advising/
// PHASE5.md "Survey", #16): 1–5 stars and an optional comment, saying plainly that the answer is anonymous; and the
// director's (or the advisor's own) results, shown only from 5 answers.
//
//   AdvSurveyForm · AdvFeedbackView   plain values       showAdvSurveySheet · showAdvFeedbackSheet   load / write
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall;
import 'adv_appt_models.dart';
import 'adv_case_parts.dart' show AdvTypedField, AdvTypedText;
import 'adv_comm_api.dart';
import 'adv_comm_parts.dart';
import 'adv_parts.dart';

String _ratingWord(int r) => switch (r) {
      1 => t('ضعيف', 'Poor'),
      2 => t('مقبول', 'Fair'),
      3 => t('جيد', 'Good'),
      4 => t('جيد جداً', 'Very good'),
      5 => t('ممتاز', 'Excellent'),
      _ => '',
    };

class AdvSurveyForm extends StatelessWidget {
  const AdvSurveyForm({super.key, required this.info, required this.rating, required this.comment, this.busy = false, this.error, this.onRating, this.onSubmit});
  final AdvSurveyInfo info;

  /// 0 = not chosen yet.
  final int rating;
  final TextEditingController comment;
  final bool busy;
  final String? error;
  final ValueChanged<int>? onRating;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        [
          if (info.advisorName.isNotEmpty) t('لقاؤك مع ${info.advisorName}', 'Your meeting with ${info.advisorName}') else t('لقاء الإرشاد', 'Your advising meeting'),
          if (info.dateText.isNotEmpty) info.dateText,
        ].join(' · '),
        style: AppType.bodyStrong(context),
      ),
      const SizedBox(height: AppSpace.xs),
      AppBanner(
        icon: Icons.privacy_tip_outlined,
        text: t('إجابتك مجهولة الهوية: لا يُحفظ اسمك ولا الموعد معها، ولا تظهر النتائج إلا مجمّعة بعد 5 إجابات على الأقل.',
            'Your answer is anonymous: neither your name nor the appointment is kept with it, and results show only as totals from 5 answers.'),
      ),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('كيف كان اللقاء؟', 'How was the meeting?'), hint: rating == 0 ? null : _ratingWord(rating)),
      Wrap(spacing: AppSpace.xxs, children: [
        for (var r = 1; r <= 5; r++)
          Semantics(
            button: true,
            selected: r == rating,
            label: t('$r من 5 — ${_ratingWord(r)}', '$r of 5 — ${_ratingWord(r)}'),
            excludeSemantics: true,
            child: IconButton(
              iconSize: AppIconSize.xl,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              onPressed: busy || onRating == null ? null : () => onRating!(r),
              icon: Icon(r <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: r <= rating ? appInk(context, c.warning) : c.textLight),
            ),
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AdvTypedField(controller: comment, label: t('تعليق (اختياري)', 'A comment (optional)'), hint: t('ما الذي ساعدك، وما الذي يمكن أن يتحسن؟', 'What helped, and what could be better?'), minLines: 3, maxLines: 6, maxLength: advSurveyCommentMax, enabled: !busy),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.send_rounded, label: t('إرسال التقييم', 'Send the rating'), busy: busy, onPressed: rating == 0 ? null : onSubmit),
    ]);
  }
}

/// The survey of [token] (the hub's card, a deep link). Returns true once answered.
Future<bool> showAdvSurveySheet(BuildContext context, AdvCommApi api, String token, {AdvSurveyInfo? info}) async {
  var shown = info;
  if (shown == null) {
    final r = await orgCall(() => api.survey(token), quiet: true);
    if (!context.mounted) return false;
    if (!r.ok) {
      showAppNotice(advCommErrorText(r.error!), error: true);
      return false;
    }
    shown = r.data as AdvSurveyInfo;
  }
  final comment = TextEditingController();
  var rating = 0;
  var busy = false;
  String? error;
  final done = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.answerSurvey(token, rating, comment.text), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advCommErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('شكراً، وصل تقييمك دون اسمك', 'Thank you — your rating was sent without your name'));
          Navigator.pop(ctx, true);
        }

        return AppSheetContent(
          title: t('قيّم لقاء الإرشاد', 'Rate your advising meeting'),
          children: [AdvSurveyForm(info: shown!, rating: rating, comment: comment, busy: busy, error: error, onRating: (v) => set(() => rating = v), onSubmit: submit)],
        );
      }));
  return done ?? false;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Results
// ═════════════════════════════════════════════════════════════════════════════

class AdvFeedbackView extends StatelessWidget {
  const AdvFeedbackView({super.key, required this.feedback, this.advisorName});
  final AdvFeedback feedback;

  /// null = the whole organization.
  final String? advisorName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = feedback;
    final answers = countText(f.count, ar1: 'إجابة واحدة', ar2: 'إجابتان', arFew: '${f.count} إجابات', arMany: '${f.count} إجابة', en1: '1 answer', en: '${f.count} answers');
    if (f.hidden) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppEmpty(
          icon: Icons.lock_clock_outlined,
          title: t('النتائج مخفية حتى 5 إجابات', 'Results stay hidden until 5 answers'),
          message: t('$answers حتى الآن. تُخفى النتائج الأقل من ذلك حتى لا يُعرف صاحب أي إجابة.', '$answers so far. Fewer are hidden so no answer can be traced to a student.'),
        ),
      ]);
    }
    final maxN = f.distribution.values.fold<int>(1, (m, v) => v > m ? v : m);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Text((f.average ?? 0).toStringAsFixed(1), textDirection: TextDirection.ltr, style: AppType.figureLarge(context)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= (f.average ?? 0).round() ? Icons.star_rounded : Icons.star_outline_rounded, size: AppIconSize.md, color: appInk(context, c.warning)),
            ]),
            Text(t('متوسط $answers', 'Average of $answers'), style: AppType.meta(context)),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.md),
      for (var r = 5; r >= 1; r--)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Semantics(
            label: t('$r نجوم: ${f.distribution[r] ?? 0}', '$r stars: ${f.distribution[r] ?? 0}'),
            excludeSemantics: true,
            child: Row(children: [
              SizedBox(width: AppSpace.lg, child: Text('$r', textAlign: TextAlign.center, style: AppType.meta(context))),
              Icon(Icons.star_rounded, size: AppIconSize.sm, color: appInk(context, c.warning)),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: AppProgressBar(value: (f.distribution[r] ?? 0).toDouble(), max: maxN.toDouble(), color: c.warning, height: 8)),
              const SizedBox(width: AppSpace.xs),
              SizedBox(width: AppSpace.xl, child: Text('${f.distribution[r] ?? 0}', textAlign: TextAlign.end, style: AppType.meta(context))),
            ]),
          ),
        ),
      if (f.comments.isNotEmpty) ...[
        AdvSectionTitle(t('التعليقات', 'Comments'), subtitle: t('دون أسماء، بالشهر فقط', 'No names, by month only')),
        for (final (text, month) in f.comments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AdvTypedText(text),
                const SizedBox(height: AppSpace.xxs),
                Text(AdvFeedback.monthLabel(month), style: AppType.meta(context)),
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// The survey results of one advisor ([advisorUserId]) or of the whole organization (null; manage).
Future<void> showAdvFeedbackSheet(BuildContext context, AdvCommApi api, {int? advisorUserId, String? advisorName}) async {
  final r = await orgCall(() => api.feedback(advisorUserId: advisorUserId), quiet: true);
  if (!context.mounted) return;
  if (!r.ok) {
    showAppNotice(advCommErrorText(r.error!), error: true);
    return;
  }
  await showAppSheet<void>(
    context,
    (ctx) => AppSheetContent(
      title: advisorName == null ? t('تقييمات لقاءات الإرشاد', 'Advising meeting ratings') : t('تقييمات $advisorName', 'Ratings of $advisorName'),
      children: [AdvFeedbackView(feedback: r.data as AdvFeedback, advisorName: advisorName)],
    ),
  );
}
