// Requests for someone else, attachments and the approval chain (D-140 / D-141): every new presentational widget
// lays out at 320×640 and 1400×900, in Arabic and English, with text scale 1.3 — the submit form with the "For"
// section (a member picked, an outside person with field errors), the chain preview, the item page with the
// beneficiary rows, the chain card (current step, earlier round) and the resubmit / export actions, the chain
// editor, the attachment chips and the image preview's frame.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/governance/gov_item_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_items_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_member_pages.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_request_parts.dart';
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
}
