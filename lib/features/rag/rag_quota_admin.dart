// The Super Admin's per-organization quota of the assistant's documents library (Phase 10, A04).
//
//   GET /api/v1/rag/orgs/{id}/quota   {org_id, docs, bytes, max_docs, max_bytes, override: {max_docs, max_bytes}}
//                                     max_* = the limits in force (null = unlimited)
//   PUT /api/v1/rag/orgs/{id}/quota   {max_docs, max_bytes} — replaces BOTH values; null = the platform default
//                                     (RAG_ORG_MAX_DOCS / RAG_ORG_MAX_BYTES), 0 = unlimited; Super Admin only
//                                     (403 super_admin_required), a negative value → 422
//
// Opened from the organization review sheet (admin_organizations_page.dart) for the Super Admin. The pure parts
// ([RagLimitMode], [RagQuotaOverrideDraft]) are unit-tested; [RagQuotaOverrideForm] is presentational and runs under
// the layout harness; [RagQuotaAdminSheet] only loads and saves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t;
import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show numText, parseNum;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_education_app/features/rag/rag_library_screen.dart' show RagQuotaBar;

const ragQuotaMaxDocs = 10000000; // the server's bound (QuotaIn.max_docs ≤ 10 000 000)
const ragQuotaMaxBytes = 1000000000000000; // the server's bound (QuotaIn.max_bytes ≤ 10^15)
const _mib = 1024 * 1024; // ragSizeText's "MB"

/// How one limit is set: follow the platform default (null), no limit (0), or a number of its own.
enum RagLimitMode { platform, unlimited, custom }

RagLimitMode ragLimitModeOf(Object? v) {
  if (v == null) return RagLimitMode.platform;
  return asInt(v) <= 0 ? RagLimitMode.unlimited : RagLimitMode.custom;
}

String ragLimitModeText(RagLimitMode m) => switch (m) {
      RagLimitMode.platform => t('الافتراضي للمنصة', 'Platform default'),
      RagLimitMode.unlimited => t('بلا حد', 'Unlimited'),
      RagLimitMode.custom => t('حد خاص', 'A limit of its own'),
    };

/// The editable override. Storage is typed in MB (1 MB = 1024 × 1024 bytes, as [ragSizeText] shows it).
class RagQuotaOverrideDraft {
  RagQuotaOverrideDraft({this.docsMode = RagLimitMode.platform, this.docs = '', this.bytesMode = RagLimitMode.platform, this.mb = ''});

  /// From the server's `override` object (null values = platform default).
  factory RagQuotaOverrideDraft.fromOverride(Object? override) {
    final o = asMap(override);
    final d = o['max_docs'], b = o['max_bytes'];
    final dm = ragLimitModeOf(d), bm = ragLimitModeOf(b);
    return RagQuotaOverrideDraft(
        docsMode: dm,
        docs: dm == RagLimitMode.custom ? '${asInt(d)}' : '',
        bytesMode: bm,
        mb: bm == RagLimitMode.custom ? numText(double.parse((asInt(b) / _mib).toStringAsFixed(2))) : '');
  }

  RagLimitMode docsMode, bytesMode;
  String docs, mb;

  int? get _docs {
    final v = parseNum(docs);
    if (v == null || v != v.truncateToDouble()) return null;
    return v.toInt();
  }

  int? get _bytes {
    final v = parseNum(mb);
    return v == null ? null : (v * _mib).round();
  }

  /// null when valid; otherwise a code for [ragQuotaDraftErrorText].
  String? validate() {
    if (docsMode == RagLimitMode.custom) {
      final d = _docs;
      if (d == null || d < 1 || d > ragQuotaMaxDocs) return 'bad_docs';
    }
    if (bytesMode == RagLimitMode.custom) {
      final b = _bytes;
      if (b == null || b < 1 || b > ragQuotaMaxBytes) return 'bad_size';
    }
    return null;
  }

  /// The PUT body — always both keys, because the PUT replaces both values.
  Map<String, dynamic> body() => {
        'max_docs': switch (docsMode) { RagLimitMode.platform => null, RagLimitMode.unlimited => 0, RagLimitMode.custom => _docs },
        'max_bytes': switch (bytesMode) { RagLimitMode.platform => null, RagLimitMode.unlimited => 0, RagLimitMode.custom => _bytes },
      };
}

String ragQuotaDraftErrorText(String code) => switch (code) {
      'bad_docs' => t('عدد المستندات رقم صحيح بين 1 و10٬000٬000', 'The number of documents must be a whole number from 1 to 10,000,000'),
      'bad_size' => t('المساحة رقم أكبر من صفر بالميغابايت', 'The storage must be a number of MB above zero'),
      _ => t('تحقق من الحقول', 'Check the fields'),
    };

/// The two limits as dropdown + number field, with a Save button. Presentational.
class RagQuotaOverrideForm extends StatefulWidget {
  const RagQuotaOverrideForm({super.key, required this.initial, required this.onSave, this.busy = false});
  final RagQuotaOverrideDraft initial;
  final bool busy;
  final void Function(Map<String, dynamic> body) onSave;

  @override
  State<RagQuotaOverrideForm> createState() => _RagQuotaOverrideFormState();
}

class _RagQuotaOverrideFormState extends State<RagQuotaOverrideForm> {
  late final RagQuotaOverrideDraft _d = RagQuotaOverrideDraft(
      docsMode: widget.initial.docsMode, docs: widget.initial.docs, bytesMode: widget.initial.bytesMode, mb: widget.initial.mb);
  late final _docs = TextEditingController(text: _d.docs), _mb = TextEditingController(text: _d.mb);
  String? _err;

  @override
  void dispose() {
    _docs.dispose();
    _mb.dispose();
    super.dispose();
  }

  Widget _mode(String label, RagLimitMode value, ValueChanged<RagLimitMode> onChanged) => AppDropdown<RagLimitMode>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final m in RagLimitMode.values)
            DropdownMenuItem(value: m, child: Text(ragLimitModeText(m), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => onChanged(v ?? RagLimitMode.platform)),
      );

  void _save() {
    _d
      ..docs = _docs.text
      ..mb = _mb.text;
    final e = _d.validate();
    setState(() => _err = e == null ? null : ragQuotaDraftErrorText(e));
    if (e == null) widget.onSave(_d.body());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _mode(t('عدد المستندات', 'Number of documents'), _d.docsMode, (m) => _d.docsMode = m),
      if (_d.docsMode == RagLimitMode.custom)
        AppNumberField(controller: _docs, label: t('أقصى عدد للمستندات', 'Most documents'), min: 0, step: 10),
      const SizedBox(height: 10),
      _mode(t('مساحة التخزين', 'Storage'), _d.bytesMode, (m) => _d.bytesMode = m),
      if (_d.bytesMode == RagLimitMode.custom)
        AppNumberField(controller: _mb, label: t('أقصى مساحة (ميغابايت)', 'Most storage (MB)'), min: 0, step: 50, decimals: 2),
      if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err!)),
      const SizedBox(height: 12),
      AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: widget.busy, onPressed: widget.busy ? null : _save),
      const SizedBox(height: 6),
      Text(
          t('خفض الحد لا يحذف شيئاً: تُرفض الرفعات الجديدة فقط حتى تؤرشف المؤسسة ما يكفي.',
              'Lowering a limit deletes nothing: only new uploads are refused until the organization archives enough.'),
          style: appText(11.5, c: c.textLight)),
    ]);
  }
}

Future<void> showRagQuotaAdminSheet(BuildContext context, {required int orgId, String? orgName, RagLibraryApi? api}) =>
    showAppSheet<void>(context, (_) => RagQuotaAdminSheet(orgId: orgId, orgName: orgName, api: api));

/// Loads the organization's quota and saves the override.
class RagQuotaAdminSheet extends StatefulWidget {
  const RagQuotaAdminSheet({super.key, required this.orgId, this.orgName, this.api});
  final int orgId;
  final String? orgName;
  final RagLibraryApi? api;

  @override
  State<RagQuotaAdminSheet> createState() => _RagQuotaAdminSheetState();
}

class _RagQuotaAdminSheetState extends State<RagQuotaAdminSheet> {
  late final RagLibraryApi _api = widget.api ?? RagLibraryApi();
  EngineResult? _r;
  bool _busy = false;
  String? _saveErr;
  int _formKey = 0; // a new form after a save, so it shows what the server stored

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _r = null);
    final r = await _api.quota(widget.orgId);
    if (mounted) setState(() => _r = r);
  }

  Future<void> _save(Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _saveErr = null;
    });
    final r = await _api.saveQuota(widget.orgId, body);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _r = r;
        _formKey++;
      } else {
        _saveErr = ragResultText(r);
      }
    });
    if (r.ok) appToast(t('تم حفظ الحصة', 'Quota saved'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _r;
    final title = t('حصة مكتبة المساعد', 'Assistant library quota');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(widget.orgName == null || widget.orgName!.isEmpty ? title : '$title — ${widget.orgName}'),
        if (r == null)
          const SizedBox(height: 160, child: AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero))
        else if (!r.ok) ...[
          AppBanner(
              icon: Icons.error_outline_rounded,
              color: c.danger,
              text: r.unavailable
                  ? t('خدمة مكتبة المساعد لا تستجيب لهذا الطلب — يلزم تحديث الخادم.', 'The assistant library service does not offer this yet — it needs a server update.')
                  : ragResultText(r)),
          const SizedBox(height: 10),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(t('إعادة المحاولة', 'Try again'))),
        ] else ...[
          if (RagQuota.fromJson(r.map) case final q?) ...[
            Text(t('الاستخدام والحد الساري الآن', 'Usage and the limits in force now'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
            const SizedBox(height: 6),
            RagQuotaBar(quota: q),
            const SizedBox(height: 16),
          ],
          RagQuotaOverrideForm(
              key: ValueKey(_formKey), initial: RagQuotaOverrideDraft.fromOverride(r.map['override']), busy: _busy, onSave: _save),
          if (_saveErr != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _saveErr!)),
        ],
      ]),
    );
  }
}
