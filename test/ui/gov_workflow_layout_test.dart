// Forwarding after approval (D-890) and external requests (D-891): the forward form for each target, the
// "forwarded to you" card, the forward lines in the routes chain and the item page of an approved external request
// lay out at 320×640 and 1400×900, in Arabic and English, with text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/governance/gov_forward_sheet.dart';
import 'package:flutter_education_app/features/org/governance/gov_item_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/gov_workflow_test.dart' show sampleForwardedItemJson;
import 'layout_harness.dart';

Widget _form(String to, {String? error}) => GovForwardForm(
      to: to,
      person: const GovUser(id: 9, name: 'سارة أحمد محمود عبد الله — a long member name'),
      actions: const ['review', 'execute'],
      externalName: TextEditingController(text: 'وزارة التعليم العالي والبحث العلمي'),
      externalOrg: TextEditingController(),
      externalRef: TextEditingController(text: 'OUT-12'),
      note: TextEditingController(text: 'مرفق قرار المجلس'),
      dueAt: DateTime.utc(2026, 11, 20, 9),
      councilName: 'مجلس كلية الحاسبات والمعلومات',
      error: error,
      onTo: (_) {},
      onPickPerson: () {},
      onToggleAction: (_) {},
      onDue: (_) {},
      onSubmit: () {},
    );

void main() {
  testWidgets('GovForwardForm: person (with an error) · outside party · higher council', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _form('user', error: 'Choose the required action ("for information only" stands alone)'),
          const Divider(height: 32),
          _form('external'),
          const Divider(height: 32),
          _form('council'),
        ]),
      ),
    );
  });

  testWidgets('GovItemBody of an approved external request: forward action, task card, forward lines', (tester) async {
    final it = WorkItem.fromJson(sampleForwardedItemJson());
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        Expanded(child: GovItemBody(item: it, currentUserId: 7, onForward: () {}, onAnswerRoute: (_) {}, onOpenAttachment: (_) {})),
        Expanded(child: GovItemBody(item: it, member: true, currentUserId: 9, onAnswerRoute: (_) {}, onOpenAttachment: (_) {})),
      ]),
    );
  });

  testWidgets('GovForwardTaskCard and GovForwardDetails alone', (tester) async {
    final it = WorkItem.fromJson(sampleForwardedItemJson());
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        GovForwardTaskCard(route: it.routes.first, busy: false, onRespond: () {}),
        GovForwardDetails(forward: it.routes.first.forward!),
        GovForwardDetails(forward: it.routes.last.forward!),
      ]),
    );
  });
}
