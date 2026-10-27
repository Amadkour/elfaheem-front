// shared/session/components/session_material_grid.dart
//
// Renders the grid/list of SessionMaterialModel items inside the expandable
// panel. Handles tap → video player / image viewer / external URL, plus
// teacher edit / delete dialogs.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../core/api_client.dart';
import '../../../../../design/app_kit.dart' show showAppSheet, AppSheetHeader, AppBanner, appText;
import '../../../../../utils/helpers.dart';
import '../../../../../utils/widget/rating_widget.dart';
import '../../../../student/courses/details/course_detail_provider.dart';
import '../../../../student/models.dart';
import '../../../../teacher/sessions/sessions_provider.dart';
import '../../video/video_player_screen.dart';
import '../session_material_model.dart';
import 'material_file_style.dart';
import 'session_exam_tile.dart';
import 'session_shared_widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/core/offline/offline_video_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Material grid
// ─────────────────────────────────────────────────────────────────────────────

class SessionMaterialGrid extends StatelessWidget {
  final TeacherSessionItem session;
  final bool isLoading;
  final List<SessionMaterialModel> materials;
  final int columns;
  final bool isTeacher;

  /// The exam attached to this session (null / empty → none). Rendered as the
  /// last, non-reorderable entry.
  final SessionExamGate? examGate;
  final VoidCallback? onOpenExam;

  const SessionMaterialGrid({
    super.key,
    required this.session,
    required this.materials,
    required this.columns,
    required this.isTeacher,
    required this.isLoading,
    this.examGate,
    this.onOpenExam,
  });

  bool get _hasExam => examGate != null && !examGate!.isEmpty;

  // ── Icons: one distinct icon per type ──────────────────────────────────────
  static const _typeIcons = {
    SessionMaterialType.image: Icons.image_rounded,
    SessionMaterialType.video: Icons.smart_display_rounded,
    // filled play screen – live/uploaded video
    SessionMaterialType.pdf: Icons.picture_as_pdf_rounded,
    SessionMaterialType.document: Icons.article_rounded,
    // document page
    SessionMaterialType.link: Icons.open_in_browser_rounded,
    // web link
    SessionMaterialType.recorded: Icons.video_library_rounded,
    // recorded archive – distinct from live video
    // SessionMaterialType.recording uses a spinning widget, not a static icon
  };

  // ── Colors per type ────────────────────────────────────────────────────────
  static const _typeColors = {
    SessionMaterialType.image: Color(0xFF4CAF50), // green
    SessionMaterialType.video: Color(0xFF2196F3), // blue
    SessionMaterialType.pdf: Color(0xFFF44336), // red
    SessionMaterialType.document: Color(0xFFFF9800), // orange
    SessionMaterialType.link: Color(0xFF9C27B0), // purple
    SessionMaterialType.recorded: Color(0xFF5C6BC0), // indigo – archive feel
    SessionMaterialType.recording: Color(0xFFE53935), // vivid red – live/active
  };

  // ── Label keys ─────────────────────────────────────────────────────────────
  static const _typeLabelKeys = {
    SessionMaterialType.image: 'material_type_image',
    SessionMaterialType.video: 'material_type_video',
    SessionMaterialType.pdf: 'material_type_pdf',
    SessionMaterialType.document: 'material_type_document',
    SessionMaterialType.link: 'material_type_link',
    SessionMaterialType.recorded: 'material_type_recorded',
    SessionMaterialType.recording: 'material_type_recording',
  };

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: AppLoadingIndicator());
    }
    if (!_hasExam) return _buildMaterialsList(context);

    // The session exam is ALWAYS the last entry. It lives OUTSIDE the
    // ReorderableListView on purpose: it can't be dragged, and nothing can be
    // dropped after it.
    final enrolled =
        isTeacher || context.read<CourseDetailProvider>().course.isEnrolled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (materials.isNotEmpty) _buildMaterialsList(context),
        SessionExamTile(
          gate: examGate!,
          isTeacher: isTeacher,
          enrolled: enrolled,
          onOpen: onOpenExam,
        ),
      ],
    );
  }

  Widget _buildMaterialsList(BuildContext context) {
    if (materials.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 18,
              color: context.colors.textLight,
            ),
            const SizedBox(width: 8),
            Text(
              'no_attachments_yet'.tr,
              style: context.colors.caption.copyWith(
                color: context.colors.textLight,
              ),
            ),
          ],
        ),
      );
    }

    // Teachers: one drag-and-drop list (long-press-free: grab the handle).
    if (isTeacher) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: materials.length,
        onReorder: (oldIndex, newIndex) => context
            .read<TeacherCourseScreenProvider>()
            .reorderMaterials(session.id, oldIndex, newIndex),
        itemBuilder: (ctx, i) => KeyedSubtree(
          key: ValueKey('material_${materials[i].id}'),
          child: _buildTile(ctx, materials[i], i + 1, dragIndex: i),
        ),
      );
    }

    if (columns == 1) {
      return Column(
        children: materials
            .asMap()
            .entries
            .map((entry) => _buildTile(context, entry.value, entry.key + 1))
            .toList(),
      );
    }

    // Multi-column layout
    final rows = <Widget>[];
    for (int i = 0; i < materials.length; i += columns) {
      final end = (i + columns).clamp(0, materials.length);
      final rowItems = materials.sublist(i, end);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int j = 0; j < rowItems.length; j++) ...[
              if (j > 0) const SizedBox(width: 12),
              Expanded(child: _buildTile(context, rowItems[j], i + j + 1)),
            ],
            if (rowItems.length < columns) ...[
              const SizedBox(width: 12),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
      if (end < session.totalMaterial) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  // ── Tile ───────────────────────────────────────────────────────────────────

  Widget _buildTile(
    BuildContext context,
    SessionMaterialModel m,
    int index, {
    int? dragIndex,
  }) {
    final isRecording = m.type == SessionMaterialType.recording;
    final isRecorded = m.type == SessionMaterialType.recorded;

    // Word / Excel / CSV / PowerPoint / Python get their own badge + colour.
    final fileStyle = m.type == SessionMaterialType.document
        ? MaterialFileStyle.forExtension(m.fileExtension)
        : null;
    final icon = _typeIcons[m.type] ?? Icons.attach_file_rounded;
    final color =
        fileStyle?.color ?? _typeColors[m.type] ?? context.colors.primary;
    final labelKey = _typeLabelKeys[m.type] ?? 'material_type_link';
    final isCompleted = m.completed;

    // ── Derived display values ─────────────────────────────────────────────
    // For recording / recorded, surface the creation date as part of the title.
    final String displayName = isRecording
        ? 'recording_in_progress'
              .tr // hardcoded "Recording in progress…"
        : (isRecorded ? '${m.name}  •  ${_formatDate(m.createdAt)}' : m.name);

    return Directionality(
      textDirection: Helpers.textDirOf(displayName),
      child: GestureDetector(
        onTap: isRecording
            ? null
            : () => _onTapMaterial(context, m, isCompleted),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCompleted
                  ? const Color(0xFF00C48C).withValues(alpha: 0.35)
                  : color.withValues(alpha: 0.18),
              width: isCompleted ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isCompleted
                    ? const Color(0xFF00C48C).withValues(alpha: 0.10)
                    : color.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                // ── Top accent strip ─────────────────────────────────────────
                if (isCompleted)
                  Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF00C48C), Color(0xFF00E5A0)],
                      ),
                    ),
                  )
                else if (isRecording)
                  // Pulsing red strip for active recording
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.4)],
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Leading icon ────────────────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(10),
                          border: BoxBorder.all(color: context.colors.primary),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: EdgeInsets.fromLTRB(5, 5, 5, 0),
                              alignment: Alignment.bottomCenter,

                              child: Text(
                                (index < 10 ? '0' : '') + index.toString(),
                                textAlign: TextAlign.center,

                                style: context.colors.h4.copyWith(
                                  color: context.colors.primary,
                                ),
                              ),
                            ),
                            isRecording
                                ? _RecordingSpinnerIcon(color: color)
                                : MaterialIconWidget(
                                    icon: icon,
                                    color: color,
                                    isCompleted: isCompleted,
                                    badge: fileStyle?.badge,
                                    badgeTextColor: fileStyle?.badgeTextColor,
                                  ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: context.colors.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      fontStyle: isRecording
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                      color: isCompleted
                                          ? context.colors.textMedium
                                          : isRecording
                                          ? color
                                          : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isCompleted && !isTeacher) ...[
                                      const MaterialCompletedBadge(),
                                      const SizedBox(width: 5),
                                    ],
                                    // For recording, show a live dot instead of age
                                    if (isRecording)
                                      _LiveDotBadge(color: color)
                                    else if (isRecorded)
                                      // Show formatted date for recorded items
                                      Text(
                                        _formatDate(m.createdAt),
                                        style: context.colors.caption.copyWith(
                                          fontSize: 10,
                                          color: color.withValues(alpha: 0.8),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    else
                                      Text(
                                        m.createdAt.age,
                                        style:
                                            context.colors.navLabelUnselected,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                SessionPill(
                                  fileStyle?.label ?? labelKey.tr,
                                  color,
                                ),
                                if (m.sizeLabel.isNotEmpty && !isRecording) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    m.sizeLabel, // KB under 1 MB, else MB
                                    style: context.colors.caption.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                                if (m.durationLabel.isNotEmpty &&
                                    !isRecording) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 11,
                                    color: context.colors.textLight,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    m.durationLabel, // h:mm:ss
                                    style: context.colors.caption.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (!isRecording)
                              RatingWidget(
                                type: RateType.material,
                                sourceId: m.id.toString(),
                                canEdit: !isTeacher,
                                rateSummary: m.rateSummary,
                              ),
                          ],
                        ),
                      ),
                      // ── Trailing: teacher actions / student open indicator ──
                      if (isTeacher)
                        Row(
                          children: [
                            if (dragIndex != null)
                              ReorderableDragStartListener(
                                index: dragIndex,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Icon(
                                    Icons.menu,
                                    size: 23,
                                    color: context.colors.textLight,
                                  ),
                                ),
                              ),
                            if (!isRecording) ...[
                              if (m.type == SessionMaterialType.video ||
                                  m.type == SessionMaterialType.recorded)
                                _CaptionsAction(
                                  key: ValueKey('captions_action.${m.id}'),
                                  material: m,
                                  onUpload: () => _pickAndUploadCaptions(context, m),
                                  onManage: (generate) =>
                                      _showCaptionsDialog(context, m, onGenerate: generate),
                                ),
                              _iconBtn(
                                icon: CupertinoIcons.settings_solid,
                                color: context.colors.textMedium,
                                onTap: () => _showEditDialog(context, m),
                              ),
                            ],
                            _iconBtn(
                              icon: CupertinoIcons.minus_circle_fill,
                              color: context.colors.danger,
                              onTap: () => _showDeleteDialog(context, m),
                            ),
                          ],
                        )
                      else if (!isRecording)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (m.type == SessionMaterialType.video ||
                                m.type == SessionMaterialType.recorded)
                              _OfflineBadge(
                                sessionId: m.sessionId,
                                materialId: m.id,
                              ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(
                                    scale: anim,
                                    child: FadeTransition(
                                      opacity: anim,
                                      child: child,
                                    ),
                                  ),
                              child: isCompleted
                                  ? const Padding(
                                      key: ValueKey('check'),
                                      padding: EdgeInsets.only(right: 5),
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        size: 15,
                                        color: Color(0xFF00C48C),
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('empty'),
                                    ),
                            ),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                              color: context.colors.textLight,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Date helper ────────────────────────────────────────────────────────────

  /// Returns a short formatted date string, e.g. "14 Jan 2025".
  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ── Tap handler ────────────────────────────────────────────────────────────

  Future<void> _onTapMaterial(
    BuildContext context,
    SessionMaterialModel m,
    bool isCompleted,
  ) async {
    // Belt-and-braces: the card that hosts this grid already blocks
    // expansion for a locked session, but guard the actual open action too
    // in case this grid is ever reached another way.
    if (!isTeacher &&
        !context.read<CourseDetailProvider>().isSessionUnlockedById(
          session.id,
        )) {
      Helpers.showMessage(
        'هذه الجلسة مقفلة — أكمل الجلسة الحالية أو اشترك في الكورس لفتحها',
        isError: true,
      );
      return;
    }
    // Protected videos arrive WITHOUT a url (m.requiresPlay): the player fetches
    // a device-bound stream link via POST .../play, which also counts the view.
    if (!m.requiresPlay && (m.urlLow == null || m.urlLow!.isEmpty)) {
      Helpers.showMessage('video_not_available'.tr);
      return;
    }
    final uri = Uri.parse(m.urlLow ?? m.urlHigh ?? '');

    if ([
      SessionMaterialType.video,
      SessionMaterialType.recorded,
    ].contains(m.type)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            autoPlay: true,
            startFullScreen: false,
            material: m,
            playlist: materials,
          ),
        ),
      );
    } else if (m.type == SessionMaterialType.image) {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            MaterialImageViewerDialog(url: m.urlLow!, title: m.name),
      );
      if (!isTeacher && context.mounted) {
        await context.read<CourseDetailProvider>().markMaterialComplete(
          session.id,
          m.id,
        );
      }
    } else {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!isTeacher && context.mounted) {
          await context.read<CourseDetailProvider>().markMaterialComplete(
            session.id,
            m.id,
          );
        }
      }
    }
  }

  // ── Icon button helper ─────────────────────────────────────────────────────

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(icon, size: 23, color: color),
    ),
  );

  // ── Teacher dialogs ────────────────────────────────────────────────────────

  void _showEditDialog(BuildContext context, SessionMaterialModel m) {
    final nameCtrl = TextEditingController(text: m.name);
    final descCtrl = TextEditingController(text: m.description ?? '');
    final urlCtrl = TextEditingController(text: m.urlLow ?? '');
    final orderCtrl = TextEditingController(text: m.order.toString());

    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'edit_material'.tr,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SessionField(ctrl: nameCtrl, label: 'name_label'.tr),
              const SizedBox(height: 12),
              SessionField(ctrl: descCtrl, label: 'description_optional'.tr),
              const SizedBox(height: 12),
              SessionField(
                ctrl: orderCtrl,
                label: 'order_label'.tr, // add key: "الترتيب" / "Order"
                keyboardType: TextInputType.number,
              ),
              if (m.type == SessionMaterialType.link) ...[
                const SizedBox(height: 12),
                SessionField(ctrl: urlCtrl, label: 'url_label'.tr),
              ],
            ],
          ),
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context.read<TeacherCourseScreenProvider>().updateMaterial(
            session.id,
            m.id,
            name: nameCtrl.text.trim().isEmpty ? m.name : nameCtrl.text.trim(),
            order: int.tryParse(orderCtrl.text.trim()) ?? m.order,
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

  // ── Captions (.vtt) ───────────────────────────────────────────────────────

  /// Pick a WebVTT file and attach it to a video / recording material.
  Future<void> _pickAndUploadCaptions(
      BuildContext context, SessionMaterialModel m) async {
    final prov = context.read<TeacherCourseScreenProvider>();
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['vtt'],
    );
    if (f == null) return;
    if (!f.name.toLowerCase().endsWith('.vtt')) {
      Helpers.showMessage('captions_pick_vtt'.tr, isError: true);
      return;
    }
    Uint8List? bytes;
    if (kIsWeb) {
      try {
        bytes = await f.readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (bytes == null) {
        Helpers.showMessage('file_load_failed'.tr, isError: true);
        return;
      }
    }
    final ok = await prov.uploadCaptions(
      session.id,
      m.id,
      fileName: f.name,
      filePath: kIsWeb ? null : f.path,
      fileBytes: bytes,
    );
    Helpers.showMessage(
      ok ? 'captions_uploaded'.tr : (prov.errorMessage ?? 'generic_error'.tr),
      isError: !ok,
    );
  }

  /// Captions already attached: replace them (file or automatic) or remove them.
  void _showCaptionsDialog(BuildContext context, SessionMaterialModel m, {VoidCallback? onGenerate}) {
    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'captions_title'.tr,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('captions_attached'.tr, style: context.colors.body),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _pickAndUploadCaptions(context, m);
              },
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text('upload_captions'.tr),
            ),
            if (onGenerate != null)
              TextButton.icon(
                key: const ValueKey('captions.generate'),
                onPressed: () {
                  Navigator.pop(context);
                  onGenerate();
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text('captions_generate'.tr),
              ),
          ],
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          final prov = context.read<TeacherCourseScreenProvider>();
          final ok = await prov.removeCaptions(session.id, m.id);
          Helpers.showMessage(
            ok
                ? 'captions_removed'.tr
                : (prov.errorMessage ?? 'generic_error'.tr),
            isError: !ok,
          );
        },
        confirmLabel: 'remove_captions'.tr,
        confirmColor: context.colors.danger,
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, SessionMaterialModel m) {
    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'delete_material'.tr,
        content: Text('delete_confirm_message'.tr, style: context.colors.body),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context.read<TeacherCourseScreenProvider>().deleteMaterial(
            session.id,
            m.id,
          );
        },
        confirmLabel: 'delete'.tr,
        confirmColor: context.colors.danger,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spinning "recording in progress" icon (replaces static icon for recording type)
// ─────────────────────────────────────────────────────────────────────────────

class _RecordingSpinnerIcon extends StatefulWidget {
  final Color color;

  const _RecordingSpinnerIcon({required this.color});

  @override
  State<_RecordingSpinnerIcon> createState() => _RecordingSpinnerIconState();
}

class _RecordingSpinnerIconState extends State<_RecordingSpinnerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Spinning ring
        RotationTransition(turns: _ctrl, child: AppLoadingIndicator()),
        // Static red dot in center
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.45),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Blinking "LIVE" dot badge shown in the trailing area for recording tiles
// ─────────────────────────────────────────────────────────────────────────────

class _LiveDotBadge extends StatefulWidget {
  final Color color;

  const _LiveDotBadge({required this.color});

  @override
  State<_LiveDotBadge> createState() => _LiveDotBadgeState();
}

class _LiveDotBadgeState extends State<_LiveDotBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: widget.color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Material icon with completion state
// ─────────────────────────────────────────────────────────────────────────────

class MaterialIconWidget extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isCompleted;

  /// Letters drawn instead of the icon (file-type badge, e.g. "W", "PY").
  final String? badge;
  final Color? badgeTextColor;

  const MaterialIconWidget({
    super.key,
    required this.icon,
    required this.color,
    required this.isCompleted,
    this.badge,
    this.badgeTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isCompleted ? const Color(0xFF00C48C) : color;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: isCompleted
                ? const LinearGradient(
                    colors: [Color(0xFF00C48C), Color(0xFF00E5A0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isCompleted
                ? null
                : (badge != null
                      ? effectiveColor
                      : effectiveColor.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isCompleted
                ? [
                    BoxShadow(
                      color: const Color(0xFF00C48C).withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: (badge != null && !isCompleted)
              ? Center(
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: badgeTextColor ?? Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: badge!.length > 2 ? 11 : 18,
                      letterSpacing: 0.3,
                    ),
                  ),
                )
              : Icon(
                  isCompleted ? Icons.check_rounded : icon,
                  color: isCompleted ? Colors.white : effectiveColor,
                  size: 20,
                ),
        ),
        if (isCompleted)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00C48C).withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline completed badge (shown next to material name for students)
// ─────────────────────────────────────────────────────────────────────────────

class MaterialCompletedBadge extends StatelessWidget {
  const MaterialCompletedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C48C), Color(0xFF00E5A0)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C48C).withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 9, color: Colors.white),
          SizedBox(width: 3),
          Text(
            '✓',
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen image viewer dialog
// ─────────────────────────────────────────────────────────────────────────────

class MaterialImageViewerDialog extends StatelessWidget {
  final String url;
  final String title;

  const MaterialImageViewerDialog({
    super.key,
    required this.url,
    required this.title,
  });

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
                    : const Center(child: AppLoadingIndicator()),
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
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
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small indicator on a material tile: downloading ring / "available offline".
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge({required this.sessionId, required this.materialId});

  final int sessionId;
  final int materialId;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final svc = OfflineVideoService.instance;
    final id = svc.idOf(sessionId, materialId);
    final primary = context.colors.primary;

    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: svc.downloading,
      builder: (_, progress, _) {
        final p = progress[id];
        if (p != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: p > 0 ? p : null,
                color: primary,
              ),
            ),
          );
        }
        return ValueListenableBuilder<Set<String>>(
          valueListenable: svc.downloadedIds,
          builder: (_, ids, _) => ids.contains(id)
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.offline_pin_rounded,
                    size: 16,
                    color: primary,
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Captions action (teacher): upload a .vtt, or let the server generate them
// ─────────────────────────────────────────────────────────────────────────────
//
// One CC button per video / recording. Its look follows the material's captions:
//   • none              → outlined CC; tap → sheet: "Upload .vtt" · "Generate automatically"
//   • queued/processing → small spinner (POST …/captions/auto answered 202); the list endpoint is polled every
//                         8 s (up to ~5 min) until the job ends, because the provider only re-fetches a session's
//                         materials when their count changes
//   • failed            → CC crossed out in red; tap → same sheet with a "Try again" note
//   • ready + url       → filled CC; tap → replace / generate / remove dialog
// A 501 `auto_captions_unavailable` means this server has no speech-to-text: a toast says so.

class _CaptionsAction extends StatefulWidget {
  const _CaptionsAction({super.key, required this.material, required this.onUpload, required this.onManage});

  final SessionMaterialModel material;
  final VoidCallback onUpload;

  /// Opens the "captions attached" dialog; receives the generate callback to offer there.
  final ValueChanged<VoidCallback> onManage;

  @override
  State<_CaptionsAction> createState() => _CaptionsActionState();
}

class _CaptionsActionState extends State<_CaptionsAction> {
  static const _pollEvery = Duration(seconds: 8);
  static const _maxPolls = 40; // ≈ 5 minutes

  String? _status;
  String? _url;
  bool _busy = false;
  Timer? _poll;
  int _polls = 0;

  SessionMaterialModel get _m => widget.material;
  bool get _pending => _status == 'queued' || _status == 'processing';
  bool get _failed => _status == 'failed' && _url == null;

  @override
  void initState() {
    super.initState();
    _sync();
    if (_pending) _startPolling();
  }

  @override
  void didUpdateWidget(covariant _CaptionsAction old) {
    super.didUpdateWidget(old);
    if (old.material.captionsUrl != _m.captionsUrl || old.material.captionsStatus != _m.captionsStatus) {
      _sync();
      if (_pending) {
        _startPolling();
      } else {
        _stopPolling();
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _sync() {
    _status = _m.captionsStatus;
    _url = _m.captionsUrl;
  }

  // ── Polling ───────────────────────────────────────────────────────────────
  void _startPolling() {
    _poll?.cancel();
    _polls = 0;
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _refresh() async {
    if (++_polls > _maxPolls) {
      _stopPolling();
      return;
    }
    try {
      final r = await ApiClient().get('/api/v1/sessions/${_m.sessionId}/materials');
      if (!mounted || r is! List) return;
      for (final e in r) {
        if (e is Map && e['id'] == _m.id) {
          final fresh = SessionMaterialModel.fromJson(Map<String, dynamic>.from(e));
          setState(() {
            _status = fresh.captionsStatus;
            _url = fresh.captionsUrl;
          });
          if (!_pending) _stopPolling();
          return;
        }
      }
    } catch (_) {
      // transient: the next tick tries again
    }
  }

  // ── Generate ──────────────────────────────────────────────────────────────
  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await ApiClient().post('/api/v1/sessions/${_m.sessionId}/materials/${_m.id}/captions/auto');
      if (!mounted) return;
      final status = (r is Map ? r['status']?.toString() : null) ?? 'queued';
      setState(() => _status = status);
      if (_pending) _startPolling();
      Helpers.showMessage('captions_auto_queued'.tr);
    } catch (e) {
      final ex = ApiException.from(e);
      final unavailable = ex.statusCode == 501 || ex.code == 'auto_captions_unavailable';
      Helpers.showMessage(unavailable ? 'captions_auto_unavailable'.tr : ex.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Sheet (no captions yet / failed) ──────────────────────────────────────
  void _showOptions() {
    final c = context.colors;
    showAppSheet<void>(
      context,
      (sheetCtx) => Column(mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader('captions_title'.tr),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_failed)
              AppBanner(
                key: const ValueKey('captions.failed_note'),
                icon: Icons.error_outline_rounded,
                text: 'captions_status_failed'.tr,
                color: c.danger,
              )
            else
              Text('captions_none'.tr, style: appText(12.5, c: c.textMedium, h: 1.5)),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('captions.upload'),
              leading: Icon(Icons.upload_file_rounded, color: c.primary),
              title: Text('upload_captions'.tr, style: appText(14, w: FontWeight.w700, c: c.textDark)),
              subtitle: Text('captions_pick_vtt'.tr, style: appText(12, c: c.textLight)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                widget.onUpload();
              },
            ),
            ListTile(
              key: const ValueKey('captions.generate'),
              leading: Icon(Icons.auto_awesome_rounded, color: c.primary),
              title: Text((_failed ? 'captions_retry' : 'captions_generate').tr,
                  style: appText(14, w: FontWeight.w700, c: c.textDark)),
              subtitle: Text('captions_auto_queued'.tr, style: appText(12, c: c.textLight)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _generate();
              },
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_busy || _pending) {
      return Tooltip(
        message: (_status == 'processing' ? 'captions_status_processing' : 'captions_status_queued').tr,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            key: const ValueKey('captions.pending'),
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
          ),
        ),
      );
    }
    final IconData icon;
    final Color color;
    final VoidCallback onTap;
    if (_url != null) {
      icon = Icons.closed_caption_rounded;
      color = c.primary;
      onTap = () => widget.onManage(_generate);
    } else if (_failed) {
      icon = Icons.closed_caption_disabled_rounded;
      color = c.danger;
      onTap = _showOptions;
    } else {
      icon = Icons.closed_caption_off_outlined;
      color = c.textMedium;
      onTap = _showOptions;
    }
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(icon, size: 23, color: color),
      ),
    );
  }
}
