import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_forms_import.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

FormPreview _preview() => FormPreview.fromJson({
      'title': 'Chapter three: a very long form title that keeps going to fill the width of the sheet on a phone',
      'is_quiz': true,
      'questions': [
        {'type': 'mcq_single', 'prompt': '2+2?', 'options': ['3', '4'], 'correct': ['4'], 'needs_answer': false},
        {'type': 'mcq_single', 'prompt': 'No key', 'options': ['a', 'b'], 'correct': [], 'needs_answer': true, 'image_dropped': true},
        {'type': 'essay', 'prompt': 'Explain', 'correct': []},
      ],
      'skipped': [
        {'title': 'Rate this very long question title that keeps going and going past the width of a phone', 'reason': 'scale'},
        {'title': '', 'reason': 'empty'},
      ],
    });

GoogleFormsImportBody _body({bool loading = false, bool connected = true, bool waiting = false, FormPreview? preview, ImportReport? report, String? error}) =>
    GoogleFormsImportBody(
      loading: loading,
      connected: connected,
      waiting: waiting,
      preview: preview,
      sections: const [(1, 'Part one'), (2, 'Part two')],
      sectionId: 1,
      onSection: (_) {},
      report: report,
      busy: false,
      error: error,
      onConnect: () {},
      onPick: () {},
      onImport: () {},
      onDone: () {},
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the preview counts what is ready and what will stay behind', () {
    final p = _preview();
    expect(p.isQuiz, isTrue);
    expect(p.ready, 2);
    expect(p.needsAnswer, 1);
    expect(p.imagesDropped, 1);
    expect(p.skipped.first.$2, 'scale');
    expect(formSkipText('scale'), 'Linear scale');
    expect(formSkipText('something new'), 'Unsupported type');
  });

  test('a known code gets its own text, in both languages', () {
    const e = ApiException(statusCode: 403, message: '', code: 'form_not_accessible');
    expect(formsErrorText(e), contains('could not be opened'));
    AppConfig.lang = 'ar';
    expect(formsErrorText(e), contains('تعذّر فتح النموذج'));
  });

  testWidgets('every step fits on every screen', (t) async {
    final report = ImportReport.fromJson({
      'created': 2,
      'errors': [
        for (var i = 0; i < 4; i++) {'row': i + 3, 'code': 'no_correct_answer', 'message': 'لا توجد إجابة صحيحة في النموذج', 'message_en': 'The form gives no correct answer'},
      ],
    });
    for (final body in [
      _body(loading: true),
      _body(connected: false),
      _body(connected: false, waiting: true),
      _body(waiting: true),
      _body(error: 'A long message that explains what went wrong with the form and how to get it right again'),
      _body(preview: _preview()),
      _body(preview: _preview(), report: report),
    ]) {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: body));
    }
  });

  testWidgets('import stays off until something can be imported', (t) async {
    await t.pumpWidget(layoutHost(SingleChildScrollView(
        child: _body(preview: FormPreview.fromJson({
      'title': 'x',
      'questions': [
        {'type': 'mcq_single', 'prompt': 'q', 'needs_answer': true}
      ]
    })))));
    expect(find.byKey(const ValueKey('exam.forms.no_answers')), findsOneWidget);
    expect(t.widget<AppPrimaryButton>(find.byKey(const ValueKey('exam.forms.import'))).onPressed, isNull);
  });
}
