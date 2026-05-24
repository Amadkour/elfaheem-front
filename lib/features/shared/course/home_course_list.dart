import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/courses/details/course_detail_screen.dart';
import '../../student/home/component/course_row.dart';
import '../profile/course_instractor_profile.dart';

class HomeCourseList extends StatelessWidget {
  const HomeCourseList({super.key,required this.hasMore, required this.courses, required this.onTap, required this.isTeacher});
  final List<CourseModel> courses;
  final bool hasMore;
  final void Function(CourseModel course) onTap;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final w = context.screenW;
    final cols = w >= 1100 ? 3 : (w >= 700 ? 2 : 1);
    final isGrid = cols > 1;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Breakpoints.contentMax),
        child: isGrid
            ? GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 2.3,
          ),
          itemCount:courses.length + (hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= courses.length) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor:
                  AlwaysStoppedAnimation(context.colors.primary),
                  strokeWidth: 2,
                ),
              );
            }
            return CourseCard(
              course: courses[i],
              isTeacher: isTeacher,
              onTap: (CourseModel c) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CourseDetailScreen(course: c)));
              },
            );
          },
        )
            : ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          physics: const BouncingScrollPhysics(),
          itemCount:
         courses.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i ==courses.length) {
              return Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(
                        context.colors.primary),
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return CourseCard(
              course: courses[i],
              isTeacher: isTeacher,
              onTap: (CourseModel c) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CourseDetailScreen(course: c)));
              },
            );
          },
        ),
      ),
    );
  }
}