// "Generate this exam for me from the course documents": the RAG service writes draft questions from the course's
// documents (grouped by topic, a few questions per group — rag_service/examgen.py), and they land in the quick exam
// builder as ordinary editable questions. The teacher reviews and edits them before publishing.
//
//   POST /api/v1/rag/exam-drafts {course_id, org_id?, types: mcq|essay|mixed, count}  → 202 the draft (queued)
//        409 no_course_documents {busy}: no ready course document yet (busy = still being read)
//   GET  /api/v1/rag/exam-drafts/{id}  → {state, questions[{type, prompt, options[{id, text}], correct, answer,
//        key_points[], points, source{title, section, page_from}}], generator}
//
// Pure (unit-tested): GenTypes, ExamGenDraft, quickQuestionsOf, ragFormatAdvice, examGenCodeText, ExamGenStep.
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import '../rag/rag_chat.dart' show RagApi;
import '../rag/rag_library.dart' show RagDocument, ragLibraryCodeText;
import 'exam_authoring.dart' show QOption;
import 'exam_engine_api.dart' show EngineResult, engineCall;
import 'exam_quick.dart';

/// The only two questions asked: which kind of questions, and how many.
enum GenTypes { mixed, mcq, essay }

const genDefaultCount = 10;
const genMaxCount = 40;

String genTypesLabel(GenTypes g) => switch (g) {
      GenTypes.mixed => t('مختلط', 'Mixed'),
      GenTypes.mcq => t('اختيار من متعدد', 'Multiple choice'),
      GenTypes.essay => t('مقالي', 'Essay'),
    };

class ExamGenDraft {
  const ExamGenDraft({required this.id, required this.state, this.questions = const [], this.generator, this.error});
  final int id;
  final String state;
  final List<Map<String, dynamic>> questions;
  final String? generator;
  final String? error;

  bool get done => state == 'done' || state == 'failed';

  factory ExamGenDraft.fromJson(Map<String, dynamic> j) => ExamGenDraft(
      id: asInt(j['id']),
      state: asStr(j['state'], 'queued'),
      questions: asMapList(j['questions']),
      generator: j['generator']?.toString(),
      error: j['error']?.toString());
}

/// The draft's questions as quick-builder questions: multiple choice keeps its choices and right answer; an essay is
/// auto-graded against its key points (or its model answer when it has none).
List<QuickQuestion> quickQuestionsOf(List<Map<String, dynamic>> questions) {
  final out = <QuickQuestion>[];
  for (final g in questions) {
    final prompt = asStr(g['prompt']).trim();
    if (prompt.isEmpty) continue;
    if (g['type'] == 'mcq') {
      final opts = [for (final o in asMapList(g['options'])) if (asStr(o['text']).trim().isNotEmpty) QOption(asStr(o['id']), asStr(o['text']))];
      if (opts.length < 2) continue;
      final q = QuickQuestion.mcq()
        ..prompt = prompt
        ..options = opts
        ..correct = opts.any((o) => o.id == g['correct']) ? asStr(g['correct']) : null;
      if (g['points'] is num) q.points = (g['points'] as num).toDouble();
      out.add(q);
    } else if (g['type'] == 'essay') {
      final points = [for (final p in (g['key_points'] is List ? g['key_points'] as List : const [])) '$p'.trim()]..removeWhere((p) => p.isEmpty);
      final answer = asStr(g['answer']).trim();
      final q = QuickQuestion.essay()..prompt = prompt;
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
      if (g['points'] is num) q.points = (g['points'] as num).toDouble();
      out.add(q);
    }
  }
  return out;
}

/// One line on which file to give, chosen for the picked file (or the general advice when none is picked yet).
String ragFormatAdvice(String? fileName) {
  final ext = fileName == null || !fileName.contains('.') ? '' : fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'docx' || 'txt' || 'md' || 'markdown' || 'html' || 'htm' =>
      t('ممتاز: النص يُقرأ كما هو، فتخرج الأسئلة أدق.', 'Great: the text is read exactly as written, so the questions come out more accurate.'),
    'pdf' => t('جيد إن كان PDF نصياً (يمكن تحديد كلماته)؛ الممسوح ضوئياً يُقرأ بالتعرف الضوئي وقد يفقد كلمات.',
        'Good if it is a text PDF (you can select its words); a scanned one goes through OCR and may lose words.'),
    'png' || 'jpg' || 'jpeg' => t('الصور تُقرأ بالتعرف الضوئي وقد تفقد كلمات — ملف Word أو PDF نصي أفضل.',
        'Photos go through OCR and may lose words — a Word file or a text PDF works better.'),
    _ => t('الأفضل ملف Word أو PDF نصي: يُقرأ النص بدقة، بخلاف الصور والملفات الممسوحة والشرائح.',
        'Best: a Word file or a text PDF — the text is read exactly, unlike photos, scans or slides.'),
  };
}

/// A scanned PDF was read by OCR: say so once it is processed (the questions may be weaker).
String? ragOcrWarning(RagDocument d) => d.ocrPages > 0
    ? t('قُرئت ${d.ocrPages} صفحة بالتعرف الضوئي — قد تكون بعض الأسئلة أضعف. ملف Word أو PDF نصي يعطي نتيجة أدق.',
        '${d.ocrPages} pages were read by OCR — some questions may be weaker. A Word file or a text PDF gives better results.')
    : null;

String examGenCodeText(String? code, String fallback) => switch (code) {
      'not_course_staff' => t('إنشاء الأسئلة لمعلمي المقرر فقط', 'Only the course\'s teachers can generate questions'),
      'no_course_documents' => t('ارفع مستند المقرر أولاً', 'Upload the course document first'),
      'bad_question_count' => t('عدد الأسئلة من 1 إلى $genMaxCount', 'Between 1 and $genMaxCount questions'),
      'draft_not_found' => t('المسودة غير موجودة', 'The draft was not found'),
      'no_questions' => t('لم نجد في المستند نصاً كافياً لكتابة أسئلة — جرّب ملفاً آخر', 'The document did not have enough text to write questions — try another file'),
      'too_many_requests' => t('طلبات كثيرة في وقت قصير — انتظر دقيقة', 'Too many requests — wait a minute'),
      _ => ragLibraryCodeText(code, fallback),
    };

/// Where the sheet is: reading the course's documents · none yet (ask for one) · being processed · ready (the two
/// questions) · writing the questions.
enum ExamGenStep { loading, needDocument, processing, ready, generating }

/// The step for the course's documents as the library lists them (course documents only; archived ones are left out).
ExamGenStep examGenStepOf(List<RagDocument> docs, int courseId) {
  final mine = docs.where((d) => d.scope == 'course' && d.courseId == courseId && !d.archived).toList();
  if (mine.any((d) => d.status == 'ready')) return ExamGenStep.ready;
  if (mine.any((d) => d.busy)) return ExamGenStep.processing;
  return ExamGenStep.needDocument;
}

class ExamGenApi {
  ExamGenApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = RagApi.base;

  Future<EngineResult> create({required int courseId, int? orgId, required GenTypes types, required int count}) => engineCall(() => _api.post(
      '$base/exam-drafts',
      body: {'course_id': courseId, 'org_id': ?orgId, 'types': types.name, 'count': count}));

  Future<EngineResult> get(int id) => engineCall(() => _api.get('$base/exam-drafts/$id'));

  /// Polls until the draft is written (or [timeout]): every 1.5 s, then slower.
  Future<EngineResult> waitFor(int id, {Duration timeout = const Duration(minutes: 4)}) async {
    final end = DateTime.now().add(timeout);
    var every = const Duration(milliseconds: 1500);
    var r = await get(id);
    while (r.ok && !ExamGenDraft.fromJson(asMap(r.map)).done && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(every);
      if (every < const Duration(seconds: 5)) every += const Duration(milliseconds: 500);
      r = await get(id);
    }
    return r;
  }
}
