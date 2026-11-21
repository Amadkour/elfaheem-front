// lib/features/org/students/student_file_page.dart — THE unified student file (D-1400, phase 1, PLAN.md §3.2).
//
//   OrgStudentFilePage(orgId:, uid:)   loads `GET …/students/{uid}/file` (the server records the open) and wires the tabs
//   StudentFileView(…)                 plain values: the header card, the "opening is recorded" line, the journey
//                                       rail, the tab strip and the chosen tab's body (from [bodyFor])
//   StudentFileHeader(file:)           photo, name ar / en, student number, programme · level, the one chip, flags,
//                                       the missing-data badge, and "Change status" when `can.status_change` (phase 2)
//
// Phase 2: "Change status" opens showStudentStatusSheet; a status row of the timeline with `can_undo` offers "Undo"
// (confirmUndoStatus). Both reload the file and the timeline when they change something. Who undid an undone change
// comes from GET …/status/events (studentUndoneFetch), only when the timeline shows one.
//
// Actions under the header (each only with its right and switch): "Change status" (the status sheet, which also sends
// to a council when the rules say so), "Ask the student" (showStudentAskSheet: students:update + org.students.asks; the
// asks then show in the timeline's `asks` kind, where the overview's "asks waiting" line lands) and "Transfer credits"
// (showTransferCreditsSheet, for a student flagged `transferred_in`).
//
// Tabs are lazy: a tab's body is built when it is first chosen, and the timeline keeps its pages when the tab is
// left and opened again. A tab the caller has no right to is not in the strip (studentFileTabs). Open it through
// students_wiring.dart (openStudentFile), never directly. Tests: test/ui/student_file_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_bidi.dart' show AutoDirText, bidiIsolate, ltrIsolate;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t, asMapList;
import '../advising/adv_student_page.dart' show AdvStudentPage;
import '../governance/gov_items_page.dart' show GovItemsPage;
import '../onboarding/onboarding_review.dart' show OnbReviewPage;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_providers.dart' show OrgSession;
import '../org_registrar_member.dart' show OrgRecordScreen;
import '../org_services_pages.dart' show OrgComplaintsPage;
import '../org_v3.dart' show OrgCall, orgErrorText;
import 'student_file_models.dart';
import 'my_ask_page.dart' show myAsksEnabled;
import 'student_ask_sheet.dart' show showStudentAskSheet;
import 'student_file_tabs.dart';
import 'student_request_detail.dart' show openStudentRequest;
import 'student_status_models.dart' show StatusEvent;
import 'student_status_sheet.dart' show confirmUndoStatus, showStudentStatusSheet;
import 'student_timeline.dart';
import 'students_api.dart';
import 'students_missing_sheet.dart' show showMissingDataSheet;
import 'students_models.dart';
import 'students_parts.dart' show MissingBadge, StudentAvatar, StudentFlagChips, StudentStandingChip, StudentStatusChip, studentExtraStanding;
import 'transfer_credits_sheet.dart' show showTransferCreditsSheet;

/// Pushes [page] with the organization session of [context] carried over (a pushed route sits outside the
/// dashboard's providers).
Future<T?> pushStudentPage<T>(BuildContext context, Widget page) {
  OrgSession? session;
  try {
    session = context.read<OrgSession>();
  } catch (_) {}
  final Widget child = session == null ? page : ChangeNotifierProvider<OrgSession>.value(value: session, child: page);
  return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => child));
}

/// The timeline call as [StudentTimelineFetch] (the API never throws: a failed call is rethrown for the controller).
StudentTimelineFetch studentTimelineFetch(StudentsApi api, int uid) => ({List<String>? kinds, String? before, int limit = 30}) async {
      final OrgCall r = await api.timeline(uid, kinds: kinds, before: before, limit: limit);
      if (!r.ok) throw r.error!;
      return TimelinePage.fromJson(r.map);
    };

/// Who undid which status change: the undo events (`reverts_id`) of the newest pages of GET …/status/events.
UndoneByFetch studentUndoneFetch(StudentsApi api, int uid, {int maxPages = 3}) => () async {
      final out = <String, UndoneBy>{};
      for (var page = 1; page <= maxPages; page++) {
        final OrgCall r = await api.statusEvents(uid, page: page);
        if (!r.ok) break;
        for (final j in asMapList(r.map['items'])) {
          final e = StatusEvent.fromJson(j);
          final rid = e.revertsId;
          if (rid == null) continue;
          final who = e.actor?.name.trim();
          out['status:$rid'] = UndoneBy(who: who == null || who.isEmpty ? null : who, at: e.createdAt, reason: e.reason);
        }
        if (r.map['has_more'] != true) break;
      }
      return out;
    };

class OrgStudentFilePage extends StatelessWidget {
  const OrgStudentFilePage({super.key, required this.orgId, required this.uid, this.name, this.api});

  final int orgId, uid;

  /// Shown as the title until the file loads.
  final String? name;
  final StudentsApi? api;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: name ?? t('ملف الطالب', 'Student file'),
        // a phone's header has room for one short line: "Updated …" alone (the name already says whose file it is)
        subtitle: name == null || MediaQuery.sizeOf(context).width < AppRoadmap.wideFrom ? null : t('ملف الطالب', 'Student file'),
        helpPageId: 'org.students.file',
        width: AppWidth.content,
        child: _StudentFileBody(orgId: orgId, uid: uid, api: api ?? StudentsApi(orgId)),
      );
}

class _StudentFileBody extends StatefulWidget {
  const _StudentFileBody({required this.orgId, required this.uid, required this.api});
  final int orgId, uid;
  final StudentsApi api;

  @override
  State<_StudentFileBody> createState() => _StudentFileBodyState();
}

class _StudentFileBodyState extends State<_StudentFileBody> {
  /// The "opening this file is recorded" line shows once per app session.
  static bool _noticeSeen = false;

  StudentFile? _file;
  String? _error;
  bool _loading = true;
  StudentFileTab _tab = StudentFileTab.overview;
  bool _showNotice = false;
  late final StudentTimelineController _timeline = StudentTimelineController(
    studentTimelineFetch(widget.api, widget.uid),
    undoneFetch: studentUndoneFetch(widget.api, widget.uid),
  );

  /// The header's Refresh and its "Updated …" line (the pushed page's own scope).
  OrgPageRefresh? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _load);
    _load();
  }

  @override
  void dispose() {
    _refresh?.unregister(_load);
    _timeline.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.api.file(widget.uid);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = orgErrorText(r.error!);
        return;
      }
      _file = StudentFile.fromJson(r.map);
      if (!_noticeSeen) {
        _noticeSeen = true;
        _showNotice = true;
      }
      if (!studentFileTabs(_file!.can).contains(_tab)) _tab = StudentFileTab.overview;
    });
    // "Updated …" in the header starts again from this load
    if (r.ok) _refresh?.markUpdated();
    if (_timeline.loaded) _timeline.load();
  }

  bool get _missingOn => !AppConfig.disableList.contains(kStudentsMissingKey);

  /// "Change status": the sheet saves or sends for approval and says so itself; the file reloads after a change.
  Future<void> _changeStatus() async {
    final r = await showStudentStatusSheet(context, widget.orgId, widget.uid, name: _file?.displayName, api: widget.api);
    if (r != null && mounted) _load();
  }

  /// "Undo this change" on a timeline row (a new compensating event on the server).
  Future<void> _undo(TimelineItem item) async {
    final eid = statusEventIdOf(item);
    if (eid == null) return;
    final r = await confirmUndoStatus(context, widget.orgId, eid, title: item.title, api: widget.api);
    if (r != null && mounted) _load();
  }

  /// The open organization's session (null outside the dashboard, e.g. in tests).
  OrgSession? get _session {
    try {
      return context.read<OrgSession>();
    } catch (_) {
      return null;
    }
  }

  /// "Ask the student": the sheet posts the ask; the file and the timeline reload once one is created.
  Future<void> _ask() async {
    final f = _file;
    if (f == null) return;
    final r = await showStudentAskSheet(context, widget.orgId, widget.uid,
        kind: 'data', name: f.displayName, canFullscreen: _session?.can('student_status', 'update') ?? false, api: widget.api);
    if (r != null && mounted) _load();
  }

  /// The overview's "asks waiting" line: the timeline on its `asks` kind.
  void _showAsks() {
    if (!studentFileTabs(_file!.can).contains(StudentFileTab.timeline)) return;
    if (_timeline.kind != 'asks') {
      _timeline.kind = 'asks';
      if (_timeline.loaded) _timeline.load();
    }
    setState(() => _tab = StudentFileTab.timeline);
  }

  /// The missing-data sheet; each completed item reloads the file, so its count and badge follow at once.
  /// One open lifecycle request: its detail (accept · reject · send to the council); reload the file when it changed.
  Future<void> _openRequest(int id) async {
    final changed = await openStudentRequest(context, widget.orgId, id);
    if (changed == true && mounted) _load();
  }

  void _openMissing() => showMissingDataSheet(context, widget.orgId, widget.uid, name: _file?.displayName, api: widget.api,
      onChanged: () {
        if (mounted) _load();
      });

  Widget _body(BuildContext context, StudentFileTab tab) {
    final f = _file!;
    final oid = widget.orgId;
    switch (tab) {
      case StudentFileTab.overview:
        return StudentOverviewTab(
          file: f,
          missingOn: _missingOn,
          onMissing: f.can.kase ? _openMissing : null,
          onOpenTab: (t) => setState(() => _tab = t),
          onShowAsks: _showAsks,
          onOpenRequest: f.can.requests ? _openRequest : null,
        );
      case StudentFileTab.timeline:
        return StudentTimeline(controller: _timeline, onUndo: f.can.statusChange ? _undo : null);
      case StudentFileTab.academic:
        return StudentAcademicTab(
          academic: f.academic,
          standing: f.row.acadStanding,
          onOpenRecord: () => pushStudentPage<void>(context, OrgRecordScreen(orgId: oid, studentId: widget.uid)),
        );
      case StudentFileTab.documents:
        final caseId = f.intake?.caseId;
        return StudentDocumentsTab(
          intake: f.intake,
          missingCount: f.row.missingCount,
          onOpenCase: caseId == null || !f.can.kase
              ? null
              : () async {
                  await pushStudentPage<void>(context, OnbReviewPage(orgId: oid, caseId: caseId, title: f.displayName));
                  if (mounted) _load();
                },
          onMissing: f.can.kase && _missingOn ? _openMissing : null,
        );
      case StudentFileTab.requests:
        return StudentRequestsTab(
          open: f.open,
          can: f.can,
          onOpenComplaints: () => pushStudentPage<void>(
              context, OrgPushedPage(title: t('الشكاوى', 'Complaints'), child: const OrgComplaintsPage())),
          onOpenRequests: () => pushStudentPage<void>(context, GovItemsPage(orgId: oid)),
          onOpenRequest: _openRequest,
        );
      case StudentFileTab.advising:
        return StudentAdvisingTab(
          advisorName: f.academic?.advisorName,
          onOpen: f.row.memberId <= 0
              ? null
              : () => pushStudentPage<void>(context, AdvStudentPage(orgId: oid, memberId: f.row.memberId, name: f.displayName)),
        );
      case StudentFileTab.accessLog:
        return StudentAccessLogTab(api: widget.api, uid: widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) {
      if (_loading) return const AppListSkeleton(items: 5);
      return AppErrorState(message: _error, onRetry: _load);
    }
    final s = _session;
    final canAsk = myAsksEnabled() && (f.can.ask || (s?.can('students', 'update') ?? false));
    final canCredits = f.row.flags.contains('transferred_in') && (s?.can('students') ?? false);
    return AppRefresh(
      onRefresh: _load,
      child: StudentFileView(
        file: f,
        tab: _tab,
        onTab: (t) => setState(() => _tab = t),
        bodyFor: _body,
        showRecordedNotice: _showNotice,
        onMissing: f.can.kase && _missingOn ? _openMissing : null,
        missingOn: _missingOn,
        onChangeStatus: f.can.statusChange ? _changeStatus : null,
        onAsk: canAsk ? _ask : null,
        onTransferCredits: canCredits ? () => showTransferCreditsSheet(context, widget.orgId, widget.uid, name: f.displayName) : null,
      ),
    );
  }
}

/// The file from plain values. [bodyFor] builds the chosen tab's body (null = an empty body).
class StudentFileView extends StatelessWidget {
  const StudentFileView({
    super.key,
    required this.file,
    required this.tab,
    required this.onTab,
    this.bodyFor,
    this.showRecordedNotice = false,
    this.onMissing,
    this.missingOn = true,
    this.onChangeStatus,
    this.onAsk,
    this.onTransferCredits,
  });

  final StudentFile file;
  final StudentFileTab tab;
  final ValueChanged<StudentFileTab> onTab;
  final Widget Function(BuildContext context, StudentFileTab tab)? bodyFor;
  final bool showRecordedNotice;
  final VoidCallback? onMissing;
  final bool missingOn;

  /// "Change status" in the header; null = the caller may not change it.
  final VoidCallback? onChangeStatus;

  /// "Ask the student" / "Transfer credits" in the header; null = hidden.
  final VoidCallback? onAsk, onTransferCredits;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = studentFileTabs(file.can);
    final index = tabs.indexOf(tab).clamp(0, tabs.length - 1);
    final journey = studentJourney(file.journey, file.row.enrolStatus);
    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        StudentFileHeader(
            file: file, onMissing: onMissing, missingOn: missingOn, onChangeStatus: onChangeStatus, onAsk: onAsk, onTransferCredits: onTransferCredits),
        if (showRecordedNotice) ...[
          AppSpace.gapXs,
          Row(children: [
            Icon(Icons.visibility_outlined, size: AppIconSize.sm, color: c.textMedium),
            const SizedBox(width: AppSpace.xxs),
            Expanded(
              child: Text(
                t('يُسجَّل فتح هذا الملف في سجل الاطلاع', 'Opening this file is recorded in its access log'),
                style: AppType.meta(context).copyWith(color: c.textMedium),
              ),
            ),
          ]),
        ],
        if (journey.nodes.isNotEmpty) ...[
          AppSpace.gapMd,
          // a wide window draws the whole journey in one row (any length), so the tabs stay above the fold
          LayoutBuilder(
            builder: (context, box) => AppCard(
              child: AppRoadmap(
                nodes: journey.nodes,
                next: journey.next,
                axis: box.maxWidth >= AppRoadmap.wideFrom ? Axis.horizontal : null,
                dense: true,
                quietAfterNext: false,
                label: t('مسار الطالب', "The student's journey"),
              ),
            ),
          ),
        ],
        AppSpace.gapLg,
        // the strip scrolls with a mouse drag / shift+wheel on the web too (AppHScroll), never wider than the page
        LayoutBuilder(
          builder: (context, box) => AppHScroll(
            padding: EdgeInsets.zero,
            thumbVisibility: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: AppUnderlineTabs(
                items: [for (final x in tabs) AppTabItem(studentFileTabText(x), icon: studentFileTabIcon(x))],
                index: index,
                onChanged: (i) => onTab(tabs[i]),
              ),
            ),
          ),
        ),
        AppSpace.gapMd,
        KeyedSubtree(key: ValueKey('student-file-tab-${tabs[index].name}'), child: bodyFor?.call(context, tabs[index]) ?? const SizedBox.shrink()),
      ],
    );
  }
}

/// The top of the file: photo, names, student number, programme · level, the one chip, flags and the missing badge.
class StudentFileHeader extends StatelessWidget {
  const StudentFileHeader(
      {super.key, required this.file, this.onMissing, this.missingOn = true, this.onChangeStatus, this.onAsk, this.onTransferCredits});

  final StudentFile file;
  final VoidCallback? onMissing;
  final bool missingOn;
  final VoidCallback? onChangeStatus, onAsk, onTransferCredits;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = file.row;
    final meta = AppType.meta(context).copyWith(color: c.textMedium);
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StudentAvatar(user: r.user, size: AppDashSize.avatarSm),
        AppSpace.gapMd,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: AutoDirText(file.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
            ),
            if (file.otherName != null) AutoDirText(file.otherName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
            if (r.studentCode != null || file.programLine != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(
                [
                  if (r.studentCode != null) t('رقم الطالب ${ltrIsolate(r.studentCode!)}', 'Student no. ${ltrIsolate(r.studentCode!)}'),
                  ?file.programLine,
                ].map(bidiIsolate).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ],
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StudentStatusChip(r.chip),
              if (studentExtraStanding(r.chip, r.acadStanding) != null) StudentStandingChip(chip: r.chip, acadStanding: r.acadStanding),
              if (missingOn && r.hasMissing) MissingBadge(count: r.missingCount!, onTap: onMissing),
            ]),
            if (r.flags.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              StudentFlagChips(r.flags),
            ],
            if (onChangeStatus != null || onAsk != null || onTransferCredits != null) ...[
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (onChangeStatus != null)
                  AppButton.tonal(
                    key: const ValueKey('student-file-change-status'),
                    label: t('تغيير الحالة', 'Change status'),
                    icon: Icons.swap_horiz_rounded,
                    size: AppButtonSize.sm,
                    onPressed: onChangeStatus,
                  ),
                if (onAsk != null)
                  AppButton(
                    key: const ValueKey('student-file-ask'),
                    label: t('اطلب من الطالب', 'Ask the student'),
                    icon: Icons.help_outline_rounded,
                    size: AppButtonSize.sm,
                    variant: AppButtonVariant.ghost,
                    onPressed: onAsk,
                  ),
                if (onTransferCredits != null)
                  AppButton(
                    key: const ValueKey('student-file-transfer-credits'),
                    label: t('المقاصة', 'Transfer credits'),
                    icon: Icons.compare_arrows_rounded,
                    size: AppButtonSize.sm,
                    variant: AppButtonVariant.ghost,
                    onPressed: onTransferCredits,
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
