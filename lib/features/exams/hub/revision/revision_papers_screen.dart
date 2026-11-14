// The session's papers, one after another: arrows back and forward (keyboard too), a list beside the paper on a wide
// screen, every paper whether decided or not, and the decisions for the ones still open.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_rows.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart' show GradeStudent;
import 'package:flutter_education_app/features/exams/hub/revision/revision_api.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_history_screen.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_models.dart';

class RevisionPapersScreen extends StatefulWidget {
  const RevisionPapersScreen({super.key, required this.sessionId, this.api, this.initialRowId});
  final int sessionId;
  final RevisionApi? api;
  final int? initialRowId;

  @override
  State<RevisionPapersScreen> createState() => _RevisionPapersScreenState();
}

class _RevisionPapersScreenState extends State<RevisionPapersScreen> {
  late final RevisionApi _api = widget.api ?? RevisionApi();
  EventOrPoll? _watch;
  RevisionSession? _info;
  List<RevisionRow> _rows = const [];
  int _index = 0;
  bool _loading = true, _busy = false;
  List<GradeStudent>? _students;

  @override
  void initState() {
    super.initState();
    _watch = EventOrPoll(kind: kMarkSessionJobKind, id: '${widget.sessionId}', every: const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20), poll: () => _load(silent: true))..start();
    _load();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false, int? keepRowId}) async {
    final keep = keepRowId ?? (_rows.isNotEmpty && _index < _rows.length ? _rows[_index].id : widget.initialRowId);
    if (!silent) setState(() => _loading = true);
    final info = await _api.session(widget.sessionId);
    final rows = await _api.papers(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _info = info ?? _info;
      if (rows != null) {
        _rows = rows;
        final i = keep == null ? -1 : rows.indexWhere((r) => r.id == keep);
        _index = i >= 0 ? i : (_index < rows.length ? _index : (rows.isEmpty ? 0 : rows.length - 1));
      }
    });
  }

  void _go(int d) {
    if (_rows.isEmpty) return;
    setState(() => _index = (_index + d).clamp(0, _rows.length - 1));
  }

  Future<Uint8List?> _crop(String url) => _api.sessions.image(url);

  Future<void> _decide(RevisionRow row, String action, {int? studentId, Map<String, double>? marks, double? value, String? reason, String? done}) async {
    setState(() => _busy = true);
    final o = await _api.decide(widget.sessionId, row.id, action, studentId: studentId, marks: marks, value: value, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (o.kind) {
      case RevisionDecideKind.ok:
        if (done != null) showAppNotice(done);
      case RevisionDecideKind.valueChanged:
        showAppNotice(t('تغيّرت هذه الدرجة أثناء المراجعة وأصبحت ${markNumberText(o.current)}. راجعها ثم قرّر.', 'This grade changed meanwhile and is now ${markNumberText(o.current)}. Look at it, then decide.'), error: true);
      case RevisionDecideKind.alreadyDecided:
      case RevisionDecideKind.sessionClosed:
      case RevisionDecideKind.error:
        showAppNotice(o.message, error: true);
    }
    await _load(silent: true, keepRowId: row.id);
  }

  Future<void> _apply(RevisionRow r) async {
    final info = _info;
    if (info == null) return;
    final why = await showAppSheet<String>(
      context,
      (ctx) => AppSheetContent(title: t('تحديث النظام', 'Update system'), children: [GradeApplySheet(row: r.row, columnLabel: info.columnLabel, onConfirm: (x) => Navigator.pop(ctx, x))]),
    );
    if (why == null || !mounted) return;
    await _decide(r, 'apply', value: r.row.proposed, reason: why, done: info.excel ? t('حُدّثت الدرجة في نسخة الملف', 'The grade was updated in the sheet copy') : t('كُتبت الدرجة', 'The grade was written'));
  }

  Future<void> _assign(RevisionRow r) async {
    final info = _info;
    if (info == null) return;
    var all = _students;
    if (all == null) {
      setState(() => _busy = true);
      try {
        all = await _api.students(info);
      } catch (_) {
        all = const [];
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _students = all;
      });
    }
    final list = all;
    final picked = await showAppSheet<GradeStudent>(context, (ctx) => AppSheetContent(title: t('تحديد الطالب', 'Assign student'), children: [GradeAssignSheet(students: list, onPick: (s) => Navigator.pop(ctx, s))]));
    if (picked != null && mounted) await _decide(r, 'assign_student', studentId: picked.id);
  }

  Future<void> _fix(RevisionRow r, MarkPart p) async {
    final v = await showAppSheet<double>(context, (ctx) => AppSheetContent(title: t('تصحيح قراءة درجة', 'Fix a misread mark'), children: [GradeFixMarkSheet(part: p, onSave: (x) => Navigator.pop(ctx, x))]));
    if (v != null && mounted) await _decide(r, 'fix_marks', marks: {p.fieldId: v});
  }

  bool _canApply(MarkRow r, MarkSession s) => !r.decided && s.open && r.hasStudent && r.proposed != null && r.marks.every((m) => m.ok) && !r.has('student_twice') && !r.has('mark_above_max');

  Widget _detail(RevisionRow r, RevisionSession info) {
    final s = info.session;
    final open = !r.decided && s.open;
    return GradeRowDetail(
      key: ValueKey('rv.paper.${r.id}.${r.row.status}'),
      row: r.row,
      session: s,
      loadCrop: _crop,
      onApply: _busy || !_canApply(r.row, s) ? null : () => _apply(r),
      onKeep: !_busy && open ? () => _decide(r, 'keep') : null,
      onDismiss: !_busy && open ? () => _decide(r, 'dismiss') : null,
      onRetake: !_busy && open ? () => _decide(r, 'retake') : null,
      onAssign: !_busy && open && !r.row.hasStudent ? () => _assign(r) : null,
      onFix: !_busy && s.open ? (p) => _fix(r, p) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
    return BasePage(
      appBar: ScreenAppBar(title: t('الأوراق', 'Papers'), actions: [
        IconButton(
          tooltip: t('السجل', 'History'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionHistoryScreen(sessionId: widget.sessionId, api: _api))),
          icon: const Icon(Icons.history_rounded),
        ),
      ]),
      child: Builder(builder: (context) {
        if (_loading && info == null) return const AppListSkeleton(items: 6);
        if (_rows.isEmpty) {
          return AppEmpty(icon: Icons.inbox_outlined, title: t('لا أوراق بعد', 'No papers yet'), message: t('تظهر هنا كل ورقة بعد قراءتها.', 'Every paper appears here once it is read.'), actionLabel: t('تحديث', 'Refresh'), onAction: _load);
        }
        if (info == null) return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر فتح الجلسة', 'The session could not be opened'), actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load);
        final r = _rows[_index];
        final bar = RevisionArrowBar(
          index: _index,
          total: _rows.length,
          onPrev: _index > 0 ? () => _go(-1) : null,
          onNext: _index < _rows.length - 1 ? () => _go(1) : null,
        );
        final detail = SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.md), child: _detail(r, info));
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(Directionality.of(context) == TextDirection.rtl ? -1 : 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(Directionality.of(context) == TextDirection.rtl ? 1 : -1),
          },
          child: Focus(
            autofocus: true,
            child: wide
                ? Row(children: [
                    SizedBox(
                      width: 380,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(AppSpace.md),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => AppSpace.gapXs,
                        itemBuilder: (_, i) => GradeRowTile(key: ValueKey('rv.tile.${_rows[i].id}'), row: _rows[i].row, list: _rows[i].list, selected: i == _index, onTap: () => setState(() => _index = i)),
                      ),
                    ),
                    VerticalDivider(width: 1, color: context.colors.divider),
                    Expanded(child: Column(children: [Expanded(child: detail), bar])),
                  ])
                : Column(children: [Expanded(child: detail), bar]),
          ),
        );
      }),
    );
  }
}

/// Back and forward through the session's papers: "Paper 3 of 12" between two arrows.
class RevisionArrowBar extends StatelessWidget {
  const RevisionArrowBar({super.key, required this.index, required this.total, this.onPrev, this.onNext});
  final int index, total;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.divider))),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: Row(children: [
          IconButton(key: const ValueKey('rv.prev'), tooltip: t('السابقة', 'Previous'), constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min), onPressed: onPrev, icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(child: Text(t('الورقة ${index + 1} من $total', 'Paper ${index + 1} of $total'), key: const ValueKey('rv.position'), textAlign: TextAlign.center, style: AppType.label(context))),
          IconButton(key: const ValueKey('rv.next'), tooltip: t('التالية', 'Next'), constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min), onPressed: onNext, icon: const Icon(Icons.arrow_forward_rounded)),
        ]),
      ),
    );
  }
}
