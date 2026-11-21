// Phase 3 of the student lifecycle (contract §7.2, §14 F2): the missing-data sheet completed in place, "Add student",
// the entry-policy picker and the wizard's "Save and invite" never overflow (320x640 and 1400x900, ar / en, text
// x1.3), and the few behaviours they own: a field saves its value, a reminder note locks the button, the type step
// leads to the methods, "Save and invite" invites the saved draft.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_api.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_models.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_types_page.dart';
import 'package:flutter_education_app/features/org/onboarding/onboarding_wizard.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show OrgCall;
import 'package:flutter_education_app/features/org/students/add_student_sheet.dart';
import 'package:flutter_education_app/features/org/students/students_missing_sheet.dart';
import 'package:flutter_education_app/features/org/students/students_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/$name.json').readAsStringSync())['payload'] as Map);

const _longAr = 'شهادة إتمام الخدمة العسكرية أو الإعفاء منها (نموذج 6 جند) مختومة من منطقة التجنيد التابع لها الطالب';
const _longEn = 'Certificate of completed military service or exemption (form 6) stamped by the student\'s recruitment district';

final _missing = StudentMissing.fromJson({
  'case_id': 3310,
  'can_upload': true,
  'can_edit': true,
  'can_waive': false,
  'due_at': '2026-12-15T00:00:00',
  'photos': [
    {'key': 'photo', 'label_ar': 'صورة شخصية', 'label_en': 'Personal photo', 'why_ar': 'مطلوبة لكل الطلاب', 'why_en': 'Required for every student'},
  ],
  'documents': [
    {'key': 'military_6', 'label_ar': _longAr, 'label_en': _longEn, 'why_ar': 'مطلوب للطلاب المصريين الذكور فوق 19 سنة', 'why_en': 'Required for male Egyptian students over 19', 'due_at': '2026-12-15T00:00:00', 'status': 'rejected'},
    {'key': 'birth', 'label_ar': 'شهادة الميلاد', 'label_en': 'Birth certificate', 'status': 'deferred'},
  ],
  'fields': [
    {'key': 'guardian_phone', 'label_ar': 'هاتف ولي الأمر', 'label_en': 'Guardian\'s phone', 'kind': 'phone', 'why_ar': 'مطلوب لمن هم دون 18 سنة', 'why_en': 'Required under 18'},
    {'key': 'guardian_email', 'label_ar': 'بريد ولي الأمر', 'label_en': 'Guardian\'s e-mail', 'kind': 'email'},
    {'key': 'issue_date', 'label_ar': 'تاريخ إصدار البطاقة', 'label_en': 'ID issue date', 'kind': 'date'},
    {'key': 'program_id', 'label_ar': 'البرنامج', 'label_en': 'Programme', 'kind': 'program'},
    {'key': 'notes', 'label_ar': _longAr, 'label_en': _longEn, 'kind': 'textarea'},
  ],
});

OnbType _ty(String key, String ar, String en, {String policy = 'review', List<Map<String, dynamic>> chain = const []}) => OnbType.fromJson({
      'key': key,
      'label_ar': ar,
      'label_en': en,
      'module': 'students',
      'preset_key': key,
      'chain': chain,
      'settings': {'entry_policy': policy},
    });

final _types = [
  _ty('student_new', 'طالب مستجد', 'New student'),
  _ty('student_transfer', 'طالب محوّل', 'Transfer student'),
  _ty('student_equivalent', 'طالب شهادة معادلة', 'Equivalent certificate student'),
  _ty('student_technical', 'طالب حاصل على دبلوم فني', 'Technical diploma student'),
  _ty('student_second_degree', 'طالب من حملة المؤهلات العليا', 'Second-degree student'),
  _ty('student_affiliated', 'طالب منتسب', 'Affiliated student'),
  _ty('student_special_program', 'طالب برنامج خاص بمصروفات', 'Paid special programme student'),
  _ty('student_visiting', 'طالب زائر / مستمع', 'Visiting / listener student', policy: 'code'),
  _ty('custom_exchange', 'طالب تبادل ضمن اتفاقية الشراكة الأكاديمية مع الجامعات الأوروبية', 'Exchange student under the academic partnership with European universities', policy: 'invitation'),
];

const _peopleChain = [
  {'key': 'person', 'label_ar': 'د. محمد عبد الحميد إبراهيم السيد، أ. فاطمة الشاذلي', 'label_en': 'Dr. Mohamed Abdelhamid Ibrahim, Ms. Fatma El-Shazly', 'need': {'user_ids': [7, 9]}},
];
const _councilChain = [
  {'key': 'council', 'label_ar': 'مجلس كلية الحاسبات والذكاء الاصطناعي', 'label_en': 'Council of the Faculty of Computers and Artificial Intelligence', 'need': {'council_id': 3}},
];

/// Records the invitation; every save succeeds.
class _FakeApi extends OnboardingApi {
  _FakeApi(this.caseJson);
  final Map<String, dynamic> caseJson;
  List<int>? invited;

  @override
  Future<OrgCall> createCase(int orgId, {required String typeKey, required Map<String, dynamic> fields, bool submit = false, bool approveNow = false}) async =>
      OrgCall({...caseJson, 'type': null});
  @override
  Future<OrgCall> patchCase(int orgId, int id, Map<String, dynamic> fields) async => OrgCall({...caseJson, 'type': null});
  @override
  Future<OrgCall> inviteCases(int orgId, List<int> caseIds) async {
    invited = caseIds;
    return OrgCall({'invited': caseIds.length, 'skipped': <dynamic>[]});
  }
}

void main() {
  late Map<String, dynamic> typeJson, caseJson;
  late OnbType type;

  setUp(() {
    typeJson = _fx('onboarding_type');
    caseJson = {..._fx('onboarding_case'), 'status': 'draft'};
    type = OnbType.fromJson(typeJson);
  });

  testWidgets('MissingDataView: editable, every group and kind, long labels, busy, remind note', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MissingDataView(
            data: _missing,
            onOpenFile: () {},
            onUpload: (_, {required photo}) {},
            onSaveField: (_, _) {},
            onRemind: () {},
            busyKeys: const {'birth', 'guardian_email'},
            remindLocked: true,
            remindNote: remindAgainText(DateTime.utc(2026, 11, 22, 9, 30)),
          ),
        ),
      ));

  testWidgets('MissingDataView: read only (no rights) and reminding', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            MissingDataView(data: _missing),
            MissingDataView(data: _missing, onRemind: () {}, reminding: true),
          ]),
        ),
      ));

  testWidgets('a missing field saves its trimmed value; an empty one says so', (tester) async {
    AppConfig.lang = 'en';
    String? saved;
    await tester.pumpWidget(layoutHost(
      SingleChildScrollView(child: MissingDataView(data: _missing, onSaveField: (it, v) => saved = '${it.key}=$v')),
      scale: 1,
    ));
    await tester.pump();
    final save = find.byKey(const ValueKey('students.missing.save.guardian_phone'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Type the value first'), findsOneWidget);
    await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('students.missing.input.guardian_phone')), matching: find.byType(TextField)), ' 01012345678 ');
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(saved, 'guardian_phone=01012345678');
    expect(find.byKey(const ValueKey('students.missing.input.program_id')), findsNothing, reason: 'a list field is chosen in the file');
  });

  testWidgets('a reminder in the last 24 hours locks the button and says when it comes back', (tester) async {
    AppConfig.lang = 'en';
    var pressed = 0;
    await tester.pumpWidget(layoutHost(
      SingleChildScrollView(child: MissingDataView(data: _missing, onRemind: () => pressed++, remindLocked: true, remindNote: remindAgainText(DateTime.utc(2026, 11, 22, 9)))),
      scale: 1,
    ));
    await tester.pump();
    final btn = find.byKey(const ValueKey('students.missing.remind'));
    await tester.ensureVisible(btn);
    await tester.tap(btn, warnIfMissed: false);
    expect(pressed, 0);
    expect(find.byKey(const ValueKey('students.missing.remind.note')), findsOneWidget);
  });

  testWidgets('Add student: the type cards, grouped, long names', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: AddStudentView(types: _types, onType: (_) {})),
      ));

  testWidgets('Add student: the methods (recommended by the policy), loading, empty, error', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            AddStudentView(types: _types, picked: _types.last, methods: AddStudentMethod.values, onMethod: (_) {}, onBack: () {}),
            AddStudentView(types: _types, picked: _types[7], methods: const [AddStudentMethod.full, AddStudentMethod.link], onMethod: (_) {}),
            const AddStudentView(types: [], loading: true),
            const AddStudentView(types: []),
            AddStudentView(types: const [], error: 'تعذر تحميل الأنواع', onRetry: () {}),
          ]),
        ),
      ));

  test('the methods follow the rights and the policy', () {
    final ty = _types.first;
    expect(addStudentMethodsFor(ty, (_, _) => true), AddStudentMethod.values);
    expect(addStudentMethodsFor(ty, (m, a) => a == 'insert'), [AddStudentMethod.full, AddStudentMethod.excel]);
    expect(addStudentRecommended('invitation'), AddStudentMethod.basics);
    expect(addStudentRecommended('code'), AddStudentMethod.link);
    expect(addStudentRecommended('direct'), AddStudentMethod.full);
    expect(addStudentRouteOf(_types[1]), AddStudentRoute.moving);
    expect(addStudentRouteOf(_types.last), AddStudentRoute.custom);
  });

  testWidgets('Add student: picking a type shows its methods', (tester) async {
    AppConfig.lang = 'en';
    OnbType? picked;
    await tester.pumpWidget(layoutHost(
      StatefulBuilder(
        builder: (context, set) => SingleChildScrollView(
          child: AddStudentView(
            types: _types,
            picked: picked,
            methods: picked == null ? const [] : AddStudentMethod.values,
            onType: (ty) => set(() => picked = ty),
            onMethod: (_) {},
          ),
        ),
      ),
      scale: 1,
    ));
    await tester.pump();
    final card = find.byKey(const ValueKey('students.add.type.student_transfer'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();
    expect(find.byKey(const ValueKey('students.add.method.basics')), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
  });

  for (final p in onbEntryPolicies) {
    testWidgets('the entry-policy picker: $p', (t) => expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              OnbEntryPolicyPicker(policy: p, chain: const [], onPolicy: (_) {}, onDecider: (_) {}),
              OnbEntryPolicyPicker(policy: p, chain: [for (final s in _peopleChain) OnbChainStep.fromJson(s)], onPolicy: (_) {}, onDecider: (_) {}, onAddPerson: () {}),
              OnbEntryPolicyPicker(policy: p, chain: [for (final s in _councilChain) OnbChainStep.fromJson(s)], onPolicy: (_) {}, onDecider: (_) {}, councilOn: false),
            ]),
          ),
        ));
  }

  test('the decider a chain stands for', () {
    expect(onbDeciderOf(const []), OnbDecider.right);
    expect(onbDeciderOf([for (final s in _peopleChain) OnbChainStep.fromJson(s)]), OnbDecider.people);
    expect(onbDeciderOf([for (final s in [..._peopleChain, ..._councilChain]) OnbChainStep.fromJson(s)]), OnbDecider.council);
  });

  testWidgets('the type editor with a body step', (t) => expectNoLayoutErrors(
        t,
        () => OnbTypeEditor(type: type.copyWith(chain: [for (final s in _councilChain) OnbChainStep.fromJson(s)]), onSave: (_) {}, onPickPerson: (_) async => null, onPickCouncil: () async => null),
      ));

  testWidgets('the wizard, basics only: identity, contact, then "Save and invite"', (tester) async {
    final api = _FakeApi(caseJson);
    for (var s = 0; s < 3; s++) {
      await expectNoLayoutErrors(tester, () => OnbWizard(orgId: 4, type: type, api: api, places: const OnbPlaces(), initialStep: s, basicsOnly: true));
    }
  });

  testWidgets('the wizard\'s last step with "Save and invite" and the next-step sentence', (tester) async {
    final api = _FakeApi(caseJson);
    final council = type.copyWith(chain: [for (final s in _councilChain) OnbChainStep.fromJson(s)]);
    await expectNoLayoutErrors(tester, () => OnbWizard(orgId: 4, type: council, api: api, places: const OnbPlaces(), initialStep: 9, canInvite: true, canApproveNow: true));
  });

  testWidgets('"Save and invite" saves the draft and invites it', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = _FakeApi(caseJson);
    final initial = OnbCase.fromJson({...caseJson, 'type': typeJson});
    OnbCase? done;
    await tester.pumpWidget(layoutHost(
      OnbWizard(orgId: 4, type: type, api: api, places: const OnbPlaces(), initial: initial, initialStep: 9, basicsOnly: true, onDone: (c) => done = c),
      scale: 1,
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('onb.review.submit')), findsNothing, reason: 'basics only: the student completes the file');
    final btn = find.byKey(const ValueKey('onb.review.invite'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.invited, [41]);
    expect(done?.id, 41);
    await tester.pump(const Duration(seconds: 5));
  });
}
