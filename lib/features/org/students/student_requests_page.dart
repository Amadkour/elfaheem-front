// lib/features/org/students/student_requests_page.dart — "Student requests": ONE list of what waits for me about
// students (student lifecycle contract §7.3, PLAN §3.6).
//
//   OrgStudentRequestsPage(orgId:, pushed:)   loads GET …/students/requests?tab=decide|waiting|done and keeps it
//                                             fresh on the live event `student_lifecycle` (and `onboarding`) through
//                                             EventOrPoll: the timer is only the slow fallback, never a poll loop
//       To decide      answered asks (accept / return for a fix with a reason), admission files at my step (opens the
//                      existing review page), lifecycle recommendations (accept / reject with a note)
//       Waiting        asks the student has not answered yet (overdue ones first, with a badge; remind / cancel),
//                      files returned for correction
//       Done           the last 90 days
//   Every row also offers "Request a meeting" and "Ask the student" when the server says so (`can`).
//   StudentRequestsView / InboxRowCard / AskReviewView   plain values (the layout harness pumps them)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../../admin/admin_common.dart' show t;
import '../../help/help_info_button.dart';
import '../onboarding/onboarding_review.dart' show OnbReviewPage;
import '../org_page_header.dart' show OrgPushedPage;
import 'student_ask_sheet.dart';
import 'student_asks_models.dart';
import 'student_file_page.dart' show pushStudentPage;
import 'students_api.dart';
import 'students_parts.dart' show StudentAvatar;

class OrgStudentRequestsPage extends StatefulWidget {
  const OrgStudentRequestsPage({super.key, required this.orgId, this.api, this.pushed = false, this.canFullscreen = true});
  final int orgId;
  final StudentsApi? api;

  /// Pushed on top of the dashboard: wear OrgPushedPage (title + help) instead of sitting in the People hub.
  final bool pushed;

  /// The caller holds `student_status:update` (offers the full-screen presentation in the ask sheet).
  final bool canFullscreen;

  @override
  State<OrgStudentRequestsPage> createState() => _OrgStudentRequestsPageState();
}

class _OrgStudentRequestsPageState extends State<OrgStudentRequestsPage> {
  late final StudentsApi _api = widget.api ?? StudentsApi(widget.orgId);
  String _tab = 'decide';
  int _page = 1;
  InboxPage? _data;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  /// The open asks by id (their due dates mark the overdue rows of "Waiting").
  Map<int, StudentAsk> _open = const {};
  final Set<String> _acting = {};
  EventOrPoll? _watch;

  @override
  void initState() {
    super.initState();
    _load();
    _watch = EventOrPoll(
      poll: () => _load(quiet: true),
      every: const Duration(seconds: 60),
      fallbackEvery: const Duration(minutes: 5),
      names: {kStudentLifecycleEvent, LiveEvents.onboarding},
    )..start();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final tab = _tab;
    final calls = await Future.wait([
      _api.requests(tab: tab, page: _page),
      if (tab == 'waiting') _api.asks(status: 'open', size: 100),
    ]);
    if (!mounted || seq != _seq) return;
    final r = calls.first;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = InboxPage.fromJson(r.map);
        _error = null;
        if (calls.length > 1 && calls[1].ok) {
          _open = {for (final a in AskListPage.fromJson(calls[1].map).items) a.id: a};
        }
      } else if (!quiet || _data == null) {
        _error = askErrorText(r.error!);
      }
    });
  }

  void _setTab(String tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _page = 1;
      _data = null;
    });
    _load();
  }

  Future<void> _run(InboxRow row, Future<bool> Function() fn) async {
    if (_acting.contains(row.id)) return;
    setState(() => _acting.add(row.id));
    final ok = await fn();
    if (!mounted) return;
    setState(() => _acting.remove(row.id));
    if (ok) _load(quiet: true);
  }

  Future<StudentAsk?> _findAsk(InboxRow row) async {
    final cached = _open[row.sourceId];
    final uid = row.student?.id;
    final r = await _api.asks(uid: uid, size: 100);
    if (!r.ok) {
      if (cached != null) return cached;
      showAppNotice(askErrorText(r.error!), error: true);
      return null;
    }
    for (final a in AskListPage.fromJson(r.map).items) {
      if (a.id == row.sourceId) return a;
    }
    showAppNotice(askCodeTexts()['ask_not_found']!, error: true);
    return null;
  }

  Future<void> _open1(InboxRow row) async {
    switch (row.source) {
      case 'case':
        await pushStudentPage<void>(context, OnbReviewPage(orgId: widget.orgId, caseId: row.sourceId, title: row.student?.displayName ?? ''));
        if (mounted) _load(quiet: true);
      case 'ask':
        final a = await _findAsk(row);
        if (a == null || !mounted) return;
        final changed = await showAppSheet<bool>(context, (ctx) => _AskReviewSheet(ask: a, api: _api));
        if (changed == true && mounted) _load(quiet: true);
      default:
        if (row.can.accept || row.can.reject) await _decision(row, 'accept');
    }
  }

  Future<void> _accept(InboxRow row) async {
    if (row.source == 'case') return _open1(row);
    if (row.source == 'decision') return _decision(row, 'accept');
    await _run(row, () async {
      final r = await _api.acceptAsk(row.sourceId);
      if (!r.ok) {
        showAppNotice(askErrorText(r.error!), error: true);
        return false;
      }
      showAppNotice(t('قُبل الرد وأُبلغ الطالب', 'Accepted; the student is told'));
      return true;
    });
  }

  Future<void> _return(InboxRow row) async {
    if (row.source == 'case') return _open1(row);
    final note = await _askNote(context,
        title: t('أعِد للتصحيح', 'Return for a fix'),
        label: t('ما الذي يصححه الطالب؟', 'What should the student fix?'),
        confirm: t('أعِد إلى الطالب', 'Return to the student'));
    if (note == null || !mounted) return;
    await _run(row, () async {
      final r = await _api.returnAsk(row.sourceId, note);
      if (!r.ok) {
        showAppNotice(askErrorText(r.error!), error: true);
        return false;
      }
      showAppNotice(t('أُعيد الطلب إلى الطالب مع السبب', 'Returned to the student with the reason'));
      return true;
    });
  }

  Future<void> _decision(InboxRow row, String verdict) async {
    final note = await _askNote(context,
        title: verdict == 'reject' ? t('رفض التوصية', 'Reject the recommendation') : t('قبول التوصية', 'Accept the recommendation'),
        subtitle: row.title,
        label: t('ملاحظة (تُحفظ في السجل)', 'Note (kept in the audit log)'),
        required: verdict == 'reject',
        confirm: verdict == 'reject' ? t('ارفض', 'Reject') : t('اقبل ونفّذ', 'Accept and apply'),
        danger: verdict == 'reject');
    if (note == null || !mounted) return;
    await _run(row, () async {
      final r = await _api.decide(row.sourceId, verdict, note: note);
      if (!r.ok) {
        showAppNotice(askErrorText(r.error!), error: true);
        return false;
      }
      showAppNotice(verdict == 'reject' ? t('رُفضت التوصية', 'The recommendation was rejected') : t('نُفّذت التوصية', 'The recommendation was applied'));
      return true;
    });
  }

  Future<void> _reject(InboxRow row) async {
    if (row.source == 'case') return _open1(row);
    return _decision(row, 'reject');
  }

  Future<void> _sheet(InboxRow row, String kind) async {
    final s = row.student;
    if (s == null) return;
    final a = await showStudentAskSheet(context, widget.orgId, s.id,
        kind: kind, name: s.displayName, canFullscreen: widget.canFullscreen, api: _api);
    if (a != null && mounted) _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final view = StudentRequestsView(
      data: _data,
      loading: _loading,
      error: _error,
      tab: _tab,
      openAsks: _open,
      acting: _acting,
      onTab: _setTab,
      onRetry: _load,
      onRefresh: () => _load(quiet: true),
      onPage: (p) {
        _page = p;
        _load();
      },
      onOpen: _open1,
      onAccept: _accept,
      onReturn: _return,
      onReject: _reject,
      onMeeting: (r) => _sheet(r, 'meeting'),
      onAsk: (r) => _sheet(r, 'data'),
    );
    if (!widget.pushed) return view;
    return OrgPushedPage(
      title: t('طلبات الطلاب', 'Student requests'),
      helpPageId: kStudentRequestsHelpId,
      width: AppWidth.content,
      child: view,
    );
  }
}

/// A reason / note sheet. Resolves to the trimmed text ('' when optional and empty), null when closed.
Future<String?> _askNote(BuildContext context,
    {required String title, String? subtitle, required String label, required String confirm, bool required = true, bool danger = false}) {
  return showAppSheet<String>(context, (ctx) => _NoteSheet(title: title, subtitle: subtitle, label: label, confirm: confirm, required: required, danger: danger));
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.title, this.subtitle, required this.label, required this.confirm, this.required = true, this.danger = false});
  final String title, label, confirm;
  final String? subtitle;
  final bool required, danger;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _done() {
    final v = _note.text.trim();
    if (widget.required && v.isEmpty) {
      setState(() => _error = t('اكتب السبب ليعرف الطالب ما المطلوب', 'Write the reason so the student knows what to do'));
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: widget.title,
        subtitle: widget.subtitle,
        icon: widget.danger ? Icons.block_rounded : Icons.edit_note_rounded,
        tone: widget.danger ? AppTone.danger : AppTone.brand,
        children: [
          AppField(
            key: const ValueKey('students.requests.note'),
            controller: _note,
            label: widget.label,
            required: widget.required,
            maxLines: 3,
            maxLength: 4000,
            autofocus: true,
            errorText: _error,
          ),
          AppSpace.gapMd,
          widget.danger
              ? AppButton.danger(label: widget.confirm, expand: true, onPressed: _done)
              : AppButton.primary(label: widget.confirm, expand: true, onPressed: _done),
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The ask review sheet
// ═════════════════════════════════════════════════════════════════════════════

class _AskReviewSheet extends StatefulWidget {
  const _AskReviewSheet({required this.ask, required this.api});
  final StudentAsk ask;
  final StudentsApi api;

  @override
  State<_AskReviewSheet> createState() => _AskReviewSheetState();
}

class _AskReviewSheetState extends State<_AskReviewSheet> {
  late StudentAsk _a = widget.ask;
  final _note = TextEditingController();
  String? _busy;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    if (_busy != null) return;
    if (action == 'return' && _note.text.trim().isEmpty) {
      setState(() => _error = t('اكتب ما الذي يصححه الطالب', 'Write what the student should fix'));
      return;
    }
    if (action == 'cancel') {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('ألغِ الطلب', 'Cancel the request'),
          message: _a.meeting == null
              ? t('سيُبلَّغ الطالب بإلغاء الطلب.', 'The student is told the request is cancelled.')
              : t('سيُلغى الاجتماع من التقويم ويُبلَّغ الطالب.', 'The meeting leaves the calendar and the student is told.'));
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = action;
      _error = null;
    });
    final note = _note.text.trim();
    final r = switch (action) {
      'accept' => await widget.api.acceptAsk(_a.id, note: note.isEmpty ? null : note),
      'return' => await widget.api.returnAsk(_a.id, note),
      'remind' => await widget.api.remindAsk(_a.id),
      _ => await widget.api.cancelAsk(_a.id),
    };
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = null;
        _error = askErrorText(r.error!);
      });
      return;
    }
    showAppNotice(switch (action) {
      'accept' => t('قُبل الرد وأُبلغ الطالب', 'Accepted; the student is told'),
      'return' => t('أُعيد الطلب إلى الطالب مع السبب', 'Returned to the student with the reason'),
      'remind' => t('أُرسل التذكير إلى الطالب', 'The reminder was sent'),
      _ => t('أُلغي الطلب', 'The request was cancelled'),
    });
    if (action == 'remind') {
      setState(() {
        _busy = null;
        _a = StudentAsk.fromJson(r.map);
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
          title: _a.title.isEmpty ? askKindRequestLabel(_a.kind) : _a.title,
          subtitle: _a.student?.displayName,
          icon: Icons.forum_outlined,
          headerTrailing: const HelpInfoButton(pageId: kStudentRequestsHelpId, autoTour: false),
          children: [
            AskReviewView(
              ask: _a,
              note: _note,
              busy: _busy,
              error: _error,
              onAccept: () => _act('accept'),
              onReturn: () => _act('return'),
              onRemind: () => _act('remind'),
              onCancel: () => _act('cancel'),
            ),
          ],
      );
}

/// One ask for the reviewer: what was asked, the answer, and the verbs that apply.
class AskReviewView extends StatelessWidget {
  const AskReviewView({
    super.key,
    required this.ask,
    required this.note,
    this.busy,
    this.error,
    this.now,
    this.onAccept,
    this.onReturn,
    this.onRemind,
    this.onCancel,
  });

  final StudentAsk ask;
  final TextEditingController note;

  /// The action being sent (`accept`, `return`, `remind`, `cancel`); null = none.
  final String? busy;
  final String? error;
  final DateTime? now;
  final VoidCallback? onAccept, onReturn, onRemind, onCancel;

  @override
  Widget build(BuildContext context) {
    final a = ask;
    final c = context.colors;
    final answer = a.answeredAt == null && a.answer.isEmpty ? const <(String, String)>[] : askAnswerLines(a);
    final facts = <(IconData, String)>[
      (Icons.label_outline_rounded, askKindRequestLabel(a.kind)),
      if (a.meeting != null) (Icons.event_rounded, a.meeting!.line),
      if (a.dueAt != null) (Icons.flag_outlined, t('آخر موعد: ${AppTime.dateTime(a.dueAt!.toUtc())}', 'Due: ${AppTime.dateTime(a.dueAt!.toUtc())}')),
      if (a.createdBy != null && a.createdBy!.name.isNotEmpty) (Icons.person_outline_rounded, t('طلبه: ${a.createdBy!.name}', 'Asked by ${a.createdBy!.name}')),
      if (a.answeredAt != null) (Icons.reply_rounded, t('ردّ في ${AppTime.dateTime(a.answeredAt!.toUtc())}', 'Answered ${AppTime.dateTime(a.answeredAt!.toUtc())}')),
    ];
    final busyNow = busy != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
        AppStatusBadge(label: a.statusLabel, tone: a.statusTone, dot: true, dense: true),
        if (a.overdue(now)) AppStatusBadge(label: t('متأخر', 'Overdue'), tone: AppTone.danger, dense: true),
        AppStatusBadge(label: askPresentationLabel(a.presentation), dense: true),
      ]),
      AppSpace.gapSm,
      for (final f in facts)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(f.$1, size: AppIconSize.sm, color: c.textMedium),
            AppSpace.gapXs,
            Expanded(child: Text(f.$2, style: AppType.meta(context))),
          ]),
        ),
      if (a.body != null) ...[
        AppSpace.gapXs,
        Text(a.body!, style: AppType.body(context)),
      ],
      AppSpace.gapMd,
      AppCard(
        key: const ValueKey('students.requests.answer'),
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(t('رد الطالب', 'The student\'s answer'), style: AppType.label(context)),
          AppSpace.gapXs,
          if (answer.isEmpty)
            Text(t('لم يرد بعد.', 'No answer yet.'), style: AppType.meta(context))
          else
            for (final l in answer)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.$1, style: AppType.meta(context)),
                  Text(l.$2, style: AppType.bodyStrong(context)),
                ]),
              ),
          if (a.kind == 'data' && a.fields.any((f) => f.caseField))
            Text(t('بيانات الملف تُحفظ فيه عند القبول فقط.', 'File data is saved to the file only when you accept.'), style: AppType.meta(context)),
        ]),
      ),
      if (a.reviewNote != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.undo_rounded, text: t('سبب الإعادة: ${a.reviewNote}', 'Returned because: ${a.reviewNote}')),
      ],
      if (a.isAnswered) ...[
        AppSpace.gapMd,
        AppField(
          key: const ValueKey('students.requests.review_note'),
          controller: note,
          label: t('ملاحظة للطالب (مطلوبة عند الإعادة)', 'A note for the student (needed to return it)'),
          maxLines: 3,
          maxLength: 4000,
          enabled: !busyNow,
        ),
      ],
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      AppSpace.gapMd,
      if (a.isAnswered) ...[
        AppButton.primary(
          key: const ValueKey('students.requests.accept'),
          label: t('اقبل الرد', 'Accept the answer'),
          icon: Icons.check_rounded,
          expand: true,
          busy: busy == 'accept',
          onPressed: busyNow ? null : onAccept,
        ),
        AppSpace.gapXs,
        AppButton.secondary(
          key: const ValueKey('students.requests.return'),
          label: t('أعِد للتصحيح', 'Return for a fix'),
          icon: Icons.undo_rounded,
          expand: true,
          busy: busy == 'return',
          onPressed: busyNow ? null : onReturn,
        ),
      ],
      if (a.isOpen)
        AppButton.tonal(
          key: const ValueKey('students.requests.remind'),
          label: t('ذكّر الطالب الآن', 'Remind the student now'),
          icon: Icons.notifications_active_outlined,
          expand: true,
          busy: busy == 'remind',
          onPressed: busyNow ? null : onRemind,
        ),
      if (a.isLive) ...[
        AppSpace.gapXs,
        AppButton.ghost(
          key: const ValueKey('students.requests.cancel'),
          label: t('ألغِ الطلب', 'Cancel the request'),
          icon: Icons.close_rounded,
          expand: true,
          busy: busy == 'cancel',
          onPressed: busyNow ? null : onCancel,
        ),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page over plain values
// ═════════════════════════════════════════════════════════════════════════════

class StudentRequestsView extends StatelessWidget {
  const StudentRequestsView({
    super.key,
    this.data,
    this.loading = false,
    this.error,
    this.tab = 'decide',
    this.openAsks = const {},
    this.acting = const {},
    this.now,
    this.onTab,
    this.onRetry,
    this.onRefresh,
    this.onPage,
    this.onOpen,
    this.onAccept,
    this.onReturn,
    this.onReject,
    this.onMeeting,
    this.onAsk,
  });

  final InboxPage? data;
  final bool loading;

  /// The text to show (already made); null = no error.
  final String? error;
  final String tab;

  /// Open asks by id: a waiting ask row past its due date is overdue.
  final Map<int, StudentAsk> openAsks;

  /// Rows with an action on the way (`InboxRow.id`).
  final Set<String> acting;
  final DateTime? now;
  final ValueChanged<String>? onTab;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final ValueChanged<int>? onPage;
  final ValueChanged<InboxRow>? onOpen, onAccept, onReturn, onReject, onMeeting, onAsk;

  bool _overdue(InboxRow r) => r.isAsk && (openAsks[r.sourceId]?.overdue(now) ?? false);

  @override
  Widget build(BuildContext context) {
    final d = data;
    final idx = inboxTabs.indexOf(tab);
    final rows = [...?d?.items];
    if (tab == 'waiting') {
      // overdue first, the rest keep the server's order (oldest first)
      final late = rows.where(_overdue).toList();
      rows
        ..removeWhere(_overdue)
        ..insertAll(0, late);
    }
    final Widget body;
    if (loading && d == null) {
      body = const AppListSkeleton(items: 5);
    } else if (error != null && d == null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (rows.isEmpty) {
      body = AppEmpty(
        icon: switch (tab) {
          'decide' => Icons.inbox_outlined,
          'waiting' => Icons.hourglass_empty_rounded,
          _ => Icons.task_alt_rounded,
        },
        title: switch (tab) {
          'decide' => t('لا شيء ينتظر قرارك', 'Nothing waits for your decision'),
          'waiting' => t('لا طلبات بانتظار الطلاب', 'No requests wait for students'),
          _ => t('لا طلبات منتهية بعد', 'Nothing finished yet'),
        },
        message: switch (tab) {
          'decide' => t('عندما يرد طالب أو يصل ملف إلى خطوتك يظهر هنا.', 'When a student answers or a file reaches your step, it shows here.'),
          'waiting' => t('ما تطلبه من الطلاب ولم يردوا عليه يظهر هنا.', 'What you ask students and they have not answered shows here.'),
          _ => t('يظهر هنا ما أُنجز خلال آخر ٩٠ يوماً.', 'What was finished in the last 90 days shows here.'),
        },
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: InboxRowCard(
              row: r,
              overdue: _overdue(r),
              busy: acting.contains(r.id),
              onOpen: onOpen == null ? null : () => onOpen!(r),
              onAccept: r.can.accept && onAccept != null ? () => onAccept!(r) : null,
              onReturn: r.can.ret && onReturn != null ? () => onReturn!(r) : null,
              onReject: r.can.reject && onReject != null ? () => onReject!(r) : null,
              onMeeting: r.can.meeting && r.student != null && onMeeting != null ? () => onMeeting!(r) : null,
              onAsk: r.can.ask && r.student != null && onAsk != null ? () => onAsk!(r) : null,
            ),
          ),
        if (d != null && d.pages > 1 && onPage != null)
          AppPagination(page: d.page, pageCount: d.pages, onPage: onPage!, total: d.total, pageSize: d.size),
      ]);
    }
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
      children: [
        AppTabs(
          key: const ValueKey('students.requests.tabs'),
          items: [
            for (final k in inboxTabs) AppTabItem(inboxTabLabel(k), count: k == 'done' ? null : (d?.count(k) ?? 0)),
          ],
          index: idx < 0 ? 0 : idx,
          onChanged: (i) => onTab?.call(inboxTabs[i]),
        ),
        AppSpace.gapMd,
        body,
      ],
    );
    final refresh = onRefresh;
    return refresh == null ? list : AppRefresh(onRefresh: refresh, child: list);
  }
}

/// One row of the inbox: who, what, since when, its type and status, and the verbs it allows.
class InboxRowCard extends StatelessWidget {
  const InboxRowCard({
    super.key,
    required this.row,
    this.overdue = false,
    this.busy = false,
    this.onOpen,
    this.onAccept,
    this.onReturn,
    this.onReject,
    this.onMeeting,
    this.onAsk,
  });

  final InboxRow row;
  final bool overdue, busy;
  final VoidCallback? onOpen, onAccept, onReturn, onReject, onMeeting, onAsk;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final s = r.student;
    final name = s == null || s.displayName.trim().isEmpty ? t('طالب', 'A student') : s.displayName;
    final verbs = [
      if (onAccept != null)
        AppButton.tonal(
            key: ValueKey('students.requests.row.${r.id}.accept'),
            label: r.isAsk ? t('اقبل', 'Accept') : (r.source == 'case' ? t('راجع', 'Review') : t('اقبل', 'Accept')),
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: busy ? null : onAccept),
      if (onReturn != null && r.source != 'case')
        AppButton.secondary(
            key: ValueKey('students.requests.row.${r.id}.return'), label: t('أعِد للتصحيح', 'Return'), icon: Icons.undo_rounded, onPressed: busy ? null : onReturn),
      if (onReject != null && r.source != 'case')
        AppButton.ghost(key: ValueKey('students.requests.row.${r.id}.reject'), label: t('ارفض', 'Reject'), icon: Icons.close_rounded, onPressed: busy ? null : onReject),
    ];
    final more = <(String, IconData, VoidCallback)>[
      if (onMeeting != null) (t('اطلب اجتماعاً', 'Request a meeting'), Icons.event_available_rounded, onMeeting!),
      if (onAsk != null) (t('اطلب من الطالب', 'Ask the student'), Icons.forum_outlined, onAsk!),
    ];
    return AppCard(
      key: ValueKey('students.requests.row.${r.id}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s != null) ...[StudentAvatar(user: s), AppSpace.gapSm],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(r.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
              if (r.at != null) ...[
                const SizedBox(height: AppSpace.xxs / 2),
                Text(AppTime.dateTime(r.at!.toUtc()), style: AppType.meta(context)),
              ],
            ]),
          ),
          if (more.isNotEmpty)
            PopupMenuButton<int>(
              key: ValueKey('students.requests.row.${r.id}.more'),
              tooltip: t('المزيد', 'More'),
              icon: const Icon(Icons.more_vert_rounded),
              enabled: !busy,
              onSelected: (i) => more[i].$3(),
              itemBuilder: (_) => [
                for (var i = 0; i < more.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    child: Row(children: [Icon(more[i].$2, size: AppIconSize.md), AppSpace.gapSm, Flexible(child: Text(more[i].$1))]),
                  ),
              ],
            ),
        ]),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          AppStatusBadge(label: r.sourceLabel, dense: true),
          AppStatusBadge(label: r.statusLabel, tone: r.statusTone, dot: true, dense: true),
          if (overdue) AppStatusBadge(key: ValueKey('students.requests.row.${r.id}.overdue'), label: t('متأخر', 'Overdue'), tone: AppTone.danger, dense: true),
        ]),
        if (verbs.isNotEmpty) ...[
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: verbs),
        ],
      ]),
    );
  }
}
