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

class _View extends StatelessWidget {
  final String courseTitle;
  final int initialTab;
  const _View({required this.courseTitle, required this.initialTab});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<StudentFlagsProvider>();
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: DefaultTabController(
        length: 2,
        initialIndex: initialTab,
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.primary,
            foregroundColor: Colors.white,
            title: Text(courseTitle,
                style: const TextStyle(
                    fontFamily: 'bahji', fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                  icon: const Icon(Icons.refresh_rounded), onPressed: p.load),
            ],
            bottom: TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                  fontFamily: 'bahji', fontWeight: FontWeight.w700),
              tabs: [
                Tab(
                    icon: const Icon(Icons.bookmark_rounded, size: 18),
                    text: '${'flag_review_bank'.tr} (${p.review.length})'),
                Tab(
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    text: '${'flag_read_bank'.tr} (${p.read.length})'),
              ],
            ),
          ),
          body: p.loading
              ? const Center(child: AppLoadingIndicator())
              : p.error != null
              ? _ErrorView(message: p.error!, onRetry: p.load)
              : TabBarView(children: [
            _ReviewTab(p: p),
            _ReadTab(p: p),
          ]),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, size: 60, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'bahji', fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('retry'.tr, style: const TextStyle(fontFamily: 'bahji')),
        ),
      ]),
    ),
  );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 72, color: Colors.grey.shade300),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 15,
                color: Colors.grey,
                fontWeight: FontWeight.w600)),
      ),
    ]),
  );
}

// ── Review bank ───────────────────────────────────────────────────────────────

class _ReviewTab extends StatelessWidget {
  final StudentFlagsProvider p;
  const _ReviewTab({required this.p});

  @override
  Widget build(BuildContext context) {
    if (!p.settings.allowReview && p.review.isEmpty) {
      return _Empty(icon: Icons.bookmark_border_rounded, text: 'flag_disabled'.tr);
    }
    if (p.review.isEmpty) {
      return _Empty(icon: Icons.bookmark_border_rounded, text: 'flag_empty_review'.tr);
    }
    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: p.review.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _QuestionTile(
          q: p.review[i],
          trailing: IconButton(
            tooltip: 'flag_remove'.tr,
            icon: Icon(Icons.bookmark_remove_rounded,
                color: context.colors.danger),
            onPressed: () => p.removeReview(p.review[i]),
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
      return _Empty(icon: Icons.menu_book_outlined, text: 'flag_disabled'.tr);
    }
    if (p.read.isEmpty) {
      return _Empty(icon: Icons.task_alt_rounded, text: 'flag_empty_read'.tr);
    }
    final c = context.colors;
    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(
                child: _Stat(
                    label: 'flag_total_wrong'.tr,
                    value: '${p.readTotalWrong}',
                    color: c.danger)),
            const SizedBox(width: 12),
            Expanded(
                child: _Stat(
                    label: 'flag_total_score'.tr,
                    value: p.readTotalScore.toStringAsFixed(1),
                    color: Colors.amber.shade800)),
          ]),
          const SizedBox(height: 14),
          for (final q in p.read) ...[
            _QuestionTile(
              q: q,
              showWrong: true,
              trailing: Column(children: [
                _Pill(
                    text: tx('flag_wrong_times', {'n': q.wrongCount}),
                    color: c.danger),
                const SizedBox(height: 4),
                _Pill(
                    text: tx('flag_score', {'n': q.score.toStringAsFixed(1)}),
                    color: Colors.amber.shade800),
              ]),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Column(children: [
      Text(value,
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color)),
      Text(label,
          style: const TextStyle(
              fontFamily: 'bahji', fontSize: 11, color: Colors.grey)),
    ]),
  );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text,
        style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color)),
  );
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.examName,
                      style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 11,
                          color: c.primary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(q.title,
                      textDirection: Helpers.textDirOf(q.title),
                      style: c.h3.copyWith(fontSize: 15, height: 1.6)),
                ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
        if (q.options.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final o in q.options) _OptionRow(q: q, option: o, showWrong: showWrong),
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
                color: c.danger),
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
    final color = correct ? c.success : (wrong ? c.danger : Colors.grey);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: correct || wrong ? .1 : .04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: correct || wrong ? .5 : .2)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(option,
              textDirection: Helpers.textDirOf(option),
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 13,
                  color: correct || wrong ? color : null,
                  fontWeight: correct ? FontWeight.w700 : FontWeight.w500)),
        ),
        if (correct) Icon(Icons.check_circle_rounded, size: 16, color: color),
        if (wrong) Icon(Icons.cancel_rounded, size: 16, color: color),
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
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text.rich(TextSpan(children: [
      TextSpan(
          text: '$label: ',
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color)),
      TextSpan(
          text: text,
          style: const TextStyle(fontFamily: 'bahji', fontSize: 13)),
    ])),
  );
}
