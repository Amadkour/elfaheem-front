// lib/features/rag/admin/rag_cache_card.dart
//
// The answer-cache card of the RAG console's Settings tab (FRONT_CONTRACTS "Cache"):
//
//   GET  /api/v1/rag/admin/cache        {entries, bytes, hits, semantic_entries, hit_rate, per_org: [{org_id|null, entries,
//                                        bytes, hits}], env_enabled, settings: {cache.enabled, cache.semantic,
//                                        cache.max_entries, cache.org_max_entries}, semantic_min, max_age_days}
//   POST /api/v1/rag/admin/cache/clear  {org_id?} -> {deleted, org_id}
//   PUT  /api/v1/rag/admin/settings     the four `cache.*` keys (the console's RagAdminApi.saveSettings)
//
// Pure, unit-tested: [RagCacheStats], [cacheSettingsBody]. Presentational, under the layout harness: [RagCacheCard].
// [RagCacheSection] owns the calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/rag/rag_library.dart' show ragLibraryCodeText;

class RagCacheOrg {
  const RagCacheOrg({this.orgId, this.entries = 0, this.bytes = 0, this.hits = 0});
  final int? orgId;
  final int entries, bytes, hits;
}

class RagCacheStats {
  const RagCacheStats({
    this.entries = 0,
    this.bytes = 0,
    this.hits = 0,
    this.semanticEntries = 0,
    this.hitRate,
    this.perOrg = const [],
    this.envEnabled = true,
    this.enabled = true,
    this.semantic = true,
    this.maxEntries = 20000,
    this.orgMaxEntries = 0,
    this.semanticMin,
    this.maxAgeDays,
  });

  factory RagCacheStats.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['settings']);
    final rate = j['hit_rate'] == null ? null : asDouble(j['hit_rate']);
    return RagCacheStats(
      entries: asInt(j['entries']),
      bytes: asInt(j['bytes']),
      hits: asInt(j['hits']),
      semanticEntries: asInt(j['semantic_entries']),
      // a fraction (0.42) or already a percent (42)
      hitRate: rate == null ? null : (rate > 1 ? rate / 100 : rate).clamp(0.0, 1.0),
      perOrg: [
        for (final o in asMapList(j['per_org']))
          RagCacheOrg(orgId: o['org_id'] == null ? null : asInt(o['org_id']), entries: asInt(o['entries']), bytes: asInt(o['bytes']), hits: asInt(o['hits'])),
      ],
      envEnabled: asBool(j['env_enabled'], true),
      enabled: asBool(s['cache.enabled'], true),
      semantic: asBool(s['cache.semantic'], true),
      maxEntries: asInt(s['cache.max_entries'], 20000),
      orgMaxEntries: asInt(s['cache.org_max_entries']),
      semanticMin: j['semantic_min'] == null ? null : asDouble(j['semantic_min']),
      maxAgeDays: j['max_age_days'] == null ? null : asInt(j['max_age_days']),
    );
  }

  final int entries, bytes, hits, semanticEntries, maxEntries, orgMaxEntries;
  final double? hitRate, semanticMin;
  final List<RagCacheOrg> perOrg;
  final bool envEnabled, enabled, semantic;
  final int? maxAgeDays;
}

/// The PUT body of the four cache keys.
Map<String, dynamic> cacheSettingsBody({required bool enabled, required bool semantic, required int maxEntries, required int orgMaxEntries}) => {
      'cache.enabled': enabled,
      'cache.semantic': semantic,
      'cache.max_entries': maxEntries,
      'cache.org_max_entries': orgMaxEntries,
    };

String cacheBytesText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _entries(int n) => countText(n, ar1: 'إجابة واحدة', ar2: 'إجابتان', arFew: '{n} إجابات', arMany: '{n} إجابة', en1: '1 entry', en: '{n} entries');

class RagCacheApi {
  RagCacheApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/rag/admin/cache';

  Future<EngineResult> stats() => engineCall(() => _api.get(base));
  Future<EngineResult> clear({int? orgId}) => engineCall(() => _api.post('$base/clear', body: {'org_id': ?orgId}));
}

/// The card: stats, the switches and limits, "Clear all" and "Clear for an organization".
class RagCacheCard extends StatefulWidget {
  const RagCacheCard({super.key, required this.stats, this.onSave, this.onClearAll, this.onClearOrg, this.busy = false});
  final RagCacheStats stats;
  final bool busy;

  /// Called with the PUT body (null hides the Save button: read only).
  final ValueChanged<Map<String, dynamic>>? onSave;
  final VoidCallback? onClearAll;

  /// Asked after the person confirmed.
  final ValueChanged<int>? onClearOrg;

  @override
  State<RagCacheCard> createState() => _RagCacheCardState();
}

class _RagCacheCardState extends State<RagCacheCard> {
  late bool _enabled = widget.stats.enabled;
  late bool _semantic = widget.stats.semantic;
  late final _max = TextEditingController(text: '${widget.stats.maxEntries}');
  late final _orgMax = TextEditingController(text: '${widget.stats.orgMaxEntries}');
  String? _problem;

  @override
  void dispose() {
    _max.dispose();
    _orgMax.dispose();
    super.dispose();
  }

  void _save() {
    final m = int.tryParse(_max.text.trim());
    final o = int.tryParse(_orgMax.text.trim());
    if (m == null || o == null || m < 0 || o < 0) {
      setState(() => _problem = t('أدخل أرقاماً صحيحة (0 = بلا حد)', 'Enter whole numbers (0 = no limit)'));
      return;
    }
    setState(() => _problem = null);
    widget.onSave?.call(cacheSettingsBody(enabled: _enabled, semantic: _semantic, maxEntries: m, orgMaxEntries: o));
  }

  Future<void> _clearAll() async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('مسح الكل', 'Clear all'),
        message: t('مسح كل الإجابات المخزّنة؟ ستُولَّد الإجابات من جديد عند السؤال.', 'Clear every cached answer? Answers are generated again when asked.'));
    if (ok) widget.onClearAll?.call();
  }

  Future<void> _clearOrg([int? known]) async {
    final id = known ?? await showAppSheet<int>(context, (_) => const _OrgIdSheet());
    if (id == null || !mounted) return;
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('مسح', 'Clear'),
        message: t('مسح الإجابات المخزّنة للمؤسسة #$id؟', 'Clear the cached answers of organization #$id?'));
    if (ok) widget.onClearOrg?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.stats;
    final rate = s.hitRate;
    return AppCard(
      key: const ValueKey('rag_cache_card'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('ذاكرة الإجابات المؤقتة', 'Answer cache'), subtitle: t('إجابات مشتركة حسب النطاق، لا حسب المستخدم', 'Shared answers per scope, never per user')),
        if (!s.envEnabled) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: t('الذاكرة المؤقتة معطّلة من إعدادات الخادم نفسه', 'The cache is switched off in the server\'s own configuration')),
        ],
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          _Tile(icon: Icons.inventory_2_outlined, label: t('إجابات مخزّنة', 'Entries'), value: '${s.entries}'),
          _Tile(icon: Icons.sd_storage_outlined, label: t('الحجم', 'Size'), value: cacheBytesText(s.bytes)),
          _Tile(icon: Icons.bolt_rounded, label: t('نسبة الإصابة', 'Hit rate'), value: rate == null ? '—' : '${(rate * 100).round()}%'),
          _Tile(icon: Icons.manage_search_rounded, label: t('دلالية', 'Semantic'), value: '${s.semanticEntries}'),
        ]),
        if (s.perOrg.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('الأكثر استخداماً حسب المؤسسة', 'Top by organization'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
          for (final o in s.perOrg.take(8))
            Padding(
              key: ValueKey('cache_org_${o.orgId ?? 'platform'}'),
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${o.orgId == null ? t('التطبيق (عام)', 'App (global)') : t('المؤسسة #${o.orgId}', 'Organization #${o.orgId}')} · ${_entries(o.entries)} · ${cacheBytesText(o.bytes)}',
                      style: appText(12.5, c: c.textDark)),
                ),
                if (o.orgId != null && widget.onClearOrg != null)
                  IconButton(
                      key: ValueKey('cache_clear_org_${o.orgId}'),
                      tooltip: t('مسح هذه المؤسسة', 'Clear this organization'),
                      onPressed: widget.busy ? null : () => _clearOrg(o.orgId),
                      icon: Icon(Icons.delete_sweep_outlined, size: 20, color: c.danger)),
              ]),
            ),
        ],
        const SizedBox(height: AppSpace.sm),
        AppSwitchTile(title: t('تفعيل الذاكرة المؤقتة', 'Cache answers'), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
        AppSwitchTile(
            title: t('مطابقة دلالية', 'Semantic matching'),
            subtitle: s.semanticMin == null
                ? t('سؤال شبه مطابق يصيب الذاكرة أيضاً', 'A near-identical question hits the cache too')
                : t('سؤال شبه مطابق (تشابه ≥ ${s.semanticMin}) يصيب الذاكرة أيضاً', 'A near-identical question (similarity ≥ ${s.semanticMin}) hits the cache too'),
            value: _semantic,
            onChanged: (v) => setState(() => _semantic = v)),
        const SizedBox(height: AppSpace.xs),
        AppNumberField(controller: _max, label: t('أقصى عدد إجابات (0 = بلا حد)', 'Max entries (0 = no limit)'), min: 0, step: 100),
        const SizedBox(height: AppSpace.sm),
        AppNumberField(controller: _orgMax, label: t('أقصى عدد لكل مؤسسة (0 = بلا حد)', 'Max entries per organization (0 = no limit)'), min: 0, step: 100),
        if (s.maxAgeDays != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
            child: Text(t('تنتهي صلاحية الإجابة بعد ${s.maxAgeDays} يوماً', 'An entry expires after ${s.maxAgeDays} days'), style: appText(12, c: c.textLight)),
          ),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(_problem!, style: appText(12.5, c: c.danger))),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (widget.onSave != null)
            FilledButton.icon(
              key: const ValueKey('cache_save'),
              onPressed: widget.busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(t('حفظ إعدادات الذاكرة', 'Save cache settings')),
            ),
          if (widget.onClearAll != null)
            OutlinedButton.icon(
              key: const ValueKey('cache_clear_all'),
              onPressed: widget.busy ? null : _clearAll,
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(t('مسح الكل', 'Clear all')),
            ),
          if (widget.onClearOrg != null)
            OutlinedButton.icon(
              key: const ValueKey('cache_clear_org'),
              onPressed: widget.busy ? null : _clearOrg,
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: const Icon(Icons.apartment_rounded, size: 18),
              label: Text(t('مسح لمؤسسة', 'Clear for an organization')),
            ),
        ]),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.textDark)),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textLight)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OrgIdSheet extends StatefulWidget {
  const _OrgIdSheet();

  @override
  State<_OrgIdSheet> createState() => _OrgIdSheetState();
}

class _OrgIdSheetState extends State<_OrgIdSheet> {
  final _c = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    final id = int.tryParse(_c.text.trim());
    if (id == null || id <= 0) return setState(() => _problem = t('أدخل رقم مؤسسة صحيحاً', 'Enter a valid organization id'));
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(title: t('مسح ذاكرة مؤسسة', 'Clear an organization\'s cache'), children: [
        AppField(controller: _c, label: t('رقم المؤسسة', 'Organization id'), keyboard: TextInputType.number, ltr: true, onSubmitted: (_) => _go()),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(_problem!, style: appText(12.5, c: context.colors.danger))),
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(label: t('متابعة', 'Continue'), icon: Icons.arrow_forward_rounded, onPressed: _go),
      ]);
}

/// The card with its calls (the Settings tab of the console). Hidden when the server has no cache route.
class RagCacheSection extends StatefulWidget {
  const RagCacheSection({super.key, this.api, required this.saveSettings});
  final RagCacheApi? api;

  /// `RagAdminApi.saveSettings`.
  final Future<EngineResult> Function(Map<String, dynamic> body) saveSettings;

  @override
  State<RagCacheSection> createState() => _RagCacheSectionState();
}

class _RagCacheSectionState extends State<RagCacheSection> {
  late final RagCacheApi _api = widget.api ?? RagCacheApi();
  RagCacheStats? _stats;
  bool _unavailable = false, _busy = false;
  int _gen = 0; // the card's inputs restart from the server's values after a reload

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.stats();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _stats = RagCacheStats.fromJson(r.map);
        _gen++;
      } else {
        _unavailable = true;
      }
    });
  }

  Future<void> _run(Future<EngineResult> Function() call, String Function(EngineResult r) okText) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showAppNotice(okText(r));
      await _load();
    } else {
      showAppNotice(ragLibraryCodeText(r.code, r.message), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (_unavailable) return const SizedBox.shrink();
    if (s == null) return const AppListSkeleton(items: 2, padding: EdgeInsets.zero);
    return RagCacheCard(
      key: ValueKey('cache_$_gen'),
      stats: s,
      busy: _busy,
      onSave: (body) => _run(() => widget.saveSettings(body), (_) => t('حُفظت إعدادات الذاكرة', 'Cache settings saved')),
      onClearAll: () => _run(_api.clear, (r) => t('مُسحت ${asInt(r.map['deleted'])} إجابة', '${asInt(r.map['deleted'])} cached answers cleared')),
      onClearOrg: (id) => _run(() => _api.clear(orgId: id), (r) => t('مُسحت ${asInt(r.map['deleted'])} إجابة للمؤسسة #$id', '${asInt(r.map['deleted'])} cached answers of organization #$id cleared')),
    );
  }
}
