// Admin points page (live-rooms-spec §9): the plain-values tabs at 320x640 and 1400x900, Arabic + English,
// textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart' show AppSwitch;
import 'package:flutter_education_app/features/admin/admin_points_page.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'عبد الرحمن بن عبد العزيز آل عبد الله الطويل جداً للاختبار';
const longEn = 'Abdulrahman bin Abdulaziz Al Abdullah, a very long name for testing';

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

List<PointsTopup> topups() => PointsTopup.sorted(PointsTopup.listFrom([
      for (final st in ['approved', 'pending', 'rejected', 'pending'])
        {
          'id': st.length + 1,
          'points': 1000000,
          'amount': 1250000.75,
          'currency': 'SAR',
          'method': 'bank_transfer',
          'status': st,
          'note': st == 'rejected' ? '$longAr $longEn' : null,
          'created_at': iso(DateTime.now()),
          'user': {'id': 3, 'name': '$longAr $longEn', 'email': 'someone.with.a.long.address@example-university.edu.sa', 'phone': '+966500000000'},
        }
    ]));

/// Part 3 §13: card top-ups next to transfers — read-only, with the provider and the payment id.
List<PointsTopup> mixedTopups() => PointsTopup.sorted(PointsTopup.listFrom({
      'items': [
        for (final st in ['pending', 'approved', 'rejected'])
          {
            'id': {'pending': 101, 'approved': 102, 'rejected': 103}[st],
            'points': 1000000,
            'amount': 1250000.75,
            'currency': 'SAR',
            'method': 'card',
            'provider': 'paymob',
            'payment_id': 'pm_0123456789abcdef0123456789abcdef0123456789',
            'has_receipt': false,
            'status': st,
            'note': st == 'rejected' ? '$longAr $longEn' : null,
            'created_at': iso(DateTime.now()),
            'user': {'id': 3, 'name': '$longAr $longEn', 'email': 'someone.with.a.long.address@example-university.edu.sa'},
          },
        {
          'id': 7,
          'points': 50,
          'amount': 50,
          'currency': 'SAR',
          'method': 'bank_transfer',
          'has_receipt': true,
          'status': 'pending',
          // older: the transfer is the first row (pending, oldest first), the pending card row second
          'created_at': iso(DateTime.now().subtract(const Duration(days: 1))),
          'user': {'id': 4, 'name': longEn},
        },
      ]
    }));

List<PointsUserRow> users() => [
      for (var i = 0; i < 4; i++)
        PointsUserRow(
            user: PointsUser(id: i, name: '$longAr $longEn $i', email: 'user$i.long.address@example-university.edu.sa', phone: '+966500000000'),
            balance: 9999999),
    ];

List<PointsLedgerEntry> ledger() => [
      for (final k in ['grant', 'deduct', 'topup', 'spend', 'refund'])
        PointsLedgerEntry(
            id: k.length,
            delta: k == 'deduct' || k == 'spend' ? -99999 : 99999,
            balanceAfter: 9999999,
            kind: k,
            note: '$longAr $longEn',
            byName: longEn,
            createdAt: DateTime.now().toUtc()),
    ];

void main() {
  group('top-ups', () {
    testWidgets('loading', (tester) async {
      await expectNoLayoutErrors(tester, () => const AdminTopupsView(items: null));
    });

    testWidgets('error', (tester) async {
      await expectNoLayoutErrors(tester, () => AdminTopupsView(items: null, error: '$longAr $longEn', onRetry: () {}));
    });

    testWidgets('empty', (tester) async {
      await expectNoLayoutErrors(tester, () => const AdminTopupsView(items: []));
    });

    testWidgets('pending first with actions, one busy', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => AdminTopupsView(
              items: topups(), filter: null, busyId: 5, onFilter: (_) {}, onApprove: (_) {}, onReject: (_) {}, onReceipt: (_) {}));
    });
  });

  group('Part 3: card top-ups are read-only', () {
    testWidgets('card rows: provider and payment id, no approve / reject / receipt', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => AdminTopupsView(items: mixedTopups(), filter: null, onFilter: (_) {}, onApprove: (_) {}, onReject: (_) {}, onReceipt: (_) {}),
        act: (t) async {
          // the pending card row (the rows below may not be built on a phone)
          expect(find.byKey(const ValueKey('admin_topup.card.101')), findsOneWidget);
          expect(find.byKey(const ValueKey('topup.payment_id.101')), findsOneWidget);
          // only the transfer can be approved and has a receipt
          int n(String en, String ar) => find.text(en).evaluate().length + find.text(ar).evaluate().length;
          expect(n('Approve', 'قبول'), 1);
          expect(n('Reject', 'رفض'), 1);
          expect(n('Receipt', 'الإيصال'), 1);
        },
      );
    });
  });

  group('users', () {
    testWidgets('loading', (tester) async {
      await expectNoLayoutErrors(tester, () => AdminPointsUsersView(search: TextEditingController(), rows: null));
    });

    testWidgets('list with more', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => AdminPointsUsersView(
              search: TextEditingController(text: longEn),
              rows: users(),
              total: 120,
              onMore: () {},
              onGrant: (_) {},
              onHistory: (_) {}));
    });

    testWidgets('no results', (tester) async {
      await expectNoLayoutErrors(tester, () => AdminPointsUsersView(search: TextEditingController(), rows: const []));
    });

    testWidgets('grant / deduct form, deduct over the balance', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: PointsGrantForm(
                user: PointsUser(id: 1, name: '$longAr $longEn'), balance: 5, submit: (_, _) async => 0)),
        act: (t) async {
          await t.tap(find.byIcon(Icons.remove_rounded).first); // the Deduct choice; the number field's stepper comes after it
          await t.pump();
          await t.enterText(find.byType(TextField).first, '999');
          await t.ensureVisible(find.byIcon(Icons.check_rounded).last);
          await t.tap(find.byIcon(Icons.check_rounded).last);
        },
      );
    });

    testWidgets('history', (tester) async {
      await expectNoLayoutErrors(tester, () => PointsHistoryView(items: ledger()));
      await expectNoLayoutErrors(tester, () => const PointsHistoryView(items: []));
      await expectNoLayoutErrors(tester, () => const PointsHistoryView(items: null));
    });
  });

  group('Part 3 settings', () {
    testWidgets('daily free minutes and the card switch', (tester) async {
      PointsSettings? saved;
      await expectNoLayoutErrors(
        tester,
        () => PointsSettingsForm(
            initial: const PointsSettings(freeMinutesDaily: 45, cardEnabled: true), save: (s) async => saved = s),
        act: (t) async {
          await t.scrollUntilVisible(find.byKey(const ValueKey('points_settings.card')), 200, scrollable: find.byType(Scrollable).first);
          await t.ensureVisible(find.byKey(const ValueKey('points_settings.card')));
          await t.pump();
          await t.tap(find.byType(AppSwitch));
          await t.pump();
          await t.scrollUntilVisible(find.byIcon(Icons.save_rounded), 200, scrollable: find.byType(Scrollable).first);
          await t.tap(find.byIcon(Icons.save_rounded));
          await t.pump();
          expect(saved!.cardEnabled, isFalse);
          expect(saved!.freeMinutesDaily, 45);
        },
      );
    });
  });

  group('settings', () {
    testWidgets('form with a validation error', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => PointsSettingsForm(initial: const PointsSettings(pointPrice: 1.25), save: (s) async => s),
        act: (t) async {
          await t.enterText(find.byType(TextField).at(0), '0');
          await t.pump();
          await t.scrollUntilVisible(find.byIcon(Icons.save_rounded), 200, scrollable: find.byType(Scrollable).first);
          await t.tap(find.byIcon(Icons.save_rounded));
        },
      );
    });
  });
}
