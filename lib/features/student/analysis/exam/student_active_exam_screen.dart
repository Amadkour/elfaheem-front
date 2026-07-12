import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/api_client.dart';
import '../../../teacher/analysis/exam/exam_model.dart';

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
      if(mounted) setState(() => _error = 'يرجى إدخال كلمة المرور');
      return;
    }
    if (_needsPasscode && _passcodeCtrl.text.trim() != widget.exam.passcode) {
      if(mounted) setState(() => _error = 'كلمة المرور غير صحيحة');
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
          _error = 'هذا الاختبار لا يحتوي على أسئلة بعد';
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
        _error = e is ApiException ? e.message : 'فشل تحميل الأسئلة';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _passcodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    final isScheduled =
        exam.startDate != null && exam.startDate!.isAfter(DateTime.now());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.primary,
          foregroundColor: Colors.white,
          title: const Text('دخول الاختبار',
              style:
              TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700)),
          leading: IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: () => Navigator.pop(context)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 20),
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [context.colors.primary, Colors.deepPurple],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: context.colors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6))
                ],
              ),
              child:
              const Icon(Icons.quiz_rounded, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 20),
            Text(exam.name,
                style: const TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 20,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            if (exam.description != null) ...[
              const SizedBox(height: 8),
              Text(exam.description!,
                  style: const TextStyle(
                      fontFamily: 'bahji', fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            _InfoCard(children: [
              _InfoRow(Icons.timer_outlined, 'مدة الاختبار',
                  '${exam.duration ?? 0} دقيقة', Colors.teal),
              _InfoRow(Icons.star_outline_rounded, 'درجة النجاح',
                  '${exam.passingScore?.toInt() ?? 0}%', Colors.amber.shade700),
              _InfoRow(Icons.help_outline_rounded, 'عدد الأسئلة',
                  '${exam.questionCount} سؤال', context.colors.primary),
              if (exam.startDate != null)
                _InfoRow(Icons.schedule_rounded, 'وقت البدء',
                    _fmtDate(exam.startDate!), Colors.orange),
            ]),
            const SizedBox(height: 20),
            if (isScheduled)
              _CountdownBanner(target: exam.startDate!)
            else ...[
              if (_needsPasscode) ...[
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('كلمة مرور الاختبار',
                      style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passcodeCtrl,
                  textAlign: TextAlign.center,
                  obscureText: true,
                  style: const TextStyle(
                      fontFamily: 'bahji', fontSize: 18, letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: '••••••',
                    errorText: _error,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onSubmitted: (_) => _enter(),
                ),
                const SizedBox(height: 20),
              ],
              if (_error != null && !_needsPasscode) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 13,
                                color: Colors.red))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _enter,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 22),
                        SizedBox(width: 8),
                        Text('ابدأ الاختبار الآن',
                            style: TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ]),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                  Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                        'بمجرد بدء الاختبار لا يمكن إيقافه مؤقتاً. تأكد من اتصالك بالإنترنت.',
                        style: TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 12,
                            color: Colors.orange),
                      )),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
        if(mounted) setState(() => _secondsLeft--);
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
        _submitError = e is ApiException ? e.message : e.toString();
        _submitting = false;
        _submitted = true;
      });
    }
  }

  void _next() {
    if (_current < widget.questions.length - 1) if(mounted) setState(() => _current++);
  }

  void _prev() {
    if (_current > 0) if(mounted) setState(() => _current--);
  }

  String get _timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor => _secondsLeft < 120
      ? Colors.redAccent
      : _secondsLeft < 300
      ? Colors.orange
      : context.colors.success;

  int get _answeredCount => _answers.values.where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    if (_submitting) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: context.colors.background,
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('جارٍ إرسال إجاباتك...',
                  style: TextStyle(fontFamily: 'bahji', fontSize: 16)),
            ]),
          ),
        ),
      );
    }
    if (_submitted) return _buildResultScreen();

    final q = widget.questions[_current];
    final opts = q.options;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(widget.exam.name,
              style: const TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
              overflow: TextOverflow.ellipsis),
          actions: [
            Container(
              margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _timerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _timerColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_rounded, size: 16, color: _timerColor),
                const SizedBox(width: 6),
                Text(_timerDisplay,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _timerColor)),
              ]),
            ),
          ],
        ),
        body: Column(children: [
          // Progress bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('السؤال ${_current + 1} من ${widget.questions.length}',
                    style: const TextStyle(
                        fontFamily: 'bahji', fontSize: 12, color: Colors.grey)),
                Text('$_answeredCount / ${widget.questions.length} تمت الإجابة',
                    style: const TextStyle(
                        fontFamily: 'bahji', fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_current + 1) / widget.questions.length,
                  backgroundColor: Colors.grey.shade100,
                  color: context.colors.primary,
                  minHeight: 6,
                ),
              ),
            ]),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question card
                    Container(
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
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color:
                                  context.colors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('${q.marks.toInt()} درجات',
                                  style: TextStyle(
                                      fontFamily: 'bahji',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: context.colors.primary)),
                            ),
                            const SizedBox(height: 12),
                            Text(q.title,
                                style: const TextStyle(
                                    fontFamily: 'bahji',
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    height: 1.5)),
                          ]),
                    ),
                    const SizedBox(height: 16),

                    // MCQ options or free-text input
                    if (opts.isNotEmpty)
                      ...List.generate(opts.length, (i) {
                        final opt = opts[i];
                        final selected = _answers[_current] == opt;
                        return GestureDetector(
                          onTap: () { if(mounted) setState(() => _answers[_current] = opt);},
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? context.colors.primary.withValues(alpha: 0.08)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? context.colors.primary
                                    : Colors.grey.shade200,
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
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? context.colors.primary
                                      : Colors.transparent,
                                  border: Border.all(
                                      color: selected
                                          ? context.colors.primary
                                          : Colors.grey.shade300,
                                      width: 2),
                                ),
                                child: selected
                                    ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 14)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(opt,
                                      style: TextStyle(
                                          fontFamily: 'bahji',
                                          fontSize: 15,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: selected
                                              ? context.colors.primary
                                              : Colors.black87))),
                            ]),
                          ),
                        );
                      })
                    else
                    // Open-ended text field
                      TextField(
                        textDirection: TextDirection.rtl,
                        maxLines: 4,
                        onChanged: (v) => _answers[_current] =
                        v.trim().isEmpty ? null : v.trim(),
                        decoration: InputDecoration(
                          hintText: 'اكتب إجابتك هنا...',
                          hintStyle: const TextStyle(
                              fontFamily: 'bahji', color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                              BorderSide(color: Colors.grey.shade200)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                              BorderSide(color: Colors.grey.shade200)),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),

                    // Navigator dots
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(widget.questions.length, (i) {
                        final answered = _answers[i] != null;
                        final isCurrent = i == _current;
                        return GestureDetector(
                          onTap: () { if(mounted) setState(() => _current = i);},
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
                                child: Text('${i + 1}',
                                    style: TextStyle(
                                        fontFamily: 'bahji',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isCurrent
                                            ? Colors.white
                                            : answered
                                            ? context.colors.success
                                            : Colors.grey))),
                          ),
                        );
                      }),
                    ),
                  ]),
            ),
          ),

          // Navigation bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            child: Row(children: [
              if (_current > 0)
                OutlinedButton.icon(
                  onPressed: _prev,
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  label: const Text('السابق',
                      style: TextStyle(fontFamily: 'bahji')),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12)),
                ),
              const Spacer(),
              if (_current < widget.questions.length - 1)
                ElevatedButton.icon(
                  onPressed: _next,
                  icon: const Text('التالي',
                      style: TextStyle(
                          fontFamily: 'bahji', fontWeight: FontWeight.w700)),
                  label: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12)),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _showSubmitDialog(),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('تسليم الاختبار',
                      style: TextStyle(
                          fontFamily: 'bahji', fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showSubmitDialog() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('تسليم الاختبار',
              style:
              TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700)),
          content: Text(
            _answeredCount < widget.questions.length
                ? 'لم تجب على ${widget.questions.length - _answeredCount} سؤال. هل أنت متأكد من التسليم؟'
                : 'هل تريد تسليم إجاباتك الآن؟',
            style: const TextStyle(fontFamily: 'bahji'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                const Text('إلغاء', style: TextStyle(fontFamily: 'bahji'))),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _submitExam();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('تأكيد التسليم',
                  style: TextStyle(
                      fontFamily: 'bahji', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultScreen() {
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: passed ? context.colors.success : Colors.redAccent,
          automaticallyImplyLeading: false,
          title: const Text('نتيجة الاختبار',
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Error banner if submission had an error
              if (_submitError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                          'تعذّر إرسال بعض الإجابات: $_submitError',
                          style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 12,
                              color: Colors.orange),
                        )),
                  ]),
                ),
              ],

              // Animated score ring
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct / 100),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOut,
                builder: (_, v, _) =>
                    Stack(alignment: Alignment.center, children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: v,
                          strokeWidth: 12,
                          backgroundColor: Colors.grey.shade100,
                          color: passed ? context.colors.success : Colors.redAccent,
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${(v * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color:
                                passed ? context.colors.success : Colors.redAccent)),
                        Text(passed ? 'ناجح ✓' : 'راسب ✗',
                            style: TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color:
                                passed ? context.colors.success : Colors.redAccent)),
                      ]),
                    ]),
              ),
              const SizedBox(height: 28),
              Text(
                passed
                    ? 'تهانينا! اجتزت الاختبار بنجاح'
                    : 'لم تجتز الاختبار هذه المرة',
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: passed ? context.colors.success : Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              Container(
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
                child: Column(children: [
                  _ResultRow(
                    'درجتك',
                    marksObtained != null
                        ? '${marksObtained.toStringAsFixed(0)} / ${totalMarks?.toStringAsFixed(0)}'
                        : '$_answeredCount / ${widget.questions.length} إجابة',
                    context.colors.primary,
                  ),
                  const Divider(height: 20),
                  _ResultRow(
                      'الأسئلة المجابة',
                      '$_answeredCount / ${widget.questions.length}',
                      Colors.teal),
                  const Divider(height: 20),
                  _ResultRow(
                      'درجة النجاح',
                      '${widget.exam.passingScore?.toInt() ?? 60}%',
                      Colors.orange),
                ]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('العودة للرئيسية',
                      style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)
      ],
    ),
    child: Column(
        children: children
            .map((c) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4), child: c))
            .toList()),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;

  const _InfoRow(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 10),
    Text(label,
        style: const TextStyle(
            fontFamily: 'bahji', fontSize: 13, color: Colors.grey)),
    const Spacer(),
    Text(value,
        style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color)),
  ]);
}

class _ResultRow extends StatelessWidget {
  final String label, value;
  final Color color;

  const _ResultRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label,
        style: const TextStyle(
            fontFamily: 'bahji', fontSize: 14, color: Colors.grey)),
    const Spacer(),
    Text(value,
        style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color)),
  ]);
}

class _CountdownBanner extends StatefulWidget {
  final DateTime target;

  const _CountdownBanner({required this.target});

  @override
  State<_CountdownBanner> createState() => _CountdownBannerState();
}

class _CountdownBannerState extends State<_CountdownBanner> {
  late Timer _timer;
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
    if(mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
    ),
    child: Column(children: [
      const Text('يبدأ الاختبار خلال',
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 14,
              color: Colors.orange,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _TimeBox(_remaining.inHours.toString().padLeft(2, '0'), 'ساعة'),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(':',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.orange))),
        _TimeBox(((_remaining.inMinutes) % 60).toString().padLeft(2, '0'),
            'دقيقة'),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(':',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.orange))),
        _TimeBox(((_remaining.inSeconds) % 60).toString().padLeft(2, '0'),
            'ثانية'),
      ]),
    ]),
  );
}

class _TimeBox extends StatelessWidget {
  final String value, label;

  const _TimeBox(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12)),
      child: Center(
          child: Text(value,
              style: const TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.orange))),
    ),
    const SizedBox(height: 4),
    Text(label,
        style: const TextStyle(
            fontFamily: 'bahji', fontSize: 11, color: Colors.grey)),
  ]);
}