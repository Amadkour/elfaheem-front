// lib/features/org/org_dynamic_form.dart
//
// One renderer for every server-defined form: department forms (OrgFormFillScreen) and the eligibility form of a
// department / academic-department join policy. The field list always comes from the server; this file only draws it.
//
//   OrgFormAnswers   the answers + text controllers of one form (keep it in the State so input survives rebuilds)
//   OrgDynamicField  one field: text · textarea · number · email · phone · select · multiselect · checkbox · date · file
//
// Options may be plain strings (`["A","B"]`) or objects (`[{"value":"y4","label_ar":"…","label_en":"…"}]`) —
// fields bound to the institution's configuration (`bind`) arrive as objects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_inputs.dart';

import '../admin/admin_common.dart';
import 'org_services_pages.dart' show fieldIcons;
import 'org_ui.dart';

/// (value, label) of one option, whatever shape the server used.
(String, String) orgOption(dynamic o) {
  if (o is Map) {
    final v = '${o['value'] ?? o['key'] ?? o['id'] ?? ''}';
    final ar = '${o['label_ar'] ?? o['name_ar'] ?? o['label'] ?? ''}';
    final en = '${o['label_en'] ?? o['name_en'] ?? o['label'] ?? ''}';
    final l = t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
    return (v, l.isEmpty ? v : l);
  }
  return ('$o', '$o');
}

class OrgFormAnswers {
  final Map<String, dynamic> values = {};
  final Map<String, TextEditingController> _ctrls = {};

  TextEditingController ctrl(String key) => _ctrls[key] ??= TextEditingController(text: values[key] is String ? values[key] : null);

  bool usesController(Map<String, dynamic> f) => !const {'select', 'multiselect', 'checkbox', 'date', 'file'}.contains('${f['type']}');

  /// Copies the text controllers into [values] and returns the answers for [fields].
  Map<String, dynamic> collect(List<Map<String, dynamic>> fields) {
    final out = <String, dynamic>{};
    for (final f in fields) {
      final k = '${f['key']}';
      if (usesController(f) && _ctrls.containsKey(k)) values[k] = _ctrls[k]!.text.trim();
      if (values.containsKey(k)) out[k] = values[k];
    }
    return out;
  }

  static bool isEmpty(Map<String, dynamic> f, dynamic v) =>
      v == null || v == '' || (v is List && v.isEmpty) || (f['type'] == 'checkbox' && v != true);

  /// Keys of required fields that are still empty (call after [collect]).
  Set<String> missing(List<Map<String, dynamic>> fields) =>
      {for (final f in fields) if (f['required'] == true && isEmpty(f, values['${f['key']}'])) '${f['key']}'};

  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
  }
}

class OrgDynamicField extends StatelessWidget {
  const OrgDynamicField({
    super.key,
    required this.field,
    required this.answers,
    required this.onChanged,
    this.error,
    this.onUpload,
  });

  final Map<String, dynamic> field;
  final OrgFormAnswers answers;
  final VoidCallback onChanged;        // the parent calls setState
  final String? error;                 // server or local validation message for this field
  final Future<Map<String, dynamic>?> Function()? onUpload;   // `file` fields only

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = field;
    final k = '${f['key']}';
    final required = f['required'] == true;
    final label = '${f['label'] ?? orgOption({'label_ar': f['label_ar'], 'label_en': f['label_en']}).$2}${required ? ' *' : ''}';
    final help = '${f['help'] ?? ''}';
    final opts = [for (final o in (f['options'] as List? ?? const [])) orgOption(o)];
    final v = answers.values;
    void put(dynamic x) {
      v[k] = x;
      onChanged();
    }

    Widget title() => Text(label, style: orgText(context, w: FontWeight.w700));
    Widget input;
    switch ('${f['type']}') {
      case 'textarea':
        input = Field(controller: answers.ctrl(k), label: label, maxLines: 4);
      case 'number':
        input = Field(controller: answers.ctrl(k), label: label, keyboard: TextInputType.number, ltr: true);
      case 'email':
        input = AppEmailField(controller: answers.ctrl(k), label: label);
      case 'phone':
        input = AppPhoneField(controller: answers.ctrl(k), label: label);
      case 'select':
        input = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (val, lbl) in opts)
              ChoiceChip(
                  label: Text(lbl, style: const TextStyle(fontFamily: 'tajawal')),
                  selected: '${v[k] ?? ''}' == val,
                  onSelected: (_) => put(val)),
          ]),
        ]);
      case 'multiselect':
        final cur = {...((v[k] as List?) ?? const []).map((e) => '$e')};
        input = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (val, lbl) in opts)
              FilterChip(
                  label: Text(lbl, style: const TextStyle(fontFamily: 'tajawal')),
                  selected: cur.contains(val),
                  onSelected: (on) => put(on ? [...cur, val] : cur.where((x) => x != val).toList())),
          ]),
        ]);
      case 'checkbox':
        input = CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: v[k] == true,
          onChanged: (x) => put(x == true),
          title: title(),
          controlAffinity: ListTileControlAffinity.leading,
        );
      case 'date':
        input = ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(fieldIcons['date'], color: c.primary),
          title: title(),
          subtitle: Text('${v[k] ?? t('اختر التاريخ', 'Pick a date')}'),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                firstDate: DateTime(1950),
                lastDate: DateTime(2100),
                initialDate: DateTime.tryParse('${v[k] ?? ''}') ?? DateTime.now());
            if (d != null) put(d.toIso8601String().substring(0, 10));
          },
        );
      case 'file':
        final files = asMapList(v[k]);
        input = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(),
          Wrap(spacing: 6, children: [
            for (final x in files) InputChip(label: Text('${x['name']}'), onDeleted: () => put(files.where((y) => y != x).toList())),
            if (onUpload != null)
              ActionChip(
                avatar: const Icon(Icons.attach_file_rounded, size: 16),
                label: Text(t('إرفاق ملف', 'Attach a file')),
                onPressed: () async {
                  final up = await onUpload!();
                  if (up != null) put([...files, {'name': up['name'], 'url': up['url']}]);
                },
              ),
          ]),
        ]);
      default:
        input = Field(controller: answers.ctrl(k), label: label);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        input,
        if (help.isNotEmpty) Text(help, style: orgText(context, size: 11.5, color: c.textLight)),
        if (!required && help.isEmpty && f['type'] != 'checkbox')
          Text(t('اختياري', 'Optional'), style: orgText(context, size: 11, color: c.textLight)),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(error!, style: orgText(context, size: 12, color: c.danger)),
          ),
      ]),
    );
  }
}
