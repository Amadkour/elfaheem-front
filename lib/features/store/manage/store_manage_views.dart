// lib/features/store/manage/store_manage_views.dart
//
// The digital store's management widgets from plain values (D-1336): no request, no provider, so the layout harness
// pumps each one at 320 and 1400 px in both languages.
//
//   StoreItemStatusBadge   draft / pending / published / hidden as a tinted pill
//   StoreItemCard          cover, title, kind · price, file state, status
//   StoreItemsListBody     the status filter chips + the cards (+ "New item")
//   StoreItemForm          the create / edit form (titles, description, kind, category, country, stage / grade /
//                          subject, price, points, VAT exempt, cover, file + preview upload with progress, publish)
//   StoreReviewQueueBody   the super admin's pending items with Approve / Reject
//   StoreRejectSheet       the reason of a rejection
//   StoreOrdersBody        the super admin's orders table (cards on phones) with the status filter and Export
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';

import '../../admin/admin_common.dart' show t, money, shortDateTime;
import 'store_manage_api.dart';

AppTone storeStatusTone(String status) => switch (status) {
      'published' => AppTone.success,
      'pending' => AppTone.warning,
      'hidden' => AppTone.neutral,
      _ => AppTone.info,
    };

AppTone storeOrderTone(String status) => switch (status) {
      'paid' => AppTone.success,
      'pending' => AppTone.warning,
      'failed' => AppTone.danger,
      _ => AppTone.neutral,
    };

/// "120 EGP" (the price as entered) and the points price when set.
String storePriceLine(StoreManageItem it) {
  final cash = it.basePrice <= 0 ? t('مجاني', 'Free') : money(it.basePrice, it.currency.isEmpty ? null : it.currency);
  return it.pointsPrice == null ? cash : '$cash · ${t('${it.pointsPrice} نقطة', '${it.pointsPrice} points')}';
}

class StoreItemStatusBadge extends StatelessWidget {
  const StoreItemStatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => AppStatusBadge(label: storeStatusLabel(status), tone: storeStatusTone(status), dense: true);
}

/// The cover thumbnail (a drawn placeholder without one).
class StoreCoverThumb extends StatelessWidget {
  const StoreCoverThumb({super.key, this.url, this.width = 56});
  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = ColoredBox(
      color: c.inputBg,
      child: Center(child: Icon(Icons.menu_book_rounded, color: c.textLight, size: AppIconSize.lg)),
    );
    return ClipRRect(
      borderRadius: AppRadius.chipAll,
      child: SizedBox(
        width: width,
        height: width * 4 / 3,
        child: (url == null || url!.isEmpty)
            ? placeholder
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}

class StoreItemCard extends StatelessWidget {
  const StoreItemCard({super.key, required this.item, this.selected = false, this.onTap, this.trailing});
  final StoreManageItem item;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [
      storeKindLabel(item.kind),
      storePriceLine(item),
      if (item.salesCount > 0) t('${item.salesCount} مبيعات', '${item.salesCount} sales'),
    ].join(' · ');
    return AppCard(
      highlight: selected,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StoreCoverThumb(url: item.coverUrl),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpace.xxs),
            Text(meta, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StoreItemStatusBadge(status: item.status),
              if (!item.hasFile)
                AppStatusBadge(label: t('بلا ملف', 'No file'), tone: AppTone.danger, dense: true)
              else if (item.fileName != null)
                Text(storeSizeLabel(item.fileSize), style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// The list side: status chips with counts, then the cards.
class StoreItemsListBody extends StatelessWidget {
  const StoreItemsListBody({
    super.key,
    required this.items,
    required this.status,
    required this.onStatus,
    required this.onOpen,
    required this.onNew,
    this.selectedId,
    this.loading = false,
  });

  final List<StoreManageItem> items;
  final String? status;
  final ValueChanged<String?> onStatus;
  final ValueChanged<StoreManageItem> onOpen;
  final VoidCallback onNew;
  final int? selectedId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final shown = status == null ? items : [for (final i in items) if (i.status == status) i];
    int count(String s) => items.where((i) => i.status == s).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        EduChoiceChip(label: '${t('الكل', 'All')} (${items.length})', selected: status == null, onTap: () => onStatus(null)),
        for (final s in kStoreStatuses) EduChoiceChip(label: '${storeStatusLabel(s)} (${count(s)})', selected: status == s, onTap: () => onStatus(s)),
      ]),
      AppSpace.gapMd,
      if (loading)
        const AppListSkeleton(items: 4)
      else if (shown.isEmpty)
        AppEmpty(
          icon: Icons.menu_book_rounded,
          title: items.isEmpty ? t('لا عناصر بعد', 'No items yet') : t('لا عناصر بهذه الحالة', 'No items with this status'),
          message: items.isEmpty ? t('أضف كتاباً أو ملخصاً ليبيعه المتجر.', 'Add a book or a summary for the store to sell.') : null,
          actionLabel: items.isEmpty ? t('عنصر جديد', 'New item') : null,
          onAction: items.isEmpty ? onNew : null,
        )
      else
        for (final it in shown) ...[
          StoreItemCard(item: it, selected: it.id == selectedId, onTap: () => onOpen(it)),
          AppSpace.gapXs,
        ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The form
// ═════════════════════════════════════════════════════════════════════════════

/// The values of the form, as the server takes them.
class StoreItemDraft {
  StoreItemDraft.from(StoreManageItem? it, {String? country})
      : titleAr = TextEditingController(text: it?.titleAr ?? ''),
        titleEn = TextEditingController(text: it?.titleEn ?? ''),
        descAr = TextEditingController(text: it?.descriptionAr ?? ''),
        descEn = TextEditingController(text: it?.descriptionEn ?? ''),
        price = TextEditingController(text: it == null ? '' : _num(it.basePrice)),
        points = TextEditingController(text: it?.pointsPrice?.toString() ?? ''),
        pages = TextEditingController(text: it?.pages?.toString() ?? ''),
        kind = it?.kind ?? 'ebook',
        country = it?.countryCode ?? country,
        stageId = it?.stageId,
        gradeId = it?.gradeId,
        subjectId = it?.subjectId,
        categoryId = it?.categoryId,
        vatExempt = it?.vatExempt ?? false,
        coverUrl = it?.coverUrl,
        _initialCover = it?.coverUrl;

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  final TextEditingController titleAr, titleEn, descAr, descEn, price, points, pages;
  String kind;
  String? country;
  int? stageId, gradeId, subjectId, categoryId;
  bool vatExempt;
  String? coverUrl;
  final String? _initialCover;

  bool get hasTitle => titleAr.text.trim().isNotEmpty || titleEn.text.trim().isNotEmpty;
  double? get priceValue => double.tryParse(price.text.trim().replaceAll(',', '.'));
  bool get valid => hasTitle && priceValue != null && priceValue! >= 0;

  /// The body of POST / PATCH. Every field is sent (null clears an optional one), except the cover: it is set by its
  /// own upload route, so the body only clears it (D-1339).
  Map<String, dynamic> body() => {
        'title_ar': titleAr.text.trim(),
        'title_en': titleEn.text.trim(),
        'description_ar': descAr.text.trim(),
        'description_en': descEn.text.trim(),
        'kind': kind,
        'price': priceValue ?? 0,
        'points_price': int.tryParse(points.text.trim()),
        'pages': int.tryParse(pages.text.trim()),
        'vat_exempt': vatExempt,
        'country_code': country,
        'stage_id': stageId,
        'grade_id': gradeId,
        'subject_id': subjectId,
        'category_id': categoryId,
        if (_initialCover != null && coverUrl == null) 'cover_url': null,
      };

  void dispose() {
    for (final c in [titleAr, titleEn, descAr, descEn, price, points, pages]) {
      c.dispose();
    }
  }
}

/// What the form asks its host to do.
abstract class StoreFormActions {
  /// Another country: the host loads that country's stages / subjects.
  void country(String code);

  /// Save the [body]; the host creates the item when it is new.
  Future<void> save(Map<String, dynamic> body);

  /// Pick + crop + upload the cover of the saved item; the new URL or null.
  Future<String?> pickCover();

  /// Pick + upload the item file (`file`) or its preview (`preview`).
  void upload(String kind);
  void publish();
  void hide();
  void delete();
}

class StoreItemForm extends StatefulWidget {
  const StoreItemForm({
    super.key,
    required this.item,
    required this.actions,
    this.countries = const {},
    this.country,
    this.stages = const [],
    this.subjects = const [],
    this.categories = const [],
    this.saving = false,
    this.uploading = const {},
  });

  /// Null = a new item.
  final StoreManageItem? item;
  final StoreFormActions actions;

  /// code → name.
  final Map<String, String> countries;
  final String? country;
  final List<EduStage> stages;
  final List<EduSubject> subjects;
  final List<StoreChoice<int>> categories;
  final bool saving;

  /// `file` / `preview` → the upload's progress (0..1) while it runs.
  final Map<String, double> uploading;

  @override
  State<StoreItemForm> createState() => _StoreItemFormState();
}

class _StoreItemFormState extends State<StoreItemForm> {
  late StoreItemDraft _d = StoreItemDraft.from(widget.item, country: widget.country);
  bool _coverBusy = false;

  @override
  void didUpdateWidget(StoreItemForm old) {
    super.didUpdateWidget(old);
    // another item opened, or the server answered a save: start from its values again (an upload keeps the edits)
    if (old.item?.id != widget.item?.id || (old.saving && !widget.saving && old.item?.updatedAt != widget.item?.updatedAt)) {
      final keep = _d;
      _d = StoreItemDraft.from(widget.item, country: widget.country);
      WidgetsBinding.instance.addPostFrameCallback((_) => keep.dispose());
    }
  }

  @override
  void dispose() {
    _d.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) => setState(fn);

  Future<void> _cover() async {
    // a new item is saved first: the cover route needs its id (D-1339)
    if (widget.item == null) {
      if (!_d.valid) {
        showAppNotice(t('اكتب العنوان والسعر أولاً، ثم أضف الغلاف', 'Enter the title and the price first, then add the cover'), error: true);
        return;
      }
      setState(() => _coverBusy = true);
      await widget.actions.save(_d.body());
      if (!mounted) return;
      if (widget.item == null) {
        setState(() => _coverBusy = false);
        return;
      }
    }
    setState(() => _coverBusy = true);
    final url = await widget.actions.pickCover();
    if (!mounted) return;
    setState(() {
      _coverBusy = false;
      if (url != null) _d.coverUrl = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final c = context.colors;
    final subjects = () {
      if (_d.gradeId == null) return widget.subjects;
      for (final s in widget.stages) {
        for (final g in s.grades) {
          if (g.id == _d.gradeId && g.subjectIds.isNotEmpty) {
            final ids = g.subjectIds.toSet();
            return [for (final x in widget.subjects) if (ids.contains(x.id)) x];
          }
        }
      }
      return widget.subjects;
    }();
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final moneyChars = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // ── head: title + status ──
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(it == null ? t('عنصر جديد', 'New item') : it.title, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (it != null) ...[AppSpace.gapXs, StoreItemStatusBadge(status: it.status)],
      ]),
      if (it?.status == 'pending') ...[
        AppSpace.gapXs,
        Text(t('ينتظر موافقة الإدارة قبل أن يظهر في المتجر.', 'Waiting for the admins to approve it before it shows in the store.'), style: AppType.meta(context)),
      ],
      AppSpace.gapMd,

      // ── what it is ──
      AppSectionCard(
        title: t('البيانات', 'Details'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: _d.titleAr, label: t('العنوان بالعربية', 'Title (Arabic)'), maxLength: 200, onChanged: (_) => _set(() {})),
          AppSpace.gapSm,
          AppField(controller: _d.titleEn, label: t('العنوان بالإنجليزية', 'Title (English)'), ltr: true, maxLength: 200, onChanged: (_) => _set(() {})),
          AppSpace.gapSm,
          AppField(controller: _d.descAr, label: t('الوصف بالعربية', 'Description (Arabic)'), maxLines: 4),
          AppSpace.gapSm,
          AppField(controller: _d.descEn, label: t('الوصف بالإنجليزية', 'Description (English)'), ltr: true, maxLines: 4),
          AppSpace.gapSm,
          AppDropdown<String>(
            value: _d.kind,
            decoration: InputDecoration(labelText: t('النوع', 'Type')),
            items: [for (final k in kStoreKinds) DropdownMenuItem(value: k, child: Text(storeKindLabel(k)))],
            onChanged: (v) => _set(() => _d.kind = v ?? _d.kind),
          ),
          if (widget.categories.isNotEmpty) ...[
            AppSpace.gapSm,
            AppDropdown<int?>(
              value: widget.categories.any((x) => x.id == _d.categoryId) ? _d.categoryId : null,
              decoration: InputDecoration(labelText: t('التصنيف (اختياري)', 'Category (optional)')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t('بدون', 'None'))),
                for (final x in widget.categories) DropdownMenuItem<int?>(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => _set(() => _d.categoryId = v),
            ),
          ],
          AppSpace.gapSm,
          AppField(controller: _d.pages, label: t('عدد الصفحات (اختياري)', 'Pages (optional)'), ltr: true, keyboard: TextInputType.number, inputFormatters: digits),
        ]),
      ),
      AppSpace.gapMd,

      // ── who it is for ──
      AppSectionCard(
        title: t('لمن هذا العنصر', 'Who it is for'),
        subtitle: t('اختياري: يساعد الطالب على إيجاده.', 'Optional: it helps students find it.'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          EduCountryPicker(
            countries: widget.countries,
            value: _d.country,
            onChanged: (v) {
              _set(() {
                _d.country = v;
                _d.stageId = _d.gradeId = _d.subjectId = null;
              });
              widget.actions.country(v);
            },
          ),
          if (widget.countries.length > 1) AppSpace.gapSm,
          EduStageGradePicker(
            stages: widget.stages,
            stageId: _d.stageId,
            gradeId: _d.gradeId,
            onChanged: (s, g, _) => _set(() {
              final same = s == _d.stageId && g == _d.gradeId;
              _d.stageId = same ? null : s;
              _d.gradeId = same ? null : g;
              _d.subjectId = null;
            }),
          ),
          if (subjects.isNotEmpty) ...[
            AppSpace.gapSm,
            AppDropdown<int?>(
              value: subjects.any((x) => x.id == _d.subjectId) ? _d.subjectId : null,
              decoration: InputDecoration(labelText: t('المادة (اختياري)', 'Subject (optional)')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t('بدون', 'None'))),
                for (final x in subjects) DropdownMenuItem<int?>(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => _set(() => _d.subjectId = v),
            ),
          ],
        ]),
      ),
      AppSpace.gapMd,

      // ── price ──
      AppSectionCard(
        title: t('السعر', 'Price'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(
            controller: _d.price,
            label: t('السعر${it == null || it.currency.isEmpty ? '' : ' (${it.currency})'}', 'Price${it == null || it.currency.isEmpty ? '' : ' (${it.currency})'}'),
            helper: t('0 = مجاني. تُحسب الضريبة حسب إعداد الدولة.', '0 = free. VAT follows the country setting.'),
            ltr: true,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: moneyChars,
            onChanged: (_) => _set(() {}),
          ),
          AppSpace.gapSm,
          AppField(
            controller: _d.points,
            label: t('السعر بالنقاط (اختياري)', 'Points price (optional)'),
            ltr: true,
            keyboard: TextInputType.number,
            inputFormatters: digits,
          ),
          AppSwitchTile(
            title: t('معفى من ضريبة القيمة المضافة', 'VAT exempt'),
            subtitle: t('مثل الكتب في بعض الدول.', 'Like books in some countries.'),
            value: _d.vatExempt,
            onChanged: (v) => _set(() => _d.vatExempt = v),
          ),
          if (it != null && it.price.vatPercent > 0 && !it.vatExempt)
            Text(
              t('يدفع الطالب ${money(it.price.gross, it.price.currency)} (منها ضريبة ${money(it.price.vat, it.price.currency)})',
                  'The student pays ${money(it.price.gross, it.price.currency)} (VAT ${money(it.price.vat, it.price.currency)})'),
              style: AppType.meta(context),
            ),
        ]),
      ),
      AppSpace.gapMd,

      // ── cover ──
      AppSectionCard(
        title: t('الغلاف', 'Cover'),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StoreCoverThumb(url: _d.coverUrl, width: 72),
          AppSpace.gapMd,
          Expanded(
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppButton.secondary(
                label: _d.coverUrl == null ? t('اختر صورة', 'Choose image') : t('تغيير', 'Change'),
                icon: Icons.image_rounded,
                busy: _coverBusy,
                size: AppButtonSize.sm,
                onPressed: _coverBusy ? null : _cover,
              ),
              if (_d.coverUrl != null)
                AppButton.ghost(label: t('إزالة', 'Remove'), size: AppButtonSize.sm, onPressed: () => _set(() => _d.coverUrl = null)),
            ]),
          ),
        ]),
      ),
      AppSpace.gapMd,

      // ── files (after the first save) ──
      AppSectionCard(
        title: t('الملفات', 'Files'),
        subtitle: it == null ? t('احفظ العنصر أولاً ثم ارفع ملفه.', 'Save the item first, then upload its file.') : t('PDF أو EPUB حتى 200 ميجابايت. تبقى الملفات خاصة.', 'PDF or EPUB up to 200 MB. Files stay private.'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _FileRow(
            label: t('ملف العنصر', 'Item file'),
            value: it == null || !it.hasFile ? t('لم يُرفع بعد', 'Not uploaded yet') : '${it.fileName ?? ''} ${storeSizeLabel(it.fileSize)}'.trim(),
            done: it?.hasFile ?? false,
            progress: widget.uploading['file'],
            onUpload: it == null ? null : () => widget.actions.upload('file'),
          ),
          AppSpace.gapSm,
          _FileRow(
            label: t('معاينة (اختياري)', 'Preview (optional)'),
            value: it?.hasPreview ?? false ? t('مرفوعة', 'Uploaded') : t('صفحات أو صورة يراها الطالب قبل الشراء', 'Pages or an image students see before buying'),
            done: it?.hasPreview ?? false,
            progress: widget.uploading['preview'],
            onUpload: it == null ? null : () => widget.actions.upload('preview'),
          ),
        ]),
      ),
      AppSpace.gapLg,

      // ── actions ──
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
        if (it != null)
          AppButton.ghost(label: t('حذف', 'Delete'), icon: Icons.delete_outline_rounded, onPressed: widget.saving ? null : widget.actions.delete),
        if (it != null && (it.status == 'published' || it.status == 'pending'))
          AppButton.secondary(label: t('إخفاء', 'Hide'), icon: Icons.visibility_off_rounded, onPressed: widget.saving ? null : widget.actions.hide),
        AppButton.secondary(
          label: t('حفظ', 'Save'),
          icon: Icons.save_rounded,
          busy: widget.saving,
          onPressed: _d.valid && !widget.saving ? () => widget.actions.save(_d.body()) : null,
        ),
        if (it != null && it.canPublish)
          AppButton.primary(label: t('نشر', 'Publish'), icon: Icons.publish_rounded, onPressed: widget.saving ? null : widget.actions.publish),
      ]),
      if (it != null && !it.hasFile && it.status != 'published') ...[
        AppSpace.gapXs,
        Text(t('ارفع ملف العنصر لتتمكن من نشره.', 'Upload the item file to publish it.'), style: AppType.meta(context).copyWith(color: c.textMedium), textAlign: TextAlign.end),
      ],
    ]);
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.label, required this.value, required this.done, this.progress, this.onUpload});
  final String label, value;
  final bool done;
  final double? progress;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = progress != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(done ? Icons.check_circle_rounded : Icons.description_outlined, size: AppIconSize.md, color: done ? c.success : c.textLight),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.bodyStrong(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(value, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        AppSpace.gapXs,
        AppButton.tonal(
          label: done ? t('استبدال', 'Replace') : t('رفع', 'Upload'),
          icon: Icons.upload_rounded,
          size: AppButtonSize.sm,
          busy: busy,
          onPressed: busy ? null : onUpload,
        ),
      ]),
      if (busy) ...[
        AppSpace.gapXs,
        Semantics(
          label: t('جارٍ الرفع ${(progress! * 100).round()}٪', 'Uploading ${(progress! * 100).round()}%'),
          child: LinearProgressIndicator(value: progress, color: c.primary, backgroundColor: c.inputBg, minHeight: AppSpace.xxs),
        ),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Super admin: review queue
// ═════════════════════════════════════════════════════════════════════════════

class StoreReviewQueueBody extends StatelessWidget {
  const StoreReviewQueueBody({super.key, required this.items, required this.onApprove, required this.onReject, this.busyId, this.loading = false});
  final List<StoreManageItem> items;
  final ValueChanged<StoreManageItem> onApprove;
  final ValueChanged<StoreManageItem> onReject;
  final int? busyId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppListSkeleton(items: 3);
    if (items.isEmpty) {
      return AppEmpty(
        icon: Icons.task_alt_rounded,
        title: t('لا شيء بانتظار المراجعة', 'Nothing waiting for review'),
        message: t('تظهر هنا العناصر التي يرسلها المعلمون للنشر.', 'Items teachers send for publishing show up here.'),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1000 ? 2 : 1;
      final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
      return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
        for (final it in items)
          SizedBox(
            width: w,
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StoreItemCard(item: it),
                if ((AppConfig.lang == 'ar' ? it.descriptionAr : it.descriptionEn).isNotEmpty) ...[
                  AppSpace.gapXs,
                  Text(AppConfig.lang == 'ar' ? it.descriptionAr : it.descriptionEn, style: AppType.body(context), maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                AppSpace.gapXs,
                Text(
                  [
                    if (it.hasPreview) t('فيه معاينة', 'Has a preview') else t('بلا معاينة', 'No preview'),
                    if (it.updatedAt != null) shortDateTime(it.updatedAt),
                  ].join(' · '),
                  style: AppType.meta(context),
                ),
                AppSpace.gapSm,
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
                  AppButton.secondary(
                    label: t('رفض', 'Reject'),
                    icon: Icons.close_rounded,
                    size: AppButtonSize.sm,
                    onPressed: busyId == it.id ? null : () => onReject(it),
                  ),
                  AppButton.primary(
                    label: t('موافقة ونشر', 'Approve'),
                    icon: Icons.check_rounded,
                    size: AppButtonSize.sm,
                    busy: busyId == it.id,
                    onPressed: busyId == it.id ? null : () => onApprove(it),
                  ),
                ]),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// The reason of a rejection (sent to the owner with the notice). Pops the text, or null.
class StoreRejectSheet extends StatefulWidget {
  const StoreRejectSheet({super.key, required this.title});
  final String title;

  @override
  State<StoreRejectSheet> createState() => _StoreRejectSheetState();
}

class _StoreRejectSheetState extends State<StoreRejectSheet> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctl.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('رفض «${widget.title}»', 'Reject "${widget.title}"'), style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          AppSpace.gapXs,
          Text(t('يعود العنصر مسودةً ويصل السبب لصاحبه.', 'The item goes back to draft and its owner gets the reason.'), style: AppType.meta(context)),
          AppSpace.gapMd,
          AppField(controller: _ctl, label: t('السبب', 'Reason'), maxLines: 3, maxLength: 500, onChanged: (_) => setState(() {})),
          AppSpace.gapMd,
          Row(children: [
            Expanded(child: AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop())),
            AppSpace.gapSm,
            Expanded(child: AppButton.danger(label: t('رفض', 'Reject'), onPressed: ready ? () => Navigator.of(context).pop(_ctl.text.trim()) : null)),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Super admin: orders
// ═════════════════════════════════════════════════════════════════════════════

const kStoreOrderStatuses = ['pending', 'paid', 'failed', 'cancelled', 'refunded'];

class StoreOrdersBody extends StatelessWidget {
  const StoreOrdersBody({
    super.key,
    required this.orders,
    required this.status,
    required this.onStatus,
    required this.onExport,
    this.state = AppTableState.ready,
    this.onRetry,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
  });

  final List<StoreOrderRow> orders;
  final String? status;
  final ValueChanged<String?> onStatus;
  final VoidCallback onExport;
  final AppTableState state;
  final VoidCallback? onRetry;
  final bool hasMore, loadingMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<StoreOrderRow>(
      state: state,
      onRetry: onRetry,
      rows: orders,
      rowId: (o) => '${o.id}',
      hasMore: hasMore,
      loadingMore: loadingMore,
      onLoadMore: onLoadMore,
      filters: [
        AppTableFilter(
          label: t('الحالة', 'Status'),
          value: status,
          options: [for (final s in kStoreOrderStatuses) (s, storeOrderStatusLabel(s))],
          onChanged: onStatus,
        ),
      ],
      toolbarTrailing: AppButton.secondary(label: t('تصدير', 'Export'), icon: Icons.ios_share_rounded, size: AppButtonSize.sm, onPressed: orders.isEmpty ? null : onExport),
      empty: AppEmpty(icon: Icons.receipt_long_rounded, title: t('لا طلبات', 'No orders'), message: t('تظهر هنا مشتريات المتجر.', 'Store purchases show up here.')),
      columns: [
        AppTableColumn.text(key: 'id', label: '#', width: 72, text: (o) => '#${o.id}'),
        AppTableColumn.text(key: 'user', label: t('المشتري', 'Buyer'), primary: true, flex: 2, text: (o) => o.username == null ? o.userName : '${o.userName} · @${o.username}'),
        AppTableColumn.text(key: 'items', label: t('العناصر', 'Items'), flex: 3, text: (o) => o.items.join('، ')),
        AppTableColumn.text(key: 'total', label: t('الإجمالي', 'Total'), numeric: true, text: (o) => o.method == 'points' && o.pointsSpent != null ? t('${o.pointsSpent} نقطة', '${o.pointsSpent} pts') : money(o.total, o.currency)),
        AppTableColumn.text(key: 'vat', label: t('الضريبة', 'VAT'), numeric: true, hideBelow: 900, text: (o) => money(o.vatAmount, o.currency)),
        AppTableColumn.text(key: 'method', label: t('الطريقة', 'Method'), text: (o) => storeMethodLabel(o.method)),
        AppTableColumn(
          key: 'status',
          label: t('الحالة', 'Status'),
          cell: (context, o) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              AppStatusBadge(label: storeOrderStatusLabel(o.status), tone: storeOrderTone(o.status), dense: true),
              if (o.needsRefund) AppStatusBadge(label: t('يحتاج استرداداً', 'Needs refund'), tone: AppTone.danger, icon: Icons.undo_rounded, dense: true),
            ]),
          ),
        ),
        AppTableColumn.text(key: 'created_at', label: t('التاريخ', 'Date'), hideBelow: 1100, text: (o) => shortDateTime(o.createdAt)),
      ],
    );
  }
}

/// The orders as an Export Studio table (bilingual labels; the caller wraps it in `bilingualExport`).
AppTableExport storeOrdersExport(List<StoreOrderRow> orders, {String? status}) => AppTableExport(
      id: 'admin.store_orders',
      title: t('طلبات المتجر', 'Store orders'),
      filters: {if (status != null) t('الحالة', 'Status'): storeOrderStatusLabel(status)},
      columns: [
        AppExportColumn('id', t('رقم الطلب', 'Order'), type: AppColType.integer, locked: true, labels: const {'ar': 'رقم الطلب', 'en': 'Order'}),
        AppExportColumn('user', t('المشتري', 'Buyer'), labels: const {'ar': 'المشتري', 'en': 'Buyer'}),
        AppExportColumn('items', t('العناصر', 'Items'), labels: const {'ar': 'العناصر', 'en': 'Items'}),
        AppExportColumn('currency', t('العملة', 'Currency'), labels: const {'ar': 'العملة', 'en': 'Currency'}),
        AppExportColumn('subtotal', t('قبل الضريبة', 'Subtotal'), type: AppColType.money, total: AppTotal.sum, labels: const {'ar': 'قبل الضريبة', 'en': 'Subtotal'}),
        AppExportColumn('vat', t('الضريبة', 'VAT'), type: AppColType.money, total: AppTotal.sum, labels: const {'ar': 'الضريبة', 'en': 'VAT'}),
        AppExportColumn('total', t('الإجمالي', 'Total'), type: AppColType.money, total: AppTotal.sum, labels: const {'ar': 'الإجمالي', 'en': 'Total'}),
        AppExportColumn('points', t('النقاط', 'Points'), type: AppColType.integer, visible: false, labels: const {'ar': 'النقاط', 'en': 'Points'}),
        AppExportColumn('method', t('الطريقة', 'Method'), labels: const {'ar': 'الطريقة', 'en': 'Method'}),
        AppExportColumn('status', t('الحالة', 'Status'),
            type: AppColType.status, statusLabels: {for (final s in kStoreOrderStatuses) s: storeOrderStatusLabel(s)}, labels: const {'ar': 'الحالة', 'en': 'Status'}),
        AppExportColumn('created_at', t('التاريخ', 'Date'), type: AppColType.dateTime, labels: const {'ar': 'التاريخ', 'en': 'Date'}),
        AppExportColumn('paid_at', t('تاريخ الدفع', 'Paid at'), type: AppColType.dateTime, visible: false, labels: const {'ar': 'تاريخ الدفع', 'en': 'Paid at'}),
        AppExportColumn('needs_refund', t('يحتاج استرداداً', 'Needs refund'), labels: const {'ar': 'يحتاج استرداداً', 'en': 'Needs refund'}),
      ],
      rows: [
        for (final o in orders)
          {
            'id': o.id,
            'user': o.username == null ? o.userName : '${o.userName} (@${o.username})',
            'items': o.items.join(' / '),
            'currency': o.currency,
            'subtotal': o.subtotal,
            'vat': o.vatAmount,
            'total': o.total,
            'points': o.pointsSpent,
            'method': storeMethodLabel(o.method),
            'status': o.status,
            'created_at': o.createdAt,
            'paid_at': o.paidAt,
            'needs_refund': o.needsRefund ? t('نعم', 'Yes') : '',
          },
      ],
    );
