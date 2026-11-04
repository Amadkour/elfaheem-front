// lib/features/admin/admin_finance_provider.dart  (NEW FILE)
//
// State of the admin "Payments hub" (admin_finance_page.dart):
//   tab 0 · Pending  — manual transfers waiting for review (with the receipt image)
//   tab 1 · History  — every payment, filterable
//   tab 2 · Payouts  — teacher withdrawals, filterable
//
// API: /api/v1/admin/finance/*   (routers/admin_finance.py)
// Live: reloads itself on the silent pushes transfers_updated / payments_updated /
//       payouts_updated (see utils/live_events.dart).
library;

import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import 'admin_common.dart';

const _base = '/api/v1/admin/finance';

// ─────────────────────────────────────────────────────────────────────────────
// Filters
// ─────────────────────────────────────────────────────────────────────────────

class FinanceFilters {
  FinanceFilters({this.lockedStatuses = const {}, this.lockedKind});

  /// The Pending tab is always "pending manual transfers" — the user cannot change that.
  final Set<String> lockedStatuses;
  final String? lockedKind;

  Set<String> statuses = {};
  Set<String> methods = {};
  String kind = 'all'; // all | online | transfer          (payments)
  bool? hasAttachment; //                                    (payments: receipt image)
  bool? hasReceipt; //                                       (payouts: transfer receipt)
  DateTimeRange? range;
  double? minAmount;
  double? maxAmount;
  String search = '';
  String sort = 'newest'; // newest | oldest | amount_desc | amount_asc

  /// Number shown on the filter button (search has its own box, so it is not counted).
  int get activeCount =>
      (statuses.isNotEmpty ? 1 : 0) +
          (methods.isNotEmpty ? 1 : 0) +
          (kind != 'all' ? 1 : 0) +
          (hasAttachment != null ? 1 : 0) +
          (hasReceipt != null ? 1 : 0) +
          (range != null ? 1 : 0) +
          (minAmount != null || maxAmount != null ? 1 : 0);

  FinanceFilters copy() => FinanceFilters(
    lockedStatuses: lockedStatuses,
    lockedKind: lockedKind,
  )
    ..statuses = {...statuses}
    ..methods = {...methods}
    ..kind = kind
    ..hasAttachment = hasAttachment
    ..hasReceipt = hasReceipt
    ..range = range
    ..minAmount = minAmount
    ..maxAmount = maxAmount
    ..search = search
    ..sort = sort;

  void applyFrom(FinanceFilters o) {
    statuses = {...o.statuses};
    methods = {...o.methods};
    kind = o.kind;
    hasAttachment = o.hasAttachment;
    hasReceipt = o.hasReceipt;
    range = o.range;
    minAmount = o.minAmount;
    maxAmount = o.maxAmount;
    sort = o.sort;
  }

  void reset() {
    statuses = {};
    methods = {};
    kind = 'all';
    hasAttachment = null;
    hasReceipt = null;
    range = null;
    minAmount = null;
    maxAmount = null;
    sort = lockedStatuses.isNotEmpty ? 'oldest' : 'newest';
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> query({required bool payouts}) {
    final st = lockedStatuses.isNotEmpty ? lockedStatuses : statuses;
    final k = lockedKind ?? kind;
    return {
      if (st.isNotEmpty) 'status': st.join(','),
      if (methods.isNotEmpty) 'method': methods.join(','),
      if (!payouts && k != 'all') 'kind': k,
      if (!payouts && hasAttachment != null) 'has_attachment': hasAttachment,
      if (payouts && hasReceipt != null) 'has_receipt': hasReceipt,
      if (range != null) 'date_from': _d(range!.start),
      if (range != null) 'date_to': _d(range!.end),
      if (minAmount != null) 'min_amount': minAmount,
      if (maxAmount != null) 'max_amount': maxAmount,
      if (search.isNotEmpty) 'search': search,
      'sort': sort,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One paged list
// ─────────────────────────────────────────────────────────────────────────────

class FinanceList {
  List<Map<String, dynamic>> items = [];
  int page = 0;
  int pages = 1;
  int total = 0;
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  String? error;

  /// Why the last "load more" failed (the list below keeps what it has and shows Retry), or null.
  String? moreError;

  /// Sum of EVERY row matching the filters (not just this page), per currency.
  Map<String, double> totals = {};
  int _req = 0;

  bool get hasMore => page < pages;
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

class AdminFinanceProvider extends ChangeNotifier {
  AdminFinanceProvider({ApiClient? api}) : _api = api ?? ApiClient() {
    _liveSub = LiveEvents.instance.listen({
      LiveEvents.transfers,
      LiveEvents.payments,
      LiveEvents.payouts,
    }, (_) => _onLive());
  }

  final ApiClient _api;
  StreamSubscription<LiveEvent>? _liveSub;
  Timer? _liveDebounce;
  bool _disposed = false;

  // tab 0 / 1 / 2
  int tab = 0;

  final pending = FinanceList();
  final history = FinanceList();
  final payouts = FinanceList();

  final pendingFilters = FinanceFilters(
    lockedStatuses: {'pending'},
    lockedKind: 'transfer',
  )..sort = 'oldest'; // a queue: longest-waiting first
  final historyFilters = FinanceFilters();
  final payoutFilters = FinanceFilters();

  /// Pending transfers right now (tab badge) — not affected by the search box.
  int pendingBadge = 0;

  // ── summary ────────────────────────────────────────────────────────────────
  Map<String, dynamic> summary = {};
  bool summaryLoading = false;
  int summaryDays = 30; // 0 = all time
  List<String> methods = [];
  List<String> payoutMethods = [];

  FinanceList list(int t) => t == 0 ? pending : (t == 1 ? history : payouts);

  FinanceFilters filters(int t) =>
      t == 0 ? pendingFilters : (t == 1 ? historyFilters : payoutFilters);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _liveDebounce?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  // ── init / tabs ────────────────────────────────────────────────────────────

  Future<void> init([int initialTab = 0]) async {
    tab = initialTab;
    notifyListeners();
    await Future.wait([
      loadSummary(),
      load(0),
      if (initialTab != 0) load(initialTab),
    ]);
  }

  void setTab(int i) {
    if (i == tab) return;
    tab = i;
    notifyListeners();
    if (!list(i).loaded && !list(i).loading) load(i);
  }

  // ── summary ────────────────────────────────────────────────────────────────

  Future<void> setSummaryDays(int days) async {
    if (days == summaryDays) return;
    summaryDays = days;
    notifyListeners();
    await loadSummary();
  }

  Future<void> loadSummary() async {
    summaryLoading = true;
    notifyListeners();
    try {
      String d(DateTime x) =>
          '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      final now = DateTime.now();
      final res = asMap(
        await _api.get(
          '$_base/summary',
          queryParams: {
            if (summaryDays > 0)
              'date_from': d(now.subtract(Duration(days: summaryDays - 1))),
            if (summaryDays > 0) 'date_to': d(now),
          },
        ),
      );
      summary = res;
      methods = (res['methods'] as List? ?? []).map((e) => '$e').toList();
      payoutMethods =
          (res['payout_methods'] as List? ?? []).map((e) => '$e').toList();
    } catch (e) {
      log('finance summary ❌ $e');
    } finally {
      summaryLoading = false;
      notifyListeners();
    }
  }

  // ── lists ──────────────────────────────────────────────────────────────────

  /// [silent] = reload page 1 in the background (no spinner, list stays on screen).
  /// [more]   = append the next page.
  Future<void> load(int t, {bool silent = false, bool more = false}) async {
    final l = list(t);
    if (more) {
      if (l.loading || l.loadingMore || !l.hasMore) return;
      l.loadingMore = true;
      l.moreError = null;
    } else if (!silent) {
      l.loading = true;
      l.error = null;
    }
    notifyListeners();

    final req = ++l._req;
    try {
      final page = more ? l.page + 1 : 1;
      final res = asMap(
        await _api.get(
          t == 2 ? '$_base/payouts' : '$_base/payments',
          queryParams: {
            ...filters(t).query(payouts: t == 2),
            'page': page,
            'size': 20,
          },
        ),
      );
      if (req != l._req) return; // a newer request replaced this one
      final fresh = asMapList(res['items']);

      if (more) {
        l.items = [...l.items, ...fresh];
        l.page = asInt(res['page'], page);
      } else if (silent && l.page > 1) {
        // the user scrolled further: update / prepend, keep what is already loaded
        final ids = fresh.map((e) => e['id']).toSet();
        l.items = [...fresh, ...l.items.where((e) => !ids.contains(e['id']))];
      } else {
        l.items = fresh;
        l.page = asInt(res['page'], 1);
      }
      l.pages = asInt(res['pages'], 1);
      l.total = asInt(res['total']);
      l.totals = {
        for (final e in asMap(asMap(res['totals'])['by_currency']).entries)
          e.key: asDouble(e.value),
      };
      l.loaded = true;
      l.error = null;
      l.moreError = null;
      if (t == 0 && filters(0).search.isEmpty) pendingBadge = l.total;
    } catch (e) {
      log('finance load($t) ❌ $e');
      if (req == l._req && !silent && !more) l.error = ApiException.from(e).message;
      if (req == l._req && more) l.moreError = ApiException.from(e).message;
    } finally {
      if (req == l._req) {
        l.loading = false;
        l.loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore(int t) => load(t, more: true);

  /// Every row of tab [t] matching the current search and filters (the server allows 50 per page), for the export.
  Future<List<Map<String, dynamic>>> fetchEvery(int t, {void Function(int loaded, int total)? onProgress, bool Function()? cancelled, int maxRows = 20000}) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      if (cancelled?.call() ?? false) break;
      final res = asMap(await _api.get(
        t == 2 ? '$_base/payouts' : '$_base/payments',
        queryParams: {...filters(t).query(payouts: t == 2), 'page': page, 'size': 50},
      ));
      final items = asMapList(res['items']);
      out.addAll(items);
      final pages = asInt(res['pages'], 1);
      onProgress?.call(out.length, asInt(res['total']));
      if (items.isEmpty || page >= pages || out.length >= maxRows) break;
    }
    return out;
  }

  Future<void> setSearch(int t, String q) async {
    if (filters(t).search == q) return;
    filters(t).search = q;
    await load(t);
  }

  Future<void> applyFilters(int t, FinanceFilters draft) async {
    filters(t).applyFrom(draft);
    await load(t);
  }

  Future<void> resetFilters(int t) async {
    filters(t)
      ..reset()
      ..search = '';
    await load(t);
  }

  Future<void> setSort(int t, String sort) async {
    if (filters(t).sort == sort) return;
    filters(t).sort = sort;
    await load(t);
  }

  /// Jump to the payouts tab already filtered (used by the summary cards).
  Future<void> openPayoutsWithStatus(String status) async {
    payoutFilters
      ..reset()
      ..statuses = {status};
    tab = 2;
    notifyListeners();
    await load(2);
  }

  // ── transfer review ────────────────────────────────────────────────────────

  String? lastError;

  Future<bool> approve(int paymentId) async {
    try {
      await _api.post('$_base/transfers/$paymentId/approve', body: {});
      return true;
    } catch (e) {
      lastError = ApiException.from(e).message;
      log('approve ❌ $e');
      return false;
    }
  }

  Future<bool> reject(int paymentId, String reason) async {
    try {
      await _api.post(
        '$_base/transfers/$paymentId/reject',
        body: {'reason': reason},
      );
      return true;
    } catch (e) {
      lastError = ApiException.from(e).message;
      log('reject ❌ $e');
      return false;
    }
  }

  /// Called by the swipe card AFTER its exit animation (so the list does not jump first).
  void removePending(int paymentId) {
    final before = pending.items.length;
    pending.items.removeWhere((e) => asInt(e['id']) == paymentId);
    if (pending.items.length != before) {
      pending.total = (pending.total - 1).clamp(0, 1 << 30);
      if (filters(0).search.isEmpty) pendingBadge = pending.total;
    }
    notifyListeners();
    loadSummary();
    if (history.loaded) load(1, silent: true); // its status just changed
  }

  // ── payout receipt ─────────────────────────────────────────────────────────

  /// {url, kind: image|pdf, expires_in}
  Future<Map<String, dynamic>?> receiptLink(int withdrawalId) async {
    try {
      return asMap(await _api.get('$_base/payouts/$withdrawalId/receipt-url'));
    } catch (e) {
      log('receiptLink ❌ $e');
      return null;
    }
  }

  // ── live refresh ───────────────────────────────────────────────────────────

  void _onLive() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (_disposed) return;
      loadSummary();
      load(0, silent: true);
      if (history.loaded) load(1, silent: true);
      if (payouts.loaded) load(2, silent: true);
    });
  }
}
