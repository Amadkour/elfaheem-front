// lib/features/admin/admin_categories_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_premium_widgets.dart';
import 'admin_providers.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminCategoriesProvider>();
    final c = context.colors;

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'categories'.tr),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "categories_float",
        key: const ValueKey("categories_float"),
        backgroundColor: c.primary,
        onPressed: () => _form(context, p),
        icon: Icon(Icons.add_rounded, color: c.onHero),
        label: Text('admin_add_category'.tr,
            style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
      ),
      child: Column(children: [
        AdminFilterBar(
          host: p,
          hintKey: 'admin_search_categories',
          specs: _categorySpecs,
          sort: _categorySort,
        ),
        Expanded(
          child: AdminSimpleList(
            loading: p.isLoading,
            error: p.error,
            isEmpty: p.items.isEmpty,
            emptyText: p.hasActiveQuery
                ? 'admin_filter_no_results'.tr
                : 'admin_no_categories_yet'.tr,
            onRefresh: p.load,
            children: [
              PremiumHero(
                icon: Icons.category_rounded,
                colors: AdminPalette.teal,
                title: 'categories'.tr,
                subtitle: 'svc_categories_d'.tr,
                footer: Wrap(spacing: 8, children: [
                  HeroPill(trp('cat_pill_total', {'n': p.items.length}),
                      icon: Icons.folder_special_rounded),
                ]),
              ),
              for (final cat in p.items) _CategoryCard(cat),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard(this.cat);

  final AdminCategory cat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminCategoriesProvider>();
    final title = cat.nameAr.isEmpty ? cat.nameEn : cat.nameAr;

    return RowCard(
      accent: c.primary,
      onTap: () => _form(context, p, existing: cat),
      child: Row(children: [
        IconBadge(Icons.category_rounded, c.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textDark)),
            if (cat.nameEn.isNotEmpty && cat.nameAr.isNotEmpty)
              Text(cat.nameEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textLight)),
            const SizedBox(height: 6),
            InfoChip(Icons.menu_book_rounded,
                '${cat.coursesCount} ${'roadmap_course_unit'.tr}', c.primary),
          ]),
        ),
        IconButton(
          tooltip: 'delete'.tr,
          icon: Icon(Icons.delete_outline_rounded, color: c.danger),
          onPressed: () async {
            final ok = await confirm(context,
                message: 'admin_delete_this_category'.tr, danger: true);
            if (ok) await p.remove(cat.id);
          },
        ),
      ]),
    );
  }
}

Future<void> _form(BuildContext context, AdminCategoriesProvider p, {AdminCategory? existing}) =>
    showAdminSheet(context, (ctx) => _CategoryForm(provider: p, existing: existing));

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

  @override
  Widget build(BuildContext ctx) {
    final p = widget.provider;
    final existing = widget.existing;
    {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(existing == null ? 'admin_add_category'.tr : 'admin_edit_category'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(children: [
              Field(controller: ar, label: 'admin_arabic_name'.tr),
              Field(controller: en, label: 'admin_english_name'.tr, ltr: true),
              Field(controller: desc, label: 'description'.tr, maxLines: 3),
              PrimaryButton(
                label: 'save'.tr,
                isLoading: busy,
                onPressed: () async {
                  if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                    toast('admin_enter_a_category_name'.tr, error: true);
                    return;
                  }
                  setState(() => busy = true);
                  final ok = await p.save(id: existing?.id, body: {
                    'name_ar': ar.text.trim().isEmpty ? null : ar.text.trim(),
                    'name_en': en.text.trim().isEmpty ? null : en.text.trim(),
                    'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
                  });
                  if (mounted) {
                    setState(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                },
              ),
            ]),
          ),
        ),
      ]);
    }
  }
}