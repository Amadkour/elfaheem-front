// features/admin/admin_required_documents_page.dart
// Admin: documents teachers must upload at registration (additional_register_screen).
import 'package:flutter/material.dart';

import '../../core/api_client.dart';

class AdminRequiredDocumentsPage extends StatefulWidget {
  const AdminRequiredDocumentsPage({super.key});

  @override
  State<AdminRequiredDocumentsPage> createState() => _AdminRequiredDocumentsPageState();
}

class _AdminRequiredDocumentsPageState extends State<AdminRequiredDocumentsPage> {
  static const _base = '/api/v1/admin/required-documents';
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get(_base);
      _items = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _reorder(int from, int to) async {
    if (to > from) to--;
    final it = _items.removeAt(from);
    _items.insert(to, it);
    setState(() {});
    try {
      await _api.post('$_base/reorder', body: {'ids': _items.map((e) => e['id']).toList()});
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _toggle(Map<String, dynamic> d, String key, bool v) async {
    try {
      await _api.put('$_base/${d['id']}', body: {key: v});
      setState(() => d[key] = v);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this document type?'),
        content: const Text('If teachers already uploaded it, it is only disabled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('$_base/${d['id']}');
      await _load();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _edit([Map<String, dynamic>? d]) async {
    final titleAr = TextEditingController(text: d?['title_ar'] ?? '');
    final titleEn = TextEditingController(text: d?['title_en'] ?? '');
    final descAr = TextEditingController(text: d?['description_ar'] ?? '');
    final descEn = TextEditingController(text: d?['description_en'] ?? '');
    final icon = TextEditingController(text: d?['icon_name'] ?? 'description');
    bool required = d?['is_required'] ?? true;
    bool active = d?['is_active'] ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(d == null ? 'New document' : 'Edit document'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: titleAr, decoration: const InputDecoration(labelText: 'Title (Arabic) *')),
              TextField(controller: titleEn, decoration: const InputDecoration(labelText: 'Title (English)')),
              TextField(controller: descAr, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (Arabic)')),
              TextField(controller: descEn, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (English)')),
              TextField(controller: icon, decoration: const InputDecoration(labelText: 'Icon name (e.g. badge, school)')),
              SwitchListTile(
                  title: const Text('Required'),
                  value: required,
                  onChanged: (v) => setD(() => required = v)),
              SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setD(() => active = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || titleAr.text.trim().isEmpty) return;
    String? n(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();
    final body = {
      'title_ar': titleAr.text.trim(),
      'title_en': n(titleEn),
      'description_ar': n(descAr),
      'description_en': n(descEn),
      'icon_name': n(icon) ?? 'description',
      'is_required': required,
      'is_active': active,
    };
    try {
      if (d == null) {
        await _api.post(_base, body: body);
      } else {
        await _api.put('$_base/${d['id']}', body: body);
      }
      await _load();
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher required documents')),
      floatingActionButton:
          FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No documents required. Teachers finish registration right after their profile.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _items.length,
                  onReorder: _reorder,
                  itemBuilder: (c, i) {
                    final d = _items[i];
                    return ListTile(
                      key: ValueKey(d['id']),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(d['title_ar'] ?? ''),
                      subtitle: Text('${d['title_en'] ?? ''}  ·  ${d['uploads']} uploads'),
                      onTap: () => _edit(d),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Tooltip(
                          message: 'Required',
                          child: Switch(
                              value: d['is_required'] == true,
                              onChanged: (v) => _toggle(d, 'is_required', v)),
                        ),
                        Tooltip(
                          message: 'Active',
                          child: Checkbox(
                              value: d['is_active'] == true,
                              onChanged: (v) => _toggle(d, 'is_active', v ?? true)),
                        ),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(d)),
                      ]),
                    );
                  },
                ),
    );
  }
}
