// lib/features/org/students/student_file_page.dart — THE unified student file (D-1400, phase 1, PLAN.md §3.2).
//
//   OrgStudentFilePage(orgId:, uid:)   loads `GET …/students/{uid}/file` (the server records the open) and wires the tabs
//   StudentFileView(…)                 plain values: the header card, the "opening is recorded" line, the journey
//                                       rail, the tab strip and the chosen tab's body (from [bodyFor])
//   StudentFileHeader(file:)           photo, name ar / en, student number, programme · level, the one chip, flags,
//                                       the missing-data badge
//
// Tabs are lazy: a tab's body is built when it is first chosen, and the timeline keeps its pages when the tab is
// left and opened again. A tab the caller has no right to is not in the strip (studentFileTabs). Open it through
// students_wiring.dart (openStudentFile), never directly. Tests: test/ui/student_file_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../advising/adv_student_page.dart' show AdvStudentPage;
import '../governance/gov_items_page.dart' show GovItemsPage;
import '../onboarding/onboarding_review.dart' show OnbReviewPage;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show OrgSession;
import '../org_registrar_member.dart' show OrgRecordScreen;
import '../org_services_pages.dart' show OrgComplaintsPage;
import '../org_v3.dart' show OrgCall, orgErrorText;
import 'student_file_models.dart';
import 'student_file_tabs.dart';
import 'student_timeline.dart';
import 'students_api.dart';
import 'students_missing_sheet.dart' show showMissingDataSheet;
import 'students_models.dart';
import 'students_parts.dart' show MissingBadge, StudentAvatar, StudentFlagChips, StudentStatusChip;

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

class OrgStudentFilePage extends StatelessWidget {
  const OrgStudentFilePage({super.key, required this.orgId, required this.uid, this.name, this.api});

  final int orgId, uid;

  /// Shown as the title until the file loads.
  final String? name;
  final StudentsApi? api;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: name ?? t('ملف الطالب', 'Student file'),
        subtitle: name == null ? null : t('ملف الطالب', 'Student file'),
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
  late final StudentTimelineController _timeline =
      StudentTimelineController(studentTimelineFetch(widget.api, widget.uid));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
    if (_timeline.loaded) _timeline.load();
  }

  bool get _missingOn => !AppConfig.disableList.contains(kStudentsMissingKey);

  void _openMissing() => showMissingDataSheet(context, widget.orgId, widget.uid, name: _file?.displayName, api: widget.api);

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
        );
      case StudentFileTab.timeline:
        return StudentTimeline(controller: _timeline);
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
  });

  final StudentFile file;
  final StudentFileTab tab;
  final ValueChanged<StudentFileTab> onTab;
  final Widget Function(BuildContext context, StudentFileTab tab)? bodyFor;
  final bool showRecordedNotice;
  final VoidCallback? onMissing;
  final bool missingOn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = studentFileTabs(file.can);
    final index = tabs.indexOf(tab).clamp(0, tabs.length - 1);
    final journey = [for (final n in file.journey) n.toRoadmapNode()];
    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        StudentFileHeader(file: file, onMissing: onMissing, missingOn: missingOn),
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
        if (journey.isNotEmpty) ...[
          AppSpace.gapMd,
          AppCard(
            child: AppRoadmap(
              nodes: journey,
              dense: true,
              quietAfterNext: false,
              label: t('مسار الطالب', "The student's journey"),
            ),
          ),
        ],
        AppSpace.gapLg,
        AppUnderlineTabs(
          items: [for (final x in tabs) AppTabItem(studentFileTabText(x), icon: studentFileTabIcon(x))],
          index: index,
          onChanged: (i) => onTab(tabs[i]),
        ),
        AppSpace.gapMd,
        KeyedSubtree(key: ValueKey('student-file-tab-${tabs[index].name}'), child: bodyFor?.call(context, tabs[index]) ?? const SizedBox.shrink()),
      ],
    );
  }
}

/// The top of the file: photo, names, student number, programme · level, the one chip, flags and the missing badge.
class StudentFileHeader extends StatelessWidget {
  const StudentFileHeader({super.key, required this.file, this.onMissing, this.missingOn = true});

  final StudentFile file;
  final VoidCallback? onMissing;
  final bool missingOn;

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
              child: Text(file.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
            ),
            if (file.otherName != null) Text(file.otherName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
            if (r.studentCode != null || file.programLine != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(
                [
                  if (r.studentCode != null) t('رقم الطالب ${r.studentCode}', 'Student no. ${r.studentCode}'),
                  ?file.programLine,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ],
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StudentStatusChip(r.chip),
              if (missingOn && r.hasMissing) MissingBadge(count: r.missingCount!, onTap: onMissing),
            ]),
            if (r.flags.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              StudentFlagChips(r.flags),
            ],
          ]),
        ),
      ]),
    );
  }
}
