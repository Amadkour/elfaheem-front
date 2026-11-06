// lib/features/org/advising/adv_comm_entries.dart — where the Phase 5 screens plug into the Phase 2–4 ones (docs/advising/
// PHASE5.md "App"): the advising page's Work tiles (Appointments, Messages with the unread count, My office hours,
// Templates, Ratings), the workspace's strip (unread messages · today's appointments), the advisor sheet's links
// (office hours, ratings) and the 360's Meetings section with its Messages entry.
//
//   advCommSetupTiles · advCommPage · AdvCommStrip · advAdvisorCommLinks · AdvStudentCommPane
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall;
import 'adv_appointments.dart';
import 'adv_appt_models.dart';
import 'adv_availability_page.dart';
import 'adv_comm_api.dart';
import 'adv_models.dart';
import 'adv_student_page.dart' show AdvStudentPage;
import 'adv_survey_sheet.dart' show showAdvFeedbackSheet;
import 'adv_templates_page.dart';
import 'adv_threads.dart';

int? _me(BuildContext context) {
  try {
    return context.read<MyAuthProvider>().currentUser?.id;
  } catch (_) {
    return null;
  }
}

/// The advising page's Phase 5 Work tiles (the keys go to [advCommPage]).
List<Widget> advCommSetupTiles(BuildContext context, AdvStatus st, ValueChanged<String> open) {
  final me = st.me;
  if (!(me.leads || me.advisor)) return const [];
  final c = context.colors;
  final comm = me.comm;
  return [
    AppActionCard(
      icon: Icons.event_note_rounded,
      title: t('المواعيد', 'Appointments'),
      subtitle: comm.appointmentsToday > 0
          ? countText(comm.appointmentsToday, ar1: 'موعد اليوم', ar2: 'موعدان اليوم', arFew: '${comm.appointmentsToday} مواعيد اليوم', arMany: '${comm.appointmentsToday} موعداً اليوم', en1: '1 appointment today', en: '${comm.appointmentsToday} appointments today')
          : (me.leads ? t('كل مواعيد الإرشاد القادمة والسابقة', 'Every advising appointment, upcoming and past') : t('مواعيدك مع طلابك', 'Your appointments with your students')),
      badge: comm.appointmentsToday,
      onTap: () => open('appointments'),
    ),
    AppActionCard(
      icon: Icons.forum_outlined,
      title: t('الرسائل', 'Messages'),
      subtitle: comm.threadsUnread > 0
          ? countText(comm.threadsUnread, ar1: 'رسالة غير مقروءة', ar2: 'رسالتان غير مقروءتين', arFew: '${comm.threadsUnread} رسائل غير مقروءة', arMany: '${comm.threadsUnread} رسالة غير مقروءة', en1: '1 unread message', en: '${comm.threadsUnread} unread messages')
          : t('أسئلة الطلاب وشكاواهم', 'Students\' questions and complaints'),
      badge: comm.threadsUnread,
      color: comm.threadsUnread > 0 ? c.primary : null,
      onTap: () => open('threads'),
    ),
    if (me.advisor)
      AppActionCard(
        icon: Icons.schedule_rounded,
        title: t('ساعاتي المكتبية', 'My office hours'),
        subtitle: t('متى يحجز طلابك، والإجازات', 'When your students can book, and days off'),
        onTap: () => open('availability'),
      ),
    if (me.leads)
      AppActionCard(
        icon: Icons.description_outlined,
        title: t('القوالب', 'Templates'),
        subtitle: t('ملاحظات اللقاء والرسائل الجاهزة', 'Meeting notes and ready-made messages'),
        onTap: () => open('templates'),
      ),
    if (me.leads)
      AppActionCard(
        icon: Icons.star_outline_rounded,
        title: t('تقييمات اللقاءات', 'Meeting ratings'),
        subtitle: t('استبيان مجهول بعد كل لقاء، يظهر من 5 إجابات', 'An anonymous survey after each meeting, shown from 5 answers'),
        onTap: () => open('feedback'),
      ),
  ];
}

/// The page behind a Phase 5 tile, null for a key that is not one of them (the ratings open a sheet: null too).
Widget? advCommPage(BuildContext context, String key, {required int orgId, required AdvStatus status}) {
  final me = _me(context);
  void openStudent(AdvAppointment a) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: orgId, memberId: a.memberId, name: a.studentShown)));
  return switch (key) {
    'appointments' => AdvAppointmentsPage(orgId: orgId, onOpenStudent: openStudent),
    'threads' => AdvThreadsPage(orgId: orgId),
    'availability' when me != null => AdvAvailabilityPage(orgId: orgId, advisorUserId: me),
    'templates' => AdvTemplatesPage(orgId: orgId, manage: status.me.leads),
    _ => null,
  };
}

/// The ratings of the whole organization (the "Meeting ratings" tile).
Future<void> advOpenOrgFeedback(BuildContext context, int orgId) => showAdvFeedbackSheet(context, AdvCommApi(orgId));

/// The advisor sheet's links: office hours and ratings ([manage]: any advisor; else one's own).
List<Widget> advAdvisorCommLinks(BuildContext context, {required int orgId, required AdvAdvisor advisor, required bool manage}) {
  final mine = advisor.userId == _me(context);
  if (!manage && !mine) return const [];
  Widget link(IconData icon, String label, VoidCallback on) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: on, icon: Icon(icon, size: AppIconSize.md), label: Text(label)),
      );
  return [
    const SizedBox(height: AppSpace.sm),
    Divider(color: context.colors.divider),
    link(Icons.schedule_rounded, mine ? t('ساعاتي المكتبية', 'My office hours') : t('الساعات المكتبية', 'Office hours'), () {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvAvailabilityPage(orgId: orgId, advisorUserId: advisor.userId, advisorName: mine ? null : advisor.shown)));
    }),
    link(Icons.star_outline_rounded, mine ? t('تقييمات لقاءاتي', 'My meeting ratings') : t('تقييمات اللقاءات', 'Meeting ratings'),
        () => showAdvFeedbackSheet(context, AdvCommApi(orgId), advisorUserId: advisor.userId, advisorName: mine ? null : advisor.shown)),
  ];
}

/// The workspace's strip: my unread messages and today's appointments (staff `/status` `me`), each opens its page.
class AdvCommStrip extends StatefulWidget {
  const AdvCommStrip({super.key, required this.orgId});
  final int orgId;

  @override
  State<AdvCommStrip> createState() => _AdvCommStripState();
}

class _AdvCommStripState extends State<AdvCommStrip> {
  AdvCommCounts? _counts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => AdvCommApi(widget.orgId).staffCounts(), quiet: true);
    if (mounted && r.ok) setState(() => _counts = r.data as AdvCommCounts);
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final k = _counts;
    if (k == null) return const SizedBox.shrink();
    return AdvCommStripView(
      counts: k,
      onMessages: () => _push(AdvThreadsPage(orgId: widget.orgId)),
      onAppointments: () => _push(AdvAppointmentsPage(
          orgId: widget.orgId,
          onOpenStudent: (a) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: widget.orgId, memberId: a.memberId, name: a.studentShown))))),
    );
  }
}

class AdvCommStripView extends StatelessWidget {
  const AdvCommStripView({super.key, required this.counts, this.onMessages, this.onAppointments});
  final AdvCommCounts counts;
  final VoidCallback? onMessages, onAppointments;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = counts;
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      AppPill(
        icon: Icons.forum_outlined,
        label: k.threadsUnread > 0
            ? countText(k.threadsUnread, ar1: 'رسالة غير مقروءة', ar2: 'رسالتان غير مقروءتين', arFew: '${k.threadsUnread} رسائل غير مقروءة', arMany: '${k.threadsUnread} رسالة غير مقروءة', en1: '1 unread message', en: '${k.threadsUnread} unread messages')
            : t('الرسائل', 'Messages'),
        color: k.threadsUnread > 0 ? c.primary : c.textMedium,
        onTap: onMessages ?? () {},
      ),
      AppPill(
        icon: Icons.event_note_rounded,
        label: k.appointmentsToday > 0
            ? countText(k.appointmentsToday, ar1: 'موعد اليوم', ar2: 'موعدان اليوم', arFew: '${k.appointmentsToday} مواعيد اليوم', arMany: '${k.appointmentsToday} موعداً اليوم', en1: '1 appointment today', en: '${k.appointmentsToday} appointments today')
            : t('المواعيد', 'Appointments'),
        color: k.appointmentsToday > 0 ? c.success : c.textMedium,
        onTap: onAppointments ?? () {},
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The 360's Meetings section
// ═════════════════════════════════════════════════════════════════════════════

/// Meetings (upcoming / past / no-shows, "Book for the student" for one of the student's advisors) and the
/// Messages entry of one student. [onChanged] reloads the 360 after a write.
class AdvStudentCommPane extends StatelessWidget {
  const AdvStudentCommPane({super.key, required this.orgId, required this.profile, this.onChanged});
  final int orgId;
  final AdvCaseProfile profile;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final me = _me(context);
    final api = AdvCommApi(orgId);
    final flow = AdvApptFlow(api, onChanged: onChanged, onChat: (_) => _openThreads(context));
    final mineStudent = me != null && p.advisors.any((a) => a.userId == me);
    final th = p.threadCounts;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppActionCard(
        icon: Icons.forum_outlined,
        title: t('الرسائل مع الطالب', 'Messages with the student'),
        subtitle: th.unread > 0
            ? countText(th.unread, ar1: 'رسالة غير مقروءة', ar2: 'رسالتان غير مقروءتين', arFew: '${th.unread} رسائل غير مقروءة', arMany: '${th.unread} رسالة غير مقروءة', en1: '1 unread message', en: '${th.unread} unread messages')
            : (th.open > 0
                ? countText(th.open, ar1: 'محادثة مفتوحة', ar2: 'محادثتان مفتوحتان', arFew: '${th.open} محادثات مفتوحة', arMany: '${th.open} محادثة مفتوحة', en1: '1 open conversation', en: '${th.open} open conversations')
                : t('لا محادثات مفتوحة — ابدأ واحدة من هنا', 'No open conversations — start one from here')),
        badge: th.unread,
        onTap: () => _openThreads(context),
      ),
      const SizedBox(height: AppSpace.md),
      AdvMeetingsPane(
        meetings: p.meetings,
        actions: flow.actions(context),
        onBook: mineStudent
            ? () async {
                final name = context.read<MyAuthProvider>().currentUser?.name ?? '';
                final made = await showAdvBookingSheet(context, api, advisors: [(me, name)], memberId: p.memberId, studentName: p.shown);
                if (made != null) onChanged?.call();
              }
            : null,
        onAll: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvAppointmentsPage(orgId: orgId, memberId: p.memberId, title: t('مواعيد ${p.shown}', 'Appointments of ${p.shown}')))),
      ),
    ]);
  }

  Future<void> _openThreads(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvThreadsPage(orgId: orgId, memberId: profile.memberId, studentName: profile.shown)));
    onChanged?.call();
  }
}
