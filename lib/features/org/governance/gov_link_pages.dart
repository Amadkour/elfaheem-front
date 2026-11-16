// lib/features/org/governance/gov_link_pages.dart — UX v3 phase 2: the exact delegation / form assignment a
// notification names (`org_delegation` · `org_form_assignment`, id = the delegation / the assignment).
//
//   GovLinkedDelegationPage(id, link:)   my delegations (`GET …/me/delegations`) → that one: the action banner + its
//                                        card; gone → StaleLinkView (button: what is delegated to me)
//   GovLinkedAssignmentPage(id, link:)   my pending forms (`GET …/me/assignments`) → that one's fill screen in place;
//                                        answered / closed → StaleLinkView (button: the forms I must answer)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/notif_link.dart';
import 'package:flutter_education_app/design/action_banner.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import '../org_member_space.dart' show OrgFormFillScreen;
import '../org_v3.dart' show OrgCall, orgCall;
import 'gov_api.dart';
import 'gov_delegations_page.dart' show GovDelegationCard;
import 'gov_member_pages.dart' show GovMyAssignmentsPage, GovMyItemsPage;
import 'gov_models.dart';

class GovLinkedDelegationPage extends StatefulWidget {
  const GovLinkedDelegationPage(this.delegationId, {super.key, this.link, this.orgId});
  final int delegationId;
  final int? orgId;
  final NotifLink? link;

  @override
  State<GovLinkedDelegationPage> createState() => _GovLinkedDelegationPageState();
}

class _GovLinkedDelegationPageState extends State<GovLinkedDelegationPage> {
  OrgCall? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_r != null) setState(() => _r = null);
    final r = await orgCall(() => GovApi.memberDelegations(), quiet: true);
    if (mounted) setState(() => _r = r);
  }

  void _toMine() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GovMyItemsPage(orgId: widget.orgId)));

  @override
  Widget build(BuildContext context) {
    final r = _r;
    Widget body;
    if (r == null) {
      body = const AppListSkeleton(items: 2);
    } else if (!r.ok) {
      body = Padding(padding: const EdgeInsets.all(AppSpace.md), child: AppErrorBox(error: r.error!, onRetry: _load));
    } else {
      final d = (r.data as List<Delegation>).where((x) => x.id == widget.delegationId).firstOrNull;
      final l = widget.link;
      body = d == null
          ? StaleLinkView(gone: true, reason: l?.staleReason ?? '', fallbackLabel: t('ما فُوّض إليّ', 'What is delegated to me'), onFallback: _toMine)
          : ListView(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), children: [
              if (l != null && l.hasAction)
                Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs), child: ActionBanner.of(l)),
              GovDelegationCard(delegation: d, showEntity: true),
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: AppButton.tonal(icon: Icons.account_tree_rounded, label: t('المعاملات المفوَّضة إليّ', 'Items delegated to me'), onPressed: _toMine),
              ),
            ]);
    }
    return BasePage(useWebCard: true, width: AppWidth.reading, appBar: ScreenAppBar(title: t('التفويض', 'Delegation')), child: body);
  }
}

class GovLinkedAssignmentPage extends StatefulWidget {
  const GovLinkedAssignmentPage(this.assignmentId, {super.key, this.link});
  final int assignmentId;
  final NotifLink? link;

  @override
  State<GovLinkedAssignmentPage> createState() => _GovLinkedAssignmentPageState();
}

class _GovLinkedAssignmentPageState extends State<GovLinkedAssignmentPage> {
  OrgCall? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_r != null) setState(() => _r = null);
    final r = await orgCall(() => GovApi.memberAssignments(), quiet: true);
    if (!mounted) return;
    final a = r.ok ? (r.data as List<FormAssignment>).where((x) => x.id == widget.assignmentId).firstOrNull : null;
    if (a?.formId != null) {
      // still pending: its fill screen, in place of this one
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: a!.formId!)));
      return;
    }
    setState(() => _r = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    Widget body;
    if (r == null) {
      body = const AppListSkeleton(items: 2);
    } else if (!r.ok) {
      body = Padding(padding: const EdgeInsets.all(AppSpace.md), child: AppErrorBox(error: r.error!, onRetry: _load));
    } else {
      body = StaleLinkView(
        // not among the pending ones: answered, waived or the form closed
        reason: widget.link?.staleReason ?? '',
        fallbackLabel: t('النماذج المطلوبة مني', 'Forms to answer'),
        onFallback: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const GovMyAssignmentsPage())),
      );
    }
    return BasePage(useWebCard: true, width: AppWidth.reading, appBar: ScreenAppBar(title: t('نموذج', 'Form')), child: body);
  }
}
