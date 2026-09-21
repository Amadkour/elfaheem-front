import 'package:flutter/material.dart';
import '../../../../../config/theme/app_theme.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../shared/session/material/components/session_progress_section.dart';
import '../../../../shared/session/material/session_material_widget.dart';
import '../../../models.dart';
import '../course_detail_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class SessionsTab extends StatelessWidget {
  const SessionsTab({
    super.key,
    required this.presented,
    required this.provider,
  });

  final List<SessionModel> presented;
  final CourseDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: AppLoadingIndicator()),
      );
    }
    if (presented.isEmpty) {
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
                child: Icon(
                  Icons.video_library_outlined,
                  size: 36,
                  color: context.colors.primary,
                ),
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
          child: SessionProgressSection(
            totalMaterial: provider.course.materialsTotal,
            completeMaterial: provider.course.materialsCompleted,
            isTeacher: false,
            isFull: true,
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: presented.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SessionMaterialCard(
              session: presented[i].toTeacher,
              course: provider.course.toTeacherModel,
              isTeacher: false,
              locked: !provider.isSessionUnlockedById(presented[i].id),
            ),
          ),
        ),
        // Footer for the next page of sessions. The actual scroll-position
        // trigger lives one level up (this list never scrolls itself — see
        // the NotificationListener around the outer CustomScrollView in
        // course_detail_screen.dart); this widget only reflects the state.
        if (provider.isLoadingMoreSessions)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(width: 22, height: 22, child: AppLoadingIndicator()),
            ),
          ),
      ],
    );
  }
}