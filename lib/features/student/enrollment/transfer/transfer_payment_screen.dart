/// transfer_payment_screen.dart — bank-transfer / InstaPay proof submission.
///
/// Open from the enrollment method picker:
///   final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
///     builder: (_) => TransferPaymentScreen(
///       courseId: course.id, method: 'bank_transfer',
///       plan: enroll.selectedPlan,
///       amount: quote.total, currencySymbol: enroll.currencySymbol)));
///   if (ok == true) enroll.setStep(EnrollStep.pending);
///
/// Needs the `image_picker` package (add to pubspec.yaml if not present).
library;

import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/clickable_text.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../enrollment_models.dart';
import '../enrollment_widgets.dart';
import 'transfer_payment_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;

class TransferPaymentScreen extends StatelessWidget {
  final int courseId;
  final String method; // "bank_transfer" | "instapay"
  final String plan; // "monthly" | "six_months" | "yearly" — sent with the proof
  final double amount; // the quote TOTAL (plan price + fees) the student must transfer
  final String currencySymbol;

  const TransferPaymentScreen({
    super.key,
    required this.courseId,
    required this.method,
    required this.plan,
    required this.amount,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
      TransferPaymentProvider(courseId: courseId, method: method, plan: plan)
        ..loadDetails(),
      child: _TransferView(amount: amount, currencySymbol: currencySymbol),
    );
  }
}

class _TransferView extends StatefulWidget {
  final double amount;
  final String currencySymbol;

  const _TransferView({required this.amount, required this.currencySymbol});

  @override
  State<_TransferView> createState() => _TransferViewState();
}

class _TransferViewState extends State<_TransferView> {
  final _senderNameCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ── Smart "send within 2 minutes" attention timer ──────────────────────
  // Starts counting down the moment the screen is shown (the assumption is
  // the transfer to the bank/InstaPay account is made right after seeing the
  // receiving details). The banner escalates from a neutral warning to an
  // urgent one, and finally to an "expired" state, without blocking submit.
  // The length of the window is set by the ADMIN per method (Admin → Payment methods →
  // requirements.transfer_window_minutes; 0 = no timer), so the countdown can only start once the
  // method's details have been loaded.
  int _totalSeconds = 0;
  int _remainingSeconds = 0;
  bool _timerStarted = false;
  Timer? _warningTimer;

  void _startTimer(int minutes) {
    _timerStarted = true;
    _totalSeconds = minutes * 60;
    _remainingSeconds = _totalSeconds;
    if (_totalSeconds <= 0) return; // admin turned the timer off
    _warningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  @override
  void dispose() {
    _warningTimer?.cancel();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(TransferPaymentProvider p) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) await p.setProofImage(picked);
  }

  Future<void> _submit(TransferPaymentProvider p) async {
    if (!_formKey.currentState!.validate()) return;
    final details = p.details;
    if (details != null && _amountProblem(details.requirementsFor(p.isBankTransfer)) != null) return;
    final ok = await p.submit(
      senderName: _senderNameCtrl.text.trim(),
      senderPhone: _senderPhoneCtrl.text.trim(),
      transferReference: _referenceCtrl.text.trim(),
    );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  /// "Label *" when the admin made the field mandatory, "Label (optional)" otherwise.
  String _fieldLabel(String key, bool required) =>
      required ? '${key.tr} *' : '${key.tr} (${'optional'.tr})';

  /// The amount the student has to transfer must be inside the admin's min / max for this method.
  String? _amountProblem(TransferRequirements r) {
    String money(double v) => '${v.toStringAsFixed(2)} ${widget.currencySymbol}';
    final min = r.minAmount, max = r.maxAmount;
    if (min != null && widget.amount < min) {
      return 'transfer_amount_below_min'.tr.replaceAll('{amount}', money(min));
    }
    if (max != null && widget.amount > max) {
      return 'transfer_amount_above_max'.tr.replaceAll('{amount}', money(max));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TransferPaymentProvider>();
    final c = context.colors;
    final d = p.details;
    // What the ADMIN requires for the method the student picked (Admin → Payment methods).
    final req = d?.requirementsFor(p.isBankTransfer) ?? const TransferRequirements();
    final amountProblem = d == null ? null : _amountProblem(req);
    if (d != null && !_timerStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_timerStarted) setState(() => _startTimer(req.transferWindowMinutes));
      });
    }

    return EnrollScaffold(
      child: Center(
        child: Column(
          children: [
            enrollAppBar(
              p.isBankTransfer
                  ? 'transfer_bank_title'.tr
                  : 'transfer_instapay_title'.tr,
            ),
            Expanded(
              child: d == null
                  ? const AppListSkeleton(items: 4, withAvatar: false)
                  : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReceivingDetailsCard(
                        details: d,
                        isBankTransfer: p.isBankTransfer,
                        amount: widget.amount,
                        currencySymbol: widget.currencySymbol,
                      ),
                      const SizedBox(height: 16),
                      if (amountProblem != null) ...[
                        _AmountProblemBanner(message: amountProblem),
                        const SizedBox(height: 16),
                      ],
                      if (_totalSeconds > 0)
                        _TransferTimeWarningBanner(
                          remainingSeconds: _remainingSeconds,
                          totalSeconds: _totalSeconds,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'transfer_details_title'.tr,
                        style: c.h3.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _senderNameCtrl,
                        decoration: InputDecoration(
                          labelText: 'sender_name_label'.tr,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'required'.tr
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _senderPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: _fieldLabel('sender_phone_field', req.requireSenderPhone),
                        ),
                        validator: (v) => (req.requireSenderPhone && (v == null || v.trim().isEmpty))
                            ? 'required'.tr
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _referenceCtrl,
                        decoration: InputDecoration(
                          labelText: _fieldLabel(
                            p.isBankTransfer ? 'bank_reference_field' : 'instapay_reference_field',
                            req.requireTransferReference,
                          ),
                        ),
                        validator: (v) => (req.requireTransferReference && (v == null || v.trim().isEmpty))
                            ? 'required'.tr
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'transfer_receipt_image_label'.tr,
                        style: c.h3.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 12),
                      _ProofImagePicker(
                        image: p.proofImage,
                        onTap: () => _pickImage(p),
                        bytes: p.proofImageBytes,
                      ),
                      if (p.step == TransferSubmitStep.failed &&
                          p.failureReason != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          p.failureReason!,
                          style: c.body.copyWith(color: c.danger),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            EnrollConfirmBar(
              label: 'submit_transfer_proof_btn'.tr,
              loading: p.step == TransferSubmitStep.submitting,
              onTap: (d == null || amountProblem != null) ? null : () => _submit(p),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountProblemBanner extends StatelessWidget {
  final String message;

  const _AmountProblemBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.danger.withValues(alpha: .25)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: c.danger, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: c.caption.copyWith(color: c.danger, height: 1.5))),
      ]),
    );
  }
}

/// A live, self-updating attention banner that reminds the user to submit
/// the transfer proof within [totalSeconds] of sending the money.
///
/// It has three states:
///  • Normal  (> 30s left)  — a calm amber reminder with a live countdown.
///  • Urgent  (<= 30s left) — turns red and adds a pulsing icon.
///  • Expired (0s left)     — swaps the countdown for a clear "time's up"
///    message, still allowing submission (never blocks the user).
class _TransferTimeWarningBanner extends StatefulWidget {
  final int remainingSeconds;
  final int totalSeconds;

  const _TransferTimeWarningBanner({
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  @override
  State<_TransferTimeWarningBanner> createState() =>
      _TransferTimeWarningBannerState();
}

class _TransferTimeWarningBannerState
    extends State<_TransferTimeWarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _pulseController, reverse: true); // reduce motion parks this decorative loop
  }

  @override
  void dispose() {
    // _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final remaining = widget.remainingSeconds;
    final expired = remaining <= 0;
    final urgent = remaining <= 30 && !expired;

    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final progress = (remaining / widget.totalSeconds).clamp(0.0, 1.0);

    // Neutral (amber-ish) vs urgent/expired (danger) palette, derived from
    // the app's existing color tokens so the banner matches the theme.
    final Color accent = (urgent || expired)
        ? c.danger
        : context.colors.warning;
    final Color bg = accent.withValues(alpha: expired ? .14 : .10);
    final Color border = accent.withValues(alpha: expired ? .5 : .3);

    Widget icon = Icon(
      expired ? Icons.error_rounded : Icons.timer_rounded,
      color: accent,
      size: 22,
    );
    if (urgent || expired) {
      icon = FadeTransition(opacity: _pulseController, child: icon);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'transfer_time_warning_n'.tr.replaceAll(
                    '{time}',
                    '${widget.totalSeconds ~/ 60} ${'minutes'.tr}',
                  ),
                  style: c.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (expired)
            Text(
              'transfer_time_expired'.tr,
              style: c.label.copyWith(color: accent, fontWeight: FontWeight.w800),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: accent.withValues(alpha: .15),
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$minutes:$seconds',
                  style: c.label.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReceivingDetailsCard extends StatelessWidget {
  final TransferMethodDetails details;
  final bool isBankTransfer;
  final double amount;
  final String currencySymbol;

  const _ReceivingDetailsCard({
    required this.details,
    required this.isBankTransfer,
    required this.amount,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = isBankTransfer
        ? {
      'bank_name_row_label'.tr: details.bankName,
      'account_name_row_label'.tr: details.accountName,
      'iban_row_label'.tr: details.iban,
      'swift_row_label'.tr: details.swiftCode,
    }
        : {'instapay_id_row_label'.tr: details.instapayId};
    final instructions = isBankTransfer
        ? details.bankInstructions
        : details.instapayInstructions;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.primary.withValues(alpha: .15)),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('required_money'.tr, style: c.body),
              Text(
                '${amount.toStringAsFixed(2)} $currencySymbol',
                style: c.h2.copyWith(color: c.primary, fontSize: 18),
              ),
            ],
          ),
          const Divider(height: 24),
          for (final e in rows.entries)
            if (e.value != null && e.value!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: c.caption),
                    SelectableText(
                      e.value!,
                      style: c.label.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          if (instructions != null && instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClickableText(text: instructions),
          ],
        ],
      ),
    );
  }
}

class _ProofImagePicker extends StatelessWidget {
  final XFile? image;
  final Uint8List? bytes;
  final VoidCallback onTap;

  const _ProofImagePicker({
    required this.image,
    required this.onTap,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.divider),
        ),
        child: image == null
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded, color: c.textLight, size: 32),
            const SizedBox(height: 8),
            Text('tap_attach_receipt'.tr, style: c.caption),
          ],
        )
            : ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            bytes!,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
      ),
    );
  }
}