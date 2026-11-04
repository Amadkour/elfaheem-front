import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/course_students/cs_models.dart';
import 'package:flutter_education_app/features/admin/course_students/cs_profile.dart';
import 'package:flutter_education_app/features/admin/course_students/cs_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'اسم طويل جداً جداً لطالب يختبر التفاف النص في كل الأحجام Abdelrahman Muhammad Al-Hamdani Al-Qurashi';

Map<String, dynamic> _access(String reason, String status, {bool has = false, List<String> flags = const [], String? exp = '2026-11-14T10:00:00'}) => {
      'has_access': has, 'reason': reason, 'course_id': 9, 'source': 'direct', 'plan': 'six_months',
      'starts_at': '2026-05-14T10:00:00', 'expires_at': exp, 'days_left': has ? 12 : -20, 'status': status, 'flags': flags,
    };

CsProfile _profile() => CsProfile.fromJson({
      'student': {'id': 5, 'name': _long, 'email': 'a.very.long.email.address.for.testing@example-university.edu.eg', 'phone': '+201000000000', 'username': 'long_username_here', 'is_active': false, 'joined_at': '2026-01-01T00:00:00', 'identifiers': {'academic_id': '2023001234', 'national_id': '**********1234', 'student_codes': ['S-1', 'S-2']}},
      'total_spent': [{'currency': 'EGP', 'amount': 1382.5}, {'currency': 'USD', 'amount': 20}],
      'courses': [
        for (var i = 0; i < 4; i++)
          {
            'course': {'id': 9 + i, 'name_ar': _long, 'name_en': _long, 'teacher_name': _long},
            'access': [
              _access('enrolled', 'active', has: true),
              _access('cancelled', 'cancelled', flags: ['paid_no_access'], exp: '2099-01-01T00:00:00'),
              _access('expired', 'expired'),
              _access('not_enrolled', 'not_enrolled', exp: null),
            ][i],
          },
      ],
      'platform_subscriptions': [{'plan_code': 'yearly', 'status': 'active', 'starts_at': '2026-01-01T00:00:00', 'ends_at': '2027-01-01T00:00:00'}],
      'payments': [{'id': 1, 'course_id': 9, 'status': 'completed', 'amount': 100, 'currency': 'EGP', 'provider': 'paymob', 'plan': 'monthly', 'paid_at': '2026-10-30T12:00:00'}],
      'events': [
        for (var i = 0; i < 14; i++)
          {
            'id': i,
            'type': ['admin_extended', 'cancelled', 'plan_backfilled', 'payment_failed', 'expired'][i % 5],
            'actor_type': 'admin', 'actor_id': 3, 'course_id': 9, 'reason': _long, 'backfilled': i % 4 == 0,
            'occurred_at': '2026-10-${10 + i}T09:00:00',
            'before': {'status': 'active', 'plan': 'monthly', 'expires_at': '2026-11-10T00:00:00'},
            'after': {'status': 'cancelled', 'expires_at': '2026-11-10T00:00:00'},
          },
      ],
    });

CsRosterRow _row(int i) => CsRosterRow.fromJson({
      'student': {'id': i, 'name': i.isEven ? _long : 'Sara', 'email': 'sara$i@example.com'},
      'access': _access(['enrolled', 'cancelled', 'expired', 'enrolled'][i % 4], ['active', 'cancelled', 'expired', 'expiring_soon'][i % 4],
          has: i % 4 == 0 || i % 4 == 3, flags: i % 4 == 1 ? ['paid_no_access'] : (i % 4 == 3 ? ['access_no_payment'] : [])),
    });

void main() {
  testWidgets('courses list', (tester) async {
    final rows = [
      for (var i = 0; i < 4; i++)
        CsCourseRow.fromJson({'id': i, 'name_ar': _long, 'name_en': _long, 'teacher': {'id': 1, 'name': _long}, 'status': 'published', 'active_students': 1234, 'expiring_soon': 12, 'expired_subscriptions': 8, 'issues': i, 'revenue': {'amount': 123456.5, 'currency': 'EGP'}}),
    ];
    await expectNoLayoutErrors(tester, () => ListView(children: [CsCourseList(items: rows, onOpen: (_) {}), CsPager(page: 2, pages: 5, total: 90, onPage: (_) {})]));
  });

  testWidgets('roster list and chips', (tester) async {
    final roster = CsRoster.fromJson({
      'course': {'id': 9, 'name_ar': 'x', 'name_en': 'x'},
      'counts': {'total': 99, 'active': 50, 'expiring_soon': 3, 'expired': 4, 'cancelled': 5, 'payment_issue': 6, 'access_error': 7, 'not_enrolled': 8},
    });
    await expectNoLayoutErrors(tester, () => ListView(children: [CsStatusChips(roster: roster, selected: CsStatus.expired, onSelect: (_) {})]));
  });

  testWidgets('roster list', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(children: [CsRosterList(items: [for (var i = 0; i < 6; i++) _row(i)], onOpen: (_) {})]));
  });

  testWidgets('lookup results', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(children: [
          CsLookupResults(items: [for (var i = 0; i < 3; i++) CsStudent(id: i, name: _long, email: 'x@example.com', matchedBy: 'national_id')], onOpen: (_) {}),
        ]));
  });

  testWidgets('profile drawer with a long name and many events', (tester) async {
    await expectNoLayoutErrors(tester, () => CsDrawerFrame(title: _long, onClose: () {}, child: CsProfileView(profile: _profile(), onAction: (_, _) {})));
  });

  testWidgets('action sheet', (tester) async {
    final course = _profile().courses.first;
    for (final action in ['extend', 'grant', 'cancel']) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CsActionSheet(action: action, studentName: _long, course: course, onSubmit: (_, _, _) async {})));
    }
  });
}
