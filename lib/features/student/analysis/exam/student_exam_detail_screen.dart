// student_exam_detail_screen.dart — Premium redesign
//
// Entry gate: shows exam info, score history, then launches quiz.
// NEW: shows "Try Again" when maxSubmissions allows more rounds.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'student_exam_frozen_screen.dart';
import 'student_exam_api.dart';
import 'student_exam_provider.dart';
import 'student_exam_quiz_screen.dart';

class StudentExamDetailScreen extends StatefulWidget {
  final StudentExamListItem exam;
  const StudentExamDetailScreen({super.key, required this.exam});

  @override
  State<StudentExamDetailScreen> createState() => _StudentExamDetailScreenState();
}

class _StudentExamDetailScreenState extends State<StudentExamDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _starting = false;
  String? _entryError;
  late AnimationController _heroCtrl;
  late Animation<double> _heroAnim;

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _heroAnim = CurvedAnimation(parent: _heroCtrl, curve: Curves.elasticOut);
    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _starting = true; _entryError = null; });
    final prov = context.read<StudentExamProvider>();
    final ok = await prov.startExam(widget.exam);
    if (!mounted) return;
    if(mounted) if(mounted) setState(() => _starting = false);
    if (!ok) {
      if(mounted) if(mounted) setState(() => _entryError = prov.questionsError ?? 'تعذّر تحميل الأسئلة');
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: prov,
          child: const StudentExamQuizScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    if (exam.isFrozen && !exam.isSubmitted) {
      return StudentExamFrozenScreen(
        exam: exam,
        onBack: () => Navigator.pop(context),
      );
    }

    final c = context.colors;
    final isDone = exam.isSubmitted;
    final canRetry = exam.canRetry && isDone;
    final isScheduled = exam.startDate != null && exam.startDate!.isAfter(DateTime.now());

    // Accent colour based on state
    final Color accent;
    if (isDone) {
      accent = exam.passed == true ? c.success : Colors.redAccent;
    } else if (isScheduled) {
      accent = Colors.orange;
    } else {
      accent = c.primary;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Gradient App Bar ─────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: accent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: .7)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        ScaleTransition(
                          scale: _heroAnim,
                          child: Container(
                            width: 78, height: 78,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: .4), width: 2),
                            ),
                            child: Icon(
                              isDone
                                  ? (exam.passed == true ? Icons.emoji_events_rounded : Icons.replay_rounded)
                                  : isScheduled
                                  ? Icons.schedule_rounded
                                  : Icons.quiz_rounded,
                              color: Colors.white, size: 38,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            exam.name,
                            style: const TextStyle(
                              fontFamily: 'bahji', fontSize: 17,
                              fontWeight: FontWeight.w800, color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (exam.courseName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            exam.courseName!,
                            style: const TextStyle(
                              fontFamily: 'bahji', fontSize: 13, color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              title: Text(
                exam.name,
                style: const TextStyle(
                  fontFamily: 'bahji', fontSize: 15,
                  fontWeight: FontWeight.w700, color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Description ──────────────────────────────────────────
                  if (exam.description != null && exam.description!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: accent.withValues(alpha: .15)),
                      ),
                      child: Text(
                        exam.description!,
                        style: TextStyle(
                          fontFamily: 'bahji', fontSize: 13, color: c.textMedium, height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Info card ─────────────────────────────────────────────
                  _InfoCard(accent: accent, children: [
                    _InfoRow(Icons.help_outline_rounded, 'عدد الأسئلة',
                        '${exam.questionCount} سؤال', c.primary),
                    _InfoRow(Icons.timer_outlined, 'المدة',
                        '${exam.duration ?? 0} دقيقة', Colors.teal),
                    if (exam.passingScore != null)
                      _InfoRow(Icons.star_outline_rounded, 'درجة النجاح',
                          '${exam.passingScore!.toInt()}%', Colors.amber.shade700),
                    if (exam.totalMarks != null)
                      _InfoRow(Icons.grade_outlined, 'إجمالي الدرجات',
                          '${exam.totalMarks!.toInt()} درجة', Colors.purple),
                    if (exam.startDate != null)
                      _InfoRow(Icons.schedule_rounded, 'وقت البدء',
                          _fmtDate(exam.startDate!), Colors.orange),
                    if (exam.endDate != null)
                      _InfoRow(
                        Icons.hourglass_bottom_rounded,
                        'الموعد النهائي',
                        _fmtDate(exam.endDate!),
                        exam.isDeadlineFrozen ? Colors.redAccent : Colors.orange,
                      ),
                    // Submissions counter
                    if (exam.maxSubmissions != null && exam.maxSubmissions! > 0) ...[
                      _InfoRow(
                        Icons.repeat_rounded,
                        'المحاولات المستخدمة',
                        '${exam.submissionCount} / ${exam.maxSubmissions}',
                        Colors.purple,
                      ),
                      _InfoRow(
                        Icons.replay_circle_filled_rounded,
                        'المحاولات المتبقية',
                        '${exam.computedRemainingSubmissions ?? 0}',
                        (exam.computedRemainingSubmissions ?? 0) > 0
                            ? Colors.green
                            : Colors.redAccent,
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),

                  // ── Best score card ───────────────────────────────────────
                  if (isDone) ...[
                    _ScoreCard(exam: exam, canRetry: canRetry),
                    const SizedBox(height: 16),
                  ],

                  // ── Countdown (scheduled) ─────────────────────────────────
                  if (isScheduled && !isDone) ...[
                    _CountdownCard(target: exam.startDate!),
                    const SizedBox(height: 16),
                  ],

                  // ── Error banner ──────────────────────────────────────────
                  if (_entryError != null) ...[
                    _ErrorBanner(message: _entryError!),
                    const SizedBox(height: 16),
                  ],

                  // ── Warning notice ────────────────────────────────────────
                  if (!isDone && !isScheduled || canRetry) ...[
                    _WarningNotice(),
                    const SizedBox(height: 16),
                  ],

                  // ── Action buttons ────────────────────────────────────────
                  if (!isScheduled) ...[
                    if (!isDone)
                      _ActionButton(
                        loading: _starting,
                        label: 'ابدأ الاختبار الآن',
                        icon: Icons.play_arrow_rounded,
                        color: c.primary,
                        onPressed: _start,
                      )
                    else ...[
                      if (canRetry)
                        _ActionButton(
                          loading: _starting,
                          label: 'حاول مرة أخرى',
                          icon: Icons.replay_rounded,
                          color: const Color(0xFF6C5CE7),
                          onPressed: _start,
                          subtitle: '${exam.computedRemainingSubmissions} محاولة متبقية',
                        ),
                      const SizedBox(height: 12),
                      _OutlineBtn(
                        label: 'العودة',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Info card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final Color accent;
  const _InfoCard({required this.children, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(20),
      boxShadow: context.colors.cardShadow,
      border: Border.all(color: accent.withValues(alpha: .10)),
    ),
    child: Column(
      children: children.asMap().entries.map((e) => Column(
        children: [
          e.value,
          if (e.key < children.length - 1)
            Divider(height: 18, color: Colors.grey.shade100),
        ],
      )).toList(),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _InfoRow(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: color, size: 17),
    ),
    const SizedBox(width: 10),
    Expanded(child: Text(label,
        style: const TextStyle(fontFamily: 'bahji', fontSize: 13, color: Colors.grey))),
    Text(value, style: TextStyle(
      fontFamily: 'bahji', fontSize: 13, fontWeight: FontWeight.w700, color: color,
    )),
  ]);
}

// ── Score card ────────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final StudentExamListItem exam;
  final bool canRetry;
  const _ScoreCard({required this.exam, required this.canRetry});

  Color get _color => exam.passed == true ? AppTheme.success : Colors.redAccent;

  @override
  Widget build(BuildContext context) {
    final pct = exam.percentage ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_color.withValues(alpha: .10), _color.withValues(alpha: .04)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: .3)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events_rounded, size: 14, color: _color),
              const SizedBox(width: 4),
              Text('أفضل نتيجة', style: TextStyle(
                fontFamily: 'bahji', fontSize: 11, fontWeight: FontWeight.w700, color: _color,
              )),
            ]),
          ),
          const Spacer(),
          Text(
            exam.passed == true ? 'ناجح ✓' : 'راسب ✗',
            style: TextStyle(
              fontFamily: 'bahji', fontSize: 14, fontWeight: FontWeight.w700, color: _color,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ScoreStat('${pct.toStringAsFixed(1)}%', 'النسبة', _color),
          Container(width: 1, height: 40, color: _color.withValues(alpha: .2)),
          _ScoreStat(
            '${exam.marksObtained?.toStringAsFixed(0) ?? 0} / ${exam.totalMarks?.toStringAsFixed(0) ?? 0}',
            'الدرجة', _color,
          ),
          Container(width: 1, height: 40, color: _color.withValues(alpha: .2)),
          _ScoreStat(
            '${exam.answeredCount} / ${exam.questionCount}',
            'أجبت', Colors.grey,
          ),
        ]),
        if (exam.submissionCount > 0) ...[
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.repeat_rounded, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              'تم التقديم ${exam.submissionCount} مرة',
              style: TextStyle(fontFamily: 'bahji', fontSize: 12, color: Colors.grey.shade500),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _ScoreStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _ScoreStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(
      fontFamily: 'bahji', fontSize: 18, fontWeight: FontWeight.w800, color: color,
    )),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontFamily: 'bahji', fontSize: 11, color: Colors.grey)),
  ]);
}

// ── Action buttons ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final bool loading;
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.loading,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onPressed,
    child: Container(
      height: subtitle != null ? 66 : 58,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: .8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(
          color: color.withValues(alpha: .38),
          blurRadius: 18, offset: const Offset(0, 7),
        )],
      ),
      child: Center(
        child: loading
            ? const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(
                fontFamily: 'bahji', fontSize: 16,
                fontWeight: FontWeight.w800, color: Colors.white,
              )),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: const TextStyle(
                fontFamily: 'bahji', fontSize: 11, color: Colors.white70,
              )),
            ],
          ],
        ),
      ),
    ),
  );
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _OutlineBtn({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onPressed,
    child: Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Text(label, style: TextStyle(
          fontFamily: 'bahji', fontSize: 15,
          fontWeight: FontWeight.w600, color: Colors.grey.shade600,
        )),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.red.shade50, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: const TextStyle(
        fontFamily: 'bahji', fontSize: 13, color: Colors.red,
      ))),
    ]),
  );
}

class _WarningNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.orange.withValues(alpha: .25)),
    ),
    child: const Row(children: [
      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'بمجرد بدء الاختبار لا يمكن إيقافه مؤقتاً. تأكد من اتصالك قبل البدء.',
          style: TextStyle(fontFamily: 'bahji', fontSize: 12, color: Colors.orange),
        ),
      ),
    ]),
  );
}

// ── Countdown card ────────────────────────────────────────────────────────────

class _CountdownCard extends StatefulWidget {
  final DateTime target;
  const _CountdownCard({required this.target});

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final r = widget.target.difference(DateTime.now());
    if(mounted) if(mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.orange.withValues(alpha: .25)),
    ),
    child: Column(children: [
      const Text('يبدأ الاختبار خلال', style: TextStyle(
        fontFamily: 'bahji', fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600,
      )),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _TimeBox(_remaining.inHours.toString().padLeft(2, '0'), 'ساعة'),
        const _Colon(),
        _TimeBox((_remaining.inMinutes % 60).toString().padLeft(2, '0'), 'دقيقة'),
        const _Colon(),
        _TimeBox((_remaining.inSeconds % 60).toString().padLeft(2, '0'), 'ثانية'),
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
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .2)),
      ),
      child: Center(child: Text(value, style: const TextStyle(
        fontFamily: 'bahji', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange,
      ))),
    ),
    const SizedBox(height: 5),
    Text(label, style: const TextStyle(fontFamily: 'bahji', fontSize: 11, color: Colors.grey)),
  ]);
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Text(':', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.orange)),
  );
}