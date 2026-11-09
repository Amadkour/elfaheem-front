// lib/features/org/advising/adv_appointments.dart — advising appointments (docs/advising/PHASE5.md "Appointments"): the
// booking sheet (advisor → day strip → free times by way of meeting → reason → confirm), the appointment card and
// list (upcoming / past), the reschedule and cancel sheets, completed / no-show, "Add meeting note" (the notes
// composer with the template picker and the appointment), "Add to calendar" (.ics) and Join (the platform's meeting
// or the advisor's https link).
//
//   AdvBookingForm · AdvAppointmentCard · AdvAppointmentList · AdvCancelForm · AdvMeetingsPane   plain values
//   showAdvBookingSheet · showAdvCancelSheet · showAdvMeetingNoteSheet · AdvApptFlow (the actions)   load / write
//   AdvAppointmentsPage   every appointment of the caller (staff) or of the student, upcoming / past
// Every time is a UTC instant shown through AppTime in the organization's zone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_page_kit.dart';
import '../org_providers.dart' show OrgSession;
import '../org_ui.dart' show orgNameOf;
import '../org_v3.dart' show orgCall;
import 'adv_appt_models.dart';
import 'adv_case_parts.dart' show AdvTypedField, AdvTypedText;
import 'adv_comm_api.dart';
import 'adv_comm_parts.dart';
import 'adv_models.dart';
import 'adv_notes.dart' show AdvNoteComposer;
import 'adv_parts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  The booking form (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// Days the booking strip shows at once.
const advBookingWindowDays = 14;

class AdvBookingForm extends StatelessWidget {
  const AdvBookingForm({
    super.key,
    required this.advisors,
    required this.advisorUserId,
    required this.days,
    required this.counts,
    required this.slots,
    required this.modes,
    required this.reason,
    this.day,
    this.slot,
    this.mode,
    this.rules = const AdvBookingRules(),
    this.load = AdvLoad.ready,
    this.reschedule = false,
    this.staff = false,
    this.studentName,
    this.force = false,
    this.offerForce = false,
    this.busy = false,
    this.error,
    this.onAdvisor,
    this.onDay,
    this.onPrev,
    this.onNext,
    this.onSlot,
    this.onMode,
    this.onForce,
    this.onRetry,
    this.onSubmit,
  });

  /// (user id, name) of the advisors that can be booked.
  final List<(int, String)> advisors;
  final int advisorUserId;
  final List<DateTime> days;

  /// day key → free times that day (in the chosen way of meeting).
  final Map<String, int> counts;

  /// The chosen day's free times.
  final List<AdvSlot> slots;

  /// The ways of meeting the loaded slots offer.
  final List<String> modes;
  final TextEditingController reason;
  final DateTime? day;
  final AdvSlot? slot;
  final String? mode;
  final AdvBookingRules rules;

  /// The free times' state.
  final AdvLoad load;
  final bool reschedule, staff;

  /// Staff booking for a student: their name in the summary.
  final String? studentName;
  final bool force, offerForce, busy;
  final String? error;
  final ValueChanged<int>? onAdvisor;
  final ValueChanged<DateTime>? onDay;
  final VoidCallback? onPrev, onNext, onRetry, onSubmit;
  final ValueChanged<AdvSlot>? onSlot;
  final ValueChanged<String>? onMode;
  final ValueChanged<bool>? onForce;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = slot;
    final err = error;
    final name = [for (final a in advisors) if (a.$1 == advisorUserId) a.$2].firstOrNull ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (advisors.length > 1) ...[
        AdvFieldLabel(t('مع', 'With')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in advisors)
            AppChoiceChip(label: a.$2, icon: Icons.person_outline_rounded, selected: a.$1 == advisorUserId, onTap: busy || onAdvisor == null ? () {} : () => onAdvisor!(a.$1)),
        ]),
        const SizedBox(height: AppSpace.md),
      ] else if (name.isNotEmpty && !staff) ...[
        AdvInfoLine(icon: Icons.co_present_rounded, text: t('مع $name', 'With $name')),
        const SizedBox(height: AppSpace.sm),
      ],
      if (modes.length > 1 || (modes.length == 1 && mode == null)) ...[
        AdvFieldLabel(t('طريقة اللقاء', 'How to meet'), hint: mode == null ? null : advModeHintFor(mode!)),
        AdvModeChips(modes: modes, selected: mode, onChanged: busy ? null : onMode),
        const SizedBox(height: AppSpace.md),
      ],
      AdvFieldLabel(t('اليوم', 'Day'), hint: reschedule ? null : rules.summary),
      AdvDateStrip(days: days, selected: day, counts: counts, onSelect: (d) => onDay?.call(d), onPrev: busy ? null : onPrev, onNext: busy ? null : onNext),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(day == null ? t('الوقت', 'Time') : t('الوقت · ${advDayLabel(day!, pattern: 'EEEE d MMMM')}', 'Time · ${advDayLabel(day!, pattern: 'EEEE d MMMM')}'),
          hint: t('بتوقيت المؤسسة', 'In the organization\'s time')),
      switch (load) {
        AdvLoad.ready => AdvSlotPicker(slots: slots, selected: s, onSelect: (x) => onSlot?.call(x)),
        AdvLoad.loading => const AppListSkeleton(items: 1),
        _ => AdvLoadState(state: load, errorText: t('تعذّر تحميل المواعيد المتاحة', 'Could not load the free times'), onRetry: onRetry, items: 1),
      },
      if (s != null) ...[
        const SizedBox(height: AppSpace.md),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.primary.withValues(alpha: c.isDark ? 0.16 : 0.06), borderRadius: AppRadius.chipAll, border: Border.all(color: c.primary.withValues(alpha: 0.3))),
          child: Row(children: [
            ExcludeSemantics(child: Icon(mode == null ? Icons.event_rounded : advModeIcon(mode), color: appInk(context, c.primary))),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${AppTime.date(s.startsAt, pattern: 'EEEE d MMMM')} · ${AppTime.time(s.startsAt)} – ${AppTime.time(s.endsAt)}', style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (mode != null) advMeetingModeLabel(mode!),
                    if (mode == 'in_person' && s.location != null) s.location!,
                    if (staff && (studentName ?? '').isNotEmpty) studentName!,
                    if (!staff && name.isNotEmpty) name,
                  ].join(' · '),
                  style: AppType.meta(context),
                ),
              ]),
            ),
          ]),
        ),
      ],
      if (!reschedule) ...[
        const SizedBox(height: AppSpace.md),
        AdvTypedField(
          controller: reason,
          label: staff ? t('موضوع اللقاء (اختياري)', 'What it is about (optional)') : t('سبب اللقاء (اختياري)', 'What you want to talk about (optional)'),
          hint: staff ? null : t('يساعد المرشد على التحضير', 'It helps your advisor prepare'),
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          enabled: !busy,
        ),
      ],
      if (staff && offerForce)
        AppSwitchTile(
          icon: Icons.event_repeat_rounded,
          title: t('احجز رغم ارتباط الطالب', 'Book although the student is busy'),
          subtitle: t('يصل الطالب إشعار بالموعد ليعيد ترتيب وقته', 'The student is told and can rearrange their time'),
          value: force,
          onChanged: busy ? null : onForce,
        ),
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        icon: reschedule ? Icons.event_repeat_rounded : Icons.event_available_rounded,
        label: reschedule ? t('نقل الموعد', 'Move the appointment') : t('تأكيد الحجز', 'Confirm the booking'),
        busy: busy,
        onPressed: s == null || mode == null ? null : onSubmit,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The booking sheet (loads the free times)
// ═════════════════════════════════════════════════════════════════════════════

/// Books (or, with [reschedule], moves) an appointment. [advisors] = who can be booked (a student: their advisors
/// with office hours; staff: themself); [memberId] / [studentName] when staff book for a student. Returns the
/// appointment the server made.
Future<AdvAppointment?> showAdvBookingSheet(
  BuildContext context,
  AdvCommApi api, {
  required List<(int, String)> advisors,
  int? memberId,
  String? studentName,
  AdvBookingRules rules = const AdvBookingRules(),
  AdvAppointment? reschedule,
}) =>
    showAppSheet<AdvAppointment>(
      context,
      (_) => _AdvBookingSheet(api: api, advisors: advisors, memberId: memberId, studentName: studentName, rules: rules, reschedule: reschedule),
    );

class _AdvBookingSheet extends StatefulWidget {
  const _AdvBookingSheet({required this.api, required this.advisors, required this.rules, this.memberId, this.studentName, this.reschedule});
  final AdvCommApi api;
  final List<(int, String)> advisors;
  final int? memberId;
  final String? studentName;
  final AdvBookingRules rules;
  final AdvAppointment? reschedule;

  @override
  State<_AdvBookingSheet> createState() => _AdvBookingSheetState();
}

class _AdvBookingSheetState extends State<_AdvBookingSheet> {
  final _reason = TextEditingController();
  late int _advisor = widget.reschedule?.advisorUserId ?? widget.advisors.first.$1;
  late final DateTime _today = advZoneToday();
  late DateTime _from = _today;
  AdvSlots _slots = const AdvSlots();
  AdvLoad _load = AdvLoad.loading;
  DateTime? _day;
  AdvSlot? _slot;
  String? _mode;
  bool _busy = false, _force = false, _offerForce = false;
  String? _error;
  int _req = 0;

  bool get _staff => !widget.api.student;
  DateTime get _last => _today.add(Duration(days: widget.rules.horizonDays.clamp(1, 365)));

  @override
  void initState() {
    super.initState();
    _mode = widget.reschedule?.mode;
    _loadSlots();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  List<DateTime> get _days {
    final out = <DateTime>[];
    for (var i = 0; i < advBookingWindowDays; i++) {
      final d = DateTime(_from.year, _from.month, _from.day + i);
      if (d.isAfter(_last)) break;
      out.add(d);
    }
    return out;
  }

  Future<void> _loadSlots() async {
    final req = ++_req;
    final days = _days;
    setState(() {
      _load = AdvLoad.loading;
      _slot = null;
    });
    final r = await orgCall(() => widget.api.slots(_advisor, from: days.first, to: days.last, memberId: widget.memberId), quiet: true);
    if (!mounted || req != _req) return;
    setState(() {
      if (r.ok) {
        _slots = r.data as AdvSlots;
        _load = AdvLoad.ready;
        final modes = _slots.modes;
        if (_mode != null && !modes.contains(_mode)) _mode = null;
        if (_mode == null && modes.length == 1) _mode = modes.first;
        final by = _slots.byDay(mode: _mode);
        final keep = _day != null && days.any((d) => advDayKey(d) == advDayKey(_day!)) && (by[advDayKey(_day!)]?.isNotEmpty ?? false);
        if (!keep) _day = days.where((d) => by[advDayKey(d)]?.isNotEmpty ?? false).firstOrNull ?? days.first;
      } else {
        _load = advFailLoad(r);
      }
    });
  }

  void _shift(int by) {
    final next = DateTime(_from.year, _from.month, _from.day + by * advBookingWindowDays);
    if (next.isBefore(_today) || next.isAfter(_last)) return;
    _from = next;
    _day = null;
    _loadSlots();
  }

  Future<void> _submit() async {
    final s = _slot, m = _mode;
    if (s == null || m == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final re = widget.reschedule;
    final r = await orgCall(
      () => re != null
          ? widget.api.reschedule(re.id, startsAt: s.startsAt, mode: m, force: _staff && _force)
          : widget.api.book(AdvBookDraft(advisorUserId: _advisor, memberId: widget.memberId, slot: s, mode: m, reason: _reason.text, force: _staff && _force)),
      quiet: true,
    );
    if (!mounted) return;
    if (!r.ok) {
      final code = r.error!.code;
      setState(() {
        _busy = false;
        _error = advCommErrorText(r.error!);
        if (code == 'advising_student_busy' && _staff) _offerForce = true;
      });
      // the time went meanwhile: show what is free now
      if (code == 'advising_slot_taken' || code == 'advising_bad_slot') _loadSlots();
      return;
    }
    final a = r.data as AdvAppointment;
    showAppNotice(re != null
        ? t('نُقل الموعد إلى ${a.whenText}', 'Appointment moved to ${a.whenText}')
        : t('تم الحجز: ${a.whenText}', 'Booked: ${a.whenText}'));
    Navigator.pop(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final by = _slots.byDay(mode: _mode);
    final dayKey = _day == null ? null : advDayKey(_day!);
    return AppSheetContent(
      title: widget.reschedule != null ? t('نقل الموعد', 'Move the appointment') : t('حجز موعد إرشاد', 'Book an advising appointment'),
      children: [
        if (widget.reschedule != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AdvInfoLine(icon: Icons.history_rounded, text: t('الموعد الحالي: ${widget.reschedule!.whenText}', 'Now: ${widget.reschedule!.whenText}')),
          ),
        AdvBookingForm(
          advisors: widget.advisors,
          advisorUserId: _advisor,
          days: days,
          counts: {for (final e in by.entries) e.key: e.value.length},
          slots: dayKey == null ? const [] : (by[dayKey] ?? const []),
          modes: _slots.modes,
          reason: _reason,
          day: _day,
          slot: _slot,
          mode: _mode,
          rules: widget.rules,
          load: _load,
          reschedule: widget.reschedule != null,
          staff: _staff,
          studentName: widget.studentName,
          force: _force,
          offerForce: _offerForce,
          busy: _busy,
          error: _error,
          onAdvisor: (id) {
            if (id == _advisor) return;
            setState(() {
              _advisor = id;
              _mode = null;
              _day = null;
            });
            _loadSlots();
          },
          onDay: (d) => setState(() {
            _day = d;
            _slot = null;
          }),
          onPrev: days.first.isAfter(_today) ? () => _shift(-1) : null,
          onNext: days.last.isBefore(_last) ? () => _shift(1) : null,
          onSlot: (s) => setState(() {
            _slot = s;
            _error = null;
            if (_mode == null || !s.modes.contains(_mode)) _mode = s.modes.length == 1 ? s.modes.first : (s.modes.contains(_mode) ? _mode : null);
          }),
          onMode: (m) => setState(() {
            _mode = m;
            if (_slot != null && !_slot!.modes.contains(m)) _slot = null;
          }),
          onForce: (v) => setState(() => _force = v),
          onRetry: _loadSlots,
          onSubmit: _submit,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Cancel
// ═════════════════════════════════════════════════════════════════════════════

class AdvCancelForm extends StatelessWidget {
  const AdvCancelForm({super.key, required this.appointment, required this.reason, this.staff = false, this.late = false, this.rules = const AdvBookingRules(), this.busy = false, this.error, this.onSubmit});
  final AdvAppointment appointment;
  final TextEditingController reason;

  /// Staff must give the reason (the student sees it).
  final bool staff;

  /// Cancelling now counts as late.
  final bool late;
  final AdvBookingRules rules;
  final bool busy;
  final String? error;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = appointment;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvInfoLine(icon: advModeIcon(a.mode), text: '${a.whenText} · ${advMeetingModeLabel(a.mode)}'),
      AdvInfoLine(icon: Icons.person_outline_rounded, text: staff ? a.studentShown : a.advisorShown),
      if (late && !staff) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.schedule_rounded, color: c.warning, text: rules.cancelSummary),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: reason,
        builder: (context, v, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdvTypedField(
            controller: reason,
            label: staff ? t('سبب الإلغاء (يراه الطالب)', 'Why it is cancelled (the student sees it)') : t('سبب الإلغاء (اختياري)', 'Why you cancel (optional)'),
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            enabled: !busy,
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
          ],
          const SizedBox(height: AppSpace.md),
          AppButton.danger(
            label: t('إلغاء الموعد', 'Cancel the appointment'),
            icon: Icons.event_busy_rounded,
            busy: busy,
            expand: true,
            onPressed: staff && v.text.trim().isEmpty ? null : onSubmit,
          ),
        ]),
      ),
    ]);
  }
}

Future<AdvAppointment?> showAdvCancelSheet(BuildContext context, AdvCommApi api, AdvAppointment a, {AdvBookingRules rules = const AdvBookingRules()}) {
  final reason = TextEditingController();
  final staff = !api.student;
  final late = a.lateIfCancelledAt(DateTime.now().toUtc(), rules);
  var busy = false;
  String? error;
  return showAppSheet<AdvAppointment>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.cancel(a.id, reason.text), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advCommErrorText(r.error!);
            });
            return;
          }
          showAppNotice(staff ? t('أُلغي الموعد وأُبلغ الطالب', 'Appointment cancelled — the student was told') : t('أُلغي الموعد وأُبلغ المرشد', 'Appointment cancelled — your advisor was told'));
          Navigator.pop(ctx, r.data as AdvAppointment);
        }

        return AppSheetContent(
          title: t('إلغاء الموعد', 'Cancel the appointment'),
          children: [AdvCancelForm(appointment: a, reason: reason, staff: staff, late: late, rules: rules, busy: busy, error: error, onSubmit: submit)],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Meeting note (the notes composer + a template)
// ═════════════════════════════════════════════════════════════════════════════

/// The placeholders' values for an appointment.
Map<String, String> advApptPlaceholders(AdvAppointment a, {String? orgName}) => {
      'student_name': a.studentName,
      'advisor_name': a.advisorName,
      'date': AppTime.date(a.startsAt),
      'time': AppTime.time(a.startsAt),
      'org_name': ?orgName,
    };

String? _orgName(BuildContext context, int orgId) {
  try {
    final s = context.read<OrgSession>();
    return s.currentId == orgId ? orgNameOf(s.current) : null;
  } catch (_) {
    return null;
  }
}

/// A template list as a dropdown: picking one fills [body] (placeholders filled).
class AdvTemplatePickerField extends StatelessWidget {
  const AdvTemplatePickerField({super.key, required this.templates, required this.selected, required this.onPick, this.enabled = true});
  final List<AdvTemplate> templates;
  final int? selected;
  final ValueChanged<AdvTemplate?> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppDropdown<int>(
        value: selected ?? 0,
        decoration: InputDecoration(labelText: t('ابدأ من قالب (اختياري)', 'Start from a template (optional)'), prefixIcon: const Icon(Icons.description_outlined)),
        items: [
          DropdownMenuItem(value: 0, child: Text(t('بلا قالب', 'No template'))),
          for (final x in templates) DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: !enabled ? null : (v) => onPick(v == null || v == 0 ? null : templates.where((x) => x.id == v).firstOrNull),
      );
}

/// Writes the meeting note of [a] (staff): the template picker, then the notes composer (contact logged in the
/// appointment's way of meeting). Returns the note.
Future<AdvNote?> showAdvMeetingNoteSheet(BuildContext context, AdvCommApi api, AdvAppointment a) {
  final values = advApptPlaceholders(a, orgName: _orgName(context, api.orgId));
  return showAppSheet<AdvNote>(context, (_) => _AdvMeetingNoteSheet(api: api, appointment: a, values: values));
}

class _AdvMeetingNoteSheet extends StatefulWidget {
  const _AdvMeetingNoteSheet({required this.api, required this.appointment, required this.values});
  final AdvCommApi api;
  final AdvAppointment appointment;
  final Map<String, String> values;

  @override
  State<_AdvMeetingNoteSheet> createState() => _AdvMeetingNoteSheetState();
}

class _AdvMeetingNoteSheetState extends State<_AdvMeetingNoteSheet> {
  final _body = TextEditingController();
  late AdvNoteDraft _draft = AdvNoteDraft(visibility: 'team', contactMode: widget.appointment.mode);
  List<AdvTemplate> _templates = const [];
  int? _template;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final r = await orgCall(() => widget.api.templates(kind: 'meeting_note'), quiet: true);
    if (mounted && r.ok) setState(() => _templates = [for (final x in r.data as List<AdvTemplate>) if (x.active) x]);
  }

  Future<void> _pick(AdvTemplate? x) async {
    if (x == null) {
      setState(() => _template = null);
      return;
    }
    if (_body.text.trim().isNotEmpty) {
      final yes = await appConfirm(context, message: t('استبدال ما كتبته بنص القالب؟', 'Replace what you wrote with the template text?'), confirmLabel: t('استبدال', 'Replace'));
      if (!yes || !mounted) return;
    }
    setState(() => _template = x.id);
    _body.text = advFillTemplate(x.body, widget.values);
  }

  Future<void> _submit() async {
    final d = _draft.copyWith(body: _body.text, clientId: () => _draft.clientId ?? 'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}');
    final why = d.error();
    if (why != null) {
      setState(() => _error = why);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _draft = d;
    });
    final r = await orgCall(() => widget.api.addMeetingNote(widget.appointment.memberId, d, appointmentId: widget.appointment.id, templateId: _template), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = advCommErrorText(r.error!);
      });
      return;
    }
    showAppNotice(t('حُفظت ملاحظة اللقاء', 'Meeting note saved'));
    Navigator.pop(context, r.data as AdvNote);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return AppSheetContent(
      title: t('ملاحظة اللقاء', 'Meeting note'),
      children: [
        AdvInfoLine(icon: advModeIcon(a.mode), text: '${a.studentShown} · ${a.whenText}'),
        const SizedBox(height: AppSpace.sm),
        if (_templates.isNotEmpty) ...[
          AdvTemplatePickerField(templates: _templates, selected: _template, onPick: _pick, enabled: !_busy),
          const SizedBox(height: AppSpace.sm),
        ],
        AdvNoteComposer(
          body: _body,
          draft: _draft,
          busy: _busy,
          error: _error,
          onVisibility: (v) => setState(() => _draft = _draft.copyWith(visibility: v)),
          onContact: (on) => setState(() => _draft = _draft.copyWith(contactMode: () => on ? a.mode : null)),
          onMode: (m) => setState(() => _draft = _draft.copyWith(contactMode: () => m)),
          onSubmit: _busy ? null : _submit,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The card and the list (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// What a card offers; null = not offered.
class AdvApptActions {
  const AdvApptActions({this.onJoin, this.onCalendar, this.onReschedule, this.onCancel, this.onComplete, this.onNoShow, this.onNote, this.onChat, this.onOpenStudent});
  final ValueChanged<AdvAppointment>? onJoin, onCalendar, onReschedule, onCancel, onComplete, onNoShow, onNote, onChat, onOpenStudent;
}

class AdvAppointmentCard extends StatelessWidget {
  const AdvAppointmentCard({super.key, required this.appointment, this.actions = const AdvApptActions(), this.staff = false, this.showStudent = true, this.showAdvisor = true, this.now});
  final AdvAppointment appointment;
  final AdvApptActions actions;

  /// The staff side (the student's name leads) or the student's (the advisor's).
  final bool staff;
  final bool showStudent, showAdvisor;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = appointment;
    final at = now ?? DateTime.now().toUtc();
    final upcoming = a.upcoming(at);
    final live = a.live(at);
    final who = staff ? (showStudent ? a.studentShown : null) : (showAdvisor ? a.advisorShown : null);
    final place = switch (a.mode) {
      'in_person' => a.location,
      'video' => a.hasLink ? t('رابط المرشد', 'The advisor\'s link') : (a.meetingId != null ? t('اجتماع المنصة', 'Platform meeting') : null),
      _ => null,
    };
    final buttons = <Widget>[];
    void add(String label, IconData icon, ValueChanged<AdvAppointment>? on, {bool danger = false}) {
      if (on == null) return;
      buttons.add(TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), foregroundColor: danger ? appInk(context, c.danger) : null),
        onPressed: () => on(a),
        icon: Icon(icon, size: AppIconSize.sm),
        label: Text(label),
      ));
    }

    if (a.booked) {
      if (a.mode == 'chat') add(t('المحادثة', 'Open the chat'), Icons.chat_bubble_outline_rounded, actions.onChat);
      if (upcoming) add(t('إضافة للتقويم', 'Add to calendar'), Icons.event_rounded, actions.onCalendar);
      if (a.can.reschedule) add(t('نقل', 'Move'), Icons.event_repeat_rounded, actions.onReschedule);
      if (a.can.complete) add(t('تم اللقاء', 'Mark held'), Icons.check_circle_outline_rounded, actions.onComplete);
      if (a.can.noShow) add(t('لم يحضر', 'No-show'), Icons.person_off_outlined, actions.onNoShow);
      if (a.can.cancel) add(t('إلغاء', 'Cancel'), Icons.event_busy_rounded, actions.onCancel, danger: true);
    }
    if (a.can.note && a.noteId == null && a.status != 'cancelled' && !upcoming) add(t('ملاحظة اللقاء', 'Meeting note'), Icons.edit_note_rounded, actions.onNote);
    if (staff && actions.onOpenStudent != null) add(t('ملف الطالب', 'Student record'), Icons.person_search_outlined, actions.onOpenStudent);

    final joinable = a.video && a.booked && (live || (upcoming && a.startsAt.difference(at).inMinutes <= 60)) && actions.onJoin != null;
    final dim = a.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DateBadge(at: a.startsAt, dim: dim),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${AppTime.time(a.startsAt)} – ${AppTime.time(a.endsAt)}',
                    style: AppType.row(context).copyWith(fontWeight: FontWeight.w700, decoration: dim ? TextDecoration.lineThrough : null, color: dim ? c.textMedium : null)),
                if (who != null) Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark)),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  AppBadgePill(advMeetingModeLabel(a.mode), color: c.primary, icon: advModeIcon(a.mode)),
                  if (!a.booked || !upcoming) AdvApptStatusPill(status: a.booked && !upcoming ? 'booked' : a.status),
                  if (live) AppBadgePill(t('الآن', 'Now'), color: c.success, icon: Icons.circle),
                  if (a.bookedBy == 'advisor' && !staff) AppBadgePill(t('حجزه المرشد', 'Booked by your advisor'), color: c.textMedium, icon: Icons.person_pin_outlined),
                  if (a.noteId != null && staff) AppBadgePill(t('كُتبت الملاحظة', 'Note written'), color: c.success, icon: Icons.sticky_note_2_outlined),
                ]),
              ]),
            ),
          ]),
          if (place != null) AdvInfoLine(icon: a.mode == 'video' ? Icons.link_rounded : Icons.place_outlined, text: place, typed: a.mode == 'in_person'),
          if (a.reason != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: AdvTypedText(a.reason!, maxLines: 3)),
          if (a.status == 'cancelled') ...[
            AdvInfoLine(icon: Icons.info_outline_rounded, text: advCancelText(a), color: a.lateCancel ? c.warning : null),
            if (a.cancelReason != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: AdvTypedText(a.cancelReason!, maxLines: 3, style: AppType.meta(context))),
          ],
          if (joinable) ...[
            const SizedBox(height: AppSpace.sm),
            AppButton.primary(label: live ? t('انضم الآن', 'Join now') : t('الانضمام للاجتماع', 'Join the meeting'), icon: Icons.videocam_rounded, expand: true, onPressed: () => actions.onJoin!(a)),
          ],
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xxs, runSpacing: 0, children: buttons),
          ],
        ]),
      ),
    );
  }
}

/// The day of an appointment as a small calendar leaf: weekday, day, month.
class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.at, this.dim = false});
  final DateTime at;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = dim ? c.textMedium : c.primary;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    return ExcludeSemantics(
      child: Container(
        width: 56 * scale,
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        decoration: BoxDecoration(color: col.withValues(alpha: c.isDark ? 0.18 : 0.08), borderRadius: AppRadius.chipAll),
        child: Column(children: [
          Text(AppTime.date(at, pattern: 'EEE'), maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: AppType.meta(context).copyWith(color: appInk(context, col))),
          Text(AppTime.date(at, pattern: 'd'), style: AppType.section(context).copyWith(color: appInk(context, col), height: 1.1)),
          Text(AppTime.date(at, pattern: 'MMM'), maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: AppType.meta(context).copyWith(color: appInk(context, col))),
        ]),
      ),
    );
  }
}

/// Upcoming and past appointments with their titles; [emptyUpcoming] says what to do when nothing is booked.
class AdvAppointmentList extends StatelessWidget {
  const AdvAppointmentList({
    super.key,
    required this.upcoming,
    required this.past,
    this.actions = const AdvApptActions(),
    this.staff = false,
    this.showStudent = true,
    this.emptyUpcoming,
    this.now,
    this.pastTitle,
  });

  final List<AdvAppointment> upcoming, past;
  final AdvApptActions actions;
  final bool staff, showStudent;
  final String? emptyUpcoming, pastTitle;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget card(AdvAppointment a) => AdvAppointmentCard(appointment: a, actions: actions, staff: staff, showStudent: showStudent, now: now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvSectionTitle(t('القادمة', 'Upcoming'), first: true, trailing: upcoming.isEmpty ? null : Text('${upcoming.length}', style: AppType.meta(context))),
      if (upcoming.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Row(children: [
            ExcludeSemantics(child: Icon(Icons.event_available_outlined, size: AppIconSize.md, color: c.textLight)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(emptyUpcoming ?? t('لا مواعيد قادمة', 'No upcoming appointments'), style: AppType.body(context))),
          ]),
        )
      else
        for (final a in upcoming) card(a),
      if (past.isNotEmpty) ...[
        AdvSectionTitle(pastTitle ?? t('السابقة', 'Past')),
        for (final a in past) card(a),
      ],
    ]);
  }
}

/// The 360's Meetings section: upcoming / past, the no-show count, "Book for the student".
class AdvMeetingsPane extends StatelessWidget {
  const AdvMeetingsPane({super.key, required this.meetings, this.actions = const AdvApptActions(), this.onBook, this.onAll, this.now});
  final AdvMeetings meetings;
  final AdvApptActions actions;
  final VoidCallback? onBook, onAll;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = meetings;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (onBook != null) AppButton.primary(label: t('حجز موعد للطالب', 'Book for the student'), icon: Icons.event_available_rounded, onPressed: onBook),
        if (m.noShows > 0)
          AppBadgePill(
            countText(m.noShows, ar1: 'غياب عن موعد واحد', ar2: 'غياب عن موعدين', arFew: 'غياب عن ${m.noShows} مواعيد', arMany: 'غياب عن ${m.noShows} موعداً', en1: '1 no-show', en: '${m.noShows} no-shows'),
            color: c.danger,
            icon: Icons.person_off_rounded,
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AdvAppointmentList(
        upcoming: m.upcoming,
        past: m.past,
        actions: actions,
        staff: true,
        showStudent: false,
        now: now,
        emptyUpcoming: t('لا مواعيد قادمة مع الطالب', 'No upcoming appointments with the student'),
      ),
      if (onAll != null && m.past.length >= 10)
        Align(
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: onAll,
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(t('كل المواعيد', 'Every appointment')),
          ),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The actions (one place for the hub, the 360 and the list page)
// ═════════════════════════════════════════════════════════════════════════════

/// Runs an appointment's actions and tells [onChanged] when one of them wrote something.
class AdvApptFlow {
  AdvApptFlow(this.api, {this.rules = const AdvBookingRules(), this.onChanged, this.onChat, this.onOpenStudent});
  final AdvCommApi api;
  final AdvBookingRules rules;
  final VoidCallback? onChanged;

  /// A chat appointment: open the student's conversation.
  final ValueChanged<AdvAppointment>? onChat;
  final ValueChanged<AdvAppointment>? onOpenStudent;

  bool get staff => !api.student;

  AdvApptActions actions(BuildContext context) => AdvApptActions(
        onJoin: (a) => advJoinAppointment(context, a),
        onCalendar: (a) => advShareIcs(api, a),
        onReschedule: (a) => _reschedule(context, a),
        onCancel: (a) => _cancel(context, a),
        onComplete: staff ? (a) => _status(context, a, 'completed') : null,
        onNoShow: staff ? (a) => _status(context, a, 'no_show') : null,
        onNote: staff ? (a) => _note(context, a) : null,
        onChat: onChat,
        onOpenStudent: onOpenStudent,
      );

  Future<void> _reschedule(BuildContext context, AdvAppointment a) async {
    final moved = await showAdvBookingSheet(context, api,
        advisors: [(a.advisorUserId, a.advisorShown)], memberId: staff ? a.memberId : null, studentName: a.studentShown, rules: rules, reschedule: a);
    if (moved != null) onChanged?.call();
  }

  Future<void> _cancel(BuildContext context, AdvAppointment a) async {
    final done = await showAdvCancelSheet(context, api, a, rules: rules);
    if (done != null) onChanged?.call();
  }

  Future<void> _status(BuildContext context, AdvAppointment a, String status) async {
    final held = status == 'completed';
    final yes = await appConfirm(
      context,
      danger: !held,
      confirmLabel: held ? t('تم اللقاء', 'Mark held') : t('لم يحضر', 'Mark no-show'),
      message: held
          ? t('تسجيل لقاء ${a.studentShown} (${a.whenText}) كتمّ؟ يصل الطالب استبيان قصير مجهول الهوية.',
              'Mark the meeting with ${a.studentShown} (${a.whenText}) as held? The student gets a short anonymous survey.')
          : t('تسجيل أن ${a.studentShown} لم يحضر موعد ${a.whenText}؟ يُبلَّغ الطالب بذلك.', 'Record that ${a.studentShown} did not come on ${a.whenText}? The student is told.'),
    );
    if (!yes || !context.mounted) return;
    final r = await orgCall(() => api.setStatus(a.id, status), quiet: true);
    if (!r.ok) {
      showAppNotice(advCommErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(held ? t('سُجّل اللقاء — اكتب ملاحظته الآن إن شئت', 'Meeting recorded — write its note now if you like') : t('سُجّل عدم الحضور', 'No-show recorded'));
    onChanged?.call();
    if (held && context.mounted) {
      final note = await showAdvMeetingNoteSheet(context, api, r.data as AdvAppointment);
      if (note != null) onChanged?.call();
    }
  }

  Future<void> _note(BuildContext context, AdvAppointment a) async {
    final note = await showAdvMeetingNoteSheet(context, api, a);
    if (note != null) onChanged?.call();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The list page
// ═════════════════════════════════════════════════════════════════════════════

/// Upcoming (soonest first) or past (newest first) appointments: the staff member's own (an advisor) or every one
/// (manage), or the student's own ([student]); [memberId] narrows it to one student (staff).
class AdvAppointmentsPage extends StatelessWidget {
  const AdvAppointmentsPage({super.key, required this.orgId, this.student = false, this.memberId, this.title, this.onOpenStudent, this.onChat});
  final int orgId;
  final bool student;
  final int? memberId;
  final String? title;
  final ValueChanged<AdvAppointment>? onOpenStudent, onChat;

  @override
  Widget build(BuildContext context) => AdvCommScaffold(
        orgId: orgId,
        title: title ?? (student ? t('مواعيدي', 'My appointments') : t('مواعيد الإرشاد', 'Advising appointments')),
        maxWidth: 1440,
        child: _AdvAppointmentsBody(orgId: orgId, student: student, memberId: memberId, onOpenStudent: onOpenStudent, onChat: onChat),
      );
}

class _AdvAppointmentsBody extends StatefulWidget {
  const _AdvAppointmentsBody({required this.orgId, required this.student, this.memberId, this.onOpenStudent, this.onChat});
  final int orgId;
  final bool student;
  final int? memberId;
  final ValueChanged<AdvAppointment>? onOpenStudent, onChat;

  @override
  State<_AdvAppointmentsBody> createState() => _AdvAppointmentsBodyState();
}

class _AdvAppointmentsBodyState extends State<_AdvAppointmentsBody> {
  late final AdvCommApi _api = AdvCommApi(widget.orgId, student: widget.student);
  OrgPageRefresh? _refresh;
  String _view = 'upcoming';
  final List<AdvAppointment> _items = [];
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  int _page = 1, _pages = 1, _req = 0;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() => _fetch();

  Future<void> _fetch({bool more = false}) async {
    final req = ++_req;
    final page = more ? _page + 1 : 1;
    if (more) setState(() => _loadingMore = true);
    final now = DateTime.now().toUtc();
    final up = _view == 'upcoming';
    final r = await orgCall(
      () => _api.appointments(memberId: widget.memberId, status: up ? 'booked' : null, from: up ? now : null, to: up ? null : now, page: page, size: 20),
      quiet: true,
    );
    if (!mounted || req != _req) return;
    setState(() {
      _loadingMore = false;
      if (r.ok) {
        final p = r.data as AdvPage<AdvAppointment>;
        if (!more) _items.clear();
        _items.addAll([for (final a in p.items) if (!_items.any((x) => x.id == a.id)) a]);
        _page = p.page;
        _pages = p.pages;
        _load = AdvLoad.ready;
      } else if (!more) {
        _load = advFailLoad(r);
        _error = advCommErrorText(r.error!);
      } else {
        showAppNotice(advCommErrorText(r.error!), error: true);
      }
    });
    if (r.ok && !more && mounted) OrgPageRefresh.reportUpdated(context);
  }

  @override
  Widget build(BuildContext context) {
    final flow = AdvApptFlow(_api, onChanged: _reload, onOpenStudent: widget.onOpenStudent, onChat: widget.onChat);
    final up = _view == 'upcoming';
    Widget body;
    if (_load != AdvLoad.ready) {
      body = AdvLoadState(state: _load, errorText: _error, onRetry: () {
        setState(() => _load = AdvLoad.loading);
        _reload();
      });
    } else if (_items.isEmpty) {
      body = AppEmpty(
        icon: up ? Icons.event_available_outlined : Icons.history_rounded,
        title: up ? t('لا مواعيد قادمة', 'No upcoming appointments') : t('لا مواعيد سابقة', 'No past appointments'),
        message: up
            ? (widget.student
                ? t('احجز موعداً مع مرشدك من صفحة «مرشدي».', 'Book one with your advisor from the "My advisor" page.')
                : t('تظهر هنا المواعيد التي يحجزها الطلاب في ساعاتك المكتبية.', 'Appointments students book in your office hours show here.'))
            : null,
      );
    } else {
      body = AdvPageFrame(maxWidth: 1440, children: [
        for (final a in _items) AdvAppointmentCard(appointment: a, actions: flow.actions(context), staff: !widget.student),
        if (_page < _pages)
          Align(
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
              onPressed: _loadingMore ? null : () => _fetch(more: true),
              icon: _loadingMore ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.expand_more_rounded),
              label: Text(t('المزيد', 'More')),
            ),
          ),
      ]);
    }
    return OrgPageBody(
      top: OrgSegmented<String>(
        value: _view,
        options: [('upcoming', t('القادمة', 'Upcoming')), ('past', t('السابقة', 'Past'))],
        onChanged: (v) {
          if (v == _view) return;
          setState(() {
            _view = v;
            _load = AdvLoad.loading;
          });
          _reload();
        },
      ),
      child: body,
    );
  }
}
