// RAG service client (Phase 7, D-022; premium assistant D-012): questions answered from the app's own pages, the
// organization's / course's documents, with citations. /api/v1/rag/… over the one ApiClient; answers come from a
// worker, so `ask` queues and `waitFor` polls `GET /queries/{id}` until the answer is done — reporting the worker's
// `stage` (plan · retrieve · write · verify) on the way.
//
// Pure parts (unit-tested): [RagCitation], [RagAnswer], [answerRuns] (the answer text split at its `[n]` markers),
// [answerBlocks] (paragraphs, bullet and numbered lists, **bold** runs), [ragStageText], [ragStarterPrompts],
// [ragCodeText], [ragChatResultText], [ragOrgBlocked].
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import '../exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'rag_library.dart' show ragOrgStatusText;

class RagCitation {
  RagCitation(this.n, this.documentId, this.title, this.section, this.pageFrom, this.pageTo, this.quote);
  final int n;
  final int documentId;
  final String title;
  final String section;
  final int? pageFrom;
  final int? pageTo;
  final String quote;

  factory RagCitation.fromJson(Map<String, dynamic> j) => RagCitation(asInt(j['n']), asInt(j['document_id']),
      '${j['title'] ?? ''}', '${j['section'] ?? ''}', _page(j['page_from']), _page(j['page_to']), '${j['quote'] ?? ''}');

  static int? _page(Object? v) => v == null ? null : asInt(v);

  /// "Student regulation › Article 5 · p. 3" (pages only when the document has them).
  String get label {
    final parts = [title, if (section.isNotEmpty) section].join(' › ');
    if (pageFrom == null) return parts;
    final pages = pageTo != null && pageTo != pageFrom ? '$pageFrom–$pageTo' : '$pageFrom';
    return '$parts · ${t('ص', 'p.')} $pages';
  }
}

class RagAnswer {
  RagAnswer(this.id, this.state, this.question, this.found, this.answer, this.citations, this.error,
      [this.helpful, this.followUps = const [], this.stage, this.generator = '', this.app = false, this.orgId]);
  final int id;
  final String state;
  final String question;
  final bool? found;
  final String answer;
  final List<RagCitation> citations;
  final String? error;

  /// the asker's rating: true / false, null = not rated
  final bool? helpful;

  /// Suggested next questions (the writer's, from the same sources).
  final List<String> followUps;

  /// The worker's current step while running: plan · retrieve · write · verify.
  final String? stage;

  /// `llm:<model>` · `llm:small_talk` · `extractive` · `extractive (model fallback)` · `none`.
  final String generator;
  final bool app;
  final int? orgId;

  bool get done => state == 'done' || state == 'failed';

  /// Written by the model (as opposed to quoted straight from the documents).
  bool get byModel => generator.startsWith('llm');

  /// A greeting / "what can you do?" answer: no sources, no rating.
  bool get smallTalk => generator == 'llm:small_talk';

  factory RagAnswer.fromJson(Map<String, dynamic> j) => RagAnswer(
      asInt(j['id']),
      '${j['state'] ?? 'queued'}',
      '${j['question'] ?? ''}',
      j['found'] is bool ? j['found'] as bool : null,
      '${j['answer'] ?? ''}',
      asMapList(j['citations']).map(RagCitation.fromJson).toList(),
      j['error']?.toString(),
      j['helpful'] is bool ? j['helpful'] as bool : null,
      [for (final f in (j['follow_ups'] is List ? j['follow_ups'] as List : const [])) '$f'.trim()]..removeWhere((f) => f.isEmpty),
      j['stage']?.toString(),
      asStr(j['generator']),
      j['app'] == true,
      j['org_id'] == null ? null : asInt(j['org_id']));

  RagCitation? citation(int n) {
    for (final c in citations) {
      if (c.n == n) return c;
    }
    return null;
  }
}

/// One piece of an answer: plain text, or a citation marker `[n]`.
class AnswerRun {
  const AnswerRun(this.text, [this.cite, this.bold = false]);
  final String text;
  final int? cite;
  final bool bold;
}

final _marker = RegExp(r'\[(\d{1,2})\]');
final _boldOrMarker = RegExp(r'\*\*(.+?)\*\*|\[(\d{1,2})\]');

List<AnswerRun> answerRuns(String answer) {
  final out = <AnswerRun>[];
  var at = 0;
  for (final m in _marker.allMatches(answer)) {
    if (m.start > at) out.add(AnswerRun(answer.substring(at, m.start)));
    out.add(AnswerRun(m.group(0)!, int.parse(m.group(1)!)));
    at = m.end;
  }
  if (at < answer.length) out.add(AnswerRun(answer.substring(at)));
  return out;
}

/// Like [answerRuns], with `**bold**` runs marked (the model's emphasis); the stars never reach the screen.
List<AnswerRun> styledRuns(String text) {
  final out = <AnswerRun>[];
  var at = 0;
  for (final m in _boldOrMarker.allMatches(text)) {
    if (m.start > at) out.add(AnswerRun(text.substring(at, m.start)));
    if (m.group(1) != null) {
      out.add(AnswerRun(m.group(1)!, null, true));
    } else {
      out.add(AnswerRun(m.group(0)!, int.parse(m.group(2)!)));
    }
    at = m.end;
  }
  if (at < text.length) out.add(AnswerRun(text.substring(at)));
  return out;
}

enum AnswerBlockKind { paragraph, bullet, numbered }

/// A paragraph, a bullet item or a numbered item of an answer, with its runs.
class AnswerBlock {
  const AnswerBlock(this.kind, this.runs, [this.number]);
  final AnswerBlockKind kind;
  final List<AnswerRun> runs;
  final int? number;

  String get text => runs.map((r) => r.text).join();
}

final _bullet = RegExp(r'^\s*[-•*]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$');

/// The answer's lines as blocks: "- item" and "• item" are bullets, "1. step" numbered items, blank lines separate
/// paragraphs, consecutive plain lines join one paragraph. Headings and tables are never produced by the server.
List<AnswerBlock> answerBlocks(String answer) {
  final out = <AnswerBlock>[];
  final para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    out.add(AnswerBlock(AnswerBlockKind.paragraph, styledRuns(para.join(' '))));
    para.clear();
  }

  for (final raw in answer.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null) {
      flush();
      out.add(AnswerBlock(AnswerBlockKind.bullet, styledRuns(b.group(1)!)));
      continue;
    }
    final n = _numbered.firstMatch(line);
    if (n != null) {
      flush();
      out.add(AnswerBlock(AnswerBlockKind.numbered, styledRuns(n.group(2)!), int.parse(n.group(1)!)));
      continue;
    }
    para.add(line.trim());
  }
  flush();
  return out;
}

/// What the assistant is doing, for the pending card.
String ragStageText(String? stage) => switch (stage) {
      'plan' => t('أفهم سؤالك…', 'Understanding your question…'),
      'retrieve' => t('أبحث في المستندات…', 'Searching the documents…'),
      'write' => t('أكتب الإجابة…', 'Writing the answer…'),
      'verify' => t('أراجع الإجابة مع المصادر…', 'Checking the answer against the sources…'),
      _ => t('أبحث في المستندات…', 'Searching the documents…'),
    };

/// The steps shown as a progress trail while an answer is prepared, in order.
const ragStages = ['plan', 'retrieve', 'write', 'verify'];

/// Where the chat is: the app assistant alone (`app`), the app assistant inside an organization (`org`), or an
/// organization / course documents chat (`docs`).
enum RagContext { app, org, docs }

RagContext ragContextOf({required bool app, int? orgId}) => app ? (orgId == null ? RagContext.app : RagContext.org) : RagContext.docs;

/// Questions to tap when the chat is empty, when the server's [RagApi.starters] (questions built from the headings
/// the asker may read, D-012) gave none: the assistant's scope, in the UI language.
List<String> ragStarterPrompts(RagContext ctx) => switch (ctx) {
      RagContext.app => [
          t('كيف أشترك في كورس؟', 'How do I subscribe to a course?'),
          t('ما سياسة الاسترداد؟', 'What is the refund policy?'),
          t('كيف أغيّر الجهاز المرتبط بحسابي؟', 'How do I change the device linked to my account?'),
          t('كيف أحمّل الدروس للمشاهدة بدون إنترنت؟', 'How do I download lessons for offline viewing?'),
        ],
      RagContext.org => [
          t('ما قواعد الحضور والغياب في مؤسستي؟', 'What are my organization\'s attendance rules?'),
          t('ما لوائح الامتحانات؟', 'What are the exam regulations?'),
          t('كيف أنضم إلى مجموعة أو قسم؟', 'How do I join a group or department?'),
          t('ما سياسة الاسترداد في التطبيق؟', 'What is the app\'s refund policy?'),
        ],
      RagContext.docs => [
          t('لخّص أهم القواعد في اللائحة', 'Summarize the key rules of the regulation'),
          t('ما شروط دخول الامتحان النهائي؟', 'What are the conditions to sit the final exam?'),
          t('ما مواعيد التسجيل؟', 'What are the registration dates?'),
        ],
    };

/// The server's starter questions (`GET /starters` → `questions`), trimmed and de-duplicated; empty when the
/// library has nothing to suggest (the caller falls back to [ragStarterPrompts]).
List<String> ragStartersFrom(Map<String, dynamic> j, {int max = 6}) {
  final out = <String>[];
  for (final q in (j['questions'] is List ? j['questions'] as List : const [])) {
    final s = '$q'.trim();
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
    if (out.length == max) break;
  }
  return out;
}

String ragCodeText(String? code, String fallback) => switch (code) {
      'too_many_requests' => t('أسئلة كثيرة في وقت قصير — انتظر دقيقة', 'Too many questions — wait a minute'),
      'rag_busy' => t('المساعد مشغول الآن — أعد المحاولة بعد قليل', 'The assistant is busy — try again shortly'),
      'question_too_long' => t('السؤال طويل جداً', 'The question is too long'),
      'question_required' => t('اكتب سؤالاً', 'Type a question'),
      'not_a_member' => t('لست عضواً في هذه المؤسسة', 'You are not a member of this organization'),
      'not_in_course' => t('لست مسجلاً في هذا المقرر', 'You are not in this course'),
      'authz_unavailable' => t('تعذر التحقق من الصلاحيات — حاول بعد قليل', 'Could not check your access — try again shortly'),
      'app_context_only' => t('مساعد التطبيق لا يتبع مقرراً', 'The app assistant does not follow a course'),
      // The organization's status (Phase 10, the core's codes): the assistant follows the organization.
      'orgs_disabled' => t('المساعد غير متاح: خدمة المؤسسات متوقفة حالياً على المنصة',
          'The assistant is unavailable: organizations are switched off on this platform right now'),
      'org_not_approved' => ragOrgStatusText(''),
      'org_inactive' => t('المساعد غير متاح: المؤسسة غير مفعّلة حالياً', 'The assistant is unavailable: this organization is deactivated'),
      _ => fallback,
    };

/// The organization codes that close the assistant (403 orgs_disabled · 423 org_not_approved · 403 org_inactive).
bool ragOrgBlocked(String? code) => code == 'orgs_disabled' || code == 'org_not_approved' || code == 'org_inactive';

/// The text of a failed chat call: [ragCodeText], plus the organization's `status` a 423 org_not_approved carries
/// (suspended · pending · rejected).
String ragChatResultText(EngineResult r) =>
    r.code == 'org_not_approved' ? ragOrgStatusText(asStr(r.detail['status'])) : ragCodeText(r.code, r.message);

class RagApi {
  RagApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/rag';

  /// [app]: the app assistant (the platform's own documents); with [orgId] too, the organization's library as well
  /// (the app assistant opened inside an organization). Never with a course.
  Future<EngineResult> ask(String question, {int? orgId, int? courseId, bool app = false}) => engineCall(
      () => _api.post('$base/ask', body: {'question': question, 'org_id': ?orgId, 'course_id': ?courseId, if (app) 'app': true}));

  Future<EngineResult> query(int id) => engineCall(() => _api.get('$base/queries/$id'));

  /// The asker's rating of a finished answer (Phase 8).
  Future<EngineResult> rate(int id, {required bool helpful, String? comment}) =>
      engineCall(() => _api.post('$base/queries/$id/feedback', body: {'helpful': helpful, 'comment': ?comment}));

  Future<EngineResult> history({int? orgId, int? courseId, bool app = false, int limit = 20}) => engineCall(() =>
      _api.get('$base/queries', queryParams: {'org_id': ?orgId, 'course_id': ?courseId, if (app) 'app': true, 'limit': limit}));

  /// Starter questions the asker's library can answer (same context rules as [ask]), in the UI language.
  Future<EngineResult> starters({int? orgId, int? courseId, bool app = false}) => engineCall(() => _api.get('$base/starters',
      queryParams: {'org_id': ?orgId, 'course_id': ?courseId, if (app) 'app': true, 'lang': AppConfig.lang == 'en' ? 'en' : 'ar'}));

  /// Polls until the worker answered (or [timeout]), every second at first and then up to every 5 s; the last state
  /// otherwise (the screen keeps it as "still working" and asks again on refresh). [onUpdate] gets every poll
  /// (the stage changes on the way).
  Future<EngineResult> waitFor(int id, {Duration timeout = const Duration(minutes: 3), void Function(RagAnswer)? onUpdate}) async {
    final end = DateTime.now().add(timeout);
    var every = const Duration(seconds: 1);
    var r = await query(id);
    if (r.ok) onUpdate?.call(RagAnswer.fromJson(r.map));
    while (r.ok && !RagAnswer.fromJson(r.map).done && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(every);
      if (every < const Duration(seconds: 4)) every += const Duration(milliseconds: 500);
      r = await query(id);
      if (r.ok) onUpdate?.call(RagAnswer.fromJson(r.map));
    }
    return r;
  }

  static List<RagAnswer> items(EngineResult r) => asMapList(asMap(r.map)['items']).map(RagAnswer.fromJson).toList();
}
