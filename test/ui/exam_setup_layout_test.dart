// "No overflow on any screen size" for the paper exam setup wizard (D-150, D-151) and the student's identifier
// dialog: every step's plain-values widget at 320×640 and 1400×900, ar / en, text ×1.3 (layout_harness.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup_wizard.dart';
import 'package:flutter_education_app/features/shared/identity/identity_request_gate.dart';
import 'package:flutter_education_app/features/shared/identity/identity_requests.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _nid = IdentityFieldDef(key: 'national_id', labelAr: 'الرقم القومي', labelEn: 'National ID', kind: 'digits', minLen: 14, maxLen: 14);

final _options = identifierOptions(const [
  _nid,
  IdentityFieldDef(key: 'academic_id', labelAr: 'الرقم الأكاديمي', labelEn: 'Academic ID'),
  IdentityFieldDef(key: 'passport_no', labelAr: 'رقم جواز السفر للطلاب الوافدين', labelEn: 'Passport number of international students'),
], dataLab: true, dataLabColumns: const [('seat', 'Seat number in the hall')]);

final _report = IdentifierReport(
  source: 'national_id',
  labelAr: 'الرقم القومي',
  labelEn: 'National ID',
  kind: 'digits',
  collectable: true,
  total: 40,
  ready: 28,
  missing: [for (var i = 0; i < 12; i++) StudentRef(i, i.isEven ? 'عبد الرحمن محمد عبد العزيز $i' : 'Alexandra Konstantinopoulou $i')],
  duplicates: const [
    [StudentRef(50, 'Ali Hassan'), StudentRef(51, 'Mona Abdelrahman Mostafa')],
    [StudentRef(52, 'سارة'), StudentRef(53, 'يوسف'), StudentRef(54, 'Omar')],
  ],
  pending: 6,
  done: 3,
);

final _questions = [
  for (var i = 0; i < 6; i++)
    ObjectiveQuestion.fromPlaced({
      'id': i + 1,
      'type': i == 5 ? 'true_false' : (i == 4 ? 'mcq_multi' : 'mcq_single'),
      'body': {'prompt': 'Question ${i + 1}: which of the following statements about photosynthesis is correct?', 'options': ['a', 'b', 'c', 'd', 'e']},
      'answer': {'correct': i == 5 ? true : (i == 4 ? ['a', 'c'] : 'b')},
    })!,
];

Widget _frame(Widget body, {String? error, int index = 0, int total = 5}) => SetupFrame(
      index: index,
      total: total,
      stepLabel: setupStepLabel(SetupStep.values[index.clamp(0, 4)]),
      title: 'How do we identify each student in this exam? A long title wraps',
      subtitle: 'Each sheet is matched to its student by this value',
      error: error,
      body: body,
      primaryLabel: 'Continue to the next step',
      onPrimary: () {},
      backLabel: 'Back',
      onBack: () {},
    );

void main() {
  setUp(() => AppConfig.disableList = []);

  testWidgets('step 1: options, audience check with many missing, duplicates', (t) async {
    await expectNoLayoutErrors(t, () => _frame(IdentifierStepBody(
          options: _options,
          selected: const IdentifierChoice('national_id'),
          onPick: (_) {},
          report: _report,
          note: 'Request sent to 6 students',
          dueLabel: 'Due: exam day, 1 Dec 2026',
          onChangeDue: () {},
          onRequest: () {},
          onRemind: () {},
          live: true,
        ), error: 'This sheet type is not approved yet — choose a published one'));
  });

  testWidgets('step 1: not collectable, everyone ready, loading, no course', (t) async {
    await expectNoLayoutErrors(t, () => _frame(Column(children: [
          IdentifierStepBody(
            options: _options,
            selected: const IdentifierChoice('datalab', 'seat'),
            onPick: (_) {},
            report: IdentifierReport(source: 'datalab', labelEn: 'Seat number', labelAr: 'رقم المقعد', total: 3, ready: 1, missing: const [StudentRef(1, 'Sara'), StudentRef(2, 'Omar')]),
          ),
          const IdentifierStepBody(
            options: [],
            selected: IdentifierChoice('email'),
            onPick: _noop,
            report: IdentifierReport(source: 'email', labelEn: 'Email', labelAr: 'البريد', collectable: true, total: 3, ready: 3, pending: 0),
          ),
          const IdentifierStepBody(options: [], selected: IdentifierChoice('email'), onPick: _noop, reportLoading: true),
          const IdentifierStepBody(options: [], selected: null, onPick: _noop, noCourse: true),
        ])));
  });

  testWidgets('steps 2 and 3: type, coming next, paper format', (t) async {
    await expectNoLayoutErrors(t, () => _frame(Column(children: [
          DeliveryStepBody(value: 'paper', onPick: (_) {}),
          OnlineComingNext(onPaper: () {}),
          PaperFormatStepBody(value: 'both', omrOn: true, onPick: (_) {}),
        ]), index: 1));
  });

  testWidgets('step 4: templates, empty with the upload entry, error', (t) async {
    await expectNoLayoutErrors(t, () => _frame(Column(children: [
          TemplateStepBody(
            templates: const [
              OmrTemplateItem(id: 1, version: 1, name: 'Bubble 50 · ministry standard layout', questions: 50, options: 4, description: 'Two columns, a shaded 10-digit ID'),
              OmrTemplateItem(id: 2, version: 3, name: 'Bubble 100', questions: 100),
            ],
            selectedId: 1,
            onPick: (_) {},
            onLearn: () {},
            onPaperOnly: () {},
          ),
          TemplateStepBody(templates: const [], selectedId: null, onPick: (_) {}, onLearn: () {}, onPaperOnly: () {}),
          TemplateStepBody(templates: null, error: 'The bubble-sheet library is for teachers and staff', selectedId: null, onPick: (_) {}, onRetry: () {}, onPaperOnly: () {}),
        ]), index: 3));
  });

  testWidgets('step 5: three models, one open, markers and the marking rules', (t) async {
    final forms = [newForm('A', _questions), newForm('B', _questions)..key.remove('2'), newForm('C', _questions)];
    await expectNoLayoutErrors(t, () => _frame(FormsStepBody(
          forms: forms,
          questions: _questions,
          markers: const ['qr', 'bubble'],
          policy: const OmrPolicy(blank: 'zero'),
          bubble: true,
          onAdd: () {},
          onRemove: (_) {},
          onChoose: (_, _, _) {},
          onToggleMarker: (_) {},
          onPolicy: (_) {},
        ), index: 4));
    await expectNoLayoutErrors(t, () => _frame(FormsStepBody(
          forms: [ExamFormDraft(code: 'A')],
          questions: const [],
          markers: const [],
          policy: const OmrPolicy(),
          bubble: false,
          onRemove: (_) {},
          onChoose: (_, _, _) {},
          onToggleMarker: (_) {},
          onPolicy: (_) {},
        ), index: 4));
  });

  testWidgets('the student\'s identifier dialog: plain, with an error, one of several, busy', (t) async {
    final item = IdentityRequestItem(
      id: 1,
      field: _nid,
      examTitle: 'Physics midterm — second term, group B',
      paper: true,
      dueUtc: DateTime.utc(2026, 11, 20, 7),
      messageAr: 'يحتاج معلمك إلى الرقم القومي للاختبار القادم. يُرجى إدخاله قبل يوم الاختبار.',
      messageEn: 'Your teacher needs your National ID for the upcoming exam. Please enter it before exam day.',
    );
    for (final (error, total, busy) in [(null, 1, false), ('This number is already used by another student. Please check it.', 3, false), (null, 2, true)]) {
      await expectNoLayoutErrors(t, () => Center(
            child: SingleChildScrollView(
              child: IdentityRequestCard(item: item, controller: TextEditingController(), onSubmit: () {}, onLater: () {}, error: error, total: total, index: 1, busy: busy),
            ),
          ));
    }
  });
}

void _noop(IdentifierOption _) {}
