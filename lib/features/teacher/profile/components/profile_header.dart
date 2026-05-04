import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Colors;

import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../student/profile/profile_provider.dart';

class ProfileHeader extends StatelessWidget {
  final ProfileProvider provider;
  final VoidCallback onImageTap;

  const ProfileHeader({super.key, 
    required this.provider,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.primary.withValues(alpha: 0.1),
                border: Border.all(color: context.colors.primaryBlue, width: 2.5),
              ),
              child: provider.avatarUrl != null
                  ? ClipOval(child: AppNetworkImage(url: provider.avatarUrl!))
                  :  Icon(Icons.person_rounded,
                  size: 52, color: context.colors.primaryBlue),
            ),
            GestureDetector(
              onTap: onImageTap,
              child: Container(
                width: 32,
                height: 32,
                decoration:  BoxDecoration(
                    color: context.colors.primaryBlue, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(provider.name, style: context.colors.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 4),
        Text(provider.email, style: context.colors.caption),
      ],
    );
  }
}