// lib/features/notebook/notebook_panel.dart
//
// دفتر المادة (SubjectProfile `panel=notes`, rows 17-18 and 27-30): the body of the subject page's notebook panel
// (`showSubjectPanel(context, title: 'دفتر <subject>', child: (_) => NotebookPanel(…))`).
//
//   view   the ruled sheet with the pages of this course, newest first (tap a page to write on it, long-press for
//          share with the teacher / delete), then "اكتب ملاحظة" and "اكتب بإصبعك"
//   edit   the segmented pill بالكيبورد · بإصبعك أو القلم, the tools, the sheet, and the footer رجوع للدفتر · احفظ
//
// Kill switch `course.notebook` (also a 403 feature_disabled from the server: the panel draws nothing).
// Motion: the sheet flips in (M1), the sticky note slaps on (M4), buttons jelly (M9, in AppButton).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/notebook/notebook_api.dart';
import 'package:flutter_education_app/features/notebook/notebook_editor.dart';
import 'package:flutter_education_app/features/notebook/notebook_models.dart';
import 'package:flutter_education_app/features/notebook/notebook_paper.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

/// The notebook's kill switch.
const String kNotebookFeatureKey = 'course.notebook';

enum NotebookMode { view, type, pen }

/// The caption of a page: its title, else when it was written ("اليوم، ٧:٤٥ م" / a date).
String notebookCaption(NotePage p, {DateTime? now}) {
  if (p.title.trim().isNotEmpty) return p.title.trim();
  final at = p.updatedAt ?? p.createdAt;
  if (at == null) return notebookTodayCaption();
  final n = AppTime.toZone(now ?? DateTime.now().toUtc());
  final w = AppTime.toZone(at);
  if (w.year == n.year && w.month == n.month && w.day == n.day) return notebookTodayCaption(at);
  return AppTime.date(at, pattern: 'EEEE d MMM');
}

/// "اليوم، ٧:٤٥ م" for [at] (default now).
String notebookTodayCaption([DateTime? at]) =>
    'sb_nb_today_at'.tr.replaceAll('{time}', AppTime.time(at ?? DateTime.now().toUtc()));

class NotebookPanel extends StatelessWidget {
  const NotebookPanel({
    super.key,
    required this.courseId,
    this.subjectId,
    this.lessonId,
    required this.subjectTitle,
    this.initialMode = NotebookMode.view,
    this.api,
  });

  final int courseId;
  final int? subjectId;

  /// The lesson open when the panel was opened: a new page is filed under it.
  final int? lessonId;
  final String subjectTitle;

  /// Opens straight in a writing mode (tests, goldens, a "write" shortcut).
  final NotebookMode initialMode;
  final NotebookApi? api;

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: kNotebookFeatureKey,
    child: NotebookPanelBody(
      courseId: courseId,
      subjectId: subjectId,
      lessonId: lessonId,
      subjectTitle: subjectTitle,
      initialMode: initialMode,
      api: api ?? NotebookApi(),
    ),
  );
}

class NotebookPanelBody extends StatefulWidget {
  const NotebookPanelBody({
    super.key,
    required this.courseId,
    this.subjectId,
    this.lessonId,
    required this.subjectTitle,
    required this.initialMode,
    required this.api,
  });

  final int courseId;
  final int? subjectId, lessonId;
  final String subjectTitle;
  final NotebookMode initialMode;
  final NotebookApi api;

  @override
  State<NotebookPanelBody> createState() => _NotebookPanelBodyState();
}

class _NotebookPanelBodyState extends State<NotebookPanelBody> {
  late NotebookMode _mode = widget.initialMode;

  List<NotePage> _pages = [];
  bool _loading = true, _more = false, _loadingMore = false, _off = false, _saving = false;
  Object? _error;

  /// The page being written (id 0 = new).
  NotePage? _draft;
  List<NoteBlock> _blocks = [];
  NoteInk? _ink;
  NoteBlockKind _kind = NoteBlockKind.paragraph;
  final _line = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != NotebookMode.view) _startDraft(null);
    _load();
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.pages(courseId: widget.courseId);
      if (!mounted) return;
      setState(() {
        _pages = r.items.where((p) => !p.deleted).toList();
        _more = r.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _off = notebookDisabled(e);
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _pages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final r = await widget.api.pages(courseId: widget.courseId, after: _pages.last);
      if (!mounted) return;
      setState(() {
        _pages = [..._pages, ...r.items.where((p) => !p.deleted)];
        _more = r.hasMore;
      });
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _startDraft(NotePage? page) {
    _draft = page ??
        NotePage(
          id: 0,
          clientId: newNoteClientId(),
          courseId: widget.courseId,
          subjectId: widget.subjectId,
          lessonId: widget.lessonId,
        );
    _blocks = [...?page?.blocks];
    _ink = page?.ink;
    _kind = NoteBlockKind.paragraph;
    _line.clear();
    _dirty = false;
  }

  void _write(NotebookMode mode, [NotePage? page]) => setState(() {
    _startDraft(page);
    _mode = mode;
  });

  List<NoteBlock> get _blocksWithLine {
    final text = _line.text.trim();
    return text.isEmpty ? _blocks : [..._blocks, NoteBlock(_kind, text)];
  }

  Future<void> _back() async {
    if (_dirty || _line.text.trim().isNotEmpty) {
      final leave = await appConfirm(context, message: 'sb_nb_discard'.tr, confirmLabel: 'sb_nb_back'.tr);
      if (!leave || !mounted) return;
    }
    setState(() => _mode = NotebookMode.view);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final page = draft.copyWith(blocks: _blocksWithLine, ink: _ink, clearInk: _ink == null);
    if (page.isEmpty) {
      setState(() => _mode = NotebookMode.view);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.api.save(page);
      if (!mounted) return;
      setState(() {
        _pages = [saved, ..._pages.where((p) => p.id != saved.id)];
        _mode = NotebookMode.view;
        _dirty = false;
      });
      showAppNotice('sb_nb_saved'.tr);
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pageActions(NotePage p) async {
    await showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(
        title: notebookCaption(p),
        children: [
          AppTile(
            icon: p.shared ? Icons.visibility_off_rounded : Icons.ios_share_rounded,
            title: (p.shared ? 'sb_nb_unshare' : 'sb_nb_share_teacher').tr,
            subtitle: p.shared ? 'sb_nb_shared'.tr : null,
            onTap: () {
              Navigator.of(ctx).pop();
              _share(p);
            },
          ),
          const SizedBox(height: AppSpace.xs),
          AppTile(
            icon: Icons.delete_outline_rounded,
            title: 'sb_nb_delete'.tr,
            onTap: () {
              Navigator.of(ctx).pop();
              _delete(p);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _share(NotePage p) async {
    try {
      final r = await widget.api.share(p.id, shared: !p.shared);
      if (!mounted) return;
      setState(() => _pages = [for (final x in _pages) x.id == r.id ? r : x]);
      showAppNotice((r.shared ? 'sb_nb_shared' : 'sb_nb_unshared').tr);
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
  }

  Future<void> _delete(NotePage p) async {
    if (!await appConfirm(context, message: 'sb_nb_delete_q'.tr, danger: true, confirmLabel: 'sb_nb_delete'.tr)) return;
    try {
      await widget.api.delete(p.id);
      if (!mounted) return;
      setState(() => _pages = _pages.where((x) => x.id != p.id).toList());
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_off) return const SizedBox.shrink();
    return _mode == NotebookMode.view ? _view(context) : _edit(context);
  }

  static const _pad = EdgeInsets.all(AppSpace.md);

  Widget _view(BuildContext context) {
    if (_loading) {
      return const SingleChildScrollView(
        padding: _pad,
        child: NotebookPaper(child: AppListSkeleton(items: 4)),
      );
    }
    if (_error != null) return Center(child: AppErrorState(message: appErrorMessage(_error), onRetry: _load));
    if (_pages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: _pad,
          child: AppEmpty(
            icon: Icons.edit_note_rounded,
            title: 'sb_nb_empty_title'.tr,
            message: 'sb_nb_empty_msg'.tr,
            actionLabel: 'sb_nb_write_note'.tr,
            onAction: () => _write(NotebookMode.type),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: _pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFlipIn(
            group: 'notebook',
            child: NotebookPaper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, p) in _pages.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpace.sm),
                    NotebookPageView(
                      page: p,
                      index: i,
                      caption: notebookCaption(p),
                      onTap: () => _write(p.ink != null && p.blocks.isEmpty ? NotebookMode.pen : NotebookMode.type, p),
                      onLongPress: () => _pageActions(p),
                    ),
                  ],
                  if (_more)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppButton.ghost(
                        label: 'sb_nb_more'.tr,
                        busy: _loadingMore,
                        onPressed: _loadMore,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          NotebookWriteButtons(
            onType: () => _write(NotebookMode.type),
            onPen: () => _write(NotebookMode.pen),
          ),
        ],
      ),
    );
  }

  Widget _edit(BuildContext context) {
    final caption = _draft == null ? notebookTodayCaption() : notebookCaption(_draft!);
    final pen = _mode == NotebookMode.pen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: _pad,
            physics: pen ? const ClampingScrollPhysics() : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTabs(
                  expand: true,
                  index: pen ? 1 : 0,
                  items: [AppTabItem('sb_nb_mode_type'.tr), AppTabItem('sb_nb_mode_pen'.tr)],
                  onChanged: (i) => setState(() {
                    // the typed line in progress joins the page before the canvas takes over
                    if (i == 1 && _line.text.trim().isNotEmpty) {
                      _blocks = _blocksWithLine;
                      _line.clear();
                    }
                    _mode = i == 1 ? NotebookMode.pen : NotebookMode.type;
                  }),
                ),
                const SizedBox(height: AppSpace.md),
                if (pen)
                  NotebookPenEditor(
                    caption: caption,
                    blocks: _blocks,
                    ink: _ink,
                    onInk: (ink) => setState(() {
                      _ink = ink;
                      _dirty = true;
                    }),
                  )
                else
                  NotebookTypedEditor(
                    caption: caption,
                    blocks: _blocks,
                    controller: _line,
                    kind: _kind,
                    onKind: (k) => setState(() => _kind = k),
                    onBlocks: (b) => setState(() {
                      _blocks = b;
                      _dirty = true;
                    }),
                  ),
              ],
            ),
          ),
        ),
        SubjectPanelFooter(
          children: [
            Expanded(child: AppButton.secondary(label: 'sb_nb_back'.tr, expand: true, onPressed: _saving ? null : _back)),
            AppButton.primary(label: 'sb_nb_save'.tr, busy: _saving, onPressed: _save),
          ],
        ),
      ],
    );
  }
}

/// "اكتب ملاحظة" (a dashed paper button) and "اكتب بإصبعك" (the area's tint, a pen icon), side by side.
class NotebookWriteButtons extends StatelessWidget {
  const NotebookWriteButtons({super.key, required this.onType, required this.onPen});

  final VoidCallback onType, onPen;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: CustomPaint(
          foregroundPainter: _DashedPill(color: AppAreaScope.of(context).a.withValues(alpha: 0.6)),
          child: AppButton.secondary(label: 'sb_nb_write_note'.tr, expand: true, onPressed: onType),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: AppButton.tonal(label: 'sb_nb_write_finger'.tr, icon: Icons.edit_outlined, expand: true, onPressed: onPen),
      ),
    ],
  );
}

/// The dashed edge of "اكتب ملاحظة" (`pv-add`), over the paper button's own edge.
class _DashedPill extends CustomPainter {
  _DashedPill({required this.color});

  final Color color;

  static const double _dash = 6, _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pill = rect.deflate(AppBorder.strong / 2);
    final path = Path()..addRRect(RRect.fromRectXY(pill, pill.height / 2, pill.height / 2));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.strong;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += _dash + _gap) {
        canvas.drawPath(m.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill old) => old.color != color;
}

/// For callers that want the error code of a notebook call without importing the client.
String? notebookErrorCode(Object e) => ApiException.from(e).code;
