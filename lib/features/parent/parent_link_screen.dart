// lib/features/parent/parent_link_screen.dart
// Parent: enter the student's code, fill the fields / attach the documents the super-admin asked for
// (shown according to the ACTIVE mode), and follow the status of every request.
//   easy      -> code only
//   advanced  -> code + dynamic fields + documents (stays "pending" until an admin decides)
//   external  -> code + dynamic fields (linked only if the external service really verifies)
// Needs: file_picker (image / PDF documents).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import 'parent_consent.dart';
import 'parent_link_providers.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart';

class ParentLinkPage extends StatefulWidget {
  const ParentLinkPage({super.key});

  @override
  State<ParentLinkPage> createState() => _ParentLinkPageState();
}

class _ParentLinkPageState extends State<ParentLinkPage> {
  final _code = TextEditingController();
  final _ctrls = <String, TextEditingController>{};
  final _selects = <String, String?>{};
  final _docs = <String, PlatformFile>{};
  String _modeSeen = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ParentLinkProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key) => _ctrls.putIfAbsent(key, () => TextEditingController());

  void _resetFormIfConfigChanged(ParentLinkProvider p) {
    final sig = '${p.mode}|${p.fields.map((f) => f['key']).join(',')}|${p.documents.map((d) => d['key']).join(',')}';
    if (sig != _modeSeen) {
      _modeSeen = sig;
      _selects.clear();
      _docs.clear();
      for (final c in _ctrls.values) {
        c.clear();
      }
    }
  }

  Future<void> _pick(String key) async {
    // file_picker v12+: pickFile() returns PlatformFile? (null if cancelled).
    // The bytes are read later, when the request is submitted.
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (f == null) return;
    // PlatformFile.size was removed in v12 — length is now a method.
    final size = f.lengthSync() ?? await f.length() ?? 0;
    if (size > 8 * 1024 * 1024) {
      plToast('pl_file_too_big'.tr);
      return;
    }
    setState(() => _docs[key] = f);
  }

  Future<void> _submit(ParentLinkProvider p) async {
    final code = _code.text.trim();
    if (code.length < 4) {
      plToast('pl_enter_code'.tr);
      return;
    }
    final values = <String, String>{};
    for (final f in p.fields) {
      final key = '${f['key']}';
      final v = (f['type'] == 'select' ? _selects[key] : _ctrl(key).text.trim()) ?? '';
      if (f['required'] == true && v.isEmpty) {
        plToast('${'pl_field_required'.tr}: ${plLabel(f)}');
        return;
      }
      if (v.isNotEmpty) values[key] = v;
    }
    for (final d in p.documents) {
      if (d['required'] == true && !_docs.containsKey('${d['key']}')) {
        plToast('${'pl_doc_required'.tr}: ${plLabel(d)}');
        return;
      }
    }
    var r = await p.redeem(code, values, Map.of(_docs));
    if (!mounted) return;
    // an under-age child: ask for the parent's consent (version v1), then send the same request with it
    if (r == null && p.lastErrorCode == 'consent_required') {
      final agreed = await showParentConsentDialog(context);
      if (!mounted) return;
      if (agreed) {
        r = await p.redeem(code, values, Map.of(_docs), consent: true);
        if (!mounted) return;
      }
    }
    if (r == null) {
      plToast(p.errorMessage);
      return;
    }
    _code.clear();
    setState(() {
      _docs.clear();
      _selects.clear();
    });
    for (final c in _ctrls.values) {
      c.clear();
    }
    plToast(r['status'] == 'approved' ? 'pl_linked_ok'.tr : 'pl_submitted_pending'.tr, error: false);
  }

  Widget _fieldWidget(Map<String, dynamic> f) {
    final key = '${f['key']}';
    final label = '${plLabel(f)}${f['required'] == true ? ' *' : ''}';
    switch (f['type']) {
      case 'select':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppDropdown<String>(
            key: ValueKey('sel-$key-$_modeSeen-${_selects[key]}'),
            initialValue: _selects[key],
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            items: [
              for (final o in (f['options'] as List? ?? []))
                DropdownMenuItem(value: '$o', child: Text(_optionLabel('$o'))),
            ],
            onChanged: (v) => setState(() => _selects[key] = v),
          ),
        );
      case 'date':
        final c = _ctrl(key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            readOnly: true,
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.calendar_month_rounded)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(DateTime.now().year - 30),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (d != null) c.text = plDate(d);
            },
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _ctrl(key),
            keyboardType: f['type'] == 'number'
                ? TextInputType.number
                : f['type'] == 'phone'
                ? TextInputType.phone
                : TextInputType.text,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          ),
        );
    }
  }

  // known option values get a translation, anything else is shown as typed
  String _optionLabel(String o) {
    final k = 'pl_opt_$o';
    final t = k.tr;
    return t == k ? o : t;
  }

  Widget _docWidget(Map<String, dynamic> d) {
    final c = context.colors;
    final key = '${d['key']}';
    final f = _docs[key];
    return PlCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(f == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
            color: f == null ? c.primary : c.success),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${plLabel(d)}${d['required'] == true ? ' *' : ''}', style: c.h2.copyWith(fontSize: 14)),
            Text(f?.name ?? 'pl_doc_hint'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.caption),
          ]),
        ),
        TextButton(onPressed: () => _pick(key), child: Text(f == null ? 'pl_choose'.tr : 'pl_change'.tr)),
        if (f != null)
          IconButton(
              icon: Icon(Icons.close_rounded, color: c.danger),
              onPressed: () => setState(() => _docs.remove(key))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParentLinkProvider>();
    final c = context.colors;
    _resetFormIfConfigChanged(p);

    return AppRefresh(
      onRefresh: p.loadAll,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PlCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.link_rounded, color: c.primary),
                const SizedBox(width: 8),
                Text('pl_link_child'.tr, style: c.h2.copyWith(fontSize: 17)),
              ]),
              const SizedBox(height: 6),
              Text('pl_mode_hint_${p.mode}'.tr, style: c.caption),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                maxLength: 9,
                style: const TextStyle(fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                    labelText: 'pl_student_code'.tr, border: const OutlineInputBorder(), counterText: ''),
              ),
              const SizedBox(height: 12),
              for (final f in p.fields) _fieldWidget(f),
              if (p.mode == 'advanced' && p.documents.isNotEmpty) ...[
                Text('pl_documents'.tr, style: c.h2.copyWith(fontSize: 15)),
                const SizedBox(height: 8),
                for (final d in p.documents) _docWidget(d),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: p.isLoading ? null : () => _submit(p),
                  child: p.isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(p.mode == 'advanced' ? 'pl_submit_request'.tr : 'pl_link_now'.tr),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('pl_my_requests'.tr, style: c.h2.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          if (p.requests.isEmpty)
            PlCard(child: Text('pl_no_requests'.tr, style: c.caption))
          else
            for (final r in p.requests)
              PlCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${r['student_name']}', style: c.h2.copyWith(fontSize: 15))),
                    PlStatusChip('${r['status']}'),
                  ]),
                  const SizedBox(height: 4),
                  Text('${'pl_mode_${r['mode']}'.tr} · ${plDateTime(r['created_at'])}', style: c.caption),
                  if ('${r['decision_note'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${'pl_admin_note'.tr}: ${r['decision_note']}',
                        style: TextStyle(color: c.danger, fontSize: 13)),
                  ],
                  if (r['status'] == 'pending')
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () async {
                          final ok = await Helpers.confirmDialog(context);
                          if (ok == true && context.mounted) {
                            final done = await p.cancel(r['id'] as int);
                            if (!done) plToast(p.errorMessage);
                          }
                        },
                        child: Text('pl_cancel_request'.tr),
                      ),
                    ),
                ]),
              ),
        ],
      ),
    );
  }
}