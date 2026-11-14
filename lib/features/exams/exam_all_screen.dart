// "All exams" (D-300): the one page with every exam the person manages — search, status tabs, course and type
// filters, quick actions; cards on a phone, a dense list on a wide window. Data and filters: `exam_all.dart`.
//
// Opened from the teacher's analytics page (header icon, the exam pass-rate tile) and from a course's exams page
// (hero icon). "New exam" asks which course (when there is a choice) and opens the quick builder, where "Import from
// Google Forms" is one of the ways to start.
//
// AllExamsBody / AllExamCard / AllExamRow / NewExamPlaceList take plain values (under the layout harness).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t;
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart';
import 'package:flutter_education_app/features/exams/exam_authoring_screen.dart' show ExamEditorScreen;
import 'package:flutter_education_app/features/exams/exam_paper_sheet.dart' show openExamPaper;
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart' show openQuickExam;
import 'package:flutter_education_app/features/exams/exam_results_screen.dart';

/// What a quick action does to one exam.
enum AllExamAction { edit, results, publish, paper }

/// Opens the page (a no-op while the kill switch is on).
Future<void> openAllExams(BuildContext context) async {
  if (AppConfig.disableList.contains(kAllExamsFeatureKey)) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllExamsScreen()));
}

/// The organizations the person works in (not where they study), from the app's organization overview.
Map<int, String> staffOrgs() {
  final out = <int, String>{};
  for (final e in AppModeController.instance.liveEntries) {
    if (!AppModeController.opensDashboard(e)) continue;
    final org = asMap(e['organization']);
    if (org['id'] == null) continue;
    out[asInt(org['id'])] = '${org['name'] ?? ''}'.trim();
  }
  return out;
}

class AllExamsScreen extends StatefulWidget {
  const AllExamsScreen({super.key, this.loader});

  /// Tests: replaces [loadAllExams].
  final Future<AllExamsData> Function()? loader;

  @override
  State<AllExamsScreen> createState() => _AllExamsScreenState();
}

class _AllExamsScreenState extends State<AllExamsScreen> {
  final _api = ExamAuthoringApi();
  AllExamsData? _data;
  Object? _error;
  DateTime? _updated;
  AllExamsFilter _filter = const AllExamsFilter();
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.loader == null) {
        final mode = AppModeController.instance;
        if (!mode.loaded) await mode.ready();
      }
      final d = await (widget.loader?.call() ?? loadAllExams(orgs: staffOrgs()));
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _newExam() async {
    final d = _data;
    final places = d == null ? newExamPlaces(const AllExamsData(exams: [])) : newExamPlaces(d);
    NewExamPlace? place = places.first;
    if (places.length > 1) {
      place = await showAppSheet<NewExamPlace>(
          context,
          (ctx) => AppSheetContent(
                title: t('لأي مقرر هذا الاختبار؟', 'Which course is this exam for?'),
                children: [NewExamPlaceList(places: places, onPick: (p) => Navigator.pop(ctx, p))],
              ));
    }
    if (place == null || !mounted) return;
    await openQuickExam(context, courseId: place.courseId, orgId: place.orgId, course: place.courseId == null ? '' : place.name);
    if (mounted) _load();          // also after a draft opened in the editor (the builder handed over to it)
  }

  Future<void> _act(AllExam e, AllExamAction a) async {
    final nav = Navigator.of(context);
    switch (a) {
      case AllExamAction.edit:
        await nav.push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: e.id, courseId: e.courseId, orgId: e.orgId)));
      case AllExamAction.results:
        await nav.push(MaterialPageRoute(builder: (_) => ExamResultsScreen(examId: e.id, examTitle: e.displayTitle, courseId: e.courseId)));
      case AllExamAction.paper:
        await openExamPaper(context, examId: e.id, course: _data?.courseName(e) ?? '');
      case AllExamAction.publish:
        if (e.questionCount == 0) {
          showAppNotice(t('أضف أسئلة قبل النشر — افتح الاختبار في المحرر', 'Add questions before publishing — open the exam in the editor'), error: true);
          return;
        }
        final ok = await appConfirm(context,
            message: t('نشر «${e.displayTitle}»؟ يراه الطلاب ويمكنهم أداؤه في موعده.', 'Publish "${e.displayTitle}"? Students will see it and can take it when it opens.'),
            confirmLabel: t('نشر', 'Publish'));
        if (!ok || !mounted) return;
        setState(() => _busy.add(e.id));
        final r = await _api.lifecycle(e.id, ExamAction.publish);
        if (!mounted) return;
        setState(() => _busy.remove(e.id));
        showAppNotice(r.ok ? t('نُشر الاختبار', 'The exam is published') : authoringError(r), error: !r.ok);
    }
    if (mounted) _load();
  }

  String? get _errorText {
    final e = _error;
    return e == null ? null : ApiException.from(e).message;
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final counts = d == null ? const <String?, int>{} : allExamCounts(d, _filter);
    final total = d?.exams.where((e) => e.status != 'archived').length;
    final nav = Navigator.of(context);
    return BasePage(
      key: const ValueKey(kAllExamsFeatureKey),
      enableFooterWidget: false,
      child: ColoredBox(
        color: context.colors.background,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _HeaderBand(
              child: AppPageHeader(
            accent: false,
            title: t('كل الاختبارات', 'All exams'),
            subtitle: total == null
                ? t('كل اختبار تديره في مكان واحد', 'Every exam you manage, in one place')
                : countText(total, ar1: 'اختبار واحد', ar2: 'اختباران', arFew: '{n} اختبارات', arMany: '{n} اختباراً', en1: '1 exam', en: '{n} exams', ar0: 'لا اختبارات بعد', en0: 'No exams yet'),
            icon: Icons.fact_check_rounded,
            onBack: nav.canPop() ? () => nav.maybePop() : null,
            onRefresh: _load,
            updatedAt: _updated,
            primaryAction: AppButton.primary(
                key: const ValueKey('exam.all.new'), label: t('اختبار جديد', 'New exam'), icon: Icons.add_rounded, onPressed: _newExam),
            search: AppSearchField(
              hint: t('ابحث باسم الاختبار أو المقرر', 'Search by exam or course name'),
              onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v)),
            ),
            bottom: AppTabs(
              items: [for (final s in allExamStatuses) AppTabItem(allExamStatusTab(s), count: d == null ? null : counts[s])],
              index: allExamStatuses.indexOf(_filter.status),
              onChanged: (i) => setState(() => _filter = _filter.copyWith(status: allExamStatuses[i])),
            ),
          )),
          Expanded(
            child: AppRefresh(
              onRefresh: _load,
              child: AllExamsBody(
                data: d,
                error: _errorText,
                filter: _filter,
                busy: _busy,
                onFilter: (f) => setState(() => _filter = f),
                onRetry: _load,
                onNew: _newExam,
                onAction: _act,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The header's band: the brand strip and the card colour run the full width, the header itself sits in the
/// content column.
class _HeaderBand extends StatelessWidget {
  const _HeaderBand({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const AppAccentStrip(),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: allExamsMaxWidth + 2 * AppSpace.lg), child: child),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════ the body ═══════════════════════════════════════════════════════════════

/// From this width the list is a dense table instead of cards.
const allExamsDenseFrom = 900.0;

/// The content column's widest.
const allExamsMaxWidth = 1240.0;

class AllExamsBody extends StatelessWidget {
  const AllExamsBody({
    super.key,
    required this.data,
    required this.filter,
    required this.onFilter,
    required this.onAction,
    required this.onRetry,
    required this.onNew,
    this.error,
    this.busy = const {},
  });

  /// null = still loading.
  final AllExamsData? data;
  final String? error;
  final AllExamsFilter filter;
  final Set<int> busy;
  final ValueChanged<AllExamsFilter> onFilter;
  final void Function(AllExam, AllExamAction) onAction;
  final VoidCallback onRetry;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return LayoutBuilder(builder: (context, box) {
      final dense = box.maxWidth >= allExamsDenseFrom;
      final pad = EdgeInsets.symmetric(
          horizontal: box.maxWidth > allExamsMaxWidth + 2 * AppSpace.lg ? (box.maxWidth - allExamsMaxWidth) / 2 : (dense ? AppSpace.lg : AppSpace.md),
          vertical: AppSpace.md);
      final List<Widget> children;
      if (error != null && d == null) {
        children = [AppErrorState(message: error, onRetry: onRetry)];
      } else if (d == null) {
        children = const [AppListSkeleton(items: 5)];
      } else {
        final shown = filterAllExams(d, filter);
        children = [
          AllExamsFilterBar(data: d, filter: filter, onFilter: onFilter),
          AppSpace.gapMd,
          if (d.fallback) ...[
            AppBanner(
                icon: Icons.info_outline_rounded,
                text: t('يعرض الخادم الحالي اختبارات حسابك والمؤسسات التي لديك فيها صلاحية الاختبارات فقط.',
                    'This server lists your own exams and those of organizations where you hold exam rights only.')),
            AppSpace.gapMd,
          ],
          if (d.exams.isEmpty)
            AppEmpty(
                icon: Icons.fact_check_outlined,
                title: t('لا اختبارات بعد', 'No exams yet'),
                message: t('أنشئ أول اختبار: يدوياً، أو مولّداً من مستندات المقرر، أو من ملف، أو من Google Forms.',
                    'Create your first exam: by hand, generated from the course documents, from a file or from Google Forms.'),
                actionLabel: t('اختبار جديد', 'New exam'),
                onAction: onNew)
          else if (shown.isEmpty)
            AppEmpty(
                icon: Icons.filter_alt_off_rounded,
                title: t('لا اختبارات تطابق', 'No matching exams'),
                message: t('غيّر البحث أو التصفية.', 'Change the search or the filters.'),
                actionLabel: filter.narrowed ? t('مسح التصفية', 'Clear filters') : null,
                onAction: filter.narrowed ? () => onFilter(AllExamsFilter(status: filter.status)) : null)
          else if (dense)
            AllExamTable(exams: shown, data: d, busy: busy, onAction: onAction)
          else
            for (final e in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AllExamCard(
                  exam: e,
                  course: d.courseName(e),
                  org: d.orgName(e),
                  busy: busy.contains(e.id),
                  onAction: (a) => onAction(e, a),
                ),
              ),
        ];
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: children,
      );
    });
  }
}

/// The course and type filters (the status sits in the header's tabs).
class AllExamsFilterBar extends StatelessWidget {
  const AllExamsFilterBar({super.key, required this.data, required this.filter, required this.onFilter});
  final AllExamsData data;
  final AllExamsFilter filter;
  final ValueChanged<AllExamsFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final courses = data.coursesWithExams;
    final course = courses.length < 2 && !data.anyWithoutCourse
        ? null
        : AppDropdown<int?>(
            key: const ValueKey('exam.all.course'),
            value: filter.courseId,
            decoration: InputDecoration(labelText: t('المقرر', 'Course'), prefixIcon: const Icon(Icons.menu_book_rounded, size: 20)),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(t('كل المقررات', 'All courses'))),
              for (final c in courses) DropdownMenuItem<int?>(value: c.$1, child: Text(c.$2, overflow: TextOverflow.ellipsis)),
              if (data.anyWithoutCourse)
                DropdownMenuItem<int?>(value: AllExamsFilter.noCourse, child: Text(t('بدون مقرر', 'Without a course'))),
            ],
            onChanged: (v) => onFilter(filter.copyWith(courseId: v)),
          );
    final chips = [
      AppChoiceChip(label: t('كل الأنواع', 'All types'), selected: filter.type == null, onTap: () => onFilter(filter.copyWith(type: null))),
      for (final k in AllExamType.values)
        AppChoiceChip(
            label: allExamTypeLabel(k),
            icon: allExamTypeIcon(k),
            selected: filter.type == k,
            onTap: () => onFilter(filter.copyWith(type: filter.type == k ? null : k))),
    ];
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 640;
      final types = narrow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.xs), chips[i]],
              ]),
            )
          : Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: chips);
      if (course == null) return types;
      if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [course, AppSpace.gapSm, types]);
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 300, child: course),
        AppSpace.gapMd,
        Expanded(child: types),
      ]);
    });
  }
}

IconData allExamTypeIcon(AllExamType k) => switch (k) {
      AllExamType.online => Icons.devices_rounded,
      AllExamType.paper => Icons.print_outlined,
      AllExamType.file => Icons.description_outlined,
    };

AppTone allExamTone(String status) => switch (status) {
      'draft' => AppTone.warning,
      'published' => AppTone.success,
      'closed' => AppTone.info,
      _ => AppTone.neutral,
    };

/// The one action a tap on the exam (or its main button) takes: drafts are edited, the rest show their results.
AllExamAction allExamMainAction(AllExam e) => e.draft ? AllExamAction.edit : AllExamAction.results;

String allExamActionLabel(AllExamAction a) => switch (a) {
      AllExamAction.edit => t('تعديل', 'Edit'),
      AllExamAction.results => t('النتائج', 'Results'),
      AllExamAction.publish => t('نشر', 'Publish'),
      AllExamAction.paper => t('ورقة الطباعة', 'Printable paper'),
    };

IconData allExamActionIcon(AllExamAction a) => switch (a) {
      AllExamAction.edit => Icons.edit_outlined,
      AllExamAction.results => Icons.leaderboard_rounded,
      AllExamAction.publish => Icons.publish_rounded,
      AllExamAction.paper => Icons.print_rounded,
    };

/// The actions of the ⋯ menu.
List<AllExamAction> allExamMenu(AllExam e) => [
      AllExamAction.edit,
      if (!e.draft) AllExamAction.results,
      if (e.draft) AllExamAction.publish,
      if (e.type != AllExamType.file) AllExamAction.paper,
    ];

/// "Starts Thu 5 Nov, 11:00" / "Created …" (or nothing).
String? allExamWhenText(AllExam e) {
  if (e.startsAt != null) return t('يبدأ ${AppTime.dateTime(e.startsAt!)}', 'Starts ${AppTime.dateTime(e.startsAt!)}');
  if (e.createdAt != null) return t('أُنشئ ${AppTime.date(e.createdAt!)}', 'Created ${AppTime.date(e.createdAt!)}');
  return null;
}

String allExamQuestionsText(int n) =>
    countText(n, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤالاً', en1: '1 question', en: '{n} questions', ar0: 'بلا أسئلة', en0: 'No questions');

String allExamAttemptsText(int n) =>
    countText(n, ar1: 'محاولة واحدة', ar2: 'محاولتان', arFew: '{n} محاولات', arMany: '{n} محاولة', en1: '1 attempt', en: '{n} attempts', ar0: 'لا محاولات', en0: 'No attempts');

class _ExamMenu extends StatelessWidget {
  const _ExamMenu({required this.exam, required this.onAction});
  final AllExam exam;
  final ValueChanged<AllExamAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<AllExamAction>(
      tooltip: t('إجراءات', 'Actions'),
      icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
      onSelected: onAction,
      itemBuilder: (_) => [
        for (final a in allExamMenu(exam))
          PopupMenuItem<AllExamAction>(
            value: a,
            child: Row(children: [
              Icon(allExamActionIcon(a), size: 18, color: c.textMedium),
              AppSpace.gapSm,
              Flexible(child: Text(allExamActionLabel(a))),
            ]),
          ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.exam, this.size = 44});
  final AllExam exam;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = appToneColor(context, allExamTone(exam.status));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Icon(allExamTypeIcon(exam.type), color: tone == c.textLight ? c.primary : tone, size: size * .5),
    );
  }
}

/// One exam on a phone.
class AllExamCard extends StatelessWidget {
  const AllExamCard({super.key, required this.exam, this.course, this.org, this.busy = false, required this.onAction});
  final AllExam exam;
  final String? course, org;
  final bool busy;
  final ValueChanged<AllExamAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final where = [?course, if (org != null && org!.isNotEmpty) org!].join(' · ');
    final when = allExamWhenText(e);
    final main = allExamMainAction(e);
    return AppCard(
      key: ValueKey('exam.all.card.${e.id}'),
      onTap: () => onAction(main),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: _TypeTile(exam: e)),
          AppSpace.gapSm,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
                if (where.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                ],
              ]),
            ),
          ),
          _ExamMenu(exam: e, onAction: onAction),
        ]),
        AppSpace.gapSm,
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppStatusBadge(label: examStatusLabel(e.status), tone: allExamTone(e.status), dot: true, dense: true),
            AppStatusBadge(label: allExamQuestionsText(e.questionCount), icon: Icons.quiz_outlined, dense: true),
            if (!e.draft) AppStatusBadge(label: allExamAttemptsText(e.attempts), icon: Icons.assignment_turned_in_outlined, dense: true),
          ]),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: AppSpace.xs, end: AppSpace.sm),
          child: Row(children: [
            Expanded(
              child: Text(when ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
            ),
            AppSpace.gapXs,
            e.draft
                ? AppButton.tonal(
                    label: allExamActionLabel(AllExamAction.publish),
                    icon: allExamActionIcon(AllExamAction.publish),
                    size: AppButtonSize.sm,
                    busy: busy,
                    onPressed: busy ? null : () => onAction(AllExamAction.publish))
                : AppButton.tonal(
                    label: allExamActionLabel(AllExamAction.results),
                    icon: allExamActionIcon(AllExamAction.results),
                    size: AppButtonSize.sm,
                    onPressed: () => onAction(AllExamAction.results)),
          ]),
        ),
      ]),
    );
  }
}

/// The dense list on a wide window: one row per exam, the columns lined up.
class AllExamTable extends StatelessWidget {
  const AllExamTable({super.key, required this.exams, required this.data, required this.onAction, this.busy = const {}});
  final List<AllExam> exams;
  final AllExamsData data;
  final Set<int> busy;
  final void Function(AllExam, AllExamAction) onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = appText(12, w: FontWeight.w700, c: c.textMedium);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
          child: Row(children: [
            const SizedBox(width: 36 + AppSpace.sm),
            Expanded(flex: 5, child: Text(t('الاختبار', 'Exam'), style: head)),
            SizedBox(width: 120, child: Text(t('الحالة', 'Status'), style: head)),
            SizedBox(width: 96, child: Text(t('الأسئلة', 'Questions'), style: head)),
            SizedBox(width: 96, child: Text(t('المحاولات', 'Attempts'), style: head)),
            Expanded(flex: 2, child: Text(t('الموعد', 'When'), style: head)),
            const SizedBox(width: 130 + 48),
          ]),
        ),
        Divider(height: 1, color: c.divider),
        for (var i = 0; i < exams.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
          AllExamRow(
            exam: exams[i],
            course: data.courseName(exams[i]),
            org: data.orgName(exams[i]),
            busy: busy.contains(exams[i].id),
            onAction: (a) => onAction(exams[i], a),
          ),
        ],
      ]),
    );
  }
}

class AllExamRow extends StatelessWidget {
  const AllExamRow({super.key, required this.exam, this.course, this.org, this.busy = false, required this.onAction});
  final AllExam exam;
  final String? course, org;
  final bool busy;
  final ValueChanged<AllExamAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final where = [?course, if (org != null && org!.isNotEmpty) org!].join(' · ');
    final cell = appText(13, c: c.textDark);
    return InkWell(
      key: ValueKey('exam.all.row.${e.id}'),
      onTap: () => onAction(allExamMainAction(e)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        child: Row(children: [
          _TypeTile(exam: e, size: 36),
          AppSpace.gapSm,
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(e.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
              Text(where.isEmpty ? allExamTypeLabel(e.type) : '$where · ${allExamTypeLabel(e.type)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
            ]),
          ),
          SizedBox(
              width: 120,
              child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppStatusBadge(label: examStatusLabel(e.status), tone: allExamTone(e.status), dot: true, dense: true))),
          SizedBox(width: 96, child: Text('${e.questionCount}', style: cell)),
          SizedBox(width: 96, child: Text(e.draft ? '—' : '${e.attempts}', style: cell)),
          Expanded(
              flex: 2,
              child: Text(e.startsAt != null ? AppTime.dateTime(e.startsAt!) : (e.createdAt != null ? AppTime.date(e.createdAt!) : '—'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium))),
          SizedBox(
            width: 130,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: e.draft
                  ? AppButton.ghost(
                      label: allExamActionLabel(AllExamAction.publish),
                      icon: allExamActionIcon(AllExamAction.publish),
                      size: AppButtonSize.sm,
                      busy: busy,
                      onPressed: busy ? null : () => onAction(AllExamAction.publish))
                  : AppButton.ghost(
                      label: allExamActionLabel(AllExamAction.results),
                      icon: allExamActionIcon(AllExamAction.results),
                      size: AppButtonSize.sm,
                      onPressed: () => onAction(AllExamAction.results)),
            ),
          ),
          SizedBox(width: 48, child: _ExamMenu(exam: e, onAction: onAction)),
        ]),
      ),
    );
  }
}

/// "Which course is this exam for?" (plain values).
class NewExamPlaceList extends StatelessWidget {
  const NewExamPlaceList({super.key, required this.places, required this.onPick});
  final List<NewExamPlace> places;
  final ValueChanged<NewExamPlace> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final p in places)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            onTap: () => onPick(p),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              Icon(p.courseId == null ? Icons.person_outline_rounded : Icons.menu_book_rounded, color: c.primary, size: 22),
              AppSpace.gapSm,
              Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark))),
              Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        ),
    ]);
  }
}
