// Student lifecycle phase 4 (contract §7.3): the Ask / MyAsks / inbox parsers read the server's shapes, AskDraft
// builds AskIn and finds the first problem (the full-screen 7-day rule included), the preview says what the student
// sees, the answer lines read back, askAnswerMissing mirrors 422 answer_incomplete, and the busy list parses.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/students/student_asks_models.dart';
import 'package:flutter_education_app/features/org/students/student_status_models.dart' show StatusSource;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _ask({String kind = 'data', String status = 'answered', String? due}) => {
      'id': 31,
      'org_id': 7,
      'user_id': 812,
      'kind': kind,
      'presentation': 'popup',
      'title': 'نحتاج بعض المعلومات',
      'body': 'رجاءً أكمل البيانات',
      'fields': [
        {'key': 'guardian_phone', 'label_ar': 'هاتف ولي الأمر', 'label_en': 'Guardian phone', 'kind': 'text', 'required': true, 'case_field': true},
        {'key': 'q1', 'label_ar': 'هل تسكن في المدينة الجامعية؟', 'label_en': 'Do you live on campus?', 'kind': 'yes_no', 'required': true, 'case_field': false},
        {'key': 'q2', 'label_ar': 'الفصل المفضل', 'label_en': 'Preferred term', 'kind': 'choice', 'options': ['الأول', 'الثاني'], 'required': false},
      ],
      'doc_keys': ['birth_cert'],
      'status': status,
      'answer': kind == 'meeting'
          ? {'confirm': false, 'note': 'عندي امتحان'}
          : {
              'values': {'guardian_phone': '0100', 'q1': true},
              'documents': {'birth_cert': 4},
            },
      'answered_at': '2026-11-21T10:00:00',
      'due_at': due,
      'remind_days': [3, 1],
      'reminded': [
        {'day': 3, 'at': '2026-11-20T09:00:00', 'manual': false},
      ],
      'meeting_id': kind == 'meeting' ? 90 : null,
      'source_type': 'complaint',
      'source_id': 77,
      'case_id': 5,
      'reviewed_by': null,
      'review_note': null,
      'created_at': '2026-11-19T08:00:00',
      'org': {'id': 7, 'name': 'كلية الهندسة', 'name_en': 'Faculty of Engineering', 'logo': null},
      'created_by': {'id': 44, 'name': 'منى السيد'},
      'student': {'id': 812, 'name': 'أحمد علي', 'image_url': null},
      'meeting': kind == 'meeting'
          ? {'id': 90, 'starts_at': '2026-11-25T08:00:00', 'ends_at': '2026-11-25T08:30:00', 'mode': 'offline', 'location': 'Room 12', 'status': 'scheduled'}
          : null,
      'can': {'answer': false, 'cancel': true, 'accept': status == 'answered'},
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('vocabulary covers every enum value in both languages', () {
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      for (final k in askKinds) {
        expect(askKindLabel(k), isNot(k));
        expect(askKindHint(k), isNotEmpty);
        expect(askDefaultTitle(k), isNotEmpty);
      }
      for (final p in askPresentations) {
        expect(askPresentationLabel(p), isNot(p));
        expect(askPresentationHint(p), isNotEmpty);
      }
      for (final s in askStatuses) {
        expect(askStatusLabel(s), isNot(s));
      }
      for (final k in askFieldKinds) {
        expect(askFieldKindLabel(k), isNot(k));
      }
      for (final tab in inboxTabs) {
        expect(inboxTabLabel(tab), isNot(tab));
      }
      for (final s in inboxSources) {
        expect(inboxSourceLabel(s), isNot(s));
      }
    }
  });

  test('StudentAsk reads the Ask shape', () {
    final a = StudentAsk.fromJson(_ask());
    expect(a.id, 31);
    expect(a.kind, 'data');
    expect(a.presentation, 'popup');
    expect(a.fields.length, 3);
    expect(a.fields.first.caseField, isTrue);
    expect(a.fields[2].options, ['الأول', 'الثاني']);
    expect(a.fields[2].required, isFalse);
    expect(a.docKeys, ['birth_cert']);
    expect(a.isAnswered, isTrue);
    expect(a.isLive, isTrue);
    expect(a.isOpen, isFalse);
    expect(a.answerValues['guardian_phone'], '0100');
    expect(a.remindedCount, 1);
    expect(a.sourceType, 'complaint');
    expect(a.sourceId, 77);
    expect(a.org?.displayName, 'Faculty of Engineering');
    expect(a.createdBy?.name, 'منى السيد');
    expect(a.student?.id, 812);
    expect(a.can.accept, isTrue);
    expect(a.answeredAt!.isUtc, isFalse); // shown in local time
    expect(a.answeredAt!.toUtc(), DateTime.utc(2026, 11, 21, 10));
  });

  test('an unknown kind or presentation falls back; a meeting reads its meeting', () {
    final a = StudentAsk.fromJson({..._ask(kind: 'meeting'), 'presentation': 'weird'});
    expect(a.presentation, 'notice');
    expect(a.meeting?.id, 90);
    expect(a.meeting?.online, isFalse);
    expect(a.meeting?.location, 'Room 12');
    expect(a.answerConfirm, isFalse);
    expect(a.answerNote, 'عندي امتحان');
    expect(StudentAsk.fromJson({'id': 1, 'kind': 'nope'}).kind, 'data');
  });

  test('overdue only while open and past due', () {
    final now = DateTime.utc(2026, 11, 22);
    expect(StudentAsk.fromJson(_ask(status: 'open', due: '2026-11-21T00:00:00')).overdue(now), isTrue);
    expect(StudentAsk.fromJson(_ask(status: 'open', due: '2026-11-23T00:00:00')).overdue(now), isFalse);
    expect(StudentAsk.fromJson(_ask(status: 'answered', due: '2026-11-21T00:00:00')).overdue(now), isFalse);
    expect(StudentAsk.fromJson(_ask(status: 'open')).overdue(now), isFalse);
  });

  test('MyAsks and AskListPage', () {
    final m = MyAsks.fromJson({
      'items': [_ask(status: 'open'), _ask(status: 'returned')],
      'fullscreen': null,
      'popup': _ask(status: 'open'),
    });
    expect(m.items.length, 2);
    expect(m.fullscreen, isNull);
    expect(m.popup?.id, 31);
    final l = AskListPage.fromJson({'items': [_ask()], 'total': 41, 'page': 2, 'size': 30, 'pages': 2});
    expect(l.total, 41);
    expect(l.page, 2);
    expect(l.pages, 2);
    expect(MyAsks.fromJson(null).items, isEmpty);
  });

  test('InboxPage reads counts, rows and can', () {
    final p = InboxPage.fromJson({
      'tab': 'decide',
      'counts': {'decide': 3, 'waiting': 5, 'done': 9},
      'items': [
        {
          'id': 'ask:31',
          'source': 'ask',
          'source_id': 31,
          'student': {'id': 812, 'name': 'أحمد علي', 'image_url': null},
          'title_ar': 'طلب بيانات: نحتاج',
          'title_en': 'Information request: we need',
          'at': '2026-11-21T10:00:00',
          'status': 'answered',
          'can': {'accept': true, 'return': true, 'reject': false, 'meeting': true, 'ask': true},
        },
        {'source': 'decision', 'source_id': 4, 'student': {'id': 0}, 'title_ar': 'فصل', 'title_en': '', 'status': 'open', 'can': {'accept': true, 'reject': true}},
      ],
      'page': 1,
      'size': 30,
      'total': 2,
    });
    expect(p.count('decide'), 3);
    expect(p.count('waiting'), 5);
    expect(p.pages, 1);
    final a = p.items.first;
    expect(a.id, 'ask:31');
    expect(a.isAsk, isTrue);
    expect(a.title, 'Information request: we need');
    expect(a.can.accept && a.can.ret && a.can.meeting && a.can.ask, isTrue);
    expect(a.can.reject, isFalse);
    expect(a.statusLabel, askStatusLabel('answered'));
    final d = p.items[1];
    expect(d.id, 'decision:4');
    expect(d.student, isNull); // id 0 = no student
    expect(d.title, 'فصل'); // falls back to Arabic
    expect(d.statusLabel, 'Waiting for a decision');
  });

  group('AskDraft', () {
    final now = DateTime.utc(2026, 11, 21, 12);

    test('a meeting needs a future time and sends both ends', () {
      final d = AskDraft(kind: 'meeting', source: const StatusSource('complaint', 77));
      expect(d.title, askDefaultTitle('meeting'));
      expect(d.problem(now), 'meeting_time');
      d.startsAt = now.subtract(const Duration(hours: 1));
      expect(d.problem(now), 'meeting_past');
      d.startsAt = DateTime.utc(2026, 11, 25, 8);
      d.minutes = 45;
      d.mode = 'online';
      expect(d.problem(now), isNull);
      final j = d.toJson();
      expect(j['kind'], 'meeting');
      expect(j['meeting'], {'starts_at': '2026-11-25T08:00:00.000Z', 'ends_at': '2026-11-25T08:45:00.000Z', 'mode': 'online', 'location': null});
      expect(j['source'], {'type': 'complaint', 'id': 77});
      expect(j['fields'], isEmpty);
      expect(j['due_at'], isNull);
      expect(j['remind_days'], isNull); // no due date, no reminders
      expect(j['force'], isFalse);
    });

    test('data: case fields toggle, written questions get free keys, choices need two options', () {
      final d = AskDraft(kind: 'data');
      expect(d.problem(now), 'fields');
      d.toggleCaseField(const AskPickable('birth_date', 'Birth date', kind: 'date'));
      expect(d.fields.single.kind, 'date');
      expect(d.fields.single.caseField, isTrue);
      final q = d.addQuestion();
      expect(q.key, 'q2');
      expect(d.problem(now), 'field_label');
      q.labelAr = 'الفصل';
      q.kind = 'choice';
      q.options = ['الأول'];
      expect(d.problem(now), 'field_options');
      q.options = ['الأول', ' الثاني ', ''];
      expect(d.problem(now), isNull);
      final f = (d.toJson()['fields'] as List).last as Map;
      expect(f['options'], ['الأول', 'الثاني']);
      expect(f['case_field'], isFalse);
      d.toggleCaseField(const AskPickable('birth_date', 'Birth date'));
      expect(d.fields.length, 1);
      expect(d.addQuestion().key, 'q3'); // q2 is taken
    });

    test('documents and confirm', () {
      final d = AskDraft(kind: 'documents');
      expect(d.problem(now), 'doc_keys');
      d.toggleDoc('birth_cert');
      expect(d.problem(now), isNull);
      expect(d.toJson()['doc_keys'], ['birth_cert']);
      d.toggleDoc('birth_cert');
      expect(d.docKeys, isEmpty);
      final c = AskDraft(kind: 'confirm');
      expect(c.problem(now), 'confirm_text');
      c.body = 'أؤكد';
      expect(c.problem(now), isNull);
      expect(c.toJson()['body'], 'أؤكد');
    });

    test('full screen needs a due date within 7 days; reminders sorted', () {
      final d = AskDraft(kind: 'confirm', body: 'x', presentation: 'fullscreen');
      expect(d.problem(now), 'fullscreen_due');
      d.dueAt = now.add(const Duration(days: 8));
      expect(d.problem(now), 'fullscreen_due');
      d.dueAt = now.add(const Duration(days: 3));
      expect(d.problem(now), isNull);
      d.remindDays = [1, 7, 3];
      expect(d.toJson()['remind_days'], [7, 3, 1]);
      d.dueAt = now.subtract(const Duration(minutes: 1));
      expect(d.problem(now), 'due_past');
      d.title = ' ';
      expect(d.problem(now), 'title');
      expect(d.problemText(now), isNotNull);
    });

    test('setKind keeps a typed title and follows the default otherwise', () {
      final d = AskDraft(kind: 'meeting');
      d.setKind('data');
      expect(d.title, askDefaultTitle('data'));
      d.title = 'My own';
      d.setKind('confirm');
      expect(d.title, 'My own');
    });

    test('the preview names how, what and when', () {
      final d = AskDraft(kind: 'data', presentation: 'popup')..dueAt = DateTime.utc(2026, 11, 24, 21);
      d.toggleCaseField(const AskPickable('guardian_phone', 'Guardian phone'));
      final lines = askPreviewLines(d, name: 'Ahmed');
      expect(lines.first, contains('Ahmed'));
      expect(lines.first, contains('window'));
      expect(lines[1], contains('Guardian phone'));
      expect(lines[2], contains('Due'));
      expect(lines.last, contains('accept'));
      AppConfig.lang = 'ar';
      expect(askPreviewLines(AskDraft(kind: 'meeting')).length, 3);
    });
  });

  test('answer lines and the missing answer keys', () {
    final a = StudentAsk.fromJson(_ask());
    final lines = askAnswerLines(a);
    expect(lines.length, 2);
    expect(lines.first.$1, 'Guardian phone');
    expect(lines.first.$2, '0100');
    expect(lines[1].$2, 'Yes');
    expect(askAnswerMissing(a, {'guardian_phone': '1'}, null), ['q1']);
    expect(askAnswerMissing(a, {'guardian_phone': '1', 'q1': false}, null), isEmpty);
    final m = StudentAsk.fromJson(_ask(kind: 'meeting'));
    expect(askAnswerLines(m).map((l) => l.$2), ['Cannot attend', 'عندي امتحان']);
    expect(askAnswerMissing(m, const {}, null), ['confirm']);
    expect(askAnswerMissing(m, const {}, false), ['note']);
    expect(askAnswerMissing(m, const {'note': 'x'}, false), isEmpty);
    expect(askAnswerMissing(m, const {}, true), isEmpty);
    final docs = StudentAsk.fromJson({..._ask(kind: 'documents'), 'doc_keys': ['birth_cert', 'photo']});
    expect(askAnswerMissing(docs, const {}, null), ['photo']);
    final conf = StudentAsk.fromJson(_ask(kind: 'confirm'));
    expect(askAnswerMissing(conf, const {}, true), isEmpty);
    expect(askAnswerMissing(conf, const {}, null), ['confirm']);
  });

  test('the busy list of attendees_busy', () {
    final b = AskBusy.listOf({
      'code': 'attendees_busy',
      'busy': [
        {
          'user': {'id': 812, 'name': 'أحمد علي'},
          'items': [
            {'title': 'Lecture', 'source': 'meeting', 'starts_at': '2026-11-25T08:00:00', 'ends_at': '2026-11-25T09:00:00'},
          ],
        },
        'junk',
      ],
    });
    expect(b.length, 1);
    expect(b.single.name, 'أحمد علي');
    expect(b.single.items.single.startsAt!.toUtc(), DateTime.utc(2026, 11, 25, 8));
    expect(b.single.line, startsWith('Lecture · '));
    expect(AskBusy.listOf(const {}), isEmpty);
  });

  test('every phase-4 code has a text', () {
    for (final c in ['bad_ask', 'ask_not_found', 'ask_action_unknown', 'fullscreen_needs_due', 'asks_disabled', 'ask_not_answered', 'ask_closed', 'answer_incomplete', 'reason_required', 'reminded_recently', 'attendees_busy']) {
      expect(askCodeTexts()[c], isNotNull, reason: c);
    }
  });
}
