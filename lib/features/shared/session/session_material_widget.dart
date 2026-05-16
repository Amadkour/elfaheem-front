// ─────────────────────────────────────────────────────────────────────────────
// Teacher session card (expandable, mobile-first)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../../utils/widget/video_screen.dart';
import '../../analytics/teacher/exam/teacher_exam_hub_screen.dart';
import '../../analytics/teacher/teacher_attendance_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/models.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/sessions/model/session_material_model.dart';
import '../../teacher/sessions/sessions_provider.dart';

class SessionMaterialCard extends StatefulWidget {
  final TeacherSessionItem session;
  final TeacherCourse course;
  final bool isTeacher;

  const SessionMaterialCard(
      {super.key,
      required this.session,
      required this.course,
      required this.isTeacher});

  @override
  State<SessionMaterialCard> createState() => _TeacherSessionCardState();
}

class _TeacherSessionCardState extends State<SessionMaterialCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherSessionsProvider>().fetchMaterials(widget.session.id);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if(mounted) setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
      if (context
          .read<TeacherSessionsProvider>()
          .materialsFor(widget.session.id)
          .isEmpty) {}
    } else {
      _ctrl.reverse();
    }
  }

  void _openAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<TeacherSessionsProvider>(),
          child: TeacherAttendanceScreen(
            sessionId: widget.session.id,
            courseId: widget.session.courseId,
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
          courseId: widget.session.courseId,
          courseTitle: widget.course.title,
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: widget.session.name);
    final descCtrl =
        TextEditingController(text: widget.session.description ?? '');
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('تعديل الدرس', style: context.colors.h3),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _Field(ctrl: nameCtrl, label: 'الاسم', context: context),
            const SizedBox(height: 12),
            _Field(ctrl: descCtrl, label: 'الوصف', context: context),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context.read<TeacherSessionsProvider>().updateSession(
                      widget.session.id,
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                    );
              },
              child: const Text('حفظ',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('حذف الدرس', style: context.colors.h3),
          content: Text(
              'هل تريد حذف "${widget.session.name}"؟ لا يمكن التراجع.',
              style: context.colors.body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context
                    .read<TeacherSessionsProvider>()
                    .deleteSession(widget.session.id);
              },
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(
    BuildContext context, {
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

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final prov = context.watch<TeacherSessionsProvider>();
    final materials = prov.materialsFor(s.id);
    final uploading = prov.isUploadingMaterial(s.id);
    final isLive = s.isLiveActive as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow: context.colors.cardShadow,
        border: isLive
            ? Border.all(color: context.colors.danger.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          child: Row(children: [
            Container(
              width: 5,
              height: widget.isTeacher || s.isLive || materials.isNotEmpty
                  ? 100
                  : 70,
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isLive
                          ? [
                              context.colors.danger,
                              context.colors.danger.withValues(alpha: 0.4)
                            ]
                          : [
                              context.colors.primary,
                              context.colors.primary.withValues(alpha: 0.4)
                            ]),
                  borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          children: [
                            Text(s.name,
                                style: context.colors.h3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            SizedBox(
                              width: 5,
                            ),
                            Text(s.createdAt.age,
                                style: context.colors.navLabelUnselected,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        
                          ],
                        ),
                        if (s.description != null)
                          Text(s.description!,
                              style: context.colors.navLabelUnselected,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(children: [
                          _TypePill(isLive: isLive),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time_rounded,
                              size: 12, color: context.colors.textLight),
                          const SizedBox(width: 3),
                          Text('${s.durationMinutes} ${'m'.tr}',
                              style: context.colors.caption),
                        ]),
                            ]),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              if (widget.isTeacher) ...[
                                _iconAction(
                                  context,
                                  icon: CupertinoIcons.settings_solid,
                                  color: context.colors.textMedium,
                                  tooltip: 'تعديل',
                                  onTap: () => _showEditDialog(context),
                                ),
                                _iconAction(
                                  context,
                                  icon: Icons.delete,
                                  color: context.colors.danger,
                                  tooltip: 'حذف',
                                  onTap: () => _confirmDelete(context),
                                ),
                              ]
                            ],
                          ),
                          RatingWidget(
                            type: RateType.session,
                            sourceId: s.id.toString(),
                            canEdit: !widget.isTeacher,
                          ),
                        ],
                      ),
                    ],
                  ),

                  Divider(
                    height: 2,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(children: [
                      if (widget.isTeacher) ...[
                        _ActionBtn(
                          icon: Icons.how_to_reg_rounded,
                          label: 'الحضور',
                          color: const Color(0xFF4DA6FF),
                          onTap: _openAttendance,
                          outlined: true,
                        ),
                        const SizedBox(width: 8),
                        _ActionBtn(
                          icon: Icons.quiz_rounded,
                          label: 'الامتحانات',
                          color: const Color(0xFFFF9F43),
                          onTap: _openExams,
                          outlined: true,
                        ),
                      ],
                      if (s.type == 'live') ...[
                        const SizedBox(width: 8),
                        _ActionBtn(
                          icon: CupertinoIcons.video_camera_solid,
                          label: 'Meet Now',
                          color: context.colors.success,
                          onTap: () async {
                            final prov =
                                context.read<TeacherSessionsProvider>();
                            if (s.isLiveActive) {
                              await prov.endLive(s.id);
                            } else {
                              await prov.startLive(s.id);
                              if (context.mounted) {
                                prov.joinLive(context, s.id, s.courseId, 200);
                              }
                            }
                          },
                          outlined: true,
                        ),
                      ],
                      Spacer(),
                      if (materials.isNotEmpty)
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _toggle,
                              child: Column(
                                children: [
                                  Text('${materials.length} ${'materials'.tr}',
                                      style: context.colors.navLabelUnselected
                                          .copyWith(height: 0.3),
                                      maxLines: 1,
                                      textDirection: TextDirection.ltr,
                                      overflow: TextOverflow.ellipsis),
                                  AnimatedRotation(
                                    turns: _expanded ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 280),
                                    child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: context.colors.textMedium),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else if (widget.isTeacher)
                        _AddMaterialButton(
                          sessionId: s.id,
                        )
                    ]),
                  ),
                ],
              ),
            ),
          ]),
        ),
        if (uploading)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: LinearProgressIndicator(
                color: context.colors.primary,
                backgroundColor: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4)),
          ),
        SizeTransition(
          sizeFactor: _anim,
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(context.colors.radiusMedium),
                bottomLeft: Radius.circular(context.colors.radiusMedium),
              ),
              border: Border(
                  top: BorderSide(
                      color: context.colors.textLight.withValues(alpha: 0.1))),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.attach_file_rounded,
                    size: 14, color: context.colors.primary),
                const SizedBox(width: 6),
                Text('المرفقات',
                    style: context.colors.caption.copyWith(
                        color: context.colors.primary,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (widget.isTeacher) _AddMaterialButton(sessionId: s.id),
              ]),
              const SizedBox(height: 10),
              _MaterialGrid(
                session: s,
                materials: materials,
                columns: context.isMobile ? 1 : 2,
                isTeacher: widget.isTeacher,
              ),
            ]),
          ),
        ),
      ]),
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

  static const _typeLabels = {
    SessionMaterialType.image: 'صورة',
    SessionMaterialType.video: 'فيديو',
    SessionMaterialType.pdf: 'PDF',
    SessionMaterialType.document: 'مستند',
    SessionMaterialType.link: 'رابط',
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
          Text('لا توجد مرفقات بعد',
              style: context.colors.caption
                  .copyWith(color: context.colors.textLight)),
        ]),
      );
    }

    if (columns == 1) {
      return Column(
          children:
              materials.map((m) => _buildMaterialTile(context, m)).toList());
    }

    final rows = <Widget>[];
    for (int i = 0; i < materials.length; i += columns) {
      final rowItems = materials.sublist(
          i, (i + columns) > materials.length ? materials.length : i + columns);
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
      if (i + columns < materials.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildMaterialTile(BuildContext context, SessionMaterialModel m) {
    final icon = _typeIcons[m.type] ?? Icons.attach_file_rounded;
    final color = _typeColors[m.type] ?? context.colors.primary;
    final label = _typeLabels[m.type] ?? '';

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(m.url);

        if (m.type == SessionMaterialType.video) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => VideoScreen(
                        uri: uri,
                        session: session,
                      )));
        } else {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Text(m.name,
                      style: context.colors.body
                          .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(
                    width: 5,
                  ),
                  Text(m.createdAt.age,
                      style: context.colors.navLabelUnselected,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
              const SizedBox(height: 3),
              Row(children: [
                _Pill(label, color),
                if (m.fileSize != null) ...[
                  const SizedBox(width: 6),
                  Text(m.sizeLabel,
                      style: context.colors.caption.copyWith(fontSize: 10)),
                ],
              ]),
                  RatingWidget(
                    type: RateType.material,
                    sourceId: m.id.toString(),
                    canEdit: !isTeacher,
                  ),
            ]),
          ),

          Row(
            children: [
          if (isTeacher) ...[
            _iconBtn(
              icon: CupertinoIcons.settings_solid,
              color: context.colors.textMedium,
              onTap: () => _showEditDialog(context, m),
            ),
            _iconBtn(
              icon: CupertinoIcons.minus_circle_fill,
              color: context.colors.danger,
              onTap: () => _confirmDelete(context, m),
            ),
          ] else
            Icon(Icons.open_in_new_rounded,
                size: 16, color: context.colors.textLight),
            ],
          )

        ]),
      ),
    );
  }

  Widget _iconBtn(
          {required IconData icon,
          required Color color,
          required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, size: 23, color: color),
        ),
      );

  void _showEditDialog(BuildContext context, SessionMaterialModel m) {
    final nameCtrl = TextEditingController(text: m.name);
    final descCtrl = TextEditingController(text: m.description ?? '');
    final urlCtrl = TextEditingController(text: m.url);
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('تعديل المرفق', style: context.colors.h3),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _Field(ctrl: nameCtrl, label: 'الاسم', context: context),
              const SizedBox(height: 12),
              _Field(
                  ctrl: descCtrl, label: 'الوصف (اختياري)', context: context),
              if (m.type == SessionMaterialType.link) ...[
                const SizedBox(height: 12),
                _Field(ctrl: urlCtrl, label: 'الرابط', context: context),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
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
              child: const Text('حفظ',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SessionMaterialModel m) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('حذف المرفق', style: context.colors.h3),
          content: Text('هل تريد حذف "${m.name}"؟ لا يمكن التراجع.',
              style: context.colors.body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context
                    .read<TeacherSessionsProvider>()
                    .deleteMaterial(session.id, m.id);
              },
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add material button + bottom sheet
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
          border:
              Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 14, color: context.colors.primary),
          const SizedBox(width: 4),
          Text('إضافة مرفق',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: context.colors.primary,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _AddMaterialSheet extends StatefulWidget {
  final int sessionId;

  const _AddMaterialSheet({required this.sessionId});

  @override
  State<_AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<_AddMaterialSheet> {
  int _mode = 0;
  PlatformFile? _pickedFile;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _saving = false;

  static const _fileTypes = [
    _FileTypeOption(
        'صورة', Icons.image_rounded, FileType.image, Color(0xFF4CAF50)),
    _FileTypeOption(
        'فيديو', Icons.play_circle_rounded, FileType.video, Color(0xFF2196F3)),
    _FileTypeOption('PDF / مستند', Icons.description_rounded, FileType.custom,
        Color(0xFFF44336)),
  ];

  int _fileTypeIdx = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: context.colors.textLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Text('إضافة مرفق', style: context.colors.h3),
          const SizedBox(height: 16),
          _ModeToggle(
            selected: _mode,
            onChanged: (v) { if(mounted) setState(() => _mode = v);},
          ),
          const SizedBox(height: 16),
          if (_mode == 0) ...[
            Row(
                children: List.generate(_fileTypes.length, (i) {
              final opt = _fileTypes[i];
              final sel = i == _fileTypeIdx;
              return Expanded(
                child: GestureDetector(
                  onTap: () { if(mounted) setState(() => _fileTypeIdx = i);},
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(
                        left: i < _fileTypes.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel
                          ? opt.color.withValues(alpha: 0.15)
                          : context.colors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel
                              ? opt.color
                              : context.colors.textLight
                                  .withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      Icon(opt.icon,
                          color: sel ? opt.color : context.colors.textLight,
                          size: 22),
                      const SizedBox(height: 4),
                      Text(opt.label,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color:
                                  sel ? opt.color : context.colors.textLight)),
                    ]),
                  ),
                ),
              );
            })),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _pickedFile != null
                      ? context.colors.success.withValues(alpha: 0.08)
                      : context.colors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _pickedFile != null
                          ? context.colors.success.withValues(alpha: 0.4)
                          : context.colors.textLight.withValues(alpha: 0.2),
                      width: 1.5),
                ),
                child: Column(children: [
                  Icon(
                      _pickedFile != null
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      size: 28,
                      color: _pickedFile != null
                          ? context.colors.success
                          : context.colors.textMedium),
                  const SizedBox(height: 6),
                  Text(
                      _pickedFile != null
                          ? _pickedFile!.name
                          : 'اضغط لاختيار الملف',
                      style: context.colors.body.copyWith(
                          fontSize: 13,
                          color: _pickedFile != null
                              ? context.colors.success
                              : context.colors.textMedium),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ] else ...[
            _Field(ctrl: _urlCtrl, label: 'الرابط (URL)', context: context),
          ],
          const SizedBox(height: 12),
          _Field(ctrl: _nameCtrl, label: 'الاسم', context: context),
          const SizedBox(height: 10),
          _Field(ctrl: _descCtrl, label: 'الوصف (اختياري)', context: context),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _saving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _submit,
                      child: const Text('إضافة المرفق',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickFile() async {
    final opt = _fileTypes[_fileTypeIdx];
    List<String>? allowedExts;
    if (opt.fileType == FileType.custom) {
      allowedExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];
    }
    final result = await FilePicker.pickFiles(
      type: opt.fileType,
      allowedExtensions: allowedExts,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      if(mounted) setState(() => _pickedFile = result.files.first);
      if (_nameCtrl.text.isEmpty) {
        _nameCtrl.text = _pickedFile!.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('يرجى إدخال الاسم');
      return;
    }

    final prov = context.read<TeacherSessionsProvider>();
    if(mounted) setState(() => _saving = true);

    try {
      if (_mode == 0) {
        if (_pickedFile == null) {
          _toast('يرجى اختيار ملف');
          return;
        }
        final bytes = _pickedFile?.bytes;
        if (bytes == null) {
          _toast('فشل تحميل الملف، حاول مرة أخرى');
          return;
        }
        await prov.uploadFileMaterial(
          sessionId: widget.sessionId,
          fileName: _pickedFile!.name,
          fileBytes: bytes,
          name: name,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
      } else {
        final url = _urlCtrl.text.trim();
        if (url.isEmpty) {
          _toast('يرجى إدخال الرابط');
          return;
        }
        await prov.addLinkMaterial(
          sessionId: widget.sessionId,
          name: name,
          url: url,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) if(mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: context.colors.danger,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
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
        ? Border.all(color: widget.color.withValues(alpha:0.40), width: 1.2)
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
                      color: widget.color.withValues(alpha:0.30),
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
              color: context.colors.textLight.withValues(alpha: 0.15))),
      child: Row(children: [
        _segment('ملف', 0, Icons.upload_file_rounded, context),
        _segment('رابط', 1, Icons.link_rounded, context),
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
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 15,
                color: sel ? Colors.white : context.colors.textMedium),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : context.colors.textMedium)),
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
            borderRadius: BorderRadius.circular(6)),
        child: Text(isLive ? '🔴 مباشر' : '▶ مسجّل',
            style: context.colors.caption
                .copyWith(color: c, fontWeight: FontWeight.w700)));
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
          borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w700)));
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
            borderSide:
                BorderSide(color: ctx.colors.textLight.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: ctx.colors.textLight.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ctx.colors.primary),
          ),
        ),
      );
}

class _FileTypeOption {
  final String label;
  final IconData icon;
  final FileType fileType;
  final Color color;

  const _FileTypeOption(this.label, this.icon, this.fileType, this.color);
}
