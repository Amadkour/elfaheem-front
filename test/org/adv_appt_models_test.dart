// Academic Advising Phase 5 models (docs/advising/PHASE5.md): availability rules and their checks, slots grouped by
// the organization's day, office hours, appointments (+ can, late cancel), conversations, drafts, templates and
// placeholders, the survey results (hidden below 5), the hub, the `/status` counts and the timeline kinds. The
// sample payloads (shaped like ../back routers/organization/org_advising_comm_router.py answers) are shared with
// test/ui/adv_appt_layout_test.dart and test/visual/adv_appt_golden_test.dart.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/advising/adv_appt_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Now" of the samples: Monday 9 Nov 2026, 08:00 UTC.
final advApptNow = DateTime.utc(2026, 11, 9, 8);

String _iso(DateTime d) => d.toIso8601String().replaceAll('Z', '').replaceAll('.000', '');

Map<String, dynamic> sampleAdvAppointmentJson({
  int id = 41,
  int dayOffset = 1,
  int hour = 9,
  String mode = 'in_person',
  String status = 'booked',
  bool past = false,
  String? reason = 'أريد مناقشة خطة الفصل القادم وتسجيل مقرر الإحصاء',
  String? cancelReason,
  String? cancelledBy,
  bool late = false,
  int? noteId,
  String bookedBy = 'student',
  bool staff = false,
}) {
  final s = advApptNow.add(Duration(days: past ? -dayOffset : dayOffset, hours: hour - 8));
  final upcoming = status == 'booked' && !past;
  return {
    'id': id,
    'member_id': 7,
    'student_name': 'سارة أحمد',
    'advisor_user_id': 12,
    'advisor_name': 'د. منى خليل',
    'starts_at': _iso(s),
    'ends_at': _iso(s.add(const Duration(minutes: 30))),
    'mode': mode,
    'location': mode == 'in_person' ? 'مبنى العلوم — مكتب 214' : null,
    'video_link': null,
    'meeting_id': mode == 'video' ? 88 : null,
    'status': status,
    'reason': reason,
    'cancel_reason': cancelReason,
    'cancelled_by': cancelledBy,
    'late_cancel': late,
    'note_id': noteId,
    'booked_by': bookedBy,
    'created_at': _iso(advApptNow.subtract(const Duration(days: 2))),
    'can': {
      'cancel': upcoming,
      'reschedule': upcoming,
      'complete': staff && status == 'booked' && past,
      'no_show': staff && status == 'booked' && past,
      'note': staff && status != 'cancelled',
    },
  };
}

Map<String, dynamic> sampleAdvSlotsJson({int days = 6}) {
  final out = <Map<String, dynamic>>[];
  for (var d = 1; d <= days; d++) {
    if (d == 3) continue; // a day without free times
    for (final h in const [7, 8, 9, 11, 12]) {
      final s = DateTime.utc(2026, 11, 9 + d, h);
      out.add({
        'starts_at': _iso(s),
        'ends_at': _iso(s.add(const Duration(minutes: 30))),
        'modes': h < 10 ? ['in_person', 'video'] : ['video', 'phone'],
        'location': h < 10 ? 'مكتب 214' : null,
      });
    }
  }
  return {'slots': out, 'timezone': 'Africa/Cairo'};
}

Map<String, dynamic> sampleAdvAvailabilityJson() => {
      'rules': [
        {'id': 1, 'weekday': 0, 'start': '09:00', 'end': '12:00', 'slot_minutes': 30, 'modes': ['in_person', 'video'], 'location': 'مبنى العلوم — مكتب 214', 'video_link': null, 'valid_from': null, 'valid_to': null},
        {'id': 2, 'weekday': 0, 'start': '13:00', 'end': '14:00', 'slot_minutes': 20, 'modes': ['phone'], 'location': null, 'video_link': null, 'valid_from': null, 'valid_to': null},
        {'id': 3, 'weekday': 2, 'start': '10:00', 'end': '12:00', 'slot_minutes': 30, 'modes': ['video', 'chat'], 'location': null, 'video_link': 'https://meet.example.edu/mona', 'valid_from': '2026-11-01', 'valid_to': '2027-01-31'},
        {'id': 4, 'weekday': 6, 'start': '11:00', 'end': '13:00', 'slot_minutes': 45, 'modes': ['in_person'], 'location': 'Science building, office 214', 'video_link': null, 'valid_from': null, 'valid_to': null},
      ],
      'off': [
        {'id': 9, 'from': '2026-11-19', 'to': '2026-11-21', 'reason': 'مؤتمر علمي'},
      ],
      'timezone': 'Africa/Cairo',
    };

Map<String, dynamic> sampleAdvThreadJson({int id = 5, String kind = 'message', String? about, String status = 'open', String priority = 'normal', int unread = 2, bool overdue = false, int? workItem, String subject = 'استفسار عن تسجيل مقرر الإحصاء'}) => {
      'id': id,
      'member_id': 7,
      'student_name': 'سارة أحمد',
      'kind': kind,
      'about': about,
      'subject': subject,
      'status': status,
      'priority': priority,
      'sla_due_at': status == 'open' ? _iso(advApptNow.add(Duration(hours: overdue ? -3 : 20))) : null,
      'overdue': overdue,
      'last_message_at': _iso(advApptNow.subtract(const Duration(hours: 2))),
      'last_message_preview': 'هل يمكنني تسجيل مقرر الإحصاء هذا الفصل رغم أن المتطلب السابق ما زال قيد التصحيح؟',
      'unread': unread,
      'work_item_id': workItem,
      'work_item_status': workItem == null ? null : 'in_progress',
      'escalated_at': workItem == null ? null : _iso(advApptNow.subtract(const Duration(hours: 1))),
      'created_at': _iso(advApptNow.subtract(const Duration(days: 1))),
    };

Map<String, dynamic> sampleAdvThreadsJson() => {
      'items': [
        sampleAdvThreadJson(),
        sampleAdvThreadJson(id: 6, kind: 'complaint', about: 'other', priority: 'high', unread: 0, overdue: true, subject: 'تأخر رصد درجة أعمال السنة'),
        sampleAdvThreadJson(id: 8, status: 'answered', unread: 0, subject: 'Question about the internship form'),
        sampleAdvThreadJson(id: 9, kind: 'complaint', about: 'advisor', status: 'escalated', priority: 'urgent', unread: 1, workItem: 314, subject: 'لم يرد المرشد على طلبي'),
        sampleAdvThreadJson(id: 10, status: 'closed', unread: 0, subject: 'موعد التدريب الصيفي'),
      ],
      'total': 5,
      'page': 1,
      'size': 25,
      'pages': 1,
      'facets': {},
      'unread_total': 3,
    };

Map<String, dynamic> sampleAdvThreadDetailJson({String status = 'open'}) => {
      'thread': sampleAdvThreadJson(status: status, unread: 0),
      'messages': [
        {
          'id': 100,
          'sender_id': 30,
          'sender_name': 'سارة أحمد',
          'mine': false,
          'body': 'السلام عليكم دكتورة، هل يمكنني تسجيل مقرر الإحصاء هذا الفصل رغم أن المتطلب السابق ما زال قيد التصحيح؟',
          'attachments': [
            {'id': 3, 'name': 'transcript.pdf', 'mime': 'application/pdf', 'size': 248000},
          ],
          'created_at': _iso(advApptNow.subtract(const Duration(hours: 20))),
          'client_id': null,
        },
        {
          'id': 101,
          'sender_id': 12,
          'sender_name': 'د. منى خليل',
          'mine': true,
          'body': 'وعليكم السلام يا سارة. نعم، يمكنك التسجيل بشرط اجتياز المتطلب. سأتابع مع شؤون الطلاب.',
          'attachments': [],
          'created_at': _iso(advApptNow.subtract(const Duration(hours: 18))),
          'client_id': 'mabc',
        },
        {
          'id': 102,
          'sender_id': 30,
          'sender_name': 'سارة أحمد',
          'mine': false,
          'body': 'Thank you! I also attached the registration form.',
          'attachments': [
            {'id': 4, 'name': 'registration-form.png', 'mime': 'image/png', 'size': 91000},
          ],
          'created_at': _iso(advApptNow.subtract(const Duration(hours: 2))),
          'client_id': null,
        },
      ],
      'next': 'bTk5',
    };

Map<String, dynamic> sampleAdvTemplatesJson() => {
      'items': [
        {'id': 1, 'key': 'meeting_summary', 'kind': 'meeting_note', 'name': 'ملخص لقاء', 'name_ar': 'ملخص لقاء', 'name_en': 'Meeting summary', 'body_ar': 'التقى {advisor_name} بالطالب {student_name} يوم {date} الساعة {time}.\nما نوقش:\nالخطوة التالية:', 'body_en': '{advisor_name} met {student_name} on {date} at {time}.\nDiscussed:\nNext step:', 'system': true, 'active': true},
        {'id': 2, 'key': 'outreach_absence', 'kind': 'outreach', 'name': 'تواصل بسبب الغياب', 'name_ar': 'تواصل بسبب الغياب', 'name_en': 'Absence outreach', 'body_ar': 'عزيزي {student_name}، لاحظنا غيابك مؤخراً في {org_name}.', 'body_en': 'Dear {student_name}, we noticed you missed classes at {org_name}.', 'system': true, 'active': true},
        {'id': 3, 'key': null, 'kind': 'message', 'name': 'تذكير بالتسجيل', 'name_ar': 'تذكير بالتسجيل', 'name_en': 'Registration reminder', 'body_ar': 'يا {student_name}، يغلق التسجيل قريباً.', 'body_en': 'Hi {student_name}, registration closes soon.', 'system': false, 'active': false},
        {'id': 4, 'key': 'support_referral', 'kind': 'support_request', 'name': 'إحالة للدعم', 'name_ar': 'إحالة للدعم', 'name_en': 'Support referral', 'body_ar': 'أحيل {student_name} إلى خدمات الدعم.', 'body_en': 'I refer {student_name} to support services.', 'system': true, 'active': true},
      ],
    };

Map<String, dynamic> sampleAdvFeedbackJson({int count = 12}) => count < 5
    ? {'count': count, 'hidden': true}
    : {
        'count': count,
        'average': 4.25,
        'distribution': {'1': 0, '2': 1, '3': 1, '4': 4, '5': 6},
        'comments': [
          {'text': 'المرشدة متعاونة جداً وأعطتني خطة واضحة', 'month': '2026-11'},
          {'text': 'Helpful, but the meeting started late.', 'month': '2026-10'},
        ],
        'hidden': false,
      };

Map<String, dynamic> sampleAdvHubJson({bool canBook = true, bool noHours = false}) => {
      'advisors': [
        {
          'user_id': 13,
          'name': 'Dr Omar Saleh',
          'type': 'support',
          'office': null,
          'contact_note': null,
          'bio': null,
          'avatar': null,
          'office_hours': {'rules': [], 'timezone': 'Africa/Cairo', 'next_free': null},
          'next_free': null,
        },
        {
          'user_id': 12,
          'name': 'د. منى خليل',
          'type': 'primary',
          'office': 'مبنى العلوم — مكتب 214',
          'contact_note': 'أفضل وسيلة: رسائل الإرشاد، وأرد خلال يوم عمل',
          'bio': 'أستاذ مشارك في الإحصاء، أرشد طلاب المستوى الثاني والثالث.',
          'avatar': null,
          'office_hours': noHours
              ? {'rules': [], 'timezone': 'Africa/Cairo', 'next_free': null}
              : {
                  'rules': [
                    {'weekday': 0, 'start': '09:00', 'end': '12:00', 'modes': ['in_person', 'video'], 'location': 'مكتب 214'},
                    {'weekday': 0, 'start': '13:00', 'end': '14:00', 'modes': ['phone'], 'location': null},
                    {'weekday': 2, 'start': '10:00', 'end': '12:00', 'modes': ['video', 'chat'], 'location': null},
                  ],
                  'timezone': 'Africa/Cairo',
                  'next_free': _iso(advApptNow.add(const Duration(days: 1, hours: 1))),
                },
          'next_free': noHours ? null : _iso(advApptNow.add(const Duration(days: 1, hours: 1))),
        },
      ],
      'upcoming': [sampleAdvAppointmentJson(), sampleAdvAppointmentJson(id: 42, dayOffset: 2, hour: 11, mode: 'video', reason: null, bookedBy: 'advisor')],
      'past': [
        sampleAdvAppointmentJson(id: 30, past: true, dayOffset: 6, status: 'completed', reason: null),
        sampleAdvAppointmentJson(id: 31, past: true, dayOffset: 12, status: 'cancelled', cancelledBy: 'student', late: true, cancelReason: 'ظرف عائلي طارئ', reason: null),
      ],
      'threads': {'unread': 2, 'open': 1},
      'notes': [
        {'id': 1, 'author_name': 'د. منى خليل', 'body': 'اتفقنا على تسجيل 15 ساعة هذا الفصل ومتابعة أسبوعية حتى الامتحانات.', 'created_at': _iso(advApptNow.subtract(const Duration(days: 6)))},
      ],
      'surveys': [
        {'token': 'tok-1', 'advisor_name': 'د. منى خليل', 'date': '2026-11-03'},
      ],
      'can_book': canBook,
      'booking_rules': {'min_notice_hours': 2, 'horizon_days': 30, 'cancel_min_notice_hours': 2, 'max_active_bookings': 2},
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('availability', () {
    test('rules parse, sort in the reader\'s week and send what the server takes', () {
      final a = AdvAvailability.fromJson(sampleAdvAvailabilityJson());
      expect(a.rules.map((r) => r.id), [1, 2, 3, 4]);
      AppConfig.lang = 'ar';
      expect(AdvAvailability.fromJson(sampleAdvAvailabilityJson()).rules.first.weekday, 6); // Sunday comes before Monday in Arabic
      AppConfig.lang = 'en';
      final r = a.rules.first;
      expect(r.slots, 6);
      expect(r.toJson()['video_link'], isNull);
      expect(a.rules[2].toJson()['video_link'], 'https://meet.example.edu/mona');
      expect(a.rules[2].validFrom, DateTime(2026, 11, 1));
      expect(a.off.single.days, 3);
      expect(advRulesError(a.rules), isNull);
    });

    test('a link is dropped when the window has no video', () {
      const r = AdvRule(modes: ['in_person'], videoLink: 'https://x.edu/m');
      expect(r.toJson()['video_link'], isNull);
    });

    test('checks: overlap, too short, no mode, insecure link', () {
      const a = AdvRule(weekday: 1, start: '09:00', end: '11:00');
      expect(advRulesError([a, const AdvRule(weekday: 1, start: '10:30', end: '12:00')]), contains('overlap'));
      expect(advRulesError([a, const AdvRule(weekday: 2, start: '10:30', end: '12:00')]), isNull);
      // periods that never meet do not clash
      final early = a.copyWith(validTo: () => DateTime(2026, 11, 30));
      final late = const AdvRule(weekday: 1, start: '10:00', end: '12:00').copyWith(validFrom: () => DateTime(2026, 12, 1));
      expect(advRulesError([early, late]), isNull);
      expect(advRulesError([const AdvRule(start: '09:00', end: '09:20')]), contains('at least one appointment'));
      expect(advRulesError([const AdvRule(modes: [])]), contains('at least one way'));
      expect(advRulesError([const AdvRule(modes: ['video'], videoLink: 'http://meet.x')]), contains('https'));
      expect(advSecureLink('https://user:pw@meet.x'), isFalse);
    });

    test('day off result names the affected appointments', () {
      final r = AdvOffResult.fromJson({'id': 3, 'from': '2026-11-20', 'to': '2026-11-20', 'reason': null, 'affected': [41, 42]});
      expect(r.affected, [41, 42]);
      expect(r.off.days, 1);
    });

    test('minutes helpers', () {
      expect(advMinutes('09:30'), 570);
      expect(advMinutes('25:00'), isNull);
      expect(advHhmm(570), '09:30');
    });
  });

  group('slots and office hours', () {
    test('slots group by the organization\'s day and filter by way of meeting', () {
      final s = AdvSlots.fromJson(sampleAdvSlotsJson());
      expect(s.slots.first.startsAt.isUtc, isTrue);
      expect(s.modes, ['in_person', 'video', 'phone']);
      final by = s.byDay();
      expect(by.length, 5);
      expect(by.values.first.length, 5);
      expect(s.byDay(mode: 'phone').values.first.length, 2);
      expect(by.containsKey('2026-11-12'), isFalse);
    });

    test('office hours: one line per day, the next free time', () {
      final hub = AdvHub.fromJson(sampleAdvHubJson());
      final h = hub.primary!.hours;
      expect(h.lines.length, 2);
      expect(h.lines.first.$1, 0);
      expect(h.lines.first.$2, contains('–'));
      expect(h.modes, ['in_person', 'video', 'phone', 'chat']);
      expect(hub.primary!.nextFree, isNotNull);
    });
  });

  group('appointments', () {
    test('parse with can, late cancel, live', () {
      final a = AdvAppointment.fromJson(sampleAdvAppointmentJson());
      expect(a.startsAt, DateTime.utc(2026, 11, 10, 9));
      expect(a.can.cancel, isTrue);
      expect(a.upcoming(advApptNow), isTrue);
      expect(a.live(DateTime.utc(2026, 11, 10, 8, 55)), isTrue);
      expect(a.live(DateTime.utc(2026, 11, 10, 8, 40)), isFalse);
      expect(a.lateIfCancelledAt(DateTime.utc(2026, 11, 10, 7, 30), const AdvBookingRules()), isTrue);
      expect(a.lateIfCancelledAt(advApptNow, const AdvBookingRules()), isFalse);
      final c = AdvAppointment.fromJson(sampleAdvAppointmentJson(status: 'cancelled', cancelledBy: 'advisor', late: true));
      expect(advCancelText(c), 'Cancelled by the advisor · late cancellation');
      final v = AdvAppointment.fromJson(sampleAdvAppointmentJson(mode: 'video'));
      expect(v.video, isTrue);
      expect(v.hasLink, isFalse);
      expect(v.meetingId, 88);
    });

    test('booking draft: validation and body', () {
      final slot = AdvSlots.fromJson(sampleAdvSlotsJson()).slots.first;
      var d = const AdvBookDraft(advisorUserId: 12);
      expect(d.error(), 'Pick a time');
      d = d.copyWith(slot: () => slot, mode: () => 'phone');
      expect(d.error(), 'Choose how to meet');
      d = d.copyWith(mode: () => 'video', reason: '  plan  ');
      expect(d.error(), isNull);
      final j = d.toJson();
      expect(j['starts_at'], '2026-11-10T07:00:00.000Z');
      expect(j['reason'], 'plan');
      expect(j.containsKey('member_id'), isFalse);
      expect(j.containsKey('force'), isFalse);
      expect(const AdvBookDraft(advisorUserId: 12, memberId: 7, force: true).toJson()['force'], isTrue);
    });

    test('the student-busy conflicts', () {
      final spans = AdvBusySpan.listOf({'code': 'advising_student_busy', 'conflicts': [{'source': 'timetable', 'starts_at': '2026-11-10T09:00:00', 'ends_at': '2026-11-10T10:30:00'}]});
      expect(spans.single.sourceLabel, 'A class');
      expect(spans.single.startsAt, DateTime.utc(2026, 11, 10, 9));
    });

    test('booking rules: defaults and summaries', () {
      const r = AdvBookingRules();
      expect(r.maxActiveBookings, 2);
      expect(r.summary, 'Book at least 2 hours ahead, up to 30 days in advance');
      expect(AdvBookingRules.fromJson({'min_notice_hours': 1}).summary, startsWith('Book at least 1 hour ahead'));
    });

    test('the 360 meetings and thread counts land on the profile', () {
      final p = AdvCaseProfile.fromJson({
        'student': {'member_id': 7, 'name': 'Sara'},
        'meetings': {'upcoming': [sampleAdvAppointmentJson(staff: true)], 'past': [], 'no_shows': 2},
        'threads': {'open': 1, 'unread': 3},
      });
      expect(p.meetings.upcoming.single.id, 41);
      expect(p.meetings.noShows, 2);
      expect(p.threadCounts.unread, 3);
      expect(AdvCaseProfile.fromJson({'student': {'member_id': 7}}).meetings.isEmpty, isTrue);
    });
  });

  group('conversations', () {
    test('list with unread total; filters', () {
      final l = AdvThreadList.fromJson(sampleAdvThreadsJson());
      expect(l.unreadTotal, 3);
      expect(l.page.items.length, 5);
      final c = l.page.items[3];
      expect(c.aboutAdvisor, isTrue);
      expect(c.escalated, isTrue);
      expect(c.kindLabel, 'Complaint about the advisor');
      const q = AdvThreadQuery(memberId: 7);
      expect(q.withFilter('overdue').toQuery()['overdue'], isTrue);
      expect(q.withFilter('complaint').toQuery()['kind'], 'complaint');
      expect(q.withFilter('closed').filter, 'closed');
      expect(q.withFilter('').toQuery().containsKey('status'), isFalse);
      expect(q.toQuery()['member_id'], 7);
      expect(advThreadFilters(staff: false).containsKey('overdue'), isFalse);
    });

    test('detail: messages oldest first, attachments, cursor', () {
      final d = AdvThreadDetail.fromJson(sampleAdvThreadDetailJson());
      expect(d.messages.map((m) => m.id), [100, 101, 102]);
      expect(d.messages.first.attachments.single.isPdf, isTrue);
      expect(d.messages.last.attachments.single.isImage, isTrue);
      expect(d.messages[1].mine, isTrue);
      expect(d.next, 'bTk5');
    });

    test('thread draft: complaint fields only for complaints', () {
      var d = const AdvThreadDraft(subject: ' Hi ', body: 'Question', clientId: 'c1');
      expect(d.error(), isNull);
      var j = d.toJson();
      expect(j.containsKey('about'), isFalse);
      expect(j['subject'], 'Hi');
      d = d.copyWith(kind: 'complaint', about: 'advisor', aboutUserId: () => 12);
      j = d.toJson();
      expect(j['about'], 'advisor');
      expect(j['about_user_id'], 12);
      expect(const AdvThreadDraft(body: 'x').error(), 'Write a subject');
      expect(AdvThreadDraft(subject: 's', body: 'x' * 5001).error(), contains('5,000'));
    });

    test('message draft: store round trip keeps the text as typed', () {
      const d = AdvMessageDraft(body: '  hello ', attachments: [AdvAttachment(id: 3, name: 'a.pdf')], clientId: 'm1');
      final back = AdvMessageDraft.fromStore(d.toStore());
      expect(back.body, '  hello ');
      expect(back.attachments.single.id, 3);
      expect(back.clientId, 'm1');
      expect(d.toJson(), {'body': 'hello', 'attachment_ids': [3], 'client_id': 'm1'});
      expect(const AdvMessageDraft(attachments: [AdvAttachment(id: 1)]).worthKeeping, isTrue);
      expect(const AdvMessageDraft().worthKeeping, isFalse);
    });
  });

  group('templates', () {
    test('names and bodies follow the language; placeholders found', () {
      final list = [for (final m in (sampleAdvTemplatesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvTemplate.fromJson(m)];
      expect(list.first.name, 'Meeting summary');
      expect(list.first.placeholders, ['student_name', 'advisor_name', 'date', 'time']);
      AppConfig.lang = 'ar';
      expect(list.first.name, 'ملخص لقاء');
      expect(list.first.body, startsWith('التقى'));
      AppConfig.lang = 'en';
      expect(list[2].active, isFalse);
      expect(list[2].system, isFalse);
    });

    test('fill: known placeholders only', () {
      expect(advFillTemplate('Hi {student_name}, see {advisor_name} {unknown} {date}', {'student_name': 'Sara', 'date': ''}), 'Hi Sara, see {advisor_name} {unknown} {date}');
    });

    test('draft validation', () {
      expect(const AdvTemplateDraft().error(), isNotNull);
      expect(const AdvTemplateDraft(nameAr: 'أ', nameEn: 'A', bodyAr: 'ب', bodyEn: 'B').error(), isNull);
      expect(const AdvTemplateDraft(kind: 'outreach', nameAr: ' أ ', nameEn: 'A', bodyAr: 'ب', bodyEn: 'B').toJson()['name_ar'], 'أ');
    });
  });

  group('survey and feedback', () {
    test('results hidden below 5', () {
      expect(AdvFeedback.fromJson(sampleAdvFeedbackJson(count: 3)).hidden, isTrue);
      expect(AdvFeedback.fromJson({'count': 3, 'hidden': false}).hidden, isTrue);
      final f = AdvFeedback.fromJson(sampleAdvFeedbackJson());
      expect(f.hidden, isFalse);
      expect(f.average, 4.25);
      expect(f.distribution[5], 6);
      expect(f.comments.first.$2, '2026-11');
      expect(AdvFeedback.monthLabel('2026-11'), 'Nov 2026');
    });

    test('survey info', () {
      final s = AdvSurveyInfo.fromJson({'advisor_name': 'Dr Mona', 'date': '2026-11-03', 'answered': false}, token: 't');
      expect(s.token, 't');
      expect(s.dateText, '3 Nov 2026');
    });
  });

  group('hub and counts', () {
    test('primary first, bookable, blocked reasons', () {
      final h = AdvHub.fromJson(sampleAdvHubJson());
      expect(h.advisors.first.type, 'primary');
      expect(h.bookable.single.userId, 12);
      expect(h.bookBlocked, isNull);
      expect(h.threads.unread, 2);
      expect(h.surveys.single.token, 'tok-1');
      expect(h.rules.maxActiveBookings, 2);
      expect(AdvHub.fromJson(sampleAdvHubJson(canBook: false)).bookBlocked, contains('2 upcoming'));
      expect(AdvHub.fromJson(sampleAdvHubJson(noHours: true)).bookBlocked, contains('office hours'));
      expect(AdvHub.fromJson(const {}).bookBlocked, contains('No advisor'));
    });

    test('staff /status me and the member status hub flag', () {
      final st = AdvStatus.fromJson({'enabled': true, 'me': {'advisor': true, 'threads_unread': 4, 'appointments_today': 2, 'surveys_pending': 0}});
      expect(st.me.comm.threadsUnread, 4);
      expect(st.me.comm.appointmentsToday, 2);
      expect(AdvStatus.fromJson(const {}).me.comm.total, 0);
      final m = AdvMemberHub.fromJson({'enabled': true, 'role': 'student', 'advisors': [], 'hub': true, 'me': {'threads_unread': 1, 'appointments_today': 0, 'surveys_pending': 1}});
      expect(m.hub && m.student, isTrue);
      expect(m.counts.surveysPending, 1);
      expect(AdvMemberHub.fromJson({'enabled': true, 'role': 'student'}).hub, isFalse);
    });
  });

  group('timeline', () {
    test('Phase 5 kinds have their own lines', () {
      String line(String kind, Map<String, dynamic> data) => AdvTimelineEntry.fromJson({'kind': kind, 'data': data}).text;
      expect(line('appointment_booked', {'starts_at': '2026-11-10T09:00:00', 'mode': 'video', 'booked_by': 'advisor'}), startsWith('The advisor booked an appointment · '));
      expect(line('appointment_cancelled', {'by': 'student', 'late': true}), 'The student cancelled an appointment (late)');
      expect(line('appointment_completed', {'advisor': {'user_id': 12, 'name': 'Dr Mona'}}), 'Advising meeting held with Dr Mona');
      expect(line('appointment_no_show', {}), 'The student did not come to the appointment');
      expect(line('thread_opened', {'kind': 'complaint', 'priority': 'urgent'}), 'New complaint · Urgent');
      expect(line('thread_escalated', {'work_item_id': 314}), 'A conversation was escalated to work item #314');
      expect(line('something_new', {}), 'Activity on the record');
    });
  });
}
