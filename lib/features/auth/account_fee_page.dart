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
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import '../org/org_creation_fee.dart' show money, showFeeTransferSheet;
import '../org/org_v3.dart' show OrgCall, orgCall, orgErrorText;
import 'auth_provider.dart';

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
                                title: t('تعذّر تحميل رسوم الحساب', 'Could not load the account fee'),
                                message: _error,
                                onRetry: _load,
                                compact: true))
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
          ),
        ),
      ),
    );
  }
}

/// The page's content from plain values (what the layout harness tests).
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
    final parent = status['role'] == 'parent';
    final price = money(status['amount'], '${status['currency'] ?? ''}');
    final p = asMap(status['payment']);
    final st = '${p['status'] ?? ''}';
    final methods = asMapList(status['methods']);
    final isCard = methods.any((m) => m['id'] == method && m['kind'] == 'card');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        highlight: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.controlAll),
              child: Icon(parent ? Icons.family_restroom_rounded : Icons.cast_for_education_rounded,
                  color: c.primary, size: AppIconSize.lg),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('فعّل حسابك', 'Activate your account'), style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                    parent
                        ? t('رسوم لمرة واحدة لفتح حساب ولي الأمر ومتابعة أبنائك.', 'A one-time fee to open your parent account and follow your children.')
                        : t('رسوم لمرة واحدة لفتح حساب المعلم ونشر كورساتك.', 'A one-time fee to open your teacher account and publish your courses.'),
                    style: AppType.meta(context)),
              ]),
            ),
          ]),
          AppSpace.gapMd,
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(price, key: const ValueKey('account_fee.price'), style: AppType.display(context).copyWith(color: c.primary)),
            ),
          ),
          Center(child: Text(t('تُدفع مرة واحدة فقط', 'Paid once only'), style: AppType.meta(context))),
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
              Text(t('اختر طريقة الدفع', 'Choose how to pay'), style: AppType.label(context)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final m in methods)
                  AppChoiceChip(
                    key: ValueKey('account_fee.method.${m['id']}'),
                    label: t('${m['label_ar']}', '${m['label_en']}'),
                    icon: m['kind'] == 'card' ? Icons.credit_card_rounded : Icons.account_balance_rounded,
                    selected: method == m['id'],
                    onTap: () => onMethod('${m['id']}'),
                  ),
              ]),
              AppSpace.gapSm,
              AppPrimaryButton(
                key: const ValueKey('account_fee.pay'),
                label: isCard ? t('ادفع $price', 'Pay $price') : t('أرسل إيصال التحويل', 'Send the transfer receipt'),
                icon: isCard ? Icons.lock_rounded : Icons.upload_rounded,
                busy: busy,
                onPressed: busy || method == null ? null : (isCard ? onPayCard : onPayTransfer),
              ),
            ],
          ],
        ]),
      ),
      AppSpace.gapSm,
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
        TextButton.icon(
          key: const ValueKey('account_fee.check'),
          onPressed: onCheck,
          icon: const Icon(Icons.refresh_rounded, size: AppIconSize.md),
          label: Text(t('دفعت؟ تحقّق الآن', 'Paid? Check now')),
        ),
        TextButton.icon(
          key: const ValueKey('account_fee.sign_out'),
          onPressed: onSignOut,
          icon: Icon(DirIcons.logout, size: AppIconSize.md),
          label: Text(t('تسجيل الخروج', 'Sign out')),
        ),
      ]),
    ]);
  }
}
