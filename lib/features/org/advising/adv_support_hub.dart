// lib/features/org/advising/adv_support_hub.dart — the student's side of Phase 7 (docs/advising/PHASE7.md, member base
// `/public/{org}/advising`): the requests and referrals their advisor filed for them with every stage, their visible
// support plans (they tick their own items) and their active accommodations. Never a draft, the information asked of
// the advisor, who decided or how the council voted.
//
//   AdvHubRequestsSection · AdvHubPlansSection · AdvHubAccommodationsSection   standalone blocks for the advising hub
//   AdvStudentRequestView (plain values) · AdvStudentRequestPage               one request
//   AdvStudentSupportPage                                                      the three blocks on one page (deep links)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPushedPage, orgUsesDashboardHeader;
import '../org_v3.dart' show orgCall;
import 'adv_accommodations.dart' show AdvAccommodationCard;
import 'adv_case_parts.dart' show AdvTypedText;
import 'adv_parts.dart';
import 'adv_plan.dart' show AdvPlanCard;
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart';
import 'adv_support_texts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Hub blocks
// ═════════════════════════════════════════════════════════════════════════════

class AdvHubRequestsSection extends StatelessWidget {
  const AdvHubRequestsSection({super.key, required this.requests, this.onOpen, this.first = false});
  final List<AdvStudentRequest> requests;
  final ValueChanged<AdvStudentRequest>? onOpen;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final open = requests.where((r) => !r.decided).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvSectionTitle(
        t('طلباتي', 'My requests'),
        subtitle: requests.isEmpty
            ? null
            : (open > 0 ? t('$open قيد المتابعة', '$open in progress') : t('كلها صدر فيها قرار', 'All decided')),
        first: first,
      ),
      if (requests.isEmpty)
        _Quiet(
          icon: Icons.support_outlined,
          text: t('يكتب مرشدك طلبات الدعم والإحالات نيابة عنك، وتتابع هنا كل مراحلها.', 'Your advisor files support requests and referrals for you; you follow every stage here.'),
        ),
      for (final r in requests) AdvRequestCard.student(r, onTap: onOpen == null ? null : () => onOpen!(r)),
    ]);
  }
}

class AdvHubPlansSection extends StatelessWidget {
  const AdvHubPlansSection({super.key, required this.plans, this.ticking = const {}, this.onTick, this.first = false});
  final List<AdvSupportPlan> plans;
  final Set<int> ticking;

  /// Ticks one of MY items (owner = student) done / open.
  final void Function(AdvSupportPlan, AdvSupportPlanItem)? onTick;
  final bool first;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AdvSectionTitle(t('خطة الدعم', 'My support plan'), subtitle: plans.isEmpty ? null : t('أشّر على بنودك عند إنجازها', 'Tick your items when you have done them'), first: first),
        if (plans.isEmpty) _Quiet(icon: Icons.route_outlined, text: t('لا خطة دعم مشتركة معك الآن.', 'No support plan is shared with you right now.')),
        for (final p in plans)
          AdvPlanCard(
            plan: p,
            student: true,
            canTick: (i) => i.mine ?? i.owner == 'student',
            ticking: ticking,
            onTick: onTick == null ? null : (i) => onTick!(p, i),
          ),
      ]);
}

class AdvHubAccommodationsSection extends StatelessWidget {
  const AdvHubAccommodationsSection({super.key, required this.accommodations, this.first = false});
  final List<AdvAccommodationGrant> accommodations;
  final bool first;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AdvSectionTitle(t('تسهيلاتي', 'My accommodations'), subtitle: accommodations.isEmpty ? null : t('أبلغ أستاذك بها عند الحاجة', 'Tell your teacher about them when you need to'), first: first),
        if (accommodations.isEmpty) _Quiet(icon: Icons.accessible_outlined, text: t('لا تسهيلات نشطة لك.', 'You have no active accommodations.')),
        for (final a in accommodations) AdvAccommodationCard(accommodation: a, student: true),
      ]);
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(children: [
          ExcludeSemantics(child: Icon(icon, color: context.colors.textLight, size: AppIconSize.lg)),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: AppType.body(context))),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  One request (the student)
// ═════════════════════════════════════════════════════════════════════════════

class AdvStudentRequestView extends StatelessWidget {
  const AdvStudentRequestView({super.key, required this.load, this.request, this.errorText, this.onRetry});
  final AdvLoad load;
  final AdvStudentRequest? request;
  final String? errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final r = request;
    if (load != AdvLoad.ready || r == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 3);
    }
    final c = context.colors;
    final col = advStageColor(context, r.stage);
    final hint = advStageHint(r.stage, postponed: r.postponed, student: true);
    final children = <Widget>[
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: Container(
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
                child: Icon(advRequestKindIcon(r.kind), color: appInk(context, col)),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(header: true, child: Text(r.shownTitle, textDirection: advTextDirection(r.shownTitle), style: AppType.section(context))),
                const SizedBox(height: AppSpace.xxs),
                Text(r.typeLabel, style: AppType.meta(context)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [AdvStagePill(stage: r.stage, postponed: r.postponed)]),
          const SizedBox(height: AppSpace.xs),
          Text(
            [
              if (r.advisorName.isNotEmpty) t('كتبه مرشدك ${advIso(r.advisorName)}', 'Filed by your advisor ${advIso(r.advisorName)}'),
              if (r.submittedAt != null) t('أُرسل ${advDate(r.submittedAt)}', 'submitted ${advDate(r.submittedAt)}'),
            ].join(' · '),
            style: AppType.meta(context),
          ),
        ]),
      ),
      AdvBlockCard(
        icon: Icons.route_rounded,
        title: t('أين وصل طلبك', 'Where your request is'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdvStageTrack(points: r.track),
          if (hint.isNotEmpty) ...[
            Divider(height: AppSpace.lg, color: c.divider),
            Text(hint, style: AppType.body(context).copyWith(color: c.textDark)),
          ],
        ]),
      ),
      if (r.decided) AdvOutcomeCard(outcome: r.outcome!, note: r.outcomeNote, at: r.outcomeAt, accommodations: r.outcome == 'approved' ? r.accommodations : const []),
      AdvBlockCard(
        icon: Icons.notes_rounded,
        title: t('التفاصيل', 'Details'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.body.trim().isEmpty) Text(t('لا تفاصيل مكتوبة.', 'No details written.'), style: AppType.body(context)) else AdvTypedText(r.body.trim()),
          if (r.referral && r.target.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            AppInfoRow(Icons.alt_route_rounded, t('محالة إلى ${r.target}', 'Referred to ${r.target}')),
          ],
          if (!r.referral && r.accommodations.isNotEmpty && !r.decided) ...[
            const SizedBox(height: AppSpace.sm),
            Text(t('التسهيلات المطلوبة', 'Accommodations requested'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              for (final a in r.accommodations) AppBadgePill(a.label, color: c.primary, icon: Icons.accessible_rounded),
            ]),
          ],
        ]),
      ),
      if (r.history.isNotEmpty)
        AdvBlockCard(
          icon: Icons.history_rounded,
          title: t('سجل المراحل', 'Stage history'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = r.history.length - 1; i >= 0; i--)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Row(children: [
                  ExcludeSemantics(child: Icon(advStageIcon(r.history[i].stage), size: AppIconSize.sm, color: appInk(context, advStageColor(context, r.history[i].stage)))),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(r.history[i].label, style: AppType.row(context))),
                  if (r.history[i].at != null) Text(advDate(r.history[i].at), style: AppType.meta(context)),
                ]),
              ),
          ]),
        ),
    ];
    return AdvPageFrame(maxWidth: AppWidth.reading.max, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.sm), children[i]],
    ]);
  }
}

/// A member page: the dashboard's header for staff of this organization, else the screen's own app bar.
Widget _memberChrome(BuildContext context, int orgId, {required String title, required Widget child}) {
  if (orgUsesDashboardHeader(context, orgId)) {
    return OrgPushedPage(title: title, helpPageId: 'org.advising', width: AppWidth.reading, child: child);
  }
  return BasePage(useWebCard: true, maxWith: 800, appBar: ScreenAppBar(title: title), child: child);
}

class AdvStudentRequestPage extends StatefulWidget {
  const AdvStudentRequestPage({super.key, required this.orgId, required this.requestId, this.initial});
  final int orgId, requestId;
  final AdvStudentRequest? initial;

  @override
  State<AdvStudentRequestPage> createState() => _AdvStudentRequestPageState();
}

class _AdvStudentRequestPageState extends State<AdvStudentRequestPage> {
  late AdvStudentRequest? _request = widget.initial;
  late AdvLoad _load = widget.initial == null ? AdvLoad.loading : AdvLoad.ready;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => AdvSupportApi.memberRequest(widget.orgId, widget.requestId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _request = r.data as AdvStudentRequest;
        _load = AdvLoad.ready;
      } else if (_request == null) {
        _load = advFailLoad(r);
        _error = advSupportErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _memberChrome(
        context,
        widget.orgId,
        title: _request?.referral ?? false ? t('إحالتي', 'My referral') : t('طلبي', 'My request'),
        child: AdvStudentRequestView(
          load: _load,
          request: _request,
          errorText: _error,
          onRetry: () {
            setState(() => _load = AdvLoad.loading);
            _reload();
          },
        ),
      );
}

/// The student's requests, plan and accommodations on one page (a plan / accommodation notice lands here).
class AdvStudentSupportPage extends StatefulWidget {
  const AdvStudentSupportPage({super.key, required this.orgId});
  final int orgId;

  @override
  State<AdvStudentSupportPage> createState() => _AdvStudentSupportPageState();
}

class _AdvStudentSupportPageState extends State<AdvStudentSupportPage> {
  AdvMemberSupport? _data;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  final Set<int> _ticking = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => AdvSupportApi.memberSupport(widget.orgId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _data = r.data as AdvMemberSupport;
        _load = AdvLoad.ready;
      } else if (_data == null) {
        _load = advFailLoad(r);
        _error = advSupportErrorText(r.error!);
      }
    });
  }

  Future<void> _tick(AdvSupportPlan p, AdvSupportPlanItem i) async {
    final id = i.id;
    final d = _data;
    if (id == null || d == null) return;
    final next = i.done ? 'open' : 'done';
    AdvMemberSupport swap(AdvSupportPlan Function(AdvSupportPlan) f) =>
        AdvMemberSupport(requests: _data!.requests, plans: [for (final x in _data!.plans) x.id == p.id ? f(x) : x], accommodations: _data!.accommodations);
    setState(() {
      _ticking.add(id);
      _data = swap((x) => x.withItemStatus(id, next));
    });
    final r = await orgCall(() => AdvSupportApi.tickPlanItem(widget.orgId, p.id, id, next), quiet: true);
    if (!mounted) return;
    setState(() => _ticking.remove(id));
    if (!r.ok) {
      showAppNotice(advSupportErrorText(r.error!), error: true);
      _reload();
      return;
    }
    final saved = r.data as AdvSupportPlan;
    setState(() => _data = swap((_) => saved));
    showAppNotice(next == 'done' ? t('أحسنت — أُنجز البند', 'Well done — item done') : t('أُعيد فتح البند', 'Item reopened'));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final Widget body = _load != AdvLoad.ready || d == null
        ? AdvLoadState(
            state: _load == AdvLoad.ready ? AdvLoad.loading : _load,
            errorText: _error,
            onRetry: () {
              setState(() => _load = AdvLoad.loading);
              _reload();
            })
        : AdvPageFrame(maxWidth: AppWidth.reading.max, children: [
            AdvHubRequestsSection(
              requests: d.requests,
              first: true,
              onOpen: (r) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentRequestPage(orgId: widget.orgId, requestId: r.id, initial: r))),
            ),
            AdvHubPlansSection(plans: d.plans, ticking: _ticking, onTick: _tick),
            AdvHubAccommodationsSection(accommodations: d.accommodations),
          ]);
    return _memberChrome(context, widget.orgId, title: t('الدعم والخطط', 'Support and plans'), child: body);
  }
}
