// Open-ended answers, the key (D-686, contract A1 / A2 in ../back/docs/grading/AUTOGRADE_CONTRACT.md): the pure part.
//
// An open answer is one of four kinds: a number (the `numeric` question type, unchanged), one word, a short answer or a
// long answer (`answer.kind` = word | short | long on `short_answer` / `essay`). The model answer is the ONLY input the
// teacher must give: the server derives the alternatives, keywords and points from it (`answer.derived`, written on
// every save), and `POST /questions/derive-key` previews them while the teacher types. Everything else is an optional
// override kept next to `model` in the answer key: `kind`, `keywords`, `points`, and `match_by` (exact wording only, or
// the meaning). An old question has none of these and opens and saves exactly as before.
//
// Unit-tested in test/org/exam_open_key_test.dart; drawn by exam_open_key_widgets.dart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asDouble, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show RubricKeyword, fmtPoints;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';

/// The kill switch of the derived key preview and the grading tiers (contract A6).
const kExamAutoGradeFeatureKey = 'exam.auto_grade';

/// The four kinds of open answer, in the order of the builder's chips.
enum OpenKind { numeric, word, short, long }

/// The kinds a `short_answer` / `essay` key can carry (a number is its own question type).
const kTextKinds = <OpenKind>[OpenKind.word, OpenKind.short, OpenKind.long];

/// `answer.kind` as the server writes it; null for a number.
String? openKindKey(OpenKind k) => k == OpenKind.numeric ? null : k.name;

OpenKind? openKindOf(Object? v) => switch ('${v ?? ''}'.trim().toLowerCase()) {
      'word' => OpenKind.word,
      'short' => OpenKind.short,
      'long' => OpenKind.long,
      _ => null,
    };

/// The question types an open kind lives on: a number is `numeric`, a long answer an `essay`, the rest `short_answer`.
String openTypeFor(OpenKind k) => switch (k) {
      OpenKind.numeric => 'numeric',
      OpenKind.long => 'essay',
      _ => 'short_answer',
    };

bool isOpenKindType(String type) => type == 'numeric' || type == 'short_answer' || type == 'essay';

/// The server's rule when no kind is given (contract A1): a rubric of 2+ criteria is long; else by the model answer's
/// words, up to 3 one word, up to 30 short, more long.
OpenKind inferOpenKind(String model, {int rubricCriteria = 0}) {
  if (rubricCriteria >= 2) return OpenKind.long;
  final words = model.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (words == 0) return OpenKind.short;
  if (words <= 3) return OpenKind.word;
  if (words <= 30) return OpenKind.short;
  return OpenKind.long;
}

/// The kind an open question shows: the teacher's, else the question type's own default (a number; an essay is long),
/// else inferred from the model answer.
OpenKind openKindShown(String type, {OpenKind? teacher, String model = '', int rubricCriteria = 0}) {
  if (type == 'numeric') return OpenKind.numeric;
  if (teacher != null) return teacher;
  if (type == 'essay') return OpenKind.long;
  return inferOpenKind(model, rubricCriteria: rubricCriteria);
}

String openKindLabel(OpenKind k) => switch (k) {
      OpenKind.numeric => t('رقم', 'Number'),
      OpenKind.word => t('كلمة واحدة', 'One word'),
      OpenKind.short => t('إجابة قصيرة', 'Short answer'),
      OpenKind.long => t('إجابة طويلة', 'Long answer'),
    };

String openKindHint(OpenKind k) => switch (k) {
      OpenKind.numeric => t('قيمة رقمية، ويمكن قبول هامش ووحدات', 'A number; a margin and units can be accepted'),
      OpenKind.word => t('كلمة أو مصطلح واحد', 'One word or term'),
      OpenKind.short => t('فكرة واحدة في جملة أو اثنتين', 'One idea, a sentence or two'),
      OpenKind.long => t('عدة أفكار، تُمنح الدرجة لكل فكرة', 'Several ideas, each earns its share'),
    };

/// The model answer's hint per kind.
String openModelHint(OpenKind k) => switch (k) {
      OpenKind.word => t('الكلمة الصحيحة', 'The right word'),
      OpenKind.long => t('اكتب الإجابة الكاملة كما تتوقعها', 'Write the full answer you expect'),
      _ => t('اكتب الإجابة الصحيحة', 'Write the right answer'),
    };

// ── points and keywords ─────────────────────────────────────────────────────────────────────────────────────────

/// One idea of a long answer, with its share of the marks (weights are relative, default 1).
class KeyPoint {
  const KeyPoint(this.text, [this.weight = 1]);
  final String text;
  final double weight;

  Map<String, dynamic> toJson() => {'text': text, if (weight != 1) 'weight': weight};

  static KeyPoint? fromJson(Object? j) {
    if (j is String) return j.trim().isEmpty ? null : KeyPoint(j.trim());
    final m = asMap(j);
    final text = '${m['text'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    final w = asDouble(m['weight'], 1);
    return KeyPoint(text, w > 0 ? w : 1);
  }

  @override
  bool operator ==(Object other) => other is KeyPoint && other.text == text && other.weight == weight;

  @override
  int get hashCode => Object.hash(text, weight);
}

final _weightSuffix = RegExp(r'\s*[×x\*]\s*(\d+(\.\d+)?)$');

/// One point per line, an optional "×2" suffix for its weight (the keywords' own convention).
List<KeyPoint> parseKeyPoints(String text) {
  final out = <KeyPoint>[];
  for (final raw in text.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    var w = 1.0;
    final m = _weightSuffix.firstMatch(line);
    if (m != null) {
      w = double.parse(m.group(1)!);
      line = line.substring(0, m.start).trim();
    }
    if (line.isEmpty) continue;
    out.add(KeyPoint(line, w > 0 ? w : 1));
  }
  return out;
}

String keyPointsText(List<KeyPoint> points) => points.map((p) => '${p.text}${p.weight != 1 ? ' ×${fmtPoints(p.weight)}' : ''}').join('\n');

/// A keyword as the server sends it: a plain string, or `{term, synonyms?, weight?}`.
RubricKeyword? keywordOf(Object? j) {
  if (j is String) return j.trim().isEmpty ? null : RubricKeyword(j.trim());
  final m = asMap(j);
  final term = '${m['term'] ?? ''}'.trim();
  if (term.isEmpty) return null;
  return RubricKeyword(term, [for (final s in (m['synonyms'] as List?) ?? const []) if ('$s'.trim().isNotEmpty) '$s'.trim()], asDouble(m['weight'], 1));
}

List<RubricKeyword> keywordsOf(Object? list) => [for (final k in (list is List ? list : const [])) ?keywordOf(k)];

bool sameKeywords(List<RubricKeyword> a, List<RubricKeyword> b) =>
    jsonEncode([for (final k in a) k.toJson()]) == jsonEncode([for (final k in b) k.toJson()]);

// ── the teacher's overrides ─────────────────────────────────────────────────────────────────────────────────────

/// How an answer is matched: by its meaning (the default: any wording that says it), or only the model answer and the
/// accepted wordings (spelling slips still forgiven).
enum MatchBy { meaning, exact }

/// What the teacher may set beyond the model answer, kept in the answer key (null / empty = the server derives it).
class OpenKeyExtras {
  OpenKeyExtras({this.kind, this.keywords, this.points, this.matchBy = MatchBy.meaning});

  OpenKind? kind;
  List<RubricKeyword>? keywords;
  List<KeyPoint>? points;
  MatchBy matchBy;

  /// The answer-key fields this owns.
  static const fields = {'kind', 'keywords', 'points', 'match_by'};

  bool get hasOverrides => keywords != null || points != null || matchBy != MatchBy.meaning;

  OpenKeyExtras copy() => OpenKeyExtras(
        kind: kind,
        keywords: keywords == null ? null : List.of(keywords!),
        points: points == null ? null : List.of(points!),
        matchBy: matchBy,
      );

  static OpenKeyExtras fromAnswer(Map answer) {
    final kws = keywordsOf(answer['keywords']);
    final pts = [for (final p in (answer['points'] is List ? answer['points'] as List : const [])) ?KeyPoint.fromJson(p)];
    return OpenKeyExtras(
      kind: openKindOf(answer['kind']),
      keywords: kws.isEmpty ? null : kws,
      points: pts.isEmpty ? null : pts,
      matchBy: '${answer['match_by'] ?? ''}' == 'exact' ? MatchBy.exact : MatchBy.meaning,
    );
  }

  /// Writes these into an answer key, removing what is unset (so a reset really goes back to the derived key).
  void writeTo(Map<String, dynamic> a) {
    for (final f in fields) {
      a.remove(f);
    }
    final k = kind == null ? null : openKindKey(kind!);
    if (k != null) a['kind'] = k;
    if (keywords != null && keywords!.isNotEmpty) a['keywords'] = [for (final x in keywords!) x.toJson()];
    if (points != null && points!.isNotEmpty) a['points'] = [for (final p in points!.take(kMaxKeyPoints)) p.toJson()];
    if (matchBy == MatchBy.exact) a['match_by'] = 'exact';
  }
}

/// The server takes 1-20 points (contract A1).
const kMaxKeyPoints = 20;

// ── the derived key (server-owned) ──────────────────────────────────────────────────────────────────────────────

/// `answer.derived` / the preview's `derived` (contract A1).
class DerivedKey {
  const DerivedKey({
    this.kind,
    this.kindSource = 'inferred',
    this.alternatives = const [],
    this.keywords = const [],
    this.points = const [],
    this.keywordsSource = 'model',
    this.pointsSource = 'model',
  });

  final OpenKind? kind;
  final String kindSource, keywordsSource, pointsSource;
  final List<String> alternatives;
  final List<RubricKeyword> keywords;
  final List<KeyPoint> points;

  static DerivedKey fromJson(Object? j) {
    final m = asMap(j);
    return DerivedKey(
      kind: openKindOf(m['kind']),
      kindSource: '${m['kind_source'] ?? 'inferred'}',
      alternatives: [for (final a in (m['alternatives'] is List ? m['alternatives'] as List : const [])) if ('$a'.trim().isNotEmpty) '$a'.trim()],
      keywords: keywordsOf(m['keywords']),
      points: [for (final p in (m['points'] is List ? m['points'] as List : const [])) ?KeyPoint.fromJson(p)],
      keywordsSource: '${m['keywords_source'] ?? 'model'}',
      pointsSource: '${m['points_source'] ?? 'model'}',
    );
  }
}

/// The answer of `POST /questions/derive-key` (contract A2): the kind, the derived key, and what the grader will use.
class DeriveKeyPreview {
  const DeriveKeyPreview({this.kind, this.kindSource = 'inferred', this.derived = const DerivedKey(), this.keywords = const [], this.points = const []});

  final OpenKind? kind;
  final String kindSource;
  final DerivedKey derived;

  /// `effective`: the teacher's override, else the derived.
  final List<RubricKeyword> keywords;
  final List<KeyPoint> points;

  bool get keywordsAreTeachers => derived.keywordsSource == 'teacher';
  bool get pointsAreTeachers => derived.pointsSource == 'teacher' || derived.pointsSource == 'rubric';

  /// The accepted wordings beyond the model answer itself (the first is the model's normalised form).
  List<String> get otherWordings => derived.alternatives.length > 1 ? derived.alternatives.sublist(1) : const [];

  static DeriveKeyPreview fromJson(Map<String, dynamic> j) {
    final d = DerivedKey.fromJson(j['derived']);
    final eff = asMap(j['effective']);
    final kws = eff.containsKey('keywords') ? keywordsOf(eff['keywords']) : d.keywords;
    final pts = eff.containsKey('points') ? [for (final p in asMapList(eff['points'])) ?KeyPoint.fromJson(p)] : d.points;
    return DeriveKeyPreview(
      kind: openKindOf(j['kind']) ?? d.kind,
      kindSource: '${j['kind_source'] ?? d.kindSource}',
      derived: d,
      keywords: kws,
      points: pts,
    );
  }
}

/// The body of `POST /questions/derive-key`: the key as it stands (model, alternatives, the teacher's overrides).
Map<String, dynamic> deriveKeyBody({int? orgId, int? courseId, required String type, required String prompt, required Map<String, dynamic> answer}) {
  final a = <String, dynamic>{
    'model': '${answer['model'] ?? ''}'.trim(),
    'kind': answer['kind'],
    'keywords': answer['keywords'],
    'points': answer['points'],
    if (answer['alternatives'] is List && (answer['alternatives'] as List).isNotEmpty) 'alternatives': answer['alternatives'],
    if (answer['rubric'] is List && (answer['rubric'] as List).isNotEmpty) 'rubric': answer['rubric'],
  };
  return {
    'org_id': ?orgId,
    'course_id': ?courseId,
    'type': type == 'essay' ? 'essay' : 'short_answer',
    'body': {'prompt': prompt.trim()},
    'answer': a,
  };
}

/// Nothing to preview yet, or nothing the server can derive from.
bool deriveKeyReady(Map<String, dynamic> body) => '${asMap(body['answer'])['model'] ?? ''}'.trim().isNotEmpty;

/// The preview's state for the strip: idle (nothing typed), loading, a preview, or hidden (switched off, an engine
/// without the route) — a preview that cannot be had is never an error the teacher must deal with.
enum DerivePhase { idle, loading, ready, hidden, failed }

/// `true` when the failure means the preview does not exist here (kill switch, an older engine): show nothing.
bool deriveKeyHidden(EngineResult r) => r.unavailable || r.code == 'feature_disabled' || r.status == 403 || r.code == 'bad_question_type';

String deriveKeyErrorText(EngineResult r) => switch (r.code) {
      'model_answer_required' => t('اكتب الإجابة النموذجية أولاً', 'Write the model answer first'),
      'bad_answer_key' => t('في المفتاح قيمة غير صالحة: راجع الإعدادات المتقدمة', 'Something in the key is not valid: check Advanced'),
      _ => t('تعذّر عرض ما استُخرج الآن', 'Could not show what was derived right now'),
    };

class DeriveKeyApi {
  DeriveKeyApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<EngineResult> preview(Map<String, dynamic> body) => engineCall(() => _api.post('${ExamEngineApi.base}/questions/derive-key', body: body));
}

/// Waits for a pause in typing, then asks for the preview once; the same body is never asked twice in a row, and an
/// answer that comes back after a newer request is dropped.
class DeriveKeyDebouncer {
  DeriveKeyDebouncer({required this.call, required this.onChange, this.pause = const Duration(milliseconds: 700)});

  final Future<EngineResult> Function(Map<String, dynamic> body) call;
  final void Function() onChange;
  final Duration pause;

  DerivePhase phase = DerivePhase.idle;
  DeriveKeyPreview? preview;
  String? error;

  Timer? _timer;
  String? _asked;
  int _seq = 0;
  bool _disposed = false;

  /// The key changed: a preview follows after [pause].
  void update(Map<String, dynamic> body) {
    if (phase == DerivePhase.hidden || _disposed) return;
    _timer?.cancel();
    if (!deriveKeyReady(body)) {
      _seq++;
      _asked = null;
      final changed = phase != DerivePhase.idle || preview != null;
      phase = DerivePhase.idle;
      preview = null;
      error = null;
      if (changed) onChange();
      return;
    }
    final sig = jsonEncode(body);
    if (sig == _asked) return;
    _timer = Timer(pause, () => _ask(body, sig));
  }

  Future<void> _ask(Map<String, dynamic> body, String sig) async {
    final mine = ++_seq;
    _asked = sig;
    phase = DerivePhase.loading;
    onChange();
    final r = await call(body);
    if (_disposed || mine != _seq) return;
    if (r.ok) {
      preview = DeriveKeyPreview.fromJson(r.map);
      error = null;
      phase = DerivePhase.ready;
    } else if (deriveKeyHidden(r)) {
      preview = null;
      phase = DerivePhase.hidden;
    } else {
      _asked = null;   // the same key may be asked again
      error = deriveKeyErrorText(r);
      phase = DerivePhase.failed;
    }
    onChange();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
