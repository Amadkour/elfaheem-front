// teacher_earnings_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Teacher Earnings & Withdrawal Screen
// — Real API calls wired to all backend endpoints
// — Fully themed via context.colors / AppTheme
// — RTL / Arabic ready (Tajawal font, Directionality.rtl)
//
// DEPENDENCIES (pubspec.yaml):
//   dio: ^5.x
//   intl: ^0.19.x
//
// BASE_URL: change _ApiService.baseUrl to your server root.
// AUTH TOKEN: call _ApiService.setToken(token) right after login.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:intl/intl.dart';

import '../../../config/app_theme.dart';
import '../../../core/api_client.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 1.  API SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class _ApiService {
  static ApiClient _api=ApiClient();
  // GET /api/v1/teacher/earnings/summary
  static Future<EarningsSummary> getSummary() async {
    final res = await _api.get('/api/v1/teacher/earnings/summary');
    return EarningsSummary.fromJson(res as Map<String, dynamic>);
  }

  // GET /api/v1/teacher/earnings?skip=&limit=&status=
  static Future<EarningsPage> getEarnings({
    int skip = 0,
    int limit = 20,
    String? status,
  }) async {
    final res = await _api.get('/api/v1/teacher/earnings', queryParams: {
      'skip': skip,
      'limit': limit,
      if (status != null) 'status': status,
    });
    return EarningsPage.fromJson(res as Map<String, dynamic>);
  }

  // GET /api/v1/teacher/withdrawals?skip=&limit=
  static Future<WithdrawalsPage> getWithdrawals(
      {int skip = 0, int limit = 20}) async {
    final res = await _api.get('/api/v1/teacher/withdrawals',
        queryParams: {'skip': skip, 'limit': limit});
    return WithdrawalsPage.fromJson(res as Map<String, dynamic>);
  }

  // POST /api/v1/teacher/withdrawals
  static Future<WithdrawalRow> requestWithdrawal({
    required double amount,
    required int savedMethodId,
    String? note,
  }) async {
    final res = await _api.post('/api/v1/teacher/withdrawals', body: {
      'amount': amount,
      'saved_method_id': savedMethodId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return WithdrawalRow.fromJson(res as Map<String, dynamic>);
  }

  // DELETE /api/v1/teacher/withdrawals/{id}
  static Future<void> cancelWithdrawal(int id) async =>
      _api.delete('/api/v1/teacher/withdrawals/$id');

  // GET saved bank accounts — adjust path to your actual endpoint
  static Future<List<BankAccount>> getBankAccounts() async {
    final res = await _api.get('/api/v1/payment-methods',
        queryParams: {'type': 'bank_account'});
    return (res as List)
        .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // POST /api/v1/payment-methods  (add bank account)
  static Future<BankAccount> addBankAccount({
    required String bankName,
    required String accountName,
    required String iban,
    String? swiftCode,
    bool isDefault = false,
  }) async {
    final res = await _api.post('/api/v1/payment-methods', body: {
      'type': 'bank_account',
      'bank_name': bankName,
      'account_name': accountName,
      'iban': iban,
      if (swiftCode != null && swiftCode.isNotEmpty) 'swift_code': swiftCode,
      'is_default': isDefault,
    });
    return BankAccount.fromJson(res.data as Map<String, dynamic>);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2.  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

class EarningsSummary {
  final double totalGross, totalPlatformFee, totalNet;
  final double pendingBalance, withdrawnTotal, pendingWithdrawal;
  final int earningsCount;

  const EarningsSummary({
    required this.totalGross,
    required this.totalPlatformFee,
    required this.totalNet,
    required this.pendingBalance,
    required this.withdrawnTotal,
    required this.pendingWithdrawal,
    required this.earningsCount,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> j) => EarningsSummary(
    totalGross: (j['total_gross'] as num).toDouble(),
    totalPlatformFee: (j['total_platform_fee'] as num).toDouble(),
    totalNet: (j['total_net'] as num).toDouble(),
    pendingBalance: (j['pending_balance'] as num).toDouble(),
    withdrawnTotal: (j['withdrawn_total'] as num).toDouble(),
    pendingWithdrawal: (j['pending_withdrawal'] as num).toDouble(),
    earningsCount: (j['earnings_count'] as num).toInt(),
  );
}

class EarningRow {
  final int id, teacherId;
  final int? courseId, withdrawalId;
  final String? courseName;
  final double grossAmount, platformFee, netAmount;
  final String status;
  final DateTime earnedAt;
  final DateTime? settledAt;

  const EarningRow({
    required this.id,
    required this.teacherId,
    this.courseId,
    this.withdrawalId,
    this.courseName,
    required this.grossAmount,
    required this.platformFee,
    required this.netAmount,
    required this.status,
    required this.earnedAt,
    this.settledAt,
  });

  factory EarningRow.fromJson(Map<String, dynamic> j) => EarningRow(
    id: j['id'] as int,
    teacherId: j['teacher_id'] as int,
    courseId: j['course_id'] as int?,
    withdrawalId: j['withdrawal_id'] as int?,
    courseName: j['course_name'] as String?,
    grossAmount: (j['gross_amount'] as num).toDouble(),
    platformFee: (j['platform_fee'] as num).toDouble(),
    netAmount: (j['net_amount'] as num).toDouble(),
    status: j['status'] as String,
    earnedAt: DateTime.parse(j['earned_at'] as String),
    settledAt: j['settled_at'] != null
        ? DateTime.parse(j['settled_at'] as String)
        : null,
  );
}

class EarningsPage {
  final List<EarningRow> items;
  final int total;
  EarningsPage({required this.items, required this.total});
  factory EarningsPage.fromJson(Map<String, dynamic> j) => EarningsPage(
    items: (j['items'] as List)
        .map((e) => EarningRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: j['total'] as int,
  );
}

class WithdrawalRow {
  final int id, teacherId;
  final int? savedMethodId;
  final double amount;
  final String status;
  final String? note, adminNote, bankReference, rejectedReason;
  final Map<String, dynamic>? bankSnapshot;
  final int earningsCount;
  final DateTime requestedAt;
  final DateTime? processedAt;

  const WithdrawalRow({
    required this.id,
    required this.teacherId,
    this.savedMethodId,
    required this.amount,
    required this.status,
    this.note,
    this.adminNote,
    this.bankReference,
    this.rejectedReason,
    this.bankSnapshot,
    this.earningsCount = 0,
    required this.requestedAt,
    this.processedAt,
  });

  factory WithdrawalRow.fromJson(Map<String, dynamic> j) => WithdrawalRow(
    id: j['id'] as int,
    teacherId: j['teacher_id'] as int,
    savedMethodId: j['saved_method_id'] as int?,
    amount: (j['amount'] as num).toDouble(),
    status: j['status'] as String,
    note: j['note'] as String?,
    adminNote: j['admin_note'] as String?,
    bankReference: j['bank_reference'] as String?,
    rejectedReason: j['rejected_reason'] as String?,
    bankSnapshot: j['bank_snapshot'] as Map<String, dynamic>?,
    earningsCount: (j['earnings_count'] as num?)?.toInt() ?? 0,
    requestedAt: DateTime.parse(j['requested_at'] as String),
    processedAt: j['processed_at'] != null
        ? DateTime.parse(j['processed_at'] as String)
        : null,
  );

  String get bankName =>
      bankSnapshot?['bank_name'] as String? ?? '—';

  String get ibanMasked {
    final raw = bankSnapshot?['iban'] as String? ?? '';
    if (raw.length < 8) return raw;
    return '${raw.substring(0, 4)} **** ${raw.substring(raw.length - 4)}';
  }
}

class WithdrawalsPage {
  final List<WithdrawalRow> items;
  final int total;
  WithdrawalsPage({required this.items, required this.total});
  factory WithdrawalsPage.fromJson(Map<String, dynamic> j) => WithdrawalsPage(
    items: (j['items'] as List)
        .map((e) => WithdrawalRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: j['total'] as int,
  );
}

class BankAccount {
  final int id;
  final String bankName, accountName, iban;
  final String? swiftCode;
  final bool isDefault;

  const BankAccount({
    required this.id,
    required this.bankName,
    required this.accountName,
    required this.iban,
    this.swiftCode,
    required this.isDefault,
  });

  factory BankAccount.fromJson(Map<String, dynamic> j) => BankAccount(
    id: j['id'] as int,
    bankName: j['bank_name'] as String? ?? '',
    accountName: j['account_name'] as String? ?? '',
    iban: j['iban'] as String? ?? '',
    swiftCode: j['swift_code'] as String?,
    isDefault: j['is_default'] as bool? ?? false,
  );

  String get ibanMasked {
    if (iban.length < 8) return iban;
    return '${iban.substring(0, 4)} **** ${iban.substring(iban.length - 4)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3.  FORMATTING HELPERS
// ═══════════════════════════════════════════════════════════════════════════

String _sar(double v) =>
    '${NumberFormat('#,##0.00', 'ar').format(v)} ر.س';

String _sarShort(double v) =>
    '${NumberFormat('#,##0', 'ar').format(v)} ر.س';

String _fmtDate(DateTime d) =>
    DateFormat('yyyy/MM/dd', 'ar').format(d.toLocal());

String _dioMsg(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    return data['detail']?.toString() ??
        data['message']?.toString() ??
        'خطأ من الخادم (${e.response?.statusCode})';
  }
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout =>
    'انتهت مهلة الاتصال. تحقق من الإنترنت.',
    DioExceptionType.connectionError => 'تعذّر الاتصال بالخادم.',
    _ => e.message ?? 'خطأ غير متوقع',
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// 4.  MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class TeacherEarningsScreen extends StatefulWidget {
  const TeacherEarningsScreen({super.key});

  @override
  State<TeacherEarningsScreen> createState() => _TeacherEarningsScreenState();
}

class _TeacherEarningsScreenState extends State<TeacherEarningsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl =
  TabController(length: 3, vsync: this);

  EarningsSummary? _summary;
  bool _summaryLoading = true;
  String? _summaryError;

  late final AnimationController _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> _fadeAnim =
  CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final s = await _ApiService.getSummary();
      if (!mounted) return;
      setState(() {
        _summary = s;
        _summaryLoading = false;
      });
      _fadeCtrl.forward(from: 0);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = _dioMsg(e);
        _summaryLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _AppBarSliver(onRefresh: _loadSummary),
            if (_summaryLoading)
              const SliverFillRemaining(child: Center(child: _Loader()))
            else if (_summaryError != null)
              SliverFillRemaining(
                  child: _ErrorPanel(
                      message: _summaryError!, onRetry: _loadSummary))
            else ...[
                SliverToBoxAdapter(
                    child: FadeTransition(
                        opacity: _fadeAnim,
                        child: _SummaryCard(summary: _summary!))),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _PrimaryButton(
                      label: 'طلب سحب جديد',
                      icon: Icons.arrow_circle_down_rounded,
                      onTap: () => _openWithdrawSheet(context),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildTabBar(c)),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _EarningsTab(onRefreshSummary: _loadSummary),
                      _WithdrawalsTab(onRefreshSummary: _loadSummary),
                      const _BankAccountsTab(),
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
    child: Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabCtrl,
        indicator: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius:
          BorderRadius.circular(AppTheme.radiusMedium - 4),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: c.textMedium,
        labelStyle: AppTheme.buttonSmall,
        unselectedLabelStyle: AppTheme.label,
        tabs: const [
          Tab(text: 'الأرباح'),
          Tab(text: 'السحوبات'),
          Tab(text: 'البنوك'),
        ],
      ),
    ),
  );

  void _openWithdrawSheet(BuildContext ctx) => showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WithdrawSheet(
      maxAmount: _summary?.pendingBalance ?? 0,
      onSuccess: () async {
        await _loadSummary();
        if (mounted) _tabCtrl.animateTo(1);
      },
    ),
  );
}

// ─── App bar ────────────────────────────────────────────────────────────────

class _AppBarSliver extends StatelessWidget {
  final VoidCallback onRefresh;
  const _AppBarSliver({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SliverAppBar(
      pinned: true,
      floating: true,
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: c.divider),
      ),
      title: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Text('أرباحي', style: c.h2),
      ]),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: c.textMedium),
          onPressed: onRefresh,
          tooltip: 'تحديث',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── Summary card ────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final EarningsSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: c.primaryShadow,
        ),
        child: Stack(children: [
          Positioned(
            top: -28, left: -28,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -20, right: -20,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الرصيد المتاح للسحب',
                  style: AppTheme.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(
                    NumberFormat('#,##0.00', 'ar').format(s.pendingBalance),
                    style: AppTheme.h1.copyWith(
                        color: Colors.white, fontSize: 36),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5, right: 8),
                    child: Text('ر.س',
                        style: AppTheme.body.copyWith(
                            color:
                            Colors.white.withValues(alpha: 0.75))),
                  ),
                ]),
                if (s.pendingWithdrawal > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.schedule_rounded,
                          color: Colors.white, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        '${_sarShort(s.pendingWithdrawal)} قيد المعالجة',
                        style: AppTheme.caption.copyWith(color: Colors.white),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),
                Divider(
                    color: Colors.white.withValues(alpha: 0.2), height: 1),
                const SizedBox(height: 18),
                Row(children: [
                  _SummaryChip(
                      label: 'إجمالي الأرباح',
                      value: _sarShort(s.totalNet)),
                  const SizedBox(width: 10),
                  _SummaryChip(
                      label: 'تم سحبه',
                      value: _sarShort(s.withdrawnTotal)),
                  const SizedBox(width: 10),
                  _SummaryChip(
                      label: 'المبيعات',
                      value: s.earningsCount.toString()),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label, value;
  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: AppTheme.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.7))),
        const SizedBox(height: 4),
        Text(value,
            style: AppTheme.bodyBold.copyWith(color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 5.  EARNINGS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _EarningsTab extends StatefulWidget {
  final VoidCallback onRefreshSummary;
  const _EarningsTab({required this.onRefreshSummary});

  @override
  State<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<_EarningsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<EarningRow> _items = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _filter = 'all';
  int _skip = 0;
  static const _limit = 20;
  final _scroll = ScrollController();

  static const _filters = [
    ('all', 'الكل'),
    ('pending', 'قيد الانتظار'),
    ('settled', 'مُحوّل'),
    ('refunded', 'مُسترد'),
  ];

  @override
  void initState() {
    super.initState();
    _loadFirst();
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 200 &&
          !_loadingMore &&
          _items.length < _total) _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
      _skip = 0;
      _items = [];
    });
    await _fetch(reset: true);
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    await _fetch(reset: false);
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _fetch({required bool reset}) async {
    try {
      final page = await _ApiService.getEarnings(
        skip: reset ? 0 : _skip,
        limit: _limit,
        status: _filter == 'all' ? null : _filter,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items = page.items;
          _skip = page.items.length;
        } else {
          _items.addAll(page.items);
          _skip += page.items.length;
        }
        _total = page.total;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioMsg(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    return Column(children: [
      const SizedBox(height: 16),
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: _filters
              .map((f) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _FilterChip(
              label: f.$2,
              selected: _filter == f.$1,
              onTap: () {
                setState(() => _filter = f.$1);
                _loadFirst();
              },
            ),
          ))
              .toList(),
        ),
      ),
      if (!_loading && _error == null) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
              alignment: Alignment.centerRight,
              child: Text('$_total سجل', style: c.caption)),
        ),
      ],
      const SizedBox(height: 8),
      Expanded(
        child: _loading
            ? const Center(child: _Loader())
            : _error != null
            ? _ErrorPanel(message: _error!, onRetry: _loadFirst)
            : _items.isEmpty
            ? _EmptyState(message: 'لا توجد أرباح حتى الآن',
            icon: Icons.payments_outlined)
            : RefreshIndicator(
          onRefresh: _loadFirst,
          color: AppTheme.primary,
          child: ListView.separated(
            controller: _scroll,
            padding:
            const EdgeInsets.fromLTRB(16, 0, 16, 32),
            itemCount:
            _items.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, __) =>
            const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i == _items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: _Loader()),
                );
              }
              return _EarningCard(e: _items[i]);
            },
          ),
        ),
      ),
    ]);
  }
}

class _EarningCard extends StatelessWidget {
  final EarningRow e;
  const _EarningCard({required this.e});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusColor = switch (e.status) {
      'settled' => AppTheme.success,
      'refunded' => AppTheme.danger,
      _ => AppTheme.accent,
    };
    final statusLabel = switch (e.status) {
      'settled' => 'مُحوّل',
      'refunded' => 'مُسترد',
      _ => 'قيد الانتظار',
    };
    final statusIcon = switch (e.status) {
      'settled' => Icons.check_circle_rounded,
      'refunded' => Icons.remove_circle_rounded,
      _ => Icons.hourglass_top_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: c.isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Icon(Icons.school_rounded, color: statusColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              e.courseName ?? 'دورة #${e.courseId ?? e.id}',
              style: c.h4,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.calendar_today_rounded,
                  size: 11, color: c.textLight),
              const SizedBox(width: 4),
              Text(_fmtDate(e.earnedAt), style: c.caption),
              const SizedBox(width: 10),
              Text('عمولة: ${_sar(e.platformFee)}',
                  style: c.caption),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('+${_sar(e.netAmount)}',
              style: AppTheme.h4.copyWith(color: AppTheme.accent2)),
          const SizedBox(height: 5),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(statusIcon, size: 10, color: statusColor),
              const SizedBox(width: 4),
              Text(statusLabel,
                  style: AppTheme.caption.copyWith(
                      color: statusColor, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 6.  WITHDRAWALS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _WithdrawalsTab extends StatefulWidget {
  final VoidCallback onRefreshSummary;
  const _WithdrawalsTab({required this.onRefreshSummary});

  @override
  State<_WithdrawalsTab> createState() => _WithdrawalsTabState();
}

class _WithdrawalsTabState extends State<_WithdrawalsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<WithdrawalRow> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _ApiService.getWithdrawals();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioMsg(e);
        _loading = false;
      });
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _ApiService.cancelWithdrawal(id);
      widget.onRefreshSummary();
      _load();
    } on DioException catch (e) {
      if (!mounted) return;
      _snack(_dioMsg(e), isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, textDirection:pageDirection),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
      ));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: _Loader());
    if (_error != null)
      return _ErrorPanel(message: _error!, onRetry: _load);
    if (_items.isEmpty)
      return _EmptyState(
          message: 'لا توجد طلبات سحب بعد',
          icon: Icons.account_balance_outlined);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _WithdrawalCard(
          w: _items[i],
          onCancel: () => _confirmCancel(context, _items[i].id),
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext ctx, int id) => showDialog(
    context: ctx,
    builder: (_) => Directionality(
      textDirection: pageDirection,
      child: AlertDialog(
        title: const Text('إلغاء طلب السحب'),
        content: const Text(
            'هل تريد إلغاء هذا الطلب؟ سيعود المبلغ إلى رصيدك المتاح.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_),
              child: const Text('تراجع')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(_);
              _cancel(id);
            },
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    ),
  );
}

class _WithdrawalCard extends StatelessWidget {
  final WithdrawalRow w;
  final VoidCallback onCancel;
  const _WithdrawalCard({required this.w, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusColor = switch (w.status) {
      'paid' => AppTheme.success,
      'rejected' => AppTheme.danger,
      'approved' => AppTheme.primaryBlue,
      _ => AppTheme.accent,
    };
    final statusLabel = switch (w.status) {
      'paid' => 'مُحوّل ✓',
      'rejected' => 'مرفوض',
      'approved' => 'موافق عليه',
      _ => 'قيد المراجعة',
    };
    final statusIcon = switch (w.status) {
      'paid' => Icons.check_circle_rounded,
      'rejected' => Icons.cancel_rounded,
      'approved' => Icons.thumb_up_alt_rounded,
      _ => Icons.hourglass_top_rounded,
    };

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: c.cardShadow,
        border: Border.all(
            color: statusColor.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius:
                BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(statusIcon, color: statusColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_sar(w.amount),
                      style: c.h3),
                  const SizedBox(height: 2),
                  Text('${w.bankName} · ${w.ibanMasked}',
                      style: c.caption),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 10, color: c.textLight),
                    const SizedBox(width: 4),
                    Text(_fmtDate(w.requestedAt), style: c.caption),
                  ]),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius:
                BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                    color: statusColor.withValues(alpha: 0.3), width: 1),
              ),
              child: Text(statusLabel,
                  style: AppTheme.caption.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        if (w.status == 'rejected' && w.rejectedReason != null)
          _InfoBanner(
              text: 'السبب: ${w.rejectedReason!}',
              color: AppTheme.danger,
              icon: Icons.error_outline_rounded),
        if (w.status == 'paid' && w.bankReference != null)
          _InfoBanner(
              text: 'المرجع البنكي: ${w.bankReference!}',
              color: AppTheme.success,
              icon: Icons.receipt_long_rounded),
        if (w.adminNote != null && w.adminNote!.isNotEmpty)
          _InfoBanner(
              text: w.adminNote!,
              color: AppTheme.accent2,
              icon: Icons.info_outline_rounded),
        if (w.status == 'pending') ...[
          Divider(height: 1, color: c.divider),
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded,
                color: AppTheme.danger, size: 16),
            label: Text('إلغاء الطلب',
                style: AppTheme.label
                    .copyWith(color: AppTheme.danger)),
          ),
        ],
      ]),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _InfoBanner(
      {required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: AppTheme.caption.copyWith(color: color))),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 7.  BANK ACCOUNTS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _BankAccountsTab extends StatefulWidget {
  const _BankAccountsTab();

  @override
  State<_BankAccountsTab> createState() => _BankAccountsTabState();
}

class _BankAccountsTabState extends State<_BankAccountsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<BankAccount> _accounts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _ApiService.getBankAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioMsg(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: _Loader());
    if (_error != null) return _ErrorPanel(message: _error!, onRetry: _load);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ..._accounts.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _BankCard(account: a),
        )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _openAddSheet(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة حساب بنكي'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(AppTheme.radiusMedium)),
          ),
        ),
      ],
    );
  }

  void _openAddSheet(BuildContext ctx) => showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddBankSheet(onAdded: (a) {
      setState(() => _accounts.insert(0, a));
    }),
  );
}

class _BankCard extends StatelessWidget {
  final BankAccount account;
  const _BankCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: account.isDefault ? c.primaryGradient : null,
        color: account.isDefault ? null : c.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: account.isDefault ? c.primaryShadow : c.cardShadow,
        border: account.isDefault
            ? null
            : Border.all(color: c.divider, width: 1),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: (account.isDefault
                ? Colors.white
                : AppTheme.primary)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Icon(Icons.account_balance_rounded,
              color: account.isDefault ? Colors.white : c.primary,
              size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(account.bankName,
                  style: account.isDefault
                      ? AppTheme.h4.copyWith(color: Colors.white)
                      : c.h4),
              if (account.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('الافتراضي',
                      style: AppTheme.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(account.accountName,
                style: account.isDefault
                    ? AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.75))
                    : c.caption),
            const SizedBox(height: 2),
            Text(account.ibanMasked,
                style: (account.isDefault
                    ? AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.7))
                    : c.caption)
                    .copyWith(letterSpacing: 1)),
          ]),
        ),
        Icon(Icons.chevron_left_rounded,
            color: account.isDefault
                ? Colors.white.withValues(alpha: 0.5)
                : c.textLight),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 8.  WITHDRAWAL BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _WithdrawSheet extends StatefulWidget {
  final double maxAmount;
  final VoidCallback onSuccess;
  const _WithdrawSheet(
      {required this.maxAmount, required this.onSuccess});

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<BankAccount> _accounts = [];
  int? _selectedId;
  bool _loadingAccounts = true;
  bool _submitting = false;
  double _sliderValue = 0;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.maxAmount;
    _amountCtrl.text = widget.maxAmount.toStringAsFixed(2);
    _ApiService.getBankAccounts().then((list) {
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _selectedId = list.isNotEmpty ? list.first.id : null;
        _loadingAccounts = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loadingAccounts = false);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setAmount(double v) {
    final clamped = v.clamp(0.0, widget.maxAmount);
    setState(() => _sliderValue = clamped);
    _amountCtrl.text = clamped.toStringAsFixed(2);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedId == null) {
      _snack('يرجى اختيار حساب بنكي', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _ApiService.requestWithdrawal(
        amount: double.parse(_amountCtrl.text),
        savedMethodId: _selectedId!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
    } on DioException catch (e) {
      if (!mounted) return;
      _snack(_dioMsg(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, textDirection: pageDirection),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
      ));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: pageDirection,
      child: Container(
        margin: EdgeInsets.only(bottom: kb),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXL)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: c.divider,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 24),
              Text('طلب سحب جديد', style: c.h2),
              const SizedBox(height: 4),
              Text('الرصيد المتاح: ${_sar(widget.maxAmount)}',
                  style: c.body),
              const SizedBox(height: 28),

              // Amount
              Align(
                  alignment: Alignment.centerRight,
                  child: Text('المبلغ (ر.س)', style: c.label)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'))
                ],
                textAlign: TextAlign.center,
                style: c.h2,
                decoration: InputDecoration(
                    suffix: Text('ر.س', style: c.body),
                    hintText: '0.00'),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  if (d == null || d <= 0) return 'أدخل مبلغاً صحيحاً';
                  if (d < 50) return 'الحد الأدنى للسحب 50 ر.س';
                  if (d > widget.maxAmount)
                    return 'يتجاوز الرصيد المتاح';
                  return null;
                },
                onChanged: (v) {
                  final d = double.tryParse(v) ?? 0;
                  if (d <= widget.maxAmount) {
                    setState(() => _sliderValue = d);
                  }
                },
              ),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbColor: AppTheme.primary,
                  activeTrackColor: AppTheme.primary,
                  inactiveTrackColor:
                  AppTheme.primary.withValues(alpha: 0.15),
                  overlayColor:
                  AppTheme.primary.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: widget.maxAmount == 0
                      ? 0
                      : _sliderValue.clamp(0, widget.maxAmount),
                  max: widget.maxAmount == 0 ? 1 : widget.maxAmount,
                  onChanged: _setAmount,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickBtn('50 ر.س', () => _setAmount(50)),
                  _QuickBtn('25%',
                          () => _setAmount(widget.maxAmount * 0.25)),
                  _QuickBtn('50%',
                          () => _setAmount(widget.maxAmount * 0.5)),
                  _QuickBtn('الكل',
                          () => _setAmount(widget.maxAmount)),
                ],
              ),
              const SizedBox(height: 24),

              // Bank picker
              Align(
                  alignment: Alignment.centerRight,
                  child: Text('حساب الاستلام', style: c.label)),
              const SizedBox(height: 10),
              if (_loadingAccounts)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: _Loader())
              else if (_accounts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: c.inputBg,
                      borderRadius:
                      BorderRadius.circular(AppTheme.radiusMedium)),
                  child: Text(
                      'لا توجد حسابات بنكية. يرجى إضافة حساب أولاً.',
                      style: c.body,
                      textAlign: TextAlign.center),
                )
              else
                ..._accounts.map((a) => GestureDetector(
                  onTap: () =>
                      setState(() => _selectedId = a.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _selectedId == a.id
                          ? AppTheme.primary.withValues(alpha: 0.07)
                          : c.cardBg,
                      borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium),
                      border: Border.all(
                        color: _selectedId == a.id
                            ? AppTheme.primary
                            : c.divider,
                        width: _selectedId == a.id ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.account_balance_rounded,
                          color: _selectedId == a.id
                              ? AppTheme.primary
                              : c.textMedium,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.bankName, style: c.h4),
                            Text(a.ibanMasked,
                                style: c.caption
                                    .copyWith(letterSpacing: 1)),
                          ],
                        ),
                      ),
                      if (_selectedId == a.id)
                        Container(
                          width: 22, height: 22,
                          decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14),
                        ),
                    ]),
                  ),
                )),

              // Note
              const SizedBox(height: 14),
              Align(
                  alignment: Alignment.centerRight,
                  child: Text('ملاحظة للإدارة (اختياري)',
                      style: c.label)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText: 'أي تعليق أو طلب خاص...'),
              ),
              const SizedBox(height: 28),

              _PrimaryButton(
                label: _submitting
                    ? 'جارٍ الإرسال...'
                    : 'إرسال طلب السحب',
                icon: Icons.send_rounded,
                onTap: _submitting ? null : _submit,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 9.  ADD BANK SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _AddBankSheet extends StatefulWidget {
  final ValueChanged<BankAccount> onAdded;
  const _AddBankSheet({required this.onAdded});

  @override
  State<_AddBankSheet> createState() => _AddBankSheetState();
}

class _AddBankSheetState extends State<_AddBankSheet> {
  final _bankCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _swiftCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isDefault = false;
  bool _saving = false;

  @override
  void dispose() {
    _bankCtrl.dispose();
    _nameCtrl.dispose();
    _ibanCtrl.dispose();
    _swiftCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final account = await _ApiService.addBankAccount(
        bankName: _bankCtrl.text.trim(),
        accountName: _nameCtrl.text.trim(),
        iban: _ibanCtrl.text.trim().replaceAll(' ', ''),
        swiftCode: _swiftCtrl.text.trim().isEmpty
            ? null
            : _swiftCtrl.text.trim(),
        isDefault: _isDefault,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded(account);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_dioMsg(e), textDirection: pageDirection),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(AppTheme.radiusMedium)),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: pageDirection,
      child: Container(
        margin: EdgeInsets.only(bottom: kb),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXL)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: c.divider,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 24),
              Text('إضافة حساب بنكي', style: c.h2),
              const SizedBox(height: 28),
              _LabelField(
                label: 'اسم البنك',
                controller: _bankCtrl,
                hint: 'مثال: البنك الأهلي السعودي',
                validator: (v) =>
                (v?.trim().isEmpty ?? true) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 14),
              _LabelField(
                label: 'اسم صاحب الحساب',
                controller: _nameCtrl,
                hint: 'الاسم الكامل',
                validator: (v) =>
                (v?.trim().isEmpty ?? true) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 14),
              _LabelField(
                label: 'رقم الآيبان (IBAN)',
                controller: _ibanCtrl,
                hint: 'SA00 0000 0000 0000 0000 00',
                validator: (v) {
                  final clean = v?.replaceAll(' ', '') ?? '';
                  if (clean.isEmpty) return 'مطلوب';
                  if (!clean.startsWith('SA') || clean.length < 22) {
                    return 'يبدأ بـ SA ولا يقل عن 22 خانة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _LabelField(
                label: 'SWIFT Code (اختياري)',
                controller: _swiftCtrl,
                hint: 'BSFASA',
                validator: null,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Checkbox(
                    value: _isDefault,
                    onChanged: (v) =>
                        setState(() => _isDefault = v ?? false)),
                const SizedBox(width: 8),
                Text('تعيين كحساب افتراضي', style: c.bodyBold),
              ]),
              const SizedBox(height: 24),
              _PrimaryButton(
                label: _saving ? 'جارٍ الحفظ...' : 'حفظ الحساب',
                icon: Icons.save_rounded,
                onTap: _saving ? null : _save,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 10. SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _PrimaryButton(
      {required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient:
            enabled ? c.primaryGradient : c.disableGradient,
            borderRadius:
            BorderRadius.circular(AppTheme.radiusMedium),
            boxShadow: enabled ? c.primaryShadow : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label,
                style: AppTheme.button.copyWith(color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : c.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border:
          Border.all(color: selected ? Colors.transparent : c.divider),
          boxShadow: selected ? c.primaryShadow : c.cardShadow,
        ),
        child: Text(label,
            style: AppTheme.label.copyWith(
                color: selected ? Colors.white : c.textMedium,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: c.divider),
        ),
        child: Text(label, style: c.label),
      ),
    );
  }
}

class _LabelField extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  const _LabelField({
    required this.label,
    required this.controller,
    required this.hint,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: c.label),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        decoration: InputDecoration(hintText: hint),
        validator: validator,
      ),
    ]);
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(
      width: 32, height: 32,
      child: CircularProgressIndicator(
          strokeWidth: 2.5, color: AppTheme.primary),
    ),
    const SizedBox(height: 10),
    Text('جارٍ التحميل...', style: context.colors.caption),
  ]);
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: c.dangerTint, shape: BoxShape.circle),
            child: const Icon(Icons.wifi_off_rounded,
                color: AppTheme.danger, size: 30),
          ),
          const SizedBox(height: 16),
          Text('تعذّر تحميل البيانات', style: c.h3),
          const SizedBox(height: 8),
          Text(message, style: c.body, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyState({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration:
          BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
          child: Icon(icon, color: AppTheme.primary, size: 34),
        ),
        const SizedBox(height: 16),
        Text(message, style: c.h3),
      ]),
    );
  }
}