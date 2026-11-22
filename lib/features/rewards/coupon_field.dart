// lib/features/rewards/coupon_field.dart — the coupon box of the three checkouts (Games v3 §3.2, CONTRACT §7; kill
// switch `rewards.coupons`): the course payment page, the package join sheet and the store checkout.
//
//   CouponFieldController  the logic: closed → open (my active coupons load once, GET /me/rewards) → checking
//                          (POST /coupons/quote) → applied (the discount) or error (the coded refusal's bilingual
//                          text, core/api_error_text.dart couponErrorText). [onChanged] hands the checkout the applied
//                          quote (its code goes into the checkout call) or null.
//   CouponField            the widget the checkouts drop in (one controller per checkout, made from the target)
//   CouponFieldView        the body with plain values (test/ui/coupon_field_test.dart)
//
// One coupon per order (O8). A typed code is trimmed and upper-cased; a code that cannot be one (not 10 characters of
// the code alphabet) is refused on the device without a request.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/rewards/rewards_api.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';

enum CouponPhase { closed, open, checking, applied, error }

typedef CouponQuoteFn = Future<CouponQuote> Function(String code);
typedef CouponMineFn = Future<List<Coupon>> Function();

class CouponFieldController extends ChangeNotifier {
  CouponFieldController({required CouponQuoteFn quote, CouponMineFn? mine, this.onChanged})
      : _quote = quote,
        _mine = mine;

  CouponQuoteFn _quote;
  final CouponMineFn? _mine;

  /// The applied quote, or null when the coupon was removed / refused.
  final ValueChanged<CouponQuote?>? onChanged;

  CouponPhase phase = CouponPhase.closed;
  String? error;
  CouponQuote? quote;
  List<Coupon> mine = const [];
  bool mineLoaded = false;
  String _lastCode = '';
  int _seq = 0;
  bool _disposed = false;

  /// The code the checkout sends (null = none applied).
  String? get appliedCode => phase == CouponPhase.applied ? quote?.coupon.code ?? _lastCode : null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Opens the box and loads my active coupons once (a failure only means no list to pick from).
  Future<void> open() async {
    if (phase == CouponPhase.closed) {
      phase = CouponPhase.open;
      _notify();
    }
    final load = _mine;
    if (mineLoaded || load == null) return;
    mineLoaded = true;
    try {
      final now = DateTime.now().toUtc();
      final all = await load();
      mine = [for (final c in all) if (c.usableAt(now)) c];
    } catch (_) {
      mine = const [];
    }
    _notify();
  }

  /// Checks [raw] against this purchase. Returns true when it applied.
  Future<bool> apply(String raw) async {
    final code = normalizeCouponCode(raw);
    if (code.isEmpty) {
      return _fail(t('اكتب رمز القسيمة أو اختر واحدة من قسائمك', 'Type a coupon code or pick one of your coupons'));
    }
    if (!kCouponCodeShape.hasMatch(code)) {
      return _fail(t('رمز القسيمة 10 أحرف وأرقام إنجليزية', 'A coupon code is 10 English letters and digits'));
    }
    final seq = ++_seq;
    _lastCode = code;
    phase = CouponPhase.checking;
    error = null;
    _notify();
    try {
      final q = await _quote(code);
      if (seq != _seq || _disposed) return false;
      quote = q;
      phase = CouponPhase.applied;
      _notify();
      onChanged?.call(q);
      return true;
    } catch (e) {
      if (seq != _seq || _disposed) return false;
      final had = quote != null;
      quote = null;
      phase = CouponPhase.error;
      error = rewardsErrorText(e);
      _notify();
      if (had) onChanged?.call(null);
      return false;
    }
  }

  bool _fail(String text) {
    final had = quote != null;
    quote = null;
    phase = CouponPhase.error;
    error = text;
    _notify();
    if (had) onChanged?.call(null);
    return false;
  }

  /// Takes the coupon off the purchase (the box stays open).
  void remove() {
    ++_seq;
    final had = quote != null;
    quote = null;
    error = null;
    _lastCode = '';
    phase = CouponPhase.open;
    _notify();
    if (had) onChanged?.call(null);
  }

  /// The purchase changed (another plan, another method): the applied code is checked again on the new [quote].
  Future<void> retarget(CouponQuoteFn quote) async {
    _quote = quote;
    if (phase == CouponPhase.applied && _lastCode.isNotEmpty) await apply(_lastCode);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The coupon box for one purchase. [target] + [targetId] / [plan] / [itemIds] say what is bought; when any of them
/// changes an applied coupon is checked again. Draws nothing while `rewards.coupons` is off.
class CouponField extends StatefulWidget {
  const CouponField({
    super.key,
    required this.target,
    this.targetId,
    this.plan,
    this.itemIds,
    this.onChanged,
    this.api,
    this.enabled = true,
  });

  final CouponTarget target;
  final int? targetId;
  final String? plan;
  final List<int>? itemIds;
  final ValueChanged<CouponQuote?>? onChanged;
  final RewardsApi? api;
  final bool enabled;

  @override
  State<CouponField> createState() => _CouponFieldState();
}

class _CouponFieldState extends State<CouponField> {
  late final RewardsApi _api = widget.api ?? RewardsApi();
  late final CouponFieldController _c = CouponFieldController(
    quote: _quoteFn(),
    mine: () async => (await _api.mine()).coupons,
    onChanged: (q) => widget.onChanged?.call(q),
  );
  final _text = TextEditingController();

  CouponQuoteFn _quoteFn() {
    final target = widget.target, id = widget.targetId, plan = widget.plan, items = widget.itemIds;
    return (code) => _api.quote(code, target: target, targetId: id, plan: plan, itemIds: items);
  }

  @override
  void didUpdateWidget(CouponField old) {
    super.didUpdateWidget(old);
    final items = '${widget.itemIds}' != '${old.itemIds}';
    if (old.targetId != widget.targetId || old.plan != widget.plan || items || old.target != widget.target) {
      _c.retarget(_quoteFn());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (couponsOff()) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => CouponFieldView(
        phase: _c.phase,
        controller: _text,
        mine: _c.mine,
        quote: _c.quote,
        error: _c.error,
        enabled: widget.enabled,
        onOpen: _c.open,
        onApply: () => _c.apply(_text.text),
        onPick: (c) {
          _text.text = c.code;
          _c.apply(c.code);
        },
        onRemove: () {
          _text.clear();
          _c.remove();
        },
      ),
    );
  }
}

class CouponFieldView extends StatelessWidget {
  const CouponFieldView({
    super.key,
    required this.phase,
    required this.controller,
    this.mine = const [],
    this.quote,
    this.error,
    this.enabled = true,
    this.onOpen,
    this.onApply,
    this.onPick,
    this.onRemove,
  });

  final CouponPhase phase;
  final TextEditingController controller;
  final List<Coupon> mine;
  final CouponQuote? quote;
  final String? error;
  final bool enabled;
  final VoidCallback? onOpen, onApply, onRemove;
  final ValueChanged<Coupon>? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (phase == CouponPhase.closed) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.ghost(
          key: const ValueKey('coupon.open'),
          label: t('لديك قسيمة خصم؟', 'Have a coupon?'),
          icon: Icons.local_offer_rounded,
          onPressed: enabled ? onOpen : null,
        ),
      );
    }
    final q = quote;
    if (phase == CouponPhase.applied && q != null) {
      return Container(
        key: const ValueKey('coupon.applied'),
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: appToneColor(context, AppTone.success).withValues(alpha: 0.08),
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: appToneColor(context, AppTone.success), width: AppBorder.hairline),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: appInk(context, appToneColor(context, AppTone.success))),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                t('خصم ${rewardsMoney(q.discount, q.currency)}', '${rewardsMoney(q.discount, q.currency)} off'),
                key: const ValueKey('coupon.discount'),
                style: AppType.bodyStrong(context),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(q.coupon.code, style: AppType.meta(context)),
              ),
              if (q.price > 0)
                Text(
                  t('السعر بعد الخصم ${rewardsMoney(q.priceAfter, q.currency)} قبل الرسوم',
                      'Price after the discount ${rewardsMoney(q.priceAfter, q.currency)} before fees'),
                  style: AppType.meta(context),
                ),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          AppButton.ghost(
            key: const ValueKey('coupon.remove'),
            label: t('إزالة', 'Remove'),
            onPressed: enabled ? onRemove : null,
          ),
        ]),
      );
    }
    final busy = phase == CouponPhase.checking;
    return Column(key: const ValueKey('coupon.box'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (mine.isNotEmpty) ...[
        AppFieldLabel(t('قسائمي', 'My coupons')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final m in mine.take(6))
            AppChoiceChip(
              key: ValueKey('coupon.mine.${m.id}'),
              icon: Icons.local_offer_rounded,
              label: m.valueText,
              selected: normalizeCouponCode(controller.text) == m.code,
              onTap: busy || !enabled ? () {} : () => onPick?.call(m),
            ),
        ]),
        const SizedBox(height: AppSpace.sm),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AppField(
            key: const ValueKey('coupon.code'),
            controller: controller,
            label: mine.isEmpty ? t('رمز القسيمة', 'Coupon code') : t('أو اكتب رمزاً', 'Or type a code'),
            hint: 'K7M2PQ4XTH',
            ltr: true,
            enabled: enabled && !busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: 14,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]'))],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onApply?.call(),
            errorText: phase == CouponPhase.error ? error : null,
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: AppButton.secondary(
            key: const ValueKey('coupon.apply'),
            label: t('تطبيق', 'Apply'),
            busy: busy,
            onPressed: busy || !enabled ? null : onApply,
          ),
        ),
      ]),
      Text(t('قسيمة واحدة لكل طلب، وتُخصم قبل الرسوم والضريبة.', 'One coupon per order; it comes off before fees and VAT.'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
    ]);
  }
}
