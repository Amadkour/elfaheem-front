import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/student/models.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../courses/list/courses_list_screen.dart';

/// The home's search box (a button that opens the course search), drawn as the kit's input well (the warm `inputBg`
/// fill, radius 14, a hairline at rest — §3a of lib/design/README.md) so it reads as "type here". Under the header on
/// a phone, at the header's end on the desktop dashboard.
class SearchBarIcon extends StatelessWidget {
  const SearchBarIcon({super.key, required this.courses, this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs)});

  final List<CourseModel> courses;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.control);
    return Padding(
      padding: padding,
      child: Semantics(
        button: true,
        label: 'search'.tr,
        excludeSemantics: true,
        child: Material(
          color: c.inputBg,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CoursesListScreen(
                  openSearch: true,
                  homeCourses: courses,
                  forMyCourses: false,
                ),
              ),
            ),
            child: SizedBox(
              height: AppTouch.min,
              child: Row(
                children: [
                  SizedBox(
                    width: AppTouch.min,
                    child: Icon(Icons.search_rounded, color: c.textLight, size: AppIconSize.md),
                  ),
                  Expanded(
                    child: Text(
                      'search'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(context).copyWith(color: c.textLight),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
