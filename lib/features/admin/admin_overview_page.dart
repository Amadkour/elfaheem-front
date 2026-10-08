// lib/features/admin/admin_overview_page.dart
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_income_breakdown.dart';
import 'admin_models.dart';
import 'admin_payouts_page.dart';
import 'admin_providers.dart';
import 'admin_subscriptions_page.dart';
import 'enrollment_request/teacher_transfers_screen.dart';

class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({super.key, required this.onOpenTab});

  /// 0 overview · 1 students · 2 courses · 3 teachers · 4 more
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminOverviewProvider()..load(),
    child: _View(onOpenTab: onOpenTab),
  );
}

class _View extends StatelessWidget {
  const _View({required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminOverviewProvider>();
    final c = context.colors;
    final o = p.data;

    if (o == null) {
      return p.error != null
          ? ErrorRetry(message: p.error!, onRetry: p.load)
          : const Center(child: CircularProgressIndicator());
    }

    // Live count owned by the dashboard shell (same number as the "More" badge).
    final pendingPayouts = context.watch<AdminPendingPayoutsProvider>().count;

    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    // EVERY card is tappable: the arrow in the corner shows it opens something.
    Widget card(
      IconData icon,
      String label,
      String value,
      Color color, {
      required VoidCallback onTap,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Icon(
                  AppConfig.lang == 'ar'
                      ? CupertinoIcons.arrow_up_left
                      : CupertinoIcons.arrow_up_right,
                  size: 16,
                  color: c.textLight,
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: c.textDark,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // long labels used to overflow the fixed-ratio card
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 12,
                color: c.textLight,
              ),
            ),
          ],
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => open(const AdminSubscriptionsPage()),
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.primary, c.primaryDark]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.subscriptionRequired
                              ? 'admin_subscription_required'.tr
                              : 'admin_the_app_is_free'.tr,
                          style: const TextStyle(
                            fontFamily: 'tajawal',
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${o.i('active_subscriptions')} ${'admin_active_subscribers'.tr}'
                          '${o.i('pending_subscriptions') > 0 ? ' • ${o.i('pending_subscriptions')} ${'admin_pending_2'.tr}' : ''}',
                          style: const TextStyle(
                            fontFamily: 'tajawal',
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_outward_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              constraints: BoxConstraints(maxWidth: 1200),
              child: GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 1000
                    ? 4
                    : MediaQuery.of(context).size.width > 700
                    ? 3
                    : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.35,
                children: [
                  card(
                    Icons.school_rounded,
                    'admin_students'.tr,
                    '${o.i('students')}',
                    c.primary,
                    onTap: () => onOpenTab(1),
                  ),
                  card(
                    Icons.person_pin_rounded,
                    'admin_teachers'.tr,
                    '${o.i('teachers')}',
                    c.purple,
                    onTap: () => onOpenTab(
                      3,
                    ), // Teachers is a tab of the shell now (was pushing a duplicate page)
                  ),
                  card(
                    Icons.menu_book_rounded,
                    'courses'.tr,
                    '${o.i('courses')}',
                    c.success,
                    onTap: () => onOpenTab(2),
                  ),
                  card(
                    Icons.public_rounded,
                    'filter_published'.tr,
                    '${o.i('published_courses')}',
                    c.warning,
                    onTap: () => onOpenTab(2),
                  ),
                  // Money cards: totals PER CURRENCY (never EGP + SAR added together); tap = full price breakdown.
                  card(
                    Icons.payments_rounded,
                    'admin_course_income_after_discounts'.tr,
                    moneyByCurrency(o.byCurrency('income_by_currency')),
                    c.success,
                    onTap: () => showIncomeBreakdown(context),
                  ),
                  card(
                    Icons.request_quote_rounded,
                    'admin_collected_incl_fees'.tr,
                    moneyByCurrency(o.byCurrency('collected_by_currency')),
                    c.charcoal,
                    onTap: () => showIncomeBreakdown(context),
                  ),
                  card(
                    Icons.account_balance_rounded,
                    'admin_platform_income'.tr,
                    moneyByCurrency(o.byCurrency('platform_income_by_currency')),
                    c.primary,
                    onTap: () => showIncomeBreakdown(context),
                  ),
                  card(
                    Icons.card_membership_rounded,
                    'admin_subscription_income'.tr,
                    moneyByCurrency(
                      o.byCurrency('subscription_income_by_currency'),
                    ),
                    c.purple,
                    onTap: () => open(const AdminSubscriptionsPage()),
                  ),
                  card(
                    Icons.pending_actions_rounded,
                    'admin_pending_transfers'.tr,
                    '${o.i('pending_transfers')}',
                    c.danger,
                    onTap: () => open(const TeacherTransfersScreen()),
                  ),
                  card(
                    Icons.how_to_reg_rounded,
                    'admin_active_enrolments'.tr,
                    '${o.i('active_enrollments')}',
                    c.primary,
                    onTap: () => onOpenTab(1),
                  ),
                  card(
                    Icons.undo_rounded,
                    'admin_refunded'.tr,
                    moneyByCurrency(o.byCurrency('refunded_by_currency')),
                    c.warning,
                    onTap: () => showIncomeBreakdown(context),
                  ),
                  // ── Counters that mirror the "More" tab ──
                  card(
                    Icons.account_balance_wallet_rounded,
                    'admin_pending_payouts'.tr,
                    '$pendingPayouts',
                    c.danger,
                    onTap: () async {
                      final badge = context.read<AdminPendingPayoutsProvider>();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminPayoutsPage(),
                        ),
                      );
                      badge.refresh();
                    },
                  ),
                  card(
                    Icons.card_membership_rounded,
                    'admin_active_subscribers'.tr,
                    '${o.i('active_subscriptions')}',
                    c.success,
                    onTap: () => open(const AdminSubscriptionsPage()),
                  ),
                  card(
                    Icons.hourglass_top_rounded,
                    'admin_pending_subscriptions'.tr,
                    '${o.i('pending_subscriptions')}',
                    c.warning,
                    onTap: () => open(const AdminSubscriptionsPage()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
