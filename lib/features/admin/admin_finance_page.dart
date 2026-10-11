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
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
// ⚠ adjust this path to wherever swipe_request_card.dart lives in your project (the file the
// transfer / device-request screens already import).
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // already used by complaint_attachement_widgets.dart

import 'admin_common.dart';
import 'admin_finance_provider.dart';
import 'admin_payouts_page.dart';

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

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: t('المدفوعات والتحويلات', 'Payments & payouts')),
      child: Column(
        children: [
          const _SummaryStrip(),
          const _Tabs(),
          Expanded(
            child: IndexedStack(
              index: p.tab,
              children: const [
                _TabBody(tab: 0),
                _TabBody(tab: 1),
                _TabBody(tab: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labels / colours
// ─────────────────────────────────────────────────────────────────────────────

const _amber = Color(0xFFF59E0B);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);
const _blue = Color(0xFF3B82F6);
const _violet = Color(0xFF8B5CF6);
const _grey = Color(0xFF6B7280);

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
  'six_months' => t('٦ شهور', '6 months'),
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

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final c = context.colors;
    final pay = asMap(p.summary['payments']);
    final out = asMap(p.summary['payouts']);
    final days = p.summaryDays;

    Widget period(int d, String label) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontFamily: 'tajawal', fontSize: 12)),
        selected: days == d,
        visualDensity: VisualDensity.compact,
        selectedColor: c.primary.withValues(alpha: 0.18),
        onSelected: (_) => p.setSummaryDays(d),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('نظرة عامة', 'Overview'),
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textDark,
                  ),
                ),
              ),
              if (p.summaryLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              period(7, t('٧ أيام', '7d')),
              period(30, t('٣٠ يوم', '30d')),
              period(0, t('الكل', 'All')),
            ],
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            children: [
              _Kpi(
                icon: Icons.trending_up_rounded,
                color: _green,
                title: t('الإيرادات', 'Revenue'),
                lines: _moneyLines(pay['completed']),
                sub: '${_countOf(pay['completed'])} ${t('عملية', 'payments')}',
                onTap: () {
                  p.historyFilters
                    ..reset()
                    ..statuses = {'completed'};
                  p.setTab(1);
                  p.load(1);
                },
              ),
              _Kpi(
                icon: Icons.hourglass_top_rounded,
                color: _amber,
                title: t('بانتظار المراجعة', 'Awaiting review'),
                lines: _moneyLines(pay['pending_transfers']),
                sub: '${_countOf(pay['pending_transfers'])} ${t('تحويل', 'transfers')}',
                onTap: () => p.setTab(0),
              ),
              _Kpi(
                icon: Icons.account_balance_wallet_rounded,
                color: _red,
                title: t('طلبات السحب', 'Payout requests'),
                lines: _moneyLines(out['pending']),
                sub: '${_countOf(out['pending'])} ${t('طلب', 'requests')}',
                onTap: () => p.openPayoutsWithStatus('pending'),
              ),
              _Kpi(
                icon: Icons.payments_rounded,
                color: _blue,
                title: t('المدفوع للمعلمين', 'Paid to teachers'),
                lines: _moneyLines(out['paid']),
                sub: '${_countOf(out['paid'])} ${t('عملية', 'payouts')}',
                onTap: () => p.openPayoutsWithStatus('paid'),
              ),
              _Kpi(
                icon: Icons.undo_rounded,
                color: _violet,
                title: t('المبالغ المستردة', 'Refunded'),
                lines: _moneyLines(pay['refunded']),
                sub: '${_countOf(pay['refunded'])} ${t('عملية', 'payments')}',
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
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.color,
    required this.title,
    required this.lines,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<String> lines;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        margin: const EdgeInsetsDirectional.only(end: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textMedium,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            for (final l in lines.take(2))
              Text(
                l,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.textDark,
                ),
              ),
            Text(
              sub,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: c.textLight),
            ),
          ],
        ),
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
    final c = context.colors;

    Widget tabItem(int i, IconData icon, String label, {int badge = 0}) {
      final selected = p.tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => p.setTab(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? c.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: selected ? Colors.white : c.textMedium),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : c.textMedium,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : _red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? _red : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final out = asMap(p.summary['payouts']);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          tabItem(0, Icons.pending_actions_rounded, t('بانتظار المراجعة', 'Pending'),
              badge: p.pendingBadge),
          tabItem(1, Icons.receipt_long_rounded, t('السجل', 'History')),
          tabItem(2, Icons.account_balance_wallet_rounded, t('السحوبات', 'Payouts'),
              badge: _countOf(out['pending'])),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One tab: search · filters · list
// ─────────────────────────────────────────────────────────────────────────────

class _TabBody extends StatelessWidget {
  const _TabBody({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final l = p.list(tab);
    final c = context.colors;

    Widget content;
    if (l.loading && l.items.isEmpty) {
      content = const Center(child: AppLoadingIndicator());
    } else if (l.error != null && l.items.isEmpty) {
      content = ErrorRetry(
        message: t('تعذّر تحميل البيانات', 'Could not load the data'),
        onRetry: () => p.load(tab),
      );
    } else if (l.items.isEmpty) {
      content = RefreshIndicator(
        onRefresh: () => p.load(tab),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: EmptyState(
                tab == 0
                    ? t('لا توجد تحويلات بانتظار المراجعة', 'No transfers waiting for review')
                    : t('لا توجد نتائج مطابقة', 'Nothing matches these filters'),
                icon: tab == 0 ? Icons.task_alt_rounded : Icons.search_off_rounded,
              ),
            ),
          ],
        ),
      );
    } else {
      content = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) p.loadMore(tab);
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () => p.load(tab),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: l.items.length + 1,
            itemBuilder: (_, i) {
              if (i == l.items.length) {
                return PagedListFooter(
                  loadingMore: l.loadingMore,
                  hasMore: l.items.length < l.total,
                );
              }
              final item = l.items[i];
              if (tab == 2) return _PayoutCard(item: item);
              if (tab == 0 && item['pending_review'] == true) {
                return _SwipePending(item: item);
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PaymentCard(item: item),
              );
            },
          ),
        ),
      );
    }

    return Column(
      children: [
        _FilterBar(tab: tab),
        if (tab == 0 && l.items.isNotEmpty) const _SwipeHint(),
        if (tab == 2) const _ManagePayoutsButton(),
        // same pinned "Showing X of Y" progress as every other list
        if (l.loaded && l.items.isNotEmpty && l.total > 20)
          PagedCountCard(
            loaded: l.items.length,
            total: l.total,
            loadingMore: l.loadingMore,
            done: l.items.length >= l.total,
            icon: tab == 2
                ? Icons.account_balance_wallet_rounded
                : Icons.receipt_long_rounded,
            margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          ),
        if (l.loaded && l.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Row(
              children: [
                if (l.total <= 20)
                  Text(
                    '${l.total} ${t('نتيجة', 'results')}',
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
                  ),
                const Spacer(),
                if (l.totals.isNotEmpty)
                  Flexible(
                    child: Text(
                      '${t('الإجمالي', 'Total')}: ${l.totals.entries.map((e) => money(e.value, _cur(e.key))).join(' · ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: c.textDark,
                      ),
                    ),
                  ),
              ],
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

class _ManagePayoutsButton extends StatelessWidget {
  const _ManagePayoutsButton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () async {
          final p = context.read<AdminFinanceProvider>();
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminPayoutsPage()),
          );
          // approve / reject / mark paid happened in there
          p.loadSummary();
          p.load(2, silent: true);
        },
        icon: const Icon(Icons.edit_note_rounded, size: 18),
        label: Text(t('إدارة طلبات السحب (موافقة / رفض / دفع)',
            'Manage payout requests (approve / reject / pay)')),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Search + filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFinanceProvider>();
    final f = p.filters(tab);
    final c = context.colors;
    final filterable = tab != 0; // the pending queue only needs search + sort

    final chips = <_ActiveChip>[
      if (filterable)
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBox(
                  hint: tab == 2
                      ? t('ابحث بالمعلم أو المرجع أو الرقم', 'Search teacher, reference or #')
                      : t('ابحث بالطالب أو الكورس أو المرجع أو الرقم',
                      'Search student, course, reference or #'),
                  onChanged: (v) => p.setSearch(tab, v),
                ),
              ),
              const SizedBox(width: 8),
              // sort
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
                          Icon(
                            f.sort == s ? Icons.check_rounded : null,
                            size: 18,
                            color: c.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(_sortLabel(s), style: const TextStyle(fontFamily: 'tajawal')),
                        ],
                      ),
                    ),
                ],
              ),
              if (filterable)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => _openFilters(context, tab),
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: t('تصفية', 'Filters'),
                    ),
                    if (f.activeCount > 0)
                      PositionedDirectional(
                        top: -2,
                        end: -2,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                          child: Text(
                            '${f.activeCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
                      padding: const EdgeInsetsDirectional.only(end: 6, top: 6),
                      child: InputChip(
                        label: Text(ch.label,
                            style: const TextStyle(fontFamily: 'tajawal', fontSize: 12)),
                        onDeleted: ch.onRemove,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 6),
                    child: ActionChip(
                      label: Text(t('مسح الكل', 'Clear all'),
                          style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.danger)),
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

  void _openFilters(BuildContext context, int tab) {
    final p = context.read<AdminFinanceProvider>();
    showAdminSheet<void>(
      context,
          (ctx) => _FilterSheet(provider: p, tab: tab),
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
              fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 13.5, color: c.textDark)),
    );

    Widget chip(String text, bool selected, VoidCallback onTap, {Color? color}) => FilterChip(
      label: Text(text,
          style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 12.5,
              color: selected ? Colors.white : c.textDark)),
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
                  chip(t('٧ أيام', '7 days'), isQuick(7), () => _quick(7)),
                  chip(t('٣٠ يوم', '30 days'), isQuick(30), () => _quick(30)),
                  chip(t('٩٠ يوم', '90 days'), isQuick(90), () => _quick(90)),
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 16),
                    label: Text(
                      _d.range == null || [0, 7, 30, 90].any(isQuick)
                          ? t('مخصص…', 'Custom…')
                          : '${shortDate(_d.range!.start.toIso8601String())} → ${shortDate(_d.range!.end.toIso8601String())}',
                      style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5),
                    ),
                    onPressed: _custom,
                  ),
                  if (_d.range != null)
                    ActionChip(
                      label: Text(t('إزالة', 'Remove'),
                          style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.danger)),
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
                    final lo = double.tryParse(_min.text.trim().replaceAll(',', '.'));
                    final hi = double.tryParse(_max.text.trim().replaceAll(',', '.'));
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
                      style: const TextStyle(color: Colors.white, fontFamily: 'tajawal')),
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

class _SwipePending extends StatelessWidget {
  const _SwipePending({required this.item});

  final Map<String, dynamic> item;

  Future<bool> _approve(BuildContext context) async {
    final p = context.read<AdminFinanceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.colors;
    final sure = await confirm(
      context,
      message: t('الموافقة على هذا التحويل وتفعيل اشتراك الطالب؟',
          'Approve this transfer and activate the student\'s enrollment?'),
      confirmLabel: t('موافقة', 'Approve'),
    );
    if (!sure) return false;
    final ok = await p.approve(asInt(item['id']));
    showRequestSnack(
      messenger,
      ok ? t('تمت الموافقة وتفعيل الاشتراك', 'Approved — enrollment activated')
          : t('تعذّر تنفيذ العملية', 'Action failed'),
      color: ok ? colors.success : colors.danger,
      icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
    );
    return ok;
  }

  Future<bool> _reject(BuildContext context) async {
    final p = context.read<AdminFinanceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.colors;
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
    showRequestSnack(
      messenger,
      ok ? t('تم رفض الطلب', 'Request rejected') : t('تعذّر تنفيذ العملية', 'Action failed'),
      color: ok ? colors.warning : colors.danger,
      icon: ok ? Icons.block_rounded : Icons.error_outline_rounded,
    );
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
                      fontFamily: 'tajawal',
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: c.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusChip(_statusLabel(status), color),
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
              _MiniChip(_methodIcon(asStrOrNull(p['method'])), _methodLabel(asStrOrNull(p['method'])), c.primary),
              _MiniChip(
                p['kind'] == 'transfer' ? Icons.swap_horiz_rounded : Icons.language_rounded,
                p['kind'] == 'transfer' ? t('تحويل', 'Transfer') : t('أونلاين', 'Online'),
                _grey,
              ),
              if (asStr(p['plan']).isNotEmpty)
                _MiniChip(Icons.event_repeat_rounded, _planLabel(asStrOrNull(p['plan'])), _blue),
              _MiniChip(Icons.schedule_rounded, shortDateTime(asStrOrNull(p['created_at'])), _grey),
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
                    icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    label: Text(t('موافقة', 'Approve'),
                        style: const TextStyle(color: Colors.white, fontFamily: 'tajawal')),
                    style: ElevatedButton.styleFrom(backgroundColor: _green),
                  ),
                ),
              ],
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
                  Text(_open ? t('إخفاء التفاصيل', 'Hide details') : t('عرض التفاصيل', 'Show details'),
                      style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.primary)),
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
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
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
                    StatusChip(_statusLabel(status), _statusColor(status == 'approved' ? 'completed' : status)),
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
                        style: const TextStyle(fontFamily: 'tajawal', fontSize: 12, color: _red)),
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
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) toast(t('تعذّر فتح الملف', 'Could not open the file'), error: true);
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
                        fontFamily: 'tajawal',
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(_statusLabel(status), color),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniChip(_methodIcon(asStrOrNull(w['payout_method'])),
                    _methodLabel(asStrOrNull(w['payout_method'])), c.primary),
                if (automatic) _MiniChip(Icons.bolt_rounded, t('تلقائي', 'Automatic'), _blue),
                if (automatic && state.isNotEmpty && state != 'none')
                  _MiniChip(
                    state == 'paid' ? Icons.check_circle_rounded : (state == 'failed' ? Icons.error_rounded : Icons.sync_rounded),
                    state,
                    state == 'paid' ? _green : (state == 'failed' ? _red : _amber),
                  ),
                _MiniChip(Icons.schedule_rounded, shortDateTime(asStrOrNull(w['requested_at'])), _grey),
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

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'tajawal', fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      ],
    ),
  );
}

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
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.textLight)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'tajawal',
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
        title: Text(title, style: const TextStyle(fontFamily: 'tajawal', fontSize: 15)),
        actions: [
          IconButton(
            tooltip: t('نسخ الرابط', 'Copy link'),
            icon: const Icon(Icons.link_rounded),
            onPressed: () => _copy(url),
          ),
          IconButton(
            tooltip: t('فتح في المتصفح', 'Open in browser'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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