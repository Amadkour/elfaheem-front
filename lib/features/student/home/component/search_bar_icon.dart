import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../courses/list/courses_list_screen.dart';

class SearchBarIcon extends StatelessWidget {
  const SearchBarIcon({super.key, required this.courses});

  final List<CourseModel> courses;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CoursesListScreen(
              openSearch: true,
              homeCourses: courses,
              forMyCourses: false,
            ),
          ),
        ),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(context.colors.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.search_rounded,
                  color: context.colors.textLight,
                  size: 22,
                ),
              ),
              Expanded(
                child: Text(
                  'search'.tr,
                  style: context.colors.caption.copyWith(
                    fontSize: 14,
                    color: context.colors.textLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
