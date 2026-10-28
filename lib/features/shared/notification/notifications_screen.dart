import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppEmpty;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_navigator.dart';
import '../../../utils/widget/base_page.dart';
import 'notifications_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<NotificationsProvider>().fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    NotificationsProvider provider = context.watch<NotificationsProvider>();
    return BasePage(
      key: ValueKey('notifications'),
      useWebCard: true,
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'notifications'.tr, actions: [AppRefreshAction(onRefresh: provider.fetchNotifications)]),
            Expanded(
              child: NotificationsStateBody(
                loading: provider.isLoading,
                empty: provider.allNotifs.isEmpty,
                error: provider.hasError ? (provider.errorMessage ?? '') : null,
                onRefresh: provider.fetchNotifications,
                onLoadMore: provider.hasMore ? () => provider.loadMore() : null,
                children: [
                  ParentComponent(featureKey: 'notifications.today', child: _NotifGroup(
                    group: NotifGroup.today,
                    groupTitle: 'today'.tr,
                  )),
                  ParentComponent(featureKey: 'notifications.yesterday', child: _NotifGroup(
                    group: NotifGroup.yesterday,
                    groupTitle: 'yesterday'.tr,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list area of the notifications page over plain values: skeleton on the first load, the server's error with
/// a retry, a real empty state, else the groups with pull-to-refresh and the next page fetched near the end.
class NotificationsStateBody extends StatelessWidget {
  const NotificationsStateBody({
    super.key,
    required this.loading,
    required this.empty,
    required this.error,
    required this.onRefresh,
    required this.children,
    this.onLoadMore,
  });

  final bool loading;
  final bool empty;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback? onLoadMore;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (empty && loading) return const AppListSkeleton();
    if (empty && error != null) {
      return AppRefresh(
        onRefresh: onRefresh,
        scrollable: false,
        child: ErrorRetry(message: error!.isEmpty ? (AppConfig.lang == 'ar' ? 'تعذّر تحميل الإشعارات' : 'Could not load notifications') : error!, onRetry: onRefresh),
      );
    }
    if (empty) {
      return AppRefresh(
        onRefresh: onRefresh,
        scrollable: false,
        child: AppEmpty(
          icon: Icons.notifications_none_rounded,
          title: AppConfig.lang == 'ar' ? 'لا توجد إشعارات' : 'No notifications yet',
          message: AppConfig.lang == 'ar' ? 'ستظهر هنا رسائل المنصة والدورات' : 'Platform and course messages will appear here',
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (onLoadMore != null && !loading && n.metrics.extentAfter < 300) onLoadMore!();
        return false;
      },
      child: AppRefresh(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          physics: const BouncingScrollPhysics(),
          children: [
            const SizedBox(height: 8),
            for (final w in children) ...[w, const SizedBox(height: 20)],
            if (loading) const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ── Notification Group ────────────────────────────────────────────────────────

class _NotifGroup extends StatelessWidget {
  final NotifGroup group;
  final String groupTitle;

  const _NotifGroup({required this.group, required this.groupTitle});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();
    // FIX: "today" used allNotifs, so every notification showed in both sections.
    List<NotificationModel> notifs = group == NotifGroup.today
        ? provider.todayNotifs
        : provider.yesterdayNotifs;
    if (notifs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(groupTitle, style: context.colors.h2)),
            ParentComponent(featureKey: 'notifications.mark_all_read', child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () async {
                // FIX: capture provider before the async gap so we never
                // access context after notifyListeners() may deactivate
                // this widget.
                final p = context.read<NotificationsProvider>();
                await p.markGroupAsRead(group);
              },
              child: Text(
                'mark_all_read'.tr,
                style: context.colors.label.copyWith(
                  color: context.colors.primary,
                ),
              ),
            )),
          ],
        ),
        const SizedBox(height: 12),
        // Notification tiles
        ...notifs.map(
              (n) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _NotifTile(notif: n),
          ),
        ),
      ],
    );
  }
}

// ── Notification Tile ─────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;

  const _NotifTile({required this.notif});

  Widget _buildIcon(String asset, BuildContext context) {
    switch (asset) {
      case 'payment':
        return _IconBadge(
          icon: Icons.credit_card_rounded,
          bg: context.colors.primary.withValues(alpha: 0.15),
          iconColor: context.colors.primary,
        );
      case 'badge':
        return _IconBadge(
          icon: Icons.workspace_premium_rounded,
          bg: context.colors.accent.withValues(alpha: 0.15),
          iconColor: context.colors.accent,
        );
      case 'new':
        return _NewBadgeIcon();
      default:
        return _IconBadge(
          icon: Icons.notifications_rounded,
          bg: context.colors.background,
          iconColor: context.colors.textMedium,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = notif.isRead;

    return GestureDetector(
      onTap: () async {
        final provider = context.read<NotificationsProvider>();
        if (!notif.isRead) {
          await provider.markAsRead(notif.id);
        }
        // Opens the course profile (student or teacher version) / profile / etc. — resolved by the server.
        await AppNavigator.openNotification(notif.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead
              ? context.colors.cardBg
              : context.colors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
          border: Border.all(
            color: isRead
                ? Colors.transparent
                : context.colors.primary.withValues(alpha: 0.2),
          ),
          boxShadow: context.colors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIcon(notif.iconAsset, context),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: context.colors.h3.copyWith(
                            color: isRead
                                ? context.colors.textDark
                                : context.colors.primary,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif.body, style: context.colors.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon Badges ───────────────────────────────────────────────────────────────

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color iconColor;

  const _IconBadge({
    required this.icon,
    required this.bg,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor, size: 26),
    );
  }
}

class _NewBadgeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: context.colors.danger,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          'NEW',
          style: TextStyle(
            color: context.colors.onHero,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            fontFamily: 'tajawal',
          ),
        ),
      ),
    );
  }
}