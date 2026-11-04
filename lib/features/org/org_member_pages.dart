// lib/features/org/org_member_pages.dart — the teacher / student side of organizations.
//
//   OrgHomeEntry          a card for the teacher home and the student home ("My organizations / Join an organization")
//   OrgMembershipScreen   my organizations (active · pending) + join by search or code
//   OrgCoursesScreen      one organization's courses → opens the normal course page (subscribe/payment as usual)
//   OrgTimetableScreen    my weekly timetable from the published schedule (teacher · assistant · student)
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/course/course_access.dart' show openCourse;
import 'package:flutter_education_app/features/student/models.dart' show CourseModel;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh, AppTime, AppType;
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'package:url_launcher/url_launcher.dart';
import 'org_member_changes.dart';
import 'org_schedule_reassign.dart' show pickSlotDate;
import 'org_my_exams.dart' show examPauseBanner, examPausesOf, openMyExams;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_academic_pages.dart' show orgCourseGate;
import 'org_access_joining.dart' show openOrgJoin;
import 'org_v3.dart' show membershipStatusLabels, orgCodeText;
import 'package:flutter_education_app/design/app_kit.dart' show appConfirm;
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton, AppButtonSize;
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
          // "Join your university" opens the join flow itself (L6: it opened an empty "My organizations" list);
          // with a membership or a request under review it opens the list.
          onTap: () => first == null && pending == 0 && p.loaded
              ? openOrgJoin(context, onDone: p.loadMine)
              : Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgMembershipScreen())).then((_) => p.loadMine()),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd, colors: [base.withValues(alpha: 0.95), c.heroEnd(base, 0.25)]),
              boxShadow: [BoxShadow(color: base.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: c.onHero.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Icon(first == null ? Icons.add_business_rounded : (orgTypeIcons[first['type']] ?? Icons.domain_rounded), color: c.onHero),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    first == null ? t('انضم إلى جامعتك أو كليتك', 'Join your university or faculty') : OrgSession.nameOf(first),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.section(context).copyWith(color: c.onHero),
                  ),
                  Text(
                    first == null
                        ? (pending > 0 ? t('طلبك قيد المراجعة', 'Your request is being reviewed') : t('اطّلع على كورسات مؤسستك واشترك بها', "See your institution's courses and subscribe"))
                        : t('${active.length} مؤسسة · الكورسات والجدول', '${active.length} organization(s) · courses & timetable'),
                    style: AppType.meta(context).copyWith(color: c.onHeroMuted),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.onHero),
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
        icon: Icon(Icons.add_business_rounded, color: c.onHero),
        label: Text(t('انضمام لمؤسسة', 'Join an organization'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
      ),
      child: !p.loaded
          ? const AppListSkeleton()
          : p.mine.isEmpty
              ? ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                  deferredOrgMyInvitationsCard(onChanged: p.loadMine),
                  OrgEmpty(icon: Icons.domain_rounded, title: t('لم تنضم لأي مؤسسة بعد', "You haven't joined an organization yet")),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                  deferredOrgMyInvitationsCard(onChanged: p.loadMine),
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
    final card = RowCard(
      accent: col,
      onTap: status == 'active'
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: o)))
          : null,
      child: Row(children: [
        IconBadge(orgTypeIcons[o['type']] ?? Icons.domain_rounded, col, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(OrgSession.nameOf(o), style: AppType.section(context)),
            Text(orgTypeLabels()[o['type']] ?? '', style: AppType.meta(context)),
            const SizedBox(height: 6),
            StatusChip(
              status == 'active' ? t('عضو', 'Member') : status == 'rejected' ? t('مرفوض', 'Declined') : status == 'removed' ? t('أُزيل', 'Removed') : membershipStatusLabels()[status] ?? status,
              status == 'active' ? c.success : status == 'pending' ? c.warning : status == 'removed' ? c.textMedium : c.danger,
            ),
            // only this organization's membership ended — the account and its other services keep working
            if (status == 'expired' || status == 'suspended')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(orgCodeText('membership_ended'), style: AppType.meta(context)),
              ),
          ]),
        ),
        if (status == 'active') const Icon(Icons.chevron_right_rounded),
      ]),
    );
    final leavable = status != 'active' || m['role'] == 'student' || m['role'] == 'teacher';
    if (!leavable) return card;
    // a labelled action under the card (text + icon), not an icon alone
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card,
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton.ghost(
          key: ValueKey('org.leave.${o['id']}'),
          label: status == 'pending' ? t('سحب الطلب', 'Withdraw request') : t('الخروج من المؤسسة', 'Leave organization'),
          icon: DirIcons.logout,
          size: AppButtonSize.sm,
          onPressed: () async {
            final active = status == 'active';
            if (await appConfirm(
              context,
              danger: true,
              confirmLabel: active ? t('خروج', 'Leave') : t('سحب', 'Withdraw'),
              message: active
                  ? t('الخروج من «${OrgSession.nameOf(o)}»؟ تفقد وصولك إلى صفوفها وجداولها وإعلاناتها، وتبقى اشتراكاتك في الكورسات كما هي. يمكنك الانضمام مجدداً بكود أو بطلب جديد.',
                      'Leave "${OrgSession.nameOf(o)}"? You lose access to its classes, timetable and announcements; your course enrollments stay. You can join again with a code or a new request.')
                  : t('سحب الطلب المرسل إلى «${OrgSession.nameOf(o)}»؟', 'Withdraw your request to "${OrgSession.nameOf(o)}"?'),
            )) {
              p.leave(asInt(o['id']));
            }
          },
        ),
      ),
    ]);
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
            icon: Icon(Icons.calendar_month_rounded, color: c.onHero),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: asInt(org['id'])))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SearchBox(hint: t('ابحث عن كورس', 'Search a course'), onChanged: (q) => p.loadCourses(asInt(org['id']), search: q)),
        ),
        if (p.isLoading && p.courses.isEmpty)
          const AppListSkeleton(items: 3)
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
                      Text(t('${row['name_ar'] ?? row['name_en']}', '${row['name_en'] ?? row['name_ar']}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, color: c.textDark)),
                      if (row['teacher'] != null) Text('${(row['teacher'] as Map)['name']}', style: AppType.meta(context)),
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
        child: _TimetableView(orgId: orgId),
      );
}

/// One timetable's week as (day, sessions sorted by period) — only days that have sessions, in week order.
List<(String, List<Map<String, dynamic>>)> memberTimetableDays(Map<String, dynamic> tt) {
  final items = asMapList(tt['items']);
  return [
    for (final day in orgDays)
      if (items.any((x) => x['day'] == day))
        (day, items.where((x) => x['day'] == day).toList()..sort((a, b) => asInt(a['order']).compareTo(asInt(b['order'])))),
  ];
}

bool _isLab(Map<String, dynamic> x) => x['kind'] == 'lab' || x['kind'] == 'section';

class _TimetableView extends StatelessWidget {
  const _TimetableView({this.orgId});
  final int? orgId;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgMembershipProvider>();
    Future<void> reload() => p.loadTimetable(orgId: orgId);
    final Widget body;
    if (p.timetables.isEmpty && p.isLoading) {
      body = const AppListSkeleton(items: 6, withAvatar: false);
    } else if (p.timetables.isEmpty && p.hasError) {
      body = Center(
        child: SingleChildScrollView(
          child: OrgEmpty(
            icon: Icons.cloud_off_rounded,
            title: t('تعذّر تحميل جدولك', "Couldn't load your timetable"),
            message: p.errorMessage,
            actionLabel: t('إعادة المحاولة', 'Try again'),
            onAction: reload,
          ),
        ),
      );
    } else if (p.timetables.isEmpty) {
      body = AppRefresh(
        onRefresh: reload,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const SizedBox(height: 40),
          OrgEmpty(
            icon: Icons.calendar_month_rounded,
            title: t('لم يُنشر جدول بعد', 'No timetable published yet'),
            message: t('سيظهر جدولك هنا فور نشره من المؤسسة.', 'Your timetable appears here as soon as it is published.'),
          ),
        ]),
      );
    } else {
      body = AppRefresh(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [for (final tt in p.timetables) ..._timetable(context, tt, reload)],
        ),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 800,
      appBar: ScreenAppBar(title: t('جدولي الدراسي', 'My timetable'), actions: [
        IconButton(
            tooltip: t('امتحاناتي', 'My exams'),
            onPressed: () => openMyExams(context, orgId: orgId),
            icon: const Icon(Icons.event_note_rounded)),
      ]),
      child: body,
    );
  }

  List<Widget> _timetable(BuildContext context, Map<String, dynamic> tt, Future<void> Function() reload) {
    final c = context.colors;
    final labels = dayLabels();
    final sched = asMap(tt['schedule']);
    final extras = asMapList(tt['extras']);
    final changes = [for (final x in asMapList(tt['changes'])) OccurrenceChange.of(x)];
    final orgId = asInt(sched['org_id']);
    // the session's own staff: pick a date of that weekday, then hold it online / back in person
    Future<void> switchDate(Map<String, dynamic> x) async {
      final date = await pickSlotDate(context, '${x['day']}');
      if (date == null || !context.mounted) return;
      final online = await askSessionMode(context, title: '${x['course'] ?? ''}', date: date);
      if (online == null || !context.mounted) return;
      if (await switchSessionMode(context, orgId: orgId, slotId: asInt(x['slot_id']), date: date, online: online)) await reload();
    }
    final days = memberTimetableDays(tt);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(text, style: AppType.bodyStrong(context).copyWith(color: c.primary)),
        );
    return [
      Text('${sched['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: c.h2),
      if ('${sched['term_label'] ?? ''}'.isNotEmpty)
        Text('${sched['term_label']}', style: AppType.meta(context)),
      const SizedBox(height: 8),
      examPauseBanner(context, examPausesOf(tt)),
      if (extras.isNotEmpty) ...[
        heading(t('قادم خلال أسبوعين', 'Coming up (next 2 weeks)')),
        for (final e in extras)
          _SlotRow(
            top: AppTime.clock('${e['start_time'] ?? ''}'),
            bottom: '${e['date'] ?? ''}',
            title: '${e['title'] ?? e['course'] ?? ''}',
            subtitle: [if (e['course'] != null && e['title'] != null) '${e['course']}', if (e['room'] != null) '${e['room']}'].join(' · '),
            accent: c.warning,
          ),
      ],
      if (changes.isNotEmpty) ...[
        heading(t('تغييرات قادمة (أسبوعان)', 'Upcoming changes (2 weeks)')),
        for (final x in changes)
          OccurrenceCard(
            change: x,
            onRespond: x.canRespond ? (d) async { if (await respondToChange(x.id, d)) await reload(); } : null,
            onUndo: x.canEdit ? () async { if (await undoChange(orgId, x.id)) await reload(); } : null,
            onOpenLink: x.onlineUrl == null ? null : () => launchUrl(Uri.parse(x.onlineUrl!), mode: LaunchMode.externalApplication),
          ),
      ],
      if (days.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(t('لا حصص لك في هذا الجدول.', 'You have no sessions in this timetable.'),
              style: TextStyle(fontFamily: AppFonts.family, color: c.textMedium)),
        ),
      for (final (day, items) in days) ...[
        heading(labels[day] ?? day),
        for (final x in items)
          _SlotRow(
            top: AppTime.clock('${x['start_time'] ?? ''}'),
            bottom: AppTime.clock('${x['end_time'] ?? ''}'),
            title: '${x['course'] ?? ''}',
            subtitle: [
              if (_isLab(x)) t('عملي', 'Lab'),
              if (x['room'] != null) '${x['room']}',
              if (x['teacher'] != null) '${x['teacher']}',
            ].join(' · '),
            // its own line, not glued into the room · teacher line (M12)
            hint: x['can_switch'] == true ? t('اضغط لعقدها أونلاين في تاريخ', 'Tap to hold it online on a date') : null,
            accent: _isLab(x) ? c.success : c.primary,
            onTap: x['can_switch'] == true ? () => switchDate(x) : null,
          ),
      ],
      const SizedBox(height: 16),
    ];
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.top, required this.bottom, required this.title, required this.subtitle, required this.accent, this.onTap, this.hint});
  final String top, bottom, title, subtitle;

  /// What a tap does, on its own line under the subtitle (null = nothing to say).
  final String? hint;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RowCard(
        accent: accent,
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 76,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(top, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
                  style: AppType.label(context).copyWith(color: accent)),
              Text(bottom, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
                  style: AppType.overline(context).copyWith(color: c.textLight)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, color: c.textDark)),
              if (subtitle.isNotEmpty)
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context)),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.wifi_tethering_rounded, size: 14, color: c.primary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(hint!, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(color: c.primary)),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
