/// courses/details/course_detail_screen.dart
///
/// Layouts
///  • phone / tablet  (< 980 px): hero → rating/support → highlights → tabs →
///                                content, with a sticky price + enroll bar.
///  • web / desktop   (≥ 980 px): left = hero + tabs + content (scrolls),
///                                right = sticky price / enroll card.
///
/// Every fact is shown ONCE:
///  students · lessons · hours · progress · category · teacher → hero
///  price · discount · enroll                                  → buy card / bar
///  certificate · live/recorded                                → highlights
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/rating_widget.dart';
import '../../../shared/course/course_price_tag.dart';
import '../../../shared/course/studend_course_roadmap_section.dart';
import '../../../shared/guest/guest_state.dart';
import '../../../shared/profile/compalints/complaint_provider.dart';
import '../../../shared/profile/compalints/new_complaint_screen.dart';
import '../../analysis/exam/student_exam_provider.dart';
import '../../enrollment/enrollment_screen.dart';
import '../../enrollment/enrollment_widgets.dart';
import '../../enrollment/roadmap_enrollment_screen.dart';
import '../../models.dart';
import 'components/content.dart';
import 'components/share_link.dart';
import 'components/student_course_hero.dart';
import 'course_detail_provider.dart';
import '../../../shared/course_profile/course_profile_screen.dart' show openCourseProfile;
import 'package:flutter_education_app/design/app_kit.dart' show AppBanner;
import 'growth_tr.dart';

/// Below this width we use the single-column (phone/tablet) layout.
const double _kTwoColumnW = 800;
const double _kSideW = 240;

void _openRecommendedCourse(BuildContext context, CourseSummary summary) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          CourseDetailScreen(course: CourseModel.fromSummary(summary)),
    ),
  );
}

/// Opens the enrollment flow and, once the student comes back, refreshes the
/// course details (enrolled state, price, etc). Shared by the enroll button
/// and by the payment-status banner's "send it again" action.
Future<void> _openEnrollment(BuildContext context, CourseModel course) async {
  if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_enroll')) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => EnrollmentScreen(course: course)));
  if (context.mounted) {
    await context.read<CourseDetailProvider>().refresh();
  }
}

void _openSupport(BuildContext context, CourseModel course) {
  if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_support')) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => ComplaintProvider(),
        child: NewComplaintScreen(
          courseTitle:
              (AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ?? '',
          courseId: course.id,
        ),
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Screen
// ═════════════════════════════════════════════════════════════════════════════

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.course});

  final CourseModel course;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final CourseDetailProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<CourseDetailProvider>();
    _provider.course = widget.course;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.init(widget.course);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    final w = MediaQuery.of(context).size.width;
    final twoCol = w >= _kTwoColumnW;

    // Full-screen loader only for the FIRST load. While the next page of
    // sessions loads (sessions already on screen) the page must stay put.
    final loading = provider.isLoading && provider.sessions.isEmpty;
    final loaderSize = (w / 5).clamp(80.0, 160.0).toDouble();

    return BasePage(
      useWebCard: true,
      enableFooterWidget: false,
      maxWith: twoCol ? 1180 : 800,
      child: loading
          ? Center(
              child: SizedBox(
                width: loaderSize,
                height: loaderSize,
                child: AppLoadingIndicator(),
              ),
            )
          : _Body(twoCol: twoCol),
    );
  }
}

/// Provides what the tabs need, then picks the layout. One set of providers
/// for BOTH layouts (the web layout used to be missing StudentExamProvider).
class _Body extends StatelessWidget {
  const _Body({required this.twoCol});

  final bool twoCol;

  @override
  Widget build(BuildContext context) {
    final course = context.read<CourseDetailProvider>().course;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentExamProvider()),
        ChangeNotifierProvider(
          create: (_) =>
              TeacherCourseScreenProvider(initialCourse: course.toTeacherModel),
        ),
      ],
      child: Column(
        children: [
          Expanded(child: twoCol ? const _WebLayout() : const _MobileLayout()),
          if (context.width < 1200) _MobileBuyBar(),
        ],
      ),
    );
  }
}

// Fires CourseDetailProvider.loadMoreSessions() a little before the
// scrollable's true end, while the lessons tab is active. The sessions list is
// embedded as a non-scrolling sliver, so the outer CustomScrollView is what
// actually scrolls.
bool _onCourseDetailScroll(BuildContext context, ScrollNotification n) {
  final provider = context.read<CourseDetailProvider>();
  if (provider.activeTab == CourseDetailTab.lessons &&
      n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
    provider.loadMoreSessions();
  }
  return false;
}

/// Slivers shared by both layouts (everything under the hero).
List<Widget> _contentSlivers(
  BuildContext context,
  CourseDetailProvider p, {
  required bool showChips,
}) {
  final c = p.course;
  final highlights = _highlights(context, c);
  return [
    const SliverToBoxAdapter(child: _MetaRow()),
    if (c.isEnrolled && int.tryParse(c.id) != null) // course profile: progress per part, attendance, certificates, archive
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: AppBanner(
            icon: Icons.dashboard_customize_rounded,
            text: gt('ملف المقرر: تقدّمك وحضورك وشهاداتك', 'Course profile: your progress, attendance and certificates'),
            action: TextButton(
              onPressed: () => openCourseProfile(context, int.parse(c.id)),
              child: Text(gt('فتح', 'Open')),
            ),
          ),
        ),
      ),
    if (showChips && highlights.isNotEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _HighlightChips(items: highlights),
        ),
      ),
    const SliverToBoxAdapter(child: _TabBarWidget()),
    const SliverToBoxAdapter(child: SizedBox(height: 4)),
    SliverToBoxAdapter(
      child: TabContent(activeTab: p.activeTab, courseId: c.id),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 20)),
    SliverToBoxAdapter(
      child: CourseRoadmapSection(
        currentCourseName:
            (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn) ?? '',
        recentCompletedCourses: c.recentCompletedCourses,
        nextCourses: c.nextCourses,
        recommendedCourses: c.recommendedCourses,
        similarCourses: c.similarCourses,
        onTapCourse: (s) => _openRecommendedCourse(context, s),
        onEnrollRoadmap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoadmapEnrollmentScreen(
              courseId: int.parse(c.id),
              courseName:
                  (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn) ?? '',
            ),
          ),
        ),
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 32)),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Phone / tablet layout
// ═════════════════════════════════════════════════════════════════════════════

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseDetailProvider>();

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: context.colors.primary,
              onRefresh: p.refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) => _onCourseDetailScroll(context, n),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: StudentCourseHero(
                        course: p.course,
                        reelUrl: p.reelUrl,
                        onBack: () => Navigator.maybePop(context),
                        onRefresh: p.refresh,
                        showRefresh: true,
                        onLike: () => GuestGuard.run(
                          context,
                          p.toggleFavorite,
                          reasonKey: 'guest_reason_favorite',
                        ),
                        onShare: () => shareCourseLink(context, p.course),
                      ),
                    ),
                    ..._contentSlivers(context, p, showChips: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky price + enroll bar (hidden once enrolled).
class _MobileBuyBar extends StatelessWidget {
  const _MobileBuyBar();

  @override
  Widget build(BuildContext context) {
    final course = context.watch<CourseDetailProvider>().course;
    if (course.isEnrolled) return const SizedBox.shrink();
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pending-review / rejected payment notice, right above the button.
          ManualTransferStatusBanner(
            courseId: course.id,
            onRetry: () => _openEnrollment(context, course),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: _PriceBlock(course: course, compact: true),
              ),
              const SizedBox(width: 14),
              const Expanded(flex: 5, child: _EnrollButton()),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Web / desktop layout
// ═════════════════════════════════════════════════════════════════════════════

class _WebLayout extends StatelessWidget {
  const _WebLayout();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseDetailProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _onCourseDetailScroll(context, n),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  // 20 = the horizontal padding the tab content uses,
                  // so the hero edge lines up with the cards below it.
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: StudentCourseHero(
                          rounded: true,
                          showRefresh: true,
                          course: p.course,
                          reelUrl: p.reelUrl,
                          onBack: () => Navigator.maybePop(context),
                          onRefresh: p.refresh,
                          onLike: () => GuestGuard.run(
                            context,
                            p.toggleFavorite,
                            reasonKey: 'guest_reason_favorite',
                          ),
                          onShare: () => shareCourseLink(context, p.course),
                        ),
                      ),
                      if (context.width > 1200) _SideCard(),
                    ],
                  ),
                ),
              ),
              ..._contentSlivers(context, p, showChips: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard();

  @override
  Widget build(BuildContext context) {
    final course = context.watch<CourseDetailProvider>().course;
    final c = context.colors;
    final highlights = _highlights(context, course);

    return Container(
      width: _kSideW,
      padding: EdgeInsets.all(15),
      margin: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (course.isEnrolled)
            Row(
              children: [
                Icon(Icons.verified_rounded, color: c.success, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'you_are_enrolled'.tr,
                    style: c.label.copyWith(
                      color: c.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            _PriceBlock(course: course),
            const SizedBox(height: 16),
            ManualTransferStatusBanner(
              courseId: course.id,
              onRetry: () => _openEnrollment(context, course),
            ),
            const _EnrollButton(),
          ],
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.07)),
            const SizedBox(height: 8),
            for (final h in highlights) _Fact(item: h),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared pieces
// ═════════════════════════════════════════════════════════════════════════════

/// Price (+ discount ribbon / countdown). Used by the buy card and buy bar.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.course, this.compact = false});

  final CourseModel course;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final discount = course.discountActive ?? false;

    final priceRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CoursePriceTag(
          originalPrice: course.price,
          finalPrice: course.finalPrice ?? 0,
          discountActive: discount,
          format: course.currency.format,
          fontSize: compact ? 20 : 28,
          originalFontSize: compact ? 12 : 14,
        ),
        if (discount) ...[
          const SizedBox(width: 10),
          DiscountRibbon(percentage: course.discountPercentage ?? 0),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        compact
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: priceRow,
              )
            : priceRow,
        if (discount && course.discountEndsAt != null) ...[
          const SizedBox(height: 6),
          DiscountCountdown(endsAt: course.discountEndsAt!),
        ],
      ],
    );
  }
}

class _EnrollButton extends StatelessWidget {
  const _EnrollButton();

  @override
  Widget build(BuildContext context) {
    final course = context.watch<CourseDetailProvider>().course;
    if (course.isEnrolled) return const SizedBox.shrink();
    final c = context.colors;

    // The price is already shown right next to the button, so the label
    // only carries the action.
    final label = (course.finalPrice ?? 0) == 0
        ? gt('سجّل مجاناً الآن', 'Enroll for free')
        : gt('انضم الآن', 'Enroll now');

    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openEnrollment(context, course),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                fontFamily: 'bahji',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Rating + support ──────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  const _MetaRow();

  @override
  Widget build(BuildContext context) {
    final course = context.watch<CourseDetailProvider>().course;
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          RatingWidget(
            type: RateType.course,
            sourceId: course.id,
            canEdit: course.isEnrolled,
          ),
          const Spacer(),
          Tooltip(
            message: gt('تواصل مع الدعم', 'Contact support'),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openSupport(context, course),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.headset_mic_rounded, size: 16, color: c.primary),
                    const SizedBox(width: 6),
                    Text(
                      gt('الدعم', 'Support'),
                      style: c.label.copyWith(
                        color: c.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Highlights (certificate · live/recorded) ─────────────────────────────────
// Students / lessons / hours live in the hero only.

typedef _Highlight = ({IconData icon, String label, Color color});

List<_Highlight> _highlights(BuildContext context, CourseModel c) {
  final col = context.colors;
  return [
    if (c.certificates.isNotEmpty)
      (
        icon: Icons.workspace_premium_rounded,
        label: gt('شهادة إتمام معتمدة', 'Certificate of completion'),
        color: col.success,
      ),
    if (c.type == 'live')
      (
        icon: Icons.sensors_rounded,
        label: gt('بث مباشر', 'Live sessions'),
        color: col.danger,
      )
    else
      (
        icon: Icons.play_circle_outline_rounded,
        label: gt('كورس مسجّل', 'Recorded course'),
        color: col.primary,
      ),
  ];
}

class _HighlightChips extends StatelessWidget {
  const _HighlightChips({required this.items});

  final List<_Highlight> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final h in items)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: h.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(h.icon, size: 14, color: h.color),
              const SizedBox(width: 6),
              Text(
                h.label,
                style: context.colors.label.copyWith(
                  color: h.color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.item});

  final _Highlight item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(item.icon, size: 17, color: item.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.label,
            style: context.colors.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab bar — segmented pill
// ═════════════════════════════════════════════════════════════════════════════

class _TabBarWidget extends StatelessWidget {
  const _TabBarWidget();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseDetailProvider>();
    final c = context.colors;

    // The live tab only makes sense for live courses or when a live session
    // is actually running.
    final showLive = p.course.type == 'live' || p.liveSessions.isNotEmpty;
    final tabs = <(CourseDetailTab, String, IconData)>[
      if (showLive) (CourseDetailTab.live, 'live'.tr, Icons.sensors_rounded),
      (CourseDetailTab.lessons, 'sessions'.tr, Icons.play_lesson_rounded),
      (CourseDetailTab.exam, 'exams'.tr, Icons.assignment_rounded),
      (CourseDetailTab.analytics, 'analytics'.tr, Icons.analytics_outlined),
      (CourseDetailTab.about, 'course_details'.tr, Icons.info_outline_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final stacked = box.maxWidth < 520; // icon above label on phones
            return Row(
              children: [
                for (final (tab, label, icon) in tabs)
                  Expanded(
                    child: _TabItem(
                      label: label,
                      icon: icon,
                      active: p.activeTab == tab,
                      stacked: stacked,
                      onTap: () =>
                          context.read<CourseDetailProvider>().setTab(tab),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.stacked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active, stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? Colors.white : c.textLight;

    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: c.label.copyWith(
        color: fg,
        fontSize: stacked ? 11 : 13,
        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
      ),
    );
    final ic = Icon(icon, size: stacked ? 18 : 17, color: fg);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          vertical: stacked ? 8 : 11,
          horizontal: 4,
        ),
        decoration: BoxDecoration(
          gradient: active ? c.primaryGradient : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: c.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [ic, const SizedBox(height: 3), text],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ic,
                  const SizedBox(width: 7),
                  Flexible(child: text),
                ],
              ),
      ),
    );
  }
}
