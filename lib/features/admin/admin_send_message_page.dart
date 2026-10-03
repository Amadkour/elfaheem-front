// features/admin/admin_send_message_page.dart
//
// Admin / super-admin broadcast: choose WHO (all students · a course's students · one student)
// and HOW it appears (e-mail · notification · dialog · dialog with a button that opens a module).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'admin_common.dart';

class AdminSendMessagePage extends StatefulWidget {
  const AdminSendMessagePage({super.key});

  @override
  State<AdminSendMessagePage> createState() => _AdminSendMessagePageState();
}

class _AdminSendMessagePageState extends State<AdminSendMessagePage> {
  final _api = ApiClient();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _label = TextEditingController();

  String _audience = 'all_students'; // all_students | course | student
  String _display = 'notification'; //  email | notification | dialog | dialog_action
  String _module = 'course'; //          profile | course | notifications | my_courses | subscription
  Map<String, dynamic>? _course; //      audience = course, or the course a button opens
  Map<String, dynamic>? _student;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _needsCourseForButton => _display == 'dialog_action' && _module == 'course';

  Future<void> _pick({required bool course}) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickerSheet(
        api: _api,
        title: course ? t('اختر الكورس', 'Choose a course') : t('اختر الطالب', 'Choose a student'),
        path: course ? '/api/v1/admin/courses' : '/api/v1/admin/users',
        extra: course ? const {} : const {'role': 'student'},
        subtitleKey: course ? null : 'gmail',
      ),
    );
    if (picked != null) setState(() => course ? _course = picked : _student = picked);
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      return _snack(t('اكتب العنوان والرسالة', 'Enter a title and a message'));
    }
    if (_audience == 'course' && _course == null) return _snack(t('اختر الكورس', 'Choose a course'));
    if (_audience == 'student' && _student == null) return _snack(t('اختر الطالب', 'Choose a student'));
    if (_needsCourseForButton && _course == null) return _snack(t('اختر الكورس الذي يفتحه الزر', 'Choose the course the button opens'));

    final ok = await confirm(context, message: t('إرسال الرسالة الآن؟', 'Send this message now?'));
    if (!ok) return;

    setState(() => _sending = true);
    try {
      final r = await _api.post('/api/v1/admin/messages', body: {
        'audience': _audience,
        if (_audience == 'course') 'course_id': _course!['id'],
        if (_audience == 'student') 'student_id': _student!['id'],
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'display_type': _display,
        if (_display == 'dialog_action') ...{
          'action_module': _module,
          if (_module == 'course') 'action_target_id': _course!['id'],
          if (_label.text.trim().isNotEmpty) 'action_label': _label.text.trim(),
        },
      });
      _snack(t('تم الإرسال إلى ${r['recipients']} مستخدم', 'Sent to ${r['recipients']} users'));
      _title.clear();
      _body.clear();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(s, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
        );

    Widget chips<T>(List<(T, String)> opts, T value, ValueChanged<T> on) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in opts)
            ChoiceChip(label: Text(o.$2), selected: value == o.$1, onSelected: (_) => on(o.$1)),
        ]);

    Widget pickerBtn(String text, IconData icon, VoidCallback on) =>
        OutlinedButton.icon(onPressed: on, icon: Icon(icon), label: Text(text, overflow: TextOverflow.ellipsis));

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(t('إرسال رسالة', 'Send a message'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              label(t('إلى من؟', 'Send to')),
              chips<String>([
                ('all_students', t('كل الطلاب', 'All students')),
                ('course', t('طلاب كورس', 'A course')),
                ('student', t('طالب محدد', 'One student')),
              ], _audience, (v) => setState(() => _audience = v)),
              if (_audience == 'course') ...[
                const SizedBox(height: 8),
                pickerBtn(_course?['name']?.toString() ?? t('اختر الكورس', 'Choose a course'), Icons.menu_book_rounded, () => _pick(course: true)),
              ],
              if (_audience == 'student') ...[
                const SizedBox(height: 8),
                pickerBtn(_student?['name']?.toString() ?? t('اختر الطالب', 'Choose a student'), Icons.person_search_rounded, () => _pick(course: false)),
              ],
              label(t('طريقة العرض', 'How it appears')),
              chips<String>([
                ('email', t('بريد إلكتروني', 'E-mail')),
                ('notification', t('إشعار', 'Notification')),
                ('dialog', t('نافذة بدون زر', 'Dialog')),
                ('dialog_action', t('نافذة مع زر', 'Dialog + button')),
              ], _display, (v) => setState(() => _display = v)),
              if (_display == 'dialog_action') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _module,
                  decoration: InputDecoration(labelText: t('الزر يفتح', 'Button opens'), border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: 'course', child: Text(t('صفحة الكورس', 'Course profile'))),
                    DropdownMenuItem(value: 'profile', child: Text(t('الملف الشخصي', 'Profile'))),
                    DropdownMenuItem(value: 'my_courses', child: Text(t('كورساتي', 'My courses'))),
                    DropdownMenuItem(value: 'notifications', child: Text(t('الإشعارات', 'Notifications'))),
                    DropdownMenuItem(value: 'subscription', child: Text(t('الاشتراك', 'Subscription'))),
                  ],
                  onChanged: (v) => setState(() => _module = v ?? 'course'),
                ),
                if (_needsCourseForButton && _audience != 'course') ...[
                  const SizedBox(height: 8),
                  pickerBtn(_course?['name']?.toString() ?? t('اختر الكورس الذي يفتحه الزر', 'Choose the course it opens'),
                      Icons.menu_book_rounded, () => _pick(course: true)),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _label,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: t('نص الزر (اختياري)', 'Button text (optional)'), border: const OutlineInputBorder()),
                ),
              ],
              label(t('الرسالة', 'Message')),
              TextField(
                controller: _title,
                maxLength: 255,
                decoration: InputDecoration(labelText: t('العنوان', 'Title'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                minLines: 4,
                maxLines: 10,
                maxLength: 4000,
                decoration: InputDecoration(labelText: t('نص الرسالة', 'Message'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: Text(t('إرسال', 'Send')),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Searchable list for the admin endpoints that return `{items: [{id, name, ...}]}`.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.api, required this.title, required this.path, required this.extra, this.subtitleKey});
  final ApiClient api;
  final String title, path;
  final Map<String, dynamic> extra;
  final String? subtitleKey;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get(widget.path, queryParams: {
        ...widget.extra,
        if (_q.text.trim().isNotEmpty) 'search': _q.text.trim(),
        'size': 30,
      });
      _items = ((r is Map ? r['items'] : null) as List? ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            const SizedBox(height: 12),
            Text(widget.title, style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 16)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
                  hintText: t('بحث', 'Search'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        return ListTile(
                          title: Text('${it['name'] ?? it['title'] ?? it['id']}'),
                          subtitle: widget.subtitleKey == null ? null : Text('${it[widget.subtitleKey] ?? ''}'),
                          onTap: () => Navigator.pop(context, {'id': it['id'], 'name': it['name'] ?? it['title']}),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
}
