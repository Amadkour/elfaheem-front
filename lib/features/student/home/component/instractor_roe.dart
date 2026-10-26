import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/profile/course_instractor_profile.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../home_provider.dart';

class InstructorsRow extends StatelessWidget {
  const InstructorsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    final instructors = provider.instructors;

    if (instructors.isEmpty) {
      return SizedBox(
        height: 128,
        child: Center(
          child: Text('لا يوجد مدرسون', style: context.colors.caption),
        ),
      );
    }

    return SizedBox(
      height: 136,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: instructors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          final ins = instructors[i];
          return SizedBox(
            width: 84,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ins.teacher != null)
                  InstructorAvatar(
                    teacher: ins.teacher!,
                    size: 50,
                    canOpen: true,
                    showTitle: false,
                  ),
                const SizedBox(height: 9),
                Text(
                  ins.teacher?.name ?? 'T',
                  style: context.colors.h3.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (ins.teacher?.teacherProfile?.specialization != null)
                  Text(AppConfig.lang=='ar'? ins.teacher!.teacherProfile!.specialization!.nameAr:ins.teacher!.teacherProfile!.specialization!.nameEn,
                    style: context.colors.caption.copyWith(
                      fontSize: 10,
                      color: context.colors.textLight,
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
