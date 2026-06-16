// student_exam_list_screen.dart — Premium redesign
//
// Shows all student exams grouped by: Upcoming / Active / Submitted / Frozen.
// Each card shows best score, remaining attempts, and deadline countdown.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'student_exam_api.dart';
import 'student_exam_detail_screen.dart';
import 'student_exam_provider.dart';

class StudentExamListScreen extends StatefulWidget {
  const StudentExamListScreen({super.key});

  @override
  State<StudentExamListScreen> createState() => _StudentExamListScreenState();
}

class _StudentExamListScreenState extends State<StudentExamListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentExamProvider>().loadMyExams();
    });
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final c = context.colors;

    final all = prov.myExams;
    final now = DateTime.now();

    final upcoming  = all.where((e) => !e.isSubmitted && e.startDate != null && e.startDate!.isAfter(now)).toList();
    final active    = all.where((e) => !e.isSubmitted && !e.isFrozen && (e.startDate == null || e.startDate!.isBefore(now))).toList();
    final submitted = all.where((e) => e.isSubmitted).toList();
    final frozen    = all.where((e) => e.isFrozen && !e.isSubmitted).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.background,
        body: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (_, __) => [
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: c.primary,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.primary, c.primary.withValues(alpha: .75)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.quiz_rounded, color: Colors.white, size: 36),
                        const SizedBox(height: 8),
                        const Text('اختباراتي', style: TextStyle(
                          fontFamily: 'bahji', fontSize: 22,
                          fontWeight: FontWeight.w800, color: Colors.white,
                        )),
                        const SizedBox(height: 4),
                        Text('${all.length} اختبار في ${all.map((e) => e.courseId).toSet().length} مادة',
                            style: const TextStyle(fontFamily: 'bahji', fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
              bottom: TabBar(
                controller: _tabCtrl,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontFamily: 'bahji', fontSize: 12),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'نشطة (${active.length})'),
                  Tab(text: 'قادمة (${upcoming.length})'),
                  Tab(text: 'مقدّمة (${submitted.length})'),
                  Tab(text: 'مغلقة (${frozen.length})'),
                ],
              ),
            ),
          ],
          body: prov.loadingList
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : prov.listError != null
              ? _ErrorState(
            message: prov.listError!,
            onRetry: () => prov.loadMyExams(),
          )
              : TabBarView(
            controller: _tabCtrl,
            children: [
              _ExamList(exams: active,    emptyMsg: 'لا توجد اختبارات نشطة الآن'),
              _ExamList(exams: upcoming,  emptyMsg: 'لا توجد اختبارات قادمة'),
              _ExamList(exams: submitted, emptyMsg: 'لم تُقدّم أي اختبار بعد'),
              _ExamList(exams: frozen,    emptyMsg: 'لا توجد اختبارات مغلقة'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Exam list ──────────────────────────────────────────────────────────────────

class _ExamList extends StatelessWidget {
  final List<StudentExamListItem> exams;
  final String emptyMsg;
  const _ExamList({required this.exams, required this.emptyMsg});

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) return _EmptyState(message: emptyMsg);
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: exams.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ExamCard(exam: exams[i]),
    );
  }
}

// ── Exam card ──────────────────────────────────────────────────────────────────

class _ExamCard extends StatelessWidget {
  final StudentExamListItem exam;
  const _ExamCard({required this.exam});

  Color get _accent {
    if (exam.isFrozen && !exam.isSubmitted) return Colors.blueGrey;
    if (exam.isSubmitted) return exam.passed == true ? AppTheme.success : Colors.redAccent;
    if (exam.startDate != null && exam.startDate!.isAfter(DateTime.now())) return Colors.orange;
    return const Color(0xFF0F4C81);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.read<StudentExamProvider>();
    final c = context.colors;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: prov,
              child: StudentExamDetailScreen(exam: exam),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent.withValues(alpha: .18)),
          boxShadow: c.cardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row ───────────────────────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_accent, _accent.withValues(alpha: .7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(
                  color: _accent.withValues(alpha: .3), blurRadius: 8, offset: const Offset(0, 3),
                )],
              ),
              child: Icon(_statusIcon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(exam.name,
                    style: c.h3.copyWith(fontSize: 14),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (exam.courseName != null) ...[
                  const SizedBox(height: 3),
                  Text(exam.courseName!,
                      style: c.caption.copyWith(fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            const SizedBox(width: 8),

            // Score or status badge
            if (exam.isSubmitted && exam.percentage != null)
              _ScoreBadge(pct: exam.percentage!, passed: exam.passed ?? false)
            else
              _StatusBadge(exam: exam, accent: _accent),
          ]),

          const SizedBox(height: 14),

          // ── Meta chips ───────────────────────────────────────────────────
          Wrap(spacing: 8, runSpacing: 6, children: [
            _MetaChip(Icons.timer_outlined, '${exam.duration ?? 0}د', Colors.teal),
            _MetaChip(Icons.help_outline_rounded, '${exam.questionCount}س', _accent),
            if (exam.maxSubmissions != null && exam.maxSubmissions! > 0) ...[
              _MetaChip(
                Icons.repeat_rounded,
                '${exam.submissionCount}/${exam.maxSubmissions} محاولة',
                Colors.purple,
              ),
              if (!exam.isFrozen)
                _MetaChip(
                  Icons.replay_rounded,
                  '${exam.computedRemainingSubmissions ?? 0} متبقية',
                  (exam.computedRemainingSubmissions ?? 0) > 0 ? Colors.green : Colors.redAccent,
                ),
            ],
            if (exam.endDate != null)
              _DeadlineChip(endDate: exam.endDate!, frozen: exam.isDeadlineFrozen),
          ]),

          // ── Best score bar ───────────────────────────────────────────────
          if (exam.isSubmitted && exam.percentage != null) ...[
            const SizedBox(height: 12),
            _ScoreBar(pct: exam.percentage!, passed: exam.passed ?? false, accent: _accent),
          ],

          // ── Retry hint ───────────────────────────────────────────────────
          if (exam.isSubmitted && exam.canRetry) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: .2)),
              ),
              child: Row(children: [
                const Icon(Icons.replay_rounded, size: 14, color: Color(0xFF6C5CE7)),
                const SizedBox(width: 6),
                Text(
                  'يمكنك المحاولة مرة أخرى (${exam.computedRemainingSubmissions} محاولة متبقية)',
                  style: const TextStyle(
                    fontFamily: 'bahji', fontSize: 11,
                    fontWeight: FontWeight.w700, color: Color(0xFF6C5CE7),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  IconData get _statusIcon {
    if (exam.isFrozen && !exam.isSubmitted) return Icons.lock_clock_rounded;
    if (exam.isSubmitted) return exam.passed == true ? Icons.emoji_events_rounded : Icons.replay_rounded;
    if (exam.startDate != null && exam.startDate!.isAfter(DateTime.now())) return Icons.schedule_rounded;
    return Icons.quiz_rounded;
  }
}

// ── Score badge ───────────────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  final double pct;
  final bool passed;
  const _ScoreBadge({required this.pct, required this.passed});

  @override
  Widget build(BuildContext context) {
    final color = passed ? AppTheme.success : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: .7)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 8)],
      ),
      child: Text('${pct.toStringAsFixed(0)}%',
          style: const TextStyle(
            fontFamily: 'bahji', fontSize: 13,
            fontWeight: FontWeight.w900, color: Colors.white,
          )),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final StudentExamListItem exam;
  final Color accent;
  const _StatusBadge({required this.exam, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: .3)),
    ),
    child: Text(
      exam.isFrozen ? 'مغلق' : 'نشط',
      style: TextStyle(fontFamily: 'bahji', fontSize: 11, fontWeight: FontWeight.w700, color: accent),
    ),
  );
}

// ── Score bar ─────────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final double pct;
  final bool passed;
  final Color accent;
  const _ScoreBar({required this.pct, required this.passed, required this.accent});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        const Icon(Icons.emoji_events_rounded, size: 12, color: Colors.amber),
        const SizedBox(width: 4),
        Text('أفضل نتيجة',
            style: const TextStyle(fontFamily: 'bahji', fontSize: 11, color: Colors.grey)),
        const Spacer(),
        Text('${pct.toStringAsFixed(1)}%',
            style: TextStyle(fontFamily: 'bahji', fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: pct / 100,
          minHeight: 6,
          backgroundColor: accent.withValues(alpha: .12),
          valueColor: AlwaysStoppedAnimation(accent),
        ),
      ),
    ],
  );
}

// ── Meta chip ─────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
        fontFamily: 'bahji', fontSize: 11, fontWeight: FontWeight.w600, color: color,
      )),
    ]),
  );
}

// ── Deadline chip with live countdown ─────────────────────────────────────────

class _DeadlineChip extends StatefulWidget {
  final DateTime endDate;
  final bool frozen;
  const _DeadlineChip({required this.endDate, required this.frozen});

  @override
  State<_DeadlineChip> createState() => _DeadlineChipState();
}

class _DeadlineChipState extends State<_DeadlineChip> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.endDate.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if(mounted) setState(() => _remaining = widget.endDate.difference(DateTime.now()));
    });
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDead = widget.frozen || _remaining.isNegative;
    final isUrgent = !isDead && _remaining.inHours < 3;
    final color = isDead ? Colors.redAccent : isUrgent ? Colors.orange : Colors.grey;
    final label = isDead
        ? 'انتهى الموعد'
        : _remaining.inHours >= 24
        ? '${widget.endDate.day}/${widget.endDate.month}'
        : isUrgent
        ? '${_remaining.inHours}س ${_remaining.inMinutes % 60}د'
        : 'ينتهي ${_remaining.inHours}س';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.hourglass_bottom_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          fontFamily: 'bahji', fontSize: 11, fontWeight: FontWeight.w600, color: color,
        )),
      ]),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inbox_rounded, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 14),
      Text(message, style: TextStyle(
        fontFamily: 'bahji', fontSize: 14, color: Colors.grey.shade500,
      )),
    ]),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.redAccent),
        const SizedBox(height: 14),
        Text(message,
            style: const TextStyle(fontFamily: 'bahji', fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'bahji')),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeConfig.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      ]),
    ),
  );
}