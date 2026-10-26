// RAG service client (Phase 7, D-022): questions answered from the organization's / course's documents, with
// citations. /api/v1/rag/… over the one ApiClient; answers come from a worker, so `ask` queues and `waitFor` polls
// `GET /queries/{id}` until the answer is done.
//
// Pure parts (unit-tested): [RagCitation], [RagAnswer], [answerRuns] (the answer text split at its `[n]` markers),
// [ragCodeText], [ragChatResultText], [ragOrgBlocked].
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
  RagAnswer(this.id, this.state, this.question, this.found, this.answer, this.citations, this.error, [this.helpful]);
  final int id;
  final String state;
  final String question;
  final bool? found;
  final String answer;
  final List<RagCitation> citations;
  final String? error;

  /// the asker's rating: true / false, null = not rated
  final bool? helpful;

  bool get done => state == 'done' || state == 'failed';

  factory RagAnswer.fromJson(Map<String, dynamic> j) => RagAnswer(asInt(j['id']), '${j['state'] ?? 'queued'}', '${j['question'] ?? ''}',
      j['found'] is bool ? j['found'] as bool : null, '${j['answer'] ?? ''}',
      asMapList(j['citations']).map(RagCitation.fromJson).toList(), j['error']?.toString(), j['helpful'] is bool ? j['helpful'] as bool : null);

  RagCitation? citation(int n) {
    for (final c in citations) {
      if (c.n == n) return c;
    }
    return null;
  }
}

/// One piece of an answer: plain text, or a citation marker `[n]`.
class AnswerRun {
  const AnswerRun(this.text, [this.cite]);
  final String text;
  final int? cite;
}

final _marker = RegExp(r'\[(\d{1,2})\]');

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

String ragCodeText(String? code, String fallback) => switch (code) {
      'too_many_requests' => t('أسئلة كثيرة في وقت قصير — انتظر دقيقة', 'Too many questions — wait a minute'),
      'rag_busy' => t('المساعد مشغول الآن — أعد المحاولة بعد قليل', 'The assistant is busy — try again shortly'),
      'question_too_long' => t('السؤال طويل جداً', 'The question is too long'),
      'question_required' => t('اكتب سؤالاً', 'Type a question'),
      'not_a_member' => t('لست عضواً في هذه المؤسسة', 'You are not a member of this organization'),
      'not_in_course' => t('لست مسجلاً في هذا المقرر', 'You are not in this course'),
      'authz_unavailable' => t('تعذر التحقق من الصلاحيات — حاول بعد قليل', 'Could not check your access — try again shortly'),
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

  Future<EngineResult> ask(String question, {int? orgId, int? courseId}) =>
      engineCall(() => _api.post('$base/ask', body: {'question': question, 'org_id': ?orgId, 'course_id': ?courseId}));

  Future<EngineResult> query(int id) => engineCall(() => _api.get('$base/queries/$id'));

  /// The asker's rating of a finished answer (Phase 8).
  Future<EngineResult> rate(int id, {required bool helpful, String? comment}) =>
      engineCall(() => _api.post('$base/queries/$id/feedback', body: {'helpful': helpful, 'comment': ?comment}));

  Future<EngineResult> history({int? orgId, int? courseId, int limit = 20}) =>
      engineCall(() => _api.get('$base/queries', queryParams: {'org_id': ?orgId, 'course_id': ?courseId, 'limit': limit}));

  /// Polls until the worker answered (or [timeout]), every second at first and then up to every 5 s; the last state
  /// otherwise (the screen keeps it as "still working" and asks again on refresh).
  Future<EngineResult> waitFor(int id, {Duration timeout = const Duration(minutes: 3)}) async {
    final end = DateTime.now().add(timeout);
    var every = const Duration(seconds: 1);
    var r = await query(id);
    while (r.ok && !RagAnswer.fromJson(r.map).done && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(every);
      if (every < const Duration(seconds: 5)) every += const Duration(milliseconds: 500);
      r = await query(id);
    }
    return r;
  }

  static List<RagAnswer> items(EngineResult r) => asMapList(asMap(r.map)['items']).map(RagAnswer.fromJson).toList();
}
