// lib/features/rag/admin/rag_feedback_review.dart
//
// Feedback review: the answers people marked unhelpful, grouped into clusters of the same question, and the
// "write the verified answer" flow that turns a cluster into a curated Q&A pair (FRONT_CONTRACTS "Feedback review").
//
//   GET  /api/v1/rag/admin/feedback/clusters?days=&min_dislikes=&org_id=&limit=&offset=             platform admins
//   GET  /api/v1/rag/orgs/{org_id}/answers/feedback/clusters?days=&min_dislikes=&limit=&offset=     the org's managers
//   POST …/clusters/{key}/verify {answer, question?, variants?, citations?, lang?, deep_link?, enabled?}
//        -> the pair + created + cache_purged;  404 cluster_not_found, 403
//
// Pure, unit-tested: [FeedbackCluster], [FeedbackPage], [feedbackVerifyBody]. Presentational, under the layout
// harness: [FeedbackClusterCard], [FeedbackFiltersBar], [VerifyAnswerSheet], [FeedbackReviewList].
// [FeedbackReviewBody] owns the calls, [RagFeedbackReviewPage] wraps it for the console and the org assistant.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, shortDateTime, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/rag/rag_library.dart' show ragLibraryCodeText;

// ── models ───────────────────────────────────────────────────────────────────────────────────────────────────

class FeedbackCitation {
  const FeedbackCitation({this.title = '', this.section = '', this.documentId, this.pageFrom});
  final String title, section;
  final int? documentId, pageFrom;

  factory FeedbackCitation.fromJson(Map<String, dynamic> j) => FeedbackCitation(
        title: asStr(j['title']),
        section: asStr(j['section']),
        documentId: j['document_id'] == null ? null : asInt(j['document_id']),
        pageFrom: j['page_from'] == null ? null : asInt(j['page_from']),
      );

  Map<String, dynamic> toJson() => {'title': title, 'section': section, 'document_id': ?documentId};

  String get label => [title, if (section.isNotEmpty) section, if (pageFrom != null) 'p.$pageFrom'].where((e) => e.isNotEmpty).join(' · ');
}

class FeedbackAnswer {
  const FeedbackAnswer({this.text = '', this.found = true, this.generator = '', this.citations = const []});
  final String text, generator;
  final bool found;
  final List<FeedbackCitation> citations;

  static FeedbackAnswer? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return FeedbackAnswer(
      text: asStr(j['text']),
      found: asBool(j['found'], true),
      generator: asStr(j['generator']),
      citations: [for (final c in asMapList(j['citations'])) FeedbackCitation.fromJson(c)],
    );
  }
}

class FeedbackComment {
  const FeedbackComment({required this.text, this.at});
  final String text;
  final String? at;
}

class FeedbackVerified {
  const FeedbackVerified({required this.qaId, this.enabled = true, this.version = 1});
  final int qaId, version;
  final bool enabled;

  static FeedbackVerified? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return FeedbackVerified(qaId: asInt(j['qa_id']), enabled: asBool(j['enabled'], true), version: asInt(j['version'], 1));
  }
}

/// One cluster of the same unhelpful question.
class FeedbackCluster {
  const FeedbackCluster({
    required this.key,
    this.scope = 'app',
    this.orgId,
    this.courseId,
    this.question = '',
    this.dislikes = 0,
    this.likes = 0,
    this.questions = const [],
    this.lastAt,
    this.queryId,
    this.answer,
    this.comments = const [],
    this.verified,
  });

  factory FeedbackCluster.fromJson(Map<String, dynamic> j) => FeedbackCluster(
        key: asStr(j['key']),
        scope: asStr(j['scope'], 'app'),
        orgId: j['org_id'] == null ? null : asInt(j['org_id']),
        courseId: j['course_id'] == null ? null : asInt(j['course_id']),
        question: asStr(j['question']),
        dislikes: asInt(j['dislikes']),
        likes: asInt(j['likes']),
        questions: [for (final q in (j['questions'] is List ? j['questions'] as List : const [])) '$q'],
        lastAt: j['last_at'] == null ? null : '${j['last_at']}',
        queryId: j['query_id'] == null ? null : asInt(j['query_id']),
        answer: FeedbackAnswer.fromJson(j['answer']),
        comments: [
          for (final c in (j['comments'] is List ? j['comments'] as List : const []))
            if (c is Map) FeedbackComment(text: asStr(c['text']), at: c['at'] == null ? null : '${c['at']}')
            else if (c is String) FeedbackComment(text: c),
        ],
        verified: FeedbackVerified.fromJson(j['verified']),
      );

  final String key, scope, question;
  final int? orgId, courseId, queryId;
  final int dislikes, likes;
  final List<String> questions;
  final String? lastAt;
  final FeedbackAnswer? answer;
  final List<FeedbackComment> comments;
  final FeedbackVerified? verified;

  bool get isVerified => verified != null;
}

class FeedbackPage {
  const FeedbackPage({this.items = const [], this.total = 0, this.limit = 20, this.offset = 0, this.days = 30, this.minDislikes = 1, this.helpful = 0, this.unhelpful = 0});

  factory FeedbackPage.fromJson(Map<String, dynamic> j) {
    final rated = asMap(j['rated']);
    return FeedbackPage(
      items: [for (final c in asMapList(j['items'])) FeedbackCluster.fromJson(c)],
      total: asInt(j['total']),
      limit: asInt(j['limit'], 20),
      offset: asInt(j['offset']),
      days: asInt(j['days'], 30),
      minDislikes: asInt(j['min_dislikes'], 1),
      helpful: asInt(rated['helpful']),
      unhelpful: asInt(rated['unhelpful']),
    );
  }

  final List<FeedbackCluster> items;
  final int total, limit, offset, days, minDislikes, helpful, unhelpful;

  bool get hasMore => offset + items.length < total;

  /// This page after [next] (the following slice) is appended.
  FeedbackPage append(FeedbackPage next) => FeedbackPage(
        items: [...items, ...next.items],
        total: next.total,
        limit: next.limit,
        offset: offset,
        days: next.days,
        minDislikes: next.minDislikes,
        helpful: next.helpful,
        unhelpful: next.unhelpful,
      );
}

/// The verify body: only what the person filled in (empty variants / link are left out).
Map<String, dynamic> feedbackVerifyBody({
  required String answer,
  String? question,
  List<String> variants = const [],
  List<FeedbackCitation> citations = const [],
  String? lang,
  String? deepLink,
  bool enabled = true,
}) {
  final vs = [for (final v in variants) if (v.trim().isNotEmpty) v.trim()];
  return {
    'answer': answer.trim(),
    if (question != null && question.trim().isNotEmpty) 'question': question.trim(),
    if (vs.isNotEmpty) 'variants': vs,
    if (citations.isNotEmpty) 'citations': [for (final c in citations) c.toJson()],
    if (lang != null && lang.isNotEmpty) 'lang': lang,
    if (deepLink != null && deepLink.trim().isNotEmpty) 'deep_link': deepLink.trim(),
    'enabled': enabled,
  };
}

String feedbackErrorText(EngineResult r) => switch (r.code) {
      'cluster_not_found' => t('لم يعد هذا التجمّع موجوداً — حدّث القائمة', 'This cluster no longer exists — refresh the list'),
      _ => r.unavailable ? t('مراجعة التقييمات تحتاج تحديث الخادم', 'Feedback review needs a server update') : ragLibraryCodeText(r.code, r.message),
    };

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The platform's routes (`orgId` null) or one organization's (`orgId` set).
class FeedbackReviewApi {
  FeedbackReviewApi({this.orgId, ApiClient? api}) : _api = api ?? ApiClient();
  final int? orgId;
  final ApiClient _api;

  String get _base => orgId == null ? '/api/v1/rag/admin/feedback/clusters' : '/api/v1/rag/orgs/$orgId/answers/feedback/clusters';

  Future<EngineResult> clusters({int days = 30, int minDislikes = 1, int? orgFilter, int limit = 20, int offset = 0}) => engineCall(() => _api.get(_base, queryParams: {
        'days': days,
        'min_dislikes': minDislikes,
        if (orgId == null) 'org_id': ?orgFilter,
        'limit': limit,
        'offset': offset,
      }));

  Future<EngineResult> verify(String key, Map<String, dynamic> body) => engineCall(() => _api.post('$_base/$key/verify', body: body));
}

// ── widgets ──────────────────────────────────────────────────────────────────────────────────────────────────

String feedbackScopeLabel(String scope) => switch (scope) {
      'org' => t('المؤسسة', 'Organization'),
      'course' => t('المقرر', 'Course'),
      _ => t('التطبيق', 'App'),
    };

/// One cluster: the question, the counts, the answer that was shown with its sources, comments, and the action.
class FeedbackClusterCard extends StatelessWidget {
  const FeedbackClusterCard({super.key, required this.cluster, this.onVerify});
  final FeedbackCluster cluster;

  /// "Write the verified answer" (or "Edit"); null hides the button.
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = cluster;
    final a = k.answer;
    return AppCard(
      key: ValueKey('cluster_${k.key}'),
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(k.question, style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          AppBadgePill(feedbackScopeLabel(k.scope), color: c.primary, icon: Icons.layers_outlined),
          AppBadgePill(countText(k.dislikes, ar1: 'تقييم سلبي واحد', ar2: 'تقييمان سلبيان', arFew: '{n} تقييمات سلبية', arMany: '{n} تقييماً سلبياً', en1: '1 dislike', en: '{n} dislikes'),
              color: c.danger, icon: Icons.thumb_down_alt_outlined),
          if (k.likes > 0)
            AppBadgePill(countText(k.likes, ar1: 'إعجاب واحد', ar2: 'إعجابان', arFew: '{n} إعجابات', arMany: '{n} إعجاباً', en1: '1 like', en: '{n} likes'),
                color: c.success, icon: Icons.thumb_up_alt_outlined),
          if (k.lastAt != null) AppBadgePill(shortDateTime(k.lastAt), color: c.textLight, icon: Icons.schedule_rounded),
          if (k.isVerified)
            AppBadgePill(k.verified!.enabled ? t('موثّقة', 'Verified') : t('موثّقة (موقوفة)', 'Verified (off)'),
                color: k.verified!.enabled ? c.success : c.warning, icon: Icons.verified_rounded),
        ]),
        if (k.questions.length > 1) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('صيغ أخرى للسؤال', 'Other wordings'), style: appText(11.5, w: FontWeight.w700, c: c.textLight)),
          for (final q in k.questions.where((q) => q != k.question).take(4))
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $q', style: appText(12.5, c: c.textMedium))),
        ],
        if (a != null) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('الإجابة التي ظهرت', 'The answer that was shown'), style: appText(11.5, w: FontWeight.w700, c: c.textLight)),
              const SizedBox(height: 2),
              Text(a.found ? a.text : t('لم تجد المساعد جواباً. ${a.text}', 'The assistant found no answer. ${a.text}'), maxLines: 8, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textDark, h: 1.45)),
              if (a.citations.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                  for (final s in a.citations.take(4)) AppBadgePill(s.label.isEmpty ? '—' : s.label, color: c.textMedium, icon: Icons.menu_book_outlined),
                ]),
              ],
            ]),
          ),
        ],
        if (k.comments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('تعليقات', 'Comments'), style: appText(11.5, w: FontWeight.w700, c: c.textLight)),
          for (final m in k.comments.take(5))
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('«${m.text}»', style: appText(12.5, c: c.textMedium))),
        ],
        if (onVerify != null) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: ValueKey('verify_${k.key}'),
              onPressed: onVerify,
              style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: Icon(k.isVerified ? Icons.edit_rounded : Icons.verified_outlined, size: 18),
              label: Text(k.isVerified ? t('تعديل الإجابة الموثّقة', 'Edit the verified answer') : t('اكتب الإجابة الموثّقة', 'Write the verified answer')),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Days · minimum dislikes · (the platform's) organization filter.
class FeedbackFiltersBar extends StatelessWidget {
  const FeedbackFiltersBar({super.key, required this.days, required this.minDislikes, required this.onChanged, this.orgFilter, this.showOrg = false, this.onOrg});
  final int days, minDislikes;
  final int? orgFilter;
  final bool showOrg;
  final void Function(int days, int minDislikes) onChanged;
  final ValueChanged<int?>? onOrg;

  static const daysChoices = [7, 30, 90];
  static const dislikeChoices = [1, 2, 3, 5];

  @override
  Widget build(BuildContext context) {
    Widget box(Widget child) => SizedBox(width: 150, child: child);
    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
      box(AppDropdown<int>(
        value: daysChoices.contains(days) ? days : 30,
        decoration: InputDecoration(labelText: t('المدة', 'Period')),
        items: [for (final d in daysChoices) DropdownMenuItem(value: d, child: Text(t('$d يوماً', '$d days'), maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => onChanged(v ?? days, minDislikes),
      )),
      box(AppDropdown<int>(
        value: dislikeChoices.contains(minDislikes) ? minDislikes : 1,
        decoration: InputDecoration(labelText: t('أقل عدد تقييمات سلبية', 'Min dislikes')),
        items: [for (final d in dislikeChoices) DropdownMenuItem(value: d, child: Text('$d+'))],
        onChanged: (v) => onChanged(days, v ?? minDislikes),
      )),
      if (showOrg) box(_OrgFilterField(value: orgFilter, onChanged: (v) => onOrg?.call(v))),
    ]);
  }
}

/// The platform's organization filter: an organization id, empty = every organization (Enter applies).
class _OrgFilterField extends StatefulWidget {
  const _OrgFilterField({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_OrgFilterField> createState() => _OrgFilterFieldState();
}

class _OrgFilterFieldState extends State<_OrgFilterField> {
  late final _c = TextEditingController(text: widget.value == null ? '' : '${widget.value}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppField(
        key: const ValueKey('feedback_org_filter'),
        controller: _c,
        label: t('رقم المؤسسة (اختياري)', 'Organization id (optional)'),
        keyboard: TextInputType.number,
        ltr: true,
        onSubmitted: (v) => widget.onChanged(int.tryParse(v.trim())),
      );
}

/// The verified-answer editor: prefilled with the answer that was shown. Pops with the verify body.
class VerifyAnswerSheet extends StatefulWidget {
  const VerifyAnswerSheet({super.key, required this.cluster});
  final FeedbackCluster cluster;

  @override
  State<VerifyAnswerSheet> createState() => _VerifyAnswerSheetState();
}

class _VerifyAnswerSheetState extends State<VerifyAnswerSheet> {
  late final _answer = TextEditingController(text: widget.cluster.answer?.text ?? '');
  late final _question = TextEditingController(text: widget.cluster.question);
  final _variant = TextEditingController();
  final _link = TextEditingController();
  late final List<String> _variants = [for (final q in widget.cluster.questions) if (q != widget.cluster.question) q];
  bool _enabled = true;
  String? _problem;

  @override
  void dispose() {
    for (final c in [_answer, _question, _variant, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addVariant() {
    final v = _variant.text.trim();
    if (v.isEmpty || _variants.contains(v)) return;
    setState(() {
      _variants.add(v);
      _variant.clear();
    });
  }

  void _submit() {
    if (_answer.text.trim().length < 3) {
      setState(() => _problem = t('اكتب الإجابة الموثّقة', 'Write the verified answer'));
      return;
    }
    // a variant typed but not added yet still counts
    final vs = [..._variants, if (_variant.text.trim().isNotEmpty) _variant.text.trim()];
    Navigator.of(context).pop(feedbackVerifyBody(
      answer: _answer.text,
      question: _question.text,
      variants: vs,
      citations: widget.cluster.answer?.citations ?? const [],
      lang: AppConfig.lang,
      deepLink: _link.text,
      enabled: _enabled,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: widget.cluster.isVerified ? t('تعديل الإجابة الموثّقة', 'Edit the verified answer') : t('اكتب الإجابة الموثّقة', 'Write the verified answer'),
      children: [
        AppField(controller: _question, label: t('السؤال', 'Question')),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: _answer, label: t('الإجابة الموثّقة', 'Verified answer'), maxLines: 6),
        const SizedBox(height: AppSpace.sm),
        Text(t('صيغ أخرى للسؤال', 'Question variants'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final v in _variants)
            InputChip(
              key: ValueKey('variant_$v'),
              label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis)),
              onDeleted: () => setState(() => _variants.remove(v)),
              deleteButtonTooltipMessage: t('إزالة', 'Remove'),
            ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: AppField(controller: _variant, label: t('أضف صيغة', 'Add a variant'), onSubmitted: (_) => _addVariant())),
          IconButton(key: const ValueKey('add_variant'), tooltip: t('إضافة', 'Add'), onPressed: _addVariant, icon: const Icon(Icons.add_circle_outline_rounded)),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: _link, label: t('رابط داخل التطبيق (اختياري)', 'In-app link (optional)'), ltr: true, hint: 'account.subscription'),
        AppSwitchTile(title: t('مفعّلة', 'Enabled'), subtitle: t('الإجابة الموثّقة تُعرض أولاً قبل أي توليد', 'A verified answer is used before any generation'), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(_problem!, style: appText(12.5, c: c.danger))),
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(label: t('حفظ وتوثيق', 'Save and verify'), icon: Icons.verified_rounded, onPressed: _submit),
      ],
    );
  }
}

/// The list part, from plain values: counts, filters, clusters, "Load more".
class FeedbackReviewList extends StatelessWidget {
  const FeedbackReviewList({
    super.key,
    required this.page,
    required this.days,
    required this.minDislikes,
    required this.onFilters,
    this.orgFilter,
    this.showOrg = false,
    this.onOrg,
    this.onVerify,
    this.onMore,
    this.loadingMore = false,
  });
  final FeedbackPage page;
  final int days, minDislikes;
  final int? orgFilter;
  final bool showOrg, loadingMore;
  final void Function(int days, int minDislikes) onFilters;
  final ValueChanged<int?>? onOrg;
  final ValueChanged<FeedbackCluster>? onVerify;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FeedbackFiltersBar(days: days, minDislikes: minDislikes, onChanged: onFilters, orgFilter: orgFilter, showOrg: showOrg, onOrg: onOrg),
      const SizedBox(height: AppSpace.sm),
      Text(
          t('${page.total} مجموعة أسئلة · ${page.unhelpful} تقييم سلبي · ${page.helpful} إيجابي', '${page.total} question groups · ${page.unhelpful} unhelpful · ${page.helpful} helpful ratings'),
          style: appText(12.5, w: FontWeight.w600, c: c.textMedium)),
      const SizedBox(height: AppSpace.sm),
      if (page.items.isEmpty)
        AppEmpty(icon: Icons.thumb_up_alt_outlined, title: t('لا إجابات غير مفيدة في هذه المدة', 'No unhelpful answers in this period'))
      else
        for (final k in page.items) FeedbackClusterCard(cluster: k, onVerify: onVerify == null ? null : () => onVerify!(k)),
      if (page.hasMore)
        Center(
          child: OutlinedButton(
            key: const ValueKey('feedback_more'),
            onPressed: loadingMore ? null : onMore,
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text(loadingMore ? t('جارٍ التحميل…', 'Loading…') : t('عرض المزيد', 'Load more')),
          ),
        ),
    ]);
  }
}

/// The review with its calls: load, filter, page, verify.
class FeedbackReviewBody extends StatefulWidget {
  const FeedbackReviewBody({super.key, required this.api, this.canVerify = true});
  final FeedbackReviewApi api;
  final bool canVerify;

  @override
  State<FeedbackReviewBody> createState() => _FeedbackReviewBodyState();
}

class _FeedbackReviewBodyState extends State<FeedbackReviewBody> {
  FeedbackPage? _page;
  String? _error;
  int _days = 30, _min = 1;
  int? _org;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await widget.api.clusters(days: _days, minDislikes: _min, orgFilter: _org);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _page = FeedbackPage.fromJson(r.map);
      } else {
        _error = feedbackErrorText(r);
      }
    });
  }

  Future<void> _loadMore() async {
    final p = _page;
    if (p == null || _more) return;
    setState(() => _more = true);
    final r = await widget.api.clusters(days: _days, minDislikes: _min, orgFilter: _org, limit: p.limit, offset: p.offset + p.items.length);
    if (!mounted) return;
    setState(() {
      _more = false;
      if (r.ok) {
        _page = p.append(FeedbackPage.fromJson(r.map));
      } else {
        showAppNotice(feedbackErrorText(r), error: true);
      }
    });
  }

  Future<void> _verify(FeedbackCluster k) async {
    final body = await showAppSheet<Map<String, dynamic>>(context, (_) => VerifyAnswerSheet(cluster: k));
    if (body == null || !mounted) return;
    final r = await widget.api.verify(k.key, body);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(feedbackErrorText(r), error: true);
      return;
    }
    final purged = asInt(r.map['cache_purged']);
    showAppNotice(purged > 0
        ? t('حُفظت الإجابة الموثّقة وحُذفت $purged إجابة مخزّنة قديمة', 'Verified answer saved; $purged cached answers were cleared')
        : t('حُفظت الإجابة الموثّقة', 'Verified answer saved'));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    if (_error != null && p == null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    }
    if (p == null) return const AppListSkeleton(items: 4, padding: EdgeInsets.all(AppSpace.md));
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!)),
        FeedbackReviewList(
          page: p,
          days: _days,
          minDislikes: _min,
          orgFilter: _org,
          showOrg: widget.api.orgId == null,
          onOrg: (v) {
            _org = v;
            _load();
          },
          onFilters: (d, m) {
            _days = d;
            _min = m;
            _load();
          },
          onVerify: widget.canVerify ? _verify : null,
          onMore: _loadMore,
          loadingMore: _more,
        ),
      ]),
    );
  }
}

/// The page: the Super Admin opens it from the RAG console (`orgId` null), an org manager from the org assistant.
class RagFeedbackReviewPage extends StatelessWidget {
  const RagFeedbackReviewPage({super.key, this.orgId, this.api});
  final int? orgId;
  final FeedbackReviewApi? api;

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('rag.feedback_review'),
      appBar: ScreenAppBar(title: t('مراجعة التقييمات', 'Feedback review')),
      child: FeedbackReviewBody(api: api ?? FeedbackReviewApi(orgId: orgId)),
    );
  }
}
