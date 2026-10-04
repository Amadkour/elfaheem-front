// lib/features/admin/admin_categories_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

class AdminCategoriesPage extends StatelessWidget {
  const AdminCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminCategoriesProvider()..load(),
        child: const _View(),
      );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminCategoriesProvider>();
    final c = context.colors;

    Widget body;
    if (p.items.isEmpty && p.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.error != null && p.items.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else if (p.items.isEmpty) {
      body = EmptyState(t('لا توجد تصنيفات', 'No categories yet'));
    } else {
      body = RefreshIndicator(
        onRefresh: p.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 90), children: [
          for (final cat in p.items)
            RowCard(
              onTap: () => _form(context, p, existing: cat),
              child: Row(children: [
                Icon(Icons.category_rounded, color: c.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cat.nameAr.isEmpty ? cat.nameEn : cat.nameAr,
                        style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                    if (cat.nameEn.isNotEmpty && cat.nameAr.isNotEmpty)
                      Text(cat.nameEn, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
                  ]),
                ),
                StatusChip('${cat.coursesCount} ${t('كورس', 'courses')}', c.primary),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                  onPressed: () async {
                    final ok = await confirm(context,
                        message: t('حذف هذا التصنيف؟', 'Delete this category?'), danger: true);
                    if (ok) await p.remove(cat.id);
                  },
                ),
              ]),
            ),
        ]),
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'categories'.tr),
      floatingActionButton: FloatingActionButton.extended(
          backgroundColor: c.primary,
          onPressed: () => _form(context, p),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text(t('إضافة تصنيف', 'Add category'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
        ),
      child: body,
    );
  }
}

Future<void> _form(BuildContext context, AdminCategoriesProvider p, {AdminCategory? existing}) {
  final ar = TextEditingController(text: existing?.nameAr);
  final en = TextEditingController(text: existing?.nameEn);
  final desc = TextEditingController(text: existing?.description);
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(builder: (ctx, setS) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(existing == null ? t('إضافة تصنيف', 'Add category') : t('تعديل التصنيف', 'Edit category')),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(children: [
              Field(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
              Field(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
              Field(controller: desc, label: t('الوصف', 'Description'), maxLines: 3),
              PrimaryButton(
                label: t('حفظ', 'Save'),
                busy: busy,
                onPressed: () async {
                  if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                    toast(t('أدخل اسم التصنيف', 'Enter a category name'), error: true);
                    return;
                  }
                  setS(() => busy = true);
                  final ok = await p.save(id: existing?.id, body: {
                    'name_ar': ar.text.trim().isEmpty ? null : ar.text.trim(),
                    'name_en': en.text.trim().isEmpty ? null : en.text.trim(),
                    'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
                  });
                  if (ctx.mounted) {
                    setS(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                },
              ),
            ]),
          ),
        ),
      ]);
    });
  }).whenComplete(() {
    ar.dispose();
    en.dispose();
    desc.dispose();
  });
}
