// M20: a browser URL opened directly (or refreshed) starts the web app on that page when the person may open it.
import 'package:flutter_education_app/utils/web_entry_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool link(String r) => r.startsWith('/c/') || r.startsWith('/live/') || r.startsWith('/@');

  test('the URL route: path and query, nothing for the root', () {
    expect(webEntryRouteFromUri(Uri.parse('https://nextbrain.site/')), isNull);
    expect(webEntryRouteFromUri(Uri.parse('https://nextbrain.site')), isNull);
    expect(webEntryRouteFromUri(Uri.parse('https://nextbrain.site/notifications')), '/notifications');
    expect(webEntryRouteFromUri(Uri.parse('https://nextbrain.site/c/12?ref=5')), '/c/12?ref=5');
  });

  test('signed in: argument-free pages open over the home; dashboards and unknown routes go home', () {
    ({String route, bool overHome})? r(String e) => resolveWebEntry(e, signedIn: true, home: '/dashboard', isLink: link);
    expect(r('/notifications'), (route: '/notifications', overHome: true));
    expect(r('/profile'), (route: '/profile', overHome: true));
    expect(r('/dashboard'), isNull, reason: 'already the home');
    expect(r('/admin_dashboard'), isNull, reason: "never another role's home");
    expect(r('/login'), isNull, reason: 'signed in: the home');
    expect(r('/course-detail'), isNull, reason: 'needs arguments');
    expect(r('/nope'), isNull);
    expect(r('/c/12?ref=5'), (route: '/c/12?ref=5', overHome: false), reason: 'share links resolve themselves');
    expect(resolveWebEntry(null, signedIn: true, home: '/dashboard', isLink: link), isNull);
  });

  test('signed out: sign-in pages and share links; a page that needs an account → the login', () {
    ({String route, bool overHome})? r(String e) => resolveWebEntry(e, signedIn: false, home: '/dashboard', isLink: link);
    expect(r('/register'), (route: '/register', overHome: false));
    expect(r('/forgot-password'), (route: '/forgot-password', overHome: false));
    expect(r('/notifications'), isNull);
    expect(r('/live/abc'), (route: '/live/abc', overHome: false));
  });
}
