// features/admin/admin_send_message_page.dart
//
// Admin / super-admin broadcast: choose WHO (all students · a course's students · one student)
// and HOW it appears (e-mail · notification · dialog · dialog with a button that opens a module).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_premium_widgets.dart';
import '../../utils/widget/primary_button.dart';

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
  final _customModule = TextEditingController();

  String _audience =
      'all_students'; // all_students | course | student | all_teachers | teacher
  String _display =
      'notification'; //  email | notification | dialog | dialog_action
  String _module =
      'course'; // profile | course | notifications | my_courses | subscription | __custom__
  Map<String, dynamic>?
  _course; //      audience = course, or the course a button opens
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _teacher;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _label.dispose();
    _customModule.dispose();
    super.dispose();
  }

  bool get _toTeachers => _audience == 'all_teachers' || _audience == 'teacher';

  /// Teachers have no "course page / my courses / subscription" button targets (student concepts).
  static const _teacherModules = ['profile', 'notifications'];
  static const _customModuleValue = '__custom__';

  bool get _isCustomModule => _module == _customModuleValue;

  bool get _needsCourseForButton =>
      !_toTeachers && _display == 'dialog_action' && _module == 'course';

  Future<void> _pick({required bool course, bool teacher = false}) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickerSheet(
        api: _api,
        title: course
            ? 'admin_choose_a_course'.tr
            : teacher
            ? 'admin_choose_a_teacher'.tr
            : 'admin_choose_a_student'.tr,
        path: course ? '/api/v1/admin/courses' : '/api/v1/admin/users',
        extra: course ? const {} : {'role': teacher ? 'teacher' : 'student'},
        subtitleKey: course ? null : 'gmail',
      ),
    );
    if (picked != null) {
      setState(() {
        if (course) {
          _course = picked;
        } else if (teacher) {
          _teacher = picked;
        } else {
          _student = picked;
        }
      });
    }
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      return _snack('admin_enter_a_title_and_a_message'.tr);
    }
    if (_audience == 'course' && _course == null) {
      return _snack('admin_choose_a_course'.tr);
    }
    if (_audience == 'student' && _student == null) {
      return _snack('admin_choose_a_student'.tr);
    }
    if (_audience == 'teacher' && _teacher == null) {
      return _snack('admin_choose_a_teacher'.tr);
    }
    if (_needsCourseForButton && _course == null) {
      return _snack('admin_choose_the_course_the_button_opens'.tr);
    }

    if (_isCustomModule && _customModule.text.trim().isEmpty) {
      return _snack('admin_enter_custom_module_name'.tr);
    }

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
          if (_audience == 'teacher') 'teacher_id': _teacher!['id'],
          'title': _title.text.trim(),
          'body': _body.text.trim(),
          'display_type': _display,
          if (_display == 'dialog_action') ...{
            'action_module':
                _isCustomModule ? _customModule.text.trim() : _module,
            if (_module == 'course') 'action_target_id': _course!['id'],
            if (_label.text.trim().isNotEmpty)
              'action_label': _label.text.trim(),
          },
        },
      );
      final recipients = r is Map ? (r['recipients'] as num?)?.toInt() ?? 0 : 0;
      if (recipients == 0) {
        // nothing was delivered (empty course / no matching students) — do not pretend it worked
        _snack('admin_msg_no_recipients'.tr);
        return;
      }
      _snack(trp('admin_sent_to_users', {'recipients': recipients}));
      _title.clear();
      _body.clear();
      _label.clear();
      _customModule.clear();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(
        'admin_send_failed'.tr,
      ); // network error etc. — used to leave the button silently idle
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

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
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PremiumHero(
            icon: Icons.campaign_rounded,
            colors: AdminPalette.blue,
            title: 'send_message'.tr,
            subtitle: 'svc_send_message_d'.tr,
          ),
          label('admin_send_to'.tr),
          chips<String>(
            [
              ('all_students', 'admin_all_students'.tr),
              ('course', 'admin_a_course'.tr),
              ('student', 'admin_one_student'.tr),
              ('all_teachers', 'admin_all_teachers'.tr),
              ('teacher', 'admin_one_teacher'.tr),
            ],
            _audience,
            (v) => setState(() {
              _audience = v;
              if (_toTeachers) {
                // teachers cannot open a course / my-courses / subscription → fall back to a valid target
                _course = null;
                if (!_teacherModules.contains(_module)) _module = 'profile';
              } else if (v == 'student') {
                // the course picked for a "student" / "all" message must not silently become the audience
                if (!(_display == 'dialog_action' && _module == 'course')) {
                  _course = null;
                }
              }
            }),
          ),
          if (_audience == 'course') ...[
            const SizedBox(height: 8),
            pickerBtn(
              _course?['name']?.toString() ?? 'admin_choose_a_course'.tr,
              Icons.menu_book_rounded,
              () => _pick(course: true),
            ),
          ],
          if (_audience == 'student') ...[
            const SizedBox(height: 8),
            pickerBtn(
              _student?['name']?.toString() ?? 'admin_choose_a_student'.tr,
              Icons.person_search_rounded,
              () => _pick(course: false),
            ),
          ],
          if (_audience == 'teacher') ...[
            const SizedBox(height: 8),
            pickerBtn(
              _teacher?['name']?.toString() ?? 'admin_choose_a_teacher'.tr,
              Icons.person_pin_rounded,
              () => _pick(course: false, teacher: true),
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
              key: ValueKey('module_$_toTeachers'),
              initialValue: _module,
              decoration: InputDecoration(
                labelText: 'admin_button_opens'.tr,
                border: const OutlineInputBorder(),
              ),
              items: [
                if (!_toTeachers)
                  DropdownMenuItem(
                    value: 'course',
                    child: Text('admin_course_profile'.tr),
                  ),
                DropdownMenuItem(
                  value: 'profile',
                  child: Text('admin_profile'.tr),
                ),
                if (!_toTeachers)
                  DropdownMenuItem(
                    value: 'my_courses',
                    child: Text('admin_my_courses'.tr),
                  ),
                DropdownMenuItem(
                  value: 'notifications',
                  child: Text('admin_notifications'.tr),
                ),
                if (!_toTeachers)
                  DropdownMenuItem(
                    value: 'subscription',
                    child: Text('admin_subscription'.tr),
                  ),
                DropdownMenuItem(
                  value: _customModuleValue,
                  child: Text('admin_custom_module'.tr),
                ),
              ],
              onChanged: (v) => setState(() {
                _module = v ?? 'course';
                if (!_isCustomModule) _customModule.clear();
              }),
            ),
            if (_isCustomModule) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customModule,
                maxLength: 255,
                decoration: InputDecoration(
                  labelText: 'admin_custom_module_name'.tr,
                  hintText: 'admin_custom_module_name_hint'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
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
          PrimaryButton(
            isLoading: _sending,
            label: 'lk_send_btn'.tr,
            icon: Icons.send_rounded,
            onPressed: _sending ? null : _send,
          ),
        ],
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
  bool _failed = false;
  int _req = 0;
  final _q = TextEditingController();
  final _debounce = Debouncer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _failed = false;
    });
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
      _failed = true;
    }
    if (mounted && req == _req) setState(() => _loading = false);
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
              textInputAction: TextInputAction.search,
              // 1 s after the last key → one request; Enter = now
              onChanged: (_) => _debounce.run(_load),
              onSubmitted: (_) => _debounce.flush(_load),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _debounce.flush(_load),
                ),
                hintText: 'search'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppLoadingIndicator())
                : _failed
                ? ErrorRetry(
                    message: 'admin_could_not_load_data'.tr,
                    onRetry: _load,
                  )
                : _items.isEmpty
                ? EmptyState('admin_nothing_here_yet'.tr)
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
