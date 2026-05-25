import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/search_text_field.dart';
import '../../student/courses/details/course_detail_screen.dart';
import '../../student/models.dart';

class FavouriteCoursesScreen extends StatefulWidget {
  const FavouriteCoursesScreen({super.key});

  @override
  State<FavouriteCoursesScreen> createState() => _FavouriteCoursesScreenState();
}

class _FavouriteCoursesScreenState extends State<FavouriteCoursesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ProfileProvider>().fetchMyFavorites();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    return BasePage(
      useWebCard: true,
      appBar: ScreenAppBar(title: 'favorite'.tr),
      child: Column(children: [
        MySearchBar(
          controller: _search,
          hint: 'search_course_by_name_description',
          onChanged: context.read<ProfileProvider>().setQuery,
        ),
        Expanded(
            child: HomeCourseList(
          hasMore: false,
          pageName: 'favorite',
          courses: provider.favourites,
          onTap: (CourseModel c) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CourseDetailScreen(course: c)));
          },
          isTeacher: false,
        ))
      ]),
    );
  }
}
