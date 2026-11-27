// lib/features/profile/teacher/t2_booking_slots.dart — "My times for فردي classes" (docs/redesign/api/booking.md,
// Teacher side): the weekly 50-minute times a student can book one to one. Kill switch `booking` (the hub hides the
// entry; the page shows "coming soon").
//
//   TeacherBookingSlotsPage  GET /booking/teacher/slots + the education catalog (subject / grade names) →
//                            TeacherSlotsView; "Add a time" → TeacherSlotForm (POST …/slots); remove an open time
//                            (DELETE …/slots/{id}, 409 `slot_taken` once a student booked it).
//   TeacherSlotsView         plain values (test/ui/wire_layout_test.dart).
//   TeacherSlotForm          subject (required), grade (optional), the first day and time (the viewer's zone through
//                            AppTime, sent as UTC); remote only: in-person times are set by the platform team.
//                            409 `slot_overlap` / `teacher_gender_unknown`, 403 `not_approved` show their text.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 't2_frame.dart';

/// One row of GET /booking/teacher/slots.
@immutable
class TeacherSlot {
  const TeacherSlot({
    required this.id,
    required this.subjectId,
    required this.startsAt,
    this.gradeId,
    this.mode = 'remote',
    this.nextAt,
    this.weekly = true,
    this.minutes = 50,
    this.status = 'open',
    this.studentName = '',
  });

  final int id, subjectId, minutes;
  final int? gradeId;
  final String mode, status, studentName;
  final DateTime startsAt;
  final DateTime? nextAt;
  final bool weekly;

  bool get taken => status == 'taken';
  DateTime get shown => nextAt ?? startsAt;

  static DateTime? _utc(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return null;
    return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  }

  static TeacherSlot? tryParse(Object? v) {
    if (v is! Map || v['id'] is! num) return null;
    final start = _utc(v['starts_at']);
    if (start == null) return null;
    final student = v['student'] is Map ? v['student'] as Map : const {};
    return TeacherSlot(
      id: (v['id'] as num).toInt(),
      subjectId: (v['edu_subject_id'] as num?)?.toInt() ?? 0,
      gradeId: (v['grade_id'] as num?)?.toInt(),
      mode: '${v['mode'] ?? 'remote'}',
      startsAt: start,
      nextAt: _utc(v['next_at']),
      weekly: v['weekly'] != false,
      minutes: (v['minutes'] as num?)?.toInt() ?? 50,
      status: '${v['status'] ?? 'open'}',
      studentName: '${student['name'] ?? ''}',
    );
  }
}

/// The text of a slot route's error code, else the server's own message.
String teacherSlotErrorText(Object e) {
  final x = ApiException.from(e);
  return switch (x.code) {
    'slot_overlap' => 't2_slot_overlap'.tr,
    'slot_taken' => 't2_slot_taken'.tr,
    'teacher_gender_unknown' => 't2_slot_gender'.tr,
    'not_approved' => 't2_slot_not_approved'.tr,
    _ => x.message,
  };
}

class TeacherBookingSlotsPage extends StatefulWidget {
  const TeacherBookingSlotsPage({super.key, this.api});

  final ApiClient? api;

  @override
  State<TeacherBookingSlotsPage> createState() => _TeacherBookingSlotsPageState();
}

class _TeacherBookingSlotsPageState extends State<TeacherBookingSlotsPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  List<TeacherSlot>? _slots;
  EduCountryCatalog? _catalog;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final code = pickEduCountry(await EduCountries.load(), null)?.code;
      if (code == null) return;
      final cat = await EduCatalog.instance.load(code);
      if (mounted) setState(() => _catalog = cat);
    } catch (_) {
      // names fall back to "Subject"; the form says it has no subjects
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.get('/api/v1/booking/teacher/slots');
      final list = r is Map ? (r['items'] as List? ?? const []) : const [];
      if (mounted) setState(() => _slots = [for (final x in list) ?TeacherSlot.tryParse(x)]);
    } catch (e) {
      if (mounted) setState(() => _error = teacherSlotErrorText(e));
    }
  }

  Future<void> _add() async {
    final added = await showAppSheet<TeacherSlot>(context, (_) => T2Scope(child: TeacherSlotForm(catalog: _catalog, api: _api)));
    if (added != null && mounted) {
      showAppNotice('t2_slot_added'.tr);
      _load();
    }
  }

  Future<void> _remove(TeacherSlot s) async {
    if (!await appConfirm(context, message: 't2_slot_remove_q'.tr, danger: true, confirmLabel: 't2_slot_remove'.tr)) return;
    try {
      await _api.delete('/api/v1/booking/teacher/slots/${s.id}');
      if (mounted) _load();
    } catch (e) {
      showAppNotice(teacherSlotErrorText(e), error: true);
      if (mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    final open = slots?.where((s) => !s.taken).length ?? 0;
    final taken = slots?.where((s) => s.taken).length ?? 0;
    return T2HeroPage(
      pageKey: const ValueKey('booking'),
      title: 't2_slots_title'.tr,
      width: AppWidth.reading,
      onRefresh: _load,
      hero: AppHero(
        title: 't2_slots_hero'.tr,
        subtitle: 't2_slots_sub'.tr,
        stats: slots == null
            ? const []
            : [
                AppHeroStat(value: '$open', label: 't2_slots_open'.tr),
                AppHeroStat(value: '$taken', label: 't2_slots_taken'.tr),
              ],
      ),
      children: [
        if (slots == null)
          _error == null ? const AppListSkeleton(items: 3) : AppCard(child: AppErrorState(message: _error, onRetry: _load))
        else
          TeacherSlotsView(slots: slots, catalog: _catalog, onAdd: _add, onRemove: _remove),
      ],
    );
  }
}

/// The times, with plain values.
class TeacherSlotsView extends StatelessWidget {
  const TeacherSlotsView({super.key, required this.slots, this.catalog, this.onAdd, this.onRemove});

  final List<TeacherSlot> slots;
  final EduCountryCatalog? catalog;
  final VoidCallback? onAdd;
  final ValueChanged<TeacherSlot>? onRemove;

  @override
  Widget build(BuildContext context) {
    final add = AppButton.primary(
      key: const ValueKey('t2.slots.add'),
      label: 't2_slot_add'.tr,
      icon: Icons.add_rounded,
      expand: true,
      onPressed: onAdd,
    );
    if (slots.isEmpty) {
      return AppCard(
        child: AppEmpty(
          icon: Icons.event_available_outlined,
          title: 't2_slots_none'.tr,
          message: 't2_slots_none_sub'.tr,
          actionLabel: 't2_slot_add'.tr,
          onAction: onAdd,
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      add,
      const SizedBox(height: AppSpace.md),
      AppCard(
        title: countText(slots.length, ar1: 'موعد واحد', ar2: 'موعدان', arFew: '{n} مواعيد', arMany: '{n} موعداً', en1: '1 time', en: '{n} times'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, s) in slots.indexed) ...[
            if (i > 0) Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: context.colors.kit.line),
            _SlotRow(key: ValueKey('t2.slot.${s.id}'), slot: s, catalog: catalog, onRemove: s.taken || onRemove == null ? null : () => onRemove!(s)),
          ],
        ]),
      ),
    ]);
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({super.key, required this.slot, this.catalog, this.onRemove});

  final TeacherSlot slot;
  final EduCountryCatalog? catalog;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = slot;
    final subject = catalog?.subject(s.subjectId)?.name ?? 't2_slot_subject'.tr;
    final grade = catalog?.grade(s.gradeId)?.name;
    final when = '${AppTime.date(s.shown, pattern: 'EEEE')} · ${AppTime.time(s.shown)}';
    final meta = [
      if (grade != null && grade.isNotEmpty) grade,
      '${'t2_slot_mode_${s.mode}'.tr} · ${countText(s.minutes, ar1: 'دقيقة', ar2: 'دقيقتان', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes')}',
    ].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Row(children: [
        AppIconBox(icon: s.taken ? Icons.event_busy_outlined : Icons.event_available_outlined),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
            Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            if (s.taken && s.studentName.isNotEmpty)
              Text(s.studentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        if (s.taken)
          AppStatusBadge(label: 't2_slots_taken'.tr, tone: AppTone.info)
        else
          AppIconButton(
            key: ValueKey('t2.slot.${s.id}.remove'),
            icon: Icons.delete_outline_rounded,
            tooltip: 't2_slot_remove'.tr,
            onPressed: onRemove,
          ),
      ]),
    );
  }
}

/// "Add a time": subject, grade (optional), the first day and time. Pops the created slot.
class TeacherSlotForm extends StatefulWidget {
  const TeacherSlotForm({super.key, this.catalog, this.api, this.initial});

  final EduCountryCatalog? catalog;
  final ApiClient? api;

  /// The first time shown (tests); default tomorrow at 4 pm on the viewer's clock.
  final DateTime? initial;

  @override
  State<TeacherSlotForm> createState() => _TeacherSlotFormState();
}

class _TeacherSlotFormState extends State<TeacherSlotForm> {
  late final ApiClient _api = widget.api ?? ApiClient();
  int? _subject, _grade;
  late DateTime _wall;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = AppTime.toZone(DateTime.now().toUtc());
    _wall = widget.initial ?? DateTime(now.year, now.month, now.day + 1, 16);
  }

  List<EduGrade> _gradesOf(int? subjectId) => [
        for (final st in widget.catalog?.stages ?? const <EduStage>[])
          for (final g in st.grades)
            if (subjectId == null || g.subjectIds.isEmpty || g.subjectIds.contains(subjectId)) g,
      ];

  Future<void> _pickDay() async {
    final now = AppTime.toZone(DateTime.now().toUtc());
    final d = await showDatePicker(
      context: context,
      initialDate: _wall.isBefore(now) ? now : _wall,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (d != null && mounted) setState(() => _wall = DateTime(d.year, d.month, d.day, _wall.hour, _wall.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _wall.hour, minute: _wall.minute));
    if (t != null && mounted) setState(() => _wall = DateTime(_wall.year, _wall.month, _wall.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_subject == null) {
      setState(() => _error = 't2_slot_pick_subject'.tr);
      return;
    }
    final at = AppTime.fromZone(_wall).toUtc();
    if (!at.isAfter(DateTime.now().toUtc())) {
      setState(() => _error = 't2_slot_future'.tr);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await _api.post('/api/v1/booking/teacher/slots', body: {
        'edu_subject_id': _subject,
        'grade_id': ?_grade,
        'mode': 'remote',
        'starts_at': at.toIso8601String(),
        'weekly': true,
      });
      if (!mounted) return;
      Navigator.of(context).pop(TeacherSlot.tryParse(r) ?? TeacherSlot(id: 0, subjectId: _subject!, startsAt: at));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = teacherSlotErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = widget.catalog?.subjects ?? const <EduSubject>[];
    final grades = _gradesOf(_subject);
    final utc = AppTime.fromZone(_wall).toUtc();
    Widget pick(Key key, IconData icon, String label, String value, VoidCallback onTap) => Expanded(
          child: AppButton.secondary(key: key, label: '$label: $value', icon: icon, expand: true, onPressed: _saving ? null : onTap),
        );
    return AppSheetContent(
      title: 't2_slot_add'.tr,
      icon: Icons.event_available_outlined,
      children: [
        if (subjects.isEmpty)
          AppBanner(icon: Icons.info_outline_rounded, text: 't2_slot_no_subjects'.tr)
        else ...[
          AppDropdown<int>(
            key: const ValueKey('t2.slot.subject'),
            value: _subject,
            decoration: InputDecoration(labelText: 't2_slot_subject'.tr),
            items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))],
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      _subject = v;
                      if (_grade != null && !_gradesOf(v).any((g) => g.id == _grade)) _grade = null;
                    }),
          ),
          const SizedBox(height: AppSpace.sm),
          AppDropdown<int?>(
            key: const ValueKey('t2.slot.grade'),
            value: _grade,
            decoration: InputDecoration(labelText: 't2_slot_grade'.tr),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text('t2_slot_any_grade'.tr)),
              for (final g in grades) DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
            ],
            onChanged: _saving ? null : (v) => setState(() => _grade = v),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          pick(const ValueKey('t2.slot.day'), Icons.calendar_today_outlined, 't2_slot_day'.tr, AppTime.date(utc, pattern: 'EEEE d MMM'), _pickDay),
          const SizedBox(width: AppSpace.xs),
          pick(const ValueKey('t2.slot.time'), Icons.schedule_rounded, 't2_slot_time'.tr, AppTime.time(utc), _pickTime),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.repeat_rounded, text: 't2_slot_weekly_note'.tr),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(_error!, style: AppType.meta(context).copyWith(color: context.colors.kit.error.ink)),
        ],
        const SizedBox(height: AppSpace.md),
        AppButton.primary(
          key: const ValueKey('t2.slot.save'),
          label: 't2_slot_save'.tr,
          expand: true,
          busy: _saving,
          onPressed: subjects.isEmpty ? null : _save,
        ),
      ],
    );
  }
}
