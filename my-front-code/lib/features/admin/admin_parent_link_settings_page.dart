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
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../parent/parent_link_providers.dart';
import '../parent/parent_widgets.dart';
import 'admin_premium_widgets.dart';

class AdminParentLinkSettingsPage extends StatelessWidget {
  const AdminParentLinkSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminParentLinkProvider(),
        child: const _Form(),
      );
}

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
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
      plToast(p.errorMessage);
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
    });
  }

  Future<void> _save() async {
    Map<String, dynamic> tmpl;
    try {
      tmpl = Map<String, dynamic>.from(jsonDecode(_template.text.trim().isEmpty ? '{}' : _template.text) as Map);
    } catch (_) {
      plToast('pl_bad_json'.tr);
      return;
    }
    final body = <String, dynamic>{
      'mode': _mode,
      'code_ttl_minutes': int.tryParse(_ttl.text.trim()) ?? 15,
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
      plToast('pl_saved'.tr);
      await _load();
    } else {
      plToast(p.errorMessage);
    }
  }

  // ── editors ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _editItem({Map<String, dynamic>? item, required bool isDoc}) async {
    final key = TextEditingController(text: '${item?['key'] ?? ''}');
    final ar = TextEditingController(text: '${item?['label_ar'] ?? ''}');
    final en = TextEditingController(text: '${item?['label_en'] ?? ''}');
    final opts = TextEditingController(text: ((item?['options'] as List?) ?? []).join(', '));
    String type = '${item?['type'] ?? 'text'}';
    bool required = item?['required'] != false;
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isDoc ? 'pl_edit_document'.tr : 'pl_edit_field'.tr),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: key,
                  enabled: item == null,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'pl_key'.tr, helperText: 'a-z 0-9 _')),
              TextField(controller: ar, decoration: InputDecoration(labelText: 'pl_label_ar'.tr)),
              TextField(controller: en, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: 'pl_label_en'.tr)),
              if (!isDoc) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(labelText: 'pl_type'.tr),
                  items: [for (final t in ['text', 'number', 'phone', 'date', 'select']) DropdownMenuItem(value: t, child: Text('pl_type_$t'.tr))],
                  onChanged: (v) => setD(() => type = v ?? 'text'),
                ),
                if (type == 'select')
                  TextField(controller: opts, decoration: InputDecoration(labelText: 'pl_options'.tr, helperText: 'a, b, c')),
              ],
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('pl_required'.tr),
                  value: required,
                  onChanged: (v) => setD(() => required = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('pl_cancel'.tr)),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'key': key.text.trim(),
                'label_ar': ar.text.trim(),
                'label_en': en.text.trim(),
                'required': required,
                if (!isDoc) 'type': type,
                if (!isDoc) 'options': type == 'select' ? opts.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : <String>[],
              }),
              child: Text('pl_confirm'.tr),
            ),
          ],
        ),
      ),
    );
    for (final c in [key, ar, en, opts]) {
      c.dispose();
    }
    return res;
  }

  Widget _list(String title, List<Map<String, dynamic>> items, bool isDoc) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: c.h2.copyWith(fontSize: 15))),
        TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text('pl_add'.tr),
          onPressed: () async {
            final r = await _editItem(isDoc: isDoc);
            if (r != null) setState(() => items.add(r));
          },
        ),
      ]),
      if (items.isEmpty) Text('pl_none'.tr, style: c.caption),
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
            final r = await _editItem(item: items[i], isDoc: isDoc);
            if (r != null) setState(() => items[i] = r);
          },
          trailing: IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: c.danger),
              onPressed: () => setState(() => items.removeAt(i))),
        ),
    ]);
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    final c = context.colors;
    return PlCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ServiceIcon(icon: icon, colors: AdminPalette.violet, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: c.h2.copyWith(fontSize: 16))),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _tf(TextEditingController c, String label, {bool ltr = false, bool number = false, String? helper, int lines = 1, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: obscure ? 1 : lines,
          obscureText: obscure,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          textDirection: ltr ? TextDirection.ltr : null,
          style: lines > 1 ? const TextStyle(fontFamily: 'monospace', fontSize: 13) : null,
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final c = context.colors;
    final p = context.watch<AdminParentLinkProvider>();
    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'pl_settings_title'.tr),
      child: !_ready
          ? (p.hasError ? PlError(p.errorMessage ?? '', onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.all(16), children: [
              PremiumHero(
                icon: Icons.family_restroom_rounded,
                colors: AdminPalette.violet,
                title: 'pl_settings_title'.tr,
                subtitle: 'svc_pl_settings_d'.tr,
                footer: Wrap(spacing: 8, children: [
                  HeroPill('pl_mode_$_mode'.tr, icon: Icons.tune_rounded),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: c.warning.withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.warning.withAlpha(80)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, color: c.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text('pl_not_retroactive'.tr, style: const TextStyle(fontSize: 13))),
                ]),
              ),
              _section('pl_active_mode'.tr, Icons.tune_rounded, [
                RadioGroup<String>(
                  groupValue: _mode,
                  onChanged: (v) => setState(() => _mode = v ?? _mode),
                  child: Column(children: [
                    for (final m in ['easy', 'advanced', 'external'])
                      RadioListTile<String>(
                        value: m,
                        contentPadding: EdgeInsets.zero,
                        title: Text('pl_mode_$m'.tr),
                        subtitle: Text('pl_mode_desc_$m'.tr, style: c.caption.copyWith(fontSize: 12)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                _tf(_ttl, 'pl_code_ttl'.tr, number: true, helper: 'pl_code_ttl_hint'.tr),
              ]),
              _section('pl_mode_advanced'.tr, Icons.fact_check_rounded, [
                _list('pl_fields'.tr, _advFields, false),
                const Divider(),
                _list('pl_documents'.tr, _advDocs, true),
              ]),
              _section('pl_mode_external'.tr, Icons.cloud_sync_rounded, [
                _tf(_provider, 'pl_provider_name'.tr),
                _tf(_url, 'pl_api_url'.tr, ltr: true, helper: 'pl_api_url_hint'.tr),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _method,
                      decoration: InputDecoration(labelText: 'pl_method'.tr, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
                      items: const [DropdownMenuItem(value: 'POST', child: Text('POST')), DropdownMenuItem(value: 'GET', child: Text('GET'))],
                      onChanged: (v) => setState(() => _method = v ?? 'POST'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _auth,
                      decoration: InputDecoration(labelText: 'pl_auth'.tr, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
                      items: [for (final a in ['none', 'bearer', 'header']) DropdownMenuItem(value: a, child: Text('pl_auth_$a'.tr))],
                      onChanged: (v) => setState(() => _auth = v ?? 'none'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_auth == 'header') _tf(_header, 'pl_auth_header'.tr, ltr: true),
                if (_auth != 'none') ...[
                  _tf(_secret, 'pl_api_secret'.tr,
                      obscure: true, ltr: true, helper: _secretSet ? 'pl_secret_saved'.tr : 'pl_secret_hint'.tr),
                  if (_secretSet)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _clearSecret,
                      onChanged: (v) => setState(() => _clearSecret = v ?? false),
                      title: Text('pl_clear_secret'.tr),
                    ),
                ],
                _tf(_timeout, 'pl_timeout'.tr, number: true),
                _tf(_template, 'pl_body_template'.tr, ltr: true, lines: 6, helper: 'pl_template_hint'.tr),
                _tf(_path, 'pl_success_path'.tr, ltr: true, helper: 'pl_success_path_hint'.tr),
                _tf(_value, 'pl_success_value'.tr, ltr: true),
                _list('pl_fields'.tr, _extFields, false),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('pl_save'.tr),
                ),
              ),
              const SizedBox(height: 24),
            ]),
    );
  }
}
