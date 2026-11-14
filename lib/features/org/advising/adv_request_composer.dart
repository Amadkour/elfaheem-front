// lib/features/org/advising/adv_request_composer.dart — writing a support request or a referral for a student
// (docs/advising/PHASE7.md "Requests and referrals"): Support request | Referral, the type (its default category
// comes with it), the accommodations and until when for a type that needs them, the priority, a template to start
// from, the title and the details (each in its own direction), attachments through the governance upload, and where
// the request will go (the student's chain, a skipped step explained). Save as draft (only the author sees it) or
// Submit. While the advisor types, the request is kept on the device (#23) and comes back when the composer opens
// again; its `client_id` makes the POST idempotent, so a retry after a lost answer never files it twice.
//
//   AdvRequestForm            the sheet's content (plain values)     AdvChainPreviewList   where it will go
//   AdvRequestDraftStore      the device copy per (user, organization, student)
//   showAdvRequestComposer    the sheet: loads the options and the preview, saves / submits through AdvSupportApi
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../governance/gov_models.dart' show GovAttachment;
import '../governance/gov_request_parts.dart' show GovAttachmentChips, openGovAttachment, uploadGovAttachment;
import '../org_page_kit.dart' show OrgSegmented;
import '../org_v3.dart' show orgCall;
import 'adv_case_parts.dart' show AdvTypedField;
import 'adv_draft_store.dart' show AdvDeviceDraftBackend, AdvDraftBackend, AdvDraftStore;
import 'adv_models.dart' show AdvAccommodation, advPriorities, advPriorityLabel;
import 'adv_parts.dart' show AdvFieldLabel, AdvPersonField, advDate;
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart';
import 'adv_support_texts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  The device copy
// ═════════════════════════════════════════════════════════════════════════════

/// The request being written, kept on the device per (signed-in user, organization, student) — the keystore on
/// phones and desktops (a request can be sensitive), SharedPreferences on the web (the notes' backend).
class AdvRequestDraftStore {
  AdvRequestDraftStore({AdvDraftBackend? backend, Future<int> Function()? userId})
      : _backend = backend ?? const AdvDeviceDraftBackend(),
        _userId = userId ?? _savedUserId;

  static final AdvRequestDraftStore instance = AdvRequestDraftStore();

  static const kDrafts = 'adv_request_drafts_v1';

  final AdvDraftBackend _backend;
  final Future<int> Function() _userId;

  static Future<int> _savedUserId() async => asInt((await StorageService.getInstance()).savedUser?['id']);

  Future<Map<String, dynamic>> _all() async {
    final raw = await _backend.read(kDrafts);
    if (raw == null || raw.isEmpty) return {};
    try {
      return asMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<String> _key(int orgId, int memberId) async => '${await _userId()}:$orgId:$memberId';

  Future<AdvRequestDraft?> read(int orgId, int memberId) async {
    final j = (await _all())[await _key(orgId, memberId)];
    return j is Map ? AdvRequestDraft.fromStore(asMap(j)) : null;
  }

  /// Keeps [d] (an empty one removes the copy).
  Future<void> save(int orgId, int memberId, AdvRequestDraft d) async {
    final k = await _key(orgId, memberId);
    final all = await _all();
    if (d.worthKeeping) {
      all[k] = d.toStore();
    } else {
      all.remove(k);
    }
    await _backend.write(kDrafts, all.isEmpty ? null : jsonEncode(all));
  }

  Future<void> clear(int orgId, int memberId) => save(orgId, memberId, const AdvRequestDraft());
}

// ═════════════════════════════════════════════════════════════════════════════
//  Where it will go
// ═════════════════════════════════════════════════════════════════════════════

class AdvChainPreviewList extends StatelessWidget {
  const AdvChainPreviewList({super.key, required this.steps, this.advisingDept});
  final List<AdvChainPreviewStep> steps;
  final String? advisingDept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = [for (final s in steps) s];
    var n = 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final s in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: MergeSemantics(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: s.resolved ? c.primary.withValues(alpha: 0.12) : c.inputBg,
                    border: Border.all(color: s.resolved ? c.primary.withValues(alpha: 0.4) : c.divider),
                  ),
                  child: s.resolved
                      ? Text('${++n}', style: AppType.meta(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w700))
                      : Icon(Icons.redo_rounded, size: AppIconSize.xs, color: c.textMedium),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.step.label,
                      style: AppType.row(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: s.resolved ? c.textDark : c.textMedium,
                        decoration: s.resolved ? null : TextDecoration.lineThrough,
                        decorationColor: c.textLight,
                      )),
                  if (!s.resolved)
                    Text(advSkipReasonText(s.reason ?? 'skipped'), style: AppType.meta(context))
                  else if (s.step.kind == 'director_review' && advisingDept != null)
                    Text(t('في $advisingDept', 'At $advisingDept'), style: AppType.meta(context)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The form
// ═════════════════════════════════════════════════════════════════════════════

class AdvRequestForm extends StatelessWidget {
  const AdvRequestForm({
    super.key,
    required this.options,
    required this.draft,
    required this.title,
    required this.body,
    this.studentName,
    this.editing = false,
    this.preview,
    this.previewLoading = false,
    this.restored = false,
    this.savedOnDevice = false,
    this.uploading = false,
    this.busy = false,
    this.error,
    this.onKind,
    this.onType,
    this.onTarget,
    this.onCategory,
    this.onPriority,
    this.onAccommodation,
    this.onPickUntil,
    this.onClearUntil,
    this.onTemplate,
    this.onAttach,
    this.onOpenAttachment,
    this.onRemoveAttachment,
    this.onSaveDraft,
    this.onSubmit,
  });

  final AdvRequestOptions options;
  final AdvRequestDraft draft;
  final TextEditingController title, body;
  final String? studentName;

  /// A saved draft opened again: the kind stays.
  final bool editing;
  final AdvChainPreview? preview;
  final bool previewLoading;

  /// The text came back from the device.
  final bool restored;

  /// The latest text is kept on the device.
  final bool savedOnDevice;
  final bool uploading, busy;
  final String? error;
  final ValueChanged<String>? onKind;
  final ValueChanged<AdvSupportType>? onType;
  final ValueChanged<int>? onTarget;
  final ValueChanged<int?>? onCategory;
  final ValueChanged<String>? onPriority, onAccommodation;
  final VoidCallback? onPickUntil, onClearUntil, onAttach, onSaveDraft, onSubmit;
  final ValueChanged<AdvRequestTemplate>? onTemplate;
  final ValueChanged<GovAttachment>? onOpenAttachment, onRemoveAttachment;

  /// The accommodations offered for [draft]: the chosen category's, else the accessibility category's.
  static List<AdvAccommodation> accommodationsFor(AdvRequestOptions o, AdvRequestDraft d) {
    final cat = o.category(d.categoryId);
    if (cat != null && cat.accommodations.isNotEmpty) return cat.accommodations;
    return o.categories.where((c) => c.key == 'accessibility').firstOrNull?.accommodations ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final type = options.type(d.supportType);
    final cat = options.category(d.categoryId);
    final target = options.target(d.targetDeptId);
    final accs = accommodationsFor(options, d);
    final off = busy;
    final err = error;
    final children = <Widget>[
      if (studentName != null) ...[
        Row(children: [
          ExcludeSemantics(child: Icon(Icons.school_outlined, size: AppIconSize.md, color: c.textMedium)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('للطالب: $studentName', 'For: $studentName'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
        ]),
        const SizedBox(height: AppSpace.sm),
      ],
      if (!editing) ...[
        OrgSegmented<String>(
          value: d.kind,
          options: [for (final k in advRequestKinds) (k, advRequestKindLabel(k))],
          onChanged: (k) => off || onKind == null ? null : onKind!(k),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (restored) ...[
        AppBanner(icon: Icons.restore_rounded, text: t('أُعيد ما كتبته على هذا الجهاز.', 'What you wrote on this device is back.')),
        const SizedBox(height: AppSpace.sm),
      ],
    ];

    if (d.referral) {
      children.add(AdvFieldLabel(t('الجهة المحال إليها', 'Refer to'), hint: t('يقرر فريقها، وتعود النتيجة إليك', 'Its team decides; the outcome comes back to you')));
      if (options.referralTargets.isEmpty) {
        children.add(AppBanner(
          icon: Icons.info_outline_rounded,
          color: c.warning,
          text: t('لا توجد إدارة خدمية نشطة تستقبل الإحالات — يضيفها مدير المؤسسة من الحوكمة ← الجهات.',
              'No active service department takes referrals yet — the organization admin adds them under Governance → Entities.'),
        ));
      } else {
        children.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final e in options.referralTargets)
            AppChoiceChip(
              label: e.name,
              icon: e.suggested ? _presetIcon(e.preset) : null,
              selected: e.id == d.targetDeptId,
              onTap: off || onTarget == null ? () {} : () => onTarget!(e.id),
            ),
        ]));
      }
    } else {
      children.add(AdvFieldLabel(t('نوع الطلب', 'Type of request')));
      children.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final x in options.supportTypes)
          AppChoiceChip(label: x.label, selected: x.key == d.supportType, onTap: off || onType == null ? () {} : () => onType!(x)),
      ]));
      children.add(const SizedBox(height: AppSpace.md));
      children.add(AppDropdown<int>(
        value: d.categoryId ?? 0,
        decoration: InputDecoration(labelText: t('التصنيف', 'Category')),
        items: [
          DropdownMenuItem(value: 0, child: Text(t('بلا تصنيف', 'No category'))),
          for (final x in options.categories)
            if (x.active || x.id == d.categoryId)
              DropdownMenuItem(value: x.id, child: Text(x.sensitive ? '${x.name} · ${t('حساس', 'sensitive')}' : x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: off || onCategory == null ? null : (v) => onCategory!(v == null || v == 0 ? null : v),
      ));
      if (cat != null && cat.sensitive) {
        children.add(const SizedBox(height: AppSpace.xs));
        children.add(AppBanner(
          icon: Icons.lock_outline_rounded,
          text: t('تصنيف حساس: لا يقرأ الطلب من فريق الإرشاد إلا أنت والمرشد الأساسي ومديرو الإرشاد، وكل قراءة مسجّلة.',
              'A sensitive category: in the advising team only you, the primary advisor and the advising directors read the request, and every read is recorded.'),
        ));
      }
      if (type != null && type.needsAccommodations) {
        children.add(const SizedBox(height: AppSpace.md));
        children.add(AdvFieldLabel(t('التسهيلات المطلوبة', 'Accommodations requested'), hint: t('تُمنح للطالب تلقائياً عند الموافقة', 'Granted to the student by themselves on approval')));
        if (accs.isEmpty) {
          children.add(Text(t('لا تسهيلات معرّفة في هذا التصنيف — يضيفها مدير الإرشاد من التصنيفات.', 'This category defines no accommodations — the advising director adds them under Categories.'),
              style: AppType.body(context)));
        } else {
          children.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final a in accs)
              AppChoiceChip(
                label: a.label,
                icon: d.accommodations.contains(a.key) ? Icons.check_rounded : Icons.add_rounded,
                selected: d.accommodations.contains(a.key),
                onTap: off || onAccommodation == null ? () {} : () => onAccommodation!(a.key),
              ),
          ]));
        }
        children.add(const SizedBox(height: AppSpace.sm));
        children.add(AdvPersonField(
          label: t('حتى تاريخ', 'Until'),
          name: d.accommodationUntil == null ? null : advDate(d.accommodationUntil, dateOnly: true),
          placeholder: t('بلا تاريخ نهاية', 'No end date'),
          icon: Icons.event_rounded,
          avatar: false,
          onPick: off ? null : onPickUntil,
          onClear: off ? null : onClearUntil,
        ));
      }
    }

    children.add(const SizedBox(height: AppSpace.md));
    children.add(AdvFieldLabel(t('الأولوية', 'Priority')));
    children.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (final p in options.priorities.isEmpty ? advPriorities : options.priorities)
        AppChoiceChip(
          label: advPriorityLabel(p),
          icon: p == 'urgent' ? Icons.priority_high_rounded : null,
          selected: p == d.priority,
          onTap: off || onPriority == null ? () {} : () => onPriority!(p),
        ),
    ]));

    if (options.templates.isNotEmpty && onTemplate != null) {
      children.add(const SizedBox(height: AppSpace.md));
      children.add(AdvFieldLabel(t('ابدأ من نموذج', 'Start from a template'), hint: t('يملأ النص، وتكمل أنت التفاصيل', 'It fills the text; you complete the details')));
      children.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final tp in options.templates)
          AppChoiceChip(label: tp.name, icon: Icons.description_outlined, selected: tp.id == d.templateId, onTap: off ? () {} : () => onTemplate!(tp)),
      ]));
    }

    children.add(const SizedBox(height: AppSpace.md));
    children.add(AdvTypedField(controller: title, label: t('العنوان', 'Title'), minLines: 1, maxLines: 2, maxLength: advRequestTitleMax, enabled: !off));
    children.add(const SizedBox(height: AppSpace.sm));
    children.add(AdvTypedField(
      controller: body,
      label: t('التفاصيل', 'Details'),
      hint: d.referral ? t('ما الذي يحتاجه الطالب من الجهة، وما الذي جُرّب', 'What the student needs from them, and what was tried') : t('الوقائع، وما يطلبه الطالب، والمستندات المرفقة', 'The facts, what the student asks for, the documents attached'),
      minLines: 5,
      maxLines: 12,
      maxLength: advRequestBodyMax,
      enabled: !off,
    ));

    children.add(const SizedBox(height: AppSpace.sm));
    if (d.attachments.isNotEmpty) {
      children.add(GovAttachmentChips(attachments: d.attachments, onOpen: onOpenAttachment, onRemove: off ? null : onRemoveAttachment));
      children.add(const SizedBox(height: AppSpace.xxs));
    }
    children.add(Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xs, children: [
      TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
        onPressed: off || uploading || onAttach == null || d.attachments.length >= advRequestMaxAttachments ? null : onAttach,
        icon: uploading ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.attach_file_rounded, size: AppIconSize.md),
        label: Text(uploading ? t('جارٍ الرفع…', 'Uploading…') : t('إرفاق ملف', 'Attach a file')),
      ),
      Text(t('حتى 10 ملفات: PDF، صور، Word، Excel', 'Up to 10 files: PDF, images, Word, Excel'), style: AppType.meta(context)),
    ]));

    children.add(const SizedBox(height: AppSpace.md));
    if (d.referral) {
      children.add(AppBanner(
        icon: Icons.alt_route_rounded,
        text: target == null
            ? t('تذهب الإحالة مباشرة إلى الجهة التي تختارها، ويصلك قرارها.', 'The referral goes straight to the department you choose, and its outcome comes back to you.')
            : t('تذهب الإحالة مباشرة إلى ${target.name}، ويصلك قرارها.', 'The referral goes straight to ${target.name}, and its outcome comes back to you.'),
      ));
    } else {
      children.add(AdvBlockCard(
        icon: Icons.account_tree_rounded,
        title: t('مسار الاعتماد لهذا الطالب', 'Where it will go for this student'),
        child: previewLoading
            ? const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
            : preview == null || preview!.steps.isEmpty
                ? Text(t('يحدد المسار مدير الإرشاد في الإعدادات.', 'The advising director sets the chain in the settings.'), style: AppType.body(context))
                : AdvChainPreviewList(steps: preview!.steps, advisingDept: preview!.advisingDept?.name),
      ));
    }

    if (savedOnDevice) {
      children.add(const SizedBox(height: AppSpace.sm));
      children.add(Row(children: [
        ExcludeSemantics(child: Icon(Icons.save_outlined, size: AppIconSize.sm, color: c.textMedium)),
        const SizedBox(width: AppSpace.xxs),
        Expanded(child: Text(t('محفوظ على هذا الجهاز', 'Saved on this device'), style: AppType.meta(context))),
      ]));
    }
    if (err != null) {
      children.add(const SizedBox(height: AppSpace.sm));
      children.add(AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err));
    }
    children.add(const SizedBox(height: AppSpace.md));
    children.add(AppPrimaryButton(
      icon: d.referral ? Icons.alt_route_rounded : Icons.send_rounded,
      label: d.referral ? t('إرسال الإحالة', 'Send the referral') : t('إرسال الطلب', 'Submit the request'),
      busy: busy,
      onPressed: onSubmit,
    ));
    if (onSaveDraft != null) {
      children.add(const SizedBox(height: AppSpace.xs));
      children.add(Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: off ? null : onSaveDraft,
          icon: const Icon(Icons.edit_note_rounded, size: AppIconSize.md),
          label: Text(t('حفظ كمسودة (تراها أنت فقط)', 'Save as a draft (only you see it)')),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  static IconData _presetIcon(String? preset) => switch (preset) {
        'healthcare' => Icons.local_hospital_outlined,
        'student_activities' => Icons.sports_soccer_rounded,
        'student_affairs' => Icons.badge_outlined,
        _ => Icons.star_outline_rounded,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  The sheet
// ═════════════════════════════════════════════════════════════════════════════

/// Writes a new request for [memberId] (or edits [editing], a draft of mine). Returns the saved / submitted request.
Future<AdvRequest?> showAdvRequestComposer(
  BuildContext context, {
  required int orgId,
  required int memberId,
  String? studentName,
  String kind = 'support',
  AdvRequest? editing,
  int? flagId,
}) async {
  final api = AdvSupportApi(orgId);
  final store = AdvRequestDraftStore.instance;
  final title = TextEditingController(text: editing?.title ?? '');
  final body = TextEditingController(text: editing?.body ?? '');
  var draft = editing == null
      ? AdvRequestDraft(kind: kind, clientId: AdvDraftStore.newClientId(), flagId: flagId)
      : AdvRequestDraft.of(editing);
  AdvRequestOptions? options;
  String? loadError;
  AdvChainPreview? preview;
  var previewLoading = true;
  var restored = false, savedOnDevice = false, uploading = false, busy = false, started = false, loaded = false;
  String? error;
  Timer? timer;
  void Function(void Function())? setSheet;

  void refresh(void Function() fn) {
    final s = setSheet;
    if (s != null) {
      s(fn);
    } else {
      fn();
    }
  }

  AdvRequestDraft current() => draft.copyWith(title: title.text, body: body.text);

  Future<void> keepOnDevice() async {
    if (editing != null) return;
    final d = current();
    await store.save(orgId, memberId, d);
    refresh(() => savedOnDevice = d.worthKeeping);
  }

  void typed() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 700), keepOnDevice);
  }

  title.addListener(typed);
  body.addListener(typed);

  Future<void> load() async {
    final optionsCall = orgCall(() => api.options(), quiet: true);
    final previewCall = orgCall(() => api.previewChain(memberId), quiet: true);
    final keptCall = editing == null ? store.read(orgId, memberId) : Future<AdvRequestDraft?>.value();
    final o = await optionsCall;
    final p = await previewCall;
    final kept = await keptCall;
    refresh(() {
      if (o.ok) {
        options = o.data as AdvRequestOptions;
      } else {
        loadError = advSupportErrorText(o.error!);
      }
      preview = p.ok ? p.data as AdvChainPreview : null;
      previewLoading = false;
    });
    if (kept != null && kept.worthKeeping && title.text.isEmpty && body.text.isEmpty) {
      refresh(() {
        draft = kept.clientId == null ? kept.copyWith(clientId: () => AdvDraftStore.newClientId()) : kept;
        restored = true;
        savedOnDevice = true;
      });
      title.text = kept.title;
      body.text = kept.body;
    }
    loaded = true;
  }

  /// Posts a new request, once more under a fresh `client_id` when the server holds that id for another student.
  Future<AdvRequest> post(AdvRequestDraft d, {required bool submit}) async {
    try {
      return await api.create(memberId, d, submit: submit);
    } catch (e) {
      if (ApiException.from(e).code != 'advising_client_id_conflict') rethrow;
      draft = draft.copyWith(clientId: () => AdvDraftStore.newClientId());
      return api.create(memberId, current(), submit: submit);
    }
  }

  final result = await showAppSheet<AdvRequest>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        setSheet = set;
        if (!started) {
          started = true;
          load();
        }

        Future<void> send({required bool submit}) async {
          final o = options;
          if (o == null) return;
          final d = current();
          final why = d.error(type: o.type(d.supportType), submit: submit);
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          timer?.cancel();
          final ed = editing;
          final r = await orgCall(() async {
            if (ed == null) return post(d, submit: submit);
            final saved = await api.save(ed.id, d, version: ed.version);
            return submit ? api.submit(saved.id, version: saved.version) : saved;
          }, quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            final e = r.error!;
            if (editing == null) await keepOnDevice();
            set(() {
              busy = false;
              error = e.isNetwork || e.isTimeout
                  ? t('لا يوجد اتصال — الطلب محفوظ على هذا الجهاز، أرسله عند عودة الاتصال.', 'No connection — the request is kept on this device; send it when you are back online.')
                  : advSupportErrorText(e);
            });
            return;
          }
          if (editing == null) await store.clear(orgId, memberId);
          final made = r.data as AdvRequest;
          showAppNotice(!submit
              ? t('حُفظت المسودة', 'Draft saved')
              : (made.referral ? t('أُرسلت الإحالة', 'Referral sent') : t('أُرسل الطلب إلى مسار الاعتماد', 'Request submitted to the approval chain')));
          if (ctx.mounted) Navigator.pop(ctx, made);
        }

        Future<void> pickUntil() async {
          final picked = await pickAdvDate(ctx, draft.accommodationUntil, days: 120);
          if (picked != null) set(() => draft = draft.copyWith(accommodationUntil: () => picked));
          keepOnDevice();
        }

        Future<void> attach() async {
          set(() => uploading = true);
          final a = await uploadGovAttachment(orgId);
          if (!ctx.mounted) return;
          set(() {
            uploading = false;
            if (a != null) draft = draft.copyWith(attachments: [...draft.attachments, a]);
          });
          if (a != null) {
            showAppNotice(t('أُرفق الملف', 'File attached'));
            keepOnDevice();
          }
        }

        void template(AdvRequestTemplate tp) {
          final o = options;
          final typeLabel = draft.referral ? (o?.target(draft.targetDeptId)?.name ?? '') : (o?.type(draft.supportType)?.label ?? '');
          final filled = advFillTemplate(tp.body, {
            'student': ?studentName,
            'topic': typeLabel,
            'date': advDate(DateTime.now().toUtc()),
          });
          set(() => draft = draft.copyWith(templateId: () => tp.id));
          if (title.text.trim().isEmpty && typeLabel.isNotEmpty) title.text = typeLabel;
          body.text = body.text.trim().isEmpty ? filled : '${body.text.trimRight()}\n\n$filled';
          body.selection = TextSelection.collapsed(offset: body.text.length);
        }

        final o = options;
        return AppSheetContent(
          title: editing != null
              ? t('تعديل المسودة', 'Edit the draft')
              : (draft.referral ? t('إحالة جديدة', 'New referral') : t('طلب دعم جديد', 'New support request')),
          children: [
            if (o == null && loadError == null)
              const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero)
            else if (o == null)
              AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: loadError!)
            else
              AdvRequestForm(
                options: o,
                draft: draft,
                title: title,
                body: body,
                studentName: studentName,
                editing: editing != null,
                preview: preview,
                previewLoading: previewLoading,
                restored: restored,
                savedOnDevice: savedOnDevice && editing == null,
                uploading: uploading,
                busy: busy,
                error: error,
                onKind: (k) {
                  set(() {
                    draft = draft.copyWith(kind: k);
                    error = null;
                  });
                  keepOnDevice();
                },
                onType: (x) {
                  set(() {
                    draft = draft.withType(x, o.categories);
                    error = null;
                  });
                  keepOnDevice();
                },
                onTarget: (id) {
                  set(() {
                    draft = draft.copyWith(targetDeptId: () => id);
                    error = null;
                  });
                  keepOnDevice();
                },
                onCategory: (id) => set(() => draft = draft.copyWith(categoryId: () => id)),
                onPriority: (p) => set(() => draft = draft.copyWith(priority: p)),
                onAccommodation: (k) => set(() => draft = draft.toggleAccommodation(k)),
                onPickUntil: pickUntil,
                onClearUntil: () => set(() => draft = draft.copyWith(accommodationUntil: () => null)),
                onTemplate: template,
                onAttach: attach,
                onOpenAttachment: (a) => openGovAttachment(ctx, a),
                onRemoveAttachment: (a) => set(() => draft = draft.copyWith(attachments: [for (final x in draft.attachments) if (x != a) x])),
                onSaveDraft: () => send(submit: false),
                onSubmit: busy ? null : () => send(submit: true),
              ),
          ],
        );
      }));
  timer?.cancel();
  setSheet = null;
  // closed without sending: what was typed stays on the device (only once the kept copy had its chance to load)
  if (result == null && editing == null && loaded) await store.save(orgId, memberId, current());
  title.removeListener(typed);
  body.removeListener(typed);
  return result;
}
