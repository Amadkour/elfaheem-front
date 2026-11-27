// The teacher's manual attendance (Tea1Class.dc.html?screen=attmanual): the lesson, the group's figures, a search and
// the two bulk choices, one row per student with a presence switch, and the save bar. Behaviour unchanged: the
// provider loads the course's lessons, a switch marks one student, "all present / all absent" saves at once and
// Save sends the changes. Teacher pages use the restrained motion only (M9 presses, M10 figures).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart' show AttChoice;
import 'package:flutter_education_app/features/exams/legacy/student/exam_ui.dart' show ExamError;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/attendance_model.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/teacher_attendance_provider.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_profile_screen.dart';
import 'package:flutter_education_app/design/app_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────

class TeacherAttendanceScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;
  final int? sessionId;

  const TeacherAttendanceScreen({super.key, required this.courseId, required this.courseTitle, this.sessionId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TeacherAttendanceProvider(courseId: courseId)..loadSessions(sessionId),
      child: _TeacherAttendanceView(courseTitle: courseTitle),
    );
  }
}

// ── Inner view ────────────────────────────────────────────────────────────────

class _TeacherAttendanceView extends StatefulWidget {
  final String courseTitle;

  const _TeacherAttendanceView({required this.courseTitle});

  @override
  State<_TeacherAttendanceView> createState() => _TeacherAttendanceViewState();
}

class _TeacherAttendanceViewState extends State<_TeacherAttendanceView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherAttendanceProvider>();
    return BasePage(
      key: const ValueKey('teacher_attendance'),
      useWebCard: true,
      width: AppWidth.wide,
      appBar: AppHeader(title: widget.courseTitle, subtitle: prov.selectedSession?.name ?? 'attendance_record'.tr),
      child: Column(children: [Expanded(child: _buildBody(prov))]),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(TeacherAttendanceProvider prov) {
    if (prov.isLoadingSessions) return const AppListSkeleton();
    if (prov.hasError && prov.sessions.isEmpty) {
      return ExamError(
        message: prov.errorMessage ?? 'something-went-wrong'.tr,
        retryLabel: 'retry'.tr,
        onRetry: () => prov.loadSessions(null),
      );
    }
    final ready = prov.selectedSession != null && !prov.isLoadingStudents && !prov.hasError;
    return Column(children: [
      // The lesson chips scroll with the register once it is shown, so a small screen keeps its room for the rows.
      if (!ready) ParentComponent(featureKey: 'teacher_attendance.session_flag', child: _buildSessionBar(prov)),
      if (prov.selectedSession != null) ...[
        if (prov.isLoadingStudents)
          const Expanded(child: AppListSkeleton())
        else if (prov.hasError)
          Expanded(
            child: ExamError(
              message: prov.errorMessage ?? 'something-went-wrong'.tr,
              retryLabel: 'retry'.tr,
              onRetry: () => prov.selectSession(prov.selectedSession!),
            ),
          )
        else ...[
          Expanded(child: _buildStudents(prov)),
          ParentComponent(featureKey: 'teacher_attendance.save_bar', child: _buildSaveBar(prov)),
        ],
      ] else
        Expanded(child: AppEmpty(icon: Icons.touch_app_rounded, title: 'select_lecture'.tr, message: 'select_session_hint_sub'.tr)),
    ]);
  }

  // ── The lessons ───────────────────────────────────────────────────────────
  Widget _buildSessionBar(TeacherAttendanceProvider prov) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('select_lecture'.tr, style: AppType.label(context)),
        AppSpace.gapXs,
        if (prov.sessions.isEmpty)
          Text('no_sessions_available'.tr, style: AppType.meta(context))
        else
          SizedBox(
            height: AppTouch.min,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: prov.sessions.length,
              separatorBuilder: (_, _) => AppSpace.gapXs,
              itemBuilder: (_, i) {
                final s = prov.sessions[i];
                return AttChoice(label: s.name, selected: prov.selectedSession?.id == s.id, onTap: () => prov.selectSession(s));
              },
            ),
          ),
      ]),
    );
  }

  // ── The group: figures, search, bulk choices, rows ────────────────────────
  Widget _buildStudents(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 1100 ? 3 : (box.maxWidth > 720 ? 2 : 1);
      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: ParentComponent(featureKey: 'teacher_attendance.session_flag', child: _buildSessionBar(prov))),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(attT('t1_cl_manual_title', args: {'lesson': prov.selectedSession?.name ?? ''}), style: AppType.section(context)),
                AppSpace.gapSm,
                ParentComponent(
                  featureKey: 'teacher_attendance.stats',
                  child: Row(children: [
                    Expanded(child: _ManualStat(label: attT('t1_cl_group_students'), value: prov.allStudents.length, tone: c.primary)),
                    AppSpace.gapXs,
                    Expanded(child: _ManualStat(label: attT('t1_cl_present'), value: prov.presentCount, tone: c.success)),
                    AppSpace.gapXs,
                    Expanded(child: _ManualStat(label: attT('t1_cl_absent'), value: prov.absentCount, tone: c.danger)),
                  ]),
                ),
                AppSpace.gapSm,
                ParentComponent(
                  featureKey: 'teacher_attendance.search',
                  child: AppSearchField(
                    controller: _searchCtrl,
                    hint: attT('t1_cl_search'),
                    debounce: Duration.zero,
                    onChanged: prov.setSearch,
                  ),
                ),
                AppSpace.gapXs,
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  AppButton.secondary(
                    size: AppButtonSize.sm,
                    icon: Icons.check_rounded,
                    label: attT('t1_cl_all_present'),
                    onPressed: () async {
                      final ok = await prov.markAll(true);
                      if (!mounted) return;
                      showAppNotice(ok ? 'attendance_saved'.tr : 'save_failed'.tr, error: !ok);
                    },
                  ),
                  AppButton.secondary(
                    size: AppButtonSize.sm,
                    icon: Icons.close_rounded,
                    label: attT('t1_cl_all_absent'),
                    onPressed: () => prov.markAll(false),
                  ),
                ]),
                AppSpace.gapSm,
              ]),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: AppEmpty(icon: Icons.search_off_rounded, title: 'no_search_results'.tr))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: AppTouch.primary * 2,
                  crossAxisSpacing: AppSpace.sm,
                  mainAxisSpacing: AppSpace.sm,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: list.length,
                  (_, i) => _StudentTile(student: list[i], onToggle: (v) => prov.toggleStudent(list[i].id, v)),
                ),
              ),
            ),
        ],
      );
    });
  }

  // ── Save bar ──────────────────────────────────────────────────────────────
  Widget _buildSaveBar(TeacherAttendanceProvider prov) {
    final c = context.colors;
    final n = prov.changes.length;
    return Container(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 480;
          final note = Text(
            n == 0
                ? attT('t1_cl_no_changes')
                : countText(n,
                    ar1: 'عدّلت طالبًا واحدًا',
                    ar2: 'عدّلت طالبين',
                    arFew: 'عدّلت {n} طلاب',
                    arMany: 'عدّلت {n} طالبًا',
                    en1: 'You edited 1 student',
                    en: 'You edited {n} students'),
            style: AppType.meta(context),
          );
          final save = AppButton.primary(
            icon: Icons.check_rounded,
            busy: prov.saving,
            expand: narrow,
            label: attT('t1_cl_save'),
            onPressed: prov.saving || prov.changes.isEmpty
                ? null
                : () async {
                    final ok = await prov.saveAttendance(prov.changes);
                    prov.clearChanges();
                    if (!mounted) return;
                    showAppNotice(ok ? 'attendance_saved'.tr : 'save_failed'.tr, error: !ok);
                  },
          );
          if (narrow) return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [note, AppSpace.gapXs, save]);
          return Row(children: [Expanded(child: note), AppSpace.gapSm, save]);
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

/// One figure of the group: the value on the tone's tint, a short label under it.
class _ManualStat extends StatelessWidget {
  const _ManualStat({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final tint = appTintOn(context, tone);
    final ink = appInkOn(context, tone, tint);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
            color: tint, borderRadius: AppRadius.cardAll, border: Border.all(color: tone.withValues(alpha: 0.35), width: AppBorder.hairline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('$value', style: AppType.figureLarge(context).copyWith(color: ink)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink)),
        ]),
      ),
    );
  }
}

/// Student tile with presence switch: the name opens the student's analytics, the switch marks them.
class _StudentTile extends StatelessWidget {
  final AttendanceStudent student;
  final ValueChanged<bool> onToggle;

  const _StudentTile({required this.student, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final present = student.isPresent;
    final tone = present ? c.success : c.danger;
    final surface = present ? c.cardBg : appTintOn(context, c.danger);
    final meta = student.durationMinutes != null
        ? attT('t1_cl_duration_min', args: {'n': '${student.durationMinutes}'})
        : (present ? '' : attT('t1_cl_no_show'));
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: present ? c.divider : c.danger.withValues(alpha: 0.4), width: AppBorder.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      child: Row(children: [
        AppAvatar(name: student.name, url: student.imageUrl, size: AppTouch.min),
        AppSpace.gapSm,
        Expanded(
          // tap the student → their analytics profile (progress, exams, marks, flags — the same one parents see)
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentAnalyticsProfileScreen.forTeacher(
                  studentId: student.id,
                  studentName: student.name,
                  courseId: context.read<TeacherAttendanceProvider>().courseId,
                ),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Text(student.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
        ),
        AppSpace.gapXs,
        Text(present ? attT('t1_cl_present') : attT('t1_cl_absent'),
            style: AppType.label(context).copyWith(color: appInkOn(context, tone, surface))),
        AppSpace.gapXs,
        AppSwitch(value: present, activeColor: c.success, inactiveColor: c.danger, onChanged: onToggle, semanticLabel: student.name),
      ]),
    );
  }
}
