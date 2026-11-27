// Guest links for live sessions at 320x640 and 1400x900, ar + en, textScaler 1.3:
//   • GuestLinkBody (teacher sheet body): no link yet (create form) · link present (facts, actions, QR, settings panel
//     with the PIN option) · PIN set (lock chip) · guests joined list (5 rows / empty / loading / error) · loading · error.
//   • GuestLiveContent (public /live/<token> page): loading skeleton · not started (waiting) · live · PIN required
//     (clean and refused) · recording consent unchecked / checked · rate limited · error (final and retryable).
// Plus the pure route helpers that resolve `/live/<token>` from a route name / browser URL, hash and path forms.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/features/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/guest/guest_live_page.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomKind;
import 'package:flutter_education_app/features/sessions/teacher/components/guest_link_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _link = GuestLink(
  url: 'https://alfheemacademy.com/live/3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e7d8f9a0b1c2d3e4f',
  token: '3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e7d8f9a0b1c2d3e4f',
  canPublish: true,
  maxGuests: 25,
  guestsJoined: 7,
  createdAt: null,
);

const _pinLink = GuestLink(
  url: 'https://alfheemacademy.com/live/abc',
  token: 'abc',
  canPublish: false,
  maxGuests: null,
  guestsJoined: 0,
  hasPin: true,
);

final _joins = List.generate(
  5,
  (i) => GuestJoinRecord(
    identity: 'guest-$i',
    name: i.isEven ? 'Mohamed Abdelrahman El-Sayed (a rather long visitor name)' : 'سارة محمود',
    joinedAt: DateTime.utc(2026, 10, 24, 9, 30 + i),
    ipMasked: i == 4 ? null : '41.33.$i.xx',
  ),
);

Widget _linkBody({
  bool loading = false,
  bool busy = false,
  String? error,
  GuestLink? link,
  bool canPublish = false,
  bool editing = false,
  bool showQr = false,
  bool joinsOpen = false,
  bool joinsLoading = false,
  String? joinsError,
  List<GuestJoinRecord> joins = const [],
  int joinsTotal = 0,
  TextEditingController? max,
  TextEditingController? pin,
}) =>
    GuestLinkBody(
      loading: loading,
      busy: busy,
      error: error,
      link: link,
      canPublish: canPublish,
      maxGuestsController: max ?? TextEditingController(text: '25'),
      pinController: pin ?? TextEditingController(),
      editing: editing,
      showQr: showQr,
      joinsOpen: joinsOpen,
      joinsLoading: joinsLoading,
      joinsError: joinsError,
      joins: joins,
      joinsTotal: joinsTotal,
      onRetry: () {},
      onCanPublishChanged: (_) {},
      onCreate: () {},
      onCopy: () {},
      onShare: () {},
      onToggleQr: () {},
      onToggleSettings: () {},
      onSaveSettings: () {},
      onRemovePin: () {},
      onRotate: () {},
      onRevoke: () {},
      onToggleJoins: () {},
      onRefreshJoins: () {},
    );

const _info = GuestLiveInfo(
  sessionId: 42,
  sessionName: 'Advanced Algorithms — week 7: dynamic programming over trees (a long session name to wrap)',
  courseName: 'خوارزميات متقدمة — الفصل الدراسي الثاني',
  teacherName: 'Dr. Ahmed Hamdy Madkour',
  isLive: true,
  canPublish: false,
  recordingEnabled: true,
  maxGuests: 10,
);

Widget _page({
  bool loading = false,
  GuestLiveInfo? info,
  String? error,
  bool errorFinal = false,
  bool joining = false,
  bool pinError = false,
  bool consent = true,
  int rateLimitSeconds = 0,
  TextEditingController? name,
  TextEditingController? pin,
}) =>
    GuestLiveContent(
      loading: loading,
      info: info,
      error: error,
      errorFinal: errorFinal,
      joining: joining,
      nameController: name ?? TextEditingController(text: 'أحمد حمدي'),
      pinController: pin,
      pinError: pinError,
      consent: consent,
      rateLimitSeconds: rateLimitSeconds,
      onPinChanged: (_) {},
      onConsentChanged: (_) {},
      onJoin: () {},
      onRetry: () {},
    );

GuestLiveInfo _copy(GuestLiveInfo i,
        {bool? isLive, bool? canPublish, bool? recording, bool? full, int? max, bool clearMax = false, bool? requiresPin}) =>
    GuestLiveInfo(
      sessionId: i.sessionId,
      sessionName: i.sessionName,
      courseName: i.courseName,
      teacherName: i.teacherName,
      isLive: isLive ?? i.isLive,
      canPublish: canPublish ?? i.canPublish,
      recordingEnabled: recording ?? i.recordingEnabled,
      maxGuests: clearMax ? null : (max ?? i.maxGuests),
      full: full ?? i.full,
      requiresPin: requiresPin ?? i.requiresPin,
    );

// The join button is AppPrimaryButton, an AppButton since the editorial kit; a busy button takes no tap.
({VoidCallback? onPressed}) _joinButton(WidgetTester t) {
  final b = t.widget<AppButton>(
      find.descendant(of: find.byKey(const ValueKey('guest_live.join')), matching: find.byType(AppButton)));
  return (onPressed: b.busy ? null : b.onPressed);
}

void main() {
  group('GuestLinkBody', () {
    testWidgets('no link yet: options (mode, cap, PIN) + create button', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: null),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.create')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.can_publish')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.pin')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.pin_remove')), findsNothing);
        },
      );
    });

    testWidgets('link present: url box, facts and every action', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: _link),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.present')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.url')), findsOneWidget);
          for (final k in ['copy', 'share', 'qr', 'settings', 'joins', 'rotate', 'revoke']) {
            expect(find.byKey(ValueKey('guest_link.$k')), findsOneWidget, reason: k);
          }
          expect(find.byKey(const ValueKey('guest_link.qr_image')), findsNothing);
          expect(find.byKey(const ValueKey('guest_link.pin_chip')), findsNothing);
          expect(find.byKey(const ValueKey('guest_link.joins_panel')), findsNothing);
        },
      );
    });

    testWidgets('link present with QR and the settings panel open, no limit, busy', (tester) async {
      const noLimit = GuestLink(url: 'https://alfheemacademy.com/live/abc', token: 'abc', canPublish: false, maxGuests: null, guestsJoined: 0);
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: noLimit, showQr: true, editing: true, busy: true, max: TextEditingController()),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.qr_image')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.settings_panel')), findsOneWidget);
        },
      );
    });

    testWidgets('PIN set: lock chip on the url box, "Remove PIN" in the settings panel', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: _pinLink),
        act: (t) async => expect(find.byKey(const ValueKey('guest_link.pin_chip')), findsOneWidget),
      );
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: _pinLink, editing: true, pin: TextEditingController(text: '12345678')),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.settings_panel')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.pin_remove')), findsOneWidget);
        },
      );
    });

    testWidgets('guests joined: 5 rows, more on the server, empty, loading, error', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: _link, joinsOpen: true, joins: _joins, joinsTotal: 12),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.joins_panel')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.joins_refresh')), findsOneWidget);
          expect(find.text('41.33.0.xx'), findsOneWidget);
        },
      );
      await expectNoLayoutErrors(tester, () => _linkBody(link: _link, joinsOpen: true));
      await expectNoLayoutErrors(tester, () => _linkBody(link: _link, joinsOpen: true, joinsLoading: true));
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: _link, joinsOpen: true, joinsError: 'The server could not be reached, a long message that wraps.'),
      );
    });

    testWidgets('loading skeleton and error banner', (tester) async {
      await expectNoLayoutErrors(tester, () => _linkBody(loading: true));
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(error: 'The server could not be reached. A rather long error message that must wrap on a phone.'),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.error')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.retry')), findsOneWidget);
        },
      );
    });
  });

  group('GuestLiveContent', () {
    testWidgets('loading skeleton', (tester) async {
      await expectNoLayoutErrors(tester, () => _page(loading: true));
    });

    testWidgets('not started: waiting banner, join disabled', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, isLive: false)),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.waiting')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.waiting_banner')), findsOneWidget);
          expect(_joinButton(t).onPressed, isNull);
        },
      );
    });

    testWidgets('live: recording note, name field, consent ticked, join enabled', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _info),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.live')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.recorded')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.consent')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.pin')), findsNothing);
          expect(_joinButton(t).onPressed, isNotNull);
        },
      );
    });

    testWidgets('recording consent: unchecked keeps Join disabled; no consent row without recording', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _info, consent: false),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.consent')), findsOneWidget);
          expect(_joinButton(t).onPressed, isNull);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, recording: false), consent: false),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.consent')), findsNothing);
          expect(_joinButton(t).onPressed, isNotNull);
        },
      );
    });

    testWidgets('PIN required: field shown; refused PIN shows the inline error', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, requiresPin: true), pin: TextEditingController(text: '1234')),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.pin')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.pin_error')), findsNothing);
          expect(_joinButton(t).onPressed, isNotNull);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, requiresPin: true), pinError: true),
        act: (t) async => expect(find.byKey(const ValueKey('guest_live.pin_error')), findsOneWidget),
      );
    });

    testWidgets('rate limited: countdown banner, Join disabled (card and error states)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, requiresPin: true), rateLimitSeconds: 47),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.rate_limited')), findsOneWidget);
          expect(_joinButton(t).onPressed, isNull);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => _page(error: 'Too many attempts.', rateLimitSeconds: 60),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.rate_limited')), findsOneWidget);
          final retry = t.widget<AppButton>(find.descendant(
              of: find.byKey(const ValueKey('guest_live.retry')), matching: find.byType(AppButton)));
          expect(retry.onPressed, isNull);
        },
      );
    });

    testWidgets('live, mic allowed, no recording, no limit, joining; and full', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, canPublish: true, recording: false, clearMax: true), joining: true, name: TextEditingController()),
      );
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _copy(_info, full: true)),
        act: (t) async => expect(find.byKey(const ValueKey('guest_live.full')), findsOneWidget),
      );
    });

    testWidgets('live with a failed poll keeps the card and shows the transient note', (tester) async {
      await expectNoLayoutErrors(tester, () => _page(info: _info, error: 'Network error'));
    });

    testWidgets('error: final (no retry) and retryable', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(error: 'This link is not valid any more.', errorFinal: true),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.error')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.retry')), findsNothing);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => _page(error: 'The server could not be reached.'),
        act: (t) async => expect(find.byKey(const ValueKey('guest_live.retry')), findsOneWidget),
      );
    });

    testWidgets('back from the room: the sign-up card alone; signed out: "Join with your account" (S-A2)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => GuestLiveContent(
          loading: false,
          info: _info,
          error: null,
          joining: false,
          nameController: TextEditingController(),
          onJoin: () {},
          onRetry: () {},
          afterRoom: GuestLiveAfterCard(kind: LiveRoomKind.meeting, onRegister: () {}, onSignIn: () {}, onLater: () {}),
        ),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.after')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.live')), findsNothing);
        },
      );
      await expectNoLayoutErrors(
        tester,
        () => GuestLiveContent(
          loading: false,
          info: _info,
          error: null,
          joining: false,
          nameController: TextEditingController(),
          onJoin: () {},
          onRetry: () {},
          onSignIn: () {},
        ),
        act: (t) async => expect(find.byKey(const ValueKey('guest_live.sign_in')), findsOneWidget),
      );
    });
  });

  group('models', () {
    test('GuestLink / GuestLiveInfo read the PIN flags, joins page parses', () {
      expect(GuestLink.fromJson({'url': 'u', 'token': 't', 'has_pin': true}).hasPin, isTrue);
      expect(GuestLink.fromJson({'url': 'u', 'token': 't'}).hasPin, isFalse);
      expect(GuestLiveInfo.fromJson({'session_id': 1, 'requires_pin': true}).requiresPin, isTrue);
      final page = GuestJoinsPage.fromJson({
        'items': [
          {'identity': 'g1', 'name': 'A', 'joined_at': '2026-10-24T09:30:00Z', 'ip_masked': '41.33.xx.xx'},
          {'identity': 'g2', 'name': 'B', 'joined_at': null, 'ip_masked': ''},
        ],
        'total': 9,
      });
      expect(page.total, 9);
      expect(page.items.length, 2);
      expect(page.items[0].ipMasked, '41.33.xx.xx');
      expect(page.items[0].joinedAt, isNotNull);
      expect(page.items[1].ipMasked, isNull);
    });

    test('guestPinValid: 4–8 digits only', () {
      expect(guestPinValid('1234'), isTrue);
      expect(guestPinValid('12345678'), isTrue);
      expect(guestPinValid('123'), isFalse);
      expect(guestPinValid('123456789'), isFalse);
      expect(guestPinValid('12a4'), isFalse);
      expect(guestPinValid(''), isFalse);
    });
  });

  group('route helpers', () {
    test('guestLiveTokenFromRoute', () {
      expect(guestLiveTokenFromRoute('/live/abc123'), 'abc123');
      expect(guestLiveTokenFromRoute('/live/abc123?x=1'), 'abc123');
      expect(guestLiveTokenFromRoute('https://alfheemacademy.com/live/t0k'), 't0k');
      expect(guestLiveTokenFromRoute('/live/'), isNull);
      expect(guestLiveTokenFromRoute('/live'), isNull);
      expect(guestLiveTokenFromRoute('/live/a/b'), isNull);
      expect(guestLiveTokenFromRoute('/c/12'), isNull);
      expect(guestLiveTokenFromRoute('/dashboard'), isNull);
      expect(guestLiveTokenFromRoute(null), isNull);
    });

    test('guestLiveRouteFromUri: path and hash forms', () {
      expect(guestLiveRouteFromUri(Uri.parse('https://alfheemacademy.com/live/abc')), '/live/abc');
      expect(guestLiveRouteFromUri(Uri.parse('https://alfheemacademy.com/#/live/abc')), '/live/abc');
      expect(guestLiveRouteFromUri(Uri.parse('https://alfheemacademy.com/live/abc#/live/abc')), '/live/abc');
      expect(guestLiveRouteFromUri(Uri.parse('https://alfheemacademy.com/')), isNull);
      expect(guestLiveRouteFromUri(Uri.parse('https://alfheemacademy.com/#/dashboard')), isNull);
    });

    test('legacyHashRoute: only old `/#/route` links, with their query; clean paths are left to the engine', () {
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/#/live/abc')), '/live/abc');
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/#/c/12?ref=5')), '/c/12?ref=5');
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/#/dashboard')), '/dashboard');
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/index.html#/login')), '/login');
      // Path strategy: the engine already starts on these.
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/live/abc')), isNull);
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/c/12?ref=5')), isNull);
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/')), isNull);
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/#/')), isNull);
      expect(legacyHashRoute(Uri.parse('https://alfheemacademy.com/#section')), isNull);
      // The token helper agrees on a hash guest link, query included.
      expect(guestLiveTokenFromRoute(legacyHashRoute(Uri.parse('https://alfheemacademy.com/#/live/x9?y=1'))), 'x9');
      // The clean URL main.dart rewrites the address bar to.
      final base = Uri.parse('https://alfheemacademy.com/#/c/12?ref=5');
      expect(base.removeFragment().resolve(legacyHashRoute(base)!.substring(1)).toString(), 'https://alfheemacademy.com/c/12?ref=5');
      final indexBase = Uri.parse('https://alfheemacademy.com/index.html#/live/abc');
      expect(indexBase.removeFragment().resolve(legacyHashRoute(indexBase)!.substring(1)).toString(), 'https://alfheemacademy.com/live/abc');
    });
  });
}
