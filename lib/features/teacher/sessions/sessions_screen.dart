// teacher_sessions_screen.dart
//
// Slim orchestrator. Creates + scopes [TeacherCourseScreenProvider] to this
// route only. All rendering is delegated to focused component files.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../shared/session/progress_banner.dart';
import '../../teacher/courses/course_form_screen.dart';
import '../../teacher/sessions/components/session_form_sheet.dart';
import 'components/course_details_section.dart';
import 'components/course_hero.dart';
import 'components/course_stats_row.dart';
import 'components/sessions_section.dart';

class TeacherSessionsScreen extends StatefulWidget {
  const TeacherSessionsScreen({super.key, this.expandDetails});

  final bool? expandDetails;

  @override
  State<TeacherSessionsScreen> createState() => _TeacherSessionsScreenState();
}

class _TeacherSessionsScreenState extends State<TeacherSessionsScreen> {
  @override
  void initState() {
    Future.microtask(() {
      if (mounted) {
        context.read<TeacherCourseScreenProvider>().refresh();
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // Scope the provider to this route. Disposed automatically on pop.
    return ChangeNotifierProvider.value(
      value: context.read<TeacherCourseScreenProvider>(),
      // kick off sessions load immediately
      child: _TeacherSessionsView(expandDetails: widget.expandDetails),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View — reads provider, owns navigation callbacks
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherSessionsView extends StatelessWidget {
  const _TeacherSessionsView({this.expandDetails});

  final bool? expandDetails;

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
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: RefreshIndicator(
          color: context.colors.primary,
          backgroundColor: context.colors.primary,
          onRefresh: () => provider.refresh(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Hero ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: CourseHero(
                  course: provider.course,
                  onBack: () => Navigator.maybePop(context),
                  onEditCourse: () => _openEditCourse(context),
                  onRefresh: () => provider.refresh(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: DetailCard(
                    key: Key('${Random().nextDouble()}'),
                    expanded:provider.openCourseDetails,
                    icon: CupertinoIcons.list_bullet_below_rectangle,
                    title: 'course_details'.tr,
                    color: const Color(0xFF4DA6FF),
                    children: [
                      // ── Rating ────────────────────────────────────────────────
                      RatingWidget(
                        type: RateType.course,
                        sourceId: provider.course.id.toString(),
                        canEdit: false,
                        compact: false,
                      ),
                      ProgressBanner(
                        progress: provider.course.progress,
                        total: provider.course.expectedHours.toInt(),
                        complete: provider.course.totalHours.toInt(),
                      ),
                      CourseStatsRow(
                        course: provider.course,
                        sessionCount: provider.sessionCount,
                      ),

                      CourseDetailsSection(course: provider.course),
                    ],
                  ),
                ),
              ),

              // ── Sessions header + list / loading / empty ──────────────
              ...buildSessionsSlivers(
                context,
                course: provider.course,
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
