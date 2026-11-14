// The paper exam's answer sheets (D-687, contract B in ../back/docs/grading/AUTOGRADE_CONTRACT.md): the pure part.
//
// A paper exam can carry two machine-read sheets: the bubble sheet (multiple choice and true / false; printed by
// Alfaheem, or sheets the teacher already has) and the NB2 answer sheet (numbers, completions, short and long answers,
// written in fixed boxes and lines). Both are personal (one per student: the course's roster with the academic ID or
// the system number, or, without a course, a CSV / Excel list) or generic (a name line and ID boxes). The wizard saves
// the choice in `settings.sheet_plan`; Deliver reads it back to print the NB2 sheets through `POST /exams/{id}/sheets`.
//
// Unit-tested in test/org/answer_sheet_plan_test.dart.
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/hub/create/paper_preview.dart' show noticePrintAdjustments;

/// Printing the NB2 sheet and the student list from a file (contract B, kill switch).
const kExamAnswerSheetFeatureKey = 'exam.answer_sheet';

/// The question types the NB2 sheet holds (contract B1); objective ones go to the bubble sheet or the answer table.
const kAnswerSheetTypes = <String>{'numeric', 'fill_blank', 'short_answer', 'essay'};

bool answerSheetCanHold(String type) => kAnswerSheetTypes.contains(type);

/// Bubble sheets printed by Alfaheem, or sheets the teacher already has (only read, never printed here).
enum BubbleSource { print, have }

/// One sheet named for each student, or generic sheets with a name line and ID boxes.
enum SheetCopies { personal, generic }

/// What a personal sheet carries: the exam's identifier (e.g. the academic ID) or the platform's user number.
enum IdSource { academic, system }

String bubbleSourceKey(BubbleSource v) => v == BubbleSource.have ? 'have' : 'print';
String sheetCopiesKey(SheetCopies v) => v == SheetCopies.generic ? 'generic' : 'personal';
String idSourceKey(IdSource v) => v == IdSource.system ? 'system' : 'academic';

BubbleSource? bubbleSourceOf(Object? v) => switch ('${v ?? ''}') { 'print' => BubbleSource.print, 'have' => BubbleSource.have, _ => null };
SheetCopies? sheetCopiesOf(Object? v) => switch ('${v ?? ''}') { 'personal' => SheetCopies.personal, 'generic' => SheetCopies.generic, _ => null };
IdSource? idSourceOf(Object? v) => switch ('${v ?? ''}') { 'academic' => IdSource.academic, 'system' => IdSource.system, _ => null };

String bubbleSourceLabel(BubbleSource v) => v == BubbleSource.print ? t('نطبعها لك', 'Print them here') : t('لديّ الأوراق بالفعل', 'I already have the sheets');

String bubbleSourceHint(BubbleSource v) => v == BubbleSource.print
    ? t('اختر نوع الورقة أو ارفع تصميمك، ونجهّزها للطباعة', 'Pick a sheet type or upload your own; we prepare it for printing')
    : t('اختر نوع الورقة التي لديك ليقرأها الماسح؛ لن نطبع أوراق تظليل', 'Pick the sheet type you have so the scanner can read it; no bubble sheets are printed');

String sheetCopiesLabel(SheetCopies v) => v == SheetCopies.personal ? t('ورقة باسم كل طالب', 'One for each student') : t('أوراق عامة', 'Generic sheets');

String sheetCopiesHint(SheetCopies v, {required bool hasCourse}) => switch (v) {
      SheetCopies.personal when hasCourse => t('تحمل اسم الطالب ورقمه من طلاب المقرر، فتُطابق وحدها', 'Each carries the student\'s name and number from the course, so it matches itself'),
      SheetCopies.personal => t('من قائمة طلاب ترفعها (CSV أو Excel)', 'From a student list you upload (CSV or Excel)'),
      SheetCopies.generic => t('يكتب الطالب اسمه ورقمه في المربعات', 'Students write their name and number in the boxes'),
    };

String idSourceLabel(IdSource v) => v == IdSource.academic ? t('الرقم الأكاديمي', 'Academic ID') : t('رقم النظام', 'System number');

String idSourceHint(IdSource v) => v == IdSource.academic
    ? t('معرّف الطالب الذي تختاره أدناه', 'The student identifier you choose below')
    : t('رقم الطالب على الفهيم، لا يحتاج إعدادًا', 'The student\'s Alfaheem number; nothing to set up');

/// "3 written questions" for the sheets step.
String writtenQuestionsText(int n) => countText(n,
    ar1: 'سؤال كتابي واحد', ar2: 'سؤالان كتابيان', arFew: '{n} أسئلة كتابية', arMany: '{n} سؤالًا كتابيًا', en1: '1 written question', en: '{n} written questions');

String studentsCountText(int n) =>
    countText(n, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');

/// `settings.sheet_plan`: what the wizard planned for the answer sheets.
class SheetPlan {
  const SheetPlan({this.bubble, this.answerSheet = false, this.copies = SheetCopies.generic, this.fromFile = false, this.idSource = IdSource.academic});

  /// Null on an exam without a bubble sheet.
  final BubbleSource? bubble;

  /// The NB2 sheet for the written answers.
  final bool answerSheet;
  final SheetCopies copies;

  /// Personal sheets from an uploaded list (an exam with no course).
  final bool fromFile;
  final IdSource idSource;

  bool get personal => copies == SheetCopies.personal;

  Map<String, dynamic> toJson() => {
        if (bubble != null) 'bubble': bubbleSourceKey(bubble!),
        if (answerSheet) 'answer_sheet': 'NB2',
        'copies': sheetCopiesKey(copies),
        if (copies == SheetCopies.personal) 'students': fromFile ? 'file' : 'course',
        if (copies == SheetCopies.personal && !fromFile) 'id_source': idSourceKey(idSource),
      };

  static SheetPlan? ofSettings(Object? settings) {
    final p = asMap(asMap(settings)['sheet_plan']);
    if (p.isEmpty) return null;
    if (p['answer_layout'] != null) {
      // v2 (D-697, back contract OFFLINE_FLOW_CONTRACT.md §1): read in the v1 terms Deliver prints with
      final b = asMap(p['bubble']);
      return SheetPlan(
        bubble: b.isEmpty ? null : (b['print'] == false ? BubbleSource.have : BubbleSource.print),
        answerSheet: '${p['answer_layout']}' != 'questions_only' && '${p['written_sheet'] ?? 'NB2'}' == 'NB2',
        copies: '${p['copies'] ?? ''}' == 'per_student' ? SheetCopies.personal : SheetCopies.generic,
        fromFile: '${asMap(p['students'])['source'] ?? ''}' == 'file',
        idSource: idSourceOf(p['id_source']) ?? IdSource.academic,
      );
    }
    return SheetPlan(
      bubble: bubbleSourceOf(p['bubble']),
      answerSheet: '${p['answer_sheet'] ?? ''}' == 'NB2',
      copies: sheetCopiesOf(p['copies']) ?? SheetCopies.generic,
      fromFile: '${p['students'] ?? ''}' == 'file',
      idSource: idSourceOf(p['id_source']) ?? IdSource.academic,
    );
  }
}

/// The body of `POST /exams/{id}/sheets` for the NB2 sheets (contract B1). [blank]: generic copies (1-500).
Map<String, dynamic> answerSheetsBody(SheetPlan plan, {int blank = 30, String? lang, List<int>? studentIds}) => {
      'layout': 'NB2',
      'copies': sheetCopiesKey(plan.copies),
      if (plan.personal) 'students': plan.fromFile ? 'file' : 'course',
      if (plan.personal && !plan.fromFile) 'id_source': idSourceKey(plan.idSource),
      if (plan.personal && !plan.fromFile && studentIds != null && studentIds.isNotEmpty) 'student_ids': studentIds,
      if (!plan.personal) 'blank': blank.clamp(1, kMaxGenericSheets),
      'lang': ?lang,
    };

const kMaxGenericSheets = 500;

/// The extensions the student list takes.
const kPeopleFileExtensions = ['csv', 'xlsx'];

/// The list's limits (contract B2).
const kPeopleFileMaxBytes = 2 * 1024 * 1024;

/// One row the server skipped.
typedef PeopleSkip = ({int row, String code});

/// The answer of `POST /exams/{id}/people/file` (and the people of `GET /exams/{id}/people`).
class PeopleUpload {
  const PeopleUpload({this.added = 0, this.updated = 0, this.total = 0, this.skipped = const [], this.names = const [], this.columns = const []});
  final int added, updated, total;
  final List<PeopleSkip> skipped;

  /// The first names on the list, for a glance.
  final List<String> names;

  /// Every other column of the list, as attributes (`file:<slug>`, contract §3): (key, label).
  final List<(String, String)> columns;

  static PeopleUpload fromJson(Map<String, dynamic> j) {
    final people = asMapList(j['people']);
    return PeopleUpload(
      added: asInt(j['added']),
      updated: asInt(j['updated']),
      total: asInt(j['total'], people.length),
      skipped: [for (final s in asMapList(j['skipped'])) (row: asInt(s['row']), code: '${s['code'] ?? ''}')],
      names: [for (final p in people.take(5)) '${p['name'] ?? ''}'.trim()].where((x) => x.isNotEmpty).toList(),
      columns: [for (final c in asMapList(j['columns'])) ('${c['key'] ?? ''}', '${c['label'] ?? ''}')],
    );
  }
}

String peopleSkipText(String code) => switch (code) {
      'empty_row' => t('صف فارغ', 'Empty row'),
      'no_name' => t('بلا اسم', 'No name'),
      'duplicate' => t('مكرر', 'Duplicate'),
      _ => code,
    };

/// A refused list / sheet request, in words (codes of contract B1 / B2).
String answerSheetErrorText(EngineResult r) {
  final problems = asMapList(r.detail['problems']);
  final first = problems.isEmpty ? '' : '${problems.first['code'] ?? ''}';
  return switch (r.code) {
    'bad_people_file' => switch (first) {
        'empty_file' => t('الملف فارغ', 'The file is empty'),
        'no_columns' => t('لم نجد عمود الاسم والرقم. اجعل العمود الأول الاسم والثاني الرقم', 'No name and number columns found. Put the name in column 1 and the number in column 2'),
        'bad_xlsx' => t('تعذّرت قراءة ملف Excel', 'The Excel file could not be read'),
        _ => t('تعذّرت قراءة القائمة', 'The list could not be read'),
      },
    'file_too_large' => t('الملف أكبر من 2 ميجابايت', 'The file is larger than 2 MB'),
    'run_has_course' => t('لهذا الاختبار مقرر، فطلابه من المقرر', 'This exam has a course; its students come from the course'),
    'no_open_questions' => t('لا أسئلة كتابية في هذا الاختبار، فلا حاجة لورقة إجابة', 'This exam has no written questions, so it needs no answer sheet'),
    'no_paper_questions' => t('لا أسئلة ورقية في هذا الاختبار', 'This exam has no paper questions'),
    'students_required' => t('اختر الطلاب أولاً', 'Choose the students first'),
    'not_a_student' => t('أحد المختارين ليس من طلاب المقرر', 'Someone chosen is not a student of the course'),
    'too_many_sheets' => t('أكثر من 2000 صفحة في المرة. قسّم الطباعة', 'More than 2000 pages at once. Print in parts'),
    'no_people' => t('ارفع قائمة الطلاب أولاً', 'Upload the student list first'),
    'roster_unavailable' => t('تعذّر الوصول إلى طلاب المقرر الآن. حاول بعد قليل', 'The course\'s students cannot be reached right now. Try again shortly'),
    'feature_disabled' => t('أوراق الإجابة متوقفة حاليًا', 'Answer sheets are switched off right now'),
    _ => r.message.isNotEmpty ? r.message : t('تعذّر الطلب', 'The request failed'),
  };
}

class AnswerSheetApi {
  AnswerSheetApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = ExamEngineApi.base;

  /// The NB2 sheets as one PDF (contract B1), or the refusal.
  Future<(Uint8List?, EngineResult?)> sheetsPdf(int examId, Map<String, dynamic> body) async {
    try {
      // the design's adjustments are said once, beside the print, never in its way (D-699)
      final bytes = await _api.postForBytes('$_b/exams/$examId/sheets', body: body, onHeaders: (h) => unawaited(noticePrintAdjustments(examId, h)));
      if (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) return (bytes, null);
      return (null, EngineResult.fail(200, null, t('لم يصل ملف PDF', 'No PDF came back')));
    } on ApiException catch (e) {
      Object? body = e.body;
      if (body is List<int>) {
        try {
          body = jsonDecode(utf8.decode(body));
        } catch (_) {}
      }
      final d = asMap(asMap(body)['detail']);
      return (null, EngineResult.fail(e.statusCode, d['code']?.toString() ?? e.code, '${d['message'] ?? e.message}', d));
    } catch (e) {
      return (null, EngineResult.fail(0, null, ApiException.from(e).message));
    }
  }

  /// The student list of an exam with no course (contract B2).
  Future<EngineResult> uploadPeople(int examId, String name, Uint8List bytes) =>
      engineCall(() => _api.postFiles('$_b/exams/$examId/people/file', files: [(name, bytes)], field: 'file'));

  Future<EngineResult> people(int examId) => engineCall(() => _api.get('$_b/exams/$examId/people'));
}
