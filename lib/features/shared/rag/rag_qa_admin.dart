// Curated Q&A pairs (Track E.2, D-061): approved answers the assistant gives BEFORE retrieval — /api/v1/rag/qa.
//
//   GET    /qa?scope=app|org&org_id=   {items[], scope, org_id, manager, embedder, thresholds{direct, example},
//                                       usage{pairs, enabled, direct}}
//   POST   /qa {scope, org_id?, question, variants[], answer, lang?, deep_link?, enabled?}  → 201 the pair (embedded)
//   PUT    /qa/{id} {question, variants, answer, lang?, deep_link?, enabled?}   the whole pair, re-embedded, version + 1
//   DELETE /qa/{id} → {id, deleted}   ·   POST /qa/{id}/toggle → the pair with `enabled` flipped
//   POST   /qa/from-query/{query_id}   "promote to Q&A": a DRAFT built from an asked question — nothing is saved,
//                                       the sheet edits it and POSTs /qa
//
// `app` pairs: platform admins; `org` pairs: the organization's library managers and the Super Admin (403
// not_library_manager). A pair embedded by another embedder is `stale`: saving it again re-embeds it. The answer is
// the text the chat renders (paragraphs, "- " bullets, "1. " steps, **bold**).
//
// Pure, unit-tested: [QaPair], [QaLibrary], [QaDraft] / [qaDraftFromQuery], [qaValidate], [qaCodeText], [qaLangText].
// Presentational, under the layout harness: [QaPairCard], [QaPairForm], [QaStatsHeader]. [RagQaAdminBody] owns the
// calls ([RagQaAdminPage] wraps it in a page; the admin console embeds it as a tab), [QaPairSheet] saves one pair.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, asStrOrNull, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'rag_chat.dart' show kRagPageMaxWidth, ragGutter;
import 'rag_library.dart' show ragLibraryCodeText;

// ── limits (the server's) ──────────────────────────────────────────────────────────────────────────────────────

const qaMaxQuestion = 500;
const qaMaxAnswer = 4000;
const qaMaxVariants = 30;
const qaLangs = ['ar', 'en', 'mixed'];

// ── models ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// One curated pair. `id` 0 = not saved yet (a draft).
class QaPair {
  const QaPair({
    this.id = 0,
    this.scope = 'app',
    this.orgId,
    this.question = '',
    this.variants = const [],
    this.answer = '',
    this.lang,
    this.deepLink,
    this.enabled = true,
    this.createdBy,
    this.usageCount = 0,
    this.lastUsedAt,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.stale = false,
  });

  final int id;

  /// `app` | `org`
  final String scope;
  final int? orgId;
  final String question;
  final List<String> variants;
  final String answer;

  /// `ar` | `en` | `mixed`; null = detected by the server.
  final String? lang;

  /// A feature key or a route the chat may open from the answer's citation.
  final String? deepLink;
  final bool enabled;
  final int? createdBy;
  final int usageCount;
  final String? lastUsedAt;
  final int version;
  final String? createdAt, updatedAt;

  /// Embedded by another embedder than the server's current one — save it again.
  final bool stale;

  bool get isNew => id <= 0;

  factory QaPair.fromJson(Map<String, dynamic> j) => QaPair(
        id: asInt(j['id']),
        scope: asStr(j['scope']) == 'org' ? 'org' : 'app',
        orgId: j['org_id'] == null ? null : asInt(j['org_id']),
        question: asStr(j['question']).trim(),
        variants: qaVariantsOf(j['variants']),
        answer: asStr(j['answer']),
        lang: qaLangOf(j['lang']),
        deepLink: _blankNull(j['deep_link']),
        enabled: asBool(j['enabled'], true),
        createdBy: j['created_by'] == null ? null : asInt(j['created_by']),
        usageCount: asInt(j['usage_count']),
        lastUsedAt: _blankNull(j['last_used_at']),
        version: asInt(j['version'], 1),
        createdAt: _blankNull(j['created_at']),
        updatedAt: _blankNull(j['updated_at']),
        stale: asBool(j['stale']),
      );

  /// The write body. A PUT sends exactly the pair's fields (the server replaces the whole pair, `lang` null = detect,
  /// `deep_link` null = none); [create] adds `scope` and, for an organization pair, `org_id`.
  Map<String, dynamic> toJson({bool create = false}) => {
        if (create) 'scope': scope,
        if (create && scope == 'org') 'org_id': orgId,
        'question': question.trim(),
        'variants': [for (final v in variants) v.trim()],
        'answer': answer.trim(),
        'lang': lang,
        'deep_link': deepLink == null || deepLink!.trim().isEmpty ? null : deepLink!.trim(),
        'enabled': enabled,
      };

  QaPair copyWith({
    int? id,
    String? scope,
    int? orgId,
    String? question,
    List<String>? variants,
    String? answer,
    String? lang,
    bool clearLang = false,
    String? deepLink,
    bool clearDeepLink = false,
    bool? enabled,
    bool? stale,
  }) =>
      QaPair(
        id: id ?? this.id,
        scope: scope ?? this.scope,
        orgId: orgId ?? this.orgId,
        question: question ?? this.question,
        variants: variants ?? this.variants,
        answer: answer ?? this.answer,
        lang: clearLang ? null : (lang ?? this.lang),
        deepLink: clearDeepLink ? null : (deepLink ?? this.deepLink),
        enabled: enabled ?? this.enabled,
        createdBy: createdBy,
        usageCount: usageCount,
        lastUsedAt: lastUsedAt,
        version: version,
        createdAt: createdAt,
        updatedAt: updatedAt,
        stale: stale ?? this.stale,
      );
}

String? _blankNull(dynamic v) {
  final s = asStrOrNull(v)?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// `ar` | `en` | `mixed`, else null (auto).
String? qaLangOf(dynamic v) {
  final s = asStr(v).trim().toLowerCase();
  return qaLangs.contains(s) ? s : null;
}

/// The variants list the server sent (or the sheet keeps): trimmed, blanks and duplicates dropped.
List<String> qaVariantsOf(dynamic v) {
  final out = <String>[];
  for (final x in (v is List ? v : const [])) {
    if (x == null) continue;
    final s = '$x'.trim();
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

String qaLangText(String? lang) => switch (lang) {
      'ar' => t('عربي', 'Arabic'),
      'en' => t('إنجليزي', 'English'),
      'mixed' => t('مختلط', 'Mixed'),
      _ => t('تلقائي', 'Auto'),
    };

/// The list the manager sees (`GET /qa`).
class QaLibrary {
  const QaLibrary({
    this.items = const [],
    this.scope = 'app',
    this.orgId,
    this.manager = false,
    this.embedder = '',
    this.directThreshold,
    this.exampleThreshold,
    this.pairs = 0,
    this.enabledCount = 0,
    this.direct = 0,
  });

  final List<QaPair> items;
  final String scope;
  final int? orgId;
  final bool manager;
  final String embedder;
  final double? directThreshold, exampleThreshold;

  /// `usage`: pairs, enabled pairs, direct hits.
  final int pairs, enabledCount, direct;

  factory QaLibrary.fromJson(Map<String, dynamic> j) {
    final items = [for (final i in asMapList(j['items'])) QaPair.fromJson(i)];
    final th = asMap(j['thresholds']);
    final u = asMap(j['usage']);
    return QaLibrary(
      items: items,
      scope: asStr(j['scope']) == 'org' ? 'org' : 'app',
      orgId: j['org_id'] == null ? null : asInt(j['org_id']),
      manager: asBool(j['manager']),
      embedder: asStr(j['embedder']),
      directThreshold: th['direct'] == null ? null : double.tryParse('${th['direct']}'),
      exampleThreshold: th['example'] == null ? null : double.tryParse('${th['example']}'),
      pairs: asInt(u['pairs'], items.length),
      enabledCount: asInt(u['enabled'], items.where((p) => p.enabled).length),
      direct: asInt(u['direct']),
    );
  }

  int get staleCount => items.where((p) => p.stale).length;
  int get disabledCount => items.where((p) => !p.enabled).length;

  /// [only]: '' (all) · `enabled` · `disabled` · `stale`; [q] matches the question, a variant or the answer.
  List<QaPair> filtered(String q, {String only = ''}) {
    final needle = q.trim().toLowerCase();
    return [
      for (final p in items)
        if (switch (only) { 'enabled' => p.enabled, 'disabled' => !p.enabled, 'stale' => p.stale, _ => true })
          if (needle.isEmpty ||
              p.question.toLowerCase().contains(needle) ||
              p.answer.toLowerCase().contains(needle) ||
              p.variants.any((v) => v.toLowerCase().contains(needle)))
            p,
    ];
  }

  /// The same list with [items] replaced (counts follow the items; `direct` hits are the server's number).
  QaLibrary withItems(List<QaPair> items) => QaLibrary(
        items: items,
        scope: scope,
        orgId: orgId,
        manager: manager,
        embedder: embedder,
        directThreshold: directThreshold,
        exampleThreshold: exampleThreshold,
        pairs: items.length,
        enabledCount: items.where((p) => p.enabled).length,
        direct: direct,
      );
}

/// What `POST /qa/from-query/{id}` hands back: a pair to edit (never saved yet) plus where it came from.
class QaDraft {
  const QaDraft({required this.pair, this.queryId = 0, this.found = false, this.context = ''});
  final QaPair pair;
  final int queryId;

  /// The assistant had found an answer (then [pair.answer] is that answer, else empty).
  final bool found;
  final String context;
}

/// "Promote to Q&A": the server's draft → a [QaPair] with no id, enabled, its scope / organization kept.
QaDraft qaDraftFromQuery(Map<String, dynamic> j) => QaDraft(
      pair: QaPair.fromJson(j).copyWith(id: 0, enabled: asBool(j['enabled'], true)),
      queryId: asInt(j['query_id']),
      found: asBool(j['found']),
      context: asStr(j['context']),
    );

/// null when the pair can be sent, else the server's code for what is wrong (same codes as its 422s).
String? qaValidate(QaPair p) {
  final q = p.question.trim();
  final a = p.answer.trim();
  if (q.isEmpty) return 'qa_question_required';
  if (q.length > qaMaxQuestion) return 'qa_question_too_long';
  if (a.isEmpty) return 'qa_answer_required';
  if (a.length > qaMaxAnswer) return 'qa_answer_too_long';
  if (p.variants.length > qaMaxVariants) return 'qa_too_many_variants';
  if (p.variants.any((v) => v.trim().length > qaMaxQuestion)) return 'qa_question_too_long';
  if (p.lang != null && !qaLangs.contains(p.lang)) return 'bad_lang';
  if (p.scope == 'org' && p.orgId == null) return 'org_required';
  return null;
}

/// The Q&A codes (422 · 403 · 404), then the library's.
String qaCodeText(String? code, String fallback) => switch (code) {
      'qa_question_required' => t('اكتب السؤال', 'Write the question'),
      'qa_question_too_long' => t('السؤال (أو إحدى صيغه) أطول من $qaMaxQuestion حرف', 'The question (or a variant) is longer than $qaMaxQuestion characters'),
      'qa_answer_required' => t('اكتب الإجابة', 'Write the answer'),
      'qa_answer_too_long' => t('الإجابة أطول من $qaMaxAnswer حرف', 'The answer is longer than $qaMaxAnswer characters'),
      'qa_too_many_variants' => t('أقصى عدد للصيغ $qaMaxVariants', 'At most $qaMaxVariants variants'),
      'bad_lang' => t('اللغة: عربي أو إنجليزي أو مختلط', 'The language must be Arabic, English or mixed'),
      'bad_deep_link' => t('الرابط العميق غير صالح: مفتاح ميزة أو مسار يبدأ بـ /', 'The deep link is not valid: a feature key or a route starting with /'),
      'qa_not_found' => t('هذه الإجابة المعتمدة لم تعد موجودة', 'This Q&A pair no longer exists'),
      'no_qa_scope' => t('سؤال من محادثة مقرر شخصية — الإجابات المعتمدة للتطبيق أو لمؤسسة', 'A personal course question — Q&A pairs belong to the app or to an organization'),
      'query_not_found' => t('السؤال غير موجود', 'The question was not found'),
      _ => ragLibraryCodeText(code, fallback),
    };

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class QaApi {
  QaApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/rag/qa';

  Future<EngineResult> list({required String scope, int? orgId}) =>
      engineCall(() => _api.get(base, queryParams: {'scope': scope, 'org_id': ?orgId}));
  Future<EngineResult> create(QaPair p) => engineCall(() => _api.post(base, body: p.toJson(create: true)));
  Future<EngineResult> update(QaPair p) => engineCall(() => _api.put('$base/${p.id}', body: p.toJson()));
  Future<EngineResult> delete(int id) => engineCall(() => _api.delete('$base/$id'));
  Future<EngineResult> toggle(int id) => engineCall(() => _api.post('$base/$id/toggle'));
  Future<EngineResult> fromQuery(int queryId) => engineCall(() => _api.post('$base/from-query/$queryId'));
}

// ── the page / body ──────────────────────────────────────────────────────────────────────────────────────────────

/// The curated Q&A of the app (`scope: 'app'`, platform admins) or of one organization (`scope: 'org'`, its
/// library managers), as its own page.
class RagQaAdminPage extends StatelessWidget {
  const RagQaAdminPage({super.key, required this.scope, this.orgId, this.api, this.title});
  final String scope;
  final int? orgId;
  final QaApi? api;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('rag.qa_admin'),
      useWebCard: true,
      width: AppWidth.wide,
      appBar: ScreenAppBar(
          title: title ?? (scope == 'org' ? t('الإجابات المعتمدة للمؤسسة', 'Organization Q&A') : t('الإجابات المعتمدة', 'Curated Q&A')),
          actions: [if (scope == 'org') const ContextExitButton()]),
      child: RagQaAdminBody(scope: scope, orgId: orgId, api: api),
    );
  }
}

/// The list: search, filter pills, counts, add / edit / toggle / delete. Fills the space it is given (a page body or
/// a tab).
class RagQaAdminBody extends StatefulWidget {
  const RagQaAdminBody({super.key, required this.scope, this.orgId, this.api});
  final String scope;
  final int? orgId;
  final QaApi? api;

  @override
  State<RagQaAdminBody> createState() => _RagQaAdminBodyState();
}

class _RagQaAdminBodyState extends State<RagQaAdminBody> {
  late final QaApi _api = widget.api ?? QaApi();
  final _search = TextEditingController();
  QaLibrary? _lib;
  bool _loading = true;
  String? _error;
  String _only = '';
  final Set<int> _working = {};

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

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final r = await _api.list(scope: widget.scope, orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _lib = QaLibrary.fromJson(r.map);
        _error = null;
      } else if (!silent || _lib == null) {
        _error = r.unavailable ? t('الإجابات المعتمدة تحتاج تحديث الخادم', 'Curated Q&A needs a server update') : qaCodeText(r.code, r.message);
      }
    });
  }

  void _replace(QaPair p) {
    final lib = _lib;
    if (lib == null) return;
    final items = [for (final x in lib.items) x.id == p.id ? p : x];
    if (!items.any((x) => x.id == p.id)) items.insert(0, p);
    setState(() => _lib = lib.withItems(items));
  }

  Future<void> _edit([QaPair? p]) async {
    final saved = await showAppSheet<QaPair>(
        context, (_) => QaPairSheet(draft: p ?? QaPair(scope: widget.scope, orgId: widget.orgId), api: _api));
    if (saved == null || !mounted) return;
    _replace(saved);
    appToast(p == null ? t('أُضيفت الإجابة المعتمدة', 'Q&A pair added') : t('تم الحفظ', 'Saved'));
  }

  Future<void> _toggle(QaPair p) async {
    setState(() => _working.add(p.id));
    final r = await _api.toggle(p.id);
    if (!mounted) return;
    setState(() => _working.remove(p.id));
    if (r.ok) {
      _replace(QaPair.fromJson(r.map));
    } else {
      appToast(qaCodeText(r.code, r.message), error: true);
    }
  }

  Future<void> _delete(QaPair p) async {
    final q = p.question.length > 60 ? '${p.question.substring(0, 60)}…' : p.question;
    if (!await appConfirm(context,
        message: t('حذف «$q»؟ لن يُطابَق هذا السؤال بعد الآن.', 'Delete "$q"? This question will not be matched any more.'),
        danger: true,
        confirmLabel: t('حذف', 'Delete'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _working.add(p.id));
    final r = await _api.delete(p.id);
    if (!mounted) return;
    setState(() => _working.remove(p.id));
    if (r.ok) {
      final lib = _lib;
      if (lib != null) setState(() => _lib = lib.withItems([for (final x in lib.items) if (x.id != p.id) x]));
      appToast(t('حُذفت', 'Deleted'));
    } else {
      appToast(qaCodeText(r.code, r.message), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lib = _lib;
    final shown = lib?.filtered(_search.text, only: _only) ?? const <QaPair>[];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: AppField(controller: _search, label: t('ابحث في الأسئلة والإجابات', 'Search questions and answers'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: IconButton.filled(tooltip: t('إضافة إجابة معتمدة', 'Add a Q&A pair'), icon: const Icon(Icons.add_rounded), onPressed: lib == null ? null : () => _edit()),
            ),
          ]),
          if (lib != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                AppChoiceChip(label: '${t('الكل', 'All')} (${lib.items.length})', selected: _only.isEmpty, onTap: () => setState(() => _only = '')),
                AppChoiceChip(label: '${t('مفعّلة', 'Enabled')} (${lib.enabledCount})', selected: _only == 'enabled', onTap: () => setState(() => _only = 'enabled')),
                if (lib.disabledCount > 0)
                  AppChoiceChip(label: '${t('معطّلة', 'Disabled')} (${lib.disabledCount})', selected: _only == 'disabled', onTap: () => setState(() => _only = 'disabled')),
                if (lib.staleCount > 0)
                  AppChoiceChip(
                      icon: Icons.refresh_rounded,
                      label: '${t('تحتاج حفظاً', 'Save again')} (${lib.staleCount})',
                      selected: _only == 'stale',
                      onTap: () => setState(() => _only = 'stale')),
              ]),
            ),
        ]),
      ),
      Expanded(
        child: _loading && lib == null
            ? const AppListSkeleton(withAvatar: false)
            : _error != null && lib == null
                ? AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
                : AppRefresh(
                    onRefresh: () => _load(silent: true),
                    // a centred column of at most kRagPageMaxWidth: long answers keep a readable line
                    child: LayoutBuilder(builder: (context, box) {
                    final side = ragGutter(box.maxWidth, maxWidth: kRagPageMaxWidth);
                    return ListView(padding: EdgeInsets.fromLTRB(side, 10, side, 90), children: [
                      QaStatsHeader(scope: widget.scope, pairs: lib!.pairs, enabled: lib.enabledCount, direct: lib.direct, stale: lib.staleCount, embedder: lib.embedder),
                      const SizedBox(height: 12),
                      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!)),
                      if (shown.isEmpty)
                        AppEmpty(
                            icon: Icons.question_answer_outlined,
                            title: lib.items.isEmpty ? t('لا إجابات معتمدة بعد', 'No Q&A pairs yet') : t('لا نتائج', 'Nothing matches'),
                            message: lib.items.isEmpty
                                ? t('أضف سؤالاً وإجابته المعتمدة ليجيب بها المساعد فوراً قبل البحث في المستندات.',
                                    'Add a question and its approved answer; the assistant gives it at once, before searching the documents.')
                                : null,
                            actionLabel: lib.items.isEmpty ? t('إضافة', 'Add') : null,
                            onAction: lib.items.isEmpty ? () => _edit() : null)
                      else
                        for (final p in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: QaPairCard(
                                pair: p,
                                working: _working.contains(p.id),
                                onEdit: () => _edit(p),
                                onToggle: () => _toggle(p),
                                onDelete: () => _delete(p)),
                          ),
                    ]);
                    }),
                  ),
      ),
    ]);
  }
}

// ── presentational ───────────────────────────────────────────────────────────────────────────────────────────────

/// The hero on top of the list: how many pairs, how many enabled, direct hits, what needs saving again.
class QaStatsHeader extends StatelessWidget {
  const QaStatsHeader({super.key, required this.scope, required this.pairs, required this.enabled, required this.direct, this.stale = 0, this.embedder = ''});
  final String scope;
  final int pairs, enabled, direct, stale;
  final String embedder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppHero(
        title: scope == 'org' ? t('الإجابات المعتمدة للمؤسسة', 'Organization Q&A') : t('الإجابات المعتمدة', 'Curated Q&A'),
        subtitle: t('سؤال يطابق إحدى هذه الأسئلة أو صيغها يأخذ إجابته المعتمدة فوراً، قبل البحث في المستندات. الأسئلة القريبة تُعرض للنموذج كأمثلة.',
            'A question that matches one of these (or a variant) gets its approved answer at once, before any document search. Close ones are shown to the model as examples.'),
        icon: Icons.verified_rounded,
        stats: [
          AppHeroStat(icon: Icons.question_answer_rounded, value: '$pairs', label: t('إجابة', 'pairs')),
          AppHeroStat(icon: Icons.check_circle_rounded, value: '$enabled', label: t('مفعّلة', 'enabled')),
          AppHeroStat(icon: Icons.bolt_rounded, value: '$direct', label: t('إجابة مباشرة', 'direct hits')),
        ],
      ),
      if (stale > 0) ...[
        const SizedBox(height: 10),
        AppBanner(
            icon: Icons.refresh_rounded,
            color: c.warning,
            text: t('$stale من الإجابات فُهرست بنموذج تضمين آخر${embedder.isEmpty ? '' : ' (الحالي: $embedder)'} — افتحها واحفظها من جديد لتُطابَق.',
                '$stale pair(s) were embedded by another embedder${embedder.isEmpty ? '' : ' (now: $embedder)'} — open and save them again so they match.')),
      ],
    ]);
  }
}

/// One pair in the list: question, answer, state pills, usage, and the actions.
class QaPairCard extends StatelessWidget {
  const QaPairCard({super.key, required this.pair, this.working = false, this.onEdit, this.onToggle, this.onDelete});
  final QaPair pair;
  final bool working;
  final VoidCallback? onEdit, onToggle, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = pair;
    final used = p.usageCount <= 0 || p.lastUsedAt == null
        ? t('لم تُستخدم بعد', 'Not used yet')
        : t('استُخدمت ${p.usageCount} مرة · آخرها ${relTime(p.lastUsedAt)}', 'Used ${p.usageCount}× · last ${relTime(p.lastUsedAt)}');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(p.question, style: appText(14, w: FontWeight.w800, c: p.enabled ? c.textDark : c.textMedium))),
          const SizedBox(width: 8),
          AppSwitch(value: p.enabled, onChanged: working || onToggle == null ? null : (_) => onToggle!(), semanticLabel: t('مفعّلة', 'Enabled')),
        ]),
        if (p.answer.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(p.answer.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium, h: 1.4)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          p.enabled
              ? AppBadgePill(t('مفعّلة', 'enabled'), color: c.success, icon: Icons.check_rounded)
              : AppBadgePill(t('معطّلة', 'disabled'), color: c.textLight, icon: Icons.pause_rounded),
          AppBadgePill(qaLangText(p.lang), icon: Icons.translate_rounded),
          if (p.variants.isNotEmpty) AppBadgePill(t('${p.variants.length} صيغة', '${p.variants.length} variants'), icon: Icons.alt_route_rounded),
          if (p.deepLink != null) AppBadgePill(p.deepLink!, color: c.primary, icon: Icons.link_rounded),
          if (p.stale) AppBadgePill(t('احفظ من جديد', 'save again'), color: c.warning, icon: Icons.refresh_rounded),
        ]),
        const SizedBox(height: 6),
        Text(used, style: appText(11.5, c: c.textLight)),
        Wrap(spacing: 4, alignment: WrapAlignment.end, children: [
          TextButton.icon(onPressed: working ? null : onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: Text(t('تعديل', 'Edit'))),
          TextButton.icon(
              onPressed: working ? null : onDelete,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(t('حذف', 'Delete'))),
        ]),
      ]),
    );
  }
}

/// The edit form: question · variants (chips + an add field) · answer · language · deep link · enabled. Takes plain
/// values; [onSave] gets a pair that passed [qaValidate].
class QaPairForm extends StatefulWidget {
  const QaPairForm({super.key, required this.pair, required this.onSave, this.busy = false, this.error});
  final QaPair pair;
  final ValueChanged<QaPair> onSave;
  final bool busy;
  final String? error;

  @override
  State<QaPairForm> createState() => _QaPairFormState();
}

class _QaPairFormState extends State<QaPairForm> {
  late final _question = TextEditingController(text: widget.pair.question);
  late final _answer = TextEditingController(text: widget.pair.answer);
  late final _deepLink = TextEditingController(text: widget.pair.deepLink ?? '');
  final _variant = TextEditingController();
  late List<String> _variants = List.of(widget.pair.variants);
  late String? _lang = widget.pair.lang;
  late bool _enabled = widget.pair.enabled;
  String? _localError;

  @override
  void dispose() {
    for (final c in [_question, _answer, _deepLink, _variant]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addVariant([String? _]) {
    final v = _variant.text.trim();
    if (v.isEmpty) return;
    setState(() {
      if (!_variants.contains(v)) _variants = [..._variants, v];
      _variant.clear();
      _localError = _variants.length > qaMaxVariants ? qaCodeText('qa_too_many_variants', '') : null;
    });
  }

  QaPair _current() => widget.pair.copyWith(
        question: _question.text,
        variants: _variants,
        answer: _answer.text,
        lang: _lang,
        clearLang: _lang == null,
        deepLink: _deepLink.text.trim(),
        clearDeepLink: _deepLink.text.trim().isEmpty,
        enabled: _enabled,
      );

  void _save() {
    _addVariant();
    final p = _current();
    final code = qaValidate(p);
    if (code != null) return setState(() => _localError = qaCodeText(code, code));
    setState(() => _localError = null);
    widget.onSave(p);
  }

  DropdownMenuItem<String> _item(String v, String label) => DropdownMenuItem(value: v, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final error = widget.error ?? _localError;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error)),
      AppField(controller: _question, label: t('السؤال', 'Question'), hint: t('كما يكتبه العضو', 'As a member would write it'), maxLines: 2),
      AppSectionTitle(t('صيغ أخرى للسؤال', 'Other ways to ask it'), subtitle: t('بالعربية والإنجليزية؛ كل صيغة تُطابَق مثل السؤال', 'In Arabic and English; every variant matches like the question')),
      const SizedBox(height: 6),
      if (_variants.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in _variants)
              InputChip(
                  label: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onDeleted: widget.busy ? null : () => setState(() => _variants = [for (final x in _variants) if (x != v) x])),
          ]),
        ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: AppField(controller: _variant, label: t('أضف صيغة', 'Add a variant'), onSubmitted: _addVariant)),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: IconButton.outlined(tooltip: t('أضف', 'Add'), icon: const Icon(Icons.add_rounded), onPressed: widget.busy ? null : _addVariant),
        ),
      ]),
      AppField(
          controller: _answer,
          label: t('الإجابة المعتمدة', 'Approved answer'),
          hint: t('فقرات، نقاط بـ "- "، خطوات بـ "1. "، و**غامق**', 'Paragraphs, "- " bullets, "1. " steps, **bold**'),
          maxLines: 7),
      AppDropdown<String>(
        value: _lang ?? 'auto',
        decoration: InputDecoration(labelText: t('اللغة', 'Language')),
        items: [
          _item('auto', t('تلقائي (يكتشفها الخادم)', 'Auto (the server detects it)')),
          _item('ar', qaLangText('ar')),
          _item('en', qaLangText('en')),
          if (_lang == 'mixed') _item('mixed', qaLangText('mixed')),
        ],
        onChanged: (v) => setState(() => _lang = v == null || v == 'auto' ? null : v),
      ),
      const SizedBox(height: 12),
      AppField(controller: _deepLink, label: t('رابط عميق (اختياري)', 'Deep link (optional)'), hint: t('مفتاح ميزة أو مسار مثل /downloads', 'A feature key or a route such as /downloads'), ltr: true),
      AppSwitchTile(
          title: t('مفعّلة', 'Enabled'),
          subtitle: t('إجابة معطّلة لا تُطابَق أبداً', 'A disabled pair never matches'),
          value: _enabled,
          onChanged: widget.busy ? null : (v) => setState(() => _enabled = v)),
      const SizedBox(height: 8),
      AppPrimaryButton(
          label: widget.pair.isNew ? t('إضافة', 'Add') : t('حفظ', 'Save'),
          icon: widget.pair.isNew ? Icons.add_rounded : Icons.save_rounded,
          busy: widget.busy,
          onPressed: widget.busy ? null : _save),
    ]);
  }
}

/// The sheet around [QaPairForm]: creates a new pair or saves an existing one and pops the saved [QaPair].
class QaPairSheet extends StatefulWidget {
  const QaPairSheet({super.key, required this.draft, this.api, this.save, this.title});
  final QaPair draft;
  final QaApi? api;

  /// Saves the pair instead of POST / PUT /qa — accepting a learned suggestion (Track F, rag_learning.dart) sends
  /// the edited pair to POST /learning/suggestions/{id}/accept. The answer may carry the pair as `pair`.
  final Future<EngineResult> Function(QaPair pair)? save;
  final String? title;

  @override
  State<QaPairSheet> createState() => _QaPairSheetState();
}

class _QaPairSheetState extends State<QaPairSheet> {
  late final QaApi _api = widget.api ?? QaApi();
  bool _busy = false;
  String? _error;

  Future<void> _save(QaPair p) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = widget.save != null ? await widget.save!(p) : (p.isNew ? await _api.create(p) : await _api.update(p));
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, QaPair.fromJson(r.map['pair'] is Map ? asMap(r.map['pair']) : r.map));
    } else {
      setState(() {
        _busy = false;
        _error = r.unavailable ? t('الإجابات المعتمدة تحتاج تحديث الخادم', 'Curated Q&A needs a server update') : qaCodeText(r.code, r.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(widget.title ?? (d.isNew ? t('إجابة معتمدة جديدة', 'New Q&A pair') : t('تعديل الإجابة المعتمدة', 'Edit the Q&A pair'))),
        QaPairForm(pair: d, busy: _busy, error: _error, onSave: _save),
      ]),
    );
  }
}
