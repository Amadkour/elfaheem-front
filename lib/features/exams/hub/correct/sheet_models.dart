// The corrected sheet (Exam Hub, F4): the pure part of the scan-to-result loop. The server's two replies as models, the
// maths that puts a box of source pixels on the fitted photo, and the small decisions the screen makes.
//
//   GET /api/v1/exam/exams/{id}/omr/pages/{page_id}/sheet     {ready, page_id, status, batch_id?, image_url?, size?,
//       student?, total?, review_count?, questions?[{question_id, n, state, max, score, selected, correct, is_correct,
//       row_box, marked_boxes, correct_boxes}]}. ready false: only page_id + status. Boxes are [x, y, w, h] in the pixels of `size`.
//   GET /api/v1/exam/exams/{id}/omr/batches/{batch_id}/sheets {items:[{page_id, page_no, status, student_name, score, max}]}
// A page read without a homography has no box at all and still has its marks: the screen then lists them on the side.
library;

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// `[x, y, w, h]` as a source-pixel rectangle; null when malformed or empty.
Rect? sheetRectOf(Object? v) {
  if (v is! List || v.length < 4) return null;
  final x = _d(v[0]), y = _d(v[1]), w = _d(v[2]), h = _d(v[3]);
  if (x == null || y == null || w == null || h == null || w <= 0 || h <= 0) return null;
  return Rect.fromLTWH(x, y, w, h);
}

List<Rect> _rects(Object? v) => [for (final b in (v is List ? v : const [])) ?sheetRectOf(b)];

List<String> _strings(Object? v) => [for (final s in (v is List ? v : const [])) '$s'];

/// How a question's marks are drawn. Never a colour alone: [right] carries a tick, [wrong] a cross, [open] a dot.
enum SheetTone { right, wrong, open }

class SheetQuestion {
  const SheetQuestion({
    required this.questionId,
    required this.n,
    this.state = '',
    this.max = 0,
    this.score,
    this.selected = const [],
    this.correct = const [],
    this.isCorrect,
    this.rowBox,
    this.markedBoxes = const [],
    this.correctBoxes = const [],
  });

  final int questionId;

  /// The number printed on the sheet.
  final int n;
  final String state;
  final double max;
  final double? score;
  final List<String> selected, correct;

  /// null: not marked yet (a person still has to decide).
  final bool? isCorrect;
  final Rect? rowBox;
  final List<Rect> markedBoxes, correctBoxes;

  static SheetQuestion fromJson(Map<String, dynamic> j) => SheetQuestion(
        questionId: asInt(j['question_id']),
        n: asInt(j['n']),
        state: '${j['state'] ?? ''}',
        max: _d(j['max']) ?? 0,
        score: _d(j['score']),
        selected: _strings(j['selected']),
        correct: _strings(j['correct']),
        isCorrect: j['is_correct'] is bool ? j['is_correct'] as bool : null,
        rowBox: sheetRectOf(j['row_box']),
        markedBoxes: _rects(j['marked_boxes']),
        correctBoxes: _rects(j['correct_boxes']),
      );

  SheetTone get tone => isCorrect == null ? SheetTone.open : (isCorrect! ? SheetTone.right : SheetTone.wrong);

  bool get hasBoxes => rowBox != null || markedBoxes.isNotEmpty || correctBoxes.isNotEmpty;

  /// "1.5/2", or "–/2" while no mark is given.
  String get degreeText => '${score == null ? '–' : sheetNum(score!)}/${sheetNum(max)}';
}

/// 2 → "2", 1.5 → "1.5", 1.25 → "1.25".
String sheetNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// Pages that will not get any better by waiting.
const kSheetDeadStates = {'rejected', 'failed', 'purged', 'dismissed', 'replaced'};

class SheetView {
  const SheetView({
    required this.ready,
    required this.pageId,
    this.status = '',
    this.batchId,
    this.imageUrl,
    this.source,
    this.studentId,
    this.studentName,
    this.identifier,
    this.score,
    this.max,
    this.reviewCount = 0,
    this.questions = const [],
  });

  final bool ready;
  final int pageId;
  final String status;
  final int? batchId;
  final String? imageUrl;

  /// The pixels every box is measured in; null when the server has no size for this reading.
  final Size? source;
  final int? studentId;
  final String? studentName;
  final String? identifier;
  final double? score, max;
  final int reviewCount;
  final List<SheetQuestion> questions;

  static SheetView fromJson(Map<String, dynamic> j) {
    final size = j['size'];
    final w = size is List && size.length >= 2 ? _d(size[0]) : null;
    final h = size is List && size.length >= 2 ? _d(size[1]) : null;
    final who = asMap(j['student']);
    final total = asMap(j['total']);
    return SheetView(
      ready: j['ready'] == true,
      pageId: asInt(j['page_id']),
      status: '${j['status'] ?? ''}',
      batchId: j['batch_id'] == null ? null : asInt(j['batch_id']),
      imageUrl: j['image_url']?.toString(),
      source: w != null && h != null && w > 0 && h > 0 ? Size(w, h) : null,
      studentId: who.isEmpty ? null : asInt(who['id']),
      studentName: who.isEmpty ? null : '${who['name'] ?? ''}',
      identifier: who['identifier_masked']?.toString(),
      score: _d(total['score']),
      max: _d(total['max']),
      reviewCount: asInt(j['review_count']),
      questions: [for (final q in asMapList(j['questions'])) SheetQuestion.fromJson(q)]..sort((a, b) => a.n.compareTo(b.n)),
    );
  }

  /// The boxes can be drawn: the reading has a size and at least one box. False = the marks go in the side list.
  bool get canDraw => source != null && questions.any((q) => q.hasBoxes);

  /// The page will never have a result: the reading refused it.
  bool get dead => !ready && kSheetDeadStates.contains(status);

  int get rightCount => questions.where((q) => q.isCorrect == true).length;
  int get wrongCount => questions.where((q) => q.isCorrect == false).length;
  int get openCount => questions.where((q) => q.isCorrect == null).length;

  SheetQuestion? question(int n) {
    for (final q in questions) {
      if (q.n == n) return q;
    }
    return null;
  }
}

/// One row of the arrows' list.
class SheetRow {
  const SheetRow({required this.pageId, this.pageNo = 1, this.status = '', this.studentName, this.score, this.max});

  final int pageId;
  final int pageNo;
  final String status;
  final String? studentName;
  final double? score, max;

  static SheetRow fromJson(Map<String, dynamic> j) => SheetRow(
        pageId: asInt(j['page_id']),
        pageNo: asInt(j['page_no'], 1),
        status: '${j['status'] ?? ''}',
        studentName: (j['student_name'] == null || '${j['student_name']}'.isEmpty) ? null : '${j['student_name']}',
        score: _d(j['score']),
        max: _d(j['max']),
      );

  SheetRow copyWith({String? status, String? studentName, double? score, double? max}) => SheetRow(
      pageId: pageId,
      pageNo: pageNo,
      status: status ?? this.status,
      studentName: studentName ?? this.studentName,
      score: score ?? this.score,
      max: max ?? this.max);
}

List<SheetRow> sheetRowsOf(Map<String, dynamic> j) => [for (final r in asMapList(j['items'])) SheetRow.fromJson(r)];

// ── geometry ────────────────────────────────────────────────────────────────────────────────────────────────────

/// The rectangle a picture of [image] takes when fitted (contain, centred) in [box]. Empty sizes give [Rect.zero].
Rect sheetFitRect(Size box, Size image) {
  if (box.width <= 0 || box.height <= 0 || image.width <= 0 || image.height <= 0) return Rect.zero;
  final s = box.width / image.width < box.height / image.height ? box.width / image.width : box.height / image.height;
  final w = image.width * s, h = image.height * s;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

/// A box of source pixels on the fitted photo.
Rect sheetToScreen(Rect box, Size source, Rect photo) {
  if (source.width <= 0 || source.height <= 0) return Rect.zero;
  final sx = photo.width / source.width, sy = photo.height / source.height;
  return Rect.fromLTWH(photo.left + box.left * sx, photo.top + box.top * sy, box.width * sx, box.height * sy);
}

/// A point on the fitted photo back in source pixels.
Offset sheetToSource(Offset p, Size source, Rect photo) {
  if (photo.width <= 0 || photo.height <= 0) return Offset.zero;
  return Offset((p.dx - photo.left) * source.width / photo.width, (p.dy - photo.top) * source.height / photo.height);
}

/// The question under [p] (a point on the box the photo is fitted in): the row whose box holds it, a few source
/// pixels of slack for a finger; the nearest row's centre when two overlap. Null when none.
int? sheetHitQuestion(Offset p, SheetView v, Size box) {
  final source = v.source;
  if (source == null) return null;
  final src = sheetToSource(p, source, sheetFitRect(box, source));
  final slack = source.longestSide * .006;
  int? best;
  var bestD = double.infinity;
  for (final q in v.questions) {
    final boxes = [?q.rowBox, ...q.markedBoxes, ...q.correctBoxes];
    for (final b in boxes) {
      if (!b.inflate(slack).contains(src)) continue;
      final d = (b.center - src).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = q.n;
      }
    }
  }
  return best;
}

// ── walking the batch ───────────────────────────────────────────────────────────────────────────────────────────

/// Where the Next button goes from [index] of [count] sheets: on the last sheet it opens the camera for the next paper.
bool sheetNextOpensCamera(int index, int count) => count == 0 || index >= count - 1;

/// [pageId]'s place in [rows]; 0 when it is not listed (yet) and the list is not empty, -1 when empty.
int sheetIndexOf(List<SheetRow> rows, int? pageId) {
  if (rows.isEmpty) return -1;
  final i = pageId == null ? -1 : rows.indexWhere((r) => r.pageId == pageId);
  return i < 0 ? 0 : i;
}

/// A live event about the watched sheet that makes a read worthwhile: the page reached a final state.
bool sheetEventIsFinal(String status) => status == 'processed' || status == 'review' || kSheetDeadStates.contains(status);

class SheetApi {
  SheetApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> sheet(int examId, int pageId) => engineCall(() => _api.get('$_b/exams/$examId/omr/pages/$pageId/sheet'));

  Future<EngineResult> sheets(int examId, int batchId) => engineCall(() => _api.get('$_b/exams/$examId/omr/batches/$batchId/sheets'));
}
