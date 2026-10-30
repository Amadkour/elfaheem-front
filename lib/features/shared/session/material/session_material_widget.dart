// shared/session/session_material_widget.dart
//
// SessionMaterialCard — one session of the course page's timeline, for the teacher and the student alike. It is
// drawn by the shared, plain-value [CourseSessionTile] (shared/course/course_space/course_sessions.dart); this
// widget adds what needs the providers: the role's actions (student: join live · start the session exam · the
// exam gate footer; teacher: the ⋮ menu with go live · guest link · attendance · exams · material · edit ·
// delete, and the drag handle), the materials panel the row opens, and the session rating inside that panel.
// The caller wraps the rows in CourseSessionsTimeline / CourseSessionsSurface and passes each row's
// [state] and [rail] (courseStudentStates / courseTeacherStates + courseSessionRail).
//
// Heavy sub-trees live in:
//   • components/session_shared_widgets.dart   (RtlDialog, SessionField)
//   • components/session_material_grid.dart    (material tiles, image viewer)
//   • components/add_material_sheet.dart       (upload / link sheet)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/student/analysis/exam/student_course_exams_widget.dart'
    show SessionExamButton;
import 'package:flutter_education_app/features/student/analysis/exam/student_exam_provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/rating_widget.dart';
import '../../course/course_space/course_sessions.dart';
import '../../../teacher/sessions/components/guest_link_sheet.dart';
import '../../../student/courses/details/course_detail_provider.dart';
import '../../../student/models.dart';
import '../../../teacher/analysis/attendance/teacher_attendance_screen.dart';
import '../../../teacher/analysis/exam/teacher_exam_hub_screen.dart';
import '../../../teacher/home/teacher_models.dart';
import '../../../teacher/sessions/sessions_provider.dart';
import 'components/add_material_sheet.dart';
import 'components/session_material_grid.dart';
import 'components/session_shared_widgets.dart';

class SessionMaterialCard extends StatefulWidget {
  final TeacherSessionItem session;
  final TeacherCourse course;
  final bool isTeacher;
  final int sessionNumber;

  /// Position inside the enclosing ReorderableListView (teacher only): a drag handle on wide screens, a long press
  /// on the row on phones.
  final int? dragIndex;

  /// True when this session should be shown as locked to the current
  /// student — i.e. it's beyond what an unpaid preview or the student's
  /// current progress allows them to open. Ignored for teachers.
  final bool locked;

  /// Where the session stands in the timeline (null → live / locked / open from the session itself).
  final CourseSessionState? state;

  /// The timeline line through this row (none by default).
  final CourseSessionRail rail;

  /// The course is a live course (the student's SessionModel → TeacherSessionItem copy drops `type`).
  final bool? liveType;

  /// Under the row's actions (the student's exam-gate notice).
  final Widget? footer;

  const SessionMaterialCard({
    super.key,
    required this.session,
    required this.course,
    required this.isTeacher,
    this.locked = false,
    required this.sessionNumber,
    this.dragIndex,
    this.state,
    this.rail = (top: null, bottom: null),
    this.liveType,
    this.footer,
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
    _loadStudentExams();
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

  // ── Row parts ──────────────────────────────────────────────────────────────

  /// Students: the course's exams (several rows mount together; only the first one fetches).
  void _loadStudentExams() {
    if (widget.isTeacher) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final prov = context.read<StudentExamProvider>();
        final cid = '${_session.courseId}';
        if (!prov.courseExamsLoadedFor(cid) && !prov.loadingCourseExamsFor(cid)) prov.loadCourseExams(cid);
      } catch (_) {}
    });
  }

  /// The student's exam attached to this session (drives the "Start exam" action under the row).
  bool _hasStudentExam() {
    if (widget.isTeacher || _isLocked) return false;
    try {
      return context.watch<StudentExamProvider>().examForSession('${_session.courseId}', _session.id) != null;
    } catch (_) {
      return false;
    }
  }

  /// Live join / end and the session exam, under the row's meta line; null when there is nothing to show.
  Widget? _below(TeacherCourseScreenProvider prov) {
    final c = context.colors;
    final live = _session.isLiveActive;
    final items = <Widget>[
      if (live && !_isLocked)
        CourseSessionAction(
          icon: Icons.videocam_rounded,
          label: widget.isTeacher ? _tt('دخول الغرفة', 'Enter room') : 'join_live_session'.tr,
          tone: c.danger,
          filled: true,
          loading: prov.joinSessionId == _session.id,
          onTap: prov.joinSessionId != -1 ? null : _joinLive,
        ),
      if (live && widget.isTeacher)
        CourseSessionAction(
          icon: Icons.stop_circle_outlined,
          label: 'end_session'.tr,
          tone: c.danger,
          loading: prov.startSessionId == _session.id,
          onTap: prov.startSessionId != -1 ? null : _toggleLive,
        ),
      if (_hasStudentExam())
        SessionExamButton(
          courseId: _session.courseId,
          sessionId: _session.id,
          builder: (ctx, {required icon, required label, required color, required onTap}) =>
              CourseSessionAction(icon: icon, label: label, tone: color, onTap: onTap),
          callback: prov.refresh,
        ),
    ];
    final uploading = prov.isUploadingMaterial(_session.id);
    if (items.isEmpty && widget.footer == null && !uploading) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: items),
        if (widget.footer != null) ...[if (items.isNotEmpty) const SizedBox(height: 8), widget.footer!],
        if (uploading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: prov.uploadProgressForSession(_session.id),
            minHeight: 3,
            color: c.primary,
            backgroundColor: c.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ],
    );
  }

  /// The teacher's ⋮: live · guest link · attendance · exams · material · edit · delete.
  Widget _teacherMenu(TeacherCourseScreenProvider prov) {
    final c = context.colors;
    final live = _session.isLiveActive;
    final guest = !AppConfig.disableList.contains(kGuestLinkFeatureKey);
    PopupMenuItem<String> item(String v, IconData icon, String label, {Color? tone}) => PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: tone ?? c.textMedium),
          const SizedBox(width: 12),
          Flexible(child: Text(label, style: TextStyle(color: tone ?? c.textDark))),
        ],
      ),
    );
    return PopupMenuButton<String>(
      tooltip: _tt('خيارات الجلسة', 'Session options'),
      icon: Icon(Icons.more_vert_rounded, color: c.textLight, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'live':
            if (prov.startSessionId == -1) _toggleLive();
          case 'guest':
            showGuestLinkSheet(context, sessionId: _session.id, sessionName: _session.name);
          case 'attendance':
            _openAttendance();
          case 'exams':
            _openExams();
          case 'new_exam':
            _openAddExam();
          case 'material':
            showAddMaterialSheet(context, sessionId: _session.id);
          case 'edit':
            _showEditSessionDialog();
          case 'delete':
            _showDeleteSessionDialog();
        }
      },
      itemBuilder: (_) => [
        item(
          'live',
          live ? Icons.stop_circle_outlined : Icons.videocam_rounded,
          live ? 'end_session'.tr : 'meet_now'.tr,
          tone: live ? c.danger : c.success,
        ),
        if (guest) item('guest', Icons.link_rounded, 'guest_link_title'.tr),
        item('attendance', Icons.how_to_reg_rounded, 'attendance'.tr),
        item('exams', Icons.quiz_outlined, 'exams'.tr),
        item('new_exam', Icons.add_task_rounded, 'new_exam'.tr),
        item('material', Icons.attach_file_rounded, 'add_material'.tr),
        const PopupMenuDivider(),
        item('edit', Icons.tune_rounded, 'edit_session'.tr),
        item('delete', Icons.delete_outline_rounded, 'delete_session'.tr, tone: c.danger),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherCourseScreenProvider>();
    final materials = prov.materialsFor(_session.id);
    final examGate = _examGate(prov);
    final hasExam = examGate != null && !examGate.isEmpty;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final isSection = _session.track == 'section';

    final state = widget.state ??
        (_session.isLiveActive
            ? CourseSessionState.live
            : _isLocked
            ? CourseSessionState.locked
            : CourseSessionState.open);
    final kind = isSection
        ? CourseSessionKind.section
        : (widget.liveType ?? _session.isLive) || _session.isLiveActive
        ? CourseSessionKind.live
        : CourseSessionKind.recorded;
    // Teachers can always open a row (its panel holds "Add material"); students only when there is something in it.
    final expandable = !_isLocked && (widget.isTeacher || _session.totalMaterial > 0 || hasExam);

    final data = CourseSessionView(
      number: widget.sessionNumber,
      title: _session.name,
      subtitle: _session.description,
      kind: kind,
      state: state,
      when: sessionUtc(_session.scheduledAt),
      durationMinutes: _session.durationMinutes,
      materials: _session.totalMaterial,
      materialsDone: _session.completeMaterial,
      showProgress: !widget.isTeacher,
      hint: widget.isTeacher && _session.totalMaterial == 0 && !hasExam ? _tt('لا مواد بعد', 'No materials yet') : null,
    );

    final drag = widget.isTeacher && widget.dragIndex != null;
    final Widget? trailing = widget.isTeacher
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _teacherMenu(prov),
              if (drag && wide)
                ReorderableDragStartListener(
                  index: widget.dragIndex!,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: SizedBox(
                      width: 32,
                      height: 44,
                      child: Icon(Icons.drag_indicator_rounded, size: 20, color: context.colors.textLight),
                    ),
                  ),
                ),
            ],
          )
        : expandable
        ? CourseSessionChevron(open: _expanded)
        : null;

    Widget tile = CourseSessionTile(
      data: data,
      rail: widget.rail,
      wide: wide,
      onTap: _isLocked ? _showLockedMessage : (expandable ? _toggleExpanded : null),
      trailing: trailing,
      below: _isLocked ? null : _below(prov),
      panel: expandable
          ? SizeTransition(
              sizeFactor: _expandAnim,
              child: CourseSessionPanel(
                title: 'attachments'.tr,
                action: widget.isTeacher ? AddMaterialButton(sessionId: _session.id) : null,
                footer: RatingWidget(
                  type: RateType.session,
                  sourceId: _session.id.toString(),
                  canEdit: !widget.isTeacher,
                  rateSummary: _session.rateSummary,
                ),
                child: SessionMaterialGrid(
                  isLoading: prov.isLoading && !(prov.materialLoaded[_session.id] ?? false),
                  session: _session,
                  materials: materials,
                  columns: context.width > 800 ? 2 : 1,
                  isTeacher: widget.isTeacher,
                  examGate: examGate,
                  onOpenExam: _openSessionExam,
                ),
              ),
            )
          : null,
    );
    // phones: a long press anywhere on the row picks it up to reorder
    if (drag && !wide) tile = ReorderableDelayedDragStartListener(index: widget.dragIndex!, child: tile);
    return KeyedSubtree(key: ValueKey('session_row:${_session.id}'), child: tile);
  }
}

String _tt(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// A session's `scheduled_at` as parsed by the models (`toLocalSaTime`: the instant shifted by +3 h and still
/// flagged UTC) → the real UTC instant AppTime expects.
DateTime? sessionUtc(DateTime? d) {
  if (d == null) return null;
  return d.isUtc ? d.subtract(const Duration(hours: 3)) : d.toUtc();
}
