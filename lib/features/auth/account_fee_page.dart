// lib/features/auth/account_fee_page.dart
//
// The account fee (D-1120): a teacher or parent whose role's fee the super admin switched on pays it once before
// using the app. The server answers 402 `account_fee_required` on every route but sign-in / sign-out, /auth/me and
// the fee routes; ApiClient opens this page in place of everything (no way back into the app until it is paid —
// it can only sign out).
//
//   GET  /api/v1/account-fee            {due, required, amount, currency, role, methods, payment, transfer_details}
//   POST /api/v1/account-fee/checkout   {method: moyasar|paymob} → {checkout_url, token}
//   POST /api/v1/account-fee/transfer   multipart (bank_transfer | instapay + receipt) → review by the platform
//
// The card checkout opens in the browser; coming back to the app re-reads the status (and "Check now" does too).
// A paid or waived account (or a fee the super admin switched off) goes to its home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppJelly, AppSlap;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import '../org/org_creation_fee.dart' show money, showFeeTransferSheet;
import '../org/org_v3.dart' show OrgCall, orgCall, orgErrorText;
import 'auth_provider.dart';
import 'auth_shell.dart';

const accountFeePath = '/api/v1/account-fee';

class AccountFeePage extends StatefulWidget {
  const AccountFeePage({super.key});

  static const route = '/account_fee';

  /// On screen now (a burst of 402s never stacks a second copy).
  static bool isOpen = false;

  @override
  State<AccountFeePage> createState() => _AccountFeePageState();
}

class _AccountFeePageState extends State<AccountFeePage> with WidgetsBindingObserver {
  Map<String, dynamic>? _s;
  String? _error;
  String? _method;
  bool _busy = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    AccountFeePage.isOpen = true;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    AccountFeePage.isOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(); // back from the card checkout in the browser
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(accountFeePath), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      if (r.endpointMissing) return _goHome(); // an older server has no account fee
      return setState(() => _error = orgErrorText(r.error!));
    }
    final s = r.map;
    if (s['due'] != true) return _goHome();
    final methods = asMapList(s['methods']);
    setState(() {
      _s = s;
      _error = null;
      if (_method == null || !methods.any((m) => m['id'] == _method)) {
        _method = methods.isEmpty ? null : '${methods.first['id']}';
      }
    });
  }

  void _goHome() {
    if (_left || !mounted) return;
    _left = true;
    final auth = context.read<MyAuthProvider>();
    showAppNotice(t('حسابك جاهز — أهلاً بك', 'Your account is ready — welcome'));
    Navigator.of(context).pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
  }

  Future<void> _payCard() async {
    setState(() => _busy = true);
    final r = await orgCall(() => ApiClient().post('$accountFeePath/checkout', body: {'method': _method}), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return _refused(r);
    final url = '${r.map['checkout_url'] ?? ''}';
    if (url.isNotEmpty) await openExternalLink(url);
    if (mounted) _load();
  }

  Future<void> _payTransfer() async {
    final s = _s!;
    final ok = await showFeeTransferSheet(context,
        path: accountFeePath,
        method: _method!,
        details: asMap(s['transfer_details']),
        amount: money(s['amount'], '${s['currency']}'));
    if (ok == true && mounted) _load();
  }

  void _refused(OrgCall r) {
    if (r.code == 'account_fee_not_due') return _goHome();
    showAppNotice(r.error == null ? '' : orgErrorText(r.error!), error: true);
    if (r.code == 'fee_under_review') _load();
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: BasePage(
        child: AuthLayout(
          showBack: false,
          kicker: 'sa_fee_kicker'.tr,
          heroTitle: 'sa_fee_hero'.tr,
          squiggle: 'sa_fee_squiggle'.tr,
          title: 'sa_fee_title'.tr,
          subtitle: 'sa_fee_sub'.tr,
          actions: (onHero) => AuthSwitches(onHero: onHero),
          body: (context, wide) => _s == null
              ? (_error != null
                  ? AppErrorState(
                      title: t('تعذّر تحميل رسوم الحساب', 'Could not load the account fee'),
                      message: _error,
                      onRetry: _load,
                      compact: true)
                  : const AppListSkeleton(items: 2))
              : AccountFeeView(
                  status: _s!,
                  method: _method,
                  busy: _busy,
                  onMethod: (m) => setState(() => _method = m),
                  onPayCard: _payCard,
                  onPayTransfer: _payTransfer,
                  onCheck: _load,
                  onSignOut: _signOut,
                ),
        ),
      ),
    );
  }
}

/// The page's content from plain values (what the layout harness tests): the price on the area's dark card with
/// its "one time" tag, the payment methods as tiles, ONE forward button and two quiet links. It sits in the auth card.
class AccountFeeView extends StatelessWidget {
  final Map<String, dynamic> status;
  final String? method;
  final bool busy;
  final ValueChanged<String> onMethod;
  final VoidCallback onPayCard, onPayTransfer, onCheck, onSignOut;

  const AccountFeeView({
    super.key,
    required this.status,
    required this.method,
    required this.busy,
    required this.onMethod,
    required this.onPayCard,
    required this.onPayTransfer,
    required this.onCheck,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final price = money(status['amount'], '${status['currency'] ?? ''}');
    final p = asMap(status['payment']);
    final st = '${p['status'] ?? ''}';
    final methods = asMapList(status['methods']);
    final isCard = methods.any((m) => m['id'] == method && m['kind'] == 'card');
    final ink = AppAreaScope.of(context).ink;
    Widget link(String key, String label, VoidCallback onTap, Color color) => TextButton(
          key: ValueKey(key),
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: color),
          child: Text(label, style: AppType.bodyStrong(context).copyWith(color: color)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // the price on the area's dark card, the "one time" tag slapped on it
      AppCard(
        variant: AppCardVariant.dark,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('sa_fee_label'.tr, style: AppType.label(context).copyWith(color: c.onHeroMuted)),
              const SizedBox(height: AppSpace.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(price,
                    key: const ValueKey('account_fee.price'), style: AppType.display(context).copyWith(color: c.onHero)),
              ),
            ]),
          ),
          const SizedBox(width: AppSpace.sm),
          AppSlap(child: AppStatusBadge(label: 'sa_fee_once'.tr, accent: AppAccent.sun)),
        ]),
      ),
      AppSpace.gapMd,
      if (st == 'review')
        AppBanner(
            icon: Icons.hourglass_top_rounded,
            color: c.warning,
            text: t('استلمنا إيصال التحويل وهو قيد المراجعة. سيفتح حسابك فور اعتماده.',
                'We received your receipt and it is being reviewed. Your account opens once it is approved.'))
      else ...[
        if (st == 'rejected' || st == 'failed')
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppBanner(
                icon: Icons.info_outline_rounded,
                color: c.danger,
                text: st == 'rejected'
                    ? t('لم يُقبل الإيصال السابق${p['review_note'] != null ? ': ${p['review_note']}' : ''} — جرّب مرة أخرى.',
                        'The previous receipt was not accepted${p['review_note'] != null ? ': ${p['review_note']}' : ''} — please try again.')
                    : t('لم تكتمل عملية الدفع السابقة — جرّب مرة أخرى.', 'The previous payment did not go through — please try again.')),
          ),
        if (methods.isEmpty)
          AppBanner(
              icon: Icons.info_outline_rounded,
              text: t('لا توجد طريقة دفع متاحة الآن — تواصل مع إدارة المنصة.',
                  'No payment method is available right now — please contact the platform team.'))
        else ...[
          // the methods the server offers for this country, as tiles (the chosen one ticked)
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 360 ? 3 : 2;
            final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
            return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final m in methods)
                SizedBox(
                  width: w,
                  child: _MethodTile(
                    key: ValueKey('account_fee.method.${m['id']}'),
                    label: t('${m['label_ar']}', '${m['label_en']}'),
                    selected: method == m['id'],
                    onTap: () => onMethod('${m['id']}'),
                  ),
                ),
            ]);
          }),
          AppSpace.gapLg,
          AppButton.hot(
            key: const ValueKey('account_fee.pay'),
            expand: true,
            size: AppButtonSize.lg,
            label: isCard ? 'sa_fee_pay'.tr.replaceAll('{price}', price) : t('أرسل إيصال التحويل', 'Send the transfer receipt'),
            busy: busy,
            onPressed: busy || method == null ? null : (isCard ? onPayCard : onPayTransfer),
          ),
        ],
      ],
      AppSpace.gapXs,
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        link('account_fee.check', 'sa_fee_check'.tr, onCheck, ink),
        ExcludeSemantics(child: Text('•', style: AppType.meta(context).copyWith(color: c.textLight))),
        link('account_fee.sign_out', 'sa_appr_sign_out'.tr, onSignOut, c.kit.error.ink),
      ]),
    ]);
  }
}

/// One payment method: a tile with a radio mark on top and the method's name; the chosen one is ticked on the
/// area's tint with its edge.
class _MethodTile extends StatelessWidget {
  const _MethodTile({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final radius = BorderRadius.circular(AppRadius.tile);
    return Semantics(
      selected: selected,
      button: true,
      child: AppJelly(
        wide: true,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: selected ? set.a : c.kit.line, width: selected ? AppBorder.focus : AppBorder.strong),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: selected
                  ? BoxDecoration(gradient: LinearGradient(colors: [c.cardBg, set.tint]))
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ExcludeSemantics(
                  child: Container(
                    width: AppIconSize.lg,
                    height: AppIconSize.lg,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? set.ink : null,
                      border: selected ? null : Border.all(color: c.kit.fieldEdge, width: AppBorder.strong),
                    ),
                    child: selected ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.cardBg) : null,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
