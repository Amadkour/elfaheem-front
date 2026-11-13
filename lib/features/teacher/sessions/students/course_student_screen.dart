// course_student_screen.dart
//
// The students of one course, for its staff (D-870 – D-874; Warm Editorial, D-610 – D-629; master-detail, D-290).
// ─────────────────────────────────────────────────────────────────────────────
// What a teacher needs, in reading order:
//   • the page header (title, the course as its subtitle, Back) with Export and "Send a certificate to everyone";
//   • four figures for the whole course: enrolled, active this week, average progress, at risk (a tap shows them);
//   • when someone needs a nudge: ONE calm amber card, "5 students need a nudge · 3 have a linked parent", Nudge all;
//   • one search, one filter (All / Active / Low progress / Inactive / Completed, with counts) and the sort;
//   • the students: cards on phones, two columns on wide lists, each with its progress bar (the class average as the
//     marker), last activity (AppTime-free relative words), lessons done, the exam average, and only what needs
//     saying — the server's low-progress reason ("No activity for 12 days") and "Nudged 3 h ago". The bell nudges an
//     at-risk student; a long press selects several (a bar at the bottom nudges them together);
//   • a tapped card opens the student's connected detail in the shared panel (D-290), with Nudge and Certificates.
// The RULE behind "low progress" is the server's (services/course_students_service.py `classify`, D-871).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart' show EntitySummary;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_viewer_actions.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../admin/admin_common.dart' show t;
import '../../../teacher/home/teacher_models.dart';
import 'course_student_card.dart';
import 'course_student_provider.dart';
import 'course_students_nudge.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppFill, AppReveal;

class EnrolledStudentsScreen extends StatefulWidget {
  final TeacherCourse course;

  const EnrolledStudentsScreen({super.key, required this.course});

  @override
  State<EnrolledStudentsScreen> createState() => _EnrolledStudentsScreenState();
}

class _EnrolledStudentsScreenState extends State<EnrolledStudentsScreen> {
  final _search = TextEditingController();
  // A student card opens that student's connected detail (their courses with me, history, Message) in the shared panel
  // (D-290); the nudge and the certificates of this course stay one action away.
  final _panel = EntityPanelController(rowKind: EntityKind.student);

  String get _courseName => (AppConfig.lang == 'ar' ? widget.course.titleAr : widget.course.titleEn) ??
      widget.course.titleAr ??
      widget.course.titleEn ??
      '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<EnrolledStudentsProvider>();
    await provider.fetch(widget.course.id);
    if (!mounted || widget.course.certificates.isEmpty) return;
    await provider.loadIssuedForCertificates(
      widget.course.certificates.map((c) => c.id).toList(),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _panel.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification n) {
    // Fire loadMore a little before the true end, so the next page is
    // already in flight by the time the user reaches the bottom.
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
      context.read<EnrolledStudentsProvider>().loadMore();
    }
    return false;
  }

  void _nudge(List<EnrolledStudent> targets, {bool allLow = false}) {
    final p = context.read<EnrolledStudentsProvider>();
    openNudgeSheet(context, p, courseName: _courseName, targets: targets, allLow: allLow);
  }

  List<EntityPanelAction> _actions(BuildContext context, EntityRef ref, EntitySummary? s) {
    final p = context.read<EnrolledStudentsProvider>();
    final st = ref.kind == EntityKind.student ? p.students.where((x) => x.id == ref.id).firstOrNull : null;
    return [
      ...entityViewerActions(context, ref, s, controller: _panel),
      if (st != null && p.nudgeEnabled)
        EntityPanelAction(
          key: const ValueKey('md.course_student.nudge'),
          icon: Icons.notifications_active_outlined,
          label: st.canNudge ? t('تذكير', 'Nudge') : t('تم التذكير', 'Nudged'),
          onPressed: () => _nudge([st]),
        ),
      if (st != null && widget.course.certificates.isNotEmpty)
        EntityPanelAction(
          key: const ValueKey('md.course_student.certificates'),
          icon: Icons.workspace_premium_rounded,
          label: 'certificates'.tr,
          onPressed: () => _showStudentDialog(context, st, widget.course, _progressColorOf(context, st)),
        ),
    ];
  }

  Future<void> _export() async {
    final p = context.read<EnrolledStudentsProvider>();
    final all = await p.fetchAll();
    if (!mounted) return;
    if (all == null) {
      showAppNotice(t('تعذّر تحميل الطلاب للتصدير', 'Could not load the students to export'), error: true);
      return;
    }
    await showAppExportSheet(context, courseStudentsExport(all, courseName: _courseName, filter: p.filter, query: p.query));
  }

  Future<void> _sendCertificateToAll() async {
    final provider = context.read<EnrolledStudentsProvider>();
    final cert = await _pickCertificate(context, widget.course.certificates);
    if (cert == null || !mounted) return;
    final students = countText(provider.summary.enrolled,
        ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');
    final ok = await appConfirm(context, message: '${'send_to_all_confirm'.tr}\n\n${cert.title} · $students', confirmLabel: 'send_btn'.tr);
    if (!ok || !mounted) return;
    final sent = await provider.sendCertificateToAll(cert.id);
    if (!mounted) return;
    _showResultSnack(context, sent >= 0, '${'send_to_all_success'.tr} ($sent)');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();
    final course = widget.course;
    return BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      child: SafeArea(
        child: MasterDetailScaffold(
          controller: _panel,
          rootLabel: 'students'.tr,
          actions: (ref, s) => _actions(context, ref, s),
          list: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageHeader(
                title: 'enrolled_students_title'.tr,
                subtitle: _courseName,
                onBack: () => Navigator.maybePop(context),
                actions: [
                  AppIconButton(
                    key: const ValueKey('course_students.export'),
                    icon: Icons.ios_share_rounded,
                    tooltip: t('تصدير', 'Export'),
                    onPressed: p.summary.enrolled == 0 ? null : _export,
                  ),
                  if (course.certificates.isNotEmpty)
                    AppIconButton(
                      key: const ValueKey('course_students.certificate_all'),
                      icon: Icons.workspace_premium_rounded,
                      tooltip: 'send_to_all_students_btn'.tr,
                      busy: p.isBulkSending,
                      onPressed: p.summary.enrolled == 0 || p.isBulkSending ? null : _sendCertificateToAll,
                    ),
                ],
              ),
              Expanded(
                child: AppRefresh(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                          sliver: SliverToBoxAdapter(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              p.loadedOnce
                                  ? CourseStudentsSummaryGrid(
                                      summary: p.summary,
                                      onAtRisk: () => p.setFilter(StudentFilter.low),
                                    )
                                  : const _SummarySkeleton(),
                              if (p.nudgeEnabled && p.summary.lowNudgeable > 0 && !p.selecting) ...[
                                AppSpace.gapSm,
                                CourseStudentsNudgeBanner(
                                  students: p.summary.lowNudgeable,
                                  withParent: p.summary.lowWithParent,
                                  onNudgeAll: () => _nudge(const [], allLow: true),
                                ),
                              ],
                              AppSpace.gapMd,
                              CourseStudentsToolbar(
                                search: _search,
                                filter: p.filter,
                                sort: p.sort,
                                countOf: p.countOf,
                                onQuery: p.setQuery,
                                onFilter: p.setFilter,
                                onSort: p.setSort,
                              ),
                            ]),
                          ),
                        ),
                        _StudentsSliver(onRetry: _load, onNudge: (s) => _nudge([s])),
                      ],
                    ),
                  ),
                ),
              ),
              if (p.selecting)
                CourseStudentsSelectionBar(
                  count: p.selected.length,
                  canNudge: p.nudgeEnabled,
                  onClear: p.clearSelection,
                  onNudge: () => _nudge(p.selectedStudents),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The export (Export Studio): every student of the current search / filter / sort
// ─────────────────────────────────────────────────────────────────────────────

/// The Export Studio table of [students] (both languages' headers, D-130).
AppTableExport courseStudentsExport(List<EnrolledStudent> students,
    {required String courseName, StudentFilter filter = StudentFilter.all, String query = ''}) {
  return bilingualExport(() => AppTableExport(
        id: 'course.students',
        title: t('طلاب المقرر', 'Course students'),
        subtitle: courseName,
        filters: {
          if (filter != StudentFilter.all) t('التصفية', 'Filter'): filter.label,
          if (query.trim().isNotEmpty) t('بحث', 'Search'): query.trim(),
        },
        columns: [
          AppExportColumn('name', t('الطالب', 'Student'), locked: true),
          AppExportColumn('username', t('اسم المستخدم', 'Username'), visible: false),
          AppExportColumn('email', t('البريد', 'E-mail')),
          AppExportColumn('progress', t('التقدم', 'Progress'), type: AppColType.percent, total: AppTotal.average),
          AppExportColumn('lessons', t('الدروس المنجزة', 'Lessons done'), type: AppColType.integer),
          AppExportColumn('lessons_total', t('كل الدروس', 'All lessons'), type: AppColType.integer, visible: false),
          AppExportColumn('exam_avg', t('متوسط الاختبارات', 'Exam average'), type: AppColType.percent),
          AppExportColumn('last_active', t('آخر نشاط', 'Last active'), type: AppColType.dateTime),
          AppExportColumn('state', t('الحالة', 'Status'), type: AppColType.status, statusLabels: {
            'completed': t('أكمل', 'Completed'),
            'active': t('نشط', 'Active'),
            'low': t('تقدّم منخفض', 'Low progress'),
            'inactive': t('غير نشط', 'Inactive'),
            'new': t('جديد', 'New'),
          }, statusTones: const {
            'completed': AppStatusTone.good,
            'active': AppStatusTone.info,
            'low': AppStatusTone.warn,
            'inactive': AppStatusTone.bad,
            'new': AppStatusTone.neutral,
          }),
          AppExportColumn('reason', t('السبب', 'Reason')),
          AppExportColumn('parents', t('أولياء الأمور', 'Parents'), type: AppColType.integer, visible: false),
          AppExportColumn('nudged', t('آخر تذكير', 'Last nudge'), type: AppColType.dateTime, visible: false),
          AppExportColumn('enrolled', t('تاريخ التسجيل', 'Enrolled'), type: AppColType.dateTime, visible: false),
        ],
        rows: [
          for (final s in students)
            {
              'name': s.name,
              'username': s.username == null ? '' : '@${s.username}',
              'email': s.gmail,
              'progress': s.progressPercentage,
              'lessons': s.lessonsDone,
              'lessons_total': s.lessonsTotal,
              'exam_avg': s.examAvg,
              'last_active': s.lastActiveAt,
              'state': s.state,
              'reason': s.atRisk && s.risk != null ? riskText(s.risk!) : '',
              'parents': s.parentCount,
              'nudged': s.lastNudgedAt,
              'enrolled': parseServerUtc(s.enrolledAt),
            },
        ],
      ));
}

// ─────────────────────────────────────────────────────────────────────────────
// The figures, the nudge card, the toolbar, the selection bar (plain values: the layout harness pumps them)
// ─────────────────────────────────────────────────────────────────────────────

/// Enrolled · active this week · average progress · at risk (a tap filters to them).
class CourseStudentsSummaryGrid extends StatelessWidget {
  const CourseStudentsSummaryGrid({super.key, required this.summary, this.onAtRisk});

  final CourseStudentsSummary summary;
  final VoidCallback? onAtRisk;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final share = s.enrolled == 0 ? 0 : (s.activeWeek / s.enrolled * 100).round();
    return AppKpiGrid(maxColumns: 4, children: [
      AppStatCard(
        icon: Icons.people_alt_rounded,
        value: '${s.enrolled}',
        label: t('مسجّلون', 'Enrolled'),
        tone: AppBlockTone.emerald,
        footer: countText(s.completed,
            ar0: 'لم يُكمل أحد بعد', ar1: 'أكمل طالب واحد', ar2: 'أكمل طالبان', arFew: 'أكمل {n} طلاب', arMany: 'أكمل {n} طالبًا',
            en0: 'None completed yet', en1: '1 completed', en: '{n} completed'),
      ),
      AppStatCard(
        icon: Icons.bolt_rounded,
        value: '${s.activeWeek}',
        label: t('نشطون هذا الأسبوع', 'Active this week'),
        tone: AppBlockTone.sky,
        footer: t('$share٪ من الطلاب', '$share% of the class'),
      ),
      AppStatCard(
        icon: Icons.trending_up_rounded,
        value: '${s.avgProgress.round()}%',
        label: t('متوسط التقدم', 'Average progress'),
        tone: AppBlockTone.peach,
        footer: t('من دروس المقرر', 'of the course lessons'),
      ),
      AppStatCard(
        key: const ValueKey('course_students.at_risk'),
        icon: Icons.error_outline_rounded,
        value: '${s.atRisk}',
        label: t('يحتاجون متابعة', 'At risk'),
        tone: AppBlockTone.gold,
        footer: s.atRisk == 0 ? t('الجميع على المسار', 'Everyone is on track') : t('اضغط لعرضهم', 'Tap to see them'),
        onTap: s.atRisk == 0 ? null : onAtRisk,
      ),
    ]);
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => AppShimmer(
        child: AppKpiGrid(maxColumns: 4, children: [
          for (var i = 0; i < 4; i++) const AppSkeletonBox(height: 96, radius: AppSpace.md),
        ]),
      );
}

/// "5 students need a nudge · 3 have a linked parent" with Nudge all — the page's one call to action.
class CourseStudentsNudgeBanner extends StatelessWidget {
  const CourseStudentsNudgeBanner({super.key, required this.students, required this.withParent, required this.onNudgeAll});

  final int students;
  final int withParent;
  final VoidCallback onNudgeAll;

  /// From this width the button stands beside the text.
  static const double _row = 560;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = countText(students,
        ar1: 'طالب واحد يحتاج تذكيرًا', ar2: 'طالبان يحتاجان تذكيرًا', arFew: '{n} طلاب يحتاجون تذكيرًا', arMany: '{n} طالبًا يحتاجون تذكيرًا',
        en1: '1 student needs a nudge', en: '{n} students need a nudge');
    final sub = withParent == 0
        ? t('تذكير ودود يعيدهم إلى المسار.', 'A friendly reminder gets them back on track.')
        : t('$withParent منهم لديهم ولي أمر مرتبط يمكن إبلاغه.', '$withParent of them have a linked parent you can tell too.');
    final button = AppButton.primary(
      key: const ValueKey('course_students.nudge_all'),
      label: t('تذكير الكل', 'Nudge all'),
      icon: Icons.notifications_active_outlined,
      onPressed: onNudgeAll,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        // opaque over the card (the page doodles never show through the call to action)
        color: c.isDark ? Color.alphaBlend(c.warning.withValues(alpha: 0.14), c.cardBg) : appWashOn(context, c.warning),
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.warning.withValues(alpha: 0.22), width: AppBorder.hairline),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final text = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.notifications_active_outlined, size: AppIconSize.md, color: appInk(context, c.warning)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
        ]);
        if (box.maxWidth >= _row) {
          return Row(children: [Expanded(child: text), const SizedBox(width: AppSpace.sm), button]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          text,
          AppSpace.gapSm,
          Align(alignment: AlignmentDirectional.centerEnd, child: button),
        ]);
      }),
    );
  }
}

/// One search, one filter (with counts), the sort.
class CourseStudentsToolbar extends StatelessWidget {
  const CourseStudentsToolbar({
    super.key,
    required this.search,
    required this.filter,
    required this.sort,
    required this.countOf,
    required this.onQuery,
    required this.onFilter,
    required this.onSort,
  });

  final TextEditingController search;
  final StudentFilter filter;
  final StudentSort sort;
  final int Function(StudentFilter) countOf;
  final ValueChanged<String> onQuery;
  final ValueChanged<StudentFilter> onFilter;
  final ValueChanged<StudentSort> onSort;

  /// From this width the sort shows its label beside the search.
  static const double _labelled = 560;

  Future<void> _pickSort(BuildContext context) async {
    final picked = await showAppSheet<StudentSort>(
      context,
      (ctx) => AppSheetContent(
        title: t('ترتيب الطلاب', 'Sort students'),
        icon: Icons.sort_rounded,
        children: [
          for (final s in StudentSort.values)
            InkWell(
              key: ValueKey('course_students.sort.${s.wire}'),
              borderRadius: AppRadius.controlAll,
              onTap: () => Navigator.pop(ctx, s),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Row(children: [
                  Icon(s == sort ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      size: AppIconSize.md, color: s == sort ? ctx.colors.primary : ctx.colors.textLight),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(s.label, style: AppType.row(ctx))),
                ]),
              ),
            ),
        ],
      ),
    );
    if (picked != null) onSort(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        final labelled = box.maxWidth >= _labelled;
        return Row(children: [
          Expanded(
            child: AppSearchField(
              controller: search,
              hint: 'search_student_by_name_email'.tr,
              onChanged: onQuery,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          labelled
              ? AppPill(
                  key: const ValueKey('course_students.sort'),
                  icon: Icons.sort_rounded,
                  label: sort.label,
                  onTap: () => _pickSort(context),
                )
              : AppIconButton(
                  key: const ValueKey('course_students.sort'),
                  icon: Icons.sort_rounded,
                  tooltip: '${t('ترتيب', 'Sort')}: ${sort.label}',
                  onPressed: () => _pickSort(context),
                ),
        ]);
      }),
      AppSpace.gapSm,
      AppTabs(
        key: const ValueKey('course_students.filter'),
        items: [for (final f in StudentFilter.values) AppTabItem(f.label, count: countOf(f))],
        index: StudentFilter.values.indexOf(filter),
        onChanged: (i) => onFilter(StudentFilter.values[i]),
      ),
    ]);
  }
}

/// The selection's bar at the bottom: how many, Clear, Nudge.
class CourseStudentsSelectionBar extends StatelessWidget {
  const CourseStudentsSelectionBar({super.key, required this.count, required this.onClear, required this.onNudge, this.canNudge = true});

  final int count;
  final bool canNudge;
  final VoidCallback onClear;
  final VoidCallback onNudge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
        child: Row(children: [
          AppIconButton(
            key: const ValueKey('course_students.selection.clear'),
            icon: Icons.close_rounded,
            tooltip: t('إلغاء التحديد', 'Clear selection'),
            onPressed: onClear,
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              countText(count, ar1: 'طالب واحد محدد', ar2: 'طالبان محددان', arFew: '{n} طلاب محددون', arMany: '{n} طالبًا محددًا',
                  en1: '1 selected', en: '{n} selected'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong(context),
            ),
          ),
          if (canNudge)
            AppButton.primary(
              key: const ValueKey('course_students.selection.nudge'),
              label: t('تذكير', 'Nudge'),
              icon: Icons.notifications_active_outlined,
              onPressed: onNudge,
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body — cards on phones, two columns once there is room.
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsSliver extends StatelessWidget {
  final VoidCallback onRetry;
  final ValueChanged<EnrolledStudent> onNudge;

  const _StudentsSliver({required this.onRetry, required this.onNudge});

  /// From this list width the cards sit in two columns.
  static const double _twoColumns = 900;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    if (p.isLoading && p.students.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.only(top: AppSpace.sm),
        sliver: SliverToBoxAdapter(child: AppListSkeleton()),
      );
    }

    // A failed first load used to show "no students yet": say it failed and offer a retry.
    if (p.students.isEmpty && p.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppErrorState(message: p.errorMessage ?? 'failed_to_load'.tr, onRetry: onRetry),
      );
    }

    if (p.students.isEmpty) {
      final narrowed = p.summary.enrolled > 0 || p.query.isNotEmpty;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: narrowed
            ? AppEmpty(
                icon: p.filter == StudentFilter.low ? Icons.verified_rounded : Icons.search_off_rounded,
                title: p.filter == StudentFilter.low && p.query.isEmpty
                    ? t('لا أحد متأخر', 'Nobody is behind')
                    : t('لا يوجد طلاب هنا', 'No students here'),
                message: p.filter == StudentFilter.low && p.query.isEmpty
                    ? t('كل الطلاب على المسار. أحسنت!', 'Every student is on track. Nice work!')
                    : t('جرّب بحثًا آخر أو تصفية أخرى.', 'Try another search or filter.'),
                actionLabel: p.filter != StudentFilter.all ? t('عرض الكل', 'Show all') : null,
                onAction: p.filter != StudentFilter.all ? () => p.setFilter(StudentFilter.all) : null,
              )
            : AppEmpty(
                icon: Icons.people_outline_rounded,
                title: 'no_students'.tr,
                message: 'no_students_hint'.tr,
              ),
      );
    }

    // The list's own width: with the detail panel open beside it the list is narrower than the window.
    MasterDetailScope.maybeOf(context)?.controller.siblings = [
      for (final s in p.students) EntityRef(EntityKind.student, s.id, label: s.name, imageUrl: s.imageUrl),
    ];
    final now = DateTime.now().toUtc();
    return SliverLayoutBuilder(builder: (context, box) {
      final columns = box.crossAxisExtent >= _twoColumns ? 2 : 1;
      Widget card(int i) => AppReveal(
            index: i,
            group: 'course_students',
            child: _StudentTile(student: p.students[i], now: now, onNudge: onNudge),
          );
      final rows = (p.students.length / columns).ceil();
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
        sliver: SliverMainAxisGroup(slivers: [
          SliverList.separated(
            itemCount: rows,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
            itemBuilder: (_, r) {
              if (columns == 1) return card(r);
              final a = r * 2, b = a + 1;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: card(a)),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: b < p.students.length ? card(b) : const SizedBox.shrink()),
              ]);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
          SliverToBoxAdapter(child: _LoadMoreFooter(provider: p)),
        ]),
      );
    });
  }
}

/// A card wired to the provider and the panel: tap opens the student (or toggles while selecting), long press selects.
class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.student, required this.now, required this.onNudge});

  final EnrolledStudent student;
  final DateTime now;
  final ValueChanged<EnrolledStudent> onNudge;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();
    final panel = MasterDetailScope.maybeOf(context)?.controller;
    final ref = EntityRef(EntityKind.student, student.id, label: student.name, imageUrl: student.imageUrl);
    Widget build(bool open) => CourseStudentCard(
          student: student,
          now: now,
          classAverage: p.summary.enrolled > 1 ? p.summary.avgProgress : null,
          selected: open,
          selecting: p.selecting,
          checked: p.selected.contains(student.id),
          showNudge: p.nudgeEnabled && student.atRisk && student.canNudge,
          onTap: p.selecting ? () => p.toggleSelected(student.id) : () => EntityNavigator.open(context, ref),
          onLongPress: p.nudgeEnabled ? () => p.toggleSelected(student.id) : null,
          onNudge: () => onNudge(student),
        );
    if (panel == null) return build(false);
    return ListenableBuilder(listenable: panel, builder: (context, _) => build(panel.selectedId == student.id));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small footer under the list — a spinner while the next page loads, or a
// quiet "you've reached the end" once the server has nothing more to give.
// ─────────────────────────────────────────────────────────────────────────────

class _LoadMoreFooter extends StatelessWidget {
  final EnrolledStudentsProvider provider;

  const _LoadMoreFooter({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Center(
          child: SizedBox(
            width: AppIconSize.md,
            height: AppIconSize.md,
            child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: context.colors.primary),
          ),
        ),
      );
    }
    if (!provider.hasMore && provider.students.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Center(child: Text('end_of_list'.tr, style: AppType.meta(context))),
      );
    }
    return const SizedBox.shrink();
  }
}

/// "3 Nov 2026" through AppTime (platform / organization timezone), or the raw text when unreadable.
String _formatDate(String raw) {
  final d = parseServerUtc(raw);
  return d == null ? raw : AppTime.date(d);
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificates — the picker, the student's certificates dialog (the panel's Certificates action).
// ─────────────────────────────────────────────────────────────────────────────

class _RingAvatar extends StatelessWidget {
  final EnrolledStudent student;
  final Color color;

  const _RingAvatar({required this.student, required this.color});

  /// The ring's side and stroke; the photo sits [_gap] inside it.
  static const double _side = 52;
  static const double _stroke = 3;
  static const double _gap = 5;
  static const double _photo = _side - 2 * _gap;

  // One stable colour per student, from the theme's roles.
  Color _avatarColor(BuildContext context) {
    final c = context.colors;
    final palette = [c.primary, c.success, c.warning, c.accent2, c.purple];
    return palette[student.id % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final url = student.imageUrl;
    return SizedBox(
      width: _side,
      height: _side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AppFill(
              value: student.progressPercentage.clamp(0, 100) / 100,
              builder: (context, v) => CircularProgressIndicator(
                value: v,
                strokeWidth: _stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: context.colors.divider,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          ClipOval(
            child: (url != null && url.isNotEmpty)
                ? Image.network(
                    url,
                    width: _photo,
                    height: _photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _initials(context),
                  )
                : _initials(context),
          ),
        ],
      ),
    );
  }

  Widget _initials(BuildContext context) {
    final tone = _avatarColor(context);
    return Container(
      width: _photo,
      height: _photo,
      color: appTintOn(context, tone),
      alignment: Alignment.center,
      child: Text(
        student.initials,
        style: AppType.bodyStrong(context).copyWith(color: appInk(context, tone)),
      ),
    );
  }
}

/// The certificate picker's rows (a sheet): one 48 px row per certificate, the gold glyph, the title.
class _CertificatePicker extends StatelessWidget {
  final List<CourseCertificate> certificates;

  const _CertificatePicker({required this.certificates});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: 'choose_certificate_title'.tr,
      children: [
        for (final cert in certificates)
          InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: () => Navigator.pop(context, cert),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(children: [
                  Icon(Icons.workspace_premium_rounded, size: AppIconSize.md, color: c.accent2),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(cert.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                  Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the only certificate directly, or lets the teacher pick one.
Future<CourseCertificate?> _pickCertificate(
    BuildContext context, List<CourseCertificate> certs) async {
  if (certs.isEmpty) {
    showAppNotice('no_certificate_for_course'.tr, error: true);
    return null;
  }
  if (certs.length == 1) return certs.first;
  return showAppSheet<CourseCertificate>(context, (_) => _CertificatePicker(certificates: certs));
}

void _showResultSnack(BuildContext context, bool success, String okMessage) {
  showAppNotice(success ? okMessage : 'certificate_send_failed'.tr, error: !success);
}

// ─────────────────────────────────────────────────────────────────────────────
// Student's certificates — the kit's dialog, opened from the detail panel's
// Certificates action. The dialog lives on the root navigator, so the
// provider is re-supplied.
// ─────────────────────────────────────────────────────────────────────────────

Color _progressColorOf(BuildContext context, EnrolledStudent student) {
  if (student.progressPercentage >= 80) return context.colors.success;
  if (student.progressPercentage >= 40) return context.colors.primary;
  return context.colors.warning;
}

void _showStudentDialog(
    BuildContext context, EnrolledStudent student, TeacherCourse course, Color color) {
  final provider = context.read<EnrolledStudentsProvider>();
  showAppDialog<void>(
    context,
    title: student.name,
    body: ChangeNotifierProvider.value(
      value: provider,
      child: _StudentDetailsBody(student: student, course: course, color: color),
    ),
    actions: [
      Builder(builder: (ctx) => AppButton.ghost(label: 'close'.tr, onPressed: () => Navigator.pop(ctx))),
    ],
  );
}

class _StudentDetailsBody extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;
  final Color color;

  const _StudentDetailsBody({
    required this.student,
    required this.course,
    required this.color,
  });

  /// The progress bar's thickness.
  static const double _bar = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final provider = context.watch<EnrolledStudentsProvider>();
    final pct = student.progressPercentage.clamp(0, 100).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          _RingAvatar(student: student, color: color),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'stat_avg_progress'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context),
              ),
              const SizedBox(height: AppSpace.xxs),
              AppCountUp(
                '${pct.toStringAsFixed(0)}%',
                style: AppType.figureLarge(context).copyWith(color: appInk(context, color)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppFill(
          value: pct / 100,
          builder: (context, v) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: v,
              minHeight: _bar,
              backgroundColor: c.inputBg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _InfoRow(icon: Icons.email_outlined, label: 'email'.tr, value: student.gmail),
        _InfoRow(icon: Icons.event_available_outlined, label: 'joined'.tr, value: _formatDate(student.enrolledAt)),
        _InfoRow(icon: Icons.flag_outlined, label: 'status'.tr, value: student.status),
        const SizedBox(height: AppSpace.lg),
        Text('certificates'.tr, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        if (course.certificates.isEmpty)
          Text('no_certificate_for_course'.tr, style: AppType.meta(context))
        else
          for (final cert in course.certificates)
            _CertificateRow(cert: cert, student: student, provider: provider),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.sm),
          Text(label, style: AppType.meta(context)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.row(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One certificate inside the dialog: title, "sent N×" info, and a
/// send / resend button (always enabled, so it can be sent again).
class _CertificateRow extends StatelessWidget {
  final CourseCertificate cert;
  final EnrolledStudent student;
  final EnrolledStudentsProvider provider;

  const _CertificateRow({
    required this.cert,
    required this.student,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = provider.issuedCount(cert.id, student.id);
    final sending = provider.isSendingCertificate(cert.id, student.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, size: AppIconSize.md, color: c.accent2),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cert.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                if (count > 0)
                  Text(
                    '${'certificate_sent_label'.tr} · $count×',
                    style: AppType.meta(context).copyWith(color: appInk(context, c.success)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: AppButton.ghost(
              label: count > 0 ? 'resend_certificate_btn'.tr : 'send_certificate_btn'.tr,
              icon: count > 0 ? Icons.replay_rounded : Icons.send_rounded,
              size: AppButtonSize.sm,
              busy: sending,
              onPressed: provider.isBulkSending
                  ? null
                  : () async {
                      final ok = await provider.sendCertificate(cert.id, student.id);
                      if (!context.mounted) return;
                      _showResultSnack(context, ok, 'certificate_sent_success'.tr);
                    },
            ),
          ),
        ],
      ),
    );
  }
}
