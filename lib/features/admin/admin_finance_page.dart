// lib/features/admin/admin_finance_page.dart  (NEW FILE)
//
// Admin / super-admin "Payments hub":
//   • overview cards (revenue · awaiting review · payout requests · paid out · refunded)
//   • Pending  — manual transfers waiting for review: receipt image, sender details,
//                swipe (or buttons) to approve / reject
//   • History  — every payment, with the receipt image when the student uploaded one
//   • Payouts  — teacher withdrawals, with their transfer receipt
//   • professional filters on History / Payouts: status, type, receipt, method, date range,
//     amount range, sort, search (+ removable "active filter" chips and the filtered total)
//
// Opens in the admin "More" tab → Finance group.   Server: routers/admin_finance.py
// Texts use the t(ar, en) helper of the other admin pages, so no new translation keys are needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart' show ltrIsolate;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
// ⚠ adjust this path to wherever swipe_request_card.dart lives in your project (the file the
// transfer / device-request screens already import).
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // already used by complaint_attachement_widgets.dart

import 'admin_common.dart' hide StatusChip;
import 'admin_page.dart';
import 'admin_premium_widgets.dart' show AdminPalette;
import 'admin_finance_provider.dart';
import 'admin_fees_page.dart';
import 'admin_money_p8.dart';
import 'admin_payouts_page.dart';
import 'admin_table_export.dart' show adminPaymentsExport, exportFetched;
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry
// ─────────────────────────────────────────────────────────────────────────────

class AdminFinancePage extends StatelessWidget {
  const AdminFinancePage({super.key, this.initialTab = 0});

  /// 0 pending · 1 history · 2 payouts
  final int initialTab;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminFinanceProvider()..init(initialTab),
    child: const _View(),
  );
}

class _View extends StatelessWidget {
  const _View();

  /// Payment history → Excel / Word / PDF with every row matching the search and filters (50 per request).
  Future<void> _export(BuildContext context, AdminFinanceProvider p) {
    final f = p.filters(1);
    return exportFetched(
      context,
      fetch: (job) => p.fetchEvery(
        1,
        cancelled: () => job.cancelled,
        onProgress: (n, total) => job.step('${t('جلب الصفوف', 'Fetching rows')} $n / $total', total == 0 ? null : n / total),
      ),
      build: adminPaymentsExport,
      filters: {
        if (f.search.isNotEmpty) t('بحث', 'Search'): f.search,
        if (f.statuses.isNotEmpty) t('الحالة', 'Status'): f.statuses.map(_statusLabel).join(', '),
        if (f.methods.isNotEmpty) t('الطريقة', 'Method'): f.methods.map(_methodLabel).join(', '),
        if (f.kind != 'all') t('النوع', 'Type'): f.kind,
        if (f.range != null) t('الفترة', 'Period'): '${shortDate(f.range!.start.toIso8601String())} → ${shortDate(f.range!.end.toIso8601String())}',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    return AdminPage(
      title: t('المدفوعات والتحويلات', 'Payments & payouts'),
      icon: Icons.receipt_long_rounded,
      onRefresh: () {
        p.loadSummary();
        p.load(p.tab, silent: p.list(p.tab).loaded);
      },
      primaryAction: p.tab == 1
          ? AppButton.primary(
              label: t('تصدير', 'Export'),
              icon: Icons.ios_share_rounded,
              onPressed: p.history.loaded && p.history.items.isNotEmpty ? () => _export(context, p) : null,
            )
          : null,
      actions: [
        // the fee policy (Round C: it lives on the Fees page, Policy tab)
        AppIconButton(
          tooltip: t('الرسوم وسياسة الرسوم', 'Fees & fee policy'),
          icon: Icons.account_balance_wallet_outlined,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeesPage(initialTab: 1))),
        ),
        AppIconButton(
          tooltip: t('معالجة استرداد معلّق', 'Resolve a pending refund'),
          icon: Icons.sync_alt_rounded,
          onPressed: () => showRefundResolveSheet(context),
        ),
      ],
      // A tall window keeps the overview and tabs on top and lets the list fill the rest; a short one (a phone) scrolls
      // the whole page and gives the list a fixed height, so the overview never squeezes the list to nothing.
      body: LayoutBuilder(builder: (context, box) {
        final stack = IndexedStack(
          index: p.tab,
          children: const [
            _TabBody(tab: 0),
            _TabBody(tab: 1),
            _TabBody(tab: 2),
          ],
        );
        if (box.maxHeight >= 900) {
          return Column(children: [const _SummaryStrip(), const _Tabs(), Expanded(child: stack)]);
        }
        return SingleChildScrollView(
          child: Column(children: [
            const _SummaryStrip(),
            const _Tabs(),
            SizedBox(height: 740, child: stack),
          ]),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labels / colours
// ─────────────────────────────────────────────────────────────────────────────

// Status colours from the live theme (AdminPalette follows the super admin's palette).
Color get _amber => AdminPalette.orange.last;
Color get _green => AdminPalette.green.last;
Color get _red => AdminPalette.rose.last;
Color get _blue => AdminPalette.indigo.last;
Color get _violet => AdminPalette.violet.last;
Color get _grey => AdminPalette.slate.last;

Color _statusColor(String s) => switch (s) {
  'pending' => _amber,
  'completed' || 'paid' => _green,
  'failed' || 'rejected' => _red,
  'approved' => _blue,
  'refunded' => _violet,
  _ => _grey,
};

String _statusLabel(String s) => switch (s) {
  'pending' => t('قيد الانتظار', 'Pending'),
  'completed' => t('مكتمل', 'Completed'),
  'failed' => t('فشل', 'Failed'),
  'refunded' => t('مُسترد', 'Refunded'),
  'approved' => t('تمت الموافقة', 'Approved'),
  'paid' => t('تم الدفع', 'Paid'),
  'rejected' => t('مرفوض', 'Rejected'),
  'cancelled' => t('ملغي', 'Cancelled'),
  _ => s,
};

String _methodLabel(String? m) => switch (m) {
  'bank_transfer' => t('تحويل بنكي', 'Bank transfer'),
  'instapay' => t('إنستاباي', 'InstaPay'),
  'mada' => t('مدى', 'mada'),
  'visa' => 'Visa',
  'mastercard' => 'Mastercard',
  'apple_pay' => 'Apple Pay',
  'creditcard' => t('بطاقة ائتمان', 'Credit card'),
  'bank_account' => t('حساب بنكي', 'Bank account'),
  'moyasar' => t('ميسر (تلقائي)', 'Moyasar (auto)'),
  'paymob' => t('باي موب (تلقائي)', 'Paymob (auto)'),
  null || '' => t('غير محدد', 'Unknown'),
  _ => m,
};

IconData _methodIcon(String? m) => switch (m) {
  'bank_transfer' || 'bank_account' => Icons.account_balance_rounded,
  'instapay' => Icons.bolt_rounded,
  'apple_pay' => Icons.apple_rounded,
  'moyasar' || 'paymob' => Icons.sync_alt_rounded,
  _ => Icons.credit_card_rounded,
};

String _planLabel(String? p) => switch (p) {
  'monthly' => t('شهري', 'Monthly'),
  'six_months' => t('6 شهور', '6 months'),
  'yearly' => t('سنوي', 'Yearly'),
  _ => p ?? '',
};

String _sortLabel(String s) => switch (s) {
  'oldest' => t('الأقدم أولاً', 'Oldest first'),
  'amount_desc' => t('الأعلى مبلغاً', 'Highest amount'),
  'amount_asc' => t('الأقل مبلغاً', 'Lowest amount'),
  _ => t('الأحدث أولاً', 'Newest first'),
};

String _cur(dynamic c) {
  final s = asStr(c);
  return s == '—' ? '' : s;
}

List<String> _moneyLines(dynamic agg) {
  final by = asMap(asMap(agg)['by_currency']);
  if (by.isEmpty) return ['0'];
  return [
    for (final e in by.entries) money(asDouble(e.value), _cur(e.key)),
  ];
}

int _countOf(dynamic agg) => asInt(asMap(agg)['count']);

void _copy(String text) {
  Clipboard.setData(ClipboardData(text: text));
  toast(t('تم النسخ', 'Copied'));
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview cards
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip();

  /// The first currency's figure, "+N" when the period holds more than one currency.
  String _value(List<String> lines) =>
      lines.length > 1 ? '${ltrIsolate(lines.first)} ${ltrIsolate('+${lines.length - 1}')}' : ltrIsolate(lines.first);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final pay = asMap(p.summary['payments']);
    final out = asMap(p.summary['payouts']);
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    String count(dynamic agg, String ar1, String ar2, String arFew, String arMany, String en1, String en) =>
        countText(_countOf(agg), ar1: ar1, ar2: ar2, arFew: arFew, arMany: arMany, en1: en1, en: en);
    String payments(dynamic a) => count(a, 'عملية واحدة', 'عمليتان', '{n} عمليات', '{n} عملية', '1 payment', '{n} payments');

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.sm, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(t('نظرة عامة', 'Overview'), style: AppType.section(context)),
              if (p.summaryLoading)
                const SizedBox(width: AppIconSize.xs, height: AppIconSize.xs, child: CircularProgressIndicator(strokeWidth: 2)),
              AppTabs(
                index: switch (p.summaryDays) { 7 => 0, 30 => 1, _ => 2 },
                onChanged: (i) => p.setSummaryDays(const [7, 30, 0][i]),
                items: [
                  AppTabItem(t('7 أيام', '7d')),
                  AppTabItem(t('30 يومًا', '30d')),
                  AppTabItem(t('الكل', 'All')),
                ],
              ),
            ],
          ),
          AppSpace.gapXs,
          AppKpiGrid(
            maxColumns: 5,
            children: [
              AppKpiCard(
                icon: Icons.trending_up_rounded,
                label: t('الإيرادات', 'Revenue'),
                value: _value(_moneyLines(pay['completed'])),
                footnote: payments(pay['completed']),
                highlight: true,
                onTap: () {
                  p.historyFilters
                    ..reset()
                    ..statuses = {'completed'};
                  p.setTab(1);
                  p.load(1);
                },
              ),
              AppKpiCard(
                icon: Icons.hourglass_top_rounded,
                label: t('بانتظار المراجعة', 'Awaiting review'),
                value: _value(_moneyLines(pay['pending_transfers'])),
                footnote: count(pay['pending_transfers'], 'تحويل واحد', 'تحويلان', '{n} تحويلات', '{n} تحويلًا', '1 transfer', '{n} transfers'),
                onTap: () => p.setTab(0),
              ),
              AppKpiCard(
                icon: Icons.account_balance_wallet_rounded,
                label: t('طلبات السحب', 'Payout requests'),
                value: _value(_moneyLines(out['pending'])),
                footnote: count(out['pending'], 'طلب واحد', 'طلبان', '{n} طلبات', '{n} طلبًا', '1 request', '{n} requests'),
                onTap: () => p.openPayoutsWithStatus('pending'),
              ),
              AppKpiCard(
                icon: Icons.payments_rounded,
                label: t('المدفوع للمعلمين', 'Paid to teachers'),
                value: _value(_moneyLines(out['paid'])),
                footnote: payments(out['paid']),
                onTap: () => p.openPayoutsWithStatus('paid'),
              ),
              AppKpiCard(
                icon: Icons.undo_rounded,
                label: t('المبالغ المستردة', 'Refunded'),
                value: _value(_moneyLines(pay['refunded'])),
                footnote: payments(pay['refunded']),
                onTap: () {
                  p.historyFilters
                    ..reset()
                    ..statuses = {'refunded'};
                  p.setTab(1);
                  p.load(1);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final out = asMap(p.summary['payouts']);
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    int? badge(int n) => n > 0 ? n : null;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.sm, gutter, AppSpace.xs),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppTabs(
          index: p.tab,
          onChanged: p.setTab,
          items: [
            AppTabItem(t('بانتظار المراجعة', 'Pending'), icon: Icons.pending_actions_rounded, count: badge(p.pendingBadge)),
            AppTabItem(t('السجل', 'History'), icon: Icons.receipt_long_rounded),
            AppTabItem(t('السحوبات', 'Payouts'), icon: Icons.account_balance_wallet_rounded, count: badge(_countOf(out['pending']))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One tab: search · filters · list
// ─────────────────────────────────────────────────────────────────────────────

AppTone _statusTone(String s) => switch (s) {
  'pending' => AppTone.warning,
  'completed' || 'paid' => AppTone.success,
  'failed' || 'rejected' => AppTone.danger,
  'approved' => AppTone.info,
  'refunded' => AppTone.brand,
  _ => AppTone.neutral,
};

class _TabBody extends StatelessWidget {
  const _TabBody({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final l = p.list(tab);
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    if (tab == 0) return _PendingTab(l: l);
    if (tab == 2) return const _PayoutsLink();

    // History (1) and Payouts (2): a real table on wide screens, cards on phones
    final f = p.filters(tab);
    final records = tab == 1;
    final moreFailed = l.moreError != null;
    final totals = l.totals.entries.map((e) => money(e.value, _cur(e.key))).join(' · ');

    return Column(
      children: [
        _FilterBar(tab: tab, compact: true),
        if (l.loaded && l.items.isNotEmpty)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, AppSpace.xxs),
            child: Row(
              children: [
                Text(
                  countText(l.total,
                      ar1: 'نتيجة واحدة', ar2: 'نتيجتان', arFew: '{n} نتائج', arMany: '{n} نتيجة', en1: '1 result', en: '{n} results'),
                  style: AppType.meta(context),
                ),
                const Spacer(),
                if (totals.isNotEmpty)
                  Flexible(
                    child: Text(
                      '${t('الإجمالي', 'Total')}: $totals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong(context),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xxs, gutter, moreFailed ? 0 : AppSpace.md),
            child: AppDataTable<Map<String, dynamic>>(
              state: l.loading && l.items.isEmpty
                  ? AppTableState.loading
                  : (l.error != null && l.items.isEmpty)
                      ? AppTableState.error
                      : AppTableState.ready,
              errorText: l.error,
              onRetry: () => p.load(tab),
              rows: l.items,
              searchHint: records
                  ? t('ابحث بالطالب أو الكورس أو المرجع أو الرقم', 'Search student, course, reference or #')
                  : t('ابحث بالمعلم أو المرجع أو الرقم', 'Search teacher, reference or #'),
              onSearch: (v) => p.setSearch(tab, v),
              filters: [
                AppTableFilter(
                  label: t('الحالة', 'Status'),
                  value: f.statuses.length == 1 ? f.statuses.first : null,
                  options: [
                    for (final s in records ? const ['pending', 'completed', 'failed', 'refunded'] : const ['pending', 'approved', 'paid', 'rejected'])
                      (s, _statusLabel(s)),
                  ],
                  onChanged: (v) {
                    f.statuses = v == null ? {} : {v};
                    p.load(tab);
                  },
                ),
              ],
              onClearFilters: () => p.resetFilters(tab),
              toolbarTrailing: _FilterBar.toolbarButtons(context, tab),
              empty: AppEmpty(icon: Icons.search_off_rounded, title: t('لا توجد نتائج مطابقة', 'Nothing matches these filters')),
              columns: records ? _paymentColumns() : _payoutColumns(),
              onRowTap: (item) => _showDetails(context, p, tab, item),
              rowActions: (item) => [
                AppRowAction(
                  icon: Icons.open_in_full_rounded,
                  label: t('التفاصيل', 'Details'),
                  onTap: () => _showDetails(context, p, tab, item),
                ),
              ],
              onLoadMore: () => p.loadMore(tab),
              hasMore: l.items.length < l.total && !moreFailed,
              loadingMore: l.loadingMore,
            ),
          ),
        ),
        if (moreFailed)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xs, gutter, AppSpace.md),
            child: AppErrorState(
              compact: true,
              message: l.moreError,
              onRetry: () => p.loadMore(tab),
            ),
          ),
      ],
    );
  }
}

List<AppTableColumn<Map<String, dynamic>>> _paymentColumns() => [
  AppTableColumn<Map<String, dynamic>>(
    key: 'payer',
    label: t('الدافع', 'Payer'),
    primary: true,
    flex: 3,
    cell: (ctx, p) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(asStr(asMap(p['student'])['name'], '—'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(ctx)),
        Text(AppLangPick.name(asMap(p['course'])), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(ctx)),
      ],
    ),
  ),
  AppTableColumn<Map<String, dynamic>>(
    key: 'amount',
    label: t('المبلغ', 'Amount'),
    numeric: true,
    align: AppColAlignment.end,
    cell: (ctx, p) => Text(money(asDouble(p['amount']), _cur(p['currency'])), style: AppType.figure(ctx), textDirection: TextDirection.ltr),
  ),
  AppTableColumn<Map<String, dynamic>>.text(
    key: 'method',
    label: t('الطريقة', 'Method'),
    text: (p) => _methodLabel(asStrOrNull(p['method'])),
  ),
  AppTableColumn<Map<String, dynamic>>(
    key: 'status',
    label: t('الحالة', 'Status'),
    cell: (ctx, p) => AppStatusBadge(label: _statusLabel(asStr(p['status'])), tone: _statusTone(asStr(p['status'])), dense: true),
  ),
  AppTableColumn<Map<String, dynamic>>.text(
    key: 'date',
    label: t('التاريخ', 'Date'),
    text: (p) => shortDateTime(asStrOrNull(p['created_at'])),
  ),
];

List<AppTableColumn<Map<String, dynamic>>> _payoutColumns() => [
  AppTableColumn<Map<String, dynamic>>(
    key: 'teacher',
    label: t('المعلم', 'Teacher'),
    primary: true,
    flex: 3,
    cell: (ctx, w) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(asStr(asMap(w['teacher'])['name'], '—'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(ctx)),
        Text('${t('طلب سحب', 'Withdrawal')} #${w['id']}', style: AppType.meta(ctx)),
      ],
    ),
  ),
  AppTableColumn<Map<String, dynamic>>(
    key: 'amount',
    label: t('المبلغ', 'Amount'),
    numeric: true,
    align: AppColAlignment.end,
    cell: (ctx, w) => Text(money(asDouble(w['amount']), _cur(w['currency'])), style: AppType.figure(ctx), textDirection: TextDirection.ltr),
  ),
  AppTableColumn<Map<String, dynamic>>.text(
    key: 'method',
    label: t('الطريقة', 'Method'),
    text: (w) => _methodLabel(asStrOrNull(w['payout_method'])),
  ),
  AppTableColumn<Map<String, dynamic>>(
    key: 'status',
    label: t('الحالة', 'Status'),
    cell: (ctx, w) => AppStatusBadge(label: _statusLabel(asStr(w['status'])), tone: _statusTone(asStr(w['status'])), dense: true),
  ),
  AppTableColumn<Map<String, dynamic>>.text(
    key: 'requested',
    label: t('تاريخ الطلب', 'Requested'),
    text: (w) => shortDateTime(asStrOrNull(w['requested_at'])),
  ),
];

/// One payment / payout in full (the existing card: receipt, fees, refund, copyable details) in a sheet.
void _showDetails(BuildContext context, AdminFinanceProvider p, int tab, Map<String, dynamic> item) {
  showAppSheet<void>(
    context,
    (ctx) => AppSheetContent(
      title: tab == 1 ? '${t('عملية دفع', 'Payment')} #${item['id']}' : '${t('طلب سحب', 'Withdrawal')} #${item['id']}',
      children: [
        ChangeNotifierProvider.value(
          value: p,
          child: tab == 1 ? _PaymentCard(item: item) : _PayoutCard(item: item),
        ),
      ],
    ),
  );
}

/// The Pending tab: manual transfers waiting for review, swipe (or buttons) to approve / reject.
class _PendingTab extends StatelessWidget {
  const _PendingTab({required this.l});

  final FinanceList l;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    Widget content;
    if (l.loading && l.items.isEmpty) {
      content = const AppLoadingState();
    } else if (l.error != null && l.items.isEmpty) {
      content = AppErrorState(message: l.error, onRetry: () => p.load(0));
    } else if (l.items.isEmpty) {
      content = AppRefresh(
        onRefresh: () => p.load(0),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: AppEmpty(
                icon: p.filters(0).search.isEmpty ? Icons.task_alt_rounded : Icons.search_off_rounded,
                title: p.filters(0).search.isEmpty
                    ? t('لا توجد تحويلات بانتظار المراجعة', 'No transfers waiting for review')
                    : t('لا توجد نتائج مطابقة', 'Nothing matches these filters'),
              ),
            ),
          ],
        ),
      );
    } else {
      content = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300 && l.moreError == null) p.loadMore(0);
          return false;
        },
        child: AppRefresh(
          onRefresh: () => p.load(0),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xxs, gutter, AppSpace.xxl + AppSpace.xl),
            itemCount: l.items.length + 1,
            itemBuilder: (_, i) {
              if (i == l.items.length) {
                if (l.moreError != null) {
                  return AppErrorState(compact: true, message: l.moreError, onRetry: () => p.loadMore(0));
                }
                return PagedListFooter(loadingMore: l.loadingMore, hasMore: l.items.length < l.total);
              }
              final item = l.items[i];
              if (item['pending_review'] == true) return _SwipePending(item: item);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _PaymentCard(item: item),
              );
            },
          ),
        ),
      );
    }

    return Column(
      children: [
        const _FilterBar(tab: 0),
        if (l.items.isNotEmpty) const _SwipeHint(),
        if (l.loaded && l.items.isNotEmpty && l.total > 20)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, AppSpace.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${l.items.length} / ${l.total}',
                style: AppType.meta(context),
              ),
            ),
          ),
        Expanded(child: content),
      ],
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // approve = drag from the start edge towards the end edge (physically left in RTL)
    final text = rtl
        ? 'اسحب لليسار للموافقة · لليمين للرفض'
        : 'Swipe right to approve · left to reject';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.swipe_rounded, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: c.caption)),
          ],
        ),
      ),
    );
  }
}

/// The Payouts tab: payouts are handled on the Payouts page, so this is a link, not a second copy of it.
/// The pending count comes from the summary the screen already loads (no extra request).
class _PayoutsLink extends StatelessWidget {
  const _PayoutsLink();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final pending = _countOf(asMap(p.summary['payouts'])['pending']);
    return ListView(
      padding: AdminPage.bodyPadding(context),
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('طلبات السحب', 'Teacher payouts'), style: AppType.section(context)),
            AppSpace.gapXs,
            Text(t('طلبات سحب المعلمين تُدار من صفحة السحوبات.', 'Teacher payouts are handled on the Payouts page.'),
                style: AppType.body(context)),
            if (pending > 0) ...[
              AppSpace.gapXs,
              AppStatusBadge(
                label: countText(pending,
                    ar1: 'طلب واحد بانتظار المراجعة',
                    ar2: 'طلبان بانتظار المراجعة',
                    arFew: '{n} طلبات بانتظار المراجعة',
                    arMany: '{n} طلبًا بانتظار المراجعة',
                    en1: '1 request waiting',
                    en: '{n} requests waiting'),
                tone: AppTone.warning,
                dense: true,
              ),
            ],
            AppSpace.gapSm,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.secondary(
                label: t('فتح صفحة السحوبات', 'Open the Payouts page'),
                icon: Icons.account_balance_wallet_rounded,
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPayoutsPage()));
                  // approve / reject / mark paid happened in there
                  p.loadSummary();
                },
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search + filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.tab, this.compact = false});

  final int tab;

  /// History / Payouts: the table has its own search and status filter, so this only draws the active-filter chips.
  final bool compact;

  /// Sort + "More filters" for the table's toolbar.
  static Widget toolbarButtons(BuildContext context, int tab) {
    final p = context.watch<AdminFinanceProvider>();
    final f = p.filters(tab);
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: t('ترتيب', 'Sort'),
          icon: Icon(Icons.sort_rounded, color: c.textMedium),
          onSelected: (v) => p.setSort(tab, v),
          itemBuilder: (_) => [
            for (final s in const ['newest', 'oldest', 'amount_desc', 'amount_asc'])
              PopupMenuItem(
                value: s,
                child: Row(
                  children: [
                    Icon(f.sort == s ? Icons.check_rounded : null, size: AppIconSize.md, color: c.primary),
                    AppSpace.gapXs,
                    Text(_sortLabel(s), style: AppType.row(context)),
                  ],
                ),
              ),
          ],
        ),
        AppIconButton(
          icon: Icons.tune_rounded,
          tooltip: t('تصفية', 'Filters'),
          badge: f.activeCount,
          onPressed: () => showAdminSheet<void>(context, (ctx) => _FilterSheet(provider: p, tab: tab)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final f = p.filters(tab);
    final c = context.colors;
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    final filterable = tab != 0; // the pending queue only needs search + sort

    final chips = <_ActiveChip>[
      // one status is the table's own filter chip; several (picked in the sheet) are listed here
      if (filterable && (!compact || f.statuses.length > 1))
        for (final s in f.statuses)
          _ActiveChip(_statusLabel(s), () {
            f.statuses.remove(s);
            p.load(tab);
          }),
      for (final m in f.methods)
        _ActiveChip(_methodLabel(m), () {
          f.methods.remove(m);
          p.load(tab);
        }),
      if (filterable && tab == 1 && f.kind != 'all')
        _ActiveChip(f.kind == 'online' ? t('أونلاين', 'Online') : t('تحويل', 'Transfer'), () {
          f.kind = 'all';
          p.load(tab);
        }),
      if (tab == 1 && f.hasAttachment != null)
        _ActiveChip(
          f.hasAttachment! ? t('بمرفق', 'With receipt') : t('بدون مرفق', 'No receipt'),
          () {
            f.hasAttachment = null;
            p.load(tab);
          },
        ),
      if (tab == 2 && f.hasReceipt != null)
        _ActiveChip(
          f.hasReceipt! ? t('بإيصال', 'With receipt') : t('بدون إيصال', 'No receipt'),
          () {
            f.hasReceipt = null;
            p.load(tab);
          },
        ),
      if (f.range != null)
        _ActiveChip('${shortDate(f.range!.start.toIso8601String())} → ${shortDate(f.range!.end.toIso8601String())}', () {
          f.range = null;
          p.load(tab);
        }),
      if (f.minAmount != null || f.maxAmount != null)
        _ActiveChip(
          '${f.minAmount != null ? money(f.minAmount!) : '0'} – ${f.maxAmount != null ? money(f.maxAmount!) : '∞'}',
          () {
            f.minAmount = null;
            f.maxAmount = null;
            p.load(tab);
          },
        ),
    ];

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, AppSpace.xs),
      child: Column(
        children: [
          if (!compact)
            Row(
              children: [
                Expanded(
                  child: AppSearchField(
                    hint: t('ابحث بالطالب أو الكورس أو المرجع أو الرقم', 'Search student, course, reference or #'),
                    onChanged: (v) => p.setSearch(tab, v),
                  ),
                ),
                AppSpace.gapXs,
                PopupMenuButton<String>(
                  tooltip: t('ترتيب', 'Sort'),
                  icon: Icon(Icons.sort_rounded, color: c.textMedium),
                  onSelected: (v) => p.setSort(tab, v),
                  itemBuilder: (_) => [
                    for (final s in const ['newest', 'oldest', 'amount_desc', 'amount_asc'])
                      PopupMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            Icon(f.sort == s ? Icons.check_rounded : null, size: AppIconSize.md, color: c.primary),
                            AppSpace.gapXs,
                            Text(_sortLabel(s), style: AppType.row(context)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          if (chips.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final ch in chips)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpace.xs, top: AppSpace.xs),
                      child: InputChip(
                        label: Text(ch.label, style: AppType.meta(context)),
                        onDeleted: ch.onRemove,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: AppSpace.xs),
                    child: ActionChip(
                      label: Text(t('مسح الكل', 'Clear all'), style: AppType.meta(context).copyWith(color: c.danger)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => p.resetFilters(tab),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveChip {
  const _ActiveChip(this.label, this.onRemove);

  final String label;
  final VoidCallback onRemove;
}

// ── The filter bottom sheet (works on a draft; Apply commits it) ─────────────

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.provider, required this.tab});

  final AdminFinanceProvider provider;
  final int tab;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final FinanceFilters _d = widget.provider.filters(widget.tab).copy();
  late final _min = TextEditingController(text: _d.minAmount == null ? '' : money(_d.minAmount!));
  late final _max = TextEditingController(text: _d.maxAmount == null ? '' : money(_d.maxAmount!));

  bool get _payouts => widget.tab == 2;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _quick(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() => _d.range = DateTimeRange(
      start: today.subtract(Duration(days: days == 0 ? 0 : days - 1)),
      end: today,
    ));
  }

  Future<void> _custom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _d.range,
    );
    if (r != null) setState(() => _d.range = r);
  }

  void _toggle(Set<String> set, String v) =>
      setState(() => set.contains(v) ? set.remove(v) : set.add(v));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.provider;
    final statuses = _payouts
        ? const ['pending', 'approved', 'paid', 'rejected']
        : const ['pending', 'completed', 'failed', 'refunded'];
    final methods = _payouts ? p.payoutMethods : p.methods;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool isQuick(int days) =>
        _d.range != null &&
            _d.range!.end == today &&
            _d.range!.start == today.subtract(Duration(days: days == 0 ? 0 : days - 1));

    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(s,
          style: TextStyle(
              fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 13.5, color: c.textDark)),
    );

    Widget chip(String text, bool selected, VoidCallback onTap, {Color? color}) => FilterChip(
      label: Text(text,
          style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 12.5,
              color: selected ? c.onHero : c.textDark)),
      selected: selected,
      showCheckmark: false,
      selectedColor: color ?? c.primary,
      onSelected: (_) => onTap(),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(t('تصفية', 'Filters')),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(t('الحالة', 'Status')),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final s in statuses)
                    chip(_statusLabel(s), _d.statuses.contains(s), () => _toggle(_d.statuses, s),
                        color: _statusColor(s)),
                ]),
                if (!_payouts) ...[
                  label(t('النوع', 'Type')),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    chip(t('الكل', 'All'), _d.kind == 'all', () => setState(() => _d.kind = 'all')),
                    chip(t('أونلاين', 'Online'), _d.kind == 'online',
                            () => setState(() => _d.kind = 'online')),
                    chip(t('تحويل (بنكي / إنستاباي)', 'Transfer (bank / InstaPay)'),
                        _d.kind == 'transfer', () => setState(() => _d.kind = 'transfer')),
                  ]),
                  label(t('المرفقات (صورة الإيصال)', 'Attachment (receipt image)')),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    chip(t('الكل', 'Any'), _d.hasAttachment == null,
                            () => setState(() => _d.hasAttachment = null)),
                    chip(t('بمرفق', 'With receipt'), _d.hasAttachment == true,
                            () => setState(() => _d.hasAttachment = true)),
                    chip(t('بدون مرفق', 'Without'), _d.hasAttachment == false,
                            () => setState(() => _d.hasAttachment = false)),
                  ]),
                ] else ...[
                  label(t('إيصال التحويل', 'Transfer receipt')),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    chip(t('الكل', 'Any'), _d.hasReceipt == null,
                            () => setState(() => _d.hasReceipt = null)),
                    chip(t('بإيصال', 'With receipt'), _d.hasReceipt == true,
                            () => setState(() => _d.hasReceipt = true)),
                    chip(t('بدون إيصال', 'Without'), _d.hasReceipt == false,
                            () => setState(() => _d.hasReceipt = false)),
                  ]),
                ],
                if (methods.isNotEmpty) ...[
                  label(t('طريقة الدفع', 'Method')),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final m in methods)
                      chip(_methodLabel(m), _d.methods.contains(m), () => _toggle(_d.methods, m)),
                  ]),
                ],
                label(t('الفترة', 'Date range')),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  chip(t('اليوم', 'Today'), isQuick(0), () => _quick(0)),
                  chip(t('7 أيام', '7 days'), isQuick(7), () => _quick(7)),
                  chip(t('30 يومًا', '30 days'), isQuick(30), () => _quick(30)),
                  chip(t('90 يومًا', '90 days'), isQuick(90), () => _quick(90)),
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 16),
                    label: Text(
                      _d.range == null || [0, 7, 30, 90].any(isQuick)
                          ? t('مخصص…', 'Custom…')
                          : '${shortDate(_d.range!.start.toIso8601String())} → ${shortDate(_d.range!.end.toIso8601String())}',
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5),
                    ),
                    onPressed: _custom,
                  ),
                  if (_d.range != null)
                    ActionChip(
                      label: Text(t('إزالة', 'Remove'),
                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, color: c.danger)),
                      onPressed: () => setState(() => _d.range = null),
                    ),
                ]),
                label(t('المبلغ', 'Amount')),
                Row(
                  children: [
                    Expanded(
                      child: Field(
                        controller: _min,
                        label: t('من', 'Min'),
                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Field(
                        controller: _max,
                        label: t('إلى', 'Max'),
                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                label(t('الترتيب', 'Sort by')),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final s in const ['newest', 'oldest', 'amount_desc', 'amount_asc'])
                    chip(_sortLabel(s), _d.sort == s, () => setState(() => _d.sort = s)),
                ]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _d.reset();
                    _min.clear();
                    _max.clear();
                  }),
                  child: Text(t('إعادة ضبط', 'Reset')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    final lo = parseAmountLoose(_min.text);
                    final hi = parseAmountLoose(_max.text);
                    if (lo != null && hi != null && lo > hi) {
                      toast(t('الحد الأدنى أكبر من الأقصى', 'Min is greater than max'), error: true);
                      return;
                    }
                    _d.minAmount = lo;
                    _d.maxAmount = hi;
                    p.applyFilters(widget.tab, _d);
                    Navigator.pop(context);
                  },
                  child: Text(t('تطبيق', 'Apply'),
                      style: TextStyle(color: c.onHero, fontFamily: AppFonts.family)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending: swipe to approve / reject
// ─────────────────────────────────────────────────────────────────────────────

/// The server's reason for a failed approve / reject; the generic line only when there is none.
String _failText(String? reason) =>
    reason != null && reason.trim().isNotEmpty ? reason : t('تعذّر تنفيذ العملية', 'Action failed');

/// Opens a link outside the app; a bad link or a device that cannot open it is a message, never an exception.
Future<void> _openUrl(String url, {String? failText}) async {
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) toast(failText ?? t('تعذّر فتح الرابط', 'Could not open the link'), error: true);
  } catch (_) {
    toast(failText ?? t('تعذّر فتح الرابط', 'Could not open the link'), error: true);
  }
}

class _SwipePending extends StatelessWidget {
  const _SwipePending({required this.item});

  final Map<String, dynamic> item;

  Future<bool> _approve(BuildContext context) async {
    final p = context.read<AdminFinanceProvider>();
    final sure = await confirm(
      context,
      message: t('الموافقة على هذا التحويل وتفعيل اشتراك الطالب؟',
          'Approve this transfer and activate the student\'s enrollment?'),
      confirmLabel: t('موافقة', 'Approve'),
    );
    if (!sure) return false;
    final ok = await p.approve(asInt(item['id']));
    // on a failure the SERVER's reason (already approved, student gone, …), never a bare "Action failed"
    showAppNotice(
      ok ? t('تمت الموافقة وتفعيل الاشتراك', 'Approved — enrollment activated') : _failText(p.lastError),
      error: !ok,
    );
    return ok;
  }

  Future<bool> _reject(BuildContext context) async {
    final p = context.read<AdminFinanceProvider>();
    final reason = await showReasonDialog(
      context,
      title: t('سبب الرفض', 'Reason for rejection'),
      hint: t('اكتب السبب ليراه الطالب', 'Write the reason the student will see'),
      quickReasons: [
        t('الإيصال غير واضح', 'The receipt is not clear'),
        t('المبلغ غير مطابق', 'The amount does not match'),
        t('لم يصلنا التحويل', 'We did not receive the transfer'),
      ],
    );
    if (reason == null || reason.isEmpty) return false;
    final ok = await p.reject(asInt(item['id']), reason);
    showAppNotice(ok ? t('تم رفض الطلب', 'Request rejected') : _failText(p.lastError), error: !ok);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return SwipeRequestCard(
      itemId: 'transfer-${item['id']}',
      approveLabel: t('موافقة', 'Approve'),
      rejectLabel: t('رفض', 'Reject'),
      onApprove: () => _approve(context),
      onReject: () => _reject(context),
      onRemoved: () => context.read<AdminFinanceProvider>().removePending(asInt(item['id'])),
      builder: (_, ctl) => _PaymentCard(item: item, ctl: ctl),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Person avatar (photo → initial)
// ─────────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.url});

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = RequestAvatar(name: name);
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: 46,
        height: 46,
        child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment card (pending + history)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentCard extends StatefulWidget {
  const _PaymentCard({required this.item, this.ctl});

  final Map<String, dynamic> item;

  /// Present only in the Pending tab (swipe card) → shows the approve / reject buttons.
  final SwipeCardController? ctl;

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.item;
    final student = asMap(p['student']);
    final course = asMap(p['course']);
    final teacher = asMap(course['teacher']);
    final proof = p['proof'] == null ? null : asMap(p['proof']);
    final status = asStr(p['status']);
    final color = _statusColor(status);
    final currency = _cur(p['currency']);
    final courseName = AppLangPick.name(course);
    final fees = p['fees'] is Map ? asMap(p['fees']) : null;
    final refunds = paymentRefundFigures(p);
    // an older server sends no refundable_amount: then the button stays as before (any completed payment)
    final canRefund = p['refundable_amount'] == null || (refunds.refundable ?? 0) > 0.0001;

    return RequestCardShell(
      accent: color,
      busy: widget.ctl?.busy ?? false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── who · how much ──────────────────────────────────────────────
          Row(
            children: [
              _Avatar(name: asStr(student['name']), url: asStrOrNull(student['image_url'])),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asStr(student['name'], '—'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.h3.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(courseName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: c.caption),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(asDouble(p['amount']), currency),
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: c.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppStatusBadge(label: _statusLabel(status), tone: _statusTone(status), dense: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── method · type · plan · date ──────────────────────────────────
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _miniChip(_methodIcon(asStrOrNull(p['method'])), _methodLabel(asStrOrNull(p['method'])), AppTone.brand),
              _miniChip(
                p['kind'] == 'transfer' ? Icons.swap_horiz_rounded : Icons.language_rounded,
                p['kind'] == 'transfer' ? t('تحويل', 'Transfer') : t('أونلاين', 'Online'),
                AppTone.neutral,
              ),
              if (asStr(p['plan']).isNotEmpty)
                _miniChip(Icons.event_repeat_rounded, _planLabel(asStrOrNull(p['plan'])), AppTone.info),
              _miniChip(Icons.schedule_rounded, shortDateTime(asStrOrNull(p['created_at'])), AppTone.neutral),
              if (refunds.refunded > 0.0001)
                _miniChip(Icons.undo_rounded, '${t('مسترد', 'Refunded')}: ${money(refunds.refunded, currency)}', AppTone.warning),
              if (refunds.refunded > 0.0001 && refunds.refundable != null && refunds.refundable! > 0.0001)
                _miniChip(Icons.account_balance_wallet_outlined,
                    '${t('قابل للاسترداد', 'Refundable')}: ${money(refunds.refundable!, currency)}', AppTone.neutral),
            ],
          ),

          // ── the receipt the student uploaded ─────────────────────────────
          if (proof != null) ...[
            const SizedBox(height: 12),
            _ProofBlock(proof: proof, title: '${t('إيصال', 'Receipt')} #${p['id']}'),
          ],

          // ── approve / reject buttons (pending tab) ────────────────────────
          if (widget.ctl != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.ctl!.busy ? null : widget.ctl!.reject,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(t('رفض', 'Reject')),
                    style: OutlinedButton.styleFrom(foregroundColor: _red),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.ctl!.busy ? null : widget.ctl!.approve,
                    icon: Icon(Icons.check_rounded, size: 18, color: c.onHero),
                    label: Text(t('موافقة', 'Approve'),
                        style: TextStyle(color: c.onHero, fontFamily: AppFonts.family)),
                    style: ElevatedButton.styleFrom(backgroundColor: _green),
                  ),
                ),
              ],
            ),
          ],

          // ── refund (Phase 8): full or partial; manual / force are offered to the super admin only ──
          if (widget.ctl == null && status == 'completed' && canRefund && asInt(p['id']) > 0) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final fin = context.read<AdminFinanceProvider>();
                  final changed = await showRefundSheet(context,
                      paymentId: asInt(p['id']),
                      amount: p['amount'] == null ? null : asDouble(p['amount']),
                      refunded: refunds.refunded,
                      refundable: refunds.refundable,
                      currency: currency);
                  if (changed) {
                    fin.loadSummary();
                    fin.load(fin.tab, silent: true);
                  }
                },
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(t('استرداد', 'Refund')),
                style: OutlinedButton.styleFrom(foregroundColor: _violet),
              ),
            ),
          ],

          // ── details toggle ────────────────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Flexible(child: Text(_open ? t('إخفاء التفاصيل', 'Hide details') : t('عرض التفاصيل', 'Show details'),
                      style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.primary))),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18, color: c.primary),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Kv(t('رقم العملية', 'Payment #'), '${p['id']}'),
                  _Kv(t('البريد', 'E-mail'), asStr(student['gmail']), copy: true),
                  _Kv(t('الهاتف', 'Phone'), asStr(student['phone']), copy: true),
                  if (teacher.isNotEmpty) _Kv(t('المعلم', 'Teacher'), asStr(teacher['name'])),
                  _Kv(t('مرجع المعاملة', 'Transaction'), asStr(p['transaction_id']), copy: true),
                  _Kv(t('مزود الدفع', 'Provider'), asStr(p['provider'])),
                  if (p['price_paid'] != null)
                    _Kv(t('سعر الكورس', 'Course price'), money(asDouble(p['price_paid']), currency)),
                  if (fees != null)
                    for (final e in fees.entries)
                      if (e.value is num && e.key != 'total')
                        _Kv(e.key.replaceAll('_', ' '), money(asDouble(e.value), currency)),
                  _Kv(t('تاريخ الدفع', 'Paid at'), shortDateTime(asStrOrNull(p['paid_at']))),
                  if (asStrOrNull(p['refunded_at']) != null)
                    _Kv(t('تاريخ الاسترداد', 'Refunded at'), shortDateTime(asStrOrNull(p['refunded_at']))),
                  if (asStr(p['rejection_reason']).isNotEmpty)
                    _Kv(t('سبب الرفض', 'Rejection reason'), asStr(p['rejection_reason']), danger: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Course name in the app language (falls back to the other one).
class AppLangPick {
  static String name(Map<String, dynamic> course) {
    final ar = asStr(course['name_ar']);
    final en = asStr(course['name_en']);
    final first = t(ar, en);
    return first.isNotEmpty ? first : (ar.isNotEmpty ? ar : (en.isNotEmpty ? en : '—'));
  }
}

// ── The receipt image + sender details ───────────────────────────────────────

class _ProofBlock extends StatelessWidget {
  const _ProofBlock({required this.proof, required this.title});

  final Map<String, dynamic> proof;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = asStr(proof['image_url']);
    final status = asStr(proof['status']);
    final reviewer = asMap(proof['reviewed_by']);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // thumbnail → full screen, pinch to zoom
          GestureDetector(
            onTap: url.isEmpty ? null : () => _showImage(context, url, title),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url.isNotEmpty)
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) => prog == null
                            ? child
                            : const Center(child: SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        errorBuilder: (_, _, _) => Container(
                          color: c.divider,
                          child: Icon(Icons.broken_image_rounded, color: c.textLight),
                        ),
                      )
                    else
                      Container(color: c.divider, child: Icon(Icons.image_not_supported_rounded, color: c.textLight)),
                    PositionedDirectional(
                      bottom: 4,
                      end: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.heroShade.withValues(alpha: 0.54),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.zoom_in_rounded, size: 14, color: c.onHero),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Kv(t('المُرسِل', 'Sender'), asStr(proof['sender_name']), compact: true),
                _Kv(t('هاتف المُرسِل', 'Sender phone'), asStr(proof['sender_phone']), copy: true, compact: true),
                _Kv(t('مرجع التحويل', 'Reference'), asStr(proof['transfer_reference']), copy: true, compact: true),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppStatusBadge(label: _statusLabel(status), tone: _statusTone(status == 'approved' ? 'completed' : status), dense: true),
                    if (reviewer.isNotEmpty && asStr(reviewer['name']).isNotEmpty)
                      Text(
                        '${t('بواسطة', 'by')} ${reviewer['name']} · ${shortDateTime(asStrOrNull(proof['reviewed_at']))}',
                        style: c.caption.copyWith(fontSize: 11),
                      ),
                  ],
                ),
                if (asStr(proof['rejection_reason']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(asStr(proof['rejection_reason']),
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: _red)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payout card
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutCard extends StatefulWidget {
  const _PayoutCard({required this.item});

  final Map<String, dynamic> item;

  @override
  State<_PayoutCard> createState() => _PayoutCardState();
}

class _PayoutCardState extends State<_PayoutCard> {
  bool _busy = false;

  Future<void> _openReceipt() async {
    final p = context.read<AdminFinanceProvider>();
    setState(() => _busy = true);
    final link = await p.receiptLink(asInt(widget.item['id']));
    if (!mounted) return;
    setState(() => _busy = false);
    final url = asStr(link?['url']);
    if (url.isEmpty) {
      toast(t('تعذّر فتح الإيصال', 'Could not open the receipt'), error: true);
      return;
    }
    if (link!['kind'] == 'image') {
      _showImage(context, url, '${t('إيصال سحب', 'Payout receipt')} #${widget.item['id']}');
    } else {
      await _openUrl(url, failText: t('تعذّر فتح الملف', 'Could not open the file'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget.item;
    final teacher = asMap(w['teacher']);
    final status = asStr(w['status']);
    final color = _statusColor(status);
    final currency = _cur(w['currency']);
    final dest = asMap(w['destination']);
    final state = asStr(w['payout_state']);
    final automatic = w['payout_automatic'] == true;

    // the interesting bits of the account snapshot (any method), shown as small rows
    const destKeys = [
      'account_name', 'bank_name', 'iban', 'account_number', 'instapay_id', 'msisdn', 'issuer',
      'bank_code', 'swift_code'
    ];
    final destRows = <MapEntry<String, String>>[
      for (final k in destKeys)
        if (asStr(dest[k]).isNotEmpty) MapEntry(k, asStr(dest[k])),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RequestCardShell(
        accent: color,
        busy: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Avatar(name: asStr(teacher['name']), url: asStrOrNull(teacher['image_url'])),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(asStr(teacher['name'], '—'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: c.h3.copyWith(fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text('${t('طلب سحب', 'Withdrawal')} #${w['id']}', style: c.caption),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(asDouble(w['amount']), currency),
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppStatusBadge(label: _statusLabel(status), tone: _statusTone(status), dense: true),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _miniChip(_methodIcon(asStrOrNull(w['payout_method'])),
                    _methodLabel(asStrOrNull(w['payout_method'])), AppTone.brand),
                if (automatic) _miniChip(Icons.bolt_rounded, t('تلقائي', 'Automatic'), AppTone.info),
                if (automatic && state.isNotEmpty && state != 'none')
                  _miniChip(
                    state == 'paid' ? Icons.check_circle_rounded : (state == 'failed' ? Icons.error_rounded : Icons.sync_rounded),
                    state,
                    state == 'paid' ? AppTone.success : (state == 'failed' ? AppTone.danger : AppTone.warning),
                  ),
                _miniChip(Icons.schedule_rounded, shortDateTime(asStrOrNull(w['requested_at'])), AppTone.neutral),
              ],
            ),
            if (destRows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    for (final r in destRows.take(5))
                      _Kv(r.key.replaceAll('_', ' '), r.value, copy: true, compact: true),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (asStr(w['bank_reference']).isNotEmpty)
              _Kv(t('مرجع التحويل', 'Reference'), asStr(w['bank_reference']), copy: true),
            if (asStrOrNull(w['processed_at']) != null)
              _Kv(t('تمت المعالجة', 'Processed'),
                  '${shortDateTime(asStrOrNull(w['processed_at']))}${asMap(w['admin']).isNotEmpty ? ' · ${asMap(w['admin'])['name']}' : ''}'),
            if (asStr(w['note']).isNotEmpty) _Kv(t('ملاحظة المعلم', 'Teacher note'), asStr(w['note'])),
            if (asStr(w['admin_note']).isNotEmpty) _Kv(t('ملاحظة الإدارة', 'Admin note'), asStr(w['admin_note'])),
            if (asStr(w['rejected_reason']).isNotEmpty)
              _Kv(t('سبب الرفض', 'Rejection reason'), asStr(w['rejected_reason']), danger: true),
            if (asStr(w['payout_error']).isNotEmpty)
              _Kv(t('خطأ التحويل', 'Transfer error'), asStr(w['payout_error']), danger: true),
            if (w['has_receipt'] == true) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _openReceipt,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(
                    asStr(w['receipt_name']).isNotEmpty
                        ? asStr(w['receipt_name'])
                        : t('عرض الإيصال', 'View receipt'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared pieces
// ─────────────────────────────────────────────────────────────────────────────

/// A small icon + label pill (method, plan, date …): the kit's status badge.
Widget _miniChip(IconData icon, String label, AppTone tone) =>
    AppStatusBadge(label: label, tone: tone, icon: icon, dense: true);

/// "label  value" row; tap copies the value when [copy]. Hidden when the value is empty.
class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value, {this.copy = false, this.danger = false, this.compact = false});

  final String label;
  final String value;
  final bool copy;
  final bool danger;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty || value == '—') return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: copy ? () => _copy(value) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compact ? 92 : 110,
              child: Text(label,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: c.textLight)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: danger ? _red : c.textDark,
                ),
              ),
            ),
            if (copy) Icon(Icons.copy_rounded, size: 13, color: c.textLight),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen image viewer (pinch to zoom)
// ─────────────────────────────────────────────────────────────────────────────

void _showImage(BuildContext context, String url, String title) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewer(url: url, title: title),
    ),
  );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: TextStyle(fontFamily: AppFonts.family, fontSize: 15)),
        actions: [
          IconButton(
            tooltip: t('نسخ الرابط', 'Copy link'),
            icon: const Icon(Icons.link_rounded),
            onPressed: () => _copy(url),
          ),
          IconButton(
            tooltip: t('فتح في المتصفح', 'Open in browser'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => _openUrl(url),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, prog) => prog == null
                ? child
                : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}