// lib/features/org/org_member_pages.dart — the teacher / student side of organizations.
//
//   OrgHomeEntry          a card for the teacher home and the student home ("My organizations / Join an organization")
//   OrgMembershipScreen   my organizations (active · pending) + join by search or code
//   OrgCoursesScreen      one organization's courses → opens the normal course page (subscribe/payment as usual)
//   OrgTimetableScreen    my weekly timetable from the published schedule (teacher · assistant · student)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/course/course_access.dart' show openCourse;
import 'package:flutter_education_app/features/student/models.dart' show CourseModel;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_member_space.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_academic_pages.dart' show orgCourseGate;
import 'org_access_joining.dart' show openOrgJoin;
import 'org_v3.dart' show membershipStatusLabels, orgCodeText;

// ═════════════════════════════════════════════════════════════════════════════
//  Home entry card
// ═════════════════════════════════════════════════════════════════════════════

class OrgHomeEntry extends StatelessWidget {
  const OrgHomeEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgMembershipProvider()..loadMine(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgMembershipProvider>();
        final c = context.colors;
        final active = p.mine.where((m) => m['status'] == 'active').toList();
        final pending = p.mine.where((m) => m['status'] == 'pending').length;
        final first = active.isEmpty ? null : Map<String, dynamic>.from(active.first['organization'] as Map);
        final base = first == null ? c.primary : orgColor(context, first);
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgMembershipScreen())).then((_) => p.loadMine()),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd, colors: [base.withValues(alpha: 0.95), Color.alphaBlend(Colors.black.withValues(alpha: 0.25), base)]),
              boxShadow: [BoxShadow(color: base.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Icon(first == null ? Icons.add_business_rounded : (orgTypeIcons[first['type']] ?? Icons.domain_rounded), color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    first == null ? t('انضم إلى جامعتك أو كليتك', 'Join your university or faculty') : OrgSession.nameOf(first),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'bahji', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  Text(
                    first == null
                        ? (pending > 0 ? t('طلبك قيد المراجعة', 'Your request is being reviewed') : t('اطّلع على كورسات مؤسستك واشترك بها', "See your institution's courses and subscribe"))
                        : t('${active.length} مؤسسة · الكورسات والجدول', '${active.length} organization(s) · courses & timetable'),
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        );
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  My organizations + join
// ═════════════════════════════════════════════════════════════════════════════

class OrgMembershipScreen extends StatelessWidget {
  const OrgMembershipScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (_) => OrgMembershipProvider()..loadMine(), child: const _MembershipView());
}

class _MembershipView extends StatelessWidget {
  const _MembershipView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgMembershipProvider>();
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      maxWith: 700,
      appBar: ScreenAppBar(title: t('مؤسساتي', 'My organizations')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'org_join',
        backgroundColor: c.primary,
        onPressed: () => openOrgJoin(context, onDone: p.loadMine),   // org_access_joining.dart: code · browse · my requests
        icon: const Icon(Icons.add_business_rounded, color: Colors.white),
        label: Text(t('انضمام لمؤسسة', 'Join an organization'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
      ),
      child: !p.loaded
          ? const Center(child: AppLoadingIndicator(size: 64))
          : p.mine.isEmpty
              ? OrgEmpty(icon: Icons.domain_rounded, title: t('لم تنضم لأي مؤسسة بعد', "You haven't joined an organization yet"))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                  for (final m in p.mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrgCard(m: m),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgTimetableScreen())),
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(t('جدولي الدراسي', 'My timetable')),
                    ),
                  ),
                ]),
    );
  }
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = Map<String, dynamic>.from(m['organization'] as Map);
    final status = '${m['status']}';
    final col = orgColor(context, o);
    final p = context.read<OrgMembershipProvider>();
    return RowCard(
      accent: col,
      onTap: status == 'active'
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: o)))
          : null,
      child: Row(children: [
        IconBadge(orgTypeIcons[o['type']] ?? Icons.domain_rounded, col, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(OrgSession.nameOf(o), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 15, color: c.textDark)),
            Text(orgTypeLabels()[o['type']] ?? '', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
            const SizedBox(height: 6),
            StatusChip(
              status == 'active' ? t('عضو', 'Member') : status == 'rejected' ? t('مرفوض', 'Declined') : membershipStatusLabels()[status] ?? status,
              status == 'active' ? c.success : status == 'pending' ? c.warning : c.danger,
            ),
            // only this organization's membership ended — the account and its other services keep working
            if (status == 'expired' || status == 'suspended')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(orgCodeText('membership_ended'), style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.textMedium)),
              ),
          ]),
        ),
        if (status == 'active') const Icon(Icons.chevron_right_rounded),
        if (status != 'active' || m['role'] == 'student' || m['role'] == 'teacher')
          IconButton(
            icon: Icon(Icons.logout_rounded, color: c.textLight, size: 20),
            tooltip: t('خروج', 'Leave'),
            onPressed: () async {
              if (await confirm(context, message: t('الخروج من المؤسسة؟ اشتراكاتك في الكورسات تبقى كما هي.', 'Leave this organization? Your course enrollments stay.'), danger: true)) {
                p.leave(asInt(o['id']));
              }
            },
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One organization's courses
// ═════════════════════════════════════════════════════════════════════════════

class OrgCoursesScreen extends StatelessWidget {
  const OrgCoursesScreen({super.key, required this.org});
  final Map<String, dynamic> org;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => OrgMembershipProvider()..loadCourses(asInt(org['id'])),
        child: _CoursesBody(org: org),
      );
}

class _CoursesBody extends StatelessWidget {
  const _CoursesBody({required this.org});
  final Map<String, dynamic> org;

  Future<void> _open(BuildContext context, Map<String, dynamic> row) async {
    // archived course → closed (request the last version); fresh / granted → open as usual
    if (!await orgCourseGate(context, asInt(row['id'])) || !context.mounted) return;
    // membership covers it: join at no cost
    if (row['free_for_me'] == true && row['is_enrolled'] != true) {
      if (!await confirm(context, message: t('هذا المقرر مجاني لأعضاء مؤسستك — انضم الآن؟', 'Free for your organization\'s members — join now?'))) return;
      final r = await OrgApi.i.post('$orgBase/public/courses/${row['id']}/join-free', null, t('انضممت للمقرر 🎉', 'You joined the course 🎉'));
      if (r == null || !context.mounted) return;
    }
    try {
      final api = ApiClient();
      final json = await api.get('/api/v1/courses/${row['id']}');
      if (json is Map && context.mounted) {
        await openCourse(context, CourseModel.fromJson(Map<String, dynamic>.from(json)), api);
      }
    } on ApiException catch (e) {
      toast(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgMembershipProvider>();
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: OrgSession.nameOf(org)),
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        OrgHero(
          org: org,
          subtitle: t('كورسات مؤسستك', 'Your institution’s courses'),
          trailing: IconButton(
            tooltip: t('جدولي', 'My timetable'),
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: asInt(org['id'])))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SearchBox(hint: t('ابحث عن كورس', 'Search a course'), onChanged: (q) => p.loadCourses(asInt(org['id']), search: q)),
        ),
        if (p.isLoading && p.courses.isEmpty)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: AppLoadingIndicator(size: 56)))
        else if (p.courses.isEmpty)
          SizedBox(height: 240, child: OrgEmpty(icon: Icons.menu_book_rounded, title: t('لا توجد كورسات منشورة بعد', 'No published courses yet')))
        else
          for (final row in p.courses)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: RowCard(
                onTap: () => _open(context, row),
                child: Row(children: [
                  IconBadge(Icons.menu_book_rounded, c.primary, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('${row['name_ar'] ?? row['name_en']}', '${row['name_en'] ?? row['name_ar']}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                      if (row['teacher'] != null) Text('${(row['teacher'] as Map)['name']}', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, children: [
                        InfoChip(Icons.payments_rounded, asDouble(row['fees']) == 0 ? t('مجاني', 'Free') : money(asDouble(row['fees'])), c.success),
                        if (row['is_enrolled'] == true) StatusChip(t('مشترك', 'Enrolled'), c.primary),
                      ]),
                    ]),
                  ),
                  Icon(row['is_enrolled'] == true ? Icons.play_circle_rounded : Icons.chevron_right_rounded, color: c.primary),
                ]),
              ),
            ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  My timetable
// ═════════════════════════════════════════════════════════════════════════════

class OrgTimetableScreen extends StatelessWidget {
  const OrgTimetableScreen({super.key, this.orgId});
  final int? orgId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => OrgMembershipProvider()..loadTimetable(orgId: orgId),
        child: const _TimetableView(),
      );
}

class _TimetableView extends StatelessWidget {
  const _TimetableView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgMembershipProvider>();
    final c = context.colors;
    final labels = dayLabels();
    return BasePage(
      useWebCard: true,
      maxWith: 800,
      appBar: ScreenAppBar(title: t('جدولي الدراسي', 'My timetable')),
      child: p.isLoading && p.timetables.isEmpty
          ? const Center(child: AppLoadingIndicator(size: 64))
          : p.timetables.isEmpty
              ? OrgEmpty(icon: Icons.calendar_month_rounded, title: t('لم يُنشر جدول بعد', 'No timetable published yet'))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
                  for (final tt in p.timetables) ...[
                    Text('${(tt['schedule'] as Map)['name']}', style: c.h2),
                    const SizedBox(height: 8),
                    for (final day in orgDays)
                      if (asMapList(tt['items']).any((x) => x['day'] == day)) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 6),
                          child: Text(labels[day]!, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.primary, fontSize: 14)),
                        ),
                        for (final x in (asMapList(tt['items']).where((x) => x['day'] == day).toList()..sort((a, b) => asInt(a['order']).compareTo(asInt(b['order'])))))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: RowCard(
                              child: Row(children: [
                                Container(
                                  width: 64,
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                                  child: Column(children: [
                                    Text('${x['start_time'] ?? ''}', textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: c.primary, fontSize: 13)),
                                    Text('${x['end_time'] ?? ''}', textDirection: TextDirection.ltr, style: TextStyle(color: c.textLight, fontSize: 11)),
                                  ]),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${x['course'] ?? ''}', style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                                    Text([if (x['room'] != null) '${x['room']}', if (x['teacher'] != null) '${x['teacher']}'].join(' · '), style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                      ],
                  ],
                ]),
    );
  }
}
