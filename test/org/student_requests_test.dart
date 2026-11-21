// Student lifecycle phase 6 (D-1400): parsing of the lifecycle requests and transfer credits (shapes of
// features/org/students/requests.py item_out / detail / options and transfer_credits.py out / listing), the drafts'
// checks and bodies, and the error texts.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/students/student_requests_api.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> myRequestsJson() => {
      'options': [
        {'request': 'suspend', 'label_ar': 'وقف القيد', 'label_en': 'Suspend my enrolment', 'needs': ['reason', 'effective_to'], 'allowed': true, 'open_item_id': null, 'fields': [], 'reason_codes': ['military', 'illness']},
        {'request': 'withdraw', 'label_ar': 'الانسحاب', 'label_en': 'Withdraw', 'needs': ['reason'], 'allowed': true, 'open_item_id': 12, 'fields': [], 'reason_codes': ['other']},
        {'request': 'reenrol', 'label_ar': 'إعادة القيد', 'label_en': 'Re-enrol', 'needs': ['reason'], 'allowed': false, 'fields': [], 'reason_codes': []},
        {
          'request': 'data_update', 'label_ar': 'تحديث بياناتي', 'label_en': 'Update my details', 'needs': ['changes'], 'allowed': true,
          'fields': [{'key': 'address', 'label_ar': 'العنوان', 'label_en': 'Address', 'kind': 'text'}], 'reason_codes': [],
        },
      ],
      'items': [
        {
          'id': 12, 'ref': 'REQ-0012', 'request': 'withdraw', 'label_ar': 'الانسحاب', 'label_en': 'Withdraw', 'status': 'open', 'stage': 'review',
          'origin': 'student', 'reason': 'Moving abroad', 'reason_code': 'other', 'effective_from': null, 'effective_to': null, 'changes': null,
          'decision_no': null, 'applied': false, 'note': null, 'created_at': '2026-11-20T08:00:00', 'decided_at': null, 'can_withdraw': true,
        },
        {
          'id': 9, 'ref': 'REQ-0009', 'request': 'postpone', 'label_ar': 'تأجيل', 'label_en': 'Postpone', 'status': 'rejected', 'stage': 'rejected',
          'origin': 'student', 'reason': 'Illness', 'effective_to': '2027-01-31', 'note': 'No medical report', 'created_at': '2026-10-01T08:00:00',
          'decided_at': '2026-10-05T08:00:00', 'can_withdraw': false,
        },
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('my requests: options, items, open and closed', () {
    final m = MyRequests.fromJson(myRequestsJson());
    expect(m.options.length, 4);
    final s = m.option('suspend')!;
    expect(s.needsUntil, isTrue);
    expect(s.canStart, isTrue);
    expect(s.reasonCodes, ['military', 'illness']);
    expect(m.option('withdraw')!.canStart, isFalse, reason: 'one of the same kind is open');
    expect(m.option('reenrol')!.canStart, isFalse);
    expect(m.option('data_update')!.fields.single.label, 'Address');
    expect(m.open.map((r) => r.id), [12]);
    expect(m.closed.map((r) => r.id), [9]);
    final rej = m.closed.single;
    expect(rej.effectiveTo, DateTime(2027, 1, 31));
    expect(rej.note, 'No medical report');
    expect(requestPathReached(rej.stage), 2);
    expect(requestPathReached('council'), 1);
    expect(m.open.single.canWithdraw, isTrue);
  });

  test('the staff detail: can, councils, the student name', () {
    final r = LifecycleRequest.fromJson({
      'id': 4, 'ref': 'REQ-4', 'request': 'suspend', 'status': 'open', 'stage': 'review', 'title': 'وقف القيد: Ahmed Ali',
      'student_id': 77, 'params': {'decision': 'suspend', 'reason': 'x'}, 'body_key': 'faculty_council', 'needs_decision_no': true,
      'councils': [{'dept_id': 5, 'council_id': 2, 'level': 3, 'name_ar': 'مجلس الكلية', 'name_en': 'Faculty council'}],
      'can': {'accept': false, 'reject': false, 'council': true},
    });
    expect(r.studentName, 'Ahmed Ali');
    expect(r.decision, 'suspend');
    expect(r.isDataUpdate, isFalse);
    expect(r.can.council, isTrue);
    expect(r.can.any, isTrue);
    expect(r.councils.single.name, 'Faculty council');
    final a = AcceptDraft();
    expect(a.check(r), 'decision_no_required');
    a
      ..decisionNo = ' 15/2026 '
      ..decisionDate = DateTime(2026, 11, 21);
    expect(a.check(r), isNull);
    expect(a.toJson(), {'decision_no': '15/2026', 'decision_date': '2026-11-21'});
  });

  test('the request draft: checks and body', () {
    final m = MyRequests.fromJson(myRequestsJson());
    final s = m.option('suspend')!;
    final d = RequestDraft('suspend');
    expect(d.check(s), 'reason_required');
    d.reason = ' Military service call ';
    expect(d.check(s), 'dates_required');
    d
      ..effectiveFrom = DateTime(2026, 12, 1)
      ..effectiveTo = DateTime(2026, 11, 1);
    expect(d.check(s), 'bad_dates');
    d
      ..effectiveTo = DateTime(2027, 6, 30)
      ..reasonCode = 'military';
    expect(d.check(s), isNull);
    expect(d.toJson(), {
      'request': 'suspend',
      'reason': 'Military service call',
      'reason_code': 'military',
      'effective_from': '2026-12-01',
      'effective_to': '2027-06-30',
    });
    final u = RequestDraft('data_update');
    final o = m.option('data_update')!;
    expect(u.check(o), 'changes_required');
    u.changes['address'] = ' 5 Nile St ';
    expect(u.check(o), isNull);
    expect(u.toJson(), {'request': 'data_update', 'changes': {'address': '5 Nile St'}});
  });

  test('transfer credits: listing, summary, draft', () {
    final d = TransferCredits.fromJson({
      'items': [
        {
          'id': 1, 'user_id': 77, 'source_institution': 'Cairo University', 'source_course': 'Calculus I', 'source_code': 'MTH101',
          'source_grade': 'B', 'source_credits': 3.0, 'course': {'id': 40, 'code': 'MATH1', 'name_ar': 'تفاضل', 'name_en': 'Calculus', 'credit_hours': 3},
          'credited_hours': null, 'counted_hours': 3, 'decision': 'credited', 'counts_in_gpa': false, 'below_min': false,
          'decided_by': {'id': 2, 'name': 'Dr. Sara'}, 'decided_at': '2026-11-20T10:00:00',
        },
        {'id': 2, 'source_course': 'Physics', 'source_grade': 'D', 'source_credits': 2.5, 'course': null, 'decision': 'pending', 'below_min': true},
      ],
      'settings': {'counts_in_gpa': false, 'min_letter': 'C'},
      'summary': {'total': 2, 'pending': 1, 'credited': 1, 'credited_hours': 3.0, 'gpa_hours': 0},
      'can': {'edit': true, 'decide': false},
    });
    expect(d.items.length, 2);
    expect(d.credited, 1);
    expect(d.pending, 1);
    expect(d.creditedHours, 3);
    expect(d.settings.minLetter, 'C');
    expect(d.canEdit, isTrue);
    expect(d.canDecide, isFalse);
    final a = d.items.first;
    expect(a.course!.label, 'MATH1 · Calculus');
    expect(a.hoursHere, 3);
    expect(a.decidedBy, 'Dr. Sara');
    final b = d.items.last;
    expect(b.course, isNull);
    expect(b.belowMin, isTrue);
    expect(creditHoursText(2.5), '2.5');
    expect(creditHoursText(3), '3');
    final draft = CreditDraft.of(b);
    expect(draft.sourceCredits, '2.5');
    draft.sourceCourse = ' ';
    expect(draft.check(), 'source_course');
    draft
      ..sourceCourse = 'Physics I'
      ..creditedHours = '99';
    expect(draft.check(), 'credited_hours');
    draft.creditedHours = '2';
    expect(draft.check(), isNull);
    final j = draft.toJson();
    expect(j['source_course'], 'Physics I');
    expect(j['credited_hours'], 2.0);
    expect(j['source_credits'], 2.5);
    expect(j.containsKey('course_id'), isTrue, reason: 'a PATCH sends every source key');
    expect(j['counts_in_gpa'], isFalse, reason: 'an existing row keeps its own');
    expect(CreditDraft().toJson().containsKey('counts_in_gpa'), isFalse, reason: 'unset = the organization default');
  });

  test('error texts: every phase-6 code, bilingual, status codes fall back', () {
    const codes = [
      'request_closed', 'request_open', 'request_not_found', 'request_unknown', 'no_student_affairs', 'no_council', 'not_council_body',
      'council_not_found', 'no_case', 'field_not_editable', 'changes_required', 'credit_decided', 'course_required', 'course_not_found',
      'bad_transfer_credit', 'transfer_credit_not_found',
    ];
    for (final lang in ['en', 'ar']) {
      AppConfig.lang = lang;
      final m = requestsCodeTexts();
      for (final c in codes) {
        expect(m[c], isNotNull, reason: c);
        expect(m[c]!.trim(), isNotEmpty);
      }
    }
    AppConfig.lang = 'en';
    final e = ApiException(message: 'x', statusCode: 409, code: 'request_open');
    expect(requestsErrorText(e), contains('same request'));
    final s = ApiException(message: 'x', statusCode: 422, code: 'decision_no_required');
    expect(requestsErrorText(s), contains('decision number'));
    for (final k in lifecycleRequestKeys) {
      expect(requestKindLabel(k), isNot('A request'), reason: k);
      expect(requestKindHint(k), isNotEmpty, reason: k);
    }
  });
}
