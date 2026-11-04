// D-170: the browser's history follows the app's pages. [planHistory] is the whole decision (pure); the registry gives
// each page its URL and its stable id.
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/core/routing/web_history.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HistoryEntry e(int serial, String location) => HistoryEntry(serial, location);
  const g = HistoryEntry(0, '/dashboard');

  group('planHistory', () {
    test('a new page is pushed; nothing to do when in step', () {
      expect(planHistory([g, e(1, '/dashboard')], [g, e(1, '/dashboard'), e(2, '/dashboard')]),
          [HistoryPush(e(2, '/dashboard'))]);
      expect(planHistory([g, e(1, '/dashboard')], [g, e(1, '/dashboard')]), isEmpty);
    });

    test('pages closed in the app take the browser back over their entries', () {
      expect(planHistory([g, e(1, '/dashboard'), e(2, '/calendar'), e(3, '/calendar')], [g, e(1, '/dashboard')]),
          [const HistoryGo(-2)]);
    });

    test('a page replaced by another: back over it, then the new one', () {
      expect(planHistory([g, e(1, '/dashboard'), e(2, '/inbox')], [g, e(1, '/dashboard'), e(3, '/calendar')]),
          [const HistoryGo(-1), HistoryPush(e(3, '/calendar'))]);
    });

    test('a tab switch rewrites the top entry in place', () {
      expect(planHistory([g, e(1, '/dashboard')], [g, e(1, '/dashboard/my-courses')]),
          [HistoryReplace(e(1, '/dashboard/my-courses'))]);
    });

    test('a tab switch under open tab pages: back to the home entry, rewrite it, then the new tab\'s pages', () {
      expect(planHistory([g, e(1, '/dashboard'), e(2, '/dashboard')], [g, e(1, '/dashboard/my-courses'), e(5, '/dashboard/my-courses')]),
          [const HistoryGo(-1), HistoryReplace(e(1, '/dashboard/my-courses')), HistoryPush(e(5, '/dashboard/my-courses'))]);
    });

    test('sign-in → home: every entry above the guard goes, the guard gets the home URL', () {
      expect(planHistory([const HistoryEntry(0, '/login'), e(1, '/login'), e(2, '/register')],
          [const HistoryEntry(0, '/teacher_dashboard'), e(3, '/teacher_dashboard')]),
          [const HistoryGo(-2), const HistoryReplace(HistoryEntry(0, '/teacher_dashboard')), HistoryPush(e(3, '/teacher_dashboard'))]);
    });
  });

  group('AppRoutes', () {
    test('ids are unique and every pattern is a path', () {
      final ids = AppRoutes.all.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final r in AppRoutes.all) {
        expect(r.path, startsWith('/'), reason: r.id);
        expect(AppRoutes.byId(r.id), same(r));
      }
    });

    test('match: path parameters, aliases, the query; no match for other shapes', () {
      final m = AppRoutes.match('/courses/12?tab=lessons')!;
      expect(m.id, 'course');
      expect(m.intParam('courseId'), 12);
      expect(m.query, {'tab': 'lessons'});
      expect(AppRoutes.match('/course-profile/7')!.intParam('courseId'), 7, reason: 'an alias');
      expect(AppRoutes.match('/@ahmed')!.params, {'username': 'ahmed'});
      expect(AppRoutes.match('/org/5')!.id, 'org.member');
      expect(AppRoutes.match('/courses'), isNull);
      expect(AppRoutes.match('/courses/12/extra'), isNull);
      expect(AppRoutes.match('/@'), isNull);
      expect(AppRoutes.match(null), isNull);
    });

    test('location: built from the id; a typo or a missing parameter throws', () {
      expect(AppRoutes.location('course', {'courseId': 12}), '/courses/12');
      expect(AppRoutes.location('link.profile', {'username': 'ahmed'}), '/@ahmed');
      expect(AppRoutes.location('inbox', const {}, {'tab': 'notifications'}), '/inbox?tab=notifications');
      expect(() => AppRoutes.location('nope'), throwsArgumentError);
      expect(() => AppRoutes.location('course'), throwsArgumentError);
    });

    test('locationOf: the URL a pushed route shows', () {
      expect(AppRoutes.locationOf('/course-profile', 12), '/courses/12');
      expect(AppRoutes.locationOf('/org_member', 5), '/org/5');
      expect(AppRoutes.locationOf('/calendar', {'org_id': 3}), '/calendar');
      expect(AppRoutes.locationOf('/course-detail', Object()), isNull, reason: 'an object without a known course id');
      expect(AppRoutes.locationOf('/course-detail', 7), '/courses/7');
      final was = AppRoutes.courseIdOf;
      AppRoutes.courseIdOf = (a) => a is String ? int.tryParse(a) : null;
      expect(AppRoutes.locationOf('/course-detail', '9'), '/courses/9', reason: 'the course object gives its id');
      expect(AppRoutes.locationOf('/course-detail', 'x'), isNull);
      AppRoutes.courseIdOf = was;
      expect(AppRoutes.locationOf(null, null), isNull, reason: 'a MaterialPageRoute keeps the URL under it');
    });

    test('home tabs: `<home>/<tab>` both ways, only for the role homes', () {
      expect(AppRoutes.tabLocation('/dashboard', 'my_courses'), '/dashboard/my-courses');
      expect(AppRoutes.splitTab('/dashboard/my-courses'), (home: '/dashboard', tab: 'my_courses'));
      expect(AppRoutes.splitTab('/courses/12'), isNull);
      expect(AppRoutes.splitTab('/dashboard'), isNull);
    });
  });

  group('URL entry (D-170)', () {
    bool link(String r) => r.startsWith('/c/');

    test('registry pages open over the home when signed in; a home tab names the tab', () {
      expect(resolveWebEntry('/courses/12', signedIn: true, home: '/dashboard', isLink: link),
          (route: '/courses/12', overHome: true));
      expect(resolveWebEntry('/org/5', signedIn: true, home: '/dashboard', isLink: link), (route: '/org/5', overHome: true));
      expect(resolveWebEntry('/dashboard/my-courses', signedIn: true, home: '/dashboard', isLink: link), isNull);
      expect(webEntryTab('/dashboard/my-courses'), 'my_courses');
    });

    test('signed out: the login, and the page comes back after it', () {
      expect(resolveWebEntry('/courses/12', signedIn: false, home: '/dashboard', isLink: link), isNull);
      expect(needsSignInFirst('/courses/12'), isTrue);
      expect(needsSignInFirst('/calendar'), isTrue);
      expect(needsSignInFirst('/teacher_dashboard/my-courses'), isTrue);
      expect(needsSignInFirst('/login'), isFalse);
      expect(needsSignInFirst('/nope'), isFalse);
    });

    test('SignInReturn opens the page once', () {
      final opened = <String>[];
      SignInReturn.opener = (l) async {
        opened.add(l);
        return true;
      };
      SignInReturn.pending = '/courses/12';
      SignInReturn.consume();
      SignInReturn.consume();
      expect(opened, ['/courses/12']);
      SignInReturn.opener = null;
    });
  });
}
