// Guest links for live sessions at 320x640 and 1400x900, ar + en, textScaler 1.3:
//   • GuestLinkBody (teacher sheet body): no link yet (create form) · link present (facts, actions, QR, settings panel) ·
//     loading · error.
//   • GuestLiveContent (public /live/<token> page): loading skeleton · not started (waiting) · live · error (final and
//     retryable).
// Plus the pure route helpers that resolve `/live/<token>` from a route name / browser URL.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_page.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/guest_link_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _link = GuestLink(
  url: 'https://nextbrain.site/live/3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e7d8f9a0b1c2d3e4f',
  token: '3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e7d8f9a0b1c2d3e4f',
  canPublish: true,
  maxGuests: 25,
  guestsJoined: 7,
  createdAt: null,
);

Widget _linkBody({
  bool loading = false,
  bool busy = false,
  String? error,
  GuestLink? link,
  bool canPublish = false,
  bool editing = false,
  bool showQr = false,
  TextEditingController? max,
}) =>
    GuestLinkBody(
      loading: loading,
      busy: busy,
      error: error,
      link: link,
      canPublish: canPublish,
      maxGuestsController: max ?? TextEditingController(text: '25'),
      editing: editing,
      showQr: showQr,
      onRetry: () {},
      onCanPublishChanged: (_) {},
      onCreate: () {},
      onCopy: () {},
      onShare: () {},
      onToggleQr: () {},
      onToggleSettings: () {},
      onSaveSettings: () {},
      onRotate: () {},
      onRevoke: () {},
    );

const _info = GuestLiveInfo(
  sessionId: 42,
  sessionName: 'Advanced Algorithms — week 7: dynamic programming over trees (a long session name to wrap)',
  courseName: 'خوارزميات متقدمة — الفصل الدراسي الثاني',
  teacherName: 'Dr. Ahmed Hamdy Madkour',
  isLive: true,
  canPublish: false,
  recordingEnabled: true,
  guestsJoined: 3,
  maxGuests: 10,
);

Widget _page({
  bool loading = false,
  GuestLiveInfo? info,
  String? error,
  bool errorFinal = false,
  bool joining = false,
  TextEditingController? name,
}) =>
    GuestLiveContent(
      loading: loading,
      info: info,
      error: error,
      errorFinal: errorFinal,
      joining: joining,
      nameController: name ?? TextEditingController(text: 'أحمد حمدي'),
      onJoin: () {},
      onRetry: () {},
    );

GuestLiveInfo _copy(GuestLiveInfo i, {bool? isLive, bool? canPublish, bool? recording, int? joined, int? max, bool clearMax = false}) =>
    GuestLiveInfo(
      sessionId: i.sessionId,
      sessionName: i.sessionName,
      courseName: i.courseName,
      teacherName: i.teacherName,
      isLive: isLive ?? i.isLive,
      canPublish: canPublish ?? i.canPublish,
      recordingEnabled: recording ?? i.recordingEnabled,
      guestsJoined: joined ?? i.guestsJoined,
      maxGuests: clearMax ? null : (max ?? i.maxGuests),
    );

void main() {
  group('GuestLinkBody', () {
    testWidgets('no link yet: options + create button', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: null),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.create')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.can_publish')), findsOneWidget);
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
          for (final k in ['copy', 'share', 'qr', 'settings', 'rotate', 'revoke']) {
            expect(find.byKey(ValueKey('guest_link.$k')), findsOneWidget, reason: k);
          }
          expect(find.byKey(const ValueKey('guest_link.qr_image')), findsNothing);
        },
      );
    });

    testWidgets('link present with QR and the settings panel open, no limit, busy', (tester) async {
      const noLimit = GuestLink(url: 'https://nextbrain.site/live/abc', token: 'abc', canPublish: false, maxGuests: null, guestsJoined: 0);
      await expectNoLayoutErrors(
        tester,
        () => _linkBody(link: noLimit, showQr: true, editing: true, busy: true, max: TextEditingController()),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_link.qr_image')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_link.settings_panel')), findsOneWidget);
        },
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
          final btn = t.widget<FilledButton>(find.descendant(
              of: find.byKey(const ValueKey('guest_live.join')), matching: find.byType(FilledButton)));
          expect(btn.onPressed, isNull);
        },
      );
    });

    testWidgets('live: recording note, name field, join enabled', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _page(info: _info),
        act: (t) async {
          expect(find.byKey(const ValueKey('guest_live.live')), findsOneWidget);
          expect(find.byKey(const ValueKey('guest_live.recorded')), findsOneWidget);
          final btn = t.widget<FilledButton>(find.descendant(
              of: find.byKey(const ValueKey('guest_live.join')), matching: find.byType(FilledButton)));
          expect(btn.onPressed, isNotNull);
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
        () => _page(info: _copy(_info, joined: 10, max: 10)),
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
  });

  group('route helpers', () {
    test('guestLiveTokenFromRoute', () {
      expect(guestLiveTokenFromRoute('/live/abc123'), 'abc123');
      expect(guestLiveTokenFromRoute('/live/abc123?x=1'), 'abc123');
      expect(guestLiveTokenFromRoute('https://nextbrain.site/live/t0k'), 't0k');
      expect(guestLiveTokenFromRoute('/live/'), isNull);
      expect(guestLiveTokenFromRoute('/live'), isNull);
      expect(guestLiveTokenFromRoute('/live/a/b'), isNull);
      expect(guestLiveTokenFromRoute('/c/12'), isNull);
      expect(guestLiveTokenFromRoute('/dashboard'), isNull);
      expect(guestLiveTokenFromRoute(null), isNull);
    });

    test('guestLiveRouteFromUri: path and hash forms', () {
      expect(guestLiveRouteFromUri(Uri.parse('https://nextbrain.site/live/abc')), '/live/abc');
      expect(guestLiveRouteFromUri(Uri.parse('https://nextbrain.site/#/live/abc')), '/live/abc');
      expect(guestLiveRouteFromUri(Uri.parse('https://nextbrain.site/live/abc#/live/abc')), '/live/abc');
      expect(guestLiveRouteFromUri(Uri.parse('https://nextbrain.site/')), isNull);
      expect(guestLiveRouteFromUri(Uri.parse('https://nextbrain.site/#/dashboard')), isNull);
    });
  });
}
