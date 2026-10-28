// Points wallet + student live-meeting plan (docs/backend/live-rooms-spec.md §7 – §9): the pure part of
// lib/features/shared/points/points_api.dart and the meeting form's request body (calendar_models.dart).
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/shared/points/points_api.dart';
import 'package:flutter_test/flutter_test.dart';

ApiException coded(int status, String code, [Map<String, dynamic> extra = const {}]) => ApiException(
    statusCode: status,
    message: 'server says $code',
    code: code,
    body: {
      'detail': {'code': code, 'message': 'server says $code', ...extra}
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('roles', () {
    test('staff never count as students; everyone else does', () {
      for (final r in ['teacher', 'admin', 'super-admin', 'developer', 'parent', 'org-admin', 'org-staff']) {
        expect(isStudentForMeetings(r), isFalse, reason: r);
      }
      expect(isStudentForMeetings('student'), isTrue);
      expect(isStudentForMeetings('guest'), isTrue);
      expect(isStudentForMeetings(null), isFalse);
      expect(isStudentForMeetings(''), isFalse);
    });
  });

  group('price maths', () {
    test('money of points rounds to cents', () {
      expect(pointsMoney(30, 1.0), 30);
      expect(pointsMoney(3, 0.333), 1.0);
      expect(pointsMoney(7, 1.255), 8.79);
      expect(moneyText(30, 'SAR'), '30 SAR');
      expect(moneyText(12.5, 'SAR'), '12.50 SAR');
      expect(moneyText(12.5, ''), '12.50');
    });

    test('parsing typed points (western and Arabic-Indic digits)', () {
      expect(parsePoints('50'), 50);
      expect(parsePoints(' 1,000 '), 1000);
      expect(parsePoints('٥٠'), 50);
      expect(parsePoints(''), isNull);
      expect(parsePoints('12.5'), isNull);
    });

    test('minimum top-up and shortfall', () {
      expect(topupAmountError(null, 10), isNotNull);
      expect(topupAmountError(0, 10), isNotNull);
      expect(topupAmountError(9, 10), contains('10'));
      expect(topupAmountError(10, 10), isNull);
      expect(pointsShortfall(12, 30), 18);
      expect(pointsShortfall(30, 30), 0);
      expect(pointsShortfall(40, 30), 0);
    });
  });

  group('models', () {
    test('live plan: inactive student, active, staff', () {
      final p = LivePlan.fromJson({
        'active': false,
        'ends_at': null,
        'price_points': 30,
        'days': 30,
        'free_minutes': 15,
        'balance': 12,
        'needed': true,
      });
      expect(p.active, isFalse);
      expect(p.canAfford, isFalse);
      expect(p.shortfall, 18);
      expect(p.copyWith(balance: 40).canAfford, isTrue);

      final now = DateTime.utc(2026, 10, 28, 12);
      final a = LivePlan.fromJson({'active': true, 'ends_at': '2026-11-27T12:00:00', 'price_points': 30, 'days': 30, 'balance': 0});
      expect(a.endsAt, DateTime.utc(2026, 11, 27, 12));
      expect(a.daysLeft(now), 30);
      expect(a.daysLeft(DateTime.utc(2026, 12, 1)), 0);

      final staff = LivePlan.fromJson({'active': true, 'ends_at': null, 'needed': false});
      expect(staff.needed, isFalse);
      expect(staff.daysLeft(now), 0);
      expect(LivePlan.fromJson(null).needed, isTrue); // defaults when the body is odd
    });

    test('meeting time limit', () {
      expect(MeetingTimeLimit.parse(null), isNull);
      final l = MeetingTimeLimit.parse({'ends_at': '2026-10-28T12:15:00', 'free_minutes': 15})!;
      expect(l.minutesLeft(DateTime.utc(2026, 10, 28, 12)), 15);
      expect(l.minutesLeft(DateTime.utc(2026, 10, 28, 12, 14, 30)), 1);
      expect(l.minutesLeft(DateTime.utc(2026, 10, 28, 12, 20)), 0);
      final notStarted = MeetingTimeLimit.parse({'ends_at': null, 'free_minutes': 20})!;
      expect(notStarted.minutesLeft(DateTime.utc(2026)), 20);
      expect(meetingFreeNote(notStarted, DateTime.utc(2026), owner: true), contains('20'));
      expect(meetingFreeNote(l, DateTime.utc(2026, 10, 28, 13)), contains('over'));
      expect(meetingFreeNote(l, DateTime.utc(2026, 10, 28, 12, 5)), contains('10'));
    });

    test('wallet: methods as strings or maps, history, top-ups', () {
      final w = PointsWallet.fromJson({
        'balance': 45,
        'price_per_point': 0.5,
        'currency': 'EGP',
        'topup_min': 20,
        'methods': [
          'bank_transfer',
          {'id': 'instapay', 'label': 'InstaPay'}
        ],
        'history': [
          {'id': 2, 'delta': -30, 'balance_after': 45, 'kind': 'spend', 'ref_type': 'live_meeting', 'created_at': '2026-10-28T10:00:00'},
          {'id': 1, 'delta': 75, 'balance_after': 75, 'kind': 'topup', 'note': 'ok'},
        ],
        'topups': [
          {'id': 9, 'points': 75, 'amount': 37.5, 'currency': 'EGP', 'method': 'instapay', 'status': 'approved'},
          {'id': 10, 'points': 20, 'amount': '10', 'currency': 'EGP', 'method': 'bank_transfer', 'status': 'pending'},
        ],
      });
      expect(w.methods, ['bank_transfer', 'instapay']);
      expect(w.priceOf(75), 37.5);
      expect(w.pendingTopups, 1);
      expect(w.history.first.kindText, 'Live-meeting plan');
      expect(w.history.first.deltaText, '−30');
      expect(w.history.first.createdAt, DateTime.utc(2026, 10, 28, 10));
      expect(w.history.last.deltaText, '+75');
      expect(w.topups.last.amount, 10);
      expect(w.topups.last.amountText, '10 EGP');
      expect(PointsWallet.fromJson({}).methods, ['bank_transfer', 'instapay']);
    });

    test('pending top-ups first (oldest first), then decided newest first', () {
      PointsTopup x(int id, String status, String at) =>
          PointsTopup.fromJson({'id': id, 'points': 10, 'amount': 10, 'status': status, 'created_at': at});
      final sorted = PointsTopup.sorted([
        x(1, 'approved', '2026-10-01T00:00:00'),
        x(2, 'pending', '2026-10-05T00:00:00'),
        x(3, 'rejected', '2026-10-09T00:00:00'),
        x(4, 'pending', '2026-10-02T00:00:00'),
      ]);
      expect(sorted.map((e) => e.id), [4, 2, 3, 1]);
    });

    test('admin user page and top-up with its user', () {
      final (rows, total) = PointsUserRow.pageFrom({
        'items': [
          {'user': {'id': 5, 'name': 'Sara', 'email': 's@x.io', 'phone': null, 'role': 'student'}, 'balance': 7}
        ],
        'total': 41,
      });
      expect(total, 41);
      expect(rows.single.user.contact, 's@x.io');
      expect(rows.single.balance, 7);
      final t = PointsTopup.listFrom({
        'items': [
          {'id': 1, 'points': 50, 'amount': 50, 'status': 'pending', 'user': {'id': 5, 'name': 'Sara', 'phone': '0100'}}
        ]
      }).single;
      expect(t.user!.name, 'Sara');
      expect(t.user!.contact, '0100');
      expect(t.isPending, isTrue);
    });

    test('settings: read, write, validate', () {
      final s = PointsSettings.fromJson({
        'live_meeting_free_minutes': 20,
        'live_meeting_price_points': 40,
        'live_meeting_plan_days': 15,
        'points_price': 0.75,
        'points_currency': 'SAR',
        'points_topup_min': 5,
      });
      expect(s.toJson(), {
        'live_meeting_free_minutes': 20,
        'live_meeting_price_points': 40,
        'live_meeting_plan_days': 15,
        'points_price': 0.75,
        'points_currency': 'SAR',
        'points_topup_min': 5,
      });
      expect(s.planMoney, 30);
      expect(s.error, isNull);
      expect(PointsSettings.fromJson({'settings': {'live_meeting_price_points': 9}}).pricePoints, 9);
      expect(const PointsSettings(pricePoints: 0).error, isNull); // a free plan is allowed by the server
      expect(const PointsSettings(pricePoints: -1).error, isNotNull);
      expect(const PointsSettings(freeMinutes: 0).error, isNotNull);
      expect(const PointsSettings(planDays: 4000).error, isNotNull);
      expect(const PointsSettings(currency: ' ').error, isNotNull);
      expect(const PointsSettings(freeMinutes: -1).error, isNotNull);
    });
  });

  group('codes and labels', () {
    test('every contract code has text in both languages', () {
      const codes = [
        'points_insufficient',
        'plan_not_needed',
        'live_plan_required',
        'meeting_time_limit',
        'student_meeting_online_private',
        'topup_decided',
        'points_negative_balance',
      ];
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final c in codes) {
          expect(pointsCodeText(c), isNotNull, reason: '$lang $c');
        }
      }
      expect(pointsCodeText('nope'), isNull);
    });

    test('error text prefers the code text, else the server message', () {
      expect(pointsErrorText(coded(402, 'points_insufficient', {'balance': 3, 'price_points': 30})), 'Not enough points');
      expect(pointsErrorCode(coded(402, 'points_insufficient')), 'points_insufficient');
      expect(pointsErrorDetail(coded(402, 'points_insufficient', {'balance': 3}))['balance'], 3);
      expect(pointsErrorText(coded(400, 'something_else')), 'server says something_else');
      final plain = ApiException(statusCode: 500, message: 'boom', body: {'detail': 'boom'});
      expect(pointsErrorCode(plain), isNull);
      expect(pointsErrorText(plain), 'boom');
      // code only in the body (the client did not lift it)
      final bodyOnly = ApiException(statusCode: 403, message: 'm', body: {'detail': {'code': 'meeting_time_limit'}});
      expect(pointsErrorCode(bodyOnly), 'meeting_time_limit');
    });

    test('labels', () {
      expect(pointsMethodText('bank_transfer'), 'Bank transfer');
      expect(pointsMethodText('instapay'), 'InstaPay');
      expect(pointsMethodText('other'), 'other');
      expect(ledgerKindText('grant'), 'Granted by the admin');
      expect(ledgerKindText('spend'), 'Spent');
      expect(topupStatusText(topupStatusFrom('pending')), 'Under review');
      expect(topupStatusFrom('weird'), TopupStatus.unknown);
      expect(const LivePlanDeclined().toString(), pointsCodeText('live_plan_required'));
      expect(const LiveJoinMessage('x').toString(), 'x');
    });

    test('receipt kind from its bytes', () {
      expect(isPdfBytes(Uint8List.fromList('%PDF-1.7'.codeUnits)), isTrue);
      expect(isPdfBytes(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), isFalse);
      expect(isPdfBytes(Uint8List(0)), isFalse);
    });
  });

  group('meeting form body (optional online title, students)', () {
    Map<String, dynamic> body({String title = '', String mode = 'online', bool student = false}) => calMeetingBody(
          title: title,
          startsAt: '2026-10-28T10:00:00.000Z',
          endsAt: '2026-10-28T10:30:00.000Z',
          mode: mode,
          location: ' Hall 3 ',
          orgId: 4,
          audience: {'user_ids': [7], 'dept_ids': [], 'head_dept_ids': [], 'course_ids': []},
          emptyAudience: {'user_ids': [], 'dept_ids': [], 'head_dept_ids': [], 'course_ids': []},
          student: student,
        );

    test('an online meeting without a title sends no title', () {
      expect(calMeetingTitleError('  ', 'online'), isNull);
      final b = body(title: '   ');
      expect(b.containsKey('title'), isFalse);
      expect(b['mode'], 'online');
      expect(b.containsKey('location'), isFalse);
      expect(b['org_id'], 4);
      expect(b.containsKey('dept_id'), isFalse);
    });

    test('an in-person meeting needs its title', () {
      expect(calMeetingTitleError('', 'offline'), isNotNull);
      expect(calMeetingTitleError('Review', 'offline'), isNull);
      final b = body(title: ' Review ', mode: 'offline');
      expect(b['title'], 'Review');
      expect(b['location'], 'Hall 3');
      expect(b['audience']['user_ids'], [7]);
    });

    test('a student meeting is always online and private', () {
      final b = body(mode: 'offline', student: true);
      expect(b['mode'], 'online');
      expect(b['audience']['user_ids'], isEmpty);
      expect(b.containsKey('location'), isFalse);
      expect(b.containsKey('title'), isFalse);
    });
  });
}
