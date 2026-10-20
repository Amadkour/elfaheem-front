// lib/features/student/analysis/student_analytics_screen.dart
// The student's analytics hub — the "Analysis" tab of the dashboard.
//
//   • a warm header: hello + one sentence about the strongest / weakest area, and the overall numbers
//     (courses, progress, attendance, exams) from the analytics profile
//   • a gentle nudge when some courses need attention, and sorting (A–Z · needs attention · progress)
//   • one card per course with progress / attendance / exams bars and direct shortcuts:
//       Attendance · Exams · My marks → the course report on that tab;  Review / Read banks → the saved flags
//   • "My full profile" → the analytics profile (every course, the marks teachers published, class averages)
//
// Uses the dashboard's StudentAnalyticsProvider when there is one (so the dashboard's refresh button refreshes what
// you see), otherwise creates its own.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../teacher/data_lab/data_lab_models.dart';
import 'attendance/student_attendance_model.dart';
import 'flags/student_flags_screen.dart';
import 'student_analytics_profile_screen.dart';
import 'student_analytics_provider.dart';
import 'student_analytics_widgets.dart';
import 'student_course_analytics_screen.dart';

class StudentAnalyticsScreen extends StatelessWidget {
  const StudentAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    StudentAnalyticsProvider? ambient;
    try {
      ambient = Provider.of<StudentAnalyticsProvider>(context, listen: false);
    } on ProviderNotFoundException {
      ambient = null;
    }
    if (ambient != null) return const _StudentAnalyticsView();
    return ChangeNotifierProvider(create: (_) => StudentAnalyticsProvider(), child: const _StudentAnalyticsView());
  }
}

// ── Hub view ─────────────────────────────────────────────────────────────────

class _StudentAnalyticsView extends StatefulWidget {
  const _StudentAnalyticsView();

  @override
  State<_StudentAnalyticsView> createState() => _StudentAnalyticsViewState();
}

class _StudentAnalyticsViewState extends State<_StudentAnalyticsView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<StudentAnalyticsProvider>();
      if (!p.loadedOnce && !p.loading) p.loadCourses();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openCourse(EnrolledCourse course, int tab) {
    final prov = context.read<StudentAnalyticsProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentCourseAnalyticsScreen(
          courseId: course.id,
          courseTitle: course.title,
          initialTab: tab,
          initialBlock: prov.blockOf(course.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.watch<StudentAnalyticsProvider>();
    final c = context.colors;

    final List<Widget> body;
    if (prov.loading && !prov.loadedOnce) {
      body = [const SliverFillRemaining(hasScrollBody: false, child: Center(child: AppLoadingIndicator()))];
    } else if (prov.error != null && prov.courses.isEmpty) {
      body = [SliverFillRemaining(hasScrollBody: false, child: AnErrorRetry(message: prov.error!, onRetry: prov.loadCourses))];
    } else if (prov.courses.isEmpty) {
      body = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AnEmpty(icon: Icons.school_outlined, title: 'an_no_courses'.tr, sub: 'an_go_enroll'.tr),
        ),
      ];
    } else {
      final list = prov.filtered;
      body = [
        SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics.search', child: _tools(prov))),
        if (prov.attentionCount > 0 && prov.search.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: _AttentionBanner(
                count: prov.attentionCount,
                active: prov.sort == AnSort.attention,
                onTap: () => prov.setSort(AnSort.attention),
              ),
            ),
          ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AnEmpty(icon: Icons.search_off_rounded, title: 'an_no_results'.tr),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, i) => _CourseCard(
                course: list[i],
                block: prov.blockOf(list[i].id),
                progress: prov.progressOf(list[i]),
                overall: prov.overallOf(list[i]),
                needsAttention: prov.needsAttention(list[i]),
                profileOn: prov.profile != null,
                onOpen: (tab) => _openCourse(list[i], tab),
              ),
            ),
          ),
      ];
    }

    return BasePage(
      key: const ValueKey('analytics'),
      useWebCard: true,
      child: ColoredBox(
        color: c.background,
        child: RefreshIndicator(
          onRefresh: prov.loadCourses,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics.header', child: _Header(prov: prov))),
              ...body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _tools(StudentAnalyticsProvider prov) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
    Widget sortChip(AnSort s, IconData icon, String label) {
      final on = prov.sort == s;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          selected: on,
          showCheckmark: false,
          avatar: Icon(icon, size: 16, color: on ? Colors.white : c.textMedium),
          label: Text(label, style: anText(12, w: FontWeight.w700, c: on ? Colors.white : c.textDark)),
          selectedColor: c.primary,
          backgroundColor: c.cardBg,
          side: BorderSide(color: on ? c.primary : c.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => prov.setSort(s),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          onChanged: prov.setSearch,
          textInputAction: TextInputAction.search,
          style: anText(14, c: c.textDark),
          decoration: InputDecoration(
            hintText: 'an_search_hint'.tr,
            hintStyle: anText(13, c: c.textLight),
            prefixIcon: Icon(Icons.search_rounded, color: c.textMedium, size: 20),
            suffixIcon: prov.search.isNotEmpty
                ? IconButton(
              icon: Icon(Icons.close_rounded, color: c.textMedium, size: 18),
              onPressed: () {
                _searchCtrl.clear();
                prov.setSearch('');
              },
            )
                : null,
            filled: true,
            fillColor: c.cardBg,
            border: b(c.divider),
            enabledBorder: b(c.divider),
            focusedBorder: b(c.primary, 1.6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            sortChip(AnSort.name, Icons.sort_by_alpha_rounded, anTr('an_sort_name', 'A–Z')),
            if (prov.profile != null)
              sortChip(AnSort.attention, Icons.volunteer_activism_rounded, anTr('an_sort_attention', 'Needs attention')),
            sortChip(AnSort.progress, Icons.trending_up_rounded, anTr('an_sort_progress', 'Progress')),
          ]),
        ),
      ]),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.prov});

  final StudentAnalyticsProvider prov;

  @override
  Widget build(BuildContext context) {
    final p = prov.profile;
    final first = (p?.name ?? '').trim().split(RegExp(r'\s+')).first;
    final progress = p?.progress ?? prov.avgProgress;
    return Container(
      decoration: anHeroDecoration(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (p != null) ...[
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                  child: _HeroAvatar(name: p.name, url: p.imageUrl, size: 46),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    first.isEmpty ? 'an_title'.tr : anFmt('an_hello', {'name': first}, 'Hello, {name} 👋'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: anText(21, w: FontWeight.w800, c: Colors.white),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p != null ? anInsightSentence(p.progress, p.attendance, p.examAvg, mine: true) : 'an_subtitle'.tr,
                    style: anText(12.5, c: Colors.white70, h: 1.5),
                  ),
                ]),
              ),
              AnGlassIcon(
                icon: Icons.refresh_rounded,
                tooltip: anTr('an_refresh', 'Refresh'),
                onTap: prov.loadCourses,
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              AnHeroStat(icon: Icons.menu_book_rounded, value: '${prov.courses.length}', label: anTr('an_courses', 'Courses')),
              const SizedBox(width: 8),
              AnHeroStat(icon: Icons.route_rounded, value: anPct(progress), label: anTr('an_course_progress', 'Course progress')),
              if (p != null) ...[
                const SizedBox(width: 8),
                AnHeroStat(icon: Icons.event_available_rounded, value: anPct(p.attendance), label: 'attendance_rate'.tr),
                const SizedBox(width: 8),
                AnHeroStat(icon: Icons.bar_chart_rounded, value: anPct(p.examAvg), label: 'sa_avg_score'.tr),
              ],
            ]),
            if (p != null) ...[
              const SizedBox(height: 14),
              ParentComponent(
                featureKey: 'data_lab.my_profile',
                child: AnGlassPill(
                  icon: Icons.insights_rounded,
                  label: anTr('an_full_profile', 'My full analytics profile'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent()),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Small avatar used on the gradient (initial letter when there is no photo).
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.name, this.url, this.size = 44});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
      child: Text(letter, style: anText(size * 0.42, w: FontWeight.w800, c: c.primary)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.count, required this.active, required this.onTap});

  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.warning.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: active ? null : onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 10, 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: c.warning.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(Icons.volunteer_activism_rounded, color: c.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                anFmt('an_attention', {'n': count}, '{n} of your courses could use a little extra attention.'),
                style: anText(12.5, w: FontWeight.w600, c: c.textDark, h: 1.4),
              ),
            ),
            if (!active) Text(anTr('an_show_first', 'Show first'), style: anText(12, w: FontWeight.w800, c: c.warning)),
          ]),
        ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.block,
    required this.progress,
    required this.overall,
    required this.needsAttention,
    required this.profileOn,
    required this.onOpen,
  });

  final EnrolledCourse course;
  final DlCourseBlock? block;
  final double progress;
  final double? overall;
  final bool needsAttention, profileOn;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = block;
    Widget metric(String label, double? v, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: c.textLight),
        const SizedBox(width: 6),
        SizedBox(width: 92, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(11.5, c: c.textMedium))),
        Expanded(child: AnBar(value: v, height: 6)),
        SizedBox(
          width: 44,
          child: Text(anPct(v), textAlign: TextAlign.end, style: anText(12, w: FontWeight.w800, c: anScoreColor(context, v))),
        ),
      ]),
    );

    return AnCard(
      padding: EdgeInsets.zero,
      borderColor: needsAttention ? c.warning.withValues(alpha: 0.45) : null,
      onTap: () => onOpen(0),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [c.primary.withValues(alpha: 0.07), Colors.transparent],
            ),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: course.imageUrl != null && course.imageUrl!.isNotEmpty
                  ? Image.network(course.imageUrl!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(context))
                  : _placeholder(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(15, w: FontWeight.w800, c: c.textDark)),
                if (course.teacherName != null && course.teacherName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.person_outline_rounded, size: 13, color: c.textLight),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(course.teacherName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(12, c: c.textMedium)),
                    ),
                  ]),
                ],
                if (needsAttention) ...[
                  const SizedBox(height: 5),
                  AnTag(anTr('an_needs_attention', 'Needs attention'), c.warning, icon: Icons.volunteer_activism_rounded),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            if (overall != null)
              Tooltip(
                message: anTr('sa_overall_hint_full', 'An average of your progress, attendance and exam results.'),
                child: AnRing(value: overall, size: 54, stroke: 5),
              )
            else
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: c.textLight),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(children: [
            metric(anTr('an_course_progress', 'Course progress'), progress, Icons.route_rounded),
            if (b != null) ...[
              metric('attendance_rate'.tr, b.attendance, Icons.event_available_rounded),
              metric('sa_avg_score'.tr, b.examAvg, Icons.bar_chart_rounded),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                ParentComponent(
                  featureKey: 'analytics.attendance_chip',
                  child: AnChip(icon: Icons.fact_check_rounded, label: 'an_attendance'.tr, color: c.success, onTap: () => onOpen(1)),
                ),
                ParentComponent(
                  featureKey: 'analytics.exams_chip',
                  child: AnChip(icon: Icons.quiz_rounded, label: 'an_exams'.tr, color: c.primary, onTap: () => onOpen(2)),
                ),
                if (profileOn)
                  ParentComponent(
                    featureKey: 'analytics.marks_chip',
                    child: AnChip(
                      icon: Icons.workspace_premium_rounded,
                      label: anTr('sa_tab_marks', 'My marks'),
                      color: c.purple,
                      badge: b?.extraColumns.length,
                      onTap: () => onOpen(3),
                    ),
                  ),
                ParentComponent(
                  featureKey: 'analytics.review_chip',
                  child: AnChip(
                    icon: Icons.bookmark_rounded,
                    label: 'flag_review_bank'.tr,
                    color: c.warning,
                    badge: b?.reviewFlags,
                    onTap: () => _flags(context, 0),
                  ),
                ),
                ParentComponent(
                  featureKey: 'analytics.read_flags_chip',
                  child: AnChip(
                    icon: Icons.menu_book_rounded,
                    label: 'flag_read_bank'.tr,
                    color: c.danger,
                    badge: b?.readFlags,
                    onTap: () => _flags(context, 1),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.video_library_outlined, size: 13, color: c.textLight),
              const SizedBox(width: 3),
              Text('${course.sessionsCount} ${'an_lectures'.tr}', style: anText(11.5, c: c.textLight)),
            ]),
          ]),
        ),
      ]),
    );
  }

  void _flags(BuildContext context, int tab) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StudentFlagsScreen(courseId: course.id, courseTitle: course.title, initialTab: tab)),
  );

  Widget _placeholder(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
    child: Icon(Icons.menu_book_rounded, color: context.colors.primary, size: 24),
  );
}
