// lib/features/admin/admin_feature_guide.dart
//
// The app features guide: every user-level feature — who has it (student, teacher, parent, organization staff,
// admins …), where it is and how to use it, in Arabic and English. The app assistant (RAG) answers "how do I …"
// from it. Seeded from the server's data/app_features_guide.json (update it with every new feature — CLAUDE.md);
// the super admin edits, adds and deletes here, and decides per feature where it shows:
//   • App        — the feature's kill-switch keys (the Features page rows). Hidden = all of them off on every
//                  platform; hidden on some platforms only = "partial". A feature without keys can't be hidden here.
//   • Assistant  — whether the assistant may explain it. A feature hidden in the app is left out of the assistant
//                  automatically.
// Changes reach the assistant on its next pass over the app pages (every few hours) or at once with "Update the
// assistant now" (POST /api/v1/rag/app/documents/sync). Opened from the app assistant dashboard and the Features page.
//
// GET/POST /api/v1/admin/features/guide · GET …/preview?lang= · PUT …/{key} · PUT …/{key}/visibility {app?, rag?} ·
// POST …/{key}/reset · DELETE …/{key}
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../org/org_v3.dart';
import '../shared/rag/rag_library.dart' show RagLibraryApi, ragOutcomeSummary, ragResultText;
import 'admin_common.dart' show asInt, asMap, asMapList, t;

const _guide = '/api/v1/admin/features/guide';
const guidePlatformNames = {'android': 'Android', 'ios': 'iOS', 'web': 'Web'};

/// One feature of the guide (the server's item map, read through getters).
class GuideFeature {
  GuideFeature(this.j);
  final Map<String, dynamic> j;

  String get key => '${j['key']}';
  String get group => '${j['group'] ?? ''}';
  List<String> get roles => [for (final r in (j['roles'] as List? ?? const [])) '$r'];
  List<String> get switchKeys => [for (final k in (j['switch_keys'] as List? ?? const [])) '$k'];
  List<String> get hiddenOn => [for (final p in (j['hidden_on'] as List? ?? const [])) '$p'];
  List<String> steps(String lang) => [for (final s in (j['steps_$lang'] as List? ?? const [])) '$s'];
  String text(String name, String lang) => '${j['${name}_$lang'] ?? ''}'.trim();

  String get title {
    final s = t(text('title', 'ar'), text('title', 'en'));
    return s.isEmpty ? key : s;
  }

  String get summary => t(text('summary', 'ar'), text('summary', 'en'));

  /// none (no switch keys) · shown · partial · hidden
  String get appState => '${j['app_state'] ?? 'none'}';
  bool get rag => j['rag_enabled'] == true;
  bool get inAssistant => j['in_assistant'] == true;
  bool get edited => j['edited'] == true;
  bool get resettable => j['resettable'] == true;
  bool get custom => j['source'] == 'custom';
}

enum GuideShow { all, inAssistant, notInAssistant, hiddenInApp }

/// The page's filters: search text (key, both titles, summaries, places), group, role ("everyone" features match
/// every role) and what is shown where.
bool guideMatches(GuideFeature f, {String q = '', String? group, String? role, GuideShow show = GuideShow.all}) {
  if (group != null && f.group != group) return false;
  if (role != null && !f.roles.contains(role) && !f.roles.contains('everyone')) return false;
  final wanted = switch (show) {
    GuideShow.all => true,
    GuideShow.inAssistant => f.inAssistant,
    GuideShow.notInAssistant => !f.inAssistant,
    GuideShow.hiddenInApp => f.appState == 'hidden',
  };
  if (!wanted) return false;
  final s = q.trim().toLowerCase();
  if (s.isEmpty) return true;
  return [f.key, for (final n in ['title', 'summary', 'where']) for (final l in ['ar', 'en']) f.text(n, l)]
      .join(' ')
      .toLowerCase()
      .contains(s);
}

/// A steps field → the steps: one per line, blank lines dropped.
List<String> guideSteps(String text) => [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

/// Where the feature shows in the app, in words ("" when it is simply shown).
String guideAppStateText(GuideFeature f) => switch (f.appState) {
      'hidden' => t('مخفية في التطبيق', 'Hidden in the app'),
      'partial' => t('مخفية على: ', 'Hidden on: ') + f.hiddenOn.map((p) => guidePlatformNames[p] ?? p).join(t('، ', ', ')),
      'none' => t('غير مربوطة بمفتاح في التطبيق', 'Not linked to an app switch'),
      _ => '',
    };

// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class AdminFeatureGuidePage extends StatefulWidget {
  const AdminFeatureGuidePage({super.key});

  @override
  State<AdminFeatureGuidePage> createState() => _AdminFeatureGuidePageState();
}

class _AdminFeatureGuidePageState extends State<AdminFeatureGuidePage> {
  Map<String, dynamic>? _data;
  String? _error;
  String _q = '';
  String? _group, _role;
  GuideShow _show = GuideShow.all;
  final Set<String> _busy = {};
  bool _dirty = false; // changed since the assistant last re-read the app pages
  bool _syncing = false;

  bool get _super => _data?['is_super_admin'] == true;
  List<GuideFeature> get _items => [for (final m in asMapList(_data?['items'])) GuideFeature(m)];
  Map<String, String> get _groups => {for (final g in asMapList(_data?['groups'])) '${g['id']}': t('${g['title_ar']}', '${g['title_en']}')};
  Map<String, String> get _roles => {for (final r in asMapList(_data?['roles'])) '${r['id']}': t('${r['title_ar']}', '${r['title_en']}')};
  Map<String, String> get _switches => {for (final s in asMapList(_data?['switches'])) '${s['key']}': t('${s['title_ar']}', '${s['title_en']}')};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(_guide), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _data = r.map;
        _error = null;
      } else {
        _error = r.endpointMissing ? t('دليل الميزات يحتاج تحديث الخادم.', 'The features guide needs a server update.') : orgErrorText(r.error!);
      }
    });
  }

  /// Applies a write's answer (every write returns the whole guide). True when it worked.
  bool _take(OrgCall r) {
    if (!r.ok || r.map['items'] is! List) return false;
    setState(() {
      _data = r.map;
      _dirty = true;
    });
    return true;
  }

  Future<bool> _write(String key, Future<dynamic> Function() fn, {String? ok}) async {
    setState(() => _busy.add(key));
    final r = await orgCall(fn, ok: ok);
    if (mounted) setState(() => _busy.remove(key));
    return mounted && _take(r);
  }

  Future<bool> _visibility(GuideFeature f, {bool? app, bool? rag}) =>
      _write(f.key, () => ApiClient().put('$_guide/${Uri.encodeComponent(f.key)}/visibility', body: {'app': ?app, 'rag': ?rag}));

  Future<void> _syncAssistant() async {
    setState(() => _syncing = true);
    final r = await RagLibraryApi().syncApp();
    if (!mounted) return;
    setState(() => _syncing = false);
    if (!r.ok) return appToast(ragResultText(r), error: true);
    final o = <String>[for (final k in ['added', 'updated', 'unchanged']) for (var i = 0; i < asInt(r.map[k]); i++) k];
    setState(() => _dirty = false);
    appToast(o.isEmpty ? t('المساعد محدَّث', 'The assistant is up to date') : ragOutcomeSummary(o));
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('rag.features_guide'),
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: t('دليل ميزات التطبيق', 'App features guide'), actions: [
        if (_data != null)
          IconButton(tooltip: t('ما يقرؤه المساعد', 'What the assistant reads'), icon: const Icon(Icons.article_outlined), onPressed: _openPreview),
        IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ]),
      floatingActionButton: _super
          ? FloatingActionButton.extended(onPressed: () => _openEditor(null), icon: const Icon(Icons.add_rounded), label: Text(t('ميزة جديدة', 'New feature')))
          : null,
      child: _error != null
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load)
          : _data == null
              ? const AppListSkeleton(items: 8)
              : _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final c = context.colors;
    final shown = _items.where((f) => guideMatches(f, q: _q, group: _group, role: _role, show: _show)).toList();
    final groups = _groups, roles = _roles;
    final byGroup = <String, List<GuideFeature>>{};
    for (final f in shown) {
      byGroup.putIfAbsent(f.group, () => []).add(f);
    }
    final rows = <Object>[];
    for (final g in [...groups.keys, ...byGroup.keys.where((k) => !groups.containsKey(k))]) {
      final list = byGroup[g];
      if (list == null || list.isEmpty) continue;
      rows.add((groups[g] ?? g, list.length));
      rows.addAll(list);
    }
    final counts = asMap(_data!['counts']);

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(children: [
            AppHero(
              title: t('دليل ميزات التطبيق', 'App features guide'),
              subtitle: t('ما يعرفه مساعد التطبيق عن الميزات: لمن هي، وأين، وكيف تُستخدم.', 'What the app assistant knows about the features: who has them, where, and how to use them.'),
              icon: Icons.menu_book_rounded,
              stats: [
                AppHeroStat(icon: Icons.widgets_rounded, value: '${counts['total'] ?? 0}', label: t('ميزة', 'Features')),
                AppHeroStat(icon: Icons.smart_toy_rounded, value: '${counts['in_assistant'] ?? 0}', label: t('يشرحها المساعد', 'In the assistant')),
                AppHeroStat(icon: Icons.visibility_off_rounded, value: '${counts['hidden_in_app'] ?? 0}', label: t('مخفية في التطبيق', 'Hidden in the app')),
              ],
            ),
            const SizedBox(height: 12),
            if (_super)
              AppBanner(
                icon: _dirty ? Icons.sync_problem_rounded : Icons.info_outline_rounded,
                color: _dirty ? c.warning : c.primary,
                text: _dirty
                    ? t('تصل تعديلاتك للمساعد خلال ساعات، أو الآن بزر «حدّث المساعد الآن».', 'Your changes reach the assistant within hours, or right now with "Update the assistant now".')
                    : t('«التطبيق» يخفي مفاتيح الميزة في كل المنصات، و«المساعد» يحدد هل يشرحها. الميزة المخفية في التطبيق لا يشرحها المساعد.',
                        '"App" turns the feature\'s switches off on every platform; "Assistant" decides whether it is explained. A feature hidden in the app is never explained.'),
              ),
            if (_super) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppPill(
                    icon: Icons.sync_rounded,
                    label: _syncing ? t('جارٍ التحديث…', 'Updating…') : t('حدّث المساعد الآن', 'Update the assistant now'),
                    onTap: _syncing ? null : _syncAssistant),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('ابحث بالاسم أو المفتاح أو الوصف', 'Search by name, key or description')),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              AppChoiceChip(label: t('الكل', 'All'), selected: _show == GuideShow.all, onTap: () => setState(() => _show = GuideShow.all)),
              AppChoiceChip(
                  label: t('في المساعد', 'In the assistant'),
                  icon: Icons.smart_toy_rounded,
                  selected: _show == GuideShow.inAssistant,
                  onTap: () => setState(() => _show = GuideShow.inAssistant)),
              AppChoiceChip(
                  label: t('ليست في المساعد', 'Not in the assistant'),
                  icon: Icons.block_rounded,
                  selected: _show == GuideShow.notInAssistant,
                  onTap: () => setState(() => _show = GuideShow.notInAssistant)),
              AppChoiceChip(
                  label: t('مخفية في التطبيق', 'Hidden in the app'),
                  icon: Icons.visibility_off_rounded,
                  selected: _show == GuideShow.hiddenInApp,
                  onTap: () => setState(() => _show = GuideShow.hiddenInApp)),
            ]),
            const SizedBox(height: 10),
            AppPicker<String>(
                label: t('الدور', 'Role'),
                icon: Icons.badge_outlined,
                value: _role,
                allowNone: true,
                noneLabel: t('كل الأدوار', 'Every role'),
                options: roles,
                onChanged: (v) => setState(() => _role = v)),
            AppPicker<String>(
                label: t('المجموعة', 'Group'),
                icon: Icons.folder_open_rounded,
                value: _group,
                allowNone: true,
                noneLabel: t('كل المجموعات', 'All groups'),
                options: {for (final g in asMapList(_data!['groups'])) '${g['id']}': '${groups['${g['id']}']} (${g['count']})'},
                onChanged: (v) => setState(() => _group = v)),
            const SizedBox(height: 6),
          ]),
        ),
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmpty(
                icon: Icons.search_off_rounded,
                title: t('لا توجد ميزات مطابقة', 'No matching features'),
                actionLabel: t('مسح الفلاتر', 'Clear filters'),
                onAction: () => setState(() {
                      _q = '';
                      _group = _role = null;
                      _show = GuideShow.all;
                    })),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final row = rows[i];
                if (row is (String, int)) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                    child: Row(children: [
                      Expanded(child: Text(row.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w800, c: c.textDark))),
                      Text('${row.$2}', style: appText(12, c: c.textLight)),
                    ]),
                  );
                }
                final f = row as GuideFeature;
                final busy = _busy.contains(f.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GuideFeatureTile(
                    feature: f,
                    roleNames: roles,
                    onTap: () => _openEditor(f),
                    onApp: _super && !busy && f.appState != 'none' ? (v) => _visibility(f, app: v) : null,
                    onRag: _super && !busy ? (v) => _visibility(f, rag: v) : null,
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }

  Future<void> _openEditor(GuideFeature? f) => showAppSheet<void>(
      context,
      (ctx) => GuideFeatureEditor(
            feature: f,
            groups: _groups,
            roles: _roles,
            switches: _switches,
            readOnly: !_super,
            onSave: (body) => f == null
                ? _write(body['key'] as String, () => ApiClient().post(_guide, body: body), ok: t('تمت إضافة الميزة', 'Feature added'))
                : _write(f.key, () => ApiClient().put('$_guide/${Uri.encodeComponent(f.key)}', body: body), ok: t('تم الحفظ', 'Saved')),
            onReset: f != null && f.resettable
                ? () => _write(f.key, () => ApiClient().post('$_guide/${Uri.encodeComponent(f.key)}/reset'), ok: t('أُعيد النص الأصلي', 'Original text restored'))
                : null,
            onDelete: f == null
                ? null
                : () async {
                    final ok = await appConfirm(context,
                        danger: true,
                        confirmLabel: t('حذف', 'Delete'),
                        message: t('حذف «${f.title}» من الدليل؟ لن يشرحها المساعد بعد الآن، ولا يتغير شيء في التطبيق.',
                            'Delete "${f.title}" from the guide? The assistant no longer explains it; nothing changes in the app.'));
                    return ok && await _write(f.key, () => ApiClient().delete('$_guide/${Uri.encodeComponent(f.key)}'), ok: t('تم الحذف', 'Deleted'));
                  },
          ));

  Future<void> _openPreview() => showAppSheet<void>(context, (_) => const _PreviewSheet());
}

// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Pieces (presentational — tested with the layout harness)
// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// One row: title, key, who has it, summary, state badges, and the two quick switches (App · Assistant) as chips.
class GuideFeatureTile extends StatelessWidget {
  const GuideFeatureTile({super.key, required this.feature, required this.roleNames, this.onTap, this.onApp, this.onRag});
  final GuideFeature feature;
  final Map<String, String> roleNames;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onApp, onRag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = feature;
    final state = guideAppStateText(f);
    final appOn = f.appState != 'hidden';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
        Text(f.key, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: appText(11, c: c.textLight).copyWith(fontFamily: 'monospace')),
        Text(f.roles.map((r) => roleNames[r] ?? r).join(t('، ', ', ')), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.primary)),
        if (f.summary.isNotEmpty) Text(f.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (f.appState != 'none')
            AppChoiceChip(
                label: t('التطبيق', 'App'),
                icon: appOn ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                selected: appOn,
                onTap: onApp == null ? () {} : () => onApp!(!appOn)),
          AppChoiceChip(
              label: t('المساعد', 'Assistant'),
              icon: f.rag ? Icons.smart_toy_rounded : Icons.block_rounded,
              selected: f.rag,
              onTap: onRag == null ? () {} : () => onRag!(!f.rag)),
          if (state.isNotEmpty) AppBadgePill(state, color: f.appState == 'none' ? c.textLight : c.warning, icon: Icons.devices_rounded),
          if (f.rag && !f.inAssistant) AppBadgePill(t('لا يشرحها المساعد وهي مخفية', 'Not explained while hidden'), color: c.textLight),
          if (f.edited) AppBadgePill(t('معدّلة', 'Edited'), color: c.purple),
          if (f.custom) AppBadgePill(t('مضافة', 'Custom'), color: c.purple),
        ]),
      ]),
    );
  }
}

/// Add / edit one feature (read-only for admins who are not the super admin). [onSave] gets the PUT / POST body and
/// says whether it worked; the sheet closes on success.
class GuideFeatureEditor extends StatefulWidget {
  const GuideFeatureEditor({
    super.key,
    required this.feature,
    required this.groups,
    required this.roles,
    required this.switches,
    required this.onSave,
    this.readOnly = false,
    this.onReset,
    this.onDelete,
  });

  final GuideFeature? feature;
  final Map<String, String> groups, roles, switches;
  final bool readOnly;
  final Future<bool> Function(Map<String, dynamic> body) onSave;
  final Future<bool> Function()? onReset, onDelete;

  @override
  State<GuideFeatureEditor> createState() => _GuideFeatureEditorState();
}

class _GuideFeatureEditorState extends State<GuideFeatureEditor> {
  late final GuideFeature? f = widget.feature;
  late final _key = TextEditingController(text: f?.key ?? '');
  late final Map<String, TextEditingController> _text = {
    for (final n in ['title', 'summary', 'where'])
      for (final l in ['ar', 'en']) '${n}_$l': TextEditingController(text: f?.text(n, l) ?? ''),
    'steps_ar': TextEditingController(text: f?.steps('ar').join('\n') ?? ''),
    'steps_en': TextEditingController(text: f?.steps('en').join('\n') ?? ''),
  };
  late String? _group = f?.group ?? (widget.groups.isEmpty ? null : widget.groups.keys.first);
  late final Set<String> _roles = {...?f?.roles};
  late final List<String> _keys = [...?f?.switchKeys];
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() fn) async {
    setState(() => _busy = true);
    final ok = await fn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  void _save() {
    String v(String k) => _text[k]!.text.trim();
    if (f == null && _key.text.trim().length < 2) return appToast(t('اكتب مفتاح الميزة', 'Enter the feature key'), error: true);
    if ([for (final k in ['title_ar', 'title_en', 'summary_ar', 'summary_en']) v(k)].any((s) => s.isEmpty)) {
      return appToast(t('الاسم والوصف مطلوبان باللغتين', 'The name and summary are required in both languages'), error: true);
    }
    if (_roles.isEmpty || _group == null) return appToast(t('اختر المجموعة ودوراً واحداً على الأقل', 'Pick the group and at least one role'), error: true);
    _run(() => widget.onSave({
          if (f == null) 'key': _key.text.trim().toLowerCase(),
          'group': _group,
          'roles': [for (final r in widget.roles.keys) if (_roles.contains(r)) r],
          for (final k in ['title_ar', 'title_en', 'summary_ar', 'summary_en']) k: v(k),
          'where_ar': v('where_ar').isEmpty ? null : v('where_ar'),
          'where_en': v('where_en').isEmpty ? null : v('where_en'),
          'steps_ar': guideSteps(_text['steps_ar']!.text),
          'steps_en': guideSteps(_text['steps_en']!.text),
          'switch_keys': _keys,
        }));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ro = widget.readOnly;
    Widget label(String s) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: Text(s, style: appText(12.5, w: FontWeight.w800, c: c.textMedium)));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(f == null ? t('ميزة جديدة في الدليل', 'New guide feature') : f!.title),
        if (f != null)
          SelectableText(f!.key, textDirection: TextDirection.ltr, style: appText(12, c: c.textLight).copyWith(fontFamily: 'monospace'))
        else
          AppField(controller: _key, label: t('المفتاح (مثل offline_downloads)', 'Key (e.g. offline_downloads)'), ltr: true),
        if (ro) ..._readOnly(context, label) else ..._form(context, label),
      ]),
    );
  }

  List<Widget> _readOnly(BuildContext context, Widget Function(String) label) {
    final c = context.colors;
    final x = f!;
    String lang(String n) => t(x.text(n, 'ar'), x.text(n, 'en'));
    return [
      label(t('لمن', 'Who has it')),
      Text(x.roles.map((r) => widget.roles[r] ?? r).join(t('، ', ', ')), style: appText(13, c: c.textDark)),
      label(t('الوصف', 'Summary')),
      Text(lang('summary'), style: appText(13, c: c.textDark)),
      if (lang('where').isNotEmpty) ...[label(t('مكانها', 'Where')), Text(lang('where'), style: appText(13, c: c.textDark))],
      if (x.steps(t('ar', 'en')).isNotEmpty) ...[
        label(t('الخطوات', 'Steps')),
        for (final (i, s) in x.steps(t('ar', 'en')).indexed) Text('${i + 1}. $s', style: appText(13, c: c.textDark)),
      ],
      const SizedBox(height: 10),
      Text(t('التعديل لمدير المنصة الأعلى فقط.', 'Only the super admin can edit the guide.'), style: appText(11.5, c: c.textLight)),
    ];
  }

  List<Widget> _form(BuildContext context, Widget Function(String) label) {
    final c = context.colors;
    final left = {for (final e in widget.switches.entries) if (!_keys.contains(e.key)) e.key: '${e.value} · ${e.key}'};
    return [
      AppPicker<String>(label: t('المجموعة', 'Group'), icon: Icons.folder_open_rounded, value: _group, options: widget.groups, onChanged: (v) => setState(() => _group = v)),
      label(t('لمن هذه الميزة', 'Who has this feature')),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in widget.roles.entries)
          AppChoiceChip(
              label: r.value,
              selected: _roles.contains(r.key),
              onTap: () => setState(() => _roles.contains(r.key) ? _roles.remove(r.key) : _roles.add(r.key))),
      ]),
      label(t('الاسم والوصف', 'Name and summary')),
      AppField(controller: _text['title_ar']!, label: t('الاسم بالعربية', 'Arabic name')),
      AppField(controller: _text['title_en']!, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
      AppField(controller: _text['summary_ar']!, label: t('ماذا تفعل (بالعربية)', 'What it does (Arabic)'), maxLines: 3),
      AppField(controller: _text['summary_en']!, label: t('ماذا تفعل (بالإنجليزية)', 'What it does (English)'), maxLines: 3, ltr: true),
      label(t('مكانها وطريقة استخدامها', 'Where it is and how to use it')),
      AppField(controller: _text['where_ar']!, label: t('مكانها (مثل: الملف الشخصي › التنزيلات)', 'Where (e.g. Profile › Downloads), Arabic')),
      AppField(controller: _text['where_en']!, label: t('مكانها بالإنجليزية', 'Where, English'), ltr: true),
      AppField(controller: _text['steps_ar']!, label: t('الخطوات بالعربية — خطوة في كل سطر', 'Steps in Arabic — one per line'), maxLines: 5),
      AppField(controller: _text['steps_en']!, label: t('الخطوات بالإنجليزية — خطوة في كل سطر', 'Steps in English — one per line'), maxLines: 5, ltr: true),
      label(t('مفاتيح التطبيق', 'App switches')),
      Text(
          t('إخفاء الميزة في التطبيق يطفئ كل هذه المفاتيح على كل المنصات (نفس صفحة «الميزات»). بدون مفاتيح لا يمكن إخفاؤها من هنا.',
              'Hiding the feature in the app turns all these switches off on every platform (the same rows as the Features page). Without switches it cannot be hidden from here.'),
          style: appText(11.5, c: c.textLight)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final k in _keys)
          InputChip(
            label: Text(widget.switches[k] ?? k, overflow: TextOverflow.ellipsis),
            onDeleted: () => setState(() => _keys.remove(k)),
          ),
      ]),
      AppPicker<String>(
          label: t('أضف مفتاحاً', 'Add a switch'),
          icon: Icons.toggle_on_outlined,
          value: null,
          options: left,
          onChanged: (v) {
            if (v != null) setState(() => _keys.add(v));
          }),
      const SizedBox(height: 14),
      AppPrimaryButton(label: f == null ? t('إضافة', 'Add') : t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _save),
      if (widget.onReset != null)
        TextButton.icon(
            icon: const Icon(Icons.restore_rounded),
            label: Text(t('استعادة النص الأصلي', 'Restore the original text')),
            onPressed: _busy ? null : () => _run(widget.onReset!)),
      if (widget.onDelete != null)
        TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.danger),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(t('حذف من الدليل', 'Delete from the guide')),
            onPressed: _busy ? null : () => _run(widget.onDelete!)),
    ];
  }
}

/// Exactly what the assistant indexes, in either language.
class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet();

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  String _lang = t('ar', 'en');
  String? _md;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _md = null);
    final r = await orgCall(() => ApiClient().get('$_guide/preview', queryParams: {'lang': _lang}));
    if (mounted) setState(() => _md = r.ok ? '${r.map['markdown'] ?? ''}' : orgErrorText(r.error!));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('ما يقرؤه المساعد', 'What the assistant reads')),
        Wrap(spacing: 8, children: [
          for (final l in ['ar', 'en'])
            AppChoiceChip(label: l == 'ar' ? 'العربية' : 'English', selected: _lang == l, onTap: () {
              _lang = l;
              _load();
            }),
        ]),
        const SizedBox(height: 10),
        Flexible(
          child: _md == null
              ? const AppListSkeleton(items: 4)
              : SingleChildScrollView(
                  child: SelectableText(_md!, textDirection: _lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, style: appText(12.5, c: c.textDark, h: 1.5))),
        ),
      ]),
    );
  }
}
