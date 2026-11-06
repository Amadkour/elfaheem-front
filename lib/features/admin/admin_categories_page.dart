// lib/features/admin/admin_categories_page.dart
//
// D-290: the categories list on the master-detail pattern, like the students and teachers lists: a row opens the
// connected detail (its courses, teachers and students), Edit and Delete sit on the row and inside the detail
// ([AdminCategoryManage], on every host of the panel).
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart' show EntitySummary;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart' show EntityThumb;
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'admin_common.dart' show t, toast;
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_models.dart';
import 'admin_page.dart';
import 'admin_providers.dart';
import 'admin_table_export.dart' show adminCategoriesExport, exportPagedList;
import 'package:flutter_education_app/design/app_kit.dart';

class AdminCategoriesPage extends StatelessWidget {
  const AdminCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminCategoriesProvider()..refresh(),
    child: const _View(),
  );
}

// ── premium filters ─────────────────────────────────────────────────────────

const _categorySort = SortSpec({
  'oldest': 'admin_sort_oldest',
  'newest': 'admin_sort_newest',
  'name_asc': 'admin_sort_name_asc',
  'name_desc': 'admin_sort_name_desc',
  'most_courses': 'admin_sort_most_courses',
  'most_teachers': 'md_p6_sort_most_teachers',
  'most_students': 'md_p6_sort_most_students',
});

const _categorySpecs = <FilterSpec>[
  FilterSpec.tri('has_courses', 'admin_filter_has_courses'),
  FilterSpec.choice('level', 'admin_filter_level', {
    'root': 'admin_filter_level_root',
    'sub': 'admin_filter_level_sub',
  }),
];

String _coursesText(int n) => countText(n,
    ar1: 'كورس واحد', ar2: 'كورسان', arFew: '{n} كورسات', arMany: '{n} كورسًا', en1: '1 course', en: '{n} courses');

String _totalText(int n) => countText(n,
    ar1: 'تصنيف واحد', ar2: 'تصنيفان', arFew: '{n} تصنيفات', arMany: '{n} تصنيفًا', en1: '1 category', en: '{n} categories');

EntityRef _refOf(AdminCategory c) =>
    EntityRef(EntityKind.category, c.id, label: c.nameAr, labelEn: c.nameEn, imageUrl: c.imageUrl);

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  DateTime? _loadedAt;

  /// The detail panel of the list (D-290).
  final _panel = EntityPanelController(rowKind: EntityKind.category);

  /// The row drawn as selected: the panel's, kept here so the table redraws only when it changes.
  int? _selected;

  /// The panel's revision this list has seen: a change made in the detail reloads the rows behind it.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _panel.addListener(_panelChanged);
  }

  void _panelChanged() {
    if (_panel.revision != _revision) {
      _revision = _panel.revision;
      context.read<AdminCategoriesProvider>().refresh();
    }
    final id = _panel.selectedId;
    if (id == _selected) return;
    void apply() {
      if (mounted) setState(() => _selected = _panel.selectedId);
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  void dispose() {
    _panel.removeListener(_panelChanged);
    _panel.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AdminRefreshScope.register(context, context.read<AdminCategoriesProvider>().refresh);
  }

  Future<void> _reload(AdminCategoriesProvider p) async {
    await p.refresh();
    if (mounted) setState(() => _loadedAt = DateTime.now());
  }

  /// The server's sort value -> the table column it belongs to.
  String? _sortKey(String? s) => switch (s) {
        'name_asc' || 'name_desc' => 'name',
        'most_courses' => 'courses',
        'most_teachers' => 'teachers',
        'most_students' => 'students',
        _ => null,
      };

  void _onSort(AdminCategoriesProvider p, String key, bool asc) {
    p.setSort(switch (key) {
      'name' => asc ? 'name_asc' : 'name_desc',
      _ => 'most_$key',
    });
  }

  /// A row's Edit: the open detail shows the new text too.
  Future<void> _edit(BuildContext context, AdminCategoriesProvider p, AdminCategory cat) async {
    await _form(context, p, existing: cat);
    final ref = _refOf(cat);
    EntitiesApi.instance.invalidate(ref);
    if (mounted && _panel.current == ref) _panel.reload();
  }

  Future<void> _deleteRow(BuildContext context, AdminCategoriesProvider p, AdminCategory cat) async {
    final gone = await _delete(context, p, cat);
    if (gone && mounted && _panel.current == _refOf(cat)) _panel.close();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final p = context.watch<AdminCategoriesProvider>();
    final items = p.items;
    _panel.siblings = [for (final cat in items) _refOf(cat)]; // previous / next and the keyboard walk these rows
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final table = AppDataTable<AdminCategory>(
      state: p.error != null && p.rows.isEmpty
          ? AppTableState.error
          : (!p.loaded && p.isLoading ? AppTableState.loading : AppTableState.ready),
      errorText: p.error,
      onRetry: p.refresh,
      rows: items,
      rowId: (cat) => cat.id,
      tableId: 'admin_categories',
      columnMenu: true,
      selectedRowId: _selected,
      onRowHover: (cat) => EntitiesApi.instance.prefetch(_refOf(cat)),
      searchHint: 'admin_search_categories'.tr,
      onSearch: p.setSearch,
      toolbarTrailing: Row(mainAxisSize: MainAxisSize.min, children: [
        AdminFilterButton(host: p, specs: _categorySpecs, sort: _categorySort),
        AppIconButton(
          icon: Icons.ios_share_rounded,
          tooltip: t('تصدير', 'Export'),
          onPressed: p.rows.isEmpty ? null : () => exportPagedList(context, p, adminCategoriesExport),
        ),
      ]),
      empty: p.hasActiveQuery
          ? AppEmpty(
              icon: Icons.search_off_rounded,
              title: 'admin_filter_no_results'.tr,
              actionLabel: 'ds_clear_filters'.tr,
              onAction: p.clearAll,
            )
          : AppEmpty(icon: Icons.category_rounded, title: 'admin_no_categories_yet'.tr),
      onClearFilters: p.clearAll,
      onRowTap: (cat) => _panel.open(_refOf(cat)),
      sortKey: _sortKey(p.sort),
      sortAscending: p.sort == 'name_asc',
      onSort: (k, asc) => _onSort(p, k, asc),
      onLoadMore: p.loadMore,
      hasMore: p.hasMore,
      loadingMore: p.loadingMore,
      columns: [
        AppTableColumn<AdminCategory>(
          key: 'name',
          label: t('التصنيف', 'Category'),
          primary: true,
          sortable: true,
          flex: 3,
          cell: (context, cat) => _NameCell(cat),
        ),
        AppTableColumn<AdminCategory>.text(
          key: 'description',
          label: 'description'.tr,
          flex: 3,
          showOnPhone: false,
          text: (cat) => cat.description.isEmpty ? '—' : cat.description,
        ),
        AppTableColumn<AdminCategory>.text(
          key: 'courses',
          label: t('الكورسات', 'Courses'),
          sortable: true,
          numeric: true,
          text: (cat) => '${cat.coursesCount}',
        ),
        AppTableColumn<AdminCategory>.text(
          key: 'teachers',
          label: 'md_stat_teachers'.tr,
          sortable: true,
          numeric: true,
          text: (cat) => '${cat.teachersCount}',
        ),
        AppTableColumn<AdminCategory>.text(
          key: 'students',
          label: 'md_stat_students'.tr,
          sortable: true,
          numeric: true,
          text: (cat) => '${cat.studentsCount}',
        ),
      ],
      rowActions: (cat) => [
        AppRowAction(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _edit(context, p, cat)),
        AppRowAction(icon: Icons.delete_outline_rounded, label: 'delete'.tr, danger: true, onTap: () => _deleteRow(context, p, cat)),
      ],
    );

    final page = AdminPage(
      title: 'categories'.tr,
      subtitle: wide && p.loaded ? _totalText(p.total) : 'svc_categories_d'.tr,
      icon: Icons.category_rounded,
      maxWidth: double.infinity,
      onRefresh: p.isLoading ? null : () => _reload(p),
      updatedAt: _loadedAt,
      primaryAction: AppButton.primary(
        label: 'admin_add_category'.tr,
        icon: Icons.add_rounded,
        onPressed: () => _form(context, p),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminActiveFilterChips(host: p, specs: _categorySpecs, sort: _categorySort),
          Expanded(child: table),
        ]),
      ),
    );
    // no `?open=`: this page is pushed from the services hub and has no URL of its own; a shared detail is `/view/…`
    return MasterDetailScaffold(controller: _panel, list: page, rootLabel: 'categories'.tr);
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell(this.cat);

  final AdminCategory cat;

  @override
  Widget build(BuildContext context) {
    final title = cat.nameAr.isEmpty ? cat.nameEn : cat.nameAr;
    return Row(children: [
      EntityThumb(_refOf(cat), size: 36),
      AppSpace.gapSm,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
          if (cat.nameEn.isNotEmpty && cat.nameAr.isNotEmpty)
            Text(cat.nameEn,
                maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
        ]),
      ),
    ]);
  }
}

/// Deletes [cat] after asking; true when it is gone. [subcategories]: known to the detail; the list only learns it from
/// the server's refusal.
Future<bool> _delete(BuildContext context, AdminCategoriesProvider p, AdminCategory cat, {int subcategories = 0}) async {
  final name = cat.display;
  if (cat.coursesCount > 0) {
    // the server refuses (409) while courses use the category: say why instead of a generic confirm
    showAppNotice(
      t('«$name» مرتبط بـ ${_coursesText(cat.coursesCount)} — انقل الكورسات إلى تصنيف آخر أولًا ثم احذفه.',
          '"$name" is used by ${_coursesText(cat.coursesCount)} — move them to another category first, then delete it.'),
      error: true,
    );
    return false;
  }
  if (subcategories > 0) {
    showAppNotice(
      t('«$name» يحتوي على تصنيفات فرعية — انقلها أو احذفها أولًا.',
          '"$name" has sub-categories — move or delete them first.'),
      error: true,
    );
    return false;
  }
  final ok = await appConfirm(
    context,
    message: t('حذف التصنيف «$name»؟', 'Delete the category "$name"?'),
    danger: true,
  );
  return ok && await p.remove(cat.id);
}

Future<void> _form(BuildContext context, AdminCategoriesProvider p, {AdminCategory? existing}) =>
    showAppSheet(context, (ctx) => _CategoryForm(provider: p, existing: existing));

/// The Edit and Delete of a category's detail for an admin.
class AdminCategoryManage extends StatefulWidget {
  const AdminCategoryManage({super.key, required this.summary, this.onChanged, this.onRemoved});

  final EntitySummary summary;
  final VoidCallback? onChanged;
  final VoidCallback? onRemoved;

  @override
  State<AdminCategoryManage> createState() => _AdminCategoryManageState();
}

class _AdminCategoryManageState extends State<AdminCategoryManage> {
  final _p = AdminCategoriesProvider(reloads: false);

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  AdminCategory get _cat {
    final s = widget.summary;
    return AdminCategory({
      'id': s.id,
      'name_ar': s.text('name_ar'),
      'name_en': s.text('name_en'),
      'description': s.text('description'),
      'courses_count': s.stat('courses') ?? 0,
    });
  }

  Future<void> _edit() async {
    final saved = await showAppSheet<bool>(context, (ctx) => _CategoryForm(provider: _p, existing: _cat));
    if (saved == true) widget.onChanged?.call();
  }

  Future<void> _remove() async {
    if (await _delete(context, _p, _cat, subcategories: widget.summary.children.length)) widget.onRemoved?.call();
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppButton.tonal(
          key: const ValueKey('md.category_edit'),
          label: t('تعديل', 'Edit'),
          icon: Icons.edit_rounded,
          size: AppButtonSize.sm,
          onPressed: _edit,
        ),
        AppButton.danger(
          key: const ValueKey('md.category_delete'),
          dangerOutline: true,
          label: 'delete'.tr,
          icon: Icons.delete_outline_rounded,
          size: AppButtonSize.sm,
          onPressed: _remove,
        ),
      ]);
}

/// The sheet content owns its controllers, so they are disposed only when the
/// sheet is really removed from the tree (after the close animation) — not
/// while the TextFields are still on screen.
class _CategoryForm extends StatefulWidget {
  const _CategoryForm({required this.provider, this.existing});

  final AdminCategoriesProvider provider;
  final AdminCategory? existing;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final ar = TextEditingController(text: widget.existing?.nameAr);
  late final en = TextEditingController(text: widget.existing?.nameEn);
  late final desc = TextEditingController(text: widget.existing?.description);
  bool busy = false;

  @override
  void dispose() {
    ar.dispose();
    en.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (busy) return;
    if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
      toast('admin_enter_a_category_name'.tr, error: true);
      return;
    }
    setState(() => busy = true);
    final ok = await widget.provider.save(id: widget.existing?.id, body: {
      'name_ar': ar.text.trim().isEmpty ? null : ar.text.trim(),
      'name_en': en.text.trim().isEmpty ? null : en.text.trim(),
      'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
    });
    if (mounted) {
      setState(() => busy = false);
      if (ok) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final existing = widget.existing;
    return AppSheetContent(
      title: existing == null ? 'admin_add_category'.tr : 'admin_edit_category'.tr,
      children: [
        AppField(controller: ar, label: 'admin_arabic_name'.tr),
        AppField(controller: en, label: 'admin_english_name'.tr, ltr: true),
        AppField(controller: desc, label: 'description'.tr, maxLines: 3),
        AppButton.primary(label: 'save'.tr, busy: busy, expand: true, onPressed: busy ? null : _save),
      ],
    );
  }
}
