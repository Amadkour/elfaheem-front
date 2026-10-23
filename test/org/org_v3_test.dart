// Organizations v3 — the shared logic behind the join / membership / timetable screens.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_application_screen.dart' show orgPasswordProblem;
import 'package:flutter_education_app/features/org/org_dynamic_form.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';

ApiException apiErr(int status, String code, [Map<String, dynamic> extra = const {}]) => ApiException(
      statusCode: status,
      message: 'server text',
      code: code,
      body: {
        'detail': {'code': code, 'message': 'server text', ...extra}
      },
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('error texts', () {
    test('known codes get a translated sentence', () {
      expect(orgErrorText(apiErr(409, 'already_pending')), 'You already have a pending request');
      expect(orgErrorText(apiErr(403, 'membership_ended')), contains('other services still work'));
      AppConfig.lang = 'ar';
      expect(orgErrorText(apiErr(409, 'already_pending')), 'لديك طلب قيد المراجعة بالفعل');
    });

    test('rate limiting shows the wait', () {
      expect(orgErrorText(apiErr(429, 'too_many_attempts', {'retry_after_minutes': 15})), endsWith('(15 min)'));
    });

    test('unknown codes and plain errors fall back to the server message', () {
      expect(orgErrorText(apiErr(400, 'something_new')), 'server text');
      expect(orgErrorText(const ApiException(statusCode: 404, message: 'not here')), 'not here');
    });

    test('OrgCall exposes the coded extras', () {
      final c = OrgCall(null, apiErr(403, 'not_eligible', {'reasons': [{'code': 'full'}]}));
      expect(c.ok, isFalse);
      expect(c.code, 'not_eligible');
      expect(c.detail['reasons'], [{'code': 'full'}]);
    });

    test('eligibility reasons', () {
      expect(joinReasonText({'code': 'level'}), 'Open to a different year / level');
      expect(joinReasonText({'code': 'answer_conflict', 'field': 'year'}), contains('record'));
      expect(joinReasonText({'code': 'brand_new', 'message': 'from server'}), 'from server');
    });
  });

  group('join policy draft', () {
    test('a never-configured unit starts closed for students', () {
      final d = JoinPolicyDraft.fromJson({'method': 'closed', 'configured': false});
      expect(d.method, 'closed');
      expect(d.roles, {'student'});
      expect(d.cohort, 'both');
      expect(d.toBody()['fields'], isEmpty);
    });

    test('round-trips the staff policy', () {
      final p = {
        'configured': true,
        'method': 'approval',
        'approver': 'assistants',
        'assistant_ids': [7, 3],
        'roles': ['student'],
        'cohort': 'incoming',
        'program_ids': [2],
        'levels': ['4'],
        'capacity': 40,
        'unverified': 'reject',
        'fields': [
          {'key': 'year', 'label': 'Your year', 'type': 'select', 'required': true, 'options': ['1', '2', '3', '4'], 'bind': 'academic_level', 'allowed': ['4']}
        ],
      };
      final b = JoinPolicyDraft.fromJson(p).toBody();
      expect(b['method'], 'approval');
      expect(b['approver'], 'assistants');
      expect(b['assistant_ids'], [3, 7]);
      expect(b['cohort'], 'incoming');
      expect(b['levels'], ['4']);
      expect(b['program_ids'], [2]);
      expect(b['capacity'], 40);
      expect(b['unverified'], 'reject');
      final f = (b['fields'] as List).single as Map;
      expect(f['bind'], 'academic_level');
      expect(f['allowed'], ['4']);
    });

    test('settings that do not apply to the method are reset, not left stale', () {
      final d = JoinPolicyDraft(method: 'auto', approver: 'assistants', assistantIds: {5});
      final b = d.toBody();
      expect(b['approver'], 'manager');
      expect(b['assistant_ids'], isEmpty);
    });

    test('cohort / level targeting only for students', () {
      final d = JoinPolicyDraft(method: 'auto', roles: {'teacher'}, cohort: 'current', levels: {'1'});
      expect(d.toBody()['cohort'], 'both');
      expect(d.toBody()['levels'], isEmpty);
      d.roles.add('student');
      expect(d.toBody()['cohort'], 'current');
      expect(d.toBody()['levels'], ['1']);
    });

    test('every key is always sent (PUT replaces the policy)', () {
      expect(JoinPolicyDraft().toBody().keys.toSet(),
          {'method', 'approver', 'assistant_ids', 'roles', 'cohort', 'program_ids', 'levels', 'capacity', 'unverified', 'fields'});
    });

    test('local validation mirrors the server', () {
      expect(JoinPolicyDraft(roles: {}).validate(), isNotNull);
      expect(JoinPolicyDraft(method: 'approval', approver: 'assistants').validate(), 'Pick at least one assistant');
      expect(JoinPolicyDraft(method: 'approval', approver: 'assistants', assistantIds: {1}).validate(), isNull);
      expect(
          JoinPolicyDraft(fields: [
            {'label': 'Pick', 'type': 'select', 'options': []}
          ]).validate(),
          isNotNull);
      // a bound select gets its options from the configuration
      expect(
          JoinPolicyDraft(fields: [
            {'label': 'Year', 'type': 'select', 'options': [], 'bind': 'academic_level'}
          ]).validate(),
          isNull);
    });

    test('a code field is shown only when the unit needs one', () {
      expect(unitNeedsCode({'method': 'code'}), isTrue);
      expect(unitNeedsCode({'method': 'auto', 'code_required': false}), isFalse);
      expect(unitNeedsCode({'method': 'approval'}), isFalse);
    });

    test('code_req needs a code AND an approver, and sends the approver fields', () {
      expect(unitNeedsCode({'method': 'code_req'}), isTrue);
      expect(unitNeedsApproval({'method': 'code_req'}), isTrue);
      expect(unitNeedsApproval({'method': 'code'}), isFalse);
      final d = JoinPolicyDraft(method: 'code_req', approver: 'assistants', assistantIds: {7, 3});
      expect(d.needsApprover, isTrue);
      final b = d.toBody();
      expect(b['method'], 'code_req');
      expect(b['approver'], 'assistants');
      expect(b['assistant_ids'], [3, 7]);
      expect(JoinPolicyDraft(method: 'code_req', approver: 'assistants').validate(), 'Pick at least one assistant');
      expect(orgCodeText('request_code_required'), isNot('request_code_required'));
    });
  });

  group('schedule draft', () {
    test('null course_ids on the server means every course', () {
      final d = ScheduleDraft.fromJson({'id': 4, 'name': 'T2', 'course_ids': null, 'settings': {}}, allCourses: [1, 2, 3]);
      expect(d.courseIds, {1, 2, 3});
      expect(d.days, scheduleDays.take(6).toList());
    });

    test('the body carries the full scope (PUT is a full replacement)', () {
      final d = ScheduleDraft.fromJson({
        'id': 4,
        'name': 'T2',
        'term_id': 9,
        'term_label': '2026/2027',
        'start_date': '2026-09-01',
        'end_date': '2027-01-15',
        'course_ids': [5, 2],
        'status': 'draft',
        'settings': {'days': ['sunday', 'saturday'], 'spread_days': false, 'custom': 1},
      });
      final b = d.toBody();
      expect(b.keys.toSet(), {'name', 'term_label', 'term_id', 'start_date', 'end_date', 'course_ids', 'settings'});
      expect(b['course_ids'], [2, 5]);
      expect(b['start_date'], '2026-09-01');
      expect((b['settings'] as Map)['custom'], 1, reason: 'unknown settings are kept');
      expect(d.days, ['saturday', 'sunday'], reason: 'days follow the week order');
    });

    test('validation', () {
      final d = ScheduleDraft()..name = 'x';
      expect(d.validate(), 'Pick at least one course');
      d.courseIds.add(1);
      expect(d.validate(), isNull);
      d
        ..start = DateTime(2026, 5, 1)
        ..end = DateTime(2026, 4, 1);
      expect(d.validate(), isNotNull);
      d.end = DateTime(2026, 6, 1);
      d.days = [];
      expect(d.validate(), 'Pick at least one teaching day');
    });

    test('a published schedule is recognised by status, not a flag', () {
      expect(ScheduleDraft.fromJson({'status': 'active', 'name': 'x'}).published, isTrue);
      expect(ScheduleDraft.fromJson({'status': 'draft', 'name': 'x'}).published, isFalse);
    });
  });

  group('runs and results', () {
    test('open runs', () {
      expect(runIsOpen({'status': 'queued'}), isTrue);
      expect(runIsOpen({'status': 'running'}), isTrue);
      for (final s in ['succeeded', 'failed', 'cancelled']) {
        expect(runIsOpen({'status': s}), isFalse);
      }
      expect(runIsOpen(null), isFalse);
    });

    test('the four solver verdicts are told apart', () {
      final labels = resultStatusLabels();
      expect(labels.keys, containsAll(['feasible', 'feasible_relaxed', 'partial', 'infeasible']));
      expect(labels.values.toSet().length, 4);
      for (final s in labels.keys) {
        expect(resultStatusHelp(s), isNotEmpty);
      }
      expect(resultStatusHelp('partial'), contains('Nothing was published'));
    });

    test('hard conflicts are described', () {
      for (final type in ['students_clash', 'teacher_double_booked', 'assistant_double_booked', 'room_double_booked', 'room_missing_capabilities', 'room_inactive', 'teacher_unavailable']) {
        expect(conflictTypeText(type), isNot(type));
      }
      expect(scheduleReasonText('no_room_fits'), contains('capabilities'));
    });
  });

  group('dates & membership periods', () {
    test('naive server timestamps are UTC', () {
      final d = orgParseUtc('2026-03-01T10:00:00')!;
      expect(d.isUtc, isFalse, reason: 'shown in local time');
      expect(d.toUtc(), DateTime.utc(2026, 3, 1, 10));
      expect(orgParseUtc('2026-03-01T10:00:00Z')!.toUtc(), DateTime.utc(2026, 3, 1, 10));
      expect(orgParseUtc('2026-03-01'), DateTime(2026, 3, 1), reason: 'a date has no time zone');
      expect(orgParseUtc(null), isNull);
    });

    test('we always send UTC', () {
      expect(orgUtc(DateTime.utc(2026, 1, 2, 3)), '2026-01-02T03:00:00.000Z');
      expect(orgUtc(null), isNull);
    });

    test('period sentences', () {
      expect(membershipPeriodText({'effective_status': 'active', 'expires_at': null}), 'Permanent membership');
      expect(membershipPeriodText({'effective_status': 'active', 'expires_at': '2030-01-01T00:00:00'}), startsWith('Until'));
      expect(membershipPeriodText({'effective_status': 'expired', 'expires_at': '2020-01-01T00:00:00'}), contains('unaffected'));
      expect(membershipPeriodText({'effective_status': 'scheduled', 'starts_at': '2030-01-01T00:00:00'}), startsWith('Starts on'));
      expect(membershipPeriodText({'effective_status': 'suspended'}), contains('Suspended'));
    });

    test('every backend membership status has a label', () {
      expect(membershipStatusLabels().keys, containsAll(['active', 'pending', 'rejected', 'suspended', 'expired', 'scheduled']));
    });
  });

  group('dynamic form answers', () {
    final fields = [
      {'key': 'name', 'type': 'text', 'required': true},
      {'key': 'year', 'type': 'select', 'required': true, 'options': ['1', '2']},
      {'key': 'agree', 'type': 'checkbox', 'required': true},
      {'key': 'note', 'type': 'textarea', 'required': false},
    ];

    test('required fields are reported until answered', () {
      final a = OrgFormAnswers();
      a.collect(fields);
      expect(a.missing(fields), {'name', 'year', 'agree'});
      a.ctrl('name').text = '  Mona ';
      a.values['year'] = '2';
      a.values['agree'] = true;
      final out = a.collect(fields);
      expect(a.missing(fields), isEmpty);
      expect(out['name'], 'Mona');
      expect(out['year'], '2');
      expect(out.containsKey('note'), isFalse, reason: 'untouched optional fields are not sent');
      a.dispose();
    });

    test('options may be strings or configuration objects', () {
      expect(orgOption('B'), ('B', 'B'));
      expect(orgOption({'value': '4', 'label_ar': 'الرابعة', 'label_en': 'Fourth year'}), ('4', 'Fourth year'));
      expect(orgOption({'key': 'y1', 'label_ar': 'الأولى'}), ('y1', 'الأولى'));
    });
  });

  test('application password rule = the server\'s', () {
    expect(orgPasswordProblem('short1'), isNotNull);
    expect(orgPasswordProblem('onlyletters'), isNotNull);
    expect(orgPasswordProblem('12345678'), isNotNull);
    expect(orgPasswordProblem('letters123'), isNull);
  });
}
