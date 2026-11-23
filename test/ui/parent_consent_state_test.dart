// A parent's child tabs (games, Quran, grammar) when the server answers 403 `consent_required` (D-1371): one state
// with "Give consent" instead of an error, the dialog's POST, then the tab reloads. Plus the state's layout.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/games/games_progress.dart';
import 'package:flutter_education_app/features/nahw/nahw_tab.dart';
import 'package:flutter_education_app/features/parent/parent_consent.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _refused = FakeResponse(403, {
  'detail': {
    'code': 'consent_required',
    'message': 'يلزم موافقة ولي الأمر على حساب الطالب القاصر',
    'message_en': "A parent's consent is required for a child's account",
  },
});

const _games = {
  'student_id': 7,
  'summary': {'minutes_7d': 0, 'finished_7d': 0, 'minutes_30d': 0, 'finished_30d': 0},
  'games': [],
  'badges': [],
  'totals': {'plays': 0, 'stars': 0, 'games': 0, 'perfect': 0},
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('the consent state fits every size, ar / en, text 1.3', (tester) async {
    await expectNoLayoutErrors(
        tester, () => ConsentRequiredView(childName: 'A child with a rather long full name for a phone', onGive: () {}));
    await expectNoLayoutErrors(tester, () => ConsentRequiredView(onGive: () {}, busy: true));
  });

  test('consent_required has a bilingual text', () {
    final e = ApiException(statusCode: 403, code: 'consent_required', message: 'x');
    expect(apiErrorText(e), contains('consent'));
    AppConfig.lang = 'ar';
    expect(apiErrorText(e), contains('موافقتك'));
    expect(isConsentRequired(e), isTrue);
    expect(isConsentRequired(ApiException(statusCode: 404, code: 'LINK_NOT_FOUND', message: 'x')), isFalse);
  });

  group('child tabs', () {
    late FakeApi fake;
    var consented = false;
    setUp(() {
      consented = false;
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      fake = FakeApi({
        'GET /api/v1/parent/children/7/games': (_) => consented ? _games : _refused,
        'GET /api/v1/parent/children/7/nahw': (_) => consented ? {'levels': []} : _refused,
        'GET /api/v1/parent/children/7/quran/progress': (_) => consented
            ? {'surahs': [], 'juz': [], 'recent': [], 'memorized_total': 0, 'total_ayahs': 6236}
            : _refused,
        'POST /api/v1/parent/children/7/consent': (_) {
          consented = true;
          return const FakeResponse(201, {'granted': true, 'minor': true, 'id': 1});
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      QuranApi.setMetaForTest(QuranMeta.fromJson({'surahs': [], 'juz': []}));
    });
    tearDown(() {
      fake.uninstall();
      QuranApi.setMetaForTest(null);
    });

    Future<void> pump(WidgetTester tester, Widget page) async {
      await tester.pumpWidget(layoutHost(page, scaffold: false, scale: 1));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('games: the state, then consent reloads the tab', (tester) async {
      await pump(tester, const ParentChildGamesPage(studentId: 7, studentName: 'Sara'));
      expect(find.byKey(const ValueKey('consent.required')), findsOneWidget);
      await tester.tap(find.text('Give consent'));
      await tester.pump(const Duration(milliseconds: 400));
      // "I agree" stays off until the box is ticked
      await tester.tap(find.byKey(const ValueKey('consent.box')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('consent.agree')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fake.calls.where((c) => c.key == 'POST /api/v1/parent/children/7/consent'), hasLength(1));
      expect(find.byKey(const ValueKey('consent.required')), findsNothing);
      expect(fake.calls.where((c) => c.key == 'GET /api/v1/parent/children/7/games'), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('nahw shows the state', (tester) async {
      await pump(tester, const ParentChildNahwPage(studentId: 7, studentName: 'Sara'));
      expect(find.byKey(const ValueKey('consent.required')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quran shows the state', (tester) async {
      await pump(tester, const QuranProgressPage.child(childId: 7, name: 'Sara'));
      expect(find.byKey(const ValueKey('consent.required')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
