// Phase 9 (fx-admin): the booking, teacher-demand and payment-markets consoles at 320x640 and 1400x900, ar / en,
// text x1.3 (no layout error) on every tab and with empty data, plus what their PUTs send (every field).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppField;
import 'package:flutter_education_app/features/admin/consoles/admin_booking_page.dart';
import 'package:flutter_education_app/features/admin/consoles/admin_demand_page.dart';
import 'package:flutter_education_app/features/admin/consoles/admin_markets_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_api.dart';
import '../../support/redesign/a1_fakes.dart';
import '../../support/redesign/admin_console_fakes.dart';
import '../layout_harness.dart';

void main() {
  late FakeApi fake;
  late MyAuthProvider auth;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  Future<void> install({bool empty = false, Map<String, FakeHandler>? extra}) async {
    auth = a1Auth(await a1SignIn(role: 'super-admin'));
    mockRequestPlugins();
    AppConfig.lang = 'ar';
    fake = FakeApi({...adminConsoleRoutes(empty: empty), ...?extra}, latency: const Duration(milliseconds: 5))..install();
    addTearDown(fake.uninstall);
  }

  Widget host(Widget child) => ChangeNotifierProvider.value(value: auth, child: child);

  Future<void> layout(WidgetTester t, Widget Function() page) =>
      expectNoLayoutErrors(t, () => host(page()), scaffold: false, frames: 12);

  group('booking', () {
    setUp(install);
    for (var i = 0; i < 4; i++) {
      testWidgets('tab $i', (t) => layout(t, () => AdminBookingPage(initialTab: i)));
    }
  });

  group('booking, nothing yet', () {
    setUp(() => install(empty: true));
    for (var i = 1; i < 4; i++) {
      testWidgets('tab $i', (t) => layout(t, () => AdminBookingPage(initialTab: i)));
    }
  });

  group('demand', () {
    setUp(install);
    testWidgets('settings', (t) => layout(t, () => const AdminTeacherDemandPage()));
  });

  group('markets', () {
    setUp(install);
    for (var i = 0; i < 3; i++) {
      testWidgets('tab $i', (t) => layout(t, () => AdminPaymentMarketsPage(initialTab: i)));
    }
  });

  group('markets, nothing yet', () {
    setUp(() => install(empty: true));
    for (var i = 0; i < 3; i++) {
      testWidgets('tab $i', (t) => layout(t, () => AdminPaymentMarketsPage(initialTab: i)));
    }
  });

  group('PUT bodies', () {
    Future<void> pump(WidgetTester t, Widget page) async {
      AppConfig.lang = 'en';
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1400, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(layoutHost(page, scale: 1)));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> done(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    }

    testWidgets('teacher demand sends the three numbers', (t) async {
      Object? sent;
      await install(extra: {
        'PUT /api/v1/admin/teacher-demand/settings': (o) {
          sent = o.data;
          return {'threshold': 6, 'group_min': 5, 'stale_days': 2, 'last_day': '2026-11-26'};
        },
      });
      await pump(t, const AdminTeacherDemandPage());
      await t.enterText(find.byType(TextField).first, '6');
      await t.pump();
      await t.tap(find.text('Save'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(sent, {'threshold': 6, 'group_min': 5, 'stale_days': 2});
      await done(t);
    });

    testWidgets('booking settings send every price and rule', (t) async {
      Object? sent;
      await install(extra: {
        'PUT /api/v1/admin/booking/settings': (o) {
          sent = o.data;
          return acBookingSettings();
        },
      });
      await pump(t, const AdminBookingPage());
      await t.enterText(find.byType(TextField).first, '210');
      await t.pump();
      await t.tap(find.text('Save'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(sent, {
        'prices': {
          'remote': {'group': 210.0, 'individual': 449.0},
          'in_person': {'group': 299.0, 'individual': 599.0},
        },
        'currency': 'SAR',
        'few_seats_at': 3,
        'proposal_hours': 24,
      });
      await done(t);
    });

    testWidgets('VAT sends the seller, every rule and the tax number', (t) async {
      Object? sent;
      await install(extra: {
        'PUT /api/v1/admin/payments/vat-rules': (o) {
          sent = o.data;
          return acVat();
        },
      });
      await pump(t, const AdminPaymentMarketsPage(initialTab: 2));
      await t.enterText(find.descendant(of: find.byWidgetPredicate((w) => w is AppField && w.label == 'Tax number'), matching: find.byType(TextField)), '300999');
      await t.pump();
      await t.tap(find.text('Save'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(sent, {
        'seller_country': 'SA',
        'rules': {
          'SA': {'percent': 15.0, 'scope': 'domestic'},
          'EG': {'percent': null, 'scope': 'all'},
        },
        'tax_number': '300999',
      });
      await done(t);
    });
  });
}
