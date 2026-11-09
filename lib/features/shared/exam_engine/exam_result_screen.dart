// What a student sees after an Exam Engine attempt: by the exam's results policy (nothing before it allows).
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, asMapList, t;
import 'exam_grading.dart' show ResultAnswer;
import 'exam_grading_widgets.dart' show ResultAnswerCard;
import 'exam_insights.dart';
import 'exam_insights_screen.dart' show StudentAppealSheet;

/// The attempt's state in the result header: graded once marked (a paper exam's attempt is "submitted" by the scan),
/// else submitted — automatically when the time ran out.
String resultStateText(String state, {bool needsReview = false}) => switch (state) {
      'graded' => t('تم التصحيح', 'Graded'),
      _ when needsReview => t('تم التسليم · ينتظر التصحيح', 'Submitted · waiting for marking'),
      'auto_submitted' => t('سُلّمت تلقائياً عند انتهاء الوقت', 'Submitted automatically when time ran out'),
      _ => t('تم التسليم', 'Submitted'),
    };

/// Plain-values body for the harness.
class ExamResultBody extends StatelessWidget {
  const ExamResultBody({super.key, required this.result, required this.examTitle, this.appeals = const {}, this.onAppeal});
  final Map<String, dynamic> result;
  final String examTitle;

  /// question id → the latest appeal on it (Phase 8)
  final Map<int, Appeal> appeals;

  /// null = appeals not offered (not allowed, not loaded, or the window closed)
  final void Function(int questionId)? onAppeal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = result['visible'] == true;
    final state = '${result['state'] ?? ''}';
    final needsReview = result['needs_review'] == true;
    final percentage = (result['percentage'] as num?)?.toDouble();
    final passed = result['passed'];
    final questions = asMapList(result['questions']);
    final answers = [for (final a in asMapList(result['answers'])) ResultAnswer.fromJson(a)];
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppHero(
        title: examTitle,
        subtitle: resultStateText(state, needsReview: needsReview),
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
        if (answers.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionTitle(t('إجاباتك', 'Your answers')),
          for (final a in answers) ResultAnswerCard(answer: a, footer: a.score == null || a.isVoided ? null : _appealLine(context, a.questionId, true)),
        ] else if (questions.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionTitle(t('حسب السؤال', 'Per question')),
          for (final q in questions)
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text(t('سؤال #${q['question_id']}', 'Question #${q['question_id']}'), style: appText(13.5, w: FontWeight.w600)),
                subtitle: _appealLine(context, asInt(q['question_id']), q['score'] != null),
                trailing: Text(q['score'] == null ? t('قيد المراجعة', 'review') : '${q['score']}', style: appText(13, w: FontWeight.w700, c: c.primary)),
              ),
            ),
        ],
      ],
    ]);
  }
}

extension on ExamResultBody {
  Widget? _appealLine(BuildContext context, int questionId, bool scored) {
    final c = context.colors;
    final a = appeals[questionId];
    if (a != null) {
      return Text(a.note == null || a.note!.isEmpty ? t('تظلم: ${appealStateText(a.state)}', 'Appeal: ${appealStateText(a.state)}')
              : t('تظلم ${appealStateText(a.state)}: ${a.note}', 'Appeal ${appealStateText(a.state)}: ${a.note}'),
          style: appText(12, c: a.state == 'accepted' ? c.success : c.textMedium), maxLines: 3, overflow: TextOverflow.ellipsis);
    }
    if (!scored || onAppeal == null) return null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(onPressed: () => onAppeal!(questionId), icon: const Icon(Icons.flag_outlined, size: 16),
          label: Text(t('طلب إعادة تصحيح', 'Request a regrade'))),
    );
  }
}

class ExamResultScreen extends StatefulWidget {
  const ExamResultScreen({super.key, required this.result, required this.examTitle});
  final Map<String, dynamic> result;
  final String examTitle;

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  final _api = ExamInsightsApi();
  Map<int, Appeal> _appeals = const {};
  bool _canAppeal = false;

  int get _attemptId => asInt(widget.result['attempt_id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.result['visible'] != true || _attemptId == 0) return;
    final r = await _api.myAppeals(_attemptId);
    if (!mounted || !r.ok) return;
    final list = asMapList(r.map['items']).map(Appeal.fromJson).toList();
    final since = DateTime.tryParse('${r.map['results_visible_since'] ?? ''}');
    final days = asInt(r.map['days']);
    setState(() {
      _appeals = {for (final a in list) if (a.state != 'withdrawn') a.questionId: a};
      _canAppeal = r.map['enabled'] == true && since != null && DateTime.now().toUtc().isBefore(since.add(Duration(days: days)));
    });
  }

  Future<void> _appeal(int questionId) async {
    final sent = await showAppSheet<bool>(context, (_) => StudentAppealSheet(
          questionLabel: t('سؤال #$questionId', 'Question #$questionId'),
          onSubmit: (reason) async {
            final r = await _api.appeal(_attemptId, questionId, reason);
            return r.ok ? null : appealCodeText(r.code, r.message);
          },
        ));
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey('exam.result'),
        appBar: AppHeader(title: t('نتيجة الاختبار', 'Exam result'), actions: const [HelpInfoButton(pageId: 'exam.result')]),
        child: ExamResultBody(result: widget.result, examTitle: widget.examTitle, appeals: _appeals, onAppeal: _canAppeal ? _appeal : null),
      );
}
