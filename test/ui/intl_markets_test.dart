// The international pass (RULES §2 – §3): the key money and time screens as four users, a student in Saudi Arabia,
// a student in Egypt, a teacher in the UAE and a parent in the UK (test/support/redesign/intl_fakes.dart). For each:
// nothing Saudi-only outside Saudi Arabia (مدى, STC Pay, 15 %, قدرات / تحصيلي), the server's currency, the VAT line
// only when the server says it applies, InstaPay only for Egypt, and every screen in English at 320 px with text
// scale 1.3 without overflow or Arabic UI copy.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/booking/booking_flow_page.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart' show bkMoney;
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/courses/student/details/subject_guest_space.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/parent/pa_kit.dart' show paRole;
import 'package:flutter_education_app/features/parent/pay/pa_payments_page.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/redesign/intl_fakes.dart';
import '../support/redesign/pa_fakes.dart' show paApi, paReem, paSetUp;
import '../support/redesign/wire_fakes.dart' show wirePaymentRow, wirePayments;
import '../support/redesign/sb_subject_fakes.dart' show sbT;
import 'layout_harness.dart';

final _arabic = RegExp('[؀-ۿ]');

/// Every piece of text on screen.
List<String> _texts(WidgetTester t) => [
      for (final r in t.widgetList<RichText>(find.byType(RichText))) r.text.toPlainText(),
      for (final e in t.widgetList<EditableText>(find.byType(EditableText))) e.controller.text,
    ];

/// Pumps [build] at 320×640, text scale 1.3, in [lang]; [settle] frames for the loads over FakeApi.
Future<List<String>> _show(WidgetTester t, String lang, Widget Function() build, {int settle = 8}) async {
  AppConfig.lang = lang;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(320, 640);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(layoutHost(build()));
  for (var i = 0; i < settle; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
  expect(t.takeException(), isNull, reason: 'layout error at 320 / $lang');
  return _texts(t);
}

/// The market rules on what is drawn: no Saudi-only word outside Saudi Arabia; in English, no Arabic UI copy.
void _expectMarket(IntlMarket m, String lang, List<String> texts, {String where = ''}) {
  final all = texts.join('\n');
  if (!m.saudi) {
    for (final w in intlSaudiOnly) {
      expect(all.contains(w), isFalse, reason: '"$w" shown to the $m ($lang) $where');
    }
  }
  if (lang == 'en') {
    final ar = [for (final s in texts) if (_arabic.hasMatch(s)) s];
    expect(ar, isEmpty, reason: 'Arabic left in English for the $m $where');
  }
}

CourseModel _course(IntlMarket m) => CourseModel.fromJson({
      'id': 41,
      'title_ar': 'رياضيات',
      'title_en': 'Mathematics',
      'fees': m.price,
      'currency': m.currency,
      'is_enrolled': false,
      'is_published': true,
    });

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  final prevLang = AppConfig.lang;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.lang = prevLang);

  for (final m in intlMarkets) {
    group('$m', () {
      setUp(() => intlUseZone(m));

      testWidgets('booking: review and pay', (t) async {
        for (final lang in const ['ar', 'en']) {
          final texts = await _show(t, lang, () => BookFlowPage(controller: intlBookingAtPay(m), autoload: false));
          final all = texts.join('\n');
          expect(all.contains(bkMoney(m.price, m.currency)), isTrue, reason: 'the price in ${m.currency} ($lang)');
          final vat = sbT('ضريبة القيمة المضافة', 'VAT');
          expect(all.contains(vat), m.vat, reason: 'the VAT line only when it applies ($lang)');
          if (m.saudi) expect(all.contains(sbT('مدى', 'mada')), isTrue, reason: 'مدى for Saudi Arabia');
          _expectMarket(m, lang, texts, where: 'on the booking');
        }
        await expectNoLayoutErrors(t, () => BookFlowPage(controller: intlBookingAtPay(m), autoload: false));
      });

      testWidgets('course checkout: methods, VAT and currency', (t) async {
        mockRequestPlugins();
        final api = FakeApi(intlCheckoutRoutes(m), latency: const Duration(milliseconds: 5))..install();
        addTearDown(api.uninstall);
        for (final lang in const ['ar', 'en']) {
          final texts = await _show(t, lang, () => EnrollmentScreen(course: _course(m)), settle: 14);
          final all = texts.join('\n');
          expect(all.contains('transfer_instapay_title'.tr), m.country == 'EG', reason: 'InstaPay only for Egypt ($lang)');
          expect(texts.any((s) => s.trim() == 'VAT'.tr), m.vat, reason: 'the VAT row only when it applies ($lang)');
          expect(all.contains(currencySymbolFor(m.currency)), isTrue, reason: 'the ${m.currency} total ($lang)');
          if (m.saudi && lang == 'ar') expect(all.contains('مدى'), isTrue, reason: 'the new card names مدى in Saudi Arabia');
          _expectMarket(m, lang, texts, where: 'at checkout');
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 1));
        }
        expect(api.calls.where((c) => c.path == '/api/v1/payments/methods'), isNotEmpty, reason: 'the payer\'s methods are asked');
      });

      testWidgets('wallet and buy points: the payer\'s methods', (t) async {
        final api = FakeApi(intlWalletRoutes(m), latency: Duration.zero)..install();
        addTearDown(api.uninstall);
        late PointsWallet w;
        await t.runAsync(() async => w = await const PointsApi().wallet());
        expect(w.methods.contains('instapay'), m.country == 'EG', reason: 'InstaPay only for Egypt');
        expect(w.hasCard, isTrue);
        expect(w.currency, m.currency);
        final now = DateTime.utc(2026, 11, 27, 9);
        for (final lang in const ['ar', 'en']) {
          final texts = [
            ...await _show(t, lang, () => PointsWalletView(wallet: w, nowUtc: now, onBuy: () {})),
            ...await _show(t, lang, () => SingleChildScrollView(child: TopupForm(wallet: w, submit: (_, _, _, _) async => null))),
          ];
          final all = texts.join('\n');
          expect(all.contains(m.currency), isTrue, reason: 'the point price in ${m.currency} ($lang)');
          expect(all.contains('transfer_instapay_title'.tr) || all.contains(sbT('إنستاباي', 'InstaPay')), m.country == 'EG',
              reason: 'InstaPay only for Egypt ($lang)');
          _expectMarket(m, lang, texts, where: 'in the wallet');
        }
      });

      testWidgets('parent payments: the payment\'s own currency', (t) async {
        await paSetUp(paApi(extra: {
          // Latin names (data) so the English pass can look for Arabic UI copy
          'GET /api/v1/parent/children': (_) => [{'id': paReem, 'name': 'Reem'}],
          'GET /api/v1/parent/children/$paReem/payments': (_) => wirePayments(paReem, rows: [
                wirePaymentRow(1191, amount: m.price, currency: m.currency, course: 'Maths'),
                wirePaymentRow(1172, status: 'pending', amount: m.price, currency: m.currency, course: 'Science'),
              ]),
        }));
        for (final lang in const ['ar', 'en']) {
          final texts = await _show(t, lang, () => paRole(const ParentPaymentsPage()));
          final all = texts.join('\n');
          expect(all.contains(m.currency), isTrue, reason: 'amounts in ${m.currency} ($lang)');
          for (final other in const ['SAR', 'EGP']) {
            if (other != m.currency) expect(all.contains(other), isFalse, reason: '$other shown to the $m ($lang)');
          }
          _expectMarket(m, lang, texts, where: 'on the payments page');
        }
      });

      testWidgets('subject page before subscribing: the price', (t) async {
        Widget page() => SubjectGuestSpace(
              title: sbT('الرياضيات', 'Mathematics'),
              teacher: sbT('أ. ماجد', 'Mr Majed'),
              subject: 'math',
              price: coursePriceLabel(AppCurrencyX.fromCode(m.currency), m.price),
              priceNote: sbT('في الشهر', 'a month'),
              primaryLabel: sbT('احجز المادة', 'Book the subject'),
              onPrimary: () {},
              onBack: () {},
            );
        for (final lang in const ['ar', 'en']) {
          final texts = await _show(t, lang, page);
          final all = texts.join('\n');
          expect(all.contains(coursePriceLabel(AppCurrencyX.fromCode(m.currency), m.price)), isTrue);
          _expectMarket(m, lang, texts, where: 'on the subject page');
        }
        await expectNoLayoutErrors(t, page);
      });

      testWidgets('schedule: in the viewer\'s zone', (t) async {
        for (final lang in const ['ar', 'en']) {
          final texts = await _show(t, lang, intlSchedulePanel);
          _expectMarket(m, lang, texts, where: 'on the schedule');
        }
        await expectNoLayoutErrors(t, intlSchedulePanel);
      });
    });
  }

  test('payer narrowing: a country list turns off what it does not name; none keeps the config', () {
    final g = GatewayConfig.fromJson(intlConfigJson(intlUkParent));
    expect(g.instapayEnabled, isTrue, reason: 'the older /config opens InstaPay for an EGP course');
    final uk = g.forPayer(intlUkParent.methods.toSet());
    expect(uk.instapayEnabled, isFalse);
    expect(uk.cardEnabled, isTrue);
    expect(uk.madaOffered, isFalse);
    expect(g.forPayer(null).instapayEnabled, isTrue);
    expect(GatewayConfig.fromJson(intlConfigJson(intlSaStudent)).forPayer({'mada'}).cardEnabled, isTrue);
    expect(FeeQuote.fromJson({'vat_on_platform': 0, 'vat_applies': false}).showVat, isFalse);
    expect(FeeQuote.fromJson({'vat_on_platform': 3.0}).showVat, isTrue, reason: 'an older server: by the amount');
  });
}
