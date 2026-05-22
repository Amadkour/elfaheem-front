import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/session/session_material_widget.dart';
import 'package:provider/provider.dart';
import '../../../../../config/app_config.dart';
import '../../../../../config/app_theme.dart';
import '../course_detail_provider.dart';
class SessionsTab extends StatelessWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    final sessions = provider.course.sessions;
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

    if (sessions.isEmpty) {
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
          child: _ProgressBanner(
            progress: provider.course.progress,
            total: provider.course.materialsTotal,
            complete: provider.course.materialsCompleted,
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: sessions.length,
          itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SessionMaterialCard(
                session: sessions[i].toTeacher,
                course: provider.course.toTeacherModel,
                isTeacher: false,
              )
              ),
        ),
      ],
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  final double progress;
  final int total;
  final int complete;
  const _ProgressBanner({
    required this.progress, required this.total, required this.complete,
  });

  @override
  Widget build(BuildContext context) {
    Gradient primary=progress>90?context.colors.successGradient:progress>30?context.colors.primaryGradient:context.colors.dangerGradient;

    return Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: primary,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: context.colors.primary.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // Circular progress
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(
                    value: progress/100,
                    strokeWidth: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                Text(
                  '$progress%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'bahji',
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    'you_progress_in_course'.tr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'bahji',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$complete ${'from'.tr} $total ',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontFamily: 'bahji',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress/100,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
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