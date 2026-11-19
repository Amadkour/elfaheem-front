// lib/features/org/onboarding/onboarding_review.dart — the reviewer's view of one case (D-1200..D-1207).
//
//   OnbReviewView    plain values: header (status, masked ID with an unmask action), the data by group, the document
//                    checklist (view, verify, reject, waive, defer), the timeline and the bottom actions
//   OnbReviewPane    loads the case, runs the actions and the dialogs; embedded in the right pane on wide screens
//   OnbReviewPage    the pane in a pushed page (phones, deep link `/org/<o>/onboarding/<caseId>`)
//   showGeneratedPassword   the one-time password of a new account, copyable
//
// Identity documents are never opened by a public link (D-1207): the preview reads the permission-checked file route.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/share/external_link.dart' show openExternalLink;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t, asMapList, asStr;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_models.dart';
import 'onboarding_rules.dart';

AppTone onbStatusTone(String s) => switch (s) {
      'approved' || 'active' => AppTone.success,
      'needs_correction' => AppTone.warning,
      'rejected' => AppTone.danger,
      'submitted' || 'under_review' => AppTone.brand,
      _ => AppTone.neutral,
    };

AppTone onbDocTone(String s) => switch (s) {
      'verified' || 'waived' => AppTone.success,
      'rejected' => AppTone.danger,
      'deferred' => AppTone.info,
      'uploaded' => AppTone.brand,
      _ => AppTone.warning,
    };

/// A document action sent to `PATCH …/documents/{id}`.
typedef OnbDocActionFn = void Function(OnbDocRecord doc, String action);

class OnbReviewView extends StatelessWidget {
  const OnbReviewView({
    super.key,
    required this.item,
    this.unmasked,
    this.busy = false,
    this.onUnmask,
    this.onPreview,
    this.onDocAction,
    this.onClaim,
    this.onApprove,
    this.onRequestCorrection,
    this.onReject,
    this.onActivate,
    this.onEdit,
  });

  final OnbCase item;

  /// The full ID after an unmask (shown instead of the masked one).
  final String? unmasked;
  final bool busy;
  final VoidCallback? onUnmask, onClaim, onApprove, onRequestCorrection, onReject, onActivate, onEdit;
  final void Function(OnbDocRecord doc)? onPreview;
  final OnbDocActionFn? onDocAction;

  @override
  Widget build(BuildContext context) {
    final c = item;
    final type = c.type;
    final colors = context.colors;
    final values = c.values;
    final reasons = [...c.correctionFields.map((e) => e.note), ...c.correctionDocs.map((e) => e.note)].where((e) => e.isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
          children: [
            // ── header ──
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.fullName.isEmpty ? t('بدون اسم', 'No name yet') : c.fullName, style: AppType.pageTitle(context)),
                AppSpace.gapXs,
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  AppStatusBadge(key: const ValueKey('onb.review.status'), label: onbStatusLabel(c.status), tone: onbStatusTone(c.status), dense: true),
                  AppStatusBadge(label: c.typeLabel.isEmpty ? (type?.label ?? c.typeKey) : c.typeLabel, tone: AppTone.neutral, dense: true),
                  if (c.stepLabel.isNotEmpty && (c.status == 'under_review' || c.status == 'submitted'))
                    AppStatusBadge(label: c.stepLabel, tone: AppTone.info, icon: Icons.account_tree_outlined, dense: true),
                  if (c.conditional) AppStatusBadge(label: t('قبول مشروط', 'Conditional'), tone: AppTone.warning, dense: true),
                  if (c.overdue) AppStatusBadge(label: t('متأخر', 'Overdue'), tone: AppTone.danger, dense: true),
                ]),
                if (c.nidMasked.isNotEmpty) ...[
                  AppSpace.gapSm,
                  Row(children: [
                    Icon(Icons.badge_outlined, size: AppIconSize.md, color: colors.textMedium),
                    AppSpace.gapXs,
                    Flexible(
                      child: SelectableText(unmasked ?? c.nidMasked, key: const ValueKey('onb.review.nid'), textDirection: TextDirection.ltr, style: AppType.bodyStrong(context)),
                    ),
                    if (c.can.unmask && unmasked == null && onUnmask != null)
                      AppIconButton(key: const ValueKey('onb.review.unmask'), icon: Icons.visibility_outlined, tooltip: t('إظهار الرقم', 'Show the number'), onPressed: onUnmask),
                  ]),
                ],
                if (c.email.isNotEmpty || c.phone.isNotEmpty) ...[
                  AppSpace.gapXs,
                  Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
                    if (c.email.isNotEmpty) Text(c.email, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                    if (c.phone.isNotEmpty) Text(c.phone, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                  ]),
                ],
                if (c.dueAt != null) ...[
                  AppSpace.gapXs,
                  Text(t('استكمال المستندات حتى ${AppTime.date(c.dueAt!)}', 'Documents due by ${AppTime.date(c.dueAt!)}'), style: AppType.meta(context)),
                ],
              ]),
            ),
            if (c.status == 'needs_correction' && (c.decisionReason.isNotEmpty || reasons.isNotEmpty)) ...[
              AppSpace.gapSm,
              AppBanner(icon: Icons.edit_note_rounded, color: colors.warning, text: [c.decisionReason, ...reasons].where((e) => e.isNotEmpty).join('\n')),
            ],
            if (c.status == 'rejected' && c.decisionReason.isNotEmpty) ...[
              AppSpace.gapSm,
              AppBanner(icon: Icons.block_rounded, color: colors.danger, text: c.decisionReason),
            ],
            // ── data ──
            if (type != null)
              for (final g in onbGroups) ..._dataSection(context, type, g, values),
            // ── documents ──
            if (type != null && type.documents.any((d) => docVisible(d, values))) ...[
              AppSpace.gapSm,
              AppSectionTitle(t('المستندات', 'Documents')),
              for (final d in type.documents.where((d) => docVisible(d, values)))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: _DocRow(
                    key: ValueKey('onb.review.doc.${d.key}'),
                    req: d,
                    record: c.docFor(d.key),
                    required: onbIsRequired(d.required, d.when, values) || d.required == 'mandatory',
                    canView: c.can.viewDocuments,
                    canDecide: c.can.edit || c.can.approve || c.can.reject,
                    onPreview: onPreview,
                    onAction: onDocAction,
                  ),
                ),
            ],
            // ── timeline ──
            if (c.events.isNotEmpty) ...[
              AppSpace.gapSm,
              AppSectionTitle(t('السجل', 'Timeline')),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final e in c.events) _EventRow(event: e),
                ]),
              ),
            ],
          ],
        ),
      ),
      _ActionBar(item: c, busy: busy, onClaim: onClaim, onApprove: onApprove, onRequestCorrection: onRequestCorrection, onReject: onReject, onActivate: onActivate, onEdit: onEdit),
    ]);
  }

  List<Widget> _dataSection(BuildContext context, OnbType type, String group, Map<String, dynamic> values) {
    final fields = [
      for (final f in type.fields)
        if (f.group == group && fieldVisible(f, values) && f.key != 'full_name' && hasValue(values[f.key]) && f.kind != 'national_id' && f.key != 'passport_no') f,
    ];
    if (fields.isEmpty) return const [];
    return [
      AppSpace.gapSm,
      AppSectionTitle(onbGroupLabel(group)),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.label.isEmpty ? f.key : f.label, style: AppType.meta(context)),
                Text(_show(f, values[f.key]), style: AppType.row(context)),
              ]),
            ),
        ]),
      ),
    ];
  }

  String _show(OnbField f, Object? v) {
    if (v is bool) return v ? t('نعم', 'Yes') : t('لا', 'No');
    if (f.kind == 'date') {
      final d = parseIsoDay(v);
      return d == null ? '$v' : AppTime.date(DateTime.utc(d.year, d.month, d.day, 12));
    }
    if (f.key == 'gender') return v == 'm' ? t('ذكر', 'Male') : (v == 'f' ? t('أنثى', 'Female') : '$v');
    if (f.options.isNotEmpty) {
      final o = {for (final x in f.options) x.value: x.label};
      if (v is List) return v.map((e) => o['$e'] ?? '$e').join('، ');
      return o['$v'] ?? '$v';
    }
    return '$v';
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({super.key, required this.req, this.record, this.required = false, this.canView = false, this.canDecide = false, this.onPreview, this.onAction});
  final OnbDocReq req;
  final OnbDocRecord? record;
  final bool required, canView, canDecide;
  final void Function(OnbDocRecord)? onPreview;
  final OnbDocActionFn? onAction;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final status = r?.status ?? 'missing';
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(req.label.isEmpty ? req.key : req.label, style: AppType.bodyStrong(context))),
          AppStatusBadge(key: ValueKey('onb.review.doc.status.${req.key}'), label: onbDocStatusLabel(status), tone: onbDocTone(status), dense: true),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          Text(onbRequiredLabel(required ? 'mandatory' : 'optional'), style: AppType.meta(context)),
          if (req.originalNeeded) Text(t('· الأصل مطلوب', '· original needed'), style: AppType.meta(context)),
          if (r != null && r.fileName.isNotEmpty) Text('· ${r.fileName}${r.size > 0 ? ' · ${fileSizeLabel(r.size)}' : ''}', style: AppType.meta(context)),
          if (r?.dueAt case final due?) Text(t('· حتى ${AppTime.date(due)}', '· due ${AppTime.date(due)}'), style: AppType.meta(context)),
        ]),
        if (r != null && r.note.isNotEmpty) Text(r.note, style: AppType.meta(context)),
        if (r != null && (canView || canDecide)) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (canView && onPreview != null)
              AppButton.tonal(key: ValueKey('onb.review.doc.view.${req.key}'), label: t('عرض', 'View'), icon: Icons.visibility_outlined, size: AppButtonSize.sm, onPressed: () => onPreview!(r)),
            if (canDecide && onAction != null) ...[
              if (r.status != 'verified')
                AppButton.secondary(key: ValueKey('onb.review.doc.verify.${req.key}'), label: t('تحقق', 'Verify'), icon: Icons.check_rounded, size: AppButtonSize.sm, onPressed: () => onAction!(r, 'verify')),
              if (r.status != 'rejected')
                AppButton.ghost(key: ValueKey('onb.review.doc.reject.${req.key}'), label: t('رفض', 'Reject'), size: AppButtonSize.sm, onPressed: () => onAction!(r, 'reject')),
              if (r.status != 'waived') AppButton.ghost(label: t('إعفاء', 'Waive'), size: AppButtonSize.sm, onPressed: () => onAction!(r, 'waive')),
              if (req.allowLater && r.status != 'deferred') AppButton.ghost(label: t('تأجيل', 'Defer'), size: AppButtonSize.sm, onPressed: () => onAction!(r, 'defer')),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final OnbEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Icon(Icons.circle, size: AppSpace.xs, color: c.primary)),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.text, style: AppType.row(context)),
            if (event.reason.isNotEmpty) Text(event.reason, style: AppType.meta(context)),
            Text([if (event.actorName.isNotEmpty) event.actorName, if (event.createdAt != null) AppTime.dateTime(event.createdAt!)].join(' · '), style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.item, required this.busy, this.onClaim, this.onApprove, this.onRequestCorrection, this.onReject, this.onActivate, this.onEdit});
  final OnbCase item;
  final bool busy;
  final VoidCallback? onClaim, onApprove, onRequestCorrection, onReject, onActivate, onEdit;

  @override
  Widget build(BuildContext context) {
    final can = item.can;
    final children = <Widget>[
      if (can.edit && onEdit != null && (item.status == 'draft' || item.status == 'needs_correction'))
        AppButton.secondary(key: const ValueKey('onb.action.edit'), label: t('تعديل', 'Edit'), icon: Icons.edit_outlined, onPressed: busy ? null : onEdit),
      if (can.claim && onClaim != null && item.status == 'submitted')
        AppButton.secondary(key: const ValueKey('onb.action.claim'), label: t('بدء المراجعة', 'Start review'), onPressed: busy ? null : onClaim),
      if (can.reject && onReject != null) AppButton.danger(key: const ValueKey('onb.action.reject'), label: t('رفض', 'Reject'), onPressed: busy ? null : onReject),
      if (can.requestCorrection && onRequestCorrection != null)
        AppButton.secondary(key: const ValueKey('onb.action.correct'), label: t('طلب تصحيح', 'Request correction'), onPressed: busy ? null : onRequestCorrection),
      if (can.activate && onActivate != null) AppButton.tonal(key: const ValueKey('onb.action.activate'), label: t('تفعيل العضوية', 'Activate'), onPressed: busy ? null : onActivate),
      if (can.approve && onApprove != null) AppButton.primary(key: const ValueKey('onb.action.approve'), label: t('قبول', 'Approve'), busy: busy, onPressed: busy ? null : onApprove),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: children),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The pane: load + actions + dialogs
// ═════════════════════════════════════════════════════════════════════════════

class OnbReviewPane extends StatefulWidget {
  const OnbReviewPane({super.key, required this.orgId, required this.caseId, this.api, this.onChanged, this.onEdit, this.initial});
  final int orgId, caseId;
  final OnboardingApi? api;

  /// Called after any action that changed the case, so the list reloads.
  final void Function(OnbCase updated)? onChanged;

  /// Opens the wizard on this case (a draft or one that needs correction).
  final void Function(OnbCase c)? onEdit;
  final OnbCase? initial;

  @override
  State<OnbReviewPane> createState() => _OnbReviewPaneState();
}

class _OnbReviewPaneState extends State<OnbReviewPane> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  OnbCase? _case;
  bool _loading = true, _busy = false;
  ApiException? _error;
  String? _unmasked;
  List<OnbRejectReason>? _reasons;

  @override
  void initState() {
    super.initState();
    _case = widget.initial;
    _load();
  }

  @override
  void didUpdateWidget(OnbReviewPane old) {
    super.didUpdateWidget(old);
    if (old.caseId != widget.caseId) {
      _case = null;
      _unmasked = null;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _case == null;
      _error = null;
    });
    final id = widget.caseId;
    final r = await _api.getCase(widget.orgId, id);
    if (!mounted || id != widget.caseId) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _case = OnbCase.fromJson(r.map);
      } else {
        _error = r.error;
      }
    });
  }

  void _apply(OnbCase c) {
    setState(() => _case = c);
    widget.onChanged?.call(c);
  }

  /// Runs a case action; shows the error, or the new case (and a generated password once).
  Future<void> _run(Future<dynamic> Function() call, {String? done}) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final c = OnbCase.fromJson(r.map);
    // an action's answer may be lighter than the detail: keep what we had when it has no detail
    final merged = c.detailed ? c : null;
    if (merged != null) {
      _apply(merged);
    } else {
      await _load();
      if (_case != null) widget.onChanged?.call(_case!);
    }
    if (done != null) showAppNotice(done);
    if (c.generatedPassword != null && mounted) await showGeneratedPassword(context, c.generatedPassword!, name: c.fullName);
  }

  Future<void> _approve() async {
    final c = _case!;
    final note = await _askNote(context, title: t('قبول الطلب', 'Approve the case'), hint: t('ملاحظة (اختياري)', 'Note (optional)'), confirm: t('قبول', 'Approve'), required: false);
    if (note == null) return;
    await _run(() => _api.approve(widget.orgId, c.id, note: note), done: t('تم القبول', 'Approved'));
  }

  Future<void> _correct() async {
    final c = _case!;
    final r = await showOnbCorrectionSheet(context, c);
    if (r == null) return;
    await _run(() => _api.requestCorrection(widget.orgId, c.id, reason: r.reason, fields: r.fields, documents: r.documents), done: t('أُرسل طلب التصحيح', 'Correction requested'));
  }

  Future<void> _reject() async {
    final c = _case!;
    _reasons ??= await _loadReasons();
    if (!mounted) return;
    final r = await showOnbRejectSheet(context, _reasons ?? const []);
    if (r == null) return;
    await _run(() => _api.reject(widget.orgId, c.id, reason: r.reason, reasonKey: r.key), done: t('رُفض الطلب', 'Case rejected'));
  }

  Future<List<OnbRejectReason>> _loadReasons() async {
    final r = await _api.rejectReasons(widget.orgId);
    if (!r.ok) return const [];
    final raw = r.data is List ? r.data as List : r.map['items'];
    return asMapList(raw).map(OnbRejectReason.fromJson).toList();
  }

  Future<void> _docAction(OnbDocRecord d, String action) async {
    String note = '';
    if (action == 'reject' || action == 'defer') {
      final n = await _askNote(context,
          title: action == 'reject' ? t('رفض المستند', 'Reject the document') : t('تأجيل المستند', 'Defer the document'),
          hint: t('السبب أو الملاحظة', 'Reason or note'),
          confirm: action == 'reject' ? t('رفض', 'Reject') : t('تأجيل', 'Defer'),
          required: action == 'reject');
      if (n == null) return;
      note = n;
    }
    setState(() => _busy = true);
    final r = await _api.documentAction(widget.orgId, d.id, action: action, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    await _load();
    if (_case != null) widget.onChanged?.call(_case!);
  }

  Future<void> _unmask() async {
    final r = await _api.unmask(widget.orgId, widget.caseId);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    setState(() => _unmasked = asStr(r.map['value']));
  }

  Future<void> _preview(OnbDocRecord d) async {
    if (d.isImage) {
      final bytes = await _api.documentBytes(widget.orgId, d.id);
      if (!mounted) return;
      if (bytes != null) {
        await showDialog<void>(
          context: context,
          barrierColor: appScrimColor(context),
          builder: (_) => _ImageDialog(bytes: bytes, title: d.fileName),
        );
        return;
      }
    }
    final url = await _api.documentLink(widget.orgId, d.id);
    if (!mounted) return;
    if (url == null) {
      showAppNotice(t('تعذر فتح المستند', 'Could not open the document'), error: true);
      return;
    }
    await openExternalLink(url, failText: t('تعذر فتح المستند', 'Could not open the document'), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    return AppStateView<OnbCase>(
      loading: _loading,
      error: _error,
      data: _case,
      onRetry: _load,
      builder: (context, c) => OnbReviewView(
        item: c,
        unmasked: _unmasked,
        busy: _busy,
        onUnmask: _unmask,
        onPreview: _preview,
        onDocAction: _docAction,
        onClaim: () => _run(() => _api.claim(widget.orgId, c.id)),
        onApprove: _approve,
        onRequestCorrection: _correct,
        onReject: _reject,
        onActivate: () => _run(() => _api.activate(widget.orgId, c.id), done: t('فُعِّلت العضوية', 'Membership activated')),
        onEdit: widget.onEdit == null ? null : () => widget.onEdit!(c),
      ),
    );
  }
}

class OnbReviewPage extends StatelessWidget {
  const OnbReviewPage({super.key, required this.orgId, required this.caseId, this.api, this.onChanged, this.onEdit, this.title = ''});
  final int orgId, caseId;
  final OnboardingApi? api;
  final void Function(OnbCase)? onChanged;
  final void Function(OnbCase)? onEdit;
  final String title;

  @override
  Widget build(BuildContext context) {
    return OrgPushedPage(
      title: title.isEmpty ? t('طلب التحاق', 'Admission case') : title,
      subtitle: t('الالتحاق والتعيين', 'Admissions & appointments'),
      helpPageId: 'org.onboarding',
      width: AppWidth.reading,
      child: OnbReviewPane(orgId: orgId, caseId: caseId, api: api, onChanged: onChanged, onEdit: onEdit),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Dialogs
// ═════════════════════════════════════════════════════════════════════════════

/// One note field. null = cancelled; '' = confirmed with nothing typed (only when not [required]).
Future<String?> _askNote(BuildContext context, {required String title, required String hint, required String confirm, bool required = false}) {
  final ctrl = TextEditingController();
  return showAppSheet<String>(context, (ctx) {
    String? err;
    return StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(title: title, children: [
        AppField(controller: ctrl, label: hint, maxLines: 3, errorText: err, required: required),
        AppSpace.gapXs,
        AppButton.primary(
          label: confirm,
          expand: true,
          onPressed: () {
            if (required && ctrl.text.trim().isEmpty) {
              set(() => err = t('هذا الحقل مطلوب', 'This field is required'));
              return;
            }
            Navigator.of(ctx).pop(ctrl.text.trim());
          },
        ),
      ]),
    );
  }).whenComplete(ctrl.dispose);
}

/// What the correction dialog returns.
class OnbCorrectionRequest {
  const OnbCorrectionRequest(this.reason, this.fields, this.documents);
  final String reason;
  final List<Map<String, String>> fields, documents;
}

/// "Request correction": a general reason plus per-field and per-document notes.
Future<OnbCorrectionRequest?> showOnbCorrectionSheet(BuildContext context, OnbCase c) {
  final type = c.type;
  final reason = TextEditingController();
  final notes = <String, TextEditingController>{};
  final picked = <String>{};
  TextEditingController note(String k) => notes.putIfAbsent(k, () => TextEditingController());
  final fields = type == null ? const <OnbField>[] : [for (final f in type.fields) if (fieldVisible(f, c.values) && f.key != 'national_id') f];
  final docs = type == null ? const <OnbDocReq>[] : [for (final d in type.documents) if (docVisible(d, c.values)) d];
  return showAppSheet<OnbCorrectionRequest>(context, (ctx) {
    String? err;
    return StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(title: t('طلب تصحيح', 'Request correction'), children: [
        AppField(key: const ValueKey('onb.correct.reason'), controller: reason, label: t('ما المطلوب تصحيحه؟', 'What needs to be corrected?'), maxLines: 3, errorText: err, required: true),
        if (fields.isNotEmpty) ...[
          AppSectionTitle(t('حقول بعينها', 'Specific fields')),
          for (final f in fields)
            _CorrectionRow(
              label: f.label.isEmpty ? f.key : f.label,
              checked: picked.contains('f:${f.key}'),
              controller: note('f:${f.key}'),
              onChanged: (v) => set(() => v ? picked.add('f:${f.key}') : picked.remove('f:${f.key}')),
            ),
        ],
        if (docs.isNotEmpty) ...[
          AppSectionTitle(t('مستندات بعينها', 'Specific documents')),
          for (final d in docs)
            _CorrectionRow(
              label: d.label.isEmpty ? d.key : d.label,
              checked: picked.contains('d:${d.key}'),
              controller: note('d:${d.key}'),
              onChanged: (v) => set(() => v ? picked.add('d:${d.key}') : picked.remove('d:${d.key}')),
            ),
        ],
        AppSpace.gapSm,
        AppButton.primary(
          key: const ValueKey('onb.correct.send'),
          label: t('إرسال', 'Send'),
          expand: true,
          onPressed: () {
            if (reason.text.trim().isEmpty && picked.isEmpty) {
              set(() => err = t('اكتب السبب أو اختر عنصراً', 'Write a reason or pick an item'));
              return;
            }
            Navigator.of(ctx).pop(OnbCorrectionRequest(
              reason.text.trim(),
              [for (final k in picked) if (k.startsWith('f:')) {'key': k.substring(2), 'note': notes[k]?.text.trim() ?? ''}],
              [for (final k in picked) if (k.startsWith('d:')) {'key': k.substring(2), 'note': notes[k]?.text.trim() ?? ''}],
            ));
          },
        ),
      ]),
    );
  }).whenComplete(() {
    reason.dispose();
    for (final c in notes.values) {
      c.dispose();
    }
  });
}

class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({required this.label, required this.checked, required this.controller, required this.onChanged});
  final String label;
  final bool checked;
  final TextEditingController controller;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSwitchTile(title: label, value: checked, dense: true, onChanged: onChanged),
      if (checked) AppField(controller: controller, label: t('ملاحظة', 'Note'), maxLines: 2),
    ]);
  }
}

/// What the reject dialog returns.
class OnbRejectRequest {
  const OnbRejectRequest(this.key, this.reason);
  final String key, reason;
}

/// "Reject": a reason picked from the server's list and/or free text; one of the two is required.
Future<OnbRejectRequest?> showOnbRejectSheet(BuildContext context, List<OnbRejectReason> reasons) {
  final text = TextEditingController();
  String? key;
  return showAppSheet<OnbRejectRequest>(context, (ctx) {
    String? err;
    return StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(title: t('رفض الطلب', 'Reject the case'), children: [
        if (reasons.isNotEmpty) ...[
          AppFieldLabel(t('سبب جاهز', 'A ready reason')),
          AppDropdown<String>(
            key: const ValueKey('onb.reject.reason'),
            value: key,
            hint: Text(t('اختر سبباً', 'Pick a reason')),
            items: [for (final r in reasons) DropdownMenuItem(value: r.key, child: Text(r.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() {
              key = v;
              if (v != null && text.text.trim().isEmpty) text.text = reasons.firstWhere((r) => r.key == v).label;
            }),
          ),
          AppSpace.gapSm,
        ],
        AppField(key: const ValueKey('onb.reject.text'), controller: text, label: t('السبب', 'Reason'), maxLines: 3, errorText: err, required: true),
        AppSpace.gapXs,
        AppButton.danger(
          key: const ValueKey('onb.reject.send'),
          label: t('رفض', 'Reject'),
          expand: true,
          onPressed: () {
            if (text.text.trim().isEmpty) {
              set(() => err = t('اكتب سبب الرفض', 'Write the reason'));
              return;
            }
            Navigator.of(ctx).pop(OnbRejectRequest(key ?? '', text.text.trim()));
          },
        ),
      ]),
    );
  }).whenComplete(text.dispose);
}

/// The password of a new account, shown once and copyable. The server never returns it again.
Future<void> showGeneratedPassword(BuildContext context, String password, {String name = ''}) {
  return showAppSheet<void>(
    context,
    (ctx) => AppSheetContent(title: t('كلمة المرور المؤقتة', 'Temporary password'), children: [
      AppBanner(
        icon: Icons.lock_clock_outlined,
        color: ctx.colors.warning,
        text: t('تظهر كلمة المرور هذه مرة واحدة فقط. سلّمها لـ ${name.isEmpty ? 'العضو' : name} الآن.', 'This password is shown only once. Hand it to ${name.isEmpty ? 'the member' : name} now.'),
      ),
      AppSpace.gapSm,
      AppCard(child: SelectableText(password, key: const ValueKey('onb.password'), textDirection: TextDirection.ltr, style: AppType.section(ctx))),
      AppSpace.gapSm,
      AppButton.primary(
        key: const ValueKey('onb.password.copy'),
        label: t('نسخ', 'Copy'),
        icon: Icons.copy_rounded,
        expand: true,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: password));
          showAppNotice(t('نُسخت كلمة المرور', 'Password copied'));
        },
      ),
    ]),
  );
}

class _ImageDialog extends StatelessWidget {
  const _ImageDialog({required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
            AppIconButton(icon: Icons.close_rounded, tooltip: t('إغلاق', 'Close'), onPressed: () => Navigator.of(context).pop()),
          ]),
        ),
        Flexible(child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain))),
      ]),
    );
  }
}
