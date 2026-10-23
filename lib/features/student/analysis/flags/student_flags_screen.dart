// features/student/analysis/flags/student_flags_screen.dart
//
// Per-course banks:  [Review bank]  — questions the student bookmarked in exams
//                    [Read flags]   — questions answered wrongly (score = wrong tries × points)
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';
import '../exam/exam_tr.dart';
import '../exam/exam_ui.dart';
import 'student_flags_api.dart';
import 'student_flags_provider.dart';

class StudentFlagsScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;
  final int initialTab; // 0 = review bank, 1 = read flags

  const StudentFlagsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    this.initialTab = 0,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => StudentFlagsProvider(courseId: courseId)..load(),
    child: _View(courseTitle: courseTitle, initialTab: initialTab),
  );
}

class _View extends StatefulWidget {
  final String courseTitle;
  final int initialTab;
  const _View({required this.courseTitle, required this.initialTab});

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<StudentFlagsProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        body: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (ctx, _) => [
            SliverToBoxAdapter(
              child: ExamHero(
                colors: [context.colors.purple, kViolet],
                child: Column(children: [
                  ExamHeroBar(
                    title: widget.courseTitle,
                    subtitle: tx('flag_review_bank'),
                    actions: [
                      GlassIcon(icon: Icons.refresh_rounded, onTap: p.load),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    HeroStat(
                      icon: Icons.bookmark_rounded,
                      color: const Color(0xFFFFD740),
                      value: '${p.review.length}',
                      label: tx('flag_review_bank'),
                    ),
                    const SizedBox(width: 10),
                    HeroStat(
                      icon: Icons.menu_book_rounded,
                      color: context.colors.primaryLight,
                      value: '${p.read.length}',
                      label: tx('flag_read_bank'),
                    ),
                    const SizedBox(width: 10),
                    HeroStat(
                      icon: Icons.close_rounded,
                      color: const Color(0xFFFF8A80),
                      value: '${p.readTotalWrong}',
                      label: tx('flag_total_wrong'),
                    ),
                  ]),
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: ExamTabsDelegate(
                controller: _tab,
                tabs: [
                  examTab(Icons.bookmark_rounded,
                      '${tx('flag_review_bank')} (${p.review.length})'),
                  examTab(Icons.menu_book_rounded,
                      '${tx('flag_read_bank')} (${p.read.length})'),
                ],
              ),
            ),
          ],
          body: p.loading
              ? const Center(child: AppLoadingIndicator())
              : p.error != null
              ? ExamError(
            message: p.error!,
            retryLabel: 'retry'.tr,
            onRetry: p.load,
          )
              : TabBarView(controller: _tab, children: [
            _ReviewTab(p: p),
            _ReadTab(p: p),
          ]),
        ),
      ),
    );
  }
}

// ── Review bank ───────────────────────────────────────────────────────────────

class _ReviewTab extends StatelessWidget {
  final StudentFlagsProvider p;
  const _ReviewTab({required this.p});

  @override
  Widget build(BuildContext context) {
    if (!p.settings.allowReview && p.review.isEmpty) {
      return ExamEmpty(
          icon: Icons.bookmark_border_rounded, text: 'flag_disabled'.tr);
    }
    if (p.review.isEmpty) {
      return ExamEmpty(
          icon: Icons.bookmark_border_rounded, text: 'flag_empty_review'.tr);
    }
    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: p.review.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _QuestionTile(
          q: p.review[i],
          trailing: Material(
            color: kDanger.withValues(alpha: 0.10),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'flag_remove'.tr,
              icon: const Icon(Icons.bookmark_remove_rounded,
                  color: kDanger, size: 20),
              onPressed: () => p.removeReview(p.review[i]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Read flags ────────────────────────────────────────────────────────────────

class _ReadTab extends StatelessWidget {
  final StudentFlagsProvider p;
  const _ReadTab({required this.p});

  @override
  Widget build(BuildContext context) {
    if (!p.settings.allowRead && p.read.isEmpty) {
      return ExamEmpty(icon: Icons.menu_book_outlined, text: 'flag_disabled'.tr);
    }
    if (p.read.isEmpty) {
      return ExamEmpty(icon: Icons.task_alt_rounded, text: 'flag_empty_read'.tr);
    }
    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            ExamStatBox('${p.readTotalWrong}', 'flag_total_wrong'.tr, kDanger),
            const SizedBox(width: 12),
            ExamStatBox(p.readTotalScore.toStringAsFixed(1),
                'flag_total_score'.tr, kAmber),
          ]),
          const SizedBox(height: 14),
          for (final q in p.read) ...[
            _QuestionTile(
              q: q,
              showWrong: true,
              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                ExamBadge(tx('flag_wrong_times', {'n': q.wrongCount}), kDanger),
                const SizedBox(height: 6),
                ExamBadge(
                    tx('flag_score', {'n': q.score.toStringAsFixed(1)}), kAmber),
              ]),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ── One question ──────────────────────────────────────────────────────────────

class _QuestionTile extends StatelessWidget {
  final FlaggedQuestion q;
  final Widget trailing;
  final bool showWrong;
  const _QuestionTile(
      {required this.q, required this.trailing, this.showWrong = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExamCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.quiz_rounded, size: 12, color: c.primary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(q.examName,
                            overflow: TextOverflow.ellipsis,
                            style: examT(11, w: FontWeight.w700, c: c.primary)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Text(q.title,
                      textDirection: Helpers.textDirOf(q.title),
                      style: examT(15, w: FontWeight.w700, c: c.textDark, h: 1.7)),
                ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
        if (q.options.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final o in q.options)
            _OptionRow(q: q, option: o, showWrong: showWrong),
        ] else if (q.correctAnswer != null) ...[
          const SizedBox(height: 10),
          _AnswerLine(
              label: 'flag_correct_answer'.tr,
              text: q.correctAnswer!,
              color: c.success),
          if (showWrong && (q.lastWrongAnswer ?? '').isNotEmpty)
            _AnswerLine(
                label: 'flag_your_wrong_answer'.tr,
                text: q.lastWrongAnswer!,
                color: kDanger),
        ],
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final FlaggedQuestion q;
  final String option;
  final bool showWrong;
  const _OptionRow(
      {required this.q, required this.option, required this.showWrong});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final correct = q.correctAnswer != null && q.correctAnswer == option;
    final wrong = showWrong && q.lastWrongAnswer == option && !correct;
    final color = correct ? c.success : (wrong ? kDanger : c.textMedium);
    final marked = correct || wrong;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: marked ? .10 : .05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: marked ? .5 : .18)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(option,
              textDirection: Helpers.textDirOf(option),
              style: examT(13.5,
                  w: correct ? FontWeight.w700 : FontWeight.w500,
                  c: marked ? color : c.textDark,
                  h: 1.5)),
        ),
        if (correct) Icon(Icons.check_circle_rounded, size: 18, color: color),
        if (wrong) Icon(Icons.cancel_rounded, size: 18, color: color),
      ]),
    );
  }
}

class _AnswerLine extends StatelessWidget {
  final String label, text;
  final Color color;
  const _AnswerLine(
      {required this.label, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Text.rich(TextSpan(children: [
      TextSpan(
          text: '$label: ',
          style: examT(12.5, w: FontWeight.w800, c: color)),
      TextSpan(
          text: text,
          style: examT(13.5, c: context.colors.textDark, h: 1.6)),
    ])),
  );
}