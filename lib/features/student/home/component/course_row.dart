/// course_row.dart  —  v3.2.0
/// Horizontal scrollable course cards on the home screen.
/// Shows: thumbnail, title, averageRating, studentsCount, sessionsCount, category
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../courses/details/course_detail_provider.dart';
import '../../courses/details/course_detail_screen.dart';
import '../../courses/list/courses_provider.dart';

class CoursesRow extends StatelessWidget {
  const CoursesRow({super.key});

  @override
  Widget build(BuildContext context) {
    final CoursesProvider provider = context.watch<CoursesProvider>();

    if (provider.isLoading) {
      return const SizedBox(
        height: 218,
        child: Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primary))),
      );
    }
    if (provider.courses.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(child: Text('لا توجد كورسات', style: AppTheme.body)),
      );
    }

    final display = provider.courses.take(5).toList();

    return SizedBox(
      height: 230,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: display.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final course = display[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CourseDetailScreen(
                course: course,
              ),
            )),
            child: Container(
              width: 175,
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                boxShadow: AppTheme.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail + price badge
                  Stack(children: [
                    AppNetworkImage(
                      url: course.imageUrl,
                      width: 175,
                      height: 118,
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          course.price == 0
                              ? 'مجاني'
                              : '\$ ${course.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              fontFamily: 'Cairo'),
                        ),
                      ),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(course.title,
                            style: AppTheme.h3.copyWith(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        // Rating + students
                        Row(children: [
                          const Icon(Icons.star_rounded,
                              color: AppTheme.accent, size: 13),
                          const SizedBox(width: 3),
                          Text(course.rate?.toStringAsFixed(1) ?? '',
                              style: AppTheme.caption.copyWith(
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                            '${course.studentsCount} طالب',
                            style: AppTheme.caption,
                            overflow: TextOverflow.ellipsis,
                          )),
                        ]),
                        const SizedBox(height: 4),
                        // Sessions count + category
                        Row(children: [
                          const Icon(Icons.video_library_rounded,
                              size: 11, color: AppTheme.textLight),
                          const SizedBox(width: 3),
                          if (course.sessions.isNotEmpty)
                            Text('${course.sessions.length} محاضرة',
                                style: AppTheme.caption),
                          const SizedBox(width: 8),
                          if (course.categoryName != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(course.categoryName!,
                                  style: AppTheme.caption.copyWith(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700)),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
