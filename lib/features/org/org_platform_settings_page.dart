// lib/features/org/org_platform_settings_page.dart
//
// Organization admin → "Time & features":
//   • Time & region — override the platform timezone / 12h-24h for this organization (or follow the platform)
//     GET/PUT /api/v1/org/orgs/{id}/region   (PUT is a FULL object: {timezone|null, time_format|null})
//   • Features — only what the super admin marked "organization admins may manage" AND kept on for the platform.
//     Switching one off hides it (it disappears, not greyed) for everyone while this organization is open.
//     GET /features · PUT /features/{key} {enabled}
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import '../admin/admin_platform_widgets.dart';
import 'org_platform_context.dart';
import 'org_providers.dart';
import 'org_v3.dart';

class OrgPlatformSettingsPage extends StatefulWidget {
  const OrgPlatformSettingsPage({super.key});

  @override
  State<OrgPlatformSettingsPage> createState() => _OrgPlatformSettingsPageState();
}

class _OrgPlatformSettingsPageState extends State<OrgPlatformSettingsPage> {
  Map<String, dynamic>? _region;
  List<Map<String, dynamic>>? _features;
  String? _zone, _fmt;
  bool _savingRegion = false, _featuresMissing = false;
  final Set<String> _busyKeys = {};
  String _q = '';
  String? _error; // the region could not be loaded (not a missing route)

  String get _base => context.read<OrgSession>().base;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final rr = await orgCall(() => ApiClient().get('$_base/region'), quiet: true);
    final fr = await orgCall(() => ApiClient().get('$_base/features'), quiet: true);
    if (!mounted) return;
    setState(() {
      _error = !rr.ok && !rr.endpointMissing ? orgErrorText(rr.error!) : null;
      _region = rr.ok ? rr.map : {};
      _zone = _region?['timezone'] as String?;
      _fmt = _region?['time_format'] as String?;
      _features = fr.ok ? asMapList(fr.map['items']) : const [];
      _featuresMissing = !fr.ok && fr.endpointMissing;
    });
  }

  bool get _regionDirty => _zone != _region?['timezone'] || _fmt != _region?['time_format'];

  Future<void> _saveRegion() async {
    setState(() => _savingRegion = true);
    final r = await orgCall(() => ApiClient().put('$_base/region', body: {'timezone': _zone, 'time_format': _fmt}),
        ok: t('تم حفظ الوقت والمنطقة', 'Time & region saved'));
    if (!mounted) return;
    setState(() {
      _savingRegion = false;
      if (r.ok) _region = r.map;
    });
    if (r.ok) OrgPlatformContext.refresh();
  }

  Future<void> _toggle(Map<String, dynamic> f, bool on) async {
    final key = '${f['key']}';
    if (!on &&
        !await appConfirm(context,
            message: t('إيقاف «${f['title_ar'] ?? key}» يخفيها عن كل أعضاء المؤسسة. متابعة؟',
                'Switching off "${f['title_en'] ?? key}" hides it for everyone in the organization. Continue?'))) {
      return;
    }
    setState(() {
      _busyKeys.add(key);
      f['enabled'] = on; // optimistic
    });
    final r = await orgCall(() => ApiClient().put('$_base/features/${Uri.encodeComponent(key)}', body: {'enabled': on}));
    if (!mounted) return;
    setState(() {
      _busyKeys.remove(key);
      if (r.ok) {
        _features = asMapList(r.map['items']);
      } else {
        f['enabled'] = !on;
      }
    });
    if (r.ok) OrgPlatformContext.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_error != null) {
      return AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: _error!,
          actionLabel: t('إعادة المحاولة', 'Try again'),
          onAction: () {
            setState(() => _region = _features = _error = null);
            _load();
          });
    }
    if (_region == null || _features == null) return const AppListSkeleton(items: 5);
    final eff = asMap(_region!['effective']);
    final plat = asMap(_region!['platform']);
    final q = _q.trim().toLowerCase();
    final shown = _features!
        .where((f) => q.isEmpty || '${f['title_ar']} ${f['title_en']} ${f['key']}'.toLowerCase().contains(q))
        .toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final f in shown) {
      groups.putIfAbsent(t('${f['tab_ar']}', '${f['tab_en']}'), () => []).add(f);
    }
    final off = _features!.where((f) => f['enabled'] != true).length;

    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        AppHero(
          title: t('الوقت والميزات', 'Time & features'),
          subtitle: t('اضبط توقيت مؤسستك واختر الميزات التي تظهر لأعضائها.',
              'Set your organization\'s clock and choose which features its members see.'),
          icon: Icons.tune_rounded,
          stats: [
            AppHeroStat(icon: Icons.public_rounded, value: AppTime.zoneInfo('${eff['timezone'] ?? AppTime.fallbackZone}').label, label: t('المنطقة', 'Zone')),
            AppHeroStat(icon: Icons.toggle_on_rounded, value: '${_features!.length - off}/${_features!.length}', label: t('ميزات مفعّلة', 'Features on')),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PlatformSectionHeader(
                icon: Icons.schedule_rounded,
                title: t('الوقت والمنطقة', 'Time & region'),
                subtitle: t('تُعرض كل الأوقات داخل المؤسسة بهذا التوقيت.', 'Every time inside the organization is shown in this clock.')),
            RegionEditor(
              zone: _zone,
              timeFormat: _fmt,
              inheritLabel: t('افتراضي المنصة', 'Platform default'),
              inheritedZone: plat['timezone'] as String?,
              inheritedFormat: plat['time_format'] as String?,
              onZone: (v) => setState(() => _zone = v),
              onFormat: (v) => setState(() => _fmt = v),
            ),
            const SizedBox(height: 14),
            AppPrimaryButton(
              label: t('حفظ', 'Save'),
              icon: Icons.check_rounded,
              busy: _savingRegion,
              onPressed: _savingRegion || !_regionDirty ? null : _saveRegion,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        PlatformSectionHeader(
          icon: Icons.dashboard_customize_rounded,
          title: t('الميزات', 'Features'),
          subtitle: t('ما تسمح إدارة المنصة لمؤسستك بالتحكم فيه فقط.', 'Only what the platform lets your organization control.'),
          trailing: off > 0 ? AppBadgePill(t('$off متوقفة', '$off off'), color: c.warning) : null,
        ),
        if (_featuresMissing)
          AppBanner(icon: Icons.cloud_off_rounded, text: t('هذه الميزة تحتاج تحديث الخادم.', 'This needs a server update.'))
        else if (_features!.isEmpty)
          AppEmpty(icon: Icons.lock_outline_rounded, title: _emptyTitle, message: _emptyMsg)
        else ...[
          if (_features!.length > 6)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: t('ابحث عن ميزة', 'Search features'),
                ),
              ),
            ),
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(g.key, style: appText(12.5, w: FontWeight.w800, c: c.textMedium)),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                for (final f in g.value)
                  AppSwitchTile(
                    title: t('${f['title_ar'] ?? f['key']}', '${f['title_en'] ?? f['key']}'),
                    subtitle: f['locked_by_parent'] == true
                        ? t('أوقفتها المؤسسة الأم', 'Switched off by the parent organization')
                        : (t('${f['description_ar'] ?? ''}', '${f['description_en'] ?? ''}').trim().isEmpty
                            ? null
                            : t('${f['description_ar'] ?? ''}', '${f['description_en'] ?? ''}')),
                    value: f['enabled'] == true,
                    onChanged: f['locked_by_parent'] == true || _busyKeys.contains('${f['key']}')
                        ? null
                        : (v) => _toggle(f, v),
                  ),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

String get _emptyTitle => t('لا توجد ميزات قابلة للإدارة بعد', 'No manageable features yet');
String get _emptyMsg =>
    t('عندما تسمح إدارة المنصة للمؤسسات بالتحكم في ميزة ستظهر هنا.', 'When the platform lets organizations control a feature, it shows up here.');
