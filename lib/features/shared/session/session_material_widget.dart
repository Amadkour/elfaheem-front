import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../../utils/widget/video_screen.dart';
import '../../teacher/analysis/attendance/teacher_attendance_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/courses/details/course_detail_provider.dart';
import '../../student/models.dart';
import '../../teacher/analysis/exam/teacher_exam_hub_screen.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/sessions/model/session_material_model.dart';
import '../../teacher/sessions/sessions_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main card widget
// ─────────────────────────────────────────────────────────────────────────────

class SessionMaterialCard extends StatefulWidget {
  final TeacherSessionItem session;
  final TeacherCourse course;
  final bool isTeacher;

  const SessionMaterialCard({
    super.key,
    required this.session,
    required this.course,
    required this.isTeacher,
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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TeacherSessionsProvider>().fetchMaterials(_session.id);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Expand / collapse materials panel ─────────────────────────────────────

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    _expanded ? _animController.forward() : _animController.reverse();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<TeacherSessionsProvider>(),
          child: TeacherAttendanceScreen(
            sessionId: _session.id,
            courseId: _session.courseId,
            courseTitle: widget.course.title,
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
          courseTitle: widget.course.title,
        ),
      ),
    );
  }

  // ── Live session control ───────────────────────────────────────────────────

  Future<void> _toggleLive() async {
    final prov = context.read<TeacherSessionsProvider>();
    if (_session.isLiveActive) {
      await prov.endLive(_session.id);
    } else {
      await prov.startLive(_session.id);
      if (mounted) prov.joinLive(context, _session.id, _session.courseId, 200);
    }
  }

  Future<void> _joinLive() async {
    context
        .read<TeacherSessionsProvider>()
        .joinLive(context, _session.id, _session.courseId, 100);
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showEditSessionDialog() {
    final nameCtrl = TextEditingController(text: _session.name);
    final descCtrl =
    TextEditingController(text: _session.description ?? '');

    showDialog(
      context: context,
      builder: (_) => _RtlDialog(
        title: 'edit_session'.tr,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _Field(ctrl: nameCtrl, label: 'name_label'.tr, context: context),
          const SizedBox(height: 12),
          _Field(ctrl: descCtrl, label: 'description'.tr, context: context),
        ]),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context.read<TeacherSessionsProvider>().updateSession(
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
      builder: (_) => _RtlDialog(
        title: 'delete_session'.tr,
        content: Text(
          // 'delete_confirm_message'.trParams({'name': _session.name}),
          'delete_confirm_message'.tr,
          style: context.colors.body,
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context
              .read<TeacherSessionsProvider>()
              .deleteSession(_session.id);
        },
        confirmLabel: 'delete'.tr,
        confirmColor: context.colors.danger,
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  /// Icon button used for edit / delete actions at the bottom of the card.
  Widget _buildIconAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(icon, size: 28, color: color),
          ),
        ),
      );

  /// The row (or wrap) of action buttons below the session info.
  Widget _buildActionsRow(List<SessionMaterialModel> materials) {
    final isLiveType = _session.type == 'live';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Teacher-only controls
        if (widget.isTeacher) ...[
          _ActionBtn(
            icon: Icons.how_to_reg_rounded,
            label: 'attendance'.tr,
            color: const Color(0xFF4DA6FF),
            onTap: _openAttendance,
            outlined: true,
          ),
          _ActionBtn(
            icon: Icons.quiz_rounded,
            label: 'exams'.tr,
            color: const Color(0xFFFF9F43),
            onTap: _openExams,
            outlined: true,
          ),
        ],

        // Live session button — teacher controls start/end, student joins
        if (isLiveType && widget.isTeacher)
          _ActionBtn(
            icon: CupertinoIcons.video_camera_solid,
            label: _session.isLiveActive
                ? 'end_session'.tr
                : 'meet_now'.tr,
            color: _session.isLiveActive
                ? context.colors.danger
                : context.colors.success,
            onTap: _toggleLive,
            outlined: true,
          ),

        if (_session.isLiveActive && !widget.isTeacher)
          _ActionBtn(
            icon: CupertinoIcons.video_camera_solid,
            label: 'join_live_session'.tr,
            color: context.colors.success,
            onTap: _joinLive,
            outlined: true,
          ),

        // Materials toggle / add shortcut
        if (materials.isNotEmpty)
          _MaterialsToggleButton(
            count: materials.length,
            expanded: _expanded,
            onTap: _toggleExpanded,
          )
        else if (widget.isTeacher)
          _AddMaterialButton(sessionId: _session.id),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherSessionsProvider>();
    final materials = prov.materialsFor(_session.id);
    final uploading = prov.isUploadingMaterial(_session.id);
    final isLiveNow = _session.isLiveActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow: context.colors.cardShadow,
        border: Border(
          right: BorderSide(
            color: isLiveNow
                ? context.colors.danger.withValues(alpha: 0.8)
                : context.colors.primary.withValues(alpha: 0.8),
            width: 4,
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Card body ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + age
                Row(children: [
                  Flexible(
                    child: Text(
                      _session.name,
                      style: context.colors.h3,
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
                ]),

                // Description (optional)
                if (_session.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _session.description!,
                    style: context.colors.navLabelUnselected,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 6),

                // Type pill + duration
                Row(children: [
                  _TypePill(isLive: isLiveNow),
                  const SizedBox(width: 8),
                  Icon(Icons.access_time_rounded,
                      size: 12, color: context.colors.textLight),
                  const SizedBox(width: 3),
                  Text(
                    '${_session.durationMinutes} ${'m'.tr}',
                    style: context.colors.caption,
                  ),
                ]),

                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Action buttons
                _buildActionsRow(materials),

                const Divider(height: 20),

                // Rating + edit/delete
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RatingWidget(
                      type: RateType.session,
                      sourceId: _session.id.toString(),
                      canEdit: !widget.isTeacher,
                    ),
                    if (widget.isTeacher)
                      Row(children: [
                        _buildIconAction(
                          icon: CupertinoIcons.settings_solid,
                          color: context.colors.textMedium,
                          tooltip: 'edit_session'.tr,
                          onTap: _showEditSessionDialog,
                        ),
                        _buildIconAction(
                          icon: Icons.delete,
                          color: context.colors.danger,
                          tooltip: 'delete_session'.tr,
                          onTap: _showDeleteSessionDialog,
                        ),
                      ]),
                  ],
                ),
              ],
            ),
          ),

          // ── Upload progress indicator ──────────────────────────────────────
          if (uploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: LinearProgressIndicator(
                color: context.colors.primary,
                backgroundColor:
                context.colors.primary.withValues(alpha: 0.1),
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
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Materials expandable panel
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialsPanel extends StatelessWidget {
  final TeacherSessionItem session;
  final List<SessionMaterialModel> materials;
  final bool isTeacher;

  const _MaterialsPanel({
    required this.session,
    required this.materials,
    required this.isTeacher,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.only(
          bottomRight: Radius.circular(context.colors.radiusMedium),
          bottomLeft: Radius.circular(context.colors.radiusMedium),
        ),
        border: Border(
          top: BorderSide(
              color: context.colors.textLight.withValues(alpha: 0.1)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Row(children: [
            Icon(Icons.attach_file_rounded,
                size: 14, color: context.colors.primary),
            const SizedBox(width: 6),
            Text(
              'attachments'.tr,
              style: context.colors.caption.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (isTeacher) _AddMaterialButton(sessionId: session.id),
          ]),
          const SizedBox(height: 10),
          _MaterialGrid(
            session: session,
            materials: materials,
            columns: context.isMobile ? 1 : 2,
            isTeacher: isTeacher,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Materials toggle button (shows count + expand arrow)
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
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  color: context.colors.purple),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Material grid
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialGrid extends StatelessWidget {
  final TeacherSessionItem session;
  final List<SessionMaterialModel> materials;
  final int columns;
  final bool isTeacher;

  const _MaterialGrid({
    required this.session,
    required this.materials,
    required this.columns,
    required this.isTeacher,
  });

  static const _typeIcons = {
    SessionMaterialType.image: Icons.image_rounded,
    SessionMaterialType.video: Icons.play_circle_rounded,
    SessionMaterialType.pdf: Icons.picture_as_pdf_rounded,
    SessionMaterialType.document: Icons.description_rounded,
    SessionMaterialType.link: Icons.link_rounded,
  };

  static const _typeColors = {
    SessionMaterialType.image: Color(0xFF4CAF50),
    SessionMaterialType.video: Color(0xFF2196F3),
    SessionMaterialType.pdf: Color(0xFFF44336),
    SessionMaterialType.document: Color(0xFFFF9800),
    SessionMaterialType.link: Color(0xFF9C27B0),
  };

  // Translation keys — resolved at call-site with .tr
  static const _typeLabelKeys = {
    SessionMaterialType.image: 'material_type_image',
    SessionMaterialType.video: 'material_type_video',
    SessionMaterialType.pdf: 'material_type_pdf',
    SessionMaterialType.document: 'material_type_document',
    SessionMaterialType.link: 'material_type_link',
  };

  @override
  Widget build(BuildContext context) {
    if (materials.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(Icons.folder_open_rounded,
              size: 18, color: context.colors.textLight),
          const SizedBox(width: 8),
          Text(
            'no_attachments_yet'.tr,
            style: context.colors.caption
                .copyWith(color: context.colors.textLight),
          ),
        ]),
      );
    }

    if (columns == 1) {
      return Column(
        children: materials
            .map((m) => _buildMaterialTile(context, m))
            .toList(),
      );
    }

    // Multi-column grid
    final rows = <Widget>[];
    for (int i = 0; i < materials.length; i += columns) {
      final end = (i + columns).clamp(0, materials.length);
      final rowItems = materials.sublist(i, end);
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int j = 0; j < rowItems.length; j++) ...[
            if (j > 0) const SizedBox(width: 12),
            Expanded(child: _buildMaterialTile(context, rowItems[j])),
          ],
          if (rowItems.length < columns) ...[
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()),
          ],
        ],
      ));
      if (end < materials.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildMaterialTile(BuildContext context, SessionMaterialModel m) {
    final icon = _typeIcons[m.type] ?? Icons.attach_file_rounded;
    final color = _typeColors[m.type] ?? context.colors.primary;
    final labelKey =
        _typeLabelKeys[m.type] ?? 'material_type_link';

    final isCompleted = !isTeacher &&
        context
            .watch<CourseDetailProvider>()
            .completedMaterialIds
            .contains(m.id);

    return GestureDetector(
      onTap: () => _onTapMaterial(context, m, isCompleted),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCompleted
                ? context.colors.success.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: isCompleted
                  ? context.colors.success.withValues(alpha: 0.08)
                  : color.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          // Icon with optional completion badge
          _MaterialIcon(
              icon: icon, color: color, isCompleted: isCompleted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        style: context.colors.body.copyWith(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      m.createdAt.age,
                      style: context.colors.navLabelUnselected,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(children: [
                  _Pill(labelKey.tr, color),
                  if (m.fileSize != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      m.sizeLabel,
                      style:
                      context.colors.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ]),
                RatingWidget(
                  type: RateType.material,
                  sourceId: m.id.toString(),
                  canEdit: !isTeacher,
                ),
              ],
            ),
          ),
          // Actions
          if (isTeacher)
            Row(children: [
              _iconBtn(
                icon: CupertinoIcons.settings_solid,
                color: context.colors.textMedium,
                onTap: () => _showEditMaterialDialog(context, m),
              ),
              _iconBtn(
                icon: CupertinoIcons.minus_circle_fill,
                color: context.colors.danger,
                onTap: () => _showDeleteMaterialDialog(context, m),
              ),
            ])
          else
            Icon(Icons.open_in_new_rounded,
                size: 16, color: context.colors.textLight),
        ]),
      ),
    );
  }

  Future<void> _onTapMaterial(
      BuildContext context,
      SessionMaterialModel m,
      bool isCompleted,
      ) async {
    final uri = Uri.parse(m.url);

    if (m.type == SessionMaterialType.video) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoScreen(
            uri: uri,
            session: session,
            onComplete: isTeacher
                ? null
                : () async {
              if (context.mounted) {
                await context
                    .read<CourseDetailProvider>()
                    .markMaterialComplete(session.id, m.id);
              }
            },
          ),
        ),
      );
    } else if (m.type == SessionMaterialType.image) {
      await showDialog<void>(
        context: context,
        builder: (_) => _ImageViewerDialog(url: m.url, title: m.name),
      );
      if (!isTeacher && context.mounted) {
        await context
            .read<CourseDetailProvider>()
            .markMaterialComplete(session.id, m.id);
      }
    } else {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!isTeacher && context.mounted) {
          await context
              .read<CourseDetailProvider>()
              .markMaterialComplete(session.id, m.id);
        }
      }
    }
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, size: 23, color: color),
        ),
      );

  void _showEditMaterialDialog(BuildContext context, SessionMaterialModel m) {
    final nameCtrl = TextEditingController(text: m.name);
    final descCtrl = TextEditingController(text: m.description ?? '');
    final urlCtrl = TextEditingController(text: m.url);

    showDialog(
      context: context,
      builder: (_) => _RtlDialog(
        title: 'edit_material'.tr,
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Field(ctrl: nameCtrl, label: 'name_label'.tr, context: context),
            const SizedBox(height: 12),
            _Field(
                ctrl: descCtrl,
                label: 'description_optional'.tr,
                context: context),
            if (m.type == SessionMaterialType.link) ...[
              const SizedBox(height: 12),
              _Field(ctrl: urlCtrl, label: 'url_label'.tr, context: context),
            ],
          ]),
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context.read<TeacherSessionsProvider>().updateMaterial(
            session.id,
            m.id,
            name: nameCtrl.text.trim(),
            description: descCtrl.text.trim().isEmpty
                ? null
                : descCtrl.text.trim(),
            url: m.type == SessionMaterialType.link
                ? urlCtrl.text.trim()
                : null,
          );
        },
        confirmLabel: 'save'.tr,
        confirmColor: context.colors.primary,
      ),
    );
  }

  void _showDeleteMaterialDialog(
      BuildContext context, SessionMaterialModel m) {
    showDialog(
      context: context,
      builder: (_) => _RtlDialog(
        title: 'delete_material'.tr,
        content: Text(
          // 'delete_confirm_message'.trParams({'name': m.name}),
          'delete_confirm_message'.tr,
          style: context.colors.body,
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context
              .read<TeacherSessionsProvider>()
              .deleteMaterial(session.id, m.id);
        },
        confirmLabel: 'delete'.tr,
        confirmColor: context.colors.danger,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Material icon with optional completion badge
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isCompleted;

  const _MaterialIcon({
    required this.icon,
    required this.color,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isCompleted ? context.colors.success : color;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: effectiveColor, size: 20),
        ),
        if (isCompleted)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: context.colors.success,
                shape: BoxShape.circle,
                border:
                Border.all(color: context.colors.cardBg, width: 1.5),
              ),
              child: const Icon(Icons.check_rounded,
                  size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add material button
// ─────────────────────────────────────────────────────────────────────────────

class _AddMaterialButton extends StatelessWidget {
  final int sessionId;

  const _AddMaterialButton({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _AddMaterialSheet(sessionId: sessionId),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: context.colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 14, color: context.colors.primary),
          const SizedBox(width: 4),
          Text(
            'add_material'.tr,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              color: context.colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add material bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddMaterialSheet extends StatefulWidget {
  final int sessionId;

  const _AddMaterialSheet({required this.sessionId});

  @override
  State<_AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<_AddMaterialSheet> {
  int _mode = 0; // 0 = file, 1 = link
  int _fileTypeIdx = 0;
  PlatformFile? _pickedFile;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  // File type options — labels resolved via .tr at build time
  static const _fileTypeOptions = [
    _FileTypeOption(
        labelKey: 'material_type_image',
        icon: Icons.image_rounded,
        fileType: FileType.image,
        color: Color(0xFF4CAF50)),
    _FileTypeOption(
        labelKey: 'material_type_video',
        icon: Icons.play_circle_rounded,
        fileType: FileType.video,
        color: Color(0xFF2196F3)),
    _FileTypeOption(
        labelKey: 'pdf_document',
        icon: Icons.description_rounded,
        fileType: FileType.custom,
        color: Color(0xFFF44336)),
  ];

  static const _documentExtensions = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final opt = _fileTypeOptions[_fileTypeIdx];
    final result = await FilePicker.pickFiles(
      type: opt.fileType,
      allowedExtensions:
      opt.fileType == FileType.custom ? _documentExtensions : null,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _pickedFile = result.files.first);
      if (_nameCtrl.text.isEmpty) {
        _nameCtrl.text =
            _pickedFile!.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('please_enter_name'.tr);
      return;
    }

    final prov = context.read<TeacherSessionsProvider>();
    setState(() => _saving = true);

    try {
      if (_mode == 0) {
        if (_pickedFile == null) {
          _showError('please_pick_file'.tr);
          return;
        }
        final bytes = _pickedFile!.bytes;
        if (bytes == null) {
          _showError('file_load_failed'.tr);
          return;
        }
        await prov.uploadFileMaterial(
          sessionId: widget.sessionId,
          fileName: _pickedFile!.name,
          fileBytes: bytes,
          name: name,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
        );
      } else {
        final url = _urlCtrl.text.trim();
        if (url.isEmpty) {
          _showError('please_enter_url'.tr);
          return;
        }
        await prov.addLinkMaterial(
          sessionId: widget.sessionId,
          name: name,
          url: url,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style:
          const TextStyle(fontFamily: 'bahji', color: Colors.white)),
      backgroundColor: context.colors.danger,
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.colors.textLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            Text('add_material_title'.tr, style: context.colors.h3),
            const SizedBox(height: 16),

            // File / Link toggle
            _ModeToggle(
              selected: _mode,
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 16),

            if (_mode == 0) ...[
              // File type selector
              _FileTypeSelector(
                options: _fileTypeOptions,
                selectedIndex: _fileTypeIdx,
                onChanged: (i) => setState(() => _fileTypeIdx = i),
              ),
              const SizedBox(height: 14),
              // File picker
              _FilePicker(
                pickedFile: _pickedFile,
                onTap: _pickFile,
              ),
            ] else ...[
              _Field(ctrl: _urlCtrl, label: 'url_label'.tr, context: context),
            ],

            const SizedBox(height: 12),
            _Field(ctrl: _nameCtrl, label: 'name_label'.tr, context: context),
            const SizedBox(height: 10),
            _Field(
                ctrl: _descCtrl,
                label: 'description_optional'.tr,
                context: context),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _saving
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  key: const ValueKey('submit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _submit,
                  child: Text(
                    'add_material_btn'.tr,
                    style: const TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File type selector row
// ─────────────────────────────────────────────────────────────────────────────

class _FileTypeSelector extends StatelessWidget {
  final List<_FileTypeOption> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FileTypeSelector({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(options.length, (i) {
        final opt = options[i];
        final selected = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(
                  left: i < options.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? opt.color.withValues(alpha: 0.15)
                    : context.colors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? opt.color
                      : context.colors.textLight.withValues(alpha: 0.2),
                ),
              ),
              child: Column(children: [
                Icon(opt.icon,
                    color: selected
                        ? opt.color
                        : context.colors.textLight,
                    size: 22),
                const SizedBox(height: 4),
                Text(
                  opt.labelKey.tr,
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? opt.color : context.colors.textLight,
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File picker drop zone
// ─────────────────────────────────────────────────────────────────────────────

class _FilePicker extends StatelessWidget {
  final PlatformFile? pickedFile;
  final VoidCallback onTap;

  const _FilePicker({required this.pickedFile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final picked = pickedFile != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: picked
              ? context.colors.success.withValues(alpha: 0.08)
              : context.colors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: picked
                ? context.colors.success.withValues(alpha: 0.4)
                : context.colors.textLight.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(children: [
          Icon(
            picked
                ? Icons.check_circle_rounded
                : Icons.upload_file_rounded,
            size: 28,
            color:
            picked ? context.colors.success : context.colors.textMedium,
          ),
          const SizedBox(height: 6),
          Text(
            picked ? pickedFile!.name : 'tap_to_pick_file'.tr,
            style: context.colors.body.copyWith(
              fontSize: 13,
              color: picked
                  ? context.colors.success
                  : context.colors.textMedium,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable dialog wrapper (RTL, themed)
// ─────────────────────────────────────────────────────────────────────────────

class _RtlDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final Color confirmColor;

  const _RtlDialog({
    required this.title,
    required this.content,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: context.colors.h3),
        content: content,
        actions: [
          TextButton(
            onPressed: onCancel,
            child: Text(
              'cancel'.tr,
              style: TextStyle(
                  fontFamily: 'bahji', color: context.colors.textMedium),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onConfirm,
            child: Text(
              confirmLabel,
              style: const TextStyle(
                fontFamily: 'bahji',
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable action button
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final bool outlined;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.outlined = false,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.filled
        ? widget.color
        : widget.outlined
        ? Colors.transparent
        : widget.color.withValues(alpha: 0.09);

    final border = widget.outlined
        ? Border.all(color: widget.color.withValues(alpha: 0.40), width: 1.2)
        : null;

    final textColor = widget.filled ? Colors.white : widget.color;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: border,
            boxShadow: widget.filled
                ? [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.30),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: textColor),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: context.colors.textLight.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        _segment('file_mode'.tr, 0, Icons.upload_file_rounded, context),
        _segment('link_mode'.tr, 1, Icons.link_rounded, context),
      ]),
    );
  }

  Widget _segment(
      String label, int index, IconData icon, BuildContext context) {
    final sel = selected == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? context.colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child:
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 15,
                color: sel ? Colors.white : context.colors.textMedium),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : context.colors.textMedium,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final bool isLive;

  const _TypePill({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final c = isLive ? context.colors.danger : context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? 'live_badge'.tr : 'recorded_badge'.tr,
        style: context.colors.caption
            .copyWith(color: c, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'bahji',
        fontSize: 9,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final BuildContext context;

  const _Field(
      {required this.ctrl, required this.label, required this.context});

  @override
  Widget build(BuildContext ctx) => TextField(
    controller: ctrl,
    style: ctx.colors.body,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: ctx.colors.caption,
      filled: true,
      fillColor: ctx.colors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: ctx.colors.textLight.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: ctx.colors.textLight.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ctx.colors.primary),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// In-app image viewer (full-screen, pinch-to-zoom)
// Dismissing this dialog signals the student has viewed the image.
// ─────────────────────────────────────────────────────────────────────────────

class _ImageViewerDialog extends StatelessWidget {
  final String url;
  final String title;

  const _ImageViewerDialog({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white)),
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
          // Top bar: close + title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                right: 12,
                bottom: 20,
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for file type options
// ─────────────────────────────────────────────────────────────────────────────

class _FileTypeOption {
  final String labelKey; // translation key, use .tr at build time
  final IconData icon;
  final FileType fileType;
  final Color color;

  const _FileTypeOption({
    required this.labelKey,
    required this.icon,
    required this.fileType,
    required this.color,
  });
}