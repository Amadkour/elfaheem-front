// The RAG admin console (D-012): the Super Admin's control room of the assistant — /api/v1/rag/admin/…
//
//   GET/PUT /admin/settings   the platform settings (generator, consent default, style, persona, agents, models) +
//                             the model's status; PUT takes any subset (422 bad_setting)
//   POST    /admin/llm/test   a one-word completion against the provider → {ok, model, latency_ms | error}
//   GET     /admin/overview?days=   questions per day, found / helpful rates, by context, generators, latency, the
//                             questions most often not found, recent unhelpful answers, documents, queue, exam drafts,
//                             `monitoring` (Track E.7: path qa_direct · cache · extractive · model per question, latency
//                             p50 / p95 per path, rates, by_day) → [RagMonitoring], drawn by [RagHealthBlock]
//   GET     /admin/monitoring/summary?days=7   the super admin home's "AI assistant" card (admin_home_body.dart)
//   GET     /admin/queries?app=&org_id=&found=&helpful=&q=&limit=   browse questions with their traces
//   GET     /admin/queries/{id} · POST /admin/playground {question, app, org_id?, course_id?} → 202 (poll the query)
//   GET     /admin/exam-drafts?limit=   recent drafts with their review summaries
//   GET     /admin/alerts · PUT /admin/alerts/rules · POST /admin/alerts/{id}/resolve · GET /admin/gate-refused
//                             the Alerts and Gate refusals tabs (rag_alerts.dart, rag_alerts_page.dart)
//   (Track F) the Learning tab — /api/v1/rag/learning/… (rag_learning.dart, rag_learning_page.dart): shown once
//   GET /learning/stats answers (an older server keeps the console as it was), kill switch rag.learning
//
// Pure, unit-tested: [RagAdminSettings], [RagOverview], [RagMonitoring], [RagTrace], [ragRate], [ragGeneratorLabel],
// [ragTraceStepText], [ragMsText], [ragPctText], [halfRateDelta].
// Presentational, under the layout harness: [RagOverviewView], [RagHealthBlock], [RagPlatformSettingsForm],
// [RagTraceView], [RagAdminQueryTile]. [RagAdminConsole] owns the calls.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart' show EventOrPoll;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, asStr, t;
import '../../admin/admin_home_data.dart' show halfDelta;
import '../../admin/models/ai_models_page.dart' show AiModelsPage;
import '../../auth/auth_provider.dart' show MyAuthProvider;
import '../exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'admin/rag_cache_card.dart' show RagCacheApi, RagCacheSection;
import 'admin/rag_console_settings.dart' show RagExtraSettings, RagExtraSettingsCard;
import 'admin/rag_feedback_review.dart' show FeedbackReviewApi, FeedbackReviewBody;
import 'rag_alerts_page.dart' show RagAlertsTab, RagGateTab;
import 'rag_chat.dart';
import 'rag_chat_screen.dart' show RagAnswerBody;
import 'rag_learning.dart' show EmbedderJob, LearningApi, kRagLearningFeatureKey, learningCodeText;
import 'rag_learning_page.dart' show RagLearningBody, RagTileGrid;
import 'rag_library.dart' show ragLibraryCodeText;
import 'rag_library_screen.dart' show RagLibraryScreen;
import 'rag_qa_admin.dart';

// ── models ───────────────────────────────────────────────────────────────────────────────────────────────────────

class RagAdminSettings {
  const RagAdminSettings({
    this.generator = 'llm',
    this.allowExternalDefault = true,
    this.answerStyle = 'balanced',
    this.assistantName = '',
    this.personaAr = '',
    this.personaEn = '',
    this.conversationTurns = 4,
    this.conversationRetentionDays = 90,
    this.planQueries = true,
    this.verifyAnswers = true,
    this.smallTalk = true,
    this.examPlanner = true,
    this.examReviewer = true,
    this.maxCitations = 4,
    this.effortAnswer = 'medium',
    this.effortLight = 'low',
    this.effortExam = 'high',
    this.model = '',
    this.fastModel = '',
    this.llmAvailable = false,
    this.llmProvider = '',
    this.llmModel = '',
    this.llmFastModel = '',
    this.llmExternal = false,
    this.effectiveGenerator = 'extractive',
    this.llmLocal = false,
    this.llmProfile = '',
    this.llmFilesOk = true,
    this.llmFilesError = '',
    this.llmTokensPerS,
    this.extra = const RagExtraSettings(),
  });

  /// The D-190 settings (answer mode, OCR, upload size, search-model training); saved on their own card.
  final RagExtraSettings extra;
  final String generator; // llm | extractive
  final bool allowExternalDefault;
  final String answerStyle; // concise | balanced | detailed
  final String assistantName, personaAr, personaEn;
  final int conversationTurns, maxCitations;

  /// Chats with no new question for this many days are deleted by the server (0 = kept forever; 0–3650, D-064).
  final int conversationRetentionDays;
  final bool planQueries, verifyAnswers, smallTalk, examPlanner, examReviewer;
  final String effortAnswer, effortLight, effortExam;
  final String model, fastModel;
  // the server's model status
  final bool llmAvailable, llmExternal;
  final String llmProvider, llmModel, llmFastModel, effectiveGenerator;
  /// `local`: the open-weight model runs inside the server's worker (provider `onnx`, D-012): no excerpt leaves the
  /// server, no consent to collect. `profile` `light` = one call per answer, code planning / checks (no effort knobs).
  final bool llmLocal, llmFilesOk;
  final String llmProfile, llmFilesError;
  final double? llmTokensPerS;

  bool get light => llmProfile == 'light';

  /// The server's bound of `conversation_retention_days`.
  static const maxRetentionDays = 3650;

  factory RagAdminSettings.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['settings']);
    final llm = asMap(j['llm']);
    return RagAdminSettings(
      generator: asStr(s['generator']) == 'extractive' ? 'extractive' : 'llm',
      allowExternalDefault: asBool(s['allow_external_default'], true),
      answerStyle: const ['concise', 'balanced', 'detailed'].contains(s['answer_style']) ? asStr(s['answer_style']) : 'balanced',
      assistantName: asStr(s['assistant_name']),
      personaAr: asStr(s['persona_ar']),
      personaEn: asStr(s['persona_en']),
      conversationTurns: asInt(s['conversation_turns'], 4),
      conversationRetentionDays: asInt(s['conversation_retention_days'], 90).clamp(0, maxRetentionDays),
      planQueries: asBool(s['plan_queries'], true),
      verifyAnswers: asBool(s['verify_answers'], true),
      smallTalk: asBool(s['small_talk'], true),
      examPlanner: asBool(s['exam_planner'], true),
      examReviewer: asBool(s['exam_reviewer'], true),
      maxCitations: asInt(s['max_citations'], 4),
      effortAnswer: asStr(s['effort_answer'], 'medium'),
      effortLight: asStr(s['effort_light'], 'low'),
      effortExam: asStr(s['effort_exam'], 'high'),
      model: asStr(s['model']),
      fastModel: asStr(s['fast_model']),
      llmAvailable: asBool(llm['available']),
      llmProvider: asStr(llm['provider']),
      llmModel: asStr(llm['model']),
      llmFastModel: asStr(llm['fast_model']),
      llmExternal: asBool(llm['external']),
      llmLocal: asBool(llm['local']),
      llmProfile: asStr(llm['profile']),
      llmFilesOk: asBool(asMap(llm['files'])['ok'], !asBool(llm['local'])),
      llmFilesError: asStr(asMap(llm['files'])['error']),
      llmTokensPerS: llm['warm_tokens_per_s'] == null ? null : double.tryParse('${llm['warm_tokens_per_s']}'),
      effectiveGenerator: asStr(j['generator_effective'], 'extractive'),
      extra: RagExtraSettings.fromJson(j['settings']),
    );
  }

  /// The PUT body: every editable key (the server merges).
  Map<String, dynamic> toJson() => {
        'generator': generator,
        'allow_external_default': allowExternalDefault,
        'answer_style': answerStyle,
        'assistant_name': assistantName,
        'persona_ar': personaAr,
        'persona_en': personaEn,
        'conversation_turns': conversationTurns,
        'conversation_retention_days': conversationRetentionDays,
        'plan_queries': planQueries,
        'verify_answers': verifyAnswers,
        'small_talk': smallTalk,
        'exam_planner': examPlanner,
        'exam_reviewer': examReviewer,
        'max_citations': maxCitations,
        'effort_answer': effortAnswer,
        'effort_light': effortLight,
        'effort_exam': effortExam,
        'model': model,
        'fast_model': fastModel,
      };

  RagAdminSettings copyWith({
    String? generator, bool? allowExternalDefault, String? answerStyle, String? assistantName, String? personaAr, String? personaEn,
    int? conversationTurns, int? conversationRetentionDays, bool? planQueries, bool? verifyAnswers, bool? smallTalk, bool? examPlanner, bool? examReviewer,
    int? maxCitations, String? effortAnswer, String? effortLight, String? effortExam, String? model, String? fastModel,
  }) =>
      RagAdminSettings(
        generator: generator ?? this.generator,
        allowExternalDefault: allowExternalDefault ?? this.allowExternalDefault,
        answerStyle: answerStyle ?? this.answerStyle,
        assistantName: assistantName ?? this.assistantName,
        personaAr: personaAr ?? this.personaAr,
        personaEn: personaEn ?? this.personaEn,
        conversationTurns: conversationTurns ?? this.conversationTurns,
        conversationRetentionDays: conversationRetentionDays ?? this.conversationRetentionDays,
        planQueries: planQueries ?? this.planQueries,
        verifyAnswers: verifyAnswers ?? this.verifyAnswers,
        smallTalk: smallTalk ?? this.smallTalk,
        examPlanner: examPlanner ?? this.examPlanner,
        examReviewer: examReviewer ?? this.examReviewer,
        maxCitations: maxCitations ?? this.maxCitations,
        effortAnswer: effortAnswer ?? this.effortAnswer,
        effortLight: effortLight ?? this.effortLight,
        effortExam: effortExam ?? this.effortExam,
        model: model ?? this.model,
        fastModel: fastModel ?? this.fastModel,
        llmAvailable: llmAvailable, llmProvider: llmProvider, llmModel: llmModel, llmFastModel: llmFastModel, llmExternal: llmExternal,
        llmLocal: llmLocal, llmProfile: llmProfile, llmFilesOk: llmFilesOk, llmFilesError: llmFilesError, llmTokensPerS: llmTokensPerS,
        effectiveGenerator: effectiveGenerator,
        extra: extra,
      );
}

class RagOverview {
  const RagOverview({
    this.days = 30, this.asked = 0, this.answered = 0, this.found = 0, this.failed = 0, this.pending = 0, this.rated = 0, this.helpful = 0,
    this.askers = 0, this.p50, this.p90, this.byDay = const [], this.contexts = const {}, this.generators = const {}, this.notFound = const [],
    this.hedged = const [], this.unhelpful = const [], this.documents = const [], this.queueWaiting = 0, this.drafts = 0, this.draftQuestions = 0,
    this.draftsLlm = 0, this.qaPairs = 0, this.qaEnabled = 0, this.qaDirect = 0, this.qaExample = 0, this.monitoring,
  });
  final int days, asked, answered, found, failed, pending, rated, helpful, askers;
  final int? p50, p90;
  final List<Map<String, dynamic>> byDay, notFound, unhelpful, documents;

  /// The questions most often answered with the closest match only (the server's hedge, D-121; empty on an older server).
  final List<Map<String, dynamic>> hedged;
  final Map<String, Map<String, int>> contexts;
  final Map<String, int> generators;
  final int queueWaiting, drafts, draftQuestions, draftsLlm;

  /// Curated Q&A (Track E.2): pairs, enabled pairs, direct hits and example uses in the window.
  final int qaPairs, qaEnabled, qaDirect, qaExample;

  /// Track E.7 (null: an older server without the block — the Health block is left out).
  final RagMonitoring? monitoring;

  factory RagOverview.fromJson(Map<String, dynamic> j) {
    final tot = asMap(j['totals']);
    final lat = asMap(j['latency_ms']);
    final ctx = asMap(j['contexts']);
    final gens = asMap(j['generators']);
    final q = asMap(j['queue']);
    final ed = asMap(j['exam_drafts']);
    final qa = asMap(j['qa']);
    return RagOverview(
      qaPairs: asInt(qa['pairs']), qaEnabled: asInt(qa['enabled']), qaDirect: asInt(qa['direct']), qaExample: asInt(qa['example']),
      days: asInt(j['days'], 30),
      asked: asInt(tot['asked']), answered: asInt(tot['answered']), found: asInt(tot['found']), failed: asInt(tot['failed']),
      pending: asInt(tot['pending']), rated: asInt(tot['rated']), helpful: asInt(tot['helpful']), askers: asInt(tot['askers']),
      p50: lat['p50'] == null ? null : asInt(lat['p50']), p90: lat['p90'] == null ? null : asInt(lat['p90']),
      byDay: asMapList(j['by_day']), notFound: asMapList(j['not_found']), hedged: asMapList(j['hedged']), unhelpful: asMapList(j['unhelpful']),
      documents: asMapList(j['documents']),
      contexts: {for (final e in ctx.entries) e.key: {for (final x in asMap(e.value).entries) x.key: asInt(x.value)}},
      generators: {for (final e in gens.entries) e.key: asInt(e.value)},
      queueWaiting: asInt(q['waiting']),
      drafts: asInt(ed['total']), draftQuestions: asInt(ed['questions']), draftsLlm: asInt(ed['llm']),
      monitoring: j['monitoring'] is Map ? RagMonitoring.fromJson(asMap(j['monitoring'])) : null,
    );
  }

  /// 0–100, null when nothing to rate.
  int? get foundRate => ragRate(found, answered);
  int? get helpfulRate => ragRate(helpful, rated);

  int get readyDocuments => documents.where((d) => d['status'] == 'ready').fold(0, (n, d) => n + asInt(d['count']));
}

/// A percentage of [part] over [whole] (null when [whole] is 0).
int? ragRate(int part, int whole) => whole <= 0 ? null : (part * 100 / whole).round();

/// The answer paths of `monitoring`, in the order the console lists them.
const ragPaths = ['qa_direct', 'cache', 'extractive', 'model'];

String ragPathLabel(String path) => switch (path) {
      'qa_direct' => t('إجابة معتمدة مباشرة', 'Direct Q&A'),
      'cache' => t('من الذاكرة المؤقتة', 'From the cache'),
      'model' => t('النموذج اللغوي', 'Language model'),
      _ => t('اقتباس من المستندات', 'Quoted from documents'),
    };

/// 45 → "45 ms", 1234 → "1.2 s", null → "—".
String ragMsText(int? ms) => ms == null ? '—' : (ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s');

/// A 0..1 rate as "12%" (null → "—").
String ragPctText(double? rate) => rate == null ? '—' : '${(rate * 100).round()}%';

/// Percent change of the rate part / whole in the second half of the window against the first half (null without
/// a base: no question, or a zero rate, in the first half).
double? halfRateDelta(List<int> part, List<int> whole) {
  if (part.length != whole.length || whole.length < 2) return null;
  final mid = whole.length ~/ 2;
  int sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);
  final w1 = sum(whole.take(mid)), w2 = sum(whole.skip(mid));
  if (w1 <= 0 || w2 <= 0) return null;
  final r1 = sum(part.take(mid)) / w1, r2 = sum(part.skip(mid)) / w2;
  if (r1 <= 0) return null;
  return (r2 - r1) / r1 * 100;
}

/// One path's latency (`monitoring.latency_ms.by_path[path]`): questions on it, how many carry a latency, p50 / p95.
class RagPathLatency {
  const RagPathLatency({required this.path, this.questions = 0, this.count = 0, this.p50, this.p95});
  factory RagPathLatency.fromJson(String path, Map<String, dynamic> j) => RagPathLatency(
      path: path, questions: asInt(j['questions']), count: asInt(j['count']),
      p50: j['p50'] == null ? null : asInt(j['p50']), p95: j['p95'] == null ? null : asInt(j['p95']));
  final String path;
  final int questions, count;
  final int? p50, p95;
}

/// One UTC day of `monitoring.by_day`.
class RagMonitorDay {
  const RagMonitorDay({required this.day, this.questions = 0, this.noAnswer = 0, this.cacheHits = 0, this.qaDirect = 0, this.p50Ms});
  factory RagMonitorDay.fromJson(Map<String, dynamic> j) => RagMonitorDay(
      day: asStr(j['day']), questions: asInt(j['questions']), noAnswer: asInt(j['no_answer']), cacheHits: asInt(j['cache_hits']),
      qaDirect: asInt(j['qa_direct']), p50Ms: j['p50_ms'] == null ? null : asInt(j['p50_ms']));
  final String day;
  final int questions, noAnswer, cacheHits, qaDirect;
  final int? p50Ms;

  /// "2026-10-07" → "7" (the bar chart's axis).
  String get dayLabel {
    final p = day.split('-');
    return p.length == 3 ? '${int.tryParse(p[2]) ?? p[2]}' : day;
  }
}

/// The overview's `monitoring` block (Track E.7): how the window's questions were answered, computed by the server
/// in SQL. Rates are 0..1 (null: nothing to divide by).
class RagMonitoring {
  const RagMonitoring({
    this.days = 30, this.questions = 0, this.p50, this.p95, this.byPath = const {}, this.cacheHitRate, this.qaDirectRate,
    this.qaExampleRate, this.noAnswerRate, this.fallbackRate, this.helpfulRate, this.byDay = const [], this.pollRate,
    this.deliveryReported = 0,
  });

  factory RagMonitoring.fromJson(Map<String, dynamic> j) {
    final lat = asMap(j['latency_ms']);
    final bp = asMap(lat['by_path']);
    double? r(String k) => j[k] == null ? null : asDouble(j[k]);
    final dl = asMap(j['delivery']);
    return RagMonitoring(
      days: asInt(j['days'], 30),
      questions: asInt(j['questions']),
      p50: lat['p50'] == null ? null : asInt(lat['p50']),
      p95: lat['p95'] == null ? null : asInt(lat['p95']),
      byPath: {for (final p in ragPaths) p: RagPathLatency.fromJson(p, asMap(bp[p]))},
      cacheHitRate: r('cache_hit_rate'), qaDirectRate: r('qa_direct_rate'), qaExampleRate: r('qa_example_rate'),
      noAnswerRate: r('no_answer_rate'), fallbackRate: r('fallback_rate'), helpfulRate: r('helpful_rate'),
      byDay: [for (final d in asMapList(j['by_day'])) RagMonitorDay.fromJson(d)],
      pollRate: dl['poll_rate'] == null ? null : asDouble(dl['poll_rate']),
      deliveryReported: asInt(dl['reported']),
    );
  }

  final int days, questions;
  final int? p50, p95;
  final Map<String, RagPathLatency> byPath;
  final double? cacheHitRate, qaDirectRate, qaExampleRate, noAnswerRate, fallbackRate, helpfulRate;
  final List<RagMonitorDay> byDay;

  /// `delivery` (rag_0015): the share of the answers the app reported getting by polling instead of the live
  /// stream, and how many reported at all (0 on an older server or before any report).
  final double? pollRate;
  final int deliveryReported;

  bool get hasActivity => questions > 0;

  List<int> get _q => [for (final d in byDay) d.questions];
  List<double> _rate(int Function(RagMonitorDay d) part) => [for (final d in byDay) d.questions == 0 ? 0 : part(d) / d.questions];

  List<double> get questionsSpark => [for (final d in byDay) d.questions.toDouble()];
  List<double> get noAnswerSpark => _rate((d) => d.noAnswer);
  List<double> get cacheSpark => _rate((d) => d.cacheHits);
  List<double> get qaDirectSpark => _rate((d) => d.qaDirect);

  /// Second half of the window against the first (AppTrendTile's delta, in percent).
  double? get questionsDelta => halfDelta(questionsSpark);
  double? get noAnswerDelta => halfRateDelta([for (final d in byDay) d.noAnswer], _q);
  double? get cacheDelta => halfRateDelta([for (final d in byDay) d.cacheHits], _q);
  double? get qaDirectDelta => halfRateDelta([for (final d in byDay) d.qaDirect], _q);

  /// The last [n] days (the bar chart: 90 groups do not fit a phone).
  List<RagMonitorDay> recent(int n) => byDay.length <= n ? byDay : byDay.sublist(byDay.length - n);
}

/// A short human label of a `generator` value.
String ragGeneratorLabel(String g) {
  if (g == 'llm:small_talk' || g == 'none:small_talk') return t('ترحيب', 'Small talk');
  if (g.startsWith('llm')) return t('نموذج لغوي', 'Model');
  if (g.startsWith('extractive (')) return t('اقتباس (بديل)', 'Quoted (fallback)');
  if (g == 'extractive') return t('اقتباس', 'Quoted');
  return t('بلا إجابة', 'None');
}

/// One answered question's pipeline trace (the admin console's drill-down).
class RagTrace {
  const RagTrace({this.steps = const [], this.plan = const {}, this.verify = const {}, this.fallback, this.hits = const [], this.totalMs = 0});
  final List<Map<String, dynamic>> steps, hits;
  final Map<String, dynamic> plan, verify;
  final String? fallback;
  final int totalMs;

  factory RagTrace.fromJson(Object? v) {
    final j = asMap(v);
    return RagTrace(
        steps: asMapList(j['steps']), plan: asMap(j['plan']), verify: asMap(j['verify']), fallback: j['fallback']?.toString(),
        hits: asMapList(j['hits']), totalMs: asInt(j['total_ms']));
  }

  bool get isEmpty => steps.isEmpty && plan.isEmpty;
  List<String> get queries => [for (final q in (plan['queries'] is List ? plan['queries'] as List : const [])) '$q'];
  String get intent => asStr(plan['intent']);
}

/// "write · claude-opus-5-5 · 1.2 s · 2.1k→310 tokens" (what a trace row says).
String ragTraceStepText(Map<String, dynamic> s) {
  final parts = <String>[asStr(s['name'])];
  if (asStr(s['model']).isNotEmpty) parts.add(asStr(s['model']));
  final ms = asInt(s['ms']);
  parts.add(ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)} s' : '$ms ms');
  if (s['in'] != null || s['out'] != null) parts.add('${_k(asInt(s['in']))}→${_k(asInt(s['out']))} ${t('رمز', 'tokens')}');
  if (asStr(s['error']).isNotEmpty) parts.add('⚠ ${asStr(s['error'])}');
  if (s['queries'] != null) parts.add('${asInt(s['queries'])} ${t('استعلام', 'queries')} · ${asInt(s['hits'])} ${t('نتيجة', 'hits')}');
  if (s['supported'] != null) parts.add(asBool(s['supported']) ? t('مدعومة', 'supported') : t('غير مدعومة', 'unsupported'));
  return parts.join(' · ');
}

String _k(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class RagAdminApi {
  RagAdminApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/rag/admin';

  Future<EngineResult> settings() => engineCall(() => _api.get('$base/settings'));
  Future<EngineResult> saveSettings(Map<String, dynamic> body) => engineCall(() => _api.put('$base/settings', body: body));
  Future<EngineResult> testLlm() => engineCall(() => _api.post('$base/llm/test'));
  Future<EngineResult> overview({int days = 30}) => engineCall(() => _api.get('$base/overview', queryParams: {'days': days}));

  /// The super admin home's card (Track E.7); `unavailable` on an older server.
  Future<EngineResult> monitoringSummary({int days = 7}) =>
      engineCall(() => _api.get('$base/monitoring/summary', queryParams: {'days': days}));
  Future<EngineResult> queries({bool? app, int? orgId, bool? found, bool? helpful, String? q, int limit = 50}) => engineCall(() =>
      _api.get('$base/queries', queryParams: {'app': ?app, 'org_id': ?orgId, 'found': ?found, 'helpful': ?helpful, 'q': ?q, 'limit': limit}));
  Future<EngineResult> query(int id) => engineCall(() => _api.get('$base/queries/$id'));
  Future<EngineResult> playground(String question, {bool app = true, int? orgId, int? courseId}) =>
      engineCall(() => _api.post('$base/playground', body: {'question': question, 'app': app, 'org_id': ?orgId, 'course_id': ?courseId}));
  Future<EngineResult> examDrafts({int limit = 50}) => engineCall(() => _api.get('$base/exam-drafts', queryParams: {'limit': limit}));

  /// Polls the playground question until the worker answered.
  Future<EngineResult> waitFor(int id, {Duration timeout = const Duration(minutes: 3)}) async {
    final end = DateTime.now().add(timeout);
    var r = await query(id);
    while (r.ok && !RagAnswer.fromJson(r.map).done && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      r = await query(id);
    }
    return r;
  }
}

String ragAdminCodeText(String? code, String fallback) => switch (code) {
      'platform_admin_required' => t('لوحة المساعد لإدارة المنصة فقط', 'The assistant console is for platform admins only'),
      'super_admin_required' => t('إعدادات المساعد يحددها مدير المنصة', 'Only the Super Admin changes the assistant\'s settings'),
      'bad_setting' => t('قيمة إعداد غير صالحة', 'An invalid setting value'),
      'context_required' => t('حدد المؤسسة أو المقرر', 'Pick the organization or the course'),
      _ => ragLibraryCodeText(code, fallback),
    };

// ── the page ─────────────────────────────────────────────────────────────────────────────────────────────────────

class RagAdminConsole extends StatefulWidget {
  const RagAdminConsole({super.key, this.api, this.qaApi, this.learningApi, this.feedbackApi, this.cacheApi, this.initialTab = 0});
  final RagAdminApi? api;
  final QaApi? qaApi;
  final LearningApi? learningApi;
  final FeedbackReviewApi? feedbackApi;
  final RagCacheApi? cacheApi;

  /// The tab to open on (the admin home's alert rows open [alertsTab]).
  final int initialTab;

  /// Overview · Settings · Playground · Questions · Alerts · Gate refusals · [Q&A] · [Learning] · Feedback.
  static const alertsTab = 4;
  static const gateTab = 5;

  @override
  State<RagAdminConsole> createState() => _RagAdminConsoleState();
}

class _RagAdminConsoleState extends State<RagAdminConsole> with SingleTickerProviderStateMixin {
  late final RagAdminApi _api = widget.api ?? RagAdminApi();
  late final QaApi _qa = widget.qaApi ?? QaApi();
  // the Q&A tab and the "promote" actions (kill switch rag.qa_admin; the whole tree rebuilds when the list changes)
  final bool _qaOn = !AppConfig.disableList.contains('rag.qa_admin');
  // the Learning tab (Track F, kill switch rag.learning): added once the server answers the learning stats
  final bool _learningAllowed = !AppConfig.disableList.contains(kRagLearningFeatureKey);
  late final LearningApi _learning = widget.learningApi ?? LearningApi();
  bool _learningOn = false;
  EmbedderJob? _embedderJob;
  EventOrPoll? _embedderPoll;
  bool _training = false;
  // the alert rules and "evaluate now" are the Super Admin's (the server answers 403 to the other platform admins)
  bool get _superAdmin {
    try {
      return const {'super-admin', 'developer'}.contains(context.read<MyAuthProvider>().currentUser?.role ?? '');
    } catch (_) {
      return false; // no auth provider above (tests): read-only
    }
  }
  late TabController _tabs = TabController(length: _tabCount, vsync: this, initialIndex: widget.initialTab.clamp(0, _tabCount - 1));
  int get _tabCount => 7 + (_qaOn ? 1 : 0) + (_learningOn ? 1 : 0);

  /// Shows / hides the Learning tab: a new controller of the new length on the same tab (the old one is disposed
  /// after the frame that stops using it).
  void _setLearning(bool on) {
    if (on == _learningOn) return;
    final old = _tabs;
    _learningOn = on;
    _tabs = TabController(length: _tabCount, vsync: this, initialIndex: old.index.clamp(0, _tabCount - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }
  RagOverview? _overview;
  RagAdminSettings? _settings;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _embedderPoll?.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rs = await Future.wait([_api.overview(days: _days), _api.settings()]);
    final learning = _learningAllowed && !_learningOn ? await _learning.stats(days: 7) : null;
    if (!mounted) return;
    if (learning != null) _setLearning(learning.ok);
    if (_learningAllowed && learning != null && learning.ok) unawaited(_refreshEmbedder());
    setState(() {
      _error = null;
      for (final r in rs) {
        if (!r.ok) _error = r.unavailable ? t('لوحة المساعد تحتاج تحديث الخادم', 'The assistant console needs a server update') : ragAdminCodeText(r.code, r.message);
      }
      if (rs[0].ok) _overview = RagOverview.fromJson(rs[0].map);
      if (rs[1].ok) _settings = RagAdminSettings.fromJson(rs[1].map);
    });
  }

  Future<void> _save(RagAdminSettings s) async {
    final r = await _api.saveSettings(s.toJson());
    if (!mounted) return;
    if (r.ok) {
      setState(() => _settings = RagAdminSettings.fromJson(r.map));
      appToast(t('تم الحفظ', 'Saved'));
    } else {
      appToast(ragAdminCodeText(r.code, r.message), error: true);
    }
  }

  /// The D-190 settings card: only its own keys travel (the server merges).
  Future<EngineResult> _saveSettingsBody(Map<String, dynamic> body) => _api.saveSettings(body);

  Future<void> _saveExtra(Map<String, dynamic> body) async {
    final r = await _api.saveSettings(body);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _settings = RagAdminSettings.fromJson(r.map));
      appToast(t('تم الحفظ', 'Saved'));
    } else {
      appToast(ragAdminCodeText(r.code, r.message), error: true);
    }
  }

  /// `GET /rag/learning/embedder/status`; while a run is active the job event (or the slow poll) refreshes it.
  Future<void> _refreshEmbedder() async {
    final st = await _learning.embedderStatus();
    if (!mounted) return;
    final job = st.ok ? EmbedderJob.fromJson(st.map) : null;
    if (st.ok) setState(() => _embedderJob = job);
    if (job?.running == true) {
      (_embedderPoll ??= EventOrPoll(
              match: (e) => e.kind == 'embedder' || e.kind == 'rag_embedder',
              every: const Duration(seconds: 10),
              fallbackEvery: const Duration(seconds: 30),
              poll: _refreshEmbedder))
          .start();
    } else {
      _embedderPoll?.stop();
    }
  }

  Future<void> _trainEmbedder() async {
    setState(() => _training = true);
    final r = await _learning.trainEmbedder();
    if (!mounted) return;
    setState(() => _training = false);
    if (r.ok) {
      appToast(t('بدأ تدريب نموذج البحث', 'Search-model training started'));
      await _refreshEmbedder();
    } else {
      appToast(learningCodeText(r.code, r.message), error: true);
    }
  }

  void _manageModels() => Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: AiModelsPage.routeName), builder: (_) => const AiModelsPage()));

  Future<void> _test() async {
    final r = await _api.testLlm();
    if (!mounted) return;
    final j = asMap(r.map);
    if (r.ok && asBool(j['ok']) && j['latency_ms'] == null) {
      appToast(t('ملفات النموذج المحلي ${asStr(j['model'])} موجودة على الخادم؛ جرّبه من تبويب التجربة',
          'The local model ${asStr(j['model'])} is on the server; try it from the Playground tab'));
    } else if (r.ok && asBool(j['ok'])) {
      appToast(t('النموذج يجيب: ${asStr(j['model'])} خلال ${asInt(j['latency_ms'])} م.ث', 'The model answers: ${asStr(j['model'])} in ${asInt(j['latency_ms'])} ms'));
    } else {
      appToast(r.ok ? asStr(j['error'], t('النموذج لا يجيب', 'The model does not answer')) : ragAdminCodeText(r.code, r.message), error: true);
    }
  }

  /// "Promote to Q&A": the server drafts a pair from the asked question; the sheet edits and saves it.
  Future<void> _promote(int queryId) async {
    final r = await _qa.fromQuery(queryId);
    if (!mounted) return;
    if (!r.ok) {
      return appToast(r.unavailable ? t('الإجابات المعتمدة تحتاج تحديث الخادم', 'Curated Q&A needs a server update') : qaCodeText(r.code, r.message), error: true);
    }
    final draft = qaDraftFromQuery(r.map);
    final saved = await showAppSheet<QaPair>(context, (_) => QaPairSheet(draft: draft.pair, api: _qa));
    if (saved != null) appToast(t('أُضيفت الإجابة المعتمدة', 'Q&A pair added'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      key: const ValueKey('rag.admin'),
      appBar: ScreenAppBar(helpPageId: 'admin.rag_console', title: t('لوحة المساعد الذكي', 'AI assistant console'), actions: [
        IconButton(
            tooltip: t('مستندات التطبيق', 'App documents'),
            icon: const Icon(Icons.folder_copy_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RagLibraryScreen(app: true, title: t('مستندات التطبيق', 'App documents'))))),
        IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ]),
      child: Column(children: [
        Material(
          color: c.background,
          child: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: t('نظرة عامة', 'Overview')),
            Tab(text: t('الإعدادات', 'Settings')),
            Tab(text: t('تجربة', 'Playground')),
            Tab(text: t('الأسئلة', 'Questions')),
            Tab(text: t('التنبيهات', 'Alerts')),
            Tab(text: t('رفض البوابة', 'Gate refusals')),
            if (_qaOn) Tab(text: t('الإجابات المعتمدة', 'Q&A')),
            if (_learningOn) Tab(text: t('التعلّم', 'Learning')),
            Tab(text: t('مراجعة التقييمات', 'Feedback')),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!)),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _overview == null
                ? const AppListSkeleton(items: 4, padding: EdgeInsets.all(16))
                : RagOverviewView(
                    overview: _overview!,
                    settings: _settings,
                    onPromote: _qaOn ? _promote : null,
                    onDays: (d) {
                      setState(() => _days = d);
                      _load();
                    }),
            _settings == null
                ? const AppListSkeleton(items: 4, padding: EdgeInsets.all(16))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      RagPlatformSettingsForm(settings: _settings!, onSave: _save, onTest: _test, onManageModels: _manageModels),
                      if (_settings!.extra.present) ...[
                        const SizedBox(height: 16),
                        RagExtraSettingsCard(
                            settings: _settings!.extra,
                            onSave: _saveExtra,
                            canEdit: _superAdmin,
                            onTrain: _learningOn && _superAdmin ? _trainEmbedder : null,
                            training: _training,
                            job: _embedderJob),
                      ],
                      const SizedBox(height: 16),
                      RagCacheSection(api: widget.cacheApi, saveSettings: _saveSettingsBody),
                    ]),
                  ),
            RagPlaygroundTab(api: _api),
            RagQuestionsTab(api: _api),
            RagAlertsTab(canEdit: _superAdmin),
            RagGateTab(onPromote: _qaOn ? _promote : null),
            if (_qaOn) RagQaAdminBody(scope: 'app', api: _qa),
            if (_learningOn) ParentComponent(featureKey: 'rag.learning', child: RagLearningBody(api: _learning, qaApi: _qa)),
            FeedbackReviewBody(api: widget.feedbackApi ?? FeedbackReviewApi(), canVerify: _qaOn),
          ]),
        ),
      ]),
    );
  }
}

// ── overview ─────────────────────────────────────────────────────────────────────────────────────────────────────

class RagOverviewView extends StatelessWidget {
  const RagOverviewView({super.key, required this.overview, this.settings, this.onDays, this.onPromote});
  final RagOverview overview;
  final RagAdminSettings? settings;
  final ValueChanged<int>? onDays;

  /// "Promote to Q&A" on a not-found / unhelpful row (its `query_id`); null hides the action.
  final ValueChanged<int>? onPromote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = overview;
    final s = settings;
    final modelOn = s != null && s.llmAvailable && s.effectiveGenerator == 'llm';
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppHero(
        title: t('المساعد الذكي', 'AI assistant'),
        subtitle: modelOn && s.llmLocal
            ? t('يكتب الإجابات النموذج المحلي ${s.llmModel} على الخادم نفسه — لا يغادر أي نص الخادم', 'Answers written by the local model ${s.llmModel} on the server itself — no text leaves the server')
            : modelOn
                ? t('يكتب الإجابات بالنموذج ${s.llmModel} ويراجعها مع المصادر', 'Answers written by ${s.llmModel} and checked against the sources')
                : t('بلا نموذج لغوي: الإجابات مقتطفة من المستندات مباشرة', 'No language model: answers are quoted straight from the documents'),
        icon: Icons.auto_awesome_rounded,
        stats: [
          AppHeroStat(icon: Icons.question_answer_rounded, value: '${o.answered}', label: t('إجابة', 'answers')),
          AppHeroStat(icon: Icons.check_circle_rounded, value: o.foundRate == null ? '—' : '${o.foundRate}%', label: t('وُجدت', 'found')),
          AppHeroStat(icon: Icons.thumb_up_alt_rounded, value: o.helpfulRate == null ? '—' : '${o.helpfulRate}%', label: t('مفيدة', 'helpful')),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in const [7, 30, 90]) AppChoiceChip(label: t('آخر $d يوماً', 'Last $d days'), selected: o.days == d, onTap: () => onDays?.call(d)),
      ]),
      const SizedBox(height: 12),
      if (o.monitoring != null) ...[RagHealthBlock(monitoring: o.monitoring!), const SizedBox(height: 16)],
      AppGrid(minTile: 150, children: [
        AppStatTile(icon: Icons.people_alt_rounded, label: t('سائلون', 'Askers'), value: o.askers),
        AppStatTile(icon: Icons.timer_outlined, label: t('زمن الإجابة (وسيط)', 'Answer time (median)'), value: o.p50 == null ? '—' : '${(o.p50! / 1000).toStringAsFixed(1)} s'),
        AppStatTile(icon: Icons.hourglass_top_rounded, label: t('في الانتظار', 'Waiting'), value: o.queueWaiting, color: o.queueWaiting > 10 ? c.warning : null),
        AppStatTile(icon: Icons.error_outline_rounded, label: t('فشلت', 'Failed'), value: o.failed, color: o.failed > 0 ? c.danger : null),
        AppStatTile(icon: Icons.description_outlined, label: t('مستندات جاهزة', 'Ready documents'), value: o.readyDocuments),
        AppStatTile(icon: Icons.quiz_outlined, label: t('أسئلة امتحانات مولّدة', 'Exam questions generated'), value: o.draftQuestions),
        if (o.qaPairs > 0 || o.qaDirect > 0)
          AppStatTile(icon: Icons.verified_rounded, label: t('إجابات معتمدة مباشرة', 'Direct Q&A answers'), value: o.qaDirect, color: c.success),
      ]),
      const SizedBox(height: 16),
      AppSectionTitle(t('أين يُسأل', 'Where questions come from')),
      AppCard(
        child: Column(children: [
          for (final e in o.contexts.entries)
            _RateRow(
                label: switch (e.key) { 'app' => t('مساعد التطبيق', 'App assistant'), 'org' => t('التطبيق داخل مؤسسة', 'App inside an organization'), _ => t('مستندات المؤسسات والمقررات', 'Organization / course documents') },
                count: e.value['asked'] ?? 0,
                rate: ragRate(e.value['found'] ?? 0, e.value['asked'] ?? 0)),
        ]),
      ),
      const SizedBox(height: 12),
      AppSectionTitle(t('كيف كُتبت الإجابات', 'How answers were written')),
      AppCard(
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in o.generators.entries) AppStatChip(icon: Icons.bolt_rounded, value: '${e.value}', label: ragGeneratorLabel(e.key)),
        ]),
      ),
      const SizedBox(height: 12),
      AppSectionTitle(t('أسئلة بلا إجابة', 'Questions without an answer'), subtitle: t('أضف مستنداً يجيب عنها أو حسّن الموجود', 'Add a document that answers them, or improve the existing ones')),
      if (o.notFound.isEmpty)
        AppEmpty(icon: Icons.task_alt_rounded, title: t('كل الأسئلة وُجدت لها إجابة', 'Every question found its answer'))
      else
        RagAskedList(rows: o.notFound, tone: c.warning, onPromote: onPromote),
      if (o.hedged.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppSectionTitle(t('أُجيبت بأقرب ما وُجد', 'Answered with the closest match'),
            subtitle: t('المستندات تجيب عنها جزئياً: أكمل القسم أو اعتمد إجابة', 'The documents half-answer them: complete the section or promote an answer')),
        RagAskedList(rows: o.hedged, tone: c.primary, onPromote: onPromote),
      ],
      const SizedBox(height: 12),
      AppSectionTitle(t('إجابات لم تُفد', 'Unhelpful answers')),
      if (o.unhelpful.isEmpty)
        AppEmpty(icon: Icons.thumb_up_alt_outlined, title: t('لا شكاوى من الإجابات', 'No answer was rated unhelpful'))
      else
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final u in o.unhelpful.take(10)) ...[
              Text(asStr(u['question']), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              Text(asStr(u['answer']), maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
              if (asStr(u['comment']).isNotEmpty) Text('«${asStr(u['comment'])}»', style: appText(12, c: c.danger)),
              if (onPromote != null && asInt(u['query_id']) > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                      onPressed: () => onPromote!(asInt(u['query_id'])),
                      icon: const Icon(Icons.playlist_add_check_circle_outlined, size: 18),
                      label: Text(t('اعتمد إجابة', 'Promote to Q&A'))),
                ),
              const Divider(height: 16),
            ],
          ]),
        ),
    ]);
  }
}

/// The overview's "Health" block (Track E.7): four trend tiles (questions, no-answer rate, cache hits, direct Q&A),
/// questions per day, and the answer time p50 / p95 per path. Plain values: the layout harness pumps it.
/// The overview's grouped questions (`not_found`, `hedged`): count · question · context, and "Promote to Q&A".
class RagAskedList extends StatelessWidget {
  const RagAskedList({super.key, required this.rows, required this.tone, this.onPromote});
  final List<Map<String, dynamic>> rows;
  final Color tone;
  final ValueChanged<int>? onPromote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(children: [
        for (final r in rows.take(10))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, backgroundColor: tone.withValues(alpha: .15), child: Text('${asInt(r['count'])}', style: appText(12, w: FontWeight.w800, c: tone))),
            title: Text(asStr(r['question']), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(asStr(r['context']) == 'docs' ? t('مؤسسة ${r['org_id'] ?? ''}', 'Organization ${r['org_id'] ?? ''}') : t('مساعد التطبيق', 'App assistant')),
            trailing: onPromote == null || asInt(r['query_id']) <= 0
                ? null
                : IconButton(
                    tooltip: t('اعتمد إجابة لهذا السؤال', 'Promote to Q&A'),
                    icon: Icon(Icons.playlist_add_check_circle_outlined, color: appInk(context, c.primary)),
                    onPressed: () => onPromote!(asInt(r['query_id']))),
          ),
      ]),
    );
  }
}

class RagHealthBlock extends StatelessWidget {
  const RagHealthBlock({super.key, required this.monitoring});
  final RagMonitoring monitoring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = monitoring;
    final palette = appChartPalette(context);
    final hint = t('مقارنة بالنصف الأول من الفترة', 'vs the first half of the period');
    final recent = m.recent(14);
    return LayoutBuilder(builder: (context, box) {
    // a wide window: the four tiles fill the row and the latency table takes the width of two of them
    final wide = box.maxWidth >= 1100;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('الصحة', 'Health'), subtitle: t('كيف أُجيب كل سؤال خلال آخر ${m.days} يوماً', 'How every question of the last ${m.days} days was answered')),
      RagTileGrid(minTile: 160, children: [
        AppTrendTile(
            label: t('الأسئلة', 'Questions'), value: appCompactNumber(m.questions), delta: m.questionsDelta, spark: m.questionsSpark,
            deltaHint: hint, icon: Icons.forum_rounded, color: palette[0]),
        AppTrendTile(
            label: t('بلا إجابة', 'No answer'), value: ragPctText(m.noAnswerRate), delta: m.noAnswerDelta, spark: m.noAnswerSpark,
            upIsGood: false, deltaHint: hint, icon: Icons.search_off_rounded, color: palette[1 % palette.length]),
        AppTrendTile(
            label: t('من الذاكرة المؤقتة', 'Cache hits'), value: ragPctText(m.cacheHitRate), delta: m.cacheDelta, spark: m.cacheSpark,
            deltaHint: hint, icon: Icons.bolt_rounded, color: palette[2 % palette.length]),
        AppTrendTile(
            label: t('رد معتمد مباشر', 'Direct Q&A'), value: ragPctText(m.qaDirectRate), delta: m.qaDirectDelta, spark: m.qaDirectSpark,
            deltaHint: hint, icon: Icons.verified_rounded, color: palette[3 % palette.length]),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _RatePill(icon: Icons.lightbulb_outline_rounded, value: ragPctText(m.qaExampleRate), label: t('استعان بإجابة معتمدة', 'helped by a Q&A pair')),
        _RatePill(icon: Icons.undo_rounded, value: ragPctText(m.fallbackRate), label: t('بديل عن النموذج', 'model fallback')),
        _RatePill(icon: Icons.thumb_up_alt_rounded, value: ragPctText(m.helpfulRate), label: t('مفيدة من المقيَّمة', 'rated helpful')),
        if (m.deliveryReported > 0)
          _RatePill(icon: Icons.sync_rounded, value: ragPctText(m.pollRate), label: t('وصلت بالاستطلاع لا بالبث', 'delivered by polling, not the stream')),
      ]),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('الأسئلة يومياً', 'Questions per day'), style: appText(14, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: 12),
          if (m.hasActivity)
            AppBarChart(
              title: t('الأسئلة يومياً', 'Questions per day'),
              labels: [for (final d in recent) d.dayLabel],
              series: [
                AppChartSeries(t('الأسئلة', 'Questions'), [for (final d in recent) d.questions.toDouble()]),
                AppChartSeries(t('بلا إجابة', 'No answer'), [for (final d in recent) d.noAnswer.toDouble()]),
              ],
            )
          else
            Text(t('لا أسئلة في هذه الفترة', 'No questions in this period'), style: appText(13, c: c.textLight)),
        ]),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? box.maxWidth / 2 - 6 : double.infinity),
          child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('زمن الإجابة حسب المسار', 'Answer time by path'), style: appText(14, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: 8),
          RagLatencyRow(label: t('المسار', 'Path'), questions: t('أسئلة', 'Asked'), p50: 'p50', p95: 'p95', header: true),
          for (final p in ragPaths)
            RagLatencyRow(
                label: ragPathLabel(p), questions: '${m.byPath[p]?.questions ?? 0}', p50: ragMsText(m.byPath[p]?.p50), p95: ragMsText(m.byPath[p]?.p95)),
          const Divider(height: 12),
          RagLatencyRow(label: t('الكل', 'All'), questions: '${m.questions}', p50: ragMsText(m.p50), p95: ragMsText(m.p95), header: true),
        ]),
          ),
        ),
      ),
    ]);
    });
  }
}

/// A secondary rate: value + label in a pill whose label wraps on a narrow screen (AppStatChip never wraps).
class _RatePill extends StatelessWidget {
  const _RatePill({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: appInk(context, c.primary)),
        const SizedBox(width: 6),
        Text(value, style: appText(13, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(width: 5),
        Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.textMedium))),
      ]),
    );
  }
}

/// One row of the latency table: a label that wraps, three figures at the row's end, each laid out left to right
/// (a figure and its unit keep their order in Arabic).
class RagLatencyRow extends StatelessWidget {
  const RagLatencyRow({super.key, required this.label, required this.questions, required this.p50, required this.p95, this.header = false});
  final String label, questions, p50, p95;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final st = appText(12.5, w: header ? FontWeight.w800 : FontWeight.w500, c: header ? c.textDark : c.textMedium);
    Widget cell(String v) => SizedBox(
        width: 58,
        child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(v, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: st)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: st)),
        cell(questions),
        cell(p50),
        cell(p95),
      ]),
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({required this.label, required this.count, required this.rate});
  final String label;
  final int count;
  final int? rate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: appText(13, c: c.textDark))),
        Text('$count', style: appText(13, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: AppProgressBar(value: rate?.toDouble() ?? 0, color: appScoreColor(context, rate?.toDouble()))),
        const SizedBox(width: 6),
        SizedBox(width: 38, child: Text(rate == null ? '—' : '$rate%', textAlign: TextAlign.end, style: appText(12, c: c.textMedium))),
      ]),
    );
  }
}

// ── settings ─────────────────────────────────────────────────────────────────────────────────────────────────────

class RagPlatformSettingsForm extends StatefulWidget {
  const RagPlatformSettingsForm({super.key, required this.settings, required this.onSave, this.onTest, this.onManageModels});
  final RagAdminSettings settings;
  final ValueChanged<RagAdminSettings> onSave;
  final VoidCallback? onTest;

  /// Opens the AI Models page. The model name fields moved there (the keys stay in the settings and are sent
  /// unchanged); null keeps the two fields as they were (tests, an older flow).
  final VoidCallback? onManageModels;

  @override
  State<RagPlatformSettingsForm> createState() => _RagPlatformSettingsFormState();
}

class _RagPlatformSettingsFormState extends State<RagPlatformSettingsForm> {
  late RagAdminSettings _s = widget.settings;
  late final _name = TextEditingController(text: _s.assistantName);
  late final _ar = TextEditingController(text: _s.personaAr);
  late final _en = TextEditingController(text: _s.personaEn);
  late final _model = TextEditingController(text: _s.model);
  late final _fast = TextEditingController(text: _s.fastModel);
  late final _retention = TextEditingController(text: '${_s.conversationRetentionDays}');

  @override
  void dispose() {
    for (final c in [_name, _ar, _en, _model, _fast, _retention]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _title(BuildContext context, String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: AppSectionTitle(s));

  DropdownMenuItem<String> _item(String v, String label) => DropdownMenuItem(value: v, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));

  String _modelText(RagAdminSettings s) {
    if (!s.llmAvailable) {
      return t('لا يوجد نموذج لغوي على الخادم (RAG_LLM_PROVIDER=none). حتى ضبطه تبقى الإجابات مقتطفة.',
          'No language model on the server (RAG_LLM_PROVIDER=none). Until one is set, answers stay quoted.');
    }
    if (s.llmLocal && !s.llmFilesOk) {
      return t('النموذج المحلي ${s.llmModel} مضبوط لكن ملفاته غير موجودة على الخادم (scripts/models/fetch_models.py). حتى تحميلها تبقى الإجابات مقتطفة. ${s.llmFilesError}',
          'The local model ${s.llmModel} is configured but its files are not on the server (scripts/models/fetch_models.py). Until they are fetched, answers stay quoted. ${s.llmFilesError}');
    }
    if (s.llmLocal) {
      return t('نموذج محلي مفتوح المصدر على الخادم: ${s.llmModel} — لا يغادر أي نص الخادم، ولا حاجة لموافقة المؤسسات',
          'Open-weight model on the server: ${s.llmModel} — no text leaves the server, no organization consent needed');
    }
    return t('النموذج متصل: ${s.llmProvider} · ${s.llmModel}${s.llmExternal ? ' (مزوّد خارجي)' : ''}',
        'Model connected: ${s.llmProvider} · ${s.llmModel}${s.llmExternal ? ' (external provider)' : ''}');
  }

  List<DropdownMenuItem<String>> _efforts({bool xhigh = false}) => [
        _item('low', t('منخفض (أسرع وأرخص)', 'Low (faster, cheaper)')),
        _item('medium', t('متوسط', 'Medium')),
        _item('high', t('عالٍ', 'High')),
        if (xhigh) _item('xhigh', t('عالٍ جداً', 'Extra high')),
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _s;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
          icon: s.llmAvailable && (!s.llmLocal || s.llmFilesOk) ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
          color: s.llmAvailable && (!s.llmLocal || s.llmFilesOk) ? c.success : c.warning,
          text: _modelText(s),
          action: widget.onTest == null || !s.llmAvailable ? null : TextButton(onPressed: widget.onTest, child: Text(t('اختبر', 'Test')))),
      _title(context, t('الإجابات', 'Answers')),
      AppDropdown<String>(
        value: s.generator,
        decoration: InputDecoration(labelText: t('كيف تُكتب الإجابات', 'How answers are written')),
        items: [_item('llm', t('يكتبها النموذج من المصادر ويراجعها', 'Written by the model from the sources and checked')), _item('extractive', t('اقتباس مباشر من المستندات (بلا نموذج)', 'Quoted straight from the documents (no model)'))],
        onChanged: (v) => setState(() => _s = _s.copyWith(generator: v)),
      ),
      const SizedBox(height: 8),
      if (s.llmExternal || !s.llmAvailable)
        AppSwitchTile(
            title: t('المؤسسات تستخدم النموذج افتراضياً', 'Organizations use the model by default'),
            subtitle: t('تُرسل مقتطفات مستندات المؤسسة إلى المزوّد ما لم تختر المؤسسة الاقتباس المباشر', 'Organization excerpts go to the provider unless the organization opts for quoting'),
            value: s.allowExternalDefault,
            onChanged: (v) => setState(() => _s = _s.copyWith(allowExternalDefault: v))),
      AppDropdown<String>(
        value: s.answerStyle,
        decoration: InputDecoration(labelText: t('أسلوب الإجابة', 'Answer style')),
        items: [_item('concise', t('مختصر', 'Concise')), _item('balanced', t('متوازن', 'Balanced')), _item('detailed', t('مفصّل', 'Detailed'))],
        onChanged: (v) => setState(() => _s = _s.copyWith(answerStyle: v)),
      ),
      const SizedBox(height: 8),
      AppField(controller: _name, label: t('اسم المساعد (اختياري)', 'Assistant name (optional)'), onChanged: (v) => _s = _s.copyWith(assistantName: v)),
      const SizedBox(height: 8),
      AppField(controller: _ar, label: t('توجيهات إضافية (بالعربية)', 'Extra guidance (Arabic)'), hint: t('النبرة، ما يُشدَّد عليه…', 'Tone, what to stress…'), maxLines: 3, onChanged: (v) => _s = _s.copyWith(personaAr: v)),
      const SizedBox(height: 8),
      AppField(controller: _en, label: t('توجيهات إضافية (بالإنجليزية)', 'Extra guidance (English)'), maxLines: 3, ltr: true, onChanged: (v) => _s = _s.copyWith(personaEn: v)),
      _title(context, t('الوكلاء', 'Agents')),
      AppSwitchTile(
          title: t('المخطِّط: فهم السؤال والبحث بلغتين', 'Planner: understand the question, search in both languages'),
          value: s.planQueries, onChanged: (v) => setState(() => _s = _s.copyWith(planQueries: v))),
      AppSwitchTile(
          title: t('المراجع: التحقق من كل جملة مع مصدرها', 'Verifier: check every sentence against its source'),
          value: s.verifyAnswers, onChanged: (v) => setState(() => _s = _s.copyWith(verifyAnswers: v))),
      AppSwitchTile(
          title: t('الترحيب بلا مكتبة', 'Greetings answered without the library'),
          value: s.smallTalk, onChanged: (v) => setState(() => _s = _s.copyWith(smallTalk: v))),
      AppSwitchTile(
          title: t('مخطِّط الامتحانات: اختيار الموضوعات الجديرة', 'Exam planner: pick the topics worth examining'),
          value: s.examPlanner, onChanged: (v) => setState(() => _s = _s.copyWith(examPlanner: v))),
      AppSwitchTile(
          title: t('مراجع الامتحانات: تصحيح الأسئلة الضعيفة وحذفها', 'Exam reviewer: fix or drop weak questions'),
          value: s.examReviewer, onChanged: (v) => setState(() => _s = _s.copyWith(examReviewer: v))),
      Row(children: [
        Expanded(child: Text(t('أسئلة سابقة تُؤخذ بالحسبان', 'Earlier turns the writer sees'), style: appText(13, c: c.textDark))),
        IconButton.outlined(onPressed: s.conversationTurns > 0 ? () => setState(() => _s = _s.copyWith(conversationTurns: s.conversationTurns - 1)) : null, icon: const Icon(Icons.remove_rounded, size: 18)),
        SizedBox(width: 36, child: Text('${s.conversationTurns}', textAlign: TextAlign.center, style: appText(15, w: FontWeight.w800, c: c.textDark))),
        IconButton.outlined(onPressed: s.conversationTurns < 10 ? () => setState(() => _s = _s.copyWith(conversationTurns: s.conversationTurns + 1)) : null, icon: const Icon(Icons.add_rounded, size: 18)),
      ]),
      Row(children: [
        Expanded(child: Text(t('أقصى عدد للمصادر في الإجابة', 'Sources quoted per answer'), style: appText(13, c: c.textDark))),
        IconButton.outlined(onPressed: s.maxCitations > 1 ? () => setState(() => _s = _s.copyWith(maxCitations: s.maxCitations - 1)) : null, icon: const Icon(Icons.remove_rounded, size: 18)),
        SizedBox(width: 36, child: Text('${s.maxCitations}', textAlign: TextAlign.center, style: appText(15, w: FontWeight.w800, c: c.textDark))),
        IconButton.outlined(onPressed: s.maxCitations < 8 ? () => setState(() => _s = _s.copyWith(maxCitations: s.maxCitations + 1)) : null, icon: const Icon(Icons.add_rounded, size: 18)),
      ]),
      const SizedBox(height: 8),
      AppField(
          controller: _retention,
          label: t('مدة الاحتفاظ بالمحادثات (أيام)', 'Keep chats for (days)'),
          keyboard: TextInputType.number,
          ltr: true,
          onChanged: (v) {
            final n = int.tryParse(v.trim());
            if (n != null) _s = _s.copyWith(conversationRetentionDays: n.clamp(0, RagAdminSettings.maxRetentionDays));
          }),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
        child: Text(t('تُحذف تلقائياً المحادثات التي لم يُطرح فيها سؤال جديد طوال هذه المدة؛ 0 يحتفظ بها دائماً',
            'Chats with no new question for this many days are deleted automatically; 0 keeps them'), style: appText(12, c: c.textLight)),
      ),
      if (s.light) ...[
        _title(context, t('النموذج المحلي', 'Local model')),
        AppBanner(
            icon: Icons.memory_rounded,
            color: appInk(context, c.primary),
            text: t('${s.llmModel} يعمل داخل الخادم بلا أي مزوّد خارجي. مع نموذج صغير يُكتب الجواب في نداء واحد، ويقوم الكود بالتخطيط والتحقق من الاستشهادات؛ لذلك لا تظهر خيارات الجهد هنا. المخطِّط والمراجع في الامتحانات يعملان ككود أيضاً.${s.llmTokensPerS == null ? '' : ' السرعة: ${s.llmTokensPerS!.toStringAsFixed(0)} رمز/ث.'}',
                '${s.llmModel} runs inside the server with no external provider. With a small model the answer is written in one call and the code does the planning and the citation checks, so there are no effort knobs here. The exam planner and reviewer run as code too.${s.llmTokensPerS == null ? '' : ' Speed: ${s.llmTokensPerS!.toStringAsFixed(0)} tokens/s.'}')),
      ] else ...[
        _title(context, t('الجهد والنماذج', 'Effort and models')),
        AppDropdown<String>(value: s.effortAnswer, decoration: InputDecoration(labelText: t('جهد كاتب الإجابة', 'Writer effort')), items: _efforts(), onChanged: (v) => setState(() => _s = _s.copyWith(effortAnswer: v))),
        const SizedBox(height: 8),
        AppDropdown<String>(value: s.effortLight, decoration: InputDecoration(labelText: t('جهد المخطِّط والمراجع', 'Planner / verifier effort')), items: _efforts(), onChanged: (v) => setState(() => _s = _s.copyWith(effortLight: v))),
        const SizedBox(height: 8),
        AppDropdown<String>(value: s.effortExam, decoration: InputDecoration(labelText: t('جهد كاتب الامتحانات', 'Exam writer effort')), items: _efforts(xhigh: true), onChanged: (v) => setState(() => _s = _s.copyWith(effortExam: v))),
        const SizedBox(height: 8),
        if (widget.onManageModels != null)
          AppActionCard(
              key: const ValueKey('manage_models'),
              icon: Icons.memory_rounded,
              title: t('إدارة النماذج', 'Manage models'),
              subtitle: t('اختيار نموذج المحادثة وتوليد الامتحانات والتصحيح، وسرعته ودقته، من صفحة النماذج',
                  'Pick the chat, exam-generation and grading models, with their speed and accuracy, on the Models page'),
              onTap: widget.onManageModels!)
        else ...[
          AppField(controller: _model, label: t('النموذج (فارغ = إعداد الخادم ${s.llmModel})', 'Model (empty = the server\'s ${s.llmModel})'), ltr: true, onChanged: (v) => _s = _s.copyWith(model: v)),
          const SizedBox(height: 8),
          AppField(controller: _fast, label: t('النموذج الأسرع للخطوات الخفيفة (فارغ = ${s.llmFastModel})', 'Fast model for the light steps (empty = ${s.llmFastModel})'), ltr: true, onChanged: (v) => _s = _s.copyWith(fastModel: v)),
        ],
      ],
      const SizedBox(height: 16),
      AppPrimaryButton(label: t('حفظ الإعدادات', 'Save settings'), icon: Icons.save_rounded, onPressed: () => widget.onSave(_s)),
    ]);
  }
}

// ── playground ───────────────────────────────────────────────────────────────────────────────────────────────────

class RagPlaygroundTab extends StatefulWidget {
  const RagPlaygroundTab({super.key, required this.api});
  final RagAdminApi api;

  @override
  State<RagPlaygroundTab> createState() => _RagPlaygroundTabState();
}

class _RagPlaygroundTabState extends State<RagPlaygroundTab> {
  final _q = TextEditingController();
  final _org = TextEditingController();
  bool _app = true;
  bool _busy = false;
  RagAnswer? _answer;
  RagTrace? _trace;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty || _busy) return;
    final org = int.tryParse(_org.text.trim());
    setState(() { _busy = true; _error = null; _answer = null; _trace = null; });
    final r = await widget.api.playground(q, app: _app, orgId: org);
    if (!mounted) return;
    if (!r.ok) return setState(() { _busy = false; _error = ragAdminCodeText(r.code, r.message); });
    final done = await widget.api.waitFor(asInt(asMap(r.map)['id']));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done.ok) {
        _answer = RagAnswer.fromJson(done.map);
        _trace = RagTrace.fromJson(asMap(done.map)['trace']);
      } else {
        _error = ragAdminCodeText(done.code, done.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppBanner(icon: Icons.science_outlined, color: appInk(context, c.primary), text: t('اسأل كما يسأل العضو وشاهد كل خطوة: الفهم، الاستعلامات، النتائج، الكتابة والمراجعة.', 'Ask as a member would and see every step: understanding, queries, hits, writing and verification.')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppChoiceChip(label: t('مساعد التطبيق', 'App assistant'), selected: _app, onTap: () => setState(() => _app = true)),
        AppChoiceChip(label: t('مستندات مؤسسة', 'Organization documents'), selected: !_app, onTap: () => setState(() => _app = false)),
      ]),
      const SizedBox(height: 8),
      AppField(controller: _org, label: _app ? t('رقم المؤسسة (اختياري: التطبيق داخل مؤسسة)', 'Organization id (optional: the app inside an organization)') : t('رقم المؤسسة', 'Organization id'), keyboard: TextInputType.number, ltr: true),
      const SizedBox(height: 8),
      EnterSubmits(onSubmit: _run, child: AppField(controller: _q, label: t('السؤال', 'Question'), maxLines: 3)),
      const SizedBox(height: 10),
      AppPrimaryButton(label: t('اسأل', 'Ask'), icon: Icons.play_arrow_rounded, busy: _busy, onPressed: _busy ? null : _run),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!)),
      if (_answer != null) ...[
        const SizedBox(height: 14),
        AppSectionTitle(t('الإجابة', 'Answer'), subtitle: '${ragGeneratorLabel(_answer!.generator)} · ${_answer!.generator}'),
        AppCard(child: RagAnswerBody(text: _answer!.answer)),
        if (_answer!.citations.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final ci in _answer!.citations) AppInfoRow(Icons.format_quote_rounded, '[${ci.n}] ${ci.label}'),
        ],
        if (_trace != null && !_trace!.isEmpty) ...[const SizedBox(height: 14), RagTraceView(trace: _trace!)],
      ],
    ]);
  }
}

/// The pipeline trace of one answer: plan, steps with models and tokens, the verdict, the retrieved chunks.
class RagTraceView extends StatelessWidget {
  const RagTraceView({super.key, required this.trace});
  final RagTrace trace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tr = trace;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('المسار', 'Trace'), subtitle: '${(tr.totalMs / 1000).toStringAsFixed(1)} s'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (tr.plan.isNotEmpty) ...[
            Text('${t('القصد', 'Intent')}: ${tr.intent} · ${t('اللغة', 'Language')}: ${asStr(tr.plan['lang'])}', style: appText(12.5, c: c.textMedium)),
            if (asStr(tr.plan['standalone']).isNotEmpty) Text('${t('السؤال المستقل', 'Standalone')}: ${asStr(tr.plan['standalone'])}', style: appText(12.5, c: c.textMedium)),
            if (tr.queries.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final q in tr.queries) AppBadgePill(q, icon: Icons.search_rounded)]),
            ],
            const Divider(height: 16),
          ],
          for (final s in tr.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(asStr(s['error']).isNotEmpty ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 16, color: asStr(s['error']).isNotEmpty ? c.danger : c.success),
                const SizedBox(width: 6),
                Expanded(child: Text(ragTraceStepText(s), style: appText(12.5, c: c.textDark))),
              ]),
            ),
          if (tr.fallback != null) ...[const SizedBox(height: 6), AppBanner(icon: Icons.undo_rounded, color: c.warning, text: '${t('بديل', 'Fallback')}: ${tr.fallback}')],
          if (tr.verify.isNotEmpty && tr.verify['issues'] is List && (tr.verify['issues'] as List).isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final i in tr.verify['issues'] as List) AppInfoRow(Icons.rule_rounded, '$i'),
          ],
          if (tr.hits.isNotEmpty) ...[
            const Divider(height: 16),
            Text(t('أفضل النتائج (مقطع · مستند · تشابه · تطابق لفظي · إعادة ترتيب)', 'Top hits (chunk · document · cosine · lexical · rerank)'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
            for (final h in tr.hits.take(8))
              Text('#${asInt(h['chunk_id'])} · d${asInt(h['document_id'])} · ${asDouble(h['vec_sim']).toStringAsFixed(2)} · ${asDouble(h['lexical']).toStringAsFixed(2)} · ${h['rerank'] == null ? '—' : asDouble(h['rerank']).toStringAsFixed(1)}',
                  style: appText(11.5, c: c.textLight)),
          ],
        ]),
      ),
    ]);
  }
}

// ── questions ────────────────────────────────────────────────────────────────────────────────────────────────────

class RagQuestionsTab extends StatefulWidget {
  const RagQuestionsTab({super.key, required this.api});
  final RagAdminApi api;

  @override
  State<RagQuestionsTab> createState() => _RagQuestionsTabState();
}

class _RagQuestionsTabState extends State<RagQuestionsTab> {
  final _search = TextEditingController();
  String _filter = 'all'; // all | notfound | unhelpful | app
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await widget.api.queries(
        found: _filter == 'notfound' ? false : null, helpful: _filter == 'unhelpful' ? false : null, app: _filter == 'app' ? true : null,
        q: _search.text.trim().isEmpty ? null : _search.text.trim());
    if (!mounted) return;
    setState(() {
      _items = r.ok ? asMapList(asMap(r.map)['items']) : const [];
      _error = r.ok ? null : ragAdminCodeText(r.code, r.message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          EnterSubmits(onSubmit: _load, child: AppField(controller: _search, label: t('ابحث في الأسئلة', 'Search the questions'), onSubmitted: (_) => _load())),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in const ['all', 'notfound', 'unhelpful', 'app'])
              AppChoiceChip(
                  label: switch (f) { 'notfound' => t('بلا إجابة', 'Not found'), 'unhelpful' => t('غير مفيدة', 'Unhelpful'), 'app' => t('مساعد التطبيق', 'App assistant'), _ => t('الكل', 'All') },
                  selected: _filter == f,
                  onTap: () {
                    setState(() => _filter = f);
                    _load();
                  }),
          ]),
        ]),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(16), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!)),
      Expanded(
        child: _items == null
            ? const AppListSkeleton(items: 5, padding: EdgeInsets.all(16))
            : _items!.isEmpty
                ? AppEmpty(icon: Icons.question_answer_outlined, title: t('لا أسئلة', 'No questions'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items!.length,
                    itemBuilder: (_, i) => RagAdminQueryTile(item: _items![i]),
                  ),
      ),
    ]);
  }
}

/// One question in the admin's list, expandable to its answer and trace.
class RagAdminQueryTile extends StatelessWidget {
  const RagAdminQueryTile({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = RagAnswer.fromJson(item);
    final tr = RagTrace.fromJson(item['trace']);
    final ctx = asStr(item['context']);
    final badge = a.found == true ? AppBadgePill(t('وُجدت', 'found'), color: c.success, icon: Icons.check_rounded) : AppBadgePill(t('بلا إجابة', 'not found'), color: c.warning, icon: Icons.search_off_rounded);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(a.question, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
          subtitle: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            badge,
            AppBadgePill(ctx == 'app' ? t('التطبيق', 'App') : ctx == 'org' ? t('التطبيق + مؤسسة ${a.orgId}', 'App + org ${a.orgId}') : t('مستندات ${a.orgId ?? ''}', 'Documents ${a.orgId ?? ''}')),
            AppBadgePill(ragGeneratorLabel(a.generator)),
            if (a.helpful == false) AppBadgePill(t('غير مفيدة', 'unhelpful'), color: c.danger, icon: Icons.thumb_down_alt_outlined),
            if (a.helpful == true) AppBadgePill(t('مفيدة', 'helpful'), color: c.success, icon: Icons.thumb_up_alt_outlined),
            Text('#${a.id} · ${t('مستخدم', 'user')} ${asInt(item['user_id'])}', style: appText(11, c: c.textLight)),
          ]),
          children: [
            Align(alignment: AlignmentDirectional.centerStart, child: RagAnswerBody(text: a.answer)),
            if (asStr(item['feedback_comment']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('«${asStr(item['feedback_comment'])}»', style: appText(12, c: c.danger))),
            if (!tr.isEmpty) ...[const SizedBox(height: 10), RagTraceView(trace: tr)],
          ],
        ),
      ),
    );
  }
}
