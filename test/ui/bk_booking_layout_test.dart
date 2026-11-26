// BookFlow (BK) and the subject page's BK parts: no layout error at any size / language / text scale for every
// step and state, the client's wording (RULES §1), the privacy rule (a seat level, never a count), the flow over
// FakeApi from the first step to "تم", and Reduce motion.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart';
import 'package:flutter_education_app/features/booking/booking_flow_page.dart';
import 'package:flutter_education_app/features/booking/booking_mine_card.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/booking/booking_sign_in_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/redesign/bk_fakes.dart';
import 'layout_harness.dart';

Widget _page(BkFlowController c) => BookFlowPage(controller: c, autoload: false);

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bkUseRiyadh();
  });

  group('BookFlow steps lay out', () {
    testWidgets('1 · remote', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController())));
    testWidgets('1 · in person with the location', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController(inPerson: true))));
    testWidgets('2 · group or individual, gender asked', (t) async =>
        expectNoLayoutErrors(t, () => _page(demoBkController(step: 2, gender: false))));
    testWidgets('3 · the groups', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController(step: 3))));
    testWidgets('3 · the one group', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController(step: 3, single: true))));
    testWidgets('3 · the free times', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController(step: 3, kind: 'individual'))));
    testWidgets('3 · propose times', (t) async =>
        expectNoLayoutErrors(t, () => _page(demoBkController(step: 3, kind: 'individual', proposing: true))));
    testWidgets('4 · review and pay', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController(step: 4))));
    testWidgets('5 · done', (t) async => expectNoLayoutErrors(t, () => _page(demoBkController(step: 5))));
    testWidgets('4ب · the sign-in sheet', (t) async => expectNoLayoutErrors(t, () => BkSignInSheet(onGoogle: () {}, onPhone: () {})));
    testWidgets('حجزك card', (t) async => expectNoLayoutErrors(
          t,
          () => ListView(children: [
            BkMineCard(booking: BkBooking.fromJson(bkBookingJson(status: 'pending_payment')), onPay: () {}),
            BkMineCard(booking: BkBooking.fromJson(bkBookingJson())),
          ]),
        ));
  });

  group('subject page BK parts lay out', () {
    testWidgets('before subscribing', (t) async => expectNoLayoutErrors(t, () => demoGuestSpace()));
    testWidgets('before subscribing, the book opens', (t) async => expectNoLayoutErrors(
          t,
          () => demoGuestSpace(),
          act: (t) async => t.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'sb_subj_tap_book_hint'.tr).first),
        ));
    testWidgets('assistant on', (t) async => expectNoLayoutErrors(t, () => demoBotPanel()));
    testWidgets('assistant locked', (t) async => expectNoLayoutErrors(t, () => demoBotPanel(on: false)));
    testWidgets('schedule', (t) async => expectNoLayoutErrors(t, () => demoSchedulePanel()));
  });

  testWidgets('the client wording: no subtitle under the question, فردي, عن بعد, never a count of classes', (t) async {
    AppConfig.lang = 'ar';
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(_page(demoBkController())));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('كيف تبي تدرس؟'), findsOneWidget);
    expect(find.text('شرح مباشر ويتم حفظ الشرح للرجوع إليه.'), findsOneWidget);
    expect(find.text('يكون وجهًا لوجه مع المعلم أو المعلمة.'), findsOneWidget);
    await t.pumpWidget(layoutHost(_page(demoBkController(step: 2))));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('فردي مع المعلم'), findsOneWidget);
    for (final bad in ['لحالك', 'أونلاين', 'كورس', 'جلسة', 'مرتين', 'حصص في الشهر']) {
      expect(find.textContaining(bad), findsNothing, reason: bad);
    }
  });

  testWidgets('a group shows a seat level, never how many seats or who', (t) async {
    AppConfig.lang = 'ar';
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(_page(demoBkController(step: 3))));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('آخر مقاعد'), findsOneWidget);
    expect(find.text('مكتملة، نبّهني إذا فضى مقعد'), findsOneWidget);
    expect(find.textContaining(RegExp(r'باقي \d|\d+ من \d+ مقاعد|\d+ (طلاب|طالب)')), findsNothing);
    expect(find.textContaining('الأحد والثلاثاء'), findsWidgets);
    expect(find.textContaining('7:30 إلى 8:20 م'), findsWidgets);
  });

  testWidgets('the flow over the server: remote, group أ, review, confirm, done', (t) async {
    AppConfig.lang = 'ar';
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final fake = FakeApi(bookingRoutes(), latency: Duration.zero)..install();
    addTearDown(fake.uninstall);
    final c = BkFlowController(subjectId: bkSubjectId, gradeId: bkGradeId, subjectKey: 'math');
    await t.pumpWidget(layoutHost(BookFlowPage(controller: c, autoload: false)));
    await t.runAsync(c.load);
    await t.pump();
    expect(c.options, isNotNull);
    c.pickMode('remote');
    await c.next();
    c.pickKind('group');
    await t.runAsync(() => c.next());
    await t.pump();
    expect(c.groups?.items.length, 4);
    c.pickGroup(41);
    await t.runAsync(() => c.next());
    await t.pump();
    expect(c.step, 4);
    expect(c.quote?.price, 199);
    expect(c.payInfo?.bookable.map((m) => m.key), ['mada', 'apple_pay', 'card']);
    await t.pump();
    await t.runAsync(() async {
      await t.tap(find.textContaining('أكّد وادفع'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.step, 5);
    expect(find.text('تم، حجزك تأكد'), findsOneWidget);
    expect(fake.calls.where((x) => x.method == 'POST' && x.path.endsWith('/booking/confirm')).length, 1);
    final confirm = fake.calls.firstWhere((x) => x.path.endsWith('/booking/confirm'));
    expect(confirm.path, '/api/v1/booking/confirm');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the picks survive the sign-in (4ب) and come back on the review', (t) async {
    final c = demoBkController(step: 4);
    await c.saveDraft();
    expect(await BkFlowController.hasDraft(bkSubjectId, bkGradeId), isTrue);
    final again = BkFlowController(subjectId: bkSubjectId, gradeId: bkGradeId);
    expect(await again.restoreDraft(), isTrue);
    expect(again.mode, 'remote');
    expect(again.kind, 'group');
    expect(again.groupId, 41);
    expect(await BkFlowController.hasDraft(bkSubjectId, bkGradeId), isFalse);
  });

  testWidgets('Reduce motion: the done step draws its end state and leaves no loop running', (t) async {
    AppConfig.lang = 'ar';
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: _page(demoBkController(step: 5)),
      ),
    ));
    await t.pump();
    expect(find.text('تم، حجزك تأكد'), findsOneWidget);
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await t.pumpWidget(const SizedBox());
  });

  test('a proposal sends days, periods and the zone, never slots', () {
    final c = demoBkController(step: 3, kind: 'individual', proposing: true);
    final body = c.request.toJson();
    expect(body['kind'], 'individual');
    expect(body.containsKey('slot_ids'), isFalse);
    expect(body['proposal']['weekdays'], [1, 6]);
    expect(body['proposal']['periods'], ['afternoon']);
    expect((body['proposal']['tz'] as String).isNotEmpty, isTrue);
  });

  test('money comes from the server: the currency word follows the code', () {
    AppConfig.lang = 'ar';
    expect(bkMoney(199, 'SAR'), '199 ريال');
    expect(bkMoney(450, 'EGP'), '450 جنيه');
    AppConfig.lang = 'en';
    expect(bkMoney(199, 'SAR'), 'SAR 199');
    AppConfig.lang = 'ar';
  });
}
