
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import '../../../teacher/analysis/exam/exam_model.dart';
import 'student_exam_provider.dart';
import 'student_exam_result_screen.dart';

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
  late Animation<double>  _fadeAnim;
  bool _slidingForward = true;

  // Timer pulse for critical seconds
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _slideAnim = Tween<Offset>(
        begin: const Offset(.15, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeIn);
    _slideCtrl.forward();

    _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
        lowerBound: 0.9,
        upperBound: 1.1)
      ..repeat(reverse: true);
    _pulseAnim = _pulseCtrl.drive(CurveTween(curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _animateTo(bool forward) {
    _slidingForward = forward;
    _slideCtrl.reset();
    _slideAnim = Tween<Offset>(
        begin: Offset(forward ? .15 : -.15, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  Future<bool> _confirmSubmit(BuildContext context) async {
    final prov = context.read<StudentExamProvider>();
    final s = prov.session!;
    final unanswered = s.questions.length - s.answeredCount;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: unanswered > 0
                      ? Colors.orange.withValues(alpha: .12)
                      : context.themeConfig.success.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  unanswered > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  color: unanswered > 0 ? Colors.orange : context.themeConfig.success,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                unanswered > 0 ? 'يوجد أسئلة بدون إجابة!' : 'هل أنت متأكد؟',
                style: const TextStyle(
                    fontFamily: 'bahji', fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                unanswered > 0
                    ? 'لم تجب على $unanswered سؤال. هل تريد التقديم الآن؟'
                    : 'ستُرسَل جميع إجاباتك ولن تتمكن من التعديل لاحقاً.',
                style: const TextStyle(
                    fontFamily: 'bahji', fontSize: 13, color: Colors.grey, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('إلغاء', style: TextStyle(fontFamily: 'bahji')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.themeConfig.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('تقديم',
                        style: TextStyle(fontFamily: 'bahji', color: Colors.white,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    return confirm == true;
  }

  void _showQuestionGrid(BuildContext context, QuizSession s) {
    showModalBottomSheet(
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
    final prov = context.watch<StudentExamProvider>();
    final s = prov.session;
    final c = context.colors;

    // Session might be null briefly on hot-reload — guard
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Navigate to result when submitted
    if (s.submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentExamResultScreen(
              session: s,
              onExit: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ),
        );
      });
    }

    final q = s.currentQuestion;
    final answered = s.answers[s.currentIndex];
    final isCritical = prov.timerCritical;
    final isWarning  = prov.timerWarning;

    final timerColor = isCritical
        ? Colors.redAccent
        : isWarning
        ? Colors.orange
        : c.primary;

    final progress = s.questions.isEmpty
        ? 0.0
        : s.answeredCount / s.questions.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final ok = await _confirmSubmit(context);
          if (ok && context.mounted) {
            await prov.submitExam();
          }
        },
        child: Scaffold(
          backgroundColor: c.background,
          body: SafeArea(
            child: Column(children: [
              // ── Header bar ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  Row(children: [
                    // Question counter
                    _CounterBadge(
                      current: s.currentIndex + 1,
                      total: s.questions.length,
                    ),
                    const Spacer(),

                    // Timer
                    GestureDetector(
                      onTap: () => _showQuestionGrid(context, s),
                      child: AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, child) => Transform.scale(
                          scale: isCritical ? _pulseAnim.value : 1.0,
                          child: child,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: timerColor.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: timerColor.withValues(alpha: .4)),
                          ),
                          child: Row(children: [
                            Icon(Icons.timer_rounded, size: 16, color: timerColor),
                            const SizedBox(width: 6),
                            Text(
                              prov.timerDisplay,
                              style: TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: timerColor,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Grid navigator
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _showQuestionGrid(context, s),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: c.primaryTint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.grid_view_rounded, color: c.primary, size: 20),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // ── Animated progress bar ────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: c.divider,
                      valueColor: AlwaysStoppedAnimation(c.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${s.answeredCount} / ${s.questions.length} مُجاب',
                          style: c.caption.copyWith(fontSize: 11)),
                      Text('${(progress * 100).toStringAsFixed(0)}%',
                          style: c.caption.copyWith(fontSize: 11, color: c.primary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ]),
              ),

              const SizedBox(height: 12),

              // ── Question card + options ───────────────────────────────────
              Expanded(
                child: SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Question card ──────────────────────────────
                          _QuestionCard(question: q, index: s.currentIndex),
                          const SizedBox(height: 16),

                          // ── Options ────────────────────────────────────
                          if (q.options.isNotEmpty)
                            ...q.options.asMap().entries.map((e) =>
                                _OptionTile(
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
                              initialValue: answered,
                              onChanged: prov.selectAnswer,
                            ),

                          const SizedBox(height: 100), // space for nav bar
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Bottom navigation bar ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  boxShadow: c.bottomNavShadow,
                ),
                child: Row(children: [
                  // Prev
                  _NavBtn(
                    icon: Icons.arrow_forward_ios_rounded,
                    enabled: !s.isFirst,
                    onTap: () {
                      _animateTo(false);
                      prov.prevQuestion();
                    },
                  ),
                  const SizedBox(width: 12),

                  // Submit / Next
                  Expanded(
                    child: s.isLast
                        ? _SubmitBtn(
                      loading: s.submitting,
                      onTap: () async {
                        final ok = await _confirmSubmit(context);
                        if (ok) await prov.submitExam();
                      },
                    )
                        : _NextBtn(
                      answered: answered != null,
                      onTap: () {
                        _animateTo(true);
                        prov.nextQuestion();
                      },
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(
          color: c.primary.withValues(alpha: .3), blurRadius: 10, offset: const Offset(0, 3),
        )],
      ),
      child: Text(
        'السؤال $current / $total',
        style: const TextStyle(
          fontFamily: 'bahji', fontSize: 13,
          fontWeight: FontWeight.w800, color: Colors.white,
        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary.withValues(alpha: .06), c.cardBg],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.primary.withValues(alpha: .15)),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Question number pill
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('السؤال ${index + 1}',
                style: const TextStyle(
                  fontFamily: 'bahji', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Colors.white,
                )),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${question.marks.toStringAsFixed(0)} درجة',
                style: TextStyle(
                  fontFamily: 'bahji', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Colors.amber.shade800,
                )),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          question.title,
          style: c.h3.copyWith(fontSize: 16, height: 1.7),
        ),
      ]),
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

  static const _letters = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letter = optionIndex < _letters.length ? _letters[optionIndex] : '${optionIndex + 1}';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: .06) : c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? c.primary : c.divider,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: c.primary.withValues(alpha: .15), blurRadius: 12, offset: const Offset(0, 4))]
              : c.cardShadow,
        ),
        child: Row(children: [
          // Letter circle
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: selected
                  ? c.primaryGradient
                  : const LinearGradient(colors: [Color(0xFFF5F5F5), Color(0xFFEEEEEE)]),
              shape: BoxShape.circle,
              boxShadow: selected
                  ? [BoxShadow(color: c.primary.withValues(alpha: .3), blurRadius: 8)]
                  : [],
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.primary : c.textDark,
                height: 1.5,
              ),
            ),
          ),
          if (selected)
            Icon(Icons.check_circle_rounded, color: c.primary, size: 20),
        ]),
      ),
    );
  }
}

// ── Text answer field ─────────────────────────────────────────────────────────

class _TextAnswerField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;
  const _TextAnswerField({required this.initialValue, required this.onChanged});

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
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        maxLines: 5,
        textDirection: TextDirection.rtl,
        style: TextStyle(fontFamily: 'bahji', fontSize: 14, color: c.textDark, height: 1.6),
        decoration: InputDecoration(
          hintText: 'اكتب إجابتك هنا…',
          hintStyle: c.caption,
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
  const _NavBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: enabled ? c.primaryTint : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: enabled ? c.primary.withValues(alpha: .3) : Colors.grey.shade200),
        ),
        child: Icon(icon, color: enabled ? c.primary : Colors.grey.shade400, size: 20),
      ),
    );
  }
}

class _NextBtn extends StatelessWidget {
  final bool answered;
  final VoidCallback onTap;
  const _NextBtn({required this.answered, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: answered ? c.primaryGradient : const LinearGradient(colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: answered
              ? [BoxShadow(color: c.primary.withValues(alpha: .3), blurRadius: 10, offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('السؤال التالي',
              style: TextStyle(
                fontFamily: 'bahji', fontSize: 14, fontWeight: FontWeight.w800,
                color: answered ? Colors.white : Colors.grey.shade500,
              )),
          const SizedBox(width: 6),
          Icon(Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: answered ? Colors.white : Colors.grey.shade500),
        ]),
      ),
    );
  }
}

class _SubmitBtn extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _SubmitBtn({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00A86B), Color(0xFF2ECC71)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00A86B).withValues(alpha: .4),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Center(
        child: loading
            ? const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.send_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('تقديم الاختبار',
              style: TextStyle(fontFamily: 'bahji', fontSize: 15,
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    ),
  );
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

    return Container(
      height: MediaQuery.of(context).size.height * .55,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 20)],
      ),
      child: Column(children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Text('الأسئلة', style: c.h2.copyWith(fontSize: 17)),
            const Spacer(),
            _LegendItem(color: c.primary, label: 'مُجاب'),
            const SizedBox(width: 14),
            _LegendItem(color: Colors.grey.shade200, label: 'غير مُجاب'),
          ]),
        ),

        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                        ? c.primaryGradient
                        : answered
                        ? LinearGradient(
                        colors: [c.primary.withValues(alpha: .2),
                          c.primary.withValues(alpha: .12)])
                        : const LinearGradient(colors: [Color(0xFFF5F5F5), Color(0xFFEEEEEE)]),
                    borderRadius: BorderRadius.circular(12),
                    border: isCurrent
                        ? Border.all(color: c.primary, width: 2)
                        : answered
                        ? Border.all(color: c.primary.withValues(alpha: .4))
                        : Border.all(color: Colors.grey.shade200),
                    boxShadow: isCurrent
                        ? [BoxShadow(color: c.primary.withValues(alpha: .3), blurRadius: 8)]
                        : [],
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: isCurrent
                              ? Colors.white
                              : answered
                              ? c.primary
                              : Colors.grey.shade500,
                        )),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 14, height: 14,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
    ),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontFamily: 'bahji', fontSize: 11, color: Colors.grey)),
  ]);
}