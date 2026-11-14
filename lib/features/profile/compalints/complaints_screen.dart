// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaints_screen.dart
// Works for both Student and Teacher roles — role-aware display.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/design/app_kit.dart' show AppEmpty, AppListSkeleton, AppRefresh, AppTime, AppTone, showAppNotice;
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_attachement_widgets.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_model.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/helpers.dart' show Helpers;
// ⚠ adjust this path to wherever swipe_request_card.dart lives in your project
// (it is the file the teacher transfer / device-request screens already import).
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_mentions.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSheetContent, AppBlock, AppBlockTone;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// ── Shared label / colour helpers (used by the new list widgets) ─────────────

Color _statusClr(ThemeConfigProvider c, ComplaintStatus s) => switch (s) {
  ComplaintStatus.open => c.warning,
  ComplaintStatus.inProgress => c.primary,
  ComplaintStatus.resolved => c.success,
  ComplaintStatus.closed => c.textLight,
};

String _statusTxt(ComplaintStatus s) => switch (s) {
  ComplaintStatus.open => 'status_open'.tr,
  ComplaintStatus.inProgress => 'status_in_progress'.tr,
  ComplaintStatus.resolved => 'status_resolved'.tr,
  ComplaintStatus.closed => 'status_closed'.tr,
};

Color _priorityClr(ThemeConfigProvider c, ComplaintPriority p) => switch (p) {
  ComplaintPriority.urgent => c.danger,
  ComplaintPriority.high => Color.lerp(c.warning, c.danger, 0.5)!,
  ComplaintPriority.medium => c.warning,
  ComplaintPriority.low => c.success,
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
  return AppTime.date(d);
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
    final ok = await p.changeStatusSilently(cm.id, target);
    if (ok) _swiped[cm.id] = target;
    showAppNotice(ok ? okMessage : 'error_try_again'.tr, error: !ok);
    return ok;
  }

  Future<bool> _resolve(ComplaintModel cm) => _setStatus(
    cm,
    ComplaintStatus.resolved,
    'complaint_resolved_snack'.tr,
  );

  /// Closing blocks further replies, so every way of closing (the swipe and the card's status menu) asks first.
  Future<bool> _confirmClose() async {
    final sure = await Helpers.confirmDialog(
      context,
      title: 'complaint_close_confirm'.tr,
      confirm: 'complaint_swipe_close'.tr,
    );
    return sure == true && mounted;
  }

  Future<bool> _close(ComplaintModel cm) async {
    if (!await _confirmClose()) return false;
    return _setStatus(cm, ComplaintStatus.closed, 'complaint_closed_snack'.tr);
  }

  /// The card's status menu: "closed" asks the same confirm the swipe asks.
  Future<void> _menuStatus(ComplaintModel cm, ComplaintStatus st) async {
    if (st == ComplaintStatus.closed && !await _confirmClose()) return;
    if (!mounted) return;
    context.read<ComplaintProvider>().updateStatus(cm.id, st);
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

    return BasePage(key: const ValueKey('complaints'), useWebCard: true, width: AppWidth.content,
      appBar: ScreenAppBar(title: 'complaints_and_support'.tr),
      child: SafeArea(
        child: Column(
          children: [
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
                margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
              ),
            Expanded(child: _buildList(p, staff, myId)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ComplaintProvider p, bool staff, int myId) {
    if (p.isLoadingList && p.complaints.isEmpty) {
      return const AppListSkeleton();
    }

    if (p.complaints.isEmpty && p.errorMsg != null && p.errorMsg != 'upload_failed') {
      return AppRefresh(
        onRefresh: () => p.loadComplaints(reset: true),
        scrollable: false,
        child: ErrorRetry(message: p.errorMsg!, onRetry: () => p.loadComplaints(reset: true)),
      );
    }

    if (p.complaints.isEmpty) {
      final filtered = p.statusFilter != null ||
          p.categoryFilter != null ||
          p.search.isNotEmpty;
      return AppRefresh(
        onRefresh: () => p.loadComplaints(reset: true),
        child: ListView(
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
    return AppRefresh(
      onRefresh: () => p.loadComplaints(reset: true),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 100),
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
            // staff move a complaint along without opening it
            onStatus: staff ? (st) => _menuStatus(cm, st) : null,
          );

          if (!_canSwipe(cm, staff, myId)) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
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
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t('نظرة عامة', 'Overview'),
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textDark,
                  ),
                ),
              ),
              if (stats.unreadAdmin > 0)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                  decoration: BoxDecoration(
                    color: context.colors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        size: 14,
                        color: context.colors.danger,
                      ),
                      const SizedBox(width: AppSpace.xxs),
                      Text(
                        'complaints_new_n'.tr
                            .replaceAll('{n}', '${stats.unreadAdmin}'),
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: context.colors.danger,
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
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
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
                color: _statusClr(context.colors, ComplaintStatus.open),
                title: _statusTxt(ComplaintStatus.open),
                value: stats.open,
                sub: share(stats.open),
                selected: selected == ComplaintStatus.open,
                onTap: () => onSelect(ComplaintStatus.open),
              ),
              _Kpi(
                icon: Icons.autorenew_rounded,
                color: _statusClr(context.colors, ComplaintStatus.inProgress),
                title: _statusTxt(ComplaintStatus.inProgress),
                value: stats.inProgress,
                sub: share(stats.inProgress),
                selected: selected == ComplaintStatus.inProgress,
                onTap: () => onSelect(ComplaintStatus.inProgress),
              ),
              _Kpi(
                icon: Icons.check_circle_rounded,
                color: _statusClr(context.colors, ComplaintStatus.resolved),
                title: _statusTxt(ComplaintStatus.resolved),
                value: stats.resolved,
                sub: share(stats.resolved),
                selected: selected == ComplaintStatus.resolved,
                onTap: () => onSelect(ComplaintStatus.resolved),
              ),
              _Kpi(
                icon: Icons.lock_rounded,
                color: _statusClr(context.colors, ComplaintStatus.closed),
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
        margin: const EdgeInsetsDirectional.only(end: AppSpace.sm),
        padding: const EdgeInsets.all(AppSpace.sm),
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
                  padding: const EdgeInsets.all(AppSpace.xs),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
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
                  fontFamily: AppFonts.display,
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
                fontFamily: AppFonts.display,
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: c.primaryWash,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.swipe_rounded, color: c.primary, size: 20),
            const SizedBox(width: AppSpace.sm),
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
    showAppModalSheet(
      useSafeArea: true,
      context: context,
      builder: (ctx) => AppSheetContent(tone: AppTone.neutral, icon: Icons.tune_rounded, 
            title: _t('تصفية حسب النوع', 'Filter by category'),
            children: [
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
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
                    fontFamily: AppFonts.display,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? context.colors.onHero : c.textMedium,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: AppSpace.xs),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? context.colors.onHero : color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? color : context.colors.onHero,
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxs),
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
              const SizedBox(width: AppSpace.xs),
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
                        padding: const EdgeInsets.all(AppSpace.xxs),
                        decoration: BoxDecoration(
                          color: context.colors.dangerBase,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '1',
                          style: TextStyle(
                            color: context.colors.onHero,
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
          const SizedBox(height: AppSpace.sm),
          // status — segmented pill (same look as the finance tabs)
          Container(
            padding: const EdgeInsets.all(AppSpace.xxs),
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
                      _statusClr(context.colors, s),
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
            const SizedBox(height: AppSpace.xs),
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
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xs, AppSpace.xxs),
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
                fontFamily: AppFonts.display,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xxs),
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
        margin: const EdgeInsetsDirectional.only(end: AppSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
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
            fontFamily: AppFonts.display,
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
    this.onStatus,
  });

  final ComplaintModel complaint;
  final bool isAdmin; // staff view → show who sent it
  final int myId;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<ComplaintStatus>? onStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cm = complaint;
    final mine = cm.userId == myId;
    final unread = (isAdmin && !mine) ? !cm.isReadByAdmin : !cm.isReadByUser;
    final statusColor = _statusClr(context.colors, cm.status);

    return GestureDetector(
      onTap: onTap,
      child: RequestCardShell(
        accent: _priorityClr(context.colors, cm.priority),
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
                const SizedBox(width: AppSpace.sm),
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
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      _agoTxt(cm.updatedAt),
                      style: c.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                if (onStatus != null)
                  PopupMenuButton<ComplaintStatus>(
                    tooltip: 'complaint_move_to'.tr,
                    icon: Icon(Icons.more_vert_rounded, color: c.textLight),
                    onSelected: onStatus,
                    itemBuilder: (_) => [
                      // only the moves that make sense from where it is now
                      for (final st in ComplaintStatus.values)
                        if (st != cm.status && !(cm.status == ComplaintStatus.closed && st == ComplaintStatus.open))
                          PopupMenuItem(
                            value: st,
                            child: Row(children: [
                              Icon(Icons.circle, size: 10, color: _statusClr(context.colors, st)),
                              const SizedBox(width: AppSpace.xs),
                              Text(_statusTxt(st)),
                            ]),
                          ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),

            // ── title + unread dot ──────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unread)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsetsDirectional.only(end: AppSpace.xs, top: AppSpace.xxs),
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
            const SizedBox(height: AppSpace.xs),
            Text(
              cm.description,
              style: c.caption.copyWith(height: 1.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpace.sm),

            // ── priority · category · counters ──────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if ((cm.targetLabel ?? '').isNotEmpty && cm.targetType != 'general')
                  _MetaChip(
                    icon: _targetIcon(cm.targetType),
                    label: cm.targetLabel!,
                    color: c.purple,
                  ),
                _MetaChip(
                  icon: Icons.flag_rounded,
                  label: _priorityTxt(cm.priority),
                  color: _priorityClr(context.colors, cm.priority),
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
                    color: context.colors.success,
                  ),
                if (cm.repliesCount > 0)
                  _MetaChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '${cm.repliesCount}',
                    color: c.textMedium,
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            _Journey(status: cm.status),
          ],
        ),
      ),
    );
  }
}

IconData _targetIcon(String? t) => switch (t) {
      'course' => Icons.menu_book_rounded,
      'teacher' => Icons.person_pin_rounded,
      'student' => Icons.school_rounded,
      'staff' => Icons.support_agent_rounded,
      'department' => Icons.apartment_rounded,
      _ => Icons.public_rounded,
    };

/// Open → In progress → Resolved → Closed: where this complaint stands, at a glance.
class _Journey extends StatelessWidget {
  const _Journey({required this.status});
  final ComplaintStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const steps = [ComplaintStatus.open, ComplaintStatus.inProgress, ComplaintStatus.resolved, ComplaintStatus.closed];
    final at = steps.indexOf(status);
    final tone = _statusClr(context.colors, status);
    return Row(children: [
      for (var i = 0; i < steps.length; i++) ...[
        Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: i == at ? 16 : 10,
            height: i == at ? 16 : 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= at ? tone : c.divider,
              border: i == at ? Border.all(color: tone.withValues(alpha: 0.25), width: 3) : null,
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(_statusTxt(steps[i]),
              style: c.caption.copyWith(fontSize: 10, fontWeight: i == at ? FontWeight.w800 : FontWeight.w500,
                  color: i <= at ? c.textDark : c.textLight)),
        ]),
        if (i < steps.length - 1)
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: AppSpace.md),
              color: i < at ? tone : c.divider,
            ),
          ),
      ],
    ]);
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
              color: context.colors.onHero,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            filtered ? 'admin_nothing_here_yet'.tr : 'no_complaints_yet'.tr,
            style: c.h2.copyWith(fontSize: 16),
          ),
          const SizedBox(height: AppSpace.xs),
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
    if (_scrollCtrl.hasClients && mounted) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: AppMotion.of(context).slow,
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
    return BasePage(appBar: ScreenAppBar(title: 'complaint_details_title'.tr), child: SafeArea(
      child: Column(
        children: [
          if (p.isLoadingDetail)
            const Expanded(
              child: AppListSkeleton(items: 4, withAvatar: false),
            )
          else if (complaint == null)
            Expanded(
              child: AppEmpty(
                icon: Icons.search_off_rounded,
                title: 'complaint_not_found'.tr,
                actionLabel: 'retry'.tr,
                onAction: () => p.loadDetail(widget.complaintId),
              ),
            )
          else ...[
              Expanded(
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
                  children: [
                    // ── Info card ──────────────────────────────────────────
                    ParentComponent(featureKey: 'complaint_detail.info', child: _InfoCard(
                      complaint: complaint,
                      isAdmin: !auth.isStudent,
                      provider: p,
                    )),
                    const SizedBox(height: AppSpace.xl),
                    // ── Replies ────────────────────────────────────────────
                    if (complaint.replies.isNotEmpty) ParentComponent(featureKey: 'complaint_detail.replies', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: Text('replies_label'.tr, style: AppType.section(context).copyWith(color: c.textDark)),
                      ),
                      ...complaint.replies.map(
                            (r) => _ReplyBubble(
                          reply: r,
                          myId: auth.currentUser?.id ?? 0,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                    ])),
                  ],
                ),
              ),
              // ── Reply input ──────────────────────────────────────────────
              if (complaint.status != ComplaintStatus.closed)
                ParentComponent(featureKey: 'complaint_detail.reply_input', child: _ReplyInput(
                  controller: _replyCtrl,
                  mentions: MentionApi.source('complaint', ref: widget.complaintId),
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

/// The thread's opening block (sky, the complaints subject — the same tone as the Complaints page): who sent it
/// (staff), the title in the editorial face, its status, the facts on paper chips and the text on a paper inset.
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
  Widget build(BuildContext context) => AppBlock(
        tone: AppBlockTone.sky,
        hero: true,
        child: Builder(builder: _body),
      );

  Widget _body(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final statusClr = _statusClr(context.colors, complaint.status);
    final motion = AppMotion.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Who sent it (staff only)
        if (isAdmin) ...[
          Row(
            children: [
              _OwnerAvatar(
                name: complaint.userName,
                imageUrl: complaint.userImage,
                size: AppTouch.min - AppSpace.xxs,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complaint.userName,
                      style: AppType.bodyStrong(context).copyWith(color: b.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(AppTime.dateTime(complaint.createdAt), style: AppType.meta(context).copyWith(color: b.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // Title + status
        Semantics(
          header: true,
          child: Text(complaint.title, style: AppType.headline(context).copyWith(color: b.ink)),
        ),
        const SizedBox(height: AppSpace.sm),
        // Meta
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            _MetaChip(icon: Icons.circle, label: _statusLabel(complaint.status), color: statusClr, dot: true),
            _MetaChip(
              icon: Icons.label_outline_rounded,
              label: _categoryLabel(complaint.category),
              color: c.primary,
            ),
            _MetaChip(
              icon: Icons.flag_outlined,
              label: _priorityLabel(complaint.priority),
              color: _priorityClr(context.colors, complaint.priority),
            ),
            if (complaint.courseTitle != null)
              _MetaChip(
                icon: Icons.book_outlined,
                label: complaint.courseTitle!,
                color: c.accent,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        // Description
        Container(
          width: double.infinity,
          padding: AppSpace.card,
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: MentionText(
            complaint.description,
            style: AppType.body(context).copyWith(color: c.textDark, height: 1.7),
          ),
        ),

        // ── Suggested solution ───────────────────────────────────────────
        if (complaint.suggestedSolution != null) ...[
          const SizedBox(height: AppSpace.sm),
          _SuggestedSolutionBlock(text: complaint.suggestedSolution!),
        ],

        // ── Complaint-level attachments ──────────────────────────────────
        if (complaint.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          AttachmentGalleryGrid(attachments: complaint.attachments),
        ],

        // Admin status updater
        if (isAdmin) ...[
          const SizedBox(height: AppSpace.lg),
          Text('update_status_label'.tr, style: AppType.label(context).copyWith(color: b.muted)),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: ComplaintStatus.values.map((s) {
              final selected = complaint.status == s;
              final sc = _statusClr(context.colors, s);
              final ink = c.blockAccentInk(sc, c.cardBg);
              return Semantics(
                button: true,
                selected: selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: selected ? null : () => provider.updateStatus(complaint.id, s),
                  child: AnimatedContainer(
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    constraints: const BoxConstraints(minHeight: AppTouch.min),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    decoration: BoxDecoration(
                      color: selected ? ink : c.cardBg,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: selected ? ink : c.divider, width: AppBorder.hairline),
                    ),
                    child: Text(
                      _statusLabel(s),
                      style: AppType.label(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? c.onHero : ink,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }


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

/// A fact on the info block: paper, the tone as readable ink (a dot for the status).
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    this.dot = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.blockAccentInk(color, c.cardBg);
    return Container(
      constraints: const BoxConstraints(minHeight: AppIconSize.xl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: color, shape: BoxShape.circle))
          else
            Icon(icon, size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpace.xs - AppSpace.xxs / 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: dot ? c.textDark : ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reply Bubble ──────────────────────────────────────────────────────────────

/// One message of the thread: mine in the primary on the end side, the team's on a peach tint, anyone else on
/// paper; the tail corner points at the sender (mirrors in RTL).
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply, required this.myId});

  final ComplaintReply reply;
  final int myId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isMe = reply.senderId == myId;
    final bubble = isMe ? c.primary : (reply.isAdmin ? c.accentTint : c.cardBg);
    final ink = isMe ? c.onHero : c.textDark;
    const big = Radius.circular(AppRadius.card);
    const tail = Radius.circular(AppSpace.xxs);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: AppIconSize.sm,
              backgroundColor: reply.isAdmin
                  ? c.primary.withValues(alpha: 0.15)
                  : c.inputBg,
              backgroundImage: reply.senderImage != null
                  ? NetworkImage(reply.senderImage!)
                  : null,
              child: reply.senderImage == null
                  ? Icon(
                Icons.person_rounded,
                size: AppIconSize.sm,
                color: reply.isAdmin ? c.blockAccentInk(c.primary, c.cardBg) : c.textMedium,
              )
                  : null,
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                decoration: BoxDecoration(
                  color: bubble,
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: big,
                    topEnd: big,
                    bottomStart: isMe ? big : tail,
                    bottomEnd: isMe ? tail : big,
                  ),
                  border: isMe ? null : Border.all(color: c.divider, width: AppBorder.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                        child: Text(
                          reply.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.meta(context).copyWith(
                            fontWeight: FontWeight.w600,
                            color: reply.isAdmin ? c.blockAccentInk(c.primary, bubble) : c.textMedium,
                          ),
                        ),
                      ),
                    if (reply.message.isNotEmpty)
                      MentionText(
                        reply.message,
                        style: AppType.body(context).copyWith(height: 1.5, color: ink),
                        mentionStyle: isMe
                            ? TextStyle(color: c.onHero, decoration: TextDecoration.underline)
                            : null,
                      ),

                    // ── Reply image attachments ──────────────────────────────
                    if (reply.attachments.isNotEmpty) ...[
                      if (reply.message.isNotEmpty) const SizedBox(height: AppSpace.xs),
                      Wrap(
                        spacing: AppSpace.xs - AppSpace.xxs / 2,
                        runSpacing: AppSpace.xs - AppSpace.xxs / 2,
                        children: reply.attachments
                            .map((a) => NetworkAttachmentTile(
                          attachment: a,
                          size: AppTouch.min * 1.5,
                        ))
                            .toList(),
                      ),
                    ],

                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      _formatTime(reply.createdAt),
                      style: AppType.overline(context).copyWith(
                        color: isMe ? c.onHero.withValues(alpha: 0.75) : c.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) => AppTime.time(d);
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
    this.mentions,
  });

  final TextEditingController controller;

  /// "@" suggests the complainant and the staff of this complaint (D-075).
  final MentionSource? mentions;
  final bool isSending;
  final List<PendingAttachment> pendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;
  final ValueChanged<int> onRemoveImage;

  Widget _withMentions(Widget field) {
    final m = mentions;
    return m == null ? field : Mentions(controller: controller, source: m, above: true, child: field);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const tap = AppTouch.min;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
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
            padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end, // the @mention list grows above the field
              children: [
                // Camera / gallery / file
                IconButton(
                  tooltip: 'add_attachment'.tr,
                  constraints: const BoxConstraints.tightFor(width: tap, height: tap),
                  onPressed: () => _showImagePicker(context),
                  icon: Icon(Icons.attach_file_rounded, size: AppIconSize.md, color: c.textMedium),
                ),
                const SizedBox(width: AppSpace.xxs),

                // Text field
                Expanded(
                  child: _withMentions(Container(
                    constraints: const BoxConstraints(minHeight: tap),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.inputBg,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: TextField(
                      controller: controller,
                      maxLines: 5,
                      minLines: 1,
                      style: AppType.body(context).copyWith(color: c.textDark),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: 'write_reply_hint'.tr,
                        hintStyle: AppType.body(context).copyWith(color: c.textLight),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                          vertical: AppSpace.sm,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  )),
                ),
                const SizedBox(width: AppSpace.xs),

                // Send button
                Semantics(
                  button: true,
                  label: 'send_btn'.tr,
                  child: AppPressScale(
                    enabled: !isSending,
                    child: GestureDetector(
                      onTap: isSending ? null : onSend,
                      child: Container(
                        width: tap,
                        height: tap,
                        decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                        child: isSending
                            ? const Padding(
                          padding: EdgeInsets.all(AppSpace.sm),
                          child: AppLoadingIndicator(),
                        )
                            : Icon(Icons.send_rounded, color: c.onHero, size: AppIconSize.md),
                      ),
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
    showAppModalSheet(
      useSafeArea: true,
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gallery doesn't make sense as a separate concept on web —
              // the browser's file picker (below) already covers it.
              if (!kIsWeb)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.primaryTint,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Icon(Icons.photo_library_outlined, color: c.primary),
                  ),
                  title: Text(
                    'pick_from_gallery'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
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
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Icon(Icons.camera_alt_outlined, color: c.accent),
                  ),
                  title: Text(
                    'take_photo'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
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
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Icon(Icons.folder_open_outlined, color: c.textLight),
                ),
                title: Text(
                  'browse_file_pdf_or_image'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
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
      height: _size + AppSpace.md,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
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
    final Color tint = c.successTint;
    final Color ink = c.blockAccentInk(c.success, tint);
    return Container(
      width: double.infinity,
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: AppIconSize.sm, color: ink),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(
                  'suggested_solution_label'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 1),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('by_student'.tr, style: AppType.overline(context).copyWith(color: c.textMedium)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(text, style: AppType.body(context).copyWith(height: 1.6, color: c.textDark)),
        ],
      ),
    );
  }
}
