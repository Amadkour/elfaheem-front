// RAG service client (Phase 7, D-022; premium assistant D-012): questions answered from the app's own pages, the
// organization's / course's documents, with citations. /api/v1/rag/… over the one ApiClient; answers come from a
// worker, so `ask` queues and `waitFor` polls `GET /queries/{id}` until the answer is done — reporting the worker's
// `stage` (plan · retrieve · write · verify) on the way.
//
// Pure parts (unit-tested): [RagCitation], [RagAnswer], [answerRuns] (the answer text split at its `[n]` markers),
// [answerBlocks] (paragraphs, bullet and numbered lists, **bold** runs), [ragStageText], [ragStarterPrompts],
// [ragCodeText], [ragChatResultText], [ragOrgBlocked], [ragAnswerChanged], [ragNextPoll], [RagDelivery],
// [ragAnswerStalled] / [ragWaitLeft] (an answer the worker never finished: a calm error with Retry, M16).
//
// Delivery telemetry: when an answer finishes after the first response, [RagApi.waitFor] tells the server once,
// fire-and-forget, how it got it — `stream` (the fetch that found it done was woken by the live job_updated event),
// `poll` (by a timed poll), `mixed` (both played a part) — and the time to the final answer:
// `POST /queries/{id}/delivery {path, ms}` → 204 (never retried, never awaited; the server's `polling_share` alert
// reads it). An answer already done in the first response (cache, Q&A) sends nothing; an older server's 404 is
// ignored.
//
// Partial answers (Track E.8): while the local model writes, the query row carries `answer_partial` — the answer so
// far, shown only after the server's quote checks passed ([RagAnswer.provisional]). It is provisional: the server's
// checks still decide and the final answer (with its citations) replaces it; a retracted draft comes back as null.
// The worker's `job_updated{kind: rag_query, stage: write, partial_len}` fetches it at once on the live stream; without
// the stream [waitFor] polls every 1.5 s while a draft grows. An older server sends no field: nothing changes.
//
// Chat sessions (Track E.5): a conversation groups the asker's questions, `/api/v1/rag/conversations`:
//   GET    ?app=&org_id=&course_id=&limit=&before=   {items: [{id, title, scope{app, org_id, course_id}, created_at,
//                                                     last_at, turns}], retention_days}   newest first
//   POST   {app, org_id?, course_id?, title?}        the conversation   ·   PATCH /{id} {title}   ·   DELETE /{id}
//   GET    /{id}/messages?limit=&before=             {items: [query rows, oldest first], has_more}
//   POST   /ask {…, conversation_id}                 the answer row carries `conversation_id` (an older server
//                                                     ignores the field and has no conversations routes: a bare 404 /
//                                                     405 = [EngineResult.unavailable], the flat history stays)
// The client only ever sends `conversation_id`: the server bounds the memory it gives the model. Codes: 404
// `conversation_not_found`, 403 `not_owner`. Pure: [RagConversation], [conversationTitleFrom], [retentionText],
// [ragRelativeTime], [ragDeepLinkModule], [ragSessionsSupported].
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/offline/downloads_availability.dart' show kDownloadsAvailable, linkAvailableHere;

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t, trp;
import '../exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'rag_library.dart' show ragOrgStatusText;

/// The widest the conversation's message column gets on a wide window (about 75 characters a line).
const double kRagChatMaxWidth = 760;

/// The widest a RAG admin list (Q&A pairs, the learning tab) gets on a wide window.
const double kRagPageMaxWidth = 960;

/// The side padding that keeps a column at most [maxWidth] wide and centred in [width], never under [min]
/// (the list keeps the full width, so its scrollbar stays at the edge).
double ragGutter(double width, {double maxWidth = kRagChatMaxWidth, double min = 16}) => math.max(min, (width - maxWidth) / 2);

class RagCitation {
  RagCitation(this.n, this.documentId, this.title, this.section, this.pageFrom, this.pageTo, this.quote, [this.kind = '', this.deepLink]);
  final int n;
  final int documentId;
  final String title;
  final String section;
  final int? pageFrom;
  final int? pageTo;
  final String quote;

  /// `` (a document chunk) or `qa` (a curated Q&A pair, Track E.2: no document, the pair's question as the title).
  final String kind;

  /// A curated pair's deep link (a feature key or a route starting with `/`), opened through AppNavigator.
  final String? deepLink;

  factory RagCitation.fromJson(Map<String, dynamic> j) => RagCitation(asInt(j['n']), asInt(j['document_id']),
      '${j['title'] ?? ''}', '${j['section'] ?? ''}', _page(j['page_from']), _page(j['page_to']), '${j['quote'] ?? ''}',
      asStr(j['kind']), _blank(j['deep_link']));

  static int? _page(Object? v) => v == null ? null : asInt(v);
  static String? _blank(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v'.trim();

  bool get isQa => kind == 'qa';

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
      [this.helpful, this.followUps = const [], this.stage, this.generator = '', this.app = false, this.orgId, this.conversationId,
      this.partial, this.createdAt]);
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

  /// The chat session this question belongs to (Track E.5); null on an older server or a question asked before.
  final int? conversationId;

  /// The answer so far while the model writes it (Track E.8, `answer_partial`); null before anything may be shown,
  /// after a retraction, once done, and on an older server.
  final String? partial;

  /// When the question was asked (`created_at`, UTC); null on a row without it.
  final DateTime? createdAt;

  bool get done => state == 'done' || state == 'failed';

  /// A draft to show under the stage trail: still running and the server sent text. Never once done (the final
  /// answer replaces it, even if a stale field came along).
  bool get provisional => !done && (partial ?? '').trim().isNotEmpty;

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
      j['org_id'] == null ? null : asInt(j['org_id']),
      j['conversation_id'] == null ? null : asInt(j['conversation_id']),
      j['answer_partial'] is String ? j['answer_partial'] as String : null,
      ragParseUtc(j['created_at']));

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
      'qa' => 'rag_stage_qa'.tr,
      _ => t('أبحث في المستندات…', 'Searching the documents…'),
    };

/// The steps shown as a progress trail while an answer is prepared, in order.
const ragStages = ['plan', 'retrieve', 'write', 'verify'];

/// Whether [next] (a poll or a live event) changes what the pending card shows compared with [prev].
bool ragAnswerChanged(RagAnswer prev, RagAnswer next) =>
    prev.state != next.state || prev.stage != next.stage || (prev.provisional ? prev.partial : null) != (next.provisional ? next.partial : null);

/// How long an answer may stay unfinished before the chat stops waiting and offers Retry (the 1.7B local model
/// takes about a minute; a stopped worker never finishes, M16).
const Duration ragAnswerPatience = Duration(minutes: 3);

/// True when [a] is still unfinished [ragAnswerPatience] after it was asked: the worker is not coming back to it.
/// A row without `created_at` is never judged by age (the wait's own timeout decides).
bool ragAnswerStalled(RagAnswer a, DateTime nowUtc, {Duration patience = ragAnswerPatience}) =>
    !a.done && a.createdAt != null && nowUtc.difference(a.createdAt!) >= patience;

/// How much longer to wait for an unfinished [a] reopened from the history: the patience left since it was asked
/// (at least 15 s, so a question asked a moment ago on another device still gets its answer).
Duration ragWaitLeft(RagAnswer a, DateTime nowUtc, {Duration patience = ragAnswerPatience}) {
  final at = a.createdAt;
  if (at == null) return patience;
  final left = patience - nowUtc.difference(at);
  return left < const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
}

/// How long the latest conversation stays the one the assistant reopens by itself (N6): older than this, opening the
/// assistant starts on a new chat with the starter questions (the old one stays under Chats).
const Duration ragResumeWindow = Duration(hours: 6);

/// Whether opening the assistant should reopen [latest] by itself: its last activity at most [ragResumeWindow] ago.
/// A row without a date is reopened (an older server).
bool ragResumeConversation(RagConversation latest, DateTime nowUtc, {Duration window = ragResumeWindow}) {
  final at = latest.lastAt ?? latest.createdAt;
  return at == null || nowUtc.difference(at) < window;
}

/// Whether a reopened history ends on a failure (N6): its last question failed, or was never finished and is past
/// [ragAnswerPatience] (judged by [askedAt] — the conversation's last activity — when the row has no `created_at`).
/// The assistant then opens on a new chat with the starter questions instead of on the failure; the history stays
/// reachable (Chats, or "Earlier questions" on an older server). A question still within its patience is not a
/// failure: it is followed as before.
bool ragOpensOnFailure(List<RagAnswer> items, DateTime nowUtc, {DateTime? askedAt, Duration patience = ragAnswerPatience}) {
  if (items.isEmpty) return false;
  final last = items.last;
  if (last.state == 'failed') return true;
  if (last.done) return false;
  final at = last.createdAt ?? askedAt;
  return at != null && nowUtc.difference(at) >= patience;
}

/// The next poll interval of [RagApi.waitFor]: 1 s growing by 0.5 s up to 4 s, but every 1.5 s at most while a draft
/// grows ([writing]: the asker is reading it).
Duration ragNextPoll(Duration every, {bool writing = false}) {
  const draft = Duration(milliseconds: 1500);
  if (writing) return every < draft ? every : draft;
  return every < const Duration(seconds: 4) ? every + const Duration(milliseconds: 500) : every;
}

/// How one answer reached the app, from the wake-ups of [RagApi.waitFor]: each fetch after the first is woken either
/// by the job's live event or by the timer (with the stream down, or connected but silent). Pure; the decision:
///   last fetch woken by the event → `stream`, or `mixed` when a poll ran while the stream was down;
///   last fetch woken by the timer → `poll` (the stream did not deliver it), or `mixed` when an event woke an
///   earlier fetch;
///   no wake-up at all (done in the first response or the first fetch) → null: nothing to report.
class RagDelivery {
  int _events = 0;
  int _downPolls = 0;
  bool? _lastByEvent;

  /// One fetch is about to run: woken [byEvent] (else by the timer), with the stream [connected] at that moment.
  void wake({required bool byEvent, required bool connected}) {
    _lastByEvent = byEvent;
    if (byEvent) {
      _events++;
    } else if (!connected) {
      _downPolls++;
    }
  }

  /// `stream` · `poll` · `mixed`, or null before any wake-up.
  String? get path {
    final last = _lastByEvent;
    if (last == null) return null;
    if (last) return _downPolls == 0 ? 'stream' : 'mixed';
    return _events == 0 ? 'poll' : 'mixed';
  }

  /// The report's body after [elapsed] (the time to the final answer), or null when there is nothing to report.
  Map<String, dynamic>? body(Duration elapsed) {
    final p = path;
    return p == null ? null : {'path': p, 'ms': elapsed.inMilliseconds < 0 ? 0 : elapsed.inMilliseconds};
  }
}

// ── chat sessions (Track E.5) ─────────────────────────────────────────────────────────────────────────────────────

/// A translation.json text in [lang] (not the UI language: the caller chooses), the key itself when not loaded.
String ragTr(String key, String lang) {
  final e = translation[key];
  return e is Map ? '${e[lang] ?? e['en'] ?? key}' : key;
}

/// One chat session of the asker, as `GET /conversations` lists it.
class RagConversation {
  const RagConversation({required this.id, required this.title, this.app = false, this.orgId, this.courseId, this.createdAt, this.lastAt, this.turns = 0});
  final int id;
  final String title;
  final bool app;
  final int? orgId;
  final int? courseId;
  final DateTime? createdAt;

  /// The last question's time (the list is ordered by it, newest first).
  final DateTime? lastAt;
  final int turns;

  factory RagConversation.fromJson(Map<String, dynamic> j) {
    final scope = asMap(j['scope']);
    return RagConversation(
      id: asInt(j['id']),
      title: asStr(j['title']).trim(),
      app: (scope['app'] ?? j['app']) == true,
      orgId: _optInt(scope['org_id'] ?? j['org_id']),
      courseId: _optInt(scope['course_id'] ?? j['course_id']),
      createdAt: ragParseUtc(j['created_at']),
      lastAt: ragParseUtc(j['last_at']) ?? ragParseUtc(j['created_at']),
      turns: asInt(j['turns']),
    );
  }

  static int? _optInt(Object? v) => v == null ? null : asInt(v);

  /// The title to show: the server's, else "New chat".
  String get displayTitle => title.isEmpty ? 'rag_new_chat'.tr : title;

  RagConversation copyWith({String? title, DateTime? lastAt, int? turns}) =>
      RagConversation(id: id, title: title ?? this.title, app: app, orgId: orgId, courseId: courseId, createdAt: createdAt, lastAt: lastAt ?? this.lastAt, turns: turns ?? this.turns);
}

/// The server's ISO time (naive UTC or with a `Z`) → a UTC instant; null when absent or unreadable.
DateTime? ragParseUtc(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
  return d?.toUtc();
}

/// The title a new conversation gets from its first question: one line, whitespace collapsed, at most [max]
/// characters (cut at a word when one is near, with an ellipsis); "New chat" (ar / en) for an empty question.
String conversationTitleFrom(String firstQuestion, {int max = 40, String? lang}) {
  final q = firstQuestion.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (q.isEmpty) return ragTr('rag_new_chat', lang ?? AppConfig.lang);
  if (q.length <= max) return q;
  var cut = q.substring(0, max - 1);
  final space = cut.lastIndexOf(' ');
  if (space >= max ~/ 2) cut = cut.substring(0, space);
  return '${cut.trimRight()}…';
}

/// "Chats are deleted automatically after N days" in [lang]; empty when the server keeps them (null / 0).
String retentionText(int? days, String lang) {
  if (days == null || days <= 0) return '';
  return ragTr('rag_retention', lang).replaceAll('{n}', '$days');
}

/// "Just now" · "5 min ago" · "3 h ago" · "Yesterday" · "4 days ago" · the date (older than a week), in the UI
/// language. [now] is for tests.
String ragRelativeTime(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final d = (now ?? DateTime.now().toUtc()).difference(at.toUtc());
  if (d.inMinutes < 1) return 'rag_time_now'.tr;
  if (d.inHours < 1) return trp('rag_time_min', {'n': d.inMinutes});
  if (d.inHours < 24) return trp('rag_time_hours', {'n': d.inHours});
  if (d.inDays < 2) return 'rag_time_yesterday'.tr;
  if (d.inDays < 7) return trp('rag_time_days', {'n': d.inDays});
  return AppTime.date(at.toUtc());
}

/// A curated pair's deep link as [AppNavigator.openModule] takes it: `/downloads` → `downloads`, a feature key
/// unchanged; null when there is nothing to open — or when it is the Downloads page and this is the web (no such
/// page there, so no "Open" button).
String? ragDeepLinkModule(String? link, {bool downloadsAvailable = kDownloadsAvailable}) {
  final s = (link ?? '').trim();
  if (s.isEmpty) return null;
  final m = s.startsWith('/') ? s.substring(1) : s;
  if (!linkAvailableHere(m, downloadsAvailable: downloadsAvailable)) return null;
  return m.isEmpty ? null : m;
}

/// Whether the server has the conversations routes: the list call succeeded, or failed with a coded error (the
/// routes exist). A bare 404 / 405 ([EngineResult.unavailable]) is an older server: the flat history stays.
bool ragSessionsSupported(EngineResult r) => r.ok || !r.unavailable;

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
      // chat sessions (Track E.5)
      'conversation_not_found' => 'rag_chat_not_found'.tr,
      'not_owner' => 'rag_chat_not_owner'.tr,
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
  /// (the app assistant opened inside an organization). Never with a course. [conversationId] (Track E.5) puts the
  /// question in that chat session — the only memory the client sends; an older server ignores it.
  Future<EngineResult> ask(String question, {int? orgId, int? courseId, bool app = false, int? conversationId}) => engineCall(() =>
      _api.post('$base/ask', body: {'question': question, 'org_id': ?orgId, 'course_id': ?courseId, if (app) 'app': true, 'conversation_id': ?conversationId}));

  // ── chat sessions (Track E.5) ──

  /// The asker's conversations of one scope, newest first; [before] (a conversation id) pages further back.
  Future<EngineResult> conversations({int? orgId, int? courseId, bool app = false, int limit = 30, int? before}) =>
      engineCall(() => _api.get('$base/conversations', queryParams: {'app': app, 'org_id': ?orgId, 'course_id': ?courseId, 'limit': limit, 'before': ?before}));

  Future<EngineResult> createConversation({int? orgId, int? courseId, bool app = false, String? title}) => engineCall(() =>
      _api.post('$base/conversations', body: {'app': app, 'org_id': ?orgId, 'course_id': ?courseId, if (title != null && title.trim().isNotEmpty) 'title': title.trim()}));

  Future<EngineResult> renameConversation(int id, String title) => engineCall(() => _api.patch('$base/conversations/$id', body: {'title': title.trim()}));

  Future<EngineResult> deleteConversation(int id) => engineCall(() => _api.delete('$base/conversations/$id'));

  /// A conversation's questions with their answers, oldest first; [before] (a query id) pages further back.
  Future<EngineResult> messages(int id, {int limit = 30, int? before}) =>
      engineCall(() => _api.get('$base/conversations/$id/messages', queryParams: {'limit': limit, 'before': ?before}));

  static List<RagConversation> conversationItems(EngineResult r) => asMapList(asMap(r.map)['items']).map(RagConversation.fromJson).toList();

  /// `retention_days` of the conversations list (null when the server did not say).
  static int? retentionDays(EngineResult r) => r.map['retention_days'] == null ? null : asInt(r.map['retention_days']);

  /// `has_more` of a messages page.
  static bool hasMore(EngineResult r) => r.map['has_more'] == true;

  Future<EngineResult> query(int id) => engineCall(() => _api.get('$base/queries/$id'));

  /// How a finished answer reached the app ([RagDelivery.body]): one best-effort report, never retried; the result is
  /// ignored (an older server answers 404).
  Future<void> reportDelivery(int id, Map<String, dynamic> body) async {
    await engineCall(() => _api.post('$base/queries/$id/delivery', body: body));
  }

  /// The asker's rating of a finished answer (Phase 8).
  Future<EngineResult> rate(int id, {required bool helpful, String? comment}) =>
      engineCall(() => _api.post('$base/queries/$id/feedback', body: {'helpful': helpful, 'comment': ?comment}));

  Future<EngineResult> history({int? orgId, int? courseId, bool app = false, int limit = 20}) => engineCall(() =>
      _api.get('$base/queries', queryParams: {'org_id': ?orgId, 'course_id': ?courseId, if (app) 'app': true, 'limit': limit}));

  /// Starter questions the asker's library can answer (same context rules as [ask]), in the UI language.
  Future<EngineResult> starters({int? orgId, int? courseId, bool app = false}) => engineCall(() => _api.get('$base/starters',
      queryParams: {'org_id': ?orgId, 'course_id': ?courseId, if (app) 'app': true, 'lang': AppConfig.lang == 'en' ? 'en' : 'ar'}));

  /// The poll while the live stream is connected: `job_updated{kind: rag_query, id}` fetches at once then.
  static const waitLive = Duration(seconds: 8);

  /// Polls until the worker answered (or [timeout]), every second at first and then up to every 4 s (1.5 s while a
  /// draft grows, [ragNextPoll]) — every [waitLive] while the live stream is connected, where the job's event (`stage`
  /// shown at once, the draft fetched) comes early; the last state otherwise (the screen keeps it as "still working"
  /// and asks again on refresh). [onUpdate] gets every poll (the stage and the draft change on the way). An answer
  /// that finishes after the first fetch is reported once ([RagDelivery], [reportDelivery]), without waiting for it.
  Future<EngineResult> waitFor(int id, {Duration timeout = ragAnswerPatience, void Function(RagAnswer)? onUpdate}) async {
    final end = DateTime.now().add(timeout);
    final clock = Stopwatch()..start();
    final delivery = RagDelivery();
    var every = const Duration(seconds: 1);
    var r = await query(id);
    if (r.ok) onUpdate?.call(RagAnswer.fromJson(r.map));
    final watch = JobWatch(kind: 'rag_query', id: '$id');
    try {
      while (r.ok && !RagAnswer.fromJson(r.map).done && DateTime.now().isBefore(end)) {
        final event = await watch.next(every, fallbackEvery: waitLive);
        delivery.wake(byEvent: event != null, connected: watch.connected);
        final stage = event?.stage;
        if (stage != null && stage.isNotEmpty) onUpdate?.call(RagAnswer.fromJson({...r.map, 'stage': stage}));
        every = ragNextPoll(every, writing: RagAnswer.fromJson(r.map).provisional);
        r = await query(id);
        if (r.ok) onUpdate?.call(RagAnswer.fromJson(r.map));
      }
    } finally {
      watch.dispose();
    }
    final report = r.ok && RagAnswer.fromJson(r.map).done ? delivery.body(clock.elapsed) : null;
    if (report != null) unawaited(reportDelivery(id, report));
    return r;
  }

  static List<RagAnswer> items(EngineResult r) => asMapList(asMap(r.map)['items']).map(RagAnswer.fromJson).toList();
}
