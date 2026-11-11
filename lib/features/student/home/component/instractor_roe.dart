import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/profile/course_instractor_profile.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../home_provider.dart';

class InstructorsRow extends StatelessWidget {
  const InstructorsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    final instructors = provider.instructors;

    // nothing to show → nothing drawn (the home hides the section title too)
    if (instructors.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 150 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs),
        scrollDirection: Axis.horizontal,
        itemCount: instructors.length,
        separatorBuilder: (_, _) => AppSpace.gapMd,
        itemBuilder: (_, i) {
          final ins = instructors[i];
          return SizedBox(
            width: AppTouch.min * 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ins.teacher != null)
                  InstructorAvatar(
                    teacher: ins.teacher!,
                    size: AppTouch.min + AppSpace.xxs,
                    canOpen: true,
                    showTitle: false,
                  ),
                AppSpace.gapXs,
                Text(
                  ins.teacher?.name ?? 'T',
                  style: AppType.label(context).copyWith(color: context.colors.textDark, height: 1.2),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xxs / 2),
                if (ins.teacher?.teacherProfile?.specialization != null)
                  Text(AppConfig.lang=='ar'? ins.teacher!.teacherProfile!.specialization!.nameAr:ins.teacher!.teacherProfile!.specialization!.nameEn,
                    style: AppType.meta(context),
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
