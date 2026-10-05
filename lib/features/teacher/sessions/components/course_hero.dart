// components/course_hero.dart
//
// Hero banner at the top of the course-detail screen.
// Reads nothing from any provider — all data passed in as constructor params.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/helpers.dart';

import '../../../../../utils/widget/refresh_button.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../shared/course/private_flag.dart';
import '../../../shared/course/topbar.dart';
import '../../../student/courses/details/components/share_link.dart';
import '../../home/teacher_models.dart';
import 'course_reel_player.dart';

class CourseHero extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onBack;
  final VoidCallback? onEditCourse;
  final VoidCallback? onLike;
  final bool? isLike;
  final Future<void> Function() onRefresh;

  /// Optional intro video (عرض أولي). When present it plays INSTEAD of the
  /// course image (the image stays as its poster / fallback).
  final String? reelUrl;

  const CourseHero({
    super.key,
    required this.course,
    required this.onBack,
    this.onEditCourse,
    required this.onRefresh,
    this.onLike,
    this.isLike,
    this.reelUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: context.height / 3.5,
          width: double.infinity,
          child: _buildBackground(context),
        ),
        SizedBox(
          height: context.height / 3.5,
          width: double.infinity,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child:

                  CourseDetailsTopBar(
                    showRefresh: true,
                    onRefresh: onRefresh,
                    onBack: ()=>Navigator.pop(context),
                    onSetting: onEditCourse,
                    onShare: ()=> shareCourseLink(context, course.toCourseModel),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: Directionality(
                    textDirection: Helpers.textDirOf(course.description??''),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (course.category != null)
                          Row(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: context.colors.primary.withValues(
                                    alpha: 0.85,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  AppConfig.lang == 'ar'
                                      ? course.category!.nameAr
                                      : course.category!.nameEn,

                                  style: const TextStyle(
                                    fontFamily: 'tajawal',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (course.isPrivate) PrivateFlag(label: 'course_hero_private'.tr),
                            ],
                          ),
                        Text(
                          course.title,
                          style: const TextStyle(
                            fontFamily: 'tajawal',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (course.description != null &&
                            course.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            course.description!,
                            style: TextStyle(
                              fontFamily: 'tajawal',
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.80),
                              height: 1.45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackground(BuildContext context) {
    final imageUrl = course.imageUrl;
    final reel = reelUrl;
    if (reel != null && reel.isNotEmpty) {
      return CourseReelPlayer(
        key: ValueKey(reel),
        url: reel,
        posterUrl: imageUrl.isNotEmpty ? imageUrl : null,
      );
    }
    if (imageUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(gradient: context.colors.primaryGradient),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.25),
                Colors.black.withValues(alpha: 0.75),
              ],
            ),
          ),
          child: Image.network(
            imageUrl,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, _, _) => const _GradientBackground(),
          ),
        ),
      );
    }
    return const _GradientBackground();
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _GradientBackground extends StatelessWidget {
  const _GradientBackground();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: context.colors.accentGradient),
    child: Center(
      child: Icon(
        Icons.school_rounded,
        size: 72,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    ),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  const _CircleBtn({required this.icon, required this.onTap}) : label = null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.70),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: const TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
