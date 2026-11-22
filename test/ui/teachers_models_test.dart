// Learning Hub v2 teachers and packages (D-1620 .. D-1639): the contract shapes (CONTRACT.md §1, §2 + Corrections v2
// C1 – C3), the wizard checks and the join-state mapping; plus the API calls over FakeApi (no_profile → empty,
// the enrol answer, the review queue query).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/teachers/teacher_review_admin.dart' show teacherRejectReasonError;
import 'package:flutter_education_app/features/teachers/teachers_api.dart';
import 'package:flutter/material.dart' show TextDirection;
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_education_app/features/teachers/teachers_parts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> profileJson({String status = 'approved'}) => {
      'user_id': 7,
      'name': 'الشيخة فاطمة',
      'avatar_url': 'https://alfheemacademy.com/a.png',
      'gender': 'female',
      'subjects': ['quran', 'tajweed', 'chemistry'],
      'bio': 'معلمة قرآن منذ خمس عشرة سنة.',
      'qualifications': 'إجازة برواية حفص',
      'languages': ['ar', 'en'],
      'years_experience': 15,
      'goals': ['memorization'],
      'session_types': ['individual', 'group'],
      'delivery': ['online', 'nowhere'],
      'status': status,
      'rejection_reason': status == 'rejected' ? 'صورة الإجازة غير واضحة' : null,
      'submitted_at': '2026-11-20T10:00:00',
      'reviewed_at': null,
      'documents': [
        {'id': 3, 'doc_type': 'ijazah', 'file_name': 'ijazah.pdf', 'status': 'pending', 'rejection_reason': null},
      ],
      'rating': 4.8,
      'reviews_count': 12,
      'packages_count': 2,
      'next_free': '2026-11-25T16:00:00',
    };

Map<String, dynamic> packageJson({
  int seatsTaken = 3,
  int max = 10,
  String overbook = 'waitlist',
  int? overbookLimit,
  double price = 300,
  int? discount = 10,
  String status = 'published',
  Map<String, dynamic>? mine,
}) =>
    {
      'id': 11,
      'teacher_id': 7,
      'teacher': {'user_id': 7, 'name': 'الشيخة فاطمة', 'avatar_url': null, 'gender': 'female'},
      'subject': 'tajweed',
      'title': 'أحكام النون الساكنة',
      'description': 'ثماني جلسات',
      'goal': 'إتقان الأحكام',
      'level': 'beginner',
      'delivery': 'both',
      'location': 'مسجد النور',
      'sessions_count': 8,
      'session_minutes': 45,
      'schedule': {'freq': 'weekly', 'interval': 1, 'weekdays': [0, 3]},
      'series_id': null,
      'start_date': '2026-12-01',
      'max_students': max,
      'overbook': overbook,
      'overbook_limit': overbookLimit,
      'price': price,
      'currency': 'egp',
      'discount_percent': discount,
      'final_price': price * (100 - (discount ?? 0)) / 100,
      'status': status,
      'seats_taken': seatsTaken,
      'waitlist_count': 2,
      'my_enrollment': mine,
      'created_at': '2026-11-21T08:00:00',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppConfig.lang = 'en');

  test('the final review codes have texts in both languages (D-1646)', () {
    const codes = ['teacher_only', 'students_only', 'not_pending', 'not_enrolled', 'card_unavailable', 'gateway_error',
      'quran_gender_rule', 'bad_rule', 'occurrence_cancelled', 'no_occurrences', 'series_ended', 'badge_key_taken',
      'sl_bad_subject', 'reason_required', 'not_due'];
    for (final c in codes) {
      final e = ApiException(statusCode: 409, message: 'server', code: c);
      AppConfig.lang = 'en';
      final en = teachersErrorText(e);
      AppConfig.lang = 'ar';
      final ar = teachersErrorText(e);
      expect(en, isNot('server'), reason: c);
      expect(ar, isNot(en), reason: c);
    }
    AppConfig.lang = 'en';
  });

  group('shapes', () {
    test('TeacherProfile reads the contract (C1: session_types + delivery)', () {
      final p = TeacherProfile.fromJson(profileJson());
      expect(p.userId, 7);
      expect(p.gender, 'female');
      expect(p.subjects, ['quran', 'tajweed']); // an unknown subject is dropped
      expect(p.sessionTypes, ['individual', 'group']);
      expect(p.delivery, ['online']);
      expect(p.approved, isTrue);
      expect(p.docsEditable, isFalse);
      expect(p.documents.single.docType, 'ijazah');
      expect(p.documents.single.isPdf, isTrue);
      expect(p.submittedAt, DateTime.utc(2026, 11, 20, 10));
      expect(p.nextFree!.isUtc, isTrue);
      expect(p.rating, 4.8);
    });

    test('old Quran genders and an empty profile', () {
      expect(TeacherProfile.fromJson({'user_id': 1, 'gender': 'm'}).gender, 'male');
      expect(TeacherProfile.empty.exists, isFalse);
      expect(TeacherProfile.fromJson(profileJson(status: 'rejected')).rejectionReason, isNotEmpty);
    });

    test('the draft sends the whole object in the server order', () {
      final d = TeacherProfileDraft.of(TeacherProfile.fromJson(profileJson()))
        ..subjects = ['tajweed', 'quran']
        ..delivery = ['offline', 'online'];
      final j = d.toJson();
      expect(j['subjects'], ['quran', 'tajweed']);
      expect(j['delivery'], ['online', 'offline']);
      expect(j['session_types'], ['individual', 'group']);
      expect(j.keys, containsAll(['name', 'gender', 'bio', 'qualifications', 'languages', 'years_experience', 'avatar_url']));
    });

    test('editing gender / subjects / qualifications on an approved profile re-reviews it', () {
      final p = TeacherProfile.fromJson(profileJson());
      final d = TeacherProfileDraft.of(p);
      expect(d.reReviewsAgainst(p), isFalse);
      d.bio = 'changed';
      expect(d.reReviewsAgainst(p), isFalse);
      d.subjects = ['quran'];
      expect(d.reReviewsAgainst(p), isTrue);
      expect(TeacherProfileDraft.of(p).reReviewsAgainst(TeacherProfile.fromJson(profileJson(status: 'draft'))), isFalse);
    });

    test('Package reads the contract (+ C3 overbook_limit)', () {
      final p = TeacherPackage.fromJson(packageJson(overbook: 'allow', overbookLimit: 2));
      expect(p.currency, 'EGP');
      expect(p.startDate, DateTime(2026, 12, 1));
      expect(p.finalPrice, 270);
      expect(p.seatsLeft, 7);
      expect(p.overbookLimit, 2);
      expect(p.schedule!['freq'], 'weekly');
      expect(p.teacher!.name, isNotEmpty);
      expect(packageFinalPrice(99.99, 15), 84.99);
    });

    test('enrol answer: the store-style checkout (C2)', () {
      final r = PackageEnrollResult.fromJson({
        'status': 'pending_payment',
        'position': null,
        'checkout': {'url': 'https://pay.example/x', 'token': 'tok', 'provider': 'moyasar'},
        'expires_at': '2026-11-21T10:30:00',
      });
      expect(r.needsPayment, isTrue);
      expect(r.checkoutUrl, 'https://pay.example/x');
      expect(r.state, PackageJoinState.pendingPayment);
      expect(PackageEnrollResult.fromJson({'status': 'waitlisted', 'position': 3, 'checkout': null}).state, PackageJoinState.waitlisted);
      expect(PackageEnrollResult.fromJson({'status': 'active'}).needsPayment, isFalse);
    });

    test('lists: teachers page, my teachers, roster', () {
      final l = TeacherListPage.fromJson({'items': [profileJson()], 'total': 41, 'page': 2});
      expect((l.items.length, l.total, l.page), (1, 41, 2));
      final mine = myTeachersFromJson([
        {'teacher': profileJson(), 'active_packages': [packageJson()], 'next_session': {'starts_at': '2026-12-01T15:00:00'}},
      ]);
      expect(mine.single.activePackages.single.id, 11);
      expect(mine.single.nextSession, DateTime.utc(2026, 12, 1, 15));
      final roster = packageRosterFromJson({'items': [
        {'id': 9, 'student': {'user_id': 5, 'name': 'Ali', 'avatar_url': null}, 'status': 'waitlisted', 'position': 1},
      ]});
      expect(roster.single.position, 1);
      expect(roster.single.studentId, 5);
      expect(roster.single.name, 'Ali');
    });

    test('filters → the query', () {
      const f = TeacherFilters(subject: 'fiqh', gender: 'male', priceMin: 50, priceMax: 120.5, minRating: 4, available: true, q: '  ali ');
      expect(f.toQuery(page: 2, size: 99), {
        'subject': 'fiqh',
        'gender': 'male',
        'price_min': '50',
        'price_max': '120.5',
        'min_rating': '4',
        'available': 'true',
        'q': 'ali',
        'page': 2,
        'size': 50,
      });
      expect(f.count, 6);
      expect(f.copyWith(subject: null).subject, isNull);
      expect(f.copyWith(q: 'x').gender, 'male');
    });
  });

  group('wizard validation', () {
    TeacherProfileDraft good() => TeacherProfileDraft(name: 'Fatima', gender: 'female', bio: 'x' * 30, subjects: ['quran']);

    test('profile step: name, gender, bio, years', () {
      expect(teacherStepError(TeacherStep.profile, good()), isNull);
      expect(teacherStepError(TeacherStep.profile, good()..name = ' '), isNotNull);
      expect(teacherStepError(TeacherStep.profile, good()..gender = null), contains('male'));
      expect(teacherStepError(TeacherStep.profile, good()..bio = 'short'), contains('20'));
      expect(teacherStepError(TeacherStep.profile, good()..yearsExperience = 71), contains('70'));
    });

    test('subjects and documents, then the first bad step', () {
      expect(teacherStepError(TeacherStep.subjects, good()..subjects = []), isNotNull);
      expect(teacherStepError(TeacherStep.documents, good()), isNotNull);
      expect(teacherStepError(TeacherStep.documents, good(), documents: 1), isNull);
      expect(teacherFirstBadStep(good()), TeacherStep.documents);
      expect(teacherFirstBadStep(good()..gender = null, documents: 1), TeacherStep.profile);
      expect(teacherFirstBadStep(good(), documents: 1), isNull);
      expect(teacherStepError(TeacherStep.review, good(), documents: 1), isNull);
    });

    test('a picked document: type and size', () {
      expect(teacherDocPickError('a.pdf', 1000), isNull);
      expect(teacherDocPickError('a.JPG', 1000), isNull);
      expect(teacherDocPickError('a.docx', 1000), isNotNull);
      expect(teacherDocPickError('a.pdf', kTeacherDocMaxBytes + 1), contains('10 MB'));
      expect(teacherDocPickError('a.pdf', 0), isNotNull);
    });

    test('the reject reason is required and at most 500', () {
      expect(teacherRejectReasonError('   '), isNotNull);
      expect(teacherRejectReasonError('Blurry photo'), isNull);
      expect(teacherRejectReasonError('x' * 501), contains('500'));
    });

    test('package defaults pass every step', () {
      final d = PackageDraft.defaults(subjects: ['nahw'], today: DateTime(2026, 11, 21))..title = 'Grammar basics';
      expect(d.subject, 'nahw');
      expect(d.startDate, DateTime(2026, 11, 28));
      expect(packageDraftErrors(d, today: DateTime(2026, 11, 21)), isEmpty);
    });

    test('package ranges', () {
      final today = DateTime(2026, 11, 21);
      PackageDraft d() => PackageDraft.defaults(subjects: ['quran'], today: today)..title = 'Juz Amma';
      expect(packageStepErrors(PackageStep.basics, d()..title = 'ab').keys, ['title']);
      expect(packageStepErrors(PackageStep.basics, d()..subject = null).keys, ['subject']);
      expect(packageStepErrors(PackageStep.basics, d()..delivery = 'offline').keys, ['location']);
      expect(packageStepErrors(PackageStep.basics, d()..delivery = 'both'..location = 'Cairo'), isEmpty);
      expect(packageStepErrors(PackageStep.schedule, d()..sessionsCount = 0, today: today).keys, ['sessions_count']);
      expect(packageStepErrors(PackageStep.schedule, d()..sessionsCount = 201, today: today).keys, ['sessions_count']);
      expect(packageStepErrors(PackageStep.schedule, d()..sessionMinutes = 14, today: today).keys, ['session_minutes']);
      expect(packageStepErrors(PackageStep.schedule, d()..sessionMinutes = 241, today: today).keys, ['session_minutes']);
      expect(packageStepErrors(PackageStep.schedule, d()..startDate = DateTime(2026, 11, 20), today: today).keys, ['start_date']);
      // a locked package keeps its past start date
      expect(packageStepErrors(PackageStep.schedule, d()..startDate = DateTime(2026, 11, 1), today: today, locked: true), isEmpty);
      expect(packageStepErrors(PackageStep.price, d()..maxStudents = 0).keys, ['max_students']);
      expect(packageStepErrors(PackageStep.price, d()..maxStudents = 501).keys, ['max_students']);
      expect(packageStepErrors(PackageStep.price, d()..discountPercent = 91).keys, ['discount_percent']);
      expect(packageStepErrors(PackageStep.price, d()..price = -1).keys, ['price']);
      expect(packageStepErrors(PackageStep.price, d()..overbook = 'allow'..overbookLimit = 0).keys, ['overbook_limit']);
      expect(packageStepErrors(PackageStep.price, d()..overbook = 'allow'), isEmpty); // blank = no limit
    });

    test('the draft body: location only in person, overbook_limit only with allow', () {
      final d = PackageDraft.defaults(subjects: ['quran'], today: DateTime(2026, 11, 21))
        ..title = ' T '
        ..location = 'Cairo'
        ..overbookLimit = 3;
      var j = d.toJson();
      expect((j['title'], j['location'], j['overbook_limit'], j['discount_percent'], j['start_date']), ('T', null, null, null, '2026-11-28'));
      d
        ..delivery = 'offline'
        ..overbook = 'allow'
        ..discountPercent = 20;
      j = d.toJson();
      expect((j['location'], j['overbook_limit'], j['discount_percent']), ('Cairo', 3, 20));
    });
  });

  group('join state (C3)', () {
    PackageJoinState s(Map<String, dynamic> j) => packageJoinState(TeacherPackage.fromJson(j));

    test('open seats: free → join, paid → pay', () {
      expect(s(packageJson(price: 0, discount: null)), PackageJoinState.join);
      expect(s(packageJson()), PackageJoinState.pay);
      expect(s(packageJson(price: 100, discount: 90)), PackageJoinState.pay);
    });

    test('full: none → full, waitlist → join the waiting list, allow → by the limit', () {
      expect(s(packageJson(seatsTaken: 10, overbook: 'none')), PackageJoinState.full);
      expect(s(packageJson(seatsTaken: 10, overbook: 'waitlist')), PackageJoinState.joinWaitlist);
      expect(s(packageJson(seatsTaken: 10, overbook: 'allow')), PackageJoinState.pay); // no limit
      expect(s(packageJson(seatsTaken: 11, overbook: 'allow', overbookLimit: 2)), PackageJoinState.pay);
      expect(s(packageJson(seatsTaken: 12, overbook: 'allow', overbookLimit: 2)), PackageJoinState.full);
    });

    test('my seat wins over the seats', () {
      expect(s(packageJson(seatsTaken: 10, overbook: 'none', mine: {'status': 'active'})), PackageJoinState.active);
      expect(s(packageJson(mine: {'status': 'waitlisted', 'position': 2})), PackageJoinState.waitlisted);
      expect(s(packageJson(mine: {'status': 'pending_payment', 'expires_at': '2026-11-21T10:30:00'})), PackageJoinState.pendingPayment);
      expect(s(packageJson(mine: {'status': 'offered'})), PackageJoinState.offered);
    });

    test('expired / cancelled may join again; paused / draft / closed may not', () {
      expect(s(packageJson(mine: {'status': 'expired'})), PackageJoinState.pay);
      expect(s(packageJson(mine: {'status': 'cancelled'}, price: 0, discount: null)), PackageJoinState.join);
      expect(s(packageJson(status: 'paused')), PackageJoinState.notOpen);
      expect(s(packageJson(status: 'draft')), PackageJoinState.notOpen);
      expect(s(packageJson(status: 'closed')), PackageJoinState.closed);
    });

    test('actionable, mine and the words', () {
      expect(packageJoinActionable(PackageJoinState.offered), isTrue);
      expect(packageJoinActionable(PackageJoinState.full), isFalse);
      expect(packageJoinMine(PackageJoinState.pendingPayment), isTrue);
      expect(packageJoinMine(PackageJoinState.join), isFalse);
      expect(packageJoinLabel(PackageJoinState.waitlisted, position: 3), contains('3'));
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final st in PackageJoinState.values) {
          expect(packageJoinLabel(st), isNotEmpty);
        }
      }
    });

    test('the hold countdown', () {
      final now = DateTime.utc(2026, 11, 21, 10);
      expect(packageHoldLeft(DateTime.utc(2026, 11, 21, 10, 12, 4), now: now), '12:04');
      expect(packageHoldLeft(DateTime.utc(2026, 11, 22, 9, 10), now: now), '23 h 10 min');
      expect(packageHoldLeft(DateTime.utc(2026, 11, 21, 9), now: now), isNull);
      expect(packageHoldLeft(null), isNull);
    });
  });

  group('calls over FakeApi', () {
    late FakeApi fake;
    final bodies = <String, Object?>{};
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      bodies.clear();
      fake = FakeApi({
        'GET /api/v1/me/teacher-profile': (_) => const FakeResponse(404, {'detail': {'code': 'no_profile', 'message': 'لا يوجد'}}),
        'POST /api/v1/packages/11/enroll': (o) => {'status': 'waitlisted', 'position': 4, 'checkout': null},
        'POST /api/v1/packages/12/enroll': (o) => const FakeResponse(409, {'detail': {'code': 'package_full', 'message': 'ممتلئة'}}),
        'GET /api/v1/admin/teachers': (o) {
          bodies['queue'] = o.queryParameters;
          return {'items': [profileJson(status: 'pending')], 'total': 1, 'page': 1};
        },
        'POST /api/v1/admin/teachers/7/reject': (o) {
          bodies['reject'] = o.data;
          return {'ok': true};
        },
      }, latency: const Duration(milliseconds: 1))
        ..install();
    });
    tearDown(() => fake.uninstall());

    test('no_profile → an empty profile', () async {
      final p = await TeachersApi().myProfile();
      expect(p.exists, isFalse);
    });

    test('enrol: waitlisted, and package_full mapped to text', () async {
      final r = await TeachersApi().enroll(11);
      expect((r.state, r.position), (PackageJoinState.waitlisted, 4));
      try {
        await TeachersApi().enroll(12);
        fail('should throw');
      } catch (e) {
        expect(teachersErrorCode(e), 'package_full');
        expect(teachersErrorText(e), 'This package is full');
        expect(e, isA<ApiException>());
      }
    });

    test('the queue query and the reject body', () async {
      final l = await TeachersApi().reviewQueue(status: 'pending', subject: 'fiqh');
      expect(l.items.single.pending, isTrue);
      expect(bodies['queue'], {'status': 'pending', 'subject': 'fiqh', 'page': 1});
      await TeachersApi().reject(7, '  Blurry  ');
      expect(bodies['reject'], isNotNull);
    });
  });

  group('QA fixes (D-1648 .. D-1659)', () {
    test('the schedule sentence, the first real day, the waiting list chip state', () {
      AppConfig.lang = 'en';
      final sched = {
        'freq': 'daily', 'interval': 1, 'weekdays': [], 'skip_weekdays': [4, 5], 'skip_dates': [], 'start_date': '2026-11-28',
        'end_date': null, 'count': 8, 'all_day': false, 'start_time': '10:00', 'end_time': '11:00', 'tz': 'Africa/Cairo',
      };
      expect(packageScheduleText(sched, 8), startsWith('Every day except Fri and Sat, '));
      expect(packageScheduleText(sched, 8), endsWith('for 8 sessions'));
      expect(packageScheduleText(null, 8), isNull);
      expect(packageFirstDay(sched, DateTime(2026, 11, 28)), DateTime(2026, 11, 29));
      expect(packageFirstDay(null, DateTime(2026, 11, 28)), DateTime(2026, 11, 28));
      final full = TeacherPackage.fromJson({'id': 1, 'status': 'published', 'max_students': 1, 'seats_taken': 1, 'overbook': 'waitlist'});
      expect(packageJoinState(full), PackageJoinState.joinWaitlist);
    });

    test('next opening as a day, avatar letters, user text direction, joins', () {
      expect(TeacherProfile.fromJson({'user_id': 1, 'next_free': '2026-11-28T00:00:00', 'next_free_kind': 'day'}).nextFreeIsDay, isTrue);
      expect(TeacherProfile.fromJson({'user_id': 1, 'next_free': '2026-11-29T08:00:00', 'next_free_kind': 'session'}).nextFreeIsDay, isFalse);
      expect(teacherInitialName('الأستاذة منى'), 'منى');
      expect(teacherInitialName('الشيخ محمود (تجريبي)'), 'محمود');
      expect(teacherInitialName('Mona Ali'), 'Mona');
      expect(teacherInitialName(''), '?');
      expect(userTextDirection('الشيخ محمود (تجريبي)'), TextDirection.rtl);
      expect(userTextDirection('  (12) Mona'), TextDirection.ltr);
      expect(userTextDirection('123'), isNull);
      AppConfig.lang = 'en';
      expect(teachersJoin(['Arabic', 'English']), 'Arabic, English');
      AppConfig.lang = 'ar';
      expect(teachersJoin(['العربية', 'الإنجليزية']), 'العربية، الإنجليزية');
      expect(teacherG('female', 'عن المعلم', 'عن المعلمة', 'About'), 'عن المعلمة');
      expect(seatsTakenText(1, 1), '1 من مقعد واحد');
      AppConfig.lang = 'en';
      expect(seatsTakenText(1, 1), '1 of 1 seat');
    });
  });
}
