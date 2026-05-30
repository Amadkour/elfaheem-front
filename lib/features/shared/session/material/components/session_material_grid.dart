// shared/session/components/session_material_grid.dart
//
// Renders the grid/list of SessionMaterialModel items inside the expandable
// panel. Handles tap → video player / image viewer / external URL, plus
// teacher edit / delete dialogs.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/app_theme.dart';
import '../../../../../utils/helpers.dart';
import '../../../../../utils/widget/rating_widget.dart';
import '../../../../student/courses/details/course_detail_provider.dart';
import '../../../../student/models.dart';
import '../../../../teacher/sessions/sessions_provider.dart';
import '../../screen_vedio_recorder.dart';
import '../../session_material_model.dart';
import 'session_shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Material grid
// ─────────────────────────────────────────────────────────────────────────────

class SessionMaterialGrid extends StatelessWidget {
  final TeacherSessionItem session;
  final bool isLoading;
  final List<SessionMaterialModel> materials;
  final int columns;
  final bool isTeacher;

  const SessionMaterialGrid({
    super.key,
    required this.session,
    required this.materials,
    required this.columns,
    required this.isTeacher,
    required this.isLoading,
  });

  static const _typeIcons = {
    SessionMaterialType.image: Icons.image_rounded,
    SessionMaterialType.video: Icons.play_circle_rounded,
    SessionMaterialType.pdf: Icons.picture_as_pdf_rounded,
    SessionMaterialType.document: Icons.description_rounded,
    SessionMaterialType.link: Icons.link_rounded,
    SessionMaterialType.recorded: Icons.play_circle_rounded,
    SessionMaterialType.recording: CupertinoIcons.timelapse,
  };

  static const _typeColors = {
    SessionMaterialType.image: Color(0xFF4CAF50),
    SessionMaterialType.video: Color(0xFF2196F3),
    SessionMaterialType.pdf: Color(0xFFF44336),
    SessionMaterialType.document: Color(0xFFFF9800),
    SessionMaterialType.link: Color(0xFF9C27B0),
  };

  static const _typeLabelKeys = {
    SessionMaterialType.image: 'material_type_image',
    SessionMaterialType.video: 'material_type_video',
    SessionMaterialType.pdf: 'material_type_pdf',
    SessionMaterialType.document: 'material_type_document',
    SessionMaterialType.link: 'material_type_link',
  };

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
        children: materials.map((m) => _buildTile(context, m)).toList(),
      );
    }

    // Multi-column layout
    final rows = <Widget>[];
    for (int i = 0; i < materials.length; i += columns) {
      final end = (i + columns).clamp(0, materials.length);
      final rowItems = materials.sublist(i, end);
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int j = 0; j < rowItems.length; j++) ...[
            if (j > 0) const SizedBox(width: 12),
            Expanded(child: _buildTile(context, rowItems[j])),
          ],
          if (rowItems.length < columns) ...[
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()),
          ],
        ],
      ));
      if (end < session.totalMaterial) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildTile(BuildContext context, SessionMaterialModel m) {
    final icon = _typeIcons[m.type] ?? Icons.attach_file_rounded;
    final color = _typeColors[m.type] ?? context.colors.primary;
    final labelKey = _typeLabelKeys[m.type] ?? 'material_type_link';
    final isCompleted = m.completed;

    return GestureDetector(
      onTap: () => _onTapMaterial(context, m, isCompleted),
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
              // Completion shimmer strip at top
              if (isCompleted)
                Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00C48C), Color(0xFF00E5A0)],
                    ),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MaterialIconWidget(
                        icon: icon, color: color, isCompleted: isCompleted),
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
                                  m.name,
                                  style: context.colors.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: isCompleted
                                        ? context.colors.textMedium
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
                                  Text(
                                    m.createdAt.age,
                                    style: context.colors.navLabelUnselected,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(children: [
                            SessionPill(labelKey.tr, color),
                            if (m.fileSize != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                m.sizeLabel,
                                style: context.colors.caption
                                    .copyWith(fontSize: 10),
                              ),
                            ],
                          ]),
                          RatingWidget(
                            type: RateType.material,
                            sourceId: m.id.toString(),
                            canEdit: !isTeacher,
                            rateSummary: m.rateSummary,
                          ),
                        ],
                      ),
                    ),
                    // Teacher actions vs student open indicator
                    if (isTeacher)
                      Row(children: [
                        _iconBtn(
                          icon: CupertinoIcons.settings_solid,
                          color: context.colors.textMedium,
                          onTap: () => _showEditDialog(context, m),
                        ),
                        _iconBtn(
                          icon: CupertinoIcons.minus_circle_fill,
                          color: context.colors.danger,
                          onTap: () => _showDeleteDialog(context, m),
                        ),
                      ])
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: FadeTransition(
                                  opacity: anim, child: child),
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
                                    key: ValueKey('empty')),
                          ),
                          Icon(Icons.open_in_new_rounded,
                              size: 16, color: context.colors.textLight),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tap handler ────────────────────────────────────────────────────────────

  Future<void> _onTapMaterial(
    BuildContext context,
    SessionMaterialModel m,
    bool isCompleted,
  ) async {
    if (m.urlLow == null) {
      Helpers.showMessage('video_not_available'.tr);
      return;
    }
    final uri = Uri.parse(m.urlLow!);

    if ([SessionMaterialType.video,SessionMaterialType.recorded ].contains(m.type ) ) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            autoPlay: true,
            startFullScreen: false,
            material: m,
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

  // ── Icon button helper ─────────────────────────────────────────────────────

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

  // ── Teacher dialogs ────────────────────────────────────────────────────────

  void _showEditDialog(BuildContext context, SessionMaterialModel m) {
    final nameCtrl = TextEditingController(text: m.name);
    final descCtrl = TextEditingController(text: m.description ?? '');
    final urlCtrl = TextEditingController(text: m.urlLow ?? '');

    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'edit_material'.tr,
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SessionField(ctrl: nameCtrl, label: 'name_label'.tr),
            const SizedBox(height: 12),
            SessionField(ctrl: descCtrl, label: 'description_optional'.tr),
            if (m.type == SessionMaterialType.link) ...[
              const SizedBox(height: 12),
              SessionField(ctrl: urlCtrl, label: 'url_label'.tr),
            ],
          ]),
        ),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context.read<TeacherCourseScreenProvider>().updateMaterial(
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

  void _showDeleteDialog(BuildContext context, SessionMaterialModel m) {
    showDialog(
      context: context,
      builder: (_) => RtlDialog(
        title: 'delete_material'.tr,
        content: Text('delete_confirm_message'.tr, style: context.colors.body),
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          Navigator.pop(context);
          await context
              .read<TeacherCourseScreenProvider>()
              .deleteMaterial(session.id, m.id);
        },
        confirmLabel: 'delete'.tr,
        confirmColor: context.colors.danger,
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

  const MaterialIconWidget({
    super.key,
    required this.icon,
    required this.color,
    required this.isCompleted,
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
                : effectiveColor.withValues(alpha: 0.12),
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
          child: Icon(
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
