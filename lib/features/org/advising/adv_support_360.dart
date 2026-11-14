// lib/features/org/advising/adv_support_360.dart — the student 360's "Support" section (docs/advising/PHASE7.md "360
// and status"): the student's requests and referrals (the latest five each, with their stage tracks), support plans
// (drafts and active ones open, finished ones folded), active accommodations, and the actions the caller may take —
// New request · Refer · New plan · Grant accommodations.
//
//   AdvSupportPane      the section (plain values; test/ui/adv_support_layout_test.dart)
//   AdvSupportSection   loads `GET …/students/{mid}/support` + `…/plans` and runs every action through AdvSupportApi
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall;
import 'adv_accommodations.dart';
import 'adv_case_parts.dart' show AdvMiniStat;
import 'adv_models.dart' show AdvCategory;
import 'adv_parts.dart';
import 'adv_plan.dart';
import 'adv_request_composer.dart';
import 'adv_requests.dart';
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart' show AdvRequestCard;
import 'adv_support_texts.dart';

class AdvSupportPane extends StatelessWidget {
  const AdvSupportPane({
    super.key,
    required this.load,
    this.summary,
    this.plans,
    this.errorText,
    this.ticking = const {},
    this.onRetry,
    this.onNewRequest,
    this.onRefer,
    this.onNewPlan,
    this.onGrant,
    this.onOpenRequest,
    this.onSeeAll,
    this.onTickItem,
    this.onEditPlan,
    this.onPlanStatus,
    this.onDeletePlan,
    this.onEndAccommodation,
    this.onReviewPlan,
  });

  final AdvLoad load;
  final AdvSupportSummary? summary;

  /// Every plan of the student (null: the summary's active ones).
  final List<AdvSupportPlan>? plans;
  final String? errorText;
  final Set<int> ticking;
  final VoidCallback? onRetry, onNewRequest, onRefer, onNewPlan, onGrant, onSeeAll;
  final ValueChanged<AdvRequest>? onOpenRequest;
  final void Function(AdvSupportPlan, AdvSupportPlanItem)? onTickItem;
  final ValueChanged<AdvSupportPlan>? onEditPlan, onPlanStatus, onDeletePlan, onReviewPlan;
  final ValueChanged<AdvAccommodationGrant>? onEndAccommodation;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (load != AdvLoad.ready || s == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 3);
    }
    final c = context.colors;
    final all = plans ?? s.activePlans;
    final open = [for (final p in all) if (!p.finished) p];
    final done = [for (final p in all) if (p.finished) p];
    final can = s.can;
    Widget action(IconData icon, String label, VoidCallback? on) => on == null
        ? const SizedBox.shrink()
        : FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: on,
            icon: Icon(icon, size: AppIconSize.md),
            label: Text(label),
          );
    final actions = [
      if (can.request && onNewRequest != null) action(Icons.support_rounded, t('طلب دعم', 'Support request'), onNewRequest),
      if (can.refer && onRefer != null) action(Icons.alt_route_rounded, t('إحالة', 'Refer'), onRefer),
      if (can.plan && onNewPlan != null) action(Icons.route_rounded, t('خطة دعم', 'Support plan'), onNewPlan),
      if (can.accommodate && onGrant != null) action(Icons.accessible_rounded, t('تسهيلات', 'Accommodations'), onGrant),
    ];
    Widget seeAll(int total, int shown) => total > shown && onSeeAll != null
        ? TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: onSeeAll, child: Text(t('عرض الكل ($total)', 'See all ($total)')))
        : const SizedBox.shrink();
    Widget quiet(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs), child: Text(text, style: AppType.body(context)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (actions.isNotEmpty) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: actions),
        const SizedBox(height: AppSpace.sm),
      ],
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 480 ? 4 : 2;
        final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final ch in [
            AdvMiniStat(label: t('طلبات مفتوحة', 'Open requests'), value: '${s.requestsOpen}', tone: s.requestsNeedsInfo > 0 ? c.warning : null),
            AdvMiniStat(label: t('إحالات مفتوحة', 'Open referrals'), value: '${s.referralsOpen}'),
            AdvMiniStat(label: t('خطط نشطة', 'Active plans'), value: '${open.where((p) => p.active).length}'),
            AdvMiniStat(label: t('تسهيلات نشطة', 'Active accommodations'), value: '${s.accommodations.length}'),
          ])
            SizedBox(width: w, child: ch),
        ]);
      }),
      if (s.requestsNeedsInfo > 0) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.help_outline_rounded,
          color: c.warning,
          text: countText(s.requestsNeedsInfo,
              ar1: 'طلب ينتظر معلومات من المرشد', ar2: 'طلبان ينتظران معلومات من المرشد', arFew: '${s.requestsNeedsInfo} طلبات تنتظر معلومات من المرشد', arMany: '${s.requestsNeedsInfo} طلباً ينتظر معلومات من المرشد',
              en1: '1 request waits for information from the advisor', en: '${s.requestsNeedsInfo} requests wait for information from the advisor'),
        ),
      ],
      AdvSectionTitle(t('طلبات الدعم', 'Support requests'), trailing: seeAll(s.requestsTotal, s.requests.length)),
      if (s.requests.isEmpty) quiet(t('لا طلبات دعم بعد.', 'No support requests yet.')),
      for (final r in s.requests) AdvRequestCard.staff(r, showStudent: false, onTap: onOpenRequest == null ? null : () => onOpenRequest!(r)),
      AdvSectionTitle(t('الإحالات', 'Referrals'), trailing: seeAll(s.referralsTotal, s.referrals.length)),
      if (s.referrals.isEmpty) quiet(t('لا إحالات بعد.', 'No referrals yet.')),
      for (final r in s.referrals) AdvRequestCard.staff(r, showStudent: false, onTap: onOpenRequest == null ? null : () => onOpenRequest!(r)),
      AdvSectionTitle(t('خطط الدعم', 'Support plans')),
      if (open.isEmpty) quiet(t('لا خطة دعم نشطة.', 'No active support plan.')),
      for (final p in open)
        AdvPlanCard(
          plan: p,
          canTick: (_) => p.can.edit,
          ticking: ticking,
          onTick: onTickItem == null ? null : (i) => onTickItem!(p, i),
          onEdit: onEditPlan == null || !p.can.edit ? null : () => onEditPlan!(p),
          onStatus: onPlanStatus == null || !p.can.status ? null : () => onPlanStatus!(p),
          onReview: onReviewPlan == null || !p.can.edit ? null : () => onReviewPlan!(p),
          onDelete: onDeletePlan == null || !p.can.delete || p.status != 'draft' ? null : () => onDeletePlan!(p),
        ),
      if (done.isNotEmpty || (plans == null && s.completedPlans > 0))
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              countText(done.isNotEmpty ? done.length : s.completedPlans,
                  ar1: 'خطة سابقة', ar2: 'خطتان سابقتان', arFew: '${done.isNotEmpty ? done.length : s.completedPlans} خطط سابقة', arMany: '${done.isNotEmpty ? done.length : s.completedPlans} خطة سابقة',
                  en1: '1 earlier plan', en: '${done.isNotEmpty ? done.length : s.completedPlans} earlier plans'),
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600),
            ),
            children: [
              for (final p in done) AdvPlanCard(plan: p, onStatus: onPlanStatus == null || !p.can.status ? null : () => onPlanStatus!(p)),
            ],
          ),
        ),
      AdvSectionTitle(t('التسهيلات', 'Accommodations')),
      if (s.accommodations.isEmpty) quiet(t('لا تسهيلات نشطة.', 'No active accommodations.')),
      for (final a in s.accommodations) AdvAccommodationCard(accommodation: a, onEnd: can.accommodate && onEndAccommodation != null ? () => onEndAccommodation!(a) : null),
      if (s.restricted > 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            ExcludeSemantics(child: Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: c.textMedium)),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                countText(s.restricted,
                    ar1: 'طلب حساس واحد لا يظهر لك', ar2: 'طلبان حساسان لا يظهران لك', arFew: '${s.restricted} طلبات حساسة لا تظهر لك', arMany: '${s.restricted} طلباً حساساً لا يظهر لك',
                    en1: '1 sensitive request is hidden from you', en: '${s.restricted} sensitive requests are hidden from you'),
                style: AppType.meta(context),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// The Support section of the 360, loading itself. [onChanged]: a write happened (the 360 reloads its numbers and
/// timeline).
class AdvSupportSection extends StatefulWidget {
  const AdvSupportSection({super.key, required this.orgId, required this.memberId, this.studentName, this.categories = const [], this.manage = false, this.onChanged});
  final int orgId, memberId;
  final String? studentName;
  final List<AdvCategory> categories;
  final bool manage;
  final VoidCallback? onChanged;

  @override
  State<AdvSupportSection> createState() => _AdvSupportSectionState();
}

class _AdvSupportSectionState extends State<AdvSupportSection> {
  late final AdvSupportApi _api = AdvSupportApi(widget.orgId);
  AdvSupportSummary? _summary;
  List<AdvSupportPlan>? _plans;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  final Set<int> _ticking = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sCall = orgCall(() => _api.support(widget.memberId), quiet: true);
    final pCall = orgCall(() => _api.plans(widget.memberId), quiet: true);
    final s = await sCall;
    final p = await pCall;
    if (!mounted) return;
    setState(() {
      if (s.ok) {
        _summary = s.data as AdvSupportSummary;
        _load = AdvLoad.ready;
      } else if (_summary == null) {
        _load = advFailLoad(s);
        _error = advSupportErrorText(s.error!);
      }
      if (p.ok) _plans = p.data as List<AdvSupportPlan>;
    });
  }

  void _changed() {
    _reload();
    widget.onChanged?.call();
  }

  Future<void> _compose(String kind) async {
    final made = await showAdvRequestComposer(context, orgId: widget.orgId, memberId: widget.memberId, studentName: widget.studentName, kind: kind);
    if (made == null || !mounted) return;
    _changed();
    await _openRequest(made);
  }

  Future<void> _openRequest(AdvRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvRequestPage(orgId: widget.orgId, requestId: r.id, initial: r)));
    if (mounted) _changed();
  }

  Future<void> _plan({AdvSupportPlan? plan}) async {
    final saved = await showAdvPlanEditor(context, _api, memberId: widget.memberId, plan: plan);
    if (saved != null && mounted) _changed();
  }

  Future<void> _planStatus(AdvSupportPlan p) async {
    final saved = await showAdvPlanStatusSheet(context, _api, p, onStale: () {
      if (mounted) _reload();
    });
    if (saved != null && mounted) _changed();
  }

  Future<void> _reviewPlan(AdvSupportPlan p) async {
    final saved = await showAdvPlanReviewSheet(context, _api, p);
    if (saved != null && mounted) _changed();
  }

  Future<void> _deletePlan(AdvSupportPlan p) async {
    final yes = await appConfirm(context, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف مسودة الخطة؟', 'Delete this draft plan?'));
    if (!yes || !mounted) return;
    final r = await orgCall(() => _api.deletePlan(p.id), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(advSupportErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(t('حُذفت مسودة الخطة', 'Draft plan deleted'));
    _changed();
  }

  Future<void> _tick(AdvSupportPlan p, AdvSupportPlanItem i) async {
    final id = i.id;
    if (id == null) return;
    final next = i.done ? 'open' : 'done';
    setState(() {
      _ticking.add(id);
      _plans = [for (final x in _plans ?? const <AdvSupportPlan>[]) x.id == p.id ? x.withItemStatus(id, next) : x];
    });
    final r = await orgCall(() => _api.setPlanItemStatus(p.id, id, next), quiet: true);
    if (!mounted) return;
    setState(() => _ticking.remove(id));
    if (!r.ok) {
      showAppNotice(advSupportErrorText(r.error!), error: true);
      _reload();
      return;
    }
    final saved = r.data as AdvSupportPlan;
    setState(() => _plans = [for (final x in _plans ?? const <AdvSupportPlan>[]) x.id == saved.id ? saved : x]);
    showAppNotice(next == 'done' ? t('أُنجز البند', 'Item done') : t('أُعيد فتح البند', 'Item reopened'));
  }

  Future<void> _grant() async {
    final active = {for (final a in _summary?.accommodations ?? const <AdvAccommodationGrant>[]) a.key};
    var cats = widget.categories;
    if (cats.isEmpty) {
      final o = await orgCall(() => _api.options(), quiet: true);
      if (!mounted) return;
      if (o.ok) cats = (o.data as AdvRequestOptions).categories;
    }
    if (!mounted) return;
    final made = await showAdvGrantSheet(context, _api, memberId: widget.memberId, categories: cats, activeKeys: active);
    if (made != null && mounted) _changed();
  }

  Future<void> _end(AdvAccommodationGrant a) async {
    final ended = await showAdvEndAccommodationSheet(context, _api, a);
    if (ended != null && mounted) _changed();
  }

  @override
  Widget build(BuildContext context) => AdvSupportPane(
        load: _load,
        summary: _summary,
        plans: _plans,
        errorText: _error,
        ticking: _ticking,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onNewRequest: () => _compose('support'),
        onRefer: () => _compose('referral'),
        onNewPlan: () => _plan(),
        onGrant: _grant,
        onOpenRequest: _openRequest,
        onSeeAll: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AdvRequestsPage(orgId: widget.orgId, manage: widget.manage, memberId: widget.memberId, studentName: widget.studentName))),
        onTickItem: _tick,
        onEditPlan: (p) => _plan(plan: p),
        onPlanStatus: _planStatus,
        onReviewPlan: _reviewPlan,
        onDeletePlan: _deletePlan,
        onEndAccommodation: _end,
      );
}
