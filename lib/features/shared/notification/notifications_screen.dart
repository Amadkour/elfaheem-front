import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_screen.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../teacher/sessions/sessions_provider.dart';
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
      useWebCard: true,
      child: SafeArea(
        child: provider.isLoading
            ? Center(
                child: CircularProgressIndicator(
                  strokeWidth: context.width / 120,
                ),
              )
            : Column(
                children: [
                  ScreenAppBar(title: 'notifications'.tr),
                  Expanded(
                    child: provider.allNotifs.isEmpty
                        ? Center(
                            child: Icon(
                              Icons.notifications_active_rounded,
                              size: 50,
                              color: context.colors.primary,
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            physics: const BouncingScrollPhysics(),
                            children: [
                              const SizedBox(height: 8),
                              _NotifGroup(
                                group: NotifGroup.today,
                                groupTitle: 'today'.tr,
                              ),
                              const SizedBox(height: 20),
                              _NotifGroup(
                                group: NotifGroup.yesterday,
                                groupTitle: 'yesterday'.tr,
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                  ),
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
    List<NotificationModel> notifs = group == NotifGroup.today
        ? provider.allNotifs
        : provider.yesterdayNotifs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(groupTitle, style: context.colors.h2),
            GestureDetector(
              onTap: () async {
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
        // FIX: The root cause of the error.
        //
        // BEFORE (broken):
        //   await context.read<NotificationsProvider>().markAsRead(notif.id);
        //   Navigator.push(context, ...);   ← crash: context deactivated
        //
        // WHY IT CRASHED:
        //   markAsRead() calls notifyListeners() → the notification list
        //   rebuilds → this tile widget is removed from the tree and
        //   deactivated. The await then completes and Navigator.push tries
        //   to look up the Navigator via the now-dead context → DartError.
        //
        // FIX: capture Navigator.of(context) BEFORE the await, while the
        // context is still alive. The captured NavigatorState remains valid
        // even after the widget is deactivated.
        final navigator = Navigator.of(context);
        final provider = context.read<NotificationsProvider>();

        await provider.markAsRead(notif.id);

        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => TeacherCourseScreenProvider(
                initialCourse: TeacherCourse.dummy(notif.sourceId),
              ),
              child: TeacherSessionsScreen(),
            ),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead
              ? context.colors.cardBg
              : context.colors.primaryBlue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
          border: Border.all(
            color: isRead
                ? Colors.transparent
                : context.colors.primaryBlue.withValues(alpha: 0.2),
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
                            color: context.colors.primaryBlue,
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
            fontFamily: 'tajawal',
          ),
        ),
      ),
    );
  }
}
