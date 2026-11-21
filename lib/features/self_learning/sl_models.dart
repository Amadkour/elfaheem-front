// lib/features/self_learning/sl_models.dart — the self-learning shapes (Learning Hub v2 CONTRACT §5, D-1600):
// a lesson or a review question delivered a few times a day, a Leitner card per item, and the student's progress.
// Tolerant readers: a missing field reads as empty, never as a crash.
//
//   SlItem      {id, subject, kind: lesson|question, category, title, body, lesson_id, question, source, sort, published}
//   SlQuestion  {prompt, options, answer, explanation}
//   SlCard      {item_id, box 0..5, due_at, last_result right|wrong|null}
//   SlState     GET /api/v1/me/self-learning: {enabled, can_toggle, subjects, today:{lessons, reviews}, progress}
//   SlProgress  {learned, due, streak_days, per_subject:{subject: {learned, due, total}}}
library;

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

/// The closed subject list (CONTRACT §1), in display order.
const kSlSubjects = ['quran', 'tajweed', 'fiqh', 'nahw'];

/// The subjects the Quran tab shows (the Nahw tab shows `nahw`).
const kSlQuranSubjects = {'quran', 'tajweed', 'fiqh'};

String slSubjectLabel(String s) => switch (s) {
      'quran' => t('القرآن', 'Quran'),
      'tajweed' => t('التجويد', 'Tajweed'),
      'fiqh' => t('الفقه', 'Fiqh'),
      'nahw' => t('النحو', 'Grammar'),
      _ => s,
    };

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;

int? _intOrNull(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

String _str(dynamic v) => v == null ? '' : '$v';

/// Naive UTC ISO (no `Z`) → a UTC DateTime.
DateTime? slParseUtc(dynamic v) {
  final s = _str(v).trim();
  if (s.isEmpty) return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

class SlQuestion {
  const SlQuestion({required this.prompt, required this.options, required this.answer, this.explanation = ''});

  final String prompt;
  final List<String> options;

  /// The right option's index.
  final int answer;
  final String explanation;

  bool get valid => options.length >= 2 && answer >= 0 && answer < options.length;

  static SlQuestion? from(dynamic v) {
    if (v is! Map) return null;
    final m = _map(v);
    return SlQuestion(
      prompt: _str(m['prompt']),
      options: [for (final o in (m['options'] as List? ?? const [])) _str(o)],
      answer: _int(m['answer'], -1),
      explanation: _str(m['explanation']),
    );
  }

  Map<String, dynamic> toJson() => {'prompt': prompt, 'options': options, 'answer': answer, 'explanation': explanation};
}

/// Where an item was taken from (a nahw lesson, a Quran range) — informational.
class SlSource {
  const SlSource({this.type, this.id, this.ref});

  /// `nahw_lesson` | `quran_range` | null.
  final String? type;
  final int? id;
  final String? ref;

  static SlSource from(dynamic v) {
    final m = _map(v);
    final type = _str(m['type']).trim();
    final ref = _str(m['ref']).trim();
    return SlSource(type: type.isEmpty ? null : type, id: _intOrNull(m['id']), ref: ref.isEmpty ? null : ref);
  }

  Map<String, dynamic> toJson() => {'type': type, if (id != null) 'id': id, if (ref != null) 'ref': ref};
}

class SlItem {
  const SlItem({
    required this.id,
    required this.subject,
    required this.kind,
    this.category = '',
    this.title = '',
    this.body = '',
    this.lessonId,
    this.question,
    this.source = const SlSource(),
    this.sort = 0,
    this.published = false,
  });

  final int id;
  final String subject;

  /// `lesson` | `question`.
  final String kind;
  final String category;
  final String title;

  /// Markdown-lite: paragraphs on new lines, `**bold**` drawn plain.
  final String body;
  final int? lessonId;
  final SlQuestion? question;
  final SlSource source;
  final int sort;
  final bool published;

  bool get isLesson => kind == 'lesson';
  bool get isQuestion => kind == 'question';

  /// The body without the markdown-lite marks, for a short preview.
  String get plainBody => body.replaceAll('**', '').replaceAll(RegExp(r'^#+\s*', multiLine: true), '').trim();

  static SlItem from(Map<String, dynamic> m) => SlItem(
        id: _int(m['id']),
        subject: _str(m['subject']),
        kind: _str(m['kind']).isEmpty ? 'lesson' : _str(m['kind']),
        category: _str(m['category']),
        title: _str(m['title']),
        body: _str(m['body']),
        lessonId: _intOrNull(m['lesson_id']),
        question: SlQuestion.from(m['question']),
        source: SlSource.from(m['source']),
        sort: _int(m['sort']),
        published: m['published'] == true,
      );

  static List<SlItem> listFrom(dynamic v) => [for (final m in _maps(v)) SlItem.from(m)];

  /// The admin's POST / PUT body.
  Map<String, dynamic> toJson() => {
        'subject': subject,
        'kind': kind,
        'category': category,
        'title': title,
        'body': body,
        'lesson_id': lessonId,
        'question': isQuestion ? question?.toJson() : null,
        'source': source.type == null ? null : source.toJson(),
        'sort': sort,
        'published': published,
      };
}

class SlCard {
  const SlCard({required this.itemId, this.box = 0, this.dueAt, this.lastResult});

  final int itemId;
  final int box;
  final DateTime? dueAt;

  /// `right` | `wrong` | null.
  final String? lastResult;

  static SlCard? from(dynamic v) {
    if (v is! Map) return null;
    final m = _map(v);
    final r = _str(m['last_result']);
    return SlCard(
      itemId: _int(m['item_id']),
      box: _int(m['box']).clamp(0, 5),
      dueAt: slParseUtc(m['due_at']),
      lastResult: r.isEmpty ? null : r,
    );
  }
}

class SlSubjectProgress {
  const SlSubjectProgress({this.learned = 0, this.due = 0, this.total = 0});

  final int learned;
  final int due;

  /// Every published item of the subject (0 = unknown: the bar then reads learned / (learned + due)).
  final int total;

  double get fraction {
    final all = total > 0 ? total : learned + due;
    return all <= 0 ? 0 : (learned / all).clamp(0.0, 1.0);
  }

  static SlSubjectProgress from(dynamic v) {
    if (v is num) return SlSubjectProgress(learned: v.toInt());
    final m = _map(v);
    return SlSubjectProgress(learned: _int(m['learned']), due: _int(m['due']), total: _int(m['total']));
  }
}

class SlProgress {
  const SlProgress({this.learned = 0, this.due = 0, this.streakDays = 0, this.perSubject = const {}});

  final int learned;
  final int due;
  final int streakDays;
  final Map<String, SlSubjectProgress> perSubject;

  static SlProgress from(dynamic v) {
    final m = _map(v);
    return SlProgress(
      learned: _int(m['learned']),
      due: _int(m['due']),
      streakDays: _int(m['streak_days']),
      perSubject: {for (final e in _map(m['per_subject']).entries) e.key: SlSubjectProgress.from(e.value)},
    );
  }
}

class SlState {
  const SlState({
    this.available = true,
    this.enabled = false,
    this.canToggle = true,
    this.subjects = const [],
    this.lessons = const [],
    this.reviews = const [],
    this.progress = const SlProgress(),
  });

  /// False = the admin has self-learning off for this student (403 `feature_disabled`, or `available: false`).
  final bool available;

  /// The student's own on / off.
  final bool enabled;
  final bool canToggle;
  final List<String> subjects;
  final List<SlItem> lessons;
  final List<SlItem> reviews;
  final SlProgress progress;

  static const off = SlState(available: false, canToggle: false);

  bool get on => available && enabled;

  /// Today's items of [only] (null = every subject).
  SlState forSubjects(Set<String>? only) => only == null
      ? this
      : SlState(
          available: available,
          enabled: enabled,
          canToggle: canToggle,
          subjects: subjects,
          lessons: [for (final i in lessons) if (only.contains(i.subject)) i],
          reviews: [for (final i in reviews) if (only.contains(i.subject)) i],
          progress: progress,
        );

  SlState copyWith({bool? enabled, List<String>? subjects, List<SlItem>? lessons, List<SlItem>? reviews, SlProgress? progress}) =>
      SlState(
        available: available,
        enabled: enabled ?? this.enabled,
        canToggle: canToggle,
        subjects: subjects ?? this.subjects,
        lessons: lessons ?? this.lessons,
        reviews: reviews ?? this.reviews,
        progress: progress ?? this.progress,
      );

  static SlState from(dynamic v) {
    final m = _map(v);
    final today = _map(m['today']);
    return SlState(
      available: m['available'] != false,
      enabled: m['enabled'] == true,
      canToggle: m['can_toggle'] != false,
      subjects: [for (final s in (m['subjects'] as List? ?? const [])) _str(s)],
      lessons: SlItem.listFrom(today['lessons']),
      reviews: SlItem.listFrom(today['reviews']),
      progress: SlProgress.from(m['progress']),
    );
  }
}

/// POST /me/self-learning/reviews/{id}'s answer.
class SlReviewResult {
  const SlReviewResult({required this.right, this.explanation = '', this.card, this.queued = false});

  final bool right;
  final String explanation;
  final SlCard? card;

  /// Kept on the device (offline): the server's answer comes with the next sync.
  final bool queued;

  static SlReviewResult from(dynamic v) {
    final m = _map(v);
    return SlReviewResult(right: m['right'] == true, explanation: _str(m['explanation']), card: SlCard.from(m['card']));
  }
}

/// One page of the admin list.
class SlItemPage {
  const SlItemPage({this.items = const [], this.total = 0, this.page = 1, this.size = 20});

  final List<SlItem> items;
  final int total;
  final int page;
  final int size;

  int get pageCount => total <= 0 ? 1 : ((total + size - 1) ~/ size);

  static SlItemPage from(dynamic v, {int size = 20}) {
    if (v is List) return SlItemPage(items: SlItem.listFrom(v), total: v.length, size: size);
    final m = _map(v);
    final items = SlItem.listFrom(m['items']);
    return SlItemPage(
      items: items,
      total: _int(m['total'], items.length),
      page: _int(m['page'], 1),
      size: _int(m['size'], size),
    );
  }
}
