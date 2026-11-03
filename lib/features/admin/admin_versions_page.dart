// lib/features/admin/admin_versions_page.dart — the update prompt (app_versions: forced / recommended update); building
// and publishing a version is App versions (app_releases/, D-144), which fills this list when a version goes live.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_kit.dart' show AppBanner;
import '../../design/app_switch.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_labels.dart';
import 'admin_list.dart';
import 'admin_premium_widgets.dart';
import 'admin_providers.dart';
import 'app_releases/app_releases_page.dart' show AppReleasesPage;
import 'package:flutter_education_app/core/display/app_fonts.dart';

final _semver = RegExp(r'^\d+(\.\d+){0,2}([+-][0-9A-Za-z.\-]+)?$');

/// Compares the numeric part of two versions ("1.2.3+4" → [1,2,3]); <0 if a<b, 0 equal, >0 if a>b.
int _cmpVersion(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[+-]')).first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

class AdminVersionsPage extends StatelessWidget {
  const AdminVersionsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminVersionsProvider()..load(),
    child: const _View(),
  );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminVersionsProvider>();
    final c = context.colors;

    return BasePage(
      key: const ValueKey('admin_versions'),
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: t('رسالة التحديث', 'Update prompt')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "admin_float",
        key: const ValueKey('admin_versions.publish'),
        backgroundColor: c.primary,
        onPressed: () => _form(context, p),
        icon: Icon(Icons.add_rounded, color: c.onHero),
        label: Text(
          t('إضافة رسالة تحديث', 'Add update prompt'),
          style: TextStyle(fontFamily: AppFonts.family, color: c.onHero),
        ),
      ),
      child: AdminSimpleList(
        loading: p.isLoading,
        error: p.error,
        isEmpty: p.items.isEmpty,
        emptyText: 'admin_no_versions_published_yet'.tr,
        emptyIcon: Icons.rocket_launch_rounded,
        onRefresh: p.load,
        children: [
          PremiumHero(
            icon: Icons.system_update_rounded,
            colors: AdminPalette.orange,
            title: t('رسالة التحديث', 'Update prompt'),
            subtitle: t('الإصدار الذي يطلب التطبيق من المستخدمين التحديث إليه، إجباريًا أو موصى به',
                'The version the app asks users to update to, forced or recommended'),
            footer: Wrap(spacing: 8, runSpacing: 6, children: [
              HeroPill(trp('ver_pill_total', {'n': p.items.length}), icon: Icons.layers_rounded),
              HeroPill(
                trp('ver_pill_active', {
                  'n': p.items.where((v) => asBool(v['is_active'])).length,
                }),
                icon: Icons.check_circle_rounded,
              ),
            ]),
          ),
          // this page builds nothing: the real build-and-publish page is App versions (super admin only)
          AppBanner(
            icon: Icons.info_outline_rounded,
            text: t('هذه الصفحة لا تبني التطبيق. لبناء إصدار جديد ونشره على المتجر أو الموقع استخدم «إصدارات التطبيق»، وعند نشره تُضاف رسالة التحديث هنا تلقائيًا.',
                'This page does not build the app. To build a new version and publish it to the store or the website, use App versions; when it goes live, its update prompt is added here by itself.'),
            action: isSuperNow(context)
                ? TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        settings: const RouteSettings(name: AppReleasesPage.routeName),
                        builder: (_) => const AppReleasesPage())),
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: Text(t('إصدارات التطبيق', 'App versions')),
                  )
                : null,
          ),
          for (final v in p.items) _VersionCard(v),
        ],
      ),
    );
  }
}

IconData _platformIcon(String platform) => switch (platform) {
  'ios' => Icons.apple_rounded,
  'web' => Icons.language_rounded,
  _ => Icons.android_rounded,
};

class _VersionCard extends StatelessWidget {
  const _VersionCard(this.v);

  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminVersionsProvider>();
    final active = asBool(v['is_active']);
    final id = asInt(v['id']);
    final platform = asStr(v['platform']);
    final accent = active ? c.success : c.textLight;
    final notes = asStr(v['release_notes_ar'], asStr(v['release_notes_en']));

    return RowCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(_platformIcon(platform), c.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'v${asStr(v['version'])}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: c.textDark,
                      ),
                    ),
                    Text(
                      platform,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 12,
                        color: c.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppSwitch(
                value: active,
                activeColor: c.success,
                onChanged: (_) async {
                  if (!active && asBool(v['force_update'])) {
                    final ok = await confirm(
                      context,
                      message: 'admin_activate_forced_version'.tr,
                      danger: true,
                    );
                    if (!ok) return;
                  }
                  await p.toggle(id);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusChip(
                active ? 'exam_status_active'.tr : 'admin_inactive'.tr,
                accent,
              ),
              if (asBool(v['force_update']))
                StatusChip('admin_forced'.tr, c.danger),
              if (asBool(v['recommend_update']))
                StatusChip('admin_recommended'.tr, c.warning),
              if (asStrOrNull(v['min_supported']) != null)
                StatusChip(
                  trp('admin_min_version', {'version': asStr(v['min_supported'])}),
                  c.charcoal,
                ),
            ],
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                notes,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 12.5,
                  color: c.textMedium,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text('btn_edit'.tr),
                  onPressed: () => _form(context, p, existing: v),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('delete'.tr),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      message: 'admin_delete_this_version'.tr,
                      danger: true,
                    );
                    if (ok) await p.remove(id);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _form(
    BuildContext context,
    AdminVersionsProvider p, {
      Map<String, dynamic>? existing,
    }) {
  final editing = existing != null;
  final version = TextEditingController(text: asStr(existing?['version']));
  final minSup = TextEditingController(text: asStr(existing?['min_supported']));
  final notesAr = TextEditingController(
    text: asStr(existing?['release_notes_ar']),
  );
  final notesEn = TextEditingController(
    text: asStr(existing?['release_notes_en']),
  );
  String platform = asStr(existing?['platform'], 'android');
  bool force = asBool(existing?['force_update']);
  bool recommend = asBool(existing?['recommend_update']);
  bool active = asBool(existing?['is_active'], true);
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, setS) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              editing
                  ? 'admin_edit_version'.tr
                  : t('رسالة تحديث جديدة', 'New update prompt'),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!editing) ...[
                      Field(
                        controller: version,
                        label: 'admin_version_e_g_1_2_3'.tr,
                        ltr: true,
                      ),
                      ChoiceRow<String>(
                        label: 'admin_platform'.tr,
                        options: const {
                          'android': 'Android',
                          'ios': 'iOS',
                          'web': 'Web',
                        },
                        value: platform,
                        onChanged: (v) => setS(() => platform = v),
                      ),
                    ],
                    Field(
                      controller: minSup,
                      label: 'admin_minimum_supported_optional'.tr,
                      ltr: true,
                    ),
                    Field(
                      controller: notesAr,
                      label: 'admin_release_notes_arabic'.tr,
                      maxLines: 3,
                    ),
                    Field(
                      controller: notesEn,
                      label: 'admin_release_notes_english'.tr,
                      maxLines: 3,
                      ltr: true,
                    ),
                    PremiumSwitchRow(
                      icon: Icons.lock_clock_rounded,
                      title: 'admin_force_update'.tr,
                      subtitle: 'admin_blocks_the_app_until_updated'.tr,
                      value: force,
                      onChanged: (v) => setS(() => force = v),
                    ),
                    PremiumSwitchRow(
                      icon: Icons.notifications_active_rounded,
                      title: 'admin_recommend_update'.tr,
                      value: recommend,
                      onChanged: (v) => setS(() => recommend = v),
                    ),
                    PremiumSwitchRow(
                      icon: Icons.check_circle_rounded,
                      title: 'admin_active_2'.tr,
                      value: active,
                      onChanged: (v) => setS(() => active = v),
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      label: 'save'.tr,
                      isLoading: busy,
                      onPressed: () async {
                        if (!editing &&
                            !_semver.hasMatch(version.text.trim())) {
                          toast(
                            'admin_invalid_version_number'.tr,
                            error: true,
                          );
                          return;
                        }
                        if (minSup.text.trim().isNotEmpty &&
                            !_semver.hasMatch(minSup.text.trim())) {
                          toast(
                            'admin_invalid_minimum_version'.tr,
                            error: true,
                          );
                          return;
                        }
                        final effectiveVersion =
                        editing ? asStr(existing['version']) : version.text.trim();
                        if (minSup.text.trim().isNotEmpty &&
                            _cmpVersion(minSup.text.trim(), effectiveVersion) > 0) {
                          toast('admin_min_version_gt'.tr, error: true);
                          return;
                        }
                        if (force && active) {
                          final ok = await confirm(
                            ctx,
                            message: 'admin_activate_forced_version'.tr,
                            danger: true,
                          );
                          if (!ok || !ctx.mounted) return;
                        }
                        setS(() => busy = true);
                        final common = <String, dynamic>{
                          'force_update': force,
                          'recommend_update': recommend,
                          'is_active': active,
                          'min_supported': minSup.text.trim().isEmpty
                              ? null
                              : minSup.text.trim(),
                          'release_notes_ar': notesAr.text.trim().isEmpty
                              ? null
                              : notesAr.text.trim(),
                          'release_notes_en': notesEn.text.trim().isEmpty
                              ? null
                              : notesEn.text.trim(),
                        };
                        final ok = editing
                            ? await p.update(asInt(existing['id']), common)
                            : await p.create({
                          'version': version.text.trim(),
                          'platform': platform,
                          ...common,
                        });
                        if (ctx.mounted) {
                          setS(() => busy = false);
                          if (ok) Navigator.pop(ctx);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }).whenComplete(() => disposeAfterRoute([version, minSup, notesAr, notesEn]));
}