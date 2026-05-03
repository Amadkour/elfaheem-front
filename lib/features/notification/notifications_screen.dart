import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/app_theme.dart';
import '../../utils/helpers.dart';
import '../../utils/widget/app_bar.dart';
import 'notifications_provider.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
               ScreenAppBar(title: 'notifications'.tr),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  children:   [
                    const SizedBox(height: 8),
                    _NotifGroup(group: NotifGroup.today,     groupTitle: 'today'.tr),
                    const SizedBox(height: 20),
                    _NotifGroup(group: NotifGroup.yesterday, groupTitle: 'yesterday'.tr),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notification Group ────────────────────────────────────────────────────────

class _NotifGroup extends StatelessWidget {
  final NotifGroup group;
  final String     groupTitle;

  const _NotifGroup({required this.group, required this.groupTitle});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();
    List<NotificationModel> notifs   = group == NotifGroup.today
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
            Text(groupTitle, style: AppTheme.h2),
            GestureDetector(
              onTap: () =>
                  context.read<NotificationsProvider>().markGroupAsRead(group),
              child: Text(
                'تحديد الكل كمقروء',
                style: AppTheme.label.copyWith(color: AppTheme.primary),
              ),
            ),
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

  /// Map iconAsset key → widget
  Widget _buildIcon(String asset) {
    switch (asset) {
      case 'payment':
        return _IconBadge(
          icon: Icons.credit_card_rounded,
          bg: AppTheme.primary.withValues(alpha:0.15),
          iconColor: AppTheme.primary,
        );
      case 'badge':
        return _IconBadge(
          icon: Icons.workspace_premium_rounded,
          bg: AppTheme.accent.withValues(alpha:0.15),
          iconColor: AppTheme.accent,
        );
      case 'new':
        return _NewBadgeIcon();
      default:
        return const _IconBadge(
          icon: Icons.notifications_rounded,
          bg: AppTheme.background,
          iconColor: AppTheme.textMedium,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = notif.isRead;

    return GestureDetector(
      onTap: () =>
          context.read<NotificationsProvider>().markAsRead(notif.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppTheme.cardBg : AppTheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: isRead ? Colors.transparent : AppTheme.primary.withValues(alpha:0.2),
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content (RTL: title + body on right)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: AppTheme.h3.copyWith(
                            color: isRead
                                ? AppTheme.textDark
                                : AppTheme.primary,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif.body, style: AppTheme.body),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Icon badge (LTR: on left for RTL layout)
            _buildIcon(notif.iconAsset),
          ],
        ),
      ),
    );
  }
}

// ── Icon Badges ───────────────────────────────────────────────────────────────

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color    bg;
  final Color    iconColor;

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
        color: Colors.pink.shade400,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Text(
          'NEW',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            fontFamily: 'Tajawal',
          ),
        ),
      ),
    );
  }
}
