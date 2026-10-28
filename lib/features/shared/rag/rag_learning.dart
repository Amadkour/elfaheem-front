// Learning from feedback (Track F, docs/polish/feedback-learning.md): the app side of the signals the assistant and
// the question generator learn from, and the admin's inbox of what they learned — /api/v1/rag/learning/…
//
//   POST /feedback {ref_type: query|exam_item|exam_draft, ref_id, kind, value}  → 204   any signed-in user; votes upsert
//        kind: chat_vote {helpful, reason?, comment?} · chat_citation_open {n, document_id, kind} ·
//              chat_deeplink {link} · chat_support {}
//   POST /exam-drafts/{id}/items/{n}/feedback {action: accept|edit|reject, reason?, final?: {question, options,
//        answer}}  → 204   the draft's owner; n = the question's index in the draft's `questions` (0-based)
//   GET  /suggestions?kind=&status=open&org_id=   {items: [{id, created_at, org_id, kind, status, support, payload,
//        source_refs, decided_by, decided_at}]}   app scope = platform admins, org scope = the org's managers
//   POST /suggestions/{id}/accept [{payload}]   qa_pair → the Q&A pair (the edited pair as `payload` when the admin
//        changed it in the sheet) · eval_item → the grown eval set · threshold / router_rule → a model candidate
//   POST /suggestions/{id}/dismiss
//   GET  /models?kind=  {items: [{id, kind, version, created_at, metrics{}, status: candidate|promoted|retired,
//        artifact_path, promoted_by, promoted_at}]}   ·   POST /models/{id}/promote (refused when the gate regresses)
//        ·   POST /models/{id}/rollback   (platform admins)
//   GET  /stats?days=[&org_id=]  {chat: {votes, helpful_rate, reasons{}, rephrase_rate}, exam: {items, accept_rate,
//        edit_rate, reject_rate, reasons{}}, suggestions_open, models: [...], lora (platform view): {writer|examgen:
//        {ready, needed, reached, by_source{}, holdout, last_candidate, last_export_at}, last_export_at, last_candidate:
//        {id, kind, version, status, gate: {passed, failures[]}}, checked_at}}
//   suggestion kind `lora_ready` (app scope, the worker's monthly check): payload {task, ready, needed, by_source,
//        month, commands: [{step, command}]} — Accept only acknowledges; training is offline
//   GET|PUT /orgs/{org_id}/settings {contribute}   the organization's opt-in "help improve the shared assistant"
//        (`learning.contribute`, default off)
//
// A bare 404 / 405 ([EngineResult.unavailable]) is an older server: the chat falls back to POST /queries/{id}/feedback
// (the reason folded into the comment), the generator's review bar and the admin pages stay hidden.
//
// Pure, unit-tested: the reason / kind codes and their labels, [RagDownVote], [chatVoteBody], [chatSignalBody],
// [legacyFeedbackComment], [examItemBody], [learningOlderServer], [LearningDebounce], [LearningSuggestion],
// [groupSuggestions], [LearningStats], [ModelVersion], [metricDeltas], [promoteConfirmText], [learningCodeText],
// [LoraReadiness] / [loraCommandsOf] (the stats' `lora` block and the `lora_ready` suggestion's offline commands, D-070).
library;

import 'dart:async' show unawaited;

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import '../exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'rag_chat.dart' show RagAnswer;
import 'rag_library.dart' show ragLibraryCodeText;
import 'rag_qa_admin.dart' show QaPair, qaLangOf;

/// The kill switch of the admin pages (console tab, org page) and of the generator's review bar.
const kRagLearningFeatureKey = 'rag.learning';

// ── codes ────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Why an answer did not help (thumbs down).
const chatReasons = ['wrong', 'incomplete', 'not_relevant', 'outdated', 'language', 'other'];

String chatReasonLabel(String code) => switch (code) {
      'wrong' => t('خاطئة', 'Wrong'),
      'incomplete' => t('ناقصة', 'Incomplete'),
      'not_relevant' => t('لا علاقة لها بسؤالي', 'Not relevant'),
      'outdated' => t('قديمة', 'Outdated'),
      'language' => t('مشكلة في اللغة', 'Language'),
      'other' => t('سبب آخر', 'Other'),
      _ => code,
    };

/// Why a generated question was rejected.
const examReasons = ['wrong_answer', 'ambiguous', 'off_topic', 'too_easy', 'too_hard', 'duplicate', 'language', 'other'];

String examReasonLabel(String code) => switch (code) {
      'wrong_answer' => t('الإجابة خاطئة', 'Wrong answer'),
      'ambiguous' => t('غامض', 'Ambiguous'),
      'off_topic' => t('خارج الموضوع', 'Off topic'),
      'too_easy' => t('سهل جداً', 'Too easy'),
      'too_hard' => t('صعب جداً', 'Too hard'),
      'duplicate' => t('مكرر', 'Duplicate'),
      'language' => t('مشكلة في اللغة', 'Language'),
      'other' => t('سبب آخر', 'Other'),
      _ => code,
    };

/// A reason of either list (the stats mix nothing, but the server may send a code the app does not know yet).
String learningReasonLabel(String code) => chatReasons.contains(code) ? chatReasonLabel(code) : examReasonLabel(code);

/// The signals the chat sends besides the vote.
const chatSignalKinds = ['chat_citation_open', 'chat_deeplink', 'chat_support'];

const suggestionKinds = ['qa_pair', 'eval_item', 'threshold', 'router_rule', 'exam_exemplar', 'exam_rule', 'lora_ready'];

String suggestionKindLabel(String kind) => switch (kind) {
      'qa_pair' => t('إجابات معتمدة مقترحة', 'Suggested Q&A pairs'),
      'eval_item' => t('أسئلة تقييم جديدة', 'New evaluation questions'),
      'threshold' => t('عتبات البحث', 'Search thresholds'),
      'router_rule' => t('قواعد التوجيه', 'Routing rules'),
      'exam_exemplar' => t('أمثلة لمولّد الأسئلة', 'Question generator examples'),
      'exam_rule' => t('قواعد فحص الأسئلة', 'Question checker rules'),
      'lora_ready' => t('جاهز لتدريب النموذج', 'Ready for model training'),
      _ => kind,
    };

/// What Accept does, for the confirmation (qa_pair opens the pair's sheet instead).
String suggestionAcceptText(String kind) => switch (kind) {
      'eval_item' => t('يُضاف السؤال إلى مجموعة التقييم الموسّعة (المجموعة الثابتة لا تتغير).',
          'The question is added to the grown evaluation set (the frozen set never changes).'),
      'threshold' || 'router_rule' => t('يُنشأ إصدار مرشّح يُقيَّم أولاً، ولا يُعتمد إلا بعد ترقيته من «الإصدارات».',
          'A candidate version is created and evaluated first; it only goes live once promoted under Model versions.'),
      'exam_exemplar' => t('يصبح السؤال مثالاً يحتذي به مولّد الأسئلة.', 'The question becomes an example the question generator follows.'),
      'exam_rule' => t('يطبّق مراجع الأسئلة هذه القاعدة على الأسئلة الجديدة.', 'The question reviewer applies this rule to new questions.'),
      'lora_ready' => t('تأكيد الاطلاع فقط: التدريب يجري خارج الخادم بالأوامر الظاهرة في «جاهزية تدريب النموذج»، ولا يتغير شيء على الخادم.',
          'Acknowledge only: training runs off the server with the commands under Model training readiness; nothing changes on the server.'),
      _ => t('يُعتمد هذا الاقتراح.', 'The suggestion is accepted.'),
    };

const modelKinds = ['reranker', 'thresholds', 'router_rules', 'writer', 'examgen'];

String modelKindLabel(String kind) => switch (kind) {
      'reranker' => t('مُعيد الترتيب', 'Reranker'),
      'thresholds' => t('عتبات البحث', 'Thresholds'),
      'router_rules' => t('قواعد التوجيه', 'Router rules'),
      'writer' => t('كاتب الإجابات (LoRA)', 'Answer writer (LoRA)'),
      'examgen' => t('مولّد الأسئلة (LoRA)', 'Question generator (LoRA)'),
      _ => kind,
    };

String modelStatusLabel(String status) => switch (status) {
      'candidate' => t('مرشّح', 'Candidate'),
      'promoted' => t('معتمد', 'Live'),
      'retired' => t('متقاعد', 'Retired'),
      _ => status,
    };

// ── chat ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/// What the thumbs-down sheet returns: the picked reason (null = none) and the comment ('' = none).
class RagDownVote {
  const RagDownVote({this.reason, this.comment = ''});
  final String? reason;
  final String comment;

  String? get commentOrNull => comment.trim().isEmpty ? null : comment.trim();

  @override
  bool operator ==(Object other) => other is RagDownVote && other.reason == reason && other.comment == comment;

  @override
  int get hashCode => Object.hash(reason, comment);

  @override
  String toString() => 'RagDownVote($reason, $comment)';
}

/// The body of a thumbs up / down on an answer.
Map<String, dynamic> chatVoteBody(int queryId, {required bool helpful, String? reason, String? comment}) {
  final c = comment?.trim() ?? '';
  return {
    'ref_type': 'query',
    'ref_id': queryId,
    'kind': 'chat_vote',
    'value': {'helpful': helpful, if (!helpful && reason != null && chatReasons.contains(reason)) 'reason': reason, if (c.isNotEmpty) 'comment': c},
  };
}

/// The answer with the asker's rating set (the learning route answers 204, not the row).
RagAnswer ragAnswerRated(RagAnswer a, bool helpful) => RagAnswer(a.id, a.state, a.question, a.found, a.answer, a.citations, a.error, helpful,
    a.followUps, a.stage, a.generator, a.app, a.orgId, a.conversationId);

/// The body of an implicit signal on an answer (a citation opened, a deep link followed, "contact support").
Map<String, dynamic> chatSignalBody(int queryId, String kind, [Map<String, dynamic> value = const {}]) =>
    {'ref_type': 'query', 'ref_id': queryId, 'kind': kind, 'value': value};

/// The older server's rating takes only a comment: the reason goes in front of it ("Wrong — the article is 7").
String? legacyFeedbackComment(String? reason, String? comment) {
  final c = comment?.trim() ?? '';
  final r = reason == null ? '' : chatReasonLabel(reason);
  if (r.isEmpty) return c.isEmpty ? null : c;
  return c.isEmpty ? r : '$r — $c';
}

/// An older server (no learning routes): a bare 404 / 405.
bool learningOlderServer(EngineResult r) => r.unavailable;

/// Drops a repeat of the same signal inside [window] (a citation opened, closed and opened again counts once).
class LearningDebounce {
  LearningDebounce({this.window = const Duration(seconds: 30), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, DateTime> _last = {};

  /// True the first time [key] is seen within [window] (and records it).
  bool pass(String key) {
    final now = _clock();
    final prev = _last[key];
    if (prev != null && now.difference(prev) < window) return false;
    if (_last.length > 200) _last.removeWhere((_, at) => now.difference(at) >= window);
    _last[key] = now;
    return true;
  }
}

/// Fire-and-forget sender of the chat's implicit signals: debounced, never awaited by the UI, silent on errors, and
/// switched off for the session once the server turns out to be older.
class LearningSignals {
  LearningSignals({LearningApi? api, LearningDebounce? debounce})
      : _api = api,
        _debounce = debounce ?? LearningDebounce();
  static final instance = LearningSignals();
  LearningApi? _api;
  LearningApi get api => _api ??= LearningApi();
  final LearningDebounce _debounce;

  /// False once a learning route answered like an older server.
  bool supported = true;

  /// Records the outcome of any learning call: an older server switches the signals (and the reason chips) off.
  void note(EngineResult r) {
    if (learningOlderServer(r)) supported = false;
  }

  void signal(int queryId, String kind, [Map<String, dynamic> value = const {}]) {
    if (!supported || queryId <= 0) return;
    if (!_debounce.pass('$kind:$queryId:${value.values.join('|')}')) return;
    unawaited(api.feedback(chatSignalBody(queryId, kind, value)).then(note, onError: (_) {}));
  }
}

// ── exam generator ───────────────────────────────────────────────────────────────────────────────────────────────

enum ExamItemAction { accept, edit, reject }

/// The body of one generated question's verdict: the reason only with a rejection, the final text only with an edit.
Map<String, dynamic> examItemBody(ExamItemAction action, {String? reason, Map<String, dynamic>? finalItem}) => {
      'action': action.name,
      if (action == ExamItemAction.reject && reason != null && examReasons.contains(reason)) 'reason': reason,
      if (action == ExamItemAction.edit && finalItem != null) 'final': finalItem,
    };

// ── suggestions ──────────────────────────────────────────────────────────────────────────────────────────────────

class LearningSuggestion {
  const LearningSuggestion({
    required this.id,
    required this.kind,
    this.status = 'open',
    this.support = 0,
    this.payload = const {},
    this.sourceRefs = const [],
    this.orgId,
    this.createdAt,
    this.decidedAt,
  });
  final int id;
  final String kind;
  final String status;

  /// Distinct askers (or thumbs-down) behind it.
  final int support;
  final Map<String, dynamic> payload;
  final List<Map<String, dynamic>> sourceRefs;
  final int? orgId;
  final String? createdAt, decidedAt;

  factory LearningSuggestion.fromJson(Map<String, dynamic> j) => LearningSuggestion(
        id: asInt(j['id']),
        kind: asStr(j['kind']),
        status: asStr(j['status'], 'open'),
        support: asInt(j['support']),
        payload: asMap(j['payload']),
        sourceRefs: asMapList(j['source_refs']),
        orgId: j['org_id'] == null ? null : asInt(j['org_id']),
        createdAt: j['created_at']?.toString(),
        decidedAt: j['decided_at']?.toString(),
      );

  bool get isQa => kind == 'qa_pair';

  /// The line the inbox shows: the question, the rule or the proposed value.
  String get title {
    if (kind == 'lora_ready') {
      return '${modelKindLabel(asStr(payload['task']))} · ${asInt(payload['ready'])} / ${asInt(payload['needed'], loraNeededDefault)}';
    }
    for (final k in ['question', 'title', 'prompt', 'rule', 'summary']) {
      final v = asStr(payload[k]).trim();
      if (v.isNotEmpty) return v;
    }
    if (kind == 'threshold') {
      final parts = [for (final e in payload.entries) if (e.value is num) '${e.key} = ${e.value}'];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final reason = asStr(payload['reason']).trim();
    if (reason.isNotEmpty) return learningReasonLabel(reason);
    return suggestionKindLabel(kind);
  }

  /// The questions people asked behind it (the cluster's questions, the variants, the source rows' questions),
  /// without repeats and without the title itself.
  List<String> get sourceQuestions {
    final seen = <String>{title.trim().toLowerCase()};
    final out = <String>[];
    void add(Object? v) {
      final s = '${v ?? ''}'.trim();
      if (s.isNotEmpty && seen.add(s.toLowerCase())) out.add(s);
    }

    for (final k in ['questions', 'variants']) {
      if (payload[k] is List) (payload[k] as List).forEach(add);
    }
    for (final r in sourceRefs) {
      add(r['question']);
    }
    return out;
  }

  /// A qa_pair as the Q&A sheet edits it (scope from the suggestion's organization).
  QaPair get qaPair => QaPair(
        scope: orgId == null ? 'app' : 'org',
        orgId: orgId,
        question: asStr(payload['question']).trim(),
        variants: <String>{
          for (final v in [...(payload['variants'] is List ? payload['variants'] as List : const []), ...(payload['questions'] is List ? payload['questions'] as List : const [])])
            if ('$v'.trim().isNotEmpty && '$v'.trim() != asStr(payload['question']).trim()) '$v'.trim()
        }.toList(),
        answer: asStr(payload['answer']),
        lang: qaLangOf(payload['lang']),
        deepLink: asStr(payload['deep_link']).trim().isEmpty ? null : asStr(payload['deep_link']).trim(),
      );
}

/// The list answer as suggestions: `{items: […]}` or a bare list (`value` after [engineCall]).
List<LearningSuggestion> suggestionsOf(Map<String, dynamic> m) =>
    asMapList(m['items'] ?? m['value']).map(LearningSuggestion.fromJson).where((s) => s.id > 0).toList();

/// Open suggestions by kind, in [suggestionKinds] order (unknown kinds last), each group by support, highest first.
List<(String, List<LearningSuggestion>)> groupSuggestions(List<LearningSuggestion> items) {
  final by = <String, List<LearningSuggestion>>{};
  for (final s in items) {
    if (s.status != 'open') continue;
    by.putIfAbsent(s.kind, () => []).add(s);
  }
  final kinds = [...suggestionKinds.where(by.containsKey), ...by.keys.where((k) => !suggestionKinds.contains(k))];
  return [
    for (final k in kinds) (k, by[k]!..sort((a, b) => b.support != a.support ? b.support.compareTo(a.support) : b.id.compareTo(a.id))),
  ];
}

// ── stats ────────────────────────────────────────────────────────────────────────────────────────────────────────

/// A rate as 0–1 (the server may send 0–1 or a percent); null when it sent none.
double? learningRate(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d > 1 ? (d / 100).clamp(0, 1).toDouble() : d.clamp(0, 1).toDouble();
}

Map<String, int> _counts(Object? v) {
  final m = asMap(v);
  return {for (final e in m.entries) if (asInt(e.value) > 0) e.key: asInt(e.value)};
}

class LearningStats {
  const LearningStats({
    this.chatVotes = 0,
    this.helpfulRate,
    this.chatReasons = const {},
    this.rephraseRate,
    this.examItems = 0,
    this.acceptRate,
    this.editRate,
    this.rejectRate,
    this.examReasons = const {},
    this.suggestionsOpen = 0,
    this.models = const [],
    this.lora,
  });
  final int chatVotes;
  final double? helpfulRate;
  final Map<String, int> chatReasons;
  final double? rephraseRate;
  final int examItems;
  final double? acceptRate, editRate, rejectRate;
  final Map<String, int> examReasons;
  final int suggestionsOpen;
  final List<ModelVersion> models;

  /// The LoRA readiness (platform admins on the platform view; null elsewhere or from an older server).
  final LoraReadiness? lora;

  factory LearningStats.fromJson(Map<String, dynamic> j) {
    final chat = asMap(j['chat']);
    final exam = asMap(j['exam']);
    return LearningStats(
      chatVotes: asInt(chat['votes']),
      helpfulRate: learningRate(chat['helpful_rate']),
      chatReasons: _counts(chat['reasons']),
      rephraseRate: learningRate(chat['rephrase_rate']),
      examItems: asInt(exam['items']),
      acceptRate: learningRate(exam['accept_rate']),
      editRate: learningRate(exam['edit_rate']),
      rejectRate: learningRate(exam['reject_rate']),
      examReasons: _counts(exam['reasons']),
      suggestionsOpen: asInt(j['suggestions_open']),
      models: asMapList(j['models']).map(ModelVersion.fromJson).toList(),
      lora: LoraReadiness.fromJson(j['lora']),
    );
  }

  bool get empty => chatVotes == 0 && examItems == 0;
}

/// Reason counts, biggest first (the donut's parts).
List<(String, int)> reasonParts(Map<String, int> reasons) =>
    (reasons.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2)));

// ── LoRA readiness (D-070) ───────────────────────────────────────────────────────────────────────────────────────

/// The export's minimum (mlops/learning/export_sft.MIN_EXAMPLES) when the server sends none.
const loraNeededDefault = 300;

/// The kinds the offline LoRA trains, in the order the page shows them.
const loraKinds = ['writer', 'examgen'];

/// The training sources per kind (export_sft.SOURCES).
const loraSources = {
  'writer': ['chat', 'qa', 'correction'],
  'examgen': ['exam_accept', 'exam_edit'],
};

String loraSourceLabel(String source) => switch (source) {
      'chat' => t('إجابات قيّمها السائلون مفيدة', 'Answers voted helpful'),
      'qa' => t('إجابات معتمدة', 'Curated Q&A pairs'),
      'correction' => t('تصحيحات التقييم', 'Evaluation corrections'),
      'exam_accept' => t('أسئلة قبلها المعلمون', 'Questions teachers accepted'),
      'exam_edit' => t('أسئلة عدّلها المعلمون', 'Questions teachers edited'),
      _ => source,
    };

String loraStepLabel(String step) => switch (step) {
      'export' => t('تصدير البيانات', 'Export the data'),
      'plan' => t('فحص الخطة', 'Check the plan'),
      'train' => t('التدريب (خارج الخادم)', 'Train (off the server)'),
      'evaluate' => t('التقييم', 'Evaluate'),
      'register' => t('الاعتماد', 'Promote'),
      'restart' => t('إعادة تشغيل العامل', 'Restart the worker'),
      _ => step,
    };

/// The newest fine-tune evaluated for a kind and the gate's verdict against the live version.
class LoraCandidate {
  const LoraCandidate(
      {required this.id, required this.kind, required this.version, this.status = 'candidate', this.createdAt, this.passed = false, this.failures = const []});
  final int id;
  final String kind, version, status;
  final String? createdAt;
  final bool passed;
  final List<String> failures;

  static LoraCandidate? fromJson(Object? v) {
    final j = asMap(v);
    if (j.isEmpty || asInt(j['id']) <= 0) return null;
    final gate = asMap(j['gate']);
    return LoraCandidate(
      id: asInt(j['id']),
      kind: asStr(j['kind']),
      version: asStr(j['version']),
      status: asStr(j['status'], 'candidate'),
      createdAt: j['created_at']?.toString(),
      passed: gate['passed'] == true,
      failures: [for (final f in (gate['failures'] is List ? gate['failures'] as List : const [])) '$f'],
    );
  }
}

class LoraKindReadiness {
  const LoraKindReadiness(
      {required this.kind, this.ready = 0, this.needed = loraNeededDefault, this.bySource = const {}, this.holdout = 0, this.lastCandidate, this.lastExportAt});
  final String kind;
  final int ready, needed, holdout;
  final Map<String, int> bySource;
  final LoraCandidate? lastCandidate;
  final String? lastExportAt;

  factory LoraKindReadiness.fromJson(String kind, Map<String, dynamic> j) {
    final by = asMap(j['by_source']);
    final known = loraSources[kind] ?? const <String>[];
    final needed = asInt(j['needed'], loraNeededDefault);
    return LoraKindReadiness(
      kind: kind,
      ready: asInt(j['ready']),
      needed: needed > 0 ? needed : loraNeededDefault,
      bySource: {for (final s in [...known, ...by.keys.where((k) => !known.contains(k))]) s: asInt(by[s])},
      holdout: asInt(j['holdout']),
      lastCandidate: LoraCandidate.fromJson(j['last_candidate']),
      lastExportAt: j['last_export_at']?.toString(),
    );
  }

  bool get reached => ready >= needed;

  /// 0–1, for the progress bar.
  double get progress => (ready / needed).clamp(0, 1).toDouble();
}

class LoraReadiness {
  const LoraReadiness({this.kinds = const [], this.lastExportAt, this.lastCandidate, this.checkedAt});
  final List<LoraKindReadiness> kinds;
  final String? lastExportAt, checkedAt;
  final LoraCandidate? lastCandidate;

  /// The stats' `lora` block; null when absent or when the server could not count (`{error}`).
  static LoraReadiness? fromJson(Object? v) {
    final j = asMap(v);
    if (j.isEmpty || j.containsKey('error')) return null;
    final kinds = [for (final k in loraKinds) if (j[k] is Map) LoraKindReadiness.fromJson(k, asMap(j[k]))];
    if (kinds.isEmpty) return null;
    return LoraReadiness(
        kinds: kinds,
        lastExportAt: j['last_export_at']?.toString(),
        lastCandidate: LoraCandidate.fromJson(j['last_candidate']),
        checkedAt: j['checked_at']?.toString());
  }
}

/// One offline step of a `lora_ready` suggestion (docs/learning/lora.md of the backend).
typedef LoraCommand = ({String step, String command});

/// The commands of a `lora_ready` suggestion, in order (empty for any other kind).
List<LoraCommand> loraCommandsOf(LearningSuggestion s) => s.kind != 'lora_ready'
    ? const []
    : [
        for (final c in asMapList(s.payload['commands']))
          if (asStr(c['command']).trim().isNotEmpty) (step: asStr(c['step']), command: asStr(c['command']).trim()),
      ];

/// The open `lora_ready` suggestion of [kind] among [items], if any.
LearningSuggestion? loraSuggestionFor(List<LearningSuggestion> items, String kind) {
  for (final s in items) {
    if (s.kind == 'lora_ready' && s.status == 'open' && asStr(s.payload['task']) == kind) return s;
  }
  return null;
}

// ── model versions ───────────────────────────────────────────────────────────────────────────────────────────────

class ModelVersion {
  const ModelVersion({
    required this.id,
    required this.kind,
    required this.version,
    this.status = 'candidate',
    this.metrics = const {},
    this.createdAt,
    this.promotedAt,
    this.artifactPath,
  });
  final int id;
  final String kind;
  final String version;
  final String status;
  final Map<String, double> metrics;
  final String? createdAt, promotedAt, artifactPath;

  factory ModelVersion.fromJson(Map<String, dynamic> j) => ModelVersion(
        id: asInt(j['id']),
        kind: asStr(j['kind']),
        version: asStr(j['version']),
        status: asStr(j['status'], 'candidate'),
        metrics: {for (final e in asMap(j['metrics']).entries) if (e.value is num) e.key: (e.value as num).toDouble()},
        createdAt: j['created_at']?.toString(),
        promotedAt: j['promoted_at']?.toString(),
        artifactPath: j['artifact_path']?.toString(),
      );

  bool get candidate => status == 'candidate';
  bool get live => status == 'promoted';
}

List<ModelVersion> modelsOf(Map<String, dynamic> m) => asMapList(m['items'] ?? m['value']).map(ModelVersion.fromJson).toList();

/// The live version of [kind] (null when none was promoted yet).
ModelVersion? liveModel(List<ModelVersion> all, String kind) {
  for (final m in all) {
    if (m.kind == kind && m.live) return m;
  }
  return null;
}

/// Lower is better for these metrics (leaks, latency, errors); higher for the rest.
bool metricLowerIsBetter(String key) {
  final k = key.toLowerCase();
  return ['leak', 'latency', 'error', 'p50', 'p95', '_ms', 'loss', 'false_found'].any(k.contains);
}

/// A rate-like metric (shown as a percent).
bool metricIsRate(String key, double v) => v >= 0 && v <= 1 && !metricLowerIsBetter(key) || key.toLowerCase().contains('rate');

String metricLabel(String key) => switch (key) {
      'not_found' || 'not_found_rate' => t('دقة «لا أعرف»', 'Not-found accuracy'),
      'leaks' => t('تسريبات', 'Leaks'),
      'correctness' => t('الصحة', 'Correctness'),
      'found_rate' => t('نسبة الإيجاد', 'Found rate'),
      'retrieval_at_5' || 'recall_at_5' => t('الاسترجاع @5', 'Retrieval @5'),
      'mrr' => 'MRR',
      'latency_ms' || 'p50_ms' => t('الزمن (م.ث)', 'Latency (ms)'),
      'latency_p95_s' => t('زمن p95 (ث)', 'p95 latency (s)'),
      'latency_p50_s' => t('زمن p50 (ث)', 'p50 latency (s)'),
      'injection' => t('مقاومة حقن التعليمات', 'Injection resistance'),
      'faithfulness' => t('الالتزام بالمصادر', 'Faithfulness'),
      'citation_precision' => t('دقة الإحالات', 'Citation precision'),
      'tok_s' => t('رمز/ثانية', 'Tokens/s'),
      'checker_pass' => t('اجتياز المدقق', 'Checker pass'),
      'accept_proxy' => t('القبول المتوقع', 'Expected acceptance'),
      'language_ok' => t('اللغة الصحيحة', 'Right language'),
      _ => key.replaceAll('_', ' '),
    };

String metricValueText(String key, double v) =>
    metricIsRate(key, v) ? '${(v * 100).toStringAsFixed(1)}%' : (v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(3));

class MetricDelta {
  const MetricDelta(this.key, this.before, this.after);
  final String key;
  final double? before, after;

  double? get delta => before == null || after == null ? null : after! - before!;

  /// True when the candidate is worse on this metric.
  bool get regresses {
    final d = delta;
    if (d == null || d.abs() < 1e-9) return false;
    return metricLowerIsBetter(key) ? d > 0 : d < 0;
  }

  bool get improves {
    final d = delta;
    if (d == null || d.abs() < 1e-9) return false;
    return !regresses;
  }

  /// "Correctness: 81.0% → 84.5% (+3.5)".
  String get text {
    final b = before == null ? '—' : metricValueText(key, before!);
    final a = after == null ? '—' : metricValueText(key, after!);
    final d = delta;
    final rate = metricIsRate(key, after ?? before ?? 2);
    final ds = d == null ? '' : ' (${d >= 0 ? '+' : ''}${rate ? (d * 100).toStringAsFixed(1) : (d == d.roundToDouble() ? '${d.round()}' : d.toStringAsFixed(3))})';
    return '${metricLabel(key)}: $b → $a$ds';
  }
}

/// The candidate's metrics against the live version's: the candidate's keys first, then the live-only ones.
List<MetricDelta> metricDeltas(ModelVersion candidate, ModelVersion? live) {
  final keys = [...candidate.metrics.keys, ...?live?.metrics.keys.where((k) => !candidate.metrics.containsKey(k))];
  return [for (final k in keys) MetricDelta(k, live?.metrics[k], candidate.metrics[k])];
}

/// The promote confirmation: what changes, metric by metric, and a warning when anything regresses.
String promoteConfirmText(ModelVersion candidate, ModelVersion? live) {
  final deltas = metricDeltas(candidate, live);
  final head = live == null
      ? t('اعتماد ${modelKindLabel(candidate.kind)} ${candidate.version} (لا إصدار معتمد قبله)', 'Promote ${modelKindLabel(candidate.kind)} ${candidate.version} (nothing is live yet)')
      : t('اعتماد ${modelKindLabel(candidate.kind)} ${candidate.version} بدل ${live.version}', 'Promote ${modelKindLabel(candidate.kind)} ${candidate.version} over ${live.version}');
  final lines = [for (final d in deltas) '• ${d.text}'];
  final worse = deltas.where((d) => d.regresses).length;
  return [
    head,
    if (lines.isNotEmpty) '\n${lines.join('\n')}',
    if (worse > 0) '\n${t('تحذير: $worse مقاييس أسوأ — قد يرفض الخادم الاعتماد', 'Warning: $worse metrics are worse — the server may refuse')}',
  ].join('\n');
}

String learningCodeText(String? code, String fallback) => switch (code) {
      'gate_regressed' || 'metrics_regress' || 'promote_regressed' || 'regression' =>
        t('لم يُعتمد: الإصدار المرشّح أسوأ من الحالي في بوابة التقييم', 'Not promoted: the candidate scores worse than the live version on the gate'),
      'not_candidate' => t('هذا الإصدار ليس مرشّحاً', 'This version is not a candidate'),
      'nothing_to_rollback' || 'no_previous_version' => t('لا إصدار سابق للرجوع إليه', 'There is no earlier version to roll back to'),
      'already_decided' || 'suggestion_closed' => t('قُرّر هذا الاقتراح من قبل', 'This suggestion was already decided'),
      'suggestion_not_found' || 'model_not_found' => t('العنصر غير موجود', 'Not found'),
      'platform_admin_required' => t('لإدارة المنصة فقط', 'For platform admins only'),
      'not_org_manager' || 'not_library_manager' => t('لمديري المؤسسة فقط', 'For the organization\'s managers only'),
      'not_draft_owner' => t('المسودة ليست لك', 'This draft is not yours'),
      'bad_reason' => t('سبب غير صالح', 'Invalid reason'),
      'bad_kind' => t('نوع غير صالح', 'Invalid kind'),
      'too_many_requests' || 'rate_limited' => t('طلبات كثيرة في وقت قصير — انتظر دقيقة', 'Too many requests — wait a minute'),
      _ => ragLibraryCodeText(code, fallback),
    };

/// The text when a whole learning page meets an older server.
String learningNeedsUpdateText() => t('التعلّم من الملاحظات يحتاج تحديث الخادم', 'Learning from feedback needs a server update');

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class LearningApi {
  LearningApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/rag/learning';

  Future<EngineResult> feedback(Map<String, dynamic> body) => engineCall(() => _api.post('$base/feedback', body: body));

  Future<EngineResult> examItemFeedback(int draftId, int n, Map<String, dynamic> body) =>
      engineCall(() => _api.post('$base/exam-drafts/$draftId/items/$n/feedback', body: body));

  Future<EngineResult> suggestions({String? kind, String status = 'open', int? orgId}) =>
      engineCall(() => _api.get('$base/suggestions', queryParams: {'kind': ?kind, 'status': status, 'org_id': ?orgId}));

  /// [payload]: the admin's edited version (a qa_pair from the sheet); null = as suggested.
  Future<EngineResult> accept(int id, {Map<String, dynamic>? payload}) =>
      engineCall(() => _api.post('$base/suggestions/$id/accept', body: {'payload': ?payload}));

  Future<EngineResult> dismiss(int id) => engineCall(() => _api.post('$base/suggestions/$id/dismiss'));

  Future<EngineResult> models({String? kind}) => engineCall(() => _api.get('$base/models', queryParams: {'kind': ?kind}));
  Future<EngineResult> promote(int id) => engineCall(() => _api.post('$base/models/$id/promote'));
  Future<EngineResult> rollback(int id) => engineCall(() => _api.post('$base/models/$id/rollback'));

  Future<EngineResult> stats({int days = 30, int? orgId}) => engineCall(() => _api.get('$base/stats', queryParams: {'days': days, 'org_id': ?orgId}));

  Future<EngineResult> orgSettings(int orgId) => engineCall(() => _api.get('$base/orgs/$orgId/settings'));
  Future<EngineResult> saveOrgSettings(int orgId, {required bool contribute}) =>
      engineCall(() => _api.put('$base/orgs/$orgId/settings', body: {'contribute': contribute}));
}
