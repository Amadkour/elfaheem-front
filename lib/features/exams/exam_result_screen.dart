// What a student sees after an Exam Engine attempt: by the exam's results policy (nothing before it allows).
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill, AppOdometer, AppReveal, AppTilt;
import 'package:flutter_education_app/core/display/app_fonts.dart' show AppFonts;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_grading.dart' show ResultAnswer;
import 'package:flutter_education_app/features/exams/exam_grading_widgets.dart' show ExamVerdict, ExamVerdictMark, ResultAnswerCard, examVerdictOf;
import 'package:flutter_education_app/features/exams/exam_insights.dart';
import 'package:flutter_education_app/features/exams/exam_page_width.dart';
import 'package:flutter_education_app/features/exams/exam_insights_screen.dart' show StudentAppealSheet;

/// The attempt's state in the result header: graded once marked (a paper exam's attempt is "submitted" by the scan),
/// else submitted — automatically when the time ran out.
String resultStateText(String state, {bool needsReview = false}) => switch (state) {
      'graded' => t('تم التصحيح', 'Graded'),
      _ when needsReview => t('تم التسليم · ينتظر التصحيح', 'Submitted · waiting for marking'),
      'auto_submitted' => t('سُلّمت تلقائياً عند انتهاء الوقت', 'Submitted automatically when time ran out'),
      _ => t('تم التسليم', 'Submitted'),
    };

/// From this percentage up a passed result is a top mark: the score block turns gold (system.md §2: gold only for
/// achievements and top marks).
const double examTopMarkPercent = 90;

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
    return ExamPageWidth(width: AppWidth.reading, builder: (side) => ListView(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl), children: [
      if (!visible)
        _PendingBlock(examTitle: examTitle, stateText: resultStateText(state, needsReview: needsReview), needsReview: needsReview)
      else ...[
        ExamScoreBlock(
          examTitle: examTitle,
          stateText: resultStateText(state, needsReview: needsReview),
          percentage: percentage,
          score: result['score'] == null ? null : '${result['score']}',
          maxScore: '${result['max_score'] ?? ''}',
          passed: passed is bool ? passed : null,
          needsReview: needsReview,
          memoryKey: 'exam.result.${result['attempt_id'] ?? examTitle}',
        ),
        if (answers.isNotEmpty)
          AppSection(
            title: t('إجاباتك', 'Your answers'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, a) in answers.indexed)
                AppReveal(
                  index: i,
                  group: 'exam.result',
                  child: ResultAnswerCard(answer: a, footer: a.score == null || a.isVoided ? null : _appealLine(context, a.questionId, true)),
                ),
            ]),
          )
        else if (questions.isNotEmpty)
          AppSection(
            title: t('حسب السؤال', 'Per question'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, q) in questions.indexed)
                AppReveal(
                  index: i,
                  group: 'exam.result',
                  child: AppCard(
                    margin: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ExamVerdictMark(verdict: q['score'] == null ? ExamVerdict.pending : examVerdictOf(score: (q['score'] as num?)?.toDouble(), max: (q['max'] as num?)?.toDouble())),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpace.xxs),
                            child: Text(t('سؤال #${q['question_id']}', 'Question #${q['question_id']}'), style: AppType.bodyStrong(context)),
                          ),
                          ?_appealLine(context, asInt(q['question_id']), q['score'] != null),
                        ]),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Flexible(child: Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xxs),
                        child: Text(q['score'] == null ? t('قيد المراجعة', 'review') : '${q['score']}',
                            textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: AppType.label(context).copyWith(
                                color: q['score'] == null ? c.textMedium : c.textDark,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      )),
                    ]),
                  ),
                ),
            ]),
          ),
      ],
    ]));
  }
}

/// The result before it is published: a calm sky block that says why and when it will appear.
class _PendingBlock extends StatelessWidget {
  const _PendingBlock({required this.examTitle, required this.stateText, required this.needsReview});
  final String examTitle;
  final String stateText;
  final bool needsReview;

  @override
  Widget build(BuildContext context) {
    final b = AppBlockColors.of(context, AppBlockTone.sky);
    return AppBlock(
      tone: AppBlockTone.sky,
      hero: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.hourglass_top_rounded, size: AppIconSize.xl, color: b.ink),
        const SizedBox(height: AppSpace.md),
        Text(examTitle, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: AppType.headline(context).copyWith(color: b.ink, fontFamilyFallback: AppFonts.fallback)),
        const SizedBox(height: AppSpace.xxs),
        Text(stateText, style: AppType.meta(context).copyWith(color: b.muted)),
        const SizedBox(height: AppSpace.md),
        Text(
          needsReview
              ? t('النتيجة ليست متاحة بعد: بعض الإجابات تنتظر مراجعة المعلم وستظهر عندما تُنشر.', 'The result is not available yet: some answers await the teacher\'s review; it appears when published.')
              : t('النتيجة ليست متاحة بعد — ستظهر عندما ينشرها المعلم.', 'The result is not available yet — it appears when the teacher publishes it.'),
          style: AppType.body(context).copyWith(color: b.ink),
        ),
      ]),
    );
  }
}

/// THE moment of the result page: the score as a large rolling figure on a block whose tone is the outcome — gold for
/// a top mark, emerald for a pass, peach otherwise (never danger: a result is not an error) — with the outcome also in
/// words and a glyph. It leans a little under the pointer.
class ExamScoreBlock extends StatelessWidget {
  const ExamScoreBlock({super.key, required this.examTitle, required this.stateText, required this.percentage, required this.score,
      required this.maxScore, required this.passed, this.needsReview = false, this.memoryKey});
  final String examTitle;
  final String stateText;
  final double? percentage;

  /// null = the score awaits review
  final String? score;
  final String maxScore;
  final bool? passed;
  final bool needsReview;
  final String? memoryKey;

  /// The score is the page's one big figure: the display role drawn this much larger.
  static const double figureScale = 1.75;

  @override
  Widget build(BuildContext context) {
    final pct = percentage;
    final top = passed == true && pct != null && pct >= examTopMarkPercent;
    final tone = top ? AppBlockTone.gold : (passed == true ? AppBlockTone.emerald : AppBlockTone.peach);
    final b = AppBlockColors.of(context, tone);
    final figure = pct == null ? '—' : '${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%';
    final display = AppType.display(context);
    final figureStyle = display.copyWith(
        fontSize: (display.fontSize ?? AppSpace.xl) * figureScale,
        color: b.ink, height: 1, fontFeatures: const [FontFeature.tabularFigures(), FontFeature.liningFigures()]);
    final outcome = passed == null
        ? null
        : AppStatusBadge(
            label: passed == true ? t('ناجح', 'Passed') : t('لم يجتز', 'Not passed'),
            tone: top ? AppTone.gold : (passed == true ? AppTone.success : AppTone.warning),
            icon: top ? Icons.workspace_premium_rounded : (passed == true ? Icons.check_circle_rounded : Icons.info_outline_rounded),
          );
    return AppTilt.subtle(
      radius: AppRadius.block,
      child: AppBlock(
        tone: tone,
        hero: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(examTitle, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: AppType.section(context).copyWith(color: b.ink, fontFamilyFallback: AppFonts.fallback)),
          const SizedBox(height: AppSpace.xxs),
          Text(stateText, style: AppType.meta(context).copyWith(color: b.muted)),
          const SizedBox(height: AppSpace.lg),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpace.md,
            runSpacing: AppSpace.sm,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                // the figure never clips: on a narrow phone with large text it scales down to the block
                child: FittedBox(fit: BoxFit.scaleDown, child: pct == null ? Text(figure, style: figureStyle) : AppOdometer(figure, memoryKey: memoryKey, style: figureStyle)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                child: Text(
                    score == null ? t('الدرجة تنتظر المراجعة', 'The score awaits review') : t('$score من $maxScore', '$score of $maxScore'),
                    style: AppType.bodyStrong(context).copyWith(color: b.ink)),
              ),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: AppSpace.md),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: SizedBox(
                  height: AppSpace.xs,
                  child: Stack(children: [
                    Positioned.fill(child: ColoredBox(color: b.ink.withValues(alpha: .1))),
                    AppFill(
                      value: (pct / 100).clamp(0.0, 1.0),
                      builder: (_, v) => FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: v, heightFactor: 1, child: ColoredBox(color: b.ink)),
                    ),
                  ]),
                ),
              ),
            ),
          ],
          if (outcome != null || needsReview) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ?outcome,
              if (needsReview)
                Text(t('بعض الإجابات ما زالت قيد المراجعة', 'Some answers are still under review'), style: AppType.meta(context).copyWith(color: b.muted)),
            ]),
          ],
        ]),
      ),
    );
  }
}

extension on ExamResultBody {
  Widget? _appealLine(BuildContext context, int questionId, bool scored) {
    final c = context.colors;
    final a = appeals[questionId];
    if (a != null) {
      return Text(a.note == null || a.note!.isEmpty ? t('تظلم: ${appealStateText(a.state)}', 'Appeal: ${appealStateText(a.state)}')
              : t('تظلم ${appealStateText(a.state)}: ${a.note}', 'Appeal ${appealStateText(a.state)}: ${a.note}'),
          style: AppType.meta(context).copyWith(color: a.state == 'accepted' ? c.success : c.textMedium), maxLines: 3, overflow: TextOverflow.ellipsis);
    }
    if (!scored || onAppeal == null) return null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppButton.ghost(onPressed: () => onAppeal!(questionId), icon: Icons.flag_outlined, size: AppButtonSize.sm,
          label: t('طلب إعادة تصحيح', 'Request a regrade')),
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
