// Requests for someone else, attachments and the approval chain (D-140 / D-141): every new presentational widget
// lays out at 320×640 and 1400×900, in Arabic and English, with text scale 1.3 — the submit form with the "For"
// section (a member picked, an outside person with field errors), the chain preview, the item page with the
// beneficiary rows, the chain card (current step, earlier round) and the resubmit / export actions, the chain
// editor, the attachment chips and the image preview's frame.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_item_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_items_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_member_pages.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_request_parts.dart';
import 'package:flutter_education_app/features/org/governance/gov_ui.dart' show askGovNote;
import 'package:flutter_test/flutter_test.dart';

import '../org/gov_filter_test.dart' show sampleEntityJson;
import '../org/gov_requests_test.dart' show sampleRequestItemJson;
import 'layout_harness.dart';

Entity _entity() => Entity.fromJson({
      ...sampleEntityJson(),
      'can_submit_for_others': true,
      'chain': [
        {'kind': 'manager', 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
        {'kind': 'entity', 'dept_id': 2, 'label_ar': 'شؤون الطلاب والخريجين', 'label_en': 'Student and graduate affairs'},
        {'kind': 'council', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
      ],
    });

GovForControllers _external() => GovForControllers()
  ..name.text = 'منى سعيد عبد الرحمن'
  ..relation.text = 'ولية أمر'
  ..phone.text = 'abc'
  ..email.text = 'mona@example.com'
  ..nationalId.text = '12'
  ..studentNumber.text = '2021/0042';

Widget _form({required String kind, GovForControllers? ctl, Map<String, String> errors = const {}, GovPerson? member}) {
  final title = TextEditingController(text: 'شهادة قيد لولي أمر طالب — a title that wraps'), body = TextEditingController(text: 'Details');
  final e = _entity();
  return GovSubmitForm(
    entities: [e],
    entity: e,
    category: null,
    type: 'request',
    title: title,
    body: body,
    priority: 'medium',
    anonymous: false,
    attachments: WorkItem.fromJson(sampleRequestItemJson()).attachments,
    onEntity: (_) {},
    onCategory: (_) {},
    onType: (_) {},
    onPriority: (_) {},
    onAnonymous: (_) {},
    onAddAttachment: () {},
    onRemoveAttachment: (_) {},
    onSubmit: () {},
    forOthers: kind != 'self',
    forWho: GovForSection(
      kind: kind,
      member: member,
      controllers: ctl ?? GovForControllers(),
      errors: errors,
      onKind: (_) {},
      onPickMember: () {},
      onClearMember: () {},
    ),
  );
}

void main() {
  testWidgets('GovSubmitForm with the For section: me · a member · an outside person with errors', (tester) async {
    final ctl = _external();
    final draft = BeneficiaryDraft(kind: 'external');
    ctl.fill(draft);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _form(kind: 'self'),
          const Divider(height: 32),
          _form(kind: 'member', member: const GovPerson(id: 9, name: 'سارة أحمد محمود عبد الله — a long member name')),
          const Divider(height: 32),
          _form(kind: 'external', ctl: ctl, errors: draft.validate()),
        ]),
      ),
    );
  });

  testWidgets('GovItemBody: beneficiary, chain with an earlier round, export (staff) and resubmit (member)', (tester) async {
    final staff = WorkItem.fromJson(sampleRequestItemJson());
    final rejected = WorkItem.fromJson({
      ...sampleRequestItemJson(),
      'status': 'rejected',
      'decision': {'outcome': 'rejected', 'by': {'id': 7, 'name': 'Dr. Omar'}, 'at': '2026-10-31T09:00:00', 'note': 'Missing the signed form', 'via': 'head'},
      'pending_route': null,
      'can': {'view': true, 'comment': true, 'resubmit': true},
    });
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        Expanded(child: GovItemBody(item: staff, currentUserId: 7, onDecide: (_) {}, onRoute: () {}, onStatus: () {}, onExport: () {}, onOpenAttachment: (_) {})),
        Expanded(child: GovItemBody(item: rejected, member: true, currentUserId: 9, onResubmit: () {}, onOpenAttachment: (_) {})),
      ]),
    );
  });

  testWidgets('GovItemCard with the beneficiary and the chain step', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        GovItemCard(item: WorkItem.fromJson(sampleRequestItemJson()), onTap: () {}),
        GovItemCard(item: WorkItem.fromJson(sampleRequestItemJson()), selectMode: true, selected: true, onTap: () {}),
      ]),
    );
  });

  testWidgets('GovChainEditor (empty, three steps with an error) · GovChainPreview · GovAttachmentChips · GovImagePreview frame', (tester) async {
    final es = [Entity.fromJson(sampleEntityJson(kind: 'service', id: 2)), Entity.fromJson(sampleEntityJson(kind: 'office', id: 3))];
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          GovChainEditor(steps: const [], entities: es, hasCouncil: true, onChanged: (_) {}),
          const SizedBox(height: 16),
          GovChainEditor(
            steps: const [ChainStep(kind: 'manager'), ChainStep(kind: 'entity', deptId: 2), ChainStep(kind: 'faculty_council')],
            entities: es,
            hasCouncil: true,
            errorIndex: 2,
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          GovChainEditor(steps: const [ChainStep(kind: 'manager'), ChainStep(kind: 'council')], entities: es, canEdit: false, onChanged: (_) {}),
          const SizedBox(height: 16),
          GovChainPreview(steps: _entity().chain),
          const SizedBox(height: 16),
          GovAttachmentChips(attachments: WorkItem.fromJson(sampleRequestItemJson()).attachments, onOpen: (_) {}, onRemove: (_) {}),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: GovImagePreview(attachment: WorkItem.fromJson(sampleRequestItemJson()).attachments[1], url: 'https://storage.invalid/x.png'),
          ),
        ]),
      ),
    );
  });

  group('QA: the chain after it stopped · the rejection reason', () {
    setUp(() => AppConfig.lang = 'en');

    Future<void> pumpChain(WidgetTester tester, List<String> statuses, {String? itemStatus}) => tester.pumpWidget(layoutHost(
          SingleChildScrollView(
            child: GovChainCard(
              chain: ItemChain(current: 1, steps: [for (final s in statuses) ChainStep(kind: 'entity', labelEn: 'Step', labelAr: 'خطوة', status: s)]),
              itemStatus: itemStatus,
            ),
          ),
          scale: 1,
        ));

    testWidgets('still moving: the current step and the waiting ones', (tester) async {
      await pumpChain(tester, ['approved', 'current', 'waiting'], itemStatus: 'in_review');
      expect(find.text('Current step'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Not reached'), findsNothing);
    });

    testWidgets('rejected at step 2: the step after it is not reached, not waiting', (tester) async {
      await pumpChain(tester, ['approved', 'rejected', 'waiting'], itemStatus: 'rejected');
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Not reached'), findsOneWidget);
      expect(find.text('Waiting'), findsNothing);
      // a rejection in the chain is enough, whatever the item status the server sent
      await pumpChain(tester, ['rejected', 'waiting', 'waiting']);
      expect(find.text('Not reached'), findsNWidgets(2));
    });

    for (final status in ['withdrawn', 'closed']) {
      testWidgets('$status mid-chain: the current step stopped there, the rest not reached', (tester) async {
        await pumpChain(tester, ['approved', 'current', 'waiting'], itemStatus: status);
        expect(find.text('Current step'), findsNothing);
        expect(find.text('Stopped here'), findsOneWidget);
        expect(find.text('Not reached'), findsOneWidget);
        AppConfig.lang = 'ar';
        await pumpChain(tester, ['approved', 'current', 'waiting'], itemStatus: status);
        expect(find.text('توقّفت هنا'), findsOneWidget);
        expect(find.text('لم تُبلَغ'), findsOneWidget);
      });
    }

    testWidgets('a reason too short keeps the sheet open with what was typed and says why', (tester) async {
      String? result;
      var closed = false;
      await tester.pumpWidget(layoutHost(
        Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () async {
                result = await askGovNote(ctx, title: 'Reject', confirmLabel: 'Reject it', required: true, minLength: 3, tooShort: 'Too short');
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
        scale: 1,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reject it'));
      await tester.pumpAndSettle();
      expect(closed, isFalse, reason: 'an empty reason keeps the sheet open');
      expect(find.text('Too short'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(find.text('Too short'), findsNothing, reason: 'typing clears the error');
      await tester.tap(find.text('Reject it'));
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(find.text('Too short'), findsOneWidget);
      expect(find.text('ab'), findsOneWidget, reason: 'what was typed is still there');

      await tester.enterText(find.byType(TextField), 'ab — missing form');
      await tester.tap(find.text('Reject it'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, 'ab — missing form');
    });
  });
}
