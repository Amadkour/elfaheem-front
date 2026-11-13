// Guest share links open straight to the video or the meeting (D-840 – D-844): the links route to the guest pages
// with no session (`/s/video/v_…`, `/s/record/g_…`, `/live/<token>`, each also under the web app's `/app/`), the web
// start honours them signed out, the guest page calls ONLY public routes (auth: false, no Authorization header even
// with a stale session in storage), holds the login redirect off while open, keeps the screen protected, and shows
// the soft sign-up card to a signed-out guest.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/guest_link_visit.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/shared/records/record_guest_page.dart';
import 'package:flutter_education_app/features/shared/records/records_guests_api.dart';
import 'package:flutter_education_app/features/shared/session/material/material_guest_links_api.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart' show layoutHost;

const _video = 'v_AbCdEfGhIjKlMnOpQrStUvWxYz012345';

/// What main.dart's router opens for a route — the same tests, in the same order (`_router`).
String? guestPageFor(String route) {
  if (guestLiveTokenFromRoute(route) != null) return 'GuestLivePage';
  final l = AppLink.parse(route);
  if (l != null && l.kind == AppLinkKind.record && isGuestRecordToken(l.token)) return 'GuestRecordPage(record)';
  if (l != null && l.kind == AppLinkKind.video) return 'GuestRecordPage(video)';
  return null;
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    GuestLinkVisit.reset();
  });

  group('routes', () {
    test('every guest link resolves to its guest page, root form and under /app/', () {
      for (final (route, page) in [
        ('/s/video/$_video', 'GuestRecordPage(video)'),
        ('/app/s/video/$_video', 'GuestRecordPage(video)'),
        ('/s/record/g_abcdefghijklmnop', 'GuestRecordPage(record)'),
        ('/app/s/record/g_abcdefghijklmnop', 'GuestRecordPage(record)'),
        ('/live/tok123', 'GuestLivePage'),
        ('/app/live/tok123', 'GuestLivePage'),
      ]) {
        expect(guestPageFor(route), page, reason: route);
      }
      expect(guestLiveTokenFromRoute('/app/live/tok123'), 'tok123');
      expect(guestLiveTokenFromRoute('/x/live/tok123'), isNull);
      // a material id is never a video link, nor is a token without its kind marker
      expect(AppLink.parse('/s/video/123'), isNull);
      expect(AppLink.parse('/s/video/g_abcdefghijklmnop'), isNull);
      expect(AppLink.parse('/s/video/v_short'), isNull);
      expect(const AppLink.video(_video).route, '/s/video/$_video');
      expect(AppLink.parse(const AppLink.video(_video).url()), const AppLink.video(_video));
    });

    test('the web start opens a guest link signed out, straight (no login first, no home under it)', () {
      bool isLink(String r) => guestPageFor(r) != null;
      for (final entry in ['/s/video/$_video', '/s/record/g_abcdefghijklmnop', '/live/tok123']) {
        final e = resolveWebEntry(entry, signedIn: false, home: '/login', isLink: isLink);
        expect(e?.route, entry);
        expect(e?.overHome, isFalse);
        expect(needsSignInFirst(entry), isFalse, reason: entry);
      }
      // the browser URL under the web app's folder
      expect(webEntryRouteFromUri(Uri.parse('https://nextbrain.site/app/s/video/$_video'), basePath: '/app/'), '/s/video/$_video');
    });
  });

  group('parsing', () {
    test("a course video's card and a record's open link", () {
      final c = GuestRecordCard.fromJson({
        'title': 'Lesson',
        'subtitle': 'فيزياء',
        'subtitle_en': 'Physics',
        'owner': {'name': 'T'},
        'personal': false,
        'kind': 'video',
      });
      expect((c.subtitle, c.personal, c.video), ('Physics', false, true));
      final r = GuestRecordCard.fromJson({'title': 'Rec'});
      expect((r.personal, r.video), (true, false)); // an older server: a personal recording link
      final g = recordGuestsFrom({
        'guests': [
          {'id': 1, 'kind': 'link', 'email': null, 'token': 'g_x1234567890', 'link': 'https://x/s/record/g_x1234567890'},
          {'id': 2, 'kind': 'email', 'email': 'a@b.co', 'token': 'g_y1234567890'},
        ]
      });
      expect([for (final x in g) (x.id, x.openLink)], [(1, true), (2, false)]);
      final l = MaterialGuestLinks.fromJson({
        'links': [
          {'id': 3, 'token': _video, 'link': 'https://nextbrain.site/s/video/$_video', 'expires_at': null, 'views': 2},
        ],
        'created': {'id': 3, 'token': _video, 'link': 'https://nextbrain.site/s/video/$_video'},
      });
      expect((l.links.single.views, l.created?.id, l.enabled), (2, 3, true));
      expect(guestRecordErrorText(const ApiException(message: 'x', statusCode: 404, code: 'link_not_found')), contains('not available'));
    });

    test('the login redirect is held off while a guest page is open', () {
      final a = Object(), b = Object();
      expect(GuestLinkVisit.active, isFalse);
      GuestLinkVisit.enter(a);
      GuestLinkVisit.enter(b);
      GuestLinkVisit.leave(a);
      expect(GuestLinkVisit.active, isTrue);
      GuestLinkVisit.leave(b);
      expect(GuestLinkVisit.active, isFalse);
    });
  });

  group('the guest page, no session', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins(accessToken: 'a-stale-token-left-in-this-browser');
    });

    testWidgets('a course video link: only public calls, no Authorization, protected, the card + sign-up', (t) async {
      final calls = <(String, Object?, Object?)>[];
      FakeHandler rec(Object? body) => (o) {
            calls.add(('${o.method} ${o.path}', o.extra['auth'], o.headers['Authorization']));
            return body;
          };
      final fake = FakeApi({
        'GET /api/v1/public/videos/$_video': rec({
          'title': "Newton's laws",
          'subtitle': 'Physics',
          'owner': {'name': 'Course Teacher'},
          'duration_seconds': 95,
          'personal': false,
          'kind': 'video',
        }),
      }, latency: const Duration(milliseconds: 1), fallback: (o) {
        calls.add(('${o.method} ${o.path}', o.extra['auth'], o.headers['Authorization']));
        return const FakeResponse(401, {'detail': 'Not authenticated'});
      })
        ..install();
      addTearDown(fake.uninstall);
      final protectCalls = <String>[];
      ScreenSecurity.instance.debugPlatform = (call, _) async => protectCalls.add(call);
      addTearDown(() => ScreenSecurity.instance.debugPlatform = null);

      await t.pumpWidget(layoutHost(const GuestRecordPage(token: _video, kind: GuestMediaKind.video), scale: 1));
      expect(GuestLinkVisit.active, isTrue);
      expect(ScreenSecurity.instance.isProtected, isTrue);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(find.text("Newton's laws"), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      expect(find.byKey(const ValueKey('guest_link.cta')), findsOneWidget);
      expect(calls, isNotEmpty);
      for (final c in calls) {
        expect(c.$1, startsWith('GET /api/v1/public/'), reason: 'an authenticated call: ${c.$1}');
        expect((c.$2, c.$3), (false, null), reason: c.$1);
      }
      await t.pumpWidget(const SizedBox());
      expect((GuestLinkVisit.active, ScreenSecurity.instance.isProtected), (false, false));
    });

    testWidgets('a revoked / unknown link: one calm "not available", no sign-in wall', (t) async {
      final fake = FakeApi({}, latency: const Duration(milliseconds: 1), fallback: (o) => const FakeResponse(404, {
            'detail': {'code': 'link_not_found', 'message': 'x'}
          }))
        ..install();
      addTearDown(fake.uninstall);
      ScreenSecurity.instance.debugPlatform = (_, _) async {};
      addTearDown(() => ScreenSecurity.instance.debugPlatform = null);
      await t.pumpWidget(layoutHost(const GuestRecordPage(token: _video, kind: GuestMediaKind.video, signedIn: true), scale: 1));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Link not available'), findsOneWidget);
      expect(find.byKey(const ValueKey('guest_link.cta')), findsNothing); // signed in: no card
      expect(fake.calls.every((c) => c.path.startsWith('/api/v1/public/videos/')), isTrue);
      await t.pumpWidget(const SizedBox());
    });
  });
}
