import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/courses/details/course_detail_screen.dart';
import '../../student/home/component/course_row.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class HomeCourseList extends StatelessWidget {
  const HomeCourseList({
    super.key,
    required this.hasMore,
    required this.courses,
    required this.onTap,
    required this.isTeacher,
    required this.pageName,
  });

  final String pageName;

  final List<CourseModel> courses;
  final bool hasMore;
  final void Function(CourseModel course) onTap;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final w = context.screenW;
    final cols = w >= 700 ? 3 : 2;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Breakpoints.contentMax),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          physics: const BouncingScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.7,
          ),
          itemCount: courses.length + (hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= courses.length) {
              return Center(child: AppLoadingIndicator());
            }
            return CourseCard(
              course: courses[i],
              pageName: pageName,
              fixedWidth: 188,
              isTeacher: isTeacher,
              fullScreen: true,
              onTap: (CourseModel c) {
                Navigator.pushNamed(context, '/course-detail', arguments: c);

              },
            );
          },
        ),
      ),
    );
  }
}
