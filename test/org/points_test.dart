// Points wallet + student live-meeting plan (docs/backend/live-rooms-spec.md §7 – §9): the pure part of
// lib/features/payments/points/points_api.dart and the meeting form's request body (calendar_models.dart).
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';
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
        // Part 3 defaults when an older server does not send them
        'live_meeting_free_minutes_daily': 30,
        'points_card_enabled': true,
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

  group('Part 3: card top-ups (§13)', () {
    test('card is a method with a label; the wallet knows it is offered', () {
      expect(pointsMethodText('card'), 'Card');
      final w = PointsWallet.fromJson({'methods': ['card', 'bank_transfer']});
      expect(w.hasCard, isTrue);
      expect(PointsWallet.fromJson({'methods': ['bank_transfer']}).hasCard, isFalse);
      expect(PointsWallet.fromJson({'methods': [{'id': 'card'}]}).hasCard, isTrue);
    });

    test('a card top-up: provider, payment id, no receipt, its own status text', () {
      final x = PointsTopup.fromJson({
        'id': 31,
        'points': 50,
        'amount': 50,
        'currency': 'SAR',
        'method': 'card',
        'provider': 'moyasar',
        'payment_id': 'pay_abc123',
        'status': 'pending',
        'created_at': '2026-10-28T10:00:00',
      });
      expect(x.isCard, isTrue);
      expect(x.provider, 'moyasar');
      expect(x.paymentId, 'pay_abc123');
      expect(x.hasReceipt, isFalse);
      expect(x.methodText, 'Card · Moyasar');
      expect(x.statusText, 'Waiting for payment');
      final approved = PointsTopup.fromJson({'id': 31, 'method': 'card', 'status': 'approved'});
      expect(approved.statusText, 'Approved');
      // a transfer keeps its receipt (has_receipt absent = true; false when the server says so)
      expect(PointsTopup.fromJson({'id': 1, 'method': 'bank_transfer'}).hasReceipt, isTrue);
      expect(PointsTopup.fromJson({'id': 1, 'method': 'bank_transfer', 'has_receipt': false}).hasReceipt, isFalse);
      expect(PointsTopup.fromJson({'id': 1, 'method': 'instapay', 'status': 'pending'}).statusText, 'Under review');
      expect(pointsProviderText('paymob'), 'Paymob');
      expect(pointsProviderText(null), '');
    });

    test('checkout: the fields that open the payment page', () {
      final c = PointsCheckout.fromJson({
        'topup_id': 31,
        'provider': 'moyasar',
        'amount': 62.5,
        'currency': 'SAR',
        'points': 50,
        'checkout_url': 'https://alfheemacademy.com/api/api/v1/payments/moyasar/form?t=abc',
      });
      expect(c.topupId, 31);
      expect(c.provider, 'moyasar');
      expect(c.amount, 62.5);
      expect(c.points, 50);
      expect(c.canOpen, isTrue);
      expect(c.alreadyPaid, isFalse);
      // nested top-up, another url key
      final n = PointsCheckout.fromJson({'topup': {'id': 9, 'points': 10, 'status': 'pending'}, 'payment_url': 'https://p.example/x'});
      expect(n.topupId, 9);
      expect(n.checkoutUrl, 'https://p.example/x');
      expect(PointsCheckout.fromJson({'topup_id': 1}).canOpen, isFalse);
      expect(PointsCheckout.fromJson({'topup_id': 1, 'already_paid': true}).alreadyPaid, isTrue);
    });

    test('polling: until decided, a failed read is retried, a timeout says so', () async {
      final slept = <Duration>[];
      Future<void> sleep(Duration d) async => slept.add(d);
      PointsTopup st(String s) => PointsTopup.fromJson({'id': 1, 'method': 'card', 'status': s});

      var calls = 0;
      final answers = [st('pending'), st('pending'), st('approved')];
      final ok = await pollTopup(() async => answers[calls++], sleep: sleep);
      expect(ok.approved, isTrue);
      expect(calls, 3);
      expect(slept.length, 2);

      calls = 0;
      final r = await pollTopup(() async {
        calls++;
        if (calls == 1) throw ApiException(statusCode: 500, message: 'boom');
        return st('rejected');
      }, sleep: sleep);
      expect(r.rejected, isTrue);
      expect(r.error, isNull);

      slept.clear();
      final late = await pollTopup(() async => st('pending'),
          every: const Duration(seconds: 3), timeout: const Duration(seconds: 9), sleep: sleep);
      expect(late.timedOut, isTrue);
      expect(late.topup!.isPending, isTrue);
      expect(slept.length, 3);

      // zero wait = one read (the payment page was closed)
      slept.clear();
      final once = await pollTopup(() async => st('pending'), timeout: Duration.zero, sleep: sleep);
      expect(once.timedOut, isTrue);
      expect(slept, isEmpty);

      final down = await pollTopup(() async => throw ApiException(statusCode: 503, message: 'down'), timeout: Duration.zero, sleep: sleep);
      expect(down.topup, isNull);
      expect(down.error, isNotNull);
    });

    test('settings: daily minutes and the card switch', () {
      final s = PointsSettings.fromJson({'live_meeting_free_minutes_daily': 0, 'points_card_enabled': false});
      expect(s.freeMinutesDaily, 0);
      expect(s.cardEnabled, isFalse);
      expect(s.error, isNull); // 0 = no daily cap
      expect(s.toJson()['live_meeting_free_minutes_daily'], 0);
      expect(s.toJson()['points_card_enabled'], false);
      expect(const PointsSettings(freeMinutesDaily: -1).error, isNotNull);
      expect(const PointsSettings(freeMinutesDaily: 2000).error, isNotNull);
    });
  });

  group('Part 3: daily cap (§14) and auto-renew (§15)', () {
    test('plan: daily free minutes / left, auto_renew, days_left', () {
      final p = LivePlan.fromJson({
        'active': false,
        'needed': true,
        'free_minutes': 15,
        'daily_free_minutes': 30,
        'daily_free_left': 12,
        'auto_renew': true,
        'days_left': 0,
      });
      expect(p.dailyFreeMinutes, 30);
      expect(p.dailyFreeLeft, 12);
      expect(p.hasDailyCap, isTrue);
      expect(p.dailyLeft, 12);
      expect(p.dailyUsedUp, isFalse);
      expect(p.autoRenew, isTrue);
      expect(p.copyWith(autoRenew: false).autoRenew, isFalse);
      expect(p.copyWith(balance: 3).dailyFreeLeft, 12);

      final used = LivePlan.fromJson({'needed': true, 'daily_free_minutes': 30, 'daily_free_left': 0});
      expect(used.dailyUsedUp, isTrue);
      // an active plan or no cap: no daily limit
      expect(LivePlan.fromJson({'active': true, 'needed': true, 'daily_free_minutes': 30, 'daily_free_left': 0}).dailyUsedUp, isFalse);
      expect(LivePlan.fromJson({'needed': true, 'daily_free_minutes': 0}).hasDailyCap, isFalse);
      expect(LivePlan.fromJson({'needed': true}).hasDailyCap, isFalse); // an older server

      final now = DateTime.utc(2026, 10, 28, 12);
      final a = LivePlan.fromJson({'active': true, 'ends_at': '2026-10-31T12:00:00', 'days_left': 3});
      expect(a.daysLeft(now), 3);
      expect(planDaysLeftText(a.daysLeft(now)), '3 days left');
      expect(planDaysLeftText(1), '1 day left');
      expect(planDaysLeftText(0), 'Ends today');
      // without days_left the app computes it
      expect(LivePlan.fromJson({'active': true, 'ends_at': '2026-10-31T12:00:00'}).daysLeft(now), 3);
      expect(dailyFreeLeftText(12, 30), '12 of 30 free minutes left today');
      expect(dailyFreeLeftText(0, 30), contains('used up'));
    });

    test('meeting time limit: daily minutes / left and the window', () {
      final l = MeetingTimeLimit.parse({'ends_at': null, 'free_minutes': 15, 'daily_minutes': 30, 'daily_left': 10})!;
      expect(l.dailyMinutes, 30);
      expect(l.dailyLeft, 10);
      expect(l.hasDailyCap, isTrue);
      expect(l.windowMinutes, 10); // min(free, daily left)
      final note = meetingFreeNote(l, DateTime.utc(2026), owner: true);
      expect(note, contains('first 10 live minutes'));
      expect(note, contains('10 of 30 free minutes left today'));
      expect(meetingFreeNote(l, DateTime.utc(2026)), isNot(contains('today'))); // not the owner's business

      final used = MeetingTimeLimit.parse({'ends_at': null, 'free_minutes': 15, 'daily_minutes': 30, 'daily_left': 0})!;
      expect(used.windowMinutes, 0);
      expect(meetingFreeNote(used, DateTime.utc(2026), owner: true), contains("Today's free time is used up"));
      expect(meetingFreeNote(used, DateTime.utc(2026)), contains('for today is used up'));

      final plenty = MeetingTimeLimit.parse({'free_minutes': 15, 'daily_minutes': 30, 'daily_left': 25})!;
      expect(plenty.windowMinutes, 15);
      // no daily fields (older server): the plain free minutes
      final old = MeetingTimeLimit.parse({'free_minutes': 15})!;
      expect(old.hasDailyCap, isFalse);
      expect(old.windowMinutes, 15);
      expect(meetingFreeNote(old, DateTime.utc(2026), owner: true), isNot(contains('today')));
    });

    test('402 live_plan_required with reason daily_limit', () {
      final e = coded(402, 'live_plan_required', {'reason': 'daily_limit', 'price_points': 30, 'balance': 0});
      expect(pointsErrorCode(e), 'live_plan_required');
      expect(pointsErrorDetail(e)['reason'], kDailyLimitReason);
      expect(livePlanReasonText('daily_limit'), "Today's free time is used up");
      expect(livePlanReasonText(null), isNull);
      expect(livePlanReasonText('meeting_limit'), isNull);
      AppConfig.lang = 'ar';
      expect(livePlanReasonText('daily_limit'), isNotEmpty);
    });

    test('notification types → the wallet / plan module', () {
      for (final t in ['live_plan', 'live_plan_required', 'live_plan_expiring', 'live_plan_renewed', 'live_plan_renew_failed']) {
        expect(pointsModuleFor(t), 'live_plan', reason: t);
      }
      expect(pointsModuleFor('points'), 'points');
      expect(pointsModuleFor('points_topup'), 'points');
      expect(pointsModuleFor('course'), isNull);
      expect(pointsModuleFor(null), isNull);
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
