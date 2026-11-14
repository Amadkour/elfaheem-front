// The results of a mark session (contract §5): three lists — Match · Mismatch · Unreadable — with live counts
// (`job_updated {kind: mark_session}`, EventOrPoll as the fallback), a row's detail and the decisions. The system never
// changes a grade by itself: Apply shows old → new and asks, a 409 `value_changed` explains that someone else changed
// the grade meanwhile. Desktop / web keys: J next · K previous · Enter open · A apply · H keep · D dismiss.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_api.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_history_screen.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_models.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_papers_screen.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_run_screen.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_camera.dart' show OmrCamera;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_capture.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_rows.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart';

/// All the students of a course (the Data Lab grid, a page at a time), for "Assign student".
Future<List<GradeStudent>> loadCourseStudents(int courseId) async {
  final api = DataLabApi();
  final out = <GradeStudent>[];
  var skip = 0;
  while (true) {
    final g = await api.grid(courseId, skip: skip, limit: 100, lang: AppConfig.lang);
    for (final r in g.rows) {
      if (r.studentId != null) out.add(GradeStudent(r.studentId!, r.name));
    }
    skip += g.rows.length;
    if (g.rows.isEmpty || skip >= g.total || skip >= 2000) break;
  }
  return out;
}

class GradeReviewScreen extends StatefulWidget {
  const GradeReviewScreen({super.key, required this.sessionId, this.api, this.students, this.studentsLoader, this.camera, this.initialList});

  final int sessionId;
  final MarkSessionsApi? api;

  /// The course's students when the caller already has them; else [studentsLoader] (default: the Data Lab grid).
  final List<GradeStudent>? students;
  final Future<List<GradeStudent>> Function(int courseId)? studentsLoader;
  final OmrCamera Function()? camera;
  final MarkList? initialList;

  @override
  State<GradeReviewScreen> createState() => _GradeReviewScreenState();
}

class _GradeReviewScreenState extends State<GradeReviewScreen> with SingleTickerProviderStateMixin {
  late final MarkSessionsApi _api = widget.api ?? MarkSessionsApi();
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialList?.index ?? 0)..addListener(_tabChanged);
  final _focus = FocusNode(debugLabel: 'grade-review');
  final _scroll = ScrollController();
  EventOrPoll? _watch;

  MarkSession? _session;

  /// The same answer with the source and the sheet; null until it is known.
  RevisionSession? _info;
  late final RevisionApi _revision = RevisionApi();
  bool get _hub => _info?.hubServer ?? false;
  final _rows = <MarkList, List<MarkRow>>{};
  bool _loading = true, _busy = false;
  String? _error;
  int _selected = 0;
  List<GradeStudent>? _students;

  MarkList get _list => MarkList.values[_tabs.index];
  List<MarkRow> get _current => _rows[_list] ?? const [];

  @override
  void initState() {
    super.initState();
    _students = widget.students;
    _watch = EventOrPoll(kind: kMarkSessionJobKind, id: '${widget.sessionId}', every: const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20), poll: () => _load(silent: true))..start();
    _load();
  }

  @override
  void dispose() {
    _watch?.dispose();
    _tabs.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    _selected = 0;
    if (!_rows.containsKey(_list)) _load(silent: true);
    setState(() {});
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final list = _list;
    // an older server treats status=all as a status no row has, so the first read asks the session first
    final s = await _api.get(widget.sessionId);
    final info = s.ok ? RevisionSession.fromJson(s.map) : null;
    final r = await _api.rows(widget.sessionId, list: list, status: (info?.hubServer ?? false) ? 'all' : null);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!s.ok) {
        if (_session == null) _error = s.message;
        return;
      }
      _error = null;
      _session = MarkSession.fromJson(s.map);
      _info = info;
      if (r.ok) {
        final got = [for (final i in (r.map['items'] as List?) ?? const []) if (i is Map) MarkRow.fromJson(Map<String, dynamic>.from(i))];
        // what still needs a decision comes first, in capture order; the decided papers stay, tagged, under it
        _rows[list] = [...got.where((x) => !x.decided), ...got.where((x) => x.decided)];
        if (_selected >= _current.length) _selected = _current.isEmpty ? 0 : _current.length - 1;
      }
    });
  }

  /// Every list may have moved after a decision: reload the open one now and forget the others.
  Future<void> _reloadAfterDecision() async {
    final keep = _list;
    _rows.removeWhere((k, _) => k != keep);
    await _load(silent: true);
  }

  // ── decisions ───────────────────────────────────────────────────────────────────────────────────────────────

  Future<bool> _decide(MarkRow row, String action, {int? studentId, Map<String, double>? marks, double? value, String? reason, bool quiet = false}) async {
    setState(() => _busy = true);
    final r = await _api.decide(widget.sessionId, row.id, action, studentId: studentId, marks: marks, value: value, reason: reason);
    if (!mounted) return false;
    setState(() => _busy = false);
    if (r.ok) {
      if (!quiet) await _reloadAfterDecision();
      return true;
    }
    if (r.status == 409 && r.code == 'value_changed') {
      showAppNotice(t('تغيّرت هذه الدرجة في الدفتر أثناء المراجعة (شخص آخر عدّلها). حدّثنا القائمة — راجع القيمة الجديدة ثم قرّر.',
          'This grade was changed in the gradebook meanwhile (someone else edited it). The list was refreshed — look at the new value, then decide again.'), error: true);
      if (!quiet) await _reloadAfterDecision();
      return false;
    }
    showAppNotice(r.message.isNotEmpty ? r.message : t('تعذّر تنفيذ القرار', 'The decision could not be saved'), error: true);
    return false;
  }

  Future<void> _apply(MarkRow row) async {
    final s = _session;
    if (s == null || row.decided || row.proposed == null || !row.hasStudent) return;
    final reason = await showAppSheet<String>(
      context,
      (ctx) => AppSheetContent(
        title: t('تطبيق التصحيح', 'Apply correction'),
        children: [GradeApplySheet(row: row, columnLabel: revisionColumnLabel(s.columnKey), onConfirm: (why) => Navigator.pop(ctx, why))],
      ),
    );
    if (reason == null || !mounted) return;
    if (await _decide(row, 'apply', value: row.proposed, reason: reason) && mounted) {
      showAppNotice((_info?.excel ?? false) ? t('حُدّثت الدرجة في نسخة الملف', 'The grade was updated in the sheet copy') : t('كُتبت الدرجة في الدفتر', 'The grade was written to the gradebook'));
    }
  }

  Future<void> _keep(MarkRow row) async {
    if (row.decided) return;
    await _decide(row, 'keep');
  }

  Future<void> _dismiss(MarkRow row) async {
    if (row.decided) return;
    await _decide(row, 'dismiss');
  }

  Future<void> _assign(MarkRow row) async {
    final s = _session;
    if (s == null) return;
    var students = _students;
    if (students == null) {
      setState(() => _busy = true);
      try {
        final info = _info;
        students = await (info != null && info.excel ? _revision.students(info) : (widget.studentsLoader ?? loadCourseStudents)(s.courseId));
      } catch (_) {
        students = const [];
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _students = students;
      });
    }
    final all = students;
    final picked = await showAppSheet<GradeStudent>(
      context,
      (ctx) => AppSheetContent(title: t('تحديد الطالب', 'Assign student'), children: [GradeAssignSheet(students: all, onPick: (st) => Navigator.pop(ctx, st))]),
    );
    if (picked == null || !mounted) return;
    await _decide(row, 'assign_student', studentId: picked.id);
  }

  Future<void> _fix(MarkRow row, MarkPart part) async {
    final v = await showAppSheet<double>(
      context,
      (ctx) => AppSheetContent(title: t('تصحيح قراءة درجة', 'Fix a misread mark'), children: [GradeFixMarkSheet(part: part, onSave: (x) => Navigator.pop(ctx, x))]),
    );
    if (v == null || !mounted) return;
    await _decide(row, 'fix_marks', marks: {part.fieldId: v});
  }

  /// Rows of the mismatch list an import can take without a second look.
  List<MarkRow> get _cleanRows => [for (final r in _rows[MarkList.mismatch] ?? const <MarkRow>[]) if (!r.decided && r.clean && r.proposed != null) r];

  Future<void> _applyAllClean() async {
    final rows = _cleanRows;
    if (rows.isEmpty) return;
    final ok = await appConfirm(
      context,
      message: t('سيتم تطبيق ${rows.length} درجة نظيفة (طالب معروف، كل الدرجات مقروءة) وكتابتها في الدفتر. هل تتابع؟',
          'This writes ${rows.length} clean mark(s) (known student, every mark read) to the gradebook. Continue?'),
      confirmLabel: t('تطبيق الكل (${rows.length})', 'Apply all (${rows.length})'),
    );
    if (!ok || !mounted) return;
    var done = 0, changed = 0;
    for (final r in rows) {
      if (!mounted) return;
      final okOne = await _decide(r, 'apply', value: r.proposed, reason: t('استيراد جماعي', 'Bulk import'), quiet: true);
      if (okOne) {
        done++;
      } else {
        changed++;
      }
    }
    if (!mounted) return;
    showAppNotice(changed == 0 ? t('طُبّقت $done درجة', '$done grade(s) applied') : t('طُبّقت $done وتعذّرت $changed — راجعها', '$done applied, $changed need a look'), error: changed > 0);
    await _reloadAfterDecision();
  }

  Future<void> _downloadSheet() async {
    final info = _info;
    if (info != null) await downloadCorrectedSheet(_revision, info);
  }

  Future<void> _close() async {
    final ok = await appConfirm(context,
        message: t('بعد الإغلاق لا تُضاف أوراق جديدة ولا تُتخذ قرارات. هل تغلق الجلسة؟', 'After closing, no more sheets are added and no decisions are made. Close the session?'),
        confirmLabel: t('إغلاق الجلسة', 'Close session'));
    if (!ok || !mounted) return;
    final r = await _api.close(widget.sessionId);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(r.message, error: true);
      return;
    }
    showAppNotice(t('أُغلقت الجلسة', 'The session is closed'));
    await _load(silent: true);
  }

  void _scanMore() {
    final s = _session;
    if (s == null) return;
    final info = _info;
    if (info != null && _hub) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionRunScreen(info: info, api: _revision, camera: widget.camera, popOnFinish: true))).then((_) {
        if (mounted) _load(silent: true);
      });
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GradeCaptureScreen(session: s, api: _api, camera: widget.camera, onDone: (ctx) => Navigator.of(ctx).maybePop()),
    ));
  }

  // ── detail ──────────────────────────────────────────────────────────────────────────────────────────────────

  bool _canApply(MarkRow r) => !r.decided && (_session?.open ?? false) && r.hasStudent && r.proposed != null && r.marks.every((m) => m.ok) && !r.has('student_twice') && !r.has('mark_above_max');

  Future<void> _open(MarkRow row) async {
    final s = _session;
    if (s == null) return;
    if (_hub) {
      // the paper's own page: arrows through the whole session, decisions and the decided papers too
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionPapersScreen(sessionId: s.id, api: _revision, initialRowId: row.id)));
      if (mounted) await _reloadAfterDecision();
      return;
    }
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(tone: AppTone.info, icon: Icons.info_outline_rounded, 
        title: t('تفاصيل الورقة', 'Sheet details'),
        children: [
          GradeRowDetail(
            row: row,
            session: s,
            loadCrop: _api.image,
            onApply: _canApply(row) ? () { Navigator.pop(ctx); _apply(row); } : null,
            onKeep: (!row.decided && s.open && row.recorded != null) ? () { Navigator.pop(ctx); _keep(row); } : null,
            onDismiss: (!row.decided && s.open) ? () { Navigator.pop(ctx); _dismiss(row); } : null,
            onAssign: (!row.decided && s.open) ? () { Navigator.pop(ctx); _assign(row); } : null,
            onFix: s.open ? (p) { Navigator.pop(ctx); _fix(row, p); } : null,
          ),
        ],
      ),
    );
  }

  // ── keyboard ────────────────────────────────────────────────────────────────────────────────────────────────

  void _move(int d) {
    if (_current.isEmpty) return;
    final n = (_selected + d).clamp(0, _current.length - 1);
    setState(() => _selected = n);
    if (_scroll.hasClients) {
      final target = (n * 92.0 - 120).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: AppMotion.of(context).base, curve: Curves.easeOut);
    }
  }

  MarkRow? get _sel => _selected < _current.length ? _current[_selected] : null;

  Map<ShortcutActivator, VoidCallback> get _keys => {
        const SingleActivator(gradeKeyNext): () => _move(1),
        const SingleActivator(gradeKeyPrev): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          final r = _sel;
          if (r != null) _open(r);
        },
        const SingleActivator(gradeKeyApply): () {
          final r = _sel;
          if (r != null && _canApply(r)) _apply(r);
        },
        const SingleActivator(gradeKeyKeep): () {
          final r = _sel;
          if (r != null && r.recorded != null && (_session?.open ?? false)) _keep(r);
        },
        const SingleActivator(gradeKeyDismiss): () {
          final r = _sel;
          if (r != null && (_session?.open ?? false)) _dismiss(r);
        },
      };

  // ── build ───────────────────────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _session;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(
        title: s == null || s.mode == MarkMode.review ? t('مراجعة الدرجات', 'Review grades') : t('استيراد الدرجات', 'Import marks'),
        actions: [
          if (s != null && s.open) IconButton(tooltip: t('تصوير المزيد', 'Scan more'), onPressed: _scanMore, icon: const Icon(Icons.photo_camera_outlined)),
          if (_hub) IconButton(tooltip: t('السجل', 'History'), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionHistoryScreen(sessionId: widget.sessionId, api: _revision))), icon: const Icon(Icons.history_rounded)),
          if (_info?.excel ?? false) IconButton(tooltip: t('تنزيل الملف المصحّح', 'Download the corrected sheet'), onPressed: _downloadSheet, icon: const Icon(Icons.download_rounded)),
          IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: () => _load(silent: true), icon: const Icon(Icons.refresh_rounded)),
          if (s != null && s.open) IconButton(tooltip: t('إغلاق الجلسة', 'Close session'), onPressed: _close, icon: const Icon(Icons.lock_outline_rounded)),
        ],
        bottom: s == null
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  _tab(Icons.check_circle_outline_rounded, t('مطابقة', 'Match'), s.counts.match),
                  _tab(Icons.compare_arrows_rounded, t('غير مطابقة', 'Mismatch'), s.counts.mismatch),
                  _tab(Icons.warning_amber_rounded, t('غير مقروءة', 'Unreadable'), s.counts.unreadable),
                ],
              ),
      ),
      body: _body(s, wide),
    );
  }

  Tab _tab(IconData icon, String label, int n) => Tab(height: AppTouch.min, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: AppIconSize.sm), const SizedBox(width: AppSpace.xxs), Text('$label ($n)')]));

  Widget _body(MarkSession? s, bool wide) {
    final c = context.colors;
    if (_loading && s == null) return const AppListSkeleton();
    if (s == null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر فتح الجلسة', 'The session could not be opened'), message: _error, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: () => _load());
    }
    final rows = _current;
    final clean = _list == MarkList.mismatch && s.mode == MarkMode.import && s.open ? _cleanRows : const <MarkRow>[];
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.content.max),
            child: Column(children: [
              _Summary(session: s),
              if (clean.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton.primary(
                      key: const ValueKey('gr.bulk'),
                      onPressed: _busy ? null : _applyAllClean,
                      icon: Icons.done_all_rounded,
                      label: t('تطبيق كل الدرجات النظيفة (${clean.length})', 'Apply all clean marks (${clean.length})'),
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(minHeight: AppBorder.focus),
              Expanded(
                child: rows.isEmpty
                    ? (_loading ? const AppListSkeleton() : AppEmpty(icon: Icons.inbox_outlined, title: _emptyText(s), message: s.counts.pending > 0 ? t('${s.counts.pending} ورقة قيد القراءة', '${s.counts.pending} sheet(s) still being read') : null))
                    : ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
                        itemBuilder: (_, i) => GradeRowTile(key: ValueKey('gr.row.${rows[i].id}'), row: rows[i], list: _list, selected: i == _selected && (wide || kIsWeb), onTap: () {
                          setState(() => _selected = i);
                          _open(rows[i]);
                        }),
                      ),
              ),
              if (wide) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(gradeShortcutsText(), style: AppType.meta(context).copyWith(color: c.textLight))),
            ]),
          ),
        ),
      ),
    );
  }

  String _emptyText(MarkSession s) => switch (_list) {
        MarkList.match => t('لا أوراق مطابقة بعد', 'No matching sheets yet'),
        MarkList.mismatch => t('لا فروق', 'No mismatches'),
        MarkList.unreadable => t('لا أوراق غير مقروءة', 'No unreadable sheets'),
      };
}

/// Progress and decisions at a glance: "9 read · 2 waiting · 4 applied · 1 kept" on a block in the colour of where the
/// session stands — sky while sheets are still being read, peach while differences wait for a person, emerald once
/// nothing is left, paper when the session is closed.
class _Summary extends StatelessWidget {
  const _Summary({required this.session});
  final MarkSession session;

  AppBlockTone get _tone {
    final k = session.counts;
    if (!session.open) return AppBlockTone.paper;
    if (k.pending > 0) return AppBlockTone.sky;
    if (k.mismatch > 0 || k.unreadable > 0) return AppBlockTone.peach;
    return AppBlockTone.emerald;
  }

  @override
  Widget build(BuildContext context) {
    final k = session.counts;
    final total = k.read + k.pending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
      child: AppBlock(
        tone: _tone,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${gradeCounterText(total, k.read, k.pending)} · ${t('${k.applied} طُبّقت', '${k.applied} applied')} · ${t('${k.kept} أُبقيت', '${k.kept} kept')}',
              key: const ValueKey('gr.summary'),
              style: AppType.bodyStrong(context).copyWith(color: b.ink, height: 1.35),
            ),
            if (session.converts)
              Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(gradeConversionText(session.paperMax, session.columnMax), style: AppType.meta(context).copyWith(color: b.muted))),
            if (k.pending > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(value: total == 0 ? null : k.read / total, minHeight: AppSpace.xxs, color: b.accentInk(context.colors.primary), backgroundColor: b.ink.withValues(alpha: .10)),
                ),
              ),
            if (!session.open) ...[
              AppSpace.gapXs,
              AppStatusBadge(label: t('الجلسة مغلقة', 'Session closed'), icon: Icons.lock_outline_rounded, dense: true),
            ],
          ]);
        }),
      ),
    );
  }
}
