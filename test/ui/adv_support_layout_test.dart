// The Phase 7 advising screens must lay out at every size and language (320×640 · 1400×900, ar · en, text scale 1.3):
// every presentational view in every state — the request list (director · advisor · empty · filtered · loading ·
// offline · failed · server update), the request page (at a council with its agenda, waiting on information,
// approved and closed, rejected, a draft, a referral, loading / failed), the stage tracker (both layouts), the
// composer (support with accommodations and the chain preview, referral, no service departments, editing a draft,
// restored with an error), the review / answer / resubmit / note sheets, the chain editor (organization, a program
// that inherits, a faculty council the organization lacks, empty), plans (active · completed · draft · the
// student's), the plan editor and status sheet, accommodations (card · grant · the organization's list), the 360's
// Support block (full · empty · loading) and inside the 360, the student hub blocks, the student's request and the
// advising page's links.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/advising/adv_accommodations.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_plan.dart';
import 'package:flutter_education_app/features/org/advising/adv_request_chain_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_request_composer.dart';
import 'package:flutter_education_app/features/org/advising/adv_requests.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_360.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_hub.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_parts.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart' show GovAttachment;
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_case_models_test.dart' show advCaseNow, sampleAdvProfileJson;
import '../org/adv_models_test.dart' show sampleAdvStatusJson;
import '../org/adv_support_models_test.dart';
import 'layout_harness.dart';

const _err = 'The server could not be reached. Check the connection and try again.';

AdvRequest _req({String stage = 'at_department_council', String kind = 'support'}) => AdvRequest.fromJson(sampleAdvRequestJson(stage: stage, kind: kind));
AdvRequestOptions get _options => AdvRequestOptions.fromJson(sampleAdvRequestOptionsJson());
AdvChainConfig _chain({bool faculty = true, int councils = 6}) => AdvChainConfig.fromJson(sampleAdvChainJson(faculty: faculty, departmentCouncils: councils));
AdvSupportPlan _plan([String status = 'active']) => AdvSupportPlan.fromJson(sampleAdvPlanJson(status: status));
List<AdvAccommodationGrant> get _accs => [for (final m in sampleAdvAccommodationsJson()) AdvAccommodationGrant.fromJson(m)];

Widget _sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

AdvRequestsView _list({AdvLoad load = AdvLoad.ready, bool manage = true, AdvPage<AdvRequest>? page, AdvRequestQuery query = const AdvRequestQuery()}) => AdvRequestsView(
      load: load,
      query: query,
      manage: manage,
      page: load == AdvLoad.ready ? (page ?? AdvPage.fromJson(sampleAdvRequestsJson(), AdvRequest.fromJson)) : null,
      errorText: _err,
      onRetry: () {},
      onQueue: (_) {},
      onFilter: (_) {},
      onSearch: (_) {},
      onPage: (_) {},
      onOpen: (_) {},
      onNew: () {},
    );

AdvRequestView _page(AdvRequest? r, {AdvLoad load = AdvLoad.ready}) =>
    AdvRequestView(load: load, request: r, errorText: _err, onRetry: () {}, onAction: (_) {}, onOpenStudent: () {}, onOpenAttachment: (_) {});

AdvRequestForm _form({AdvRequestDraft? draft, AdvRequestOptions? options, bool editing = false, bool restored = false, String? error, bool loadingPreview = false}) => AdvRequestForm(
      options: options ?? _options,
      draft: draft ??
          const AdvRequestDraft(supportType: 'accommodation', categoryId: 7, accommodations: ['extra_time', 'front_seating'], priority: 'high', templateId: 5, attachments: [
            GovAttachment(name: 'medical_report.pdf', id: 71, ext: 'pdf', size: 248000),
          ]),
      title: TextEditingController(text: 'تسهيلات امتحانات الفصل الأول بسبب ضعف السمع'),
      body: TextEditingController(text: 'The student has had hearing loss since September; the medical report is attached.'),
      studentName: 'ليلى أحمد',
      editing: editing,
      preview: AdvChainPreview.fromJson(sampleAdvChainPreviewJson()),
      previewLoading: loadingPreview,
      restored: restored,
      savedOnDevice: true,
      error: error,
      onKind: (_) {},
      onType: (_) {},
      onTarget: (_) {},
      onCategory: (_) {},
      onPriority: (_) {},
      onAccommodation: (_) {},
      onPickUntil: () {},
      onClearUntil: () {},
      onTemplate: (_) {},
      onAttach: () {},
      onOpenAttachment: (_) {},
      onRemoveAttachment: (_) {},
      onSaveDraft: () {},
      onSubmit: () {},
    );

AdvChainEditorView _editor({AdvChainConfig? config, bool inherit = false, List<AdvChainStep>? steps, String? error}) {
  final c = config ?? _chain();
  const org = AdvChainScopeChoice(type: 'org', label: 'Organization');
  const prog = AdvChainScopeChoice(type: 'program', ref: '11', label: 'Program: Software Engineering');
  return AdvChainEditorView(
    config: c,
    scopes: const [org, prog],
    scope: inherit ? prog : org,
    steps: steps ?? c.orgSteps,
    inherit: inherit,
    dirty: true,
    error: error,
    onScope: (_) {},
    onAddScope: () {},
    onInherit: (_) {},
    onReset: () {},
    onAdd: (_) {},
    onMove: (_, _) {},
    onRemove: (_) {},
    onSave: () {},
    onPreview: () {},
  );
}

AdvSupportPane _pane({AdvLoad load = AdvLoad.ready, bool empty = false}) => AdvSupportPane(
      load: load,
      summary: load == AdvLoad.ready ? AdvSupportSummary.fromJson(sampleAdvSupportJson(empty: empty)) : null,
      plans: empty ? null : [_plan(), _plan('draft'), _plan('completed')],
      errorText: _err,
      ticking: const {3},
      onRetry: () {},
      onNewRequest: () {},
      onRefer: () {},
      onNewPlan: () {},
      onGrant: () {},
      onOpenRequest: (_) {},
      onSeeAll: () {},
      onTickItem: (_, _) {},
      onEditPlan: (_) {},
      onPlanStatus: (_) {},
      onDeletePlan: (_) {},
      onEndAccommodation: (_) {},
    );

void main() {
  group('requests', () {
    testWidgets('the list: a director, an advisor, empty, filtered and every load state', (tester) async {
      await expectNoLayoutErrors(tester, () => _list());
      await expectNoLayoutErrors(tester, () => _list(manage: false, query: const AdvRequestQuery(mine: true)));
      await expectNoLayoutErrors(tester, () => _list(page: const AdvPage(), query: const AdvRequestQuery(queue: 'review')));
      await expectNoLayoutErrors(tester, () => _list(page: const AdvPage(), query: const AdvRequestQuery(filter: 'kind:referral', q: 'x')));
      for (final l in [AdvLoad.loading, AdvLoad.offline, AdvLoad.failed, AdvLoad.missing]) {
        await expectNoLayoutErrors(tester, () => _list(load: l));
      }
    });

    testWidgets('the request page at every moment', (tester) async {
      for (final s in ['at_department_council', 'needs_info', 'approved', 'closed', 'rejected', 'draft', 'submitted']) {
        await expectNoLayoutErrors(tester, () => _page(_req(stage: s)));
      }
      await expectNoLayoutErrors(tester, () => _page(AdvRequest.fromJson({...sampleAdvRequestJson(stage: 'in_progress', kind: 'referral'), 'chain': null, 'step': null})));
      await expectNoLayoutErrors(tester, () => _page(AdvRequest.fromJson(const {'id': 1})));
      await expectNoLayoutErrors(tester, () => _page(null, load: AdvLoad.loading));
      await expectNoLayoutErrors(tester, () => _page(null, load: AdvLoad.failed));
    });

    testWidgets('the stage tracker, horizontal and vertical, and the dots', (tester) async {
      await expectNoLayoutErrors(tester, () => _sheet(Column(children: [
            AdvStageTrack(points: _req().track),
            const SizedBox(height: 24),
            AdvStageTrack(points: _req(stage: 'closed').track, forceVertical: true),
            const SizedBox(height: 24),
            AdvStageTrack(points: _req(stage: 'needs_info').track),
            const SizedBox(height: 24),
            AdvTrackDots(points: _req(stage: 'rejected').track),
          ])));
    });

    testWidgets('the composer: support, referral, no departments, editing, restored with an error', (tester) async {
      await expectNoLayoutErrors(tester, () => _sheet(_form()));
      await expectNoLayoutErrors(tester, () => _sheet(_form(draft: const AdvRequestDraft(kind: 'referral', targetDeptId: 41, priority: 'urgent'))));
      await expectNoLayoutErrors(tester, () => _sheet(_form(draft: const AdvRequestDraft(kind: 'referral'), options: AdvRequestOptions.fromJson({...sampleAdvRequestOptionsJson(), 'referral_targets': <Map<String, dynamic>>[]}))));
      await expectNoLayoutErrors(tester, () => _sheet(_form(editing: true, loadingPreview: true)));
      await expectNoLayoutErrors(tester, () => _sheet(_form(restored: true, error: _err, draft: const AdvRequestDraft(supportType: 'exam_excuse'))));
    });

    testWidgets('the review, answer, resubmit and note sheets', (tester) async {
      await expectNoLayoutErrors(tester, () => _sheet(AdvReviewForm(request: _req(stage: 'submitted'), note: TextEditingController(text: 'Attach the hospital report.'), decision: 'needs_info', error: _err, onDecision: (_) {}, onSubmit: () {})));
      await expectNoLayoutErrors(tester, () => _sheet(AdvReviewForm(request: _req(), note: TextEditingController(), decision: 'approve', onDecision: (_) {}, onSubmit: () {})));
      final info = _req(stage: 'needs_info');
      await expectNoLayoutErrors(tester, () => _sheet(AdvInfoAnswerForm(
            info: info.info!,
            answer: TextEditingController(text: 'التقرير مرفق.'),
            attachments: info.attachments,
            uploading: true,
            error: _err,
            onAttach: () {},
            onRemoveAttachment: (_) {},
            onSubmit: () {},
          )));
      final no = _req(stage: 'rejected');
      await expectNoLayoutErrors(tester, () => _sheet(AdvResubmitForm(
            title: TextEditingController(text: no.title),
            body: TextEditingController(text: no.body),
            note: TextEditingController(),
            reason: no.outcomeNote,
            attachments: no.attachments,
            onAttach: () {},
            onRemoveAttachment: (_) {},
            onSubmit: () {},
          )));
      await expectNoLayoutErrors(tester, () => _sheet(AdvNoteSheetForm(note: TextEditingController(), label: 'Follow-up note (required)', action: 'Close the case', intro: 'The decision stays.', required: true, error: _err, onSubmit: () {})));
    });
  });

  group('the chain editor', () {
    testWidgets('organization, an inheriting program, no faculty council, no councils, empty', (tester) async {
      await expectNoLayoutErrors(tester, () => _editor());
      await expectNoLayoutErrors(tester, () => _editor(inherit: true));
      await expectNoLayoutErrors(tester, () => _editor(config: _chain(faculty: false, councils: 0), error: _err));
      await expectNoLayoutErrors(tester, () => _editor(steps: const []));
      await expectNoLayoutErrors(tester, () => _sheet(AdvChainPreviewList(steps: AdvChainPreview.fromJson(sampleAdvChainPreviewJson()).steps, advisingDept: 'الإرشاد الأكاديمي')));
    });
  });

  group('plans and accommodations', () {
    testWidgets('plan cards: active, completed, draft, the student\'s own', (tester) async {
      await expectNoLayoutErrors(tester, () => _sheet(Column(children: [
            AdvPlanCard(plan: _plan(), canTick: (_) => true, ticking: const {3}, onTick: (_) {}, onEdit: () {}, onStatus: () {}, onReview: () {}),
            AdvPlanCard(plan: _plan('completed'), onStatus: () {}),
            AdvPlanCard(plan: _plan('draft'), onEdit: () {}, onStatus: () {}, onDelete: () {}),
            AdvPlanCard(plan: _plan(), student: true, canTick: (i) => i.owner == 'student', onTick: (_) {}),
          ])));
    });

    testWidgets('the plan editor and the status sheet', (tester) async {
      final p = _plan();
      final items = [for (final i in p.items) AdvPlanItemFields.of(i)];
      await expectNoLayoutErrors(tester, () => _sheet(AdvPlanForm(
            title: TextEditingController(text: p.title),
            draft: AdvPlanDraft.of(p),
            target: TextEditingController(text: '2.30'),
            measureText: TextEditingController(),
            items: items,
            error: _err,
            onMeasureKind: (_) {},
            onPickFollowUp: () {},
            onClearFollowUp: () {},
            onVisible: (_) {},
            onOwner: (_, _) {},
            onPickDue: (_) {},
            onClearDue: (_) {},
            onAddItem: () {},
            onRemoveItem: (_) {},
            onSaveDraft: () {},
            onSave: () {},
          )));
      await expectNoLayoutErrors(tester, () => _sheet(AdvPlanForm(
            title: TextEditingController(),
            draft: const AdvPlanDraft(measure: AdvPlanMeasure(kind: 'custom')),
            target: TextEditingController(),
            measureText: TextEditingController(text: 'Finish the internship report'),
            items: [AdvPlanItemFields()],
            editing: true,
            onSave: () {},
          )));
      await expectNoLayoutErrors(tester, () => _sheet(AdvPlanReviewForm(plan: p, note: TextEditingController(text: 'On track.'), next: DateTime(2026, 12, 4), error: _err, onPickNext: () {}, onClearNext: () {}, onSubmit: () {})));
      await expectNoLayoutErrors(tester, () => _sheet(AdvPlanStatusForm(plan: p, outcome: TextEditingController(text: 'GPA 2.48'), chosen: 'completed', error: _err, onChoose: (_) {}, onSubmit: () {})));
    });

    testWidgets('accommodations: cards, the grant sheet, the organization\'s list', (tester) async {
      await expectNoLayoutErrors(tester, () => _sheet(Column(children: [
            for (final a in _accs) AdvAccommodationCard(accommodation: a, onEnd: () {}),
            AdvAccommodationCard(accommodation: _accs.first, student: true),
            AdvAccommodationCard(accommodation: _accs.first, showStudent: true, onOpenStudent: () {}),
          ])));
      final cats = AdvRequestOptions.fromJson(sampleAdvRequestOptionsJson()).categories;
      await expectNoLayoutErrors(tester, () => _sheet(AdvGrantForm(
            categories: advGrantCategories(cats),
            draft: AdvGrantDraft(categoryId: 7, keys: const ['recorded_lectures'], startsOn: DateTime(2026, 11, 3), endsOn: DateTime(2027, 1, 31)),
            note: TextEditingController(),
            activeKeys: const {'extra_time'},
            error: _err,
            onCategory: (_) {},
            onKey: (_) {},
            onPickStart: () {},
            onClearStart: () {},
            onPickEnd: () {},
            onClearEnd: () {},
            onSubmit: () {},
          )));
      final page = AdvPage(items: _accs, total: 2);
      await expectNoLayoutErrors(tester, () => AdvAccommodationsView(load: AdvLoad.ready, page: page, onStatus: (_) {}, onSearch: (_) {}, onOpen: (_) {}));
      await expectNoLayoutErrors(tester, () => AdvAccommodationsView(load: AdvLoad.ready, page: const AdvPage(), onStatus: (_) {}, onSearch: (_) {}));
      await expectNoLayoutErrors(tester, () => AdvAccommodationsView(load: AdvLoad.loading, onStatus: (_) {}));
    });
  });

  group('the 360, the student and the entry', () {
    testWidgets('the Support block: full, empty, loading', (tester) async {
      await expectNoLayoutErrors(tester, () => _sheet(_pane()));
      await expectNoLayoutErrors(tester, () => _sheet(_pane(empty: true)));
      await expectNoLayoutErrors(tester, () => _sheet(_pane(load: AdvLoad.failed)));
    });

    testWidgets('the 360 on its Support section', (tester) async {
      await expectNoLayoutErrors(tester, () => AdvStudentView(
            load: AdvLoad.ready,
            profile: AdvCaseProfile.fromJson(sampleAdvProfileJson()),
            section: 'support',
            now: advCaseNow,
            onSection: (_) {},
            support: _pane(),
          ));
    });

    testWidgets('the student hub blocks and the student\'s request', (tester) async {
      final m = AdvMemberSupport.fromJson(sampleAdvMemberSupportJson());
      await expectNoLayoutErrors(tester, () => _sheet(Column(children: [
            AdvHubRequestsSection(requests: m.requests, onOpen: (_) {}, first: true),
            AdvHubPlansSection(plans: m.plans, ticking: const {3}, onTick: (_, _) {}),
            AdvHubAccommodationsSection(accommodations: m.accommodations),
          ])));
      await expectNoLayoutErrors(tester, () => _sheet(const Column(children: [
            AdvHubRequestsSection(requests: []),
            AdvHubPlansSection(plans: []),
            AdvHubAccommodationsSection(accommodations: []),
          ])));
      for (final s in ['at_department_council', 'approved']) {
        await expectNoLayoutErrors(tester, () => AdvStudentRequestView(load: AdvLoad.ready, request: AdvStudentRequest.fromJson(sampleAdvStudentRequestJson(stage: s))));
      }
      await expectNoLayoutErrors(tester, () => AdvStudentRequestView(load: AdvLoad.offline, errorText: _err, onRetry: () {}));
    });

    testWidgets('the advising page shows Requests, the chain and accommodations with their counts', (tester) async {
      await expectNoLayoutErrors(tester, () => AdvSetupView(
            state: AdvSetupState.on,
            deptName: 'Academic Advising',
            status: AdvStatus.fromJson({
              ...sampleAdvStatusJson(admin: false, director: true, advisor: true),
              'me': {'admin': false, 'director': true, 'advisor': true, 'advisees': 12, 'requests_review': 3, 'requests_needs_info': 1, 'requests_overdue': 2},
            }),
            onOpen: (_) {},
            onDisable: () {},
          ));
    });
  });
}
