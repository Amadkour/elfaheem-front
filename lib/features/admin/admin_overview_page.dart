// lib/features/admin/admin_overview_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_providers.dart';

class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({super.key, required this.onOpenTab});

  /// 0 overview · 1 students · 2 courses · 3 more
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

    Widget card(IconData icon, String label, String value, Color color, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value,
                    style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 22, color: c.textDark)),
              ),
              Text(label, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
            ]),
          ),
        );

    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.primary, c.primaryDark]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      o.subscriptionRequired
                          ? 'admin_subscription_required'.tr
                          : 'admin_the_app_is_free'.tr,
                      style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${o.i('active_subscriptions')} ${'admin_active_subscribers'.tr}'
                      '${o.i('pending_subscriptions') > 0 ? ' • ${o.i('pending_subscriptions')} ${'admin_pending_2'.tr}' : ''}',
                      style: const TextStyle(fontFamily: 'tajawal', color: Colors.white70, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              card(Icons.school_rounded, 'admin_students'.tr, '${o.i('students')}', c.primary, onTap: () => onOpenTab(1)),
              card(Icons.person_pin_rounded, 'admin_teachers'.tr, '${o.i('teachers')}', c.purple),
              card(Icons.menu_book_rounded, 'courses'.tr, '${o.i('courses')}', c.success, onTap: () => onOpenTab(2)),
              card(Icons.public_rounded, 'filter_published'.tr, '${o.i('published_courses')}', c.warning),
              card(Icons.payments_rounded, 'admin_course_income_after_discounts'.tr, money(o.d('course_income')), c.success),
              card(Icons.request_quote_rounded, 'admin_collected_incl_fees'.tr, money(o.d('collected')), c.charcoal),
              card(Icons.account_balance_rounded, 'admin_platform_income'.tr, money(o.d('platform_income')), c.primary),
              card(Icons.card_membership_rounded, 'admin_subscription_income'.tr, money(o.d('subscription_income')), c.purple),
              card(Icons.pending_actions_rounded, 'admin_pending_transfers'.tr, '${o.i('pending_transfers')}', c.danger),
              card(Icons.how_to_reg_rounded, 'admin_active_enrolments'.tr, '${o.i('active_enrollments')}', c.primary),
              card(Icons.undo_rounded, 'admin_refunded'.tr, money(o.d('refunded')), c.warning),
            ],
          ),
        ],
      ),
    );
  }
}
