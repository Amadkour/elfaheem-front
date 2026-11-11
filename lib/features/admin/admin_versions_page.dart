// lib/features/admin/admin_versions_page.dart — the update prompt history (every app_versions row: toggle, edit,
// delete). The everyday screen is App versions (admin_app_versions_page.dart, D-309: one policy per platform with a
// live preview), which opens this list; building a version (app_releases/, D-144) fills it when a version goes live.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_kit.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_labels.dart';
import 'admin_page.dart';
import 'admin_premium_widgets.dart';
import 'admin_providers.dart';
import 'app_releases/app_releases_page.dart' show AppReleasesPage;

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
    return AdminPage(
      key: const ValueKey('admin_versions'),
      width: AppWidth.wide,
      title: t('سجل رسائل التحديث', 'Update prompt history'),
      subtitle: t('الإصدار الذي يطلب التطبيق من المستخدمين التحديث إليه، إجباريًا أو موصى به',
          'The version the app asks users to update to, forced or recommended'),
      icon: Icons.system_update_rounded,
      onRefresh: p.load,
      primaryAction: AdminVersionsAddButton(provider: p),
      body: const AdminVersionsContent(),
    );
  }
}

/// The header's one primary action of the update prompt list ("Add update prompt").
class AdminVersionsAddButton extends StatelessWidget {
  const AdminVersionsAddButton({super.key, required this.provider});

  final AdminVersionsProvider provider;

  @override
  Widget build(BuildContext context) => AppButton.primary(
        key: const ValueKey('admin_versions.publish'),
        label: t('إضافة رسالة تحديث', 'Add update prompt'),
        icon: Icons.add_rounded,
        onPressed: () => _form(context, provider),
      );
}

/// The update prompt list without a page header, so it sits inside a tab (App versions, C-round) or under
/// [AdminVersionsPage]'s own header. Reads the [AdminVersionsProvider] above it.
///
/// [onOpenBuild]: when the Build & publish tab is next door, the banner's button switches to it; null keeps the
/// standalone behaviour (a super admin gets a button that pushes the App versions page).
class AdminVersionsContent extends StatelessWidget {
  const AdminVersionsContent({super.key, this.onOpenBuild});

  final VoidCallback? onOpenBuild;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminVersionsProvider>();
    final loaded = !p.isLoading || p.items.isNotEmpty;
    if (!loaded) return const AppListSkeleton();
    if (p.error != null && p.items.isEmpty) return AppErrorState(message: p.error, onRetry: p.load);
    return AppRefresh(
      onRefresh: p.load,
      child: ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          AppKpiGrid(maxColumns: 2, children: [
            AppKpiCard(icon: Icons.layers_rounded, value: '${p.items.length}', label: t('رسائل التحديث', 'Update prompts')),
            AppKpiCard(
                icon: Icons.check_circle_rounded,
                value: '${p.items.where((v) => asBool(v['is_active'])).length}',
                label: t('مفعّلة', 'Active')),
          ]),
          AppSpace.gapSm,
          if (p.error != null) ...[
            AppErrorState(compact: true, message: p.error, onRetry: p.load),
            AppSpace.gapSm,
          ],
          // this page builds nothing: the real build-and-publish page is App versions (super admin only)
          AppBanner(
            icon: Icons.info_outline_rounded,
            text: t('هذه الصفحة لا تبني التطبيق. لبناء إصدار جديد ونشره على المتجر أو الموقع استخدم «إصدارات التطبيق»، وعند نشره تُضاف رسالة التحديث هنا تلقائيًا.',
                'This page does not build the app. To build a new version and publish it to the store or the website, use App versions; when it goes live, its update prompt is added here by itself.'),
          ),
          if (onOpenBuild != null) ...[
            AppSpace.gapXs,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.secondary(
                key: const ValueKey('admin_versions.open_build'),
                icon: Icons.rocket_launch_rounded,
                label: t('بناء ونشر', 'Build & publish'),
                onPressed: onOpenBuild,
              ),
            ),
          ] else if (isSuperNow(context)) ...[
            AppSpace.gapXs,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.secondary(
                icon: Icons.rocket_launch_rounded,
                label: t('إصدارات التطبيق', 'App versions'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    settings: const RouteSettings(name: AppReleasesPage.routeName), builder: (_) => deferredAppReleases())),
              ),
            ),
          ],
          AppSpace.gapMd,
          if (p.items.isEmpty)
            AppEmpty(icon: Icons.rocket_launch_rounded, title: 'admin_no_versions_published_yet'.tr)
          else
            for (final v in p.items) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: _VersionCard(v)),
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

/// The platform's name, not the raw server code.
String _platformName(String platform) => switch (platform) {
  'ios' => 'iOS',
  'web' => 'Web',
  'android' => 'Android',
  'macos' => 'macOS',
  'windows' => 'Windows',
  'linux' => 'Linux',
  _ => platform,
};

class _VersionCard extends StatefulWidget {
  const _VersionCard(this.v);

  final Map<String, dynamic> v;

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  bool _toggling = false;

  Future<void> _toggle(AdminVersionsProvider p, bool active, int id) async {
    if (_toggling) return;
    if (!active && asBool(widget.v['force_update'])) {
      final ok = await confirm(context, message: 'admin_activate_forced_version'.tr, danger: true);
      if (!ok || !mounted) return;
    }
    setState(() => _toggling = true);
    await p.toggle(id);
    if (mounted) setState(() => _toggling = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final c = context.colors;
    final p = context.read<AdminVersionsProvider>();
    final active = asBool(v['is_active']);
    final id = asInt(v['id']);
    final platform = asStr(v['platform']);
    final notes = asStr(v['release_notes_ar'], asStr(v['release_notes_en']));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_platformIcon(platform), color: c.primary),
              AppSpace.gapSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('v${asStr(v['version'])}', textDirection: TextDirection.ltr, style: AppType.section(context)),
                    Text(_platformName(platform), style: AppType.meta(context)),
                  ],
                ),
              ),
              AppSpace.gapXs,
              AppSwitch(
                value: active,
                semanticLabel: 'v${asStr(v['version'])} ${_platformName(platform)}',
                onChanged: _toggling ? null : (_) => _toggle(p, active, id),
              ),
            ],
          ),
          AppSpace.gapSm,
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              AppStatusBadge(
                  label: active ? 'exam_status_active'.tr : 'admin_inactive'.tr,
                  tone: active ? AppTone.success : AppTone.neutral,
                  dot: true),
              if (asBool(v['force_update'])) AppStatusBadge(label: 'admin_forced'.tr, tone: AppTone.danger),
              if (asBool(v['recommend_update'])) AppStatusBadge(label: 'admin_recommended'.tr, tone: AppTone.warning),
              if (asStrOrNull(v['min_supported']) != null)
                AppStatusBadge(label: trp('admin_min_version', {'version': asStr(v['min_supported'])})),
            ],
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(notes, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
            ),
          AppSpace.gapSm,
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            alignment: WrapAlignment.spaceBetween,
            children: [
              AppButton.secondary(
                icon: Icons.edit_rounded,
                label: 'btn_edit'.tr,
                onPressed: () => _form(context, p, existing: v),
              ),
              AppButton.danger(
                dangerOutline: true,
                icon: Icons.delete_outline_rounded,
                label: 'delete'.tr,
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    message: t('حذف رسالة التحديث v${asStr(v['version'])} (${_platformName(platform)})؟',
                        'Delete the update prompt v${asStr(v['version'])} (${_platformName(platform)})?'),
                    danger: true,
                  );
                  if (ok) await p.remove(id);
                },
              ),
            ],
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
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
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
                    const SizedBox(height: AppSpace.xs),
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