import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Colors;

import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../shared/profile/profile_provider.dart' show ProfileProvider;

class ProfileHeader extends StatelessWidget {
  final ProfileProvider provider;

  const ProfileHeader({super.key, 
    required this.provider,
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
              child: provider.imageUrl.isNotEmpty
                  ? ClipOval(child: AppNetworkImage(url: provider.imageUrl))
                  :  Icon(Icons.person_rounded,
                  size: 52, color: context.colors.primaryBlue),
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