// What a student sees after an Exam Engine attempt: by the exam's results policy (nothing before it allows).
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppBurst, AppFill, AppOdometer, AppReveal, AppSlap, AppTilt, BurstMoment;
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';
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

/// Plain-values body for the harness (redesign S-C, Stu2Exams?screen=result): the outcome in the hero ("Well done,
/// Faisal, you passed" with the squiggle, "Almost", "With the teacher"), the score card riding on it (the ring draws
/// in, M2, the "Passed" stamp slaps on, M4, and a pass fires the bounded burst, M11), then "Your answers" with one
/// filter row (all · right · wrong · partial) and the regrade request on each marked answer.
class ExamResultBody extends StatelessWidget {
  const ExamResultBody({super.key, required this.result, required this.examTitle, this.appeals = const {}, this.onAppeal, this.firstName, this.onDone});
  final Map<String, dynamic> result;
  final String examTitle;

  /// question id → the latest appeal on it (Phase 8)
  final Map<int, Appeal> appeals;

  /// null = appeals not offered (not allowed, not loaded, or the window closed)
  final void Function(int questionId)? onAppeal;

  /// The student's first name for the hero ("Well done, Faisal").
  final String? firstName;

  /// "Back to the course" (null: no button).
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final visible = result['visible'] == true;
    final state = '${result['state'] ?? ''}';
    final needsReview = result['needs_review'] == true;
    final percentage = (result['percentage'] as num?)?.toDouble();
    final passed = result['passed'] is bool ? result['passed'] as bool : null;
    final questions = asMapList(result['questions']);
    final answers = [for (final a in asMapList(result['answers'])) ResultAnswer.fromJson(a)];
    final score = result['score'] == null ? null : fmtScore(result['score']);
    final max = fmtScore(result['max_score'] ?? '');
    final name = firstName == null ? '' : t(' يا $firstName', ', $firstName');
    final word = t('مبروك', 'Well done');
    final (title, sub) = !visible
        ? (t('إجاباتك وصلت للمعلم', 'Your answers reached the teacher'), t('نعلمك أول ما تطلع النتيجة', "We'll tell you as soon as the result is out"))
        : passed == true
            ? (t('$word$name، نجحت', '$word$name, you passed'), score == null ? resultStateText(state, needsReview: needsReview) : t('$score من $max', '$score of $max'))
            : passed == false
                ? (t('قربت$name', 'Almost there$name'), score == null ? resultStateText(state, needsReview: needsReview) : t('$score من $max', '$score of $max'))
                : (resultStateText(state, needsReview: needsReview), score == null ? null : t('$score من $max', '$score of $max'));
    final hero = AppHero(
      kicker: examTitle,
      title: appDigits(title),
      squiggle: visible && passed == true ? word : null,
      subtitle: sub == null ? null : appDigits(sub),
    );
    final cards = <Widget>[
      if (!visible)
        _PendingBlock(examTitle: examTitle, stateText: resultStateText(state, needsReview: needsReview), needsReview: needsReview, onDone: onDone)
      else
        ExamScoreCard(
          percentage: percentage,
          score: score,
          maxScore: max,
          passed: passed,
          needsReview: needsReview,
          stateText: resultStateText(state, needsReview: needsReview),
          memoryKey: 'exam.result.${result['attempt_id'] ?? examTitle}',
          onDone: onDone,
        ),
      if (visible && answers.isNotEmpty)
        _AnswersCard(answers: answers, appealLine: (a) => a.score == null || a.isVoided ? null : _appealLine(context, a.questionId, true))
      else if (visible && questions.isNotEmpty)
        AppCard(
          title: t('حسب السؤال', 'Per question'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, q) in questions.indexed) ...[
              if (i > 0) Divider(height: AppSpace.lg, thickness: AppBorder.hairline, color: context.colors.kit.line),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExamVerdictMark(verdict: q['score'] == null ? ExamVerdict.pending : examVerdictOf(score: (q['score'] as num?)?.toDouble(), max: (q['max'] as num?)?.toDouble())),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs),
                      // D-1131: the question's place on the paper (an older server sends none: the row's order)
                      child: Text(appDigits(t('السؤال ${q['position'] ?? i + 1}', 'Question ${q['position'] ?? i + 1}')), style: AppType.bodyStrong(context)),
                    ),
                    ?_appealLine(context, asInt(q['question_id']), q['score'] != null),
                  ]),
                ),
                const SizedBox(width: AppSpace.sm),
                // the mark sits at the row's end, in a smaller share that wraps rather than overflows
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Text(
                        q['score'] == null
                            ? t('قيد المراجعة', 'Under review')
                            : appDigits(q['max'] is num ? t('${fmtScore(q['score'])} من ${fmtScore(q['max'])}', '${fmtScore(q['score'])} of ${fmtScore(q['max'])}') : fmtScore(q['score'])),
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(
                            color: q['score'] == null ? context.colors.textMedium : context.colors.textDark,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
              ]),
            ],
          ]),
        ),
    ];
    return AppAreaScope(
      area: AppArea.exam,
      child: ExamPageWidth(
        width: AppWidth.reading,
        builder: (side) => ListView(padding: const EdgeInsets.only(bottom: AppSpace.xl), children: [
          AppHeroOverlap(
            hero: hero,
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.md), cards[i]],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The result before it is published: why and when it will appear, calm (a result is never an error).
class _PendingBlock extends StatelessWidget {
  const _PendingBlock({required this.examTitle, required this.stateText, required this.needsReview, this.onDone});
  final String examTitle;
  final String stateText;
  final bool needsReview;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: AppEmpty(
        icon: Icons.hourglass_top_rounded,
        title: stateText,
        message: needsReview
            ? t('بعض الإجابات تنتظر المعلم، والنتيجة تطلع لما تنتشر', 'Some answers wait for the teacher; the result shows once it is published')
            : t('النتيجة تطلع لما ينشرها المعلم', 'The result shows once the teacher publishes it'),
        actionLabel: onDone == null ? null : t('ارجع للدورة', 'Back to the course'),
        onAction: onDone,
      ),
    );
  }
}

/// The score card: the ring with the percentage and "your mark" inside, the outcome stamp on its edge, the marks and
/// the next step. A pass fires the burst once.
class ExamScoreCard extends StatefulWidget {
  const ExamScoreCard({super.key, required this.percentage, required this.score, required this.maxScore, required this.passed,
      this.needsReview = false, this.stateText, this.memoryKey, this.onDone});
  final double? percentage;
  final String? score;
  final String maxScore;
  final bool? passed;
  final bool needsReview;
  final String? stateText;
  final String? memoryKey;
  final VoidCallback? onDone;

  /// The ring of the result: the area's large ring.
  static const double ring = AppDashSize.ring + AppSpace.xxl;

  @override
  State<ExamScoreCard> createState() => _ExamScoreCardState();
}

class _ExamScoreCardState extends State<ExamScoreCard> {
  final _anchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.passed == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppBurst.fire(context, BurstMoment.examPassed, anchor: _anchor);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.colors.kit;
    final pct = widget.percentage;
    final passed = widget.passed;
    final tone = passed == true ? k.ok : (passed == false ? k.warn : AppAreaScope.of(context).tone);
    final figure = pct == null ? '—' : '${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%';
    final stamp = passed == null
        ? null
        : AppSlap(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(AppRadius.glyph),
                border: Border.all(color: tone.color, width: AppBorder.focus + AppBorder.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(passed ? Icons.check_rounded : Icons.replay_rounded, size: AppIconSize.sm, color: tone.ink),
                const SizedBox(width: AppSpace.xxs),
                Text(passed ? t('ناجح', 'Passed') : t('ما نجح', 'Not passed'),
                    style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: ExamScoreCard.ring + AppSpace.xxl,
          height: ExamScoreCard.ring + AppSpace.md,
          child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
            AppProgressRing(
              key: _anchor,
              value: ((pct ?? 0) / 100).clamp(0.0, 1.0),
              size: ExamScoreCard.ring,
              stroke: AppSpace.sm,
              tone: tone,
              showPercent: false,
              semanticLabel: figure,
            ),
            SizedBox(
              width: ExamScoreCard.ring - AppSpace.xl,
              height: ExamScoreCard.ring,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: pct == null
                        ? Text(figure, style: AppType.figureLarge(context))
                        : AppOdometer(appDigits(figure), memoryKey: widget.memoryKey, style: AppType.figureLarge(context)),
                  ),
                ),
                Text(t('درجتك', 'Your mark'), style: AppType.meta(context)),
              ]),
            ),
            if (stamp != null) PositionedDirectional(top: 0, start: 0, child: stamp),
          ]),
        ),
        AppSpace.gapMd,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.center, children: [
          AppStatusBadge(
              label: appDigits(widget.score == null ? t('الدرجة تنتظر المراجعة', 'The score awaits review') : t('${widget.score} من ${widget.maxScore}', '${widget.score} of ${widget.maxScore}')),
              tone: passed == true ? AppTone.success : AppTone.neutral),
          // the attempt's state ("Graded", "Submitted automatically …"): the hero carries it only when there is no
          // pass mark, so the card names it when the hero speaks of the outcome
          if (widget.stateText != null && passed != null) AppStatusBadge(label: widget.stateText!, tone: AppTone.neutral),
          if (widget.needsReview) AppStatusBadge(label: t('فيه إجابات عند المعلم', 'Some answers are with the teacher'), tone: AppTone.warning),
        ]),
        if (widget.onDone != null) ...[
          AppSpace.gapMd,
          passed == true
              ? AppButton.hot(label: t('كمّل الدورة', 'Continue the course'), icon: Icons.play_arrow_rounded, onPressed: widget.onDone)
              : AppButton.primary(label: t('ارجع للدورة', 'Back to the course'), onPressed: widget.onDone),
        ],
      ]),
    );
  }
}

/// "Your answers": one filter row, then every answer with its regrade line.
class _AnswersCard extends StatefulWidget {
  const _AnswersCard({required this.answers, required this.appealLine});
  final List<ResultAnswer> answers;
  final Widget? Function(ResultAnswer a) appealLine;

  @override
  State<_AnswersCard> createState() => _AnswersCardState();
}

class _AnswersCardState extends State<_AnswersCard> {
  ExamVerdict? _only;

  ExamVerdict _verdict(ResultAnswer a) => examVerdictOf(score: a.score, max: a.max, voided: a.isVoided);

  @override
  Widget build(BuildContext context) {
    final right = widget.answers.where((a) => _verdict(a) == ExamVerdict.correct).length;
    final shown = _only == null ? widget.answers : widget.answers.where((a) => _verdict(a) == _only).toList();
    final filters = <(ExamVerdict?, String)>[
      (null, t('الكل', 'All')),
      (ExamVerdict.correct, t('الصح', 'Right')),
      (ExamVerdict.wrong, t('الغلط', 'Wrong')),
      if (widget.answers.any((a) => _verdict(a) == ExamVerdict.partial)) (ExamVerdict.partial, t('جزئي', 'Partial')),
    ];
    return AppCard(
      title: t('إجاباتك', 'Your answers'),
      action: Text(appDigits(t('$right صح من ${widget.answers.length}', '$right right of ${widget.answers.length}')), style: AppType.meta(context)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final (v, label) in filters) AppChip(label: label, selected: _only == v, onTap: () => setState(() => _only = v)),
        ]),
        AppSpace.gapSm,
        for (final (i, a) in shown.indexed)
          AppReveal(index: i, group: 'exam.result', child: ResultAnswerCard(answer: a, footer: widget.appealLine(a))),
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

  /// "Question 3 · 2 / 5" from the result's own rows (D-1131 / D-1135), never the database id.
  String _questionLabel(int questionId) {
    for (final q in asMapList(widget.result['questions'])) {
      if (asInt(q['question_id']) != questionId || q['position'] == null) continue;
      final pos = asInt(q['position']);
      return t('السؤال $pos', 'Question $pos');
    }
    return t('السؤال', 'Question');
  }

  Future<void> _appeal(int questionId) async {
    final sent = await showAppSheet<bool>(context, (_) => StudentAppealSheet(
          questionLabel: _questionLabel(questionId),
          onSubmit: (reason) async {
            final r = await _api.appeal(_attemptId, questionId, reason);
            return r.ok ? null : appealCodeText(r.code, r.message);
          },
        ));
    if (sent == true) _load();
  }

  String? _firstName(BuildContext context) {
    final name = Provider.of<MyAuthProvider?>(context, listen: false)?.currentUser?.name.trim() ?? '';
    return name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey('exam.result'),
        appBar: AppHeader(title: t('نتيجة الاختبار', 'Exam result'), actions: const [HelpInfoButton(pageId: 'exam.result')]),
        child: ExamResultBody(result: widget.result, examTitle: widget.examTitle, appeals: _appeals, onAppeal: _canAppeal ? _appeal : null,
            firstName: _firstName(context), onDone: () => Navigator.maybePop(context)),
      );
}

/// A mark without a trailing ".0" (2.0 → "2", 2.5 → "2.5").
String fmtScore(Object? v) {
  final n = v is num ? v : num.tryParse('$v');
  if (n == null) return '$v';
  return n == n.roundToDouble() ? '${n.toInt()}' : n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}
