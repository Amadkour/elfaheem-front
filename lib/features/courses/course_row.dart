import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseModel, DiscountInfoX;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/design/app_kit.dart' show AppSpace, AppIconSize, AppType, appInk, appTintOn;

class CoursesRow extends StatelessWidget {
  final List<CourseModel> courses;
  final bool isTeacher;
  final bool isFullScreen;
  final String pageName;
  final void Function(CourseModel course) onTap;

  const CoursesRow({
    super.key,
    required this.courses,
    required this.isTeacher,
    required this.onTap,
    this.isFullScreen = false,
    required this.pageName,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_row',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final ScrollController controller = ScrollController();

    if (courses.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text('no_courses_yet'.tr, style: AppType.body(context)),
        ),
      );
    }
    Widget list;
    // ── Mobile: horizontal scroll ───────────────────────────────────────────
    if (courses.length < 5) {
      list = SizedBox(
        height: context.height / 2 > 300 ? 300 : context.height / 3,
        child: ListView.separated(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          scrollDirection: isFullScreen ? Axis.vertical : Axis.horizontal,
          itemCount: courses.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
          itemBuilder: (_, i) => CourseCard(
            course: courses[i],
            fixedWidth: 188,
            isTeacher: isTeacher,
            onTap: onTap,
            pageName: pageName,
          ),
        ),
      );
    } else {
      list = SizedBox(
        height: context.height / 2 > 600 ? 600 : context.height / 3,
        child: GridView.builder(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          scrollDirection: Axis.horizontal,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // 2 items vertically
            crossAxisSpacing: AppSpace.sm,
            mainAxisSpacing: AppSpace.sm,
            childAspectRatio: 3 / 2,
          ),
          itemCount: courses.length,
          itemBuilder: (_, i) => CourseCard(
            course: courses[i],
            fixedWidth: 188,
            isTeacher: isTeacher,
            onTap: onTap,
            pageName: pageName,
          ),
        ),
      );
    }
    if (!kIsWeb) return list;
    return Scrollbar(
      controller: controller,
      thumbVisibility: true, // This keeps the 'cursor' visible
      trackVisibility: true, // Optional: shows the path of the scrollbar
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
        child: list,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Course Card — a CourseModel drawn as the shared CourseListCard
// (course_list_card.dart: the one card language of every course list)
// ────────────────────────────────────────────────────────────────────────────
class CourseCard extends StatelessWidget {
  final CourseModel course;
  final double? fixedWidth;
  final bool isTeacher;
  final bool fullScreen;
  final String pageName;
  final void Function(CourseModel course) onTap;

  /// Row (phone list) or tile (grid cell).
  final CourseCardShape shape;

  /// Leads the meta line in place of the teacher / organization — where the course lives in a mixed list.
  final Widget? badge;

  const CourseCard({
    super.key,
    required this.course,
    this.fixedWidth,
    required this.isTeacher,
    required this.onTap,
    this.fullScreen = false,
    required this.pageName,
    this.shape = CourseCardShape.tile,
    this.badge,
  });

  /// Exact cell height of a tile in a grid: use it as `mainAxisExtent`.
  static double cellHeight(BuildContext context, double cellWidth) => CourseListCard.tileHeight(context, cellWidth);

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card',
    child: SizedBox(width: fixedWidth, child: _card(context)),
  );

  Widget _card(BuildContext context) {
    final c = course;
    final ar = AppConfig.lang == 'ar';
    final title = (ar ? c.titleAr ?? c.titleEn : c.titleEn ?? c.titleAr) ?? '';
    // who: the organization for an organization course, else the teacher (a teacher's own list skips himself)
    final who = c.org?.name ?? (isTeacher ? null : c.teacher?.name);
    final amount = c.sessionsCount > 0
        ? courseLessonsLabel(c.sessionsCount)
        : (c.hoursCount > 0 ? courseHoursLabel(c.hoursCount) : null);
    final meta = <String>[
      if (badge == null && who != null && !courseFeatureOff('course_card.instructor')) who,
      ?amount,
    ];

    final Widget footer;
    if (isTeacher) {
      footer = CourseStatsFooter(
        students: c.studentsCount,
        sessions: c.sessionsCount,
        rating: c.rateSummary?.average,
      );
    } else if (c.isEnrolled) {
      footer = CourseProgressFooter(progress: c.progress);
    } else {
      final off = c.hasDiscount ? c.discountPercentage?.round() : null;
      footer = CoursePriceFooter(
        price: coursePriceLabel(c.currency, c.effectivePrice),
        free: c.effectivePrice == 0,
        original: c.hasDiscount && c.price > c.effectivePrice ? coursePriceLabel(c.currency, c.price) : null,
        offPercent: off,
      );
    }

    return CourseListCard(
      shape: shape,
      title: title,
      imageUrl: c.imageUrl,
      heroTag: 'course-row-card-$pageName-${c.id}',
      chip: isTeacher
          ? (courseFeatureOff('course_card.publish_status')
              ? null
              : CourseCoverChip.status(context, published: c.isPublished))
          : (courseFeatureOff('course_card.type_badge') ? null : CourseCoverChip.type(context, live: c.type == 'live')),
      corner: !isTeacher && c.isFavorite && !courseFeatureOff('course_card.favorite') ? const CourseFavoriteMark() : null,
      meta: meta,
      metaLead: badge,
      isPrivate: c.isPrivate,
      footer: footer,
      onTap: () => onTap(c),
    );
  }
}

class IconColored extends StatelessWidget {
  final Color color;
  final IconData icon;

  const IconColored({super.key, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppIconSize.md,
      height: AppIconSize.md,
      decoration: BoxDecoration(
        color: appTintOn(context, color),
        borderRadius: BorderRadius.circular(AppSpace.xxs + 1),
      ),
      child: Icon(icon, size: AppIconSize.xs - 1, color: appInk(context, color)),
    );
  }
}
