// student_exam_list_screen.dart — Premium redesign (analytics style)
//
// Shows all student exams grouped by: Active / Upcoming / Submitted / Closed.
// Hero with overall stats, pinned segmented tabs, rich exam cards.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../../utils/widget/base_page.dart';
import 'exam_tr.dart';
import 'exam_ui.dart';
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
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<StudentExamProvider>().loadMyExams();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final c = context.colors;

    final all = prov.myExams;
    final now = DateTime.now();

    final upcoming = all
        .where((e) =>
    !e.isSubmitted && e.startDate != null && e.startDate!.isAfter(now))
        .toList();
    final active = all
        .where((e) =>
    !e.isSubmitted &&
        !e.isFrozen &&
        (e.startDate == null || e.startDate!.isBefore(now)))
        .toList();
    final submitted = all.where((e) => e.isSubmitted).toList();
    final frozen = all.where((e) => e.isFrozen && !e.isSubmitted).toList();

    final scored =
    submitted.where((e) => e.percentage != null).toList(growable: false);
    final passed = submitted.where((e) => e.passed == true).length;
    final avg = scored.isEmpty
        ? 0.0
        : scored.map((e) => e.percentage!).reduce((a, b) => a + b) /
        scored.length;
    final courses = all.map((e) => e.courseId).toSet().length;

    return BasePage( useWebCard: true,maxWith: 1100, child: NestedScrollView(
        physics: const BouncingScrollPhysics(),
        headerSliverBuilder: (ctx, _) => [
          SliverToBoxAdapter(
            child: ExamHero(
              child: Column(children: [
                ExamHeroBar(
                  title: tx('exam_my_exams'),
                  subtitle: tx('exam_list_summary',
                      {'exams': all.length, 'courses': courses}),
                  actions: [
                    GlassIcon(
                      icon: Icons.refresh_rounded,
                      onTap: () => prov.loadMyExams(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(children: [
                  HeroStat(
                    icon: Icons.quiz_rounded,
                    color: context.colors.primaryLight,
                    value: '${all.length}',
                    label: 'exams'.tr,
                  ),
                  const SizedBox(width: 10),
                  HeroStat(
                    icon: Icons.emoji_events_rounded,
                    color: const Color(0xFFFFD740),
                    value: '$passed/${submitted.length}',
                    label: 'sa_passed_exams'.tr,
                  ),
                  const SizedBox(width: 10),
                  HeroStat(
                    icon: Icons.bar_chart_rounded,
                    color: const Color(0xFF69F0AE),
                    value: '${avg.toStringAsFixed(0)}%',
                    label: 'sa_avg_score'.tr,
                  ),
                ]),
              ]),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: ExamTabsDelegate(
              controller: _tabCtrl,
              scrollable: true,
              tabs: [
                examTab(Icons.play_circle_rounded,
                    tx('exam_tab_active', {'n': active.length})),
                examTab(Icons.schedule_rounded,
                    tx('exam_tab_upcoming', {'n': upcoming.length})),
                examTab(Icons.task_alt_rounded,
                    tx('exam_tab_submitted', {'n': submitted.length})),
                examTab(Icons.lock_clock_rounded,
                    tx('exam_tab_closed', {'n': frozen.length})),
              ],
            ),
          ),
        ],
        body: prov.loadingList
            ? const Center(child: AppLoadingIndicator())
            : prov.listError != null
            ? ExamError(
          message: prov.listError!,
          retryLabel: tx('exam_reload'),
          onRetry: () => prov.loadMyExams(),
        )
            : TabBarView(
          controller: _tabCtrl,
          children: [
            _ExamList(
                exams: active,
                icon: Icons.quiz_outlined,
                emptyMsg: tx('exam_empty_active')),
            _ExamList(
                exams: upcoming,
                icon: Icons.schedule_rounded,
                emptyMsg: tx('exam_empty_upcoming')),
            _ExamList(
                exams: submitted,
                icon: Icons.task_alt_rounded,
                emptyMsg: tx('exam_empty_submitted')),
            _ExamList(
                exams: frozen,
                icon: Icons.lock_clock_rounded,
                emptyMsg: tx('exam_empty_closed')),
          ],
        ),
      ),
    );
  }
}

// ── Exam list ─────────────────────────────────────────────────────────────────

class _ExamList extends StatelessWidget {
  final List<StudentExamListItem> exams;
  final String emptyMsg;
  final IconData icon;
  const _ExamList(
      {required this.exams, required this.emptyMsg, required this.icon});

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) return ExamEmpty(icon: icon, text: emptyMsg);
    return RefreshIndicator(
      onRefresh: () => context.read<StudentExamProvider>().loadMyExams(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: exams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ExamCard(exam: exams[i]),
      ),
    );
  }
}

// ── Exam card ─────────────────────────────────────────────────────────────────

class _ExamCard extends StatelessWidget {
  final StudentExamListItem exam;
  const _ExamCard({required this.exam});

  Color _accent(BuildContext context) {
    if (exam.isFrozen && !exam.isSubmitted) return Colors.blueGrey;
    if (exam.isSubmitted) {
      return exam.passed == true ? context.colors.success : kDanger;
    }
    if (exam.startDate != null && exam.startDate!.isAfter(DateTime.now())) {
      return kAmber;
    }
    return context.colors.primary;
  }

  IconData get _statusIcon {
    if (exam.isFrozen && !exam.isSubmitted) return Icons.lock_clock_rounded;
    if (exam.isSubmitted) {
      return exam.passed == true
          ? Icons.emoji_events_rounded
          : Icons.replay_rounded;
    }
    if (exam.startDate != null && exam.startDate!.isAfter(DateTime.now())) {
      return Icons.schedule_rounded;
    }
    return Icons.quiz_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.read<StudentExamProvider>();
    final c = context.colors;
    final accent = _accent(context);
    final hasScore = exam.isSubmitted && exam.percentage != null;

    return ExamCard(
      padding: const EdgeInsets.all(16),
      borderColor: accent.withValues(alpha: 0.22),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(_statusIcon, accent, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exam.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: examT(14.5, w: FontWeight.w800, c: c.textDark, h: 1.4)),
              if (exam.courseName != null) ...[
                const SizedBox(height: 3),
                Text(exam.courseName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: examT(11.5, c: c.textMedium)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (hasScore)
            ExamRing(
              value: exam.percentage!,
              size: 52,
              stroke: 5,
              color: accent,
              track: accent.withValues(alpha: 0.14),
              center: Text('${exam.percentage!.toStringAsFixed(0)}%',
                  style: examT(12, w: FontWeight.w900, c: accent)),
            )
          else
            ExamBadge(
              exam.isFrozen
                  ? tx('exam_status_closed_label')
                  : tx('exam_status_open_label'),
              accent,
            ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ExamChip(Icons.timer_outlined,
              tx('exam_minutes_short', {'n': exam.duration ?? 0}), context.colors.success),
          ExamChip(Icons.help_outline_rounded,
              tx('exam_questions_short', {'n': exam.questionCount}), accent),
          if (exam.maxSubmissions != null && exam.maxSubmissions! > 0) ...[
            ExamChip(
              Icons.repeat_rounded,
              tx('exam_attempts_of',
                  {'used': exam.submissionCount, 'max': exam.maxSubmissions}),
              kViolet,
            ),
            if (!exam.isFrozen)
              ExamChip(
                Icons.replay_rounded,
                tx('exam_attempts_left_short',
                    {'n': exam.computedRemainingSubmissions ?? 0}),
                (exam.computedRemainingSubmissions ?? 0) > 0
                    ? c.success
                    : kDanger,
              ),
          ],
          if (exam.endDate != null)
            _DeadlineChip(endDate: exam.endDate!, frozen: exam.isDeadlineFrozen),
        ]),
        if (hasScore) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.emoji_events_rounded, size: 14, color: kAmber),
            const SizedBox(width: 5),
            Text(tx('exam_best_score'), style: examT(11.5, c: c.textMedium)),
            const Spacer(),
            Text('${exam.percentage!.toStringAsFixed(1)}%',
                style: examT(12.5, w: FontWeight.w800, c: accent)),
          ]),
          const SizedBox(height: 6),
          ExamBar(pct: exam.percentage!, color: accent),
        ],
        if (exam.isSubmitted && exam.canRetry) ...[
          const SizedBox(height: 12),
          ExamBanner(
            icon: Icons.replay_rounded,
            color: kViolet,
            text: tx('exam_retry_hint',
                {'n': exam.computedRemainingSubmissions}),
          ),
        ],
      ]),
    );
  }
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
  late final Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.endDate.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(
                () => _remaining = widget.endDate.difference(DateTime.now()));
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDead = widget.frozen || _remaining.isNegative;
    final isUrgent = !isDead && _remaining.inHours < 3;
    final color = isDead
        ? kDanger
        : isUrgent
        ? kAmber
        : context.colors.primary;
    final label = isDead
        ? tx('exam_deadline_ended')
        : _remaining.inHours >= 24
        ? '${widget.endDate.day}/${widget.endDate.month}'
        : isUrgent
        ? tx('exam_hm_short', {
      'h': _remaining.inHours,
      'm': _remaining.inMinutes % 60,
    })
        : tx('exam_ends_in_h', {'h': _remaining.inHours});

    return ExamChip(Icons.hourglass_bottom_rounded, label, color);
  }
}