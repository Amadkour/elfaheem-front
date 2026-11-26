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
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, t;
import '../org/org_v3.dart' show orgCall, orgErrorText;
import '../profile/about/about_and_terms_screen.dart' show AboutScreen;
import 'account_fee_page.dart' show AccountFeePage;
import 'auth_provider.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart' show AuthButton;

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
    final rejected = _s?['state'] == 'rejected';
    return PopScope(
      canPop: false,
      child: BasePage(
        child: AuthLayout(
          showBack: false,
          kicker: rejected ? 'sa_appr_kicker_rejected'.tr : 'sa_appr_kicker'.tr,
          heroTitle: rejected ? 'sa_appr_hero_rejected'.tr : 'sa_appr_hero'.tr,
          squiggle: rejected ? 'sa_appr_squiggle_rejected'.tr : 'sa_appr_squiggle'.tr,
          glyph: rejected ? Icons.edit_note_rounded : Icons.hourglass_top_rounded,
          glyphTone: rejected ? context.colors.kit.accent(AppAccent.pink) : null,
          title: rejected ? 'sa_appr_title_rejected'.tr : 'sa_appr_title'.tr,
          subtitle: rejected ? 'sa_appr_sub_rejected'.tr : 'sa_appr_sub'.tr,
          actions: (onHero) => AuthSwitches(onHero: onHero),
          body: (context, wide) => _s == null
              ? (_error != null
                  ? AppErrorState(
                      title: t('تعذّر تحميل حالة حسابك', 'Could not load your account status'),
                      message: _error,
                      onRetry: _load,
                      compact: true)
                  : const AppListSkeleton(items: 2))
              : AccountApprovalView(
                  rejected: rejected,
                  reason: _s!['reason'] as String?,
                  paidFirst: _s!['mode'] == 'paid_approval',
                  checking: _checking,
                  onCheck: _load,
                  onContact: _contact,
                  onSignOut: _signOut,
                  // the public catalogue route (guest explore) while the account waits
                  onBrowse: () => Navigator.of(context).pushNamed('/explore'),
                ),
        ),
      ),
    );
  }
}

/// The waiting page's content from plain values (what the layout harness tests): the steps as one path (done ·
/// now · soon), ONE button (check now) and two quiet links (contact · sign out). It sits in the auth card.
class AccountApprovalView extends StatelessWidget {
  /// An admin turned the account down ([reason] may say why); otherwise it is waiting.
  final bool rejected;
  final String? reason;

  /// The role's mode is "pay, then approval": the fee is already paid, say so.
  final bool paidFirst;
  final bool checking;
  final VoidCallback onCheck, onContact, onSignOut;

  /// Browse the courses while waiting; null = no link.
  final VoidCallback? onBrowse;

  const AccountApprovalView({
    super.key,
    required this.rejected,
    this.reason,
    this.paidFirst = false,
    this.checking = false,
    required this.onCheck,
    required this.onContact,
    required this.onSignOut,
    this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final why = (reason ?? '').trim();
    final ink = AppAreaScope.of(context).ink;
    Widget link(String key, String label, VoidCallback? onTap, Color color) => TextButton(
          key: ValueKey(key),
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: color),
          child: Text(label, style: AppType.bodyStrong(context).copyWith(color: color)),
        );
    return Column(
      key: const ValueKey('account_approval.card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rejected && why.isNotEmpty) ...[
          AppBanner(
            key: const ValueKey('account_approval.reason'),
            icon: Icons.info_outline_rounded,
            color: c.danger,
            text: t('السبب: $why', 'Reason: $why'),
          ),
          AppSpace.gapMd,
        ],
        AppRoadmap(
          dense: true,
          axis: Axis.vertical,
          nodes: [
            if (paidFirst) AppRoadmapNode(title: 'sa_appr_step_paid'.tr, state: AppRoadmapState.done),
            AppRoadmapNode(title: 'sa_appr_step_signed'.tr, state: AppRoadmapState.done),
            AppRoadmapNode(
              title: rejected ? 'sa_appr_step_fix'.tr : 'sa_appr_step_review'.tr,
              subtitle: 'sa_appr_now'.tr,
              state: rejected ? AppRoadmapState.warn : AppRoadmapState.current,
            ),
            AppRoadmapNode(title: 'sa_appr_step_open'.tr, subtitle: 'sa_appr_soon'.tr),
          ],
        ),
        AppSpace.gapLg,
        KeyedSubtree(
          key: const ValueKey('account_approval.check'),
          child: AuthButton(label: 'sa_appr_check'.tr, loading: checking, onPressed: onCheck),
        ),
        AppSpace.gapXs,
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (onBrowse != null) ...[
            link('account_approval.browse', 'sa_appr_browse'.tr, onBrowse, ink),
            ExcludeSemantics(child: Text('•', style: AppType.meta(context).copyWith(color: c.textLight))),
          ],
          link('account_approval.contact', 'sa_appr_contact'.tr, onContact, ink),
          ExcludeSemantics(child: Text('•', style: AppType.meta(context).copyWith(color: c.textLight))),
          link('account_approval.sign_out', 'sa_appr_sign_out'.tr, onSignOut, c.kit.error.ink),
        ]),
      ],
    );
  }
}
