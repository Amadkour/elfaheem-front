// teacher_sessions_screen.dart
//
// Slim orchestrator. Creates + scopes [TeacherCourseScreenProvider] to this
// route only. All rendering is delegated to focused component files.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../shared/session/progress_banner.dart';
import '../../teacher/courses/course_form_screen.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/sessions/components/session_form_sheet.dart';
import 'components/course_details_section.dart';
import 'components/course_hero.dart';
import 'components/course_stats_row.dart';
import 'components/sessions_section.dart';

class TeacherSessionsScreen extends StatelessWidget {
  final TeacherCourse course;

  const TeacherSessionsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    // Scope the provider to this route. Disposed automatically on pop.
    return ChangeNotifierProvider(
      create: (_) => TeacherCourseScreenProvider(initialCourse: course)
        ..refresh(), // kick off sessions load immediately
      child: const _TeacherSessionsView(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View — reads provider, owns navigation callbacks
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherSessionsView extends StatelessWidget {
  const _TeacherSessionsView();

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _openAddSheet(BuildContext context) {
    final provider = context.read<TeacherCourseScreenProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: SessionFormSheet(courseId: provider.course.id),
      ),
    );
  }

  Future<void> _openEditCourse(BuildContext context) async {
    final provider = context.read<TeacherCourseScreenProvider>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseFormScreen(course: provider.course),
      ),
    );
    // Refresh header + sessions after editing
    await provider.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherCourseScreenProvider>();

    // Watch only the course object for the hero / stats / details sections.
    // Sessions list is watched inside [buildSessionsSlivers] — isolated rebuilds.
    final course = context.select<TeacherCourseScreenProvider, TeacherCourse>(
      (p) => p.course,
    );
    final sessionCount = context.select<TeacherCourseScreenProvider, int>(
      (p) => p.sessionCount,
    );

    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child:RefreshIndicator(
                color: context.colors.primary,
                backgroundColor: context.colors.surface,
                onRefresh: () => provider.refresh(),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // ── Hero ──────────────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: CourseHero(
                        course: course,
                        onBack: () => Navigator.maybePop(context),
                        onEditCourse: () => _openEditCourse(context),
                        onRefresh: () => provider.refresh(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: DetailCard(
                            icon: CupertinoIcons.list_bullet_below_rectangle,
                            title: 'course_details'.tr,
                            color: const Color(0xFF4DA6FF),
                            children: [
                              // ── Rating ────────────────────────────────────────────────
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                child: RatingWidget(
                                  type: RateType.course,
                                  sourceId: course.id.toString(),
                                  canEdit: false,
                                  compact: false,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 14, 20, 4),
                                child: ProgressBanner(
                                  progress: course.progress,
                                  total: course.expectedHours.toInt(),
                                  complete: course.totalHours.toInt(),
                                ),
                              ),
                              CourseStatsRow(
                                course: course,
                                sessionCount: sessionCount,
                              ),

                              CourseDetailsSection(course: course),
                            ]),
                      ),
                    ),
                    // ── Sessions header + list / loading / empty ──────────────

                    ...buildSessionsSlivers(
                      context,
                      course: course,
                      provider: provider,
                      onAdd: () => _openAddSheet(context),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
