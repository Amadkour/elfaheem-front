import 'package:flutter_education_app/core/api_error_text.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/api_client.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../shared/models/exam_model.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'exam_ui.dart';

String _fmt(String key, Map<String, Object?> params) =>
    examFill(key.tr, params);

// ── Entry point: passcode gate ───────────────────────────────────────────────
class StudentExamEntryScreen extends StatefulWidget {
  final ExamModel exam;

  const StudentExamEntryScreen({super.key, required this.exam});

  @override
  State<StudentExamEntryScreen> createState() => _StudentExamEntryScreenState();
}

class _StudentExamEntryScreenState extends State<StudentExamEntryScreen> {
  final _passcodeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _needsPasscode =>
      widget.exam.passcode != null && widget.exam.passcode!.isNotEmpty;

  Future<void> _enter() async {
    if (_needsPasscode && _passcodeCtrl.text.trim().isEmpty) {
      if (mounted) setState(() => _error = 'passcode_required'.tr);
      return;
    }
    if (_needsPasscode && _passcodeCtrl.text.trim() != widget.exam.passcode) {
      if (mounted) setState(() => _error = 'wrong_passcode'.tr);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Fetch actual questions from server before entering the quiz
    try {
      final data =
      await ApiClient().get('/api/v1/exams/${widget.exam.id}/questions');
      if (!mounted) return;
      final questions = (data as List)
          .map((q) => Question.fromJson(q as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      if (questions.isEmpty) {
        setState(() {
          _error = 'exam_err_no_questions'.tr;
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              StudentExamQuizScreen(exam: widget.exam, questions: questions),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'exam_load_questions_failed'.tr;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _passcodeCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exam = widget.exam;
    final isScheduled =
        exam.startDate != null && exam.startDate!.isAfter(DateTime.now());

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage( useWebCard: true,maxWith: 1100, child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(children: [
            ExamHero(
              child: Column(children: [
                ExamHeroBar(title: 'enter_exam'.tr),
                const SizedBox(height: 20),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: c.onHero.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.onHeroFaint, width: 2),
                  ),
                  child: Icon(Icons.quiz_rounded,
                      color: c.onHero, size: 42),
                ),
                const SizedBox(height: 14),
                Text(exam.name,
                    textAlign: TextAlign.center,
                    style:
                    examT(20, w: FontWeight.w800, c: context.colors.onHero, h: 1.4)),
                if (exam.description != null) ...[
                  const SizedBox(height: 8),
                  Text(exam.description!,
                      textAlign: TextAlign.center,
                      style: examT(12.5, c: c.onHeroMuted, h: 1.6)),
                ],
                const SizedBox(height: 18),
                Row(children: [
                  HeroStat(
                    icon: Icons.timer_outlined,
                    color: context.colors.primaryLight,
                    value: _fmt('exam_n_minutes', {'n': exam.duration ?? 0}),
                    label: 'exam_exam_duration'.tr,
                  ),
                  const SizedBox(width: 10),
                  HeroStat(
                    icon: Icons.star_rounded,
                    color: context.colors.accent,
                    value: '${exam.passingScore?.toInt() ?? 0}%',
                    label: 'exam_passing_score'.tr,
                  ),
                  const SizedBox(width: 10),
                  HeroStat(
                    icon: Icons.help_outline_rounded,
                    color: c.success,
                    value: '${exam.questionCount}',
                    label: 'exam_question_count'.tr,
                  ),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(children: [
                if (exam.startDate != null) ...[
                  ExamCard(
                    padding: const EdgeInsets.all(16),
                    child: ExamInfoRow(Icons.schedule_rounded,
                        'exam_start_time'.tr, _fmtDate(exam.startDate!), context.colors.warning),
                  ),
                  const SizedBox(height: 16),
                ],
                if (isScheduled)
                  _CountdownBanner(target: exam.startDate!)
                else ...[
                  if (_needsPasscode) ...[
                    ExamSectionCard(
                      icon: Icons.lock_outline_rounded,
                      title: 'exam_passcode'.tr,
                      child: TextField(
                        controller: _passcodeCtrl,
                        textAlign: TextAlign.center,
                        obscureText: true,
                        style: examT(20, w: FontWeight.w700, c: c.textDark)
                            .copyWith(letterSpacing: 6),
                        decoration: InputDecoration(
                          hintText: '••••••',
                          errorText: _error,
                          filled: true,
                          fillColor: c.primary.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: c.divider.withValues(alpha: 0.8))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                              BorderSide(color: c.primary, width: 1.6)),
                          prefixIcon: Icon(Icons.lock_outline_rounded,
                              color: c.textMedium),
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onSubmitted: (_) => _enter(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null && !_needsPasscode) ...[
                    ExamBanner(
                        icon: Icons.error_outline_rounded,
                        color: context.colors.danger,
                        text: _error!),
                    const SizedBox(height: 16),
                  ],
                  ExamBanner(
                      icon: Icons.warning_amber_rounded,
                      color: context.colors.warning,
                      text: 'exam_warning'.tr),
                  const SizedBox(height: 18),
                  GradientButton(
                    loading: _loading,
                    loader: const SizedBox(
                        width: 24, height: 24, child: AppLoadingIndicator()),
                    label: 'exam_start_now'.tr,
                    icon: Icons.play_arrow_rounded,
                    onTap: _enter,
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Live Quiz Screen ─────────────────────────────────────────────────────────
class StudentExamQuizScreen extends StatefulWidget {
  final ExamModel exam;
  final List<Question> questions;

  const StudentExamQuizScreen(
      {super.key, required this.exam, required this.questions});

  @override
  State<StudentExamQuizScreen> createState() => _StudentExamQuizScreenState();
}

class _StudentExamQuizScreenState extends State<StudentExamQuizScreen> {
  int _current = 0;

  // Maps question index → chosen answer string
  final Map<int, String?> _answers = {};
  late Timer _timer;
  late int _secondsLeft;
  bool _submitting = false;
  bool _submitted = false;
  String? _submitError;

  // Stores the server result after submission
  Map<String, dynamic>? _serverResult;
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _secondsLeft = (widget.exam.duration ?? 60) * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) {
        _submitExam();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  // ── API: Submit all answers ───────────────────────────────────────────
  Future<void> _submitExam() async {
    _timer.cancel();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      // Submit each answered question; unanswered ones are skipped
      for (int i = 0; i < widget.questions.length; i++) {
        final answer = _answers[i];
        if (answer == null) continue;
        final q = widget.questions[i];
        await _api.post('/api/v1/exam-answers', body: {
          'exam_id': widget.exam.id,
          'question_id': q.id,
          'answer': answer,
        });
      }

      // Fetch own result from the server
      final result = await _api.get('/api/v1/exams/${widget.exam.id}/results');
      if (!mounted) return;
      setState(() {
        _serverResult = result is Map<String, dynamic> ? result : null;
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Even on error we mark submitted so they see a result screen
      setState(() {
        _submitError = apiErrorText(ApiException.from(e));
        _submitting = false;
        _submitted = true;
      });
    }
  }

  void _next() {
    if (_current < widget.questions.length - 1 && mounted) {
      setState(() => _current++);
    }
  }

  void _prev() {
    if (_current > 0 && mounted) setState(() => _current--);
  }

  String get _timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor => _secondsLeft < 120
      ? context.colors.danger
      : _secondsLeft < 300
      ? context.colors.warning
      : context.colors.primary;

  int get _answeredCount => _answers.values.where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    AppShellNav.markFullScreen(context); // a sitting: no tab bar even when opened inside a tab (D-081)
    final c = context.colors;

    if (_submitting) {
      return Directionality(
        textDirection: Helpers.pageDirection,
        child: Scaffold(
          backgroundColor: c.background,
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppLoadingIndicator(),
              const SizedBox(height: 20),
              Text('exam_sending_answers'.tr,
                  style: examT(15, w: FontWeight.w700, c: c.textMedium)),
            ]),
          ),
        ),
      );
    }
    if (_submitted) return _buildResultScreen();

    final q = widget.questions[_current];
    final opts = q.options;
    final total = widget.questions.length;
    final progress = total == 0 ? 0.0 : _answeredCount / total;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(children: [
          // ── Header ────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                    color: c.heroShade.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: Text(widget.exam.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: examT(15, w: FontWeight.w800, c: c.textDark)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: _timerColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _timerColor.withValues(alpha: 0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.timer_rounded, size: 17, color: _timerColor),
                        const SizedBox(width: 6),
                        Text(_timerDisplay,
                            style: examT(15,
                                w: FontWeight.w800, c: _timerColor)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  ExamBar(pct: progress * 100, color: c.primary, height: 8),
                  const SizedBox(height: 6),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            _fmt('exam_quiz_counter',
                                {'current': _current + 1, 'total': total}),
                            style: examT(11, c: c.textMedium)),
                        Text(
                            _fmt('exam_quiz_answered_progress', {
                              'answered': _answeredCount,
                              'total': total
                            }),
                            style: examT(11, c: c.textMedium)),
                      ]),
                ]),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExamCard(
                      radius: 22,
                      borderColor: c.primary.withValues(alpha: 0.16),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExamChip(
                                Icons.grade_rounded,
                                _fmt('exam_n_marks',
                                    {'n': q.marks.toInt()}),
                                context.colors.warning),
                            const SizedBox(height: 14),
                            Text(q.title,
                                textDirection: Helpers.textDirOf(q.title),
                                style: examT(17,
                                    w: FontWeight.w700,
                                    c: c.textDark,
                                    h: 1.7)),
                          ]),
                    ),
                    const SizedBox(height: 16),

                    if (opts.isNotEmpty)
                      ...List.generate(opts.length, (i) {
                        final opt = opts[i];
                        final selected = _answers[_current] == opt;
                        return GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() => _answers[_current] = opt);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? c.primary.withValues(alpha: 0.07)
                                  : c.cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selected
                                    ? c.primary
                                    : c.divider.withValues(alpha: 0.7),
                                width: selected ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: selected
                                        ? c.primary.withValues(alpha: 0.16)
                                        : c.heroShade.withValues(alpha: 0.04),
                                    blurRadius: selected ? 14 : 10,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Row(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: selected
                                      ? LinearGradient(
                                      colors: [context.colors.primaryDark, c.primary])
                                      : null,
                                  color: selected
                                      ? null
                                      : c.divider.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text('${i + 1}',
                                      style: examT(14,
                                          w: FontWeight.w800,
                                          c: selected
                                              ? context.colors.onHero
                                              : c.textMedium)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(opt,
                                      textDirection: Helpers.textDirOf(opt),
                                      style: examT(14.5,
                                          w: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          c: selected
                                              ? c.primary
                                              : c.textDark,
                                          h: 1.55))),
                            ]),
                          ),
                        );
                      })
                    else
                      ExamCard(
                        radius: 18,
                        child: TextField(
                          key: ValueKey(_current),
                          controller:
                          TextEditingController(text: _answers[_current]),
                          maxLines: 5,
                          onChanged: (v) => _answers[_current] =
                          v.trim().isEmpty ? null : v.trim(),
                          style: examT(14.5, c: c.textDark, h: 1.7),
                          decoration: InputDecoration(
                            hintText: 'exam_quiz_answer_hint'.tr,
                            hintStyle: examT(14, c: c.textMedium),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(18),
                          ),
                        ),
                      ),

                    // Navigator dots
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(total, (i) {
                        final answered = _answers[i] != null;
                        final isCurrent = i == _current;
                        return GestureDetector(
                          onTap: () {
                            if (mounted) setState(() => _current = i);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: isCurrent
                                  ? LinearGradient(colors: [context.colors.primaryDark, c.primary])
                                  : null,
                              color: isCurrent
                                  ? null
                                  : answered
                                  ? c.success.withValues(alpha: 0.13)
                                  : c.divider.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent
                                    ? c.primary
                                    : answered
                                    ? c.success
                                    : c.divider,
                              ),
                            ),
                            child: Center(
                                child: Text('${i + 1}',
                                    style: examT(12,
                                        w: FontWeight.w700,
                                        c: isCurrent
                                            ? context.colors.onHero
                                            : answered
                                            ? c.success
                                            : c.textMedium))),
                          ),
                        );
                      }),
                    ),
                  ]),
            ),
          ),

          // Navigation bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                    color: c.heroShade.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(children: [
                if (_current > 0) ...[
                  SizedBox(
                    width: 120,
                    child: SoftButton(
                        label: 'previous_question'.tr, onTap: _prev),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _current < total - 1
                      ? GradientButton(
                      label: 'next_question'.tr,
                      icon: Icons.arrow_forward_ios_rounded,
                      height: 50,
                      onTap: _next)
                      : GradientButton(
                      label: 'submit_exam'.tr,
                      icon: Icons.send_rounded,
                      color: c.success,
                      height: 50,
                      onTap: _showSubmitDialog),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  void _showSubmitDialog() {
    showDialog(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: Helpers.pageDirection,
        child: Dialog(
          backgroundColor: dctx.colors.cardBg,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconTile(
                  _answeredCount < widget.questions.length
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  _answeredCount < widget.questions.length
                      ? context.colors.warning
                      : dctx.colors.success,
                  size: 68,
                ),
                const SizedBox(height: 18),
                Text('submit_exam'.tr,
                    style: examT(18,
                        w: FontWeight.w800, c: dctx.colors.textDark)),
                const SizedBox(height: 10),
                Text(
                  _answeredCount < widget.questions.length
                      ? _fmt('exam_quiz_unanswered_msg', {
                    'count': widget.questions.length - _answeredCount
                  })
                      : 'submit_confirm_all_answered'.tr,
                  textAlign: TextAlign.center,
                  style: examT(13, c: dctx.colors.textMedium, h: 1.7),
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: SoftButton(
                        label: 'exam_cancel'.tr,
                        onTap: () => Navigator.pop(dctx)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'confirm_submit'.tr,
                      height: 50,
                      color: dctx.colors.success,
                      onTap: () {
                        Navigator.pop(dctx);
                        _submitExam();
                      },
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultScreen() {
    final c = context.colors;
    // Use server result if available; fallback to local calculation
    final pct = (_serverResult?['percentage'] as num?)?.toDouble() ??
        (_answeredCount == 0
            ? 0.0
            : (_answers.length / widget.questions.length * 100));
    final passed = _serverResult?['passed'] as bool? ??
        pct >= (widget.exam.passingScore ?? 60);
    final marksObtained =
    (_serverResult?['marks_obtained'] as num?)?.toDouble();
    final totalMarks = (_serverResult?['total_marks'] as num?)?.toDouble() ??
        widget.questions.fold(0.0, (s, q) => (s ?? 0) + q.marks);
    final accent = passed ? c.success : context.colors.danger;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(children: [
            ExamHero(
              colors: [Color.lerp(accent, context.colors.heroShade, .35)!, accent],
              child: Column(children: [
                ExamHeroBar(title: 'exam_result'.tr, showBack: false),
                const SizedBox(height: 22),
                ExamRing(
                  value: pct,
                  size: 140,
                  center: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${pct.toStringAsFixed(0)}%',
                        style: examT(32, w: FontWeight.w800, c: context.colors.onHero)),
                    Text(
                        passed
                            ? 'exam_passed_mark'.tr
                            : 'exam_failed_mark'.tr,
                        style: examT(13, c: c.onHeroMuted)),
                  ]),
                ),
                const SizedBox(height: 16),
                Text(
                  passed ? 'congratulations_passed'.tr : 'sorry_failed'.tr,
                  textAlign: TextAlign.center,
                  style: examT(17, w: FontWeight.w800, c: context.colors.onHero, h: 1.5),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(children: [
                if (_submitError != null) ...[
                  ExamBanner(
                    icon: Icons.warning_amber_rounded,
                    color: context.colors.warning,
                    text: _fmt('exam_submit_partial_error',
                        {'error': _submitError}),
                  ),
                  const SizedBox(height: 16),
                ],
                ExamCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    ExamInfoRow(
                      Icons.grade_rounded,
                      'your_score'.tr,
                      marksObtained != null
                          ? '${marksObtained.toStringAsFixed(0)} / ${totalMarks?.toStringAsFixed(0)}'
                          : _fmt('exam_answers_count', {
                        'answered': _answeredCount,
                        'total': widget.questions.length
                      }),
                      c.primary,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                          height: 1, color: c.divider.withValues(alpha: 0.6)),
                    ),
                    ExamInfoRow(
                        Icons.task_alt_rounded,
                        'questions_answered'.tr,
                        '$_answeredCount / ${widget.questions.length}',
                        context.colors.success),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                          height: 1, color: c.divider.withValues(alpha: 0.6)),
                    ),
                    ExamInfoRow(
                        Icons.star_rounded,
                        'exam_passing_score'.tr,
                        '${widget.exam.passingScore?.toInt() ?? 60}%',
                        context.colors.warning),
                  ]),
                ),
                const SizedBox(height: 22),
                GradientButton(
                  label: 'back_to_home'.tr,
                  icon: Icons.home_rounded,
                  onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CountdownBanner extends StatefulWidget {
  final DateTime target;

  const _CountdownBanner({required this.target});

  @override
  State<_CountdownBanner> createState() => _CountdownBannerState();
}

class _CountdownBannerState extends State<_CountdownBanner> {
  late final Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final r = widget.target.difference(DateTime.now());
    setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Widget _box(String v, String label) => Column(children: [
    Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.warning.withValues(alpha: 0.25)),
      ),
      child: Center(
          child: Text(v, style: examT(24, w: FontWeight.w900, c: context.colors.warning))),
    ),
    const SizedBox(height: 6),
    Text(label, style: examT(11, c: context.colors.textMedium)),
  ]);

  Widget get _colon => Padding(
    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 22),
    child: Text(':', style: examT(26, w: FontWeight.w900, c: context.colors.warning)),
  );

  @override
  Widget build(BuildContext context) => ExamSectionCard(
    icon: Icons.hourglass_top_rounded,
    accent: context.colors.warning,
    title: 'exam_starts_in'.tr,
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _box(_remaining.inHours.toString().padLeft(2, '0'),
          'exam_hours'.tr),
      _colon,
      _box((_remaining.inMinutes % 60).toString().padLeft(2, '0'),
          'exam_minutes'.tr),
      _colon,
      _box((_remaining.inSeconds % 60).toString().padLeft(2, '0'),
          'exam_seconds'.tr),
    ]),
  );
}