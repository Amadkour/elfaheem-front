// lib/features/home/teacher/add_class_materials_page.dart
//
// "أضف مواد للحصة" (owner 2026-11-27): the teacher picks the course and the class, then adds files, recordings,
// links or a note, and sees what the class already has with a remove on each row. Reached from the teacher home (the
// materials figure and the "materials missing" to-do), pushed with MaterialPageRoute. The teacher frame (T2HeroPage)
// and the kit; every call is the existing session-materials API through TeacherCourseScreenProvider (the same sheet
// the course screen uses for a file / a recording / a link; a note is uploaded as a .txt file).
library;

import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherSessionItem;
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart' show TeacherCourse;
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_education_app/features/sessions/material/components/add_material_sheet.dart' show showAddMaterialSheet;
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart' show TeacherCourseScreenProvider;

/// Opens the page; [courseId] / [sessionId] preselect (a to-do row knows them).
Future<void> openAddClassMaterials(BuildContext context, {required List<TeacherCourse> courses, int? courseId, int? sessionId}) =>
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/add-class-materials'),
      builder: (_) => AddClassMaterialsPage(courses: courses, courseId: courseId, sessionId: sessionId),
    ));

String _courseTitle(TeacherCourse c) {
  final ar = c.titleAr ?? '', en = c.titleEn ?? '';
  return AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
}

/// The class a page opens on: the one asked for, else the latest that has started, else the first.
TeacherSessionItem? pickDefaultSession(List<TeacherSessionItem> all, {int? sessionId, DateTime? now}) {
  if (all.isEmpty) return null;
  final asked = all.where((s) => s.id == sessionId).firstOrNull;
  if (asked != null) return asked;
  final t = now ?? DateTime.now();
  final started = all.where((s) => s.isLiveActive || (s.scheduledAt != null && !s.scheduledAt!.isAfter(t))).toList()
    ..sort((a, b) => (a.scheduledAt ?? a.createdAt).compareTo(b.scheduledAt ?? b.createdAt));
  return started.isNotEmpty ? started.last : all.first;
}

class AddClassMaterialsPage extends StatefulWidget {
  const AddClassMaterialsPage({super.key, required this.courses, this.courseId, this.sessionId});

  final List<TeacherCourse> courses;
  final int? courseId, sessionId;

  @override
  State<AddClassMaterialsPage> createState() => _AddClassMaterialsPageState();
}

class _AddClassMaterialsPageState extends State<AddClassMaterialsPage> {
  TeacherCourseScreenProvider? _prov;
  int? _sessionId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final first = widget.courses.where((c) => c.id == widget.courseId).firstOrNull ??
        (widget.courses.isEmpty ? null : widget.courses.first);
    if (first != null) _openCourse(first, sessionId: widget.sessionId);
  }

  @override
  void dispose() {
    _prov?.dispose();
    super.dispose();
  }

  Future<void> _openCourse(TeacherCourse c, {int? sessionId}) async {
    _prov?.dispose();
    final p = TeacherCourseScreenProvider(initialCourse: c);
    setState(() {
      _prov = p;
      _sessionId = null;
      _loading = true;
    });
    await p.fetchSessions();
    if (!mounted || _prov != p) return;
    final s = pickDefaultSession(p.sessions, sessionId: sessionId);
    setState(() => _sessionId = s?.id);
    if (s != null) await p.fetchMaterials(s);
    if (mounted && _prov == p) setState(() => _loading = false);
  }

  Future<void> _openSession(int id) async {
    final p = _prov;
    final s = p?.sessions.where((x) => x.id == id).firstOrNull;
    if (p == null || s == null) return;
    setState(() {
      _sessionId = id;
      _loading = true;
    });
    await p.fetchMaterials(s);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reload() async {
    final p = _prov;
    final s = p?.sessions.where((x) => x.id == _sessionId).firstOrNull;
    if (p != null && s != null) await p.reloadMaterials(s);
  }

  Future<void> _remove(SessionMaterialModel m) async {
    final p = _prov;
    if (p == null) return;
    final ok = await appConfirm(context, message: 'ow_mat_remove_q'.tr.replaceAll('{name}', m.name), danger: true, confirmLabel: 'ow_mat_remove'.tr);
    if (!ok || !mounted) return;
    final done = await p.deleteMaterial(m.sessionId, m.id);
    showAppNotice(done ? 'ow_mat_removed'.tr : (p.errorMessage ?? 'ow_mat_failed'.tr), error: !done);
  }

  Future<void> _addNote(BuildContext ctx) async {
    final p = _prov, sid = _sessionId;
    if (p == null || sid == null) return;
    final saved = await showAppSheet<bool>(ctx, (_) => _NoteSheet(onSave: (title, body) async {
      final safe = title.replaceAll(RegExp(r'[^\w؀-ۿ \-]'), '').trim();
      final m = await p.uploadFileMaterial(
        sessionId: sid,
        fileName: '${safe.isEmpty ? 'note' : safe}.txt',
        name: title,
        fileBytes: utf8.encode(body),
      );
      return m != null;
    }));
    if (saved == true) showAppNotice('ow_mat_added'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final p = _prov;
    final body = <Widget>[];
    if (p == null) {
      body.add(AppEmpty(icon: Icons.menu_book_outlined, title: 'ow_mat_no_courses'.tr, message: 'ow_mat_no_courses_hint'.tr));
    } else {
      body.add(ChangeNotifierProvider.value(
        value: p,
        child: Consumer<TeacherCourseScreenProvider>(builder: (ctx, prov, _) => _content(ctx, prov)),
      ));
    }
    return T2HeroPage(
      title: 'ow_mat_title'.tr,
      pageKey: const ValueKey('teacher.add_class_materials'),
      onRefresh: _reload,
      width: AppWidth.content,
      hero: AppHero(title: 'ow_mat_hero'.tr, subtitle: 'ow_mat_hero_sub'.tr),
      children: body,
    );
  }

  Widget _content(BuildContext ctx, TeacherCourseScreenProvider prov) {
    final sessions = prov.sessions;
    final sid = _sessionId;
    final ready = sid != null;
    final mats = ready ? prov.materialsFor(sid) : const <SessionMaterialModel>[];
    final uploading = ready && prov.isUploadingMaterial(sid);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 1 — which class
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ow_mat_pick'.tr, style: AppType.section(ctx)),
          const SizedBox(height: AppSpace.sm),
          if (widget.courses.length > 1) ...[
            AppDropdown<int>(
              key: const ValueKey('add_mat.course'),
              value: prov.course.id,
              hint: Text('ow_mat_course'.tr),
              items: [
                for (final c in widget.courses)
                  DropdownMenuItem(value: c.id, child: Text(_courseTitle(c), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) {
                final c = widget.courses.where((x) => x.id == id).firstOrNull;
                if (c != null && c.id != prov.course.id) _openCourse(c);
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(_courseTitle(prov.course), style: AppType.bodyStrong(ctx)),
            ),
          if (sessions.isEmpty && !_loading)
            Text('ow_mat_no_classes'.tr, style: AppType.meta(ctx))
          else if (sessions.isNotEmpty)
            AppDropdown<int>(
              key: const ValueKey('add_mat.session'),
              value: sid,
              hint: Text('ow_mat_class'.tr),
              items: [
                for (final s in sessions)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.scheduledAt == null ? s.name : '${s.name} · ${AppTime.date(s.scheduledAt!.toUtc())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => id == null ? null : _openSession(id),
            ),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      // 2 — add
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ow_mat_add'.tr, style: AppType.section(ctx)),
          const SizedBox(height: AppSpace.sm),
          LayoutBuilder(builder: (_, box) {
            final cols = box.maxWidth >= 560 ? 4 : 2;
            final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
            final tiles = <Widget>[
              _AddTile(key: const ValueKey('add_mat.file'), icon: Icons.upload_file_rounded, label: 'ow_mat_file'.tr,
                  onTap: ready ? () => showAddMaterialSheet(ctx, sessionId: sid, initialFileType: 2) : null),
              _AddTile(key: const ValueKey('add_mat.recording'), icon: Icons.videocam_outlined, label: 'ow_mat_recording'.tr,
                  onTap: ready ? () => showAddMaterialSheet(ctx, sessionId: sid, initialFileType: 1) : null),
              _AddTile(key: const ValueKey('add_mat.link'), icon: Icons.link_rounded, label: 'ow_mat_link'.tr,
                  onTap: ready ? () => showAddMaterialSheet(ctx, sessionId: sid, initialMode: 1) : null),
              _AddTile(key: const ValueKey('add_mat.note'), icon: Icons.sticky_note_2_outlined, label: 'ow_mat_note'.tr,
                  onTap: ready ? () => _addNote(ctx) : null),
            ];
            return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
              for (final t in tiles) SizedBox(width: w, child: t),
            ]);
          }),
          if (uploading) ...[
            const SizedBox(height: AppSpace.sm),
            LinearProgressIndicator(value: prov.uploadProgressForSession(sid), semanticsLabel: 'ow_mat_uploading'.tr),
          ],
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      // 3 — what the class has
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ow_mat_attached'.tr, style: AppType.section(ctx)),
          const SizedBox(height: AppSpace.sm),
          if (_loading)
            const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
          else if (mats.isEmpty)
            AppEmpty(icon: Icons.folder_open_outlined, title: 'ow_mat_empty'.tr, message: ready ? 'ow_mat_empty_hint'.tr : null)
          else
            for (final m in mats) _MaterialRow(material: m, onRemove: () => _remove(m)),
        ]),
      ),
    ]);
  }
}

IconData _typeIcon(SessionMaterialType t) => switch (t) {
      SessionMaterialType.image => Icons.image_outlined,
      SessionMaterialType.video || SessionMaterialType.recorded || SessionMaterialType.recording => Icons.videocam_outlined,
      SessionMaterialType.pdf => Icons.picture_as_pdf_outlined,
      SessionMaterialType.link => Icons.link_rounded,
      SessionMaterialType.document => Icons.description_outlined,
    };

class _AddTile extends StatelessWidget {
  const _AddTile({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = onTap != null;
    return AppCard(
      variant: AppCardVariant.flat,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.lg, color: on ? c.primary : c.textMedium),
        const SizedBox(height: AppSpace.xs),
        Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
      ]),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.material, required this.onRemove});

  final SessionMaterialModel material;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(children: [
        Icon(_typeIcon(material.type), color: c.primary),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(material.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text(AppTime.date(material.createdAt.toUtc()), style: AppType.meta(context)),
          ]),
        ),
        IconButton(
          tooltip: 'ow_mat_remove'.tr,
          icon: Icon(Icons.delete_outline_rounded, color: c.danger),
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

/// A short note for the class: a title and the text, saved as a .txt material.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.onSave});

  final Future<bool> Function(String title, String body) onSave;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim(), body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'ow_mat_note_required'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = false;
    try {
      ok = await widget.onSave(title, body);
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = 'ow_mat_failed'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: 'ow_mat_note'.tr,
        icon: Icons.sticky_note_2_outlined,
        children: [
          AppField(controller: _title, label: 'ow_mat_note_title'.tr, required: true, maxLength: 120),
          const SizedBox(height: AppSpace.sm),
          AppField(controller: _body, label: 'ow_mat_note_body'.tr, maxLines: 6, required: true, errorText: _error),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(label: 'ow_mat_save'.tr, icon: Icons.check_rounded, expand: true, busy: _busy, onPressed: _busy ? null : _save),
        ],
      );
}
