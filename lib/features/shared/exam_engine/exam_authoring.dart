// Exam Engine authoring (Phase 5 contract, D-018): the pure side of building exams in the app — question drafts for
// every type with their body / answer-key JSON, exam settings, sections, the proctoring policy, accommodations, the
// publish gate, lifecycle, and the `ExamAuthoringApi` over the one ApiClient.
//
// Server contract (the source of truth): ../../../../../back/exam_engine/routers/{questions,exams,proctoring}.py,
// services/questions.py (per-type validation), services/grading_objective.py (answer-key shapes), services/exams.py
// (settings, sections, placements, publish rules) and back/FLUTTER_API_CHANGES.md "phase 5" / "phase 6".
// Nothing here touches the widget tree; `exam_authoring_screen.dart` drives these pieces.
import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asDouble, asInt, asMap, asMapList, t;
import 'exam_engine_api.dart';
import 'exam_grading.dart' show resultsViews;
import 'exam_media.dart';
import 'exam_taking.dart' show examCodeText;

// ── vocabularies (exam_engine/models.py) ────────────────────────────────────────────────────────────────────────

const questionTypes = <String>['mcq_single', 'mcq_multi', 'true_false', 'fill_blank', 'matching', 'ordering', 'numeric',
  'short_answer', 'essay', 'file_upload'];
const openQuestionTypes = <String>{'short_answer', 'essay', 'file_upload'};
const sectionModes = <String>['online', 'paper', 'hybrid'];
const sectionNavigations = <String>['free', 'one_way'];
const resultsPolicies = <String>['hidden', 'after_submit', 'when_published'];
const examPlatforms = <String>['web', 'mobile'];
const proctorConsequences = <String>['warn', 'flag', 'lock', 'auto_submit', 'reject'];

/// Event kinds a rule may count (EVENT_KINDS minus NEVER_COUNTED in services/proctoring.py).
const proctorCategories = <String>['looking_away', 'tab_switch', 'other_app', 'background', 'fullscreen_exit', 'copy_paste',
  'screenshot', 'no_face', 'multiple_faces', 'speech'];

/// Which sensor a category needs (MONITORED in services/proctoring.py); the rest are platform events.
const categorySensor = <String, String>{'multiple_faces': 'camera', 'no_face': 'camera', 'looking_away': 'camera', 'speech': 'mic', 'screenshot': 'screen'};

String questionTypeLabel(String type) => switch (type) {
      'mcq_single' => t('اختيار من متعدد (إجابة واحدة)', 'Multiple choice (one answer)'),
      'mcq_multi' => t('اختيار من متعدد (عدة إجابات)', 'Multiple choice (several answers)'),
      'true_false' => t('صح أو خطأ', 'True / false'),
      'fill_blank' => t('أكمل الفراغ', 'Fill in the blank'),
      'matching' => t('مطابقة', 'Matching'),
      'ordering' => t('ترتيب', 'Ordering'),
      'numeric' => t('إجابة رقمية', 'Numeric'),
      'short_answer' => t('إجابة قصيرة', 'Short answer'),
      'essay' => t('مقالي', 'Essay'),
      'file_upload' => t('رفع ملف', 'File upload'),
      _ => type,
    };

String sectionModeLabel(String mode) => switch (mode) {
      'online' => t('إلكتروني', 'Online'),
      'paper' => t('ورقي', 'Paper'),
      'hybrid' => t('مختلط', 'Hybrid'),
      _ => mode,
    };

String navigationLabel(String nav) => switch (nav) {
      'free' => t('تنقل حر', 'Free navigation'),
      'one_way' => t('اتجاه واحد (بلا عودة)', 'One way (no going back)'),
      _ => nav,
    };

String resultsPolicyLabel(String p) => switch (p) {
      'hidden' => t('مخفية عن الطلاب', 'Hidden from students'),
      'after_submit' => t('تظهر بعد التسليم', 'Shown after submitting'),
      'when_published' => t('تظهر عند نشرها', 'Shown when you publish them'),
      _ => p,
    };

String consequenceLabel(String c) => switch (c) {
      'warn' => t('تنبيه الطالب', 'Warn the student'),
      'flag' => t('تعليم للمراجعة', 'Flag for review'),
      'lock' => t('قفل المحاولة', 'Lock the attempt'),
      'auto_submit' => t('تسليم تلقائي', 'Submit automatically'),
      'reject' => t('رفض المحاولة', 'Reject the attempt'),
      _ => c,
    };

String categoryLabel(String c) => switch (c) {
      'looking_away' => t('النظر بعيداً عن الشاشة', 'Looking away'),
      'tab_switch' => t('تبديل التبويب', 'Switching tabs'),
      'other_app' => t('فتح تطبيق آخر', 'Opening another app'),
      'background' => t('إرسال التطبيق للخلفية', 'App sent to background'),
      'fullscreen_exit' => t('الخروج من ملء الشاشة', 'Leaving full screen'),
      'copy_paste' => t('نسخ ولصق', 'Copy / paste'),
      'screenshot' => t('لقطة شاشة', 'Screenshot'),
      'no_face' => t('لا يظهر وجه', 'No face visible'),
      'multiple_faces' => t('أكثر من وجه', 'More than one face'),
      'speech' => t('كلام مسموع', 'Speech heard'),
      _ => c,
    };

String examStatusLabel(String s) => switch (s) {
      'draft' => t('مسودة', 'Draft'),
      'published' => t('منشور', 'Published'),
      'closed' => t('مغلق', 'Closed'),
      'archived' => t('مؤرشف', 'Archived'),
      _ => s,
    };

// ── small helpers ───────────────────────────────────────────────────────────────────────────────────────────────

/// Server instants are naive UTC ISO strings; `Z` / offsets are honoured too.
DateTime? parseEngineUtc(dynamic v) {
  if (v == null || '$v'.isEmpty) return null;
  final s = '$v';
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

String? engineIso(DateTime? utc) => utc?.toUtc().toIso8601String();

double? parseNum(String s) {
  final v = s.trim().translate();
  if (v.isEmpty) return null;
  return double.tryParse(v);
}

int? parseIntField(String s) {
  final v = parseNum(s);
  if (v == null || v != v.roundToDouble()) return null;
  return v.toInt();
}

extension _ArabicDigits on String {
  String translate() {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in split('')) {
      final i = ar.indexOf(ch);
      b.write(i >= 0 ? '$i' : (ch == '٫' ? '.' : ch));
    }
    return b.toString();
  }
}

String fmtPoints(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// "a, b ; c" → ["a", "b", "c"] (commas, Arabic commas, semicolons and new lines separate).
List<String> splitList(String s) => s.split(RegExp(r'[,،;\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// Option ids a, b, c … z, then o27, o28 …: the next one not used yet.
String nextOptionId(Iterable<String> used) {
  final u = used.toSet();
  for (var i = 0; i < 26; i++) {
    final id = String.fromCharCode(97 + i);
    if (!u.contains(id)) return id;
  }
  var n = 27;
  while (u.contains('o$n')) {
    n++;
  }
  return 'o$n';
}

/// How many blanks the prompt marks with "___" (three or more underscores).
int blankMarkers(String prompt) => RegExp(r'_{3,}').allMatches(prompt).length;

var _uid = 0;
int _nextUid() => ++_uid;

// ── question drafts ─────────────────────────────────────────────────────────────────────────────────────────────

class QOption {
  QOption(this.id, [this.text = '']) : uid = _nextUid();
  final int uid;
  String id;
  String text;
}

class RubricKeyword {
  RubricKeyword(this.term, [this.synonyms = const [], this.weight = 1]);
  final String term;
  final List<String> synonyms;
  final double weight;

  Map<String, dynamic> toJson() => {'term': term, if (synonyms.isNotEmpty) 'synonyms': synonyms, if (weight != 1) 'weight': weight};
  static RubricKeyword fromJson(Map<String, dynamic> j) =>
      RubricKeyword('${j['term'] ?? ''}', [for (final s in (j['synonyms'] as List?) ?? const []) '$s'], asDouble(j['weight'], 1));
}

/// One keyword per line: "term = synonym, synonym" (a "×2" suffix on the term doubles its weight).
List<RubricKeyword> parseKeywords(String text) {
  final out = <RubricKeyword>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('=');
    var term = parts.first.trim();
    var weight = 1.0;
    final m = RegExp(r'\s*[×x\*]\s*(\d+(\.\d+)?)$').firstMatch(term);
    if (m != null) {
      weight = double.parse(m.group(1)!);
      term = term.substring(0, m.start).trim();
    }
    if (term.isEmpty) continue;
    final syns = parts.length > 1 ? splitList(parts.sublist(1).join('=')) : const <String>[];
    out.add(RubricKeyword(term, syns, weight));
  }
  return out;
}

String keywordsText(List<RubricKeyword> kws) => kws
    .map((k) => '${k.term}${k.weight != 1 ? ' ×${fmtPoints(k.weight)}' : ''}${k.synonyms.isEmpty ? '' : ' = ${k.synonyms.join(', ')}'}')
    .join('\n');

class RubricCriterion {
  RubricCriterion({required this.id, this.criterion = '', this.points = 1, this.model = '', List<RubricKeyword>? keywords})
      : uid = _nextUid(),
        keywords = keywords ?? [];
  final int uid;
  String id;
  String criterion;
  double points;
  String model;
  List<RubricKeyword> keywords;

  Map<String, dynamic> toJson() => {
        'id': id,
        'criterion': criterion.trim(),
        'points': points,
        if (model.trim().isNotEmpty) 'model': model.trim(),
        if (keywords.isNotEmpty) 'keywords': [for (final k in keywords) k.toJson()],
      };

  static RubricCriterion fromJson(Map<String, dynamic> j, int i) => RubricCriterion(
        id: '${j['id'] ?? 'c${i + 1}'}',
        criterion: '${j['criterion'] ?? ''}',
        points: asDouble(j['points'], 1),
        model: '${j['model'] ?? ''}',
        keywords: [for (final k in asMapList(j['keywords'])) RubricKeyword.fromJson(k)],
      );
}

double rubricTotal(Iterable<RubricCriterion> rubric) => rubric.fold(0.0, (s, c) => s + (c.points > 0 ? c.points : 0));

String nextCriterionId(Iterable<RubricCriterion> rubric) {
  final used = rubric.map((c) => c.id).toSet();
  var n = rubric.length + 1;
  while (used.contains('c$n')) {
    n++;
  }
  return 'c$n';
}

class MatchPair {
  MatchPair([this.left = '', this.right = '']) : uid = _nextUid();
  final int uid;
  String left;
  String right;
}

class NumericUnit {
  NumericUnit([this.name = '', this.factor = '1']) : uid = _nextUid();
  final int uid;
  String name;

  /// As typed (validated on save): how many base units one of this unit is.
  String factor;
}

class TextItem {
  TextItem([this.text = '']) : uid = _nextUid();
  final int uid;
  String text;
}

/// Everything the editor needs for any type. `body()` / `answer()` build exactly the shapes the server validates
/// and grades; keys the editor does not know (from another client) are kept on a round trip.
class QuestionDraft {
  QuestionDraft({this.type = 'mcq_single'}) {
    if (type == 'mcq_single' || type == 'mcq_multi') options = [QOption('a'), QOption('b')];
    if (type == 'fill_blank') blanks = [TextItem()];
    if (type == 'matching') pairs = [MatchPair(), MatchPair()];
    if (type == 'ordering') items = [TextItem(), TextItem(), TextItem()];
  }

  int? id;
  int? version;
  String type;
  String prompt = '';
  String explanation = '';
  double points = 1;
  List<String> tags = [];
  int difficulty = 3;

  // mcq
  List<QOption> options = [];
  String? correctSingle;
  Set<String> correctMulti = {};
  String multiPartial = 'proportional';
  // true / false
  bool? tfCorrect;
  // fill blank: each blank's accepted answers, comma separated as typed
  List<TextItem> blanks = [];
  String blankPartial = 'per_blank';
  // matching
  List<MatchPair> pairs = [];
  String distractors = '';
  String matchPartial = 'proportional';
  // ordering, in the correct order
  List<TextItem> items = [];
  String orderPartial = 'position';
  // numeric
  String numValue = '';
  String numTolerance = '';
  String toleranceKind = 'abs';
  List<NumericUnit> units = [];
  // open types
  String model = '';
  String alternatives = '';
  List<RubricCriterion> rubric = [];

  Map<String, dynamic> extraBody = {};
  Map<String, dynamic> extraAnswer = {};

  bool get isOpen => openQuestionTypes.contains(type);
  bool get isNew => id == null;

  /// The question's optional image (body `media`, at most one); kept in [extraBody] so it round-trips.
  QuestionMedia? get media => mediaOfBody(extraBody);
  set media(QuestionMedia? m) {
    if (m == null) {
      extraBody.remove('media');
    } else {
      extraBody['media'] = [m.toJson()];
    }
  }

  /// Switch the type of a NEW question: the prompt, points and tags stay, the type's own parts start fresh.
  QuestionDraft withType(String next) {
    final d = QuestionDraft(type: next)
      ..prompt = prompt
      ..explanation = explanation
      ..points = points
      ..tags = List.of(tags)
      ..difficulty = difficulty;
    final m = media;
    if (m != null) d.media = m;
    if ((next == 'mcq_single' || next == 'mcq_multi') && options.isNotEmpty) d.options = options;
    if (openQuestionTypes.contains(next)) {
      d.model = model;
      d.alternatives = alternatives;
      d.rubric = rubric;
    }
    return d;
  }

  static QuestionDraft fromJson(Map<String, dynamic> q) {
    final type = '${q['type'] ?? 'mcq_single'}';
    final body = asMap(q['body']);
    final ans = asMap(q['answer']);
    final d = QuestionDraft(type: type)
      ..id = q['id'] == null ? null : asInt(q['id'])
      ..version = q['version'] == null ? null : asInt(q['version'])
      ..prompt = '${body['prompt'] ?? ''}'
      ..explanation = '${body['explanation'] ?? ''}'
      ..points = asDouble(q['points'], 1)
      ..tags = [for (final t in (q['tags'] as List?) ?? const []) '$t']
      ..difficulty = asInt(q['difficulty'], 3).clamp(1, 5);
    final knownBody = {'prompt', 'explanation'};
    final knownAnswer = <String>{};
    switch (type) {
      case 'mcq_single':
      case 'mcq_multi':
        d.options = [
          for (final o in (body['options'] as List?) ?? const [])
            o is Map ? QOption('${o['id']}', '${o['text'] ?? ''}') : QOption('$o', '$o'),
        ];
        if (type == 'mcq_single') {
          d.correctSingle = ans['correct'] == null ? null : '${ans['correct']}';
        } else {
          d.correctMulti = {for (final c in (ans['correct'] as List?) ?? const []) '$c'};
          d.multiPartial = '${ans['partial'] ?? 'proportional'}';
        }
        knownBody.add('options');
        knownAnswer.addAll({'correct', 'partial'});
      case 'true_false':
        d.tfCorrect = ans['correct'] is bool ? ans['correct'] as bool : null;
        knownAnswer.add('correct');
      case 'fill_blank':
        d.blanks = [
          for (final b in (ans['blanks'] as List?) ?? const []) TextItem(b is List ? b.map((e) => '$e').join(', ') : '$b'),
        ];
        if (d.blanks.isEmpty) d.blanks = [TextItem()];
        d.blankPartial = '${ans['partial'] ?? 'per_blank'}';
        knownBody.add('blanks_count');
        knownAnswer.addAll({'blanks', 'partial'});
      case 'matching':
        final key = asMap(ans['pairs']);
        final left = [for (final l in (body['left'] as List?) ?? const []) '$l'];
        final right = [for (final r in (body['right'] as List?) ?? const []) '$r'];
        d.pairs = [for (final l in left) MatchPair(l, '${key[l] ?? ''}')];
        for (final e in key.entries) {
          if (!left.contains(e.key)) d.pairs.add(MatchPair(e.key, '${e.value}'));
        }
        final used = key.values.map((v) => '$v').toSet();
        d.distractors = right.where((r) => !used.contains(r)).join(', ');
        d.matchPartial = '${ans['partial'] ?? 'proportional'}';
        knownBody.addAll({'left', 'right'});
        knownAnswer.addAll({'pairs', 'partial'});
      case 'ordering':
        final order = [for (final o in (ans['order'] as List?) ?? const []) '$o'];
        d.items = [for (final o in order.isNotEmpty ? order : [for (final i in (body['items'] as List?) ?? const []) '$i']) TextItem(o)];
        d.orderPartial = '${ans['partial'] ?? 'position'}';
        knownBody.add('items');
        knownAnswer.addAll({'order', 'partial'});
      case 'numeric':
        d.numValue = ans['value'] == null ? '' : '${ans['value']}';
        d.numTolerance = ans['tolerance'] == null ? '' : '${ans['tolerance']}';
        d.toleranceKind = '${ans['tolerance_kind'] ?? 'abs'}';
        d.units = [for (final e in asMap(ans['units']).entries) NumericUnit(e.key, '${e.value}')];
        knownBody.add('units');
        knownAnswer.addAll({'value', 'tolerance', 'tolerance_kind', 'units'});
      default:
        d.model = '${ans['model'] ?? ''}';
        d.alternatives = [for (final a in (ans['alternatives'] as List?) ?? const []) '$a'].join('\n');
        final rub = asMapList(ans['rubric']);
        d.rubric = [for (var i = 0; i < rub.length; i++) RubricCriterion.fromJson(rub[i], i)];
        knownAnswer.addAll({'model', 'alternatives', 'rubric'});
    }
    d.extraBody = {for (final e in body.entries) if (!knownBody.contains(e.key)) e.key: e.value};
    d.extraAnswer = {for (final e in ans.entries) if (!knownAnswer.contains(e.key)) e.key: e.value};
    return d;
  }

  /// The body students see (never the key).
  Map<String, dynamic> body() {
    final b = <String, dynamic>{...extraBody, 'prompt': prompt.trim()};
    if (explanation.trim().isNotEmpty) b['explanation'] = explanation.trim();
    switch (type) {
      case 'mcq_single':
      case 'mcq_multi':
        b['options'] = [for (final o in options) {'id': o.id, 'text': o.text.trim()}];
      case 'matching':
        final lefts = [for (final p in pairs) p.left.trim()];
        final rights = <String>[];
        for (final r in [for (final p in pairs) p.right.trim(), ...splitList(distractors)]) {
          if (r.isNotEmpty && !rights.contains(r)) rights.add(r);
        }
        b['left'] = lefts;
        b['right'] = rights;
      case 'ordering':
        b['items'] = [for (final i in items) i.text.trim()];
      case 'numeric':
        if (units.isNotEmpty) b['units'] = [for (final u in units) u.name.trim()];
    }
    return b;
  }

  /// The answer key, in the shapes of services/grading_objective.py.
  Map<String, dynamic> answer() {
    final a = <String, dynamic>{...extraAnswer};
    switch (type) {
      case 'mcq_single':
        a['correct'] = correctSingle;
      case 'mcq_multi':
        a['correct'] = [for (final o in options) if (correctMulti.contains(o.id)) o.id];
        a['partial'] = multiPartial;
      case 'true_false':
        a['correct'] = tfCorrect;
      case 'fill_blank':
        a['blanks'] = [for (final b in blanks) splitList(b.text)];
        a['partial'] = blankPartial;
      case 'matching':
        a['pairs'] = {for (final p in pairs) p.left.trim(): p.right.trim()};
        a['partial'] = matchPartial;
      case 'ordering':
        a['order'] = [for (final i in items) i.text.trim()];
        a['partial'] = orderPartial;
      case 'numeric':
        a['value'] = parseNum(numValue);
        a['tolerance'] = parseNum(numTolerance) ?? 0;
        a['tolerance_kind'] = toleranceKind;
        if (units.isNotEmpty) a['units'] = {for (final u in units) u.name.trim(): parseNum(u.factor)};
      default:
        a['model'] = model.trim();
        final alts = alternatives.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (alts.isNotEmpty) a['alternatives'] = alts;
        if (rubric.isNotEmpty) a['rubric'] = [for (final c in rubric) c.toJson()];
    }
    return a;
  }

  /// [courseId]: a course's teacher creates through their course (they may lack the organization's exam rights).
  Map<String, dynamic> toCreate({int? orgId, int? courseId}) => {
        'org_id': ?orgId,
        'course_id': ?courseId,
        'type': type,
        'body': body(),
        'answer': answer(),
        'points': points,
        'tags': tags,
        'difficulty': difficulty,
      };

  /// PUT = a NEW version; exams keep the version they pinned.
  Map<String, dynamic> toUpdate() => {'body': body(), 'answer': answer(), 'points': points, 'tags': tags, 'difficulty': difficulty};

  /// Client-side check mirroring services/questions.py `validate` (+ a few the server cannot see, like empty option
  /// texts). Returns error codes for [authoringCodeText]; empty = ready to save.
  List<String> validate() {
    final out = <String>[];
    if (prompt.trim().isEmpty) out.add('prompt_required');
    if (!(points > 0)) out.add('points_positive');
    out.addAll(validateMediaList(extraBody['media']));
    switch (type) {
      case 'mcq_single':
      case 'mcq_multi':
        final ids = options.map((o) => o.id).toList();
        if (options.length < 2) out.add('options_required');
        if (ids.toSet().length != ids.length) out.add('duplicate_options');
        if (options.any((o) => o.text.trim().isEmpty)) out.add('option_text_required');
        if (type == 'mcq_single' && (correctSingle == null || !ids.contains(correctSingle))) out.add('bad_answer_key');
        if (type == 'mcq_multi' && (correctMulti.isEmpty || correctMulti.any((c) => !ids.contains(c)))) out.add('bad_answer_key');
      case 'true_false':
        if (tfCorrect == null) out.add('bad_answer_key');
      case 'fill_blank':
        if (blanks.isEmpty || blanks.any((b) => splitList(b.text).isEmpty)) out.add('blank_answer_required');
      case 'matching':
        final lefts = pairs.map((p) => p.left.trim()).toList();
        if (pairs.length < 2) out.add('pairs_required');
        if (pairs.any((p) => p.left.trim().isEmpty || p.right.trim().isEmpty)) out.add('pair_incomplete');
        if (lefts.toSet().length != lefts.length) out.add('duplicate_items');
      case 'ordering':
        final texts = items.map((i) => i.text.trim()).toList();
        if (items.length < 2) out.add('items_required');
        if (texts.any((e) => e.isEmpty)) out.add('item_text_required');
        if (texts.toSet().length != texts.length) out.add('duplicate_items');
      case 'numeric':
        if (parseNum(numValue) == null) out.add('bad_numeric_value');
        final tol = numTolerance.trim().isEmpty ? 0 : parseNum(numTolerance);
        if (tol == null || tol < 0) out.add('bad_tolerance');
        if (units.isNotEmpty) {
          final names = units.map((u) => u.name.trim()).toList();
          if (names.any((n) => n.isEmpty) || names.toSet().length != names.length) out.add('bad_unit');
          final factors = units.map((u) => parseNum(u.factor)).toList();
          if (factors.any((f) => f == null || f <= 0)) out.add('bad_unit_factor');
          if (!factors.contains(1.0)) out.add('unit_base_required');
        }
      default:
        // auto_grade false: the teacher marks it, there is nothing to grade against (services/questions.py)
        final graded = extraAnswer['auto_grade'] != false && type != 'file_upload';
        if (graded && model.trim().isEmpty && rubric.isEmpty) out.add('model_answer_required');
        if (rubric.any((c) => c.criterion.trim().isEmpty || !(c.points > 0))) out.add('bad_rubric');
        final ids = rubric.map((c) => c.id).toList();
        if (ids.toSet().length != ids.length) out.add('bad_rubric');
    }
    return out.toSet().toList();
  }
}

/// One row of the bank list.
class BankQuestion {
  BankQuestion({required this.id, required this.type, required this.prompt, required this.points, required this.tags,
      required this.version, required this.status, required this.raw});
  final int id;
  final String type;
  final String prompt;
  final double points;
  final List<String> tags;
  final int version;
  final String status;
  final Map<String, dynamic> raw;

  QuestionMedia? get media => mediaOfBody(asMap(raw['body']));
  int get difficulty => asInt(raw['difficulty'], 3);

  static BankQuestion fromJson(Map<String, dynamic> q) => BankQuestion(
        id: asInt(q['id']), type: '${q['type'] ?? ''}', prompt: '${asMap(q['body'])['prompt'] ?? ''}', points: asDouble(q['points'], 1),
        tags: [for (final t in (q['tags'] as List?) ?? const []) '$t'], version: asInt(q['current_version'] ?? q['version'], 1),
        status: '${q['status'] ?? 'active'}', raw: q);
}

// ── exam settings ───────────────────────────────────────────────────────────────────────────────────────────────

class ExamDraft {
  int? id;
  int? orgId;
  int? courseId;
  int version = 0;
  String status = 'draft';
  String title = '';
  String description = '';
  DateTime? startsAt;
  DateTime? endsAt;
  int? durationMinutes;
  int maxAttempts = 1;
  bool hasPasscode = false;

  /// null = leave the passcode as it is; '' = remove it; text = the new one.
  String? passcode;
  String resultsPolicy = 'when_published';
  bool highStakes = true;
  bool anonymousGrading = false;
  Set<String> platforms = {'web', 'mobile'};
  double passingPercent = 50;
  bool showPerQuestion = false;
  bool appealsEnabled = true;
  int appealDays = 14;
  int appealsPerAttempt = 5;
  bool independentReviewer = false;

  /// The session whose lessons this exam locks (`settings.session_id`, D-197): students must pass it to open what
  /// comes after that session. null = no lock.
  int? sessionId;

  /// What students see once published (`settings.results_view`): score · answers · answers_key.
  String resultsView = 'score';
  DateTime? resultsPublishedAt;

  /// Every settings key as loaded (grading policy, granted retries …): a settings save never wipes them.
  Map<String, dynamic> settings = {};

  bool get isDraft => status == 'draft';

  static ExamDraft fromJson(Map<String, dynamic> e) {
    final s = asMap(e['settings']);
    final ap = asMap(s['appeals']);
    return ExamDraft()
      ..id = e['id'] == null ? null : asInt(e['id'])
      ..orgId = e['org_id'] == null ? null : asInt(e['org_id'])
      ..courseId = e['course_id'] == null ? null : asInt(e['course_id'])
      ..version = asInt(e['version'])
      ..status = '${e['status'] ?? 'draft'}'
      ..title = '${e['title'] ?? ''}'
      ..description = '${e['description'] ?? ''}'
      ..startsAt = parseEngineUtc(e['starts_at'])
      ..endsAt = parseEngineUtc(e['ends_at'])
      ..durationMinutes = e['duration_minutes'] == null ? null : asInt(e['duration_minutes'])
      ..maxAttempts = asInt(e['max_attempts'], 1)
      ..hasPasscode = e['has_passcode'] == true
      ..resultsPolicy = '${e['results_policy'] ?? 'when_published'}'
      ..highStakes = e['high_stakes'] != false
      ..anonymousGrading = e['anonymous_grading'] == true
      ..platforms = {for (final p in (e['allowed_platforms'] as List?) ?? examPlatforms) '$p'}
      ..passingPercent = asDouble(s['passing_percent'], 50)
      ..showPerQuestion = s['show_per_question'] == true
      ..appealsEnabled = ap['enabled'] != false
      ..appealDays = asInt(ap['days'], 14)
      ..appealsPerAttempt = asInt(ap['per_attempt'], 5)
      ..independentReviewer = ap['independent_reviewer'] == true
      ..sessionId = s['session_id'] == null ? null : asInt(s['session_id'])
      ..resultsView = resultsViews.contains(s['results_view']) ? '${s['results_view']}' : 'score'
      ..resultsPublishedAt = parseEngineUtc(e['results_published_at'])
      ..settings = s;
  }

  ExamDraft copy() => ExamDraft.fromJson(toJsonForCopy())..passcode = passcode;

  Map<String, dynamic> toJsonForCopy() => {
        'id': id, 'org_id': orgId, 'course_id': courseId, 'version': version, 'status': status, 'title': title,
        'description': description, 'starts_at': engineIso(startsAt), 'ends_at': engineIso(endsAt), 'duration_minutes': durationMinutes,
        'max_attempts': maxAttempts, 'has_passcode': hasPasscode, 'results_policy': resultsPolicy, 'high_stakes': highStakes,
        'anonymous_grading': anonymousGrading, 'allowed_platforms': [for (final p in examPlatforms) if (platforms.contains(p)) p],
        'settings': mergedSettings(), 'results_published_at': engineIso(resultsPublishedAt),
      };

  Map<String, dynamic> mergedSettings() => {
        ...settings,
        'passing_percent': passingPercent,
        'show_per_question': showPerQuestion,
        if (sessionId != null) 'session_id': sessionId else if (settings.containsKey('session_id')) 'session_id': null,
        if (resultsView != 'score' || settings.containsKey('results_view')) 'results_view': resultsView,
        'appeals': {
          ...asMap(settings['appeals']),
          'enabled': appealsEnabled,
          'days': appealDays,
          'per_attempt': appealsPerAttempt,
          'independent_reviewer': independentReviewer,
        },
      };

  /// `POST /exams` (no [original]) or `PUT /exams/{id}` against what was loaded. On an update the duration and the
  /// number of attempts are sent only when they changed: the server refuses them once students started (409
  /// `attempts_exist`) even with the same value.
  Map<String, dynamic> toBody({ExamDraft? original}) {
    final b = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'starts_at': engineIso(startsAt),
      'ends_at': engineIso(endsAt),
      'results_policy': resultsPolicy,
      'high_stakes': highStakes,
      'anonymous_grading': anonymousGrading,
      'allowed_platforms': [for (final p in examPlatforms) if (platforms.contains(p)) p],
      'settings': mergedSettings(),
    };
    if (original == null) {
      b['duration_minutes'] = durationMinutes;
      b['max_attempts'] = maxAttempts;
      if (orgId != null) b['org_id'] = orgId;
      if (courseId != null) b['course_id'] = courseId;
      if (passcode != null && passcode!.trim().isNotEmpty) b['passcode'] = passcode!.trim();
    } else {
      if (durationMinutes != original.durationMinutes) b['duration_minutes'] = durationMinutes;
      if (maxAttempts != original.maxAttempts) b['max_attempts'] = maxAttempts;
      if (passcode != null) b['passcode'] = passcode!.trim();
      b['expected_version'] = original.version;
    }
    return b;
  }

  List<String> validate() {
    final out = <String>[];
    if (title.trim().isEmpty) out.add('title_required');
    if (startsAt != null && endsAt != null && !endsAt!.isAfter(startsAt!)) out.add('bad_window');
    if (durationMinutes != null && durationMinutes! <= 0) out.add('bad_duration');
    if (maxAttempts < 0 || maxAttempts > 100) out.add('bad_attempts');
    if (platforms.isEmpty) out.add('platform_required');
    if (passingPercent < 0 || passingPercent > 100) out.add('bad_passing');
    if (appealsEnabled && (appealDays < 1 || appealDays > 365)) out.add('bad_appeal_days');
    if (appealsEnabled && (appealsPerAttempt < 1 || appealsPerAttempt > 50)) out.add('bad_appeal_limit');
    if (status == 'published' && durationMinutes == null && endsAt == null) out.add('duration_required');
    return out;
  }
}

/// The platform recommendation under the web / mobile choice.
String platformAdvice(Set<String> platforms, {required bool highStakes}) {
  if (platforms.isEmpty) return t('اختر منصة واحدة على الأقل', 'Pick at least one platform');
  final web = platforms.contains('web'), mobile = platforms.contains('mobile');
  if (web && mobile) {
    return highStakes
        ? t('للاختبارات المصيرية يُنصح بالويب على حاسوب: ملء الشاشة واكتشاف تبديل التبويب أدق. الجوال يكتشف مغادرة التطبيق ولقطات الشاشة.',
            'For high-stakes exams the web on a computer is recommended: full screen and tab-switch detection are stronger. Mobile detects leaving the app and screenshots.')
        : t('يمكن للطلاب الدخول من الويب أو تطبيق الجوال. المحاولة تبقى على الجهاز الذي بدأت عليه.',
            'Students may sit it on the web or in the mobile app. An attempt stays on the device it started on.');
  }
  if (web) return t('الويب فقط: يُنصح به للاختبارات المصيرية (ملء الشاشة، اكتشاف التبويب).', 'Web only: recommended for high-stakes exams (full screen, tab detection).');
  return t('الجوال فقط: التطبيق يمنع لقطات الشاشة ويكتشف مغادرة التطبيق.', 'Mobile only: the app blocks screenshots and detects leaving the app.');
}

// ── sections and placements ─────────────────────────────────────────────────────────────────────────────────────

class SectionDraft {
  int? id;
  int position = 0;
  String title = '';
  String instructions = '';
  String mode = 'online';
  double weight = 1;
  int? timeBoxMinutes;
  String navigation = 'free';
  bool shuffleQuestions = false;
  bool shuffleOptions = false;
  int? poolSize;
  List<String> poolTags = [];

  static SectionDraft fromJson(Map<String, dynamic> s) => SectionDraft()
    ..id = s['id'] == null ? null : asInt(s['id'])
    ..position = asInt(s['position'])
    ..title = '${s['title'] ?? ''}'
    ..instructions = '${s['instructions'] ?? ''}'
    ..mode = '${s['mode'] ?? 'online'}'
    ..weight = asDouble(s['weight'], 1)
    ..timeBoxMinutes = s['time_box_minutes'] == null ? null : asInt(s['time_box_minutes'])
    ..navigation = '${s['navigation'] ?? 'free'}'
    ..shuffleQuestions = s['shuffle_questions'] == true
    ..shuffleOptions = s['shuffle_options'] == true
    ..poolSize = s['pool_size'] == null ? null : asInt(s['pool_size'])
    ..poolTags = [for (final t in (s['pool_tags'] as List?) ?? const []) '$t'];

  SectionDraft copy() => SectionDraft.fromJson(toBody()..['id'] = id..['position'] = position);

  /// Every field (the server compares structural ones with what it has, so unchanged values are fine after publishing).
  Map<String, dynamic> toBody() => {
        'title': title.trim(),
        'instructions': instructions.trim().isEmpty ? null : instructions.trim(),
        'mode': mode,
        'weight': weight,
        'time_box_minutes': timeBoxMinutes,
        'navigation': navigation,
        'shuffle_questions': shuffleQuestions,
        'shuffle_options': shuffleOptions,
        'pool_size': poolSize,
        'pool_tags': poolTags,
      };

  /// Only what may change after publishing (texts and the time box).
  Map<String, dynamic> toPublishedBody() => {
        'title': title.trim(),
        'instructions': instructions.trim().isEmpty ? null : instructions.trim(),
        'time_box_minutes': timeBoxMinutes,
      };

  List<String> validate() => [
        if (!(weight > 0)) 'bad_weight',
        if (timeBoxMinutes != null && timeBoxMinutes! <= 0) 'bad_time_box_minutes',
        if (poolSize != null && poolSize! <= 0) 'bad_pool_size',
      ];
}

class PlacedQuestion {
  PlacedQuestion({required this.placementId, required this.questionId, required this.type, required this.prompt, required this.points,
      required this.required, required this.pinnedVersion, required this.outdated, required this.tags, required this.raw});
  final int placementId;
  final int questionId;
  final String type;
  final String prompt;
  final double points;
  final bool required;
  final int pinnedVersion;
  final bool outdated;
  final List<String> tags;
  final Map<String, dynamic> raw;

  QuestionMedia? get media => mediaOfBody(asMap(raw['body']));
  int get difficulty => asInt(raw['difficulty'], 3);

  static PlacedQuestion fromJson(Map<String, dynamic> q) => PlacedQuestion(
        placementId: asInt(q['placement_id']), questionId: asInt(q['id']), type: '${q['type'] ?? ''}',
        prompt: '${asMap(q['body'])['prompt'] ?? ''}', points: asDouble(q['points']), required: q['required'] == true,
        pinnedVersion: asInt(q['pinned_version'] ?? q['version'], 1), outdated: q['outdated'] == true,
        tags: [for (final t in (q['tags'] as List?) ?? const []) '$t'], raw: q);
}

class SectionView {
  SectionView(this.section, this.questions);
  final SectionDraft section;
  final List<PlacedQuestion> questions;

  /// Questions the pool may draw (all, or those carrying one of the pool tags).
  int get eligible => section.poolTags.isEmpty ? questions.length : questions.where((q) => q.tags.any(section.poolTags.contains)).length;
  double get points {
    final pts = questions.map((q) => q.points).toList()..sort((a, b) => b.compareTo(a));
    final used = section.poolSize != null && section.poolSize! < pts.length ? pts.take(section.poolSize!) : pts;
    return used.fold(0.0, (s, p) => s + p) * section.weight;
  }
}

/// `GET /exams/{id}` for managers: the settings, the sections with their placed questions, the proctoring policy.
class ExamView {
  ExamView({required this.exam, required this.sections, required this.maxScore, this.proctoring});
  final ExamDraft exam;
  final List<SectionView> sections;
  final double maxScore;
  final Map<String, dynamic>? proctoring;

  static ExamView fromJson(Map<String, dynamic> j) => ExamView(
        exam: ExamDraft.fromJson(j),
        sections: [
          for (final s in asMapList(j['sections'])) SectionView(SectionDraft.fromJson(s), [for (final q in asMapList(s['questions'])) PlacedQuestion.fromJson(q)]),
        ],
        maxScore: asDouble(j['max_score']),
        proctoring: j['proctoring'] is Map ? asMap(j['proctoring']) : null,
      );

  int get questionCount => sections.fold(0, (s, v) => s + v.questions.length);
  Set<int> get placedIds => {for (final s in sections) for (final q in s.questions) q.questionId};
}

/// One reason the exam cannot be published yet (mirrors services/exams.py `publish`), with the section it is about.
class PublishBlocker {
  const PublishBlocker(this.code, [this.section]);
  final String code;
  final String? section;

  String get text {
    final base = authoringCodeText(code);
    return section == null ? base : '$base — «$section»';
  }

  @override
  bool operator ==(Object other) => other is PublishBlocker && other.code == code && other.section == section;
  @override
  int get hashCode => Object.hash(code, section);
}

List<PublishBlocker> publishBlockers(ExamView v) {
  final out = <PublishBlocker>[];
  if (v.sections.isEmpty) out.add(const PublishBlocker('no_sections'));
  if (v.sections.isNotEmpty && v.questionCount == 0) out.add(const PublishBlocker('no_questions'));
  // per-section checks only once the exam has questions (the server stops at `no_questions` first)
  for (final s in v.questionCount == 0 ? const <SectionView>[] : v.sections) {
    final name = s.section.title.trim().isEmpty ? '${s.section.position + 1}' : s.section.title.trim();
    if (s.section.mode != 'paper' && s.questions.isEmpty) out.add(PublishBlocker('empty_section', name));
    if (s.section.poolSize != null && s.section.poolSize! > s.eligible) out.add(PublishBlocker('pool_too_small', name));
  }
  if (v.exam.durationMinutes == null && v.exam.endsAt == null) out.add(const PublishBlocker('duration_required'));
  return out;
}

/// The lifecycle actions an exam offers now.
enum ExamAction { publish, unpublish, close, publishResults }

List<ExamAction> lifecycleActions(String status, {required bool resultsPublished}) => [
      if (status == 'draft') ExamAction.publish,
      if (status == 'published') ExamAction.unpublish,
      if (status == 'published') ExamAction.close,
      if ((status == 'published' || status == 'closed') && !resultsPublished) ExamAction.publishResults,
    ];

String examActionLabel(ExamAction a) => switch (a) {
      ExamAction.publish => t('نشر الاختبار', 'Publish the exam'),
      ExamAction.unpublish => t('إلغاء النشر (مسودة)', 'Unpublish (back to draft)'),
      ExamAction.close => t('إغلاق الاختبار', 'Close the exam'),
      ExamAction.publishResults => t('نشر النتائج للطلاب', 'Publish results to students'),
    };

/// New order of section ids after moving [id] by [delta] (−1 up, +1 down); the same list when it cannot move.
List<int> moveInOrder(List<int> ids, int id, int delta) {
  final i = ids.indexOf(id);
  final j = i + delta;
  if (i < 0 || j < 0 || j >= ids.length) return List.of(ids);
  final out = List.of(ids);
  out[i] = ids[j];
  out[j] = id;
  return out;
}

// ── proctoring ──────────────────────────────────────────────────────────────────────────────────────────────────

class ProctorRule {
  ProctorRule(this.category, this.max, this.consequence);
  String category;
  int max;
  String consequence;
  Map<String, dynamic> toJson() => {'category': category, 'max': max, 'consequence': consequence};
}

/// The brief's defaults: 3 times looking away, 1 tab switch / other app (the server creates the same set).
List<ProctorRule> defaultProctorRules() => [
      ProctorRule('looking_away', 3, 'flag'),
      ProctorRule('other_app', 1, 'flag'),
      ProctorRule('tab_switch', 1, 'flag'),
      ProctorRule('no_face', 3, 'warn'),
      ProctorRule('multiple_faces', 1, 'flag'),
    ];

class ProctoringDraft {
  bool camera = false;
  bool mic = false;
  bool screen = false;
  List<ProctorRule> rules = defaultProctorRules();
  bool autoReject = false;
  bool calibration = false;

  static ProctoringDraft fromJson(Map<String, dynamic>? j) {
    final d = ProctoringDraft();
    if (j == null) return d;
    final m = asMap(j['monitoring']);
    d
      ..camera = m['camera'] == true
      ..mic = m['mic'] == true
      ..screen = m['screen'] == true
      ..autoReject = j['auto_reject'] == true
      ..calibration = j['calibration'] == true;
    if (j['rules'] is List) d.rules = [for (final r in asMapList(j['rules'])) ProctorRule('${r['category']}', asInt(r['max']), '${r['consequence']}')];
    return d;
  }

  Map<String, dynamic> toBody() => {
        'monitoring': {'camera': camera, 'mic': mic, 'screen': screen},
        'rules': [for (final r in rules) r.toJson()],
        'auto_reject': autoReject,
        'calibration': calibration,
      };

  List<String> get unusedCategories => [for (final c in proctorCategories) if (!rules.any((r) => r.category == c)) c];

  bool sensorOn(String sensor) => switch (sensor) { 'camera' => camera, 'mic' => mic, 'screen' => screen, _ => false };

  /// Rules that will never fire because their sensor is not monitored.
  List<ProctorRule> get idleRules => [for (final r in rules) if (categorySensor[r.category] != null && !sensorOn(categorySensor[r.category]!)) r];

  List<String> validate() {
    final out = <String>[];
    final cats = rules.map((r) => r.category).toList();
    if (cats.toSet().length != cats.length) out.add('duplicate_rule');
    if (rules.any((r) => r.max < 0 || !proctorConsequences.contains(r.consequence))) out.add('bad_rule');
    if (rules.any((r) => !proctorCategories.contains(r.category))) out.add('bad_rule_category');
    return out;
  }
}

/// Sensors the policy monitors that the active consent text(s) do not declare: the server ignores those events
/// (monitoring is never covert), so the teacher should know before the exam.
List<String> undeclaredSensors(ProctoringDraft p, List<Map<String, dynamic>> consents) {
  final active = consents.where((c) => c['active'] == true).toList();
  final out = <String>[];
  for (final s in const ['camera', 'mic', 'screen']) {
    if (!p.sensorOn(s)) continue;
    if (active.isEmpty || active.any((c) => asMap(c['requires'])[s] != true)) out.add(s);
  }
  return out;
}

String sensorLabel(String s) => switch (s) {
      'camera' => t('الكاميرا', 'camera'),
      'mic' => t('الميكروفون', 'microphone'),
      'screen' => t('الشاشة', 'screen'),
      _ => s,
    };

class AccommodationDraft {
  String studentId = '';
  String extraMinutes = '';
  String extraPercent = '';
  bool largeText = false;
  bool screenReader = false;
  bool relaxedThresholds = false;
  String note = '';
  bool examOnly = true;

  List<String> validate() {
    final out = <String>[];
    final sid = parseIntField(studentId);
    if (sid == null || sid <= 0) out.add('student_required');
    final m = extraMinutes.trim().isEmpty ? 0 : parseIntField(extraMinutes);
    final p = extraPercent.trim().isEmpty ? 0 : parseIntField(extraPercent);
    if (m == null || m < 0 || p == null || p < 0) out.add('bad_extra_time');
    if ((m ?? 0) == 0 && (p ?? 0) == 0 && !largeText && !screenReader && !relaxedThresholds) out.add('accommodation_empty');
    return out;
  }

  Map<String, dynamic> toBody() => {
        'student_id': parseIntField(studentId),
        'extra_minutes': parseIntField(extraMinutes) ?? 0,
        'extra_percent': parseIntField(extraPercent) ?? 0,
        'large_text': largeText,
        'screen_reader': screenReader,
        'relaxed_thresholds': relaxedThresholds,
        if (note.trim().isNotEmpty) 'note': note.trim(),
        'exam_only': examOnly,
      };
}

String accommodationSummary(Map<String, dynamic> a) {
  final parts = <String>[];
  final m = asInt(a['extra_minutes']), p = asInt(a['extra_percent']);
  if (m > 0) parts.add(t('+$m دقيقة', '+$m min'));
  if (p > 0) parts.add(t('+$p٪ من الوقت', '+$p% time'));
  if (a['large_text'] == true) parts.add(t('خط كبير', 'large text'));
  if (a['screen_reader'] == true) parts.add(t('قارئ شاشة', 'screen reader'));
  if (a['relaxed_thresholds'] == true) parts.add(t('مراقبة مخففة', 'relaxed proctoring'));
  if (a['exam_id'] == null) parts.add(t('لكل الاختبارات', 'all exams'));
  return parts.join(' · ');
}

// ── codes → text ────────────────────────────────────────────────────────────────────────────────────────────────

/// Bilingual texts for the authoring codes (server codes and the client checks above); others fall back to the
/// taking flow's [examCodeText].
String authoringCodeText(String code) => switch (code) {
      'prompt_required' => t('نص السؤال مطلوب', 'The question text is required'),
      'points_positive' => t('الدرجة يجب أن تكون أكبر من صفر', 'Points must be more than zero'),
      'options_required' => t('خياران على الأقل', 'At least two options'),
      'duplicate_options' => t('معرّفات الخيارات مكررة', 'Option ids are repeated'),
      'option_text_required' => t('اكتب نص كل خيار', 'Write the text of every option'),
      'bad_answer_key' => t('حدد الإجابة الصحيحة', 'Mark the correct answer'),
      'blank_answer_required' => t('كل فراغ يحتاج إجابة مقبولة واحدة على الأقل', 'Every blank needs at least one accepted answer'),
      'pairs_required' => t('زوجان على الأقل للمطابقة', 'At least two pairs to match'),
      'pair_incomplete' => t('أكمل طرفي كل زوج', 'Fill both sides of every pair'),
      'items_required' => t('عنصران على الأقل للترتيب', 'At least two items to order'),
      'item_text_required' => t('اكتب نص كل عنصر', 'Write the text of every item'),
      'duplicate_items' => t('عناصر مكررة — اجعل كل عنصر مختلفاً', 'Repeated items — make every item different'),
      'bad_numeric_value' => t('القيمة الصحيحة يجب أن تكون رقماً', 'The correct value must be a number'),
      'bad_tolerance' => t('التسامح رقم لا يكون سالباً', 'The tolerance is a number, never negative'),
      'bad_unit' => t('لكل وحدة اسم مختلف', 'Every unit needs its own name'),
      'bad_unit_factor' => t('معامل الوحدة رقم موجب', 'A unit factor is a positive number'),
      'unit_base_required' => t('وحدة واحدة معاملها 1 (وحدة القيمة الصحيحة)', 'One unit must have factor 1 (the unit of the correct value)'),
      'model_answer_required' => t('أضف إجابة نموذجية أو معايير تصحيح', 'Add a model answer or rubric criteria'),
      'bad_rubric' => t('كل معيار يحتاج وصفاً ودرجة موجبة ومعرّفاً مختلفاً', 'Every criterion needs a description, positive points and its own id'),
      'bad_question_type' => t('نوع سؤال غير معروف', 'Unknown question type'),
      'question_not_found' => t('السؤال غير موجود في بنك هذه المساحة', 'The question is not in this bank'),
      'version_not_found' => t('نسخة السؤال غير موجودة', 'That version of the question does not exist'),
      'question_archived' => t('السؤال مؤرشف', 'The question is archived'),
      'title_required' => t('عنوان الاختبار مطلوب', 'The exam title is required'),
      'bad_window' => t('نهاية الاختبار يجب أن تكون بعد بدايته', 'The end must be after the start'),
      'bad_duration' => t('المدة بالدقائق يجب أن تكون موجبة', 'The duration must be positive minutes'),
      'bad_attempts' => t('عدد المحاولات بين 0 (بلا حد) و100', 'Attempts: 0 (unlimited) to 100'),
      'platform_required' => t('اختر منصة واحدة على الأقل (ويب أو جوال)', 'Pick at least one platform (web or mobile)'),
      'bad_results_policy' => t('سياسة نتائج غير معروفة', 'Unknown results policy'),
      'bad_datetime' => t('صيغة تاريخ غير صالحة', 'Invalid date'),
      'bad_passing' => t('نسبة النجاح بين 0 و 100', 'The pass mark is between 0 and 100'),
      'bad_appeal_days' => t('مدة التظلم بين 1 و 365 يوماً', 'The appeal window is 1–365 days'),
      'bad_appeal_limit' => t('عدد التظلمات بين 1 و 50', 'Appeals per attempt: 1–50'),
      'stale_version' => t('عُدّل الاختبار من جهاز آخر — أعد التحميل', 'The exam changed on another device — reload it'),
      'attempts_exist' => t('بدأ طلاب الاختبار: لا تتغير المدة ولا عدد المحاولات، ولا يُلغى النشر — أغلقه بدلاً من ذلك',
          'Students have started: the duration and attempts cannot change and it cannot be unpublished — close it instead'),
      'duration_required' => t('حدد مدة الاختبار أو موعد انتهائه', 'Set a duration or an end time'),
      'no_sections' => t('أضف قسماً واحداً على الأقل', 'Add at least one section'),
      'no_questions' => t('أضف أسئلة قبل النشر', 'Add questions before publishing'),
      'empty_section' => t('قسم إلكتروني بلا أسئلة', 'An online section has no questions'),
      'pool_too_small' => t('السحب العشوائي يطلب أسئلة أكثر مما في القسم', 'The random pool asks for more questions than the section has'),
      'review_pending' || 'review_items_open' => t('محاولات تنتظر مراجعة التصحيح قبل نشر النتائج', 'Attempts wait for marking review before results can be published'),
      'exam_draft' => t('الاختبار مسودة', 'The exam is a draft'),
      'exam_published' => t('الاختبار منشور بالفعل', 'The exam is already published'),
      'exam_closed' => t('الاختبار مغلق', 'The exam is closed'),
      'exam_archived' => t('الاختبار مؤرشف', 'The exam is archived'),
      'exam_not_found' => t('الاختبار غير موجود', 'The exam was not found'),
      'section_not_found' => t('القسم غير موجود', 'The section was not found'),
      'bad_mode' => t('طريقة تقديم غير معروفة', 'Unknown section mode'),
      'bad_navigation' => t('طريقة تنقل غير معروفة', 'Unknown navigation'),
      'bad_weight' => t('وزن القسم يجب أن يكون موجباً', 'The section weight must be positive'),
      'bad_time_box_minutes' => t('وقت القسم يجب أن يكون موجباً', 'The section time must be positive'),
      'bad_pool_size' => t('عدد أسئلة السحب يجب أن يكون موجباً', 'The pool size must be positive'),
      'order_mismatch' => t('ترتيب الأسئلة تغيّر — أعد التحميل', 'The question order changed — reload'),
      'exam_not_draft' => t('الاختبار لم يعد مسودة', 'The exam is no longer a draft'),
      'bad_points' => t('الدرجة غير صالحة', 'Invalid points'),
      'bad_order' => t('ترتيب الأقسام غير مطابق — أعد التحميل', 'The section order does not match — reload'),
      'already_placed' => t('السؤال موجود في هذا الاختبار بالفعل', 'The question is already in this exam'),
      'placement_not_found' => t('السؤال ليس في هذا الاختبار', 'The question is not in this exam'),
      'policy_not_found' => t('لا توجد سياسة مراقبة لهذا الاختبار', 'This exam has no proctoring policy'),
      'bad_rule_category' => t('فئة مراقبة غير معروفة', 'Unknown proctoring category'),
      'bad_rule' => t('كل قاعدة تحتاج حداً (0 أو أكثر) ونتيجة', 'Every rule needs a limit (0 or more) and a consequence'),
      'duplicate_rule' => t('فئة مكررة في القواعد', 'A category is repeated in the rules'),
      'student_required' => t('حدد رقم الطالب', 'Enter the student id'),
      'bad_extra_time' => t('الوقت الإضافي رقم صحيح غير سالب', 'Extra time is a whole number, not negative'),
      'accommodation_empty' => t('اختر تيسيراً واحداً على الأقل', 'Choose at least one accommodation'),
      'accommodation_not_found' => t('التيسير غير موجود', 'The accommodation was not found'),
      'forbidden' => t('ليس لديك صلاحية على هذا', 'You do not have permission for this'),
      'engine_unavailable' => t('خدمة الاختبارات الجديدة غير متاحة بعد على الخادم', 'The exam service is not available on the server yet'),
      _ => mediaCodeText(code) ?? examCodeText(code),
    };

/// The text to show for a failed call: the mapped code, else the server's message.
String authoringError(EngineResult r) {
  if (r.unavailable) return authoringCodeText('engine_unavailable');
  final code = r.code;
  if (code != null && code.isNotEmpty) {
    final text = authoringCodeText(code);
    if (text != code) return text;
  }
  return r.message.isNotEmpty ? r.message : (code ?? t('تعذّر الحفظ', 'Could not save'));
}

/// `GET /exams?course_id` answers 409 `course_not_in_org` (+`course_org_id`) for an organization's course: the
/// organization to use instead. null = not that answer.
int? orgFromScopeError(EngineResult r) {
  if (r.ok || r.code != 'course_not_in_org') return null;
  final v = r.detail['course_org_id'];
  return v == null ? null : asInt(v);
}

/// Which space a course's exams live in: the organization the server named (or none = the personal space).
class ExamScope {
  ExamScope({required this.courseId, required this.orgId, required this.list});
  final int? courseId;
  final int? orgId;
  final EngineResult list;
}

// ── reorder / paging (pure) ─────────────────────────────────────────────────────────────────────────────────────

/// `ReorderableListView.onReorder` semantics (newIndex is the position BEFORE the removal): the new list of ids.
List<int> reorderIds(List<int> ids, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= ids.length) return List.of(ids);
  var to = newIndex;
  if (to > oldIndex) to -= 1;
  to = to.clamp(0, ids.length - 1);
  final out = List.of(ids);
  out.insert(to, out.removeAt(oldIndex));
  return out;
}

/// The same reorder applied to any list (optimistic update; rolled back by restoring the old list).
List<T> reorderList<T>(List<T> items, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= items.length) return List.of(items);
  var to = newIndex;
  if (to > oldIndex) to -= 1;
  to = to.clamp(0, items.length - 1);
  final out = List.of(items);
  out.insert(to, out.removeAt(oldIndex));
  return out;
}

/// One page of the bank. Understands the new shape (`items` + `next_before` + `scan_capped`) and the old ones
/// (`items` only, or a bare list that `engineCall` wraps as `value`).
class BankPage {
  BankPage(this.items, this.nextBefore, this.scanCapped);
  final List<BankQuestion> items;
  final int? nextBefore;
  final bool scanCapped;

  static BankPage fromResult(Map<String, dynamic> m) {
    final raw = m['items'] is List ? asMapList(m['items']) : (m['value'] is List ? asMapList(m['value']) : const <Map<String, dynamic>>[]);
    final nb = m['next_before'];
    return BankPage([for (final q in raw) BankQuestion.fromJson(q)], nb == null ? null : asInt(nb), m['scan_capped'] == true);
  }
}

/// Paging state of the bank list: filters reset it, "load more" appends and never duplicates a question.
class BankPaging {
  final List<BankQuestion> items = [];
  int? nextBefore;
  bool scanCapped = false;
  bool get hasMore => nextBefore != null;

  void reset() {
    items.clear();
    nextBefore = null;
    scanCapped = false;
  }

  void add(BankPage p) {
    final seen = {for (final q in items) q.id};
    items.addAll(p.items.where((q) => seen.add(q.id)));
    nextBefore = p.nextBefore;
    scanCapped = p.scanCapped;
  }
}

// ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/// A course session the "lock the lessons after" picker offers (D-197).
class LockSession {
  const LockSession({required this.id, required this.name, required this.order});
  final int id;
  final String name;
  final int order;

  static List<LockSession> list(dynamic body) {
    final out = <LockSession>[];
    if (body is Map && body['items'] is List) {
      for (final s in asMapList(body['items'])) {
        out.add(LockSession(id: asInt(s['id']), name: '${s['name'] ?? ''}', order: asInt(s['order'])));
      }
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }
}

/// The line under the session picker.
String sessionLockHint() => t('لا يفتح الطلاب الدروس بعد هذه الجلسة حتى ينجحوا في الاختبار', 'Students cannot open the lessons after this session until they pass the exam');

/// One row the Excel import refused.
class ImportRowError {
  const ImportRowError({required this.row, required this.code, required this.message});
  final int row;
  final String code;
  final String message;
}

/// `POST /exams/{id}/questions/import`: how many questions were created and which rows were refused.
class ImportReport {
  const ImportReport({required this.created, required this.errors});
  final int created;
  final List<ImportRowError> errors;

  static ImportReport fromJson(Map<String, dynamic> j) => ImportReport(
        created: asInt(j['created']),
        errors: [for (final e in asMapList(j['errors'])) ImportRowError(row: asInt(e['row']), code: '${e['code'] ?? ''}', message: '${e['message'] ?? ''}')],
      );
}

/// A refused row in words: the known codes bilingual, any other code with the server's own message.
String importRowText(ImportRowError e) {
  final known = switch (e.code) {
    'prompt_required' || 'question_required' => t('نص السؤال فارغ', 'The question text is empty'),
    'options_required' => t('خيارات ناقصة', 'Not enough choices'),
    'bad_correct' || 'pick_correct' || 'correct_required' => t('الإجابة الصحيحة غير موجودة بين الخيارات', 'The correct answer is not among the choices'),
    'bad_type' || 'unknown_type' => t('نوع السؤال غير معروف', 'Unknown question type'),
    'bad_points' || 'points_positive' => t('الدرجة غير صحيحة', 'The points are not valid'),
    _ => null,
  };
  return known ?? (e.message.isNotEmpty ? e.message : e.code);
}

class ExamAuthoringApi {
  ExamAuthoringApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  // question bank
  Future<EngineResult> questions({int? orgId, int? courseId, String? type, String? tag, String? q, bool includeArchived = false,
          Set<int> difficulty = const {}, int? limit, int? before}) =>
      engineCall(() => _api.get('$base/questions', queryParams: {
            'org_id': ?orgId,
            'course_id': ?courseId,
            'type': ?type,
            if (tag != null && tag.isNotEmpty) 'tag': tag,
            if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
            if (includeArchived) 'include_archived': true,
            if (difficulty.isNotEmpty) 'difficulty': (difficulty.toList()..sort()).join(','),
            'limit': ?limit,
            'before': ?before,
          }));
  Future<EngineResult> question(int id, {int? version}) => engineCall(() => _api.get('$base/questions/$id', queryParams: {'version': ?version}));
  Future<EngineResult> createQuestion(Map<String, dynamic> body) => engineCall(() => _api.post('$base/questions', body: body));
  Future<EngineResult> updateQuestion(int id, Map<String, dynamic> body) => engineCall(() => _api.put('$base/questions/$id', body: body));
  Future<EngineResult> archiveQuestion(int id) => engineCall(() => _api.delete('$base/questions/$id'));

  // exams
  Future<EngineResult> exams({int? orgId, int? courseId, String? status}) => engineCall(() => _api.get('$base/exams', queryParams: {
        'org_id': ?orgId,
        'course_id': ?courseId,
        'status': ?status,
      }));

  /// The space each course's exams were found in this session (course id → organization id, null = personal).
  static final Map<int, int?> _knownScope = {};

  /// Tests: forget the remembered spaces.
  static void forgetScopes() => _knownScope.clear();

  /// A caller that knows the course's organization (the teacher's course carries `org`) says so before the first
  /// list: it is then asked under it at once, no 409 `course_not_in_org` round trip.
  static void knowScope(int courseId, int? orgId) {
    if (orgId != null) _knownScope[courseId] = orgId;
  }

  /// The course's exams, in the space the server says the course belongs to (asked once without an organization:
  /// an organization's course answers 409 `course_not_in_org` naming it, then asked again under it). The answer is
  /// remembered for the session, so the next visit asks in the right space at once (the hub reloads on every return:
  /// it logged a 409 and a retry each time). A course moved since is caught by the same 409 and asked again.
  Future<ExamScope> resolveScope(int courseId, {int? orgId}) async {
    final s = await _resolveScope(courseId, orgId: orgId ?? _knownScope[courseId]);
    if (s.list.ok) _knownScope[courseId] = s.orgId;
    return s;
  }

  Future<ExamScope> _resolveScope(int courseId, {int? orgId}) async {
    var r = await exams(orgId: orgId, courseId: courseId);
    if (!r.ok && r.code == 'course_not_in_org' && r.detail['course_org_id'] == null && orgId != null) {
      r = await exams(courseId: courseId);                 // a teacher's personal course: the personal space
      return ExamScope(courseId: courseId, orgId: null, list: r);
    }
    final named = orgFromScopeError(r);
    if (named != null && named != orgId) {
      r = await exams(orgId: named, courseId: courseId);
      return ExamScope(courseId: courseId, orgId: named, list: r);
    }
    return ExamScope(courseId: courseId, orgId: orgId, list: r);
  }

  Future<EngineResult> exam(int id) => engineCall(() => _api.get('$base/exams/$id'));
  Future<EngineResult> createExam(Map<String, dynamic> body) => engineCall(() => _api.post('$base/exams', body: body));
  Future<EngineResult> updateExam(int id, Map<String, dynamic> body) => engineCall(() => _api.put('$base/exams/$id', body: body));
  Future<EngineResult> lifecycle(int id, ExamAction a) => engineCall(() => _api.post(switch (a) {
        ExamAction.publish => '$base/exams/$id/publish',
        ExamAction.unpublish => '$base/exams/$id/unpublish',
        ExamAction.close => '$base/exams/$id/close',
        ExamAction.publishResults => '$base/exams/$id/results/publish',
      }));

  // sections + placements
  Future<EngineResult> addSection(int examId, Map<String, dynamic> body) => engineCall(() => _api.post('$base/exams/$examId/sections', body: body));
  Future<EngineResult> updateSection(int examId, int sid, Map<String, dynamic> body) =>
      engineCall(() => _api.put('$base/exams/$examId/sections/$sid', body: body));
  Future<EngineResult> deleteSection(int examId, int sid) => engineCall(() => _api.delete('$base/exams/$examId/sections/$sid'));
  Future<EngineResult> reorderSections(int examId, List<int> order) =>
      engineCall(() => _api.put('$base/exams/$examId/sections/order', body: {'order': order}));
  Future<EngineResult> place(int examId, int sid, {required int questionId, int? version, double? points, int? position, bool required = false}) =>
      engineCall(() => _api.post('$base/exams/$examId/sections/$sid/questions', body: {
            'question_id': questionId,
            'version': ?version,
            'points': ?points,
            'position': ?position,
            'required': required,
          }));
  /// New order of one section's placements (exactly its set), draft only.
  Future<EngineResult> reorderQuestions(int examId, int sid, List<int> placementIds) =>
      engineCall(() => _api.put('$base/exams/$examId/sections/$sid/questions/order', body: {'placement_ids': placementIds}));
  /// Move a placement to another section and/or position (0-based), or change its points.
  Future<EngineResult> movePlacement(int examId, int placementId, {int? sectionId, int? position, double? points}) =>
      engineCall(() => _api.put('$base/exams/$examId/placements/$placementId', body: {'section_id': ?sectionId, 'position': ?position, 'points': ?points}));
  Future<EngineResult> unplace(int examId, int placementId) => engineCall(() => _api.delete('$base/exams/$examId/placements/$placementId'));

  // proctoring + accommodations + consent texts
  Future<EngineResult> proctoring(int examId) => engineCall(() => _api.get('$base/exams/$examId/proctoring'));
  Future<EngineResult> setProctoring(int examId, Map<String, dynamic> body) => engineCall(() => _api.put('$base/exams/$examId/proctoring', body: body));
  Future<EngineResult> accommodations(int examId) => engineCall(() => _api.get('$base/exams/$examId/accommodations'));
  Future<EngineResult> grantAccommodation(int examId, Map<String, dynamic> body) =>
      engineCall(() => _api.post('$base/exams/$examId/accommodations', body: body));
  Future<EngineResult> revokeAccommodation(int id) => engineCall(() => _api.delete('$base/accommodations/$id'));
  Future<EngineResult> consents({int? orgId}) => engineCall(() => _api.get('$base/consents', queryParams: {'org_id': ?orgId}));

  /// The course's sessions in lesson order (core API, the hub's own call); an unreachable list is just empty.
  Future<List<LockSession>> courseSessions(int courseId) async {
    const page = 100;
    final all = <LockSession>[];
    try {
      for (var skip = 0;; skip += page) {
        final got = LockSession.list(await _api.get('/api/v1/courses/$courseId/sessions', queryParams: {'skip': skip, 'limit': page}));
        all.addAll(got);
        if (got.length < page) break;
      }
    } catch (_) {
      // not fatal: the exam is simply not tied to a session
    }
    all.sort((a, b) => a.order.compareTo(b.order));
    return all;
  }

  // Excel import of questions into a draft exam (D-197): the template, then the filled file.
  Future<Uint8List> importTemplate(String lang) => _api.getBytes('$base/questions/import-template', queryParams: {'lang': lang});
  Future<EngineResult> importQuestions(int examId, {required String fileName, Uint8List? bytes, String? path, int? sectionId}) => engineCall(() => _api.postMultipart(
      '$base/exams/$examId/questions/import',
      fields: {'section_id': ?(sectionId == null ? null : '$sectionId')},
      fileField: 'file', fileName: fileName, fileBytes: bytes, filePath: path));

  // the exam as an uploaded file (quick exam, settings.paper_file)
  Future<EngineResult> uploadPaperFile(int examId, {required String fileName, Uint8List? bytes, String? path}) => engineCall(() => _api.postMultipart(
      '$base/exams/$examId/paper-file', fields: const {}, fileField: 'file', fileName: fileName, fileBytes: bytes, filePath: path));
  Future<EngineResult> removePaperFile(int examId) => engineCall(() => _api.delete('$base/exams/$examId/paper-file'));
  Future<Uint8List> paperFile(int examId) => _api.getBytes('$base/exams/$examId/paper-file');

  // results: every attempt, one attempt's answers, a student's uploaded answer file, the course roster's names
  Future<EngineResult> attempts(int examId) => engineCall(() => _api.get('$base/exams/$examId/attempts'));
  Future<EngineResult> attemptReview(int attemptId) => engineCall(() => _api.get('$base/attempts/$attemptId/review'));
  Future<Uint8List> answerFile(int attemptId, int questionId) => _api.getBytes('$base/attempts/$attemptId/files/$questionId');
  Future<EngineResult> enterMarks(int examId, List<Map<String, dynamic>> rows) => engineCall(() => _api.post('$base/exams/$examId/marks', body: {'rows': rows}));
  Future<EngineResult> courseStudents(int courseId) => engineCall(() => _api.get('/api/v1/courses/$courseId/students'));
}
