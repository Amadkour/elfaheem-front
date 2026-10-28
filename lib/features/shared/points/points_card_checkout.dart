// lib/features/shared/points/points_card_checkout.dart — buying points by card (docs/backend/live-rooms-spec.md
// Part 3 §13).
//
//   runCardTopup(context, api, checkout)   the whole card flow after `POST /me/points/checkout`: opens the
//                                          provider's payment page exactly like the course checkout does
//                                          (MobileCheckoutPage's WebView on phones, IFrameCheckoutPage on the web —
//                                          both pop the result page's status), then the status sheet polls
//                                          `GET /me/points/topups/{id}` until approved / rejected. True = credited.
//   CardTopupSheet                         the polling sheet (pollTopup, a timeout, "Check again").
//   CardTopupStatusView                    its plain-values body (test/ui/points_layout_test.dart).
//
// Strings: t(ar, en). The points are credited by the server's verified provider callback, never by this screen.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../student/enrollment/checkout_pages.dart' show MobileCheckoutPage;
import '../../student/enrollment/checkout_web_impl.dart'
    if (dart.library.io) '../../student/enrollment/checkout_stub_impl.dart' show IFrameCheckoutPage;
import 'points_api.dart';

/// How long the sheet waits for the provider's confirmation before it offers "Check again".
const Duration kCardTopupWait = Duration(minutes: 2);

/// How long one "Check again" waits.
const Duration kCardTopupRecheck = Duration(seconds: 30);

/// Opens the provider's payment page (the course checkout's pages) and returns the result page's status:
/// `paid` · `initiated` · `failed` · `cancelled` (closed by the person).
Future<String> openPointsPaymentPage(BuildContext context, String url) async {
  final Widget page = kIsWeb ? IFrameCheckoutPage(url: url) : MobileCheckoutPage(url: url);
  final r = await Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
  return r ?? 'cancelled';
}

/// The card flow after the checkout call. True once the points were credited.
Future<bool> runCardTopup(BuildContext context, PointsApi api, PointsCheckout checkout) async {
  if (checkout.alreadyPaid) {
    appToast(t('أُضيفت النقاط إلى رصيدك', 'The points were added to your balance'));
    return true;
  }
  if (!checkout.canOpen) {
    appToast(pointsCodeText('checkout_failed')!);
    return false;
  }
  final status = await openPointsPaymentPage(context, checkout.checkoutUrl);
  if (!context.mounted) return false;
  final ok = await showAppSheet<bool>(
    context,
    (_) => CardTopupSheet(
      api: api,
      topupId: checkout.topupId,
      points: checkout.points,
      // Closed without paying: one quick read (it may still have gone through), then "Check again".
      wait: status == 'cancelled' ? Duration.zero : kCardTopupWait,
    ),
  );
  return ok == true;
}

/// Where the card top-up stands on the status sheet.
enum CardTopupPhase { checking, approved, rejected, waiting, error }

CardTopupPhase cardTopupPhaseOf(TopupPollResult r) {
  if (r.approved) return CardTopupPhase.approved;
  if (r.rejected) return CardTopupPhase.rejected;
  if (r.topup == null && r.error != null) return CardTopupPhase.error;
  return CardTopupPhase.waiting;
}

class CardTopupSheet extends StatefulWidget {
  const CardTopupSheet({
    super.key,
    required this.api,
    required this.topupId,
    this.points = 0,
    this.wait = kCardTopupWait,
    this.every = const Duration(seconds: 3),
  });

  final PointsApi api;
  final int topupId;
  final int points;
  final Duration wait;
  final Duration every;

  @override
  State<CardTopupSheet> createState() => _CardTopupSheetState();
}

class _CardTopupSheetState extends State<CardTopupSheet> {
  CardTopupPhase _phase = CardTopupPhase.checking;
  PointsTopup? _topup;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll(widget.wait);
  }

  Future<void> _poll(Duration wait) async {
    setState(() {
      _phase = CardTopupPhase.checking;
      _error = null;
    });
    final r = await pollTopup(() => widget.api.topup(widget.topupId),
        every: widget.every, timeout: wait, cancelled: () => !mounted);
    if (!mounted) return;
    setState(() {
      _topup = r.topup ?? _topup;
      _phase = cardTopupPhaseOf(r);
      _error = r.error == null ? null : pointsErrorText(r.error!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final x = _topup;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('الدفع بالبطاقة', 'Card payment')),
        CardTopupStatusView(
          phase: _phase,
          points: x?.points ?? widget.points,
          amountText: x == null || x.amount <= 0 ? null : x.amountText,
          reason: x?.failureReason ?? x?.note,
          error: _error,
          onCheckAgain: () => _poll(kCardTopupRecheck),
          onClose: () => Navigator.pop(context, _phase == CardTopupPhase.approved),
        ),
      ]),
    );
  }
}

/// The status sheet's body with plain values.
class CardTopupStatusView extends StatelessWidget {
  const CardTopupStatusView({
    super.key,
    required this.phase,
    this.points = 0,
    this.amountText,
    this.reason,
    this.error,
    this.onCheckAgain,
    this.onClose,
  });

  final CardTopupPhase phase;
  final int points;
  final String? amountText;

  /// The provider's reason of a rejected payment (the top-up's `note`).
  final String? reason;
  final String? error;
  final VoidCallback? onCheckAgain, onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final what = [if (points > 0) '$points ${t('نقطة', 'points')}', ?amountText].join(' · ');
    final (IconData icon, Color color, String title, String body) = switch (phase) {
      CardTopupPhase.checking => (
          Icons.hourglass_top_rounded,
          c.primary,
          t('نتأكد من الدفع…', 'Confirming your payment…'),
          t('ننتظر تأكيد مزوّد الدفع؛ لا تغلق التطبيق.', 'Waiting for the payment provider to confirm it; keep the app open.'),
        ),
      CardTopupPhase.approved => (
          Icons.check_circle_rounded,
          c.success,
          t('تم الدفع', 'Payment confirmed'),
          t('أُضيفت النقاط إلى رصيدك.', 'The points were added to your balance.'),
        ),
      CardTopupPhase.rejected => (
          Icons.cancel_rounded,
          c.danger,
          t('لم يكتمل الدفع', 'The payment did not go through'),
          (reason ?? '').trim().isEmpty
              ? t('لم تُخصم أي نقاط ولم يُضف شيء إلى رصيدك. يمكنك المحاولة مرة أخرى.',
                  'Nothing was added to your balance. You can try again.')
              : reason!.trim(),
        ),
      CardTopupPhase.waiting => (
          Icons.schedule_rounded,
          c.warning,
          t('لم يصل التأكيد بعد', 'No confirmation yet'),
          t('إن أتممت الدفع فقد يستغرق التأكيد دقيقة. تُضاف النقاط تلقائياً فور التأكيد.',
              'If you completed the payment, the confirmation can take a minute. The points are added as soon as it arrives.'),
        ),
      CardTopupPhase.error => (
          Icons.wifi_off_rounded,
          c.danger,
          t('تعذّر التحقق من الدفع', 'The payment could not be checked'),
          error ?? t('تحقق من الاتصال ثم أعد المحاولة.', 'Check the connection and try again.'),
        ),
    };
    final canRecheck = phase == CardTopupPhase.waiting || phase == CardTopupPhase.error;
    return Column(
      key: ValueKey('card_topup.${phase.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
            child: Icon(icon, color: color, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: appText(17, w: FontWeight.w800, c: c.textDark)),
        if (what.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(what, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.textMedium)),
        ],
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium, h: 1.5)),
        if (phase == CardTopupPhase.checking) ...[
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(minHeight: 4, color: c.primary)),
        ],
        if (phase == CardTopupPhase.waiting && error != null) ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
        ],
        const SizedBox(height: 18),
        if (canRecheck)
          AppPrimaryButton(
            key: const ValueKey('card_topup.check_again'),
            label: t('تحقق مرة أخرى', 'Check again'),
            icon: Icons.refresh_rounded,
            onPressed: onCheckAgain,
          ),
        if (phase != CardTopupPhase.checking)
          TextButton(
            key: const ValueKey('card_topup.close'),
            onPressed: onClose,
            child: Text(phase == CardTopupPhase.approved ? t('تم', 'Done') : t('إغلاق', 'Close')),
          ),
      ],
    );
  }
}
