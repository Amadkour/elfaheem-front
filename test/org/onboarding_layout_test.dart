// Member onboarding screens: no layout error at 320x640 and 1400x900, ar / en, textScaler 1.3 (the project rule).
// Data comes from a fake api (no network): the contract's sample payloads in test/fixtures/payloads/onboarding_*.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_api.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_models.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_page.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_review.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_types_page.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_wizard.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show OrgCall;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/$name.json').readAsStringSync())['payload'] as Map);

/// Answers from memory; every write succeeds.
class _FakeApi extends OnboardingApi {
  _FakeApi(this.caseJson, this.typeJson);
  final Map<String, dynamic> caseJson, typeJson;

  Map<String, dynamic> get _row => {...caseJson, 'type': null, 'documents': null, 'events': null};

  @override
  Future<OrgCall> types(int orgId) async => OrgCall([typeJson]);
  @override
  Future<OrgCall> presets(int orgId) async => OrgCall([
        {'key': 'egypt_public', 'label_ar': 'جامعة حكومية', 'label_en': 'Public university', 'types': ['student_new']},
      ]);
  @override
  Future<OrgCall> summary(int orgId) async => OrgCall({
        'counts': {'submitted': 2, 'under_review': 1, 'needs_correction': 1, 'draft': 3, 'active': 40},
        'overdue': 1,
        'by_type': <String, dynamic>{},
      });
  @override
  Future<OrgCall> cases(int orgId, {OnbStage? stage, String? status, String type = '', String q = '', bool overdue = false, int page = 1, int pageSize = 20}) async =>
      OrgCall({
        'items': [
          _row,
          {..._row, 'id': 42, 'full_name': 'فاطمة عبد الرحمن إبراهيم محمد السيد الشاذلي', 'status': 'submitted', 'overdue': true, 'conditional': true, 'phone': '+966501234567'},
          {..._row, 'id': 43, 'full_name': '', 'status': 'draft', 'nid_masked': '', 'missing_count': 6},
        ],
        'total': 3,
      });
  @override
  Future<OrgCall> getCase(int orgId, int id) async => OrgCall({...caseJson, 'type': typeJson});
  @override
  Future<OrgCall> createCase(int orgId, {required String typeKey, required Map<String, dynamic> fields, bool submit = false, bool approveNow = false}) async =>
      OrgCall({...caseJson, 'type': null});
  @override
  Future<OrgCall> patchCase(int orgId, int id, Map<String, dynamic> fields) async => OrgCall({...caseJson, 'type': null});
}

void main() {
  late Map<String, dynamic> typeJson, caseJson;
  late OnbType type;
  late OnbCase item;
  late _FakeApi api;

  setUp(() {
    typeJson = _fx('onboarding_type');
    caseJson = _fx('onboarding_case');
    type = OnbType.fromJson(typeJson);
    item = OnbCase.fromJson({...caseJson, 'type': typeJson});
    api = _FakeApi(caseJson, typeJson);
  });

  testWidgets('the admissions page: tabs, filter, cards', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => OnboardingPage(orgId: 4, api: api, can: (_, _) => true, live: false, places: const OnbPlaces()),
      frames: 6,
    );
  });

  testWidgets('the admissions page on every stage and empty', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => OnboardingPage(orgId: 4, api: api, can: (_, _) => false, live: false, initialStage: OnbStage.done),
      frames: 6,
    );
  });

  testWidgets('the case list states over plain values', (tester) async {
    await expectNoLayoutErrors(tester, () => const OnbCaseList(items: [], loading: true));
    await expectNoLayoutErrors(tester, () => const OnbCaseList(items: [], loading: false, filtered: true));
    await expectNoLayoutErrors(tester, () => OnbCaseList(items: [item, item], loading: false, total: 5, onOpen: (_) {}, selectedId: 41));
  });

  testWidgets('the Add dialog: one person, Excel and invite (disabled)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (c) => TextButton(onPressed: () => showOnbAddSheet(c, types: [type]), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('onb.add.one')), findsOneWidget);
        expect(find.byKey(const ValueKey('onb.add.excel')), findsOneWidget);
        expect(find.byKey(const ValueKey('onb.add.invite')), findsOneWidget);
      },
    );
  });

  for (var s = 0; s < 5; s++) {
    testWidgets('the wizard, step ${s + 1} of 5', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => OnbWizard(orgId: 4, type: type, api: api, places: const OnbPlaces(departments: {1: 'Computer science'}, programs: {7: 'Software'}), initialStep: s, canApproveNow: true),
      );
    });
  }

  testWidgets('the wizard continuing a case that needs correction (locked ID, documents, review)', (tester) async {
    final c = OnbCase.fromJson({...caseJson, 'status': 'needs_correction', 'type': typeJson});
    for (final step in [0, 3, 4]) {
      await expectNoLayoutErrors(
        tester,
        () => OnbWizard(orgId: 4, type: type, api: api, places: const OnbPlaces(), initial: c, mode: OnbMode.applicant, initialStep: step),
      );
    }
  });

  testWidgets('the wizard walks identity → personal on a valid ID and shows the governorate', (tester) async {
    final prevLang = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prevLang);
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(OnbWizard(orgId: 4, type: type, api: api, places: const OnbPlaces()), scale: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('onb.wizard.progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('onb.field.passport_no')), findsNothing, reason: 'conditional on a foreign nationality');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('onb.field.national_id')), matching: find.byType(TextField)), '30503140101234');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('onb.nid.governorate')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('onb.field.full_name')), matching: find.byType(TextField)), 'Ali Hassan');
    await tester.tap(find.byKey(const ValueKey('onb.wizard.next')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Step 2 of'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the document tile in every state', (tester) async {
    final photo = type.doc('photo')!, military = type.doc('military_form')!;
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        OnbDocTile(req: photo, required: true, onUpload: () {}),
        OnbDocTile(req: military, required: true, onUpload: () {}, onLater: () {}),
        OnbDocTile(req: military, required: true, later: true, onUpload: () {}, onLater: () {}),
        OnbDocTile(req: photo, required: true, busy: true, record: const OnbDocRecord(id: 1, reqKey: 'photo', fileName: 'a-very-long-file-name-of-a-scanned-photograph.jpg', size: 2400000)),
        OnbDocTile(req: photo, record: const OnbDocRecord(id: 1, reqKey: 'photo', status: 'rejected', note: 'Too dark: take it again in daylight'), onUpload: () {}),
      ]),
    );
  });

  testWidgets('the review view: data, documents, timeline, actions', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => OnbReviewView(item: item, onUnmask: () {}, onPreview: (_) {}, onDocAction: (_, _) {}, onApprove: () {}, onReject: () {}, onRequestCorrection: () {}, onClaim: () {}, onActivate: () {}),
    );
  });

  testWidgets('the review view: unmasked ID, rejected case, draft without type', (tester) async {
    await expectNoLayoutErrors(tester, () => OnbReviewView(item: item, unmasked: '30503140101234', busy: true, onApprove: () {}));
    final rejected = OnbCase.fromJson({...caseJson, 'type': typeJson, 'status': 'rejected', 'decision_reason': 'Duplicate application: this person already applied with the same national ID last week.', 'can': <String, dynamic>{}});
    await expectNoLayoutErrors(tester, () => OnbReviewView(item: rejected));
    await expectNoLayoutErrors(tester, () => OnbReviewView(item: OnbCase.fromJson({'id': 9, 'status': 'draft', 'can': {'edit': true}}), onEdit: () {}));
  });

  testWidgets('the review pane loads the case through the api', (tester) async {
    await expectNoLayoutErrors(tester, () => OnbReviewPane(orgId: 4, caseId: 41, api: api), frames: 5);
  });

  testWidgets('the correction, reject and password dialogs', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (c) => TextButton(onPressed: () => showOnbCorrectionSheet(c, item), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('onb.correct.send')), findsOneWidget);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (c) => TextButton(onPressed: () => showOnbRejectSheet(c, const [OnbRejectReason('dup', 'طلب مكرر', 'Duplicate application')]), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('onb.reject.send')), findsOneWidget);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (c) => TextButton(onPressed: () => showGeneratedPassword(c, 'Zk3-pass-word', name: 'Ahmed'), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('onb.password')), findsOneWidget);
      },
    );
  });

  testWidgets('the types list and the type editor', (tester) async {
    await expectNoLayoutErrors(tester, () => OnbTypesList(types: [type, type.copyWith(active: false)], loading: false, onToggle: (_, _) {}, onOpen: (_) {}));
    await expectNoLayoutErrors(tester, () => const OnbTypesList(types: [], loading: false));
    await expectNoLayoutErrors(tester, () => OnbTypeEditor(type: type, onSave: (_) {}));
  });

  testWidgets('the field, document and preset editors', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (c) => TextButton(onPressed: () => showOnbFieldSheet(c, type.field('birth_date')!), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (c) => TextButton(onPressed: () => showOnbDocSheet(c, type.doc('military_form')!), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => Builder(
          builder: (c) => TextButton(
              onPressed: () => showOnbPresetSheet(c, const [OnbPreset(key: 'egypt_public', labelAr: 'جامعة حكومية', labelEn: 'Public university', types: ['student_new', 'faculty'])]), child: const Text('go'))),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('onb.preset.apply')), findsOneWidget);
      },
    );
  });
}
