import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/course_access.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _access({String reason = 'enrolled', bool has = true, String? exp, String status = 'active', int? days}) => {
      'has_access': has,
      'reason': reason,
      'course_id': 9,
      'source': 'direct',
      'subscription_id': 191,
      'payment_id': 209,
      'plan': 'six_months',
      'starts_at': '2026-10-30T12:02:16',
      'expires_at': exp,
      'days_left': days,
      'status': status,
      'flags': ['paid_no_access'],
    };

CourseAccess _a(String reason, {bool has = false, String? exp}) => CourseAccess.tryParse(_access(reason: reason, has: has, exp: exp))!;

Map<String, dynamic> _course({Object? access, bool withAccess = true, bool enrolled = true, bool? expiredFlag}) => {
      'id': 9,
      'is_enrolled': enrolled,
      'is_published': true,
      if (withAccess) 'access': access,
      'access_expired': ?expiredFlag,
    };

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');
  tearDownAll(() => translation = {});

  group('CourseAccess parsing', () {
    test('full payload', () {
      final a = CourseAccess.tryParse(_access(exp: '2027-04-28T16:19:07', days: 175))!;
      expect(a.hasAccess, isTrue);
      expect(a.reason, 'enrolled');
      expect(a.courseId, 9);
      expect(a.plan, 'six_months');
      expect(a.expiresAt, DateTime.utc(2027, 4, 28, 16, 19, 7)); // no offset = UTC
      expect(a.expiresAt!.isUtc, isTrue);
      expect(a.daysLeft, 175);
      expect(a.flags, ['paid_no_access']);
    });

    test('unknown reason and status are tolerated, garbage is null', () {
      final a = CourseAccess.tryParse({'has_access': false, 'reason': 'brand_new', 'status': 'weird'})!;
      expect(a.reason, 'brand_new');
      expect(a.expiresAt, isNull);
      expect(CourseAccess.tryParse(null), isNull);
      expect(CourseAccess.tryParse('x'), isNull);
      expect(CourseAccess.tryParse(<String, dynamic>{}), isNull);
    });

    test('CourseModel reads access and access_expired', () {
      final m = CourseModel.fromJson(_course(access: _access(reason: 'expired', has: false, exp: '2026-11-01T00:00:00'), enrolled: false));
      expect(m.isEnrolled, isFalse);
      expect(m.access!.reason, 'expired');
      expect(m.accessExpired, isTrue);
      expect(CourseModel.fromJson(_course(access: null, enrolled: false, expiredFlag: true)).accessExpired, isTrue);
    });

    test('an older server without access keeps working', () {
      final m = CourseModel.fromJson(_course(withAccess: false));
      expect(m.access, isNull);
      expect(m.accessExpired, isFalse);
      expect(m.isEnrolled, isTrue);
    });
  });

  group('reason text', () {
    const reasons = ['expired', 'payment_pending', 'payment_failed', 'cancelled', 'refunded', 'org_subscription_required', 'not_enrolled', 'zzz'];

    test('every reason has a distinct sentence in both languages', () {
      final en = <String>{}, ar = <String>{};
      for (final r in reasons) {
        AppConfig.lang = 'en';
        en.add(accessReasonTextFor(r));
        AppConfig.lang = 'ar';
        ar.add(accessReasonTextFor(r));
      }
      expect(en.length, reasons.length);
      expect(ar.length, reasons.length);
      expect(ar.every((t) => RegExp(r'[؀-ۿ]').hasMatch(t)), isTrue);
    });

    test('expired carries the end date', () {
      final a = _a('expired', exp: '2026-11-01T10:00:00');
      expect(accessReasonText(a), contains('2026'));
      expect(accessReasonText(a), contains('renew'));
      AppConfig.lang = 'ar';
      expect(accessReasonText(a), contains('جدّد'));
    });

    test('403 and 402 bodies map to the reason text', () {
      final e403 = ApiException(
        statusCode: 403,
        message: 'x',
        code: 'course_access_denied',
        body: {'detail': {'code': 'course_access_denied', 'reason': 'cancelled', 'message': 'ar'}},
      );
      expect(accessDeniedText(e403), accessReasonTextFor('cancelled'));
      final e402 = ApiException(statusCode: 402, message: 'x', code: 'SUBSCRIPTION_REQUIRED', body: {'detail': {'code': 'SUBSCRIPTION_REQUIRED'}});
      expect(accessDeniedText(e402), accessReasonTextFor('org_subscription_required'));
      expect(accessDeniedText(const ApiException(statusCode: 500, message: 'x')), isNull);
    });
  });

  group('enroll bar mode', () {
    test('mapping', () {
      expect(enrollBarMode(enrolled: true, access: _a('enrolled', has: true)), EnrollBarMode.hidden);
      expect(enrollBarMode(enrolled: false, access: _a('expired')), EnrollBarMode.renew);
      expect(enrollBarMode(enrolled: false, access: _a('payment_pending')), EnrollBarMode.pending);
      expect(enrollBarMode(enrolled: false, access: _a('cancelled')), EnrollBarMode.support);
      expect(enrollBarMode(enrolled: false, access: _a('refunded')), EnrollBarMode.support);
      expect(enrollBarMode(enrolled: false, access: _a('not_enrolled')), EnrollBarMode.subscribe);
      expect(enrollBarMode(enrolled: false, access: _a('payment_failed')), EnrollBarMode.subscribe);
      expect(enrollBarMode(enrolled: false), EnrollBarMode.subscribe);
    });
  });

  group('locked session message', () {
    test('kind', () {
      expect(lockedSessionKind(enrolled: true, hasBlockingExam: false), LockedKind.finishPrevious);
      expect(lockedSessionKind(enrolled: true, hasBlockingExam: true), LockedKind.blockingExam);
      expect(lockedSessionKind(enrolled: false, hasBlockingExam: false), LockedKind.subscribe);
      expect(lockedSessionKind(enrolled: false, hasBlockingExam: false, access: _a('expired')), LockedKind.renew);
    });

    test('an enrolled student is never told to subscribe', () {
      final m = lockedSessionMessage(LockedKind.finishPrevious, previousName: 'Intro');
      expect(m, contains('Intro'));
      expect(m.toLowerCase(), isNot(contains('subscribe')));
      AppConfig.lang = 'ar';
      expect(lockedSessionMessage(LockedKind.finishPrevious, previousName: 'Intro'), isNot(contains('اشترك')));
      expect(lockedSessionMessage(LockedKind.finishPrevious), isNot(contains('{name}')));
    });

    test('exam, subscribe and renew wording', () {
      expect(lockedSessionMessage(LockedKind.blockingExam, examName: 'Quiz 1'), endsWith('Quiz 1'));
      expect(lockedSessionMessage(LockedKind.subscribe).toLowerCase(), contains('subscribe'));
      expect(lockedSessionMessage(LockedKind.renew, access: _a('expired', exp: '2026-11-01T00:00:00')), contains('renew'));
    });
  });

  group('offline verdict', () {
    test('online + denied for a blocking reason -> refuse', () {
      for (final r in ['expired', 'cancelled', 'refunded']) {
        expect(offlineVerdict(online: true, courseKnown: true, access: _a(r)), OfflineVerdict.refuse, reason: r);
      }
    });

    test('fail open: network error, offline, unknown course, granted, other reasons', () {
      expect(offlineVerdict(online: true, courseKnown: true, access: null), OfflineVerdict.allow); // network error / timeout
      expect(offlineVerdict(online: false, courseKnown: true, access: _a('expired')), OfflineVerdict.allow); // offline keeps the 30-day rule
      expect(offlineVerdict(online: true, courseKnown: false, access: _a('expired')), OfflineVerdict.allow); // old copy
      expect(offlineVerdict(online: true, courseKnown: true, access: _a('enrolled', has: true)), OfflineVerdict.allow);
      expect(offlineVerdict(online: true, courseKnown: true, access: _a('payment_pending')), OfflineVerdict.allow);
      expect(offlineVerdict(online: true, courseKnown: true, access: _a('something_new')), OfflineVerdict.allow);
    });
  });
}
