// lib/features/admin/rewards/admin_rewards_page.dart — the super admin's Rewards page (Games v3 §3.3, CONTRACT §9;
// kill switch `admin.rewards`, help page `admin.rewards`). Opened from the admin services hub (Finance group).
//
//   Rules       the reward rules: one card each (trigger, who, reward, limits) with an AppSwitch that turns it on /
//               off (PUT with every field), add / edit in a sheet, delete (409 reward_rule_used → switch it off)
//   Champions   the winners by period (daily / weekly), status and "flagged only": Award (optionally by a rule),
//               Revoke (a reason), Void the whole period (a reason, recomputed by the server)
//   Coupons     search by code / name, a status filter, Give a coupon by hand, Revoke with a reason
//   Referrals   the review queue (review first), Approve / Reject with an optional reason
//
// Master-detail: from Breakpoints.desktop the list and the chosen row's detail sit side by side; narrower the
// detail opens in a sheet. The bodies take plain values (AdminRewardRulesView, AdminChampionsView,
// AdminCouponsView, AdminReferralsView and their detail / form widgets) so test/ui/admin_rewards_layout_test.dart
// pumps them without the network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/payments/points/points_api.dart' show PointsApi;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin_common.dart' show t;
import '../admin_page.dart';
import 'admin_rewards_api.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

const kRewardTriggers = ['champion_daily', 'champion_weekly', 'referrals', 'shares', 'referee_welcome'];
const kRewardScopes = <String?>[null, 'platform', 'category', 'org'];
const kRewardWindows = ['month', 'lifetime'];
const kRewardKinds = ['coupon_percent', 'coupon_fixed', 'points'];
const kRewardAppliesTo = ['any', 'course', 'package', 'store'];

String rewardTriggerName(String v) => switch (v) {
      'champion_daily' => t('بطل اليوم', 'Daily champion'),
      'champion_weekly' => t('بطل الأسبوع', 'Weekly champion'),
      'referrals' => t('دعوات مؤهلة', 'Qualified referrals'),
      'shares' => t('فتحات رابط المشاركة', 'Share link opens'),
      'referee_welcome' => t('ترحيب بالمدعو', 'Welcome for the invited'),
      _ => v,
    };

String rewardScopeName(String? v) => switch (v) {
      null => t('أي نطاق', 'Any scope'),
      'platform' => t('الجميع', 'Everyone'),
      'category' => t('تصنيف', 'A category'),
      'org' => t('مؤسسة', 'An organization'),
      _ => v,
    };

String rewardWindowName(String? v) => switch (v) {
      'month' => t('في الشهر', 'per month'),
      'lifetime' => t('منذ البداية', 'lifetime'),
      _ => '',
    };

String rewardKindName(String v) => switch (v) {
      'coupon_percent' => t('قسيمة نسبة', 'Percent coupon'),
      'coupon_fixed' => t('قسيمة مبلغ', 'Fixed coupon'),
      'points' => t('نقاط', 'Points'),
      _ => v,
    };

String rewardAppliesName(String v) => switch (v) {
      'any' => t('أي شراء', 'Anything'),
      'course' => t('الدورات', 'Courses'),
      'package' => t('الباقات', 'Packages'),
      'store' => t('المتجر', 'The store'),
      _ => v,
    };

String _num(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// "30 %" · "50 EGP" · "100 points".
String rewardValueText({required String kind, required double value, String? currency}) => switch (kind) {
      'coupon_percent' || 'percent' => '${_num(value)} %',
      'points' => countText(value.round(),
          ar1: 'نقطة واحدة', ar2: 'نقطتان', arFew: '${value.round()} نقاط', arMany: '${value.round()} نقطة', en1: '1 point', en: '${value.round()} points'),
      _ => '${_num(value)} ${currency ?? ''}'.trim(),
    };

String rewardStatusName(String v) => switch (v) {
      'pending' => t('بانتظار المراجعة', 'Waiting for review'),
      'issued' => t('صدرت', 'Issued'),
      'revoked' => t('أُلغيت', 'Revoked'),
      _ => t('بلا مكافأة', 'No reward'),
    };

AppTone rewardStatusTone(String v) => switch (v) {
      'pending' => AppTone.warning,
      'issued' => AppTone.success,
      'revoked' => AppTone.danger,
      _ => AppTone.neutral,
    };

String championFlagName(String v) => switch (v) {
      'too_fast' => t('سريع جداً', 'Too fast'),
      'grade_mismatch' => t('نتيجة لا تطابق', 'Score mismatch'),
      'burst' => t('جولات كثيرة', 'Many rounds'),
      'shared_device' => t('جهاز مشترك', 'Shared device'),
      _ => v,
    };

const kCouponStatuses = <String?>[null, 'active', 'reserved', 'redeemed', 'expired', 'revoked'];

String couponStatusName(String? v) => switch (v) {
      null => t('الكل', 'All'),
      'active' => t('نشطة', 'Active'),
      'reserved' => t('محجوزة', 'Held'),
      'redeemed' => t('مستخدمة', 'Used'),
      'expired' => t('منتهية', 'Expired'),
      'revoked' => t('ملغاة', 'Revoked'),
      _ => v,
    };

AppTone couponStatusTone(String v) => switch (v) {
      'active' => AppTone.success,
      'reserved' => AppTone.warning,
      'redeemed' => AppTone.brand,
      'revoked' => AppTone.danger,
      _ => AppTone.neutral,
    };

String couponSourceName(String v) => v == 'manual' ? t('يدوية', 'By hand') : rewardTriggerName(v);

const kReferralStatuses = <String?>['review', 'pending', 'qualified', 'rejected', null];

String referralStatusName(String? v) => switch (v) {
      null => t('الكل', 'All'),
      'review' => t('للمراجعة', 'To review'),
      'pending' => t('قيد الانتظار', 'Pending'),
      'qualified' => t('مؤهلة', 'Qualified'),
      'rejected' => t('مرفوضة', 'Rejected'),
      _ => v,
    };

AppTone referralStatusTone(String v) => switch (v) {
      'review' => AppTone.warning,
      'qualified' => AppTone.success,
      'rejected' => AppTone.danger,
      _ => AppTone.info,
    };

String referralReasonName(String? v) => switch (v) {
      'self' => t('دعوة النفس', 'Self-referral'),
      'device_seen' => t('الجهاز نفسه', 'Same device'),
      'ip_burst' => t('دعوات كثيرة من شبكة واحدة', 'Many from one network'),
      'referrer_inactive' => t('الداعي غير نشط', 'Referrer inactive'),
      'admin' => t('قرار المشرف', 'Admin decision'),
      _ => '',
    };

String _periodText(RewardsPeriod p) {
  final kind = p.kind == 'weekly' ? t('أسبوع', 'Week') : t('يوم', 'Day');
  final start = p.start == null ? '' : AppTime.date(p.start!);
  final key = p.scopeKey == null ? '' : ' · ${p.scopeKey}';
  return '$kind $start · ${rewardScopeName(p.scopeKind)}$key';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdminRewardsPage extends StatefulWidget {
  const AdminRewardsPage({super.key, this.api});

  final AdminRewardsApi? api;

  @override
  State<AdminRewardsPage> createState() => _AdminRewardsPageState();
}

class _AdminRewardsPageState extends State<AdminRewardsPage> {
  late final AdminRewardsApi _api = widget.api ?? AdminRewardsApi();
  final _rules = GlobalKey<_RulesTabState>();
  final _champions = GlobalKey<_ChampionsTabState>();
  final _coupons = GlobalKey<_CouponsTabState>();
  final _referrals = GlobalKey<_ReferralsTabState>();
  final _visited = <int>{0};
  int _tab = 0;

  void _refresh() {
    switch (_tab) {
      case 0:
        _rules.currentState?._load();
      case 1:
        _champions.currentState?._load();
      case 2:
        _coupons.currentState?._load();
      default:
        _referrals.currentState?._load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return BasePage(
      key: const ValueKey(kAdminRewardsFeatureKey),
      child: AdminPage(
        width: AppWidth.wide,
        title: t('المكافآت والقسائم', 'Rewards & coupons'),
        icon: Icons.card_giftcard_rounded,
        helpPageId: 'admin.rewards',
        onRefresh: _refresh,
        body: Column(children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.md, gutter, AppSpace.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: AppTabs(
                  index: _tab,
                  onChanged: (i) => setState(() {
                    _tab = i;
                    _visited.add(i);
                  }),
                  items: [
                    AppTabItem(t('القواعد', 'Rules')),
                    AppTabItem(t('الأبطال', 'Champions')),
                    AppTabItem(t('القسائم', 'Coupons')),
                    AppTabItem(t('الدعوات', 'Referrals')),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(index: _tab, children: [
              _RulesTab(key: _rules, api: _api),
              _visited.contains(1) ? _ChampionsTab(key: _champions, api: _api) : const SizedBox.shrink(),
              _visited.contains(2) ? _CouponsTab(key: _coupons, api: _api) : const SizedBox.shrink(),
              _visited.contains(3) ? _ReferralsTab(key: _referrals, api: _api) : const SizedBox.shrink(),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// List + detail: side by side from [Breakpoints.desktop] (the detail in a card at the end side), else the list
/// alone (the caller opens the detail in a sheet).
class RewardsMasterDetail extends StatelessWidget {
  const RewardsMasterDetail({super.key, required this.list, this.detail, this.emptyDetail});

  final Widget list;
  final Widget? detail;
  final String? emptyDetail;

  static bool wide(BuildContext context, double width) => width >= Breakpoints.desktop;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (!wide(context, box.maxWidth)) return list;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: list),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(0, AppSpace.md, AppSpace.md, AppSpace.lg),
              child: AppCard(
                child: detail ??
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                      child: Text(emptyDetail ?? t('اختر عنصراً لعرض تفاصيله', 'Pick a row to see its details'),
                          textAlign: TextAlign.center, style: AppType.meta(context)),
                    ),
              ),
            ),
          ),
        ]);
      });
}

bool _wideNow(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

/// A reason in a sheet (null = cancelled). [required] refuses an empty one.
Future<String?> askRewardsReason(BuildContext context, {required String title, bool required = true, String? confirmLabel, bool danger = false}) =>
    showAppSheet<String>(context, (ctx) => RewardsReasonSheet(title: title, required: required, confirmLabel: confirmLabel, danger: danger));

class RewardsReasonSheet extends StatefulWidget {
  const RewardsReasonSheet({super.key, required this.title, this.required = true, this.confirmLabel, this.danger = false});

  final String title;
  final bool required, danger;
  final String? confirmLabel;

  @override
  State<RewardsReasonSheet> createState() => _RewardsReasonSheetState();
}

class _RewardsReasonSheetState extends State<RewardsReasonSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = !widget.required || _c.text.trim().isNotEmpty;
    final label = widget.confirmLabel ?? t('تأكيد', 'Confirm');
    void done() => Navigator.of(context).pop(_c.text.trim());
    return AppSheetContent(title: widget.title, icon: Icons.edit_note_rounded, children: [
      AppField(
        controller: _c,
        label: widget.required ? t('السبب', 'Reason') : t('السبب (اختياري)', 'Reason (optional)'),
        maxLines: 3,
        autofocus: true,
        required: widget.required,
        onChanged: (_) => setState(() {}),
      ),
      AppSpace.gapLg,
      widget.danger
          ? AppButton.danger(label: label, expand: true, onPressed: ok ? done : null)
          : AppButton.primary(label: label, expand: true, onPressed: ok ? done : null),
    ]);
  }
}

/// A list's head: [lead] (text or a search field) with ONE [action] at its end; stacked on a narrow box.
class _HeadRow extends StatelessWidget {
  const _HeadRow({required this.lead, required this.action});
  final Widget lead, action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => box.maxWidth < Breakpoints.mobile * 0.75
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                lead,
                AppSpace.gapSm,
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ])
            : Row(children: [Expanded(child: lead), const SizedBox(width: AppSpace.sm), action]),
      );
}

/// A row of filter chips that scrolls sideways.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.xs), children[i]],
        ]),
      );
}

/// A label · value line of a detail pane.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: Text(label, style: AppType.meta(context))),
          const SizedBox(width: AppSpace.sm),
          Expanded(flex: 3, child: Text(value.isEmpty ? '—' : value, style: AppType.body(context))),
        ]),
      );
}

Widget _stateBody({required bool loading, String? error, VoidCallback? onRetry, required bool empty, required Widget emptyState, required Widget list}) {
  if (loading) return const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
  if (error != null) return AppErrorState(message: error, onRetry: onRetry);
  if (empty) return emptyState;
  return list;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rules
// ═════════════════════════════════════════════════════════════════════════════

class _RulesTab extends StatefulWidget {
  const _RulesTab({super.key, required this.api});
  final AdminRewardsApi api;

  @override
  State<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<_RulesTab> with AutomaticKeepAliveClientMixin {
  List<RewardRule> _items = const [];
  bool _loading = true;
  String? _error;
  final _busy = <int>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await widget.api.rules();
      if (!mounted) return;
      setState(() {
        _items = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rewardsAdminErrorText(e);
      });
    }
  }

  Future<void> _toggle(RewardRule r, bool on) async {
    final id = r.id;
    if (id == null) return;
    setState(() => _busy.add(id));
    try {
      final saved = await widget.api.updateRule(id, r.copyWith(active: on));
      if (!mounted) return;
      setState(() => _items = [for (final x in _items) x.id == id ? saved : x]);
      showAppNotice(on ? t('القاعدة تعمل الآن', 'The rule is on') : t('أُوقفت القاعدة', 'The rule is off'));
    } catch (e) {
      showAppNotice(rewardsAdminErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _edit([RewardRule? r]) async {
    final saved = await showAppSheet<RewardRule>(
        context,
        (ctx) => AppSheetContent(
              title: r == null ? t('قاعدة جديدة', 'New rule') : t('تعديل القاعدة', 'Edit the rule'),
              icon: Icons.rule_rounded,
              children: [
                RewardRuleForm(
                  initial: r,
                  onSubmit: (draft) async {
                    final out = r?.id == null ? await widget.api.createRule(draft) : await widget.api.updateRule(r!.id!, draft);
                    if (ctx.mounted) Navigator.of(ctx).pop(out);
                  },
                ),
              ],
            ));
    if (saved == null || !mounted) return;
    showAppNotice(t('حُفظت القاعدة', 'The rule is saved'));
    unawaited(_load());
  }

  Future<void> _delete(RewardRule r) async {
    final id = r.id;
    if (id == null) return;
    final ok = await appConfirm(context,
        message: t('حذف قاعدة "${rewardTriggerName(r.trigger)}"؟', 'Delete the "${rewardTriggerName(r.trigger)}" rule?'),
        danger: true,
        confirmLabel: t('احذف', 'Delete'));
    if (!ok) return;
    try {
      await widget.api.deleteRule(id);
      if (!mounted) return;
      setState(() => _items = [for (final x in _items) if (x.id != id) x]);
      showAppNotice(t('حُذفت القاعدة', 'The rule is deleted'));
    } catch (e) {
      showAppNotice(rewardsAdminErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AdminRewardRulesView(
      rules: _items,
      loading: _loading,
      error: _error,
      busyIds: _busy,
      onRetry: _load,
      onAdd: () => _edit(),
      onEdit: _edit,
      onToggle: _toggle,
      onDelete: _delete,
    );
  }
}

/// The rules list with plain values.
class AdminRewardRulesView extends StatelessWidget {
  const AdminRewardRulesView({
    super.key,
    required this.rules,
    this.loading = false,
    this.error,
    this.busyIds = const {},
    this.onRetry,
    this.onAdd,
    this.onEdit,
    this.onToggle,
    this.onDelete,
  });

  final List<RewardRule> rules;
  final bool loading;
  final String? error;
  final Set<int> busyIds;
  final VoidCallback? onRetry, onAdd;
  final ValueChanged<RewardRule>? onEdit, onDelete;
  final void Function(RewardRule rule, bool on)? onToggle;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      key: const ValueKey('admin.rewards.rules'),
      padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, AppSpace.lg),
      children: [
        _HeadRow(
          lead: Text(
            t('القواعد تبدأ متوقفة. راجع القيم ثم شغّل القاعدة.', 'Rules start switched off. Check the values, then switch one on.'),
            style: AppType.meta(context),
          ),
          action: AppButton.primary(
              key: const ValueKey('admin.rewards.rules.add'), label: t('قاعدة جديدة', 'New rule'), icon: Icons.add_rounded, onPressed: onAdd),
        ),
        AppSpace.gapMd,
        _stateBody(
          loading: loading,
          error: error,
          onRetry: onRetry,
          empty: rules.isEmpty,
          emptyState: AppEmpty(
            icon: Icons.rule_rounded,
            title: t('لا توجد قواعد بعد', 'No rules yet'),
            message: t('أضف قاعدة لتمنح الأبطال والداعين قسائم خصم.', 'Add a rule to give champions and referrers discount coupons.'),
            actionLabel: t('قاعدة جديدة', 'New rule'),
            onAction: onAdd,
          ),
          list: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final r in rules)
              RewardRuleCard(
                key: ValueKey('admin.rewards.rule.${r.id}'),
                rule: r,
                busy: r.id != null && busyIds.contains(r.id),
                onEdit: onEdit == null ? null : () => onEdit!(r),
                onDelete: onDelete == null ? null : () => onDelete!(r),
                onToggle: onToggle == null ? null : (v) => onToggle!(r, v),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Who a rule rewards, in one line.
String rewardRuleWho(RewardRule r) {
  if (r.isChampion) {
    final from = r.rankFrom ?? 1, to = r.rankTo ?? from;
    final ranks = from == to ? t('المركز $from', 'Rank $from') : t('المراكز $from–$to', 'Ranks $from–$to');
    return '$ranks · ${rewardScopeName(r.scopeKind)}';
  }
  if (r.isThreshold) {
    final n = r.threshold ?? 0;
    final what = r.trigger == 'shares'
        ? countText(n, ar1: 'فتحة واحدة', ar2: 'فتحتان', arFew: '$n فتحات', arMany: '$n فتحة', en1: '1 open', en: '$n opens')
        : countText(n, ar1: 'دعوة واحدة', ar2: 'دعوتان', arFew: '$n دعوات', arMany: '$n دعوة', en1: '1 referral', en: '$n referrals');
    return '$what ${rewardWindowName(r.window)}'.trim();
  }
  return t('كل مدعو جديد', 'Every new invited account');
}

/// What a rule gives, in one line.
String rewardRuleGives(RewardRule r) {
  final v = rewardValueText(kind: r.rewardKind, value: r.value, currency: r.currency);
  if (r.rewardKind == 'points') return v;
  final cap = r.maxDiscount == null ? '' : t(' · حتى ${_num(r.maxDiscount!)} ${r.currency ?? ''}', ' · up to ${_num(r.maxDiscount!)} ${r.currency ?? ''}');
  final days = countText(r.validDays, ar1: 'يوم واحد', ar2: 'يومان', arFew: '${r.validDays} أيام', arMany: '${r.validDays} يوماً', en1: '1 day', en: '${r.validDays} days');
  return '$v$cap · ${rewardAppliesName(r.appliesTo)} · $days';
}

class RewardRuleCard extends StatelessWidget {
  const RewardRuleCard({super.key, required this.rule, this.busy = false, this.onEdit, this.onDelete, this.onToggle});

  final RewardRule rule;
  final bool busy;
  final VoidCallback? onEdit, onDelete;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final r = rule;
    final cap = r.perUserMonthCap == null
        ? null
        : t('حد ${r.perUserMonthCap} لكل مستخدم شهرياً', 'Max ${r.perUserMonthCap} per user a month');
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      onTap: onEdit,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(rewardTriggerName(r.trigger), style: AppType.section(context)),
              AppStatusBadge(
                  label: r.active ? t('تعمل', 'On') : t('متوقفة', 'Off'), tone: r.active ? AppTone.success : AppTone.neutral, dense: true),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(rewardRuleWho(r), style: AppType.body(context)),
            Text(rewardRuleGives(r), style: AppType.meta(context)),
            if (cap != null || r.monthBudget != null || r.countryCode != null)
              Text(
                [
                  ?cap,
                  if (r.monthBudget != null) t('ميزانية شهرية ${_num(r.monthBudget!)}', 'Monthly budget ${_num(r.monthBudget!)}'),
                  if (r.countryCode != null) r.countryCode!,
                ].join(' · '),
                style: AppType.meta(context),
              ),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, children: [
              AppButton.ghost(label: t('تعديل', 'Edit'), icon: Icons.edit_rounded, size: AppButtonSize.sm, onPressed: onEdit),
              AppButton.ghost(label: t('حذف', 'Delete'), icon: Icons.delete_outline_rounded, size: AppButtonSize.sm, onPressed: onDelete),
            ]),
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        AppSwitch(
          value: r.active,
          semanticLabel: t('تشغيل القاعدة', 'Rule on'),
          onChanged: busy || onToggle == null ? null : onToggle,
        ),
      ]),
    );
  }
}

/// The add / edit form of a rule. [onSubmit] saves (its error shows under the form).
class RewardRuleForm extends StatefulWidget {
  const RewardRuleForm({super.key, this.initial, required this.onSubmit});

  final RewardRule? initial;
  final Future<void> Function(RewardRule draft) onSubmit;

  @override
  State<RewardRuleForm> createState() => _RewardRuleFormState();
}

class _RewardRuleFormState extends State<RewardRuleForm> {
  late final RewardRule _r = widget.initial ?? const RewardRule();
  late String _trigger = _r.trigger;
  late String? _scope = _r.scopeKind;
  late String _window = _r.window ?? 'month';
  late String _kind = _r.rewardKind;
  late String _applies = _r.appliesTo;
  late bool _active = _r.active;
  late final _rankFrom = TextEditingController(text: '${_r.rankFrom ?? 1}');
  late final _rankTo = TextEditingController(text: '${_r.rankTo ?? _r.rankFrom ?? 1}');
  late final _threshold = TextEditingController(text: _r.threshold == null ? '' : '${_r.threshold}');
  late final _value = TextEditingController(text: _num(_r.value));
  late final _currency = TextEditingController(text: _r.currency ?? 'EGP');
  late final _maxDiscount = TextEditingController(text: _r.maxDiscount == null ? '' : _num(_r.maxDiscount!));
  late final _minOrder = TextEditingController(text: _num(_r.minOrder));
  late final _validDays = TextEditingController(text: '${_r.validDays}');
  late final _cap = TextEditingController(text: _r.perUserMonthCap == null ? '' : '${_r.perUserMonthCap}');
  late final _budget = TextEditingController(text: _r.monthBudget == null ? '' : _num(_r.monthBudget!));
  late final _country = TextEditingController(text: _r.countryCode ?? '');
  bool _busy = false;
  String? _error;

  bool get _champion => _trigger == 'champion_daily' || _trigger == 'champion_weekly';
  bool get _isThreshold => _trigger == 'referrals' || _trigger == 'shares';

  @override
  void dispose() {
    for (final c in [_rankFrom, _rankTo, _threshold, _value, _currency, _maxDiscount, _minOrder, _validDays, _cap, _budget, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());
  double? _dbl(TextEditingController c) => double.tryParse(c.text.trim());
  String? _str(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final value = _dbl(_value);
    if (value == null || value <= 0) {
      setState(() => _error = t('اكتب قيمة المكافأة', 'Enter the reward value'));
      return;
    }
    if (_isThreshold && (_int(_threshold) ?? 0) <= 0) {
      setState(() => _error = t('اكتب العدد المطلوب', 'Enter the number needed'));
      return;
    }
    final draft = RewardRule(
      id: _r.id,
      trigger: _trigger,
      scopeKind: _champion ? _scope : null,
      rankFrom: _champion ? (_int(_rankFrom) ?? 1) : null,
      rankTo: _champion ? (_int(_rankTo) ?? _int(_rankFrom) ?? 1) : null,
      threshold: _isThreshold ? _int(_threshold) : null,
      window: _isThreshold ? _window : null,
      rewardKind: _kind,
      value: value,
      currency: _kind == 'points' ? null : _str(_currency)?.toUpperCase(),
      maxDiscount: _kind == 'points' ? null : _dbl(_maxDiscount),
      appliesTo: _applies,
      minOrder: _dbl(_minOrder) ?? 0,
      validDays: _int(_validDays) ?? 30,
      perUserMonthCap: _int(_cap),
      monthBudget: _dbl(_budget),
      countryCode: _str(_country)?.toUpperCase(),
      active: _active,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(draft);
    } catch (e) {
      if (mounted) setState(() => _error = rewardsAdminErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pair(Widget a, Widget b) => LayoutBuilder(
        builder: (context, box) => box.maxWidth < Breakpoints.mobile / 2 + AppSpace.xl * 4
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, AppSpace.gapSm, b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: AppSpace.sm), Expanded(child: b)]),
      );

  AppDropdown<String> _drop(String key, String label, String value, List<String> values, String Function(String) name, ValueChanged<String> on) =>
      AppDropdown<String>(
        key: ValueKey('admin.rewards.form.$key'),
        decoration: InputDecoration(labelText: label),
        value: value,
        items: [for (final v in values) DropdownMenuItem(value: v, child: Text(name(v), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) setState(() => on(v));
        },
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final money = _kind != 'points';
    return Column(key: const ValueKey('admin.rewards.rule_form'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _drop('trigger', t('متى تُمنح', 'When it is given'), _trigger, kRewardTriggers, rewardTriggerName, (v) => _trigger = v),
      AppSpace.gapSm,
      if (_champion) ...[
        AppDropdown<String>(
          key: const ValueKey('admin.rewards.form.scope'),
          decoration: InputDecoration(labelText: t('النطاق', 'Scope')),
          value: _scope ?? '',
          items: [
            for (final s in kRewardScopes) DropdownMenuItem(value: s ?? '', child: Text(rewardScopeName(s), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _scope = v == null || v.isEmpty ? null : v),
        ),
        AppSpace.gapSm,
        _pair(
          AppNumberField(controller: _rankFrom, label: t('من المركز', 'From rank'), min: 1, max: 10),
          AppNumberField(controller: _rankTo, label: t('إلى المركز', 'To rank'), min: 1, max: 10),
        ),
        AppSpace.gapSm,
      ],
      if (_isThreshold) ...[
        _pair(
          AppNumberField(controller: _threshold, label: t('العدد المطلوب', 'Number needed'), min: 1),
          _drop('window', t('خلال', 'Counted'), _window, kRewardWindows, rewardWindowName, (v) => _window = v),
        ),
        AppSpace.gapSm,
      ],
      _pair(
        _drop('kind', t('نوع المكافأة', 'Reward'), _kind, kRewardKinds, rewardKindName, (v) => _kind = v),
        AppNumberField(
            controller: _value,
            label: _kind == 'coupon_percent' ? t('النسبة %', 'Percent') : (_kind == 'points' ? t('النقاط', 'Points') : t('المبلغ', 'Amount')),
            min: 0,
            decimals: _kind == 'coupon_fixed' ? 2 : 0),
      ),
      AppSpace.gapSm,
      if (money) ...[
        _pair(
          AppField(controller: _currency, label: t('العملة', 'Currency'), ltr: true),
          AppNumberField(controller: _maxDiscount, label: t('أقصى خصم (اختياري)', 'Max discount (optional)'), min: 0, decimals: 2),
        ),
        AppSpace.gapSm,
        _pair(
          _drop('applies', t('تصلح لـ', 'Works on'), _applies, kRewardAppliesTo, rewardAppliesName, (v) => _applies = v),
          AppNumberField(controller: _minOrder, label: t('أقل قيمة للطلب', 'Minimum order'), min: 0, decimals: 2),
        ),
        AppSpace.gapSm,
      ],
      _pair(
        AppNumberField(controller: _validDays, label: t('صالحة لعدد أيام', 'Valid for days'), min: 1, max: 365),
        AppNumberField(controller: _cap, label: t('حد لكل مستخدم شهرياً', 'Per user a month'), min: 1),
      ),
      AppSpace.gapSm,
      _pair(
        AppNumberField(controller: _budget, label: t('ميزانية الشهر (اختياري)', 'Month budget (optional)'), min: 0, decimals: 2),
        AppField(controller: _country, label: t('رمز الدولة (اختياري)', 'Country code (optional)'), ltr: true),
      ),
      AppSpace.gapSm,
      AppSwitchTile(
        key: const ValueKey('admin.rewards.form.active'),
        title: t('القاعدة تعمل', 'Rule is on'),
        subtitle: t('عند التشغيل تُمنح المكافأة تلقائياً لمن يستحق.', 'When on, the reward is given to whoever qualifies.'),
        icon: Icons.power_settings_new_rounded,
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
      if (_error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      AppSpace.gapLg,
      AppButton.primary(
        key: const ValueKey('admin.rewards.form.save'),
        label: t('حفظ', 'Save'),
        icon: Icons.check_rounded,
        expand: true,
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Champions
// ═════════════════════════════════════════════════════════════════════════════

class _ChampionsTab extends StatefulWidget {
  const _ChampionsTab({super.key, required this.api});
  final AdminRewardsApi api;

  @override
  State<_ChampionsTab> createState() => _ChampionsTabState();
}

class _ChampionsTabState extends State<_ChampionsTab> with AutomaticKeepAliveClientMixin {
  String _period = 'weekly';
  bool _flagged = false;
  String? _status;
  List<AdminChampion> _items = const [];
  List<RewardRule> _rules = const [];
  bool _loading = true, _busy = false;
  String? _error;
  int? _selected;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.api.rules().then((r) {
      if (mounted) setState(() => _rules = r);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.champions(period: _period, status: _status, flagged: _flagged);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = r.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = rewardsAdminErrorText(e);
      });
    }
  }

  AdminChampion? get _current => _items.where((x) => x.id == _selected).firstOrNull;

  void _replace(AdminChampion c) => setState(() => _items = [for (final x in _items) x.id == c.id ? c : x]);

  Future<void> _run(Future<void> Function() fn, String done) async {
    setState(() => _busy = true);
    try {
      await fn();
      showAppNotice(done);
    } catch (e) {
      showAppNotice(rewardsAdminErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _award(AdminChampion c, int? ruleId) => _run(() async => _replace(await widget.api.award(c.id, ruleId: ruleId)), t('صدرت المكافأة', 'The reward is issued'));

  Future<void> _revoke(AdminChampion c) async {
    final reason = await askRewardsReason(context, title: t('إلغاء مكافأة ${c.name}', 'Revoke ${c.name}\'s reward'), danger: true, confirmLabel: t('ألغِ', 'Revoke'));
    if (reason == null || !mounted) return;
    await _run(() async => _replace(await widget.api.revokeChampion(c.id, reason)), t('أُلغيت المكافأة', 'The reward is revoked'));
  }

  Future<void> _void(AdminChampion c) async {
    final p = c.period;
    if (p == null) return;
    final ok = await appConfirm(context,
        message: t('إلغاء نتيجة هذه الفترة كلها وإعادة حسابها؟ تُلغى مكافآت أبطالها.', 'Void this whole period and compute it again? Its champions\' rewards are revoked.'),
        danger: true,
        confirmLabel: t('ألغِ الفترة', 'Void the period'));
    if (!ok || !mounted) return;
    final reason = await askRewardsReason(context, title: t('سبب إلغاء الفترة', 'Why void the period'), danger: true, confirmLabel: t('ألغِ الفترة', 'Void the period'));
    if (reason == null || !mounted) return;
    await _run(() async {
      await widget.api.voidPeriod(p.id, reason);
      _selected = null;
      await _load();
    }, t('أُلغيت الفترة', 'The period is voided'));
  }

  Widget _detail(AdminChampion c) => AdminChampionDetail(
        champion: c,
        rules: [for (final r in _rules) if (r.isChampion) r],
        busy: _busy,
        onAward: (ruleId) => _award(c, ruleId),
        onRevoke: () => _revoke(c),
        onVoid: () => _void(c),
      );

  void _open(AdminChampion c) {
    if (_wideNow(context)) {
      setState(() => _selected = c.id);
    } else {
      showAppSheet<void>(context, (_) => AppSheetContent(title: c.name, icon: Icons.emoji_events_rounded, children: [_detail(c)]));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cur = _current;
    return RewardsMasterDetail(
      detail: cur == null ? null : _detail(cur),
      list: AdminChampionsView(
        items: _items,
        loading: _loading,
        error: _error,
        onRetry: _load,
        period: _period,
        onPeriod: (v) {
          setState(() => _period = v);
          _load();
        },
        flagged: _flagged,
        onFlagged: (v) {
          setState(() => _flagged = v);
          _load();
        },
        status: _status,
        onStatus: (v) {
          setState(() => _status = v);
          _load();
        },
        selectedId: _selected,
        onOpen: _open,
      ),
    );
  }
}

/// The champions list with plain values.
class AdminChampionsView extends StatelessWidget {
  const AdminChampionsView({
    super.key,
    required this.items,
    this.loading = false,
    this.error,
    this.onRetry,
    this.period = 'weekly',
    this.onPeriod,
    this.flagged = false,
    this.onFlagged,
    this.status,
    this.onStatus,
    this.selectedId,
    this.onOpen,
  });

  final List<AdminChampion> items;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String period;
  final ValueChanged<String>? onPeriod;
  final bool flagged;
  final ValueChanged<bool>? onFlagged;

  /// The reward status filter (null = every one).
  final String? status;
  final ValueChanged<String?>? onStatus;
  final int? selectedId;
  final ValueChanged<AdminChampion>? onOpen;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      key: const ValueKey('admin.rewards.champions'),
      padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, AppSpace.lg),
      children: [
        _ChipRow(children: [
          AppChoiceChip(label: t('يومي', 'Daily'), selected: period == 'daily', onTap: () => onPeriod?.call('daily')),
          AppChoiceChip(label: t('أسبوعي', 'Weekly'), selected: period == 'weekly', onTap: () => onPeriod?.call('weekly')),
          AppChoiceChip(
            key: const ValueKey('admin.rewards.champions.flagged'),
            icon: Icons.flag_rounded,
            label: t('المعلَّمة فقط', 'Flagged only'),
            selected: flagged,
            onTap: () => onFlagged?.call(!flagged),
          ),
          for (final s in const ['pending', 'issued', 'revoked'])
            AppChoiceChip(label: rewardStatusName(s), selected: status == s, onTap: () => onStatus?.call(status == s ? null : s)),
        ]),
        AppSpace.gapMd,
        _stateBody(
          loading: loading,
          error: error,
          onRetry: onRetry,
          empty: items.isEmpty,
          emptyState: AppEmpty(
            icon: Icons.emoji_events_rounded,
            title: t('لا يوجد أبطال هنا بعد', 'No champions here yet'),
            message: t('يظهر الأبطال بعد انتهاء كل فترة.', 'Champions show up after each period ends.'),
          ),
          list: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final c in items)
              AdminChampionTile(key: ValueKey('admin.rewards.champion.${c.id}'), champion: c, selected: c.id == selectedId, onTap: () => onOpen?.call(c)),
          ]),
        ),
      ],
    );
  }
}

class AdminChampionTile extends StatelessWidget {
  const AdminChampionTile({super.key, required this.champion, this.selected = false, this.onTap});

  final AdminChampion champion;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = champion;
    final colors = context.colors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      highlight: selected,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppTouch.min),
          child: Text('${c.rank}', textAlign: TextAlign.center, style: AppType.section(context).copyWith(color: colors.textMedium)),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name.isEmpty ? (c.user?.label ?? '#${c.id}') : c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text(
              [
                countText(c.games, ar1: 'لعبة واحدة', ar2: 'لعبتان', arFew: '${c.games} ألعاب', arMany: '${c.games} لعبة', en1: '1 game', en: '${c.games} games'),
                if (c.period != null) _periodText(c.period!),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              AppStatusBadge(label: rewardStatusName(c.rewardStatus), tone: rewardStatusTone(c.rewardStatus), dense: true),
              for (final f in c.flags) AppStatusBadge(label: championFlagName(f), tone: AppTone.danger, icon: Icons.flag_rounded, dense: true),
            ]),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Text('${c.points}', style: AppType.section(context)),
      ]),
    );
  }
}

/// One champion: the facts, then Award (optionally by a rule) / Revoke / Void the period.
class AdminChampionDetail extends StatefulWidget {
  const AdminChampionDetail({super.key, required this.champion, this.rules = const [], this.busy = false, this.onAward, this.onRevoke, this.onVoid});

  final AdminChampion champion;
  final List<RewardRule> rules;
  final bool busy;
  final ValueChanged<int?>? onAward;
  final VoidCallback? onRevoke, onVoid;

  @override
  State<AdminChampionDetail> createState() => _AdminChampionDetailState();
}

class _AdminChampionDetailState extends State<AdminChampionDetail> {
  int? _rule;

  @override
  Widget build(BuildContext context) {
    final c = widget.champion;
    final acc = c.accuracy == null ? '' : '${(c.accuracy! * (c.accuracy! <= 1 ? 100 : 1)).round()} %';
    final mins = c.durationMs == null ? '' : '${(c.durationMs! / 60000).toStringAsFixed(1)} ${t('دقيقة', 'min')}';
    final canAward = c.rewardStatus == 'none' || c.rewardStatus == 'pending';
    final canRevoke = c.rewardStatus == 'issued' || c.rewardStatus == 'pending';
    return Column(key: const ValueKey('admin.rewards.champion_detail'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(c.name.isEmpty ? '#${c.id}' : c.name, style: AppType.section(context)),
      if (c.user != null) Text(c.user!.label, style: AppType.meta(context)),
      AppSpace.gapSm,
      _Fact(t('المركز', 'Rank'), '${c.rank}'),
      _Fact(t('النقاط', 'Points'), '${c.points}'),
      _Fact(t('الألعاب', 'Games'), '${c.games}'),
      _Fact(t('الدقة', 'Accuracy'), acc),
      _Fact(t('الوقت الكلي', 'Total time'), mins),
      if (c.period != null) _Fact(t('الفترة', 'Period'), _periodText(c.period!)),
      _Fact(t('المكافأة', 'Reward'), rewardStatusName(c.rewardStatus)),
      if (c.couponId != null) _Fact(t('القسيمة', 'Coupon'), '#${c.couponId}'),
      if (c.notifiedAt != null) _Fact(t('أُبلغ', 'Notified'), AppTime.dateTime(c.notifiedAt!)),
      if (c.flags.isNotEmpty) ...[
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          for (final f in c.flags) AppStatusBadge(label: championFlagName(f), tone: AppTone.danger, icon: Icons.flag_rounded, dense: true),
        ]),
      ],
      AppSpace.gapMd,
      if (canAward) ...[
        if (widget.rules.isNotEmpty) ...[
          AppDropdown<int>(
            key: const ValueKey('admin.rewards.award.rule'),
            decoration: InputDecoration(labelText: t('حسب القاعدة', 'By the rule')),
            value: _rule ?? 0,
            items: [
              DropdownMenuItem(value: 0, child: Text(t('القاعدة المطابقة تلقائياً', 'The matching rule'), overflow: TextOverflow.ellipsis)),
              for (final r in widget.rules)
                if (r.id != null)
                  DropdownMenuItem(value: r.id!, child: Text('${rewardTriggerName(r.trigger)} · ${rewardRuleGives(r)}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _rule = v == 0 ? null : v),
          ),
          AppSpace.gapSm,
        ],
        AppButton.primary(
          key: const ValueKey('admin.rewards.award'),
          label: t('امنح المكافأة', 'Award'),
          icon: Icons.card_giftcard_rounded,
          expand: true,
          busy: widget.busy,
          onPressed: widget.busy || widget.onAward == null ? null : () => widget.onAward!(_rule),
        ),
        AppSpace.gapXs,
      ],
      if (canRevoke) ...[
        AppButton.secondary(
          label: t('ألغِ المكافأة', 'Revoke'),
          icon: Icons.undo_rounded,
          expand: true,
          onPressed: widget.busy ? null : widget.onRevoke,
        ),
        AppSpace.gapXs,
      ],
      AppButton.danger(
        key: const ValueKey('admin.rewards.void'),
        label: t('ألغِ الفترة كلها', 'Void the whole period'),
        icon: Icons.block_rounded,
        expand: true,
        onPressed: widget.busy || c.period == null ? null : widget.onVoid,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Coupons
// ═════════════════════════════════════════════════════════════════════════════

class _CouponsTab extends StatefulWidget {
  const _CouponsTab({super.key, required this.api});
  final AdminRewardsApi api;

  @override
  State<_CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends State<_CouponsTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String? _status;
  List<AdminCoupon> _items = const [];
  int _total = 0;
  bool _loading = true, _busy = false;
  String? _error;
  int? _selected;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.coupons(q: _q, status: _status);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = r.items;
        _total = r.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = rewardsAdminErrorText(e);
      });
    }
  }

  Future<void> _give() async {
    final made = await showAppSheet<AdminCoupon>(
        context,
        (ctx) => AppSheetContent(title: t('امنح قسيمة', 'Give a coupon'), icon: Icons.card_giftcard_rounded, children: [
              RewardsGiveCouponForm(
                searchUsers: (q) async => [
                  for (final r in (await const PointsApi().users(q: q)).$1) RewardsUser(id: r.user.id, name: r.user.name, username: r.user.username),
                ],
                onSubmit: (d) async {
                  final c = await widget.api.giveCoupon(d);
                  if (ctx.mounted) Navigator.of(ctx).pop(c);
                },
              ),
            ]));
    if (made == null || !mounted) return;
    showAppNotice(t('أُرسلت القسيمة ${made.code}', 'Coupon ${made.code} sent'));
    unawaited(_load());
  }

  Future<void> _revoke(AdminCoupon c) async {
    final reason = await askRewardsReason(context, title: t('إلغاء القسيمة ${c.code}', 'Revoke coupon ${c.code}'), danger: true, confirmLabel: t('ألغِ', 'Revoke'));
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await widget.api.revokeCoupon(c.id, reason);
      if (!mounted) return;
      setState(() => _items = [for (final x in _items) x.id == c.id ? out : x]);
      showAppNotice(t('أُلغيت القسيمة', 'The coupon is revoked'));
    } catch (e) {
      showAppNotice(rewardsAdminErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _detail(AdminCoupon c) => AdminCouponDetail(coupon: c, busy: _busy, onRevoke: () => _revoke(c));

  void _open(AdminCoupon c) {
    if (_wideNow(context)) {
      setState(() => _selected = c.id);
    } else {
      showAppSheet<void>(context, (_) => AppSheetContent(title: c.code, icon: Icons.confirmation_number_rounded, children: [_detail(c)]));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cur = _items.where((x) => x.id == _selected).firstOrNull;
    return RewardsMasterDetail(
      detail: cur == null ? null : _detail(cur),
      list: AdminCouponsView(
        items: _items,
        total: _total,
        loading: _loading,
        error: _error,
        onRetry: _load,
        onSearch: (q) {
          _q = q;
          _load();
        },
        status: _status,
        onStatus: (v) {
          setState(() => _status = v);
          _load();
        },
        onGive: _give,
        selectedId: _selected,
        onOpen: _open,
      ),
    );
  }
}

/// The coupons list with plain values.
class AdminCouponsView extends StatelessWidget {
  const AdminCouponsView({
    super.key,
    required this.items,
    this.total = 0,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onSearch,
    this.status,
    this.onStatus,
    this.onGive,
    this.selectedId,
    this.onOpen,
  });

  final List<AdminCoupon> items;
  final int total;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry, onGive;
  final ValueChanged<String>? onSearch;
  final String? status;
  final ValueChanged<String?>? onStatus;
  final int? selectedId;
  final ValueChanged<AdminCoupon>? onOpen;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      key: const ValueKey('admin.rewards.coupons'),
      padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, AppSpace.lg),
      children: [
        _HeadRow(
          lead: AppSearchField(
            key: const ValueKey('admin.rewards.coupons.search'),
            hint: t('ابحث بالرمز أو الاسم', 'Search by code or name'),
            onChanged: (q) => onSearch?.call(q),
          ),
          action: AppButton.primary(
              key: const ValueKey('admin.rewards.coupons.give'), label: t('امنح قسيمة', 'Give a coupon'), icon: Icons.add_rounded, onPressed: onGive),
        ),
        AppSpace.gapSm,
        _ChipRow(children: [
          for (final s in kCouponStatuses) AppChoiceChip(label: couponStatusName(s), selected: status == s, onTap: () => onStatus?.call(s)),
        ]),
        AppSpace.gapMd,
        if (!loading && error == null && items.isNotEmpty) ...[
          Text(countText(total, ar1: 'قسيمة واحدة', ar2: 'قسيمتان', arFew: '$total قسائم', arMany: '$total قسيمة', en1: '1 coupon', en: '$total coupons'),
              style: AppType.meta(context)),
          AppSpace.gapXs,
        ],
        _stateBody(
          loading: loading,
          error: error,
          onRetry: onRetry,
          empty: items.isEmpty,
          emptyState: AppEmpty(
            icon: Icons.confirmation_number_rounded,
            title: t('لا توجد قسائم هنا', 'No coupons here'),
            message: t('تصدر القسائم من القواعد، أو امنح واحدة بيدك.', 'Coupons come from the rules, or give one by hand.'),
            actionLabel: t('امنح قسيمة', 'Give a coupon'),
            onAction: onGive,
          ),
          list: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final c in items)
              AdminCouponTile(key: ValueKey('admin.rewards.coupon.${c.id}'), coupon: c, selected: c.id == selectedId, onTap: () => onOpen?.call(c)),
          ]),
        ),
      ],
    );
  }
}

class AdminCouponTile extends StatelessWidget {
  const AdminCouponTile({super.key, required this.coupon, this.selected = false, this.onTap});

  final AdminCoupon coupon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = coupon;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      highlight: selected,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Directionality(textDirection: TextDirection.ltr, child: Text(c.code, style: AppType.section(context))),
          AppStatusBadge(label: couponStatusName(c.status), tone: couponStatusTone(c.status), dense: true),
          Text(rewardValueText(kind: c.kind, value: c.value, currency: c.currency), style: AppType.bodyStrong(context)),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(c.user?.label ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
        Text(
          [
            couponSourceName(c.source),
            if (c.expiresAt != null) t('تنتهي ${AppTime.date(c.expiresAt!)}', 'Ends ${AppTime.date(c.expiresAt!)}'),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context),
        ),
      ]),
    );
  }
}

class AdminCouponDetail extends StatelessWidget {
  const AdminCouponDetail({super.key, required this.coupon, this.busy = false, this.onRevoke});

  final AdminCoupon coupon;
  final bool busy;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = coupon;
    final canRevoke = c.status == 'active';
    return Column(key: const ValueKey('admin.rewards.coupon_detail'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Directionality(textDirection: TextDirection.ltr, child: Text(c.code, style: AppType.section(context))),
      AppSpace.gapSm,
      _Fact(t('الحالة', 'Status'), couponStatusName(c.status)),
      _Fact(t('القيمة', 'Value'), rewardValueText(kind: c.kind, value: c.value, currency: c.currency)),
      if (c.maxDiscount != null) _Fact(t('أقصى خصم', 'Max discount'), '${_num(c.maxDiscount!)} ${c.currency ?? ''}'),
      _Fact(t('تصلح لـ', 'Works on'), rewardAppliesName(c.appliesTo)),
      if (c.minOrder > 0) _Fact(t('أقل طلب', 'Minimum order'), _num(c.minOrder)),
      _Fact(t('المصدر', 'Source'), couponSourceName(c.source)),
      _Fact(t('صاحبها', 'Owner'), c.user?.label ?? ''),
      if (c.issuedAt != null) _Fact(t('صدرت', 'Issued'), AppTime.dateTime(c.issuedAt!)),
      if (c.expiresAt != null) _Fact(t('تنتهي', 'Ends'), AppTime.dateTime(c.expiresAt!)),
      if (c.redeemedAt != null) _Fact(t('استُخدمت', 'Used'), AppTime.dateTime(c.redeemedAt!)),
      if (c.revokeReason != null) _Fact(t('سبب الإلغاء', 'Revoke reason'), c.revokeReason!),
      if (c.issueKey != null) _Fact(t('مفتاح الإصدار', 'Issue key'), c.issueKey!),
      if (canRevoke) ...[
        AppSpace.gapMd,
        AppButton.danger(
          key: const ValueKey('admin.rewards.coupon.revoke'),
          label: t('ألغِ القسيمة', 'Revoke the coupon'),
          icon: Icons.block_rounded,
          expand: true,
          busy: busy,
          onPressed: busy ? null : onRevoke,
        ),
      ],
    ]);
  }
}

/// "Give a coupon": find the person (by name, e-mail, @username or an id), the coupon's terms, a note.
class RewardsGiveCouponForm extends StatefulWidget {
  const RewardsGiveCouponForm({super.key, required this.onSubmit, this.searchUsers});

  final Future<void> Function(RewardsCouponDraft draft) onSubmit;
  final Future<List<RewardsUser>> Function(String q)? searchUsers;

  @override
  State<RewardsGiveCouponForm> createState() => _RewardsGiveCouponFormState();
}

class _RewardsGiveCouponFormState extends State<RewardsGiveCouponForm> {
  RewardsUser? _user;
  List<RewardsUser> _found = const [];
  bool _searching = false;
  String _kind = 'percent';
  String _applies = 'any';
  final _value = TextEditingController(text: '10');
  final _currency = TextEditingController(text: 'EGP');
  final _max = TextEditingController();
  final _min = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    for (final c in [_value, _currency, _max, _min, _days, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search(String q) async {
    final s = q.trim();
    final id = int.tryParse(s);
    if (id != null) {
      setState(() => _found = [RewardsUser(id: id, name: '#$id')]);
      return;
    }
    final fn = widget.searchUsers;
    if (fn == null || s.length < 2) {
      setState(() => _found = const []);
      return;
    }
    final seq = ++_seq;
    setState(() => _searching = true);
    try {
      final r = await fn(s);
      if (mounted && seq == _seq) setState(() => _found = r.take(8).toList());
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _found = const []);
    } finally {
      if (mounted && seq == _seq) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final u = _user;
    final value = double.tryParse(_value.text.trim());
    if (u == null) return setState(() => _error = t('اختر الشخص أولاً', 'Pick the person first'));
    if (value == null || value <= 0) return setState(() => _error = t('اكتب قيمة القسيمة', 'Enter the coupon value'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(RewardsCouponDraft(
        userId: u.id,
        kind: _kind,
        value: value,
        currency: _currency.text.trim().isEmpty ? null : _currency.text.trim().toUpperCase(),
        maxDiscount: double.tryParse(_max.text.trim()),
        appliesTo: _applies,
        minOrder: double.tryParse(_min.text.trim()),
        validDays: int.tryParse(_days.text.trim()),
        note: _note.text,
      ));
    } catch (e) {
      if (mounted) setState(() => _error = rewardsAdminErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = _user;
    return Column(key: const ValueKey('admin.rewards.give_form'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppFieldLabel(t('لمن', 'For')),
      if (u != null)
        AppCard(
          child: Row(children: [
            Icon(Icons.person_rounded, color: c.primary, size: AppIconSize.md),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(u.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            AppButton.ghost(label: t('تغيير', 'Change'), size: AppButtonSize.sm, onPressed: () => setState(() => _user = null)),
          ]),
        )
      else ...[
        AppSearchField(
          key: const ValueKey('admin.rewards.give.user'),
          hint: t('الاسم أو البريد أو @المستخدم أو الرقم', 'Name, e-mail, @username or id'),
          onChanged: _search,
        ),
        if (_searching) const Padding(padding: EdgeInsets.only(top: AppSpace.xs), child: AppListSkeleton(items: 2, padding: EdgeInsets.zero)),
        for (final f in _found)
          AppCard(
            margin: const EdgeInsets.only(top: AppSpace.xs),
            onTap: () => setState(() {
              _user = f;
              _found = const [];
            }),
            child: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
          ),
      ],
      AppSpace.gapMd,
      AppDropdown<String>(
        decoration: InputDecoration(labelText: t('النوع', 'Kind')),
        value: _kind,
        items: [
          DropdownMenuItem(value: 'percent', child: Text(t('نسبة %', 'Percent'), overflow: TextOverflow.ellipsis)),
          DropdownMenuItem(value: 'fixed', child: Text(t('مبلغ ثابت', 'Fixed amount'), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _kind = v ?? 'percent'),
      ),
      AppSpace.gapSm,
      AppNumberField(controller: _value, label: _kind == 'percent' ? t('النسبة %', 'Percent') : t('المبلغ', 'Amount'), min: 0, decimals: _kind == 'fixed' ? 2 : 0),
      AppSpace.gapSm,
      AppField(controller: _currency, label: t('العملة', 'Currency'), ltr: true),
      AppSpace.gapSm,
      AppNumberField(controller: _max, label: t('أقصى خصم (اختياري)', 'Max discount (optional)'), min: 0, decimals: 2),
      AppSpace.gapSm,
      AppDropdown<String>(
        decoration: InputDecoration(labelText: t('تصلح لـ', 'Works on')),
        value: _applies,
        items: [for (final v in kRewardAppliesTo) DropdownMenuItem(value: v, child: Text(rewardAppliesName(v), overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _applies = v ?? 'any'),
      ),
      AppSpace.gapSm,
      AppNumberField(controller: _min, label: t('أقل قيمة للطلب (اختياري)', 'Minimum order (optional)'), min: 0, decimals: 2),
      AppSpace.gapSm,
      AppNumberField(controller: _days, label: t('صالحة لعدد أيام', 'Valid for days'), min: 1, max: 365),
      AppSpace.gapSm,
      AppField(controller: _note, label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 2),
      if (_error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      AppSpace.gapLg,
      AppButton.primary(
        key: const ValueKey('admin.rewards.give.save'),
        label: t('امنح القسيمة', 'Give the coupon'),
        icon: Icons.send_rounded,
        expand: true,
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Referrals
// ═════════════════════════════════════════════════════════════════════════════

class _ReferralsTab extends StatefulWidget {
  const _ReferralsTab({super.key, required this.api});
  final AdminRewardsApi api;

  @override
  State<_ReferralsTab> createState() => _ReferralsTabState();
}

class _ReferralsTabState extends State<_ReferralsTab> with AutomaticKeepAliveClientMixin {
  String? _status = 'review';
  List<AdminReferral> _items = const [];
  bool _loading = true, _busy = false;
  String? _error;
  int? _selected;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.referrals(status: _status);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = r.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = rewardsAdminErrorText(e);
      });
    }
  }

  Future<void> _decide(AdminReferral r, bool approve, {BuildContext? sheet}) async {
    final reason = await askRewardsReason(context,
        title: approve ? t('قبول الدعوة', 'Approve the referral') : t('رفض الدعوة', 'Reject the referral'),
        required: false,
        danger: !approve,
        confirmLabel: approve ? t('اقبل', 'Approve') : t('ارفض', 'Reject'));
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = approve ? await widget.api.approveReferral(r.id, reason: reason) : await widget.api.rejectReferral(r.id, reason: reason);
      if (!mounted) return;
      setState(() => _items = [for (final x in _items) x.id == r.id ? out : x]);
      if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
      showAppNotice(approve ? t('قُبلت الدعوة', 'The referral is approved') : t('رُفضت الدعوة', 'The referral is rejected'));
    } catch (e) {
      showAppNotice(rewardsAdminErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(AdminReferral r) {
    if (_wideNow(context)) {
      setState(() => _selected = r.id);
    } else {
      showAppSheet<void>(
          context,
          (ctx) => AppSheetContent(title: t('دعوة', 'Referral'), icon: Icons.person_add_alt_1_rounded, children: [
                AdminReferralDetail(
                    referral: r, onApprove: () => _decide(r, true, sheet: ctx), onReject: () => _decide(r, false, sheet: ctx)),
              ]));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cur = _items.where((x) => x.id == _selected).firstOrNull;
    return RewardsMasterDetail(
      detail: cur == null
          ? null
          : AdminReferralDetail(referral: cur, busy: _busy, onApprove: () => _decide(cur, true), onReject: () => _decide(cur, false)),
      list: AdminReferralsView(
        items: _items,
        loading: _loading,
        error: _error,
        onRetry: _load,
        status: _status,
        onStatus: (v) {
          setState(() => _status = v);
          _load();
        },
        selectedId: _selected,
        onOpen: _open,
      ),
    );
  }
}

/// The referrals list with plain values.
class AdminReferralsView extends StatelessWidget {
  const AdminReferralsView({
    super.key,
    required this.items,
    this.loading = false,
    this.error,
    this.onRetry,
    this.status = 'review',
    this.onStatus,
    this.selectedId,
    this.onOpen,
  });

  final List<AdminReferral> items;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String? status;
  final ValueChanged<String?>? onStatus;
  final int? selectedId;
  final ValueChanged<AdminReferral>? onOpen;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      key: const ValueKey('admin.rewards.referrals'),
      padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, AppSpace.lg),
      children: [
        _ChipRow(children: [
          for (final s in kReferralStatuses) AppChoiceChip(label: referralStatusName(s), selected: status == s, onTap: () => onStatus?.call(s)),
        ]),
        AppSpace.gapMd,
        _stateBody(
          loading: loading,
          error: error,
          onRetry: onRetry,
          empty: items.isEmpty,
          emptyState: AppEmpty(
            icon: Icons.person_add_alt_1_rounded,
            title: status == 'review' ? t('لا شيء للمراجعة', 'Nothing to review') : t('لا توجد دعوات هنا', 'No referrals here'),
            message: t('تصل هنا الدعوات التي تتجاوز الحد الشهري أو تبدو مريبة.', 'Referrals past the monthly cap or that look odd land here.'),
          ),
          list: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final r in items)
              AdminReferralTile(key: ValueKey('admin.rewards.referral.${r.id}'), referral: r, selected: r.id == selectedId, onTap: () => onOpen?.call(r)),
          ]),
        ),
      ],
    );
  }
}

class AdminReferralTile extends StatelessWidget {
  const AdminReferralTile({super.key, required this.referral, this.selected = false, this.onTap});

  final AdminReferral referral;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    final reason = referralReasonName(r.reason);
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      highlight: selected,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: referralStatusName(r.status), tone: referralStatusTone(r.status), dense: true),
          if (reason.isNotEmpty) AppStatusBadge(label: reason, tone: AppTone.warning, dense: true),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text('${r.referrer?.label ?? '—'} → ${r.referee?.label ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
        Text(
          [
            r.source == 'username' ? t('باسم المستخدم', 'By username') : t('برابط', 'By link'),
            if (r.createdAt != null) AppTime.date(r.createdAt!),
          ].join(' · '),
          style: AppType.meta(context),
        ),
      ]),
    );
  }
}

class AdminReferralDetail extends StatelessWidget {
  const AdminReferralDetail({super.key, required this.referral, this.busy = false, this.onApprove, this.onReject});

  final AdminReferral referral;
  final bool busy;
  final VoidCallback? onApprove, onReject;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    return Column(key: const ValueKey('admin.rewards.referral_detail'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Fact(t('الداعي', 'Referrer'), r.referrer?.label ?? ''),
      _Fact(t('المدعو', 'Invited'), r.referee?.label ?? ''),
      _Fact(t('الطريقة', 'How'), r.source == 'username' ? t('باسم المستخدم', 'By username') : t('برابط', 'By link')),
      _Fact(t('الحالة', 'Status'), referralStatusName(r.status)),
      _Fact(t('السبب', 'Reason'), referralReasonName(r.reason)),
      if (r.createdAt != null) _Fact(t('التسجيل', 'Signed up'), AppTime.dateTime(r.createdAt!)),
      if (r.qualifiedAt != null) _Fact(t('تأهلت', 'Qualified'), AppTime.dateTime(r.qualifiedAt!)),
      if (r.open) ...[
        AppSpace.gapMd,
        AppButton.primary(
            key: const ValueKey('admin.rewards.referral.approve'),
            label: t('اقبل', 'Approve'),
            icon: Icons.check_rounded,
            expand: true,
            busy: busy,
            onPressed: busy ? null : onApprove),
        AppSpace.gapXs,
        AppButton.danger(
            key: const ValueKey('admin.rewards.referral.reject'),
            label: t('ارفض', 'Reject'),
            icon: Icons.close_rounded,
            expand: true,
            onPressed: busy ? null : onReject),
      ],
    ]);
  }
}
