import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/student/models.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../courses/list/courses_list_screen.dart';

/// The home's search box (a button that opens the course search): the card surface with a hairline, like the
/// course lists' search field. Under the header on a phone, at the header's end on the desktop dashboard.
class SearchBarIcon extends StatelessWidget {
  const SearchBarIcon({super.key, required this.courses, this.padding = const EdgeInsets.symmetric(horizontal: 20)});

  final List<CourseModel> courses;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(c.radiusLarge);
    return Padding(
      padding: padding,
      child: Semantics(
        button: true,
        label: 'search'.tr,
        excludeSemantics: true,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider)),
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
              height: 48,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(Icons.search_rounded, color: c.textLight, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      'search'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appText(14, c: c.textLight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
