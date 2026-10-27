// The RAG admin console (D-012): the Super Admin's control room of the assistant — /api/v1/rag/admin/…
//
//   GET/PUT /admin/settings   the platform settings (generator, consent default, style, persona, agents, models) +
//                             the model's status; PUT takes any subset (422 bad_setting)
//   POST    /admin/llm/test   a one-word completion against the provider → {ok, model, latency_ms | error}
//   GET     /admin/overview?days=   questions per day, found / helpful rates, by context, generators, latency, the
//                             questions most often not found, recent unhelpful answers, documents, queue, exam drafts
//   GET     /admin/queries?app=&org_id=&found=&helpful=&q=&limit=   browse questions with their traces
//   GET     /admin/queries/{id} · POST /admin/playground {question, app, org_id?, course_id?} → 202 (poll the query)
//   GET     /admin/exam-drafts?limit=   recent drafts with their review summaries
//
// Pure, unit-tested: [RagAdminSettings], [RagOverview], [RagTrace], [ragRate], [ragGeneratorLabel], [ragTraceStepText].
// Presentational, under the layout harness: [RagOverviewView], [RagPlatformSettingsForm], [RagTraceView],
// [RagAdminQueryTile]. [RagAdminConsole] owns the calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, asStr, t;
import '../exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'rag_chat.dart';
import 'rag_chat_screen.dart' show RagAnswerBody;
import 'rag_library.dart' show ragLibraryCodeText;
import 'rag_library_screen.dart' show RagLibraryScreen;

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
  });
  final String generator; // llm | extractive
  final bool allowExternalDefault;
  final String answerStyle; // concise | balanced | detailed
  final String assistantName, personaAr, personaEn;
  final int conversationTurns, maxCitations;
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
    int? conversationTurns, bool? planQueries, bool? verifyAnswers, bool? smallTalk, bool? examPlanner, bool? examReviewer,
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
      );
}

class RagOverview {
  const RagOverview({
    this.days = 30, this.asked = 0, this.answered = 0, this.found = 0, this.failed = 0, this.pending = 0, this.rated = 0, this.helpful = 0,
    this.askers = 0, this.p50, this.p90, this.byDay = const [], this.contexts = const {}, this.generators = const {}, this.notFound = const [],
    this.unhelpful = const [], this.documents = const [], this.queueWaiting = 0, this.drafts = 0, this.draftQuestions = 0, this.draftsLlm = 0,
  });
  final int days, asked, answered, found, failed, pending, rated, helpful, askers;
  final int? p50, p90;
  final List<Map<String, dynamic>> byDay, notFound, unhelpful, documents;
  final Map<String, Map<String, int>> contexts;
  final Map<String, int> generators;
  final int queueWaiting, drafts, draftQuestions, draftsLlm;

  factory RagOverview.fromJson(Map<String, dynamic> j) {
    final tot = asMap(j['totals']);
    final lat = asMap(j['latency_ms']);
    final ctx = asMap(j['contexts']);
    final gens = asMap(j['generators']);
    final q = asMap(j['queue']);
    final ed = asMap(j['exam_drafts']);
    return RagOverview(
      days: asInt(j['days'], 30),
      asked: asInt(tot['asked']), answered: asInt(tot['answered']), found: asInt(tot['found']), failed: asInt(tot['failed']),
      pending: asInt(tot['pending']), rated: asInt(tot['rated']), helpful: asInt(tot['helpful']), askers: asInt(tot['askers']),
      p50: lat['p50'] == null ? null : asInt(lat['p50']), p90: lat['p90'] == null ? null : asInt(lat['p90']),
      byDay: asMapList(j['by_day']), notFound: asMapList(j['not_found']), unhelpful: asMapList(j['unhelpful']), documents: asMapList(j['documents']),
      contexts: {for (final e in ctx.entries) e.key: {for (final x in asMap(e.value).entries) x.key: asInt(x.value)}},
      generators: {for (final e in gens.entries) e.key: asInt(e.value)},
      queueWaiting: asInt(q['waiting']),
      drafts: asInt(ed['total']), draftQuestions: asInt(ed['questions']), draftsLlm: asInt(ed['llm']),
    );
  }

  /// 0–100, null when nothing to rate.
  int? get foundRate => ragRate(found, answered);
  int? get helpfulRate => ragRate(helpful, rated);

  int get readyDocuments => documents.where((d) => d['status'] == 'ready').fold(0, (n, d) => n + asInt(d['count']));
}

/// A percentage of [part] over [whole] (null when [whole] is 0).
int? ragRate(int part, int whole) => whole <= 0 ? null : (part * 100 / whole).round();

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
  const RagAdminConsole({super.key, this.api});
  final RagAdminApi? api;

  @override
  State<RagAdminConsole> createState() => _RagAdminConsoleState();
}

class _RagAdminConsoleState extends State<RagAdminConsole> with SingleTickerProviderStateMixin {
  late final RagAdminApi _api = widget.api ?? RagAdminApi();
  late final TabController _tabs = TabController(length: 4, vsync: this);
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
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rs = await Future.wait([_api.overview(days: _days), _api.settings()]);
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      key: const ValueKey('rag.admin'),
      appBar: ScreenAppBar(title: t('لوحة المساعد الذكي', 'AI assistant console'), actions: [
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
                    onDays: (d) {
                      setState(() => _days = d);
                      _load();
                    }),
            _settings == null
                ? const AppListSkeleton(items: 4, padding: EdgeInsets.all(16))
                : SingleChildScrollView(padding: const EdgeInsets.all(16), child: RagPlatformSettingsForm(settings: _settings!, onSave: _save, onTest: _test)),
            RagPlaygroundTab(api: _api),
            RagQuestionsTab(api: _api),
          ]),
        ),
      ]),
    );
  }
}

// ── overview ─────────────────────────────────────────────────────────────────────────────────────────────────────

class RagOverviewView extends StatelessWidget {
  const RagOverviewView({super.key, required this.overview, this.settings, this.onDays});
  final RagOverview overview;
  final RagAdminSettings? settings;
  final ValueChanged<int>? onDays;

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
      AppGrid(minTile: 150, children: [
        AppStatTile(icon: Icons.people_alt_rounded, label: t('سائلون', 'Askers'), value: o.askers),
        AppStatTile(icon: Icons.timer_outlined, label: t('زمن الإجابة (وسيط)', 'Answer time (median)'), value: o.p50 == null ? '—' : '${(o.p50! / 1000).toStringAsFixed(1)} s'),
        AppStatTile(icon: Icons.hourglass_top_rounded, label: t('في الانتظار', 'Waiting'), value: o.queueWaiting, color: o.queueWaiting > 10 ? c.warning : null),
        AppStatTile(icon: Icons.error_outline_rounded, label: t('فشلت', 'Failed'), value: o.failed, color: o.failed > 0 ? c.danger : null),
        AppStatTile(icon: Icons.description_outlined, label: t('مستندات جاهزة', 'Ready documents'), value: o.readyDocuments),
        AppStatTile(icon: Icons.quiz_outlined, label: t('أسئلة امتحانات مولّدة', 'Exam questions generated'), value: o.draftQuestions),
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
        AppCard(
          child: Column(children: [
            for (final nf in o.notFound.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 14, backgroundColor: c.warning.withValues(alpha: .15), child: Text('${asInt(nf['count'])}', style: appText(12, w: FontWeight.w800, c: c.warning))),
                title: Text(asStr(nf['question']), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(asStr(nf['context']) == 'docs' ? t('مؤسسة ${nf['org_id'] ?? ''}', 'Organization ${nf['org_id'] ?? ''}') : t('مساعد التطبيق', 'App assistant')),
              ),
          ]),
        ),
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
              const Divider(height: 16),
            ],
          ]),
        ),
    ]);
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
  const RagPlatformSettingsForm({super.key, required this.settings, required this.onSave, this.onTest});
  final RagAdminSettings settings;
  final ValueChanged<RagAdminSettings> onSave;
  final VoidCallback? onTest;

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

  @override
  void dispose() {
    for (final c in [_name, _ar, _en, _model, _fast]) {
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
      if (s.light) ...[
        _title(context, t('النموذج المحلي', 'Local model')),
        AppBanner(
            icon: Icons.memory_rounded,
            color: c.primary,
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
        AppField(controller: _model, label: t('النموذج (فارغ = إعداد الخادم ${s.llmModel})', 'Model (empty = the server\'s ${s.llmModel})'), ltr: true, onChanged: (v) => _s = _s.copyWith(model: v)),
        const SizedBox(height: 8),
        AppField(controller: _fast, label: t('النموذج الأسرع للخطوات الخفيفة (فارغ = ${s.llmFastModel})', 'Fast model for the light steps (empty = ${s.llmFastModel})'), ltr: true, onChanged: (v) => _s = _s.copyWith(fastModel: v)),
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
      AppBanner(icon: Icons.science_outlined, color: c.primary, text: t('اسأل كما يسأل العضو وشاهد كل خطوة: الفهم، الاستعلامات، النتائج، الكتابة والمراجعة.', 'Ask as a member would and see every step: understanding, queries, hits, writing and verification.')),
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
