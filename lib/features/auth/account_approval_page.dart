// lib/features/auth/account_approval_page.dart
//
// Registration modes (D-1121): a new account whose role the super admin set to "admin approval" (or "pay, then
// approval") waits for a platform admin before using the app. The server answers 403 `account_pending_approval`
// (or `account_rejected`, with the reason) on every route but sign-in / sign-out, /auth/me, the account-fee routes and
// the live event stream; ApiClient opens this page in place of everything. It can only wait, look for contact
// details, or sign out.
//
//   GET /api/v1/auth/me   → account_approval {state: none | pending | rejected, reason?}, account_fee {due}
//
// It reloads when the `account_approval` live event arrives (SSE + silent push, the admin's decision), when the app
// comes back to the front, and on "Check now" — never on a timer. An approved account (or a role switched to a mode
// without approval) goes to its home; an account that still owes the fee goes to the pay page.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, t;
import '../org/org_v3.dart' show orgCall, orgErrorText;
import '../profile/about/about_and_terms_screen.dart' show AboutScreen;
import 'account_fee_page.dart' show AccountFeePage;
import 'auth_provider.dart';

class AccountApprovalPage extends StatefulWidget {
  const AccountApprovalPage({super.key});

  static const route = '/account_approval';

  /// On screen now (a burst of 403s never stacks a second copy).
  static bool isOpen = false;

  @override
  State<AccountApprovalPage> createState() => _AccountApprovalPageState();
}

class _AccountApprovalPageState extends State<AccountApprovalPage> with WidgetsBindingObserver {
  Map<String, dynamic>? _s;
  String? _error;
  bool _checking = false;
  bool _left = false;
  StreamSubscription<LiveEvent>? _sub;

  @override
  void initState() {
    super.initState();
    AccountApprovalPage.isOpen = true;
    WidgetsBinding.instance.addObserver(this);
    LiveEventsClient.instance.bind();
    _sub = LiveEvents.instance.listen({LiveEvents.accountApproval}, (_) => _load());
    _load();
  }

  @override
  void dispose() {
    AccountApprovalPage.isOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    LiveEventsClient.instance.release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_left) return;
    setState(() => _checking = true);
    final r = await orgCall(() => ApiClient().get('/api/v1/auth/me'), quiet: true);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!r.ok) return setState(() => _error = orgErrorText(r.error!));
    final me = r.map;
    if (asMap(me['account_fee'])['due'] == true) return _goFee();
    final a = asMap(me['account_approval']);
    final state = '${a['state'] ?? 'none'}';
    if (state != 'pending' && state != 'rejected') return _goHome();
    setState(() {
      _s = a;
      _error = null;
    });
  }

  void _goHome() {
    if (_left || !mounted) return;
    _left = true;
    final auth = context.read<MyAuthProvider>();
    showAppNotice(t('تمت الموافقة على حسابك — أهلاً بك', 'Your account is approved — welcome'));
    Navigator.of(context).pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
  }

  void _goFee() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
            builder: (_) => const AccountFeePage(), settings: const RouteSettings(name: AccountFeePage.route)),
        (_) => false);
  }

  Future<void> _signOut() async {
    final auth = context.read<MyAuthProvider>();
    final nav = Navigator.of(context);
    _left = true;
    if (!await auth.logout()) {
      _left = false;                               // kept signed in: unsent offline work the person kept
      return;
    }
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  void _contact() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen(canAsk: false)));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: BasePage(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                child: _s == null
                    ? (_error != null
                        ? AppCard(
                            child: AppErrorState(
                                title: t('تعذّر تحميل حالة حسابك', 'Could not load your account status'),
                                message: _error,
                                onRetry: _load,
                                compact: true))
                        : const AppListSkeleton(items: 2))
                    : AccountApprovalView(
                        rejected: _s!['state'] == 'rejected',
                        reason: _s!['reason'] as String?,
                        paidFirst: _s!['mode'] == 'paid_approval',
                        checking: _checking,
                        onCheck: _load,
                        onContact: _contact,
                        onSignOut: _signOut,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The waiting page's content from plain values (what the layout harness tests).
class AccountApprovalView extends StatelessWidget {
  /// An admin turned the account down ([reason] may say why); otherwise it is waiting.
  final bool rejected;
  final String? reason;

  /// The role's mode is "pay, then approval": the fee is already paid, say so.
  final bool paidFirst;
  final bool checking;
  final VoidCallback onCheck, onContact, onSignOut;

  const AccountApprovalView({
    super.key,
    required this.rejected,
    this.reason,
    this.paidFirst = false,
    this.checking = false,
    required this.onCheck,
    required this.onContact,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = rejected ? c.danger : c.primary;
    final why = (reason ?? '').trim();
    final steps = [
      if (paidFirst) (Icons.check_circle_rounded, t('استلمنا رسوم الحساب', 'We received your account fee'), true),
      (Icons.check_circle_rounded, t('أنشأت حسابك وأكدت بياناتك', 'You created your account and confirmed your details'), true),
      (
        rejected ? Icons.cancel_rounded : Icons.hourglass_top_rounded,
        rejected ? t('لم تتم الموافقة', 'Not approved') : t('مراجعة إدارة المنصة', 'Review by the platform team'),
        false,
      ),
      if (!rejected)
        (Icons.notifications_active_rounded, t('نخبرك بإشعار وبريد فور القرار', 'We let you know by notification and e-mail'), false),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        key: const ValueKey('account_approval.card'),
        highlight: !rejected,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                  color: rejected ? c.dangerTint : c.primaryTint, borderRadius: AppRadius.controlAll),
              child: Icon(rejected ? Icons.person_off_rounded : Icons.verified_user_rounded,
                  color: tone, size: AppIconSize.lg),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  rejected ? t('لم تتم الموافقة على حسابك', 'Your account was not approved') : t('حسابك قيد المراجعة', 'Your account is being reviewed'),
                  key: const ValueKey('account_approval.title'),
                  style: AppType.section(context),
                ),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  rejected
                      ? t('يمكنك التواصل مع إدارة المنصة لمعرفة التفاصيل أو تصحيح بياناتك.',
                          'You can contact the platform team for details or to correct your information.')
                      : t('تراجع إدارة المنصة الحسابات الجديدة قبل فتحها. لا تحتاج لفعل شيء الآن.',
                          'The platform team reviews new accounts before they open. There is nothing you need to do now.'),
                  style: AppType.meta(context),
                ),
              ]),
            ),
          ]),
          if (rejected && why.isNotEmpty) ...[
            AppSpace.gapMd,
            AppBanner(
              key: const ValueKey('account_approval.reason'),
              icon: Icons.info_outline_rounded,
              color: c.danger,
              text: t('السبب: $why', 'Reason: $why'),
            ),
          ],
          AppSpace.gapMd,
          for (final (icon, label, done) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon,
                    size: AppIconSize.md,
                    color: done ? c.success : (rejected && icon == Icons.cancel_rounded ? c.danger : c.textLight)),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(label,
                      style: AppType.body(context).copyWith(color: done ? c.textMedium : c.textDark)),
                ),
              ]),
            ),
          AppSpace.gapXs,
          AppButton.secondary(
            key: const ValueKey('account_approval.contact'),
            expand: true,
            label: t('تواصل مع إدارة المنصة', 'Contact the platform team'),
            icon: Icons.support_agent_rounded,
            onPressed: onContact,
          ),
        ]),
      ),
      AppSpace.gapSm,
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
        TextButton.icon(
          key: const ValueKey('account_approval.check'),
          onPressed: checking ? null : onCheck,
          icon: const Icon(Icons.refresh_rounded, size: AppIconSize.md),
          label: Text(t('تحقّق الآن', 'Check now')),
        ),
        TextButton.icon(
          key: const ValueKey('account_approval.sign_out'),
          onPressed: onSignOut,
          icon: Icon(DirIcons.logout, size: AppIconSize.md),
          label: Text(t('تسجيل الخروج', 'Sign out')),
        ),
      ]),
    ]);
  }
}
