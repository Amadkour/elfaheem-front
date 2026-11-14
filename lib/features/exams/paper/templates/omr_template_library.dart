// "Bubble sheet types" — the super admin's global library of OMR templates (D-155): every family with its versions
// (draft · pending approval · published · rejected · retired), questions × options, the student ID kind and a preview;
// approve / reject (with a reason) a teacher's pending version; whether teachers' sheet types need approval
// (`omr.require_approval`, default on); "New bubble sheet type" opens the learning flow. Kill switch `exam.omr`
// (the services hub tile). Presentational: TemplateLibraryView (plain values); the state below wires the engine.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asMapList, t;
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart' show omrPublishedText, omrTypesText, omrVersionsText;
import 'package:flutter_education_app/features/exams/paper/templates/omr_template_learn.dart';
import 'package:flutter_education_app/features/exams/paper/templates/omr_templates.dart';

Future<void> openOmrTemplateLibrary(BuildContext context, {bool isSuperAdmin = true}) => Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: OmrTemplateLibraryPage.routeName),
      builder: (_) => OmrTemplateLibraryPage(isSuperAdmin: isSuperAdmin),
    ));

/// Opens a version in the learning flow (tests swap it).
typedef OpenTemplate = Future<bool?> Function(BuildContext context, {int? templateId, bool readOnly});

class OmrTemplateLibraryPage extends StatefulWidget {
  const OmrTemplateLibraryPage({super.key, this.isSuperAdmin = true, this.api, this.openTemplate});

  static const routeName = '/omr-templates';
  final bool isSuperAdmin;
  final OmrTemplatesApi? api;
  final OpenTemplate? openTemplate;

  @override
  State<OmrTemplateLibraryPage> createState() => _OmrTemplateLibraryPageState();
}

class _OmrTemplateLibraryPageState extends State<OmrTemplateLibraryPage> {
  late final OmrTemplatesApi _api = widget.api ?? OmrTemplatesApi();
  List<OmrTemplateRow>? _rows;
  bool? _requireApproval;
  bool? _smartPhotos; // null: not loaded, or an older server without the switch
  String? _error;
  LibraryFilter _filter = LibraryFilter.all;
  final _previews = <int, Uint8List?>{};
  final _asked = <int>{};
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.isSuperAdmin) _loadSettings();
    final r = await _api.list();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = [for (final m in asMapList(r.map['items'])) OmrTemplateRow.fromJson(m)];
        _requireApproval = r.map['require_approval'] is bool ? r.map['require_approval'] as bool : _requireApproval;
        _error = null;
      } else {
        _error = omrTemplateErrorText(r);
      }
    });
  }

  Future<void> _loadSettings() async {
    final r = await _api.settings();
    if (!mounted || !r.ok) return;
    final v = r.map['smart_photos'];
    if (v is bool) setState(() => _smartPhotos = v);
  }

  Future<void> _preview(int id) async {
    if (!_asked.add(id)) return;
    final b = await _api.image(id, 'preview');
    if (mounted) setState(() => _previews[id] = b);
  }

  Future<bool?> _open({int? templateId, bool readOnly = false}) {
    final o = widget.openTemplate;
    if (o != null) return o(context, templateId: templateId, readOnly: readOnly);
    return openOmrTemplateLearn(context, isSuperAdmin: widget.isSuperAdmin, templateId: templateId, readOnly: readOnly);
  }

  Future<void> _openAndReload({int? templateId, bool readOnly = false}) async {
    await _open(templateId: templateId, readOnly: readOnly);
    if (mounted) _load();
  }

  Future<void> _approve(OmrTemplateRow row) async {
    setState(() => _busyId = row.id);
    final r = await _api.approve(row.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!r.ok) {
      showAppNotice(omrTemplateErrorText(r), error: true);
      return;
    }
    showAppNotice(t('نُشر «${row.displayName}» الإصدار ${row.version}', '"${row.displayName}" version ${row.version} is published'));
    _load();
  }

  Future<void> _reject(OmrTemplateRow row) async {
    final reason = await askRejectReason(context);
    if (reason == null || !mounted) return;
    setState(() => _busyId = row.id);
    final r = await _api.reject(row.id, reason);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!r.ok) {
      showAppNotice(omrTemplateErrorText(r), error: true);
      return;
    }
    showAppNotice(t('رُفض الإصدار ${row.version} — يرى صاحبه السبب', 'Version ${row.version} rejected — its owner sees the reason'));
    _load();
  }

  Future<void> _newVersion(OmrTemplateRow row) async {
    setState(() => _busyId = row.id);
    final r = await _api.newVersion(row.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!r.ok) {
      showAppNotice(omrTemplateErrorText(r), error: true);
      return;
    }
    final nv = OmrTemplateRow.fromJson(r.map);
    showAppNotice(t('أُنشئ الإصدار ${nv.version} — الاختبارات التي تستخدم الإصدار ${row.version} تبقى عليه.',
        'Version ${nv.version} created — exams that use version ${row.version} keep it.'));
    await _openAndReload(templateId: nv.id);
  }

  Future<void> _setApproval(bool v) async {
    final before = _requireApproval;
    setState(() => _requireApproval = v);
    final r = await _api.putSettings(requireApproval: v);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _requireApproval = before);
      showAppNotice(omrTemplateErrorText(r), error: true);
      return;
    }
    final now = r.map['require_approval'] is bool ? r.map['require_approval'] as bool : v;
    setState(() => _requireApproval = now);
    showAppNotice(now
        ? t('حُفظ: أنواع المعلمين تحتاج اعتمادك', "Saved: teachers' sheet types need your approval")
        : t('حُفظ: تُنشر أنواع المعلمين فور حفظها', "Saved: teachers' sheet types are published as soon as they are saved"));
  }

  Future<void> _setSmartPhotos(bool v) async {
    final before = _smartPhotos;
    setState(() => _smartPhotos = v);
    final r = await _api.putSettings(smartPhotos: v);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _smartPhotos = before);
      showAppNotice(omrTemplateErrorText(r), error: true);
      return;
    }
    final now = r.map['smart_photos'] is bool ? r.map['smart_photos'] as bool : v;
    setState(() => _smartPhotos = now);
    // saved: said like the other settings (the switch alone moved without a word)
    showAppNotice(now
        ? t('حُفظ: المعالجة الذكية لصور الأوراق مفعّلة', 'Saved: smart processing of sheet photos is on')
        : t('حُفظ: المعالجة الذكية لصور الأوراق متوقفة — يعمل القارئ السابق', 'Saved: smart processing of sheet photos is off — the previous reader is used'));
  }

  void _family(OmrTemplateFamily f) {
    showAppSheet<void>(
      context,
      (ctx) => FamilySheet(
        family: f,
        preview: _previews[f.current.id],
        isSuperAdmin: widget.isSuperAdmin,
        onAction: (action, row) {
          Navigator.of(ctx).pop();
          switch (action) {
            case FamilyAction.open:
              _openAndReload(templateId: row.id, readOnly: !row.editable);
            case FamilyAction.review:
              _openAndReload(templateId: row.id, readOnly: true);
            case FamilyAction.approve:
              _approve(row);
            case FamilyAction.reject:
              _reject(row);
            case FamilyAction.newVersion:
              _newVersion(row);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey(kOmrFeatureKey),
      appBar: ScreenAppBar(
        title: t('أنواع أوراق التظليل', 'Bubble sheet types'),
        actions: [AppRefreshAction(onRefresh: _load)],
      ),
      child: AppRefresh(
        onRefresh: _load,
        child: TemplateLibraryView(
          rows: _rows,
          error: _error,
          filter: _filter,
          requireApproval: _requireApproval,
          isSuperAdmin: widget.isSuperAdmin,
          previews: _previews,
          busyId: _busyId,
          onNeedPreview: _preview,
          onFilter: (f) => setState(() => _filter = f),
          onRetry: _load,
          onNew: () => _openAndReload(),
          onFamily: _family,
          onApprove: _approve,
          onReject: _reject,
          onReview: (r) => _openAndReload(templateId: r.id, readOnly: true),
          onApproval: widget.isSuperAdmin ? _setApproval : null,
          smartPhotos: _smartPhotos,
          onSmartPhotos: widget.isSuperAdmin ? _setSmartPhotos : null,
        ),
      ),
    );
  }
}

class TemplateLibraryView extends StatelessWidget {
  const TemplateLibraryView({
    super.key,
    required this.rows,
    this.error,
    this.filter = LibraryFilter.all,
    this.requireApproval,
    this.isSuperAdmin = true,
    this.previews = const {},
    this.busyId,
    this.onNeedPreview,
    required this.onFilter,
    required this.onRetry,
    required this.onNew,
    required this.onFamily,
    required this.onApprove,
    required this.onReject,
    required this.onReview,
    this.onApproval,
    this.smartPhotos,
    this.onSmartPhotos,
  });

  /// null = loading.
  final List<OmrTemplateRow>? rows;
  final String? error;
  final LibraryFilter filter;
  final bool? requireApproval;
  final bool isSuperAdmin;
  final Map<int, Uint8List?> previews;
  final int? busyId;
  final ValueChanged<int>? onNeedPreview;
  final ValueChanged<LibraryFilter> onFilter;
  final VoidCallback onRetry;
  final VoidCallback onNew;
  final ValueChanged<OmrTemplateFamily> onFamily;
  final ValueChanged<OmrTemplateRow> onApprove;
  final ValueChanged<OmrTemplateRow> onReject;
  final ValueChanged<OmrTemplateRow> onReview;
  final ValueChanged<bool>? onApproval;

  /// The super admin's smart phone photos switch (D-163); hidden while null.
  final bool? smartPhotos;
  final ValueChanged<bool>? onSmartPhotos;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = rows;
    final families = list == null ? const <OmrTemplateFamily>[] : groupFamilies(list);
    final pending = [for (final f in families) ...f.versions.where((v) => v.pending)];
    final shown = [for (final f in families) if (libraryFilterMatches(filter, f)) f];
    final published = families.where((f) => f.versions.any((v) => v.published)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Header(families: families.length, published: published, pending: pending.length, onNew: onNew),
              const SizedBox(height: AppSpace.md),
              if (error != null && list == null)
                AppEmpty(icon: Icons.cloud_off_rounded, title: error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: onRetry)
              else if (list == null)
                const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
              else ...[
                if ((onApproval != null && requireApproval != null) || (onSmartPhotos != null && smartPhotos != null)) ...[
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (onApproval != null && requireApproval != null)
                        AppSwitchTile(
                          key: const ValueKey('omr.require_approval'),
                          icon: Icons.verified_user_outlined,
                          title: t('أنواع المعلمين تحتاج اعتمادي', 'Teachers\' sheet types need my approval'),
                          subtitle: t('عند الإيقاف يُنشر ما يتعلّمه المعلم فور حفظه.', 'When off, a teacher\'s learned sheet is published as soon as it is saved.'),
                          value: requireApproval!,
                          onChanged: onApproval,
                        ),
                      if (onSmartPhotos != null && smartPhotos != null)
                        AppSwitchTile(
                          key: const ValueKey('omr.smart_photos'),
                          icon: Icons.auto_fix_high_rounded,
                          title: t('المعالجة الذكية لصور الأوراق', 'Smart processing of sheet photos'),
                          subtitle: t('تُحسَّن الصورة العادية بدل رفضها، والإجابة غير الواضحة تذهب للمراجعة. عند الإيقاف يعود القارئ السابق.',
                              'An ordinary photo is improved instead of refused, and an unclear answer goes to review. When off, the previous reader is used.'),
                          value: smartPhotos!,
                          onChanged: onSmartPhotos,
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpace.md),
                ],
                if (isSuperAdmin && pending.isNotEmpty) ...[
                  AppSectionTitle(t('بانتظار اعتمادك', 'Waiting for your approval'), subtitle: omrVersionsText(pending.length)),
                  const SizedBox(height: AppSpace.xs),
                  for (final p in pending)
                    PendingCard(
                      row: p,
                      preview: previews[p.id],
                      busy: busyId == p.id,
                      onNeedPreview: onNeedPreview,
                      onApprove: () => onApprove(p),
                      onReject: () => onReject(p),
                      onReview: () => onReview(p),
                    ),
                  const SizedBox(height: AppSpace.md),
                ],
                AppSectionTitle(t('كل الأنواع', 'Every sheet type')),
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  for (final f in LibraryFilter.values)
                    KeyedSubtree(key: ValueKey('omr.filter.${f.name}'), child: AppChoiceChip(label: libraryFilterLabel(f), selected: filter == f, onTap: () => onFilter(f))),
                ]),
                const SizedBox(height: AppSpace.sm),
                if (shown.isEmpty)
                  AppEmpty(
                    icon: Icons.grid_off_rounded,
                    title: families.isEmpty ? t('لا توجد أنواع بعد', 'No sheet types yet') : t('لا شيء هنا', 'Nothing here'),
                    message: families.isEmpty
                        ? t('ارفع ورقة فارغة ونموذجًا مظلّلًا لتعليم المنصة نوعًا جديدًا.', 'Upload a blank and a filled sheet to teach the platform a new type.')
                        : t('جرّب عامل تصفية آخر.', 'Try another filter.'),
                    actionLabel: families.isEmpty ? t('نوع ورقة جديد', 'New bubble sheet type') : null,
                    onAction: families.isEmpty ? onNew : null,
                  )
                else
                  LayoutBuilder(builder: (context, box) {
                    final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
                    final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
                    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                      for (final f in shown)
                        SizedBox(
                          width: w,
                          child: FamilyCard(family: f, preview: previews[f.current.id], onNeedPreview: onNeedPreview, onTap: () => onFamily(f)),
                        ),
                    ]);
                  }),
                if (error != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(error!, style: appText(12.5, c: c.danger)),
                ],
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.families, required this.published, required this.pending, required this.onNew});
  final int families;
  final int published;
  final int pending;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('مكتبة أوراق التظليل', 'Bubble sheet library'), style: appText(19, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: AppSpace.xxs),
          Text(
              t('الأنواع التي يختارها المعلمون لاختبارات أوراق التظليل. كل نوع له إصدارات؛ تبقى الاختبارات على الإصدار الذي اختارته.',
                  'The types teachers choose for bubble-sheet exams. Each type has versions; an exam keeps the version it picked.'),
              style: appText(13, c: c.textMedium, h: 1.45)),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            FactChip(key: const ValueKey('omr.library.types'), icon: Icons.grid_on_rounded, label: omrTypesText(families)),
            FactChip(key: const ValueKey('omr.library.published'), icon: Icons.verified_rounded, color: c.success, label: omrPublishedText(published)),
            if (pending > 0) FactChip(icon: Icons.hourglass_top_rounded, color: c.warning, label: t('$pending بانتظار الاعتماد', '$pending pending approval')),
          ]),
        ]);
        final button = KeyedSubtree(
          key: const ValueKey('omr.library.new'),
          child: AppPrimaryButton(label: t('نوع ورقة جديد', 'New bubble sheet type'), icon: Icons.add_rounded, onPressed: onNew),
        );
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: AppSpace.md), button]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: text),
          const SizedBox(width: AppSpace.lg),
          SizedBox(width: 260, child: button),
        ]);
      }),
    );
  }
}

/// The sheet preview (or a calm placeholder while it loads / when there is none).
class SheetThumb extends StatelessWidget {
  const SheetThumb({super.key, required this.id, required this.bytes, this.onNeed, this.width = 72});
  final int id;
  final Uint8List? bytes;
  final ValueChanged<int>? onNeed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (bytes == null) WidgetsBinding.instance.addPostFrameCallback((_) => onNeed?.call(id));
    return Container(
      width: width,
      height: width * 1.414,
      decoration: BoxDecoration(color: c.cardBg2, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? Icon(Icons.grid_on_rounded, color: c.textLight, size: width * 0.4)
          : Image.memory(bytes!, fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: t('معاينة الورقة', 'Sheet preview')),
    );
  }
}

class FamilyCard extends StatelessWidget {
  const FamilyCard({super.key, required this.family, this.preview, this.onNeedPreview, required this.onTap});
  final OmrTemplateFamily family;
  final Uint8List? preview;
  final ValueChanged<int>? onNeedPreview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cur = family.current;
    return Semantics(
      button: true,
      label: cur.displayName,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetThumb(key: ValueKey('omr.thumb.${cur.id}'), id: cur.id, bytes: preview, onNeed: onNeedPreview),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cur.displayName, key: ValueKey('omr.family.${family.familyId}'), style: appText(14.5, w: FontWeight.w800, c: c.textDark, h: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(cur.shape, style: appText(12.5, c: c.textMedium)),
              Text(cur.idLine, style: appText(12.5, c: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                if (family.isBuiltin) AppBadgePill(t('مدمج', 'Built-in'), color: c.purple, icon: Icons.print_rounded),
                for (final v in family.versions.take(4))
                  AppBadgePill(t('إصدار ${v.version} · ${omrStatusLabel(v.status)}', 'v${v.version} · ${omrStatusLabel(v.status)}'), color: omrStatusColor(context, v.status)),
                if (family.versions.length > 4) AppBadgePill('+${family.versions.length - 4}', color: c.textMedium),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class PendingCard extends StatelessWidget {
  const PendingCard({
    super.key,
    required this.row,
    this.preview,
    this.busy = false,
    this.onNeedPreview,
    required this.onApprove,
    required this.onReject,
    required this.onReview,
  });
  final OmrTemplateRow row;
  final Uint8List? preview;
  final bool busy;
  final ValueChanged<int>? onNeedPreview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final created = row.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetThumb(id: row.id, bytes: preview, onNeed: onNeedPreview, width: 60),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('${row.displayName} · الإصدار ${row.version}', '${row.displayName} · v${row.version}'),
                    style: appText(14.5, w: FontWeight.w800, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${row.shape} · ${row.idLine}', style: appText(12.5, c: c.textMedium, h: 1.4)),
                Text(
                    [
                      row.ownerRole == 'teacher' ? t('من معلم', 'From a teacher') : t('من ${row.ownerRole}', 'From ${row.ownerRole}'),
                      if (created != null) AppTime.dateTime(created),
                      if (row.validationOk == true) t('اجتاز الفحص', 'Passed the checks'),
                    ].join(' · '),
                    style: appText(12, c: c.textLight)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            TextButton.icon(
              key: ValueKey('omr.pending.review.${row.id}'),
              onPressed: busy ? null : onReview,
              style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(t('مراجعة الأسئلة', 'Walk the questions')),
            ),
            OutlinedButton(
              key: ValueKey('omr.pending.reject.${row.id}'),
              onPressed: busy ? null : onReject,
              style: OutlinedButton.styleFrom(foregroundColor: c.danger, minimumSize: const Size(AppTouch.min, AppTouch.min), side: BorderSide(color: c.danger.withValues(alpha: 0.5))),
              child: Text(t('رفض', 'Reject')),
            ),
            FilledButton.icon(
              key: ValueKey('omr.pending.approve.${row.id}'),
              onPressed: busy ? null : onApprove,
              style: FilledButton.styleFrom(backgroundColor: c.successBase, foregroundColor: c.onHero, minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: Text(t('اعتماد ونشر', 'Approve and publish')),
            ),
          ]),
        ]),
      ),
    );
  }
}

enum FamilyAction { open, review, approve, reject, newVersion }

/// One family: the preview, every version with its status and the actions it allows.
class FamilySheet extends StatelessWidget {
  const FamilySheet({super.key, required this.family, this.preview, this.isSuperAdmin = true, required this.onAction});
  final OmrTemplateFamily family;
  final Uint8List? preview;
  final bool isSuperAdmin;
  final void Function(FamilyAction action, OmrTemplateRow row) onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cur = family.current;
    final top = family.topVersion;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetThumb(id: cur.id, bytes: preview, width: 96),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cur.displayName, style: appText(17, w: FontWeight.w800, c: c.textDark, h: 1.35)),
              const SizedBox(height: AppSpace.xxs),
              Text(cur.shape, style: appText(13, c: c.textMedium)),
              Text(cur.idLine, style: appText(13, c: c.textMedium)),
              if (cur.formsOnSheet.isNotEmpty) Text(t('النماذج: ${cur.formsOnSheet.join('، ')}', 'Models: ${cur.formsOnSheet.join(', ')}'), style: appText(13, c: c.textMedium)),
              if (cur.printable) ...[
                const SizedBox(height: AppSpace.xxs),
                AppBadgePill(t('تطبعه المنصة', 'Printed by the platform'), color: c.purple, icon: Icons.print_rounded),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('الإصدارات', 'Versions')),
        const SizedBox(height: AppSpace.xs),
        for (final v in family.versions) _VersionTile(row: v, isSuperAdmin: isSuperAdmin, newVersion: top + 1, onAction: onAction),
      ]),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.row, required this.isSuperAdmin, required this.newVersion, required this.onAction});
  final OmrTemplateRow row;
  final bool isSuperAdmin;
  final int newVersion;
  final void Function(FamilyAction action, OmrTemplateRow row) onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = row.approvedAt ?? row.createdAt;
    Widget btn(String key, String label, FamilyAction a, {bool primary = false, Color? color}) => primary
        ? FilledButton(
            key: ValueKey('omr.version.$key.${row.id}'),
            onPressed: () => onAction(a, row),
            style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text(label))
        : TextButton(
            key: ValueKey('omr.version.$key.${row.id}'),
            onPressed: () => onAction(a, row),
            style: TextButton.styleFrom(foregroundColor: color, minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text(label));
    final actions = <Widget>[
      if (row.editable && !row.isBuiltin) btn('open', t('متابعة', 'Continue'), FamilyAction.open, primary: true),
      if (row.pending && isSuperAdmin) ...[
        btn('review', t('مراجعة', 'Review'), FamilyAction.review),
        btn('reject', t('رفض', 'Reject'), FamilyAction.reject, color: c.danger),
        btn('approve', t('اعتماد', 'Approve'), FamilyAction.approve, primary: true, color: c.successBase),
      ],
      if (row.published && !row.isBuiltin) btn('view', t('عرض', 'View'), FamilyAction.open),
      if (row.versionable && !row.isBuiltin) btn('edit', t('تعديل (إصدار $newVersion)', 'Edit (version $newVersion)'), FamilyAction.newVersion),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(t('الإصدار ${row.version}', 'Version ${row.version}'), style: appText(14, w: FontWeight.w800, c: c.textDark)),
            AppBadgePill(omrStatusLabel(row.status), color: omrStatusColor(context, row.status)),
            if (when != null) Text(AppTime.date(when), style: appText(12, c: c.textLight)),
          ]),
          if (row.reviewNote != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('سبب الرفض: ${row.reviewNote}', 'Rejected because: ${row.reviewNote}'), style: appText(12.5, c: c.danger, h: 1.4)),
          ],
          if (row.versionable && !row.isBuiltin) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('التعديل يُنشئ الإصدار $newVersion؛ تبقى الاختبارات على الإصدار ${row.version}.', 'Editing creates version $newVersion; exams keep version ${row.version}.'),
                style: appText(12, c: c.textMedium, h: 1.4)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: actions),
          ],
        ]),
      ),
    );
  }
}
