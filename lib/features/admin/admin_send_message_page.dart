// features/admin/admin_send_message_page.dart
//
// Admin / super-admin broadcast: choose WHO (all students · a course's students · one student)
// and HOW it appears (e-mail · notification · dialog · dialog with a button that opens a module).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
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
  String _display =
      'notification'; //  email | notification | dialog | dialog_action
  String _module =
      'course'; //          profile | course | notifications | my_courses | subscription
  Map<String, dynamic>?
  _course; //      audience = course, or the course a button opens
  Map<String, dynamic>? _student;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _needsCourseForButton =>
      _display == 'dialog_action' && _module == 'course';

  Future<void> _pick({required bool course}) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickerSheet(
        api: _api,
        title: course
            ? 'admin_choose_a_course'.tr
            : 'admin_choose_a_student'.tr,
        path: course ? '/api/v1/admin/courses' : '/api/v1/admin/users',
        extra: course ? const {} : const {'role': 'student'},
        subtitleKey: course ? null : 'gmail',
      ),
    );
    if (picked != null)
      setState(() => course ? _course = picked : _student = picked);
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      return _snack('admin_enter_a_title_and_a_message'.tr);
    }
    if (_audience == 'course' && _course == null)
      return _snack('admin_choose_a_course'.tr);
    if (_audience == 'student' && _student == null)
      return _snack('admin_choose_a_student'.tr);
    if (_needsCourseForButton && _course == null)
      return _snack(
        'admin_choose_the_course_the_button_opens'.tr,
      );

    final ok = await confirm(
      context,
      message: 'admin_send_this_message_now'.tr,
    );
    if (!ok) return;

    setState(() => _sending = true);
    try {
      final r = await _api.post(
        '/api/v1/admin/messages',
        body: {
          'audience': _audience,
          if (_audience == 'course') 'course_id': _course!['id'],
          if (_audience == 'student') 'student_id': _student!['id'],
          'title': _title.text.trim(),
          'body': _body.text.trim(),
          'display_type': _display,
          if (_display == 'dialog_action') ...{
            'action_module': _module,
            if (_module == 'course') 'action_target_id': _course!['id'],
            if (_label.text.trim().isNotEmpty)
              'action_label': _label.text.trim(),
          },
        },
      );
      _snack(
        trp('admin_sent_to_users', {'recipients': r['recipients']}),
      );
      _title.clear();
      _body.clear();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        s,
        style: TextStyle(
          fontFamily: 'tajawal',
          fontWeight: FontWeight.w800,
          color: c.textDark,
        ),
      ),
    );

    Widget chips<T>(List<(T, String)> opts, T value, ValueChanged<T> on) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in opts)
              ChoiceChip(
                label: Text(o.$2),
                selected: value == o.$1,
                onSelected: (_) => on(o.$1),
              ),
          ],
        );

    Widget pickerBtn(String text, IconData icon, VoidCallback on) =>
        OutlinedButton.icon(
          onPressed: on,
          icon: Icon(icon),
          label: Text(text, overflow: TextOverflow.ellipsis),
        );

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'send_message'.tr),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            label('admin_send_to'.tr),
            chips<String>(
              [
                ('all_students', 'admin_all_students'.tr),
                ('course', 'admin_a_course'.tr),
                ('student', 'admin_one_student'.tr),
              ],
              _audience,
              (v) => setState(() => _audience = v),
            ),
            if (_audience == 'course') ...[
              const SizedBox(height: 8),
              pickerBtn(
                _course?['name']?.toString() ??
                    'admin_choose_a_course'.tr,
                Icons.menu_book_rounded,
                () => _pick(course: true),
              ),
            ],
            if (_audience == 'student') ...[
              const SizedBox(height: 8),
              pickerBtn(
                _student?['name']?.toString() ??
                    'admin_choose_a_student'.tr,
                Icons.person_search_rounded,
                () => _pick(course: false),
              ),
            ],
            label('admin_how_it_appears'.tr),
            chips<String>(
              [
                ('email', 'admin_e_mail'.tr),
                ('notification', 'admin_notification'.tr),
                ('dialog', 'admin_dialog'.tr),
                ('dialog_action', 'admin_dialog_button'.tr),
              ],
              _display,
              (v) => setState(() => _display = v),
            ),
            if (_display == 'dialog_action') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _module,
                decoration: InputDecoration(
                  labelText: 'admin_button_opens'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'course',
                    child: Text('admin_course_profile'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'profile',
                    child: Text('admin_profile'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'my_courses',
                    child: Text('admin_my_courses'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'notifications',
                    child: Text('admin_notifications'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'subscription',
                    child: Text('admin_subscription'.tr),
                  ),
                ],
                onChanged: (v) => setState(() => _module = v ?? 'course'),
              ),
              if (_needsCourseForButton && _audience != 'course') ...[
                const SizedBox(height: 8),
                pickerBtn(
                  _course?['name']?.toString() ??
                      'admin_choose_the_course_it_opens'.tr,
                  Icons.menu_book_rounded,
                  () => _pick(course: true),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: 'admin_button_text_optional'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            label('admin_message_2'.tr),
            TextField(
              controller: _title,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: 'video_title'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 10,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: 'admin_message'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text('lk_send_btn'.tr),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable list for the admin endpoints that return `{items: [{id, name, ...}]}`.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.api,
    required this.title,
    required this.path,
    required this.extra,
    this.subtitleKey,
  });

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
      final r = await widget.api.get(
        widget.path,
        queryParams: {
          ...widget.extra,
          if (_q.text.trim().isNotEmpty) 'search': _q.text.trim(),
          'size': 30,
        },
      );
      _items = ((r is Map ? r['items'] : null) as List? ?? [])
          .cast<Map<String, dynamic>>();
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
      child: Column(
        children: [
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: const TextStyle(
              fontFamily: 'tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _load,
                ),
                hintText: 'search'.tr,
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
                        subtitle: widget.subtitleKey == null
                            ? null
                            : Text('${it[widget.subtitleKey] ?? ''}'),
                        onTap: () => Navigator.pop(context, {
                          'id': it['id'],
                          'name': it['name'] ?? it['title'],
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
