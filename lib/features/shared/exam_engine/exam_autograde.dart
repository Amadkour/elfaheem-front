// Open-answer auto-grading as the review screens show it (contract A3 – A5, back D-673..D-677; front D-688), the
// pure part (unit-tested: test/org/exam_autograde_test.dart):
//
//   AutoGrade       the tiers' proposal: which tier decided, the answer kind, the long answer's points with the
//                   character span of the student's sentence that matched each, the keywords found / missing, and the
//                   remembered teacher decision that settled it. Read from the online `auto_feedback` (the review
//                   item's `proposal`), a paper short answer's `reading.auto` and an essay run's `reading.auto`.
//   autoPointRuns   the student's text cut into runs, each marked with the state of the point it matched
//   Nb2Chars        an NB2 character-box reading (contract B): every box with its confidence, the doubtful ones
//   AnswerMemoryApi a question's remembered decisions: list / forget one (A5)
//
// Never decide a mark here: the score and what is final are the engine's.
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_engine_api.dart';

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
List<String> _strs(Object? v) => v is List ? [for (final x in v) if (x is Map) '${x['term'] ?? ''}' else '$x'] : const [];

/// One point of a long answer and how the student's text covered it.
class AutoPoint {
  const AutoPoint({required this.idx, required this.text, this.weight = 1, this.sentence, this.start, this.end, this.score = 0, this.state = 'missing'});

  factory AutoPoint.fromJson(Map<String, dynamic> j) => AutoPoint(
        idx: asInt(j['idx']),
        text: '${j['text'] ?? ''}',
        weight: _d(j['weight']) ?? 1,
        sentence: j['sentence']?.toString(),
        start: j['start'] == null ? null : asInt(j['start']),
        end: j['end'] == null ? null : asInt(j['end']),
        score: _d(j['score']) ?? 0,
        state: '${j['state'] ?? 'missing'}',
      );

  final int idx;
  final String text;
  final double weight, score;
  final String? sentence;
  final int? start, end;

  /// matched | partial | missing | contradicted | unsure.
  final String state;

  bool get covered => state == 'matched' || state == 'partial';
  bool get hasSpan => start != null && end != null && end! > start!;
}

/// The remembered teacher decision that settled (or vetoed) this answer.
class AutoMemoryHit {
  const AutoMemoryHit({required this.id, required this.verdict, this.fraction, this.decisions = 1});
  final int id;
  final String verdict;
  final double? fraction;
  final int decisions;
}

/// The tiers' proposal for one open answer (contract A3 / A4).
class AutoGrade {
  const AutoGrade({
    required this.tier,
    this.kind,
    this.decided = false,
    this.score,
    this.version,
    this.found = const [],
    this.missing = const [],
    this.points = const [],
    this.memory,
  });

  /// null when [v] carries no tier (an older engine, or a proposal from before this job).
  static AutoGrade? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final tier = j['tier']?.toString();
    if (tier == null || tier.isEmpty) return null;
    final kw = asMap(j['keywords']);
    final mem = j['memory'] is Map ? asMap(j['memory']) : null;
    return AutoGrade(
      tier: tier,
      kind: j['kind']?.toString(),
      decided: j['decided'] == true,
      score: _d(j['score']),
      version: j['tiers_version']?.toString(),
      found: _strs(kw['found']),
      missing: _strs(kw['missing']),
      points: [for (final p in asMapList(j['points'])) AutoPoint.fromJson(p)],
      memory: mem == null ? null : AutoMemoryHit(id: asInt(mem['id']), verdict: '${mem['verdict'] ?? ''}', fraction: _d(mem['fraction']), decisions: asInt(mem['decisions'], 1)),
    );
  }

  /// empty | memory | exact | fuzzy | embedding | nli | review.
  final String tier;

  /// word | short | long.
  final String? kind;
  final bool decided;
  final double? score;
  final String? version;
  final List<String> found, missing;
  final List<AutoPoint> points;
  final AutoMemoryHit? memory;

  List<AutoPoint> get coveredPoints => [for (final p in points) if (p.covered) p];

  /// Points the answer does not cover (missing, or not sure enough to credit).
  List<AutoPoint> get missingPoints => [for (final p in points) if (p.state == 'missing' || p.state == 'unsure') p];
  List<AutoPoint> get contradictedPoints => [for (final p in points) if (p.state == 'contradicted') p];
}

/// The tier that decided, in words.
String autoTierText(String tier) => switch (tier) {
      'empty' => t('إجابة فارغة', 'Empty answer'),
      'key_verified' => t('الخط المكتوب طابق المفتاح', 'Handwriting matched the key'),
      'memory' => t('قرار سابق لك', 'Your earlier decision'),
      'exact' => t('مطابقة تامة', 'Exact match'),
      'fuzzy' => t('مطابقة مع خطأ إملائي', 'Match with a spelling slip'),
      'embedding' => t('قريبة في المعنى', 'Close in meaning'),
      'nli' => t('حَكَم الاستنتاج', 'Inference judge'),
      'review' => t('تحتاج قرارك', 'Needs your decision'),
      _ => tier,
    };

/// One line on how the proposal was reached (shown under the tier).
String autoTierHint(AutoGrade a) => switch (a.tier) {
      'memory' => a.memory == null
          ? t('صحّحتَ الإجابة نفسها من قبل', 'You marked the same answer before')
          : t('صحّحتَ الإجابة نفسها من قبل (${a.memory!.decisions} قرار)', 'You marked the same answer before (${a.memory!.decisions} decision${a.memory!.decisions == 1 ? '' : 's'})'),
      'exact' => t('تطابق الإجابة النموذجية أو بديلاً مقبولاً', 'Matches the model answer or an accepted alternative'),
      'fuzzy' => t('تطابق مع اختلاف حروف قليلة', 'Matches with a few letters off'),
      'embedding' => t('معناها قريب من الإجابة النموذجية', 'Its meaning is close to the model answer'),
      'nli' => t('النقاط حُسمت بالاستنتاج من النموذج', 'The points were settled by inference from the model answer'),
      'review' => t('لم تحسمها المراحل الآلية: الدرجة اقتراح فقط', 'The automatic steps did not settle it: the mark is only a suggestion'),
      'key_verified' => t('صورة الإجابة تدعم إجابة المفتاح، فحُسمت دون مراجعة', 'The answer image supports the key, so it was settled without review'),
      _ => '',
    };

String autoPointStateText(String s) => switch (s) {
      'matched' => t('مذكورة', 'Covered'),
      'partial' => t('مذكورة جزئياً', 'Partly covered'),
      'contradicted' => t('تناقض الإجابة', 'Contradicted'),
      'unsure' => t('غير مؤكدة', 'Not sure'),
      _ => t('ناقصة', 'Missing'),
    };

/// The student's [text] cut into (run, state) pieces: a run inside a point's span carries that point's state
/// (contradicted wins over matched over partial over unsure where spans overlap), the rest null. Spans out of range
/// are clipped; missing points have none.
List<(String, String?)> autoPointRuns(String text, Iterable<AutoPoint> points) {
  if (text.isEmpty) return const [];
  const rank = {'contradicted': 4, 'matched': 3, 'partial': 2, 'unsure': 1};
  final marks = List<String?>.filled(text.length, null);
  for (final p in points) {
    final r = rank[p.state];
    if (r == null || !p.hasSpan) continue;
    final a = p.start!.clamp(0, text.length), b = p.end!.clamp(0, text.length);
    for (var i = a; i < b; i++) {
      final cur = marks[i];
      if (cur == null || (rank[cur] ?? 0) < r) marks[i] = p.state;
    }
  }
  final out = <(String, String?)>[];
  var from = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marks[i] != marks[from]) {
      out.add((text.substring(from, i), marks[from]));
      from = i;
    }
  }
  return out;
}

// ── NB2 character boxes (contract B: answer.nb2) ─────────────────────────────────────────────────────────────────

class Nb2Char {
  const Nb2Char(this.ch, this.conf, {this.alt, this.low = false});
  final String ch;
  final double? conf;

  /// The reader's runner-up for a doubtful box.
  final String? alt;
  final bool low;
}

/// An NB2 reading: per character box (unit `chars`), or a line (unit `line`, no boxes).
class Nb2Chars {
  const Nb2Chars({required this.unit, required this.read, this.chars = const [], this.nearMissFrom, this.confidence});

  static Nb2Chars? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final low = {for (final x in (j['low_chars'] is List ? j['low_chars'] as List : const [])) asInt(x)};
    final chars = [
      for (final (i, c) in asMapList(j['chars']).indexed)
        Nb2Char('${c['ch'] ?? ''}', _d(c['conf']), alt: c['alt']?.toString(), low: low.contains(i) || c['ok'] == false),
    ];
    // the server lists every box of the row; the unused ones after the answer are empty (`ch: ""`): not drawn
    while (chars.isNotEmpty && chars.last.ch.isEmpty && !chars.last.low) {
      chars.removeLast();
    }
    final nm = j['near_miss'] is Map ? asMap(j['near_miss']) : null;
    return Nb2Chars(
      unit: '${j['unit'] ?? 'chars'}',
      read: '${j['read'] ?? ''}',
      chars: chars,
      nearMissFrom: nm != null && nm['applied'] == true ? nm['from']?.toString() : null,
      confidence: _d(j['confidence']),
    );
  }

  final String unit, read;
  final List<Nb2Char> chars;

  /// The reading before a doubtful box was moved to its runner-up to match the key (D-680); null when untouched.
  final String? nearMissFrom;
  final double? confidence;

  int get lowCount => chars.where((c) => c.low).length;
}

// ── answer memory (A5) ───────────────────────────────────────────────────────────────────────────────────────────

class AnswerMemoryItem {
  const AnswerMemoryItem({required this.id, required this.text, required this.verdict, this.fraction, this.decisions = 1, this.conflict = false, this.source = 'mark', this.updatedAt});

  factory AnswerMemoryItem.fromJson(Map<String, dynamic> j) => AnswerMemoryItem(
        id: asInt(j['id']),
        text: '${j['text'] ?? ''}',
        verdict: '${j['verdict'] ?? ''}',
        fraction: _d(j['fraction']),
        decisions: asInt(j['decisions'], 1),
        conflict: j['conflict'] == true,
        source: '${j['source'] ?? 'mark'}',
        updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}'),
      );

  final int id, decisions;
  final String text, verdict, source;
  final double? fraction;
  final bool conflict;
  final DateTime? updatedAt;
}

List<AnswerMemoryItem> answerMemoryOf(Map<String, dynamic> j) => [for (final i in asMapList(j['items'])) AnswerMemoryItem.fromJson(i)];

String answerMemoryVerdictText(String v) => switch (v) {
      'right' => t('صحيحة', 'Right'),
      'partial' => t('صحيحة جزئياً', 'Partly right'),
      'wrong' => t('خاطئة', 'Wrong'),
      _ => v,
    };

String answerMemorySourceText(String s) => switch (s) {
      'paper' => t('من الأوراق الممسوحة', 'From scanned papers'),
      'essay_run' => t('من تصحيح الأوراق المكتوبة', 'From written papers'),
      _ => t('من التصحيح الإلكتروني', 'From online marking'),
    };

/// A question's remembered decisions (its managers only).
class AnswerMemoryApi {
  AnswerMemoryApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  Future<EngineResult> list(int questionId, {int limit = 100}) => engineCall(() => _api.get('$base/questions/$questionId/answer-memory', queryParams: {'limit': limit}));

  /// 204; 404 `memory_not_found`.
  Future<EngineResult> forget(int questionId, int id) => engineCall(() => _api.delete('$base/questions/$questionId/answer-memory/$id'));
}
