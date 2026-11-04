// Mark sessions (grade review by camera and mark import from paper, contract §5): the client of
// `/api/v1/exam/mark-sessions…` and the plain-value models of its answers. Every call returns an [EngineResult] (the
// failure's code and the server's `detail`), nothing here reads a platform object.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../../../admin/admin_common.dart' show asInt, asMap;
import '../exam_engine_api.dart' show EngineResult, engineCall;
import '../paper/scan/omr_scan.dart' show photoNameOf;

/// The live event kind of a mark session's progress (`job_updated {kind: mark_session, id}`).
const kMarkSessionJobKind = 'mark_session';

/// The push / live `exam_notice` kind sent to the creator when the session's queue empties.
const kMarkSessionDoneNotice = 'mark_session_done';

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// A mark / total as the person reads it: no trailing zeros (`12`, `12.5`, `0.25`).
String markNumberText(double? v) {
  if (v == null) return '—';
  final r = (v * 100).round() / 100;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
}

enum MarkMode { review, import }

MarkMode markModeOf(Object? v) => '$v' == 'import' ? MarkMode.import : MarkMode.review;

enum MarkList { match, mismatch, unreadable }

class MarkCounts {
  const MarkCounts({this.match = 0, this.mismatch = 0, this.unreadable = 0, this.pending = 0, this.applied = 0, this.kept = 0});
  final int match, mismatch, unreadable, pending, applied, kept;

  /// Rows read so far (the three lists together).
  int get read => match + mismatch + unreadable;

  factory MarkCounts.fromJson(Object? v) {
    final j = asMap(v);
    return MarkCounts(
      match: asInt(j['match']),
      mismatch: asInt(j['mismatch']),
      unreadable: asInt(j['unreadable']),
      pending: asInt(j['pending']),
      applied: asInt(j['applied']),
      kept: asInt(j['kept']),
    );
  }

  int forList(MarkList l) => switch (l) {
        MarkList.match => match,
        MarkList.mismatch => mismatch,
        MarkList.unreadable => unreadable,
      };
}

class MarkSession {
  const MarkSession({
    required this.id,
    required this.courseId,
    required this.mode,
    required this.columnKey,
    required this.columnMax,
    required this.paperMax,
    this.examId,
    this.templateId,
    this.roundingStep,
    this.open = true,
    this.counts = const MarkCounts(),
    this.createdAt,
  });

  final int id, courseId;
  final int? examId, templateId;
  final MarkMode mode;
  final String columnKey;
  final double columnMax, paperMax;
  final double? roundingStep;
  final bool open;
  final MarkCounts counts;
  final String? createdAt;

  bool get converts => (columnMax - paperMax).abs() > 0.0001 && columnMax > 0 && paperMax > 0;

  factory MarkSession.fromJson(Map<String, dynamic> j) {
    final s = j['session'] is Map ? asMap(j['session']) : j;
    return MarkSession(
      id: asInt(s['id']),
      courseId: asInt(s['course_id']),
      examId: s['exam_id'] == null ? null : asInt(s['exam_id']),
      templateId: s['template_id'] == null ? null : asInt(s['template_id']),
      mode: markModeOf(s['mode']),
      columnKey: '${s['column_key'] ?? ''}',
      columnMax: _num(s['column_max']) ?? 0,
      paperMax: _num(s['paper_max']) ?? 0,
      roundingStep: _num(s['rounding_step']),
      open: '${s['status'] ?? 'open'}' != 'closed',
      counts: MarkCounts.fromJson(j['counts'] ?? s['counts']),
      createdAt: s['created_at']?.toString(),
    );
  }
}

/// One mark read on the paper.
class MarkPart {
  const MarkPart({required this.fieldId, this.questionNo, this.value, this.conf, this.max, this.status = 'ok', this.cropUrl});
  final String fieldId;
  final String? questionNo;
  final double? value, conf, max;

  /// ok | unreadable | above_max | … (anything but ok needs a person).
  final String status;
  final String? cropUrl;

  bool get ok => status == 'ok';

  factory MarkPart.fromJson(Map<String, dynamic> j) => MarkPart(
        fieldId: '${j['field_id'] ?? ''}',
        questionNo: j['question_no']?.toString(),
        value: _num(j['value']),
        conf: _num(j['conf']),
        max: _num(j['max']),
        status: '${j['status'] ?? 'ok'}',
        cropUrl: j['crop_url']?.toString(),
      );
}

class MarkRow {
  const MarkRow({
    required this.id,
    this.pageId,
    this.studentId,
    this.studentName,
    this.identifierMasked = '',
    this.identifierMethod,
    this.marks = const [],
    this.written,
    this.computed,
    this.used,
    this.scaled,
    this.recorded,
    this.diff,
    this.issues = const [],
    this.issueTexts = const {},
    this.status = 'open',
  });

  final int id;
  final int? pageId, studentId;
  final String? studentName;
  final String identifierMasked;
  final String? identifierMethod;
  final List<MarkPart> marks;
  final double? written, computed, used, scaled, recorded, diff;
  final List<String> issues;

  /// The server's own wording per issue code (`issue_texts`: code -> (ar, en)); empty from an older server.
  final Map<String, ({String ar, String en})> issueTexts;

  /// open | applied | kept | dismissed
  final String status;

  bool get decided => status != 'open';
  bool get hasStudent => studentId != null;
  bool has(String issue) => issues.contains(issue);

  /// The value Apply would write ([scaled] first; the paper's used total when nothing was converted).
  double? get proposed => scaled ?? used;

  /// Issues that only describe the normal case of an import or a conversion: a row with nothing else is "clean".
  static const infoIssues = {'scaled', 'not_recorded'};
  bool get clean => hasStudent && marks.every((m) => m.ok) && issues.every(infoIssues.contains);

  factory MarkRow.fromJson(Map<String, dynamic> j) {
    final st = j['student'] is Map ? asMap(j['student']) : const <String, dynamic>{};
    final idf = asMap(j['identifier']);
    return MarkRow(
      id: asInt(j['id']),
      pageId: j['page_id'] == null ? null : asInt(j['page_id']),
      studentId: st['id'] == null ? null : asInt(st['id']),
      studentName: st['name']?.toString(),
      identifierMasked: '${idf['value_masked'] ?? ''}',
      identifierMethod: idf['method']?.toString(),
      marks: [for (final m in (j['marks'] as List?) ?? const []) if (m is Map) MarkPart.fromJson(asMap(m))],
      written: _num(j['paper_total_written']),
      computed: _num(j['paper_total_computed']),
      used: _num(j['paper_total_used']),
      scaled: _num(j['scaled']),
      recorded: _num(j['recorded']),
      diff: _num(j['diff']),
      issues: [for (final i in (j['issues'] as List?) ?? const []) '$i'],
      issueTexts: {
        for (final i in (j['issue_texts'] as List?) ?? const [])
          if (i is Map && i['code'] != null) '${i['code']}': (ar: '${i['ar'] ?? ''}', en: '${i['en'] ?? ''}'),
      },
      status: '${j['status'] ?? 'open'}',
    );
  }
}

/// What a page upload came to: 202 queued · 422 retake (quality gate) · 409 page_duplicate · anything else an error.
enum MarkPageKind { queued, retake, duplicate, error }

class MarkPageOutcome {
  const MarkPageOutcome(this.kind, {this.code = '', this.message = '', this.pageId});
  final MarkPageKind kind;
  final String code;

  /// The server's own sentence in the current language (empty: the screen has its own text for [code]).
  final String message;
  final int? pageId;

  bool get ok => kind == MarkPageKind.queued;
}

MarkPageOutcome markPageOutcome(EngineResult r, {required bool arabic}) {
  if (r.ok) return MarkPageOutcome(MarkPageKind.queued, pageId: r.map['page_id'] == null ? null : asInt(r.map['page_id']));
  final code = r.code ?? '${r.detail['code'] ?? ''}';
  final en = '${r.detail['message_en'] ?? ''}', ar = '${r.detail['message'] ?? r.message}';
  final msg = arabic ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  if (r.status == 409 && (code == 'page_duplicate' || code.isEmpty)) return MarkPageOutcome(MarkPageKind.duplicate, code: 'page_duplicate', message: msg);
  if (r.status == 422) return MarkPageOutcome(MarkPageKind.retake, code: code, message: msg);
  return MarkPageOutcome(MarkPageKind.error, code: code, message: msg);
}

/// `…/live-hint` answers `{ready, corners, tip_code, tip_ar, tip_en}`; the camera layer speaks `{ok, code, en, ar,
/// corners, corners_found, stat, motion}`. This maps one into the other (an answer already in the OMR shape is kept).
Map<String, dynamic> markHintToOmr(Map<String, dynamic> j) {
  if (j.containsKey('ok') || j.containsKey('code')) return j;
  final ready = j['ready'] == true;
  final corners = (j['corners'] as List?) ?? const [];
  return {
    'ok': ready,
    'code': ready ? 'ready' : '${j['tip_code'] ?? 'no_sheet'}',
    'en': '${j['tip_en'] ?? ''}',
    'ar': '${j['tip_ar'] ?? ''}',
    'corners': corners,
    'corners_found': j['corners_found'] ?? corners.length,
    'stat': j['stat'],
    'motion': j['motion'] ?? (ready ? 0.0 : null),
    'blocking': j['blocking'],
  };
}

class MarkSessionsApi {
  MarkSessionsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam/mark-sessions';

  Future<EngineResult> create({
    required int courseId,
    required MarkMode mode,
    required int templateId,
    required String columnKey,
    int? examId,
    double? roundingStep,
  }) =>
      engineCall(() => _api.post(_b, body: {
            'course_id': courseId,
            'mode': mode.name,
            'template_id': templateId,
            'column_key': columnKey,
            'exam_id': ?examId,
            'rounding_step': ?roundingStep,
          }));

  Future<EngineResult> list(int courseId) => engineCall(() => _api.get(_b, queryParams: {'course_id': courseId}));

  Future<EngineResult> get(int sid) => engineCall(() => _api.get('$_b/$sid'));

  Future<EngineResult> close(int sid) => engineCall(() => _api.post('$_b/$sid/close', body: const {}));

  Future<EngineResult> liveHint(int sid, Uint8List jpeg, {String? prev}) =>
      engineCall(() => _api.postFiles('$_b/$sid/live-hint', files: [('frame.jpg', jpeg)], field: 'frame', fields: {'prev': ?prev}));

  /// One page; [camera] false = picked from files. The quality gate answers on the request.
  Future<EngineResult> addPage(int sid, Uint8List image, {bool camera = true, String? name}) => engineCall(() => _api.postFiles('$_b/$sid/pages',
      files: [(name ?? photoNameOf(image), image)], field: 'image', fields: {'source': camera ? 'camera' : 'upload'}));

  Future<EngineResult> rows(int sid, {MarkList? list, String? status}) =>
      engineCall(() => _api.get('$_b/$sid/rows', queryParams: {'list': ?list?.name, 'status': ?status}));

  Future<EngineResult> decide(int sid, int rid, String action, {int? studentId, Map<String, double>? marks, double? value, String? reason}) =>
      engineCall(() => _api.post('$_b/$sid/rows/$rid/decide', body: {
            'action': action,
            'student_id': ?studentId,
            'marks': ?marks,
            'value': ?value,
            if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
          }));

  /// A signed crop image (a mark's `crop_url`); null when it cannot be read.
  Future<Uint8List?> image(String? signedUrl) async {
    final u = Uri.tryParse(signedUrl ?? '');
    if (u == null || u.path.isEmpty) return null;
    final i = u.path.indexOf('/api/v1/');
    final path = i >= 0 ? u.path.substring(i) : u.path;
    try {
      return await _api.getBytes(path, queryParams: u.queryParameters);
    } catch (_) {
      return null;
    }
  }
}
