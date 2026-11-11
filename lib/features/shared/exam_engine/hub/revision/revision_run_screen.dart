// The run of a grade revision: the camera loop stays open and the results come back on their own time.
//
// The calm rule (see [RevisionFlow]): a match is one quiet line, with a light haptic where there is one, and the camera
// goes straight on. A paper that needs the teacher waits in a queue and is shown ONE at a time, over its own frozen scan,
// only while the camera is between papers; a result never appears while a shot is being taken or a paper is being held
// steady, and two never stack. "2 waiting for you" lets the teacher open them sooner; "Decide later" keeps a paper open
// on the server and offers it again on the summary.
//
// Each page is read once (`GET …/pages/{id}/row`) when its `job_updated` arrives; JobWatch's slow tick is the fallback
// for a dropped stream, nothing polls on a timer of its own.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart' show LiveEvent;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../marks/mark_sessions_api.dart';
import '../../marks/review/grade_capture_logic.dart';
import '../../marks/review/grade_review_capture.dart';
import '../../marks/review/grade_review_rows.dart' show GradeAssignSheet, GradeFixMarkSheet, gradeRowName, gradeStatusText;
import '../../marks/review/grade_review_screen.dart' show GradeReviewScreen;
import '../../marks/review/grade_review_start.dart' show GradeStudent;
import '../../paper/scan/omr_camera.dart' show OmrCamera;
import 'revision_api.dart';
import 'revision_history_screen.dart';
import 'revision_models.dart';
import 'revision_papers_screen.dart';
import 'revision_result_panel.dart';
import 'revision_wizard_steps.dart' show revisionAccent;

class RevisionRunScreen extends StatefulWidget {
  const RevisionRunScreen({super.key, required this.info, this.api, this.camera, this.popOnFinish = false});

  final RevisionSession info;
  final RevisionApi? api;
  final OmrCamera Function()? camera;

  /// Reached from the results screen: Finish goes back to it instead of the summary.
  final bool popOnFinish;

  @override
  State<RevisionRunScreen> createState() => _RevisionRunScreenState();
}

class _RevisionRunScreenState extends State<RevisionRunScreen> {
  late final RevisionApi _api = widget.api ?? RevisionApi();
  final _flow = RevisionFlow();
  final _bridge = GradeCaptureBridge();
  late final JobWatch _watch;

  List<RevisionRow> _papers = const [];
  int _cursor = -1;
  bool _busy = false, _disposed = false;
  ({String name, String degree})? _quiet;
  Timer? _quietTimer;
  String? _retakeTip;
  List<GradeStudent>? _students;
  Future<List<GradeStudent>>? _studentsLoad;
  int? _choosing;

  /// A page's event can overtake the answer to the upload that created it.
  final _early = <int>{};

  int get _sid => widget.info.id;

  @override
  void initState() {
    super.initState();
    _bridge.onQueued = (page, photo) {
      _flow.shot(page, photo);
      if (_early.remove(page)) unawaited(_read(page));
      if (mounted) setState(() => _retakeTip = null);
    };
    _bridge.addListener(_maybePresent);
    _watch = JobWatch(kind: kMarkSessionJobKind, id: '$_sid', onEvent: _onEvent);
    unawaited(_fallbackLoop());
    unawaited(_loadPapers());
  }

  @override
  void dispose() {
    _disposed = true;
    _quietTimer?.cancel();
    _watch.dispose();
    _bridge.removeListener(_maybePresent);
    _bridge.dispose();
    super.dispose();
  }

  Future<void> _loadPapers() async {
    final rows = await _api.papers(_sid);
    if (!mounted || rows == null) return;
    setState(() {
      _papers = rows;
      if (_papers.isNotEmpty) _cursor = _papers.length - 1;
    });
  }

  void _onEvent(LiveEvent e) {
    final page = int.tryParse('${e.data['page_id'] ?? ''}');
    if (page == null) return;
    if (_flow.waiting.contains(page)) {
      unawaited(_read(page));
    } else {
      _early.add(page);
    }
  }

  /// Only when the stream is down or has been quiet: the oldest papers still waiting, three at most.
  Future<void> _fallbackLoop() async {
    while (!_disposed) {
      final e = await _watch.next(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20));
      if (_disposed) return;
      if (e != null) continue; // [_onEvent] already read it
      for (final page in _flow.waiting.take(3)) {
        await _read(page);
        if (_disposed) return;
      }
    }
  }

  Future<void> _read(int pageId) async {
    if (!_flow.waiting.contains(pageId)) return;
    final read = await _api.pageRow(_sid, pageId);
    if (!mounted || read == null) return;
    final kind = _flow.take(pageId, read);
    if (kind == RevisionReadKind.stillReading) return;
    final row = read.row;
    if (row != null) _papers = upsertRow(_papers, row);
    if (kind == RevisionReadKind.matched && row != null) _showQuiet(row);
    if (row != null && row.needsStudent) unawaited(_loadStudents());
    setState(() => _cursor = _papers.isEmpty ? -1 : _papers.length - 1);
    _maybePresent();
  }

  void _showQuiet(RevisionRow r) {
    unawaited(HapticFeedback.selectionClick());
    _quietTimer?.cancel();
    _quiet = (name: gradeRowName(r.row), degree: markNumberText(r.row.proposed));
    _quietTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _quiet = null);
    });
  }

  void _maybePresent() {
    if (!mounted) return;
    if (_flow.canPresent(cameraBusy: _bridge.busy)) {
      setState(() => _flow.showing = true);
      _bridge.hold = true;
    }
  }

  void _openNow() {
    if (_flow.current == null || _flow.showing) return;
    setState(() => _flow.showing = true);
    _bridge.hold = true;
  }

  /// The paper on screen is finished with: the hold goes, the next one may come.
  void _next() {
    _bridge.hold = false;
    setState(() {});
    _maybePresent();
  }

  Future<void> _decide(String action, {int? studentId, Map<String, double>? marks, double? value}) async {
    final a = _flow.current;
    final row = a?.row;
    if (a == null || row == null) return;
    setState(() => _busy = true);
    final o = await _api.decide(_sid, row.id, action, studentId: studentId, marks: marks, value: value);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (o.kind) {
      case RevisionDecideKind.ok:
        final got = o.row;
        if (got != null) _papers = upsertRow(_papers, got);
        if (action == 'assign_student' || action == 'fix_marks') {
          a.changedTo = null;
          if (got != null && _flow.update(got)) {
            _showQuiet(got);
            _next();
          } else {
            setState(() {});
          }
          return;
        }
        if (action == 'retake') {
          _retakeTip = t('أعد تصوير ورقة ${gradeRowName(row.row)}', "Scan ${gradeRowName(row.row)}'s paper again");
          _bridge.rearm();
        } else if (action == 'apply') {
          unawaited(HapticFeedback.selectionClick());
          showAppNotice(widget.info.excel ? t('حُدّثت الدرجة في نسخة الملف', 'The grade was updated in the sheet copy') : t('كُتبت الدرجة', 'The grade was written'));
        }
        _flow.removeCurrent();
        _next();
      case RevisionDecideKind.valueChanged:
        // the server has already re-read the row: show the new value and ask again
        final fresh = await _api.pageRow(_sid, a.pageId);
        if (!mounted) return;
        a.changedTo = o.current;
        final r = fresh?.row;
        if (r != null && _flow.update(r)) {
          showAppNotice(t('أصبحت الدرجة المسجّلة مطابقة للورقة، لا حاجة لقرار', 'The recorded grade now matches the paper: nothing to decide'));
          _next();
        } else {
          setState(() {});
        }
      case RevisionDecideKind.alreadyDecided:
        showAppNotice(o.message);
        _flow.removeCurrent();
        _next();
      case RevisionDecideKind.sessionClosed:
        showAppNotice(o.message, error: true);
        _flow.removeCurrent();
        _next();
      case RevisionDecideKind.error:
        showAppNotice(o.message, error: true);
    }
  }

  void _later() {
    _flow.deferCurrent();
    _next();
  }

  /// The reader refused the page: nothing to decide on the server, only the next attempt.
  void _rejectedRetake() {
    _bridge.rearm();
    _flow.removeCurrent();
    _next();
  }

  /// The list is read ahead, as soon as a paper needs a student, so "someone else" opens at once.
  Future<List<GradeStudent>> _loadStudents() {
    final have = _students;
    if (have != null) return Future.value(have);
    return _studentsLoad ??= _api.students(widget.info).catchError((Object _) => const <GradeStudent>[]).then((list) {
      _studentsLoad = null;
      if (list.isNotEmpty) _students = list; // an empty answer may be a failed one: asked again next time
      return list;
    });
  }

  Future<void> _choose(int studentId) async {
    setState(() => _choosing = studentId);
    await _decide('assign_student', studentId: studentId);
    if (mounted) setState(() => _choosing = null);
  }

  /// Students who already have a paper in this session.
  Set<int> get _taken => {for (final r in _papers) if (r.row.studentId != null && r.row.status != 'dismissed') r.row.studentId!};

  Future<void> _assign() async {
    var list = _students;
    if (list == null) {
      setState(() => _busy = true);
      list = await _loadStudents();
      if (!mounted) return;
      setState(() => _busy = false);
    }
    final all = list;
    final picked = await showAppSheet<GradeStudent>(context, (ctx) => AppSheetContent(title: t('تحديد الطالب', 'Assign student'), children: [GradeAssignSheet(students: all, taken: _taken, onPick: (s) => Navigator.pop(ctx, s))]));
    if (picked != null && mounted) await _choose(picked.id);
  }

  Future<void> _fix(MarkPart p) async {
    final v = await showAppSheet<double>(context, (ctx) => AppSheetContent(title: t('تصحيح قراءة درجة', 'Fix a misread mark'), children: [GradeFixMarkSheet(part: p, onSave: (x) => Navigator.pop(ctx, x))]));
    if (v != null && mounted) await _decide('fix_marks', marks: {p.fieldId: v});
  }

  void _finish(BuildContext ctx) {
    if (widget.popOnFinish) {
      Navigator.of(ctx).maybePop();
      return;
    }
    Navigator.of(ctx).pushReplacement(MaterialPageRoute<void>(builder: (_) => RevisionFinishScreen(sessionId: _sid, api: _api, camera: widget.camera, later: _flow.later.length)));
  }

  void _openPaper([int? rowId]) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionPapersScreen(sessionId: _sid, api: _api, initialRowId: rowId)));
  }

  Widget _top() {
    final c = context.colors;
    final q = _quiet;
    final waiting = _flow.queue.length;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedSwitcher(
        duration: AppMotion.of(context).base,
        child: q == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey('rv.quiet.${q.name}'),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                decoration: BoxDecoration(color: c.heroShade.withValues(alpha: .8), borderRadius: BorderRadius.circular(AppRadius.hero)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, size: AppIconSize.xs, color: c.success),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(child: Text('${q.name} · ${q.degree}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600))),
                ]),
              ),
      ),
      if (_retakeTip != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(_retakeTip!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
      ],
      if (waiting > 0 && !_flow.showing)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: ActionChip(
            key: const ValueKey('rv.waiting'),
            avatar: Icon(Icons.notifications_active_outlined, size: AppIconSize.xs, color: c.warning),
            label: Text(countText(waiting, ar1: 'ورقة تنتظرك', ar2: 'ورقتان تنتظرانك', arFew: '$waiting أوراق تنتظرك', arMany: '$waiting ورقة تنتظرك', en1: '1 waiting for you', en: '$waiting waiting for you'), overflow: TextOverflow.ellipsis),
            onPressed: _openNow,
          ),
        ),
    ]);
  }

  Widget? _bottom() {
    final c = context.colors;
    if (_papers.isEmpty) return null;
    final i = _cursor.clamp(0, _papers.length - 1);
    final r = _papers[i];
    final status = r.decided ? gradeStatusText(r.row.status) : r.needsStudent ? t('اختر الطالب', 'Choose the student') : switch (r.list) { MarkList.match => t('مطابقة', 'Match'), MarkList.mismatch => t('تختلف', 'Differs'), MarkList.unreadable => t('غير مقروءة', 'Unreadable') };
    Widget arrow(IconData icon, String key, String tip, VoidCallback? onTap) => IconButton(
          key: ValueKey(key),
          tooltip: tip,
          color: c.onHero,
          disabledColor: c.onHeroMuted,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: onTap,
          icon: Icon(icon),
        );
    return Container(
      key: const ValueKey('rv.strip'),
      decoration: BoxDecoration(color: c.heroShade.withValues(alpha: .8), borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(children: [
        arrow(Icons.arrow_back_rounded, 'rv.strip.prev', t('الورقة السابقة', 'Previous paper'), i > 0 ? () => setState(() => _cursor = i - 1) : null),
        Expanded(
          child: InkWell(
            onTap: () => _openPaper(r.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(gradeRowName(r.row), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
                Text('${i + 1} / ${_papers.length} · $status', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
              ]),
            ),
          ),
        ),
        arrow(Icons.arrow_forward_rounded, 'rv.strip.next', t('الورقة التالية', 'Next paper'), i < _papers.length - 1 ? () => setState(() => _cursor = i + 1) : null),
        arrow(Icons.history_rounded, 'rv.strip.history', t('السجل', 'History'), () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionHistoryScreen(sessionId: _sid, api: _api)))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _flow.current;
    return Stack(fit: StackFit.expand, children: [
      GradeCaptureScreen(
        session: widget.info.session,
        api: _api.sessions,
        camera: widget.camera,
        bridge: _bridge,
        title: t('مراجعة الدرجات', 'Grade revision'),
        finishLabel: t('إنهاء', 'Finish'),
        onDone: _finish,
        topExtra: _top(),
        bottomExtra: _bottom(),
      ),
      AnimatedSwitcher(
        duration: AppMotion.of(context).base,
        child: _flow.showing && a != null
            ? RevisionResultPanel(
                key: ValueKey('rv.panel.${a.pageId}'),
                row: a.row,
                session: widget.info.session,
                photo: a.photo,
                code: a.code,
                message: a.message,
                changedTo: a.changedTo,
                busy: _busy,
                behind: _flow.queue.length - 1,
                loadCrop: _api.sessions.image,
                onUpdate: () => _decide('apply', value: a.row?.row.proposed),
                onIgnore: () => _decide('keep'),
                onRetake: a.rejected ? _rejectedRetake : () => _decide('retake'),
                onLater: _later,
                onAssign: _assign,
                onChoose: _choose,
                pendingStudentId: _choosing,
                onFix: _fix,
              )
            : const SizedBox.shrink(key: ValueKey('rv.panel.none')),
      ),
    ]);
  }
}

/// The end of a run: what happened at a glance, then the one next thing to do.
class RevisionFinishScreen extends StatefulWidget {
  const RevisionFinishScreen({super.key, required this.sessionId, this.api, this.camera, this.later = 0});
  final int sessionId;
  final RevisionApi? api;
  final OmrCamera Function()? camera;

  /// Papers the teacher chose to decide later in this run (still open, also inside the counts).
  final int later;

  @override
  State<RevisionFinishScreen> createState() => _RevisionFinishScreenState();
}

class _RevisionFinishScreenState extends State<RevisionFinishScreen> {
  late final RevisionApi _api = widget.api ?? RevisionApi();
  EventOrPoll? _watch;
  RevisionSession? _info;
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _watch = EventOrPoll(kind: kMarkSessionJobKind, id: '${widget.sessionId}', every: const Duration(seconds: 6), fallbackEvery: const Duration(seconds: 30), poll: _load)..start(pollNow: true);
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _api.session(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _info = s ?? _info;
    });
  }

  Future<void> _download() async {
    final s = _info;
    if (s == null) return;
    setState(() => _saving = true);
    await downloadCorrectedSheet(_api, s);
    if (mounted) setState(() => _saving = false);
  }

  void _review() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GradeReviewScreen(sessionId: widget.sessionId, camera: widget.camera)));

  void _papers() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionPapersScreen(sessionId: widget.sessionId, api: _api)));

  void _history() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RevisionHistoryScreen(sessionId: widget.sessionId, api: _api)));

  void _scanMore() {
    final s = _info;
    if (s == null) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => RevisionRunScreen(info: s, api: _api, camera: widget.camera)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _info;
    return BasePage(
      appBar: ScreenAppBar(title: t('ملخص المراجعة', 'Revision summary')),
      child: _loading && s == null
          ? const AppListSkeleton(items: 4)
          : s == null
              ? AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر فتح الجلسة', 'The session could not be opened'), actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load)
              : RevisionFinishBody(
                  counts: s.counts,
                  excel: s.excel,
                  saving: _saving,
                  onDownload: _download,
                  onReview: _review,
                  onPapers: _papers,
                  onHistory: _history,
                  onScanMore: s.session.open ? _scanMore : null,
                ),
    );
  }
}

/// Plain values: the harness pumps it.
class RevisionFinishBody extends StatelessWidget {
  const RevisionFinishBody({super.key, required this.counts, required this.excel, this.saving = false, this.onDownload, this.onReview, this.onPapers, this.onHistory, this.onScanMore});

  final RevisionCounts counts;
  final bool excel, saving;
  final VoidCallback? onDownload, onReview, onPapers, onHistory, onScanMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sum = revisionSummary(counts);
    final open = counts.open;
    final reading = counts.pending;
    final (icon, tone, head, sub) = reading > 0
        ? (Icons.hourglass_top_rounded, c.primary, t('ما زلنا نقرأ الأوراق', 'Still reading the papers'), t('تظهر النتائج هنا فور اكتمالها، ويمكنك إغلاق هذه الشاشة.', 'Results appear here as soon as they are ready. You can leave this screen.'))
        : open > 0
            ? (Icons.pending_actions_rounded, c.warning, countText(open, ar1: 'ورقة واحدة تنتظر قرارك', ar2: 'ورقتان تنتظران قرارك', arFew: '$open أوراق تنتظر قرارك', arMany: '$open ورقة تنتظر قرارك', en1: '1 paper needs your decision', en: '$open papers need your decision'), t('لم يتغير شيء إلا بقرارك. راجع ما تبقّى ثم أنهِ.', 'Nothing changed without your decision. Review what is left, then finish.'))
            : (Icons.task_alt_rounded, c.success, t('انتهت المراجعة', 'The revision is done'), t('كل الأوراق المقروءة حُسمت.', 'Every paper that was read has been settled.'));
    Widget tile(String label, int n, Color color, IconData i) => AppCard(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            Icon(i, color: color),
            AppSpace.gapSm,
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            Text('$n', style: AppType.figure(context).copyWith(color: color)),
          ]),
        );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.form.max),
        child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          Icon(icon, size: AppIconSize.hero + AppSpace.lg, color: tone),
          AppSpace.gapSm,
          Text(head, key: const ValueKey('rv.finish.head'), textAlign: TextAlign.center, style: AppType.pageTitle(context)),
          Text(sub, textAlign: TextAlign.center, style: AppType.meta(context)),
          AppSpace.gapMd,
          tile(t('مطابقة', 'Matched'), sum.matched, c.success, Icons.check_circle_outline_rounded),
          AppSpace.gapXs,
          tile(t('حُدّثت', 'Updated'), sum.updated, revisionAccent(context), Icons.edit_note_rounded),
          AppSpace.gapXs,
          tile(t('تم تجاهلها', 'Ignored'), sum.ignored, c.textMedium, Icons.lock_outline_rounded),
          AppSpace.gapXs,
          tile(t('غير مقروءة', 'Unreadable'), sum.unreadable, c.danger, Icons.warning_amber_rounded),
          if (sum.differ > 0) ...[
            AppSpace.gapXs,
            tile(t('تختلف وتنتظر قرارك', 'Differ, waiting for you'), sum.differ, c.warning, Icons.compare_arrows_rounded),
          ],
          AppSpace.gapMd,
          if (excel) ...[
            AppPrimaryButton(key: const ValueKey('rv.finish.download'), label: t('تنزيل الملف المصحّح', 'Download the corrected sheet'), icon: Icons.download_rounded, busy: saving, onPressed: saving ? null : onDownload),
            AppSpace.gapXs,
          ],
          if (open > 0)
            excel
                ? OutlinedButton.icon(key: const ValueKey('rv.finish.review'), onPressed: onReview, icon: const Icon(Icons.fact_check_outlined), label: Text(t('مراجعة ما تبقّى ($open)', 'Review what is left ($open)')))
                : AppPrimaryButton(key: const ValueKey('rv.finish.review'), label: t('مراجعة ما تبقّى ($open)', 'Review what is left ($open)'), icon: Icons.fact_check_outlined, onPressed: onReview)
          else if (!excel)
            AppPrimaryButton(key: const ValueKey('rv.finish.results'), label: t('عرض النتائج', 'See the results'), icon: Icons.fact_check_outlined, onPressed: onReview),
          AppSpace.gapXs,
          Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            TextButton.icon(onPressed: onPapers, icon: const Icon(Icons.layers_outlined), label: Text(t('كل الأوراق', 'All papers'))),
            TextButton.icon(onPressed: onHistory, icon: const Icon(Icons.history_rounded), label: Text(t('السجل', 'History'))),
            if (onScanMore != null) TextButton.icon(onPressed: onScanMore, icon: const Icon(Icons.photo_camera_outlined), label: Text(t('تصوير المزيد', 'Scan more'))),
          ]),
        ]),
      ),
    );
  }
}
