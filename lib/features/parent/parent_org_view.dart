// lib/features/parent/parent_org_view.dart — a parent sees their child's organization (C2, kill switch parent.org_view).
//
//   GET /api/v1/org/parent/children                          → {children: [{student, orgs: [...]}]}
//   GET /api/v1/org/parent/children/{sid}/orgs/{org_id}      → today · next 7 days · announcements · grades · attendance
//
// Read-only. The pieces:
//   parseParentChildren / ParentOrgView.parse   pure parsers (unit-tested; every key optional, an older / newer server
//                                               never throws)
//   ParentOrgApi                                the two calls
//   ParentOrgChildrenList                       presentational: one calm card per child that has organizations
//   ParentOrgChildrenCard                       loads the list for the parent home (hidden when nothing to show, a compact
//                                               Retry when the load failed)
//   ParentOrgScreen / ParentOrgBody             one child + one organization (plain-values body, layout-tested)
//
// Layout tests: test/ui/of_f4_parent_org_layout_test.dart; flows: test/org/of_f4_parent_org_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../admin/admin_common.dart' show t, asInt, asMap, asMapList;
import '../org/org_v3.dart' show orgParseUtc;

/// The kill switch of this whole surface.
const parentOrgViewKey = 'parent.org_view';

String _s(dynamic v) => v == null ? '' : '$v';

/// The Arabic or English name by the app language, falling back to the other one.
String _bilingual(String ar, String en) {
  final a = ar.trim(), e = en.trim();
  final first = t(a, e), second = t(e, a);
  return first.isNotEmpty ? first : second;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Models (pure)
// ═════════════════════════════════════════════════════════════════════════════

class ParentOrgRef {
  const ParentOrgRef({required this.id, this.nameAr = '', this.nameEn = '', this.logoUrl, this.role = '', this.status = ''});
  final int id;
  final String nameAr, nameEn;
  final String? logoUrl;
  final String role, status;

  String get name => _bilingual(nameAr, nameEn);

  factory ParentOrgRef.parse(Map<String, dynamic> j) => ParentOrgRef(
        id: asInt(j['id']),
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        logoUrl: _s(j['logo_url']).isEmpty ? null : _s(j['logo_url']),
        role: _s(j['role']),
        status: _s(j['status']),
      );
}

class ParentChildOrgs {
  const ParentChildOrgs({required this.studentId, required this.name, this.avatarUrl, this.orgs = const []});
  final int studentId;
  final String name;
  final String? avatarUrl;
  final List<ParentOrgRef> orgs;
}

/// The children of `GET /org/parent/children` that belong to at least one organization.
List<ParentChildOrgs> parseParentChildren(dynamic json) {
  final out = <ParentChildOrgs>[];
  for (final c in asMapList(asMap(json)['children'])) {
    final st = asMap(c['student']);
    final orgs = [for (final o in asMapList(c['orgs'])) ParentOrgRef.parse(o)];
    if (orgs.isEmpty) continue;
    out.add(ParentChildOrgs(
      studentId: asInt(st['id']),
      name: _s(st['name']),
      avatarUrl: _s(st['avatar_url']).isEmpty ? null : _s(st['avatar_url']),
      orgs: orgs,
    ));
  }
  return out;
}

enum ParentSessionStatus { scheduled, changed, cancelled }

class ParentOrgSession {
  const ParentOrgSession({
    this.title = '',
    this.courseName = '',
    this.startsAt,
    this.endsAt,
    this.room = '',
    this.online = false,
    this.status = ParentSessionStatus.scheduled,
  });
  final String title, courseName, room;
  final DateTime? startsAt, endsAt; // UTC
  final bool online;
  final ParentSessionStatus status;

  String get heading => title.isNotEmpty ? title : courseName;

  factory ParentOrgSession.parse(Map<String, dynamic> j) => ParentOrgSession(
        title: _s(j['title']),
        courseName: _s(j['course_name']),
        startsAt: orgParseUtc(j['starts_at'])?.toUtc(),
        endsAt: orgParseUtc(j['ends_at'])?.toUtc(),
        room: _s(j['room']),
        online: _s(j['mode']) == 'online',
        status: switch (_s(j['status'])) {
          'changed' => ParentSessionStatus.changed,
          'cancelled' => ParentSessionStatus.cancelled,
          _ => ParentSessionStatus.scheduled,
        },
      );
}

class ParentOrgAnnouncement {
  const ParentOrgAnnouncement({required this.id, this.title = '', this.body = '', this.publishedAt});
  final int id;
  final String title, body;
  final DateTime? publishedAt;
}

class ParentOrgGrade {
  const ParentOrgGrade({this.courseName = '', this.grade = '', this.points, this.termLabel = '', this.publishedAt});
  final String courseName, grade, termLabel;
  final double? points;
  final DateTime? publishedAt;
}

class ParentOrgAttendance {
  const ParentOrgAttendance({this.present = 0, this.absent = 0, this.late = 0});
  final int present, absent, late;
  int get total => present + absent + late;

  /// 0..1 share of attended sessions (late counts as attended), null when nothing is recorded.
  double? get rate => total == 0 ? null : (present + late) / total;
}

class ParentOrgView {
  const ParentOrgView({
    required this.org,
    this.studentName = '',
    this.today = const [],
    this.week = const [],
    this.announcements = const [],
    this.grades = const [],
    this.attendance,
  });
  final ParentOrgRef org;
  final String studentName;
  final List<ParentOrgSession> today, week;
  final List<ParentOrgAnnouncement> announcements;
  final List<ParentOrgGrade> grades;
  final ParentOrgAttendance? attendance;

  factory ParentOrgView.parse(dynamic json) {
    final j = asMap(json);
    final att = j['attendance'];
    return ParentOrgView(
      org: ParentOrgRef.parse(asMap(j['org'])),
      studentName: _s(asMap(j['student'])['name']),
      today: [for (final x in asMapList(j['today'])) ParentOrgSession.parse(x)],
      week: [for (final x in asMapList(j['week'])) ParentOrgSession.parse(x)],
      announcements: [
        for (final x in asMapList(j['announcements']))
          ParentOrgAnnouncement(id: asInt(x['id']), title: _s(x['title']), body: _s(x['body']), publishedAt: orgParseUtc(x['published_at'])?.toUtc()),
      ],
      grades: [
        for (final x in asMapList(j['grades']))
          ParentOrgGrade(
            courseName: _s(x['course_name']),
            grade: _s(x['grade']),
            points: x['points'] is num ? (x['points'] as num).toDouble() : double.tryParse(_s(x['points'])),
            termLabel: _s(x['term_label']),
            publishedAt: orgParseUtc(x['published_at'])?.toUtc(),
          ),
      ],
      attendance: att is Map
          ? ParentOrgAttendance(present: asInt(att['present']), absent: asInt(att['absent']), late: asInt(att['late']))
          : null,
    );
  }
}

/// The week's sessions grouped by calendar day (in the effective timezone), days in order, each day by start time.
List<(DateTime day, List<ParentOrgSession> sessions)> parentWeekByDay(List<ParentOrgSession> week) {
  final byDay = <DateTime, List<ParentOrgSession>>{};
  for (final s in week) {
    final at = s.startsAt;
    if (at == null) continue;
    final w = AppTime.toZone(at);
    byDay.putIfAbsent(DateTime(w.year, w.month, w.day), () => []).add(s);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final d in days) (d, byDay[d]!..sort((a, b) => a.startsAt!.compareTo(b.startsAt!))),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
//  The calls
// ═════════════════════════════════════════════════════════════════════════════

class ParentOrgApi {
  const ParentOrgApi._();

  static Future<List<ParentChildOrgs>> children() async =>
      parseParentChildren(await ApiClient().get('/api/v1/org/parent/children'));

  static Future<ParentOrgView> view(int studentId, int orgId) async =>
      ParentOrgView.parse(await ApiClient().get('/api/v1/org/parent/children/$studentId/orgs/$orgId'));
}

// ═════════════════════════════════════════════════════════════════════════════
//  The home card
// ═════════════════════════════════════════════════════════════════════════════

void openParentOrg(BuildContext context, ParentChildOrgs child, ParentOrgRef org) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ParentOrgScreen(studentId: child.studentId, studentName: child.name, org: org)),
    );

/// Loads the children's organizations for the parent home. Nothing is drawn while loading or when no child is in an
/// organization (a calm home); a failed load is one slim row with Retry.
class ParentOrgChildrenCard extends StatefulWidget {
  const ParentOrgChildrenCard({super.key, this.loader});

  /// Test seam; the real call by default.
  final Future<List<ParentChildOrgs>> Function()? loader;

  @override
  State<ParentOrgChildrenCard> createState() => _ParentOrgChildrenCardState();
}

class _ParentOrgChildrenCardState extends State<ParentOrgChildrenCard> {
  List<ParentChildOrgs>? _children;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_error != null) setState(() => _error = null);
    try {
      final r = await (widget.loader ?? ParentOrgApi.children)();
      if (mounted) setState(() => _children = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _error != null
        ? Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
            child: AppErrorState(compact: true, message: appErrorMessage(_error), onRetry: _load),
          )
        : (_children == null || _children!.isEmpty)
            ? const SizedBox.shrink()
            : ParentOrgChildrenList(
                children: _children!,
                onOpen: (c, o) => openParentOrg(context, c, o),
              );
    return ParentComponent(featureKey: parentOrgViewKey, child: child);
  }
}

class ParentOrgChildrenList extends StatelessWidget {
  const ParentOrgChildrenList({super.key, required this.children, required this.onOpen});
  final List<ParentChildOrgs> children;
  final void Function(ParentChildOrgs child, ParentOrgRef org) onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
      child: AppSection(
        title: t('مؤسسات أبنائي', "My children's organizations"),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in children)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: _ChildOrgsCard(child: c, onOpen: onOpen),
            ),
        ]),
      ),
    );
  }
}

class _ChildOrgsCard extends StatelessWidget {
  const _ChildOrgsCard({required this.child, required this.onOpen});
  final ParentChildOrgs child;
  final void Function(ParentChildOrgs child, ParentOrgRef org) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxs),
          child: Text(child.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
        ),
        for (final o in child.orgs)
          InkWell(
            key: ValueKey('parent.org.${child.studentId}.${o.id}'),
            onTap: () => onOpen(child, o),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
                child: Row(children: [
                  Icon(Icons.apartment_rounded, size: AppIconSize.md, color: c.primary),
                  AppSpace.gapSm,
                  Expanded(
                    child: Text(o.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  ),
                  if (o.status.isNotEmpty && o.status != 'active' && o.status != 'approved')
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                      child: AppStatusBadge(label: statusLabel(o.status), tone: AppTone.warning, dense: true),
                    ),
                  Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One child, one organization
// ═════════════════════════════════════════════════════════════════════════════

class ParentOrgScreen extends StatefulWidget {
  const ParentOrgScreen({super.key, required this.studentId, required this.studentName, required this.org, this.loader});
  final int studentId;
  final String studentName;
  final ParentOrgRef org;

  /// Test seam; the real call by default.
  final Future<ParentOrgView> Function(int studentId, int orgId)? loader;

  @override
  State<ParentOrgScreen> createState() => _ParentOrgScreenState();
}

class _ParentOrgScreenState extends State<ParentOrgScreen> {
  ParentOrgView? _view;
  Object? _error;
  bool _loading = true;
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await (widget.loader ?? ParentOrgApi.view)(widget.studentId, widget.org.id);
      if (mounted) {
        setState(() {
          _view = v;
          _updated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    final orgName = v?.org.name.isNotEmpty == true ? v!.org.name : widget.org.name;
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      child: Column(children: [
        AppPageHeader(
          title: orgName,
          subtitle: widget.studentName,
          icon: Icons.apartment_rounded,
          onBack: () => Navigator.of(context).maybePop(),
          onRefresh: _load,
          updatedAt: _updated,
        ),
        Expanded(
          child: AppStateView<ParentOrgView>(
            loading: _loading && v == null,
            error: _error,
            data: v,
            onRetry: _load,
            loadingShape: AppLoadingShape.cards,
            builder: (context, view) => AppRefresh(onRefresh: _load, child: ParentOrgBody(view: view, childName: widget.studentName)),
          ),
        ),
      ]),
    );
  }
}

/// The page body over plain values.
class ParentOrgBody extends StatelessWidget {
  const ParentOrgBody({super.key, required this.view, this.childName = ''});
  final ParentOrgView view;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final name = childName.isNotEmpty ? childName : view.studentName;
    final days = parentWeekByDay(view.week);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
      children: [
        AppSection(
          title: t('اليوم', 'Today'),
          child: view.today.isEmpty
              ? _Note(
                  icon: Icons.wb_sunny_outlined,
                  title: t('لا حصص اليوم', 'No sessions today'),
                  message: t('إن كان لدى $name حصص هذا الأسبوع فستجدها أدناه', 'Any sessions $name has this week are listed below'))
              : _SessionList(view.today),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('الأيام السبعة القادمة', 'Next 7 days'),
          child: days.isEmpty
              ? _Note(
                  icon: Icons.event_busy_rounded,
                  title: t('لا حصص قادمة', 'No upcoming sessions'),
                  message: t('يظهر الجدول هنا بعد أن تنشره المؤسسة', 'The timetable appears here once the organization publishes it'))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (day, sessions) in days) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxs),
                      child: Text(AppTime.date(day.toUtc(), pattern: 'EEEE d MMM'), style: AppType.label(context)),
                    ),
                    _SessionList(sessions, showDay: false),
                  ],
                ]),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('آخر الإعلانات', 'Latest announcements'),
          child: view.announcements.isEmpty
              ? _Note(
                  icon: Icons.campaign_outlined,
                  title: t('لا إعلانات', 'No announcements'),
                  message: t('إعلانات المؤسسة الموجهة لـ $name تظهر هنا', 'Announcements the organization sends to $name appear here'))
              : Column(children: [for (final a in view.announcements) _AnnouncementRow(a)]),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('الدرجات المنشورة', 'Published grades'),
          child: view.grades.isEmpty
              ? _Note(
                  icon: Icons.grade_outlined,
                  title: t('لا درجات منشورة', 'No published grades'),
                  message: t('تظهر الدرجات هنا بعد أن تنشرها المؤسسة (قد لا تستخدم هذه المؤسسة نظام الدرجات)',
                      'Grades appear here once the organization publishes them (this organization may not use grades)'))
              : Column(children: [for (final g in view.grades) _GradeRow(g)]),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('الحضور', 'Attendance'),
          child: view.attendance == null || view.attendance!.total == 0
              ? _Note(
                  icon: Icons.fact_check_outlined,
                  title: t('لا سجل حضور بعد', 'No attendance recorded yet'),
                  message: t('ملخص الحضور يظهر بعد تسجيله في الحصص', 'The summary appears once attendance is taken in sessions'))
              : _AttendanceRow(view.attendance!),
        ),
      ],
    );
  }
}

/// An empty section that says why and what to expect.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title, message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.lg, color: c.textLight),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.row(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(message, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList(this.sessions, {this.showDay = false});
  final List<ParentOrgSession> sessions;
  final bool showDay;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final s in sessions) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: _SessionRow(s)),
      ]);
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(this.s);
  final ParentOrgSession s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cancelled = s.status == ParentSessionStatus.cancelled;
    final a = s.startsAt, b = s.endsAt;
    final time = a == null ? '' : (b == null ? AppTime.time(a) : '${AppTime.time(a)} – ${AppTime.time(b)}');
    final sub = [
      if (s.title.isNotEmpty && s.courseName.isNotEmpty) s.courseName,
      if (s.room.isNotEmpty) s.room,
    ].join(' · ');
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(s.online ? Icons.videocam_outlined : Icons.meeting_room_outlined, size: AppIconSize.md, color: cancelled ? c.textLight : c.primary),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.heading,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.row(context).copyWith(decoration: cancelled ? TextDecoration.lineThrough : null)),
            if (time.isNotEmpty) Text(time, style: AppType.meta(context)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            if (s.status != ParentSessionStatus.scheduled || s.online)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                  if (s.status == ParentSessionStatus.changed) AppStatusBadge(label: t('تغيّرت', 'Changed'), tone: AppTone.warning, dense: true),
                  if (cancelled) AppStatusBadge(label: t('أُلغيت', 'Cancelled'), tone: AppTone.danger, dense: true),
                  if (s.online) AppStatusBadge(label: t('أونلاين', 'Online'), tone: AppTone.info, dense: true),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  const _AnnouncementRow(this.a);
  final ParentOrgAnnouncement a;

  @override
  Widget build(BuildContext context) {
    final at = a.publishedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
          if (a.body.isNotEmpty) Text(a.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
          if (at != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(AppTime.date(at), style: AppType.meta(context))),
        ]),
      ),
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow(this.g);
  final ParentOrgGrade g;

  @override
  Widget build(BuildContext context) {
    final sub = [if (g.termLabel.isNotEmpty) g.termLabel, if (g.publishedAt != null) AppTime.date(g.publishedAt!)].join(' · ');
    final pts = g.points == null ? '' : (g.points! == g.points!.roundToDouble() ? '${g.points!.round()}' : g.points!.toStringAsFixed(1));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.courseName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          AppSpace.gapSm,
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(g.grade, style: AppType.figure(context)),
            if (pts.isNotEmpty) Text(pts, style: AppType.meta(context)),
          ]),
        ]),
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow(this.a);
  final ParentOrgAttendance a;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String label, int n, Color tone) => Expanded(
          child: Column(children: [
            Text('$n', style: AppType.figure(context).copyWith(color: tone)),
            Text(label, textAlign: TextAlign.center, style: AppType.meta(context)),
          ]),
        );
    return AppCard(
      child: Row(children: [
        cell(t('حضر', 'Present'), a.present, c.success),
        cell(t('غاب', 'Absent'), a.absent, c.danger),
        cell(t('تأخر', 'Late'), a.late, c.warning),
      ]),
    );
  }
}
