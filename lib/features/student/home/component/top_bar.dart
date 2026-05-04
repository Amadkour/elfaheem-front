import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/app_theme.dart';
import '../../../auth/auth_provider.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final name = user?.name ?? 'sir'.tr;
    final initial = name.isNotEmpty ? name[0] : '؟';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: [
          // Gradient avatar with glow
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: context.colors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: context.colors.primary.withValues(alpha:0.40),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Greeting + name
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

          // Notification bell — elevated card style
          GestureDetector(
            onTap: () =>
                Navigator.of(context).popAndPushNamed('/notifications'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.colors.cardBg,
                    borderRadius:
                    BorderRadius.circular(context.colors.radiusMedium),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child:  Icon(
                    Icons.notifications_rounded,
                    color: context.colors.primary,
                    size: 22,
                  ),
                ),
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: context.colors.danger,
                      shape: BoxShape.circle,
                      border:
                      Border.all(color: context.colors.cardBg, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}