// Questions with more choices than the bubble sheet has bubbles (D-720 – D-723). The print panel used to stop at "Some
// questions have more options than the sheet has bubbles"; now it names them and offers four ways out:
//   trim     remove wrong choices (never a correct one) so the question fits: a new version, undone with Restore
//   ignore   not on the bubble sheet: answered on the question paper, its mark entered by hand
//   written  not on the bubble sheet: a choice row on the written answer sheet (NB2), or the booklet's table
//   another sheet  PUT …/setup omr_template_id with a sheet that has enough bubbles, or the teacher's own sheet
// Server: GET / PUT /api/v1/exam/exams/{id}/omr/fit (back exam_engine/services/bubble_fit.py), stored in
// `settings.bubble_fit`, so printing, reading and grading follow the same choice.
//
// Pure (unit-tested): BubbleFit · BubbleFitItem · BubbleFitAction · bubbleFitBody · bubbleFitSheets · the words.
library;

import '../../../../../core/api_client.dart';
import '../../../../../core/plural.dart';
import '../../../../admin/admin_common.dart' show t, asInt, asMap;
import '../../exam_engine_api.dart';
import '../exam_setup.dart' show OmrTemplateItem;

/// The server code of the print check this flow answers.
const kBubbleFitCode = 'question_options_exceed_sheet';

/// What happens to one question. [bubble] = back on the sheet (clears ignore / written); [restore] undoes a trim.
enum BubbleFitAction { trim, ignore, written, bubble, restore }

BubbleFitAction? bubbleFitActionOf(Object? v) => switch (v) {
      'trim' => BubbleFitAction.trim,
      'ignore' => BubbleFitAction.ignore,
      'written' => BubbleFitAction.written,
      _ => null,
    };

class BubbleFitOption {
  const BubbleFitOption({required this.id, required this.text, this.correct = false});
  final String id;
  final String text;
  final bool correct;

  static BubbleFitOption fromJson(Map<String, dynamic> j) =>
      BubbleFitOption(id: '${j['id'] ?? ''}', text: '${j['text'] ?? ''}', correct: j['correct'] == true);
}

/// One question that does not fit.
class BubbleFitItem {
  const BubbleFitItem({
    required this.questionId,
    required this.number,
    required this.count,
    this.prompt = '',
    this.options = const [],
    this.choice,
    this.canTrim = true,
    this.trimRemoves = const [],
  });

  final int questionId;

  /// Its number on the question paper.
  final int number;
  final int count;
  final String prompt;
  final List<BubbleFitOption> options;

  /// The stored choice (ignore / written), null while open.
  final BubbleFitAction? choice;

  /// False when the correct answers alone need more bubbles than the sheet has.
  final bool canTrim;

  /// The option ids a trim removes (wrong ones, from the last up).
  final List<String> trimRemoves;

  static BubbleFitItem fromJson(Map<String, dynamic> j) => BubbleFitItem(
        questionId: asInt(j['question_id']),
        number: asInt(j['n']),
        count: asInt(j['count']),
        prompt: '${j['prompt'] ?? ''}',
        options: [for (final o in (j['options'] is List ? j['options'] as List : const [])) if (o is Map) BubbleFitOption.fromJson(asMap(o))],
        choice: bubbleFitActionOf(j['choice']),
        canTrim: j['can_trim'] != false,
        trimRemoves: [for (final x in (j['trim_removes'] is List ? j['trim_removes'] as List : const [])) '$x'],
      );
}

/// A question already trimmed for this exam (Restore pins the original back).
class BubbleFitTrimmed {
  const BubbleFitTrimmed({required this.questionId, required this.number, this.removed = const []});
  final int questionId;
  final int number;
  final List<String> removed;

  static BubbleFitTrimmed fromJson(Map<String, dynamic> j) => BubbleFitTrimmed(
      questionId: asInt(j['question_id']), number: asInt(j['n']), removed: [for (final x in (j['removed'] is List ? j['removed'] as List : const [])) '$x']);
}

/// `GET …/omr/fit`.
class BubbleFit {
  const BubbleFit({required this.sheetOptions, this.templateId, this.orgId, this.writtenSheet = 'NB2', this.locked = false, this.items = const [], this.trimmed = const []});

  final int sheetOptions;
  final int? templateId;
  final int? orgId;

  /// `NB2` (moved questions get a choice row on the written answer sheet) or `booklet`.
  final String writtenSheet;

  /// Sheets were printed or read: questions can no longer move between sheets.
  final bool locked;
  final List<BubbleFitItem> items;
  final List<BubbleFitTrimmed> trimmed;

  bool get onNb2 => writtenSheet != 'booklet';

  /// The most choices any listed question has.
  int get maxOptions => items.fold(sheetOptions, (m, x) => x.count > m ? x.count : m);

  static BubbleFit fromJson(Map<String, dynamic> j) => BubbleFit(
        sheetOptions: asInt(j['sheet_options']),
        templateId: j['template_id'] is num ? (j['template_id'] as num).toInt() : null,
        orgId: j['org_id'] is num ? (j['org_id'] as num).toInt() : null,
        writtenSheet: '${j['written_sheet'] ?? 'NB2'}',
        locked: j['locked'] == true,
        items: [for (final x in (j['items'] is List ? j['items'] as List : const [])) if (x is Map) BubbleFitItem.fromJson(asMap(x))],
        trimmed: [for (final x in (j['trimmed'] is List ? j['trimmed'] as List : const [])) if (x is Map) BubbleFitTrimmed.fromJson(asMap(x))],
      );
}

/// The PUT body: only the questions whose choice differs from what is stored.
Map<String, dynamic> bubbleFitBody(BubbleFit fit, Map<int, BubbleFitAction> chosen) => {
      'questions': {
        for (final x in fit.items)
          if (chosen[x.questionId] != null && chosen[x.questionId] != x.choice) '${x.questionId}': chosen[x.questionId]!.name,
      },
    };

/// The sheets that hold every question as it is: enough choices and rows, printable bubble sheets first, the smallest
/// fitting one first. [questions] = how many questions go on the sheet.
List<OmrTemplateItem> bubbleFitSheets(List<OmrTemplateItem> all, {required int options, required int questions, int? current}) {
  final fit = [
    for (final x in all)
      if (x.id != current && x.kind != 'answer_table' && (x.options ?? 0) >= options && (questions <= 0 || x.questions >= questions)) x,
  ];
  int rank(OmrTemplateItem x) => x.kind == 'bubble' ? 0 : 1;
  fit.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.questions.compareTo(b.questions));
  return fit;
}

/// The letter printed for option [i] (A, B, C … / أ، ب، ج …).
String bubbleFitLetter(int i, {required bool ar}) {
  const arL = ['أ', 'ب', 'ج', 'د', 'هـ', 'و', 'ز', 'ح', 'ط', 'ي', 'ك', 'ل'];
  if (ar) return i < arL.length ? arL[i] : '${i + 1}';
  return i < 26 ? String.fromCharCode(65 + i) : '${i + 1}';
}

// ── words ──────────────────────────────────────────────────────────────────────────────────────────────────────

String bubbleFitActionTitle(BubbleFitAction a) => switch (a) {
      BubbleFitAction.trim => t('احذف خيارات خاطئة', 'Remove wrong choices'),
      BubbleFitAction.ignore => t('خارج ورقة التظليل', 'Leave off the sheet'),
      BubbleFitAction.written => t('في ورقة الإجابة الكتابية', 'Answer on the written sheet'),
      BubbleFitAction.bubble => t('على ورقة التظليل', 'On the bubble sheet'),
      BubbleFitAction.restore => t('تراجع', 'Undo'),
    };

/// One line on what the choice does, and how the question gets its mark.
String bubbleFitActionLine(BubbleFitAction a, {required bool onNb2, required int sheetOptions}) => switch (a) {
      BubbleFitAction.trim => t('يبقى السؤال على ورقة التظليل بـ $sheetOptions خيارات ويُصحَّح تلقائيًا. الإجابة الصحيحة لا تُحذف أبدًا، وأعد طباعة ورقة الأسئلة.',
          'The question stays on the bubble sheet with $sheetOptions choices and is graded automatically. The correct answer is never removed; print the question paper again.'),
      BubbleFitAction.ignore => t('يجيب الطالب على ورقة الأسئلة، وتُدخل درجته بنفسك مع النتائج (إدخال الدرجات أو ملف الدرجات).',
          'Students answer it on the question paper; you enter its mark yourself with the results (Enter marks or the marks file).'),
      BubbleFitAction.written => onNb2
          ? t('يظهر في ورقة الإجابة الكتابية كصف خيارات يضع الطالب علامة على حرفه، ويُصحَّح مع تلك الورقة.',
              'It appears on the written answer sheet as a row of choice boxes; students mark the letter and it is graded with that sheet.')
          : t('يكتب الطالب حرف الإجابة في جدول دفتر الإجابة، وتصححه مع الدفتر.',
              "Students write the letter in the answer booklet's table; you mark it with the booklet."),
      BubbleFitAction.bubble || BubbleFitAction.restore => '',
    };

String bubbleFitHeadline(BubbleFit f) {
  final n = countText(f.items.length, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤالًا', en1: '1 question has', en: '{n} questions have');
  return t('$n فيها خيارات أكثر من فقاعات هذه الورقة (${f.sheetOptions} لكل سؤال). اختر ما يحدث لكل منها، أو استخدم ورقة أخرى.',
      '$n more choices than this sheet has bubbles (${f.sheetOptions} per question). Choose what happens to each, or use another sheet.');
}

String bubbleFitCountLine(BubbleFitItem x, int sheetOptions) =>
    t('${x.count} خيارات · الورقة $sheetOptions', '${x.count} choices · the sheet has $sheetOptions');

/// Server codes of this flow in words.
String bubbleFitCodeText(EngineResult r) => switch (r.code) {
      'plan_locked_by_sheets' => t('طُبعت أوراق الإجابة أو صُوّرت: لا يمكن نقل الأسئلة بين الأوراق الآن',
          'Answer sheets were printed or scanned: questions can no longer move between sheets.'),
      'trim_impossible' => t('الإجابات الصحيحة وحدها أكثر من فقاعات الورقة', 'The correct answers alone are more than the sheet has bubbles.'),
      'trim_after_answers' => t('لهذا السؤال إجابات مسجلة: لا يمكن تغيير خياراته الآن', 'This question already has answers: its choices can no longer change.'),
      'exam_closed' => t('الاختبار مغلق', 'The exam is closed.'),
      _ => r.message.isNotEmpty && r.message != 'Not Found' ? r.message : t('تعذّر الحفظ — أعد المحاولة', 'Could not save — try again'),
    };

// ── API ────────────────────────────────────────────────────────────────────────────────────────────────────────

class BubbleFitApi {
  BubbleFitApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> get(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/fit'));
  Future<EngineResult> put(int examId, Map<String, dynamic> body) => engineCall(() => _api.put('$_b/exams/$examId/omr/fit', body: body));
}
