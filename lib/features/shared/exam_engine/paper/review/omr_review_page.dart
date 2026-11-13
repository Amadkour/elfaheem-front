// The review queue of a scanned bubble-sheet exam (brief 4.3 / 4.4 / 4.6, Examples 6 and 7): every uncertain case
// the engine would not guess, grouped by kind with counts; each one shows the cropped region next to the system's
// reading and why it is here, and is fixed in one action (tap the option, mark blank, confirm the form, accept or
// fix the digits, pick the student). The engine regrades at once: the new score comes back in the reply and the
// next item opens. Keyboard (web / desktop): 1–5 or A–E pick an option / a form, 0 or Delete = no answer, Enter
// accepts / saves, arrows move through the queue. The full paper view draws the detected answers over the page.
// Every decision is the server's audited `manual_changes` row (D-158) — shown as "Changed by you · 10:42".
//
// Handwritten answers (D-160): completion / short answer — accept the suggestion, set the score, fix the text; a
// corrected short answer waits `pending` for the recomputed suggestion (EventOrPoll on `job_updated {kind:
// omr_review}`, a short poll only as the fallback: the engine's recompute job sends no event of its own yet).
// Live: the engine's `job_updated {kind: omr_scan | omr_review, exam_id}` (after every scanned page / every decision,
// a second reviewer's too) reloads the queue through EventOrPoll; the timer is only the slow fallback. API and models:
// omr_review.dart; widgets: omr_review_parts.dart, omr_review_written.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../../../admin/admin_common.dart' show asInt, t;
import '../exam_setup.dart' show kExamOmrFeatureKey;
import '../scan/omr_scan.dart' show OmrScanApi, OmrReplaceResult, omrReplaceProblem;
import '../scan/omr_scan.dart' as scan show omrErrorText;
import '../scan/omr_upload_screen.dart' show OmrFilePicker;
import '../scan/scan_sources.dart' show pickOneScanPage;
import 'omr_results_page.dart';
import 'omr_review.dart';
import 'omr_review_parts.dart';

/// The signed-in user's id (to say "by you"); null outside the app's providers (tests pass [OmrReviewPage.meId]).
int? omrMeId(BuildContext context) {
  try {
    return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
  } catch (_) {
    return null;
  }
}

/// True while a text field has the keyboard focus (then letters and digits are typing, not shortcuts).
bool omrTyping() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// The live watch of an exam's scans and review decisions: `job_updated {kind: omr_scan | omr_review, exam_id}`.
EventOrPoll omrScanWatch(int examId, Future<void> Function() poll, {LiveStreamHandle? stream, LiveEvents? bus}) => EventOrPoll(
      poll: poll,
      every: const Duration(seconds: 20),
      fallbackEvery: const Duration(seconds: 90),
      names: const {LiveEvents.jobUpdated},
      match: (e) => omrExamEvent(e, examId),
      stream: stream,
      bus: bus,
    );

/// A scanned page or a review decision of [examId].
bool omrExamEvent(LiveEvent e, int examId) =>
    (e.kind == kOmrScanEventKind || e.kind == kOmrReviewEventKind) && asInt(e.data['exam_id'], -1) == examId;

/// One student's answer to open first (a written answer in Review marking): its attempt and question, and under
/// anonymous grading — where the queue hides the attempts — the student's pseudonym [code].
typedef OmrReviewFocus = ({int attemptId, int questionId, String? code});

/// The queue item of [focus] (its latest one when there are several); null when the list has none (resolved
/// meanwhile).
OmrReviewItem? omrFocusItem(List<OmrReviewItem> items, OmrReviewFocus? focus) {
  if (focus == null) return null;
  final code = focus.code;
  return items
      .where((i) =>
          i.questionId == focus.questionId &&
          (i.attemptId != null ? i.attemptId == focus.attemptId : code != null && code.isNotEmpty && i.studentCode == code))
      .lastOrNull;
}

class OmrReviewPage extends StatefulWidget {
  const OmrReviewPage(
      {super.key, required this.examId, this.initialItemId, this.focus, this.api, this.scanApi, this.picker, this.liveStream, this.liveBus, this.meId});

  final int examId;

  /// Open this item first (a deep link, a tap on the full paper view).
  final int? initialItemId;

  /// Open this student's answer first ("Review it on the paper image" in Review marking); the first item when the
  /// queue has no item for it.
  final OmrReviewFocus? focus;
  final OmrReviewApi? api;

  /// "Replace this page" on an image-quality item (tests hand their own API and picker).
  final OmrScanApi? scanApi;
  final OmrFilePicker? picker;
  final LiveStreamHandle? liveStream;
  final LiveEvents? liveBus;

  /// The signed-in user (else read from MyAuthProvider).
  final int? meId;

  @override
  State<OmrReviewPage> createState() => _OmrReviewPageState();
}

class _OmrReviewPageState extends State<OmrReviewPage> {
  late final OmrReviewApi _api = widget.api ?? OmrReviewApi();
  late final OmrScanApi _scan = widget.scanApi ?? OmrScanApi();
  final _keys = FocusNode(debugLabel: 'omr.review.keys');
  EventOrPoll? _watch;

  /// While a corrected short answer's suggestion is recomputed: the item, re-read on the event (short poll fallback).
  EventOrPoll? _pendingWatch;
  int? _pendingId;

  OmrReviewList? _list;
  String? _filter;
  String? _error;
  OmrReviewItem? _item;
  bool _detailLoading = false;
  bool _busy = false;
  OmrResolveReply? _last;
  Set<String> _picked = {};
  final Map<int, OmrReviewItem> _details = {};
  final Map<int, Uint8List?> _crops = {};
  final Set<int> _cropLoading = {};
  int _openSeq = 0;

  int get _examId => widget.examId;

  @override
  void initState() {
    super.initState();
    _load(first: true);
    _watch = omrScanWatch(_examId, () => _load(silent: true), stream: widget.liveStream, bus: widget.liveBus)..start();
  }

  @override
  void dispose() {
    _watch?.dispose();
    _pendingWatch?.dispose();
    _keys.dispose();
    super.dispose();
  }

  int? get _me => widget.meId ?? omrMeId(context);

  // ── loading ──

  Future<void> _load({bool first = false, bool silent = false}) async {
    final status = _filter == 'resolved' ? 'resolved' : 'open';
    final kind = _filter == null || _filter == 'resolved' ? null : _filter;
    final r = await _api.items(_examId, status: status, kind: kind);
    if (!mounted) return;
    if (!r.ok) {
      if (!silent) setState(() => _error = omrErrorText(r));
      return;
    }
    final list = OmrReviewList.fromJson(r.map);
    setState(() {
      _error = null;
      _list = list;
    });
    final cur = _item;
    final focused = first ? omrFocusItem(list.items, widget.focus) : null;
    if (first && widget.initialItemId != null) {
      _open(widget.initialItemId!);
    } else if (focused != null) {
      _open(focused.id);
    } else if (cur == null || !list.items.any((i) => i.id == cur.id) && (cur.open || _filter == 'resolved')) {
      // the current item left the list (decided elsewhere / filter changed): the next one
      final next = cur == null ? null : _after(cur.id, list.items);
      if (silent && cur != null && !cur.open) return; // keep the decided item on screen with its score
      if (list.items.isNotEmpty) {
        _open((next ?? list.items.first).id);
      } else {
        setState(() => _item = null);
      }
    }
  }

  OmrReviewItem? _after(int id, List<OmrReviewItem> items) {
    final later = items.where((i) => i.id > id).toList();
    return later.isNotEmpty ? later.first : (items.isNotEmpty ? items.first : null);
  }

  Future<void> _open(int id, {bool keepLast = false}) async {
    final seq = ++_openSeq;
    final row = _list?.items.where((i) => i.id == id).firstOrNull;
    setState(() {
      _item = _details[id] ?? row ?? _item;
      _picked = {};
      _detailLoading = !_details.containsKey(id);
      if (!keepLast) _last = null;
    });
    final d = _details[id] ?? await _fetchDetail(id);
    if (!mounted || seq != _openSeq) return;
    setState(() {
      if (d != null) _item = d;
      _detailLoading = false;
    });
    if (d != null) _loadCrop(d);
    _prefetchAfter(id);
  }

  Future<OmrReviewItem?> _fetchDetail(int id) async {
    final r = await _api.item(_examId, id);
    if (!r.ok) {
      if (mounted && _item?.id == id) showAppNotice(omrErrorText(r), error: true);
      return null;
    }
    final d = OmrReviewItem.fromJson(r.map);
    _details[id] = d;
    return d;
  }

  Future<void> _loadCrop(OmrReviewItem d) async {
    if (!d.hasCrop || _crops.containsKey(d.id) || _cropLoading.contains(d.id)) return;
    _cropLoading.add(d.id);
    if (mounted) setState(() {});
    final bytes = await _api.image(d.cropUrl);
    _cropLoading.remove(d.id);
    _crops[d.id] = bytes;
    if (mounted) setState(() {});
  }

  /// Speed: the next item's detail and crop are fetched while the teacher looks at this one.
  Future<void> _prefetchAfter(int id) async {
    final items = _list?.items ?? const <OmrReviewItem>[];
    final i = items.indexWhere((x) => x.id == id);
    if (i < 0 || i + 1 >= items.length) return;
    final nextId = items[i + 1].id;
    if (_details.containsKey(nextId)) return;
    final d = await _fetchDetail(nextId);
    if (d != null) _loadCrop(d);
  }

  /// The exam's audience (`GET …/omr/students?q=`); null = no search here (403 / not routed): type the number.
  bool _openRun = false, _openAsked = false;

  /// D-672: a correction with no course takes new students in review. Asked once, when an ID item is first shown.
  void _askOpen() {
    if (_openAsked) return;
    _openAsked = true;
    _api.audience(_examId, '').then((r) {
      if (mounted && r.ok && OmrAudience.fromJson(r.map).open) setState(() => _openRun = true);
    });
  }

  Future<List<OmrStudent>?> _search(String q) async {
    final r = await _api.audience(_examId, q);
    if (!r.ok) return r.status == 403 || r.status == 404 || r.unavailable ? null : const [];
    return OmrAudience.fromJson(r.map).items;
  }

  // ── a suggestion being recomputed ──

  void _watchPending(int id) {
    if (_pendingId == id && (_pendingWatch?.running ?? false)) return;
    _pendingWatch?.dispose();
    _pendingId = id;
    _pendingWatch = EventOrPoll(
      poll: () => _refreshPending(id),
      every: const Duration(seconds: 3),
      fallbackEvery: const Duration(seconds: 5),
      names: const {LiveEvents.jobUpdated},
      match: (e) => omrExamEvent(e, _examId),
      stream: widget.liveStream,
      bus: widget.liveBus,
    )..start();
  }

  void _stopPending() {
    _pendingWatch?.dispose();
    _pendingWatch = null;
    _pendingId = null;
  }

  Future<void> _refreshPending(int id) async {
    final r = await _api.item(_examId, id);
    if (!mounted || !r.ok) return;
    final d = OmrReviewItem.fromJson(r.map);
    _details[id] = d;
    if (_item?.id == id) setState(() => _item = d);
    if (!d.pending || !d.open) _stopPending();
  }

  // ── decisions ──

  Future<void> _resolve(Map<String, dynamic> body) async {
    final it = _item;
    if (it == null || !it.open || _busy) return;
    setState(() => _busy = true);
    final r = await _api.resolve(_examId, it.id, body);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(omrErrorText(r), error: true);
      if (r.code == 'review_item_resolved' || r.code == 'page_gone') {
        _details.remove(it.id);
        _load(silent: true);
      }
      return;
    }
    final reply = OmrResolveReply.fromJson(r.map);
    HapticFeedback.selectionClick();
    if (reply.stillOpen && reply.item.id == it.id) {
      // a fixed text that matched near again, or a short answer whose suggestion is recomputed: the item stays here
      _details.remove(it.id);
      setState(() {
        _last = reply;
        _item = it.withReading(reply.item);
      });
      final d = await _fetchDetail(it.id);
      if (!mounted) return;
      if (d != null && _item?.id == it.id) setState(() => _item = d);
      if ((d ?? reply.item).pending) _watchPending(it.id);
      _load(silent: true);
      return;
    }
    if (_pendingId == it.id) _stopPending();
    final list = _list;
    setState(() {
      _last = reply;
      _details.remove(it.id);
      if (list != null) {
        final counts = Map<String, int>.of(list.openByKind);
        counts[it.kind] = ((counts[it.kind] ?? 1) - 1).clamp(0, 1 << 30);
        _list = OmrReviewList(items: [for (final x in list.items) if (x.id != it.id) x], total: (list.total - 1).clamp(0, 1 << 30), openByKind: counts);
      }
    });
    final items = _list?.items ?? const <OmrReviewItem>[];
    final nextId = reply.nextItemId != null && items.any((x) => x.id == reply.nextItemId) ? reply.nextItemId : _after(it.id, items)?.id;
    if (nextId != null) {
      _open(nextId, keepLast: true);
    } else {
      setState(() => _item = null);
    }
    _load(silent: true);
  }

  void _choose(List<String> letters) => _resolve(omrResolveBody('choose', options: letters));
  void _setScore(double v) => _resolve(omrResolveBody('set_score', score: v));
  void _fixText(List<String> texts) {
    final it = _item;
    if (it != null) _resolve(omrFixTextBody(texts, blanks: it.blankCount));
  }
  void _blank() => _resolve(omrResolveBody('blank'));
  void _toggle(String l) => setState(() => _picked = {..._picked}..toggle(l));

  Future<void> _dismiss() async {
    final ok = await appConfirm(context,
        message: t('تُنحّى هذه الورقة ولا تُصحَّح. يمكنك رفعها مرة أخرى لاحقًا. متابعة؟', 'This paper is set aside and not graded. You can upload it again later. Continue?'),
        confirmLabel: t('تنحية', 'Set aside'));
    if (ok) _resolve(omrResolveBody('dismiss'));
  }

  Future<void> _replace() async {
    final it = _item;
    final who = it?.gradedStudentText;
    final page = it?.gradedPageText;
    final ok = await appConfirm(context,
        message: who == null
            ? t('تصبح هذه الورقة ورقة الطالب وتُصحَّح بدل الورقة السابقة. متابعة؟', "This sheet becomes the student's sheet and is graded instead of the earlier one. Continue?")
            : t('تصبح هذه الورقة ورقة $who وتُصحَّح بدل ${page ?? 'الورقة المصحّحة'}. متابعة؟',
                'This sheet becomes the sheet of $who and is graded instead of ${page ?? 'the graded one'}. Continue?'),
        confirmLabel: t('استبدال', 'Replace'));
    if (ok) _resolve(omrResolveBody('replace'));
  }

  /// An image-quality item: a clearer image of its page, through the batch page's replace flow (the capture gate on
  /// the request). Accepted → the page is read again and its open items close as "replaced"; refused → the reason.
  Future<void> _replacePage() async {
    final it = _item;
    final pageId = it?.scanPageId;
    if (it == null || pageId == null || _busy) return;
    final label = it.pageName;
    final files = widget.picker != null ? await widget.picker!(many: false) : await pickOneScanPage(context, pageLabel: label);
    if (files.isEmpty || !mounted) return;
    final problem = omrReplaceProblem(files.first);
    if (problem != null) {
      showAppNotice(problem, error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await _scan.replacePage(_examId, pageId, files.first);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(scan.omrErrorText(r), error: true);
      return;
    }
    final res = OmrReplaceResult.fromJson(r.map);
    if (!res.accepted) {
      showAppNotice(res.refusal, error: true);
      return;
    }
    showAppNotice(res.text.isNotEmpty ? res.text : t('استُبدلت الصفحة وتُقرأ الآن', 'The page was replaced. It is being read now.'));
    _details.remove(it.id);
    await _load(silent: true);
  }

  void _step(int delta) {
    final items = _list?.items ?? const <OmrReviewItem>[];
    if (items.isEmpty) return;
    final i = items.indexWhere((x) => x.id == _item?.id);
    final n = i < 0 ? 0 : (i + delta).clamp(0, items.length - 1);
    if (n != i) _open(items[n].id);
  }

  void _setFilter(String? f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _item = null;
      _last = null;
      _list = null;
    });
    _load();
  }

  // ── keyboard ──

  static final _letterKeys = {
    LogicalKeyboardKey.keyA: 0,
    LogicalKeyboardKey.keyB: 1,
    LogicalKeyboardKey.keyC: 2,
    LogicalKeyboardKey.keyD: 3,
    LogicalKeyboardKey.keyE: 4,
    LogicalKeyboardKey.keyF: 5,
    LogicalKeyboardKey.keyG: 6,
    LogicalKeyboardKey.keyH: 7,
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
    LogicalKeyboardKey.digit6: 5,
    LogicalKeyboardKey.digit7: 6,
    LogicalKeyboardKey.digit8: 7,
    LogicalKeyboardKey.numpad1: 0,
    LogicalKeyboardKey.numpad2: 1,
    LogicalKeyboardKey.numpad3: 2,
    LogicalKeyboardKey.numpad4: 3,
    LogicalKeyboardKey.numpad5: 4,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || omrTyping() || _busy) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final rtl = AppConfig.lang == 'ar';
    if (k == LogicalKeyboardKey.arrowDown || k == (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
      _step(-1);
      return KeyEventResult.handled;
    }
    final it = _item;
    if (it == null || !it.open || _detailLoading) return KeyEventResult.ignored;
    final idx = _letterKeys[k];
    if (it.kind == 'bubble') {
      if (idx != null && idx < it.letters.length) {
        final l = it.letters[idx];
        it.multi ? _toggle(l) : _choose([l]);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0 || k == LogicalKeyboardKey.delete) {
        _blank();
        return KeyEventResult.handled;
      }
      if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && it.multi && _picked.isNotEmpty) {
        _choose(it.letters.where(_picked.contains).toList());
        return KeyEventResult.handled;
      }
    }
    if (it.kind == 'form' && idx != null) {
      final forms = it.forms;
      if (idx < forms.length) {
        _resolve(omrResolveBody('confirm', form: forms[idx]));
        return KeyEventResult.handled;
      }
    }
    if (it.written && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && it.canAcceptSuggestion) {
      _resolve(omrResolveBody('accept'));
      return KeyEventResult.handled;
    }
    if (it.kind == 'identifier' && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && it.can('accept') &&
        it.readValue.isNotEmpty && !it.partlyRead && const {'identifier_unclear', 'identifier_conflict', 'student_not_in_exam', 'attempt_in_progress'}.contains(it.code)) {
      _resolve(omrResolveBody('accept'));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── sheets / routes ──

  Future<void> _openPaper() async {
    final it = _item;
    if (it?.scanPageId == null) return;
    final picked = await Navigator.of(context).push<int>(MaterialPageRoute(
        builder: (_) => OmrPaperPage(examId: _examId, pageId: it!.scanPageId!, focusN: it.kind == 'bubble' ? it.n : null, api: _api)));
    if (picked != null && mounted) {
      if (_filter == 'resolved') _setFilter(null);
      _open(picked);
    }
    _keys.requestFocus();
  }

  Future<void> _showChanges() async {
    final r = await _api.changes(_examId);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(omrErrorText(r), error: true);
      return;
    }
    final rows = [for (final m in (r.map['items'] is List ? r.map['items'] as List : const [])) if (m is Map) OmrChange.fromJson(Map<String, dynamic>.from(m))];
    await showAppSheet<void>(
        context,
        (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(tone: AppTone.info, icon: Icons.history_rounded, t('سجل التعديلات اليدوية', 'Manual changes')),
              Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.md), child: OmrChangesList(changes: rows, meId: _me))),
            ]));
  }

  Future<void> _showQueue() async {
    final list = _list;
    if (list == null) return;
    final picked = await showAppSheet<int>(
        context,
        (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(t('قائمة المراجعة', 'Review queue')),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  child: OmrQueueList(items: list.items, currentId: _item?.id, onTap: (it) => Navigator.of(ctx).pop(it.id)),
                ),
              ),
            ]));
    if (picked != null && mounted) _open(picked);
  }

  void _openResults() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OmrResultsPage(examId: _examId, liveStream: widget.liveStream, liveBus: widget.liveBus)));

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      key: const ValueKey(kExamOmrFeatureKey),
      appBar: AppHeader(
        // three actions leave a phone's title ~190 px: the short name there, the full one on wider screens
        title: MediaQuery.sizeOf(context).width < Breakpoints.mobile
                ? t('مراجعة الأوراق', 'Review papers')
                : t('مراجعة الأوراق الممسوحة', 'Review scanned papers'),
        actions: [
          IconButton(
              key: const ValueKey('omr.changes'),
              tooltip: t('سجل التعديلات', 'Change history'),
              onPressed: _showChanges,
              icon: const Icon(Icons.history_rounded)),
          IconButton(
              key: const ValueKey('omr.toResults'),
              tooltip: t('النتائج', 'Results'),
              onPressed: _openResults,
              icon: const Icon(Icons.leaderboard_outlined)),
          AppRefreshAction(onRefresh: () => _load()),
        ],
      ),
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= Breakpoints.desktop;
          final list = _list;
          if (_error != null && list == null) {
            return Padding(
              padding: EdgeInsets.all(AppSpace.gutter(box.maxWidth)),
              child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!, action: TextButton(onPressed: () => _load(), child: Text(t('إعادة المحاولة', 'Try again')))),
            );
          }
          if (list == null) return const AppListSkeleton(items: 4, withAvatar: false);
          final filter = OmrKindFilter(list: list, selected: _filter, onPick: _setFilter);
          final detail = _detailPane(context, list, wide: wide);
          if (!wide) {
            return AppRefresh(
              onRefresh: () => _load(),
              child: ListView(padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg), children: [
                filter,
                const SizedBox(height: AppSpace.sm),
                detail,
              ]),
            );
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 360,
              child: DecoratedBox(
                decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: c.divider))),
                child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
                  filter,
                  const SizedBox(height: AppSpace.md),
                  if (list.items.isEmpty)
                    Text(t('لا عناصر هنا', 'Nothing here'), style: appText(13, c: c.textMedium))
                  else
                    OmrQueueList(items: list.items, currentId: _item?.id, onTap: (it) => _open(it.id)),
                ]),
              ),
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: AppWidth.content.max),
                  child: ListView(padding: const EdgeInsets.all(AppSpace.lg), children: [detail]),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _detailPane(BuildContext context, OmrReviewList list, {required bool wide}) {
    final c = context.colors;
    final it = _item;
    final last = _last;
    final children = <Widget>[
      if (last != null) ...[OmrScoreBanner(reply: last), const SizedBox(height: AppSpace.sm)],
    ];
    if (it == null) {
      children.add(_filter == 'resolved'
          ? AppEmpty(icon: Icons.history_rounded, title: t('لا شيء تمت مراجعته بعد', 'Nothing resolved yet'))
          : AppEmpty(
              key: const ValueKey('omr.allClear'),
              icon: Icons.task_alt_rounded,
              title: t('لا شيء ينتظر المراجعة', 'Nothing waits for review'),
              message: t('كل ورقة ممسوحة حُسم أمرها', 'Every scanned paper is decided'),
              actionLabel: t('عرض النتائج', 'See the results'),
              onAction: _openResults,
            ));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    final items = list.items;
    final i = items.indexWhere((x) => x.id == it.id);
    final position = i < 0 ? null : t('${i + 1} من ${items.length}', '${i + 1} of ${items.length}');
    if (it.kind == 'identifier' && !_openAsked) WidgetsBinding.instance.addPostFrameCallback((_) => _askOpen());
    children.add(OmrReviewItemCard(
      item: it,
      crop: _crops[it.id],
      cropLoading: _cropLoading.contains(it.id) || (_detailLoading && it.hasCrop && !_crops.containsKey(it.id)),
      busy: _busy || _detailLoading,
      position: position,
      meId: _me,
      picked: _picked,
      onToggle: _toggle,
      fix: OmrFixCallbacks(
        onChoose: _choose,
        onBlank: _blank,
        onAccept: () => _resolve(omrResolveBody('accept')),
        onFix: (v) => _resolve(omrResolveBody('fix', value: v)),
        onAssign: (s) => _resolve(omrResolveBody('assign', studentId: s.id)),
        onSearch: _search,
        onConfirmForm: (f) => _resolve(omrResolveBody('confirm', form: f)),
        onDismiss: _dismiss,
        onReplace: _replace,
        onOpenPaper: _openPaper,
        onSetScore: _setScore,
        onFixText: _fixText,
        onReplacePage: _replacePage,
        onNewStudent: _openRun ? (name, code) => _resolve(omrResolveBody('assign', name: name, code: code)) : null,
      ),
    ));
    children.add(const SizedBox(height: AppSpace.sm));
    children.add(Row(children: [
      IconButton(
        key: const ValueKey('omr.prev'),
        tooltip: t('السابق', 'Previous'),
        onPressed: i > 0 ? () => _step(-1) : null,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      IconButton(
        key: const ValueKey('omr.next'),
        tooltip: t('التالي', 'Next'),
        onPressed: i >= 0 && i < items.length - 1 ? () => _step(1) : null,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
      const Spacer(),
      if (!wide)
        TextButton.icon(
          key: const ValueKey('omr.queue'),
          onPressed: _showQueue,
          icon: const Icon(Icons.list_rounded, size: 18),
          label: Text(t('القائمة (${items.length})', 'Queue (${items.length})')),
        ),
    ]));
    if (wide && it.open) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Text(omrKeyboardHint(it), key: const ValueKey('omr.keys.hint'), style: appText(12, c: c.textLight)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// The keyboard line under an item: only the keys that act on it (1–5 / A–E pick an answer on an answer item only).
String omrKeyboardHint(OmrReviewItem it) {
  if (it.written) return t('لوحة المفاتيح: Enter لقبول الدرجة المقترحة · الأسهم للتنقل', 'Keyboard: Enter accepts the suggested score · arrows move');
  if (it.kind == 'bubble' && it.code != 'key_missing') {
    return t('لوحة المفاتيح: 1–5 أو A–E لاختيار الإجابة · 0 بلا إجابة · Enter للتأكيد · الأسهم للتنقل',
        'Keyboard: 1–5 or A–E pick the answer · 0 no answer · Enter confirms · arrows move');
  }
  if (it.kind == 'form' && it.can('confirm')) return t('لوحة المفاتيح: 1–5 لاختيار النموذج · الأسهم للتنقل', 'Keyboard: 1–5 pick the form · arrows move');
  if (it.kind == 'identifier' && it.can('accept') && it.readValue.isNotEmpty && !it.partlyRead &&
      const {'identifier_unclear', 'identifier_conflict', 'student_not_in_exam', 'attempt_in_progress'}.contains(it.code)) {
    return t('لوحة المفاتيح: Enter لقبول الرقم · الأسهم للتنقل', 'Keyboard: Enter accepts the ID · arrows move');
  }
  return t('لوحة المفاتيح: الأسهم للتنقل بين العناصر', 'Keyboard: arrows move through the queue');
}

extension on Set<String> {
  /// Adds [v] when absent, removes it when present.
  void toggle(String v) => contains(v) ? remove(v) : add(v);
}

// ── the full paper ──────────────────────────────────────────────────────────────────────────────────────────────

/// One scanned page with the detected answers overlaid (zoom / pan). Pops with an item id when the teacher taps a
/// question or a decision that waits for review. A rejected page offers "Replace this page" (one photo through the
/// capture gate: accepted, or refused with the exact reason). Also the scans list's view of a bubble-sheet page (the
/// legacy `/scans/{id}/image` answers 409 `omr_page_use_review` for them).
class OmrPaperPage extends StatefulWidget {
  const OmrPaperPage({super.key, required this.examId, required this.pageId, this.focusN, this.api, this.scanApi, this.picker});
  final int examId;
  final int pageId;
  final int? focusN;
  final OmrReviewApi? api;
  final OmrScanApi? scanApi;

  /// Picks the replacement photo (tests hand their own).
  final OmrFilePicker? picker;

  @override
  State<OmrPaperPage> createState() => _OmrPaperPageState();
}

class _OmrPaperPageState extends State<OmrPaperPage> {
  late final OmrReviewApi _api = widget.api ?? OmrReviewApi();
  late final OmrScanApi _scan = widget.scanApi ?? OmrScanApi();
  OmrPageView? _page;
  Uint8List? _bytes;
  bool _imageLoading = true;
  String? _error;
  bool _replacing = false;
  OmrReplaceResult? _replaced;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.page(widget.examId, widget.pageId);
    if (!mounted) return;
    if (!r.ok) return setState(() => _error = omrErrorText(r));
    final p = OmrPageView.fromJson(r.map);
    setState(() => _page = p);
    final b = p.imageUrl == null ? null : await _api.image(p.imageUrl);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _imageLoading = false;
    });
  }

  Future<void> _replace() async {
    // one clearer image: the source sheet (the phone's photos or files), or the test's picker
    final files = widget.picker != null ? await widget.picker!(many: false) : await pickOneScanPage(context);
    if (files.isEmpty || !mounted) return;
    final problem = omrReplaceProblem(files.first);
    if (problem != null) {
      showAppNotice(problem, error: true);
      return;
    }
    setState(() => _replacing = true);
    final r = await _scan.replacePage(widget.examId, widget.pageId, files.first);
    if (!mounted) return;
    setState(() => _replacing = false);
    if (!r.ok) {
      showAppNotice(scan.omrErrorText(r), error: true);
      return;
    }
    final res = OmrReplaceResult.fromJson(r.map);
    setState(() => _replaced = res);
    if (res.accepted) _load();
  }

  void _openNew(int pageId) => Navigator.of(context).pushReplacement(MaterialPageRoute<int>(
      builder: (_) => OmrPaperPage(examId: widget.examId, pageId: pageId, api: widget.api, scanApi: widget.scanApi, picker: widget.picker)));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _page;
    final title = p?.label == null ? t('الورقة', 'Paper') : t('الورقة · صفحة ${p!.label}', 'Paper · page ${p.label}');
    return BasePage(
      key: const ValueKey(kExamOmrFeatureKey),
      appBar: AppHeader(title: title),
      child: LayoutBuilder(builder: (context, box) {
        final pad = AppSpace.gutter(box.maxWidth);
        if (_error != null) return Padding(padding: EdgeInsets.all(pad), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!));
        if (p == null) return const AppListSkeleton(items: 3, withAvatar: false);
        final wide = box.maxWidth >= Breakpoints.desktop;
        final overlay = OmrPaperOverlay(page: p, bytes: _bytes, loading: _imageLoading, focusN: widget.focusN);
        final rep = _replaced;
        final side = <Widget>[
          OmrPageStatusCard(
            page: p,
            replacing: _replacing,
            result: rep,
            onReplace: p.status == 'rejected' ? _replace : null,
            onOpenNew: rep != null && rep.accepted ? () => _openNew(rep.pageId) : null,
          ),
          const SizedBox(height: AppSpace.sm),
          OmrPageItemsList(page: p, onItem: (id) => Navigator.of(context).pop(id)),
          if (p.answers.isNotEmpty) ...[
            Text(t('الأسئلة كما قُرئت', 'The questions as read'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: AppSpace.xs),
            OmrPageAnswers(page: p, onItem: (id) => Navigator.of(context).pop(id)),
          ],
          if (p.identifierValue != null || p.formValue != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
                [
                  if (p.identifierValue != null) t('رقم الطالب: ${p.identifierValue}', 'Student ID: ${p.identifierValue}'),
                  if (p.formValue != null) t('النموذج: ${p.formValue}', 'Form: ${p.formValue}'),
                ].join(' · '),
                style: appText(13, c: c.textMedium)),
          ],
        ];
        if (wide) {
          return Padding(
            padding: EdgeInsets.all(pad),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: overlay),
              const SizedBox(width: AppSpace.lg),
              Expanded(flex: 2, child: ListView(children: side)),
            ]),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, AppSpace.sm, pad, AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 3, child: overlay),
            const SizedBox(height: AppSpace.sm),
            Expanded(flex: 2, child: ListView(children: side)),
          ]),
        );
      }),
    );
  }
}
