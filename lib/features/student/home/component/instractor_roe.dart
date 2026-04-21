import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../home_provider.dart';

const List<List<Color>> _avatarGradients = [
  [Color(0xFF5B4FCF), Color(0xFF9B93FF)],
  [Color(0xFFFF8C42), Color(0xFFFFBA80)],
  [Color(0xFFFF4D6A), Color(0xFFFF8FA3)],
  [Color(0xFF2EC4B6), Color(0xFF70DFD8)],
];

class InstructorsRow extends StatelessWidget {
  const InstructorsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    final instructors = provider.instructors;

    if (instructors.isEmpty) {
      return const SizedBox(
        height: 128,
        child: Center(
          child: Text('لا يوجد مدرسون', style: AppTheme.caption),
        ),
      );
    }

    return SizedBox(
      height: 136,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: instructors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          final ins = instructors[i];
          final gradColors = _avatarGradients[i % _avatarGradients.length];
          final initial = ins.name.isNotEmpty ? ins.name[0] : '؟';

          return SizedBox(
            width: 84,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar with gradient ring + shadow
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: gradColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: gradColors[0].withValues(alpha:0.25),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradColors[0].withValues(alpha:0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ins.avatarUrl.isNotEmpty
                      ? ClipOval(
                    child: AppNetworkImage(
                      url: ins.avatarUrl,
                      fit: BoxFit.cover,
                    ),
                  )
                      : Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  ins.name,
                  style: AppTheme.h3.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  ins.specialty,
                  style: AppTheme.caption.copyWith(
                    fontSize: 10,
                    color: AppTheme.textLight,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}