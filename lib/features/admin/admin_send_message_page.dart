// features/admin/admin_send_message_page.dart
//
// Admin / super-admin broadcast: choose WHO (all students · a course's students · one student)
// and HOW it appears (e-mail · notification · dialog · dialog with a button that opens a module).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../config/app_config.dart';
import 'admin_common.dart';
import 'admin_page.dart';
import 'adm_kit.dart' show AdmPage;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_username.dart';

class AdminSendMessagePage extends StatefulWidget {
  const AdminSendMessagePage({super.key, this.student, this.teacher});

  /// Opens addressed to this one student (`{id, name}`), e.g. from their detail.
  final Map<String, dynamic>? student;

  /// Opens already addressed to this teacher (`{id, name}`, the Message action of a teacher's detail).
  final Map<String, dynamic>? teacher;

  @override
  State<AdminSendMessagePage> createState() => _AdminSendMessagePageState();
}

class _AdminSendMessagePageState extends State<AdminSendMessagePage> {
  final _api = ApiClient();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _label = TextEditingController();
  final _customModule = TextEditingController();

  late String _audience = widget.student == null ? 'all_students' : 'student'; // all_students | course | student | all_teachers | teacher
  String _display = 'notification'; //  email | notification | dialog | dialog_action
  String _module = 'course'; // profile | course | notifications | my_courses | subscription | __custom__
  Map<String, dynamic>? _course; //      audience = course, or the course a button opens
  late Map<String, dynamic>? _student = widget.student;
  Map<String, dynamic>? _teacher;
  bool _sending = false;

  /// "Will reach N people": the total of the audience, null while unknown / loading (never blocks sending).
  int? _reach;
  int _reachReq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.teacher != null) {
      _audience = 'teacher';
      _teacher = widget.teacher;
    }
    _refreshReach();
  }

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

  bool get _needsCourseForButton => !_toTeachers && _display == 'dialog_action' && _module == 'course';

  bool get _dirty => _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;

  /// The size of the audience from data the existing lists already return (the users list's `total`, the picked
  /// course's `students_count`): no extra server route.
  Future<void> _refreshReach() async {
    final my = ++_reachReq;
    int? n;
    switch (_audience) {
      case 'student':
        n = _student == null ? null : 1;
      case 'teacher':
        n = _teacher == null ? null : 1;
      case 'course':
        n = _course == null ? null : (_course!['students'] as num?)?.toInt();
      default:
        setState(() => _reach = null);
        try {
          final r = await _api.get('/api/v1/admin/users',
              queryParams: {'role': _audience == 'all_teachers' ? 'teacher' : 'student', 'size': 1});
          n = r is Map ? (r['total'] as num?)?.toInt() : null;
        } catch (_) {
          n = null;
        }
    }
    if (mounted && my == _reachReq) setState(() => _reach = n);
  }

  Future<void> _pick({required bool course, bool teacher = false}) async {
    final picked = await showAppSheet<Map<String, dynamic>>(
      context,
      (_) => _PickerSheet(
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
      _refreshReach();
    }
  }

  Future<void> _send() async {
    if (_sending) return;
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

    final n = _reach;
    final ok = await appConfirm(
      context,
      message: n == null ? 'admin_send_this_message_now'.tr : '${_reachText(n)}\n${'admin_send_this_message_now'.tr}',
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
            'action_module': _isCustomModule ? _customModule.text.trim() : _module,
            if (_module == 'course') 'action_target_id': _course!['id'],
            if (_label.text.trim().isNotEmpty) 'action_label': _label.text.trim(),
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
      _snack(e.message, error: true);
    } catch (_) {
      _snack('admin_send_failed'.tr, error: true); // network error etc. — used to leave the button silently idle
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setAudience(String v) {
    setState(() {
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
    });
    _refreshReach();
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    showAppNotice(m, error: error);
  }

  String _reachText(int n) => t(
        'ستصل إلى ${countText(n, ar1: 'شخص واحد', ar2: 'شخصين', arFew: '{n} أشخاص', arMany: '{n} شخصًا', en1: '1 person', en: '{n} people')}',
        'Will reach ${countText(n, ar1: '', arFew: '', en1: '1 person', en: '{n} people')}',
      );

  @override
  Widget build(BuildContext context) {
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs),
          child: Text(s, style: AppType.section(context)),
        );

    Widget chips<T>(List<(T, String)> opts, T value, ValueChanged<T> on) => Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final o in opts) AppChoiceChip(label: o.$2, selected: value == o.$1, onTap: () => on(o.$1)),
          ],
        );

    Widget pickerBtn(String text, IconData icon, VoidCallback on) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(label: text, icon: icon, onPressed: on),
        );

    final reach = _reach;
    return AdmPage(
      kicker: 'admin_group_people'.tr,
      width: AppWidth.reading,
      refreshable: false,
      title: 'send_message'.tr,
      headline: 'a1_msg_head'.tr,
      subtitle: 'a1_msg_line'.tr,
      icon: Icons.mark_email_unread_rounded,
      dirty: _dirty && !_sending,
      primaryAction: AppButton.primary(
        label: 'lk_send_btn'.tr,
        icon: Icons.send_rounded,
        busy: _sending,
        onPressed: _sending ? null : _send,
      ),
      body: ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          label('a1_msg_who'.tr),
          // redesign A1 (AdmPeople message): the audience as option tiles (glyph, name), two per row
          Builder(builder: (context) {
            final kit = context.colors.kit;
            final opts = [
              ('all_students', 'admin_all_students'.tr, Icons.groups_rounded, kit.accent(AppAccent.sky)),
              ('course', 'a1_course_students'.tr, Icons.menu_book_rounded, kit.warmTone),
              ('student', 'admin_one_student'.tr, Icons.person_rounded, kit.ok),
              ('all_teachers', 'admin_all_teachers'.tr, Icons.school_rounded, kit.accent(AppAccent.grape)),
              ('teacher', 'admin_one_teacher'.tr, Icons.co_present_rounded, kit.live),
            ];
            final rows = <Widget>[];
            for (var i = 0; i < opts.length; i += 2) {
              rows.add(Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Row(children: [
                  for (var j = i; j < i + 2; j++) ...[
                    if (j > i) AppSpace.gapXs,
                    Expanded(
                      child: j < opts.length
                          ? AppTile(
                              key: ValueKey('admin.msg.audience.${opts[j].$1}'),
                              icon: opts[j].$3,
                              tone: opts[j].$4,
                              title: opts[j].$2,
                              selected: _audience == opts[j].$1,
                              onTap: () => _setAudience(opts[j].$1),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ]),
              ));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
          }),
          if (_audience == 'course') ...[
            AppSpace.gapXs,
            pickerBtn(_course?['name']?.toString() ?? 'admin_choose_a_course'.tr, Icons.menu_book_rounded, () => _pick(course: true)),
          ],
          if (_audience == 'student') ...[
            AppSpace.gapXs,
            pickerBtn(_student?['name']?.toString() ?? 'admin_choose_a_student'.tr, Icons.person_search_rounded, () => _pick(course: false)),
          ],
          if (_audience == 'teacher') ...[
            AppSpace.gapXs,
            pickerBtn(_teacher?['name']?.toString() ?? 'admin_choose_a_teacher'.tr, Icons.person_pin_rounded, () => _pick(course: false, teacher: true)),
          ],
          if (reach != null) ...[
            AppSpace.gapXs,
            Row(children: [
              Icon(Icons.groups_rounded, size: AppIconSize.md, color: context.colors.primary),
              AppSpace.gapXs,
              Flexible(child: Text(_reachText(reach), style: AppType.meta(context))),
            ]),
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
            AppSpace.gapSm,
            AppDropdown<String>(
              key: ValueKey('module_$_toTeachers'),
              initialValue: _module,
              decoration: InputDecoration(labelText: 'admin_button_opens'.tr),
              items: [
                if (!_toTeachers) DropdownMenuItem(value: 'course', child: Text('admin_course_profile'.tr)),
                DropdownMenuItem(value: 'profile', child: Text('admin_profile'.tr)),
                if (!_toTeachers) DropdownMenuItem(value: 'my_courses', child: Text('admin_my_courses'.tr)),
                DropdownMenuItem(value: 'notifications', child: Text('admin_notifications'.tr)),
                if (!_toTeachers) DropdownMenuItem(value: 'subscription', child: Text('admin_subscription'.tr)),
                DropdownMenuItem(value: _customModuleValue, child: Text('admin_custom_module'.tr)),
              ],
              onChanged: (v) => setState(() {
                _module = v ?? 'course';
                if (!_isCustomModule) _customModule.clear();
              }),
            ),
            if (_isCustomModule) ...[
              AppSpace.gapSm,
              TextField(
                controller: _customModule,
                maxLength: 255,
                decoration: InputDecoration(
                  labelText: 'admin_custom_module_name'.tr,
                  hintText: 'admin_custom_module_name_hint'.tr,
                ),
              ),
            ],
            if (_needsCourseForButton && _audience != 'course') ...[
              AppSpace.gapXs,
              pickerBtn(_course?['name']?.toString() ?? 'admin_choose_the_course_it_opens'.tr, Icons.menu_book_rounded, () => _pick(course: true)),
            ],
            AppSpace.gapSm,
            TextField(
              controller: _label,
              maxLength: 80,
              decoration: InputDecoration(labelText: 'admin_button_text_optional'.tr),
            ),
          ],
          label('admin_message_2'.tr),
          TextField(
            controller: _title,
            maxLength: 255,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t('العنوان', 'Title')),
          ),
          AppSpace.gapXs,
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 10,
            maxLength: 4000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'admin_message'.tr),
          ),
        ],
      ),
    );
  }
}

/// Searchable list for the admin endpoints that return `{items: [{id, name, ...}]}`; more pages load as it scrolls.
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
  static const _size = 30;
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  int _page = 1;
  int _total = 0;
  int _req = 0;
  final _q = TextEditingController();
  final _scroll = ScrollController();
  final _debounce = Debouncer();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 200) _more();
    });
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<Map?> _fetch(int page) async {
    final r = await widget.api.get(
      widget.path,
      queryParams: {
        ...widget.extra,
        if (_q.text.trim().isNotEmpty) 'search': _q.text.trim(),
        'page': page,
        'size': _size,
      },
    );
    return r is Map ? r : null;
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _failed = false;
      _page = 1;
    });
    try {
      final r = await _fetch(1);
      if (req != _req) return;
      _items
        ..clear()
        ..addAll(((r?['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      _total = (r?['total'] as num?)?.toInt() ?? _items.length;
    } catch (_) {
      if (req != _req) return;
      _items.clear();
      _failed = true;
    }
    if (mounted && req == _req) setState(() => _loading = false);
  }

  Future<void> _more() async {
    if (_loading || _loadingMore || _failed || _items.length >= _total) return;
    final req = _req;
    setState(() => _loadingMore = true);
    try {
      final r = await _fetch(_page + 1);
      if (req != _req) return;
      final more = ((r?['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e));
      _page++;
      _items.addAll(more);
      if (more.isEmpty) _total = _items.length;
    } catch (_) {
      // the rows already loaded stay; scrolling again retries
    }
    if (mounted && req == _req) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final isCourse = widget.subtitleKey == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSheetHeader(widget.title),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
              child: AppSearchField(
                hint: 'search'.tr,
                onChanged: (_) => _debounce.run(_load),
                onSubmitted: (_) => _debounce.flush(_load),
              ),
            ),
            Expanded(
              child: _loading
                  ? const AppListSkeleton()
                  : _failed
                      ? Center(child: AppErrorState(message: 'admin_could_not_load_data'.tr, onRetry: _load))
                      : _items.isEmpty
                          ? AppEmpty(icon: Icons.search_off_rounded, title: 'admin_nothing_here_yet'.tr)
                          : ListView.builder(
                              controller: _scroll,
                              itemCount: _items.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i >= _items.length) {
                                  return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 1));
                                }
                                final it = _items[i];
                                final uname = usernameFrom(it);
                                return ListTile(
                                  title: Text('${it['name'] ?? it['title'] ?? it['id']}'),
                                  subtitle: isCourse
                                      ? (uname == null ? null : AppUsernameLine(uname))
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AppUsernameLine(uname),
                                            Text('${it[widget.subtitleKey] ?? ''}'),
                                          ],
                                        ),
                                  onTap: () => Navigator.pop(context, {
                                    'id': it['id'],
                                    'name': it['name'] ?? it['title'],
                                    if (isCourse) 'students': it['students_count'],
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
}
