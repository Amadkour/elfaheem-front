// lib/features/admin/admin_app_versions_page.dart — App versions: ONE page for "Build & publish" (the super admin's
// Codemagic / runner builds, D-143/D-144) and "Update prompt" (the version the app asks users to update to, which
// every admin can edit). C-round consolidation of the two hub tiles.
//
//   Build & publish   super admin only, and only while the kill switch `admin.app_releases` is on. AppReleasesPage
//                     draws its own AdminPage (header, refresh, primary action), so it cannot sit inside a tab
//                     without a second header; the tab is a card whose button opens it, through the deferred
//                     library (`deferredAppReleases()`, D-171), exactly as the old hub tile did.
//   Update prompt     the existing list (AdminVersionsContent), for every admin. Alone, no tab bar is drawn.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/routing/deferred_screens.dart';
import '../../design/app_kit.dart';
import 'admin_common.dart';
import 'admin_page.dart';
import 'admin_providers.dart';
import 'admin_versions_page.dart';
import 'app_releases/app_releases_page.dart' show AppReleasesPage, kAppReleasesFeatureKey;

class AdminAppVersionsPage extends StatefulWidget {
  const AdminAppVersionsPage({super.key, this.showUpdatePrompt = false});

  /// Open on the Update prompt tab even when Build & publish is available.
  final bool showUpdatePrompt;

  @override
  State<AdminAppVersionsPage> createState() => _AdminAppVersionsPageState();
}

class _AdminAppVersionsPageState extends State<AdminAppVersionsPage> {
  final AdminVersionsProvider _p = AdminVersionsProvider();
  bool? _build; // the user's choice; null = the default (Build when it is available)

  @override
  void initState() {
    super.initState();
    _p.load();
    if (widget.showUpdatePrompt) _build = false;
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _openBuildPage() => Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: AppReleasesPage.routeName), builder: (_) => deferredAppReleases()));

  @override
  Widget build(BuildContext context) {
    // the kill switch can change while the page is open (theme refresh)
    return ValueListenableBuilder<int>(
      valueListenable: AppConfig.disableListVersion,
      builder: (context, _, _) {
        final buildAvailable = isSuperNow(context) && !AppConfig.disableList.contains(kAppReleasesFeatureKey);
        final onBuild = buildAvailable && (_build ?? true);
        return ChangeNotifierProvider<AdminVersionsProvider>.value(
          value: _p,
          child: Builder(builder: (context) {
            final p = context.watch<AdminVersionsProvider>();
            return AdminPage(
              key: const ValueKey('admin_app_versions'),
              title: t('إصدارات التطبيق', 'App versions'),
              subtitle: buildAvailable
                  ? t('ابنِ إصدارًا جديدًا وانشره، وحدّد رسالة التحديث التي يراها المستخدمون',
                      'Build and publish a version, and set the update prompt users see')
                  : t('الإصدار الذي يطلب التطبيق من المستخدمين التحديث إليه، إجباريًا أو موصى به',
                      'The version the app asks users to update to, forced or recommended'),
              icon: Icons.rocket_launch_rounded,
              onRefresh: onBuild ? null : p.load,
              primaryAction: onBuild ? null : AdminVersionsAddButton(provider: p),
              body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (buildAvailable)
                  Padding(
                    padding: EdgeInsets.fromLTRB(AppSpace.gutter(MediaQuery.sizeOf(context).width), AppSpace.sm,
                        AppSpace.gutter(MediaQuery.sizeOf(context).width), 0),
                    child: AppTabs(
                      key: const ValueKey('admin_app_versions.tabs'),
                      items: [
                        AppTabItem(t('بناء ونشر', 'Build & publish'), icon: Icons.build_circle_rounded),
                        AppTabItem(t('رسالة التحديث', 'Update prompt'), icon: Icons.system_update_rounded),
                      ],
                      index: onBuild ? 0 : 1,
                      onChanged: (i) => setState(() => _build = i == 0),
                    ),
                  ),
                Expanded(
                  child: onBuild
                      ? _BuildTab(onOpen: _openBuildPage)
                      : AdminVersionsContent(onOpenBuild: buildAvailable ? () => setState(() => _build = true) : null),
                ),
              ]),
            );
          }),
        );
      },
    );
  }
}

class _BuildTab extends StatelessWidget {
  const _BuildTab({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: AdminPage.bodyPadding(context), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.rocket_launch_rounded, color: c.primary),
            AppSpace.gapSm,
            Expanded(child: Text(t('بناء ونشر', 'Build & publish'), style: AppType.section(context))),
          ]),
          AppSpace.gapXs,
          Text(
            t('بناء إصدار جديد لأندرويد أو الويب أو لينكس أو ويندوز على Codemagic ونشره على المتجر أو في شريط التحميل بالموقع. عند نشره تُضاف رسالة التحديث تلقائيًا.',
                'Build a new Android, web, Linux or Windows version on Codemagic and publish it to the store or the website download banner. When it goes live, its update prompt is added by itself.'),
            style: AppType.body(context).copyWith(color: c.textMedium),
          ),
          AppSpace.gapMd,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.primary(
              key: const ValueKey('admin_app_versions.open'),
              icon: Icons.open_in_new_rounded,
              label: t('فتح إصدارات التطبيق', 'Open App versions'),
              onPressed: onOpen,
            ),
          ),
        ]),
      ),
    ]);
  }
}
