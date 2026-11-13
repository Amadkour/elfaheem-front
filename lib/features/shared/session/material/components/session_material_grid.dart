// shared/session/components/session_material_grid.dart
//
// Renders the grid/list of SessionMaterialModel items inside the expandable
// panel. Handles tap → video player / image viewer / external URL, plus
// teacher edit / delete dialogs.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_education_app/design/app_share_sheet.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../core/api_client.dart';
import '../../../../../core/app_time.dart';
import '../../../../../core/live/event_wait.dart';
import '../../../../../design/app_kit.dart' show showAppSheet, AppSheetHeader, AppBanner, AppListSkeleton;
import '../../../../../design/app_tokens.dart';
import '../../../../../utils/helpers.dart';
import '../../../../../utils/widget/rating_widget.dart';
import '../../../../student/courses/details/course_detail_provider.dart';
import '../../../../student/models.dart';
import '../../../../teacher/sessions/sessions_provider.dart';
import '../../video/video_player_screen.dart';
import '../../video/vod_player_parts.dart' show VodAction, VodInk, VodGlassButton, vodText;
import '../../../../../core/offline/offline_strings.dart' show offlineT;
import '../../../../../design/app_motion_kit.dart' show AppPressScale, AppEase;
import '../../../records/material_studio_page.dart'
    show MaterialStudioDraftsPanel, materialStudioLabel, materialStudioOn, openMaterialStudio;
import '../session_material_model.dart';
import 'material_file_style.dart';
import 'material_tile_parts.dart';
import 'material_title.dart';
import 'session_exam_tile.dart';
import 'session_shared_widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_number_field.dart';

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
  static Color _typeColor(BuildContext context, SessionMaterialType t) {
    final c = context.colors;
    switch (t) {
      case SessionMaterialType.image:
        return c.success; // green
      case SessionMaterialType.video:
        return c.primary; // blue
      case SessionMaterialType.pdf:
        return c.danger; // red
      case SessionMaterialType.document:
        return c.warning; // orange
      case SessionMaterialType.link:
        return c.purple; // purple
      case SessionMaterialType.recorded:
        return c.primaryLight; // indigo – archive feel
      case SessionMaterialType.recording:
        return c.danger; // vivid red – live/active
    }
  }

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
      return const AppListSkeleton(items: 4, padding: EdgeInsets.symmetric(vertical: 8));
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
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(
          children: [
            Icon(Icons.folder_open_rounded, size: AppIconSize.md - 2, color: context.colors.textLight),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text('no_attachments_yet'.tr, style: AppType.meta(context))),
          ],
        ),
      );
    }

    // Teachers: one drag-and-drop list (long-press-free: grab the handle).
    if (isTeacher) {
      final list = ReorderableListView.builder(
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
      if (!materialStudioOn) return list;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MaterialStudioDraftsPanel(
          key: ValueKey('material.drafts.${session.id}'),
          sessionId: session.id,
          onChanged: () => _reloadMaterials(context),
        ),
        list,
      ]);
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
              if (j > 0) const SizedBox(width: AppSpace.sm),
              Expanded(child: _buildTile(context, rowItems[j], i + j + 1)),
            ],
            if (rowItems.length < columns) ...[
              const SizedBox(width: AppSpace.sm),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
      if (end < session.totalMaterial) rows.add(const SizedBox(height: AppSpace.xs));
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
    final c = context.colors;
    final isRecording = m.type == SessionMaterialType.recording;
    final isRecorded = m.type == SessionMaterialType.recorded;
    final isVideo = m.type == SessionMaterialType.video || isRecorded;

    // Word / Excel / CSV / PowerPoint / Python get their own badge + colour.
    final fileStyle = m.type == SessionMaterialType.document
        ? MaterialFileStyle.forExtension(m.fileExtension)
        : null;
    final icon = _typeIcons[m.type] ?? Icons.attach_file_rounded;
    final color =
        fileStyle?.color ?? _typeColor(context, m.type);
    final labelKey = _typeLabelKeys[m.type] ?? 'material_type_link';
    final isCompleted = m.completed;

    // ── Derived display values ─────────────────────────────────────────────
    // (the recorded item's date sits in the meta line through AppTime, not glued to the title)
    // a class recording drops "<session> — تسجيل الحصة": the row above names the session, the pill says "Recorded" (N9)
    final String displayName = isRecording ? 'recording_in_progress'.tr : materialTitle(m.name, recorded: isRecorded);
    // Stars only once there are ratings ("0.0 (0)" on every file read as noise, N9); a student who finished a file
    // with none yet gets a small "Rate" link that opens them.
    final rating = isRecording
        ? RatingShow.none
        : ratingShow(total: m.rateSummary?.total ?? 0, canRate: !isTeacher && isCompleted);
    final showRating = rating == RatingShow.stars;
    final offerRating = rating == RatingShow.invite;

    final meta = AppType.meta(context);
    Widget fact(String text, {IconData? glyph}) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (glyph != null) ...[
            Icon(glyph, size: AppIconSize.xs - 2, color: c.textLight),
            const SizedBox(width: AppSpace.xxs / 2),
          ],
          Text(text,
              textDirection: TextDirection.ltr, // "15.2 MB" / "1:02:33" stay whole, also in RTL
              style: meta.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]);

    Widget typeTile() => isRecording
        ? _RecordingSpinnerIcon(color: color)
        : MaterialIconWidget(
            icon: icon,
            color: color,
            // one done mark per card (N9): the check at the end, not a green tile + pill too
            isCompleted: false,
            badge: fileStyle?.badge,
            badgeTextColor: fileStyle?.badgeTextColor,
            size: 44,
          );

    return Directionality(
      textDirection: Helpers.textDirOf(displayName),
      child: _MaterialCardShell(
        key: ValueKey('material.card.${m.id}'),
        onTap: isRecording
            ? null
            : () => _onTapMaterial(context, m, isCompleted),
        completed: isCompleted,
        accent: color,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, isTeacher ? AppSpace.xxs : AppSpace.sm, AppSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Leading: the type tile, its number on the corner (D-316) ──
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs + 2, start: AppSpace.xxs),
                    child: typeTile(),
                  ),
                  PositionedDirectional(top: 0, start: 0, child: MaterialIndexBadge(index: index)),
                ],
              ),

              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: AppType.row(context).copyWith(
                          fontWeight: FontWeight.w600,
                          fontStyle: isRecording ? FontStyle.italic : FontStyle.normal,
                          color: isCompleted ? c.textMedium : c.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpace.xxs + 2),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SessionPill(fileStyle?.label ?? labelKey.tr, color),
                          if (m.sizeLabel.isNotEmpty && !isRecording) fact(m.sizeLabel), // KB under 1 MB, else MB
                          if (m.durationLabel.isNotEmpty && !isRecording) fact(m.durationLabel, glyph: Icons.schedule_rounded),
                          // For recording, a live dot instead of the age; a recorded class shows its date
                          if (isRecording)
                            _LiveDotBadge(color: color)
                          else
                            Builder(builder: (_) {
                              final when = isRecorded ? _formatDate(m.createdAt) : m.createdAt.age;
                              return Text(
                                when,
                                textDirection: Helpers.textDirOf(when), // "3 days ago" reads whole in an Arabic row
                                style: meta.copyWith(color: c.textLight),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            }),
                        ],
                      ),
                      if (showRating)
                        RatingWidget(
                          type: RateType.material,
                          sourceId: m.id.toString(),
                          canEdit: !isTeacher,
                          rateSummary: m.rateSummary,
                        )
                      else if (offerRating)
                        RateLater(type: RateType.material, sourceId: m.id.toString(), rateSummary: m.rateSummary),
                    ],
                  ),
                ),
              ),
              // ── Trailing: teacher actions / student open indicator ──
              if (isTeacher)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dragIndex != null)
                      ReorderableDragStartListener(
                        index: dragIndex,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: SizedBox(
                            width: AppSpace.xl + AppSpace.xxs,
                            height: AppTouch.min,
                            child: Icon(Icons.drag_indicator_rounded, size: AppIconSize.md, color: c.textLight),
                          ),
                        ),
                      ),
                    if (!isRecording && isVideo)
                      _CaptionsAction(
                        key: ValueKey('captions_action.${m.id}'),
                        material: m,
                        onUpload: () => _pickAndUploadCaptions(context, m),
                        onManage: (generate) =>
                            _showCaptionsDialog(context, m, onGenerate: generate),
                      ),
                    // Studio · Edit details · Share · Delete: ONE ⋯ (D-316)
                    MaterialMoreButton(
                      key: ValueKey('material.more.${m.id}'),
                      onTap: () => _showOptions(
                        context,
                        m,
                        icon: typeTile(),
                        color: color,
                        facts: [
                          fileStyle?.label ?? labelKey.tr,
                          if (m.sizeLabel.isNotEmpty && !isRecording) m.sizeLabel,
                          if (m.durationLabel.isNotEmpty && !isRecording) m.durationLabel,
                        ],
                      ),
                    ),
                  ],
                )
              else if (!isRecording)
                SizedBox(
                  height: AppTouch.min,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isVideo)
                        _OfflineBadge(
                          sessionId: m.sessionId,
                          materialId: m.id,
                        ),
                      AnimatedSwitcher(
                        duration: AppMotion.of(context).slow,
                        switchInCurve: AppEase.out,
                        switchOutCurve: AppEase.out,
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: Tween(begin: 0.6, end: 1.0).animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: isCompleted
                            ? Padding(
                                key: const ValueKey('check'),
                                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs - 2),
                                child: Semantics(
                                  label: 'completed'.tr,
                                  child: Icon(Icons.check_circle_rounded, size: AppIconSize.md, color: c.success),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('empty')),
                      ),
                      // a lecture plays here, a file opens outside
                      Icon(
                        isVideo ? Icons.play_circle_outline_rounded : Icons.open_in_new_rounded,
                        size: isVideo ? AppIconSize.md : AppIconSize.sm,
                        color: isVideo ? c.blockAccentInk(c.primary, c.cardBg) : c.textLight,
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

  // ── Date helper ────────────────────────────────────────────────────────────

  /// A short date in the platform / organization timezone and the app's language, e.g. "14 Jan 2025".
  String _formatDate(DateTime dt) => AppTime.date(dt.toUtc(), pattern: 'd MMM y');

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
      final nav = Navigator.of(context); // read now: the tile under the player may be rebuilt or gone later
      final reload = _reloader(context);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            autoPlay: true,
            startFullScreen: false,
            material: m,
            playlist: materials,
            actionsFor: isTeacher && materialStudioOn ? (cur) => _studioActions(nav, reload, cur) : null,
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

  // ── Studio (D-315) ─────────────────────────────────────────────────────────

  /// Opens the Studio on [nav]. [replaceTop]: called from the player, which the Studio replaces in one step.
  Future<void> _openStudio(NavigatorState nav, VoidCallback? reload, SessionMaterialModel m, {bool replaceTop = false}) async {
    final changed = await openMaterialStudio(null,
        navigator: nav, replaceTop: replaceTop, sessionId: m.sessionId == 0 ? session.id : m.sessionId, materialId: m.id);
    if (changed) reload?.call();
  }

  void _reloadMaterials(BuildContext context) => _reloader(context)?.call();

  VoidCallback? _reloader(BuildContext context) {
    try {
      final p = context.read<TeacherCourseScreenProvider>();
      return () => p.reloadMaterials(session);
    } catch (_) {
      return null; // opened outside the teacher's course page: nothing to reload
    }
  }

  /// The player's Open in Studio for a video / recorded lecture: the Studio takes the player's place.
  List<VodAction> _studioActions(NavigatorState nav, VoidCallback? reload, SessionMaterialModel cur) {
    if (cur.id <= 0 || !(cur.type == SessionMaterialType.video || cur.type == SessionMaterialType.recorded)) return const [];
    return [
      VodAction(
        id: 'studio',
        icon: Icons.movie_edit,
        label: materialStudioLabel,
        onTap: () => _openStudio(nav, reload, cur, replaceTop: true),
      ),
    ];
  }

  // ── Options (D-316): Studio · Edit details · Share · Delete behind ONE ⋯ ─────

  Future<void> _showOptions(BuildContext context, SessionMaterialModel m,
      {required Widget icon, required Color color, required List<String> facts}) async {
    final isRecording = m.type == SessionMaterialType.recording;
    final isVideo = m.type == SessionMaterialType.video || m.type == SessionMaterialType.recorded;
    final ar = AppConfig.lang == 'ar';
    String tt(String a, String e) => ar ? a : e;
    final nav = Navigator.of(context);
    final reload = _reloader(context);
    final id = await showAppSheet<String>(
      context,
      (_) => MaterialOptionsSheet(
        title: isRecording ? 'recording_in_progress'.tr : materialTitle(m.name, recorded: m.type == SessionMaterialType.recorded),
        icon: icon,
        color: color,
        facts: facts,
        groups: [
          if (!isRecording && isVideo && materialStudioOn)
            [
              MaterialOption(
                id: 'studio',
                icon: Icons.movie_edit,
                label: materialStudioLabel,
                hint: tt('قصّ، اقتطاع، تقسيم، سرعة، دمج — كمسودة لا يراها الطلاب حتى تنشرها',
                    "Trim, cut, split, speed, merge — as a draft students don't see until you publish it"),
              ),
            ],
          if (!isRecording)
            [
              MaterialOption(
                id: 'edit',
                icon: Icons.tune_rounded,
                label: 'edit_material'.tr,
                hint: m.type == SessionMaterialType.link
                    ? tt('الاسم والوصف والترتيب والرابط', 'Name, description, order and link')
                    : tt('الاسم والوصف والترتيب', 'Name, description and order'),
              ),
              if (!AppConfig.disableList.contains(kShareLinksKey))
                MaterialOption(
                  id: 'share',
                  icon: Icons.ios_share_rounded,
                  label: _shareTip,
                  hint: tt('يفتحه طلاب المقرر بعد تسجيل الدخول', 'The course students open it after signing in'),
                ),
            ],
        ],
        danger: MaterialOption(
          id: 'delete',
          icon: Icons.delete_outline_rounded,
          label: tt('حذف المادة', 'Delete material'),
          danger: true,
        ),
      ),
    );
    if (id == null || !context.mounted) return;
    switch (id) {
      case 'studio':
        await _openStudio(nav, reload, m);
      case 'edit':
        _showEditDialog(context, m);
      case 'share':
        shareAppLink(context, AppLink.material(m.id), title: m.name, subtitle: session.name);
      case 'delete':
        _showDeleteDialog(context, m);
    }
  }

  /// The lesson's member link (D-307, `/s/material/<id>`): the course's students open it after signing in.
  static String get _shareTip => AppConfig.lang == 'ar' ? 'مشاركة رابط الدرس' : 'Share lesson link';

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
              const SizedBox(height: AppSpace.sm),
              SessionField(ctrl: descCtrl, label: 'description_optional'.tr),
              const SizedBox(height: AppSpace.sm),
              AppNumberField(controller: orderCtrl, label: 'order_label'.tr, min: 0),
              if (m.type == SessionMaterialType.link) ...[
                const SizedBox(height: AppSpace.sm),
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
            const SizedBox(height: AppSpace.sm),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _ctrl); // reduce motion parks the ring
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Spinning ring
          RotationTransition(turns: _ctrl, child: AppLoadingIndicator()),
          // the recording's red dot in the middle
          Container(
            width: AppIconSize.xs,
            height: AppIconSize.xs,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        ],
      ),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _ctrl, reverse: true); // reduce motion parks this decorative loop
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
        decoration: BoxDecoration(
          color: context.colors.dangerTint,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSpace.xs - 2,
              height: AppSpace.xs - 2,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpace.xxs),
            Flexible(
              child: Text(
                'live'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.overline(context).copyWith(color: context.colors.blockAccentInk(widget.color, context.colors.cardBg)),
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
    this.size = 38,
  });

  /// The tile's side (38 in lists; 44 on the material card, D-316).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // a tinted well with the type's mark in its colour (lifted to AA on the tint); file brands keep their solid
    // badge; a completed tile is the solid success well with a check
    final well = isCompleted ? c.success : (badge != null ? color : Color.alphaBlend(color.withValues(alpha: 0.12), c.cardBg));
    final radius = BorderRadius.circular(size >= 40 ? AppRadius.control - 2 : AppRadius.chip);
    final label = badge;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: well, borderRadius: radius),
      child: (label != null && !isCompleted)
          ? Padding(
              padding: const EdgeInsets.all(AppSpace.xxs),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textDirection: TextDirection.ltr,
                  style: (label.length > 2 ? AppType.overline(context) : AppType.figure(context))
                      .copyWith(color: badgeTextColor ?? c.onHero, fontWeight: FontWeight.w700),
                ),
              ),
            )
          : Icon(
              isCompleted ? Icons.check_rounded : icon,
              color: isCompleted ? c.onHero : c.blockAccentInk(color, well),
              size: size * 0.5,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Rate" link: a finished file (or a held session) with no ratings yet opens the stars on demand (no "0.0 (0)"
// row, N9)
// ─────────────────────────────────────────────────────────────────────────────

class RateLater extends StatefulWidget {
  const RateLater({super.key, required this.type, required this.sourceId, this.rateSummary, this.labelKey = 'material_rate_it'});

  final RateType type;
  final String sourceId;
  final RatingSummary? rateSummary;

  /// The link's text (translation key).
  final String labelKey;

  @override
  State<RateLater> createState() => _RateLaterState();
}

class _RateLaterState extends State<RateLater> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_open) {
      return RatingWidget(
        type: widget.type,
        sourceId: widget.sourceId,
        canEdit: true,
        rateSummary: widget.rateSummary,
      );
    }
    final c = context.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => setState(() => _open = true),
        style: TextButton.styleFrom(
          minimumSize: const Size(AppTouch.min, AppTouch.min - AppSpace.xs),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 2),
          visualDensity: VisualDensity.compact,
          foregroundColor: c.textMedium,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
        ),
        icon: Icon(Icons.star_outline_rounded, size: AppIconSize.sm, color: c.textLight),
        label: Text(widget.labelKey.tr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500)),
      ),
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
    final c = context.colors;
    return Semantics(
      label: 'completed'.tr,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: c.successBase, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: AppIconSize.xs - 2, color: c.onHero),
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
      backgroundColor: VodInk.letterbox,
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
                  color: VodInk.textHigh,
                  size: AppSpace.xxxl,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                // a legibility scrim over the picture
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [VodInk.shade(0.78), VodInk.shade(0)],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + AppSpace.xs,
                left: AppSpace.xs,
                right: AppSpace.md,
                bottom: AppSpace.lg,
              ),
              child: Row(
                children: [
                  VodGlassButton(icon: Icons.close_rounded, tooltip: 'close'.tr, bright: true, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      title,
                      style: vodText(AppType.section(context)),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
            child: SizedBox(
              width: AppIconSize.sm,
              height: AppIconSize.sm,
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
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                  child: Icon(
                    Icons.offline_pin_rounded,
                    size: AppIconSize.sm,
                    color: primary,
                    semanticLabel: offlineT('dl_on_device'),
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
  static const _pollEveryLive = Duration(seconds: 30); // the fallback while `job_updated{kind: caption}` arrives
  static const _maxPolls = 40; // ≈ 5 minutes

  String? _status;
  String? _url;
  bool _busy = false;
  EventOrPoll? _poll;
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
    _poll?.dispose();
    super.dispose();
  }

  void _sync() {
    _status = _m.captionsStatus;
    _url = _m.captionsUrl;
  }

  // ── Polling (the fallback: the live event `job_updated{kind: caption, id}` refreshes at once) ──────────────
  void _startPolling() {
    _polls = 0;
    (_poll ??= EventOrPoll(kind: 'caption', id: '${_m.id}', every: _pollEvery, fallbackEvery: _pollEveryLive, poll: _refresh)).start();
  }

  void _stopPolling() {
    _poll?.stop();
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
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_failed)
              AppBanner(
                key: const ValueKey('captions.failed_note'),
                icon: Icons.error_outline_rounded,
                text: 'captions_status_failed'.tr,
                color: c.danger,
              )
            else
              Text('captions_none'.tr, style: AppType.body(context)),
            const SizedBox(height: AppSpace.sm),
            ListTile(
              key: const ValueKey('captions.upload'),
              leading: Icon(Icons.upload_file_rounded, color: c.primary),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
              title: Text('upload_captions'.tr, style: AppType.bodyStrong(context)),
              subtitle: Text('captions_pick_vtt'.tr, style: AppType.meta(context)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                widget.onUpload();
              },
            ),
            ListTile(
              key: const ValueKey('captions.generate'),
              leading: Icon(Icons.auto_awesome_rounded, color: c.primary),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
              title: Text((_failed ? 'captions_retry' : 'captions_generate').tr, style: AppType.bodyStrong(context)),
              subtitle: Text('captions_auto_queued'.tr, style: AppType.meta(context)),
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
        child: SizedBox.square(
          dimension: AppTouch.min,
          child: Center(
            child: SizedBox(
              key: const ValueKey('captions.pending'),
              width: AppIconSize.md - 2,
              height: AppIconSize.md - 2,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
            ),
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
    return IconButton(
      tooltip: 'captions_title'.tr,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      icon: Icon(icon, size: AppIconSize.md + 2, color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The material card's shell (D-316): a soft raised card with ink + hover, the type's colour as a thin start edge.
// ─────────────────────────────────────────────────────────────────────────────
class _MaterialCardShell extends StatelessWidget {
  const _MaterialCardShell({super.key, required this.onTap, required this.completed, required this.accent, required this.child});

  final VoidCallback? onTap;
  final bool completed;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            // calm hairline; "done" is the check, not a heavy green frame
            side: BorderSide(color: c.divider, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: Color.alphaBlend(accent.withValues(alpha: 0.03), c.inputBg).withValues(alpha: 0.6),
            splashColor: accent.withValues(alpha: 0.08),
            highlightColor: accent.withValues(alpha: 0.04),
            child: child,
          ),
        ),
      ),
    );
  }
}
