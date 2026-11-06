// lib/features/org/advising/adv_wiring.dart — where the Academic Advising screens plug into the rest of the app
// (the governance module's gov_wiring.dart pattern). Phase 2: the org dashboard's Services entry; Phase 4: the same
// entry for advisors (the `advising` key of `/org/mine`). Later phases add the department tab, the member pill and
// the deep links here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../admin/admin_common.dart' show t;
import '../org_providers.dart' show OrgSession;
import 'adv_api.dart' show AdvApi;
import 'adv_appointments.dart' show AdvAppointmentsPage;
import 'adv_comm_api.dart' show AdvCommApi;
import 'adv_models.dart' show AdvMineInfo, advMaybeEligible;
import 'adv_setup_page.dart';
import 'adv_student_hub.dart' show AdvStudentHubPage;
import 'adv_student_page.dart' show AdvStudentPage;
import 'adv_threads.dart' show AdvThreadPage;

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

// ── Phase 5: the student hub pill and the appointment / conversation / survey deep links ──────────────────────────

/// Organizations where I study whose advising hub is known: org id → I have an active advisor there (member status
/// `hub`). Filled on demand by [advMemberPills]; a hub page refreshes it.
final Map<int, bool> _hubKnown = {};
final Set<int> _hubLoading = {};

/// The member home's "My advisor" pill (students with an active advisor in [orgId]), in the gov_wiring pill shape.
/// The first build asks the member status once and redraws the home when the answer comes.
List<Widget> advMemberPills(BuildContext context, int orgId, Widget Function({required IconData icon, required String label, required VoidCallback onTap}) pill) {
  if (!advEnabled() || orgId == 0) return const [];
  final known = _hubKnown[orgId];
  if (known == null) {
    if (_hubLoading.add(orgId)) {
      AdvCommApi(orgId, student: true).memberHub().then((h) => _hubKnown[orgId] = h.enabled && h.student && h.hub, onError: (_) => _hubKnown[orgId] = false).whenComplete(() {
        _hubLoading.remove(orgId);
        // the member home builds its pills synchronously: redraw it now that the answer is known
        if (context.mounted && _hubKnown[orgId] == true) (context as Element).markNeedsBuild();
      });
    }
    return const [];
  }
  if (!known) return const [];
  return [
    pill(
      icon: Icons.co_present_rounded,
      label: t('مرشدي الأكاديمي', 'My academic advisor'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentHubPage(orgId: orgId))),
    ),
  ];
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
