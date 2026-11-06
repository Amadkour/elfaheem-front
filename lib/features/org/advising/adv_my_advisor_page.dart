// lib/features/org/advising/adv_my_advisor_page.dart — a student's advising card (docs/advising/PHASE6.md
// "Nudges"): who their advisors are and how to reach them (office, contact note), from the member status
// `GET …/public/{org}/advising/status`. Opened by the `nudge_student_no_contact` push (`screen: advisor`); Phase 5's
// student hub takes its place once merged.
//
//   AdvMyAdvisorView   the card (plain values)       AdvMyAdvisorPage   loads the member status
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_case_parts.dart' show AdvTypedText;
import 'adv_models.dart';
import 'adv_parts.dart';

class AdvMyAdvisorView extends StatelessWidget {
  const AdvMyAdvisorView({super.key, required this.load, this.status, this.errorText, this.onRetry});
  final AdvLoad load;
  final AdvMemberStatus? status;
  final String? errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    if (load != AdvLoad.ready || s == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 2);
    }
    if (!s.enabled || !s.isStudent || s.advisors.isEmpty) {
      return AppEmpty(
        icon: Icons.person_search_rounded,
        title: t('لا مرشد أكاديمي بعد', 'No academic advisor yet'),
        message: t('يسند إليك مدير الإرشاد مرشداً قريباً، وتجده هنا.', 'The advising director assigns you an advisor soon; you will find them here.'),
      );
    }
    return AdvPageFrame(maxWidth: 720, children: [
      AppBanner(
        icon: Icons.waving_hand_outlined,
        text: t('مرشدك الأكاديمي هنا ليساعدك في خطتك ومقرراتك وأي صعوبة تواجهك — تواصل معه متى احتجت.',
            'Your academic advisor is here to help with your plan, your courses and anything in your way — reach out whenever you need.'),
      ),
      const SizedBox(height: AppSpace.sm),
      for (final a in s.advisors)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            padding: AppSpace.card,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ExcludeSemantics(child: AppAvatar(name: a.name.isEmpty ? '#${a.userId}' : a.name, size: AppTouch.primary)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(header: true, child: Text(a.name.isEmpty ? '#${a.userId}' : a.name, style: AppType.section(context))),
                    Text(a.typeLabel, style: AppType.meta(context)),
                  ]),
                ),
              ]),
              if (a.officeLocation != null) ...[
                const SizedBox(height: AppSpace.sm),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ExcludeSemantics(child: Icon(Icons.meeting_room_outlined, size: AppIconSize.md, color: c.textMedium)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AdvTypedText(a.officeLocation!)),
                ]),
              ],
              if (a.contactNote != null) ...[
                const SizedBox(height: AppSpace.xs),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ExcludeSemantics(child: Icon(Icons.forum_outlined, size: AppIconSize.md, color: c.textMedium)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AdvTypedText(a.contactNote!)),
                ]),
              ],
              if (a.officeLocation == null && a.contactNote == null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(t('لم يكتب مرشدك طريقة التواصل بعد — اسأل عنه في إدارة الإرشاد.', 'Your advisor has not written how to reach them yet — ask the advising office.'), style: AppType.meta(context)),
              ],
            ]),
          ),
        ),
    ]);
  }
}

class AdvMyAdvisorPage extends StatefulWidget {
  const AdvMyAdvisorPage({super.key, required this.orgId});
  final int orgId;

  @override
  State<AdvMyAdvisorPage> createState() => _AdvMyAdvisorPageState();
}

class _AdvMyAdvisorPageState extends State<AdvMyAdvisorPage> {
  final _refresh = OrgPageRefresh();
  AdvMemberStatus? _status;
  AdvLoad _load = AdvLoad.loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh.attach(_reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => AdvApi.memberStatus(widget.orgId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _status = r.data as AdvMemberStatus;
        _load = AdvLoad.ready;
      } else if (_status == null) {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
      }
    });
    if (r.ok) _refresh.markUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final title = t('مرشدي الأكاديمي', 'My academic advisor');
    final body = AdvMyAdvisorView(
      load: _load,
      status: _status,
      errorText: _error,
      onRetry: () {
        setState(() => _load = AdvLoad.loading);
        _reload();
      },
    );
    // a student opens it from a push, outside the staff dashboard: the app's own page frame then
    return orgUsesDashboardHeader(context, widget.orgId)
        ? OrgPushedPage(title: title, refresh: _refresh, maxWidth: 760, child: body)
        : BasePage(useWebCard: true, maxWith: 760, appBar: ScreenAppBar(title: title), child: body);
  }
}
