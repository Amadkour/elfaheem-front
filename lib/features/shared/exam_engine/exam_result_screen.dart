// What a student sees after an Exam Engine attempt: by the exam's results policy (nothing before it allows).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asMapList, t;

/// Plain-values body for the harness.
class ExamResultBody extends StatelessWidget {
  const ExamResultBody({super.key, required this.result, required this.examTitle});
  final Map<String, dynamic> result;
  final String examTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = result['visible'] == true;
    final state = '${result['state'] ?? ''}';
    final needsReview = result['needs_review'] == true;
    final percentage = (result['percentage'] as num?)?.toDouble();
    final passed = result['passed'];
    final questions = asMapList(result['questions']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppHero(
        title: examTitle,
        subtitle: state == 'auto_submitted' ? t('سُلّمت تلقائياً عند انتهاء الوقت', 'Submitted automatically when time ran out') : t('تم التسليم', 'Submitted'),
        icon: Icons.task_alt_rounded,
      ),
      const SizedBox(height: 12),
      if (!visible)
        AppBanner(
          icon: Icons.hourglass_top_rounded,
          text: needsReview
              ? t('النتيجة ليست متاحة بعد: بعض الإجابات تنتظر مراجعة المعلم وستظهر عندما تُنشر.', 'The result is not available yet: some answers await the teacher\'s review; it appears when published.')
              : t('النتيجة ليست متاحة بعد — ستظهر عندما ينشرها المعلم.', 'The result is not available yet — it appears when the teacher publishes it.'),
        )
      else ...[
        AppCard(
          child: Column(children: [
            Text(percentage == null ? '—' : '${percentage.toStringAsFixed(percentage == percentage.roundToDouble() ? 0 : 1)}%',
                style: appText(40, w: FontWeight.w800, c: passed == true ? c.success : (passed == false ? c.warning : c.textDark))),
            const SizedBox(height: 4),
            Text(result['score'] == null
                    ? t('الدرجة تنتظر المراجعة', 'The score awaits review')
                    : t('${result['score']} من ${result['max_score']}', '${result['score']} of ${result['max_score']}'),
                style: appText(14, c: c.textMedium)),
            if (passed != null) ...[
              const SizedBox(height: 8),
              AppBadgePill(passed == true ? t('ناجح', 'Passed') : t('لم يجتز', 'Not passed'), color: passed == true ? c.success : c.warning),
            ],
            if (needsReview) ...[
              const SizedBox(height: 8),
              Text(t('بعض الإجابات ما زالت قيد المراجعة', 'Some answers are still under review'), style: appText(12.5, c: c.textLight)),
            ],
          ]),
        ),
        if (questions.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionTitle(t('حسب السؤال', 'Per question')),
          for (final q in questions)
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text(t('سؤال #${q['question_id']}', 'Question #${q['question_id']}'), style: appText(13.5, w: FontWeight.w600)),
                trailing: Text(q['score'] == null ? t('قيد المراجعة', 'review') : '${q['score']}', style: appText(13, w: FontWeight.w700, c: c.primary)),
              ),
            ),
        ],
      ],
    ]);
  }
}

class ExamResultScreen extends StatelessWidget {
  const ExamResultScreen({super.key, required this.result, required this.examTitle});
  final Map<String, dynamic> result;
  final String examTitle;

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey('exam.result'),
        appBar: AppBar(title: Text(t('نتيجة الاختبار', 'Exam result'))),
        child: ExamResultBody(result: result, examTitle: examTitle),
      );
}
