// lib/features/admin/admin_features_page.dart
//
// Feature catalog (super admin / admins): every switchable part of the app in ONE grouped list.
//   • search (name / key / description), filters: group · on/off · "organization admins may manage"
//   • the switch = shown / hidden on every platform; the detail sheet has per-platform control, the admin grant,
//     the organization grant, the description, and delete (features added from here only)
//   • "Add feature": key + Arabic / English names + group (existing or new) + description + grants
// A feature switched OFF here disappears for everyone — organization admins can never switch it back on.
// The super admin sees the AI controls first (admin_ai_controls.dart, D-780): the same keys, switched on every platform.
// The app bar opens the app features guide (admin_feature_guide.dart): user-level features built on these switches,
// with what the app assistant explains about each.
//
// GET/POST /api/v1/admin/features/catalog · PUT …/catalog/{key}/org-manageable · PUT …/catalog/{key}/description ·
// DELETE …/catalog/{key} · PUT /api/v1/admin/features/{key} {hidden, platforms} · PUT /api/v1/admin/features/{key}/access
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../org/org_v3.dart';
import 'admin_ai_controls.dart' show AiControlsSection;
import 'admin_common.dart' show asMap, asMapList, t;
import 'admin_feature_guide.dart' show AdminFeatureGuidePage;
import 'admin_labels.dart' show disposeAfterRoute;
import 'admin_page.dart';
import 'cfg_common.dart';

const _catalog = '/api/v1/admin/features/catalog';
const _features = '/api/v1/admin/features';
const _platformNames = {'android': 'Android', 'ios': 'iOS', 'web': 'Web'};

class AdminFeaturesPage extends StatefulWidget {
  const AdminFeaturesPage({super.key});

  @override
  State<AdminFeaturesPage> createState() => _AdminFeaturesPageState();
}

enum _State { all, on, off }

class _AdminFeaturesPageState extends State<AdminFeaturesPage> {
  Map<String, dynamic>? _data;
  ApiException? _error;
  String _q = '';
  String? _group;
  _State _state = _State.all;
  bool _orgOnly = false;
  final Set<String> _busy = {};

  bool get _super => _data?['is_super_admin'] == true;
  List<Map<String, dynamic>> get _items => asMapList(_data?['items']);
  List<Map<String, dynamic>> get _tabs => asMapList(_data?['tabs']);
  List<String> get _platforms => [for (final p in (_data?['platforms'] as List? ?? const ['android', 'ios', 'web'])) '$p'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The AI controls section reloads with the list (D-802): pull-to-refresh, or a key switched in the list below.
  int _aiGeneration = 0;

  Future<void> _refresh() {
    setState(() => _aiGeneration++);
    return _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(_catalog), quiet: true);
    if (!mounted) return;
    // a failed refresh keeps the loaded list: a notice, never an empty page
    if (!r.ok && _data != null) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    setState(() {
      if (r.ok) {
        _data = r.map;
        _error = null;
      } else {
        _error = r.error;
      }
    });
  }

  void _take(OrgCall r) {
    if (r.ok && r.map['items'] is List) setState(() => _data = r.map);
  }

  String _title(Map<String, dynamic> f) {
    final s = t('${f['title_ar'] ?? ''}', '${f['title_en'] ?? ''}').trim();
    return s.isEmpty ? '${f['key']}' : s;
  }

  String? _desc(Map<String, dynamic> f) {
    final s = t('${f['description_ar'] ?? ''}', '${f['description_en'] ?? ''}').trim();
    return s.isEmpty ? null : s;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _q.trim().toLowerCase();
    return _items.where((f) {
      if (_group != null && f['tab'] != _group) return false;
      final hidden = f['hidden'] == true;
      if (_state == _State.on && hidden) return false;
      if (_state == _State.off && !hidden) return false;
      if (_orgOnly && f['org_manageable'] != true) return false;
      if (q.isEmpty) return true;
      return '${f['key']} ${f['title_ar']} ${f['title_en']} ${f['description_ar'] ?? ''} ${f['description_en'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _setVisible(Map<String, dynamic> f, bool visible, {List<String>? platforms}) async {
    final key = '${f['key']}';
    if (_busy.contains(key)) return;
    if (!visible) {
      // switching a feature OFF hides it in every app immediately: say which one, and for whom
      final hiddenNow = {for (final p in (f['platforms'] as List? ?? const [])) '$p'};
      final everywhere = (platforms ?? _platforms).toSet().union(hiddenNow).containsAll(_platforms);
      if (everywhere) {
        final ok = await appConfirm(context,
            danger: true,
            confirmLabel: t('إخفاء', 'Hide'),
            message: t('إخفاء «${_title(f)}» عن كل المستخدمين؟ سيختفي من كل التطبيقات فوراً، ولا يستطيع مديرو المؤسسات إعادته.',
                'Hide "${_title(f)}" for everyone? It disappears from every app immediately and organization admins cannot bring it back.'));
        if (!ok || !mounted) return;
      }
    }
    setState(() => _busy.add(key));
    final r = await orgCall(() => ApiClient().put('$_features/${Uri.encodeComponent(key)}',
        body: {'hidden': !visible, 'platforms': platforms}));
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (r.ok) {
      _aiGeneration++;
      setState(() {
        final cur = {for (final p in (f['platforms'] as List? ?? const [])) '$p'};
        final targets = platforms ?? _platforms;
        visible ? cur.removeAll(targets) : cur.addAll(targets);
        f['platforms'] = cur.toList()..sort();
        f['hidden'] = cur.isNotEmpty;
        f['hidden_everywhere'] = cur.length >= _platforms.length;
      });
    }
  }

  Future<void> _setAccess(Map<String, dynamic> f, bool allow) async {
    final id = 'access:${f['key']}';
    if (!_busy.add(id)) return;
    final r = await orgCall(() => ApiClient().put('$_features/${Uri.encodeComponent('${f['key']}')}/access', body: {'allow_to_admin': allow}));
    _busy.remove(id);
    if (r.ok && mounted) setState(() => f['allow_to_admin'] = allow);
  }

  Future<void> _setOrg(Map<String, dynamic> f, bool on) async {
    final id = 'org:${f['key']}';
    if (!_busy.add(id)) return;
    final r = await orgCall(() => ApiClient().put('$_catalog/${Uri.encodeComponent('${f['key']}')}/org-manageable', body: {'org_manageable': on}),
        ok: on ? t('يمكن لمديري المؤسسات التحكم بها الآن', 'Organization admins can control it now') : t('أصبحت بيد المنصة فقط', 'Now controlled by the platform only'));
    _busy.remove(id);
    _take(r);
    if (r.ok) f['org_manageable'] = on;
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف «${_title(f)}» نهائياً؟ سيُزال من القائمة ومن إعدادات كل المؤسسات.',
            'Delete "${_title(f)}" for good? It is removed from the list and from every organization\'s settings.'));
    if (!ok) return;
    _take(await orgCall(() => ApiClient().delete('$_catalog/${Uri.encodeComponent('${f['key']}')}'), ok: t('تم الحذف', 'Deleted')));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      helpPageId: 'admin.features',
      width: AppWidth.wide,
      title: t('الميزات', 'Features'),
      subtitle: t('ما تخفيه هنا يختفي من التطبيق لكل المستخدمين فوراً.', 'What you hide here disappears from the app for everyone, right away.'),
      icon: Icons.dashboard_customize_rounded,
      onRefresh: _refresh,
      primaryAction: _super && _data != null
          ? AppButton.primary(label: t('ميزة جديدة', 'New feature'), icon: Icons.add_rounded, onPressed: _openCreate)
          : null,
      actions: [
        AppIconButton(
            tooltip: t('دليل ميزات التطبيق (للمساعد)', 'App features guide (assistant)'),
            icon: Icons.menu_book_rounded,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeatureGuidePage()))),
      ],
      body: _error != null
          ? cfgErrorState(_error, onRetry: _load)
          : _data == null
              ? const AppListSkeleton(items: 8)
              : _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final shown = _filtered;
    // flatten: group header rows + feature rows (one lazy list, fine for hundreds of features)
    final order = [for (final tb in _tabs) '${tb['id']}'];
    final names = {for (final tb in _tabs) '${tb['id']}': t('${tb['title_ar']}', '${tb['title_en']}')};
    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final f in shown) {
      byGroup.putIfAbsent('${f['tab']}', () => []).add(f);
    }
    final rows = <Object>[];
    for (final g in [...order, ...byGroup.keys.where((k) => !order.contains(k))]) {
      final list = byGroup[g];
      if (list == null || list.isEmpty) continue;
      rows.add((g, names[g] ?? t('${list.first['tab_ar']}', '${list.first['tab_en']}'), list.length, list.where((f) => f['hidden'] == true).length));
      rows.addAll(list);
    }
    final counts = asMap(_data!['counts']);
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    return AppRefresh(
      onRefresh: _refresh,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, 0),
          sliver: SliverList.list(children: [
            // D-780: the AI features first — one platform-wide switch each, enforced by the server too
            if (_super) ...[AiControlsSection(onChanged: _load, generation: _aiGeneration), AppSpace.gapMd],
            AppKpiGrid(maxColumns: 3, children: [
              AppKpiCard(icon: Icons.widgets_rounded, value: '${counts['total'] ?? _items.length}', label: t('ميزة', 'Features')),
              AppKpiCard(icon: Icons.visibility_off_rounded, value: '${counts['hidden'] ?? 0}', label: t('مخفية', 'Hidden')),
              AppKpiCard(icon: Icons.account_balance_rounded, value: '${counts['org_manageable'] ?? 0}', label: t('بيد المؤسسات', 'Org-managed')),
            ]),
            AppSpace.gapMd,
            AppSearchField(
              hint: t('ابحث بالاسم أو المفتاح أو الوصف', 'Search by name, key or description'),
              onChanged: (v) => setState(() => _q = v),
            ),
            AppSpace.gapSm,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppChoiceChip(label: t('الكل', 'All'), selected: _state == _State.all, onTap: () => setState(() => _state = _State.all)),
              AppChoiceChip(label: t('ظاهرة', 'Shown'), icon: Icons.visibility_rounded, selected: _state == _State.on, onTap: () => setState(() => _state = _State.on)),
              AppChoiceChip(label: t('مخفية', 'Hidden'), icon: Icons.visibility_off_rounded, selected: _state == _State.off, onTap: () => setState(() => _state = _State.off)),
              AppChoiceChip(
                  label: t('بيد المؤسسات', 'Org-managed'),
                  icon: Icons.account_balance_rounded,
                  selected: _orgOnly,
                  onTap: () => setState(() => _orgOnly = !_orgOnly)),
            ]),
            AppSpace.gapSm,
            AppPicker<String>(
              label: t('المجموعة', 'Group'),
              icon: Icons.folder_open_rounded,
              value: _group,
              allowNone: true,
              noneLabel: t('كل المجموعات', 'All groups'),
              options: {for (final tb in _tabs) '${tb['id']}': '${names['${tb['id']}']} (${tb['count']})'},
              onChanged: (v) => setState(() => _group = v),
            ),
            AppSpace.gapXs,
          ]),
        ),
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmpty(icon: Icons.search_off_rounded, title: t('لا توجد ميزات مطابقة', 'No matching features'),
                actionLabel: t('مسح الفلاتر', 'Clear filters'),
                onAction: () => setState(() {
                      _q = '';
                      _group = null;
                      _state = _State.all;
                      _orgOnly = false;
                    })),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.xxs, gutter, AppSpace.xxl),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final row = rows[i];
                if (row is (String, String, int, int)) {
                  return Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.md, AppSpace.xxs, AppSpace.xs),
                    child: Row(children: [
                      Expanded(child: Text(row.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
                      AppSpace.gapXs,
                      Text(row.$4 > 0 ? t('${row.$3} · ${row.$4} مخفية', '${row.$3} · ${row.$4} hidden') : '${row.$3}',
                          style: AppType.meta(context)),
                    ]),
                  );
                }
                return _row(context, row as Map<String, dynamic>);
              },
            ),
          ),
      ]),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> f) {
    final key = '${f['key']}';
    final plats = [for (final p in (f['platforms'] as List? ?? const [])) '$p'];
    final partial = plats.isNotEmpty && f['hidden_everywhere'] != true;
    final desc = _desc(f);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xs, AppSpace.xs),
        onTap: () => _openDetail(f),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(f), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
              Text(key, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
              if (desc != null) Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              if (partial || f['org_manageable'] == true || f['is_custom'] == true) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  if (partial)
                    AppStatusBadge(
                        label: t('مخفية على: ', 'Hidden on: ') + plats.map((p) => _platformNames[p] ?? p).join('، '),
                        tone: AppTone.warning,
                        icon: Icons.devices_rounded),
                  if (f['org_manageable'] == true)
                    AppStatusBadge(label: t('بيد المؤسسات', 'Org-managed'), tone: AppTone.brand, icon: Icons.account_balance_rounded),
                  if (f['is_custom'] == true) AppStatusBadge(label: t('مضافة', 'Custom')),
                ]),
              ],
            ]),
          ),
          AppSpace.gapXs,
          AppSwitch(
            value: f['hidden'] != true,
            semanticLabel: _title(f),
            onChanged: _busy.contains(key) ? null : (v) => _setVisible(f, v),
          ),
        ]),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> f) async {
    final descAr = TextEditingController(text: '${f['description_ar'] ?? ''}');
    final descEn = TextEditingController(text: '${f['description_en'] ?? ''}');
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final busyAccess = _busy.contains('access:${f['key']}');
          final busyOrg = _busy.contains('org:${f['key']}');
          final plats = {for (final p in (f['platforms'] as List? ?? const [])) '$p'};
          Future<void> run(Future<void> Function() fn) async {
            await fn();
            if (ctx.mounted) set(() {});
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(_title(f)),
              SelectableText('${f['key']}', textDirection: TextDirection.ltr, style: AppType.meta(ctx)),
              AppSpace.gapSm,
              Text(t('الظهور حسب المنصة', 'Visibility per platform'), style: AppType.label(ctx)),
              for (final p in _platforms)
                AppSwitchTile(
                  dense: true,
                  icon: p == 'web' ? Icons.language_rounded : (p == 'ios' ? Icons.phone_iphone_rounded : Icons.android_rounded),
                  title: _platformNames[p] ?? p,
                  value: !plats.contains(p),
                  onChanged: _busy.contains('${f['key']}') ? null : (v) => run(() => _setVisible(f, v, platforms: [p])),
                ),
              if (_super) ...[
                const Divider(height: AppSpace.lg),
                Text(t('من يمكنه التحكم', 'Who may control it'), style: AppType.label(ctx)),
                AppSwitchTile(
                  icon: Icons.admin_panel_settings_rounded,
                  title: t('مديرو المنصة', 'Platform admins'),
                  subtitle: t('يظهر لهم المفتاح ويمكنهم إخفاؤها.', 'They see this switch and may hide it.'),
                  value: f['allow_to_admin'] == true,
                  onChanged: busyAccess ? null : (v) => run(() => _setAccess(f, v)),
                ),
                AppSwitchTile(
                  icon: Icons.account_balance_rounded,
                  title: t('مديرو المؤسسات', 'Organization admins'),
                  subtitle: t('يمكنهم إيقافها داخل مؤسستهم فقط. إيقافك هنا يغلب دائماً.',
                      'They may switch it off inside their organization only. Your OFF here always wins.'),
                  value: f['org_manageable'] == true,
                  onChanged: busyOrg ? null : (v) => run(() => _setOrg(f, v)),
                ),
                const Divider(height: AppSpace.lg),
                Text(t('الوصف', 'Description'), style: AppType.label(ctx)),
                const SizedBox(height: AppSpace.xs),
                AppField(controller: descAr, label: t('بالعربية', 'Arabic'), maxLines: 2),
                AppField(controller: descEn, label: t('بالإنجليزية', 'English'), maxLines: 2, ltr: true),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton.secondary(
                    icon: Icons.save_rounded,
                    label: t('حفظ الوصف', 'Save description'),
                    onPressed: () => run(() async {
                      final r = await orgCall(
                          () => ApiClient().put('$_catalog/${Uri.encodeComponent('${f['key']}')}/description',
                              body: {'description_ar': descAr.text.trim(), 'description_en': descEn.text.trim()}),
                          ok: t('تم الحفظ', 'Saved'));
                      if (r.ok) {
                        f['description_ar'] = descAr.text.trim();
                        f['description_en'] = descEn.text.trim();
                        _take(r);
                      }
                    }),
                  ),
                ),
                if (f['deletable'] == true) ...[
                  AppSpace.gapSm,
                  AppButton.danger(
                    dangerOutline: true,
                    icon: Icons.delete_outline_rounded,
                    label: t('حذف الميزة', 'Delete feature'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _delete(f);
                    },
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(t('ميزة أساسية في التطبيق — يمكن إخفاؤها ولا يمكن حذفها.', 'A built-in feature — it can be hidden but not deleted.'),
                        style: AppType.meta(ctx)),
                  ),
              ],
            ]),
          );
        }));
    disposeAfterRoute([descAr, descEn]);
    if (mounted) setState(() {});
  }

  Future<void> _openCreate() async {
    final key = TextEditingController(), ar = TextEditingController(), en = TextEditingController();
    final dAr = TextEditingController(), dEn = TextEditingController();
    final gAr = TextEditingController(), gEn = TextEditingController();
    String? group = _group ?? (_tabs.isEmpty ? null : '${_tabs.first['id']}');
    bool newGroup = false, admins = false, orgs = false, hidden = false, busy = false;
    final names = {for (final tb in _tabs) '${tb['id']}': t('${tb['title_ar']}', '${tb['title_en']}')};
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(t('ميزة جديدة', 'New feature')),
              AppBanner(
                  icon: Icons.info_outline_rounded,
                  text: t('المفتاح يجب أن يطابق ما يستخدمه التطبيق (ParentComponent / ValueKey).',
                      'The key must match what the app uses (ParentComponent / ValueKey).')),
              const SizedBox(height: AppSpace.sm),
              AppField(controller: key, label: t('المفتاح (مثل profile.chat)', 'Key (e.g. profile.chat)'), ltr: true),
              AppField(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
              AppField(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
              Row(children: [
                Expanded(child: Text(t('المجموعة', 'Group'), style: AppType.label(ctx))),
                AppChoiceChip(label: t('مجموعة جديدة', 'New group'), icon: Icons.add_rounded, selected: newGroup, onTap: () => set(() => newGroup = !newGroup)),
              ]),
              const SizedBox(height: AppSpace.xs),
              if (newGroup) ...[
                AppField(controller: gAr, label: t('اسم المجموعة بالعربية', 'Group name (Arabic)')),
                AppField(controller: gEn, label: t('اسم المجموعة بالإنجليزية', 'Group name (English)'), ltr: true),
              ] else
                AppPicker<String>(label: t('المجموعة', 'Group'), value: group, options: names, onChanged: (v) => set(() => group = v)),
              AppField(controller: dAr, label: t('الوصف بالعربية (اختياري)', 'Arabic description (optional)'), maxLines: 2),
              AppField(controller: dEn, label: t('الوصف بالإنجليزية (اختياري)', 'English description (optional)'), maxLines: 2, ltr: true),
              AppSwitchTile(
                  title: t('يتحكم بها مديرو المنصة', 'Platform admins may control it'),
                  value: admins,
                  onChanged: (v) => set(() => admins = v)),
              AppSwitchTile(
                  title: t('يتحكم بها مديرو المؤسسات', 'Organization admins may control it'),
                  value: orgs,
                  onChanged: (v) => set(() => orgs = v)),
              AppSwitchTile(title: t('ابدأ وهي مخفية', 'Start hidden'), value: hidden, onChanged: (v) => set(() => hidden = v)),
              AppSpace.gapSm,
              AppButton.primary(
                label: t('إضافة', 'Add'),
                icon: Icons.add_rounded,
                busy: busy,
                onPressed: busy
                    ? null
                    : () async {
                        if (key.text.trim().isEmpty || ar.text.trim().isEmpty || en.text.trim().isEmpty) {
                          return appToast(t('المفتاح والاسمان مطلوبة', 'Key and both names are required'), error: true);
                        }
                        if (newGroup && (gAr.text.trim().isEmpty || gEn.text.trim().isEmpty)) {
                          return appToast(t('اكتب اسمي المجموعة', 'Enter both group names'), error: true);
                        }
                        set(() => busy = true);
                        final r = await orgCall(
                            () => ApiClient().post(_catalog, body: {
                                  'key': key.text.trim(),
                                  'title_ar': ar.text.trim(),
                                  'title_en': en.text.trim(),
                                  if (newGroup) ...{'tab_ar': gAr.text.trim(), 'tab_en': gEn.text.trim()} else 'tab_id': group,
                                  'description_ar': dAr.text.trim(),
                                  'description_en': dEn.text.trim(),
                                  'allow_to_admin': admins,
                                  'org_manageable': orgs,
                                  'hidden': hidden,
                                }),
                            ok: t('تمت إضافة الميزة', 'Feature added'));
                        if (!ctx.mounted) return;
                        set(() => busy = false);
                        if (r.ok) {
                          _take(r);
                          Navigator.pop(ctx);
                        }
                      },
              ),
            ]),
          );
        }));
    disposeAfterRoute([key, ar, en, dAr, dEn, gAr, gEn]);
  }
}
