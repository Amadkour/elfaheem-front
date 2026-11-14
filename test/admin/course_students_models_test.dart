import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/admin/course_students/cs_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> access({String reason = 'enrolled', String status = 'active', bool has = true, String? exp = '2027-04-28T16:19:07', List<String> flags = const []}) => {
      'has_access': has, 'reason': reason, 'course_id': 9, 'source': 'direct', 'plan': 'six_months',
      'starts_at': '2026-10-30T12:02:16', 'expires_at': exp, 'days_left': 175, 'status': status, 'flags': flags,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('times are parsed as UTC, with or without an offset', () {
    final a = CsAccess.fromJson(access());
    expect(a.expiresAt!.isUtc, isTrue);
    expect(a.expiresAt, DateTime.utc(2027, 4, 28, 16, 19, 7));
    expect(csTime('2026-01-01T10:00:00+02:00'), DateTime.utc(2026, 1, 1, 8));
    expect(csTime('nope'), isNull);
    expect(csTime(null), isNull);
  });

  test('CourseAccess survives missing keys and unknown values', () {
    final a = CsAccess.fromJson({'status': 'brand_new_status', 'flags': ['paid_no_access', 'x']});
    expect(a.hasAccess, isFalse);
    expect(a.kind, CsStatus.unknown);
    expect(a.paidNoAccess, isTrue);
    expect(CsAccess.fromJson(null).reason, '');
    expect(csStatusLabel(a.kind), isNotEmpty);
  });

  test('course list row and filters', () {
    final p = CsCoursesPage.fromJson({
      'items': [
        {'id': 9, 'name_ar': 'ع', 'name_en': 'Physics', 'teacher': {'id': 4, 'name': 'T'}, 'status': 'published', 'active_students': 19, 'expiring_soon': 2, 'expired_subscriptions': 1, 'issues': 1, 'revenue': {'amount': 4210.5, 'currency': 'EGP'}},
      ],
      'total': 41, 'page': 1, 'page_size': 20,
      'filters': {'teachers': [{'id': 4, 'name': 'T'}], 'categories': [{'id': 1, 'name_ar': 'ف', 'name_en': 'Sci'}]},
    });
    final r = p.items.single;
    expect(r.name, 'Physics');
    expect([r.active, r.expiringSoon, r.expired, r.issues], [19, 2, 1, 1]);
    expect(r.revenue, 4210.5);
    expect(r.currency, 'EGP');
    expect(p.pages, 3);
    expect(p.teachers.single.id, 4);
    expect(p.categories.single.name, 'Sci');
    expect(CsCoursesPage.fromJson(null).items, isEmpty);
  });

  test('roster counts and rows', () {
    final r = CsRoster.fromJson({
      'course': {'id': 9, 'name_ar': 'ع', 'name_en': 'Physics', 'teacher': {'id': 4, 'name': 'T'}},
      'counts': {'total': 22, 'active': 17, 'expiring_soon': 2, 'payment_issue': 1},
      'items': [
        {'student': {'id': 5, 'name': 'Sara', 'email': 's@x.io'}, 'access': access(flags: ['access_no_payment']), 'last_payment': null},
      ],
      'total': 22, 'page': 1, 'page_size': 25,
    });
    expect(r.countOf(CsStatus.active), 17);
    expect(r.countOf(CsStatus.expiringSoon), 2);
    expect(r.countOf(CsStatus.expired), 0);
    expect(r.items.single.access.accessNoPayment, isTrue);
    expect(r.items.single.student.contact, 's@x.io');
    expect(csStatusWire(CsStatus.paymentIssue), 'payment_issue');
  });

  test('reason text, English', () {
    expect(csReasonText(CsAccess.fromJson(access())), contains('2027'));
    expect(csReasonText(CsAccess.fromJson(access(reason: 'expired', status: 'expired', has: false, exp: '2026-11-14T10:00:00'))), 'Plan ended on 14 Nov 2026');
    expect(csReasonText(CsAccess.fromJson(access(reason: 'payment_pending', status: 'payment_issue', has: false))), 'Payment pending review');
    final removed = CsAccess.fromJson(access(reason: 'cancelled', status: 'cancelled', has: false, exp: '2099-01-02T00:00:00', flags: ['paid_no_access']));
    expect(csReasonText(removed), startsWith('Removed by an admin while the paid plan still runs until'));
    expect(csReasonText(CsAccess.fromJson(access(reason: 'not_enrolled', status: 'not_enrolled', has: false, exp: null))), 'Never enrolled in this course');
  });

  test('reason text, Arabic', () {
    AppConfig.lang = 'ar';
    expect(csReasonText(CsAccess.fromJson(access(reason: 'payment_pending', has: false))), 'الدفع قيد المراجعة');
    expect(csReasonText(CsAccess.fromJson(access(reason: 'expired', has: false, exp: '2026-11-14T10:00:00'))), startsWith('انتهت الباقة في'));
  });

  test('which actions are offered', () {
    const all = ['extend', 'reactivate', 'grant', 'cancel'];
    final active = CsAccess.fromJson(access());
    final expired = CsAccess.fromJson(access(reason: 'expired', status: 'expired', has: false));
    final none = CsAccess.fromJson(access(reason: 'not_enrolled', status: 'not_enrolled', has: false, exp: null));
    final lifetime = CsAccess.fromJson(access(exp: null));
    expect([for (final a in all) csActionValid(a, active)], [true, false, false, true]);
    expect([for (final a in all) csActionValid(a, expired)], [true, true, true, false]);
    expect([for (final a in all) csActionValid(a, none)], [false, false, true, false]);
    expect(csActionValid('extend', lifetime), isFalse);
  });

  test('profile, timeline merge and error codes', () {
    final p = CsProfile.fromJson({
      'student': {'id': 5, 'name': 'Sara', 'is_active': true, 'joined_at': '2026-01-01T00:00:00', 'identifiers': {'academic_id': 'A1', 'national_id': '**********1234', 'student_codes': ['S9']}},
      'total_spent': [{'currency': 'EGP', 'amount': 382.0}],
      'courses': [
        {'course': {'id': 9, 'name_ar': 'ع', 'name_en': 'Physics'}, 'access': access()},
      ],
      'payments': [
        {'id': 1, 'course_id': 9, 'status': 'completed', 'amount': 100, 'currency': 'EGP', 'paid_at': '2026-10-30T12:00:00'},
        {'id': 2, 'course_id': 9, 'status': 'completed', 'amount': 50, 'currency': 'EGP', 'paid_at': '2026-09-01T12:00:00'},
      ],
      'events': [
        {'id': 1, 'type': 'payment_succeeded', 'actor_type': 'webhook', 'payment_id': 1, 'course_id': 9, 'occurred_at': '2026-10-30T12:00:01'},
        {'id': 2, 'type': 'admin_extended', 'actor_type': 'admin', 'actor_id': 3, 'course_id': 9, 'reason': 'goodwill', 'occurred_at': '2026-11-01T09:00:00', 'before': {'status': 'active', 'expires_at': '2026-11-10T00:00:00'}, 'after': {'status': 'active', 'expires_at': '2026-12-10T00:00:00'}},
        {'id': 3, 'type': 'plan_backfilled', 'actor_type': 'system', 'backfilled': true, 'occurred_at': '2026-08-01T00:00:00'},
      ],
    });
    expect(p.nationalId, '**********1234');
    expect(p.totalSpent.single.amount, 382);
    expect(p.courseName(9), 'Physics');
    final tl = csTimeline(p);
    // payment 1 is already described by its event, payment 2 is not
    expect(tl.length, 4);
    expect(tl.first.event!.type, 'admin_extended');
    for (var i = 1; i < tl.length; i++) {
      expect(tl[i].at!.isAfter(tl[i - 1].at!), isFalse, reason: 'newest first');
    }
    expect(tl.last.event!.backfilled, isTrue);
    expect(csChangeText(tl.first.event!), contains('->'));
    expect(csErrorText('already_has_access', 'x'), 'The student already has access');
    expect(csErrorText('weird', 'server text'), 'server text');
  });
}
