// The paper exam's plan and its student attributes on the server (back contract OFFLINE_FLOW_CONTRACT.md §2 / §3,
// D-694 / D-695): the plan with its routing, and every attribute a copy can carry with its coverage, the sample student
// and the custom ones. The parsers are pure (test/org/offline_flow_test.dart); the calls are `ApiClient` through
// `engineCall`, so a refusal is an [EngineResult] with the server's code.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/hub/create/offline_flow.dart';

/// The most attributes a plan takes (contract §2, `plan_attributes_too_many`).
const kMaxPlanAttributes = 12;

/// One attribute of `GET /exams/{id}/attributes`.
class ExamAttribute {
  const ExamAttribute({required this.key, required this.source, required this.labelAr, required this.labelEn, this.filled = 0, this.masked = false, this.editable = false, this.exam = false});
  final String key;

  /// builtin · core · datalab · file · exam.
  final String source;
  final String labelAr, labelEn;
  final int filled;
  final bool masked, editable;

  /// One of this exam's custom attributes (`x:` on a file exam, a Data Lab column with `exam: true` on a course exam).
  final bool exam;

  String get label => t(labelAr.isEmpty ? labelEn : labelAr, labelEn.isEmpty ? labelAr : labelEn);
  bool get custom => exam || source == 'exam';

  static ExamAttribute fromJson(Map<String, dynamic> j) => ExamAttribute(
        key: '${j['key'] ?? ''}',
        source: '${j['source'] ?? ''}',
        labelAr: '${j['label_ar'] ?? ''}',
        labelEn: '${j['label_en'] ?? ''}',
        filled: asInt(j['filled']),
        masked: j['masked'] == true,
        editable: j['editable'] == true,
        exam: j['exam'] == true || '${j['source'] ?? ''}' == 'exam',
      );
}

/// `GET /exams/{id}/attributes`.
class ExamAttributes {
  const ExamAttributes({this.studentsSource = 'none', this.total = 0, this.items = const [], this.selected = const [], this.sampleName = '', this.sample = const {}});

  /// course · file · none.
  final String studentsSource;
  final int total;
  final List<ExamAttribute> items;

  /// The keys the plan prints now (the server's default when the plan has none).
  final List<String> selected;
  final String sampleName;

  /// The sample student's value of each attribute, as it prints.
  final Map<String, String> sample;

  static ExamAttributes fromJson(Map<String, dynamic> j) {
    final s = asMap(j['students']);
    final sample = asMap(j['sample']);
    final values = asMap(sample['values']);
    return ExamAttributes(
      studentsSource: '${s['source'] ?? 'none'}',
      total: asInt(s['total']),
      items: [for (final a in asMapList(j['attributes'])) ExamAttribute.fromJson(a)],
      selected: [for (final k in (j['selected'] as List?) ?? const []) '$k'],
      sampleName: '${sample['name'] ?? ''}',
      sample: {for (final e in values.entries) e.key: '${e.value ?? ''}'},
    );
  }

  ExamAttribute? byKey(String key) => items.where((a) => a.key == key).firstOrNull;

  /// The file columns a custom attribute can copy its values from.
  List<ExamAttribute> get fileColumns => [for (final a in items) if (a.source == 'file') a];
}

/// The keys to print: [wanted] in its order, without what the exam does not have, the name always first, at most
/// [kMaxPlanAttributes].
List<String> cleanAttributeKeys(List<String> wanted, ExamAttributes all) {
  final known = {for (final a in all.items) a.key};
  final out = <String>['name'];
  for (final k in wanted) {
    if (k != 'name' && known.contains(k) && !out.contains(k)) out.add(k);
  }
  return out.length > kMaxPlanAttributes ? out.sublist(0, kMaxPlanAttributes) : out;
}

/// The keys to start the step on: what the plan holds, else what this teacher printed last time (those the exam has),
/// else the server's selection.
List<String> startingAttributeKeys(ExamAttributes all, {List<String> plan = const [], List<String> remembered = const []}) {
  if (plan.isNotEmpty) return cleanAttributeKeys(plan, all);
  final last = cleanAttributeKeys(remembered, all);
  if (last.length > 1) return last;
  return cleanAttributeKeys(all.selected, all);
}

/// `POST /exams/{id}/attributes/{key}/file`.
class AttributeFileResult {
  const AttributeFileResult({this.rows = 0, this.matched = 0, this.written = 0, this.unmatched = 0, this.duplicates = 0});
  final int rows, matched, written, unmatched, duplicates;

  static AttributeFileResult fromJson(Map<String, dynamic> j) => AttributeFileResult(
        rows: asInt(j['rows']),
        matched: asInt(j['matched']),
        written: asInt(j['written']),
        unmatched: asMapList(j['unmatched']).length,
        duplicates: asMapList(j['duplicates']).length,
      );
}

/// A refused plan / attribute call, in words (contract §2 / §3 codes).
String offlinePlanErrorText(EngineResult r) => switch (r.code) {
      'plan_layout_invalid' => t('طريقة ورقة الإجابة غير صالحة', 'The answer sheet layout is not valid'),
      'plan_bubble_required' => t('اختر نموذج التظليل أولًا', 'Choose the bubble form first'),
      'plan_bubble_invalid' => t('نموذج التظليل غير متاح', 'The bubble form is not available'),
      'plan_copies_invalid' => t('اختيار النسخ غير صالح', 'The copies choice is not valid'),
      'plan_students_invalid' => t('مصدر الطلاب لا يناسب هذا الاختبار', 'That student source does not fit this exam'),
      'plan_attribute_unknown' => t('أحد البيانات المختارة لم يعد موجودًا', 'One of the chosen attributes no longer exists'),
      'plan_attributes_too_many' => t('$kMaxPlanAttributes بيانًا على الأكثر', 'At most $kMaxPlanAttributes attributes'),
      'exam_locked' || 'exam_closed' => t('لا يمكن تعديل هذا الاختبار الآن', 'This exam can no longer be changed'),
      'attributes_too_many' => t('10 بيانات مخصصة على الأكثر لكل اختبار', 'At most 10 custom attributes per exam'),
      'versions_shuffle_options' => t('مربعات الاختيار في ورقة الإجابة تتبع ترتيب الاختيارات، فأوقف خلط الاختيارات', 'The choice boxes on the answer sheet follow the option order: turn off shuffling the choices'),
      'attribute_label_required' => t('اكتب اسم البيان', 'Write the attribute\'s name'),
      'attribute_from_unknown' || 'attribute_column_unknown' => t('لم نجد هذا العمود في الملف', 'That column is not in the file'),
      'attributes_need_students' => t('أضف الطلاب أولًا', 'Add the students first'),
      'datalab_columns_limit' => t('وصل جدول المقرر إلى أقصى عدد من الأعمدة', 'The course sheet holds no more columns'),
      'attribute_readonly' => t('قيم هذا البيان لا تُعدَّل من هنا', 'This attribute\'s values cannot be edited here'),
      'student_not_in_course' => t('أحد الطلاب ليس في المقرر', 'Someone is not a student of the course'),
      'attribute_not_found' => t('البيان غير موجود', 'The attribute does not exist'),
      'bad_people_file' => t('تعذّرت قراءة الملف', 'The file could not be read'),
      'file_too_large' => t('الملف أكبر من 2 ميجابايت', 'The file is larger than 2 MB'),
      'roster_unavailable' => t('تعذّر الوصول إلى طلاب المقرر الآن. حاول بعد قليل', 'The course\'s students cannot be reached right now. Try again shortly'),
      'forbidden' => t('لا تملك صلاحية تعديل جدول المقرر', 'You may not change the course sheet'),
      _ => r.message.isNotEmpty ? r.message : t('تعذّر الطلب', 'The request failed'),
    };

class OfflinePlanApi {
  OfflinePlanApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = ExamEngineApi.base;

  /// Validates and stores the v2 plan; the answer is the GET's.
  Future<EngineResult> putPlan(int examId, OfflinePlan plan) => engineCall(() => _api.put('$_b/exams/$examId/offline-plan', body: {'plan': plan.toJson()}));

  Future<EngineResult> attributes(int examId) => engineCall(() => _api.get('$_b/exams/$examId/attributes'));

  /// [from]: a file column to copy the values from (exams with a student list).
  Future<EngineResult> createAttribute(int examId, {required String labelAr, required String labelEn, String? from}) =>
      engineCall(() => _api.post('$_b/exams/$examId/attributes', body: {'label_ar': labelAr, 'label_en': labelEn, 'from': ?from}));

  Future<EngineResult> putAttributeValues(int examId, String key, List<(int, String)> values) => engineCall(() => _api.put(
      '$_b/exams/$examId/attributes/${Uri.encodeComponent(key)}',
      body: {
        'values': [for (final (id, v) in values) {'student_id': id, 'value': v}],
      }));

  /// [column]: a header as written, or a 1-based column number.
  Future<EngineResult> attributeFile(int examId, String key, String name, Uint8List bytes, {required String column}) => engineCall(
      () => _api.postFiles('$_b/exams/$examId/attributes/${Uri.encodeComponent(key)}/file', files: [(name, bytes)], field: 'file', fields: {'column': column}));

  Future<EngineResult> attributeValues(int examId, String key) => engineCall(() => _api.get('$_b/exams/$examId/attributes/${Uri.encodeComponent(key)}/values'));
}
