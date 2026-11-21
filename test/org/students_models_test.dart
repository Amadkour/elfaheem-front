// Students section models (student lifecycle contract §1, §3, §4): labels cover every enum value, the pure rules
// (intake label, the one chip, its tone), and the parsers read the contract's sample payloads.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone;
import 'package:flutter_education_app/features/org/students/students_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({Map<String, dynamic> over = const {}}) => {
      'user': {'id': 812, 'name': 'أحمد محمد علي', 'name_en': 'Ahmed Mohamed Ali', 'image_url': null, 'username': 'ahmed.m'},
      'member_id': 5531,
      'member_status': 'active',
      'student_code': '20261234',
      'program': {'id': 7, 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer Science'},
      'level': '2',
      'cohort': 'current',
      'type_key': 'student_new',
      'nid_last4': '4821',
      'enrol_status': 'enrolled',
      'enrol_until': null,
      'acad_standing': 'carrying',
      'flags': ['transferred_in'],
      'intake': {'case_id': 3310, 'status': 'active', 'label': 'missing', 'conditional': true, 'due_at': '2026-12-15T00:00:00'},
      'missing_count': 3,
      'chip': {'dimension': 'intake', 'value': 'missing'},
      ...over,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('every enum value has an Arabic and an English label', () {
    void covers(Map<String, BiText> m, Iterable<String> values) {
      for (final v in values) {
        expect(m[v], isNotNull, reason: 'no label for $v');
        expect(m[v]!.$1.trim(), isNotEmpty, reason: 'no Arabic for $v');
        expect(m[v]!.$2.trim(), isNotEmpty, reason: 'no English for $v');
      }
    }

    covers(enrolText, enrolStatuses);
    covers(standingText, standings);
    covers(flagText, [...flagKeys, ...derivedFlagKeys]);
    covers(intakeText, intakeLabels);
    covers(memberStatusText, memberStatuses);
    covers(accessSectionText, accessSections);
    expect({...enrolPaused, ...enrolFinal}.every(enrolStatuses.contains), isTrue);
    expect(staffOnlyFlags.every(flagKeys.contains), isTrue);
    AppConfig.lang = 'ar';
    expect(enrolLabel('graduated'), 'خريج');
    AppConfig.lang = 'en';
    expect(enrolLabel('graduated'), 'Graduated');
    expect(enrolLabel('something_new'), 'something_new');
  });

  test('intakeLabel follows §3.1', () {
    expect(intakeLabel(null), 'accepted');
    expect(intakeLabel('draft', source: 'excel'), 'nominated');
    expect(intakeLabel('draft', source: 'intake'), 'nominated');
    expect(intakeLabel('draft', source: 'excel', everSubmitted: true), 'provisional');
    expect(intakeLabel('draft', source: 'wizard'), 'provisional');
    expect(intakeLabel('submitted'), 'provisional');
    expect(intakeLabel('needs_correction'), 'missing');
    expect(intakeLabel('under_review'), 'awaiting');
    expect(intakeLabel('approved'), 'awaiting');
    expect(intakeLabel('active', missingCount: 2), 'missing');
    expect(intakeLabel('active'), 'accepted');
    expect(intakeLabel('rejected'), 'rejected');
    expect(intakeLabel('withdrawn'), 'withdrawn');
  });

  test('studentChip precedence: enrolment, member, intake, standing', () {
    expect(studentChip(enrolStatus: 'postponed', memberStatus: 'suspended', intake: 'missing'), const StudentChip('enrolment', 'postponed'));
    expect(studentChip(memberStatus: 'pending', intake: 'missing'), const StudentChip('member', 'pending'));
    expect(studentChip(intake: 'awaiting', acadStanding: 'warning'), const StudentChip('intake', 'awaiting'));
    expect(studentChip(acadStanding: 'repeating'), const StudentChip('standing', 'repeating'));
    expect(studentChip(), const StudentChip('standing', 'regular'));
    expect(studentChip(acadStanding: ''), const StudentChip('standing', 'regular'));
  });

  test('chipTone follows §3.2', () {
    AppTone tone(String dim, String v) => chipTone(StudentChip(dim, v));
    expect(tone('standing', 'regular'), AppTone.success);
    expect(tone('intake', 'accepted'), AppTone.success);
    for (final v in ['carrying']) {
      expect(tone('standing', v), AppTone.warning);
    }
    for (final v in ['missing', 'awaiting', 'provisional', 'nominated']) {
      expect(tone('intake', v), AppTone.warning);
    }
    expect(tone('enrolment', 'postponed'), AppTone.warning);
    for (final v in ['repeating', 'warning', 'final_chance']) {
      expect(tone('standing', v), AppTone.danger);
    }
    for (final v in ['suspended', 'disc_suspended', 'outside']) {
      expect(tone('enrolment', v), AppTone.danger);
    }
    for (final v in ['withdrawn', 'cancelled', 'dismissed', 'transferred_out', 'deceased']) {
      expect(tone('enrolment', v), AppTone.neutral);
    }
    expect(tone('enrolment', 'graduated'), AppTone.gold);
    expect(tone('member', 'suspended'), AppTone.danger);
    expect(tone('member', 'pending'), AppTone.warning);
    expect(const StudentChip('intake', 'missing').label, 'Missing data');
    expect(const StudentChip('member', 'pending').label, 'Pending');
    expect(const StudentChip('enrolment', 'graduated').label, 'Graduated');
  });

  test('StudentRow parses the §3.3 sample', () {
    final r = StudentRow.fromJson(_row());
    expect(r.id, 812);
    expect(r.name, 'Ahmed Mohamed Ali');
    AppConfig.lang = 'ar';
    expect(r.name, 'أحمد محمد علي');
    expect(r.program!.label, 'علوم الحاسب');
    AppConfig.lang = 'en';
    expect(r.user.username, 'ahmed.m');
    expect(r.user.imageUrl, isNull);
    expect(r.memberId, 5531);
    expect(r.studentCode, '20261234');
    expect(r.program!.code, 'CS');
    expect(r.level, '2');
    expect(r.typeKey, 'student_new');
    expect(r.nidLast4, '4821');
    expect(r.enrolStatus, 'enrolled');
    expect(r.enrolUntil, isNull);
    expect(r.acadStanding, 'carrying');
    expect(r.flags, ['transferred_in']);
    expect(r.intake!.caseId, 3310);
    expect(r.intake!.label, 'missing');
    expect(r.intake!.conditional, isTrue);
    expect(r.intake!.dueAt!.toUtc(), DateTime.utc(2026, 12, 15));
    expect(r.missingCount, 3);
    expect(r.hasMissing, isTrue);
    expect(r.chip, const StudentChip('intake', 'missing'));
  });

  test('StudentRow: the nullable keys and a server without a chip', () {
    final r = StudentRow.fromJson(_row(over: {
      'program': null,
      'level': null,
      'student_code': null,
      'type_key': null,
      'nid_last4': null,
      'intake': null,
      'missing_count': null,
      'chip': null,
      'acad_standing': 'warning',
      'user': {'id': 9, 'name': '', 'name_en': 'Only English'},
    }));
    expect(r.program, isNull);
    expect(r.studentCode, isNull);
    expect(r.intake, isNull);
    expect(r.missingCount, isNull);
    expect(r.hasMissing, isFalse);
    expect(r.chip, const StudentChip('standing', 'warning'));
    AppConfig.lang = 'ar';
    expect(r.name, 'Only English');
  });

  test('StudentsPageData parses §4.1', () {
    final d = StudentsPageData.fromJson({
      'total': 1840,
      'page': 1,
      'size': 30,
      'pages': 62,
      'summary': {'enrolled': 1712, 'missing': 96, 'awaiting': 41, 'attention': 58, 'suspended': 12},
      'can': {'add': true, 'import': true, 'export': true, 'settings': false},
      'items': [_row(), _row(over: {'user': {'id': 813, 'name': 'سارة'}})],
    });
    expect(d.total, 1840);
    expect(d.pages, 62);
    expect(d.summary.enrolled, 1712);
    expect(d.summary.of('awaiting'), 41);
    expect(d.summary.of('attention'), 58);
    expect(d.summary.of('suspended'), 12);
    expect(d.summary.of('missing'), 96);
    expect(d.can.add, isTrue);
    expect(d.can.settings, isFalse);
    expect(d.items.map((x) => x.id), [812, 813]);
    final empty = StudentsPageData.fromJson({});
    expect(empty.items, isEmpty);
    expect(empty.summary.enrolled, 0);
  });

  test('StudentsQuery.toQuery and copyWith', () {
    expect(const StudentsQuery().toQuery(), {'page': 1, 'size': 30});
    final q = const StudentsQuery(q: '  4821 ', chip: 'missing', programId: 7, sort: 'code', page: 3, size: 500);
    expect(q.toQuery(), {'q': '4821', 'chip': 'missing', 'program_id': 7, 'sort': 'code', 'page': 3, 'size': 100});
    expect(q.filtered, isTrue);
    expect(const StudentsQuery().filtered, isFalse);
    final c = q.copyWith(chip: null);
    expect(c.chip, isNull);
    expect(c.programId, 7);
    expect(c.page, 1);
    expect(q.copyWith(page: 4).page, 4);
    expect(q.copyWith(enrol: 'withdrawn').toQuery()['enrol'], 'withdrawn');
    expect(q.copyWith(standing: 'warning', flag: 'struggling', level: '2', typeKey: 'x', memberStatus: 'pending').toQuery(),
        containsPair('member_status', 'pending'));
  });

  test('StudentMissing parses §4.4 and the no-case answer', () {
    final m = StudentMissing.fromJson({
      'case_id': 3310,
      'can_upload': true,
      'can_edit': true,
      'can_waive': false,
      'due_at': '2026-12-15T00:00:00',
      'photos': [
        {'key': 'photo', 'label_ar': 'صورة شخصية', 'label_en': 'Personal photo', 'why_ar': 'مطلوبة لكل الطلاب', 'why_en': 'Required for every student', 'due_at': null, 'status': null},
      ],
      'documents': [
        {'key': 'military_2', 'label_ar': 'نموذج 2 جند', 'label_en': 'Military form 2', 'why_ar': 'مطلوب للطلاب المصريين الذكور', 'why_en': 'Required for male Egyptian students', 'due_at': '2026-12-15T00:00:00', 'status': 'deferred'},
      ],
      'fields': [
        {'key': 'guardian_phone', 'label_ar': 'هاتف ولي الأمر', 'label_en': "Guardian's phone", 'kind': 'phone', 'why_ar': 'مطلوب لمن هم دون 18 سنة', 'why_en': 'Required under 18'},
      ],
    });
    expect(m.caseId, 3310);
    expect(m.canUpload, isTrue);
    expect(m.canWaive, isFalse);
    expect(m.total, 3);
    expect(m.photos.single.label, 'Personal photo');
    expect(m.photos.single.status, isNull);
    expect(m.documents.single.status, 'deferred');
    expect(m.documents.single.dueAt!.toUtc(), DateTime.utc(2026, 12, 15));
    expect(m.fields.single.kind, 'phone');
    expect(m.fields.single.why, 'Required under 18');
    AppConfig.lang = 'ar';
    expect(m.fields.single.label, 'هاتف ولي الأمر');
    expect(missingStatusText('deferred'), 'مؤجل');
    final none = StudentMissing.fromJson({'case_id': null, 'photos': [], 'documents': [], 'fields': []});
    expect(none.caseId, isNull);
    expect(none.isEmpty, isTrue);
  });

  test('StudentAccessLog parses §4.5', () {
    final l = StudentAccessLog.fromJson({
      'total': 14,
      'page': 1,
      'size': 30,
      'pages': 1,
      'items': [
        {'at': '2026-11-21T10:02:11', 'actor': {'id': 44, 'name': 'منى السيد'}, 'actor_role': 'org-staff', 'section': 'file', 'ip': '196.2.x.x'},
      ],
    });
    expect(l.total, 14);
    final e = l.items.single;
    expect(e.at!.toUtc(), DateTime.utc(2026, 11, 21, 10, 2, 11));
    expect(e.actorId, 44);
    expect(e.actorName, 'منى السيد');
    expect(e.actorRole, 'org-staff');
    expect(e.sectionLabel, 'File');
    expect(e.ip, '196.2.x.x');
  });
}
