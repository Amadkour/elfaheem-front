// student_exam_list_screen.dart: the student's exams (redesign S-C, Stu2Exams?screen=list).
//
// The exam area (grape): a hero ("Good luck, Faisal" / "You have 3 open exams"), then ONE card riding on it with the
// four stage tabs (Open · Coming · Handed in · Closed) and the exams dealt in (M5); "For review" (saved and got wrong,
// across every course) and the exams waiting on this phone sit under it on a phone, beside it on the web. Every card
// opens the exam's page (start, passcode, consent and results live there, unchanged); a course chip still opens the
// course in the shared panel (D-290).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_api.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_screen.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/sc_exam_widgets.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_api.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_detail_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart' show OfflineExamsList;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

/// The four stages of the list, in the tabs' order.
enum ScExamStage { open, coming, handedIn, closed }

/// Which stage [e] is in at [now].
ScExamStage scExamStageOf(StudentExamListItem e, DateTime now) {
  if (e.isSubmitted) return ScExamStage.handedIn;
  if (e.startDate != null && e.startDate!.isAfter(now)) return ScExamStage.coming;
  if (e.isFrozen) return ScExamStage.closed;
  return ScExamStage.open;
}

class StudentExamListScreen extends StatefulWidget {
  const StudentExamListScreen({super.key, this.asTab = false, this.flagsApi, this.showOffline = !kIsWeb});

  /// Inside a role shell: the shell draws the top bar.
  final bool asTab;
  final StudentFlagsApi? flagsApi;

  /// The exams waiting on this phone (phones only; off in tests).
  final bool showOffline;

  @override
  State<StudentExamListScreen> createState() => _StudentExamListScreenState();
}

class _StudentExamListScreenState extends State<StudentExamListScreen> {
  // An exam's course chip opens that course (progress, what is due, Continue learning) in the shared panel (D-290).
  final _panel = EntityPanelController(rowKind: EntityKind.course);
  late final StudentFlagsApi _flags = widget.flagsApi ?? StudentFlagsApi();
  int _tab = 0;
  ({int saved, int wrong})? _review;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentExamProvider>().loadMyExams();
      _loadReview();
    });
  }

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  Future<void> _loadReview() async {
    try {
      final r = await Future.wait([_flags.fetchReview(), _flags.fetchRead()]);
      if (!mounted) return;
      setState(() => _review = (saved: (r[0] as ReviewBank).items.length, wrong: (r[1] as ReadBank).items.length));
    } catch (_) {
      // the review card is a shortcut: without it the list still works
    }
  }

  Future<void> _reload() async {
    await Future.wait([context.read<StudentExamProvider>().loadMyExams(), _loadReview()]);
  }

  void _open(StudentExamListItem exam) {
    final prov = context.read<StudentExamProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: prov, child: StudentExamDetailScreen(exam: exam)),
      ),
    );
  }

  void _openReview([int tab = 0]) {
    final names = {
      for (final e in context.read<StudentExamProvider>().myExams)
        if (e.courseName != null) e.courseId: e.courseName!,
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => StudentFlagsScreen(initialTab: tab, courseNames: names)))
        .then((_) => _loadReview());
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final name = Provider.of<MyAuthProvider?>(context)?.currentUser?.name;
    final now = DateTime.now();
    final byStage = {for (final s in ScExamStage.values) s: <StudentExamListItem>[]};
    for (final e in prov.myExams) {
      byStage[scExamStageOf(e, now)]!.add(e);
    }
    final open = byStage[ScExamStage.open]!;

    final hero = AppHero(
      wipe: false,
      kicker: 'sc_exam_good_luck'.tr.replaceAll('{name}', scFirstName(name, 'sir'.tr)),
      title: appDigits(countText(open.length,
          ar0: 'ما عندك اختبار مفتوح الحين',
          ar1: 'عندك اختبار واحد مفتوح',
          ar2: 'عندك اختباران مفتوحان',
          arFew: 'عندك {n} اختبارات مفتوحة',
          arMany: 'عندك {n} اختبارًا مفتوحًا',
          en0: 'No open exams right now',
          en1: 'You have 1 open exam',
          en: 'You have {n} open exams')),
      trailing: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChip(
          label: 'sc_exam_review_questions'.tr,
          icon: Icons.bookmark_border_rounded,
          onHero: true,
          count: _review == null ? null : _review!.saved + _review!.wrong,
          onTap: _openReview,
        ),
      ]),
    );

    final listCard = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTabs(
          expand: true,
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
          items: [
            AppTabItem('sc_exam_tab_open'.tr, count: open.length),
            AppTabItem('sc_exam_tab_coming'.tr, count: byStage[ScExamStage.coming]!.length),
            AppTabItem('sc_exam_tab_handed_in'.tr, count: byStage[ScExamStage.handedIn]!.length),
            AppTabItem('sc_exam_tab_closed'.tr, count: byStage[ScExamStage.closed]!.length),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        AppWipeSwitcher(
          switchKey: _tab,
          child: _StageList(
            stage: ScExamStage.values[_tab],
            exams: byStage[ScExamStage.values[_tab]]!,
            loading: prov.loadingList && prov.myExams.isEmpty,
            error: prov.listError,
            onRetry: prov.loadMyExams,
            onOpen: _open,
          ),
        ),
      ]),
    );

    final side = <Widget>[
      ScReviewSummary(saved: _review?.saved ?? 0, wrong: _review?.wrong ?? 0, onOpen: _openReview),
      if (widget.showOffline) const OfflineExamsList(shrinkWrap: true),
    ];

    final body = LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= Breakpoints.desktop;
      final gutter = wide ? AppSpace.lg : AppSpace.md;
      final content = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: listCard),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(children: [
                  for (final w in side) ...[w, const SizedBox(height: AppSpace.md)],
                ]),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              listCard,
              for (final w in side) ...[const SizedBox(height: AppSpace.md), w],
            ]);
      return AppRefresh(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpace.xl),
          children: [
            AppHeroOverlap(
              hero: hero,
              body: Padding(padding: EdgeInsets.symmetric(horizontal: gutter), child: content),
            ),
          ],
        ),
      );
    });

    return AppAreaScope(
      area: AppArea.exam,
      child: BasePage(
        appBar: widget.asTab ? null : AppHeader(title: 'sc_exam_title'.tr),
        width: AppWidth.wide,
        child: MasterDetailScaffold(controller: _panel, rootLabel: 'sc_exam_title'.tr, list: body),
      ),
    );
  }
}

// ── One stage ───────────────────────────────────────────────────────────────────────────────────────────────────────

class _StageList extends StatelessWidget {
  const _StageList({
    required this.stage,
    required this.exams,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final ScExamStage stage;
  final List<StudentExamListItem> exams;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<StudentExamListItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppLoadingState(items: 3);
    if (error != null && exams.isEmpty) return AppErrorState(message: error, onRetry: onRetry);
    if (exams.isEmpty) {
      final (icon, title) = switch (stage) {
        ScExamStage.open => (Icons.task_alt_rounded, 'sc_exam_empty_open'.tr),
        ScExamStage.coming => (Icons.event_available_outlined, 'sc_exam_empty_coming'.tr),
        ScExamStage.handedIn => (Icons.inbox_outlined, 'sc_exam_empty_handed_in'.tr),
        ScExamStage.closed => (Icons.lock_open_rounded, 'sc_exam_empty_closed'.tr),
      };
      return AppEmpty(icon: icon, title: title);
    }
    // the forward button is ONE per screen: the first exam the student is in the middle of
    final firstOngoing = exams.indexWhere((e) => stage == ScExamStage.open && e.answeredCount > 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < exams.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.sm),
        AppDeal(index: i, group: 'sc.exams', child: _card(context, exams[i], i == firstOngoing)),
      ],
    ]);
  }

  Widget _card(BuildContext context, StudentExamListItem e, bool forward) {
    final ongoing = stage == ScExamStage.open && e.answeredCount > 0;
    final facts = <String>[
      if ((e.duration ?? 0) > 0) countText(e.duration!, ar1: 'دقيقة', ar2: 'دقيقتان', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes'),
      countText(e.questionCount, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤال', en1: '1 question', en: '{n} questions'),
      if (stage == ScExamStage.handedIn && e.percentage != null)
        'sc_exam_best_score'.tr.replaceAll('{n}', e.percentage!.toStringAsFixed(0))
      else if ((e.maxSubmissions ?? 0) > 1 && e.submissionCount > 0)
        'sc_exam_attempt_of'.tr.replaceAll('{n}', '${e.submissionCount + (ongoing ? 0 : 1)}').replaceAll('{m}', '${e.maxSubmissions}')
      else if ((e.maxSubmissions ?? 0) > 1)
        countText(e.maxSubmissions!, ar1: 'محاولة واحدة', ar2: 'محاولتين', arFew: '{n} محاولات', arMany: '{n} محاولة', en1: '1 attempt', en: '{n} attempts'),
    ];
    final (foot, tone) = _foot(e);
    final (label, action) = switch (stage) {
      ScExamStage.open when ongoing => ('sc_exam_continue'.tr, forward ? ScExamAction.hot : ScExamAction.ghost),
      ScExamStage.open => ('sc_exam_start'.tr, ScExamAction.ghost),
      ScExamStage.handedIn when e.canRetry => ('sc_exam_try_again'.tr, ScExamAction.ghost),
      ScExamStage.handedIn => ('sc_exam_see_result'.tr, ScExamAction.link),
      ScExamStage.closed => ('sc_exam_details'.tr, ScExamAction.link),
      ScExamStage.coming => (null, ScExamAction.link),
    };
    return ScExamCard(
      key: ValueKey('sc.exam.${e.id}'),
      title: e.name,
      subject: e.courseName,
      icon: switch (stage) {
        ScExamStage.handedIn => e.passed == true ? Icons.emoji_events_outlined : Icons.task_alt_rounded,
        ScExamStage.closed => Icons.lock_outline_rounded,
        ScExamStage.coming => Icons.schedule_rounded,
        ScExamStage.open => Icons.quiz_outlined,
      },
      subtitle: e.courseName == null
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: EntityChip(
                  key: ValueKey('md.exam.course.${e.id}'), EntityRef(EntityKind.course, e.courseId, label: e.courseName!)),
            ),
      facts: facts,
      foot: foot,
      footTone: tone,
      hot: ongoing && forward,
      actionLabel: label,
      action: action,
      onAction: () => onOpen(e),
      onTap: () => onOpen(e),
    );
  }

  (String?, ScFootTone) _foot(StudentExamListItem e) {
    final now = DateTime.now();
    switch (stage) {
      case ScExamStage.coming:
        return ('sc_exam_opens_at'.tr.replaceAll('{t}', AppTime.dateTime(e.startDate!.toUtc())), ScFootTone.muted);
      case ScExamStage.closed:
        return (e.isSubmissionsFrozen ? 'sc_exam_no_attempts_left'.tr : 'sc_exam_time_over'.tr, ScFootTone.muted);
      case ScExamStage.handedIn:
        if (e.passed == null) return ('sc_exam_with_teacher'.tr, ScFootTone.warn);
        return (e.passed! ? 'sc_exam_passed'.tr : 'sc_exam_not_passed'.tr, e.passed! ? ScFootTone.ok : ScFootTone.muted);
      case ScExamStage.open:
        final end = e.endDate;
        if (end == null) return (null, ScFootTone.muted);
        final left = end.difference(now);
        if (left.inMinutes < 60) {
          return (countText(left.inMinutes.clamp(1, 59), ar1: 'باقي دقيقة', ar2: 'باقي دقيقتين', arFew: 'باقي {n} دقائق', arMany: 'باقي {n} دقيقة', en1: '1 minute left', en: '{n} minutes left'),
              ScFootTone.live);
        }
        if (left.inHours < 48) return ('sc_exam_closes_at'.tr.replaceAll('{t}', AppTime.dateTime(end.toUtc())), ScFootTone.warn);
        return ('sc_exam_closes_on'.tr.replaceAll('{t}', AppTime.date(end.toUtc())), ScFootTone.muted);
    }
  }
}
