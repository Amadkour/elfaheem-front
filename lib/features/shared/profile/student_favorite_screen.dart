import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppEmpty, AppRefresh;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/search_text_field.dart';
import '../../student/courses/details/course_detail_screen.dart';
import '../../student/models.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;

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
      key: const ValueKey('favorites'),
      useWebCard: true,
      width: AppWidth.wide,
      appBar: ScreenAppBar(title: 'my_favorite'.tr),
      child: Column(children: [
        ParentComponent(
          featureKey: 'favorites.search',
          child: MySearchBar(
            controller: _search,
            hint: 'search_course_by_name_description',
            onChanged: context.read<ProfileProvider>().setQuery,
          ),
        ),
        Expanded(
            child: ParentComponent(
                featureKey: 'favorites.list',
                child: FavouritesStateBody(
                  loading: provider.isLoading,
                  empty: provider.favourites.isEmpty,
                  filtered: _search.text.trim().isNotEmpty,
                  error: provider.hasError ? (provider.errorMessage ?? '') : null,
                  onRefresh: provider.fetchMyFavorites,
                  list: HomeCourseList(
                  maxWidth: AppWidth.wide.max,
                  hasMore: false,
                  pageName: 'favorite',
                  courses: provider.favourites,
                  onTap: (CourseModel c) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            settings: RouteSettings(name: '/course-detail', arguments: c),
                            builder: (_) => CourseDetailScreen(course: c)));
                  },
                  isTeacher: false,
                ))))
      ]),
    );
  }
}

/// The favourites list area over plain values: skeleton on the first load, the error with a retry, an empty state
/// (no favourites yet / nothing matches the search), else the list — each with pull-to-refresh.
class FavouritesStateBody extends StatelessWidget {
  const FavouritesStateBody({
    super.key,
    required this.loading,
    required this.empty,
    required this.filtered,
    required this.error,
    required this.onRefresh,
    required this.list,
  });

  final bool loading, empty, filtered;
  final String? error;
  final Future<void> Function() onRefresh;
  final Widget list;

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    if (empty && loading) return const AppListSkeleton(withAvatar: false);
    if (empty && error != null) {
      return AppRefresh(
        onRefresh: onRefresh,
        scrollable: false,
        child: ErrorRetry(
            message: error!.isEmpty ? (ar ? 'تعذّر تحميل المفضلة' : 'Could not load your favourites') : error!,
            onRetry: onRefresh),
      );
    }
    if (empty) {
      return AppRefresh(
        onRefresh: onRefresh,
        scrollable: false,
        child: AppEmpty(
          icon: filtered ? Icons.search_off_rounded : Icons.favorite_border_rounded,
          title: filtered
              ? (ar ? 'لا توجد نتائج مطابقة' : 'Nothing matches your search')
              : (ar ? 'لا توجد دورات مفضلة بعد' : 'No favourite courses yet'),
          message: filtered ? null : (ar ? 'اضغط على القلب في أي دورة لتجدها هنا' : 'Tap the heart on any course to keep it here'),
        ),
      );
    }
    return AppRefresh(onRefresh: onRefresh, child: list);
  }
}
