// lib/features/admin/admin_courses_page.dart — all courses: the table, the connected detail, full control.
//
// D-290: the list is a MasterDetailScaffold over AppDataTable (server-side search, filters, sort and numbered pages; a
// card per course on a phone). A row opens the course's detail panel; its category and teacher are links. The panel's
// quick actions and the row's menu are every action the old sheet had: Edit, Publish, Mark completed and Move to
// trash directly; Manage opens the sheet below for what needs a form (per-course payment provider, allowed methods
// and platform fee, private access code, resubscribe, the plans and income in full, recent payments, exams).
library;

import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart' show EntitySummary;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_bidi.dart' show ltrIsolate;
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_pagination.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart'
    show EntityProgress, EntityThumb, mdCourseStatusLabel, mdPercent, mdStudents;
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/outline_button.dart';
import '../../utils/widget/primary_button.dart';
import '../shared/course/course_price_tag.dart' show coursePriceLabel;
import '../student/models.dart' show AppCurrencyX;
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_labels.dart';
import 'admin_page.dart';
import 'admin_table_export.dart' show adminCoursesExport, exportPagedList;
import 'admin_bulk.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_table_export.dart' show showAppExportSheet;
import 'admin_models.dart';
import 'admin_providers.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppCard, AppDropdown, AppEmpty, AppListSkeleton;
import '../shared/exam_engine/exam_review_screen.dart' show EngineReviewSection;
import 'package:flutter_education_app/core/display/app_fonts.dart';

class AdminCoursesPage extends StatelessWidget {
  const AdminCoursesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminCoursesProvider()..refresh(),
    child: _CoursesView(embedded: embedded),
  );
}

// ── premium filters ─────────────────────────────────────────────────────────

const _courseSort = SortSpec({
  'newest': 'admin_sort_newest',
  'oldest': 'admin_sort_oldest',
  'name_asc': 'admin_sort_name_asc',
  'name_desc': 'admin_sort_name_desc',
  'price_asc': 'admin_sort_price_asc',
  'price_desc': 'admin_sort_price_desc',
  'students_desc': 'md_sort_students_desc',
  'students_asc': 'md_p5_sort_students_asc',
  'rating_desc': 'md_sort_rating_desc',
  'rating_asc': 'md_p5_sort_rating_asc',
  'completion_desc': 'md_p5_sort_completion_desc',
  'completion_asc': 'md_p5_sort_completion_asc',
});

const _courseSpecs = <FilterSpec>[
  FilterSpec.tri('published', 'admin_filter_publish_state', yesKey: 'published', noKey: 'status_draft'),
  FilterSpec.choice('status', 'admin_filter_status', {
    'in_progress': 'admin_in_progress',
    'completed': 'completed',
  }),
  FilterSpec.lookup('teacher_id', 'admin_filter_teacher', 'teachers'),
  FilterSpec.lookup('category_id', 'admin_filter_category', 'categories'),
  FilterSpec.remoteChoice('type', 'admin_filter_course_type', 'course_types'),
  FilterSpec.remoteChoice('currency', 'admin_filter_currency', 'currencies'),
  FilterSpec.numberRange('price_min', 'price_max', 'admin_filter_price'),
  FilterSpec.tri('is_private', 'admin_filter_private'),
  FilterSpec.tri('discount_active', 'admin_filter_discount'),
  FilterSpec.tri('has_students', 'admin_filter_has_students'),
  FilterSpec.tri('has_pending_payments', 'admin_filter_pending_payments'),
  FilterSpec.dateRange('created_from', 'created_to', 'admin_filter_created'),
];

/// The table column of the server's sort value, and back.
const _sortOfColumn = {
  'title': ('name_asc', 'name_desc'),
  'students': ('students_asc', 'students_desc'),
  'completion': ('completion_asc', 'completion_desc'),
  'rating': ('rating_asc', 'rating_desc'),
  'price': ('price_asc', 'price_desc'),
  'created': ('oldest', 'newest'),
};

/// Columns whose first tap shows the largest first (the question is "which course leads?").
const _largestFirst = {'students', 'completion', 'rating', 'created'};

EntityRef _refOf(AdminCourse c) => EntityRef(EntityKind.course, c.id,
    label: asStrOrNull(c.j['name_ar']), labelEn: asStrOrNull(c.j['name_en']) ?? c.name, imageUrl: c.imageUrl);

/// The course's name in the app language.
String _nameOf(AdminCourse c) {
  final n = _refOf(c).name;
  return n.isEmpty ? '#${c.id}' : n;
}

/// The one status a row shows: in the trash, a draft, finished, or on sale.
(String, AppTone) _statusOf(AdminCourse c) {
  if (c.archived) return (mdCourseStatusLabel('archived'), AppTone.danger);
  if (!c.isPublished) return (mdCourseStatusLabel('draft'), AppTone.neutral);
  if (c.status == 'completed') return (mdCourseStatusLabel('completed'), AppTone.brand);
  return (mdCourseStatusLabel('published'), AppTone.success);
}

String _priceOf(AdminCourse c) => coursePriceLabel(AppCurrencyX.fromCode(c.currency), c.finalPrice);

String? _typeOf(AdminCourse c) => switch (c.type.toLowerCase()) {
      'recorded' => 'session_type_recorded'.tr,
      'live' => 'session_type_live'.tr,
      'both' => 'session_type_both'.tr,
      _ => null,
    };

String _pendingText(int n) => countText(n,
    ar1: 'دفعة معلقة', ar2: 'دفعتان معلقتان', arFew: '{n} دفعات معلقة', arMany: '{n} دفعة معلقة',
    en1: '1 pending payment', en: '{n} pending payments');

/// The line under a course's name: its type and what deserves a look.
String _factsOf(AdminCourse c) => [
      ?_typeOf(c),
      if (c.isPrivate) 'md_private'.tr,
      if (c.discountActive) ltrIsolate('-${c.discountPercentage.toStringAsFixed(0)}%'),
      if (c.pendingPayments > 0) _pendingText(c.pendingPayments),
    ].join(' · ');

class _CoursesView extends StatefulWidget {
  const _CoursesView({required this.embedded});

  final bool embedded;

  @override
  State<_CoursesView> createState() => _CoursesViewState();
}

class _CoursesViewState extends State<_CoursesView> {
  /// The detail panel of the list (D-290).
  final EntityPanelController _panel = EntityPanelController(rowKind: EntityKind.course);
  final TextEditingController _search = TextEditingController();

  /// The row drawn as selected: the panel's, kept here so the table redraws only when it changes.
  int? _selected;

  /// The rows ticked in the table (bulk actions, D-290 phase 8).
  final Set<Object> _picked = {};

  List<AdminCourse> _pickedRows(List<AdminCourse> rows) => [
        for (final c in rows)
          if (_picked.contains(c.id)) c,
      ];

  Future<void> _bulkPublish(List<AdminCourse> rows, bool published) async {
    final label = (published ? 'publish_exam' : 'admin_unpublish').tr;
    if (!await confirmAdminBulk(context, label, rows.length, danger: !published) || !mounted) return;
    await runAdminBulk([for (final c in rows) c.id],
        (id) => ApiClient.instance.put('/api/v1/admin/courses/$id', body: {'is_published': published}),
        refresh: _p.reloadPage);
    for (final c in rows) {
      EntitiesApi.instance.invalidate(_refOf(c));
    }
    if (mounted) setState(_picked.clear);
  }

  List<Widget> _bulkActions(List<AdminCourse> rows) {
    final picked = _pickedRows(rows);
    return [
      adminBulkButton('publish_exam'.tr, Icons.visibility_rounded, () => _bulkPublish(picked, true)),
      adminBulkButton('admin_unpublish'.tr, Icons.visibility_off_rounded, () => _bulkPublish(picked, false)),
      adminBulkButton('md_p8_export_selected'.tr, Icons.file_download_outlined,
          () => showAppExportSheet(context, adminCoursesExport([for (final c in picked) c.j]))),
    ];
  }

  AdminCoursesProvider get _p => context.read<AdminCoursesProvider>();

  @override
  void initState() {
    super.initState();
    _panel.addListener(_panelChanged);
  }

  void _panelChanged() {
    final id = _panel.selectedId;
    if (id == _selected) return;
    void apply() {
      if (mounted) setState(() => _selected = _panel.selectedId);
    }
    // `?open=` opens the panel while the list is being built: redraw after that frame.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // the shell's Refresh reloads the page on screen: filters, search text and the page stay
    AdminRefreshScope.register(context, context.read<AdminCoursesProvider>().reloadPage);
  }

  @override
  void dispose() {
    _panel.removeListener(_panelChanged);
    _panel.dispose();
    _search.dispose();
    super.dispose();
  }

  // ── actions (the row's menu, the panel's quick actions and the Manage sheet share them) ─────────────────────────

  /// A course changed: the detail shows it again.
  void _changed(int id) {
    final ref = EntityRef(EntityKind.course, id);
    EntitiesApi.instance.invalidate(ref);
    if (mounted && _panel.current == ref) _panel.reload();
  }

  Future<void> _manage(int id) async {
    final p = _p;
    final exit = await showAdminSheet<_ManageExit>(
      context,
      (ctx) => ChangeNotifierProvider.value(value: p, child: _CourseDetail(id: id)),
    );
    _changed(id);
    if (!mounted) return;
    switch (exit) {
      case _ManageExit.edit:
        await _edit(id);
      case _ManageExit.trashed:
        _closeIfOpen(id);
      case _ManageExit.done:
      case null:
        break;
    }
  }

  Future<void> _edit(int id) async {
    final p = _p;
    final course = await p.detail(id);
    if (course == null || !mounted) return;
    await _openCourseForm(context, p, existing: course);
    _changed(id);
  }

  Future<void> _setPublished(int id, bool published) async {
    if (await _p.update(id, {'is_published': published})) _changed(id);
  }

  Future<void> _setCompleted(int id, bool completed) async {
    if (await _p.update(id, {'status': completed ? 'completed' : 'in_progress'})) _changed(id);
  }

  Future<void> _trash(int id) async {
    final p = _p;
    final ok = await confirm(
      context,
      message: 'course_trash_confirm'.tr,
      danger: true,
      confirmLabel: 'course_move_to_trash'.tr,
    );
    if (!ok) return;
    if (await p.remove(id, force: true)) _closeIfOpen(id);
  }

  void _closeIfOpen(int id) {
    EntitiesApi.instance.invalidate(EntityRef(EntityKind.course, id));
    if (mounted && _panel.root == EntityRef(EntityKind.course, id)) _panel.close();
  }

  /// The panel's quick actions on a course this admin manages; a link inside the panel opens other kinds, which have
  /// their own lists.
  List<EntityPanelAction> _panelActions(EntityRef ref, EntitySummary? s) {
    if (ref.kind != EntityKind.course || s?.can.manage != true) return const [];
    final inTrash = s!.time('archived_at') != null;
    final published = s.flag('is_published') == true;
    final completed = s.text('status') == 'completed';
    return [
      EntityPanelAction(
        key: const ValueKey('md.course.manage'),
        icon: Icons.tune_rounded,
        label: 'md_manage'.tr,
        onPressed: () => _manage(ref.id),
      ),
      EntityPanelAction(
        key: const ValueKey('md.course.edit'),
        icon: Icons.edit_rounded,
        label: 'btn_edit'.tr,
        onPressed: () => _edit(ref.id),
      ),
      if (!inTrash) ...[
        EntityPanelAction(
          key: const ValueKey('md.course.publish'),
          icon: published ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          label: published ? 'admin_unpublish'.tr : 'publish_exam'.tr,
          onPressed: () => _setPublished(ref.id, !published),
        ),
        EntityPanelAction(
          key: const ValueKey('md.course.complete'),
          icon: completed ? Icons.replay_rounded : Icons.flag_rounded,
          label: completed ? 'admin_reopen'.tr : 'admin_mark_completed'.tr,
          onPressed: () => _setCompleted(ref.id, !completed),
        ),
      ],
    ];
  }

  List<AppRowAction<AdminCourse>> _rowActions(AdminCourse c) => [
        AppRowAction(icon: Icons.open_in_new_rounded, label: 'md_p5_open'.tr, onTap: () => _panel.open(_refOf(c))),
        AppRowAction(icon: Icons.edit_rounded, label: 'btn_edit'.tr, onTap: () => _edit(c.id)),
        if (!c.archived) ...[
          AppRowAction(
            icon: c.isPublished ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            label: c.isPublished ? 'admin_unpublish'.tr : 'publish_exam'.tr,
            onTap: () => _setPublished(c.id, !c.isPublished),
          ),
          AppRowAction(
            icon: c.status == 'completed' ? Icons.replay_rounded : Icons.flag_rounded,
            label: c.status == 'completed' ? 'admin_reopen'.tr : 'admin_mark_completed'.tr,
            onTap: () => _setCompleted(c.id, c.status != 'completed'),
          ),
        ],
        AppRowAction(icon: Icons.tune_rounded, label: 'md_manage'.tr, onTap: () => _manage(c.id)),
        if (!c.archived)
          AppRowAction(
            icon: Icons.delete_outline_rounded,
            label: 'course_move_to_trash'.tr,
            danger: true,
            onTap: () => _trash(c.id),
          ),
      ];

  // ── the table ─────────────────────────────────────────────────────────────────────────────────────────────────

  String? _sortColumn(String? sort) {
    for (final e in _sortOfColumn.entries) {
      if (e.value.$1 == sort || e.value.$2 == sort) return e.key;
    }
    return null;
  }

  void _onSort(AdminCoursesProvider p, String key, bool asc) {
    final pair = _sortOfColumn[key];
    if (pair == null) return;
    final fresh = _sortColumn(p.sort) != key;
    p.setSort(fresh && _largestFirst.contains(key) || !asc ? pair.$2 : pair.$1);
  }

  List<AppTableColumn<AdminCourse>> _columns() => [
        AppTableColumn(
          key: 'title',
          label: 'md_kind_course'.tr,
          primary: true,
          sortable: true,
          flex: 5,
          cell: (ctx, c) => _TitleCell(c),
        ),
        AppTableColumn(
          key: 'category',
          label: 'category_label'.tr,
          flex: 3,
          hideBelow: 1040,
          cell: (ctx, c) => _LinkCell(_categoryRef(c)),
        ),
        AppTableColumn(
          key: 'teacher',
          label: 'admin_teacher'.tr,
          flex: 3,
          cell: (ctx, c) => _LinkCell(_teacherRef(c), avatar: true),
        ),
        AppTableColumn.text(
          key: 'students',
          label: 'md_stat_students'.tr,
          sortable: true,
          numeric: true,
          width: 100,
          text: (c) => '${c.studentsCount}',
        ),
        AppTableColumn(
          key: 'completion',
          label: 'md_stat_completion'.tr,
          sortable: true,
          width: 128,
          hideBelow: 800,
          cell: (ctx, c) => _CompletionCell(c),
        ),
        AppTableColumn(
          key: 'rating',
          label: 'md_stat_rating'.tr,
          sortable: true,
          numeric: true,
          width: 88,
          hideBelow: 900,
          cell: (ctx, c) => _RatingCell(c),
        ),
        AppTableColumn.text(
          key: 'price',
          label: 'admin_price'.tr,
          sortable: true,
          numeric: true,
          width: 100,
          text: _priceOf,
        ),
        AppTableColumn(
          key: 'status',
          label: 'status'.tr,
          width: 104,
          cell: (ctx, c) {
            final (label, tone) = _statusOf(c);
            return AppStatusBadge(label: label, tone: tone, dense: true);
          },
        ),
        AppTableColumn.text(
          key: 'income',
          label: 'admin_income'.tr,
          numeric: true,
          width: 112,
          hideBelow: 1320,
          text: (c) => ltrIsolate(money(c.income, c.currency)),
        ),
        AppTableColumn.text(
          key: 'created',
          label: 'admin_filter_created'.tr,
          sortable: true,
          width: 104,
          hideBelow: 1240,
          text: (c) => shortDate(c.createdAt),
        ),
      ];

  /// The search lives in the table toolbar; this is the rest of the ONE row of controls: publishing, the filter sheet
  /// (category, teacher, status, dates, the sort …) and Export.
  Widget _controls(BuildContext context, AdminCoursesProvider p) {
    final published = p.published;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: AppDropdown<String>(
            value: published == null ? 'all' : (published ? 'pub' : 'draft'),
            decoration: InputDecoration(labelText: 'admin_filter_publish_state'.tr),
            items: [
              DropdownMenuItem(value: 'all', child: Text('filter_all'.tr)),
              DropdownMenuItem(value: 'pub', child: Text('published'.tr)),
              DropdownMenuItem(value: 'draft', child: Text('status_draft'.tr)),
            ],
            onChanged: (v) => p.setPublished(v == null || v == 'all' ? null : v == 'pub'),
          ),
        ),
      ),
      const SizedBox(width: AppSpace.xxs),
      AdminFilterButton(host: p, specs: _courseSpecs, sort: _courseSort, quickKeys: const {'published'}),
      AppIconButton(
        icon: Icons.ios_share_rounded,
        tooltip: 'md_p5_export'.tr,
        onPressed: p.rows.isEmpty ? null : () => exportPagedList(context, p, adminCoursesExport),
      ),
    ]);
  }

  void _clearAll(AdminCoursesProvider p) {
    _search.clear();
    p.clearAll();
  }

  String _totalText(int n) => countText(n,
      ar0: 'لا دورات', ar1: 'دورة واحدة', ar2: 'دورتان', arFew: '{n} دورات', arMany: '{n} دورة',
      en0: 'No courses', en1: '1 course', en: '{n} courses');

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminCoursesProvider>();
    final courses = p.courses;
    _panel.siblings = [for (final c in courses) _refOf(c)]; // previous / next and the keyboard walk these rows
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final state = p.error != null && p.rows.isEmpty
        ? AppTableState.error
        : (!p.loaded && p.isLoading ? AppTableState.loading : AppTableState.ready);

    final table = AppDataTable<AdminCourse>(
      state: state,
      errorText: p.error,
      onRetry: p.refresh,
      rows: courses,
      rowId: (c) => c.id,
      tableId: 'admin_courses',
      columnMenu: true,
      columnResize: true,
      maxInlineActions: 0,
      selectedRowId: _selected,
      selectable: true,
      selected: _picked,
      onSelectionChanged: (s) => setState(() => _picked
        ..clear()
        ..addAll(s)),
      bulkActions: (_) => _bulkActions(courses),
      onRowHover: (c) => EntitiesApi.instance.prefetch(_refOf(c)),
      searchHint: 'admin_search_course_name'.tr,
      searchController: _search,
      onSearch: p.setSearch,
      toolbarTrailing: _controls(context, p),
      columns: _columns(),
      mobileCard: (ctx, c) => _CourseCard(c),
      sortKey: _sortColumn(p.sort),
      sortAscending: _sortOfColumn[_sortColumn(p.sort)]?.$1 == p.sort,
      onSort: (k, asc) => _onSort(p, k, asc),
      onRowTap: (c) => _panel.open(_refOf(c)),
      rowActions: _rowActions,
      empty: p.hasActiveQuery
          ? AppEmpty(
              icon: Icons.search_off_rounded,
              title: 'ds_no_results'.tr,
              message: 'ds_no_results_hint'.tr,
              actionLabel: 'ds_clear_filters'.tr,
              onAction: () => _clearAll(p),
            )
          : AppEmpty(icon: Icons.auto_stories_outlined, title: 'admin_no_courses_found'.tr),
      onClearFilters: () => _clearAll(p),
      pagination: p.loaded && p.total > 0
          ? AppPagination(
              page: p.page,
              pageCount: p.pages,
              total: p.total,
              pageSize: p.pageSize,
              onPage: p.goToPage,
              onPageSize: wide ? p.setPageSize : null, // a phone keeps its one line of paging
            )
          : null,
    );

    final page = AdminPage(
      helpPageId: 'admin.courses',
      title: 'courses'.tr,
      icon: Icons.auto_stories_rounded,
      subtitle: wide && p.loaded ? _totalText(p.total) : null,
      showBack: !widget.embedded,
      maxWidth: double.infinity,
      onRefresh: p.reloadPage,
      primaryAction: AppButton.primary(
        key: const ValueKey('courses_add'),
        label: 'admin_add_course'.tr,
        icon: Icons.add_rounded,
        onPressed: () => _openCourseForm(context, p),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminActiveFilterChips(host: p, specs: _courseSpecs, sort: _courseSort, quickKeys: const {'published'}),
          if (p.incomeByCurrency.isNotEmpty) _IncomeStrip(income: p.incomeByCurrency),
          Expanded(child: table),
        ]),
      ),
    );
    return MasterDetailScaffold(
      controller: _panel,
      list: page,
      rootLabel: 'courses'.tr,
      deepLinks: widget.embedded,
      actions: _panelActions,
    );
  }
}

EntityRef? _categoryRef(AdminCourse c) {
  final j = asMap(c.j['category']);
  if (j.isEmpty) return null;
  return EntityRef(EntityKind.category, asInt(j['id']), label: asStrOrNull(j['name_ar']), labelEn: asStrOrNull(j['name_en']));
}

EntityRef? _teacherRef(AdminCourse c) {
  final j = asMap(c.j['teacher']);
  if (j.isNotEmpty) {
    return EntityRef(EntityKind.teacher, asInt(j['id']), label: asStrOrNull(j['name']), imageUrl: asStrOrNull(j['image_url']));
  }
  return c.teacherId == 0 ? null : EntityRef(EntityKind.teacher, c.teacherId, label: c.teacherName);
}

/// What every course earned after discounts, one figure per currency (the table's pages show one course at a time).
class _IncomeStrip extends StatelessWidget {
  const _IncomeStrip({required this.income});

  final Map<String, double> income;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // each amount stays whole inside Arabic; the figures drop to their own line when the width asks for it
    final figures = [for (final e in income.entries) ltrIsolate(money(e.value, e.key))].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Semantics(
        container: true,
        child: Wrap(
          spacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: AppIconSize.md, color: c.textMedium),
            Text('admin_total_course_income_after_discounts'.tr, style: AppType.meta(context)),
            Text(figures,
                style: AppType.bodyStrong(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}

/// The cover, the name and the line under it (the name alone in compact rows).
class _TitleCell extends StatelessWidget {
  const _TitleCell(this.course);

  final AdminCourse course;

  @override
  Widget build(BuildContext context) {
    final compact = AppDataTable.compactOf(context);
    final facts = compact ? '' : _factsOf(course);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? AppSpace.xxs : AppSpace.xs),
      child: Row(children: [
        EntityThumb(_refOf(course), size: compact ? AppSpace.lg + AppSpace.xxs : AppSpace.xl + AppSpace.xs),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_nameOf(course), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            if (facts.isNotEmpty)
              Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

/// A category or teacher as a link; "—" when the course has none.
class _LinkCell extends StatelessWidget {
  const _LinkCell(this.entity, {this.avatar = false});

  final EntityRef? entity;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    final ref = entity;
    if (ref == null) return Text('—', style: AppType.meta(context));
    return EntityChip(ref,
        avatar: avatar,
        showIcon: false,
        minHeight: AppDataTable.compactOf(context) ? AppSpace.xl : AppTouch.min);
  }
}

/// The share of students who finished, as a small bar; "—" before anyone counts.
class _CompletionCell extends StatelessWidget {
  const _CompletionCell(this.course);

  final AdminCourse course;

  @override
  Widget build(BuildContext context) {
    if (course.studentsCount == 0 && course.completionRate == 0) return Text('—', style: AppType.meta(context));
    return EntityProgress(course.completionRate, tone: context.colors.primary);
  }
}

class _RatingCell extends StatelessWidget {
  const _RatingCell(this.course);

  final AdminCourse course;

  @override
  Widget build(BuildContext context) {
    final r = course.ratingAvg;
    if (r == null) return Text('—', style: AppType.meta(context));
    return Semantics(
      label: '${'md_stat_rating'.tr} ${r.toStringAsFixed(1)}, ${course.ratingCount}',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: AppIconSize.sm, color: context.colors.warning),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(r.toStringAsFixed(1), maxLines: 1, style: AppType.row(context))),
      ]),
    );
  }
}

/// A course on a phone (and in a list a panel left narrow): the same facts as the table's row, in the same order.
class _CourseCard extends StatelessWidget {
  const _CourseCard(this.course);

  final AdminCourse course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, tone) = _statusOf(course);
    final facts = _factsOf(course);
    final category = _categoryRef(course), teacher = _teacherRef(course);
    final rating = course.ratingAvg;
    final meta = AppType.meta(context);
    Widget fact(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        EntityThumb(_refOf(course), size: AppSpace.xxl),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_nameOf(course), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            if (facts.isNotEmpty) Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
            const SizedBox(height: AppSpace.xxs),
            AppStatusBadge(label: label, tone: tone, dense: true),
          ]),
        ),
      ]),
      if (category != null || teacher != null)
        Wrap(spacing: AppSpace.xs, children: [
          if (category != null) EntityChip(category, showIcon: false, maxWidth: 160),
          if (teacher != null) EntityChip(teacher, avatar: true, showIcon: false, maxWidth: 180),
        ]),
      Wrap(
        spacing: AppSpace.md,
        runSpacing: AppSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          fact(Icons.groups_rounded, mdStudents(course.studentsCount)),
          if (rating != null) fact(Icons.star_rounded, rating.toStringAsFixed(1)),
          fact(Icons.sell_outlined, _priceOf(course)),
          if (course.studentsCount > 0)
            fact(Icons.workspace_premium_outlined, '${'md_stat_completion'.tr} ${mdPercent(course.completionRate)}'),
        ],
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Manage: the forms behind the panel (payment settings, access, plans, exams)
// ═════════════════════════════════════════════════════════════════════════════

/// How the Manage sheet closed.
enum _ManageExit { done, edit, trashed }

class _CourseDetail extends StatefulWidget {
  const _CourseDetail({required this.id});

  final int id;

  @override
  State<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends State<_CourseDetail> {
  AdminCourse? course;
  Map<String, dynamic> raw = {};
  bool loading = true;

  // payment-settings form
  String? provider; // null = default
  bool restrictMethods = false;
  final Set<String> methods = {'card', 'bank_transfer', 'instapay'};
  final _fee = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await context.read<AdminCoursesProvider>().detail(widget.id);
    final rawMap = await context.read<AdminCoursesProvider>().detailRaw(widget.id);
    if (!mounted) return;
    setState(() {
      course = r;
      raw = rawMap ?? {};
      loading = false;
      if (r != null) {
        provider = r.paymentSettings.provider;
        final allowed = r.paymentSettings.allowedMethods;
        restrictMethods = allowed != null;
        methods
          ..clear()
          ..addAll(allowed ?? const ['card', 'bank_transfer', 'instapay']);
        _fee.text = r.paymentSettings.feePercent?.toString() ?? '';
      }
    });
  }

  String _randomCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  Future<void> _changeCode(int id) async {
    final ctrl = TextEditingController(text: (raw['access_code'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: dir,
          child: AlertDialog(
            scrollable: true,
            title: Text('admin_change_access_code'.tr,
                style: TextStyle(fontFamily: AppFonts.family)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(
                  controller: ctrl,
                  label: 'admin_access_code_hint'.tr,
                  keyboard: TextInputType.number,
                ),
                TextButton.icon(
                  onPressed: () => setS(() => ctrl.text = _randomCode()),
                  icon: const Icon(Icons.casino_rounded, size: 18),
                  label: Text('admin_generate_code'.tr),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('exam_cancel'.tr),
              ),
              TextButton(
                onPressed: () {
                  if (!RegExp(r'^\d{6}$').hasMatch(ctrl.text.trim())) {
                    toast('admin_code_6_digits'.tr, error: true);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text('save'.tr),
              ),
            ],
          ),
        ),
      ),
    );
    final code = ctrl.text.trim();
    disposeAfterRoute([ctrl]);
    if (ok == true && mounted) {
      if (await context.read<AdminCoursesProvider>().update(id, {'access_code': code})) {
        await _load();
      }
    }
  }

  Future<void> _savePayment() async {
    final feeText = _fee.text.trim();
    double? fee;
    if (feeText.isNotEmpty) {
      fee = double.tryParse(feeText);
      if (fee == null || fee < 0 || fee > 100) {
        toast('admin_fee_must_be_between_0_and_100'.tr, error: true);
        return;
      }
    }
    if (restrictMethods && methods.isEmpty) {
      toast('admin_pick_at_least_one_payment_method'.tr, error: true);
      return;
    }
    setState(() => saving = true);
    // Every key is sent on purpose: null RESETS the field to the system default.
    final ok = await context.read<AdminCoursesProvider>().savePaymentSettings(
      widget.id,
      {
        'payment_provider': provider,
        'allowed_methods': restrictMethods ? (methods.toList()..sort()) : null,
        'platform_fee_percent': fee,
      },
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminCoursesProvider>();
    if (loading) {
      return const SizedBox(
        height: 260,
        child: AppListSkeleton(items: 3),
      );
    }
    final co = course;
    if (co == null) {
      return SizedBox(
        height: 260,
        child: ErrorRetry(
          message: 'admin_could_not_load_data'.tr,
          onRetry: _load,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(_nameOf(co)),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Section(
                title: 'admin_overview'.tr,
                child: Column(
                  children: [
                    KeyValue('admin_teacher'.tr, co.teacherName),
                    KeyValue(
                      'admin_list_price'.tr,
                      money(co.listPrice, co.currency),
                    ),
                    for (final o in co.priceOptions)
                      KeyValue(
                        planLabel(asStr(o['plan'])),
                        asBool(o['discount_active'])
                            ? '${money(asDouble(o['final_price']), co.currency)}  (${money(asDouble(o['price']))})'
                            : money(asDouble(o['final_price']), co.currency),
                      ),
                    if (co.discountActive)
                      KeyValue(
                        'admin_price_after_discount'.tr,
                        '${money(co.finalPrice, co.currency)}  (-${co.discountPercentage.toStringAsFixed(0)}%)',
                      ),
                    KeyValue('admin_students'.tr, '${co.studentsCount}'),
                    KeyValue('admin_paid'.tr, '${co.paidCount}'),
                    KeyValue(
                      'admin_income_after_discount'.tr,
                      money(co.income, co.currency),
                    ),
                    KeyValue(
                      'admin_collected_from_students_incl_fees'.tr,
                      money(co.collected, co.currency),
                    ),
                    KeyValue(
                      'admin_effective_platform_fee'.tr,
                      '${co.paymentSettings.effectiveFeePercent}%',
                    ),
                  ],
                ),
              ),
              Section(
                title: 'admin_access_and_resubscribe'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSwitchTile(
                      dense: true,
                      title: 'admin_private_course'.tr,
                      value: raw['is_private'] == true,
                      activeColor: c.primary,
                      onChanged: (v) async {
                        if (await p.update(co.id, {'is_private': v})) await _load();
                      },
                    ),
                    if (raw['is_private'] == true) ...[
                      KeyValue('admin_access_code'.tr,
                          (raw['access_code'] ?? '—').toString()),
                      Row(
                        children: [
                          OutlineButton(
                            label: 'admin_change_access_code'.tr,
                            color: c.primary,
                            icon: Icons.password_rounded,
                            onPressed: () => _changeCode(co.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    AppSwitchTile(
                      dense: true,
                      title: 'admin_allow_resubscribe'.tr,
                      subtitle: 'admin_allow_resubscribe_hint'.tr,
                      value: raw['allow_resubscribe'] != false,
                      activeColor: c.primary,
                      onChanged: (v) async {
                        if (await p.update(co.id, {'allow_resubscribe': v})) await _load();
                      },
                    ),
                  ],
                ),
              ),
              Section(
                title: 'admin_payment_settings'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChoiceRow<String?>(
                      label: 'admin_card_gateway'.tr,
                      options: {
                        null: 'admin_system_default'.tr,
                        'moyasar': 'Moyasar',
                        'paymob': 'Paymob',
                      },
                      value: provider,
                      onChanged: (v) => setState(() => provider = v),
                    ),
                    AppSwitchTile(
                      dense: true,
                      title: 'admin_restrict_payment_methods'.tr,
                      value: restrictMethods,
                      activeColor: c.primary,
                      onChanged: (v) => setState(() => restrictMethods = v),
                    ),
                    if (restrictMethods)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in {
                            'card': 'Moyasar / Paymob',
                            'bank_transfer': 'admin_bank_transfer'.tr,
                            'instapay': 'InstaPay',
                          }.entries)
                            FilterChip(
                              label: Text(
                                m.value,
                                style: TextStyle(fontFamily: AppFonts.family),
                              ),
                              selected: methods.contains(m.key),
                              selectedColor: c.primary.withValues(alpha: 0.25),
                              onSelected: (s) => setState(
                                    () => s
                                    ? methods.add(m.key)
                                    : methods.remove(m.key),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Field(
                      controller: _fee,
                      label: 'admin_platform_fee_empty_default'.tr,
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    Text(
                      'admin_instapay_is_only_shown_for_egp_courses'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 11.5,
                        color: c.textLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'admin_save_payment_settings'.tr,
                      isLoading: saving,
                      onPressed: _savePayment,
                    ),
                  ],
                ),
              ),
              if (co.recentPayments.isNotEmpty)
                Section(
                  title: 'admin_recent_payments'.tr,
                  child: Column(
                    children: [
                      for (final pay in co.recentPayments.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '#${pay['id']} • ${asStr(pay['method'], '—')} • ${shortDate(asStrOrNull(pay['created_at']))}',
                                  style: TextStyle(
                                    fontFamily: AppFonts.family,
                                    fontSize: 12.5,
                                    color: c.textMedium,
                                  ),
                                ),
                              ),
                              Text(
                                money(
                                  asDouble(
                                    pay['price_paid'],
                                    asDouble(pay['amount']),
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontWeight: FontWeight.w700,
                                  color: c.textDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusChip(
                                asStr(pay['status']),
                                asStr(pay['status']) == 'completed'
                                    ? c.success
                                    : (asStr(pay['status']) == 'pending'
                                    ? c.warning
                                    : c.danger),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              // the course's exams: the list, New exam and the question bank a teacher has (the engine lets a platform
              // admin manage any course's exams; it decides the organization scope itself)
              AppCard(margin: const EdgeInsets.only(bottom: 14), child: EngineReviewSection(courseId: co.id, showEmpty: true)),
              Section(
                title: 'admin_controls'.tr,
                child: Column(
                  children: [
                    Row(
                      children: [
                        OutlineButton(
                          label: co.isPublished
                              ? 'admin_unpublish'.tr
                              : 'publish_exam'.tr,
                          color: co.isPublished
                              ? context.colors.warning
                              : context.colors.success,
                          icon: co.isPublished
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          onPressed: () async {
                            final ok = await p.update(co.id, {
                              'is_published': !co.isPublished,
                            });
                            if (ok && context.mounted) {
                              Navigator.pop(context, _ManageExit.done); // close the sheet and go back to the list
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlineButton(
                          label: 'btn_edit'.tr,
                          color: context.colors.warning,
                          icon: Icons.edit_rounded,
                          onPressed: () => Navigator.pop(context, _ManageExit.edit),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlineButton(
                          label: co.status == 'completed'
                              ? 'admin_reopen'.tr
                              : 'admin_mark_completed'.tr,
                          color: context.colors.primary,
                          icon: co.status == 'completed'
                              ? Icons.replay_rounded
                              : Icons.flag_rounded,
                          onPressed: () async {
                            final next = co.status == 'completed'
                                ? 'in_progress'
                                : 'completed';
                            if (await p.update(co.id, {'status': next})) {
                              await _load();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlineButton(
                          label: 'delete'.tr,
                          color: context.colors.danger,
                          icon: Icons.delete_outline_rounded,
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              message: 'course_trash_confirm'.tr,
                              danger: true,
                              confirmLabel: 'course_move_to_trash'.tr,
                            );
                            if (!ok) return;
                            if (await p.remove(co.id, force: true) &&
                                context.mounted) {
                              Navigator.pop(context, _ManageExit.trashed);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create / edit course
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openCourseForm(
    BuildContext context,
    AdminCoursesProvider p, {
      AdminCourse? existing,
    }) {
  return showAdminSheet(
    context,
        (ctx) => _CourseForm(provider: p, existing: existing),
  );
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({required this.provider, this.existing});

  final AdminCoursesProvider provider;
  final AdminCourse? existing;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _fees = TextEditingController(
    text: widget.existing == null ? '0' : widget.existing!.fees.toString(),
  );
  late final _max = TextEditingController(
    text: widget.existing?.maxStudents?.toString() ?? '',
  );

  // optional shorter plans; `fees` above is the YEARLY price
  late final _monthly = TextEditingController(
    text: widget.existing?.priceMonthly?.toString() ?? '',
  );
  late final _sixMonths = TextEditingController(
    text: widget.existing?.priceSixMonths?.toString() ?? '',
  );

  late String currency = widget.existing?.currency ?? 'EGP';
  late int defaultPlan =
      widget.existing?.defaultPricePlanIndex ??
          0; // 0 yearly · 1 six months · 2 monthly
  late String type = (widget.existing?.type ?? 'recorded').toLowerCase();
  int? teacherId;
  int? categoryId;
  bool published = false;
  bool isPrivate = false;
  bool allowResub = true;
  final _code = TextEditingController();

  List<AdminUser> teachers = [];
  List<AdminCategory> categories = [];
  bool busy = false;
  bool ready = false;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    teacherId = widget.existing?.teacherId;
    categoryId = widget.existing?.categoryId;
    published = widget.existing?.isPublished ?? false;
    _loadChoices();
  }

  Future<void> _loadChoices() async {
    final tch = await widget.provider.teacherChoices();
    final cat = await widget.provider.categoryChoices();
    Map<String, dynamic>? raw;
    if (widget.existing != null) {
      raw = await widget.provider.detailRaw(widget.existing!.id);
    }
    if (!mounted) return;
    setState(() {
      teachers = tch;
      categories = cat;
      if (raw != null) {
        isPrivate = raw['is_private'] == true;
        allowResub = raw['allow_resubscribe'] != false;
        _code.text = (raw['access_code'] ?? '').toString();
      }
      ready = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _fees, _max, _monthly, _sixMonths, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (teacherId == null) {
      toast('admin_choose_a_teacher'.tr, error: true);
      return;
    }
    setState(() => busy = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'fees': double.tryParse(_fees.text.trim()) ?? 0, // YEARLY price
      // empty = the plan is not offered (null clears it on edit)
      'price_monthly': double.tryParse(_monthly.text.trim()),
      'price_six_months': double.tryParse(_sixMonths.text.trim()),
      'default_price_plan_index': defaultPlan,
      'currency': currency,
      'type': type,
      'teacher_id': teacherId,
      'category_id': categoryId,
      'max_students': int.tryParse(_max.text.trim()),
      'is_published': published,
      'is_private': isPrivate,
      'allow_resubscribe': allowResub,
      if (isPrivate && _code.text.trim().isNotEmpty)
        'access_code': _code.text.trim(),
    };
    final ok = editing
        ? await widget.provider.update(widget.existing!.id, body)
        : await widget.provider.create(body);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _pickTeacher() async {
    final r = await showDialog<AdminUser>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: SimpleDialog(
          title: Text(
            'admin_choose_teacher'.tr,
            style: TextStyle(fontFamily: AppFonts.family),
          ),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 340,
              child: ListView(
                children: [
                  for (final u in teachers)
                    ListTile(
                      title: Text(
                        u.name,
                        style: TextStyle(fontFamily: AppFonts.family),
                      ),
                      subtitle: Text(
                        u.gmail,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (r != null) setState(() => teacherId = r.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final teacherName =
        teachers
            .where((u) => u.id == teacherId)
            .map((u) => u.name)
            .firstOrNull ??
            (editing ? widget.existing!.teacherName : null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(editing ? 'admin_edit_course'.tr : 'admin_add_course'.tr),
        Flexible(
          child: !ready
              ? const SizedBox(
            height: 200,
            child: AppListSkeleton(items: 3),
          )
              : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Field(
                    controller: _name,
                    label: 'admin_course_name'.tr,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'admin_name_is_required'.tr
                        : null,
                  ),
                  Field(
                    controller: _desc,
                    label: 'description'.tr,
                    maxLines: 3,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          controller: _fees,
                          label: 'price_yearly_label'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            return (n == null || n < 0)
                                ? 'admin_invalid_price'.tr
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(
                          controller: _max,
                          label: 'admin_max_students'.tr,
                          keyboard: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          controller: _sixMonths,
                          label: 'price_six_months_label'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return null;
                            final n = double.tryParse(s);
                            return (n == null || n < 0)
                                ? 'admin_invalid_price'.tr
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(
                          controller: _monthly,
                          label: 'price_monthly_label'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return null;
                            final n = double.tryParse(s);
                            return (n == null || n < 0)
                                ? 'admin_invalid_price'.tr
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'price_plans_hint'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 11.5,
                        color: context.colors.textLight,
                      ),
                    ),
                  ),
                  ChoiceRow<int>(
                    label: 'default_plan_label'.tr,
                    options: {
                      0: 'price_yearly_label'.tr,
                      1: 'price_six_months_label'.tr,
                      2: 'price_monthly_label'.tr,
                    },
                    value: defaultPlan,
                    onChanged: (v) => setState(() => defaultPlan = v),
                  ),
                  ChoiceRow<String>(
                    label: 'currency_label'.tr,
                    options: const {
                      'EGP': 'EGP',
                      'SAR': 'SAR',
                      'USD': 'USD',
                    },
                    value: currency,
                    onChanged: (v) => setState(() => currency = v),
                  ),
                  ChoiceRow<String>(
                    label: 'admin_type'.tr,
                    options: {
                      'recorded': 'session_type_recorded'.tr,
                      'live': 'session_type_live'.tr,
                      'both': 'session_type_both'.tr,
                    },
                    value: type,
                    onChanged: (v) => setState(() => type = v),
                  ),
                  Row(
                    children: [
                      OutlineButton(
                        color: context.colors.primary,
                        onPressed: _pickTeacher,
                        icon: Icons.school_rounded,
                        label: teacherName ?? 'admin_choose_teacher'.tr,
                      ),
                      Spacer(flex:3)
                    ],
                  ),
                  if (categories.isNotEmpty)
                    ChoiceRow<int?>(
                      label: 'category_label'.tr,
                      options: {
                        null: 'admin_none'.tr,
                        for (final cat in categories) cat.id: cat.display,
                      },
                      value: categoryId,
                      onChanged: (v) => setState(() => categoryId = v),
                    ),
                  AppSwitchTile(
                    title: 'admin_private_course'.tr,
                    value: isPrivate,
                    activeColor: c.primary,
                    onChanged: (v) => setState(() => isPrivate = v),
                  ),
                  if (isPrivate)
                    Field(
                      controller: _code,
                      label: 'admin_access_code_hint'.tr,
                      keyboard: TextInputType.number,
                      validator: (v) {
                        final s = (v ?? '').trim();
                        return (s.isEmpty || RegExp(r'^\d{6}$').hasMatch(s))
                            ? null
                            : 'admin_code_6_digits'.tr;
                      },
                    ),
                  AppSwitchTile(
                    title: 'admin_allow_resubscribe'.tr,
                    subtitle: 'admin_allow_resubscribe_hint'.tr,
                    value: allowResub,
                    activeColor: c.primary,
                    onChanged: (v) => setState(() => allowResub = v),
                  ),
                  AppSwitchTile(
                    title: 'published'.tr,
                    value: published,
                    activeColor: c.primary,
                    onChanged: (v) => setState(() => published = v),
                  ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: 'save'.tr,
                    isLoading: busy,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}