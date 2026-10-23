import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/student/analysis/exam/exam_ui.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import 'attendance_model.dart';
import 'teacher_attendance_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../student/analysis/student_analytics_profile_screen.dart';
import 'package:flutter_education_app/design/app_notice.dart';

// ─────────────────────────────────────────────────────────────────────────────

class TeacherAttendanceScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;
  final int? sessionId;

  const TeacherAttendanceScreen(
      {super.key,
        required this.courseId,
        required this.courseTitle,
        this.sessionId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
      TeacherAttendanceProvider(courseId: courseId)..loadSessions(sessionId),
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
    final isWide = MediaQuery.of(context).size.width > 720;

    return BasePage(
      key: const ValueKey('teacher_attendance'),
      useWebCard: true,
      maxWith: 1100,
      child: Column(
        children: [
          _buildHero(prov),
          Expanded(child: _buildBody(prov, isWide)),
        ],
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _buildHero(TeacherAttendanceProvider prov) {
    final showStats = prov.selectedSession != null &&
        !prov.isLoadingStudents &&
        !prov.hasError;

    return ExamHero(
      child: Column(children: [
        ExamHeroBar(
          title: widget.courseTitle,
          subtitle: prov.selectedSession?.name ?? 'attendance_record'.tr,
        ),
        if (showStats) ...[
          const SizedBox(height: 16),
          ParentComponent(
            featureKey: 'teacher_attendance.stats',
            child: Row(children: [
              HeroStat(
                icon: Icons.people_rounded,
                color: const Color(0xFF80D8FF),
                value: '${prov.allStudents.length}',
                label: 'total_students'.tr,
              ),
              const SizedBox(width: 10),
              HeroStat(
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF69F0AE),
                value: '${prov.presentCount}',
                label: 'present'.tr,
              ),
              const SizedBox(width: 10),
              HeroStat(
                icon: Icons.cancel_rounded,
                color: const Color(0xFFFF8A80),
                value: '${prov.absentCount}',
                label: 'absent'.tr,
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(TeacherAttendanceProvider prov, bool isWide) {
    if (prov.isLoadingSessions) {
      return _buildLoadingState();
    }
    if (prov.hasError && prov.sessions.isEmpty) {
      return ExamError(
        message: prov.errorMessage ?? 'something-went-wrong'.tr,
        retryLabel: 'retry'.tr,
        onRetry: () => prov.loadSessions(null),
      );
    }
    return Column(children: [
      ParentComponent(
        featureKey: 'teacher_attendance.session_flag',
        child: _buildSessionFlagBar(prov),
      ),
      if (prov.selectedSession != null) ...[
        if (prov.isLoadingStudents)
          const Expanded(child: Center(child: AppLoadingIndicator()))
        else if (prov.hasError)
          Expanded(
            child: ExamError(
              message: prov.errorMessage ?? 'something-went-wrong'.tr,
              retryLabel: 'retry'.tr,
              onRetry: () => prov.selectSession(prov.selectedSession!),
            ),
          )
        else ...[
            ParentComponent(
              featureKey: 'teacher_attendance.search',
              child: _buildSearchBar(prov),
            ),
            Expanded(child: isWide ? _buildWideGrid(prov) : _buildList(prov)),
            ParentComponent(
              featureKey: 'teacher_attendance.save_bar',
              child: _buildSaveBar(prov),
            ),
          ],
      ] else
        Expanded(child: _buildSelectSessionHint()),
    ]);
  }

  Widget _buildLoadingState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 52, height: 52, child: AppLoadingIndicator()),
      const SizedBox(height: 16),
      Text('loading_attendance'.tr,
          style: examT(14, c: context.colors.textMedium)),
    ]),
  );

  Widget _buildSelectSessionHint() => ExamEmpty(
    icon: Icons.touch_app_rounded,
    text: '${'select_lecture'.tr}\n${'select_session_hint_sub'.tr}',
  );

  // ── Session flag bar ──────────────────────────────────────────────────────
  Widget _buildSessionFlagBar(TeacherAttendanceProvider prov) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.video_library_rounded, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Text('select_lecture'.tr,
                style: examT(14, w: FontWeight.w800, c: c.textDark)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: prov.sessions.isEmpty
                ? Center(
              child: Text('no_sessions_available'.tr,
                  style: examT(13, c: c.textMedium)),
            )
                : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: prov.sessions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final s = prov.sessions[i];
                return _SessionFlag(
                  name: s.name,
                  index: i,
                  isSelected: prov.selectedSession?.id == s.id,
                  onTap: () => prov.selectSession(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────
  Widget _buildSearchBar(TeacherAttendanceProvider prov) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ExamCard(
        radius: 16,
        child: TextField(
          controller: _searchCtrl,
          textDirection: Helpers.pageDirection,
          style: examT(14, c: c.textDark),
          decoration: InputDecoration(
            hintText: 'search_student'.tr,
            hintStyle: examT(13, c: c.textMedium),
            prefixIcon:
            Icon(Icons.search_rounded, color: c.textMedium, size: 21),
            suffixIcon: prov.search.isNotEmpty
                ? IconButton(
                icon: Icon(Icons.close_rounded,
                    color: c.textMedium, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  prov.setSearch('');
                })
                : null,
            border: InputBorder.none,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: prov.setSearch,
        ),
      ),
    );
  }

  // ── Lists ─────────────────────────────────────────────────────────────────
  Widget _buildList(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    if (list.isEmpty) {
      return ExamEmpty(
          icon: Icons.search_off_rounded, text: 'no_search_results'.tr);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      physics: const BouncingScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _StudentTile(
        student: list[i],
        onToggle: (v) => prov.toggleStudent(list[i].id, v),
      ),
    );
  }

  Widget _buildWideGrid(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    if (list.isEmpty) {
      return ExamEmpty(
          icon: Icons.search_off_rounded, text: 'no_search_results'.tr);
    }
    return LayoutBuilder(
      builder: (_, c) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: c.maxWidth > 1100 ? 3 : 2,
          mainAxisExtent: 82,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _StudentTile(
          student: list[i],
          onToggle: (v) => prov.toggleStudent(list[i].id, v),
        ),
      ),
    );
  }

  // ── Save bar ──────────────────────────────────────────────────────────────
  Widget _buildSaveBar(TeacherAttendanceProvider prov) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            flex: 3,
            child: GradientButton(
              loading: prov.saving,
              label: prov.saving ? 'saving'.tr : 'save_attendance'.tr,
              icon: Icons.save_rounded,
              color: c.success,
              height: 54,
              onTap: prov.saving || prov.changes.isEmpty
                  ? null
                  : () async {
                final ok = await prov.saveAttendance(prov.changes);
                prov.clearChanges();
                if (!context.mounted) return;
                _showSnack(
                  ok ? 'attendance_saved'.tr : 'save_failed'.tr,
                  ok ? c.success : kDanger,
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          _QuickActionBtn(
            label: 'mark_all_present'.tr,
            color: c.success,
            icon: Icons.done_all_rounded,
            onTap: () async {
              final ok = await prov.markAll(true);
              if (!context.mounted) return;
              _showSnack(
                ok ? 'attendance_saved'.tr : 'save_failed'.tr,
                ok ? c.success : kDanger,
              );
            },
          ),
          const SizedBox(width: 8),
          _QuickActionBtn(
            label: 'mark_all_absent'.tr,
            color: kDanger,
            icon: Icons.remove_done_rounded,
            onTap: () => prov.markAll(false),
          ),
        ]),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    showAppNotice(msg);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Flag-style session chip (vertical card with number + name)
class _SessionFlag extends StatelessWidget {
  final String name;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _SessionFlag({
    required this.name,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 96,
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [kDeep, c.primary],
          )
              : null,
          color: isSelected ? null : c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : c.divider.withValues(alpha: .8),
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? c.primary.withValues(alpha: .35)
                  : Colors.black.withValues(alpha: .04),
              blurRadius: isSelected ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: .22)
                    : c.primary.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('${index + 1}',
                    style: examT(12,
                        w: FontWeight.w800,
                        c: isSelected ? Colors.white : c.primary)),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: examT(11,
                    w: FontWeight.w700,
                    c: isSelected ? Colors.white : c.textDark,
                    h: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Student tile with presence switch
class _StudentTile extends StatelessWidget {
  final AttendanceStudent student;
  final ValueChanged<bool> onToggle;

  const _StudentTile({required this.student, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final present = student.isPresent;
    final statusColor = present ? c.success : kDanger;
    final initial = student.name.isEmpty ? '?' : student.name[0];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: .25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: statusColor.withValues(alpha: .12),
            backgroundImage: student.imageUrl != null
                ? NetworkImage(student.imageUrl!)
                : null,
            child: student.imageUrl == null
                ? Text(initial,
                style: examT(16, w: FontWeight.w800, c: statusColor))
                : null,
          ),
          PositionedDirectional(
            bottom: -2,
            end: -2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: c.cardBg, width: 2),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          // tap the student → their analytics profile (progress, exams, marks, flags — the same one parents see)
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
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
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Flexible(
                  child: Text(student.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: examT(14, w: FontWeight.w800, c: c.textDark)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.insights_rounded, size: 14, color: c.primary.withValues(alpha: 0.7)),
              ]),
              const SizedBox(height: 5),
              if (student.durationMinutes != null)
                ExamChip(
                  Icons.timer_outlined,
                  '${'attendance_duration'.tr}: ${student.durationMinutes} ${'minutes'.tr}',
                  c.textMedium,
                )
              else
                ExamBadge(present ? 'present'.tr : 'absent'.tr, statusColor),
            ],
          ),
          ),
        ),
        AppSwitch(
          value: present,
          activeColor: c.success,
          inactiveColor: kDanger,
          onChanged: onToggle,
          semanticLabel: student.name,
        ),
      ]),
    );
  }
}

/// Quick action button (All Present / All Absent)
class _QuickActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 64,
      height: 54,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: examT(9.5, w: FontWeight.w700, c: color),
            ),
          ),
        ],
      ),
    ),
  );
}