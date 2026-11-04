import 'package:flutter_education_app/features/onboarding/landing_api.dart';
import 'package:flutter_education_app/features/onboarding/start_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? start({bool auth = false, bool web = false, bool seen = false, bool link = false}) =>
      decideSignedOutStart(isAuthenticated: auth, isWeb: web, onboardingSeen: seen, hasEntryLink: link);

  test('signed in keeps the usual home', () {
    expect(start(auth: true), isNull);
    expect(start(auth: true, web: true, seen: true), isNull);
  });

  test('app: onboarding first, then the guest search', () {
    expect(start(), '/onboarding');
    expect(start(seen: true), '/guest-search');
  });

  test('web: the login (the website did the pitch)', () {
    expect(start(web: true), '/login');
    expect(start(web: true, seen: true), '/login');
  });

  test('an entry link is left to the router', () {
    expect(start(link: true), isNull);
    expect(start(web: true, link: true), isNull);
  });

  test('explore URL parsing', () {
    final r = ExploreRequest.parse('/explore?subject=3&level=9&mode=online&lang=en');
    expect((r.subject, r.level, r.mode, r.lang, r.categoryId), (3, 9, 'online', 'en', 9));
    final s = ExploreRequest.parse('/explore?subject=3&mode=bogus&lang=fr');
    expect((s.subject, s.level, s.mode, s.lang, s.categoryId), (3, null, 'any', null, 3));
    expect(ExploreRequest.parse('/explore').categoryId, isNull);
    expect(ExploreRequest.matches('/explore?x=1'), isTrue);
    expect(ExploreRequest.matches('/exploreme'), isFalse);
  });

  test('institution and register-role routes', () {
    expect(isInstitutionRoute('/start/institution'), isTrue);
    expect(isInstitutionRoute('/start/institution?lang=ar'), isTrue);
    expect(isInstitutionRoute('/start'), isFalse);
    expect(registerRoleFromRoute('/register?role=teacher'), 'teacher');
    expect(registerRoleFromRoute('/register?role=admin'), isNull);
    expect(registerRoleFromRoute('/register'), isNull);
  });

  test('landing payloads fail soft', () {
    expect(parseLandingOptions(null), isEmpty);
    expect(parseLandingOptions({'subjects': 'x'}), isEmpty);
    final o = parseLandingOptions({
      'subjects': [
        {
          'id': 1, 'name_ar': 'رياضيات', 'name_en': 'Math', 'courses': 4,
          'levels': [
            {'id': 2, 'name_ar': 'ثالث', 'name_en': 'Grade 3', 'courses': 2}
          ]
        }
      ]
    });
    expect(o.single.levels.single.id, 2);
    expect(parseLandingCount({'courses': 5, 'teachers': 2})?.courses, 5);
    expect(parseLandingCount({'x': 1}), isNull);
  });
}
