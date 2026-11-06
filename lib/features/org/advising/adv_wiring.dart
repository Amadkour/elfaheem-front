// lib/features/org/advising/adv_wiring.dart — where the Academic Advising screens plug into the rest of the app
// (the governance module's gov_wiring.dart pattern). Phase 2: the org dashboard's Services entry; Phase 4: the same
// entry for advisors (the `advising` key of `/org/mine`). Later phases add the department tab, the member pill and
// the deep links here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppActionCard, AppSpace;

import '../../admin/admin_common.dart' show t;
import '../org_providers.dart' show OrgSession;
import 'adv_api.dart' show AdvApi;
import 'adv_appointments.dart' show AdvAppointmentsPage;
import 'adv_appt_models.dart' show AdvMemberHub;
import 'adv_comm_api.dart' show AdvCommApi;
import 'adv_director_page.dart' show AdvDirectorPage;
import 'adv_models.dart' show AdvMineInfo, AdvStatus, advMaybeEligible;
import 'adv_outreach.dart' show AdvOutreachTrackingPage, AdvStudentMessagesPage;
import 'adv_setup_page.dart';
import 'adv_student_hub.dart' show AdvStudentHubPage;
import 'adv_student_page.dart' show AdvStudentPage;
import '../org_v3.dart' show orgCall, orgParseUtc;
import 'adv_alerts_page.dart' show AdvAlertsPage;
import 'adv_threads.dart' show AdvThreadPage;
import 'adv_warning_parts.dart' show advWarningOn;
import 'adv_workspace_page.dart' show AdvWorkspacePage;

// Phase 7: the request / plan / accommodation deep links and the advising page's Requests links
export 'adv_support_wiring.dart' show advOpenSupportLink;

/// Kill switch of the whole module (`org.advising`, feature_catalog.py; not org-manageable). Hidden features
/// disappear.
bool advEnabled() => !AppConfig.disableList.contains('org.advising');

/// Does `/org/mine` name me as an advising director, or an advisor with students, in [item]?
bool advAdvisesIn(Map<String, dynamic>? item) {
  final mine = AdvMineInfo.of(item);
  return mine != null && (mine.director || mine.advisees > 0);
}

/// The "Services" section entries of the org dashboard: (key, label, icon, page). Org admins, holders of an
/// `advising` right (the advising director role) and anyone `/org/mine` names as a director or an advisor with
/// students there ([advAdvisesIn]); hidden where the organization can never offer advising.
List<(String, String, IconData, Widget)> advServiceSubs(OrgSession s) {
  final oid = s.currentId;
  if (!advEnabled() || oid == null) return const [];
  if (!(s.isOrgAdmin || s.canAny('advising') || advAdvisesIn(s.current))) return const [];
  if (!advMaybeEligible(s.items, oid)) return const [];
  return [
    ('advising', t('الإرشاد الأكاديمي', 'Academic advising'), Icons.co_present_rounded, AdvSetupPage(orgId: oid)),
  ];
}

/// Deep link of the advising notices that name a student (an urgent flag, an escalation, a review due: push data
/// `module: advising` with `member_id` / `flag_id`): that student's 360. `AppNavigator` opens the organization first.
Future<void> advOpenStudentLink(NavigatorState nav, {required int orgId, required int memberId}) =>
    nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: orgId, memberId: memberId)));

/// Phase 6: the early-warning notices that name a screen (push data `module: advising` with `screen`, or a
/// `warning_alert` with `action: propose_meeting`). `alerts` → the alerts (since the digest's `since`) · `workspace`
/// → My students by last contact · `advisor` → the student's advising hub · `propose_meeting` + `member_id` → the
/// 360 ready to log a contact. False when [data] names none of them (the caller opens the 360 or the notifications).
Future<bool> advOpenScreenLink(NavigatorState nav, {required int orgId, required Map<String, dynamic> data}) async {
  if (!advWarningOn()) return false;
  final screen = '${data['screen'] ?? ''}';
  final member = int.tryParse('${data['member_id'] ?? ''}');
  if (data['action'] == 'propose_meeting' && member != null) {
    await nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: orgId, memberId: member, section: 'notes', logContact: true)));
    return true;
  }
  if (screen == 'advisor') {
    await nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentHubPage(orgId: orgId)));
    return true;
  }
  if (screen != 'alerts' && screen != 'workspace') return false;
  // a director sees the whole organization, an advisor their own students
  final st = await orgCall(() => AdvApi(orgId).status(), quiet: true);
  final lead = st.ok && (st.data as AdvStatus).me.leads;
  await nav.push(MaterialPageRoute<void>(
    builder: (_) => screen == 'alerts'
        ? AdvAlertsPage(orgId: orgId, manage: lead, since: orgParseUtc(data['since']))
        : AdvWorkspacePage(orgId: orgId, manage: lead, sort: '${data['sort'] ?? 'contact'}'),
  ));
  return true;
}

// ── Phase 5: the student hub pill and the appointment / conversation / survey deep links ──────────────────────────

/// The member home's "My academic advisor" row (students with an active advisor in [orgId]). It asks the member
/// status itself (one cached answer per organization, shared by every copy of the row) and draws nothing until the
/// answer says I have an advisor there; the unread messages, today's appointments and pending surveys are its badge.
class AdvMemberHubEntry extends StatefulWidget {
  const AdvMemberHubEntry({super.key, required this.orgId, this.padding = const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm)});
  final int orgId;
  final EdgeInsetsGeometry padding;

  /// org id → the member status answer (one request per organization while the app runs; a hub visit refreshes it).
  static final Map<int, Future<AdvMemberHub?>> _cache = {};

  static Future<AdvMemberHub?> _load(int orgId, {bool fresh = false}) {
    if (fresh) _cache.remove(orgId);
    return _cache.putIfAbsent(orgId, () => AdvCommApi(orgId, student: true).memberHub().then<AdvMemberHub?>((h) => h, onError: (_) {
          _cache.remove(orgId); // a failed answer is asked again next time
          return null;
        }));
  }

  @override
  State<AdvMemberHubEntry> createState() => _AdvMemberHubEntryState();
}

class _AdvMemberHubEntryState extends State<AdvMemberHubEntry> {
  late Future<AdvMemberHub?> _hub = AdvMemberHubEntry._load(widget.orgId);

  @override
  void didUpdateWidget(AdvMemberHubEntry old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) _hub = AdvMemberHubEntry._load(widget.orgId);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentHubPage(orgId: widget.orgId)));
    if (mounted) setState(() => _hub = AdvMemberHubEntry._load(widget.orgId, fresh: true));
  }

  @override
  Widget build(BuildContext context) {
    if (!advEnabled() || widget.orgId == 0) return const SizedBox.shrink();
    return FutureBuilder<AdvMemberHub?>(
      future: _hub,
      builder: (context, snap) {
        final h = snap.data;
        if (h == null || !(h.enabled && h.student && h.hub)) return const SizedBox.shrink();
        final k = h.counts;
        final parts = [
          if (k.threadsUnread > 0) countText(k.threadsUnread, ar1: 'رسالة جديدة', ar2: 'رسالتان جديدتان', arFew: '${k.threadsUnread} رسائل جديدة', arMany: '${k.threadsUnread} رسالة جديدة', en1: '1 new message', en: '${k.threadsUnread} new messages'),
          if (k.appointmentsToday > 0) countText(k.appointmentsToday, ar1: 'موعد اليوم', ar2: 'موعدان اليوم', arFew: '${k.appointmentsToday} مواعيد اليوم', arMany: '${k.appointmentsToday} موعداً اليوم', en1: '1 appointment today', en: '${k.appointmentsToday} appointments today'),
          if (k.surveysPending > 0) t('استبيان بانتظارك', 'A survey waits for you'),
        ];
        return Padding(
          padding: widget.padding,
          child: AppActionCard(
            icon: Icons.co_present_rounded,
            title: t('مرشدي الأكاديمي', 'My academic advisor'),
            subtitle: parts.isEmpty ? t('الساعات المكتبية، المواعيد والرسائل', 'Office hours, appointments and messages') : parts.join(' · '),
            badge: k.total,
            onTap: _open,
          ),
        );
      },
    );
  }
}

/// Am I a student in [orgId] (the member base) rather than staff? Asked once per link.
Future<bool> _studentIn(int orgId) async {
  try {
    return (await AdvApi.memberStatus(orgId)).isStudent;
  } catch (_) {
    return false;
  }
}

/// Phase 5 deep links (push data `kind` = `org_adv_appointment` + `appointment_id` · `org_adv_thread` + `thread_id` ·
/// `org_adv_survey` + `token`): a student lands on their hub (the survey opens on it) or the conversation, staff on
/// the appointments list or the conversation. false when [data] names none of them.
Future<bool> advOpenCommLink(NavigatorState nav, {required int orgId, required Map<String, dynamic> data, String? kind}) async {
  final inner = data['data'];
  final d = {if (inner is Map) ...inner.map((k, v) => MapEntry('$k', v)), ...data};
  final k = '${d['kind'] ?? kind ?? ''}';
  final student = await _studentIn(orgId);
  switch (k) {
    case 'org_adv_thread':
      final id = int.tryParse('${d['thread_id'] ?? d['target_id'] ?? ''}');
      if (id == null) return false;
      await nav.push(MaterialPageRoute<void>(builder: (_) => AdvThreadPage(orgId: orgId, threadId: id, student: student)));
      return true;
    case 'org_adv_appointment':
      await nav.push(MaterialPageRoute<void>(builder: (_) => student ? AdvStudentHubPage(orgId: orgId) : AdvAppointmentsPage(orgId: orgId)));
      return true;
    case 'org_adv_survey':
      final token = '${d['token'] ?? ''}';
      if (!student) return false;
      await nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentHubPage(orgId: orgId, surveyToken: token.isEmpty ? null : token)));
      return true;
  }
  return false;
}

/// Phase 8 deep links (push data `module: advising`): `kind: org_adv_outreach` + `outreach_id` → the student's
/// message (`audience: student`) or the sender's tracking page; `screen: health` → the analytics page with its data
/// check. False when [data] is neither (the caller goes on with its own handling).
Future<bool> advOpenAnalyticsLink(NavigatorState nav, {required int orgId, required Map<String, dynamic> data}) async {
  final outreach = int.tryParse('${data['outreach_id'] ?? ''}');
  if (data['kind'] == 'org_adv_outreach' && outreach != null) {
    if (data['audience'] == 'student') {
      nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentMessagesPage(orgId: orgId)));
    } else {
      nav.push(MaterialPageRoute<void>(builder: (_) => AdvOutreachTrackingPage(orgId: orgId, outreachId: outreach)));
    }
    return true;
  }
  if (data['screen'] == 'health') {
    nav.push(MaterialPageRoute<void>(builder: (_) => AdvDirectorPage(orgId: orgId)));
    return true;
  }
  return false;
}
