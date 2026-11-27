// lib/features/admin/admin_parent_link_settings_page.dart
// SUPER-ADMIN: parent ⇄ student linking settings.
//   • active mode: easy | advanced | external
//   • life of the student's link code
//   • advanced mode: fields + documents the parent must provide
//   • external mode: the verification service (URL, auth, request template, how "verified" is read)
// Changes apply to NEW requests only — requests already made keep the rules they were submitted under.
// The external API secret is write-only: the server never sends it back.
//
// Open it from the admin "More" page:
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminParentLinkSettingsPage()));
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../parent/parent_link_providers.dart';
import '../parent/parent_widgets.dart' show plLabel, plList;
import 'package:flutter_education_app/design/app_kit.dart';
import 'admin_common.dart' show t;
import 'admin_labels.dart';
import 'admin_page.dart';
import 'adm_kit.dart' show AdmPage;

class AdminParentLinkSettingsPage extends StatelessWidget {
  const AdminParentLinkSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminParentLinkProvider(),
        child: const _Form(),
      );
}

/// What a host page (the Parent linking page's header) needs to know about an embedded [ParentLinkSettingsForm], and
/// how to drive it: its Save and Refresh. The form keeps it up to date; listen to it to redraw the header.
class ParentLinkSettingsHandle extends ChangeNotifier {
  bool ready = false, dirty = false, saving = false;
  DateTime? loadedAt;
  Future<void> Function()? save, reload;

  void _sync({required bool ready, required bool dirty, required bool saving, required DateTime? loadedAt}) {
    if (this.ready == ready && this.dirty == dirty && this.saving == saving && this.loadedAt == loadedAt) return;
    this.ready = ready;
    this.dirty = dirty;
    this.saving = saving;
    this.loadedAt = loadedAt;
    notifyListeners();
  }
}

class _Form extends StatelessWidget {
  const _Form();

  @override
  Widget build(BuildContext context) => const ParentLinkSettingsForm();
}

/// The settings form. Alone (no [handle]) it is a whole page with its own header; with a [handle] it is the body only
/// and the host draws Save / Refresh / the unsaved-changes guard from the handle. Reads the [AdminParentLinkProvider]
/// above it.
class ParentLinkSettingsForm extends StatefulWidget {
  const ParentLinkSettingsForm({super.key, this.handle});

  final ParentLinkSettingsHandle? handle;

  @override
  State<ParentLinkSettingsForm> createState() => _FormState();
}

class _FormState extends State<ParentLinkSettingsForm> {
  bool _ready = false, _saving = false;
  String _mode = 'easy';
  final _ttl = TextEditingController();
  List<Map<String, dynamic>> _advFields = [], _advDocs = [], _extFields = [];

  // external
  final _provider = TextEditingController(), _url = TextEditingController();
  final _header = TextEditingController(), _secret = TextEditingController();
  final _timeout = TextEditingController(), _template = TextEditingController();
  final _path = TextEditingController(), _value = TextEditingController();
  String _method = 'POST', _auth = 'none';
  bool _secretSet = false, _clearSecret = false;

  /// The form as the server holds it: Back asks only when something differs.
  String _saved = '';
  DateTime? _loadedAt;

  String _snap() => jsonEncode([
        _mode, _ttl.text, _advFields, _advDocs, _extFields, _provider.text, _url.text, _header.text, _secret.text,
        _timeout.text, _template.text, _path.text, _value.text, _method, _auth, _clearSecret,
      ]);

  bool get _dirty => _ready && _snap() != _saved;

  @override
  void initState() {
    super.initState();
    widget.handle?.save = _save;
    widget.handle?.reload = _load;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    final h = widget.handle;
    if (h != null && h.save == _save) h.save = h.reload = null;
    for (final c in [_ttl, _provider, _url, _header, _secret, _timeout, _template, _path, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = context.read<AdminParentLinkProvider>();
    final ok = await p.loadSettings();
    if (!mounted) return;
    if (!ok) {
      setState(() {}); // the error state (or the old form, when this was a refresh) redraws
      if (_ready) showAppNotice(p.errorMessage ?? 'ds_error_body'.tr, error: true);
      return;
    }
    final s = p.settings;
    final adv = Map<String, dynamic>.from(s['advanced'] as Map? ?? {});
    final ext = Map<String, dynamic>.from(s['external'] as Map? ?? {});
    setState(() {
      _mode = '${s['mode']}';
      _ttl.text = '${s['code_ttl_minutes']}';
      _advFields = plList(adv['fields']);
      _advDocs = plList(adv['documents']);
      _extFields = plList(ext['fields']);
      _provider.text = '${ext['provider_name'] ?? ''}';
      _url.text = '${ext['url'] ?? ''}';
      _header.text = '${ext['auth_header'] ?? 'X-API-Key'}';
      _timeout.text = '${ext['timeout_seconds'] ?? 10}';
      _template.text = const JsonEncoder.withIndent('  ').convert(ext['body_template'] ?? {});
      _path.text = '${ext['success_path'] ?? ''}';
      _value.text = '${ext['success_value'] ?? 'true'}';
      _method = '${ext['method'] ?? 'POST'}';
      _auth = '${ext['auth_type'] ?? 'none'}';
      _secretSet = ext['secret_set'] == true;
      _clearSecret = false;
      _secret.clear();
      _ready = true;
      _loadedAt = DateTime.now();
      _saved = _snap();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    Map<String, dynamic> tmpl;
    try {
      tmpl = Map<String, dynamic>.from(jsonDecode(_template.text.trim().isEmpty ? '{}' : _template.text) as Map);
    } catch (_) {
      showAppNotice('pl_bad_json'.tr, error: true);
      return;
    }
    final ttl = int.tryParse(_ttl.text.trim());
    if (ttl == null || ttl <= 0) {
      showAppNotice(t('مدة صلاحية الرمز يجب أن تكون عددًا موجبًا من الدقائق', 'The code life must be a positive number of minutes'), error: true);
      return;
    }
    final body = <String, dynamic>{
      'mode': _mode,
      'code_ttl_minutes': ttl,
      'advanced': {'fields': _advFields, 'documents': _advDocs},
    };
    // Only send the external block when it is configured (or is the mode being activated),
    // so an untouched, empty form never produces a validation error for the other modes.
    if (_url.text.trim().isNotEmpty || _mode == 'external') {
      body['external'] = {
        'provider_name': _provider.text.trim(),
        'url': _url.text.trim(),
        'method': _method,
        'auth_type': _auth,
        'auth_header': _header.text.trim(),
        'timeout_seconds': int.tryParse(_timeout.text.trim()) ?? 10,
        'body_template': tmpl,
        'success_path': _path.text.trim(),
        'success_value': _value.text.trim(),
        'fields': _extFields,
        if (_secret.text.trim().isNotEmpty) 'secret': _secret.text.trim(),
        if (_clearSecret) 'clear_secret': true,
      };
    }
    setState(() => _saving = true);
    final p = context.read<AdminParentLinkProvider>();
    final ok = await p.saveSettings(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      showAppNotice('pl_saved'.tr);
      await _load();
    } else {
      showAppNotice(p.errorMessage ?? 'ds_error_body'.tr, error: true);
    }
  }

  // ── editors ────────────────────────────────────────────────────────────────

  /// Add / edit one field or document. The key is required, a-z 0-9 _, and unique inside [existing].
  Future<Map<String, dynamic>?> _editItem({
    Map<String, dynamic>? item,
    required bool isDoc,
    required List<Map<String, dynamic>> existing,
  }) async {
    final key = TextEditingController(text: '${item?['key'] ?? ''}');
    final ar = TextEditingController(text: '${item?['label_ar'] ?? ''}');
    final en = TextEditingController(text: '${item?['label_en'] ?? ''}');
    final opts = TextEditingController(text: ((item?['options'] as List?) ?? []).join(', '));
    String type = '${item?['type'] ?? 'text'}';
    bool required = item?['required'] != false;
    String? error;
    final res = await showAppSheet<Map<String, dynamic>>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String? validate() {
            final k = key.text.trim();
            if (k.isEmpty) return t('المفتاح مطلوب', 'The key is required');
            if (!RegExp(r'^[a-z0-9_]+$').hasMatch(k)) return t('المفتاح: حروف إنجليزية صغيرة وأرقام و _ فقط', 'Key: lowercase letters, digits and _ only');
            if (item == null && existing.any((e) => e['key'] == k)) return t('هذا المفتاح مستخدم بالفعل', 'This key is already used');
            if (ar.text.trim().isEmpty && en.text.trim().isEmpty) return t('اكتب الاسم بلغة واحدة على الأقل', 'Give it a name in at least one language');
            if (!isDoc && type == 'select' && !opts.text.split(',').any((e) => e.trim().isNotEmpty)) {
              return t('أضف خيارًا واحدًا على الأقل', 'Add at least one option');
            }
            return null;
          }

          return AppSheetContent(
            title: isDoc ? 'pl_edit_document'.tr : 'pl_edit_field'.tr,
            children: [
              TextField(
                  controller: key,
                  enabled: item == null,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'pl_key'.tr, helperText: 'a-z 0-9 _')),
              AppSpace.gapXs,
              TextField(controller: ar, decoration: InputDecoration(labelText: 'pl_label_ar'.tr)),
              AppSpace.gapXs,
              TextField(controller: en, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: 'pl_label_en'.tr)),
              if (!isDoc) ...[
                AppSpace.gapSm,
                AppDropdown<String>(
                  initialValue: type,
                  decoration: InputDecoration(labelText: 'pl_type'.tr),
                  items: [for (final x in ['text', 'number', 'phone', 'date', 'select']) DropdownMenuItem(value: x, child: Text('pl_type_$x'.tr))],
                  onChanged: (v) => setD(() => type = v ?? 'text'),
                ),
                if (type == 'select')
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: TextField(controller: opts, decoration: InputDecoration(labelText: 'pl_options'.tr, helperText: 'a, b, c')),
                  ),
              ],
              AppSwitchTile(title: 'pl_required'.tr, value: required, onChanged: (v) => setD(() => required = v)),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Text(error!, style: AppType.meta(ctx).copyWith(color: ctx.colors.danger)),
                ),
              AppButton.primary(
                label: 'pl_confirm'.tr,
                expand: true,
                onPressed: () {
                  final e = validate();
                  if (e != null) {
                    setD(() => error = e);
                    return;
                  }
                  Navigator.pop(ctx, {
                    'key': key.text.trim(),
                    'label_ar': ar.text.trim(),
                    'label_en': en.text.trim(),
                    'required': required,
                    if (!isDoc) 'type': type,
                    if (!isDoc) 'options': type == 'select' ? opts.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : <String>[],
                  });
                },
              ),
            ],
          );
        },
      ),
    );
    // the sheet is still animating out: dispose only after it is gone
    disposeAfterRoute([key, ar, en, opts]);
    return res;
  }

  Widget _list(String title, List<Map<String, dynamic>> items, bool isDoc) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: AppType.section(context))),
        AppButton.tonal(
          icon: Icons.add_rounded,
          label: 'pl_add'.tr,
          size: AppButtonSize.sm,
          onPressed: () async {
            final r = await _editItem(isDoc: isDoc, existing: items);
            if (r != null) setState(() => items.add(r));
          },
        ),
      ]),
      if (items.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs), child: Text('pl_none'.tr, style: AppType.meta(context))),
      for (var i = 0; i < items.length; i++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(isDoc ? Icons.description_rounded : Icons.text_fields_rounded, color: c.primary),
          title: Text('${plLabel(items[i])}  ·  ${items[i]['key']}'),
          subtitle: Text(isDoc
              ? (items[i]['required'] == true ? 'pl_required'.tr : 'pl_optional'.tr)
              : '${'pl_type_${items[i]['type']}'.tr} · ${items[i]['required'] == true ? 'pl_required'.tr : 'pl_optional'.tr}'),
          onTap: () async {
            final r = await _editItem(item: items[i], isDoc: isDoc, existing: items);
            if (r != null) setState(() => items[i] = r);
          },
          trailing: AppIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: t('حذف', 'Delete'),
            onPressed: () async {
              final name = plLabel(items[i]);
              final ok = await appConfirm(
                context,
                message: isDoc
                    ? t('حذف المستند «$name»؟ لن يُطلب من أولياء الأمور في الطلبات الجديدة.', 'Delete the document "$name"? New requests will no longer ask for it.')
                    : t('حذف الحقل «$name»؟ لن يُطلب من أولياء الأمور في الطلبات الجديدة.', 'Delete the field "$name"? New requests will no longer ask for it.'),
                danger: true,
              );
              if (ok && mounted) setState(() => items.removeAt(i));
            },
          ),
        ),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: AppSection(
          title: title,
          child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ),
      );

  Widget _numberField(TextEditingController c, String label, {String? helper}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppNumberField(controller: c, label: label, min: 0, onChanged: (_) => setState(() {})),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(helper, style: AppType.meta(context)),
            ),
        ]),
      );

  Widget _tf(TextEditingController c, String label, {bool ltr = false, String? helper, int lines = 1, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: TextField(
          controller: c,
          maxLines: obscure ? 1 : lines,
          obscureText: obscure,
          keyboardType: TextInputType.text,
          textDirection: ltr ? TextDirection.ltr : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final c = context.colors;
    final p = context.watch<AdminParentLinkProvider>();
    final h = widget.handle;
    if (h != null) {
      final (ready, dirty, saving, at) = (_ready, _dirty, _saving, _loadedAt);
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? h._sync(ready: ready, dirty: dirty, saving: saving, loadedAt: at) : null);
    }
    final body = !_ready
          ? (p.hasError
              ? Center(child: AppErrorState(message: p.errorMessage, onRetry: _load))
              : const AppListSkeleton())
          : ListView(padding: AdminPage.bodyPadding(context), children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: AppBanner(icon: Icons.info_outline_rounded, text: 'pl_not_retroactive'.tr, color: c.warning),
              ),
              _section('pl_active_mode'.tr, [
                RadioGroup<String>(
                  groupValue: _mode,
                  onChanged: (v) => setState(() => _mode = v ?? _mode),
                  child: Column(children: [
                    for (final m in ['easy', 'advanced', 'external'])
                      RadioListTile<String>(
                        value: m,
                        contentPadding: EdgeInsets.zero,
                        title: Text('pl_mode_$m'.tr),
                        subtitle: Text('pl_mode_desc_$m'.tr, style: AppType.meta(context)),
                      ),
                  ]),
                ),
                AppSpace.gapXs,
                _numberField(_ttl, 'pl_code_ttl'.tr, helper: 'pl_code_ttl_hint'.tr),
              ]),
              _section('pl_mode_advanced'.tr, [
                _list('pl_fields'.tr, _advFields, false),
                const Divider(),
                _list('pl_documents'.tr, _advDocs, true),
              ]),
              _section('pl_mode_external'.tr, [
                _tf(_provider, 'pl_provider_name'.tr),
                _tf(_url, 'pl_api_url'.tr, ltr: true, helper: 'pl_api_url_hint'.tr),
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                  SizedBox(
                    width: 220,
                    child: AppDropdown<String>(
                      initialValue: _method,
                      decoration: InputDecoration(labelText: 'pl_method'.tr),
                      items: const [DropdownMenuItem(value: 'POST', child: Text('POST')), DropdownMenuItem(value: 'GET', child: Text('GET'))],
                      onChanged: (v) => setState(() => _method = v ?? 'POST'),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: AppDropdown<String>(
                      initialValue: _auth,
                      decoration: InputDecoration(labelText: 'pl_auth'.tr),
                      items: [for (final a in ['none', 'bearer', 'header']) DropdownMenuItem(value: a, child: Text('pl_auth_$a'.tr))],
                      onChanged: (v) => setState(() => _auth = v ?? 'none'),
                    ),
                  ),
                ]),
                AppSpace.gapSm,
                if (_auth == 'header') _tf(_header, 'pl_auth_header'.tr, ltr: true),
                if (_auth != 'none') ...[
                  _tf(_secret, 'pl_api_secret'.tr,
                      obscure: true, ltr: true, helper: _secretSet ? 'pl_secret_saved'.tr : 'pl_secret_hint'.tr),
                  if (_secretSet)
                    AppSwitchTile(
                      title: 'pl_clear_secret'.tr,
                      value: _clearSecret,
                      onChanged: (v) => setState(() => _clearSecret = v),
                    ),
                ],
                _numberField(_timeout, 'pl_timeout'.tr),
                _tf(_template, 'pl_body_template'.tr, ltr: true, lines: 6, helper: 'pl_template_hint'.tr),
                _tf(_path, 'pl_success_path'.tr, ltr: true, helper: 'pl_success_path_hint'.tr),
                _tf(_value, 'pl_success_value'.tr, ltr: true),
                _list('pl_fields'.tr, _extFields, false),
              ]),
            ]);
    if (h != null) return body;
    return AdmPage(
      kicker: 'admin_group_people'.tr,
      width: AppWidth.reading,
      title: 'pl_settings_title'.tr,
      subtitle: 'svc_pl_settings_d'.tr,
      icon: Icons.family_restroom_rounded,
      onRefresh: _saving || (p.isLoading && !_ready) ? null : _load,
      updatedAt: _loadedAt,
      dirty: _dirty,
      primaryAction: _ready ? AppButton.primary(label: 'pl_save'.tr, busy: _saving, onPressed: _dirty ? _save : null) : null,
      body: body,
    );
  }
}
