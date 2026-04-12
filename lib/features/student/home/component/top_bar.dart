
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/app_theme.dart';
import '../../../auth/auth_provider.dart';

class TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final name = user?.name ?? 'sir'.tr;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          // Avatar
          Container(
            width:  52,
            height: 52,
            decoration: BoxDecoration(
              shape:     BoxShape.circle,
              border:    Border.all(color: AppTheme.primary, width: 2.5),
              boxShadow: AppTheme.primaryShadow,
            ),
            child:  const ClipOval(
              child: Icon(Icons.person_rounded,
                  size: 30, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('welcome'.tr,
                    style: AppTheme.caption.copyWith(fontSize: 12)),
                Text(name, style: AppTheme.h2.copyWith(fontSize: 18)),
              ],
            ),
          ),
          // Emoji chip
          InkWell(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        AppTheme.cardBg,
                borderRadius: BorderRadius.circular(14),
                boxShadow:    AppTheme.cardShadow,
              ),
              child: const Text('🐣', style: TextStyle(fontSize: 22)),
            ),
            onTap: (){
              Navigator.of(context).popAndPushNamed('/notifications');
            },
          ),
        ],
      ),
    );
  }
}
