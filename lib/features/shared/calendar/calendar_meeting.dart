// lib/features/shared/calendar/calendar_meeting.dart — create a meeting, see / answer / manage one, and turn a
// complaint into a meeting. Calls: calendar_api.dart.
//
//   showMeetingForm     quick-add sheet: title · day & time · online/offline · private or with people / departments /
//                       the person responsible / a course group; a live "who is busy then" check before sending
//   showMeetingSheet    details: time, place, join (online, the live-session room), invitees with their answer;
//                       invitee: accept · decline · propose another time; organizer: accept a proposal, move, cancel
//   showComplaintMeetingSheet   one tap from a complaint: a meeting with its sender (both calendars + notification)
//   startQuickMeeting   "Meet now" (live-rooms-spec §7): POST …/meetings/quick → the pre-join page joins by itself
//   openMeetingRoom     the one way into a meeting's room (detail → PreJoinPage); a 402 live_plan_required offers the
//                       student live-meeting plan and retries once (§8)
//
// Students (a role outside the server's staff list) create online, private meetings only (§8).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/live/live_lobby_sheets.dart' show showLobbySheet, showShareLinkSheet;
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/prejoin.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt;
// [meeting-recording] the latest recording's card + the creator's Record right (docs/backend/live-rooms-spec.md §5)
import '../live/meeting_recording.dart' show MeetingRecording;
import '../live/meeting_recording_sheets.dart' show MeetingRecordingStatus;
import '../points/live_plan_sheet.dart' show showLivePlanSheet;
import '../points/points_api.dart';
import 'calendar_api.dart';
import 'calendar_models.dart';
import 'package:flutter_education_app/design/app_username.dart';

String _utcIso(DateTime wall) => AppTime.fromZone(wall).toUtc().toIso8601String();

DateTime? _parse(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final z = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(z ? s : '${s}Z')?.toUtc();
}

String _range(DateTime s, DateTime e) {
  final sameDay = calDay(AppTime.toZone(s)) == calDay(AppTime.toZone(e));
  return sameDay
      ? '${AppTime.date(s, pattern: 'EEE d MMM')} · ${AppTime.time(s)} – ${AppTime.time(e)}'
      : '${AppTime.dateTime(s)} – ${AppTime.dateTime(e)}';
}

/// Day + start/end picker row (wall clock of AppTime's zone).
class CalTimeFields extends StatelessWidget {
  const CalTimeFields({super.key, required this.start, required this.end, required this.onChanged});
  final DateTime start, end; // wall
  final void Function(DateTime start, DateTime end) onChanged;

  String _clock(DateTime d) => AppTime.clockMinutes(d.hour * 60 + d.minute);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Future<void> pickDay() async {
      final d = await showDatePicker(
          context: context,
          initialDate: start,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 730)));
      if (d == null) return;
      final s = DateTime(d.year, d.month, d.day, start.hour, start.minute);
      onChanged(s, s.add(end.difference(start)));
    }

    Future<void> pickTime(bool isStart) async {
      final base = isStart ? start : end;
      final tod = await showTimePicker(context: context, initialTime: TimeOfDay(hour: base.hour, minute: base.minute));
      if (tod == null) return;
      if (isStart) {
        final s = DateTime(start.year, start.month, start.day, tod.hour, tod.minute);
        onChanged(s, s.add(end.difference(start)));
      } else {
        var e = DateTime(start.year, start.month, start.day, tod.hour, tod.minute);
        if (!e.isAfter(start)) e = start.add(const Duration(minutes: 30));
        onChanged(start, e);
      }
    }

    Widget box(IconData icon, String label, String value, VoidCallback onTap) => Material(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(c.radiusMedium),
          child: InkWell(
            borderRadius: BorderRadius.circular(c.radiusMedium),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(icon, size: 18, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, c: c.textLight)),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                  ]),
                ),
              ]),
            ),
          ),
        );

    return Column(children: [
      box(Icons.calendar_today_rounded, t('اليوم', 'Day'),
          AppTime.date(AppTime.fromZone(DateTime(start.year, start.month, start.day, 12)), pattern: 'EEEE d MMMM y'), pickDay),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: box(Icons.schedule_rounded, t('من', 'From'), _clock(start), () => pickTime(true))),
        const SizedBox(width: 8),
        Expanded(child: box(Icons.schedule_rounded, t('إلى', 'To'), _clock(end), () => pickTime(false))),
      ]),
    ]);
  }
}

/// Online / offline segmented choice.
class CalModeChoice extends StatelessWidget {
  const CalModeChoice({super.key, required this.mode, required this.onChanged});
  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        AppChoiceChip(
            label: t('حضوري', 'In person'),
            icon: Icons.place_rounded,
            selected: mode == 'offline',
            onTap: () => onChanged('offline')),
        AppChoiceChip(
            label: t('عبر الإنترنت', 'Online'),
            icon: Icons.videocam_rounded,
            selected: mode == 'online',
            onTap: () => onChanged('online')),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Invitees
// ═════════════════════════════════════════════════════════════════════════════

class CalAudience {
  final users = <int, String>{};
  final depts = <int, String>{};
  final heads = <int, String>{};
  final courses = <int, String>{};

  bool get isEmpty => users.isEmpty && depts.isEmpty && heads.isEmpty && courses.isEmpty;

  Map<String, dynamic> toJson() => {
        'user_ids': users.keys.toList(),
        'dept_ids': depts.keys.toList(),
        'head_dept_ids': heads.keys.toList(),
        'course_ids': courses.keys.toList(),
      };
}

String _name(Map m) =>
    '${(AppConfig.lang == 'ar' ? (m['name_ar'] ?? m['name_en']) : (m['name_en'] ?? m['name_ar'])) ?? m['name'] ?? ''}';

Future<void> _pickAudience(BuildContext context, CalendarApi api, CalAudience aud, int? orgId) async {
  await showAppSheet<void>(context, (ctx) => _AudiencePicker(api: api, aud: aud, orgId: orgId));
}

class _AudiencePicker extends StatefulWidget {
  const _AudiencePicker({required this.api, required this.aud, this.orgId});
  final CalendarApi api;
  final CalAudience aud;
  final int? orgId;

  @override
  State<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<_AudiencePicker> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _debounce;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.people(orgId: widget.orgId, q: _q);
      if (mounted) setState(() { _data = asMap(r); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = calErrorText(e));
    }
  }

  void _toggle(Map<int, String> m, int id, String name) => setState(() => m.containsKey(id) ? m.remove(id) : m[id] = name);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _data;
    final a = widget.aud;
    Widget row(IconData icon, String title, String? sub, bool on, VoidCallback onTap, {Widget? avatar, String? username}) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: avatar ?? CircleAvatar(radius: 17, backgroundColor: c.primaryTint, child: Icon(icon, size: 18, color: c.primary)),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
          subtitle: username != null
              ? AppUsernameLine(username) // the search also matches @username (D-071 v2)
              : sub == null ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
          trailing: Icon(on ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: on ? c.success : c.textLight),
          onTap: onTap,
        );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(children: [
          AppSheetHeader(t('مع من؟', 'Who is invited?'),
              trailing: TextButton(onPressed: () => Navigator.pop(context), child: Text(t('تم', 'Done')))),
          TextField(
            onChanged: (q) {
              _q = q;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            decoration: InputDecoration(
                isDense: true, prefixIcon: const Icon(Icons.search_rounded), hintText: t('ابحث بالاسم أو @اسم المستخدم', 'Search by name or @username')),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: d == null && _error == null
                ? const AppListSkeleton(items: 5)
                : _error != null
                    ? AppBanner(
                        icon: Icons.error_outline_rounded,
                        text: _error!,
                        color: c.danger,
                        action: IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)))
                    : ListView(children: [
                        if (asMapList(d!['people']).isNotEmpty) AppSectionTitle(t('أشخاص', 'People')),
                        for (final p in asMapList(d['people']))
                          row(Icons.person_rounded, '${p['name']}', null, a.users.containsKey(asInt(p['id'])),
                              () => _toggle(a.users, asInt(p['id']), '${p['name']}'),
                              avatar: AppAvatar(name: '${p['name']}', url: p['image_url']?.toString(), size: 34),
                              username: usernameFrom(p)),
                        if (asMapList(d['departments']).isNotEmpty) AppSectionTitle(t('إدارات وأقسام', 'Departments')),
                        for (final dp in asMapList(d['departments'])) ...[
                          row(Icons.apartment_rounded, _name(dp), t('كل أعضاء الإدارة', 'Everyone in it'),
                              a.depts.containsKey(asInt(dp['id'])), () => _toggle(a.depts, asInt(dp['id']), _name(dp))),
                          if (asMapList(dp['heads']).isNotEmpty)
                            row(Icons.verified_user_rounded, '${t('المسؤول', 'Person in charge')} · ${_name(dp)}',
                                asMapList(dp['heads']).map((h) => '${h['name']}').join('، '),
                                a.heads.containsKey(asInt(dp['id'])),
                                () => _toggle(a.heads, asInt(dp['id']), '${t('مسؤول', 'Head')} ${_name(dp)}')),
                        ],
                        if (asMapList(d['courses']).isNotEmpty) AppSectionTitle(t('مجموعات المقررات', 'Course groups')),
                        for (final co in asMapList(d['courses']))
                          row(Icons.school_rounded, _name(co), '${co['students'] ?? 0} ${t('طالب', 'students')}',
                              a.courses.containsKey(asInt(co['id'])), () => _toggle(a.courses, asInt(co['id']), _name(co))),
                        if (asMapList(d['people']).isEmpty && asMapList(d['departments']).isEmpty && asMapList(d['courses']).isEmpty)
                          AppEmpty(
                              icon: Icons.person_search_rounded,
                              title: t('لا نتائج', 'No results'),
                              message: t('يمكن دعوة أعضاء مؤسساتك فقط.', 'You can invite members of your organizations.')),
                      ]),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  New meeting
// ═════════════════════════════════════════════════════════════════════════════

/// Quick-add sheet. Returns the created meeting (detail map) or null.
Future<Map<String, dynamic>?> showMeetingForm(BuildContext context,
        {required CalendarApi api, required DateTime start, int? orgId, int? deptId}) =>
    showAppSheet<Map<String, dynamic>>(
        context, (ctx) => MeetingForm(api: api, start: start, orgId: orgId, deptId: deptId));

/// Is the signed-in person a "student" for meetings (online + private only, free time without the plan)?
bool calIsStudent(BuildContext context) {
  try {
    return isStudentForMeetings(context.read<MyAuthProvider>().currentUser?.role);
  } catch (_) {
    return false; // no auth provider above (tests / previews)
  }
}

class MeetingForm extends StatefulWidget {
  const MeetingForm({super.key, required this.api, required this.start, this.orgId, this.deptId, this.student});
  final CalendarApi api;
  final DateTime start; // wall
  final int? orgId, deptId;

  /// Online + "Only me" forced, the mode and audience pickers hidden. Null → from the signed-in role.
  final bool? student;

  @override
  State<MeetingForm> createState() => _MeetingFormState();
}

class _MeetingFormState extends State<MeetingForm> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  final _notes = TextEditingController();
  final _aud = CalAudience();
  late DateTime _s = widget.start, _e = widget.start.add(const Duration(minutes: 30));
  String _mode = 'offline';
  bool _private = true, _saving = false, _checking = false, _student = false;
  List<Map<String, dynamic>> _busy = const [];
  String? _error;
  Timer? _debounce;
  int _check = 0;

  @override
  void initState() {
    super.initState();
    _student = widget.student ?? calIsStudent(context);
    if (_student) _mode = 'online';
    _scheduleCheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _runCheck);
  }

  Future<void> _runCheck() async {
    final n = ++_check;
    if (mounted) setState(() => _checking = true);
    try {
      final r = await widget.api.busy({
        'starts_at': _utcIso(_s),
        'ends_at': _utcIso(_e),
        'audience': _private ? CalAudience().toJson() : _aud.toJson(),
        'org_id': ?widget.orgId,
      });
      if (!mounted || n != _check) return;
      setState(() { _busy = asMapList(asMap(r)['busy']); _checking = false; });
    } catch (_) {
      if (mounted && n == _check) setState(() => _checking = false); // the check is a hint; saving checks again
    }
  }

  Future<void> _save() async {
    final titleError = calMeetingTitleError(_title.text, _mode);
    if (titleError != null) {
      setState(() => _error = titleError);
      return;
    }
    if (!_student && !_private && _aud.isEmpty) {
      setState(() => _error = t('اختر المدعوين أو اجعله خاصاً', 'Pick who is invited, or make it private'));
      return;
    }
    setState(() { _saving = true; _error = null; });
    final othersBusy = _busy.where((b) => asInt(asMap(b['user'])['id']) != _me).isNotEmpty;
    try {
      final r = await widget.api.create(calMeetingBody(
        title: _title.text, // blank + online → left out: the server names it after its start
        notes: _notes.text,
        startsAt: _utcIso(_s),
        endsAt: _utcIso(_e),
        mode: _mode,
        location: _place.text,
        orgId: widget.orgId,
        deptId: widget.deptId,
        audience: _private ? CalAudience().toJson() : _aud.toJson(),
        emptyAudience: CalAudience().toJson(),
        student: _student,
        force: othersBusy, // the warning was on screen: sending is a decision
      ));
      if (mounted) Navigator.pop(context, asMap(r));
    } catch (e) {
      final busy = calBusyOf(e);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (busy.isNotEmpty) {
          _busy = busy;
        } else {
          _error = calErrorText(e);
        }
      });
    }
  }

  int? get _me {
    try {
      return context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {
      return null; // no auth provider above (tests / previews)
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = _busy.where((b) => asInt(asMap(b['user'])['id']) == _me).toList();
    final others = _busy.where((b) => asInt(asMap(b['user'])['id']) != _me).toList();
    final chips = [
      for (final e in _aud.users.entries) (e.key, e.value, Icons.person_rounded, _aud.users),
      for (final e in _aud.depts.entries) (e.key, e.value, Icons.apartment_rounded, _aud.depts),
      for (final e in _aud.heads.entries) (e.key, e.value, Icons.verified_user_rounded, _aud.heads),
      for (final e in _aud.courses.entries) (e.key, e.value, Icons.school_rounded, _aud.courses),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('اجتماع جديد', 'New meeting')),
        _mode == 'online'
            ? AppField(
                key: const ValueKey('meeting_form.title_optional'),
                controller: _title,
                label: t('العنوان (اختياري)', 'Title (optional)'),
                hint: t('اختياري، يُستخدم التاريخ', 'Optional, the date is used'))
            : AppField(controller: _title, label: t('العنوان', 'Title'), hint: t('مثال: متابعة المشروع', 'e.g. Project check-in')),
        const SizedBox(height: 12),
        CalTimeFields(
            start: _s,
            end: _e,
            onChanged: (s, e) {
              setState(() { _s = s; _e = e; });
              _scheduleCheck();
            }),
        const SizedBox(height: 14),
        if (_student)
          AppBanner(
              key: const ValueKey('meeting_form.student_note'),
              icon: Icons.videocam_rounded,
              text: t('يمكن للطلاب إنشاء اجتماعات خاصة عبر الإنترنت؛ شارك الرابط لدعوة الآخرين',
                  'Students can create online private meetings; share the link to invite people'),
              color: c.primary)
        else ...[
        CalModeChoice(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
        const SizedBox(height: 10),
        if (_mode == 'offline')
          AppField(controller: _place, label: t('المكان', 'Location'), hint: t('قاعة، مكتب، مبنى…', 'Room, office, building…'))
        else
          AppBanner(
              icon: Icons.link_rounded,
              text: t('يُنشأ رابط الانضمام تلقائياً عبر البث المباشر للمنصة.', 'A join link is created automatically (live video).'),
              color: c.primary),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppChoiceChip(
              label: t('خاص بي', 'Only me'),
              icon: Icons.lock_rounded,
              selected: _private,
              onTap: () {
                setState(() => _private = true);
                _scheduleCheck();
              }),
          AppChoiceChip(
              label: t('مع آخرين', 'With others'),
              icon: Icons.group_add_rounded,
              selected: !_private,
              onTap: () async {
                setState(() => _private = false);
                await _pickAudience(context, widget.api, _aud, widget.orgId);
                if (mounted) setState(() {});
                _scheduleCheck();
              }),
        ]),
        if (!_private) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (id, label, icon, map) in chips)
              InputChip(
                avatar: Icon(icon, size: 16, color: c.primary),
                label: Text(label, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textDark)),
                onDeleted: () {
                  setState(() => map.remove(id));
                  _scheduleCheck();
                },
              ),
            ActionChip(
              avatar: Icon(Icons.add_rounded, size: 16, color: c.primary),
              label: Text(t('إضافة', 'Add'), style: appText(12, w: FontWeight.w700, c: c.primary)),
              onPressed: () async {
                await _pickAudience(context, widget.api, _aud, widget.orgId);
                if (mounted) setState(() {});
                _scheduleCheck();
              },
            ),
          ]),
        ],
        ],
        const SizedBox(height: 10),
        AppField(controller: _notes, label: t('ملاحظات (اختياري)', 'Notes (optional)'), maxLines: 3),
        if (_checking || mine.isNotEmpty || others.isNotEmpty) const SizedBox(height: 12),
        if (_checking && mine.isEmpty && others.isEmpty)
          Text(t('نتحقق من التوفر…', 'Checking availability…'), style: appText(12, c: c.textLight)),
        if (mine.isNotEmpty)
          AppBanner(
              icon: Icons.event_busy_rounded,
              color: c.warning,
              text: '${t('لديك في هذا الوقت', 'You already have')}: ${asMapList(mine.first['items']).map((i) => i['title']).join('، ')}'),
        if (others.isNotEmpty) ...[
          if (mine.isNotEmpty) const SizedBox(height: 8),
          AppBanner(
              icon: Icons.warning_amber_rounded,
              color: c.danger,
              text: '${t('مشغولون في هذا الوقت', 'Busy at this time')}: '
                  '${others.take(4).map((b) => asMap(b['user'])['name']).join('، ')}'
                  '${others.length > 4 ? ' +${others.length - 4}' : ''}'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(
          label: others.isNotEmpty ? t('أرسل رغم ذلك', 'Send anyway') : (_private ? t('حفظ', 'Save') : t('إرسال الدعوات', 'Send invitations')),
          icon: _private ? Icons.check_rounded : Icons.send_rounded,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Meeting details
// ═════════════════════════════════════════════════════════════════════════════

/// Details + actions. Returns true when something changed (the calendar reloads).
Future<bool> showMeetingSheet(BuildContext context, {required CalendarApi api, required int meetingId}) async =>
    await showAppSheet<bool>(context, (ctx) => MeetingSheet(api: api, meetingId: meetingId)) ?? false;

class MeetingSheet extends StatefulWidget {
  const MeetingSheet({super.key, required this.api, required this.meetingId, this.initial});
  final CalendarApi api;
  final int meetingId;
  final Map<String, dynamic>? initial;

  @override
  State<MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends State<MeetingSheet> {
  Map<String, dynamic>? _m;
  String? _error;
  bool _busy = false, _changed = false;

  // [meeting-recording] bumped when the room closes, so the recording card reloads
  int _recordingRefresh = 0;

  /// The creator may record an online meeting: the server's `can_record`; an older server (no field) → is_owner.
  bool get _canRecord {
    final m = _m;
    if (m == null) return false;
    final v = m['can_record'];
    if (v is bool) return v;
    return m['is_owner'] == true && m['mode'] == 'online';
  }

  @override
  void initState() {
    super.initState();
    _m = widget.initial;
    if (_m == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.api.meeting(widget.meetingId);
      if (mounted) setState(() => _m = asMap(r));
    } catch (e) {
      if (mounted) setState(() => _error = calErrorText(e));
    }
  }

  Future<void> _act(Future<dynamic> Function() fn, {String? ok, bool close = false}) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      _changed = true;
      if (ok != null) appToast(ok);
      if (!mounted) return;
      if (close) return Navigator.pop(context, true);
      setState(() {
        _busy = false;
        if (r is Map && r['id'] != null) _m = asMap(r);
      });
    } catch (e) {
      final busy = calBusyOf(e);
      if (!mounted) return;
      setState(() => _busy = false);
      if (busy.isNotEmpty) {
        final names = busy.map((b) => asMap(b['user'])['name']).join('، ');
        final go = await appConfirm(context,
            message: '${t('مشغولون في هذا الوقت', 'Busy at this time')}: $names', confirmLabel: t('انقل رغم ذلك', 'Move anyway'));
        if (go && mounted) await _move(force: true);
      } else {
        appToast(calErrorText(e), error: true);
      }
    }
  }

  DateTime? _pendingS, _pendingE;

  Future<void> _move({bool force = false}) async {
    if (!force) {
      final m = _m!;
      final s = AppTime.toZone(_parse(m['starts_at'])!), e = AppTime.toZone(_parse(m['ends_at'])!);
      final picked = await showAppSheet<(DateTime, DateTime)>(context, (ctx) => _TimePickSheet(
          title: t('موعد جديد', 'New time'), start: s, end: e, action: t('نقل الاجتماع', 'Move meeting')));
      if (picked == null) return;
      _pendingS = picked.$1;
      _pendingE = picked.$2;
    }
    if (_pendingS == null) return;
    await _act(() => widget.api.update(widget.meetingId,
        {'starts_at': _utcIso(_pendingS!), 'ends_at': _utcIso(_pendingE!), 'force': force}), ok: t('تم النقل وإبلاغ المدعوين', 'Moved — invitees notified'));
  }

  Future<void> _propose() async {
    final m = _m!;
    final s = AppTime.toZone(_parse(m['starts_at'])!), e = AppTime.toZone(_parse(m['ends_at'])!);
    final picked = await showAppSheet<(DateTime, DateTime)>(context, (ctx) => _TimePickSheet(
        title: t('اقترح موعداً آخر', 'Propose another time'), start: s, end: e, action: t('إرسال الاقتراح', 'Send proposal')));
    if (picked == null) return;
    await _act(() => widget.api.respond(widget.meetingId,
        {'status': 'proposed', 'proposed_start': _utcIso(picked.$1), 'proposed_end': _utcIso(picked.$2)}), ok: t('أُرسل اقتراحك', 'Proposal sent'));
  }

  Future<void> _join() async {
    await openMeetingRoom(context, api: widget.api, meeting: {...?_m, 'id': widget.meetingId}, canRecord: _canRecord);
    // [meeting-recording] back from the room: the latest recording (and the detail) may have changed
    if (!mounted) return;
    setState(() => _recordingRefresh++);
    unawaited(_load());
  }

  /// Owner of an online meeting: the share link and the admission lobby (kill switches `live.share_link` / `live.lobby`).
  Widget _hostActions(BuildContext context) {
    final ref = LiveRoomRef.meeting(widget.meetingId);
    final title = '${_m?['title'] ?? ''}';
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ParentComponent(
        featureKey: kLiveShareLinkFeatureKey,
        child: AppPill(
          key: const ValueKey('meeting.share_link'),
          icon: Icons.link_rounded,
          label: t('رابط المشاركة', 'Share link'),
          onTap: _busy ? null : () => showShareLinkSheet(context, ref, title: title),
        ),
      ),
      ParentComponent(
        featureKey: kLiveLobbyFeatureKey,
        child: AppPill(
          key: const ValueKey('meeting.lobby'),
          icon: Icons.meeting_room_rounded,
          label: t('غرفة الانتظار والقبول', 'Lobby & admission'),
          onTap: _busy ? null : () => showLobbySheet(context, ref),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = _m;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.pop(context, _changed);
      },
      child: m == null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: _error == null
                  ? const SizedBox(height: 260, child: AppListSkeleton(items: 3))
                  : AppBanner(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      color: c.danger,
                      action: IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))),
            )
          : _body(context, m),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> m) {
    final c = context.colors;
    final s = _parse(m['starts_at']), e = _parse(m['ends_at']);
    final owner = m['is_owner'] == true;
    final my = '${m['my_status'] ?? ''}';
    final counts = asMap(m['counts']);
    final attendees = asMapList(m['attendees']);
    final online = m['mode'] == 'online';
    final dept = asMap(m['dept']), org = asMap(m['org']);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader('${m['title']}'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppTag(calStatusLabel(my), calStatusColor(c, my), icon: calStatusIcon(my)),
          AppTag(online ? t('عبر الإنترنت', 'Online') : t('حضوري', 'In person'), c.primary,
              icon: online ? Icons.videocam_rounded : Icons.place_rounded),
          if (m['visibility'] == 'private') AppTag(t('خاص', 'Private'), c.accent, icon: Icons.lock_rounded),
          if (m['source_type'] == 'complaint') AppTag(t('من شكوى / طلب', 'From a request'), c.warning, icon: Icons.support_agent_rounded),
        ]),
        const SizedBox(height: 12),
        if (s != null && e != null) _Info(icon: Icons.schedule_rounded, label: t('الموعد', 'When'), value: _range(s, e)),
        if (!online && '${m['location'] ?? ''}'.isNotEmpty)
          _Info(icon: Icons.place_rounded, label: t('المكان', 'Where'), value: '${m['location']}'),
        _Info(icon: Icons.person_rounded, label: t('المنظّم', 'Organizer'), value: '${asMap(m['owner'])['name'] ?? ''}'),
        if (dept.isNotEmpty || org.isNotEmpty)
          _Info(
              icon: Icons.apartment_rounded,
              label: t('الجهة', 'Unit'),
              value: [if (org.isNotEmpty) _name(org), if (dept.isNotEmpty) _name(dept)].join(' · ')),
        if ('${m['notes'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${m['notes']}', style: appText(13, c: c.textMedium, h: 1.5)),
        ],
        if (online && m['status'] != 'cancelled')
          if (MeetingTimeLimit.parse(m['time_limit']) case final limit?)
            if (!(owner && m['owner_plan_active'] == true)) ...[
              const SizedBox(height: 12),
              AppBanner(
                key: const ValueKey('meeting.free_time'),
                icon: Icons.timer_outlined,
                color: c.warning,
                text: meetingFreeNote(limit, DateTime.now().toUtc(), owner: owner),
                action: owner
                    ? ParentComponent(
                        featureKey: kPointsFeatureKey,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await showLivePlanSheet(context) && mounted) unawaited(_load());
                                },
                          child: Text(t('ترقية', 'Upgrade')),
                        ),
                      )
                    : null,
              ),
            ],
        if (m['can_join'] == true) ...[
          const SizedBox(height: 14),
          AppPrimaryButton(label: t('انضم الآن', 'Join now'), icon: Icons.videocam_rounded, onPressed: _busy ? null : _join),
        ],
        // [meeting-recording] the latest recording: status while it is made, the drive link when done
        if (online) ...[
          const SizedBox(height: 12),
          MeetingRecordingStatus(
            key: ValueKey('meeting_recording.${widget.meetingId}'),
            meetingId: widget.meetingId,
            initial: MeetingRecording.latestOf(m),
            refreshKey: _recordingRefresh,
            gap: 0,
          ),
        ],
        if (owner && online && m['status'] != 'cancelled') ...[
          const SizedBox(height: 10),
          _hostActions(context),
        ],
        if (!owner && my.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('ردّك', 'Your answer'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChoiceChip(
                label: t('قبول', 'Accept'),
                icon: Icons.check_rounded,
                selected: my == 'accepted',
                onTap: () => _act(() => widget.api.respond(widget.meetingId, {'status': 'accepted'}), ok: t('تم القبول', 'Accepted'))),
            AppChoiceChip(
                label: t('اعتذار', 'Decline'),
                icon: Icons.close_rounded,
                selected: my == 'declined',
                onTap: () => _act(() => widget.api.respond(widget.meetingId, {'status': 'declined'}), ok: t('تم الاعتذار', 'Declined'))),
            AppChoiceChip(label: t('اقترح موعداً', 'Propose a time'), icon: Icons.schedule_send_rounded, selected: my == 'proposed', onTap: _propose),
          ]),
        ],
        if (attendees.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppSectionTitle(t('المدعوون', 'Invitees'),
              subtitle: [
                for (final k in ['accepted', 'pending', 'proposed', 'declined'])
                  if (asInt(counts[k]) > 0) '${asInt(counts[k])} ${calStatusLabel(k)}',
              ].join(' · ')),
          for (final a in attendees) _attendee(context, a, owner),
        ],
        if (owner && m['status'] == 'scheduled') ...[
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppPill(icon: Icons.edit_calendar_rounded, label: t('تغيير الموعد', 'Change time'), onTap: _busy ? null : () => _move()),
            AppPill(
                icon: Icons.event_busy_rounded,
                label: t('إلغاء الاجتماع', 'Cancel meeting'),
                color: c.danger,
                onTap: _busy
                    ? null
                    : () async {
                        if (await appConfirm(context,
                            message: t('إلغاء الاجتماع وإبلاغ المدعوين؟', 'Cancel the meeting and notify invitees?'), danger: true)) {
                          await _act(() => widget.api.cancel(widget.meetingId), ok: t('أُلغي الاجتماع', 'Meeting cancelled'), close: true);
                        }
                      }),
          ]),
        ],
      ]),
    );
  }

  Widget _attendee(BuildContext context, Map<String, dynamic> a, bool owner) {
    final c = context.colors;
    final st = '${a['status']}';
    final u = asMap(a['user']);
    final ps = _parse(a['proposed_start']), pe = _parse(a['proposed_end']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(clipBehavior: Clip.none, children: [
          AppAvatar(name: '${u['name'] ?? ''}', url: u['image_url']?.toString(), size: 36),
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
              child: Icon(calStatusIcon(st), size: 15, color: calStatusColor(c, st)),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${u['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
            Text(calStatusLabel(st), style: appText(12, c: calStatusColor(c, st))),
            if (ps != null && pe != null) Text(_range(ps, pe), style: appText(12, c: c.textMedium)),
            if ('${a['note'] ?? ''}'.isNotEmpty) Text('${a['note']}', style: appText(12, c: c.textLight)),
          ]),
        ),
        if (owner && st == 'proposed' && ps != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => _act(() => widget.api.acceptProposal(widget.meetingId, asInt(a['id'])),
                    ok: t('نُقل الاجتماع للموعد المقترح', 'Moved to the proposed time')),
            child: Text(t('اعتماد', 'Use it')),
          ),
      ]),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: c.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: appText(11, c: c.textLight)),
            Text(value, style: appText(14, w: FontWeight.w600, c: c.textDark)),
          ]),
        ),
      ]),
    );
  }
}

class _TimePickSheet extends StatefulWidget {
  const _TimePickSheet({required this.title, required this.start, required this.end, required this.action});
  final String title, action;
  final DateTime start, end;

  @override
  State<_TimePickSheet> createState() => _TimePickSheetState();
}

class _TimePickSheetState extends State<_TimePickSheet> {
  late DateTime _s = widget.start, _e = widget.end;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(widget.title),
          CalTimeFields(start: _s, end: _e, onChanged: (s, e) => setState(() { _s = s; _e = e; })),
          const SizedBox(height: 16),
          AppPrimaryButton(label: widget.action, icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, (_s, _e))),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Into the room: a meeting's join · "Meet now"
// ═════════════════════════════════════════════════════════════════════════════

DateTime? calParseUtc(dynamic v) => _parse(v);

/// The creator may record an online meeting: the server's `can_record`; an older server (no field) → is_owner.
bool meetingCanRecord(Map<String, dynamic> m) {
  final v = m['can_record'];
  if (v is bool) return v;
  return m['is_owner'] == true && m['mode'] == 'online';
}

/// POST …/meetings/{id}/join with the student plan (live-rooms-spec §8): a 402 `live_plan_required` (the owner of a
/// student meeting over its free time) opens the plan sheet and, once subscribed, joins again (once); closing the
/// sheet stops with [LivePlanDeclined]. A 403 `meeting_time_limit` becomes a [LiveJoinMessage] with a clear text.
/// 200 → the room; 202 waiting → PreJoinPage shows "Waiting for the host…" (§4).
Future<JoinOutcome> joinMeetingWithPlan(BuildContext context, CalendarApi api, int id) async {
  try {
    return JoinOutcome.parse(await api.join(id));
  } catch (e) {
    final code = pointsErrorCode(e);
    if (code == 'meeting_time_limit') throw LiveJoinMessage(pointsCodeText(code)!);
    if (code != 'live_plan_required' || !context.mounted) rethrow;
    if (!await showLivePlanSheet(context)) throw const LivePlanDeclined();
    try {
      return JoinOutcome.parse(await api.join(id));
    } catch (e2) {
      final c2 = pointsErrorCode(e2);
      if (pointsCodeText(c2) case final text?) throw LiveJoinMessage(text);
      rethrow;
    }
  }
}

/// The pre-join page of a meeting (its detail map: id, title, starts_at, owner, is_owner, mode, can_record).
/// [autoJoin]: the pre-join page presses Join by itself once the devices are ready (the quick meeting).
Future<void> openMeetingRoom(BuildContext context,
    {required CalendarApi api, required Map<String, dynamic> meeting, bool autoJoin = false, bool? canRecord, bool? isHost}) async {
  final auth = context.read<MyAuthProvider>();
  final id = asInt(meeting['id']);
  final owner = isHost ?? meeting['is_owner'] == true;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PreJoinPage(
      args: JoinArgs(
        sessionId: -id, // not a course session: keeps the course-session calls of the room away from real ones
        roomRef: LiveRoomRef.meeting(id),
        isHost: owner, // the owner runs the lobby (share link, admission) without being a "teacher"
        courseId: 0,
        isTeacher: false,
        canRecord: canRecord ?? meetingCanRecord(meeting), // [meeting-recording]
        userId: auth.currentUser?.id ?? -1,
        userName: auth.currentUser?.name ?? '--',
        sessionName: '${meeting['title'] ?? ''}',
        apiClient: ApiClient(),
        autoJoin: autoJoin,
        startsAt: _parse(meeting['starts_at']),
        hostName: _strOrNull(asMap(meeting['owner'])['name']),
        onStart: () => joinMeetingWithPlan(context, api, id),
        onEnd: () async {},
      ),
    ),
  ));
}

String? _strOrNull(dynamic v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// "Meet now" (live-rooms-spec §7): creates an online, private meeting that starts now (no title: the server names
/// it after its start) and opens its pre-join page, which joins by itself; the creator is the host. Returns the
/// meeting (null when it could not be created — the person was told).
Future<Map<String, dynamic>?> startQuickMeeting(BuildContext context, {int? orgId, CalendarApi api = const RemoteCalendarApi()}) async {
  final Map<String, dynamic> m;
  try {
    m = asMap(await api.quick(orgId: orgId));
  } catch (e) {
    appToast(pointsErrorText(e), error: true);
    return null;
  }
  if (asInt(m['id']) <= 0 || !context.mounted) return m.isEmpty ? null : m;
  await openMeetingRoom(context, api: api, meeting: m, autoJoin: true, canRecord: true, isHost: true);
  return m;
}

/// The "Meet now" button (kill switch `live.quick_meeting`); [onDone] runs after the room (reload a list).
class QuickMeetingButton extends StatefulWidget {
  const QuickMeetingButton({super.key, this.orgId, this.api = const RemoteCalendarApi(), this.onDone, this.fab = false});
  final int? orgId;
  final CalendarApi api;
  final VoidCallback? onDone;

  /// A floating action button (the calendar) instead of a compact pill (lists).
  final bool fab;

  @override
  State<QuickMeetingButton> createState() => _QuickMeetingButtonState();
}

class _QuickMeetingButtonState extends State<QuickMeetingButton> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    final m = await startQuickMeeting(context, orgId: widget.orgId, api: widget.api);
    if (!mounted) return;
    setState(() => _busy = false);
    if (m != null) widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = t('اجتمع الآن', 'Meet now');
    return ParentComponent(
      featureKey: kQuickMeetingFeatureKey,
      child: widget.fab
          ? FloatingActionButton.extended(
              key: const ValueKey('calendar.meet_now'),
              heroTag: 'cal_meet_now',
              onPressed: _busy ? null : _go,
              backgroundColor: c.accent,
              foregroundColor: c.onHero,
              icon: _busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero))
                  : const Icon(Icons.video_call_rounded),
              label: Text(label, style: appText(14, w: FontWeight.w700, c: c.onHero)),
            )
          : AppPill(
              key: const ValueKey('meetings.meet_now'),
              icon: Icons.video_call_rounded,
              label: label,
              onTap: _busy ? null : _go,
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Complaint / request → meeting
// ═════════════════════════════════════════════════════════════════════════════

/// One tap from a complaint thread. Returns true when the meeting was created (reload the thread).
Future<bool> showComplaintMeetingSheet(BuildContext context,
        {required int orgId, required int complaintId, required String subject, CalendarApi api = const RemoteCalendarApi()}) async =>
    await showAppSheet<bool>(
        context, (ctx) => _ComplaintMeetingForm(api: api, orgId: orgId, complaintId: complaintId, subject: subject)) ??
    false;

class _ComplaintMeetingForm extends StatefulWidget {
  const _ComplaintMeetingForm({required this.api, required this.orgId, required this.complaintId, required this.subject});
  final CalendarApi api;
  final int orgId, complaintId;
  final String subject;

  @override
  State<_ComplaintMeetingForm> createState() => _ComplaintMeetingFormState();
}

class _ComplaintMeetingFormState extends State<_ComplaintMeetingForm> {
  late DateTime _s = _nextSlot(), _e = _nextSlot().add(const Duration(minutes: 30));
  String _mode = 'offline';
  final _place = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  static DateTime _nextSlot() {
    final n = AppTime.toZone(DateTime.now().toUtc()).add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 10);
  }

  @override
  void dispose() {
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.complaintMeeting(widget.orgId, widget.complaintId, {
        'starts_at': _utcIso(_s),
        'ends_at': _utcIso(_e),
        'mode': _mode,
        if (_mode == 'offline' && _place.text.trim().isNotEmpty) 'location': _place.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      appToast(t('حُدّد الاجتماع وأُبلغ صاحب الطلب', 'Meeting set — the sender was notified'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = calErrorText(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('تحويل إلى اجتماع', 'Turn into a meeting')),
        Text(widget.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium)),
        const SizedBox(height: 12),
        CalTimeFields(start: _s, end: _e, onChanged: (s, e) => setState(() { _s = s; _e = e; })),
        const SizedBox(height: 12),
        CalModeChoice(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
        const SizedBox(height: 10),
        if (_mode == 'offline') AppField(controller: _place, label: t('المكان', 'Location')),
        if (_mode == 'offline') const SizedBox(height: 10),
        AppField(controller: _note, label: t('رسالة لصاحب الطلب (اختياري)', 'Message to the sender (optional)'), maxLines: 2),
        if (_error != null) ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(label: t('تحديد الاجتماع', 'Set the meeting'), icon: Icons.event_available_rounded, busy: _saving, onPressed: _saving ? null : _save),
      ]),
    );
  }
}
