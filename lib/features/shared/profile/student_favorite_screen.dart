import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/base_page.dart';
import '../../student/courses/details/course_detail_screen.dart';
import '../../student/home/component/course_row.dart';
import '../../student/models.dart';
import '../../teacher/home/home_screen.dart';
import 'course_instractor_profile.dart';

class FavouriteCoursesScreen extends StatefulWidget {
  const FavouriteCoursesScreen({super.key});

  @override
  State<FavouriteCoursesScreen> createState() => _FavouriteCoursesScreenState();
}

class _FavouriteCoursesScreenState extends State<FavouriteCoursesScreen> {
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
      child:HomeCourseList(hasMore: false, courses: provider.favourites, onTap:  (CourseModel c) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CourseDetailScreen(course: c)));
      }, isTeacher: false)
    );
  }
}