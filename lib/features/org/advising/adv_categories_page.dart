// lib/features/org/advising/adv_categories_page.dart — the flag and note categories (docs/advising/PHASE4.md
// "Categories", brief §2.3 + #24), for org admins and advising directors: each category's names, whether it is
// sensitive (its flags and notes are read only by their author, the primary advisor and the directors), on / off,
// and its recommended accommodations (e.g. extra exam time for Accessibility). System categories can be renamed and
// switched off, never deleted; a category used by open flags answers 409 `advising_category_in_use` on delete.
//
//   AdvCategoryCard   one category                 AdvCategoriesView   the list (plain values)
//   AdvCategoryForm   the add / edit sheet's content (with the accommodations editor)
//   AdvCategoriesPage loads `GET …/categories`; POST / whole-object PUT / DELETE
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_models.dart';
import 'adv_parts.dart';

class AdvCategoryCard extends StatelessWidget {
  const AdvCategoryCard({super.key, required this.category, this.onTap});
  final AdvCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = category;
    final other = t(x.nameEn, x.nameAr);
    final acc = x.accommodations;
    return AdvRowCard(
      title: x.name,
      subtitle: other.isNotEmpty && other != x.name ? other : null,
      leading: Container(
        width: AppTouch.min - AppSpace.xs,
        height: AppTouch.min - AppSpace.xs,
        decoration: BoxDecoration(color: (x.sensitive ? c.warning : c.primary).withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
        child: Icon(x.sensitive ? Icons.lock_outline_rounded : Icons.label_outline_rounded, size: AppIconSize.md, color: appInk(context, x.sensitive ? c.warning : c.primary)),
      ),
      trailing: !x.active ? AppBadgePill(t('متوقف', 'Off'), color: c.textMedium, icon: Icons.pause_rounded) : null,
      onTap: onTap,
      below: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
        if (x.sensitive) AppBadgePill(t('حساس', 'Sensitive'), color: c.warning, icon: Icons.lock_outline_rounded),
        if (x.system) AppBadgePill(t('من النظام', 'Built in'), color: c.textMedium, icon: Icons.verified_outlined),
        if (acc.isNotEmpty)
          AppBadgePill(
            countText(acc.length, ar1: 'تسهيل واحد', ar2: 'تسهيلان', arFew: '${acc.length} تسهيلات', arMany: '${acc.length} تسهيلاً', en1: '1 accommodation', en: '${acc.length} accommodations'),
            color: c.primary,
            icon: Icons.accessible_rounded,
          ),
      ]),
    );
  }
}

class AdvCategoriesView extends StatelessWidget {
  const AdvCategoriesView({super.key, required this.load, this.categories, this.errorText, this.onRetry, this.onAdd, this.onOpen});
  final AdvLoad load;
  final List<AdvCategory>? categories;
  final String? errorText;
  final VoidCallback? onRetry, onAdd;
  final ValueChanged<AdvCategory>? onOpen;

  @override
  Widget build(BuildContext context) {
    final list = categories;
    final primary = onAdd == null ? null : OrgPrimaryAction(id: 'add_category', icon: Icons.add_rounded, label: t('تصنيف جديد', 'New category'), onTap: onAdd!);
    Widget body;
    if (load != AdvLoad.ready || list == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    } else if (list.isEmpty) {
      body = AppEmpty(
        icon: Icons.label_outline_rounded,
        title: t('لا تصنيفات بعد', 'No categories yet'),
        message: t('التصنيفات تجمع التنبيهات والملاحظات: أكاديمي، مالي، صحي…', 'Categories group flags and notes: academic, financial, health…'),
      );
    } else {
      final on = [for (final x in list) if (x.active) x], off = [for (final x in list) if (!x.active) x];
      body = AdvPageFrame(fab: primary != null, children: [
        AdvSectionTitle(
          t('التصنيفات', 'Categories'),
          first: true,
          subtitle: t('الحساس منها لا يقرؤه إلا كاتبه والمرشد الأساسي ومديرو الإرشاد', 'Sensitive ones are read only by their author, the primary advisor and the directors'),
        ),
        for (final x in on) AdvCategoryCard(category: x, onTap: onOpen == null ? null : () => onOpen!(x)),
        if (off.isNotEmpty) ...[
          AdvSectionTitle(t('متوقفة', 'Switched off'), subtitle: t('لا تظهر عند فتح تنبيه جديد', 'Not offered for new flags')),
          for (final x in off) AdvCategoryCard(category: x, onTap: onOpen == null ? null : () => onOpen!(x)),
        ],
      ]);
    }
    return OrgPageBody(primary: primary, child: body);
  }
}

/// One accommodation row being edited: its key (empty for a new one) and its two names.
class AdvAccommodationRow {
  AdvAccommodationRow({this.key = '', String ar = '', String en = ''})
      : ar = TextEditingController(text: ar),
        en = TextEditingController(text: en);

  factory AdvAccommodationRow.of(AdvAccommodation a) => AdvAccommodationRow(key: a.key, ar: a.labelAr, en: a.labelEn);

  final String key;
  final TextEditingController ar, en;

  AdvAccommodation get value => AdvAccommodation(key: key, labelAr: ar.text.trim(), labelEn: en.text.trim());
}

class AdvCategoryForm extends StatelessWidget {
  const AdvCategoryForm({
    super.key,
    required this.nameAr,
    required this.nameEn,
    required this.sensitive,
    required this.active,
    required this.rows,
    this.category,
    this.busy = false,
    this.error,
    this.onSensitive,
    this.onActive,
    this.onAddRow,
    this.onRemoveRow,
    this.onSubmit,
    this.onDelete,
  });

  /// null: a new category.
  final AdvCategory? category;
  final TextEditingController nameAr, nameEn;
  final bool sensitive, active;
  final List<AdvAccommodationRow> rows;
  final bool busy;
  final String? error;
  final ValueChanged<bool>? onSensitive, onActive;
  final VoidCallback? onAddRow, onSubmit, onDelete;
  final ValueChanged<int>? onRemoveRow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = category;
    final err = error;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppField(controller: nameAr, label: t('الاسم بالعربية', 'Name in Arabic')),
      AppField(controller: nameEn, label: t('الاسم بالإنجليزية', 'Name in English'), ltr: true),
      AppSwitchTile(
        icon: Icons.lock_outline_rounded,
        title: t('تصنيف حساس', 'Sensitive category'),
        subtitle: x != null && x.system
            ? t('تصنيف من النظام: حساسيته ثابتة', 'A built-in category: its sensitivity is fixed')
            : t('تنبيهاته وملاحظاته لكاتبها والمرشد الأساسي ومديري الإرشاد فقط، وكل قراءة مسجّلة', 'Its flags and notes: only the author, the primary advisor and the directors; every read is recorded'),
        value: sensitive,
        onChanged: busy || (x != null && x.system) ? null : onSensitive,
      ),
      if (x != null)
        AppSwitchTile(
          icon: Icons.toggle_on_outlined,
          title: t('مفعّل', 'Active'),
          subtitle: t('المتوقف لا يظهر عند فتح تنبيه جديد، وتبقى سجلاته', 'A switched-off category is not offered for new flags; its records stay'),
          value: active,
          onChanged: busy ? null : onActive,
        ),
      AdvSectionTitle(
        t('التسهيلات الموصى بها', 'Recommended accommodations'),
        subtitle: t('تُختار عند فتح تنبيه بهذا التصنيف (مثل وقت إضافي في الامتحان)', 'Picked when a flag of this category is opened (e.g. extra exam time)'),
      ),
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xxs, AppSpace.xxs),
            decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.5), borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final ar = AppField(controller: rows[i].ar, label: t('بالعربية', 'In Arabic'));
                  final en = AppField(controller: rows[i].en, label: t('بالإنجليزية', 'In English'), ltr: true);
                  if (box.maxWidth < 460 * MediaQuery.textScalerOf(context).scale(1)) return Column(children: [ar, en]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: ar), const SizedBox(width: AppSpace.xs), Expanded(child: en)]);
                }),
              ),
              IconButton(
                tooltip: t('إزالة التسهيل', 'Remove the accommodation'),
                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                onPressed: busy || onRemoveRow == null ? null : () => onRemoveRow!(i),
                icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
              ),
            ]),
          ),
        ),
      if (rows.isEmpty) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(t('لا تسهيلات لهذا التصنيف.', 'No accommodations for this category.'), style: AppType.body(context))),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: busy ? null : onAddRow,
          icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
          label: Text(t('إضافة تسهيل', 'Add an accommodation')),
        ),
      ),
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.check_rounded, label: x == null ? t('إضافة التصنيف', 'Add the category') : t('حفظ', 'Save'), busy: busy, onPressed: onSubmit),
      if (x != null && !x.system && onDelete != null) ...[
        const SizedBox(height: AppSpace.xs),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), foregroundColor: appInk(context, c.danger)),
          onPressed: busy ? null : onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: AppIconSize.md),
          label: Text(t('حذف التصنيف', 'Delete the category')),
        ),
      ],
      if (x != null && x.system) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('تصنيف من النظام: يُعاد تسميته أو يُوقف، ولا يُحذف.', 'A built-in category: rename it or switch it off; it cannot be deleted.'), style: AppType.meta(context), textAlign: TextAlign.center),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvCategoriesPage extends StatelessWidget {
  const AdvCategoriesPage({super.key, required this.orgId});
  final int orgId;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('تصنيفات الإرشاد', 'Advising categories'),
        helpPageId: 'org.advising',
        maxWidth: AppWidth.wide.max,
        child: _AdvCategoriesBody(orgId: orgId),
      );
}

class _AdvCategoriesBody extends StatefulWidget {
  const _AdvCategoriesBody({required this.orgId});
  final int orgId;

  @override
  State<_AdvCategoriesBody> createState() => _AdvCategoriesBodyState();
}

class _AdvCategoriesBodyState extends State<_AdvCategoriesBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  List<AdvCategory>? _list;
  AdvLoad _load = AdvLoad.loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.categories(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _list = r.data as List<AdvCategory>;
        _load = AdvLoad.ready;
      } else {
        _load = r.endpointMissing ? AdvLoad.missing : AdvLoad.failed;
        _error = advErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _edit([AdvCategory? x]) async {
    final nameAr = TextEditingController(text: x?.nameAr ?? ''), nameEn = TextEditingController(text: x?.nameEn ?? '');
    final rows = [for (final a in x?.accommodations ?? const <AdvAccommodation>[]) AdvAccommodationRow.of(a)];
    var sensitive = x?.sensitive ?? false, active = x?.active ?? true, busy = false;
    String? error;
    final changed = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          AdvCategoryDraft draft() => AdvCategoryDraft(
                nameAr: nameAr.text,
                nameEn: nameEn.text,
                sensitive: sensitive,
                active: active,
                accommodations: [for (final r in rows) r.value],
              );

          Future<void> submit() async {
            final d = draft();
            final why = d.error();
            if (why != null) {
              set(() => error = why);
              return;
            }
            set(() {
              busy = true;
              error = null;
            });
            final r = await orgCall(() => x == null ? _api.addCategory(d) : _api.saveCategory(x.id, d), quiet: true);
            if (!ctx.mounted) return;
            if (!r.ok) {
              set(() {
                busy = false;
                error = advErrorText(r.error!);
              });
              return;
            }
            final res = r.data;
            final downgraded = res is (AdvCategory, int) ? res.$2 : 0;
            showAppNotice(x == null
                ? t('أُضيف التصنيف', 'Category added')
                : downgraded > 0
                    ? countText(downgraded,
                        ar1: 'حُفظ التصنيف، وأصبحت ملاحظة كان يراها الطالب لفريق الإرشاد فقط',
                        ar2: 'حُفظ التصنيف، وأصبحت ملاحظتان كان يراهما الطالب لفريق الإرشاد فقط',
                        arFew: 'حُفظ التصنيف، وأصبحت $downgraded ملاحظات كان يراها الطالب لفريق الإرشاد فقط',
                        arMany: 'حُفظ التصنيف، وأصبحت $downgraded ملاحظة كان يراها الطالب لفريق الإرشاد فقط',
                        en1: 'Category saved; 1 student-visible note became team-only',
                        en: 'Category saved; $downgraded student-visible notes became team-only')
                    : t('حُفظ التصنيف', 'Category saved'));
            Navigator.pop(ctx, true);
          }

          Future<void> delete() async {
            if (x == null) return;
            if (!await appConfirm(ctx, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف تصنيف «${x.name}»؟ تبقى التنبيهات المغلقة به في السجلات.', 'Delete the category "${x.name}"? Closed flags that use it stay in the records.'))) {
              return;
            }
            set(() {
              busy = true;
              error = null;
            });
            final r = await orgCall(() => _api.deleteCategory(x.id), quiet: true);
            if (!ctx.mounted) return;
            if (!r.ok) {
              set(() {
                busy = false;
                error = advErrorText(r.error!);
              });
              return;
            }
            showAppNotice(t('حُذف التصنيف', 'Category deleted'));
            Navigator.pop(ctx, true);
          }

          return AppSheetContent(
            title: x == null ? t('تصنيف جديد', 'New category') : t('تعديل التصنيف', 'Edit the category'),
            children: [
              AdvCategoryForm(
                category: x,
                nameAr: nameAr,
                nameEn: nameEn,
                sensitive: sensitive,
                active: active,
                rows: rows,
                busy: busy,
                error: error,
                onSensitive: (v) => set(() => sensitive = v),
                onActive: (v) => set(() => active = v),
                onAddRow: () => set(() => rows.add(AdvAccommodationRow())),
                onRemoveRow: (i) => set(() => rows.removeAt(i)),
                onSubmit: submit,
                onDelete: delete,
              ),
            ],
          );
        }));
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => AdvCategoriesView(
        load: _load,
        categories: _list,
        errorText: _error,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onAdd: () => _edit(),
        onOpen: _edit,
      );
}
