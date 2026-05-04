// features/student/exam/student_exam_quiz_screen.dart
//
// The active quiz: question cards, MCQ/open-ended input, timer, dot navigator,
// submit confirmation, and animated result screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'student_exam_provider.dart';
import 'student_exam_result_screen.dart';

class StudentExamQuizScreen extends StatelessWidget {
  const StudentExamQuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final s = prov.session;

    // ── Guards ────────────────────────────────────────────────────────────────
    if (s == null) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body:
              Center(child: Text('لا توجد جلسة اختبار نشطة')),
        ),
      );
    }

    if (s.submitting) return _buildSubmittingScreen();

    if (s.submitted) {
      return StudentExamResultScreen(
        session: s,
        onExit: () {
          prov.closeSession();
          Navigator.popUntil(context, (r) => r.isFirst);
        },
      );
    }

    return _buildQuizBody(context, prov, s);
  }

  // ── Submitting overlay ────────────────────────────────────────────────────

  Widget _buildSubmittingScreen() => const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('جارٍ إرسال إجاباتك...',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      color: Colors.grey)),
            ]),
          ),
        ),
      );

  // ── Main quiz body ────────────────────────────────────────────────────────

  Widget _buildQuizBody(
      BuildContext context, StudentExamProvider prov, QuizSession s) {
    final q = s.currentQuestion;
    final opts = q.options;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        // ── App bar with timer ──────────────────────────────────────────────
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            s.exam.name,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            _TimerChip(prov: prov),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(children: [
          // ── Progress ──────────────────────────────────────────────────────
          _ProgressBar(
            current: s.currentIndex + 1,
            total: s.questions.length,
            answered: s.answeredCount,
          ),

          // ── Question + options ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(children: [
                // Question card
                _QuestionCard(
                  index: s.currentIndex,
                  text: q.title,
                  marks: q.marks,
                ),
                const SizedBox(height: 16),

                // MCQ options
                if (opts.isNotEmpty)
                  ...opts.asMap().entries.map(
                        (e) => _McqOption(
                          text: e.value,
                          selected:
                              s.answers[s.currentIndex] == e.value,
                          onTap: () => context
                              .read<StudentExamProvider>()
                              .selectAnswer(e.value),
                        ),
                      )
                // Open-ended text area
                else
                  _OpenEndedField(
                    initialValue: s.answers[s.currentIndex],
                    onChanged: (v) => context
                        .read<StudentExamProvider>()
                        .selectAnswer(v),
                  ),

                // Question dot navigator
                const SizedBox(height: 20),
                _DotNavigator(session: s, prov: prov),
              ]),
            ),
          ),

          // ── Bottom nav bar ────────────────────────────────────────────────
          _BottomNavBar(session: s, prov: prov),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

class _TimerChip extends StatelessWidget {
  final StudentExamProvider prov;
  const _TimerChip({required this.prov});

  Color get _color => prov.timerCritical
      ? Colors.redAccent
      : prov.timerWarning
          ? Colors.orange
          : AppTheme.success;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_rounded, size: 15, color: _color),
          const SizedBox(width: 5),
          Text(
            prov.timerDisplay,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _color),
          ),
        ]),
      );
}

class _ProgressBar extends StatelessWidget {
  final int current, total, answered;
  const _ProgressBar(
      {required this.current,
      required this.total,
      required this.answered});

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('السؤال $current من $total',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.grey)),
                Text('$answered / $total تمت الإجابة',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.grey)),
              ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: current / total,
              backgroundColor: Colors.grey.shade100,
              color: context.colors.primary,
              minHeight: 6,
            ),
          ),
        ]),
      );
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final String text;
  final double marks;
  const _QuestionCard(
      {required this.index, required this.text, required this.marks});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10)
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Marks badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              '${marks.toInt()} درجات',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.5),
          ),
        ]),
      );
}

class _McqOption extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _McqOption(
      {required this.text,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.primary.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? context.colors.primary : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            // Radio circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? context.colors.primary : Colors.transparent,
                border: Border.all(
                    color:
                        selected ? context.colors.primary : Colors.grey.shade300,
                    width: 2),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selected ? context.colors.primary : Colors.black87),
              ),
            ),
          ]),
        ),
      );
}

class _OpenEndedField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;
  const _OpenEndedField(
      {required this.initialValue, required this.onChanged});

  @override
  State<_OpenEndedField> createState() => _OpenEndedFieldState();
}

class _OpenEndedFieldState extends State<_OpenEndedField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        textDirection: TextDirection.rtl,
        maxLines: 5,
        onChanged: (v) =>
            widget.onChanged(v.trim().isEmpty ? '' : v.trim()),
        decoration: InputDecoration(
          hintText: 'اكتب إجابتك هنا...',
          hintStyle: const TextStyle(
              fontFamily: 'Cairo', color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.colors.primary, width: 2)),
          contentPadding: const EdgeInsets.all(16),
        ),
      );
}

class _DotNavigator extends StatelessWidget {
  final QuizSession session;
  final StudentExamProvider prov;
  const _DotNavigator({required this.session, required this.prov});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: List.generate(session.questions.length, (i) {
          final answered = session.answers.containsKey(i);
          final isCurrent = i == session.currentIndex;

          return GestureDetector(
            onTap: () => prov.goToQuestion(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? context.colors.primary
                    : answered
                        ? context.colors.success.withValues(alpha: 0.12)
                        : Colors.white,
                border: Border.all(
                  color: isCurrent
                      ? context.colors.primary
                      : answered
                          ? context.colors.success
                          : Colors.grey.shade300,
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isCurrent
                        ? Colors.white
                        : answered
                            ? context.colors.success
                            : Colors.grey,
                  ),
                ),
              ),
            ),
          );
        }),
      );
}

class _BottomNavBar extends StatelessWidget {
  final QuizSession session;
  final StudentExamProvider prov;
  const _BottomNavBar({required this.session, required this.prov});

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        child: Row(children: [
          // Prev
          if (!session.isFirst)
            OutlinedButton.icon(
              onPressed: prov.prevQuestion,
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              label: const Text('السابق',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),

          const Spacer(),

          // Next or Submit
          if (!session.isLast)
            ElevatedButton.icon(
              onPressed: prov.nextQuestion,
              icon: const Text('التالي',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              label: const Icon(Icons.arrow_back_ios_rounded, size: 14),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _confirmSubmit(context, prov, session),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('تسليم الاختبار',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
            ),
        ]),
      );

  void _confirmSubmit(BuildContext context, StudentExamProvider prov,
      QuizSession session) {
    final unanswered =
        session.questions.length - session.answeredCount;
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          title: const Text('تسليم الاختبار',
              style: TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Text(
            unanswered > 0
                ? 'لم تجب على $unanswered سؤال بعد. هل أنت متأكد من التسليم؟'
                : 'هل تريد تسليم إجاباتك الآن؟',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                prov.submitExam();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('تأكيد التسليم',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
