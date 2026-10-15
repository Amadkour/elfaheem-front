import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../auth/auth_provider.dart';
import '../../../shared/guest/guest_state.dart';
import '../../dashboard/dashboard_screen.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthProvider provider = context.watch<AuthProvider>();
    final unread = context.watch<NotificationsProvider>().unreadCount;
    final name = GuestState.active
        ? 'guest_name'.tr
        : (provider.currentUser?.name ?? 'sir'.tr);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient avatar with glow
          if(provider.currentUser!=null)
            UserChipButton(
              user: provider.currentUser!,
              showLabel: false,
            ),
          // Greeting + name
          SizedBox(width:5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'welcome'.tr} 👋',
                  style: context.colors.caption.copyWith(
                    fontSize: 12,
                    color: context.colors.textLight,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  name,
                  style: context.colors.h2.copyWith(
                    fontSize: 17,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          // A guest has no inbox.
          if (!GuestState.active) NotificationIcon(unreadCount: unread),

        ],
      ),
    );
  }
}