// lib/features/store/store_checkout.dart — the cart and the checkout sheet of the digital store (D-1333).
//
//   StoreCart             the items picked on this device (in memory; the tab's cart button shows its count)
//   StoreLibraryBus       bumped after a paid order: My Library reloads
//   showStoreCheckout     the sheet for a list of items: POST /store/quote → the lines, the sums, the method →
//                         POST /store/orders with an Idempotency-Key (one UUID per attempt; a new one when the
//                         method changes or after a failure). Card opens the provider's page exactly like the points
//                         top-up (openPointsPaymentPage: WebView on phones, iframe on the web, the result page's
//                         `#/payment/callback?…&store_order=<id>` pops it), then GET /store/orders/{id} is polled
//                         until paid / failed. Points and free settle at once.
//   StoreCheckoutView     the sheet's body with plain values (test/ui/store_layout_test.dart)
//
// An order is never shown as paid on the payment page's word: only the server's order status counts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart' show openPointsPaymentPage;
import 'package:flutter_education_app/features/store/store_api.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/rewards/coupon_field.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart' show CouponQuote, CouponTarget;

/// The items picked on this device. In memory: a cart is a few taps, not something to keep across launches.
class StoreCart extends ValueNotifier<List<StoreItem>> {
  StoreCart._() : super(const []);

  static final StoreCart instance = StoreCart._();

  bool contains(int id) => value.any((e) => e.id == id);

  void add(StoreItem item) {
    if (item.owned || contains(item.id)) return;
    value = [...value, item];
  }

  void remove(int id) => value = [for (final e in value) if (e.id != id) e];

  void removeAll(Iterable<int> ids) {
    final s = ids.toSet();
    value = [for (final e in value) if (!s.contains(e.id)) e];
  }

  void clear() => value = const [];
}

/// Bumped after a paid order so My Library (and an item page) reload.
class StoreLibraryBus {
  StoreLibraryBus._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void changed() => revision.value++;
}

/// Where the checkout stands.
enum StoreCheckoutPhase { quoting, ready, paying, confirming, paid, failed, waiting, error }

/// Opens the checkout for [items]. True once an order was paid.
Future<bool> showStoreCheckout(BuildContext context, List<StoreItem> items, {StoreApi? api}) async {
  final r = await showAppSheet<bool>(context, (_) => StoreCheckoutSheet(items: items, api: api ?? StoreApi()));
  return r == true;
}

class StoreCheckoutSheet extends StatefulWidget {
  const StoreCheckoutSheet({super.key, required this.items, required this.api});

  final List<StoreItem> items;
  final StoreApi api;

  @override
  State<StoreCheckoutSheet> createState() => _StoreCheckoutSheetState();
}

class _StoreCheckoutSheetState extends State<StoreCheckoutSheet> {
  StoreCheckoutPhase _phase = StoreCheckoutPhase.quoting;
  StoreQuote? _quote;
  StoreOrder? _order;
  String? _error;
  String _method = 'card';

  /// One key per checkout attempt; reset when the method changes or the server refused the attempt (never on a
  /// timeout / lost connection, D-1339).
  String? _key;

  /// Games v3 (CONTRACT §7): the applied coupon's code; money (card) only, never with points.
  String? _coupon;

  List<int> get _ids => [for (final i in widget.items) i.id];

  /// The coupon box applied [q] or took it off: the sums are quoted again with it, quietly (the box stays).
  Future<void> _onCoupon(CouponQuote? q) async {
    final code = q?.coupon.code;
    if (code == _coupon) return;
    setState(() {
      _coupon = code;
      _key = null; // another price is another attempt
    });
    try {
      final quote = await widget.api.quote(_ids, couponCode: code);
      if (mounted && _coupon == code) setState(() => _quote = quote);
    } catch (e) {
      if (mounted) showAppNotice(storeErrorText(e), error: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _phase = StoreCheckoutPhase.quoting;
      _error = null;
    });
    try {
      final q = await widget.api.quote(_ids);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _method = q.isFree ? 'free' : 'card';
        _phase = StoreCheckoutPhase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = storeErrorText(e);
        _phase = StoreCheckoutPhase.error;
      });
    }
  }

  void _pickMethod(String m) {
    if (m == _method) return;
    final dropCoupon = m != 'card' && _coupon != null;
    setState(() {
      _method = m;
      _key = null;
    });
    if (dropCoupon) _onCoupon(null); // a coupon is money off: never with points
  }

  Future<void> _pay() async {
    if (offlineBlocked()) return; // money is never queued on the device (D-1351)
    final key = _key ??= newIdempotencyKey();
    setState(() {
      _phase = StoreCheckoutPhase.paying;
      _error = null;
    });
    try {
      final a = await widget.api.order(_ids, method: _method, idempotencyKey: key, couponCode: _method == 'card' ? _coupon : null);
      if (!mounted) return;
      _order = a.order;
      if (a.order.paid) return _settled(a.order);
      final c = a.checkout;
      if (_method != 'card' || c == null || !c.canOpen) {
        _key = null;
        return setState(() {
          _phase = StoreCheckoutPhase.failed;
          _error = storeFailureText(a.order.failureCode);
        });
      }
      final status = await openPointsPaymentPage(context, c.url);
      if (!mounted) return;
      await _confirm(wait: status == 'cancelled' ? Duration.zero : const Duration(minutes: 2));
    } catch (e) {
      if (!mounted) return;
      if (storeDefiniteAnswer(e)) _key = null; // a lost answer keeps the key: the retry finds the same order
      if (storeErrorCode(e) == 'store_already_owned') {
        // paid before (another device, an earlier attempt): it is in the library already
        StoreCart.instance.removeAll(_ids);
        StoreLibraryBus.changed();
        showAppNotice(storeErrorText(e));
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _error = storeErrorText(e);
        _phase = _quote == null ? StoreCheckoutPhase.error : StoreCheckoutPhase.ready;
      });
      showAppNotice(_error!, error: true);
    }
  }

  Future<void> _confirm({Duration wait = const Duration(seconds: 30)}) async {
    final id = _order?.id;
    if (id == null) return;
    setState(() => _phase = StoreCheckoutPhase.confirming);
    final o = await pollStoreOrder(() async => (await widget.api.orderById(id)).order, timeout: wait, cancelled: () => !mounted);
    if (!mounted) return;
    if (o != null && o.paid) return _settled(o);
    setState(() {
      _order = o ?? _order;
      if (o != null && o.done) {
        _key = null;
        _phase = StoreCheckoutPhase.failed;
        _error = storeFailureText(o.failureCode);
      } else {
        _phase = StoreCheckoutPhase.waiting;
      }
    });
  }

  void _settled(StoreOrder o) {
    StoreCart.instance.removeAll(_ids);
    StoreLibraryBus.changed();
    setState(() {
      _order = o;
      _phase = StoreCheckoutPhase.paid;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetContent(
      title: t('إتمام الشراء', 'Checkout'),
      icon: Icons.shopping_bag_rounded,
      children: [
        StoreCheckoutView(
          phase: _phase,
          quote: _quote,
          method: _method,
          pointsAllowed: _quote?.pointsTotal != null && !storePointsOff(),
          error: _error,
          onMethod: _pickMethod,
          coupon: _method == 'card' && _quote != null && !_quote!.isFree
              ? CouponField(
                  key: const ValueKey('store.checkout.coupon'),
                  target: CouponTarget.store,
                  itemIds: _ids,
                  enabled: _phase == StoreCheckoutPhase.ready,
                  onChanged: _onCoupon,
                )
              : null,
          onPay: storeBuyOff() ? null : _pay,
          onRetry: _quote == null ? _loadQuote : () => _confirm(),
          onDone: () => Navigator.of(context).pop(_phase == StoreCheckoutPhase.paid),
        ),
      ],
    );
  }
}

/// The checkout's body with plain values.
class StoreCheckoutView extends StatelessWidget {
  const StoreCheckoutView({
    super.key,
    required this.phase,
    this.quote,
    this.method = 'card',
    this.pointsAllowed = false,
    this.error,
    this.onMethod,
    this.onPay,
    this.onRetry,
    this.onDone,
    this.coupon,
  });

  /// The coupon box (Games v3), drawn under the sums while paying by card; null = none.
  final Widget? coupon;

  final StoreCheckoutPhase phase;
  final StoreQuote? quote;
  final String method;
  final bool pointsAllowed;
  final String? error;
  final ValueChanged<String>? onMethod;
  final VoidCallback? onPay, onRetry, onDone;

  @override
  Widget build(BuildContext context) {
    return switch (phase) {
      StoreCheckoutPhase.quoting => const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero),
      StoreCheckoutPhase.error => _outcome(context,
          icon: Icons.error_outline_rounded,
          tone: AppTone.danger,
          title: t('تعذّر تجهيز الطلب', 'The order could not be prepared'),
          body: error ?? t('أعد المحاولة.', 'Try again.'),
          primary: (t('أعد المحاولة', 'Try again'), onRetry)),
      StoreCheckoutPhase.paid => _outcome(context,
          icon: Icons.check_circle_rounded,
          tone: AppTone.success,
          title: t('تم الشراء', 'Purchase complete'),
          body: t('العناصر الآن في مكتبتك.', 'The items are now in your library.'),
          primary: (t('افتح مكتبتي', 'Open My Library'), onDone)),
      StoreCheckoutPhase.failed => _outcome(context,
          icon: Icons.cancel_rounded,
          tone: AppTone.danger,
          title: t('لم يكتمل الدفع', 'The payment did not go through'),
          body: (error ?? '').trim().isNotEmpty ? error!.trim() : t('لم يُخصم شيء. يمكنك المحاولة مرة أخرى.', 'Nothing was charged. You can try again.'),
          primary: (t('حاول مرة أخرى', 'Try again'), onPay),
          secondary: (t('إغلاق', 'Close'), onDone)),
      StoreCheckoutPhase.confirming => _outcome(context,
          icon: Icons.hourglass_top_rounded,
          tone: AppTone.brand,
          title: t('نتأكد من الدفع…', 'Confirming your payment…'),
          body: t('ننتظر تأكيد مزوّد الدفع؛ لا تغلق التطبيق.', 'Waiting for the payment provider to confirm it; keep the app open.'),
          progress: true),
      StoreCheckoutPhase.waiting => _outcome(context,
          icon: Icons.schedule_rounded,
          tone: AppTone.warning,
          title: t('لم يصل التأكيد بعد', 'No confirmation yet'),
          body: t('إن أتممت الدفع فقد يستغرق التأكيد دقيقة، وتظهر العناصر في مكتبتك فور وصوله.',
              'If you completed the payment, the confirmation can take a minute; the items appear in your library as soon as it arrives.'),
          primary: (t('تحقق مرة أخرى', 'Check again'), onRetry),
          secondary: (t('إغلاق', 'Close'), onDone)),
      StoreCheckoutPhase.ready || StoreCheckoutPhase.paying => _summary(context),
    };
  }

  Widget _summary(BuildContext context) {
    final c = context.colors;
    final q = quote!;
    final busy = phase == StoreCheckoutPhase.paying;
    Widget row(String label, String value, {bool strong = false, Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(label, style: strong ? AppType.bodyStrong(context) : AppType.body(context))),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end, style: strong ? AppType.bodyStrong(context) : AppType.body(context).copyWith(color: c.textMedium)),
            ),
          ]),
        );
    final payLabel = error != null && method == 'card' ? t('أعد المحاولة', 'Try again') : switch (method) {
      'free' => t('احصل عليه مجاناً', 'Get it free'),
      'points' => t('ادفع ${q.pointsTotal} نقطة', 'Pay ${q.pointsTotal} points'),
      _ => t('ادفع ${storeMoney(q.total, q.currency)}', 'Pay ${storeMoney(q.total, q.currency)}'),
    };
    return Column(
      key: const ValueKey('store.checkout.summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in q.lines)
          AppCard(
            margin: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(
                l.vatExempt || (q.vatAmount <= 0 && q.vatPercent <= 0)
                    ? (l.vatExempt ? '${storeMoney(l.gross, q.currency)} · ${t('معفى من الضريبة', 'VAT exempt')}' : storeMoney(l.gross, q.currency))
                    : '${t('الصافي', 'Net')} ${storeMoney(l.net, q.currency)} · ${t('الضريبة', 'VAT')} ${storeMoney(l.vat, q.currency)} · ${storeMoney(l.gross, q.currency)}',
                style: AppType.meta(context),
              ),
            ]),
          ),
        const SizedBox(height: AppSpace.xs),
        row(t('المجموع قبل الضريبة', 'Subtotal (net)'), storeMoney(q.subtotal, q.currency)),
        if (q.couponDiscount > 0)
          row(t('خصم القسيمة', 'Coupon discount'), '−${storeMoney(q.couponDiscount, q.currency)}', key: const ValueKey('store.checkout.coupon_discount')),
        // the VAT line only where the server charged one (payments.md §2: no VAT for a payer it does not apply to)
        if (q.vatAmount > 0 || q.vatPercent > 0)
        row('${t('ضريبة القيمة المضافة', 'VAT')} (${StorePrice(net: 0, vat: 0, gross: 0, currency: '', vatPercent: q.vatPercent).vatPercentText})',
            storeMoney(q.vatAmount, q.currency)),
        const Divider(height: AppSpace.md),
        row(t('الإجمالي', 'Total'), storeMoney(q.total, q.currency), strong: true, key: const ValueKey('store.checkout.total')),
        if (!q.isFree) ...[
          const SizedBox(height: AppSpace.md),
          AppFieldLabel(t('طريقة الدفع', 'Pay with')),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(
              key: const ValueKey('store.checkout.card'),
              label: t('بطاقة', 'Card'),
              icon: Icons.credit_card_rounded,
              selected: method == 'card',
              onTap: () => onMethod?.call('card'),
            ),
            if (pointsAllowed)
              AppChoiceChip(
                key: const ValueKey('store.checkout.points'),
                label: t('النقاط (${q.pointsTotal})', 'Points (${q.pointsTotal})'),
                icon: Icons.stars_rounded,
                selected: method == 'points',
                onTap: () => onMethod?.call('points'),
              ),
          ]),
        ],
        if (coupon != null) ...[
          const SizedBox(height: AppSpace.md),
          coupon!,
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
        ],
        const SizedBox(height: AppSpace.lg),
        if (onPay == null)
          AppBanner(icon: Icons.block_rounded, text: t('الشراء متوقف حالياً', 'Buying is switched off right now'), color: c.warning)
        else
          AppButton.primary(
            key: const ValueKey('store.checkout.pay'),
            label: payLabel,
            icon: Icons.lock_rounded,
            expand: true,
            busy: busy,
            onPressed: busy ? null : onPay,
          ),
      ],
    );
  }

  Widget _outcome(
    BuildContext context, {
    required IconData icon,
    required AppTone tone,
    required String title,
    required String body,
    (String, VoidCallback?)? primary,
    (String, VoidCallback?)? secondary,
    bool progress = false,
  }) {
    final c = context.colors;
    final color = appToneColor(context, tone);
    return Column(
      key: ValueKey('store.checkout.${phase.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: AppTouch.primary + AppSpace.xs,
            height: AppTouch.primary + AppSpace.xs,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
            child: Icon(icon, color: appInk(context, color), size: AppIconSize.xl),
          ),
        ),
        AppSpace.gapMd,
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, textAlign: TextAlign.center, style: AppType.headline(context)),
        ),
        AppSpace.gapXs,
        Text(body, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
        if (progress) ...[
          AppSpace.gapMd,
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(minHeight: AppSpace.xxs, color: c.primary, backgroundColor: c.primaryTint),
          ),
        ],
        if (primary != null) ...[
          AppSpace.gapLg,
          AppButton.primary(
              key: ValueKey('store.checkout.${phase.name}.primary'), label: primary.$1, expand: true, onPressed: primary.$2),
        ],
        if (secondary != null) ...[
          AppSpace.gapXs,
          AppButton.ghost(label: secondary.$1, expand: true, onPressed: secondary.$2),
        ],
      ],
    );
  }
}
