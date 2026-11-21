// lib/features/nahw/nahw_models.dart — Arabic grammar (nahw) models and on-device grading (Learning Hub Phase 6,
// D-1349; server D-1343..D-1345). Tolerant readers: a missing field is a safe default, never a crash.
//
//   NahwLevel / NahwLessonRef / NahwProgress    GET /nahw/levels (and the parent's view of a child): levels beginner →
//                                               advanced, each with its lessons and my progress per lesson
//   NahwLesson / NahwExercise                   GET /nahw/lessons/{id}: the reading text and the exercises WITH their
//                                               answers (the device grades, so a lesson works offline)
//   NahwResponse / nahwGrade                    what the student picked and its score: choose 1 point, fill 1 point,
//                                               classify 1 point per item; an unknown kind is skipped (not counted)
library;

import 'package:flutter_education_app/features/learn_kit/learn_kit.dart' show learnText;

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? d;

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// A student's result on one lesson.
class NahwProgress {
  const NahwProgress({required this.lessonId, this.bestScore = 0, this.maxScore = 0, this.attempts = 0, this.completed = false});

  final int lessonId;
  final int bestScore;
  final int maxScore;
  final int attempts;

  /// Reached 60 % once.
  final bool completed;

  int get percent => maxScore <= 0 ? 0 : ((bestScore / maxScore) * 100).round().clamp(0, 100);

  static NahwProgress? from(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    return NahwProgress(
      lessonId: _int(m['lesson_id']),
      bestScore: _int(m['best_score']),
      maxScore: _int(m['max_score']),
      attempts: _int(m['attempts']),
      completed: m['completed'] == true,
    );
  }
}

/// A lesson as listed under its level.
class NahwLessonRef {
  const NahwLessonRef({
    required this.id,
    required this.levelId,
    required this.titleAr,
    this.titleEn = '',
    this.exerciseCount = 0,
    this.progress,
  });

  final int id;
  final int levelId;
  final String titleAr;
  final String titleEn;
  final int exerciseCount;
  final NahwProgress? progress;

  String get title => learnText(titleAr, titleEn);

  static NahwLessonRef from(Map<String, dynamic> m) => NahwLessonRef(
        id: _int(m['id']),
        levelId: _int(m['level_id']),
        titleAr: '${m['title_ar'] ?? ''}',
        titleEn: '${m['title_en'] ?? ''}',
        exerciseCount: _int(m['exercise_count']),
        progress: NahwProgress.from(m['progress']),
      );
}

class NahwLevel {
  const NahwLevel({
    required this.id,
    required this.key,
    required this.titleAr,
    this.titleEn = '',
    this.stageId,
    this.gradeId,
    this.total = 0,
    this.completed = 0,
    this.lessons = const [],
  });

  final int id;
  final String key;
  final String titleAr;
  final String titleEn;

  /// The stage / grade the level is linked to (null = for everyone).
  final int? stageId;
  final int? gradeId;
  final int total;
  final int completed;
  final List<NahwLessonRef> lessons;

  String get title => learnText(titleAr, titleEn);

  /// 0..1 of the lessons completed.
  double get fraction => total <= 0 ? 0 : (completed / total).clamp(0, 1).toDouble();

  static NahwLevel from(Map<String, dynamic> m) {
    final lessons = [for (final l in _maps(m['lessons'])) NahwLessonRef.from(l)];
    return NahwLevel(
      id: _int(m['id']),
      key: '${m['key'] ?? ''}',
      titleAr: '${m['title_ar'] ?? ''}',
      titleEn: '${m['title_en'] ?? ''}',
      stageId: m['stage_id'] == null ? null : _int(m['stage_id']),
      gradeId: m['grade_id'] == null ? null : _int(m['grade_id']),
      total: m['total'] == null ? lessons.length : _int(m['total']),
      completed: m['completed'] == null ? lessons.where((l) => l.progress?.completed == true).length : _int(m['completed']),
      lessons: lessons,
    );
  }

  static List<NahwLevel> listFrom(dynamic v) => [for (final l in _maps(_map(v)['levels'])) NahwLevel.from(l)];
}

/// A category of a classify exercise.
class NahwCategory {
  const NahwCategory(this.key, this.labelAr, this.labelEn);
  final String key;
  final String labelAr;
  final String labelEn;
  String get label => learnText(labelAr, labelEn);
}

class NahwExercise {
  const NahwExercise({
    required this.id,
    required this.kind,
    required this.prompt,
    this.promptEn = '',
    this.data = const {},
    this.answer = const {},
    this.explanation = '',
  });

  final int id;

  /// `choose` | `fill` | `classify` (`order` and any other kind are skipped: no shape agreed yet).
  final String kind;
  final String prompt;
  final String promptEn;
  final Map<String, dynamic> data;
  final Map<String, dynamic> answer;
  final String explanation;

  static const kinds = {'choose', 'fill', 'classify'};

  bool get supported =>
      kinds.contains(kind) &&
      switch (kind) {
        'choose' => options.isNotEmpty && answer['index'] is num,
        'fill' => options.isNotEmpty && (answer['text'] ?? '').toString().isNotEmpty,
        _ => items.isNotEmpty && categories.isNotEmpty && answerItems.length == items.length,
      };

  String get title => learnText(prompt, promptEn);

  /// choose / fill: the choices.
  List<String> get options => [for (final o in (data['options'] as List? ?? const [])) '$o'];

  /// fill: the sentence with `___` where the answer goes.
  String get text => '${data['text'] ?? ''}';

  /// classify: the words / sentences to sort.
  List<String> get items => [for (final i in (data['items'] as List? ?? const [])) i is Map ? '${i['text'] ?? ''}' : '$i'];

  List<NahwCategory> get categories => [
        for (final c in _maps(data['categories'])) NahwCategory('${c['key'] ?? ''}', '${c['label_ar'] ?? ''}', '${c['label_en'] ?? ''}'),
      ];

  List<String> get answerItems => [for (final a in (answer['items'] as List? ?? const [])) '$a'];

  int get maxScore => kind == 'classify' ? items.length : 1;

  static NahwExercise from(Map<String, dynamic> m) {
    final data = _map(m['data']);
    return NahwExercise(
      id: _int(m['id']),
      kind: '${m['kind'] ?? ''}',
      prompt: '${m['prompt'] ?? ''}',
      promptEn: '${data['prompt_en'] ?? ''}',
      data: data,
      answer: _map(m['answer']),
      explanation: '${m['explanation'] ?? ''}',
    );
  }
}

class NahwLesson {
  const NahwLesson({
    required this.id,
    required this.levelId,
    required this.titleAr,
    this.titleEn = '',
    this.bodyAr = '',
    this.exercises = const [],
    this.progress,
  });

  final int id;
  final int levelId;
  final String titleAr;
  final String titleEn;

  /// The reading text (Arabic: the subject is Arabic grammar).
  final String bodyAr;

  /// Only the kinds the app can grade.
  final List<NahwExercise> exercises;
  final NahwProgress? progress;

  String get title => learnText(titleAr, titleEn);

  int get maxScore => exercises.fold(0, (s, e) => s + e.maxScore);

  static NahwLesson from(dynamic v) {
    final m = _map(v);
    return NahwLesson(
      id: _int(m['id']),
      levelId: _int(m['level_id']),
      titleAr: '${m['title_ar'] ?? ''}',
      titleEn: '${m['title_en'] ?? ''}',
      bodyAr: '${m['body_ar'] ?? ''}',
      exercises: [
        for (final e in _maps(m['exercises']).map(NahwExercise.from))
          if (e.supported) e,
      ],
      progress: NahwProgress.from(m['progress']),
    );
  }
}

/// What the student picked on one exercise: choose → [choice] (option index), fill → [choice] (option index) or
/// [text] (typed), classify → [items] (a category key per item, null = not sorted yet).
class NahwResponse {
  const NahwResponse({this.choice, this.text, this.items = const []});

  final int? choice;
  final String? text;
  final List<String?> items;

  NahwResponse withChoice(int i) => NahwResponse(choice: i, text: text, items: items);

  NahwResponse withItem(int index, String key, int count) {
    final next = List<String?>.filled(count, null);
    for (var i = 0; i < count && i < items.length; i++) {
      next[i] = items[i];
    }
    next[index] = key;
    return NahwResponse(choice: choice, text: text, items: next);
  }

  /// Ready to check.
  bool complete(NahwExercise e) => switch (e.kind) {
        'choose' => choice != null,
        'fill' => choice != null || (text ?? '').trim().isNotEmpty,
        'classify' => items.length == e.items.length && items.every((k) => k != null),
        _ => false,
      };

  /// The answer as sent with the attempt (the server keeps it for the record only).
  Object? toJson(NahwExercise e) => switch (e.kind) {
        'choose' => {'index': choice},
        'fill' => {'text': choice != null && choice! < e.options.length ? e.options[choice!] : (text ?? '').trim()},
        'classify' => {'items': items},
        _ => null,
      };
}

class NahwGrade {
  const NahwGrade(this.score, this.max, {this.itemsRight = const []});
  final int score;
  final int max;

  /// classify: right / wrong per item.
  final List<bool> itemsRight;

  bool get correct => score == max;
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Grades [r] on the device against the answer the lesson carries.
NahwGrade nahwGrade(NahwExercise e, NahwResponse r) {
  switch (e.kind) {
    case 'choose':
      return NahwGrade(r.choice == _int(e.answer['index'], -1) ? 1 : 0, 1);
    case 'fill':
      final want = _norm('${e.answer['text'] ?? ''}');
      final got = r.choice != null && r.choice! < e.options.length ? e.options[r.choice!] : (r.text ?? '');
      return NahwGrade(_norm(got) == want ? 1 : 0, 1);
    case 'classify':
      final want = e.answerItems;
      final right = [for (var i = 0; i < want.length; i++) i < r.items.length && r.items[i] == want[i]];
      return NahwGrade(right.where((x) => x).length, want.length, itemsRight: right);
  }
  return const NahwGrade(0, 0);
}
