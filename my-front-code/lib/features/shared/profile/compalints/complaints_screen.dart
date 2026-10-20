// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaints_screen.dart
// Works for both Student and Teacher roles — role-aware display.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:async';
import 'dart:developer';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../auth/auth_provider.dart';
import '../../../auth/auth_widgets.dart';
import 'complaint_attachement_widgets.dart';
import 'complaint_model.dart';
import 'complaint_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../../utils/helpers.dart' show Helpers;
// ⚠ adjust this path to wherever swipe_request_card.dart lives in your project
// (it is the file the teacher transfer / device-request screens already import).
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// ── Shared label / colour helpers (used by the new list widgets) ─────────────

Color _statusClr(ComplaintStatus s) => switch (s) {
  ComplaintStatus.open => const Color(0xFFF59E0B),
  ComplaintStatus.inProgress => const Color(0xFF3B82F6),
  ComplaintStatus.resolved => const Color(0xFF10B981),
  ComplaintStatus.closed => const Color(0xFF6B7280),
};

String _statusTxt(ComplaintStatus s) => switch (s) {
  ComplaintStatus.open => 'status_open'.tr,
  ComplaintStatus.inProgress => 'status_in_progress'.tr,
  ComplaintStatus.resolved => 'status_resolved'.tr,
  ComplaintStatus.closed => 'status_closed'.tr,
};

Color _priorityClr(ComplaintPriority p) => switch (p) {
  ComplaintPriority.urgent => const Color(0xFFEF4444),
  ComplaintPriority.high => const Color(0xFFF97316),
  ComplaintPriority.medium => const Color(0xFFF59E0B),
  ComplaintPriority.low => const Color(0xFF10B981),
};

String _priorityTxt(ComplaintPriority p) => switch (p) {
  ComplaintPriority.urgent => 'priority_urgent'.tr,
  ComplaintPriority.high => 'priority_high'.tr,
  ComplaintPriority.medium => 'priority_medium'.tr,
  ComplaintPriority.low => 'priority_low'.tr,
};

String _categoryTxt(ComplaintCategory cat) => switch (cat) {
  ComplaintCategory.technical => 'category_technical'.tr,
  ComplaintCategory.payment => 'category_payment'.tr,
  ComplaintCategory.courseContent => 'category_content'.tr,
  ComplaintCategory.teacher => 'category_teacher'.tr,
  ComplaintCategory.student => 'category_student'.tr,
  ComplaintCategory.general => 'category_general'.tr,
};

IconData _categoryIcon(ComplaintCategory cat) => switch (cat) {
  ComplaintCategory.technical => Icons.build_circle_outlined,
  ComplaintCategory.payment => Icons.payments_outlined,
  ComplaintCategory.courseContent => Icons.menu_book_outlined,
  ComplaintCategory.teacher => Icons.person_pin_outlined,
  ComplaintCategory.student => Icons.school_outlined,
  ComplaintCategory.general => Icons.support_agent_rounded,
};

String _agoTxt(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) {
    return 'ago_minutes_short'.tr.replaceAll('{n}', '${diff.inMinutes}');
  }
  if (diff.inHours < 24) {
    return 'ago_hours_short'.tr.replaceAll('{n}', '${diff.inHours}');
  }
  return '${d.day}/${d.month}/${d.year}';
}

// ── Entry point ───────────────────────────────────────────────────────────────

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  /// Status chosen by a swipe, applied to the list once the card has left.
  final Map<int, ComplaintStatus> _swiped = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ComplaintProvider>();
      p.loadComplaints(reset: true);
      p.loadStats();
    });
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
  }

  int _fillRows = -1; // rows count at the last "fill the screen" attempt

  /// Near the bottom → append the next page (provider ignores it when busy / done).
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.extentAfter < 320) {
      context.read<ComplaintProvider>().loadComplaints();
    }
  }

  /// Too few rows to scroll → keep loading until the screen is full.
  /// Runs once per row-count, so a failing request can never loop.
  void _fillViewport(ComplaintProvider p) {
    if (!p.hasMore || p.isLoadingList || p.errorMsg != null) return;
    if (p.complaints.length == _fillRows) return;
    _fillRows = p.complaints.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (_scrollCtrl.position.maxScrollExtent <= 0) p.loadComplaints();
    });
  }

  /// The search box was never connected to the provider — typing did nothing.
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final p = context.read<ComplaintProvider>();
      final q = _searchCtrl.text.trim();
      if (q != p.search) p.setSearch(q);
    });
  }

  void _clearFilters() {
    _searchCtrl.clear();
    context.read<ComplaintProvider>().clearFilters();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Staff can swipe other people's open / in-progress complaints.
  bool _canSwipe(ComplaintModel cm, bool staff, int myId) =>
      staff &&
          cm.userId != myId &&
          (cm.status == ComplaintStatus.open ||
              cm.status == ComplaintStatus.inProgress);

  Future<bool> _setStatus(
      ComplaintModel cm,
      ComplaintStatus target,
      String okMessage,
      ) async {
    final p = context.read<ComplaintProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.colors;
    final ok = await p.changeStatusSilently(cm.id, target);
    if (ok) _swiped[cm.id] = target;
    showRequestSnack(
      messenger,
      ok ? okMessage : 'error_try_again'.tr,
      color: ok ? colors.success : colors.danger,
      icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
    );
    return ok;
  }

  Future<bool> _resolve(ComplaintModel cm) => _setStatus(
    cm,
    ComplaintStatus.resolved,
    'complaint_resolved_snack'.tr,
  );

  Future<bool> _close(ComplaintModel cm) async {
    // Closing blocks further replies, so confirm first.
    final sure = await Helpers.confirmDialog(
      context,
      title: 'complaint_close_confirm'.tr,
      confirm: 'complaint_swipe_close'.tr,
    );
    if (sure != true || !mounted) return false;
    return _setStatus(cm, ComplaintStatus.closed, 'complaint_closed_snack'.tr);
  }

  void _onSwipedAway(int id) {
    final target = _swiped.remove(id);
    if (target != null && mounted) {
      context.read<ComplaintProvider>().applyStatus(id, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ComplaintProvider>();
    final auth = context.watch<MyAuthProvider>();
    final staff = !auth.isStudent;
    final myId = auth.currentUser?.id ?? 0;
    final swipeable =
        p.complaints.where((cm) => _canSwipe(cm, staff, myId)).length;

    return BasePage(key: const ValueKey('complaints'), useWebCard: true, maxWith: 1000,
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'complaints_and_support'.tr),
            ParentComponent(
              featureKey: 'complaints.stats',
              child: _OverviewStrip(
                stats: p.stats,
                selected: p.statusFilter,
                onSelect: p.setStatusFilter,
              ),
            ),
            ParentComponent(
              featureKey: 'complaints.filters',
              child: _FilterRow(
                provider: p,
                searchCtrl: _searchCtrl,
                onClear: _clearFilters,
              ),
            ),
            if (swipeable > 0) const _SwipeHint(),
            // pinned "Showing 20 of 134" — same pagination progress as every admin list
            if (p.complaints.isNotEmpty && p.total > 20)
              PagedCountCard(
                loaded: p.complaints.length,
                total: p.total,
                loadingMore: p.loadingMore,
                done: !p.hasMore,
                icon: Icons.support_agent_rounded,
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              ),
            Expanded(child: _buildList(p, staff, myId)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ComplaintProvider p, bool staff, int myId) {
    if (p.isLoadingList && p.complaints.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }

    if (p.complaints.isEmpty) {
      final filtered = p.statusFilter != null ||
          p.categoryFilter != null ||
          p.search.isNotEmpty;
      return RefreshIndicator(
        onRefresh: () => p.loadComplaints(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: _EmptyState(
                filtered: filtered,
                onClear: filtered ? _clearFilters : null,
              ),
            ),
          ],
        ),
      );
    }

    _fillViewport(p);
    return RefreshIndicator(
      onRefresh: () => p.loadComplaints(reset: true),
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
        itemCount: p.complaints.length + 1,
        itemBuilder: (_, i) {
          if (i == p.complaints.length) {
            return PagedListFooter(
              loadingMore: p.loadingMore,
              hasMore: p.hasMore,
            );
          }
          final cm = p.complaints[i];

          Widget card(bool busy) => _ComplaintCard(
            complaint: cm,
            isAdmin: staff,
            myId: myId,
            busy: busy,
            onTap: () => _openDetail(cm.id),
          );

          if (!_canSwipe(cm, staff, myId)) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: card(false),
            );
          }
          return SwipeRequestCard(
            // status in the key: after a swipe the item may stay in the list
            // (filter "all") as a different, non-swipeable card.
            itemId: 'complaint-${cm.id}-${cm.status.name}',
            approveLabel: 'complaint_swipe_resolve'.tr,
            rejectLabel: 'complaint_swipe_close'.tr,
            onApprove: () => _resolve(cm),
            onReject: () => _close(cm),
            onRemoved: () => _onSwipedAway(cm.id),
            builder: (_, ctl) => card(ctl.busy),
          );
        },
      ),
    );
  }

  void _openDetail(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<ComplaintProvider>(),
          child: ComplaintDetailScreen(complaintId: id),
        ),
      ),
    );
  }
}

// ── Overview strip (KPI cards — tap one to filter) ───────────────────────────

class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({
    required this.stats,
    required this.selected,
    required this.onSelect,
  });

  final ComplaintStats stats;
  final ComplaintStatus? selected;
  final ValueChanged<ComplaintStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String share(int n) =>
        stats.total == 0 ? '0%' : '${(n * 100 / stats.total).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t('نظرة عامة', 'Overview'),
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textDark,
                  ),
                ),
              ),
              if (stats.unreadAdmin > 0)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        size: 14,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'complaints_new_n'.tr
                            .replaceAll('{n}', '${stats.unreadAdmin}'),
                        style: const TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            children: [
              _Kpi(
                icon: Icons.inbox_rounded,
                color: c.primary,
                title: 'stat_all'.tr,
                value: stats.total,
                sub: _t('كل الشكاوى', 'All complaints'),
                selected: selected == null,
                onTap: () => onSelect(null),
              ),
              _Kpi(
                icon: Icons.mark_email_unread_rounded,
                color: _statusClr(ComplaintStatus.open),
                title: _statusTxt(ComplaintStatus.open),
                value: stats.open,
                sub: share(stats.open),
                selected: selected == ComplaintStatus.open,
                onTap: () => onSelect(ComplaintStatus.open),
              ),
              _Kpi(
                icon: Icons.autorenew_rounded,
                color: _statusClr(ComplaintStatus.inProgress),
                title: _statusTxt(ComplaintStatus.inProgress),
                value: stats.inProgress,
                sub: share(stats.inProgress),
                selected: selected == ComplaintStatus.inProgress,
                onTap: () => onSelect(ComplaintStatus.inProgress),
              ),
              _Kpi(
                icon: Icons.check_circle_rounded,
                color: _statusClr(ComplaintStatus.resolved),
                title: _statusTxt(ComplaintStatus.resolved),
                value: stats.resolved,
                sub: share(stats.resolved),
                selected: selected == ComplaintStatus.resolved,
                onTap: () => onSelect(ComplaintStatus.resolved),
              ),
              _Kpi(
                icon: Icons.lock_rounded,
                color: _statusClr(ComplaintStatus.closed),
                title: _statusTxt(ComplaintStatus.closed),
                value: stats.closed,
                sub: share(stats.closed),
                selected: selected == ComplaintStatus.closed,
                onTap: () => onSelect(ComplaintStatus.closed),
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
    required this.value,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final int value;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 150,
        margin: const EdgeInsetsDirectional.only(end: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.25),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      fontFamily: 'bahji',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textMedium,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.toDouble()),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(
                '${v.round()}',
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: c.textDark,
                ),
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 11,
                color: c.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Swipe hint ────────────────────────────────────────────────────────────────

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Resolve = drag from start towards end (physically left in RTL).
    final text = rtl
        ? 'complaint_swipe_hint_left'.tr
        : 'complaint_swipe_hint_right'.tr;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.swipe_rounded, color: c.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: c.caption)),
          ],
        ),
      ),
    );
  }
}

// ── Filter bar (search · filter button · status pill · active chips) ─────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.provider,
    required this.searchCtrl,
    required this.onClear,
  });

  final ComplaintProvider provider;
  final TextEditingController searchCtrl;
  final VoidCallback onClear;

  void _openCategorySheet(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _t('تصفية حسب النوع', 'Filter by category'),
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.textDark,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'stat_all'.tr,
                    selected: provider.categoryFilter == null,
                    onTap: () {
                      provider.setCategoryFilter(null);
                      Navigator.pop(ctx);
                    },
                  ),
                  for (final cat in ComplaintCategory.values)
                    _FilterChip(
                      label: _categoryTxt(cat),
                      selected: provider.categoryFilter == cat,
                      onTap: () {
                        provider.setCategoryFilter(cat);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stats = provider.stats;
    final active = provider.statusFilter != null ||
        provider.categoryFilter != null ||
        provider.search.isNotEmpty;

    Widget seg(
        String label,
        bool selected,
        Color color,
        VoidCallback onTap, {
          int badge = 0,
        }) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : c.textMedium,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? color : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

    final category = provider.categoryFilter;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: IconTextField(
                  controller: searchCtrl,
                  label: 'search_complaints_hint'.tr,
                  icon: Icons.search_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _openCategorySheet(context),
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: _t('تصفية', 'Filters'),
                  ),
                  if (category != null)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '1',
                          style: TextStyle(
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
          const SizedBox(height: 10),
          // status — segmented pill (same look as the finance tabs)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  seg('stat_all'.tr, provider.statusFilter == null, c.primary,
                          () => provider.setStatusFilter(null)),
                  for (final s in ComplaintStatus.values)
                    seg(
                      _statusTxt(s),
                      provider.statusFilter == s,
                      _statusClr(s),
                          () => provider.setStatusFilter(s),
                      // numbers that need attention
                      badge: s == ComplaintStatus.open
                          ? stats.open
                          : s == ComplaintStatus.inProgress
                          ? stats.inProgress
                          : 0,
                    ),
                ],
              ),
            ),
          ),
          // removable active filters
          if (active) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (category != null)
                  _ActiveChip(
                    _categoryTxt(category),
                        () => provider.setCategoryFilter(null),
                  ),
                if (provider.search.isNotEmpty)
                  _ActiveChip('“${provider.search}”', () {
                    searchCtrl.clear();
                    provider.setSearch('');
                  }),
                TextButton.icon(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: c.danger,
                  ),
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: Text('clear_btn'.tr),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Removable chip for an active filter.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip(this.label, this.onRemove);

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 6, 5),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 16, color: c.primary),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  }) : color = null;

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = color ?? c.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : c.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? accent : c.textMedium,
          ),
        ),
      ),
    );
  }
}

// ── Owner avatar (photo, falls back to the initial) ──────────────────────────

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({required this.name, this.imageUrl, this.size = 44});

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(
      width: size,
      height: size,
      child: FittedBox(child: RequestAvatar(name: name)),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

// ── Complaint Card (finance-style: who · status, text, chips, counters) ─────

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.complaint,
    required this.isAdmin,
    required this.myId,
    required this.onTap,
    this.busy = false,
  });

  final ComplaintModel complaint;
  final bool isAdmin; // staff view → show who sent it
  final int myId;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cm = complaint;
    final mine = cm.userId == myId;
    final unread = (isAdmin && !mine) ? !cm.isReadByAdmin : !cm.isReadByUser;
    final statusColor = _statusClr(cm.status);

    return GestureDetector(
      onTap: onTap,
      child: RequestCardShell(
        accent: _priorityClr(cm.priority),
        busy: busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── who · status ────────────────────────────────────────────
            Row(
              children: [
                if (isAdmin)
                  _OwnerAvatar(name: cm.userName, imageUrl: cm.userImage)
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _categoryIcon(cm.category),
                      color: c.primary,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAdmin
                            ? (mine ? 'you_label'.tr : cm.userName)
                            : _categoryTxt(cm.category),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.h3.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cm.courseTitle ??
                            (isAdmin ? _categoryTxt(cm.category) : _agoTxt(cm.updatedAt)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.caption,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MetaChip(
                      icon: Icons.circle,
                      label: _statusTxt(cm.status),
                      color: statusColor,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _agoTxt(cm.updatedAt),
                      style: c.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── title + unread dot ──────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unread)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsetsDirectional.only(end: 8, top: 5),
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    cm.title,
                    style: c.h3.copyWith(
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              cm.description,
              style: c.caption.copyWith(height: 1.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // ── priority · category · counters ──────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MetaChip(
                  icon: Icons.flag_rounded,
                  label: _priorityTxt(cm.priority),
                  color: _priorityClr(cm.priority),
                ),
                if (isAdmin || cm.courseTitle != null)
                  _MetaChip(
                    icon: _categoryIcon(cm.category),
                    label: _categoryTxt(cm.category),
                    color: c.primary,
                  ),
                if (cm.attachments.isNotEmpty)
                  _MetaChip(
                    icon: Icons.attach_file_rounded,
                    label: '${cm.attachments.length}',
                    color: c.textMedium,
                  ),
                if (cm.suggestedSolution != null)
                  _MetaChip(
                    icon: Icons.lightbulb_outline_rounded,
                    label: 'suggested_solution_label'.tr,
                    color: const Color(0xFF059669),
                  ),
                if (cm.repliesCount > 0)
                  _MetaChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '${cm.repliesCount}',
                    color: c.textMedium,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.filtered = false, this.onClear});

  /// Filters / search are active → "nothing matches" instead of "no complaints yet".
  final bool filtered;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: c.primaryShadow,
            ),
            child: Icon(
              filtered ? Icons.search_off_rounded : Icons.support_agent_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            filtered ? 'admin_nothing_here_yet'.tr : 'no_complaints_yet'.tr,
            style: c.h2.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (!filtered)
            Text(
              'complaints_empty_hint'.tr,
              style: c.caption.copyWith(color: c.textLight),
            ),
          if (filtered && onClear != null)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: Text('clear_btn'.tr),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Complaint Detail Screen
// ══════════════════════════════════════════════════════════════════════════════

class ComplaintDetailScreen extends StatefulWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final int complaintId;

  @override
  State<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<ComplaintDetailScreen> {
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComplaintProvider>().loadDetail(widget.complaintId);
    });
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    // Clear any staged reply images if user navigates away
    // context.read<ComplaintProvider>().clearReplyImages();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final msg = _replyCtrl.text.trim();
    final p = context.read<ComplaintProvider>();
    if (msg.isEmpty && p.pendingReplyAttachments.isEmpty) return;
    _replyCtrl.clear();

    final sent = await p.addReply(complaintId: widget.complaintId, message: msg);
    // Failed (network / upload) → give the typed text back instead of losing it.
    if (sent == null && mounted) _replyCtrl.text = msg;
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ComplaintProvider>();
    final c = context.colors;
    final auth = context.read<MyAuthProvider>();
    final complaint = p.selected;
    log(' persona is===========> ${auth.isStudent}');
    return BasePage(child: SafeArea(
      child: Column(
        children: [
          ScreenAppBar(title: 'complaint_details_title'.tr),
          if (p.isLoadingDetail)
            const Expanded(
              child: Center(child: AppLoadingIndicator()),
            )
          else if (complaint == null)
            Expanded(child: Center(child: Text('complaint_not_found'.tr)))
          else ...[
              Expanded(
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    // ── Info card ──────────────────────────────────────────
                    ParentComponent(featureKey: 'complaint_detail.info', child: _InfoCard(
                      complaint: complaint,
                      isAdmin: !auth.isStudent,
                      provider: p,
                    )),
                    const SizedBox(height: 16),
                    // ── Replies ────────────────────────────────────────────
                    if (complaint.replies.isNotEmpty) ParentComponent(featureKey: 'complaint_detail.replies', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('replies_label'.tr, style: c.h3),
                      ),
                      ...complaint.replies.map(
                            (r) => _ReplyBubble(
                          reply: r,
                          myId: auth.currentUser?.id ?? 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ])),
                  ],
                ),
              ),
              // ── Reply input ──────────────────────────────────────────────
              if (complaint.status != ComplaintStatus.closed)
                ParentComponent(featureKey: 'complaint_detail.reply_input', child: _ReplyInput(
                  controller: _replyCtrl,
                  isSending: p.isSending,
                  pendingAttachments: p.pendingReplyAttachments,
                  onSend: _sendReply,
                  onPickGallery: () => p.pickReplyImage(),
                  onPickCamera: () => p.pickReplyImageFromCamera(),
                  onPickFile: () => p.pickReplyFile(),
                  onRemoveImage: (i) => p.removeReplyImage(i),
                )),
            ],
        ],
      ),
    ),
    );
  }
}

// ── Info Card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.complaint,
    required this.isAdmin,
    required this.provider,
  });

  final ComplaintModel complaint;
  final bool isAdmin;
  final ComplaintProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusClr = _statusColor(complaint.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Who sent it (staff only)
          if (isAdmin) ...[
            Row(
              children: [
                _OwnerAvatar(
                  name: complaint.userName,
                  imageUrl: complaint.userImage,
                  size: 42,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        complaint.userName,
                        style: c.h3.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${complaint.createdAt.day}/${complaint.createdAt.month}/${complaint.createdAt.year}'
                            '  ${complaint.createdAt.hour.toString().padLeft(2, '0')}:${complaint.createdAt.minute.toString().padLeft(2, '0')}',
                        style: c.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: c.divider),
            ),
          ],
          // Title + status
          Row(
            children: [
              Expanded(
                child: Text(
                  complaint.title,
                  style: c.h2.copyWith(fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusClr.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(complaint.status),
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusClr,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Meta
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.label_outline_rounded,
                label: _categoryLabel(complaint.category),
                color: c.primary,
              ),
              _MetaChip(
                icon: Icons.flag_outlined,
                label: _priorityLabel(complaint.priority),
                color: _priorityColor(complaint.priority),
              ),
              if (complaint.courseTitle != null)
                _MetaChip(
                  icon: Icons.book_outlined,
                  label: complaint.courseTitle!,
                  color: c.accent,
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Description
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              complaint.description,
              style: c.body.copyWith(height: 1.7),
            ),
          ),

          // ── Suggested solution ───────────────────────────────────────────
          if (complaint.suggestedSolution != null) ...[
            const SizedBox(height: 14),
            _SuggestedSolutionBlock(text: complaint.suggestedSolution!),
          ],

          // ── Complaint-level attachments ──────────────────────────────────
          if (complaint.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            AttachmentGalleryGrid(attachments: complaint.attachments),
          ],

          // Admin status updater
          if (isAdmin) ...[
            const SizedBox(height: 16),
            Text('update_status_label'.tr, style: c.caption),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ComplaintStatus.values.map((s) {
                final selected = complaint.status == s;
                final sc = _statusColor(s);
                return GestureDetector(
                  onTap: selected
                      ? null
                      : () => provider.updateStatus(complaint.id, s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? sc : c.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sc, width: 1.5),
                    ),
                    child: Text(
                      _statusLabel(s),
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : sc,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => const Color(0xFFF59E0B),
    ComplaintStatus.inProgress => const Color(0xFF3B82F6),
    ComplaintStatus.resolved => const Color(0xFF10B981),
    ComplaintStatus.closed => const Color(0xFF6B7280),
  };

  Color _priorityColor(ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => const Color(0xFFEF4444),
    ComplaintPriority.high => const Color(0xFFF97316),
    ComplaintPriority.medium => const Color(0xFFF59E0B),
    ComplaintPriority.low => const Color(0xFF10B981),
  };

  String _statusLabel(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => 'status_open'.tr,
    ComplaintStatus.inProgress => 'status_in_progress'.tr,
    ComplaintStatus.resolved => 'status_resolved'.tr,
    ComplaintStatus.closed => 'status_closed'.tr,
  };

  String _categoryLabel(ComplaintCategory cat) => switch (cat) {
    ComplaintCategory.technical => 'category_technical'.tr,
    ComplaintCategory.payment => 'category_payment'.tr,
    ComplaintCategory.courseContent => 'category_content'.tr,
    ComplaintCategory.teacher => 'category_teacher'.tr,
    ComplaintCategory.student => 'category_student'.tr,
    ComplaintCategory.general => 'category_general'.tr,
  };

  String _priorityLabel(ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => 'priority_urgent'.tr,
    ComplaintPriority.high => 'priority_high'.tr,
    ComplaintPriority.medium => 'priority_medium'.tr,
    ComplaintPriority.low => 'priority_low'.tr,
  };
}

// ── Meta Chip ─────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reply Bubble ──────────────────────────────────────────────────────────────

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply, required this.myId});

  final ComplaintReply reply;
  final int myId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isMe = reply.senderId == myId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: reply.isAdmin
                  ? c.primary.withValues(alpha: 0.15)
                  : c.accent.withValues(alpha: 0.15),
              backgroundImage: reply.senderImage != null
                  ? NetworkImage(reply.senderImage!)
                  : null,
              child: reply.senderImage == null
                  ? Icon(
                Icons.person_rounded,
                size: 18,
                color: reply.isAdmin ? c.primary : c.accent,
              )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? c.primary
                    : reply.isAdmin
                    ? c.accentTint
                    : c.cardBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: c.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        reply.senderName,
                        style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: reply.isAdmin ? c.accent : c.textMedium,
                        ),
                      ),
                    ),
                  if (reply.message.isNotEmpty)
                    Text(
                      reply.message,
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 14,
                        height: 1.5,
                        color: isMe ? Colors.white : c.textDark,
                      ),
                    ),

                  // ── Reply image attachments ──────────────────────────────
                  if (reply.attachments.isNotEmpty) ...[
                    if (reply.message.isNotEmpty) const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reply.attachments
                          .map((a) => NetworkAttachmentTile(
                        attachment: a,
                        size: 70,
                      ))
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 4),
                  Text(
                    _formatTime(reply.createdAt),
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 10,
                      color: isMe ? Colors.white60 : c.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Reply Input (with image attach strip) ─────────────────────────────────────

class _ReplyInput extends StatelessWidget {
  const _ReplyInput({
    required this.controller,
    required this.isSending,
    required this.pendingAttachments,
    required this.onSend,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickFile,
    required this.onRemoveImage,
  });

  final TextEditingController controller;
  final bool isSending;
  final List<PendingAttachment> pendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Pending image strip ────────────────────────────────────────────
          if (pendingAttachments.isNotEmpty)
            _PendingImageStrip(
              attachments: pendingAttachments,
              onRemove: onRemoveImage,
            ),

          // ── Text input row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                // Camera / gallery button
                GestureDetector(
                  onTap: () => _showImagePicker(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: c.primaryTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.attach_file_rounded,
                      size: 20,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: c.divider),
                    ),
                    child: TextField(
                      controller: controller,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: 'bahji', color: c.textDark),
                      decoration: InputDecoration(
                        hintText: 'write_reply_hint'.tr,
                        hintStyle: TextStyle(
                          fontFamily: 'bahji',
                          color: c.textLight,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Send button
                GestureDetector(
                  onTap: isSending ? null : onSend,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: c.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: c.primaryShadow,
                    ),
                    child: isSending
                        ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: AppLoadingIndicator(),
                    )
                        : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePicker(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Gallery doesn't make sense as a separate concept on web —
              // the browser's file picker (below) already covers it.
              if (!kIsWeb)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.primaryTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.photo_library_outlined, color: c.primary),
                  ),
                  title: Text(
                    'pick_from_gallery'.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onPickGallery();
                  },
                ),
              if (!kIsWeb)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accentTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.camera_alt_outlined, color: c.accent),
                  ),
                  title: Text(
                    'take_photo'.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onPickCamera();
                  },
                ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.inputBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.folder_open_outlined, color: c.textLight),
                ),
                title: Text(
                  'browse_file_pdf_or_image'.tr,
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.w600,
                    color: c.textDark,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onPickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pending image strip inside reply bar ──────────────────────────────────────

class _PendingImageStrip extends StatelessWidget {
  const _PendingImageStrip({required this.attachments, required this.onRemove});

  final List<PendingAttachment> attachments;
  final ValueChanged<int> onRemove;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: _size + 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => PendingAttachmentTile(
          attachment: attachments[i],
          onRemove: () => onRemove(i),
          size: _size,
        ),
      ),
    );
  }
}

// ── Suggested solution display block (read-only) ──────────────────────────────
// Used in both _InfoCard (detail screen) and _ExpandedBody (history card).

class _SuggestedSolutionBlock extends StatelessWidget {
  const _SuggestedSolutionBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const Color accent = Color(0xFF059669); // emerald-600
    const Color tint = Color(0xFFD1FAE5); // emerald-100
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                'suggested_solution_label'.tr,
                style: const TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'by_student'.tr,
                  style: const TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: c.body.copyWith(fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}