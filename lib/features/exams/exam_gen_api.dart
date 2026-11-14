// Question generation v2 (D-194 / D-195), the client side. Pure and unit-tested (test/org/exam_generate_v2_test.dart):
// the request body, the outline / materials / job models, the mapping of the server's six question types to the quick
// builder's [QuickQuestion]s, and the calls. The wizard is exam_generate_wizard.dart; exam_generate.dart keeps the
// entry points the quick builder uses (genItemsOf, regenerateGenItem, ExamGenReview).
//
//   GET    /api/v1/rag/courses/{id}/outline?document_ids=1,2  → {documents[{id, title, state, pages, excluded}], sections[…]}
//   GET    /api/v1/rag/courses/{id}/materials                 → {items[{id, title, file_name, size, document_id, state}]}
//   POST   /api/v1/rag/documents/from-material {course_id, material_id, org_id?}  → 202 the document
//   POST   /api/v1/rag/exam-gen {course_id, document_ids, section_ids, exclude_pages, types[{type, count, points}],
//          difficulty{easy, medium, hard}, lang, focus?}      → 202 the job
//   GET    /api/v1/rag/exam-gen/{id}                          → {state, progress{done, total, phase, percent}, questions[Q], warnings[]}
//   POST   /api/v1/rag/exam-gen/{id}/items/{n}/regenerate {hint?} → 202 · DELETE …/items/{n} → the job
// D-301: the body also takes speed (fast | quality), avoid_prompts (the exam's own questions) and topic (no sections:
// topic-only writing); the job has progress.ready / failed / eta_seconds, cancelled, claimed, mode; 409 exam_gen_busy
// carries job_id. GET /exam-gen?course_id= lists the caller's recent jobs (the resume offer); POST …/cancel stops one,
// POST …/claim marks its questions taken. Kill switch `exam.auto_create` (403 feature_disabled).
// A bare 404 / 405 on outline or exam-gen = an older server: the old sheet (exam_generate_sheet.dart) stays in charge.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart' show RagApi;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show MatchPair, QOption, TextItem;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/exams/exam_quick.dart';

/// The Super Admin's kill switches (D-301): automatic question generation, and automatic correction (bubble sheets,
/// scanned sheets, camera marking, offline auto-grade). The services refuse them too (403 feature_disabled).
const kExamAutoCreateKey = 'exam.auto_create';
const kExamAutoCorrectKey = 'exam.auto_correct';

// ── what to ask for ─────────────────────────────────────────────────────────────────────────────────────────────

/// The types the server writes, in the wizard's order (the quick builder's own).
const genV2Types = quickQuestionTypes;

/// The server's caps: questions per type and in total, marks per question.
const genV2MaxPerType = 40;
const genV2MaxTotal = 60;
const genV2MinPoints = 0.25;
const genV2MaxPoints = 100.0;

String genV2TypeLabel(String type) => quickTypeLabel(type);

/// One row of the Questions step: a type, switched on or off, how many, the marks of each.
class GenTypeRow {
  GenTypeRow(this.type, {this.enabled = false, this.count = 4, this.points = 1});
  final String type;
  bool enabled;
  int count;
  double points;

  int get effectiveCount => enabled ? count : 0;
}

/// The default rows: ten single-answer choice questions, the other types off with a sensible count and mark.
List<GenTypeRow> defaultGenRows() => [
      GenTypeRow('mcq_single', enabled: true, count: 10, points: 1),
      GenTypeRow('true_false', count: 4, points: 1),
      GenTypeRow('fill_blank', count: 4, points: 1),
      GenTypeRow('short_answer', count: 3, points: 2),
      GenTypeRow('matching', count: 2, points: 2),
      GenTypeRow('essay', count: 2, points: 5),
    ];

int genTotalQuestions(List<GenTypeRow> rows) => rows.fold(0, (s, r) => s + r.effectiveCount);

double genTotalMarks(List<GenTypeRow> rows) {
  final v = rows.fold<double>(0, (s, r) => s + r.effectiveCount * r.points);
  return double.parse(v.toStringAsFixed(2));
}

/// "12" or "7.5": marks without a trailing ".0".
String genNum(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

enum GenLevel { easy, medium, hard }

String genLevelLabel(GenLevel l) => switch (l) {
      GenLevel.easy => t('سهل', 'Easy'),
      GenLevel.medium => t('متوسط', 'Medium'),
      GenLevel.hard => t('صعب', 'Hard'),
    };

/// The difficulty mix: three whole percentages that always sum to 100.
class GenMix {
  const GenMix(this.easy, this.medium, this.hard);
  final int easy, medium, hard;

  static const balanced = GenMix(30, 50, 20);
  static const easier = GenMix(50, 40, 10);
  static const harder = GenMix(15, 45, 40);
  static const presets = <GenMix>[easier, balanced, harder];

  int of(GenLevel l) => switch (l) { GenLevel.easy => easy, GenLevel.medium => medium, GenLevel.hard => hard };
  int get sum => easy + medium + hard;
  bool get valid => sum == 100 && easy >= 0 && medium >= 0 && hard >= 0;

  /// [level] set to [value] (0–100); what is left is shared by the other two in proportion to what they had, so the
  /// sum stays 100.
  GenMix set(GenLevel level, int value) {
    final v = value.clamp(0, 100);
    final others = GenLevel.values.where((l) => l != level).toList();
    final rest = 100 - v;
    final a = of(others[0]), b = of(others[1]);
    final first = a + b == 0 ? rest ~/ 2 : (rest * a / (a + b)).round();
    final second = rest - first;
    return GenMix._of({level: v, others[0]: first, others[1]: second});
  }

  factory GenMix._of(Map<GenLevel, int> m) => GenMix(m[GenLevel.easy]!, m[GenLevel.medium]!, m[GenLevel.hard]!);

  Map<String, int> toJson() => {'easy': easy, 'medium': medium, 'hard': hard};

  @override
  bool operator ==(Object other) => other is GenMix && other.easy == easy && other.medium == medium && other.hard == hard;
  @override
  int get hashCode => Object.hash(easy, medium, hard);
}

/// Page ranges typed by the teacher ("1-3, 7, 10–12"; Arabic digits, "،" and "؛" accepted) → `[[1,3],[7,7],[10,12]]`.
/// [bad] is set when a piece is not a number or a range (the ranges that parsed are still returned).
class ExcludeParse {
  const ExcludeParse(this.ranges, this.bad);
  final List<List<int>> ranges;
  final bool bad;
}

ExcludeParse parseExcludeRanges(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var s = input;
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(arabic[i], '$i');
  }
  s = s.replaceAll(RegExp('[‒–—−]'), '-');
  final out = <List<int>>[];
  var bad = false;
  for (final raw in s.split(RegExp(r'[,،;؛\n]'))) {
    final p = raw.replaceAll(RegExp(r'\s+'), '');
    if (p.isEmpty) continue;
    final m = RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$').firstMatch(p);
    if (m == null) {
      bad = true;
      continue;
    }
    var a = int.parse(m.group(1)!), b = m.group(2) == null ? a : int.parse(m.group(2)!);
    if (a < 1 || b < 1) {
      bad = true;
      continue;
    }
    if (b < a) (a, b) = (b, a);
    out.add([a, b]);
  }
  return ExcludeParse(out, bad);
}

/// Why the plan cannot be sent yet (a code for [genV2CodeText]), or null.
String? genV2Problem(
    {required List<int> sectionIds, required List<GenTypeRow> rows, required GenMix mix, Iterable<String> excludeTexts = const [], String topic = ''}) {
  if (sectionIds.isEmpty && topic.trim().length < 3) return 'no_sections';
  final total = genTotalQuestions(rows);
  if (total < 1) return 'no_types';
  if (total > genV2MaxTotal || rows.any((r) => r.effectiveCount > genV2MaxPerType)) return 'too_many_questions';
  if (rows.any((r) => r.enabled && (r.points < genV2MinPoints || r.points > genV2MaxPoints))) return 'bad_points';
  if (!mix.valid) return 'bad_mix';
  if (excludeTexts.any((x) => parseExcludeRanges(x).bad)) return 'bad_pages';
  return null;
}

String genV2CodeText(String? code, String fallback) => switch (code) {
      'no_sections' => t('اختر فصلاً واحداً على الأقل', 'Pick at least one chapter'),
      'no_types' => t('فعّل نوع أسئلة واحداً على الأقل', 'Switch on at least one question type'),
      'too_many_questions' => t('الحد الأقصى $genV2MaxTotal سؤالاً ($genV2MaxPerType لكل نوع)', 'At most $genV2MaxTotal questions ($genV2MaxPerType per type)'),
      'bad_points' => t('درجة السؤال من ${genNum(genV2MinPoints)} إلى ${genNum(genV2MaxPoints)}', 'Marks per question: ${genNum(genV2MinPoints)} to ${genNum(genV2MaxPoints)}'),
      'bad_mix' => t('مجموع نسب الصعوبة يجب أن يكون 100', 'The difficulty mix must add up to 100'),
      'bad_pages' => t('اكتب الصفحات هكذا: 1-3، 7، 10-12', 'Write the pages like this: 1-3, 7, 10-12'),
      'sections_invalid' => t('بعض الفصول المختارة لم تعد موجودة — أعد اختيارها', 'Some chosen chapters no longer exist — pick them again'),
      'no_course_documents' => t('ارفع مستند المقرر أولاً', 'Upload the course document first'),
      'exam_gen_busy' => t('لديك أسئلة قيد الإنشاء في مقرر آخر — أوقفها أو انتظر حتى تنتهي', 'You have questions being written for another course — stop them or wait until they finish'),
      'feature_disabled' => t('إنشاء الأسئلة تلقائياً متوقف حالياً', 'Automatic question generation is switched off right now'),
      'topic_needs_model' => t('الكتابة من موضوع تحتاج نموذج لغة غير متاح الآن — ارفع ملفاً للمقرر', 'Writing from a topic needs a language model, which is not available now — upload a course file'),
      'bad_topic' => t('اكتب موضوعاً أوضح (3 أحرف على الأقل)', 'Type a clearer topic (at least 3 characters)'),
      'draft_not_running' => t('انتهى إنشاء هذه الأسئلة بالفعل', 'These questions are already finished'),
      _ => fallback,
    };

/// The POST /rag/exam-gen body (pure): only switched-on types, the exclude ranges of the documents that have any.
Map<String, dynamic> examGenV2Body({
  required int courseId,
  int? orgId,
  List<int> documentIds = const [],
  required List<int> sectionIds,
  Map<int, List<List<int>>> excludePages = const {},
  required List<GenTypeRow> rows,
  GenMix mix = GenMix.balanced,
  String lang = 'auto',
  String focus = '',
  String validate = 'auto',
  int maxFocus = 300,
  GenSpeed speed = GenSpeed.fast,
  List<String> avoidPrompts = const [],
  String topic = '',
}) {
  final f = focus.trim();
  final tp = topic.trim();
  final avoid = genAvoidPrompts(avoidPrompts);
  return {
    'course_id': courseId,
    'org_id': ?orgId,
    if (documentIds.isNotEmpty) 'document_ids': documentIds,
    'section_ids': sectionIds,
    if (tp.isNotEmpty) 'topic': tp.length > genMaxTopicChars ? tp.substring(0, genMaxTopicChars) : tp,
    'speed': speed.name,
    if (avoid.isNotEmpty) 'avoid_prompts': avoid,
    if (excludePages.values.any((v) => v.isNotEmpty))
      'exclude_pages': {for (final e in excludePages.entries) if (e.value.isNotEmpty) '${e.key}': e.value},
    'types': [
      for (final r in rows)
        if (r.enabled && r.count > 0) {'type': r.type, 'count': r.count, 'points': r.points}
    ],
    'difficulty': mix.toJson(),
    'lang': lang,
    if (f.isNotEmpty) 'focus': f.length > maxFocus ? f.substring(0, maxFocus) : f,
    'validate': validate,
  };
}

// ── the outline and the course materials ────────────────────────────────────────────────────────────────────────

class GenSection {
  const GenSection({required this.id, required this.documentId, required this.title, this.headingPath = '', this.level = 1, this.pageFrom, this.pageTo, this.words = 0});
  final int id, documentId, level, words;
  final String title, headingPath;
  final int? pageFrom, pageTo;

  factory GenSection.fromJson(Map<String, dynamic> j) => GenSection(
      id: asInt(j['id']),
      documentId: asInt(j['document_id']),
      title: asStr(j['title']),
      headingPath: asStr(j['heading_path']),
      level: asInt(j['level'], 1),
      pageFrom: j['page_from'] == null ? null : asInt(j['page_from']),
      pageTo: j['page_to'] == null ? null : asInt(j['page_to']),
      words: asInt(j['words']));

  /// "ص 3–7" / "pp. 3–7"; empty when the section has no pages.
  String get pagesLabel => genPagesLabel(pageFrom, pageTo);
}

String genPagesLabel(int? from, int? to) {
  if (from == null) return '';
  if (to == null || to == from) return t('ص $from', 'p. $from');
  return t('ص $from–$to', 'pp. $from–$to');
}

class GenOutlineDoc {
  const GenOutlineDoc({required this.id, required this.title, this.state = 'ready', this.pages = 0, this.sections = const []});
  final int id, pages;
  final String title, state;
  final List<GenSection> sections;
  bool get ready => state == 'ready';
}

class GenOutline {
  const GenOutline(this.documents);
  final List<GenOutlineDoc> documents;
  static const empty = GenOutline([]);

  List<GenSection> get allSections => [for (final d in documents) ...d.sections];

  factory GenOutline.fromJson(Map<String, dynamic> j) {
    final secs = [for (final s in asMapList(j['sections'])) GenSection.fromJson(s)];
    return GenOutline([
      for (final d in asMapList(j['documents']))
        GenOutlineDoc(
            id: asInt(d['id']),
            title: asStr(d['title']),
            state: asStr(d['state'], 'ready'),
            pages: asInt(d['pages']),
            sections: [for (final s in secs) if (s.documentId == asInt(d['id'])) s])
    ]);
  }
}

/// A file of the course's own materials (the sessions' files), and the RAG document it already became, if any.
class GenMaterial {
  const GenMaterial({required this.id, required this.title, this.fileName = '', this.size = 0, this.sessionTitle = '', this.documentId, this.state = ''});
  final int id, size;
  final String title, fileName, sessionTitle, state;
  final int? documentId;

  bool get used => documentId != null;
  String get displayTitle => title.trim().isNotEmpty ? title : fileName;

  factory GenMaterial.fromJson(Map<String, dynamic> j) => GenMaterial(
      id: asInt(j['id']),
      title: asStr(j['title']),
      fileName: asStr(j['file_name']),
      size: asInt(j['size']),
      sessionTitle: asStr(j['session_title']),
      documentId: j['document_id'] == null ? null : asInt(j['document_id']),
      state: asStr(j['state']));
}

List<GenMaterial> genMaterialsOf(Map<String, dynamic> j) => [for (final m in asMapList(j['items'])) if (asInt(m['id']) > 0) GenMaterial.fromJson(m)];

// ── the job ─────────────────────────────────────────────────────────────────────────────────────────────────────

class GenProgress {
  const GenProgress({this.done = 0, this.total = 0, this.phase = 'planning', this.percent = 0, this.ready, this.failed = 0, this.etaSeconds});
  final int done, total, percent;
  final String phase;

  /// Questions that passed every check (D-301); null on an older server ([readyCount] falls back to [done]).
  final int? ready;
  final int failed;

  /// Seconds left from the run's own pace; null = not known yet / finished.
  final int? etaSeconds;

  int get readyCount => ready ?? done;

  factory GenProgress.fromJson(Map<String, dynamic> j) {
    final done = asInt(j['done']), total = asInt(j['total']);
    final p = j['percent'];
    final percent = p is num ? p.round() : (total > 0 ? (done * 100 / total).round() : 0);
    return GenProgress(
        done: done,
        total: total,
        phase: asStr(j['phase'], 'planning'),
        percent: percent.clamp(0, 100),
        ready: j['ready'] is num ? asInt(j['ready']) : null,
        failed: asInt(j['failed']),
        etaSeconds: j['eta_seconds'] is num ? asInt(j['eta_seconds']) : null);
  }
}

/// How fast the questions are written (D-301): [fast] with the platform's quick model and the rules' checks, [quality]
/// with the exam model and a second check of every question by the model (about 1.5x the time, measured locally).
enum GenSpeed { fast, quality }

String genSpeedLabel(GenSpeed s) => switch (s) {
      GenSpeed.fast => t('سريع', 'Fast'),
      GenSpeed.quality => t('أعلى جودة', 'Best quality'),
    };

String genSpeedHint(GenSpeed s) => switch (s) {
      GenSpeed.fast => t('الأسرع: تُفحص كل إجابة بقواعد صارمة في النص.', 'Quickest: every answer is checked against the text by strict rules.'),
      GenSpeed.quality => t('أبطأ بنحو النصف: نموذج أكبر يكتب الأسئلة ثم يراجع كل سؤال مرة ثانية.',
          'About half as fast again: a larger model writes the questions, then checks every one a second time.'),
    };

/// The longest topic the server takes (topic-only writing).
const genMaxTopicChars = 200;

/// The exam's own questions to send as `avoid_prompts`: trimmed, 8+ characters, no repeats, at most 200 of 300 chars.
List<String> genAvoidPrompts(Iterable<String> prompts) {
  final out = <String>[];
  final seen = <String>{};
  for (final p in prompts) {
    var x = p.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (x.length < 8) continue;
    if (x.length > 300) x = x.substring(0, 300);
    if (seen.add(x.toLowerCase())) out.add(x);
    if (out.length >= 200) break;
  }
  return out;
}

/// "About 4 min left" / "Less than a minute left"; null when unknown.
String? genEtaText(int? seconds) {
  if (seconds == null || seconds < 0) return null;
  if (seconds < 60) return t('أقل من دقيقة متبقية', 'Less than a minute left');
  final m = (seconds / 60).round();
  if (m >= 60) {
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? t('نحو $h ساعة متبقية', 'About $h h left') : t('نحو $h ساعة و$r دقيقة متبقية', 'About $h h $r min left');
  }
  return t('نحو $m دقيقة متبقية', 'About $m min left');
}

/// What the teacher sees of a job: waiting its turn, being written, finished (some may have failed), stopped, failed.
enum GenJobStatus { queued, writing, done, partial, cancelled, failed }

String genJobStatusLabel(GenJobStatus s) => switch (s) {
      GenJobStatus.queued => t('في الانتظار — سيبدأ بعد قليل', 'Waiting its turn — starting shortly'),
      GenJobStatus.writing => t('نكتب الأسئلة', 'Writing the questions'),
      GenJobStatus.done => t('اكتملت الأسئلة', 'The questions are ready'),
      GenJobStatus.partial => t('اكتمل معظم الأسئلة', 'Most of the questions are ready'),
      GenJobStatus.cancelled => t('أُوقف الإنشاء', 'Generation stopped'),
      GenJobStatus.failed => t('تعذّر إنشاء الأسئلة', 'The questions could not be generated'),
    };

String genPhaseLabel(String phase) => switch (phase) {
      'planning' => t('نخطّط توزيع الأسئلة على الفصول…', 'Planning the questions across the chapters…'),
      'concepts' => t('نستخرج المفاهيم الأساسية…', 'Finding the key concepts…'),
      'writing' => t('نكتب الأسئلة…', 'Writing the questions…'),
      'validating' => t('نراجع الأسئلة ونتحقق من إجاباتها…', 'Checking the questions and their answers…'),
      'done' => t('اكتمل', 'Done'),
      _ => t('نجهّز الأسئلة…', 'Getting ready…'),
    };

/// A note the server attached to a generation job; [text] is what the teacher reads, in the app's language.
class GenWarning {
  const GenWarning(this.code, this.message, {this.n, this.reason = '', this.title = ''});
  final String code, message;

  /// The question it is about (from 1), when it is about one.
  final int? n;

  /// `rules_writer`: no_model | platform_off | org_choice | needs_consent; `slot_failed`: why the slot failed.
  final String reason;

  /// `section_empty`: the section's title.
  final String title;

  factory GenWarning.fromJson(Map<String, dynamic> w) =>
      GenWarning(asStr(w['code']), asStr(w['message']), n: w['n'] is num ? asInt(w['n']) : null, reason: asStr(w['reason']), title: asStr(w['title']));

  String get text {
    final q = n == null ? '' : t('السؤال $n: ', 'Question $n: ');
    return switch (code) {
      'rules_writer' => switch (reason) {
          'no_model' => t('كُتبت الأسئلة من نص المادة مباشرةً لأنه لا يوجد نموذج لغوي مُعدّ. راجعها قبل النشر.',
              'The questions were written straight from the text because no language model is set up. Review them before publishing.'),
          'org_choice' => t('اختارت مؤسستك كتابة الأسئلة من نص المادة دون نموذج لغوي. راجعها قبل النشر.',
              'Your organization chose to write questions from the text without a language model. Review them before publishing.'),
          'needs_consent' => t('كُتبت الأسئلة من نص المادة لأن مؤسستك لم تسمح بإرسال المحتوى إلى نموذج خارجي. يمكن لمسؤول المؤسسة السماح بذلك.',
              'The questions were written from the text because your organization has not allowed sending content to an external model. An organization admin can allow it.'),
          _ => t('كُتبت الأسئلة من نص المادة دون نموذج لغوي. راجعها قبل النشر.', 'The questions were written from the text without a language model. Review them before publishing.'),
        },
      'matching_to_mcq' => '$q${t('لا توجد تعريفات كافية للمطابقة في هذا الفصل، فكُتب السؤال اختيارًا من متعدد.', 'the chapter has no definitions to match, so it was written as multiple choice.')}',
      'slot_failed' => '$q${t('تعذّرت كتابة سؤال من هذا الجزء. أعد التوليد أو اكتبه يدويًا.', 'could not be written from this part. Regenerate it or write it by hand.')}',
      'regenerate_failed' => '$q${t('تعذّرت إعادة التوليد، وبقي السؤال السابق.', 'regenerating failed; the previous question was kept.')}',
      'section_empty' => title.isEmpty
          ? t('أحد الفصول المختارة لا يحتوي نصًا صالحًا للأسئلة.', 'One of the chosen chapters has no text usable for questions.')
          : t('الفصل «$title» لا يحتوي نصًا صالحًا للأسئلة.', 'The chapter “$title” has no text usable for questions.'),
      'section_unavailable' => t('أحد الفصول المختارة لم يعد متاحًا.', 'One of the chosen chapters is no longer available.'),
      'topic_only' => t('كُتبت الأسئلة من الموضوع دون ملفات المقرر — راجع كل إجابة قبل النشر.',
          'The questions were written from the topic, without the course files — check every answer before publishing.'),
      'focus_not_found' => t('لم نجد في الفصول المختارة نصاً عن «التركيز»، فاستخدمنا كل الفصول.',
          'Nothing in the chosen chapters matched the focus, so every chapter was used.'),
      _ => message,
    };
  }
}

class GenJob {
  const GenJob(
      {required this.id,
      required this.state,
      this.progress = const GenProgress(),
      this.questions = const [],
      this.warnings = const [],
      this.error,
      this.params = const {},
      this.courseId,
      this.cancelled = false,
      this.claimed = false,
      this.mode = 'sections'});
  final int id;
  final String state;
  final GenProgress progress;
  final List<Map<String, dynamic>> questions;
  final List<GenWarning> warnings;
  final String? error;
  final Map<String, dynamic> params;
  final int? courseId;

  /// Stopped by the person (D-301): state failed, error `cancelled`; the questions written before stay.
  final bool cancelled;

  /// Its questions were taken into an exam already: no resume offer.
  final bool claimed;

  /// sections · topic (written from a topic, no course passage).
  final String mode;

  bool get done => state == 'done' || state == 'failed';
  bool get failed => state == 'failed';
  bool get active => state == 'queued' || state == 'running';

  /// The usable questions written so far (the ones that passed; removed / failed ones left out).
  List<Map<String, dynamic>> get readyItems => [for (final q in questions) if (asStr(q['state'], 'ok') == 'ok' && q['removed'] != true) q];

  GenJobStatus get status {
    if (state == 'queued') return GenJobStatus.queued;
    if (state == 'running') return GenJobStatus.writing;
    if (cancelled || error == 'cancelled') return GenJobStatus.cancelled;
    if (state == 'failed') return GenJobStatus.failed;
    return progress.failed > 0 || questions.any((q) => q['state'] == 'failed') ? GenJobStatus.partial : GenJobStatus.done;
  }

  /// Offered again when the generator opens: still being written, or finished with questions nobody took yet.
  bool get resumable => active || (!claimed && !cancelled && state == 'done' && progress.readyCount > 0);

  factory GenJob.fromJson(Map<String, dynamic> j) => GenJob(
      id: asInt(j['id']),
      state: asStr(j['state'], 'queued'),
      progress: GenProgress.fromJson(asMap(j['progress'])),
      questions: asMapList(j['questions']),
      warnings: [for (final w in asMapList(j['warnings'])) GenWarning.fromJson(w)],
      error: j['error']?.toString(),
      params: asMap(j['params']),
      courseId: j['course_id'] == null ? null : asInt(j['course_id']),
      cancelled: j['cancelled'] == true,
      claimed: j['claimed'] == true,
      mode: asStr(j['mode'], 'sections'));

  /// The item the SERVER numbered `n` (from 1; its `n` field, not its position in [questions]); null when there is none.
  Map<String, dynamic>? item(int n) {
    for (final q in questions) {
      if (q['n'] is num && asInt(q['n']) == n) return q;
    }
    return null;
  }
}

// ── a question's origin ─────────────────────────────────────────────────────────────────────────────────────────

/// Where in the course a question came from.
class GenSourceInfo {
  const GenSourceInfo({this.documentId, this.title = '', this.section = '', this.pageFrom, this.pageTo});
  final int? documentId, pageFrom, pageTo;
  final String title, section;

  factory GenSourceInfo.fromJson(Map<String, dynamic> j) => GenSourceInfo(
      documentId: j['document_id'] == null ? null : asInt(j['document_id']),
      title: asStr(j['title']),
      section: asStr(j['section']),
      pageFrom: j['page_from'] == null ? null : asInt(j['page_from']),
      pageTo: j['page_to'] == null ? null : asInt(j['page_to']));

  /// "ص 12 · الفصل 2" / "p. 12 · Chapter 2": the pages and the section's own title (the document's when none).
  String get label {
    final parts = [genPagesLabel(pageFrom, pageTo), section.trim().isNotEmpty ? section.trim() : title.trim()]..removeWhere((p) => p.isEmpty);
    return parts.join(' · ');
  }
}

/// What the server knows about a generated question besides the question: its source, the passage it came from and
/// how the check went. Kept next to the [QuickQuestion] (see [genMetaOf]).
class GenQMeta {
  const GenQMeta({this.n, this.source, this.evidence = '', this.concept = '', this.supported, this.checkedBy = '', this.writer = ''});

  /// The item number the SERVER gave the question (from 1): what regenerate and delete address. Not the feedback
  /// index (that one is the position in the draft's list, see `GenItemRef.n`). Null when the payload has none.
  final int? n;
  final GenSourceInfo? source;
  final String evidence, concept, checkedBy, writer;

  /// False = the check could not find the answer in the passage (the creator should look twice); null = not checked.
  final bool? supported;

  bool get hasSource => source != null && source!.label.isNotEmpty;
  bool get needsLook => supported == false;

  factory GenQMeta.fromJson(Map<String, dynamic> g) {
    final v = asMap(g['validation']);
    return GenQMeta(
        n: g['n'] is num ? asInt(g['n']) : null,
        source: g['source'] is Map ? GenSourceInfo.fromJson(asMap(g['source'])) : null,
        evidence: asStr(g['evidence']).trim(),
        concept: asStr(g['concept']),
        supported: v['supported'] is bool ? v['supported'] as bool : null,
        checkedBy: asStr(v['checked_by']),
        writer: asStr(g['writer']));
  }
}

final Expando<GenQMeta> _meta = Expando('genQMeta');

/// The server's notes on a generated question (null for a question the teacher wrote, or from an older server).
GenQMeta? genMetaOf(QuickQuestion q) => _meta[q];
void setGenMeta(QuickQuestion q, GenQMeta? m) => _meta[q] = m;

// ── the server's question → the quick builder's ─────────────────────────────────────────────────────────────────

const _levelToDifficulty = {'easy': 2, 'medium': 3, 'hard': 4};

bool _isV2Question(Map<String, dynamic> g) => g['type'] != 'mcq' && genV2Types.contains(g['type']);

/// Whether [g] is a v2 question (a type the old generator never wrote, or one with a `source`).
bool genIsV2(Map<String, dynamic> g) => _isV2Question(g) || g['source'] is Map || g['state'] is String;

/// A v2 question as a quick-builder question, or null when it cannot be used (removed, failed, empty, broken).
QuickQuestion? quickOfV2(Map<String, dynamic> g) {
  if (g['removed'] == true || g['state'] == 'failed' || g['state'] == 'regenerating') return null;
  final prompt = asStr(g['prompt']).trim();
  if (prompt.isEmpty) return null;
  final type = asStr(g['type']);
  final QuickQuestion? q;
  switch (type) {
    case 'mcq_single' || 'mcq':
      final opts = [for (final o in asMapList(g['options'])) if (asStr(o['text']).trim().isNotEmpty) QOption(asStr(o['id']), asStr(o['text']))];
      if (opts.length < 2) return null;
      q = QuickQuestion.mcq()
        ..options = opts
        ..correct = opts.any((o) => o.id == g['correct']) ? asStr(g['correct']) : null;
    case 'true_false':
      if (g['answer'] is! bool) return null;
      q = QuickQuestion.ofType('true_false');
      q.engine!.tfCorrect = g['answer'] as bool;
    case 'fill_blank':
      final answers = [for (final a in (g['answer'] is List ? g['answer'] as List : const [])) '$a'.trim()]..removeWhere((a) => a.isEmpty);
      if (answers.isEmpty) return null;
      q = QuickQuestion.ofType('fill_blank');
      q.engine!.blanks = [for (final a in answers) TextItem(a)];
    case 'matching':
      final pairs = [for (final p in (g['answer'] is List ? g['answer'] as List : const [])) if (p is Map) (asStr(p['left']).trim(), asStr(p['right']).trim())]
        ..removeWhere((p) => p.$1.isEmpty || p.$2.isEmpty);
      if (pairs.length < 2) return null;
      q = QuickQuestion.ofType('matching');
      q.engine!.pairs = [for (final (l, r) in pairs) MatchPair(l, r)];
    case 'short_answer' || 'essay':
      q = type == 'essay' ? QuickQuestion.essay() : QuickQuestion.shortAnswer();
      final points = [for (final p in (g['key_points'] is List ? g['key_points'] as List : const [])) '$p'.trim()]..removeWhere((p) => p.isEmpty);
      final answer = g['answer'] is String ? asStr(g['answer']).trim() : '';
      if (points.isNotEmpty) {
        q
          ..keyBy = EssayKey.points
          ..keyText = points.join('\n');
      } else if (answer.isNotEmpty) {
        q
          ..keyBy = EssayKey.model
          ..keyText = answer;
      } else {
        q.autoGrade = false;
      }
    default:
      return null;
  }
  q.prompt = prompt;
  if (g['points'] is num && (g['points'] as num) > 0) q.points = (g['points'] as num).toDouble();
  q.difficulty = _levelToDifficulty[asStr(g['difficulty'])] ?? q.difficulty;
  if (g['source'] is Map || g['evidence'] != null || g['validation'] is Map || g['n'] is num) setGenMeta(q, GenQMeta.fromJson(g));
  return q;
}

// ── the calls ───────────────────────────────────────────────────────────────────────────────────────────────────

/// An older server: no outline / generation v2 routes. The old sheet stays in charge.
bool genV2Unavailable(EngineResult r) => r.unavailable;

class ExamGenV2Api {
  ExamGenV2Api([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = RagApi.base;

  Future<EngineResult> outline(int courseId, {List<int> documentIds = const []}) =>
      engineCall(() => _api.get('$base/courses/$courseId/outline', queryParams: {if (documentIds.isNotEmpty) 'document_ids': documentIds.join(',')}));

  Future<EngineResult> materials(int courseId) => engineCall(() => _api.get('$base/courses/$courseId/materials'));

  Future<EngineResult> fromMaterial(int courseId, int materialId, {int? orgId}) =>
      engineCall(() => _api.post('$base/documents/from-material', body: {'course_id': courseId, 'material_id': materialId, 'org_id': ?orgId}));

  Future<EngineResult> create(Map<String, dynamic> body) => engineCall(() => _api.post('$base/exam-gen', body: body));

  Future<EngineResult> get(int id) => engineCall(() => _api.get('$base/exam-gen/$id'));

  /// The caller's jobs of the last 24 hours for [courseId], newest first (D-301: the resume offer). A bare 404 = older server.
  Future<EngineResult> list(int courseId) => engineCall(() => _api.get('$base/exam-gen', queryParams: {'course_id': '$courseId'}));

  /// Stops a queued / running job; the questions written so far stay.
  Future<EngineResult> cancel(int id) => engineCall(() => _api.post('$base/exam-gen/$id/cancel', body: const <String, dynamic>{}));

  /// Marks the job's questions taken (the resume offer forgets it). Fire-and-forget.
  Future<EngineResult> claim(int id) => engineCall(() => _api.post('$base/exam-gen/$id/claim', body: const <String, dynamic>{}));

  Future<EngineResult> regenerate(int id, int n, {String? hint}) {
    final h = hint?.trim() ?? '';
    return engineCall(() => _api.post('$base/exam-gen/$id/items/$n/regenerate', body: {if (h.isNotEmpty) 'hint': h.length > 200 ? h.substring(0, 200) : h}));
  }

  Future<EngineResult> removeItem(int id, int n) => engineCall(() => _api.delete('$base/exam-gen/$id/items/$n'));

  /// Fetches the job until [until] holds (default: it is done) or [timeout]; [onJob] sees every answer (the progress
  /// bar). The wait runs on the live stream's `job_updated{kind: exam_draft}` and polls only as the fallback. The last
  /// answer is returned (a failed fetch ends the wait with its error).
  Future<EngineResult> waitFor(int id,
      {bool Function(GenJob job)? until,
      void Function(GenJob job)? onJob,
      bool Function()? cancelled,
      Duration timeout = const Duration(hours: 3),
      Duration every = const Duration(milliseconds: 1500),
      Duration fallbackEvery = const Duration(seconds: 15)}) async {
    final stop = until ?? (j) => j.done;
    final end = DateTime.now().add(timeout);
    var r = await get(id);
    final watch = JobWatch(kind: 'exam_draft', id: '$id');
    try {
      while (r.ok) {
        final job = GenJob.fromJson(asMap(r.map));
        onJob?.call(job);
        if (stop(job) || job.failed || (until == null && job.done) || !DateTime.now().isBefore(end)) break;
        await watch.next(every, fallbackEvery: fallbackEvery);
        if (cancelled?.call() ?? false) break;          // the screen stopped caring (D-301): no poll left behind
        r = await get(id);
      }
    } finally {
      watch.dispose();
    }
    return r;
  }
}

/// Another question for item [n] of job [jobId] (the "Regenerate" of the review bar): asks the server, waits until
/// the item is written again, and returns it as a quick question (with its source). Null when the server refused or
/// could not write another one; the old question then stays.
Future<QuickQuestion?> regenerateGenItemWith(ExamGenV2Api api, int jobId, int n, {String? hint, Duration every = const Duration(milliseconds: 1500)}) async {
  final r = await api.regenerate(jobId, n, hint: hint);
  if (!r.ok) return null;
  bool settled(GenJob j) {
    final it = j.item(n);
    return it == null || asStr(it['state']) != 'regenerating';
  }

  final done = await api.waitFor(jobId, until: settled, every: every, timeout: const Duration(minutes: 3));
  if (!done.ok) return null;
  final item = GenJob.fromJson(asMap(done.map)).item(n);
  if (item == null || asStr(item['state']) == 'regenerating') return null;
  return quickOfV2(item);
}

/// The server's `removed` flag on an item the creator deleted; fire-and-forget by the caller (never throws).
Future<bool> removeGenItem(ExamGenV2Api api, int jobId, int n) async {
  try {
    return (await api.removeItem(jobId, n)).ok;
  } catch (_) {
    return false;
  }
}

/// Whether the wizard may be shown: false on an older server (see [genV2Unavailable]); every other answer — even an
/// error — keeps the wizard, which says what went wrong.
bool genUseWizard(EngineResult outline) => !genV2Unavailable(outline);


/// The newest job worth offering again from the list answer (`{items}`), or null (D-301).
GenJob? genResumableOf(Map<String, dynamic> listAnswer, {int? courseId}) {
  for (final j in asMapList(listAnswer['items'])) {
    final job = GenJob.fromJson(j);
    if (courseId != null && job.courseId != null && job.courseId != courseId) continue;
    if (job.resumable) return job;
  }
  return null;
}
