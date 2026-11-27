// features/analytics/student/flags/student_flags_screen.dart: Review (redesign S-C, Stu2Exams?screen=review).
//
// Two banks, one course or every course (courseId null, the Exams area's Review page):
//   [Saved]      questions the student bookmarked during an exam ("Got it" removes the bookmark)
//   [Got wrong]  questions answered wrongly (his answer next to the right one)
// The hero counts them and starts a run through them as flash cards (question, then the answer). Course chips narrow
// the list when it spans several courses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_api.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

class StudentFlagsScreen extends StatelessWidget {
  const StudentFlagsScreen({
    super.key,
    this.courseId,
    this.courseTitle,
    this.initialTab = 0,
    this.courseNames = const {},
    this.provider,
  });

  /// Null: every course.
  final int? courseId;
  final String? courseTitle;

  /// 0 = saved, 1 = got wrong.
  final int initialTab;

  /// Course id -> name, for the course chips and each card's course line.
  final Map<int, String> courseNames;

  /// A ready provider (tests); null = one for [courseId], loaded now.
  final StudentFlagsProvider? provider;

  @override
  Widget build(BuildContext context) {
    final view = AppAreaScope(
      area: AppArea.exam,
      child: _View(courseTitle: courseTitle, initialTab: initialTab, courseNames: courseNames),
    );
    if (provider != null) return ChangeNotifierProvider.value(value: provider!, child: view);
    return ChangeNotifierProvider(create: (_) => StudentFlagsProvider(courseId: courseId)..load(), child: view);
  }
}

class _View extends StatefulWidget {
  const _View({required this.courseTitle, required this.initialTab, required this.courseNames});

  final String? courseTitle;
  final int initialTab;
  final Map<int, String> courseNames;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  late int _tab = widget.initialTab.clamp(0, 1);
  int? _course;

  void _practice(List<FlaggedQuestion> items) {
    if (items.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ScReviewRunPage(items: items, courseNames: widget.courseNames)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StudentFlagsProvider>();
    final all = _tab == 0 ? p.review : p.read;
    final courses = {for (final q in [...p.review, ...p.read]) q.courseId};
    final shown = _course == null ? all : all.where((q) => q.courseId == _course).toList();
    final total = p.review.length + p.read.length;
    final empty = !p.loading && p.error == null && total == 0;

    final hero = AppHero(
      wipe: false,
      title: empty
          ? 'sc_review_empty_title'.tr
          : appDigits(countText(total,
              ar1: 'سؤال واحد يستاهل نظرة',
              ar2: 'سؤالان يستاهلون نظرة',
              arFew: '{n} أسئلة تستاهل نظرة',
              arMany: '{n} سؤال تستاهل نظرة',
              en1: '1 question worth a look',
              en: '{n} questions worth a look')),
      subtitle: empty ? 'sc_review_empty_sub'.tr : widget.courseTitle,
      actions: [
        if (!empty && all.isNotEmpty)
          AppButton.hot(
              label: 'sc_review_start'.tr, icon: Icons.play_arrow_rounded, onPressed: () => _practice(shown)),
      ],
    );

    Widget card;
    if (p.loading && total == 0) {
      card = const AppCard(child: AppLoadingState(items: 3));
    } else if (p.error != null && total == 0) {
      card = AppCard(child: AppErrorState(message: p.error, onRetry: p.load));
    } else if (empty) {
      card = AppCard(
        child: AppEmpty(
          icon: Icons.bookmark_added_outlined,
          title: 'sc_review_all_clear'.tr,
          message: 'sc_review_all_clear_sub'.tr,
          actionLabel: 'sc_review_back_to_exams'.tr,
          onAction: () => Navigator.maybePop(context),
        ),
      );
    } else {
      card = AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTabs(
            expand: true,
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
            items: [
              AppTabItem('sc_review_tab_saved'.tr, count: p.review.length),
              AppTabItem('sc_review_tab_wrong'.tr, count: p.read.length),
            ],
          ),
          if (courses.length > 1) ...[
            const SizedBox(height: AppSpace.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                AppChip(label: 'sc_all'.tr, selected: _course == null, onTap: () => setState(() => _course = null)),
                for (final id in courses) ...[
                  const SizedBox(width: AppSpace.xs),
                  AppChip(
                    label: widget.courseNames[id] ?? 'sc_course_n'.tr.replaceAll('{n}', appDigits('$id')),
                    leading: _Dot(color: subjectColors(context, widget.courseNames[id]).tone.color),
                    selected: _course == id,
                    onTap: () => setState(() => _course = id),
                  ),
                ],
              ]),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          AppWipeSwitcher(
            switchKey: '$_tab.$_course',
            child: _Bank(
              items: shown,
              wrong: _tab == 1,
              enabled: _tab == 0 ? p.settings.allowReview : p.settings.allowRead,
              courseNames: widget.courseNames,
              onGotIt: _tab == 0 ? p.removeReview : null,
            ),
          ),
        ]),
      );
    }

    return BasePage(
      appBar: AppHeader(title: 'sc_review_page_title'.tr),
      width: AppWidth.reading,
      child: AppRefresh(
        onRefresh: p.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpace.xl),
          children: [
            AppHeroOverlap(
              hero: hero,
              body: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), child: card),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AppSpace.xs + AppSpace.xxs / 2,
        height: AppSpace.xs + AppSpace.xxs / 2,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── One bank ────────────────────────────────────────────────────────────────────────────────────────────────────────

class _Bank extends StatelessWidget {
  const _Bank({
    required this.items,
    required this.wrong,
    required this.enabled,
    required this.courseNames,
    required this.onGotIt,
  });

  final List<FlaggedQuestion> items;
  final bool wrong;
  final bool enabled;
  final Map<int, String> courseNames;
  final Future<void> Function(FlaggedQuestion q)? onGotIt;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return AppEmpty(
        icon: wrong ? Icons.task_alt_rounded : Icons.bookmark_border_rounded,
        title: !enabled ? 'flag_disabled'.tr : (wrong ? 'flag_empty_read'.tr : 'flag_empty_review'.tr),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.sm),
        AppDeal(
          index: i,
          group: 'sc.review',
          child: ScFlaggedCard(
            key: ValueKey('sc.flag.${items[i].questionId}'),
            course: courseNames[items[i].courseId],
            exam: items[i].examName,
            question: items[i].title,
            yourAnswer: wrong ? items[i].lastWrongAnswer : null,
            rightAnswer: wrong ? items[i].correctAnswer : null,
            onGotIt: onGotIt == null ? null : () => onGotIt!(items[i]),
          ),
        ),
      ],
    ]);
  }
}

/// One question of the Review page, plain values: the course (with its colour) and the exam, the question, and for
/// a wrong one the student's answer beside the right one; "Got it" when the bookmark can be removed.
class ScFlaggedCard extends StatelessWidget {
  const ScFlaggedCard({
    super.key,
    this.course,
    required this.exam,
    required this.question,
    this.yourAnswer,
    this.rightAnswer,
    this.onGotIt,
  });

  final String? course;
  final String exam;
  final String question;
  final String? yourAnswer;
  final String? rightAnswer;
  final VoidCallback? onGotIt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = subjectColors(context, course);
    Widget answer(String label, String text, KitTone tone) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
          child: Text('$label: $text',
              textDirection: Helpers.textDirOf(text),
              style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600)),
        );
    return AppCard(
      variant: AppCardVariant.flat,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Dot(color: sub.tone.color),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                if (course != null)
                  TextSpan(text: '$course، ', style: TextStyle(color: sub.tone.ink, fontWeight: FontWeight.w600)),
                TextSpan(text: exam),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(question, textDirection: Helpers.textDirOf(question), style: AppType.tileTitle(context)),
        if (yourAnswer != null || rightAnswer != null) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if ((yourAnswer ?? '').isNotEmpty) answer('sc_review_your_answer'.tr, yourAnswer!, c.kit.live),
            if ((rightAnswer ?? '').isNotEmpty) answer('sc_review_right_answer'.tr, rightAnswer!, c.kit.ok),
          ]),
        ],
        if (onGotIt != null) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.ghost(label: 'sc_review_got_it'.tr, icon: Icons.check_rounded, onPressed: onGotIt, size: AppButtonSize.sm),
          ),
        ],
      ]),
    );
  }
}

// ── The run: one flash card at a time ───────────────────────────────────────────────────────────────────────────────

class ScReviewRunPage extends StatefulWidget {
  const ScReviewRunPage({super.key, required this.items, this.courseNames = const {}});

  final List<FlaggedQuestion> items;
  final Map<int, String> courseNames;

  @override
  State<ScReviewRunPage> createState() => _ScReviewRunPageState();
}

class _ScReviewRunPageState extends State<ScReviewRunPage> {
  int _i = 0;
  bool _flipped = false;

  void _go(int d) => setState(() {
        _i = (_i + d).clamp(0, widget.items.length - 1);
        _flipped = false;
      });

  @override
  Widget build(BuildContext context) {
    final q = widget.items[_i];
    final last = _i == widget.items.length - 1;
    Widget face(bool back) => AppCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDashSize.courseTile),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(back ? 'sc_review_right_answer'.tr : q.examName,
                  textAlign: TextAlign.center, style: AppType.meta(context)),
              const SizedBox(height: AppSpace.sm),
              Text(
                back ? (q.correctAnswer ?? 'sc_review_answer_after_result'.tr) : q.title,
                textAlign: TextAlign.center,
                textDirection: Helpers.textDirOf(back ? (q.correctAnswer ?? '') : q.title),
                style: AppType.section(context),
              ),
              if (!back && q.options.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                for (final o in q.options)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: AppTile(title: o, dense: true),
                  ),
              ],
            ]),
          ),
        );
    return AppAreaScope(
      area: AppArea.exam,
      child: BasePage(
        appBar: AppHeader(
            title: 'sc_review_run_title'.tr
                .replaceAll('{n}', appDigits('${_i + 1}'))
                .replaceAll('{m}', appDigits('${widget.items.length}'))),
        width: AppWidth.form,
        child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          AppProgressBar(value: (_i + 1) * 100 / widget.items.length),
          const SizedBox(height: AppSpace.md),
          GestureDetector(
            onTap: () => setState(() => _flipped = !_flipped),
            child: AppFlip3D(flipped: _flipped, front: face(false), back: face(true)),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(
            label: _flipped ? (last ? 'sc_review_done'.tr : 'sc_review_next'.tr) : 'sc_review_show_answer'.tr,
            expand: true,
            onPressed: () {
              if (!_flipped) {
                setState(() => _flipped = true);
              } else if (last) {
                Navigator.maybePop(context);
              } else {
                _go(1);
              }
            },
          ),
          if (_i > 0) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(label: 'sc_review_previous'.tr, expand: true, onPressed: () => _go(-1)),
          ],
        ]),
      ),
    );
  }
}
