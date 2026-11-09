// student_exam_quiz_screen.dart — Premium redesign (analytics style)
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import '../../../shared/models/exam_model.dart';
import 'student_exam_provider.dart';
import 'student_exam_result_screen.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'exam_tr.dart';
import 'exam_ui.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;

class StudentExamQuizScreen extends StatefulWidget {
  const StudentExamQuizScreen({super.key});

  @override
  State<StudentExamQuizScreen> createState() => _StudentExamQuizScreenState();
}

class _StudentExamQuizScreenState extends State<StudentExamQuizScreen>
    with TickerProviderStateMixin {
  // Slide animation between questions
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  // Guards against pushing the result screen more than once.
  bool _navigatedToResult = false;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeIn);
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _animateTo(bool forward) {
    _slideCtrl.reset();
    _slideAnim = Tween<Offset>(
      begin: Offset(forward ? .15 : -.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  Future<bool> _confirmSubmit(BuildContext context) async {
    final prov = context.read<StudentExamProvider>();
    final s = prov.session!;
    final unanswered = s.questions.length - s.answeredCount;
    final warn = unanswered > 0;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => Directionality(
        textDirection: Helpers.pageDirection,
        child: Dialog(
          backgroundColor: dctx.colors.cardBg,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTile(
                    warn
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                    warn ? context.colors.warning : dctx.colors.success,
                    size: 68,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    warn
                        ? tx('exam_quiz_unanswered_title')
                        : tx('exam_quiz_confirm_title'),
                    textAlign: TextAlign.center,
                    style: examT(18, w: FontWeight.w800, c: dctx.colors.textDark),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    warn
                        ? tx('exam_quiz_unanswered_msg', {'count': unanswered})
                        : tx('exam_quiz_confirm_msg'),
                    textAlign: TextAlign.center,
                    style: examT(13, c: dctx.colors.textMedium, h: 1.7),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SoftButton(
                          label: tx('exam_cancel'),
                          onTap: () => Navigator.pop(dctx, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: tx('exam_quiz_submit_short'),
                          height: 50,
                          onTap: () => Navigator.pop(dctx, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return confirm == true;
  }

  void _showQuestionGrid(BuildContext context, QuizSession s) {
    showAppModalSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<StudentExamProvider>(),
        child: _QuestionGridSheet(session: s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppShellNav.markFullScreen(context); // a sitting: no tab bar even when opened inside a tab (D-081)
    final prov = context.watch<StudentExamProvider>();
    final s = prov.session;
    final c = context.colors;

    // Session might be null briefly on hot-reload — guard
    if (s == null) {
      return const BasePage( useWebCard: true,width: AppWidth.reading, child: AppListSkeleton(items: 4, withAvatar: false));
    }

    // Navigate to the result screen once, right after submitting.
    if (s.submitted && !_navigatedToResult) {
      _navigatedToResult = true;
      final nav = Navigator.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        nav.pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: prov,
              child: StudentExamResultScreen(
                session: s,
                onExit: () {
                  // Pop the result screen (back to the course / exam list).
                  nav.pop();
                  prov.closeSession();
                },
              ),
            ),
          ),
        );
      });
    }

    final q = s.currentQuestion;
    final answered = s.answers[s.currentIndex];
    final progress =
    s.questions.isEmpty ? 0.0 : s.answeredCount / s.questions.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmSubmit(context);
        if (ok && context.mounted) {
          await prov.submitExam();
        }
      },
      child: BasePage(
        useWebCard: true,
        width: AppWidth.reading,
        child: Column(
          children: [
            // ── Header card ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: c.heroShade.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _showQuestionGrid(context, s),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: c.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(Icons.grid_view_rounded,
                                  color: c.primary, size: 21),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _TimerChip(
                            prov: prov,
                            onTap: () => _showQuestionGrid(context, s),
                          ),
                          const Spacer(),
                          _CounterBadge(
                            current: s.currentIndex + 1,
                            total: s.questions.length,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ExamBar(pct: progress * 100, color: c.primary, height: 8),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tx('exam_quiz_answered_progress', {
                              'answered': s.answeredCount,
                              'total': s.questions.length,
                            }),
                            style: examT(11, c: c.textMedium),
                          ),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: examT(11, w: FontWeight.w800, c: c.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Question card + options ─────────────────────────────────
            Expanded(
              child: SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _QuestionCard(question: q, index: s.currentIndex),
                        const SizedBox(height: 16),
                        if (q.options.isNotEmpty)
                          ...q.options.asMap().entries.map(
                                (e) => _OptionTile(
                              label: e.value.toString(),
                              optionIndex: e.key,
                              selected: answered == e.value.toString(),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                prov.selectAnswer(e.value.toString());
                              },
                            ),
                          )
                        else
                          _TextAnswerField(
                            // New key per question so the field resets.
                            key: ValueKey(s.currentIndex),
                            initialValue: answered,
                            onChanged: prov.selectAnswer,
                          ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom navigation bar ───────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: c.heroShade.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                        child: s.isLast
                            ? GradientButton(
                          loading: s.submitting,
                          loader: const SizedBox(
                              height: 22,
                              width: 22,
                              child: AppLoadingIndicator(showLogo: false)),
                          label: tx('exam_quiz_submit'),
                          icon: Icons.send_rounded,
                          color: c.success,
                          height: 52,
                          onTap: () async {
                            final ok = await _confirmSubmit(context);
                            if (ok) await prov.submitExam();
                          },
                        )
                            : GradientButton(
                          label: tx('exam_quiz_next'),
                          icon: Icons.arrow_forward_ios_rounded,
                          height: 52,
                          onTap: () {
                            _animateTo(true);
                            prov.nextQuestion();
                          },
                        )
                    ),
                    const SizedBox(width: 12),
                    _NavBtn(
                      icon: Icons.arrow_forward_ios_rounded,
                      enabled: !s.isFirst,
                      onTap: () {
                        _animateTo(false);
                        prov.prevQuestion();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Timer chip ────────────────────────────────────────────────────────────────
// Rebuilds only itself every second; pulses only while the time is critical.

class _TimerChip extends StatefulWidget {
  final StudentExamProvider prov;
  final VoidCallback onTap;

  const _TimerChip({required this.prov, required this.onTap});

  @override
  State<_TimerChip> createState() => _TimerChipState();
}

class _TimerChipState extends State<_TimerChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    lowerBound: 0.92,
    upperBound: 1.08,
    value: 1.0,
  );
  bool _pulsing = false;

  @override
  void initState() {
    super.initState();
    widget.prov.secondsLeftNotifier.addListener(_syncPulse);
    _syncPulse();
  }

  void _syncPulse() {
    final critical = widget.prov.timerCritical;
    if (critical && !_pulsing) {
      _pulsing = true;
      _pulse.repeat(reverse: true);
    } else if (!critical && _pulsing) {
      _pulsing = false;
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    widget.prov.secondsLeftNotifier.removeListener(_syncPulse);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<int>(
      valueListenable: widget.prov.secondsLeftNotifier,
      builder: (context, secs, _) {
        final critical = secs < 120;
        final warning = secs < 300 && !critical;
        final color = critical
            ? context.colors.danger
            : warning
            ? context.colors.warning
            : c.primary;
        final text =
            '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
        return GestureDetector(
          onTap: widget.onTap,
          child: ScaleTransition(
            scale: _pulse,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: .35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_rounded, size: 17, color: color),
                  const SizedBox(width: 6),
                  Text(text, style: examT(15, w: FontWeight.w800, c: color)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Counter badge ─────────────────────────────────────────────────────────────

class _CounterBadge extends StatelessWidget {
  final int current, total;

  const _CounterBadge({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [context.colors.primaryDark, c.primary]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: .3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        tx('exam_quiz_counter', {'current': current, 'total': total}),
        style: examT(12.5, w: FontWeight.w800, c: context.colors.onHero),
      ),
    );
  }
}

// ── Question card ─────────────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final Question question;
  final int index;

  const _QuestionCard({required this.question, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExamCard(
      radius: 22,
      borderColor: c.primary.withValues(alpha: .16),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [context.colors.primaryDark, c.primary]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tx('exam_question_n', {'n': index + 1}),
                  style: examT(11.5, w: FontWeight.w700, c: context.colors.onHero),
                ),
              ),
              const Spacer(),
              ExamChip(
                Icons.grade_rounded,
                tx('exam_n_marks', {'n': question.marks.toStringAsFixed(0)}),
                context.colors.warning,
              ),
              const SizedBox(width: 6),
              _ReviewFlagButton(question: question),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: Text(
              question.title,
              textDirection: Helpers.textDirOf(question.title),
              textAlign: TextAlign.start,
              style: examT(16.5, w: FontWeight.w700, c: c.textDark, h: 1.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Review-flag (bookmark) button ─────────────────────────────────────────────

class _ReviewFlagButton extends StatelessWidget {
  final Question question;
  const _ReviewFlagButton({required this.question});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    if (!prov.reviewFlagsEnabled) return const SizedBox.shrink();
    final flagged = prov.isReviewFlagged(question.id);
    final color = flagged ? context.colors.danger : context.colors.textLight;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: prov.flagBusy
          ? null
          : () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final wasFlagged = flagged;
        final err = await prov.toggleReviewFlag(question);
        messenger?.hideCurrentSnackBar();
        showAppNotice(err ??
                (wasFlagged
                    ? tx('flag_review_removed')
                    : tx('flag_review_added')));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            flagged ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            flagged ? tx('flag_review_marked') : tx('flag_review_mark'),
            style: examT(11, w: FontWeight.w700, c: color),
          ),
        ]),
      ),
    );
  }
}

// ── Option tile ───────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String label;
  final int optionIndex;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.optionIndex,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letters = tx('exam_option_letters').split(',');
    final letter =
    optionIndex < letters.length ? letters[optionIndex] : '${optionIndex + 1}';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: .07) : c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.primary : c.divider.withValues(alpha: .7),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: c.primary.withValues(alpha: .16),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ]
              : [
            BoxShadow(
              color: c.heroShade.withValues(alpha: .04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: selected
                    ? LinearGradient(colors: [context.colors.primaryDark, c.primary])
                    : null,
                color: selected ? null : c.divider.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: examT(14,
                      w: FontWeight.w800,
                      c: selected ? context.colors.onHero : c.textMedium),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                textDirection: Helpers.textDirOf(label),
                textAlign: TextAlign.start,
                style: examT(14.5,
                    w: selected ? FontWeight.w700 : FontWeight.w500,
                    c: selected ? c.primary : c.textDark,
                    h: 1.55),
              ),
            ),
            AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: selected ? 1 : 0,
              child: Icon(Icons.check_circle_rounded, color: c.primary, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text answer field ─────────────────────────────────────────────────────────

class _TextAnswerField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;

  const _TextAnswerField(
      {super.key, required this.initialValue, required this.onChanged});

  @override
  State<_TextAnswerField> createState() => _TextAnswerFieldState();
}

class _TextAnswerFieldState extends State<_TextAnswerField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExamCard(
      radius: 18,
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        maxLines: 6,
        textDirection: Directionality.of(context),
        style: examT(14.5, c: c.textDark, h: 1.7),
        decoration: InputDecoration(
          hintText: tx('exam_quiz_answer_hint'),
          hintStyle: examT(14, c: c.textMedium),
          contentPadding: const EdgeInsets.all(18),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

// ── Navigation buttons ────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? c.primary.withValues(alpha: .10) : c.divider.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? c.primary.withValues(alpha: .3) : c.divider,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? c.primary : c.textMedium.withValues(alpha: .4),
          size: 20,
        ),
      ),
    );
  }
}

// ── Question grid bottom sheet ────────────────────────────────────────────────

class _QuestionGridSheet extends StatelessWidget {
  final QuizSession session;

  const _QuestionGridSheet({required this.session});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final s = prov.session ?? session;
    final c = context.colors;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Container(
        height: MediaQuery.of(context).size.height * .6,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
                color: c.heroShade.withValues(alpha: .1), blurRadius: 24),
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.grid_view_rounded, size: 19, color: c.primary),
                  const SizedBox(width: 8),
                  Text(tx('exam_quiz_questions'),
                      style: examT(16.5, w: FontWeight.w800, c: c.textDark)),
                  const Spacer(),
                  _LegendItem(color: c.primary, label: tx('exam_answered')),
                  const SizedBox(width: 14),
                  _LegendItem(
                    color: c.divider,
                    label: tx('exam_unanswered'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: ExamBar(
                pct: s.questions.isEmpty
                    ? 0
                    : s.answeredCount * 100 / s.questions.length,
                color: c.primary,
                height: 6,
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemCount: s.questions.length,
                itemBuilder: (_, i) {
                  final answered = s.answers.containsKey(i);
                  final isCurrent = i == s.currentIndex;
                  return GestureDetector(
                    onTap: () {
                      prov.goToQuestion(i);
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: isCurrent
                            ? LinearGradient(colors: [context.colors.primaryDark, c.primary])
                            : null,
                        color: isCurrent
                            ? null
                            : answered
                            ? c.primary.withValues(alpha: .13)
                            : c.divider.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrent
                              ? c.primary
                              : answered
                              ? c.primary.withValues(alpha: .4)
                              : c.divider,
                          width: isCurrent ? 2 : 1,
                        ),
                        boxShadow: isCurrent
                            ? [
                          BoxShadow(
                            color: c.primary.withValues(alpha: .3),
                            blurRadius: 10,
                          ),
                        ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: examT(
                            14,
                            w: FontWeight.w800,
                            c: isCurrent
                                ? context.colors.onHero
                                : answered
                                ? c.primary
                                : c.textMedium,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: examT(11, c: context.colors.textMedium)),
    ],
  );
}