import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/private_flag.dart';
import 'package:flutter_education_app/features/student/models.dart'
    show CourseModel, AppCurrencyX, DiscountInfoX;
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../profile/course_instractor_profile.dart';
import 'course_price_tag.dart';

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
          child: Text('no_courses_yet'.tr, style: context.colors.body),
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: isFullScreen ? Axis.vertical : Axis.horizontal,
          itemCount: courses.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // 2 items vertically
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
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
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
        child: list,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Course Card — full data display
// ────────────────────────────────────────────────────────────────────────────
class CourseCard extends StatelessWidget {
  final CourseModel course;
  final double? fixedWidth;
  final bool isTeacher;
  final bool fullScreen;
  final String pageName;
  final void Function(CourseModel course) onTap;

  const CourseCard({
    super.key,
    required this.course,
    this.fixedWidth,
    required this.isTeacher,
    required this.onTap,
    this.fullScreen = false,
    required this.pageName,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final hasLectures = course.sessionsCount > 0;
    final hasHours = course.hoursCount > 0;
    final hasCertificate = course.certificates.isNotEmpty;
    final hasStudents = course.studentsCount > 0;
    final String description =
        (AppConfig.lang == 'ar'
            ? course.descriptionAr
            : course.descriptionEn) ??
            '';

    return GestureDetector(
      onTap: () => onTap.call(course),
      child: Container(
        width: fixedWidth,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: _Thumbnail(
                course: course,
                isTeacher: isTeacher,
                fullScreen: fullScreen,
                pageName: pageName,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            (AppConfig.lang == 'ar'
                                ? course.titleAr
                                : course.titleEn) ??
                                '',
                            style: context.colors.h3.copyWith(
                              fontSize: 13,
                              overflow: TextOverflow.ellipsis,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (course.rateSummary?.average != null)
                          _StatsRow(course: course),
                      ],
                    ),

                    const _CardDivider(),

                    // Teacher
                    Spacer(flex: 1),
                    if (description.isNotEmpty) ...[
                      ParentComponent(featureKey: 'course_card.description', child: Text(
                        description,
                        style: context.colors.caption.copyWith(
                          overflow: TextOverflow.ellipsis,
                          color: context.colors.textLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                      )),
                      Spacer(flex: 1),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (!isTeacher && course.teacher != null)
                          Expanded(
                            flex: 1,
                            child: ParentComponent(featureKey: 'course_card.instructor', child: InstructorAvatar(
                              teacher: course.teacher!,
                              size: 30,
                              canOpen: true,
                              showTitle: true,
                              showImage: false,
                            )),
                          ),
                        if (course.category != null)
                          Flexible(
                            flex: 1,
                            child: ParentComponent(featureKey: 'course_card.category', child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                AppConfig.lang == 'ar'
                                    ? course.category!.nameAr
                                    : course.category!.nameEn,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'bahji',
                                ),
                              ),
                            )),
                          ),
                        if (isTeacher)
                          Flexible(
                            flex: 1,
                            child: ParentComponent(featureKey: 'course_card.publish_status', child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: course.isPublished
                                    ? context.colors.success
                                    : context.colors.warning,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                course.isPublished
                                    ? 'published'.tr
                                    : 'draft'.tr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'bahji',
                                ),
                              ),
                            )),
                          ),
                      ],
                    ),
                    Spacer(flex: 1),
                    if (hasStudents || hasCertificate)
                      _StudentRow(
                        course: course,
                        hasStudents: hasStudents,
                        hasCertificate: hasCertificate,
                      ),
                    Spacer(),

                    // Lectures + hours
                    if (hasHours || hasLectures)
                      _MetaRow(
                        course: course,
                        hasHours: hasHours,
                        hasLectures: hasLectures,
                      ),
                    Spacer(flex: 2),

                    // Text(course.progress.toString()),
                    // Progress bar — only when enrolled
                    if ((course.isEnrolled || isTeacher) &&
                        course.progress > 0) ...[
                      _ProgressBar(progress: course.progress),
                      Spacer(flex: 2),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Thumbnail ────────────────────────────────────────────────────────────────
class _Thumbnail extends StatelessWidget {
  final CourseModel course;
  final bool isTeacher;
  final bool fullScreen;
  final String pageName;

  const _Thumbnail({
    required this.course,
    required this.isTeacher,
    required this.fullScreen,
    required this.pageName,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card.thumbnail',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AppNetworkImage(
            url: course.imageUrl,
            width: double.infinity,
            fit: BoxFit.cover,
            heroTag: "course-row-card-$pageName-${course.id}",
          ),
        ),
        // Bottom dark gradient for readability
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.36),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // Type badge — top right
        Positioned(
          top: 10,
          right: 10,
          child: ParentComponent(featureKey: 'course_card.type_badge', child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: BoxBorder.all(color: Colors.white, width: 0.75),
            ),
            child: Text(
              course.type.tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'bahji',
              ),
            ),
          )),
        ),

        // Favorite heart — top left
        if (!isTeacher)
          Positioned(
            top: 8,
            left: 10,
            child: ParentComponent(featureKey: 'course_card.favorite', child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                shape: BoxShape.circle,
              ),
              child: Icon(
                course.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 15,
                color: course.isFavorite
                    ? const Color(0xFFE24B4A)
                    : Colors.grey.shade400,
              ),
            )),
          ),

        // Discount ribbon — top right, under the type badge
        if (course.hasDiscount)
          Positioned(
            top: 34,
            right: 10,
            child: ParentComponent(featureKey: 'course_card.discount', child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DiscountRibbon.forCourse(course: course),
                if (course.discountEndsAt != null) ...[
                  SizedBox(height: 2),
                  DiscountCountdownBadge(course: course, compact: true),
                ],
              ],
            )),
          ),

        // Private course flag — bottom left
        if (course.isPrivate)
          Positioned(bottom: 10, left: 10, child: ParentComponent(featureKey: 'course_card.private_flag', child: PrivateFlag())),

        // Countdown — bottom left, opposite the price badge. This is the
        // "hurry up" nudge: calm amber while there's still time, switching
        // to a pulsing red pill once the discount enters its last 24h.

        // Price badge — bottom right
        Positioned(
          bottom: 10,
          right: 10,
          child: ParentComponent(featureKey: 'course_card.price', child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: course.effectivePrice == 0
                  ? const Color(0xFF0F6E56)
                  : context.colors.primary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color:
                  (course.effectivePrice == 0
                      ? const Color(0xFF0F6E56)
                      : context.colors.primary)
                      .withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (course.hasDiscount) ...[
                  Text(
                    course.currency.format(course.price),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 9,
                      fontFamily: 'bahji',
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  course.currency.format(course.effectivePrice),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    fontFamily: 'bahji',
                  ),
                ),
              ],
            ),
          )),
        ),
      ],
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
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }
}

// ── Thin divider ─────────────────────────────────────────────────────────────
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: Colors.black.withValues(alpha: 0.07),
      ),
    );
  }
}

// ── Rating + students ────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final CourseModel course;

  const _StatsRow({required this.course});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card.rating',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.star_rounded, color: context.colors.accent, size: 13),
        const SizedBox(width: 3),
        Text(
          course.rateSummary?.average.toStringAsFixed(1) ?? '',
          style: context.colors.caption.copyWith(
            color: context.colors.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ── Lectures + hours ─────────────────────────────────────────────────────────
class _MetaRow extends StatelessWidget {
  final CourseModel course;
  final bool hasLectures, hasHours;

  const _MetaRow({
    required this.course,
    required this.hasLectures,
    required this.hasHours,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card.meta',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    return Row(
      children: [
        if (hasLectures) ...[
          IconColored(
            color: context.colors.primary,
            icon: Icons.play_circle_outline_rounded,
          ),
          const SizedBox(width: 3),
          Text(
            '${course.sessionsCount} ${'session'.tr}',
            maxLines: 1,
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        if (hasLectures && hasHours) Spacer(),
        if (hasHours) ...[
          IconColored(
            color: context.colors.accent,
            icon: Icons.access_time_rounded,
          ),
          const SizedBox(width: 3),
          Text(
            '${course.hoursCount} ${'hours'.tr}',
            maxLines: 1,
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        Spacer(),
      ],
    );
  }
}

// ── Lectures + hours ─────────────────────────────────────────────────────────
class _StudentRow extends StatelessWidget {
  final CourseModel course;
  final bool hasStudents, hasCertificate;

  const _StudentRow({
    required this.course,
    required this.hasStudents,
    required this.hasCertificate,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card.students',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    return Row(
      children: [
        if (hasCertificate) ...[
          IconColored(
            color: context.colors.success,
            icon: Icons.workspace_premium_rounded,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              course.certificates.first.title,
              maxLines: 1,
              style: context.colors.caption.copyWith(fontSize: 10),
            ),
          ),
        ],
        if (hasStudents && hasCertificate) Spacer(),
        if (hasStudents) ...[
          IconColored(
            color: context.colors.accent2,
            icon: CupertinoIcons.group,
          ),
          const SizedBox(width: 3),
          Text(
            '${course.studentsCount} ${'student'.tr}',
            maxLines: 1,
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        Spacer(),
      ],
    );
  }
}

// ── Progress bar ─────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final int progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_card.progress',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    Color primary = progress > 90
        ? context.colors.success
        : progress > 30
        ? context.colors.primary
        : context.colors.danger;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'you_progress'.tr,
          style: context.colors.caption.copyWith(fontSize: 10),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (progress / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: context.colors.primaryLight.withValues(
                  alpha: 0.3,
                ),
                valueColor: AlwaysStoppedAnimation(primary),
              ),
            ),
          ),
        ),
        Text(
          '$progress%',
          style: context.colors.caption.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
      ],
    );
  }
}