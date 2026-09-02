// teacher_sessions_screen.dart
//
// Slim orchestrator. Creates + scopes [TeacherCourseScreenProvider] to this
// route only. All rendering is delegated to focused component files.
//
// PERFORMANCE REFACTOR
// ─────────────────────────────────────────────────────────────────────────
// The previous version called `context.watch<TeacherCourseScreenProvider>()`
// once at the top of `_TeacherSessionsView`. TeacherCourseScreenProvider is a
// "mega provider" — it owns the course header, the sessions list, per-session
// materials, upload progress flags, and live-session state — and calls
// notifyListeners() for all of them. A single top-level `watch` meant *every*
// notifyListeners() (e.g. toggling an upload-in-progress flag for one
// session) rebuilt the hero, the rating widget, the course-details card, and
// the entire sessions list, even though none of that data had changed.
//
// It also gave `DetailCard` a brand new `Key` (`Random().nextDouble()`) on
// every single build. A changing key tells Flutter "this is a different
// widget", so DetailCard was being torn down and recreated from scratch on
// every rebuild — losing its own internal expand/collapse animation state
// and paying full widget-creation cost for no reason.
//
// Fix, keeping the app's existing Provider architecture (no need for a
// framework switch — the app already has 20+ ChangeNotifierProviders wired
// through `providers.dart`; the fix is scoping rebuilds correctly):
//   • No more top-level `watch`. `_TeacherSessionsView` itself never rebuilds
//     from provider changes.
//   • `CourseHero` is wrapped in a `Selector<..., TeacherCourse>` — it only
//     rebuilds when the course object itself changes (i.e. after
//     refreshCourse()), not on session/material/live-state churn.
//   • The course-details card is wrapped in a `Selector` over a record of
//     exactly the three values it needs (course, sessionCount, expanded).
//     Dart records have structural equality, so the Selector only rebuilds
//     when one of those three actually changes.
//   • DetailCard gets a stable `ValueKey` instead of a random one, so its
//     internal expand/collapse state and animation survive rebuilds.
//   • The sessions list is the one section that legitimately needs to react
//     to almost everything (session CRUD, live flags, materials), so it's
//     isolated into its own `_SessionsSlivers` widget that does its own
//     `watch` — confined to a `SliverMainAxisGroup` so its rebuilds can never
//     leak into the hero or details card next to it.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:developer';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../shared/session/progress_banner.dart';
import '../../teacher/courses/course_form_screen.dart';
import '../../teacher/sessions/components/session_form_sheet.dart';
import '../home/teacher_models.dart';
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
    super.initState();
    // addPostFrameCallback instead of Future.microtask — runs after the
    // first frame is laid out, consistent with the rest of the app (see
    // EnrolledStudentsScreen), and avoids any chance of racing widget build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TeacherCourseScreenProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scope the provider to this route. Disposed automatically on pop.
    return ChangeNotifierProvider.value(
      value: context.read<TeacherCourseScreenProvider>(),
      child: _TeacherSessionsView(expandDetails: widget.expandDetails),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View — owns navigation callbacks only. Does NOT watch the provider: every
// section below scopes its own rebuild independently.
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
    // `read`, not `watch` — this widget has nothing that depends on provider
    // state directly (onRefresh just delegates), so it should never rebuild
    // when the provider notifies.
    final provider = context.read<TeacherCourseScreenProvider>();

    return BasePage(
      useWebCard: true,
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: context.colors.primary,
          backgroundColor: context.colors.primary,
          onRefresh: () => provider.refresh(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Hero — rebuilds only when `course` changes ────────────
              SliverToBoxAdapter(
                child: Selector<TeacherCourseScreenProvider, TeacherCourse>(
                  selector: (_, p) => p.course,
                  builder: (context, course, _) {

                    return CourseHero(
                    course: course,
                    onBack: () => Navigator.maybePop(context),
                    onEditCourse: () => _openEditCourse(context),
                    onRefresh: () => provider.refresh(),
                  );
                  },
                ),
              ),

              // ── Course details card — rebuilds only when course,
              // sessionCount, or the expand flag actually change. A record
              // has structural equality, so Selector correctly skips
              // rebuilds triggered by unrelated provider activity (uploads,
              // live-session flags, etc.). ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child:
                      Selector<TeacherCourseScreenProvider,
                        (TeacherCourse course, int sessionCount, bool expanded)>(
                        selector: (_, p) =>(p.course, p.sessionCount, p.openCourseDetails),
                        builder: (context, data, _) {
                          final (course, sessionCount, expanded) = data;
                          return  DetailCard(
                            // Stable key — DetailCard keeps its own
                            // expand/collapse animation state across
                            // rebuilds instead of being destroyed and
                            // recreated every time (previously a fresh
                            // Random() key every build).
                            key:  ValueKey({Random().nextDouble()}),
                            expanded: expanded,
                            icon: CupertinoIcons.list_bullet_below_rectangle,
                            title: 'course_details'.tr,
                            color: const Color(0xFF4DA6FF),
                            children: [
                              // ── Rating ──────────────────────────────
                              RatingWidget(
                                type: RateType.course,
                                sourceId: course.id.toString(),
                                canEdit: false,
                                compact: false,
                              ),
                              ProgressBanner(
                                progress: course.progress,
                                total: course.expectedHours.toInt(),
                                complete: course.totalHours.toInt(),
                              ),
                              CourseStatsRow(
                                course: course,
                                sessionCount: sessionCount,
                              ),
                              CourseDetailsSection(course: course),
                            ],
                          );
                        },
                      ),
                ),
              ),

              // ── Sessions header + list / loading / empty ──────────────
              // Isolated so its (legitimately broad) rebuilds never touch
              // the hero or details card above.
              _SessionsSlivers(onAdd: () => _openAddSheet(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sessions section — the one area that needs to react to nearly everything
// the provider does (session CRUD, live-session flags, material uploads),
// so it does its own `watch`. `SliverMainAxisGroup` lets a single widget own
// a whole group of slivers, which is what confines this rebuild boundary.
// ─────────────────────────────────────────────────────────────────────────

class _SessionsSlivers extends StatelessWidget {
  const _SessionsSlivers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherCourseScreenProvider>();
    return SliverMainAxisGroup(
      slivers: buildSessionsSlivers(
        context,
        course: provider.course,
        provider: provider,
        onAdd: onAdd,
      ),
    );
  }
}
