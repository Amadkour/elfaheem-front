// Quick exam: the short way to create an Exam Engine exam (first: manual, generated or one uploaded file; then the
// questions; last: online or printed; everything else is a smart default the creator may open under "Advanced").
//
// It builds the same engine objects as the full editor (exam_authoring.dart): one exam, one section (online, or
// paper for offline), and bank questions placed in it. Nothing new on the server except
//   answer.auto_grade = false        an open question the teacher marks by hand (no model answer needed)
//   POST|DELETE|GET …/exams/{id}/paper-file   the exam as an uploaded file (settings.paper_file)
//   settings.schedule_slot_id        the exam-timetable slot it was created from (org_schedule_exams.dart)
// (back: exam_engine/services/questions.py, attempts.py, routers/exams.py; FLUTTER_API_CHANGES.md "quick exam").
//
// Pure (unit-tested): QuickExam (defaults, validate, bodies) · QuickQuestion (essay key → answer key) · splitPoints ·
// examForSlot. `createQuickExam` runs the calls; `exam_quick_screen.dart` is the UI.
library;

import 'dart:typed_data';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_authoring.dart';

/// Where the exam is sat.
enum QuickMode { online, offline }

/// In-app questions, or the whole exam as one uploaded file.
enum QuickSource { questions, file }

/// How an essay's auto-grading key is given: a model paragraph, key points (ideas), or words that must appear.
enum EssayKey { model, points, keywords }

/// What the exam is for; picks the defaults.
enum QuickKind { quiz, midterm, finalExam }

QuickKind quickKindOf(String? scheduleKind) => switch (scheduleKind) {
      'midterm' => QuickKind.midterm,
      'final' => QuickKind.finalExam,
      _ => QuickKind.quiz,
    };

String quickKindTitle(QuickKind k) => switch (k) {
      QuickKind.midterm => t('امتحان منتصف الفصل', 'Midterm exam'),
      QuickKind.finalExam => t('الامتحان النهائي', 'Final exam'),
      QuickKind.quiz => t('اختبار قصير', 'Quiz'),
    };

String essayKeyLabel(EssayKey k) => switch (k) {
      EssayKey.model => t('إجابة نموذجية', 'Model answer'),
      EssayKey.points => t('نقاط أساسية', 'Key points'),
      EssayKey.keywords => t('كلمات يجب ذكرها', 'Must-have words'),
    };

String essayKeyHint(EssayKey k) => switch (k) {
      EssayKey.model => t('اكتب فقرة الإجابة الصحيحة', 'Write the correct answer as a paragraph'),
      EssayKey.points => t('فكرة في كل سطر — تُقسم الدرجة عليها', 'One idea per line — the points are shared among them'),
      EssayKey.keywords => t('كلمة في كل سطر، ويمكن إضافة مرادفات: ضوء = إضاءة، نور', 'One word per line, synonyms after "=": light = lighting, glow'),
    };

/// [total] shared over [n] parts in 0.01 steps; the last part takes the rounding rest so the sum is exact.
List<double> splitPoints(double total, int n) {
  if (n <= 0) return const [];
  final each = (total / n * 100).floorToDouble() / 100;
  final out = List<double>.filled(n, each);
  out[n - 1] = double.parse((total - each * (n - 1)).toStringAsFixed(2));
  return out;
}

List<String> _lines(String s) => s.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// The types the quick builder offers, in the order of its "add a question" row.
const quickQuestionTypes = <String>['mcq_single', 'true_false', 'fill_blank', 'short_answer', 'matching', 'essay'];

/// One question of the quick builder: multiple choice (one right answer), true / false, complete (fill_blank), short
/// answer, matching or essay. Multiple choice, the generator's and the open types keep their own fields; true / false,
/// complete and matching are carried by an engine [QuestionDraft] ([engine]), so their bodies and validation are the
/// full editor's, not a second copy.
class QuickQuestion {
  QuickQuestion.mcq()
      : type = 'mcq_single',
        points = 1,
        options = [QOption('a'), QOption('b'), QOption('c'), QOption('d')];
  QuickQuestion.essay()
      : type = 'essay',
        points = 5,
        options = [];
  QuickQuestion.shortAnswer()
      : type = 'short_answer',
        points = 2,
        options = [];
  QuickQuestion._engine(this.type, this.points)
      : options = [],
        engine = QuestionDraft(type: type);

  /// A new empty question of [type] (one of [quickQuestionTypes]).
  factory QuickQuestion.ofType(String type) => switch (type) {
        'true_false' => QuickQuestion._engine(type, 1),
        'fill_blank' => QuickQuestion._engine(type, 1),
        'matching' => QuickQuestion._engine(type, 2),
        'short_answer' => QuickQuestion.shortAnswer(),
        'essay' => QuickQuestion.essay(),
        _ => QuickQuestion.mcq(),
      };

  final String type;
  String prompt = '';
  double points;

  /// 1 (easy) to 5 (hard); kept on the bank question.
  int difficulty = 3;

  /// true / false, complete and matching: the engine draft that holds their answer parts.
  QuestionDraft? engine;
  List<QOption> options;
  String? correct;

  /// Essay: graded by the project's grader when on; the teacher marks it otherwise.
  bool autoGrade = true;
  EssayKey keyBy = EssayKey.model;
  String keyText = '';

  bool get isEssay => type == 'essay' || type == 'short_answer';

  /// The engine question (body + answer key) this stands for.
  QuestionDraft toDraft() {
    final e = engine;
    if (e != null) {
      return e
        ..prompt = prompt
        ..points = points
        ..difficulty = difficulty;
    }
    final d = QuestionDraft(type: type)
      ..prompt = prompt
      ..points = points
      ..difficulty = difficulty;
    if (!isEssay) {
      d.options = [for (final o in options) if (o.text.trim().isNotEmpty) o];
      d.correctSingle = d.options.any((o) => o.id == correct) ? correct : null;
      return d;
    }
    if (!autoGrade) {
      d.extraAnswer = {'auto_grade': false};
      return d;
    }
    switch (keyBy) {
      case EssayKey.model:
        d.model = keyText;
      case EssayKey.points:
        final ideas = _lines(keyText);
        final pts = splitPoints(points, ideas.length);
        d.rubric = [for (var i = 0; i < ideas.length; i++) RubricCriterion(id: 'c${i + 1}', criterion: ideas[i], points: pts[i])];
      case EssayKey.keywords:
        final kws = parseKeywords(keyText);
        final pts = splitPoints(points, kws.length);
        d.rubric = [
          for (var i = 0; i < kws.length; i++)
            RubricCriterion(id: 'c${i + 1}', criterion: kws[i].term, points: pts[i], keywords: [RubricKeyword(kws[i].term, kws[i].synonyms)]),
        ];
    }
    return d;
  }

  /// Codes for [quickCodeText]; empty = ready.
  List<String> validate() {
    if (engine != null) return toDraft().validate();
    final out = <String>[];
    if (prompt.trim().isEmpty) out.add('prompt_required');
    if (!(points > 0)) out.add('points_positive');
    if (!isEssay) {
      final filled = options.where((o) => o.text.trim().isNotEmpty).toList();
      if (filled.length < 2) out.add('options_required');
      if (correct == null || !filled.any((o) => o.id == correct)) out.add('pick_correct');
    } else if (autoGrade && _lines(keyText).isEmpty) {
      out.add('essay_key_required');
    }
    return out;
  }
}

/// The whole quick exam: the creator's answers plus the defaults.
class QuickExam {
  QuickExam({required this.kind, this.courseId, this.orgId, this.scheduleSlotId, this.sessionId, String? title, this.startsAt, this.endsAt})
      : title = title ?? quickKindTitle(kind) {
    final window = startsAt != null && endsAt != null ? endsAt!.difference(startsAt!).inMinutes : null;
    durationMinutes = window != null && window > 0
        ? window
        : switch (kind) {
            QuickKind.quiz => 30,
            QuickKind.midterm => 60,
            QuickKind.finalExam => 120,
          };
    highStakes = kind != QuickKind.quiz;
    resultsPolicy = kind == QuickKind.quiz ? 'after_submit' : 'when_published';
  }

  final QuickKind kind;
  final int? courseId;
  int? orgId;
  final int? scheduleSlotId;

  /// The session this exam locks the lessons after (settings.session_id, D-197); null = no lock.
  int? sessionId;

  QuickMode? mode;
  QuickSource source = QuickSource.questions;
  String title;
  final List<QuickQuestion> questions = [];

  // the uploaded exam paper
  String? fileName;
  Uint8List? fileBytes;
  String? filePath;
  double filePoints = 100;

  // Advanced (smart defaults)
  late int durationMinutes;
  DateTime? startsAt;
  DateTime? endsAt;
  /// 0 = unlimited attempts.
  int maxAttempts = 1;

  /// Shown to students above the questions.
  String description = '';

  /// Questions each student gets drawn from the list (the section pool_size); null = all of them.
  int? poolSize;
  bool shuffle = true;
  late bool highStakes;
  late String resultsPolicy;
  double passingPercent = 50;
  String passcode = '';

  bool get isFile => source == QuickSource.file;
  bool get hasFile => fileName != null && (fileBytes != null || filePath != null);
  double get totalPoints => isFile ? filePoints : questions.fold(0.0, (s, q) => s + q.points);

  /// The single question that stands for an uploaded paper: online students upload their answer file; offline the
  /// teacher enters one mark per student. Never auto-graded.
  QuickQuestion get paperQuestion => QuickQuestion.essay()
    ..prompt = t('أجب عن أسئلة الملف المرفق', 'Answer the questions in the attached file')
    ..points = filePoints
    ..autoGrade = false;

  String get paperQuestionType => mode == QuickMode.offline ? 'essay' : 'file_upload';

  /// Codes for [quickCodeText] (the exam), and per question its index → codes.
  (List<String>, Map<int, List<String>>) validate() {
    final out = <String>[];
    final perQ = <int, List<String>>{};
    if (mode == null) out.add('mode_required');
    if (title.trim().isEmpty) out.add('title_required');
    if (durationMinutes <= 0) out.add('bad_duration');
    if (maxAttempts < 0 || maxAttempts > 100) out.add('bad_attempts');
    if (poolSize != null && !isFile && (poolSize! < 1 || (questions.isNotEmpty && poolSize! > questions.length))) out.add('bad_pool');
    if (startsAt != null && endsAt != null && !endsAt!.isAfter(startsAt!)) out.add('bad_window');
    if (isFile) {
      if (!hasFile) out.add('file_required');
      if (!(filePoints > 0)) out.add('points_positive');
    } else {
      if (questions.isEmpty) out.add('no_questions');
      for (var i = 0; i < questions.length; i++) {
        final v = questions[i].validate();
        if (v.isNotEmpty) perQ[i] = v;
      }
    }
    return (out, perQ);
  }

  ExamDraft toExamDraft() {
    final d = ExamDraft()
      ..orgId = orgId
      ..courseId = courseId
      ..title = title.trim()
      ..description = description.trim()
      ..sessionId = sessionId
      ..durationMinutes = durationMinutes
      ..startsAt = startsAt
      ..endsAt = endsAt
      ..maxAttempts = maxAttempts
      ..highStakes = highStakes
      ..resultsPolicy = resultsPolicy
      ..passingPercent = passingPercent
      ..passcode = passcode.trim().isEmpty ? null : passcode.trim()
      ..settings = {
        'quick': true,
        'mode': mode == QuickMode.offline ? 'offline' : 'online',
        'schedule_slot_id': ?scheduleSlotId,
      };
    return d;
  }

  SectionDraft toSection() => SectionDraft()
    ..title = isFile ? t('ورقة الامتحان', 'Exam paper') : t('الأسئلة', 'Questions')
    ..mode = mode == QuickMode.offline ? 'paper' : 'online'
    ..shuffleQuestions = shuffle && !isFile && mode == QuickMode.online
    ..shuffleOptions = shuffle && !isFile && mode == QuickMode.online
    ..poolSize = isFile ? null : poolSize;

  /// The engine questions to create, in order.
  List<QuestionDraft> questionDrafts() {
    if (!isFile) return [for (final q in questions) q.toDraft()];
    final p = paperQuestion;
    final d = QuestionDraft(type: paperQuestionType)
      ..prompt = p.prompt
      ..points = p.points
      ..extraAnswer = {'auto_grade': false};
    return [d];
  }
}

String quickTypeLabel(String type) => switch (type) {
      'true_false' => t('صح / خطأ', 'True / False'),
      'fill_blank' => t('أكمل', 'Complete'),
      'short_answer' => t('إجابة قصيرة', 'Short answer'),
      'matching' => t('مطابقة', 'Matching'),
      'essay' => t('مقالي', 'Essay'),
      _ => t('اختيار من متعدد', 'Multiple choice'),
    };

/// The delivery choice that closes the builder: online in the app, or printed / exported.
String quickModeTitle(QuickMode m) => m == QuickMode.online ? t('إلكتروني في التطبيق', 'Online in the app') : t('طباعة / تصدير', 'Print / export');

String quickCodeText(String code) => switch (code) {
      'mode_required' => t('اختر: إلكتروني أم ورقي', 'Choose online or offline'),
      'title_required' => t('اكتب اسم الاختبار', 'Give the exam a name'),
      'bad_duration' => t('المدة يجب أن تكون أكبر من صفر', 'The duration must be more than zero'),
      'bad_attempts' => t('عدد المحاولات بين 0 (بلا حد) و100', 'Attempts: 0 (unlimited) to 100'),
      'bad_pool' => t('عدد الأسئلة لكل طالب بين 1 وعدد الأسئلة', 'Questions per student: from 1 up to the number of questions'),
      'bad_window' => t('النهاية يجب أن تكون بعد البداية', 'The end must be after the start'),
      'file_required' => t('ارفع ملف الامتحان', 'Upload the exam file'),
      'no_questions' => t('أضف سؤالاً واحداً على الأقل', 'Add at least one question'),
      'prompt_required' => t('اكتب نص السؤال', 'Write the question'),
      'points_positive' => t('الدرجة يجب أن تكون أكبر من صفر', 'Points must be more than zero'),
      'options_required' => t('اكتب خيارين على الأقل', 'Write at least two choices'),
      'pick_correct' => t('اختر الإجابة الصحيحة', 'Pick the right answer'),
      'essay_key_required' => t('أضف ما يُصحَّح عليه، أو أوقف التصحيح التلقائي', 'Add what to grade against, or turn auto-grading off'),
      _ => authoringCodeText(code),
    };

/// The engine exam created from an exam-timetable slot, if any (`settings.schedule_slot_id`).
Map<String, dynamic>? examForSlot(List<Map<String, dynamic>> exams, int slotId) {
  for (final e in exams) {
    if (asInt(asMap(e['settings'])['schedule_slot_id'], -1) == slotId && e['status'] != 'archived') return e;
  }
  return null;
}

/// The engine exams of [exams] keyed by the timetable slot they were made from.
Map<int, Map<String, dynamic>> examsBySlot(List<Map<String, dynamic>> exams) => {
      for (final e in exams)
        if (asMap(e['settings'])['schedule_slot_id'] != null && e['status'] != 'archived') asInt(asMap(e['settings'])['schedule_slot_id']): e,
    };

// ── running it ──────────────────────────────────────────────────────────────────────────────────────────────────

/// What `createQuickExam` did: the exam id once it exists (even when a later step failed, so the creator can finish
/// in the full editor), and the error text of the step that failed.
class QuickResult {
  const QuickResult({this.examId, this.error, this.published = false});
  final int? examId;
  final String? error;
  final bool published;
  bool get ok => error == null && examId != null;
}

/// Exam → section → questions (created and placed) → paper file → publish. Stops at the first failure.
Future<QuickResult> createQuickExam(ExamAuthoringApi api, QuickExam q, {bool publish = true}) async {
  if (q.orgId == null && q.courseId != null) q.orgId = (await api.resolveScope(q.courseId!)).orgId;
  final ex = await api.createExam(q.toExamDraft().toBody());
  if (!ex.ok) return QuickResult(error: authoringError(ex));
  final id = asInt(ex.map['id']);
  final sec = await api.addSection(id, q.toSection().toBody());
  if (!sec.ok) return QuickResult(examId: id, error: authoringError(sec));
  final sid = asInt(sec.map['id']);
  for (final d in q.questionDrafts()) {
    final created = await api.createQuestion(d.toCreate(orgId: q.orgId, courseId: q.courseId));
    if (!created.ok) return QuickResult(examId: id, error: authoringError(created));
    final placed = await api.place(id, sid, questionId: asInt(created.map['id']), points: d.points);
    if (!placed.ok) return QuickResult(examId: id, error: authoringError(placed));
  }
  if (q.isFile) {
    final up = await api.uploadPaperFile(id, fileName: q.fileName!, bytes: q.fileBytes, path: q.filePath);
    if (!up.ok) return QuickResult(examId: id, error: authoringError(up));
  }
  if (!publish) return QuickResult(examId: id);
  final pub = await api.lifecycle(id, ExamAction.publish);
  if (!pub.ok) return QuickResult(examId: id, error: authoringError(pub));
  return QuickResult(examId: id, published: true);
}

/// The file attached to an exam (`settings.paper_file` without the storage key), or null.
Map<String, dynamic>? paperFileOf(Map<String, dynamic> exam) {
  final f = asMap(asMap(exam['settings'])['paper_file']);
  return f.isEmpty ? null : f;
}

/// Engine exam rows for a results list: `GET /exams/{id}/attempts` items with the roster's names.
class ResultRow {
  ResultRow({required this.attemptId, required this.studentId, required this.name, required this.state, this.percentage, this.score,
      this.maxScore, this.passed, required this.needsReview});
  final int attemptId;
  final int? studentId;
  final String name;
  final String state;
  final double? percentage, score, maxScore;
  final bool? passed;
  final bool needsReview;

  bool get finished => const {'submitted', 'auto_submitted', 'graded'}.contains(state);

  static List<ResultRow> fromAttempts(Map<String, dynamic> body, Map<int, String> names) {
    final out = <ResultRow>[];
    for (final a in asMapList(body['items'])) {
      final sid = a['student_id'] == null ? null : asInt(a['student_id']);
      double? d(String k) => a[k] == null ? null : (a[k] as num).toDouble();
      out.add(ResultRow(
        attemptId: asInt(a['id']),
        studentId: sid,
        name: sid == null ? t('طالب (تصحيح مجهول الهوية)', 'Student (anonymous marking)') : (names[sid] ?? t('طالب #$sid', 'Student #$sid')),
        state: '${a['state'] ?? ''}',
        percentage: d('percentage'),
        score: d('score'),
        maxScore: d('max_score'),
        passed: a['passed'] is bool ? a['passed'] as bool : null,
        needsReview: a['needs_review'] == true,
      ));
    }
    // waiting for the teacher first, then by name
    out.sort((x, y) => x.needsReview != y.needsReview ? (x.needsReview ? -1 : 1) : x.name.compareTo(y.name));
    return out;
  }
}
