// lib/features/admin/admin_categories_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'admin_common.dart' show t, toast;
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_models.dart';
import 'admin_page.dart';
import 'admin_providers.dart';
import 'package:flutter_education_app/design/app_kit.dart';

class AdminCategoriesPage extends StatelessWidget {
  const AdminCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminCategoriesProvider()..load(),
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

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  DateTime? _loadedAt;

  Future<void> _reload(AdminCategoriesProvider p) async {
    await p.load();
    if (mounted) setState(() => _loadedAt = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final p = context.watch<AdminCategoriesProvider>();
    final c = context.colors;
    final first = p.items.isEmpty;

    return AdminPage(
      title: 'categories'.tr,
      subtitle: 'svc_categories_d'.tr,
      icon: Icons.category_rounded,
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
          AdminFilterBar(
            host: p,
            hintKey: 'admin_search_categories',
            specs: _categorySpecs,
            sort: _categorySort,
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
          ),
          Expanded(
            child: AppDataTable<AdminCategory>(
              state: p.isLoading && first
                  ? AppTableState.loading
                  : p.error != null && first
                      ? AppTableState.error
                      : AppTableState.ready,
              errorText: p.error,
              onRetry: p.load,
              rows: p.items,
              empty: AppEmpty(
                icon: Icons.category_rounded,
                title: p.hasActiveQuery ? 'admin_filter_no_results'.tr : 'admin_no_categories_yet'.tr,
              ),
              onRowTap: (cat) => _form(context, p, existing: cat),
              columns: [
                AppTableColumn<AdminCategory>(
                  key: 'name',
                  label: t('التصنيف', 'Category'),
                  primary: true,
                  flex: 3,
                  cell: (context, cat) {
                    final title = cat.nameAr.isEmpty ? cat.nameEn : cat.nameAr;
                    return Row(children: [
                      Icon(Icons.category_rounded, color: c.primary, size: AppIconSize.lg),
                      AppSpace.gapSm,
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                          if (cat.nameEn.isNotEmpty && cat.nameAr.isNotEmpty)
                            Text(cat.nameEn,
                                maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                        ]),
                      ),
                    ]);
                  },
                ),
                AppTableColumn<AdminCategory>.text(
                  key: 'courses',
                  label: t('الكورسات', 'Courses'),
                  text: (cat) => _coursesText(cat.coursesCount),
                ),
              ],
              rowActions: (cat) => [
                AppRowAction(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _form(context, p, existing: cat)),
                AppRowAction(icon: Icons.delete_outline_rounded, label: 'delete'.tr, danger: true, onTap: () => _delete(context, p, cat)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

Future<void> _delete(BuildContext context, AdminCategoriesProvider p, AdminCategory cat) async {
  final name = cat.display;
  if (cat.coursesCount > 0) {
    // the server refuses (409) while courses use the category: say why instead of a generic confirm
    showAppNotice(
      t('«$name» مرتبط بـ ${_coursesText(cat.coursesCount)} — انقل الكورسات إلى تصنيف آخر أولًا ثم احذفه.',
          '"$name" is used by ${_coursesText(cat.coursesCount)} — move them to another category first, then delete it.'),
      error: true,
    );
    return;
  }
  final ok = await appConfirm(
    context,
    message: t('حذف التصنيف «$name»؟', 'Delete the category "$name"?'),
    danger: true,
  );
  if (ok) await p.remove(cat.id);
}

Future<void> _form(BuildContext context, AdminCategoriesProvider p, {AdminCategory? existing}) =>
    showAppSheet(context, (ctx) => _CategoryForm(provider: p, existing: existing));

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
      if (ok) Navigator.pop(context);
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
