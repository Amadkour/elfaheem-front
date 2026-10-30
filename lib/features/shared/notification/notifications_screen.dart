import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppEmpty, appText;
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
                  if (provider.unreadCount > 0)
                    ParentComponent(featureKey: 'notifications.mark_all_read', child: NotificationsMarkAllBar(
                      // ONE action for the whole page (N12), not one per day group; one PUT /read-all.
                      onPressed: () => context.read<NotificationsProvider>().markAllAsRead(),
                    )),
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
        // Group header (the page's single "Mark all read" sits above the groups, N12)
        Text(groupTitle, style: context.colors.h2),
        const SizedBox(height: 12),
        // Notification tiles
        ...notifs.map(
              (n) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NotificationTile(notif: n),
          ),
        ),
      ],
    );
  }
}

/// The page's one "Mark all read", above the day groups (end-aligned, 48 px target).
class NotificationsMarkAllBar extends StatelessWidget {
  const NotificationsMarkAllBar({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: onPressed,
        icon: Icon(Icons.done_all_rounded, size: 18, color: context.colors.primary),
        label: Text('mark_all_read'.tr, style: context.colors.label.copyWith(color: context.colors.primary)),
      ),
    );
  }
}

/// What a notification is about, for its icon (N12): read from the server's `type` first, then `related_type`.
enum NotifKind { live, recording, schedule, exam, course, payment, certificate, complaint, announcement, request, organization, person, general }

NotifKind notificationKind(String type, String relatedType) {
  final t = type.toLowerCase();
  final r = relatedType.toLowerCase();
  bool any(List<String> keys) => keys.any((k) => t.contains(k) || r.contains(k));
  if (t.contains('record') || r.contains('record')) return NotifKind.recording;
  if (t.contains('session_started') || t.contains('live') || any(['meeting'])) return NotifKind.live;
  if (any(['exam', 'quiz'])) return NotifKind.exam;
  if (any(['payment', 'topup', 'subscription', 'fee', 'transfer', 'points'])) return NotifKind.payment;
  if (any(['certificate', 'badge', 'graduation', 'premium'])) return NotifKind.certificate;
  if (any(['complain'])) return NotifKind.complaint;
  if (any(['announcement'])) return NotifKind.announcement;
  if (any(['schedule', 'timetable', 'session', 'availability', 'calendar'])) return NotifKind.schedule;
  if (any(['course', 'material', 'learning', 'module', 'lesson', 'enroll'])) return NotifKind.course;
  if (any(['work_item', 'decision', 'council', 'form', 'request', 'consent', 'review', 'delegation', 'registrar', 'registration', 'program_choice'])) {
    return NotifKind.request;
  }
  if (any(['parent', 'username', 'mention', 'user', 'profile'])) return NotifKind.person;
  if (t.startsWith('org') || r.startsWith('org')) return NotifKind.organization;
  return NotifKind.general;
}

IconData notificationIcon(NotifKind kind) => switch (kind) {
  NotifKind.live => Icons.videocam_rounded,
  NotifKind.recording => Icons.play_circle_outline_rounded,
  NotifKind.schedule => Icons.event_note_rounded,
  NotifKind.exam => Icons.quiz_outlined,
  NotifKind.course => Icons.menu_book_rounded,
  NotifKind.payment => Icons.credit_card_rounded,
  NotifKind.certificate => Icons.workspace_premium_rounded,
  NotifKind.complaint => Icons.support_agent_rounded,
  NotifKind.announcement => Icons.campaign_outlined,
  NotifKind.request => Icons.assignment_outlined,
  NotifKind.organization => Icons.apartment_rounded,
  NotifKind.person => Icons.person_outline_rounded,
  NotifKind.general => Icons.notifications_none_rounded,
};

// ── Notification Tile ─────────────────────────────────────────────────────────

/// One notification row (calm: an unread one adds a dot and a w600 title, M2).
class NotificationTile extends StatelessWidget {
  final NotificationModel notif;

  const NotificationTile({super.key, required this.notif});

  Widget _buildIcon(String asset, BuildContext context) {
    final kind = notificationKind(notif.type, notif.relatedType);
    if (kind != NotifKind.general) {
      final c = context.colors;
      final tone = kind == NotifKind.certificate ? c.accent : c.primary;
      return _IconBadge(icon: notificationIcon(kind), bg: tone.withValues(alpha: 0.12), iconColor: tone);
    }
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
        return _IconBadge(
          icon: Icons.campaign_outlined,
          bg: context.colors.primary.withValues(alpha: 0.10),
          iconColor: context.colors.primary,
        );
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
    final c = context.colors;
    final title = notificationPlainText(notif.title);
    final body = notificationPlainText(notif.body);

    // Calm rows (M2): every row looks the same; an unread one only adds a dot and a w600 title.
    return Semantics(
      button: true,
      label: isRead ? null : (AppConfig.lang == 'ar' ? 'غير مقروء' : 'Unread'),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(c.radiusMedium),
          onTap: () async {
            final provider = context.read<NotificationsProvider>();
            if (!notif.isRead) {
              await provider.markAsRead(notif.id);
            }
            // Opens the course profile (student or teacher version) / profile / etc. — resolved by the server.
            await AppNavigator.openNotification(notif.id);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(c.radiusMedium),
              border: Border.all(color: c.divider),
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
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: appText(15, w: isRead ? FontWeight.w500 : FontWeight.w600, c: c.textDark),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.45),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isRead) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A notification's text without emoji / pictographs (the server writes "⏹" / "🎥" into some titles; most fonts
/// draw them as empty boxes, M2), with the spaces they leave tidied.
String notificationPlainText(String s) => s
    .replaceAll(_emoji, '')
    .replaceAll(RegExp(r' {2,}'), ' ')
    .trim();

final RegExp _emoji = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{20E3}]',
  unicode: true,
);

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
