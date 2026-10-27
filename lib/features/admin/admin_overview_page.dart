// lib/features/admin/admin_overview_page.dart
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';

import '../auth/auth_provider.dart';
import 'admin_common.dart';
import 'admin_income_breakdown.dart';
import 'admin_models.dart';
import 'admin_payouts_page.dart';
import 'admin_premium_widgets.dart';
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
    context.watch<LangProvider>();
    final p = context.watch<AdminOverviewProvider>();
    final c = context.colors;
    final o = p.data;
    final width = MediaQuery.of(context).size.width;
    if (o == null) {
      return p.error != null
          ? ErrorRetry(message: p.error!, onRetry: p.load)
          : const AppListSkeleton(items: 6);
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.divider),
          boxShadow: c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ServiceIcon(
                  icon: icon,
                  size: 38,
                  colors: [Color.lerp(color, Colors.white, 0.28)!, color],
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

    final waiting = o.i('pending_transfers') + pendingPayouts + o.i('pending_subscriptions');
    final name = context.watch<MyAuthProvider>().currentUser?.name ?? '';

    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // ── home: greeting · what waits for a decision · shortcuts (then the platform numbers below)
          HomeEntrance(
            index: 0,
            child: HomeHeader(name: name, subtitle: 'home_admin_sub'.tr, padding: const EdgeInsets.fromLTRB(6, 6, 6, 16)),
          ),
          HomeEntrance(
            index: 1,
            child: HomeHeroCard(
              margin: EdgeInsets.zero,
              gradient: waiting > 0 ? null : c.successGradient,
              glow: waiting > 0 ? null : c.success,
              child: Builder(builder: (context) {
                final on = homeOnHero(context);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  HomeHeroTag('home_admin_pulse'.tr, icon: Icons.monitor_heart_rounded),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$waiting', style: appText(44, w: FontWeight.w900, c: on, h: 1)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(waiting > 0 ? 'home_admin_waiting'.tr : 'home_admin_clear'.tr,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: on, h: 1.2)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: HomeHeroFigure(value: '${o.i('students')}', label: 'admin_students'.tr)),
                    Expanded(child: HomeHeroFigure(value: '${o.i('teachers')}', label: 'admin_teachers'.tr)),
                    Expanded(child: HomeHeroFigure(value: '${o.i('courses')}', label: 'courses'.tr)),
                  ]),
                ]);
              }),
            ),
          ),
          const SizedBox(height: 24),
          HomeEntrance(index: 2, child: HomeSectionTitle('home_needs_you'.tr, count: waiting, padding: const EdgeInsets.fromLTRB(6, 0, 0, 10))),
          HomeEntrance(
            index: 3,
            child: HomeActionGrid(padding: EdgeInsets.zero, children: [
              HomeActionCard(
                icon: Icons.pending_actions_rounded,
                title: 'admin_pending_transfers'.tr,
                count: o.i('pending_transfers'),
                tone: c.danger,
                attentionKey: AttentionTabs.adminFinance,
                onTap: () => open(const TeacherTransfersScreen()),
              ),
              HomeActionCard(
                icon: Icons.account_balance_wallet_rounded,
                title: 'admin_pending_payouts'.tr,
                count: pendingPayouts,
                tone: c.warning,
                onTap: () async {
                  final badge = context.read<AdminPendingPayoutsProvider>();
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPayoutsPage()));
                  badge.refresh();
                },
              ),
              HomeActionCard(
                icon: Icons.hourglass_top_rounded,
                title: 'admin_pending_subscriptions'.tr,
                count: o.i('pending_subscriptions'),
                tone: c.purple,
                onTap: () => open(const AdminSubscriptionsPage()),
              ),
              const HomeTodoCard(tabKey: AttentionTabs.adminSupport),
            ]),
          ),
          const SizedBox(height: 24),
          HomeEntrance(
            index: 4,
            child: HomeShortcuts(padding: EdgeInsets.zero, items: [
              HomeShortcut(icon: Icons.school_rounded, label: 'admin_students'.tr, onTap: () => onOpenTab(1)),
              HomeShortcut(icon: Icons.menu_book_rounded, label: 'courses'.tr, onTap: () => onOpenTab(2)),
              HomeShortcut(icon: Icons.person_pin_rounded, label: 'admin_teachers'.tr, onTap: () => onOpenTab(3)),
              HomeShortcut(icon: Icons.apps_rounded, label: 'home_admin_more'.tr, onTap: () => onOpenTab(4)),
            ]),
          ),
          const SizedBox(height: 24),
          HomeSectionTitle('home_admin_numbers'.tr, padding: const EdgeInsets.fromLTRB(6, 0, 0, 10)),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => open(const AdminSubscriptionsPage()),
            child: Container(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [c.primary, c.primaryDark],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: c.primary.withValues(alpha: 0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
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
          GridView.count(
            crossAxisCount: width > 2000
                ? 7
                :width > 1800
                ? 6
                : width > 1500
                ? 5
                : width > 1200
                ? 4
                : width > 900
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
        ],
      ),
    );
  }
}
