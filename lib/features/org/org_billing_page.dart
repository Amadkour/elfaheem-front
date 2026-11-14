// lib/features/org/org_billing_page.dart
//
// C3: the org admin's READ-ONLY "Billing" page (kill switch `org.billing_view`), reached from Settings.
//   GET /api/v1/org/orgs/{id}/billing
//     {configured, plans: [{code, label_ar, label_en, price, currency}], applies_to: {students, staff, admins},
//      notice: null | "unset_yearly_default", creation_fee: {paid, amount, currency, paid_at, method} | null,
//      payments: [{id, kind, amount, currency, status, method, created_at}]}
// Only the platform's Super Admin changes what people pay (Membership fees on the organization's page); here the admin
// sees what their students and staff are charged, what the organization paid to be created and the payments so far.
//   OrgBillingData        pure model + the plain-language texts (test/org/of_f3_billing_test.dart)
//   OrgBillingView        presentational (test/ui/of_f3_layout_test.dart)
//   OrgBillingPage        the live page: loading skeleton · error with Retry · the view
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import 'org_creation_fee.dart' show money;
import 'org_providers.dart' show OrgSession;
import 'org_v3.dart' show orgCall, orgErrorText, orgParseUtc;

const orgBillingFeatureKey = 'org.billing_view';

class OrgPlan {
  const OrgPlan({required this.code, required this.labelAr, required this.labelEn, required this.price, required this.currency});
  final String code, labelAr, labelEn, currency;
  final dynamic price;
  String get label => t(labelAr.isNotEmpty ? labelAr : labelEn, labelEn.isNotEmpty ? labelEn : labelAr);
}

class OrgPayment {
  const OrgPayment({required this.id, required this.kind, required this.amount, required this.currency, required this.status, required this.method, required this.createdAt});
  final String id, kind, currency, status, method, createdAt;
  final dynamic amount;
}

class OrgBillingData {
  const OrgBillingData({
    required this.configured,
    required this.plans,
    required this.students,
    required this.staff,
    required this.admins,
    required this.notice,
    required this.feePaid,
    required this.feeAmount,
    required this.feeCurrency,
    required this.feePaidAt,
    required this.feeMethod,
    required this.hasFee,
    required this.payments,
  });

  final bool configured, hasFee, feePaid;
  final List<OrgPlan> plans;
  final dynamic students, staff, admins, feeAmount;
  final String? notice, feeCurrency, feePaidAt, feeMethod;
  final List<OrgPayment> payments;

  factory OrgBillingData.fromJson(Map<String, dynamic> j) {
    final fee = j['creation_fee'];
    final f = asMap(fee);
    final a = asMap(j['applies_to']);
    return OrgBillingData(
      configured: j['configured'] == true,
      plans: [
        for (final p in asMapList(j['plans']))
          OrgPlan(code: '${p['code']}', labelAr: '${p['label_ar'] ?? ''}', labelEn: '${p['label_en'] ?? ''}', price: p['price'], currency: '${p['currency'] ?? ''}'),
      ],
      students: a['students'],
      staff: a['staff'],
      admins: a['admins'],
      notice: j['notice'] == null ? null : '${j['notice']}',
      hasFee: fee is Map,
      feePaid: f['paid'] == true,
      feeAmount: f['amount'],
      feeCurrency: f['currency'] == null ? null : '${f['currency']}',
      feePaidAt: f['paid_at'] == null ? null : '${f['paid_at']}',
      feeMethod: f['method'] == null ? null : '${f['method']}',
      payments: [
        for (final p in asMapList(j['payments']))
          OrgPayment(
              id: '${p['id']}',
              kind: '${p['kind'] ?? ''}',
              amount: p['amount'],
              currency: '${p['currency'] ?? ''}',
              status: '${p['status'] ?? ''}',
              method: '${p['method'] ?? ''}',
              createdAt: '${p['created_at'] ?? ''}'),
      ],
    );
  }
}

/// What a group pays, in plain words. [v] is the server's value: true / "free" = free; "per_course"; "per_account" /
/// "subscription" / false = a subscription; anything else is shown as it came.
String orgPaysText(dynamic v) {
  if (v == true || v == 'free') return t('مجاني', 'Free');
  if (v == 'per_course') return t('يدفع لكل مقرر', 'Pays per course');
  if (v == false || v == 'per_account' || v == 'subscription' || v == 'paid' || v == 'charged') return t('يدفع اشتراكاً', 'Pays a subscription');
  return v == null ? '—' : '$v';
}

/// The plain-language explanation of the server's `notice`; null = nothing to say.
String? orgBillingNotice(String? notice) => switch (notice) {
      'unset_yearly_default' => t(
          'لم يضبط أحد رسوم هذه المؤسسة بعد، لذلك يُطلب من الطلاب الاشتراك السنوي للمنصة على مقررات مؤسستك. يمكن لمدير المنصة تحديد خطط وأسعار خاصة بمؤسستك أو جعلها مجانية.',
          'Nobody has set this organization\'s fees yet, so students are asked for the platform\'s yearly plan on your organization\'s own courses. The platform admin can set plans and prices just for your organization, or make it free.'),
      null || '' => null,
      _ => notice,
    };

String orgPaymentStatusText(String s) => switch (s) {
      'paid' || 'completed' || 'succeeded' || 'approved' => t('مدفوعة', 'Paid'),
      'pending' || 'review' => t('قيد المراجعة', 'Pending'),
      'failed' || 'rejected' => t('فشلت', 'Failed'),
      'refunded' => t('مستردة', 'Refunded'),
      _ => s,
    };

AppTone orgPaymentTone(String s) => switch (s) {
      'paid' || 'completed' || 'succeeded' || 'approved' => AppTone.success,
      'pending' || 'review' => AppTone.warning,
      'failed' || 'rejected' => AppTone.danger,
      _ => AppTone.neutral,
    };

String _date(String iso) {
  final d = orgParseUtc(iso);
  return d == null ? '—' : AppTime.date(d);
}

// ═════════════════════════════════════════════════════════════════════════════
//  View
// ═════════════════════════════════════════════════════════════════════════════

class OrgBillingView extends StatelessWidget {
  const OrgBillingView({super.key, required this.data});
  final OrgBillingData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notice = orgBillingNotice(data.notice);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Text(label, style: AppType.body(context))),
            AppSpace.gapXs,
            Expanded(flex: 2, child: Text(value, textAlign: TextAlign.end, style: AppType.bodyStrong(context))),
          ]),
        );
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl),
      children: [
        AppBanner(
          icon: Icons.lock_outline_rounded,
          text: t('هذه الصفحة للعرض فقط. يضبط مدير المنصة الأسعار والخطط لمؤسستك.',
              'This page is read-only. The platform admin sets the plans and prices for your organization.'),
        ),
        if (notice != null) ...[
          AppSpace.gapSm,
          AppBanner(key: const ValueKey('billing.notice'), icon: Icons.info_outline_rounded, color: c.warning, text: notice),
        ],
        AppSpace.gapMd,
        AppSection(
          title: t('من يدفع ماذا', 'Who pays what'),
          child: AppCard(child: Column(children: [
            row(t('الطلاب', 'Students'), orgPaysText(data.students)),
            row(t('هيئة التدريس والموظفون', 'Teaching & admin staff'), orgPaysText(data.staff)),
            row(t('مديرو المؤسسة', 'Organization admins'), orgPaysText(data.admins)),
          ])),
        ),
        AppSpace.gapMd,
        AppSection(
          title: t('الخطط والأسعار', 'Plans and prices'),
          child: AppCard(
            child: data.plans.isEmpty
                ? Text(
                    data.configured
                        ? t('لا توجد خطط اشتراك — الطلاب غير مطالبين باشتراك حساب.', 'No subscription plans — students are not asked for an account subscription.')
                        : t('لا توجد خطط خاصة بمؤسستك بعد.', 'No plans of your own yet.'),
                    style: AppType.body(context))
                : Column(children: [for (final p in data.plans) row(p.label, money(p.price, p.currency))]),
          ),
        ),
        AppSpace.gapMd,
        AppSection(
          title: t('رسوم إنشاء المؤسسة', 'Organization creation fee'),
          child: AppCard(
            child: !data.hasFee
                ? Text(t('لا توجد رسوم إنشاء مسجّلة لهذه المؤسسة.', 'No creation fee on record for this organization.'), style: AppType.body(context))
                : Column(children: [
                    row(t('الحالة', 'Status'), data.feePaid ? t('مدفوعة', 'Paid') : t('غير مدفوعة', 'Not paid')),
                    row(t('المبلغ', 'Amount'), money(data.feeAmount, data.feeCurrency ?? '')),
                    if (data.feePaidAt != null) row(t('تاريخ الدفع', 'Paid on'), _date(data.feePaidAt!)),
                    if (data.feeMethod != null && data.feeMethod!.isNotEmpty) row(t('طريقة الدفع', 'Method'), data.feeMethod!),
                  ]),
          ),
        ),
        AppSpace.gapMd,
        AppSection(
          title: t('المدفوعات', 'Payments'),
          child: data.payments.isEmpty
              ? AppCard(child: Text(t('لا مدفوعات بعد.', 'No payments yet.'), style: AppType.body(context)))
              : AppDataTable<OrgPayment>(
                  shrinkWrap: true,
                  rows: data.payments,
                  rowId: (p) => p.id,
                  columns: [
                    AppTableColumn<OrgPayment>.text(key: 'kind', label: t('النوع', 'Type'), primary: true, flex: 2, text: (p) => p.kind.isEmpty ? '—' : p.kind),
                    AppTableColumn<OrgPayment>.text(key: 'amount', label: t('المبلغ', 'Amount'), numeric: true, flex: 2, text: (p) => money(p.amount, p.currency)),
                    AppTableColumn<OrgPayment>(
                      key: 'status',
                      label: t('الحالة', 'Status'),
                      flex: 2,
                      cell: (_, p) => Align(alignment: AlignmentDirectional.centerStart, child: AppStatusBadge(label: orgPaymentStatusText(p.status), tone: orgPaymentTone(p.status))),
                    ),
                    AppTableColumn<OrgPayment>.text(key: 'method', label: t('الطريقة', 'Method'), flex: 2, text: (p) => p.method.isEmpty ? '—' : p.method),
                    AppTableColumn<OrgPayment>.text(key: 'date', label: t('التاريخ', 'Date'), flex: 2, text: (p) => _date(p.createdAt)),
                  ],
                ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OrgBillingPage extends StatefulWidget {
  const OrgBillingPage({super.key, this.orgId});
  final int? orgId;

  @override
  State<OrgBillingPage> createState() => _OrgBillingPageState();
}

class _OrgBillingPageState extends State<OrgBillingPage> {
  OrgBillingData? _data;
  String? _error;

  int? get _id => widget.orgId ?? context.read<OrgSession>().currentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final id = _id;
    if (id == null) return;
    setState(() => _error = null);
    final r = await orgCall(() => ApiClient().get('/api/v1/org/orgs/$id/billing'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _data = OrgBillingData.fromJson(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_data != null) {
      body = AppRefresh(onRefresh: _load, child: OrgBillingView(data: _data!));
    } else if (_error != null) {
      body = AppErrorState(message: _error, onRetry: _load);
    } else {
      body = const AppListSkeleton(items: 4);
    }
    return ParentComponent(featureKey: orgBillingFeatureKey, child: body);
  }
}
