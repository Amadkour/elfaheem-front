// Phase 9 wiring (rd/fx-wire): the screens of routes that had none — the parent's payments per child and the invoice
// (WP13), the games nickname editor (WP4) and the teacher's booking slots — at 320x640 and 1400x900, Arabic +
// English, textScaler 1.3, plus what each must show or hide (VAT only when sent, the tax number only when set, the
// 422 reason under the field, the change lock, a booked time that cannot be removed).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/games/learner/nickname_sheet.dart';
import 'package:flutter_education_app/features/parent/pa_kit.dart';
import 'package:flutter_education_app/features/parent/pay/pa_payments_page.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_booking_slots.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/redesign/pa_fakes.dart';
import '../support/redesign/wire_fakes.dart';
import 'layout_harness.dart';

const _long = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة Office of Student Affairs and Research';

Future<void> _host(WidgetTester t, Widget child) async {
  AppConfig.lang = 'ar';
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 2400);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(layoutHost(child, scale: 1));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => AppConfig.disableList = []);

  group('parent payments (WP13)', () {
    final invoices = [
      PaInvoice.fromJson(wireInvoice(paReem, 1191)),
      PaInvoice.fromJson(wireInvoice(paReem, 1184, vat: false, taxNumber: null)),
      PaInvoice.fromJson({...wireInvoice(paReem, 1150, status: 'refunded'), 'course': {'id': 1, 'name': _long}, 'invoice_number': 'INV-2026-123456789012'}),
    ];

    testWidgets('layout: the list, the invoice, the receipt', (t) async {
      await paSetUp(paApi(extra: wireParentRoutes()));
      await expectNoLayoutErrors(t, () => paRole(const ParentPaymentsPage()), frames: 8);
      for (final inv in invoices) {
        await expectNoLayoutErrors(t, () => SingleChildScrollView(child: paRole(PaInvoiceView(invoice: inv, onPdf: () {}))));
      }
      await expectNoLayoutErrors(t, () => paRole(const PaInvoicePage(childId: paReem, paymentId: 1191)), frames: 6);
      await expectNoLayoutErrors(t, () => SingleChildScrollView(
            child: paRole(PaReceiptSheet(payment: PaPayment.tryParse({...wirePaymentRow(1172, status: 'pending'), 'course_name': _long})!)),
          ));
    });

    testWidgets('VAT only when sent, the tax number only when set', (t) async {
      await _host(t, SingleChildScrollView(child: paRole(PaInvoiceView(invoice: invoices[0]))));
      expect(find.byKey(const ValueKey('pa.invoice.vat.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('pa.invoice.tax_number')), findsOneWidget);
      expect(find.text('300123456700003'), findsOneWidget);
      await _host(t, SingleChildScrollView(child: paRole(PaInvoiceView(invoice: invoices[1]))));
      expect(find.byKey(const ValueKey('pa.invoice.vat.0')), findsNothing);
      expect(find.byKey(const ValueKey('pa.invoice.tax_number')), findsNothing);
      await _host(t, SingleChildScrollView(child: paRole(PaInvoiceView(invoice: invoices[2]))));
      expect(find.byKey(const ValueKey('pa.invoice.refunded')), findsOneWidget);
    });

    testWidgets('one child\'s payments, the status filter, the invoice and its PDF', (t) async {
      final api = paApi(extra: wireParentRoutes());
      await paSetUp(api);
      await _host(t, paRole(const ParentPaymentsPage()));
      expect(api.calls.any((c) => c.path == '/api/v1/parent/children/$paReem/payments' && c.query['limit'] == '20'), isTrue);
      expect(api.calls.any((c) => c.path == '/api/v1/my-payments'), isFalse);
      expect(find.byKey(const ValueKey('pa.pay.1172')), findsOneWidget);
      // "In review" asks the server for pending payments only
      await t.ensureVisible(find.text('pa_pay_tab_review'.tr));
      await t.pump();
      await t.tap(find.text('pa_pay_tab_review'.tr));
      await _settle(t);
      expect(api.calls.any((c) => c.query['status'] == 'pending'), isTrue);
      expect(find.byKey(const ValueKey('pa.pay.1191')), findsNothing);
      await t.ensureVisible(find.text('pa_pay_tab_all'.tr));
      await t.pump();
      await t.tap(find.text('pa_pay_tab_all'.tr));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('pa.pay.1191')));
      await _settle(t);
      expect(find.byType(PaInvoiceView), findsOneWidget);
      expect(api.calls.any((c) => c.path.endsWith('/payments/1191/invoice')), isTrue);
    });

    testWidgets('a pending invoice (409) and a child no longer linked (403)', (t) async {
      await paSetUp(paApi(extra: wireParentRoutes(notLinked: paReem)));
      await _host(t, paRole(const PaInvoicePage(childId: paFaisal, paymentId: 1172)));
      expect(find.text('pa_invoice_not_ready'.tr), findsOneWidget);
      await _host(t, paRole(const ParentPaymentsPage()));
      expect(find.text('pa_pay_not_linked'.tr), findsOneWidget);
    });

    testWidgets('kill switch parent.payments', (t) async {
      AppConfig.disableList = [kParentPaymentsKey];
      await paSetUp(paApi(extra: wireParentRoutes()));
      await _host(t, paRole(const ParentPaymentsPage()));
      expect(find.byType(PaInvoiceView), findsNothing);
      expect(find.byKey(const ValueKey('pa.pay.1191')), findsNothing);
    });
  });

  group('games nickname (WP4)', () {
    Widget editor({int lockedDays = 0, String? error, String text = 'صقر الأرقام'}) => NicknameEditor(
          me: GamesNickname.fromJson(wireNickname(lockedDays: lockedDays)),
          controller: TextEditingController(text: text),
          icon: 'bolt',
          color: 'y',
          suggestions: const ['نسر نجد', 'برق الحساب', 'نجم المعادلات', 'فارس الحروف', _long],
          fieldError: error,
          onSave: () {},
        );

    testWidgets('layout: open, locked, with an error', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: editor()));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: editor(lockedDays: 9, text: _long)));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: editor(error: 'sd_nick_contact'.tr)));
    });

    testWidgets('the lock hides the suggestions and makes the name read-only', (t) async {
      await _host(t, SingleChildScrollView(child: editor(lockedDays: 9)));
      expect(find.byKey(const ValueKey('games.nick.s.نسر نجد')), findsNothing);
      expect(find.byKey(const ValueKey('games.nick.icon.star')), findsOneWidget);
    });

    testWidgets('the sheet: 5 suggestions, a 422 reason inline, a 409 swaps the suggestions', (t) async {
      final api = FakeApi(wireNicknameRoutes(), latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      await paSetUp(api);
      await _host(t, Builder(builder: (context) => Center(child: TextButton(onPressed: () => showNicknameSheet(context), child: const Text('open')))));
      await t.tap(find.text('open'));
      await _settle(t);
      expect(find.byKey(const ValueKey('games.nick.s.برق الحساب')), findsOneWidget);
      await t.enterText(find.byType(TextField), 'صقر 12345');
      await t.tap(find.byKey(const ValueKey('games.nick.save')));
      await _settle(t);
      expect(find.text('sd_nick_contact'.tr), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('games.nick.s.نسر نجد')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('games.nick.save')));
      await _settle(t);
      expect(find.text('sd_nick_taken'.tr), findsOneWidget);
      expect(find.byKey(const ValueKey('games.nick.s.نسر الجنوب')), findsOneWidget);
      final put = api.calls.where((c) => c.method == 'PUT').toList();
      expect(put, hasLength(2));
    });
  });

  group('teacher booking slots', () {
    final catalog = EduCountryCatalog.fromJson(paCatalog());
    List<TeacherSlot> slots() => [for (final s in [wireSlot(90), wireSlot(91, day: 3, hour: 18, status: 'taken'), wireSlot(93, subject: 999, grade: null)]) TeacherSlot.tryParse(s)!];

    testWidgets('layout: times, none, the form', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: TeacherSlotsView(slots: slots(), catalog: catalog, onAdd: () {}, onRemove: (_) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: TeacherSlotsView(slots: const [], catalog: catalog, onAdd: () {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: TeacherSlotForm(catalog: catalog)));
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: TeacherSlotForm()));
    });

    testWidgets('a booked time has no remove button', (t) async {
      await _host(t, SingleChildScrollView(child: TeacherSlotsView(slots: slots(), catalog: catalog, onRemove: (_) {})));
      expect(find.byKey(const ValueKey('t2.slot.90.remove')), findsOneWidget);
      expect(find.byKey(const ValueKey('t2.slot.91.remove')), findsNothing);
    });

    testWidgets('the page reads GET /booking/teacher/slots', (t) async {
      final api = FakeApi(wireSlotRoutes(), latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      await paSetUp(api);
      await _host(t, const TeacherBookingSlotsPage());
      expect(api.calls.any((c) => c.method == 'GET' && c.path == '/api/v1/booking/teacher/slots'), isTrue);
      expect(find.byKey(const ValueKey('t2.slot.90')), findsOneWidget);
    });
  });
}
