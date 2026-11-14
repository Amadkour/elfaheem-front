// Track A2 polish, area "auth + shared" (docs/polish/screen-audit-auth-shared.md): the presentational bodies touched
// by the sweep, pumped at 320x640 and 1400x900, in Arabic and English, with textScaler 1.3 — plus the behaviour the
// sweep fixed (paging near the end of the notifications list, the chevron that Flutter mirrors by itself, complaint
// timestamps as real UTC instants).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart' show ProgressBar;
import 'package:flutter_education_app/features/auth/verify_way.dart';
import 'package:flutter_education_app/features/analytics/analytics_ui.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_screen.dart';
import 'package:flutter_education_app/features/shared/passcode/passcode_screen.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_model.dart' show complaintUtc;
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart';
import 'package:flutter_education_app/features/shared/profile/student_favorite_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'نص عربي طويل جداً لاختبار الالتفاف على الشاشات الصغيرة مع تكبير الخط إلى مئة وثلاثين بالمئة';
const _longEn = 'A very long English line that has to wrap on a 320 px phone with the text scaled to 130 percent';

Future<void> _noop() async {}

List<Widget> _cards(int n) => [
      for (var i = 0; i < n; i++)
        Container(
          padding: const EdgeInsets.all(14),
          child: Text('$i · $_longAr · $_longEn'),
        ),
    ];

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('NotificationsStateBody', () {
    for (final s in <String, NotificationsStateBody Function()>{
      'first load': () => NotificationsStateBody(loading: true, empty: true, error: null, onRefresh: _noop, children: const []),
      'error': () => NotificationsStateBody(loading: false, empty: true, error: _longAr, onRefresh: _noop, children: const []),
      'error without text': () => NotificationsStateBody(loading: false, empty: true, error: '', onRefresh: _noop, children: const []),
      'empty': () => NotificationsStateBody(loading: false, empty: true, error: null, onRefresh: _noop, children: const []),
      'list': () => NotificationsStateBody(loading: false, empty: false, error: null, onRefresh: _noop, children: _cards(8)),
      'list + next page loading': () =>
          NotificationsStateBody(loading: true, empty: false, error: null, onRefresh: _noop, onLoadMore: () {}, children: _cards(3)),
    }.entries) {
      testWidgets(s.key, (t) async => expectNoLayoutErrors(t, s.value));
    }

    testWidgets('asks for the next page near the end of the list, never while loading', (t) async {
      var asked = 0;
      Widget body({bool loading = false}) => layoutHost(
            NotificationsStateBody(
              loading: loading,
              empty: false,
              error: null,
              onRefresh: _noop,
              onLoadMore: () => asked++,
              children: _cards(40),
            ),
            scale: 1.0,
          );
      await t.pumpWidget(body());
      await t.drag(find.byType(ListView), const Offset(0, -200));
      await t.pump();
      expect(asked, 0, reason: 'far from the end');
      await t.fling(find.byType(ListView), const Offset(0, -20000), 5000);
      await t.pumpAndSettle();
      expect(asked, greaterThan(0));
      asked = 0;
      await t.pumpWidget(body(loading: true));
      await t.drag(find.byType(ListView).first, const Offset(0, -50)); // .first: the trailing skeleton is a ListView too
      await t.pump();
      expect(asked, 0, reason: 'a page is already on its way');
    });
  });

  group('FavouritesStateBody', () {
    final list = ListView(children: _cards(6));
    for (final s in <String, FavouritesStateBody Function()>{
      'first load': () => FavouritesStateBody(loading: true, empty: true, filtered: false, error: null, onRefresh: _noop, list: list),
      'error': () => FavouritesStateBody(loading: false, empty: true, filtered: false, error: _longEn, onRefresh: _noop, list: list),
      'empty': () => FavouritesStateBody(loading: false, empty: true, filtered: false, error: null, onRefresh: _noop, list: list),
      'nothing matches': () => FavouritesStateBody(loading: false, empty: true, filtered: true, error: null, onRefresh: _noop, list: list),
      'list': () => FavouritesStateBody(loading: false, empty: false, filtered: false, error: null, onRefresh: _noop, list: list),
    }.entries) {
      testWidgets(s.key, (t) async => expectNoLayoutErrors(t, s.value));
    }
  });

  group('PasscodeSheet', () {
    testWidgets('fits every screen (theme colours, keypad stays LTR)', (t) async {
      await expectNoLayoutErrors(
        t,
        () => Align(
          alignment: Alignment.bottomCenter,
          child: PasscodeSheet(title: _longAr, hint: _longEn, wrongText: _longAr, verify: (_) => false, pinLength: 8),
        ),
      );
    });

    testWidgets('icon-only keys carry a screen-reader label', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(layoutHost(PasscodeSheet(title: 'PIN', hint: 'hint', wrongText: 'wrong', verify: (_) => true)));
      await t.pump();
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a full code is handed to verify', (t) async {
      String? got;
      await t.pumpWidget(layoutHost(PasscodeSheet(
          title: 'PIN', hint: 'hint', wrongText: 'wrong', pinLength: 4, verify: (c) {
        got = c;
        return false;
      })));
      for (final d in ['1', '2', '3', '4']) {
        await t.tap(find.text(d));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 400));
      expect(got, '1234');
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('auth pieces', () {
    testWidgets('header, banner, step bar', (t) async {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: Column(children: [
            const AuthHeader(title: _longAr, subtitle: _longEn),
            const AuthInfoBanner(text: _longAr, icon: Icons.info_outline_rounded),
            const ProgressBar(currentStep: 1, totalSteps: 4),
          ]),
        ),
      );
    });

    testWidgets('verification ways', (t) async {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: Column(children: [
            VerifyWaySwitcher(
                ways: VerifyWay.values, selected: VerifyWay.whatsapp, onChanged: (_) {}, verified: const {VerifyWay.email}),
            VerifyWayButton(way: VerifyWay.telegram, label: _longAr, onPressed: () {}),
            const VerifyWayStatusPill(way: VerifyWay.sms, label: _longEn),
            const VerifyDestinationChip(way: VerifyWay.email, text: 'a.very.long.address.for.testing@example-domain.com'),
            const VerifyStepTracker(channels: ['email', 'phone'], pending: ['phone'], current: 'phone'),
          ]),
        ),
      );
    });
  });

  group('analytics pieces', () {
    testWidgets('hero stats, pills, chips, rings, empty and error', (t) async {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: Column(children: [
            Builder(
              builder: (context) => Container(
                decoration: anHeroDecoration(context),
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  const Row(children: [
                    AnHeroStat(icon: Icons.school_rounded, value: '98%', label: _longAr), // an Expanded itself
                    AnHeroStat(icon: Icons.timer_rounded, value: '12', label: _longEn),
                  ]),
                  const Wrap(children: [AnGlassPill(label: _longEn, icon: Icons.bolt_rounded)]),
                ]),
              ),
            ),
            Builder(builder: (context) => AnChip(icon: Icons.flag_rounded, label: _longAr, color: Colors.teal, badge: 120)),
            const Row(children: [AnRing(value: 72, label: 'avg'), Expanded(child: AnBar(value: 64, marker: 50))]),
            const AnEmpty(icon: Icons.insights_rounded, title: _longAr, sub: _longEn),
            AnErrorRetry(message: _longEn, onRetry: () {}),
          ]),
        ),
      );
    });
  });

  group('direction', () {
    testWidgets('the settings row chevron is chevron_right in both languages (Flutter mirrors it in Arabic)', (t) async {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        await t.pumpWidget(layoutHost(SettingsTile(
            icon: Icons.person_rounded, iconBg: Colors.black12, iconColor: Colors.black, label: 'x', onTap: () {})));
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget, reason: lang);
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing, reason: lang);
      }
    });
  });

  group('complaint timestamps', () {
    test('a naive server time is UTC; an offset is honoured; garbage falls back to now', () {
      final a = complaintUtc('2026-10-28T10:15:00');
      expect(a.isUtc, isTrue);
      expect([a.hour, a.minute], [10, 15]);
      final b = complaintUtc('2026-10-28T13:15:00+03:00');
      expect(b.isUtc, isTrue);
      expect(b.hour, 10);
      final c = complaintUtc('not a date');
      expect(c.isUtc, isTrue);
      expect(DateTime.now().toUtc().difference(c).inSeconds.abs(), lessThan(5));
    });
  });
}
