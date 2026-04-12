import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../home_provider.dart';

class InstructorsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    final instructors = provider.instructors;
    return SizedBox(
      height: 130,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: instructors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          final ins = instructors[i];
          return SizedBox(
            width: 90,
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        width: 2.5),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: ClipOval(
                    child: AppNetworkImage(
                      url: ins.avatarUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(ins.name,
                    style: AppTheme.h3.copyWith(fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(ins.specialty,
                    style: AppTheme.caption,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }
}
