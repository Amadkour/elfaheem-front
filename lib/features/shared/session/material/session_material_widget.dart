// shared/session/session_material_widget.dart
//
// SessionMaterialCard — the session row card rendered inside both the teacher
// and student course-detail screens.
//
// After the split this file is a slim orchestrator (~200 lines).
// All heavy sub-trees live in:
//   • components/session_shared_widgets.dart   (RtlDialog, SessionField, pills, ActionBtn)
//   • components/session_progress_section.dart (progress bar + labels)
//   • components/session_material_grid.dart    (material tiles, image viewer)
//   • components/add_material_sheet.dart       (upload / link sheet)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/student/analysis/exam/student_course_exams_widget.dart'
    show SessionExamButton;

import '../../../../config/app_config.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/parent_component.dart';
import '../../../../utils/widget/rating_widget.dart';
import '../../../teacher/sessions/components/guest_link_sheet.dart';
import '../../../student/courses/details/course_detail_provider.dart';
import '../../../student/models.dart';
import '../../../teacher/analysis/attendance/teacher_attendance_screen.dart';
import '../../../teacher/analysis/exam/teacher_exam_hub_screen.dart';
import '../../../teacher/home/teacher_models.dart';
import '../../../teacher/sessions/sessions_provider.dart';
import 'components/add_material_sheet.dart';
import 'components/session_material_grid.dart';
import 'components/session_progress_section.dart';
import 'components/session_shared_widgets.dart';

class SessionMaterialCard extends StatefulWidget {
  final TeacherSessionItem session;
  final TeacherCourse course;
  final bool isTeacher;
  final int sessionNumber;

  /// Position inside the enclosing ReorderableListView (teacher only). When
  /// set, a drag handle is shown in the card header.
  final int? dragIndex;

  /// True when this session should be shown as locked to the current
  /// student — i.e. it's beyond what an unpaid preview or the student's
  /// current progress allows them to open. Ignored for teachers.
  final bool locked;

  const SessionMaterialCard({
    super.key,
    required this.session,
    required this.course,
    required this.isTeacher,
    this.locked = false,
    required this.sessionNumber,
    this.dragIndex,
  });

  @override
  State<SessionMaterialCard> createState() => _SessionMaterialCardState();
}

class _SessionMaterialCardState extends State<SessionMaterialCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animController;
  late final Animation<double> _expandAnim;

  TeacherSessionItem get _session => widget.session;


  /// Locking only ever applies to students — teachers always keep full
  /// access to manage their own sessions.
  bool get _isLocked => widget.locked && !widget.isTeacher;

  void _showLockedMessage() {
    // NOTE: hardcoded Arabic string (mirrors the pattern already used
    // elsewhere in this file, e.g. delete_confirm_message fallback text).
    // Move this to your translations file under a proper key if you'd
    // rather keep all student-facing strings in one place. Kept generic
    // (rather than branching on enrollment) since TeacherCourse doesn't
    // necessarily expose an isEnrolled flag.
    var message =
        'هذه الجلسة مقفلة — أكمل الجلسة الحالية أو اشترك في الكورس لفتحها';
    // Locked because of an unpassed exam → say WHICH exam.
    if (!widget.isTeacher) {
      try {
        final cd = context.read<CourseDetailProvider>();
        final idx = cd.sessions.indexWhere((s) => s.id == _session.id);
        final blocking = idx < 0 ? null : cd.blockingExamFor(idx);
        if (blocking != null) {
          message = '${'session_exam_must_pass'.tr}: ${blocking.name}';
        }
      } catch (_) {}
    }
    Helpers.showMessage(message, isError: true);
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Expand / collapse ──────────────────────────────────────────────────────

  Future<void> _toggleExpanded() async {
    if (_isLocked) {
      _showLockedMessage();
      return;
    }
    setState(() => _expanded = !_expanded);
    _expanded ? _animController.forward() : _animController.reverse();
    // Lazy-load materials on first expand
    context.read<TeacherCourseScreenProvider>().fetchMaterials(_session);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<TeacherCourseScreenProvider>(),
          child: TeacherAttendanceScreen(
            sessionId: _session.id,
            courseId: _session.courseId,
            courseTitle: (AppConfig.lang=='ar'? widget.course.titleAr:widget.course.titleEn)??'',
          ),
        ),
      ),
    );
  }

  void _openExams() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherExamHubScreen(
          courseId: _session.courseId,
          courseTitle: (AppConfig.lang=='ar'? widget.course.titleAr:widget.course.titleEn)??'',
        ),
      ),
    );
  }

  /// Opens the exam hub with the "new exam" sheet already open and this
  /// session pre-selected, so the new exam is attached to it on creation.
  void _openAddExam() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherExamHubScreen(
          courseId: _session.courseId,
          courseTitle: (AppConfig.lang=='ar'? widget.course.titleAr:widget.course.titleEn)??'',
          initialSessionId: _session.id,
          openCreateOnStart: true,
        ),
      ),
    );
  }

  // ── Session exam ───────────────────────────────────────────────────────────

  /// The exam(s) attached to this session (teacher: from the sessions list of
  /// TeacherCourseScreenProvider, student: from CourseDetailProvider).
  SessionExamGate? _examGate(TeacherCourseScreenProvider prov) {
    if (widget.isTeacher) return prov.examGates[_session.id];
    try {
      return context.watch<CourseDetailProvider>().examGates[_session.id];
    } catch (_) {
      return null;
    }
  }

  void _openSessionExam() {
    if (widget.isTeacher) {
      _openExams();
      return;
    }
    context.read<CourseDetailProvider>().setTab(CourseDetailTab.exam);
  }

  // ── Live controls ──────────────────────────────────────────────────────────

  Future<void> _toggleLive() async {
    final prov = context.read<TeacherCourseScreenProvider>();
    if (_session.isLiveActive) {
      await prov.endLive(_session.id);
    } else {
      await prov.startLive(_session.id);
      if (mounted) {
        prov.joinLive(context, _session.id, _session.courseId, 200, false);
      }
    }
  }

  Future<void> _joinLive() async {
    if (_isLocked) {
      _showLockedMessage();
      return;
    }
    context.read<TeacherCourseScreenProvider>().joinLive(
      context,
      _session.id,
      _session.courseId,
      100,
      _session.isLiveActive,
    );
  }

  // ── Teacher session dialogs ────────────────────────────────────────────────

  void _showEditSessionDialog() {
    final nameCtrl = TextEditingController(text: _session.name);
    final descCtrl = TextEditingController(text: _session.description ?? '');

    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'edit_session'.tr,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SessionField(ctrl: nameCtrl, label: 'name_label'.tr),
            const SizedBox(height: 12),
            SessionField(ctrl: descCtrl, label: 'description'.tr),
          ],
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context.read<TeacherCourseScreenProvider>().updateSession(
            _session.id,
            name: nameCtrl.text.trim(),
            description: descCtrl.text.trim().isEmpty
                ? null
                : descCtrl.text.trim(),
          );
        },
        confirmLabel: 'save'.tr,
        confirmColor: context.colors.primary,
      ),
    );
  }

  void _showDeleteSessionDialog() {
    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'delete_session'.tr,
        content: Text(
          'delete_confirm_message'.tr.replaceAll('{name}', _session.name),
          style: context.colors.body,
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          bool result = await context
              .read<TeacherCourseScreenProvider>()
              .deleteSession(_session.id);
          if (result) {
            Helpers.showMessage(
              result
                  ? 'delete_session_successfully'.tr
                  : 'exam_delete_failed_snack'.tr,
              isError: !result,
            );
          }
        },
        confirmLabel: 'delete'.tr,
        confirmColor: context.colors.danger,
      ),
    );
  }

  // ── Actions row ────────────────────────────────────────────────────────────

  Widget _buildActionsRow(TeacherCourseScreenProvider prov, bool hasExam) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.isTeacher) ...[
          SessionActionBtn(
            icon: CupertinoIcons.video_camera_solid,
            loading: prov.startSessionId == _session.id,
            label: _session.isLiveActive ? 'end_session'.tr : 'meet_now'.tr,
            color: _session.isLiveActive
                ? context.colors.danger
                : context.colors.success,
            onTap: prov.startSessionId != -1 ? null : _toggleLive,
          ),
          // Public guest link of this live session (kill-switch: live.guest_link)
          ParentComponent(
            featureKey: kGuestLinkFeatureKey,
            child: SessionActionBtn(
              icon: Icons.link_rounded,
              label: 'guest_link_title'.tr,
              color: context.colors.accent,
              onTap: () => showGuestLinkSheet(context, sessionId: _session.id, sessionName: _session.name),
              outlined: true,
            ),
          ),
          SessionActionBtn(
            icon: Icons.how_to_reg_rounded,
            label: 'attendance'.tr,
            color: context.colors.primary,
            onTap: _openAttendance,
            outlined: true,
          ),
          SessionActionBtn(
            icon: Icons.quiz_rounded,
            label: 'exams'.tr,
            color: context.colors.warning,
            onTap: _openExams,
            outlined: true,
          ),
          SessionActionBtn(
            icon: Icons.add_task_rounded,
            label: 'new_exam'.tr,
            color: context.colors.purple,
            onTap: _openAddExam,
            outlined: true,
          ),

        ],
        if (!widget.isTeacher && !_isLocked)
          SessionExamButton(
            courseId: _session.courseId,
            sessionId: _session.id,
            builder:
                (
                ctx, {
              required icon,
              required label,
              required color,
              required onTap,
            }) => SessionActionBtn(
              icon: icon,
              label: label,
              color: color,
              onTap: onTap,
            ),
            callback: prov.refresh,
          ),
        // if (isLiveType && widget.isTeacher)
        if (_session.isLiveActive)
          SessionActionBtn(
            loading: prov.joinSessionId == _session.id,
            icon: CupertinoIcons.video_camera_solid,
            label: 'join_live_session'.tr,
            color: context.colors.success,
            onTap: prov.joinSessionId != -1 ? null : _joinLive,
          ),
        if (_session.totalMaterial > 0 || hasExam)
          _MaterialsToggleButton(
            count: _session.totalMaterial + (hasExam ? 1 : 0),
            expanded: _expanded,
            onTap: _toggleExpanded,
          )
        else if (widget.isTeacher)
          AddMaterialButton(sessionId: _session.id),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherCourseScreenProvider>();
    final materials = prov.materialsFor(_session.id);
    final uploading = prov.isUploadingMaterial(_session.id);
    final uploadProgress = prov.uploadProgressForSession(_session.id);
    final isLiveNow = _session.isLiveActive;
    final examGate = _examGate(prov);
    final hasExam = examGate != null && !examGate.isEmpty;

    final c = context.colors;
    final isSection = _session.track == 'section';
    final accent = isLiveNow ? c.danger : (isSection ? c.purple : c.primary);
    final card = Container(
      key: ValueKey("session_reorder_list:${widget.dragIndex}"),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge),
        boxShadow: c.cardShadow,
        border: Border.all(color: isLiveNow ? c.danger.withValues(alpha: 0.45) : c.divider.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        // accent strip on the reading-start edge (red while live · purple for sections)
        PositionedDirectional(start: 0, top: 0, bottom: 0, child: Container(width: 4, color: accent)),
        Column(
        children: [
          // ── Main card body ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + age
                Directionality(
                  textDirection: Helpers.textDirOf(_session.name),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        margin: const EdgeInsetsDirectional.only(end: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: AlignmentDirectional.topStart,
                            end: AlignmentDirectional.bottomEnd,
                            colors: [accent, Color.lerp(accent, Colors.black, 0.25)!],
                          ),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Text(
                          (widget.sessionNumber < 10 ? '0' : '') + widget.sessionNumber.toString(),
                          style: c.h4.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          _session.name,
                          style: c.h3.copyWith(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _session.createdAt.age,
                        style: context.colors.navLabelUnselected,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.isTeacher && widget.dragIndex != null) ...[
                        const Spacer(),
                        ReorderableDragStartListener(
                          index: widget.dragIndex!,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.menu,
                              size: 24,
                              color: context.colors.textLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Description
                if (_session.description != null) ...[
                  const SizedBox(height: 2),
                  Directionality(
                    textDirection: Helpers.textDirOf(_session.name),
                    child: Text(
                      _session.description!,
                      style: context.colors.navLabelUnselected,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // Type pill + duration (+ section badge)
                const SizedBox(height: 6),
                Row(
                  children: [
                    SessionTypePill(isLive: isLiveNow),
                    if (isSection) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.science_rounded, size: 12, color: c.purple),
                          const SizedBox(width: 4),
                          Text(AppConfig.lang == 'ar' ? 'سكشن' : 'Section',
                              style: c.caption.copyWith(color: c.purple, fontWeight: FontWeight.w800, fontSize: 11)),
                        ]),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: context.colors.textLight,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${_session.durationMinutes} ${'m'.tr}',
                      style: context.colors.caption,
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                const Divider(height: 1),

                // Student progress section
                SessionProgressSection(
                  totalMaterial: _session.totalMaterial,
                  completeMaterial: _session.completeMaterial,
                  isTeacher: widget.isTeacher,
                  isFull: false,
                ),

                const SizedBox(height: 10),
                _buildActionsRow(prov, hasExam),
                const Divider(height: 20),

                // Rating + teacher edit/delete icons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RatingWidget(
                      type: RateType.session,
                      sourceId: _session.id.toString(),
                      canEdit: !widget.isTeacher,
                      rateSummary: _session.rateSummary,
                    ),
                    if (widget.isTeacher)
                      PopupMenuButton<String>(
                        tooltip: 'edit_session'.tr,
                        icon: Icon(Icons.more_horiz_rounded, color: c.textMedium),
                        onSelected: (v) => v == 'edit' ? _showEditSessionDialog() : _showDeleteSessionDialog(),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'edit', child: Row(children: [
                            Icon(Icons.tune_rounded, size: 18, color: c.textMedium), const SizedBox(width: 10), Text('edit_session'.tr)])),
                          PopupMenuItem(value: 'delete', child: Row(children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: c.danger), const SizedBox(width: 10),
                            Text('delete_session'.tr, style: TextStyle(color: c.danger))])),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Upload indicator ───────────────────────────────────────────────
          // `uploadProgress` is only non-null for the new background (video)
          // uploads — the old bytes-based image/PDF flow has no byte-level
          // progress, so it still shows an indeterminate bar (value: null).
          if (uploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: LinearProgressIndicator(
                value: uploadProgress,
                color: context.colors.primary,
                backgroundColor: context.colors.primary.withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),

          // ── Expandable materials panel ─────────────────────────────────────
          SizeTransition(
            sizeFactor: _expandAnim,
            child: _MaterialsPanel(
              session: _session,
              materials: materials,
              isTeacher: widget.isTeacher,
              examGate: examGate,
              onOpenExam: _openSessionExam,
            ),
          ),
        ],
      ),
      ]),
    );

    if (!_isLocked) return card;

    // Locked: keep the card visible (students can still see what's coming
    // next) but dim it, block every interaction inside it, and show a lock
    // badge. Tapping anywhere on the card surfaces why it's locked.
    return GestureDetector(
      onTap: _showLockedMessage,
      child: Stack(
        children: [
          AbsorbPointer(child: Opacity(opacity: 0.5, child: card)),
          Positioned(
            left: 10,
            top: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(Icons.lock_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Materials expandable panel (panel shell + grid)
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialsPanel extends StatelessWidget {
  final TeacherSessionItem session;
  final List<SessionMaterialModel> materials;
  final bool isTeacher;
  final SessionExamGate? examGate;
  final VoidCallback? onOpenExam;

  const _MaterialsPanel({
    required this.session,
    required this.materials,
    required this.isTeacher,
    this.examGate,
    this.onOpenExam,
  });

  @override
  Widget build(BuildContext context) {
    final prov = context.read<TeacherCourseScreenProvider>();
    final isLoadingMaterials =
        prov.isLoading && !(prov.materialLoaded[session.id] ?? false);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.only(
          bottomRight: Radius.circular(context.colors.radiusMedium),
          bottomLeft: Radius.circular(context.colors.radiusMedium),
        ),
        border: Border(
          top: BorderSide(
            color: context.colors.textLight.withValues(alpha: 0.1),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Row(
            children: [
              Icon(
                Icons.attach_file_rounded,
                size: 14,
                color: context.colors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'attachments'.tr,
                style: context.colors.caption.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (isTeacher) AddMaterialButton(sessionId: session.id),
            ],
          ),
          const SizedBox(height: 10),
          // Grid / list of material tiles
          SessionMaterialGrid(
            isLoading: isLoadingMaterials,
            session: session,
            materials: materials,
            columns: context.width > 800 ? 2 : 1,
            isTeacher: isTeacher,
            examGate: examGate,
            onOpenExam: onOpenExam,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Materials toggle button (count chip + expand arrow)
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialsToggleButton extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _MaterialsToggleButton({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppTheme.purple),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count ${'materials'.tr}',
              style: TextStyle(color: context.colors.purple),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 280),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.colors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}