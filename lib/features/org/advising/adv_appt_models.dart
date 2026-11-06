// lib/features/org/advising/adv_appt_models.dart — pure models of the Academic Advising Phase 5 (docs/advising/PHASE5.md):
// availability (weekly rules in the organization's wall clock, days off), free slots and office hours, appointments,
// conversations (threads, messages, attachments), templates with their placeholders, the anonymous survey and its
// results, the student hub and the `/status` counts. No Flutter widgets: unit-tested in
// test/org/adv_appt_models_test.dart. Backend: ../back routers/organization/org_advising_comm_router.py.
//
// Every instant the server sends is naive UTC and is kept here as a UTC DateTime; the screens show it through
// AppTime (the organization's timezone, 12h / 24h). Every parser is tolerant of missing keys.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t;
import '../org_v3.dart' show orgParseUtc, orgUtc;
import 'adv_analytics_models.dart' show AdvHubOutreach;
import 'adv_models.dart' show AdvPage, AdvRef, advAdvisorTypeLabel, advMeetingModeLabel, advPriorityLabel;

// ═════════════════════════════════════════════════════════════════════════════
//  Small helpers
// ═════════════════════════════════════════════════════════════════════════════

String? _text(dynamic v) {
  final s = asStr(v).trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// A server instant (naive UTC) as a UTC DateTime.
DateTime? advUtc(dynamic v) => orgParseUtc(v)?.toUtc();

List<String> _modes(dynamic v) => v is List ? [for (final x in v) if (advApptModes.contains('$x')) '$x'] : const [];

/// "YYYY-MM-DD" of a calendar day (no time zone involved).
String advDayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A "YYYY-MM-DD" value as a calendar day (midnight, no zone), null when it is not one.
DateTime? advParseDay(dynamic v) {
  final s = _text(v);
  if (s == null || s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// A calendar day in the reader's language ("Mon 9 Nov" / "الاثنين 9 نوفمبر"); the day is drawn at noon UTC so no
/// zone moves it.
String advDayLabel(DateTime day, {String pattern = 'EEE d MMM'}) => AppTime.date(DateTime.utc(day.year, day.month, day.day, 12), pattern: pattern);

/// Today in the organization's timezone (the effective AppTime zone).
DateTime advZoneToday([DateTime? now]) {
  final w = AppTime.toZone((now ?? DateTime.now()).toUtc());
  return DateTime(w.year, w.month, w.day);
}

/// The calendar day (organization's zone) an instant falls on.
DateTime advZoneDay(DateTime utc) {
  final w = AppTime.toZone(utc.toUtc());
  return DateTime(w.year, w.month, w.day);
}

/// "HH:MM" → minutes after midnight (null when it is not one).
int? advMinutes(String? hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm?.trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
  if (h > 23 || mm > 59) return null;
  return h * 60 + mm;
}

/// Minutes after midnight → "HH:MM".
String advHhmm(int minutes) {
  final m = minutes.clamp(0, 23 * 60 + 59);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

/// How an appointment takes place, in the order the app offers them.
const advApptModes = ['in_person', 'video', 'phone', 'chat'];

/// The appointment lengths the server accepts.
const advSlotLengths = [15, 20, 30, 45, 60];

/// Weekdays as the server counts them: Monday = 0 … Sunday = 6.
String advWeekdayLabel(int wd, {bool short = false}) => switch (wd) {
      0 => short ? t('اثنين', 'Mon') : t('الاثنين', 'Monday'),
      1 => short ? t('ثلاثاء', 'Tue') : t('الثلاثاء', 'Tuesday'),
      2 => short ? t('أربعاء', 'Wed') : t('الأربعاء', 'Wednesday'),
      3 => short ? t('خميس', 'Thu') : t('الخميس', 'Thursday'),
      4 => short ? t('جمعة', 'Fri') : t('الجمعة', 'Friday'),
      5 => short ? t('سبت', 'Sat') : t('السبت', 'Saturday'),
      _ => short ? t('أحد', 'Sun') : t('الأحد', 'Sunday'),
    };

/// The week as a reader expects it: Saturday first in Arabic (the region's week), Monday first in English.
List<int> advWeekOrder() => AppConfig.lang == 'ar' ? const [5, 6, 0, 1, 2, 3, 4] : const [0, 1, 2, 3, 4, 5, 6];

const advApptStatuses = ['booked', 'completed', 'no_show', 'cancelled'];

String advApptStatusLabel(String s) => switch (s) {
      'booked' => t('محجوز', 'Booked'),
      'completed' => t('تم', 'Completed'),
      'no_show' => t('لم يحضر', 'No-show'),
      'cancelled' => t('أُلغي', 'Cancelled'),
      _ => s,
    };

/// "Cancelled by the student" / "… by the advisor" (+ "late").
String advCancelText(AdvAppointment a) {
  final who = switch (a.cancelledBy) {
    'student' => t('ألغاه الطالب', 'Cancelled by the student'),
    'advisor' => t('ألغاه المرشد', 'Cancelled by the advisor'),
    'system' => t('أُلغي تلقائياً', 'Cancelled automatically'),
    _ => t('أُلغي', 'Cancelled'),
  };
  return a.lateCancel ? '$who · ${t('إلغاء متأخر', 'late cancellation')}' : who;
}

String advModeHintFor(String mode) => switch (mode) {
      'video' => t('اجتماع مرئي عبر المنصة أو رابط المرشد', 'A video meeting on the platform or the advisor\'s link'),
      'phone' => t('يتصل بك المرشد حسب وسيلة التواصل في ملفه', 'The advisor calls you as their profile says'),
      'chat' => t('محادثة مكتوبة في رسائل الإرشاد', 'A written chat in your advising messages'),
      _ => t('في مكتب المرشد', 'At the advisor\'s office'),
    };

const advThreadStatuses = ['open', 'answered', 'closed', 'escalated'];
const advThreadPriorities = ['low', 'normal', 'high', 'urgent'];

String advThreadStatusLabel(String s) => switch (s) {
      'open' => t('بانتظار الرد', 'Awaiting reply'),
      'answered' => t('تم الرد', 'Answered'),
      'closed' => t('مغلقة', 'Closed'),
      'escalated' => t('مُصعّدة', 'Escalated'),
      _ => s,
    };

String advThreadKindLabel(String k, {String? about}) => switch (k) {
      'complaint' => about == 'advisor' ? t('شكوى عن المرشد', 'Complaint about the advisor') : t('شكوى', 'Complaint'),
      _ => t('رسالة', 'Message'),
    };

/// A governance work item's status (the escalated complaint), as the thread shows it.
String advWorkItemStatusLabel(String? s) => switch (s) {
      null || '' => '',
      'open' || 'new' || 'submitted' => t('مفتوحة', 'Open'),
      'in_progress' || 'assigned' || 'routed' => t('قيد المعالجة', 'In progress'),
      'resolved' || 'closed' || 'approved' || 'done' => t('مغلقة', 'Closed'),
      'rejected' => t('مرفوضة', 'Rejected'),
      _ => s,
    };

const advTemplateKinds = ['meeting_note', 'outreach', 'support_request', 'message'];

String advTemplateKindLabel(String k) => switch (k) {
      'meeting_note' => t('ملاحظة لقاء', 'Meeting note'),
      'outreach' => t('تواصل مبادر', 'Outreach'),
      'support_request' => t('طلب دعم', 'Support request'),
      'message' => t('رسالة', 'Message'),
      _ => k,
    };

/// The placeholders a template may hold; the app fills them before the person edits the text.
const advPlaceholders = ['student_name', 'advisor_name', 'date', 'time', 'org_name'];

String advPlaceholderLabel(String p) => switch (p) {
      'student_name' => t('اسم الطالب', 'Student name'),
      'advisor_name' => t('اسم المرشد', 'Advisor name'),
      'date' => t('التاريخ', 'Date'),
      'time' => t('الوقت', 'Time'),
      'org_name' => t('اسم المؤسسة', 'Organization name'),
      _ => p,
    };

/// [body] with each known placeholder (`{student_name}` …) replaced by its value in [values]; a placeholder without a
/// value and anything else between braces stay as written.
String advFillTemplate(String body, Map<String, String> values) => body.replaceAllMapped(RegExp(r'\{([a-z_]+)\}'), (m) {
      final key = m.group(1)!;
      final v = values[key];
      return advPlaceholders.contains(key) && v != null && v.isNotEmpty ? v : m.group(0)!;
    });

// ═════════════════════════════════════════════════════════════════════════════
//  Availability
// ═════════════════════════════════════════════════════════════════════════════

/// One weekly office-hours window, in the organization's wall clock.
class AdvRule {
  const AdvRule({
    this.id,
    this.weekday = 0,
    this.start = '09:00',
    this.end = '12:00',
    this.slotMinutes = 30,
    this.modes = const ['in_person'],
    this.location,
    this.videoLink,
    this.validFrom,
    this.validTo,
  });

  final int? id;

  /// Monday = 0 … Sunday = 6.
  final int weekday;

  /// "HH:MM".
  final String start, end;
  final int slotMinutes;
  final List<String> modes;
  final String? location, videoLink;

  /// Calendar days (no zone); null = open-ended.
  final DateTime? validFrom, validTo;

  factory AdvRule.fromJson(Map<String, dynamic> j) {
    final slot = asInt(j['slot_minutes'], 30);
    return AdvRule(
      id: j['id'] == null ? null : asInt(j['id']),
      weekday: asInt(j['weekday']).clamp(0, 6),
      start: _text(j['start']) ?? '09:00',
      end: _text(j['end']) ?? '12:00',
      slotMinutes: advSlotLengths.contains(slot) ? slot : 30,
      modes: _modes(j['modes']),
      location: _text(j['location']),
      videoLink: _text(j['video_link']),
      validFrom: advParseDay(j['valid_from']),
      validTo: advParseDay(j['valid_to']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': ?id,
        'weekday': weekday,
        'start': start,
        'end': end,
        'slot_minutes': slotMinutes,
        'modes': [for (final m in advApptModes) if (modes.contains(m)) m],
        'location': (location ?? '').trim().isEmpty ? null : location!.trim(),
        'video_link': modes.contains('video') && (videoLink ?? '').trim().isNotEmpty ? videoLink!.trim() : null,
        'valid_from': validFrom == null ? null : advDayKey(validFrom!),
        'valid_to': validTo == null ? null : advDayKey(validTo!),
      };

  AdvRule copyWith({
    int? weekday,
    String? start,
    String? end,
    int? slotMinutes,
    List<String>? modes,
    String? Function()? location,
    String? Function()? videoLink,
    DateTime? Function()? validFrom,
    DateTime? Function()? validTo,
  }) =>
      AdvRule(
        id: id,
        weekday: weekday ?? this.weekday,
        start: start ?? this.start,
        end: end ?? this.end,
        slotMinutes: slotMinutes ?? this.slotMinutes,
        modes: modes ?? this.modes,
        location: location == null ? this.location : location(),
        videoLink: videoLink == null ? this.videoLink : videoLink(),
        validFrom: validFrom == null ? this.validFrom : validFrom(),
        validTo: validTo == null ? this.validTo : validTo(),
      );

  int get startMin => advMinutes(start) ?? 0;
  int get endMin => advMinutes(end) ?? 0;

  /// How many appointments the window holds.
  int get slots => endMin <= startMin ? 0 : (endMin - startMin) ~/ slotMinutes;

  bool overlaps(AdvRule o) {
    if (o.weekday != weekday) return false;
    final a0 = validFrom, a1 = validTo, b0 = o.validFrom, b1 = o.validTo;
    // two windows valid in periods that never meet do not clash
    if (a1 != null && b0 != null && a1.isBefore(b0)) return false;
    if (b1 != null && a0 != null && b1.isBefore(a0)) return false;
    return startMin < o.endMin && o.startMin < endMin;
  }

  /// "9:00 AM – 12:00 PM · 30 min".
  String get timeText => AppTime.clockRange(start, end);
}

/// Is [link] an acceptable meeting link (https, a host, no credentials)?
bool advSecureLink(String link) {
  final u = Uri.tryParse(link.trim());
  return u != null && u.scheme == 'https' && u.host.isNotEmpty && u.userInfo.isEmpty;
}

/// Why the weekly rules cannot be saved (the server's own checks, bilingual), null when they can.
String? advRulesError(List<AdvRule> rules) {
  for (final r in rules) {
    if (r.modes.isEmpty) return t('اختر طريقة واحدة على الأقل لكل فترة', 'Choose at least one way to meet for each window');
    if (r.slots < 1) {
      return t('${advWeekdayLabel(r.weekday)}: وقت النهاية يجب أن يكون بعد البداية بمدة موعد واحد على الأقل',
          '${advWeekdayLabel(r.weekday)}: the end must be at least one appointment length after the start');
    }
    final link = r.videoLink?.trim() ?? '';
    if (r.modes.contains('video') && link.isNotEmpty && !advSecureLink(link)) {
      return t('رابط الاجتماع يجب أن يبدأ بـ https://', 'The meeting link must start with https://');
    }
    if (r.validFrom != null && r.validTo != null && r.validTo!.isBefore(r.validFrom!)) {
      return t('تاريخ نهاية الصلاحية قبل بدايتها', 'The "valid until" date is before the "valid from" date');
    }
  }
  for (var i = 0; i < rules.length; i++) {
    for (var j = i + 1; j < rules.length; j++) {
      if (rules[i].overlaps(rules[j])) {
        return t('فترتان متداخلتان يوم ${advWeekdayLabel(rules[i].weekday)} — عدّل إحداهما',
            'Two windows overlap on ${advWeekdayLabel(rules[i].weekday)} — change one of them');
      }
    }
  }
  return null;
}

/// A day off (or a run of days): calendar days in the organization's zone.
class AdvDayOff {
  const AdvDayOff({required this.id, required this.from, required this.to, this.reason});
  final int id;
  final DateTime from, to;
  final String? reason;

  factory AdvDayOff.fromJson(Map<String, dynamic> j) {
    final from = advParseDay(j['from']) ?? DateTime(2000);
    return AdvDayOff(id: asInt(j['id']), from: from, to: advParseDay(j['to']) ?? from, reason: _text(j['reason']));
  }

  int get days => to.difference(from).inDays + 1;

  String get rangeText => advDayKey(from) == advDayKey(to) ? advDayLabel(from, pattern: 'EEE d MMM y') : '${advDayLabel(from)} – ${advDayLabel(to, pattern: 'EEE d MMM y')}';
}

/// `GET …/advisors/{uid}/availability`.
class AdvAvailability {
  const AdvAvailability({this.rules = const [], this.off = const [], this.timezone = ''});
  final List<AdvRule> rules;
  final List<AdvDayOff> off;
  final String timezone;

  factory AdvAvailability.fromJson(Map<String, dynamic> j) => AdvAvailability(
        rules: [for (final m in asMapList(j['rules'])) AdvRule.fromJson(m)]..sort(advRuleOrder),
        off: [for (final m in asMapList(j['off'])) AdvDayOff.fromJson(m)]..sort((a, b) => a.from.compareTo(b.from)),
        timezone: asStr(j['timezone']),
      );

  /// The rules of one weekday, earliest first.
  List<AdvRule> on(int weekday) => [for (final r in rules) if (r.weekday == weekday) r];
}

/// Week order of the reader, then start time.
int advRuleOrder(AdvRule a, AdvRule b) {
  final order = advWeekOrder();
  final d = order.indexOf(a.weekday) - order.indexOf(b.weekday);
  return d != 0 ? d : a.startMin - b.startMin;
}

/// `POST …/off`: the new day off and the booked appointments it covers (they are NOT cancelled by it).
class AdvOffResult {
  const AdvOffResult({required this.off, this.affected = const []});
  final AdvDayOff off;
  final List<int> affected;

  factory AdvOffResult.fromJson(Map<String, dynamic> j) =>
      AdvOffResult(off: AdvDayOff.fromJson(j), affected: [for (final x in (j['affected'] is List ? j['affected'] as List : const [])) asInt(x)]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Slots and office hours
// ═════════════════════════════════════════════════════════════════════════════

class AdvSlot {
  const AdvSlot({required this.startsAt, required this.endsAt, this.modes = const [], this.location});
  final DateTime startsAt, endsAt;
  final List<String> modes;
  final String? location;

  factory AdvSlot.fromJson(Map<String, dynamic> j) {
    final s = advUtc(j['starts_at']) ?? DateTime.utc(2000);
    return AdvSlot(startsAt: s, endsAt: advUtc(j['ends_at']) ?? s, modes: _modes(j['modes']), location: _text(j['location']));
  }

  int get minutes => endsAt.difference(startsAt).inMinutes;
}

/// `GET …/advisors/{uid}/slots`: free slots, grouped by the organization's calendar day.
class AdvSlots {
  const AdvSlots({this.slots = const [], this.timezone = ''});
  final List<AdvSlot> slots;
  final String timezone;

  factory AdvSlots.fromJson(Map<String, dynamic> j) =>
      AdvSlots(slots: [for (final m in asMapList(j['slots'])) AdvSlot.fromJson(m)]..sort((a, b) => a.startsAt.compareTo(b.startsAt)), timezone: asStr(j['timezone']));

  /// day key ("YYYY-MM-DD", organization's zone) → its slots that offer [mode] (null: any), in order.
  Map<String, List<AdvSlot>> byDay({String? mode}) {
    final out = <String, List<AdvSlot>>{};
    for (final s in slots) {
      if (mode != null && !s.modes.contains(mode)) continue;
      out.putIfAbsent(advDayKey(advZoneDay(s.startsAt)), () => []).add(s);
    }
    return out;
  }

  /// The ways to meet any slot offers, in the app's order.
  List<String> get modes => [for (final m in advApptModes) if (slots.any((s) => s.modes.contains(m))) m];
}

/// One weekday window of the office hours (no links).
class AdvOfficeRule {
  const AdvOfficeRule({this.weekday = 0, this.start = '', this.end = '', this.modes = const [], this.location});
  final int weekday;
  final String start, end;
  final List<String> modes;
  final String? location;

  factory AdvOfficeRule.fromJson(Map<String, dynamic> j) => AdvOfficeRule(
        weekday: asInt(j['weekday']).clamp(0, 6),
        start: asStr(j['start']),
        end: asStr(j['end']),
        modes: _modes(j['modes']),
        location: _text(j['location']),
      );
}

/// `GET …/advisors/{uid}/office-hours` (and each hub advisor's `office_hours`).
class AdvOfficeHours {
  const AdvOfficeHours({this.rules = const [], this.timezone = '', this.nextFree});
  final List<AdvOfficeRule> rules;
  final String timezone;
  final DateTime? nextFree;

  factory AdvOfficeHours.fromJson(Map<String, dynamic> j) => AdvOfficeHours(
        rules: [for (final m in asMapList(j['rules'])) AdvOfficeRule.fromJson(m)],
        timezone: asStr(j['timezone']),
        nextFree: advUtc(j['next_free']),
      );

  bool get isEmpty => rules.isEmpty;

  /// One line per weekday in the reader's week order: (weekday, "9:00 – 12:00 · 2:00 – 4:00 PM").
  List<(int, String)> get lines {
    final out = <(int, String)>[];
    for (final wd in advWeekOrder()) {
      final day = [for (final r in rules) if (r.weekday == wd) r]..sort((a, b) => (advMinutes(a.start) ?? 0) - (advMinutes(b.start) ?? 0));
      if (day.isEmpty) continue;
      out.add((wd, day.map((r) => AppTime.clockRange(r.start, r.end)).join(' · ')));
    }
    return out;
  }

  /// The ways to meet across the week.
  List<String> get modes => [for (final m in advApptModes) if (rules.any((r) => r.modes.contains(m))) m];
}

// ═════════════════════════════════════════════════════════════════════════════
//  Appointments
// ═════════════════════════════════════════════════════════════════════════════

class AdvApptCan {
  const AdvApptCan({this.cancel = false, this.reschedule = false, this.complete = false, this.noShow = false, this.note = false});
  final bool cancel, reschedule, complete, noShow, note;

  factory AdvApptCan.fromJson(Map<String, dynamic> j) => AdvApptCan(
        cancel: asBool(j['cancel']),
        reschedule: asBool(j['reschedule']),
        complete: asBool(j['complete']),
        noShow: asBool(j['no_show']),
        note: asBool(j['note']),
      );
}

class AdvAppointment {
  const AdvAppointment({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    this.memberId = 0,
    this.studentName = '',
    this.advisorUserId = 0,
    this.advisorName = '',
    this.mode = 'in_person',
    this.location,
    this.videoLink,
    this.meetingId,
    this.status = 'booked',
    this.reason,
    this.cancelReason,
    this.cancelledBy,
    this.lateCancel = false,
    this.noteId,
    this.bookedBy = 'student',
    this.createdAt,
    this.can = const AdvApptCan(),
  });

  final int id, memberId, advisorUserId;
  final String studentName, advisorName;
  final DateTime startsAt, endsAt;

  /// `in_person` · `video` · `phone` · `chat`.
  final String mode;
  final String? location, videoLink;

  /// The mirrored calendar meeting (a video appointment without a link is an ONLINE one: the calendar's Join).
  final int? meetingId;

  /// `booked` · `cancelled` · `completed` · `no_show`.
  final String status;
  final String? reason, cancelReason;

  /// `student` · `advisor` · `system`.
  final String? cancelledBy;
  final bool lateCancel;
  final int? noteId;

  /// `student` · `advisor`.
  final String bookedBy;
  final DateTime? createdAt;
  final AdvApptCan can;

  factory AdvAppointment.fromJson(Map<String, dynamic> j) {
    final s = advUtc(j['starts_at']) ?? DateTime.utc(2000);
    final st = asStr(j['status'], 'booked');
    final mode = asStr(j['mode'], 'in_person');
    return AdvAppointment(
      id: asInt(j['id']),
      memberId: asInt(j['member_id']),
      studentName: asStr(j['student_name']).trim(),
      advisorUserId: asInt(j['advisor_user_id']),
      advisorName: asStr(j['advisor_name']).trim(),
      startsAt: s,
      endsAt: advUtc(j['ends_at']) ?? s,
      mode: advApptModes.contains(mode) ? mode : 'in_person',
      location: _text(j['location']),
      videoLink: _text(j['video_link']),
      meetingId: j['meeting_id'] == null ? null : asInt(j['meeting_id']),
      status: advApptStatuses.contains(st) ? st : 'booked',
      reason: _text(j['reason']),
      cancelReason: _text(j['cancel_reason']),
      cancelledBy: _text(j['cancelled_by']),
      lateCancel: asBool(j['late_cancel']),
      noteId: j['note_id'] == null ? null : asInt(j['note_id']),
      bookedBy: asStr(j['booked_by'], 'student'),
      createdAt: advUtc(j['created_at']),
      can: AdvApptCan.fromJson(asMap(j['can'])),
    );
  }

  String get studentShown => studentName.isEmpty ? '#$memberId' : studentName;
  String get advisorShown => advisorName.isEmpty ? '#$advisorUserId' : advisorName;

  bool get booked => status == 'booked';
  bool upcoming(DateTime now) => booked && startsAt.isAfter(now);

  /// Taking place now (from 10 minutes before the start until the end).
  bool live(DateTime now) => booked && !now.isBefore(startsAt.subtract(const Duration(minutes: 10))) && now.isBefore(endsAt);

  /// A video appointment: the advisor's own https link, else the platform's online meeting.
  bool get video => mode == 'video';
  bool get hasLink => (videoLink ?? '').isNotEmpty && advSecureLink(videoLink!);

  /// "Mon 9 Nov · 10:00 – 10:30 AM".
  String get whenText => '${AppTime.date(startsAt, pattern: 'EEE d MMM')} · ${AppTime.time(startsAt)} – ${AppTime.time(endsAt)}';

  /// Cancelling now counts as late (within [rules]' notice), the student is told so before confirming.
  bool lateIfCancelledAt(DateTime now, AdvBookingRules rules) => startsAt.difference(now).inMinutes < rules.cancelMinNoticeHours * 60;
}

/// What a student (or an advisor for a student) books.
class AdvBookDraft {
  const AdvBookDraft({required this.advisorUserId, this.memberId, this.slot, this.mode, this.reason = '', this.force = false});

  final int advisorUserId;

  /// Staff only: the student (a student books for themself: null).
  final int? memberId;
  final AdvSlot? slot;
  final String? mode;
  final String reason;

  /// Staff only: book even when the student's calendar is busy.
  final bool force;

  AdvBookDraft copyWith({AdvSlot? Function()? slot, String? Function()? mode, String? reason, bool? force}) => AdvBookDraft(
        advisorUserId: advisorUserId,
        memberId: memberId,
        slot: slot == null ? this.slot : slot(),
        mode: mode == null ? this.mode : mode(),
        reason: reason ?? this.reason,
        force: force ?? this.force,
      );

  bool get ready => slot != null && mode != null && slot!.modes.contains(mode);

  /// Why it cannot be booked yet, null when it can.
  String? error() {
    if (slot == null) return t('اختر موعداً', 'Pick a time');
    if (mode == null || !slot!.modes.contains(mode)) return t('اختر طريقة اللقاء', 'Choose how to meet');
    if (reason.trim().length > 500) return t('السبب أطول من 500 حرف', 'The reason is longer than 500 characters');
    return null;
  }

  Map<String, dynamic> toJson() => {
        'member_id': ?memberId,
        'advisor_user_id': advisorUserId,
        'starts_at': orgUtc(slot?.startsAt),
        'mode': mode,
        'reason': reason.trim().isEmpty ? null : reason.trim(),
        if (force) 'force': true,
      };
}

/// One clash the server names with `advising_student_busy` (no titles).
class AdvBusySpan {
  const AdvBusySpan({required this.source, required this.startsAt, required this.endsAt});
  final String source;
  final DateTime startsAt, endsAt;

  /// The `conflicts` of an error body's `detail`.
  static List<AdvBusySpan> listOf(dynamic detail) => [
        for (final m in asMapList(asMap(detail)['conflicts']))
          AdvBusySpan(source: asStr(m['source']), startsAt: advUtc(m['starts_at']) ?? DateTime.utc(2000), endsAt: advUtc(m['ends_at']) ?? DateTime.utc(2000)),
      ];

  String get sourceLabel => switch (source) {
        'timetable' || 'slot' => t('محاضرة', 'A class'),
        'exam' => t('امتحان', 'An exam'),
        'meeting' => t('اجتماع', 'A meeting'),
        'session' || 'live' => t('جلسة مباشرة', 'A live session'),
        'appointment' || 'advising' => t('موعد إرشاد', 'An advising appointment'),
        _ => t('ارتباط', 'Something'),
      };
}

/// The booking rules of the student's scope (the hub's `booking_rules`).
class AdvBookingRules {
  const AdvBookingRules({this.minNoticeHours = 2, this.horizonDays = 30, this.cancelMinNoticeHours = 2, this.maxActiveBookings = 2});
  final int minNoticeHours, horizonDays, cancelMinNoticeHours, maxActiveBookings;

  factory AdvBookingRules.fromJson(Map<String, dynamic> j) {
    const d = AdvBookingRules();
    return AdvBookingRules(
      minNoticeHours: j.containsKey('min_notice_hours') ? asInt(j['min_notice_hours'], d.minNoticeHours) : d.minNoticeHours,
      horizonDays: j.containsKey('horizon_days') ? asInt(j['horizon_days'], d.horizonDays) : d.horizonDays,
      cancelMinNoticeHours: j.containsKey('cancel_min_notice_hours') ? asInt(j['cancel_min_notice_hours'], d.cancelMinNoticeHours) : d.cancelMinNoticeHours,
      maxActiveBookings: j.containsKey('max_active_bookings') ? asInt(j['max_active_bookings'], d.maxActiveBookings) : d.maxActiveBookings,
    );
  }

  /// "Book at least 2 hours ahead, up to 30 days."
  String get summary {
    final h = countText(minNoticeHours, ar1: 'ساعة', ar2: 'ساعتين', arFew: '$minNoticeHours ساعات', arMany: '$minNoticeHours ساعة', en1: '1 hour', en: '$minNoticeHours hours');
    final d = countText(horizonDays, ar1: 'يوم واحد', ar2: 'يومين', arFew: '$horizonDays أيام', arMany: '$horizonDays يوماً', en1: '1 day', en: '$horizonDays days');
    return t('احجز قبل الموعد بـ $h على الأقل، وحتى $d مقدماً', 'Book at least $h ahead, up to $d in advance');
  }

  /// "Cancel at least 2 hours before, or it counts as late."
  String get cancelSummary {
    final h = countText(cancelMinNoticeHours,
        ar1: 'ساعة', ar2: 'ساعتين', arFew: '$cancelMinNoticeHours ساعات', arMany: '$cancelMinNoticeHours ساعة', en1: '1 hour', en: '$cancelMinNoticeHours hours');
    return t('الإلغاء قبل الموعد بأقل من $h يُحتسب متأخراً ويُبلَّغ به المرشد', 'Cancelling less than $h before counts as late and the advisor is told');
  }
}

/// The 360's `meetings`: the next booked, the last others, how many no-shows.
class AdvMeetings {
  const AdvMeetings({this.upcoming = const [], this.past = const [], this.noShows = 0});
  final List<AdvAppointment> upcoming, past;
  final int noShows;

  factory AdvMeetings.fromJson(Map<String, dynamic> j) => AdvMeetings(
        upcoming: [for (final m in asMapList(j['upcoming'])) AdvAppointment.fromJson(m)],
        past: [for (final m in asMapList(j['past'])) AdvAppointment.fromJson(m)],
        noShows: asInt(j['no_shows']),
      );

  bool get isEmpty => upcoming.isEmpty && past.isEmpty;
}

/// `{"open","unread"}` of one student's conversations.
class AdvThreadCounts {
  const AdvThreadCounts({this.open = 0, this.unread = 0});
  final int open, unread;
  factory AdvThreadCounts.fromJson(Map<String, dynamic> j) => AdvThreadCounts(open: asInt(j['open']), unread: asInt(j['unread']));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Conversations
// ═════════════════════════════════════════════════════════════════════════════

class AdvAttachment {
  const AdvAttachment({required this.id, this.name = '', this.mime = '', this.size = 0});
  final int id;
  final String name, mime;
  final int size;

  factory AdvAttachment.fromJson(Map<String, dynamic> j) =>
      AdvAttachment(id: asInt(j['id']), name: asStr(j['name']).trim(), mime: asStr(j['mime']), size: asInt(j['size']));

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'mime': mime, 'size': size};

  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isImage => mime.startsWith('image/') || const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(ext);
  bool get isPdf => mime == 'application/pdf' || ext == 'pdf';
  String get shown => name.isEmpty ? '#$id' : name;
}

/// The most attachments one message carries.
const advMaxAttachments = 5;

/// The longest message / subject the server keeps.
const advMessageMax = 5000;
const advSubjectMax = 200;

class AdvThread {
  const AdvThread({
    required this.id,
    this.memberId = 0,
    this.studentName = '',
    this.kind = 'message',
    this.about,
    this.subject = '',
    this.status = 'open',
    this.priority = 'normal',
    this.slaDueAt,
    this.overdue = false,
    this.lastMessageAt,
    this.preview = '',
    this.unread = 0,
    this.workItemId,
    this.workItemStatus,
    this.escalatedAt,
    this.createdAt,
  });

  final int id, memberId;
  final String studentName;

  /// `message` · `complaint`.
  final String kind;

  /// A complaint's `advisor` · `other`.
  final String? about;
  final String subject;

  /// `open` (the student waits) · `answered` · `closed` · `escalated`.
  final String status;
  final String priority;
  final DateTime? slaDueAt;
  final bool overdue;
  final DateTime? lastMessageAt;
  final String preview;
  final int unread;
  final int? workItemId;
  final String? workItemStatus;
  final DateTime? escalatedAt, createdAt;

  factory AdvThread.fromJson(Map<String, dynamic> j) {
    final st = asStr(j['status'], 'open');
    final p = asStr(j['priority'], 'normal');
    return AdvThread(
      id: asInt(j['id']),
      memberId: asInt(j['member_id']),
      studentName: asStr(j['student_name']).trim(),
      kind: asStr(j['kind']) == 'complaint' ? 'complaint' : 'message',
      about: _text(j['about']),
      subject: asStr(j['subject']).trim(),
      status: advThreadStatuses.contains(st) ? st : 'open',
      priority: advThreadPriorities.contains(p) ? p : 'normal',
      slaDueAt: advUtc(j['sla_due_at']),
      overdue: asBool(j['overdue']),
      lastMessageAt: advUtc(j['last_message_at']),
      preview: asStr(j['last_message_preview']).trim(),
      unread: asInt(j['unread']),
      workItemId: j['work_item_id'] == null ? null : asInt(j['work_item_id']),
      workItemStatus: _text(j['work_item_status']),
      escalatedAt: advUtc(j['escalated_at']),
      createdAt: advUtc(j['created_at']),
    );
  }

  bool get closed => status == 'closed';
  bool get escalated => workItemId != null;
  bool get aboutAdvisor => kind == 'complaint' && about == 'advisor';
  String get studentShown => studentName.isEmpty ? '#$memberId' : studentName;
  String get subjectShown => subject.isEmpty ? t('بلا عنوان', 'No subject') : subject;
  String get kindLabel => advThreadKindLabel(kind, about: about);

  AdvThread withStatus(String s) => AdvThread(
        id: id,
        memberId: memberId,
        studentName: studentName,
        kind: kind,
        about: about,
        subject: subject,
        status: s,
        priority: priority,
        slaDueAt: s == 'closed' ? null : slaDueAt,
        overdue: s == 'closed' ? false : overdue,
        lastMessageAt: lastMessageAt,
        preview: preview,
        unread: unread,
        workItemId: workItemId,
        workItemStatus: workItemStatus,
        escalatedAt: escalatedAt,
        createdAt: createdAt,
      );
}

class AdvMessage {
  const AdvMessage({required this.id, this.senderId, this.senderName = '', this.mine = false, this.body = '', this.attachments = const [], this.createdAt, this.clientId});
  final int id;
  final int? senderId;
  final String senderName;
  final bool mine;

  /// Plain text, never rendered as markup.
  final String body;
  final List<AdvAttachment> attachments;
  final DateTime? createdAt;

  /// The draft id it was posted with (only on one's own messages).
  final String? clientId;

  factory AdvMessage.fromJson(Map<String, dynamic> j) => AdvMessage(
        id: asInt(j['id']),
        senderId: j['sender_id'] == null ? null : asInt(j['sender_id']),
        senderName: asStr(j['sender_name']).trim(),
        mine: asBool(j['mine']),
        body: asStr(j['body']),
        attachments: [for (final m in asMapList(j['attachments'])) AdvAttachment.fromJson(m)],
        createdAt: advUtc(j['created_at']),
        clientId: _text(j['client_id']),
      );
}

/// `GET …/threads/{id}`: the thread and one page of messages, oldest first; [next] = the cursor of older ones.
class AdvThreadDetail {
  const AdvThreadDetail({required this.thread, this.messages = const [], this.next});
  final AdvThread thread;
  final List<AdvMessage> messages;
  final String? next;

  factory AdvThreadDetail.fromJson(Map<String, dynamic> j) => AdvThreadDetail(
        thread: AdvThread.fromJson(asMap(j['thread'])),
        messages: [for (final m in asMapList(j['messages'])) AdvMessage.fromJson(m)],
        next: _text(j['next']),
      );
}

/// `GET …/threads`: the page and every unread message the caller has across conversations.
class AdvThreadList {
  const AdvThreadList({required this.page, this.unreadTotal = 0});
  final AdvPage<AdvThread> page;
  final int unreadTotal;

  factory AdvThreadList.fromJson(Map<String, dynamic> j) => AdvThreadList(page: AdvPage.fromJson(j, AdvThread.fromJson), unreadTotal: asInt(j['unread_total']));
}

/// The thread list's filters.
class AdvThreadQuery {
  const AdvThreadQuery({this.status = '', this.kind = '', this.overdue = false, this.q = '', this.memberId, this.page = 1});
  final String status, kind, q;
  final bool overdue;
  final int? memberId;
  final int page;

  AdvThreadQuery copyWith({String? status, String? kind, bool? overdue, String? q, int? page}) =>
      AdvThreadQuery(status: status ?? this.status, kind: kind ?? this.kind, overdue: overdue ?? this.overdue, q: q ?? this.q, memberId: memberId, page: page ?? this.page);

  Map<String, dynamic> toQuery({int size = 25}) => {
        'member_id': ?memberId,
        if (status.isNotEmpty) 'status': status,
        if (kind.isNotEmpty) 'kind': kind,
        if (overdue) 'overdue': true,
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'size': size,
      };

  /// The one filter control's value: `''` · a status · `overdue` · `complaint`.
  String get filter => overdue ? 'overdue' : (kind == 'complaint' ? 'complaint' : status);

  AdvThreadQuery withFilter(String f) => AdvThreadQuery(
        status: advThreadStatuses.contains(f) ? f : '',
        kind: f == 'complaint' ? 'complaint' : '',
        overdue: f == 'overdue',
        q: q,
        memberId: memberId,
      );
}

/// The thread list's filter values with their labels.
Map<String, String> advThreadFilters({bool staff = true}) => {
      '': t('كل المحادثات', 'All conversations'),
      'open': staff ? t('بانتظار ردّك', 'Waiting for your reply') : t('بانتظار الرد', 'Awaiting reply'),
      'answered': t('تم الرد', 'Answered'),
      if (staff) 'overdue': t('متأخرة', 'Overdue'),
      'complaint': t('الشكاوى', 'Complaints'),
      'escalated': t('مُصعّدة', 'Escalated'),
      'closed': t('مغلقة', 'Closed'),
    };

/// A new conversation (the student: a message or a complaint; staff: a message to one student).
class AdvThreadDraft {
  const AdvThreadDraft({
    this.memberId,
    this.kind = 'message',
    this.about = 'other',
    this.aboutUserId,
    this.subject = '',
    this.body = '',
    this.priority = 'normal',
    this.attachments = const [],
    this.clientId,
  });

  final int? memberId;
  final String kind, about;
  final int? aboutUserId;
  final String subject, body, priority;
  final List<AdvAttachment> attachments;
  final String? clientId;

  AdvThreadDraft copyWith({
    String? kind,
    String? about,
    int? Function()? aboutUserId,
    String? subject,
    String? body,
    String? priority,
    List<AdvAttachment>? attachments,
    String? Function()? clientId,
  }) =>
      AdvThreadDraft(
        memberId: memberId,
        kind: kind ?? this.kind,
        about: about ?? this.about,
        aboutUserId: aboutUserId == null ? this.aboutUserId : aboutUserId(),
        subject: subject ?? this.subject,
        body: body ?? this.body,
        priority: priority ?? this.priority,
        attachments: attachments ?? this.attachments,
        clientId: clientId == null ? this.clientId : clientId(),
      );

  String? error() {
    if (subject.trim().isEmpty) return t('اكتب عنواناً للمحادثة', 'Write a subject');
    if (subject.trim().length > advSubjectMax) return t('العنوان أطول من 200 حرف', 'The subject is longer than 200 characters');
    if (body.trim().isEmpty) return t('اكتب رسالتك', 'Write your message');
    if (body.length > advMessageMax) return t('الرسالة أطول من 5000 حرف', 'The message is longer than 5,000 characters');
    if (attachments.length > advMaxAttachments) return t('5 مرفقات على الأكثر', '5 attachments at most');
    return null;
  }

  Map<String, dynamic> toJson() => {
        'member_id': ?memberId,
        'kind': kind,
        if (kind == 'complaint') 'about': about,
        if (kind == 'complaint' && about == 'advisor' && aboutUserId != null) 'about_user_id': aboutUserId,
        'subject': subject.trim(),
        'body': body.trim(),
        'priority': priority,
        'attachment_ids': [for (final a in attachments) a.id],
        'client_id': ?clientId,
      };
}

/// A reply being written: the composer, the offline draft and the queued message.
class AdvMessageDraft {
  const AdvMessageDraft({this.body = '', this.attachments = const [], this.clientId});
  final String body;
  final List<AdvAttachment> attachments;
  final String? clientId;

  AdvMessageDraft copyWith({String? body, List<AdvAttachment>? attachments, String? Function()? clientId}) =>
      AdvMessageDraft(body: body ?? this.body, attachments: attachments ?? this.attachments, clientId: clientId == null ? this.clientId : clientId());

  bool get isEmpty => body.trim().isEmpty;
  bool get worthKeeping => !isEmpty || attachments.isNotEmpty;

  String? error() {
    if (body.trim().isEmpty) return t('اكتب رسالتك', 'Write your message');
    if (body.length > advMessageMax) return t('الرسالة أطول من 5000 حرف', 'The message is longer than 5,000 characters');
    if (attachments.length > advMaxAttachments) return t('5 مرفقات على الأكثر', '5 attachments at most');
    return null;
  }

  Map<String, dynamic> toJson() => {'body': body.trim(), 'attachment_ids': [for (final a in attachments) a.id], 'client_id': ?clientId};

  /// What the device keeps: the body as typed.
  Map<String, dynamic> toStore() => {'body': body, 'attachments': [for (final a in attachments) a.toJson()], 'client_id': clientId};

  factory AdvMessageDraft.fromStore(Map<String, dynamic> j) => AdvMessageDraft(
        body: asStr(j['body']),
        attachments: [for (final m in asMapList(j['attachments'])) AdvAttachment.fromJson(m)],
        clientId: _text(j['client_id']),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Templates
// ═════════════════════════════════════════════════════════════════════════════

class AdvTemplate {
  const AdvTemplate({
    required this.id,
    this.key,
    this.kind = 'message',
    this.nameAr = '',
    this.nameEn = '',
    this.bodyAr = '',
    this.bodyEn = '',
    this.system = false,
    this.active = true,
  });

  final int id;

  /// A system template's key (null for one the organization added).
  final String? key;
  final String kind, nameAr, nameEn, bodyAr, bodyEn;
  final bool system, active;

  factory AdvTemplate.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']).trim();
    final k = asStr(j['kind']);
    return AdvTemplate(
      id: asInt(j['id']),
      key: _text(j['key']),
      kind: advTemplateKinds.contains(k) ? k : 'message',
      nameAr: _text(j['name_ar']) ?? name,
      nameEn: _text(j['name_en']) ?? name,
      bodyAr: asStr(j['body_ar']),
      bodyEn: asStr(j['body_en']),
      system: asBool(j['system']),
      active: asBool(j['active'], true),
    );
  }

  String get name {
    final n = t(nameAr, nameEn);
    return n.isNotEmpty ? n : (nameAr.isNotEmpty ? nameAr : nameEn);
  }

  /// The body in the reader's language (the other one when it is empty).
  String get body {
    final b = t(bodyAr, bodyEn);
    return b.trim().isNotEmpty ? b : (bodyAr.trim().isNotEmpty ? bodyAr : bodyEn);
  }

  /// The placeholders the body uses.
  List<String> get placeholders => [for (final p in advPlaceholders) if (bodyAr.contains('{$p}') || bodyEn.contains('{$p}')) p];
}

class AdvTemplateDraft {
  const AdvTemplateDraft({this.kind = 'message', this.nameAr = '', this.nameEn = '', this.bodyAr = '', this.bodyEn = '', this.active = true});

  factory AdvTemplateDraft.of(AdvTemplate x) =>
      AdvTemplateDraft(kind: x.kind, nameAr: x.nameAr, nameEn: x.nameEn, bodyAr: x.bodyAr, bodyEn: x.bodyEn, active: x.active);

  final String kind, nameAr, nameEn, bodyAr, bodyEn;
  final bool active;

  AdvTemplateDraft copyWith({String? kind, String? nameAr, String? nameEn, String? bodyAr, String? bodyEn, bool? active}) => AdvTemplateDraft(
        kind: kind ?? this.kind,
        nameAr: nameAr ?? this.nameAr,
        nameEn: nameEn ?? this.nameEn,
        bodyAr: bodyAr ?? this.bodyAr,
        bodyEn: bodyEn ?? this.bodyEn,
        active: active ?? this.active,
      );

  String? error() {
    if (nameAr.trim().isEmpty || nameEn.trim().isEmpty) return t('اكتب اسم القالب بالعربية والإنجليزية', 'Write the template name in Arabic and in English');
    if (nameAr.trim().length > 120 || nameEn.trim().length > 120) return t('الاسم أطول من 120 حرفاً', 'The name is longer than 120 characters');
    if (bodyAr.trim().isEmpty || bodyEn.trim().isEmpty) return t('اكتب نص القالب بالعربية والإنجليزية', 'Write the template text in Arabic and in English');
    if (bodyAr.length > 10000 || bodyEn.length > 10000) return t('النص أطول من 10000 حرف', 'The text is longer than 10,000 characters');
    return null;
  }

  Map<String, dynamic> toJson() =>
      {'kind': kind, 'name_ar': nameAr.trim(), 'name_en': nameEn.trim(), 'body_ar': bodyAr.trim(), 'body_en': bodyEn.trim(), 'active': active};
}

// ═════════════════════════════════════════════════════════════════════════════
//  Survey and feedback
// ═════════════════════════════════════════════════════════════════════════════

/// Results show only from this many answers (anonymity).
const advFeedbackMin = 5;

/// The longest survey comment.
const advSurveyCommentMax = 1000;

/// A survey waiting for the student (the hub's `surveys`, `GET /survey/{token}`).
class AdvSurveyInfo {
  const AdvSurveyInfo({this.token = '', this.advisorName = '', this.date});
  final String token, advisorName;

  /// The meeting's calendar day.
  final DateTime? date;

  factory AdvSurveyInfo.fromJson(Map<String, dynamic> j, {String? token}) =>
      AdvSurveyInfo(token: token ?? asStr(j['token']), advisorName: asStr(j['advisor_name']).trim(), date: advParseDay(j['date']));

  String get dateText => date == null ? '' : advDayLabel(date!, pattern: 'd MMM y');
}

/// `GET …/feedback`: hidden below [advFeedbackMin] answers.
class AdvFeedback {
  const AdvFeedback({this.count = 0, this.hidden = true, this.average, this.distribution = const {}, this.comments = const []});
  final int count;
  final bool hidden;
  final double? average;

  /// rating 1–5 → answers.
  final Map<int, int> distribution;

  /// (text, "YYYY-MM"), newest first.
  final List<(String, String)> comments;

  factory AdvFeedback.fromJson(Map<String, dynamic> j) {
    final count = asInt(j['count']);
    final avg = j['average'];
    final dist = asMap(j['distribution']);
    return AdvFeedback(
      count: count,
      hidden: asBool(j['hidden'], count < advFeedbackMin) || count < advFeedbackMin,
      average: avg is num ? avg.toDouble() : double.tryParse('${avg ?? ''}'),
      distribution: {for (var r = 1; r <= 5; r++) r: asInt(dist['$r'])},
      comments: [
        for (final m in asMapList(j['comments']))
          if (asStr(m['text']).trim().isNotEmpty) (asStr(m['text']).trim(), asStr(m['month'])),
      ],
    );
  }

  /// The month of a comment in the reader's language ("Nov 2026").
  static String monthLabel(String ym) {
    final d = DateTime.tryParse('$ym-01');
    return d == null ? ym : AppTime.date(DateTime.utc(d.year, d.month, 15, 12), pattern: 'MMM y');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The student hub
// ═════════════════════════════════════════════════════════════════════════════

class AdvHubAdvisor {
  const AdvHubAdvisor({required this.userId, this.name = '', this.type = 'primary', this.office, this.contactNote, this.bio, this.avatar, this.hours = const AdvOfficeHours(), this.nextFree});
  final int userId;
  final String name, type;
  final String? office, contactNote, bio, avatar;
  final AdvOfficeHours hours;
  final DateTime? nextFree;

  factory AdvHubAdvisor.fromJson(Map<String, dynamic> j) {
    final hours = AdvOfficeHours.fromJson(asMap(j['office_hours']));
    return AdvHubAdvisor(
      userId: asInt(j['user_id']),
      name: asStr(j['name']).trim(),
      type: asStr(j['type'], 'primary'),
      office: _text(j['office']),
      contactNote: _text(j['contact_note']),
      bio: _text(j['bio']),
      avatar: _text(j['avatar']),
      hours: hours,
      nextFree: advUtc(j['next_free']) ?? hours.nextFree,
    );
  }

  String get shown => name.isEmpty ? '#$userId' : name;
  String get typeLabel => advAdvisorTypeLabel(type);

  /// Has weekly office hours (so it can be booked).
  bool get bookable => !hours.isEmpty;
}

class AdvHubNote {
  const AdvHubNote({required this.id, this.authorName = '', this.body = '', this.createdAt});
  final int id;
  final String authorName, body;
  final DateTime? createdAt;

  factory AdvHubNote.fromJson(Map<String, dynamic> j) =>
      AdvHubNote(id: asInt(j['id']), authorName: asStr(j['author_name']).trim(), body: asStr(j['body']), createdAt: advUtc(j['created_at']));
}

/// `GET /org/public/{id}/advising/me`.
class AdvHub {
  const AdvHub({
    this.advisors = const [],
    this.upcoming = const [],
    this.past = const [],
    this.threads = const AdvThreadCounts(),
    this.notes = const [],
    this.surveys = const [],
    this.canBook = false,
    this.rules = const AdvBookingRules(),
    this.outreach = const AdvHubOutreach(),
  });

  /// Primary first.
  final List<AdvHubAdvisor> advisors;
  final List<AdvAppointment> upcoming, past;
  final AdvThreadCounts threads;
  final List<AdvHubNote> notes;
  final List<AdvSurveyInfo> surveys;
  final bool canBook;
  final AdvBookingRules rules;

  /// Phase 8: the latest group messages from my advising staff (absent on an older server → empty).
  final AdvHubOutreach outreach;

  factory AdvHub.fromJson(Map<String, dynamic> j) {
    const order = ['primary', 'co', 'support'];
    int rank(String t) => order.contains(t) ? order.indexOf(t) : order.length;
    return AdvHub(
      advisors: [for (final m in asMapList(j['advisors'])) AdvHubAdvisor.fromJson(m)]..sort((a, b) => rank(a.type) - rank(b.type)),
      upcoming: [for (final m in asMapList(j['upcoming'])) AdvAppointment.fromJson(m)],
      past: [for (final m in asMapList(j['past'])) AdvAppointment.fromJson(m)],
      threads: AdvThreadCounts.fromJson(asMap(j['threads'])),
      notes: [for (final m in asMapList(j['notes'])) AdvHubNote.fromJson(m)],
      surveys: [for (final m in asMapList(j['surveys'])) AdvSurveyInfo.fromJson(m)],
      canBook: asBool(j['can_book']),
      rules: AdvBookingRules.fromJson(asMap(j['booking_rules'])),
      outreach: AdvHubOutreach.fromJson(j['outreach']),
    );
  }

  AdvHubAdvisor? get primary => advisors.where((a) => a.type == 'primary').firstOrNull ?? advisors.firstOrNull;

  /// The advisors a student can book with (they have office hours).
  List<AdvHubAdvisor> get bookable => [for (final a in advisors) if (a.bookable) a];

  /// Why booking is closed right now (null when it is open).
  String? get bookBlocked {
    if (advisors.isEmpty) return t('لم يُسند إليك مرشد بعد', 'No advisor is assigned to you yet');
    if (bookable.isEmpty) return t('لم يحدد مرشدك ساعات مكتبية بعد — راسله لتتفقا على موعد', 'Your advisor has not set office hours yet — message them to agree on a time');
    if (!canBook) {
      final n = rules.maxActiveBookings;
      return countText(n,
          ar1: 'لديك موعد قادم بالفعل — الحد موعد واحد في الوقت نفسه',
          ar2: 'لديك موعدان قادمان — الحد موعدان في الوقت نفسه',
          arFew: 'لديك $n مواعيد قادمة — وهو الحد المسموح',
          arMany: 'لديك $n موعداً قادماً — وهو الحد المسموح',
          en1: 'You already have an upcoming appointment — one at a time is the limit',
          en: 'You already have $n upcoming appointments — that is the limit');
    }
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  `/status` counts and the member status hub flag
// ═════════════════════════════════════════════════════════════════════════════

/// `me.threads_unread` · `me.appointments_today` · `me.surveys_pending` (staff `/status` and the member status).
class AdvCommCounts {
  const AdvCommCounts({this.threadsUnread = 0, this.appointmentsToday = 0, this.surveysPending = 0});
  final int threadsUnread, appointmentsToday, surveysPending;

  factory AdvCommCounts.fromJson(Map<String, dynamic> me) => AdvCommCounts(
        threadsUnread: asInt(me['threads_unread']),
        appointmentsToday: asInt(me['appointments_today']),
        surveysPending: asInt(me['surveys_pending']),
      );

  int get total => threadsUnread + appointmentsToday + surveysPending;
}

/// The Phase 5 part of the member status (`GET /org/public/{id}/advising/status`): the hub entry and its counts.
class AdvMemberHub {
  const AdvMemberHub({this.enabled = false, this.student = false, this.hub = false, this.counts = const AdvCommCounts()});
  final bool enabled, student;

  /// The student has an active advisor (the hub entry shows).
  final bool hub;
  final AdvCommCounts counts;

  factory AdvMemberHub.fromJson(Map<String, dynamic> j) => AdvMemberHub(
        enabled: asBool(j['enabled']),
        student: asStr(j['role']) == 'student',
        hub: asBool(j['hub']),
        counts: AdvCommCounts.fromJson(asMap(j['me'])),
      );

  /// The `advising` block of one membership of `GET /org/public/me/overview` (also `/me/home` `org_overview`, Phase 9):
  /// `{hub, unread, appointments_today, surveys_pending}`, present only for a live student of an organization with
  /// advising on who has an active advisor. null when the key is absent (none of that, or an older server: the row
  /// then asks the member status itself).
  static AdvMemberHub? fromOverview(Object? block) {
    if (block is! Map) return null;
    final j = asMap(block);
    return AdvMemberHub(
      enabled: true,
      student: true,
      hub: asBool(j['hub']),
      counts: AdvCommCounts(threadsUnread: asInt(j['unread']), appointmentsToday: asInt(j['appointments_today']), surveysPending: asInt(j['surveys_pending'])),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Timeline (Phase 5 kinds)
// ═════════════════════════════════════════════════════════════════════════════

/// The Phase 5 timeline kinds.
const advCommTimelineKinds = [
  'appointment_booked',
  'appointment_cancelled',
  'appointment_completed',
  'appointment_no_show',
  'thread_opened',
  'thread_escalated',
];

String? _who(dynamic v) {
  if (v is Map) {
    final r = AdvRef.maybe(v);
    return r?.shown;
  }
  return _text(v);
}

/// The line the 360's timeline writes for a Phase 5 kind (null for any other kind).
String? advCommTimelineText(String kind, Map<String, dynamic> d) {
  final at = advUtc(d['starts_at']);
  final mode = _text(d['mode']);
  final when = [if (at != null) AppTime.dateTime(at), if (mode != null) advMeetingModeLabel(mode)].join(' · ');
  String withWhen(String s) => when.isEmpty ? s : '$s · $when';
  switch (kind) {
    case 'appointment_booked':
      final by = _text(d['booked_by']);
      return withWhen(by == 'advisor' ? t('حجز المرشد موعداً', 'The advisor booked an appointment') : t('حجز الطالب موعداً', 'The student booked an appointment'));
    case 'appointment_cancelled':
      final base = switch (_text(d['by'])) {
        'student' => t('ألغى الطالب موعداً', 'The student cancelled an appointment'),
        'advisor' => t('ألغى المرشد موعداً', 'The advisor cancelled an appointment'),
        _ => t('أُلغي موعد', 'An appointment was cancelled'),
      };
      return withWhen(asBool(d['late']) ? '$base (${t('متأخر', 'late')})' : base);
    case 'appointment_completed':
      final who = _who(d['advisor']);
      return withWhen(who == null ? t('تم لقاء الإرشاد', 'Advising meeting held') : t('تم لقاء الإرشاد مع $who', 'Advising meeting held with $who'));
    case 'appointment_no_show':
      return withWhen(t('لم يحضر الطالب موعده', 'The student did not come to the appointment'));
    case 'thread_opened':
      final k = _text(d['kind']) ?? 'message';
      final p = _text(d['priority']);
      return [k == 'complaint' ? t('شكوى جديدة', 'New complaint') : t('محادثة جديدة', 'New conversation'), if (p != null && p != 'normal') advPriorityLabel(p)].join(' · ');
    case 'thread_escalated':
      final wi = d['work_item_id'];
      return wi == null ? t('صُعّدت محادثة', 'A conversation was escalated') : t('صُعّدت محادثة إلى المعاملة #$wi', 'A conversation was escalated to work item #$wi');
  }
  return null;
}
