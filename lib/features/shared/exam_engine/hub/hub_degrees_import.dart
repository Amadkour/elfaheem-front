// An exam's totals from an Excel sheet (D-353, kill switch `exam.results.import`): the pure part. The sheet is
// `hub_degrees_import_sheet.dart`.
//
//   GET  /api/v1/exam/exams/{id}/degrees/template    xlsx with the course's students and an empty degree column
//   POST /api/v1/exam/exams/{id}/degrees/preview     multipart file, match_column?, degree_column?, max_score?
//   POST /api/v1/exam/exams/{id}/degrees/commit      {import_key, max_score} → {written}
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../exam_engine_api.dart';

/// The server's limit on the file.
const kDegreesMaxBytes = 2 * 1024 * 1024;
const kDegreesFileTypes = ['xlsx', 'xlsm', 'csv'];

/// One row of the sheet that will not be saved.
class DegreeIssue {
  const DegreeIssue({required this.row, required this.value, this.reason});
  factory DegreeIssue.fromJson(Map<String, dynamic> m) => DegreeIssue(row: asInt(m['row']), value: '${m['value'] ?? ''}', reason: m['reason']?.toString());
  final int row;
  final String value;
  final String? reason;
}

class DegreesPreview {
  const DegreesPreview({
    this.columns = const [],
    this.matchColumn,
    this.degreeColumn,
    this.maxScore,
    this.rows = 0,
    this.matched = 0,
    this.unmatched = const [],
    this.invalid = const [],
    this.importKey,
  });

  factory DegreesPreview.fromJson(Map<String, dynamic> m) => DegreesPreview(
        columns: [for (final c in (m['columns'] is List ? m['columns'] as List : const [])) '$c'],
        matchColumn: m['match_column']?.toString(),
        degreeColumn: m['degree_column']?.toString(),
        maxScore: m['max_score'] is num ? (m['max_score'] as num).toDouble() : null,
        rows: asInt(m['rows']),
        matched: asInt(m['matched']),
        unmatched: [for (final x in asMapList(m['unmatched'])) DegreeIssue.fromJson(x)],
        invalid: [for (final x in asMapList(m['invalid'])) DegreeIssue.fromJson(x)],
        importKey: m['import_key']?.toString(),
      );

  final List<String> columns;
  final String? matchColumn, degreeColumn;
  final double? maxScore;
  final int rows, matched;
  final List<DegreeIssue> unmatched, invalid;
  final String? importKey;

  /// The server could not tell which column is which: the person must choose.
  bool get needsColumns => matchColumn == null || degreeColumn == null;
  bool get canSave => importKey != null && matched > 0;
}

/// Why a row was not accepted, in words.
String degreeReasonText(String? reason) => switch (reason) {
      'empty' => t('الدرجة فارغة', 'The degree is empty'),
      'not_a_number' => t('الدرجة ليست رقماً', 'The degree is not a number'),
      'negative' => t('الدرجة أقل من صفر', 'The degree is below zero'),
      'duplicate_student' => t('الطالب مكرر في الملف', 'This student appears twice'),
      'above_max' => t('أعلى من الدرجة العظمى', 'Above the full mark'),
      _ => t('غير صالحة', 'Not valid'),
    };

/// A server code in words (the engine sends a message too, for a code we do not know).
String degreesErrorText(EngineResult r) {
  final text = switch (r.code) {
    'no_course' => t('هذا الاختبار غير مرتبط بمقرر، فلا توجد قائمة طلاب للمطابقة', 'This exam is not linked to a course, so there is no student list to match'),
    'bad_degrees_file' => t('تعذرت قراءة الملف. استخدم ملف Excel أو CSV', 'This file could not be read. Use an Excel or CSV file'),
    'column_not_found' => t('العمود غير موجود في الملف', 'That column is not in the file'),
    'import_expired' || 'import_key_invalid' => t('انتهت صلاحية المعاينة. ارفع الملف مرة أخرى', 'This preview has expired. Upload the file again'),
    'max_score_invalid' => t('الدرجة العظمى غير صالحة', 'The full mark is not valid'),
    'feature_disabled' => t('استيراد الدرجات غير متاح الآن', 'Importing degrees is not available right now'),
    _ => null,
  };
  if (text != null) return text;
  return r.message.isNotEmpty ? r.message : t('تعذّر إكمال العملية', 'That could not be completed');
}

/// A typed mark ("20", "٢٠", "12.5"); null when it is not a usable full mark.
double? parseFullMark(String raw) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in raw.trim().split('')) {
    final i = ar.indexOf(ch), j = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : (ch == '٫' || ch == ',' ? '.' : ch)));
  }
  final v = double.tryParse(b.toString());
  return v == null || !v.isFinite || v <= 0 || v > 100000 ? null : v;
}

/// "20" not "20.0".
String fullMarkText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// The summary sentence above the numbers.
String degreesHeadline(DegreesPreview p) {
  if (p.needsColumns) return t('اختر عمود الطالب وعمود الدرجة لنطابق الملف', 'Choose the student column and the degree column to match the file');
  if (p.rows == 0) return t('الملف بلا صفوف', 'This file has no rows');
  if (p.matched == 0) return t('لم يطابق أي صف طلاب هذا المقرر', 'No row matches a student of this course');
  if (p.matched == p.rows) {
    return countText(p.rows,
        ar1: 'الصف الوحيد جاهز للحفظ', ar2: 'الصفان جاهزان للحفظ', arFew: 'الصفوف الـ{n} جاهزة للحفظ', arMany: 'الصفوف الـ{n} جاهزة للحفظ',
        en1: 'The one row is ready to save', en: 'All {n} rows are ready to save');
  }
  return t('جاهز للحفظ: ${p.matched} من ${p.rows}', '${p.matched} of ${p.rows} rows are ready to save');
}

String degreesSaveLabel(int n) => countText(n,
    ar1: 'حفظ درجة واحدة', ar2: 'حفظ درجتين', arFew: 'حفظ {n} درجات', arMany: 'حفظ {n} درجة', en1: 'Save 1 degree', en: 'Save {n} degrees');

class DegreesApi {
  DegreesApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _base = '/api/v1/exam/exams';

  Future<Uint8List> template(int examId) => _api.getBytes('$_base/$examId/degrees/template');

  Future<(DegreesPreview?, EngineResult)> preview(int examId,
      {required String fileName, required Uint8List bytes, String? matchColumn, String? degreeColumn, double? maxScore}) async {
    final r = await engineCall(() => _api.postMultipart('$_base/$examId/degrees/preview',
        fields: {'match_column': ?matchColumn, 'degree_column': ?degreeColumn, 'max_score': ?(maxScore == null ? null : fullMarkText(maxScore))}, fileField: 'file', fileName: fileName, fileBytes: bytes));
    return (r.ok ? DegreesPreview.fromJson(asMap(r.map)) : null, r);
  }

  Future<EngineResult> commit(int examId, {required String importKey, required double maxScore}) =>
      engineCall(() => _api.post('$_base/$examId/degrees/commit', body: {'import_key': importKey, 'max_score': maxScore}));
}
