import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/session/session_material_widget.dart';
import 'package:provider/provider.dart';
import '../../../../../config/app_config.dart';
import '../../../../../config/app_theme.dart';
import '../../../../shared/session/progress_banner.dart';
import '../course_detail_provider.dart';
class SessionsTab extends StatelessWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    if (provider.isLoading) {
      return Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.colors.primary),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (provider.sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.colors.primaryLight.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.video_library_outlined,
                    size: 36, color: context.colors.primary),
              ),
              const SizedBox(height: 14),
              Text('لا توجد دروس بعد', style: context.colors.body),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Progress summary banner
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: ProgressBanner(
            progress: provider.course.progress,
            total: provider.course.materialsTotal,
            complete: provider.course.materialsCompleted,
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: provider.sessions.length,
          itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SessionMaterialCard(
                session: provider.sessions[i].toTeacher,
                course: provider.course.toTeacherModel,
                isTeacher: false,
              )
              ),
        ),
      ],
    );
  }
}
