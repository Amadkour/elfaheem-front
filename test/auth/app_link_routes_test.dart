// F13: every App Link prefix the Android manifest claims (android/app/src/main/AndroidManifest.xml, the
// `android:pathPrefix` entries) reaches a route case in main.dart's `_router`: the parser that case asks answers a
// sample link of that prefix. A prefix added to the manifest without a case here fails, so a link the phone hands
// to the app can never fall through to the 404 page.
import 'dart:io';

import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart' show exportLinkTokenFromRoute;
import 'package:flutter_education_app/features/certificates/issue/cert_issue_logic.dart' show certVerifyTokenFromRoute;
import 'package:flutter_education_app/features/games/learner/challenges.dart' show challengeCodeFromRoute;
import 'package:flutter_education_app/features/guest/guest_live_api.dart' show guestLiveTokenFromRoute;
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Manifest prefix → (a sample route the app is handed, does `_router`'s case for it take it).
final _cases = <String, (String, bool Function(String))>{
  '/c/': ('/c/12?ref=5', (r) => DeepLinkService.parse(r)?.courseId == 12),
  '/live/': ('/live/tok-123', (r) => guestLiveTokenFromRoute(r) == 'tok-123'),
  '/@': ('/@ahmed', (r) => DeepLinkService.parseProfile(r)?.username == 'ahmed'),
  '/verify/': ('/verify/ABC123', (r) => certVerifyTokenFromRoute(r) == 'ABC123'),
  '/e/': ('/e/abcDEF123_-xyz', (r) => exportLinkTokenFromRoute(r) == 'abcDEF123_-xyz'),
  '/j/': ('/j/JOIN42', (r) => AppRoutes.match(r)?.id == 'link.org_join'),
  '/i/': ('/i/inv-token-1', (r) => AppRoutes.match(r)?.id == 'link.org_invitation'),
  '/onboard/': ('/onboard/AB12CD', (r) => AppRoutes.match(r)?.id == 'link.onboard' && AppRoutes.match(r)?.params['code'] == 'AB12CD'),
  '/s/': ('/s/meeting/7', (r) => AppLink.parse(r) == const AppLink.meeting(7)),
  '/app/live/': ('/app/live/tok-123', (r) => guestLiveTokenFromRoute(r) == 'tok-123'),
  '/app/games/challenge/': ('/app/games/challenge/ABC123', (r) => challengeCodeFromRoute(r) == 'ABC123'),
  '/app/games/c/': ('/app/games/c/ABC123', (r) => challengeCodeFromRoute(r) == 'ABC123'),
  '/app/s/': ('/app/s/meeting/7', (r) => AppLink.parse(r) == const AppLink.meeting(7)),
};

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final prefixes = RegExp(r'android:pathPrefix="([^"]+)"').allMatches(manifest).map((m) => m.group(1)!).toSet();

  test('the manifest claims the App Link prefixes this test knows', () {
    expect(prefixes, isNotEmpty);
    expect(prefixes.difference(_cases.keys.toSet()), isEmpty,
        reason: 'a new manifest prefix needs a route case in main.dart _router and an entry in _cases');
  });

  for (final p in _cases.keys) {
    test('$p has a route case', () {
      final (sample, handled) = _cases[p]!;
      expect(sample.startsWith(p), isTrue, reason: sample);
      expect(handled(sample), isTrue, reason: sample);
    });
  }

  test('the cases do not claim each other\'s links', () {
    // (a course link /c/ also parses as an AppLink; _router asks DeepLinkService.parse first)
    expect(DeepLinkService.parse('/@ahmed'), isNull);
    expect(guestLiveTokenFromRoute('/s/meeting/7'), isNull);
    expect(exportLinkTokenFromRoute('/verify/ABC123'), isNull);
  });
}
