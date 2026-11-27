// lib/features/booking/booking_transfer_sheet.dart
//
// Bank transfer in booking (owner 2026-11-27, docs/redesign/api/booking.md "Owner decisions"): after "أكّد وادفع"
// with the bank transfer picked, the seat is held and this sheet shows where to send the money (the admin's bank
// details, each copyable) and the proof form: the sender's name, the phone and the reference when the admin requires
// them, and the receipt photo. Sent → the team reviews it; the booking shows "تحويلك قيد المراجعة".
//
//   BkTransferForm       the plain-values sheet body (bank rows, fields, the photo tile, the send button)
//   showBkTransferSheet  opens it over the flow; true once the proof was sent
//   showBkResendProof    the subject page's booking card: a held seat without a proof, or a rejected proof — asks
//                        the server for the bank details (pay with `bank_transfer`), then the same sheet
library;


import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/booking/booking_parts.dart' show bkFill;

/// The proof upload behind the sheet: null when sent, else the error text.
typedef BkSendProof = Future<String?> Function({
  required String senderName,
  String? senderPhone,
  String? reference,
  required String fileName,
  String? filePath,
  Uint8List? fileBytes,
});

/// Opens the proof sheet for the booking [c] just confirmed. True when the proof was sent.
Future<bool> showBkTransferSheet(BuildContext context, BkFlowController c) async {
  final r = await showAppSheet<bool>(
    context,
    (ctx) => ListenableBuilder(
      listenable: c,
      builder: (_, _) => _BkTransferSheet(
        info: c.transferInfo ?? const BkTransferInfo(),
        amount: c.price == null ? null : bkMoney(c.price!, c.currency),
        busy: c.busy,
        send: c.sendTransfer,
      ),
    ),
  );
  return r == true;
}

/// Sends (again) the proof of booking [b] from the subject page. True when the proof was sent; an error is shown.
Future<bool> showBkResendProof(BuildContext context, BkBooking b, {BookingApi? api}) async {
  final a = api ?? BookingApi();
  BkTransferInfo? info;
  try {
    info = (await a.pay(b.id, provider: kBkTransfer)).transfer;
  } catch (e) {
    showAppNotice(bkErrorText(e), error: true);
    return false;
  }
  if (!context.mounted) return false;
  Future<String?> send({
    required String senderName,
    String? senderPhone,
    String? reference,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    try {
      await a.sendTransfer(b.id,
          senderName: senderName,
          senderPhone: senderPhone,
          reference: reference,
          fileName: fileName,
          filePath: filePath,
          fileBytes: fileBytes);
      return null;
    } catch (e) {
      return bkErrorText(e);
    }
  }

  final r = await showAppSheet<bool>(
    context,
    (_) => _BkTransferSheet(
      info: info ?? const BkTransferInfo(),
      amount: b.price == null ? null : bkMoney(b.price!, b.currency),
      send: send,
    ),
  );
  if (r == true) showAppNotice('ow_transfer_sent'.tr);
  return r == true;
}

class _BkTransferSheet extends StatefulWidget {
  const _BkTransferSheet({required this.info, required this.send, this.amount, this.busy = false});

  final BkTransferInfo info;
  final String? amount;
  final bool busy;
  final BkSendProof send;

  @override
  State<_BkTransferSheet> createState() => _BkTransferSheetState();
}

class _BkTransferSheetState extends State<_BkTransferSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _ref = TextEditingController();
  XFile? _file;
  Uint8List? _bytes;
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
    if (x == null || !mounted) return;
    final b = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _file = x;
      _bytes = b;
      _error = null;
    });
  }

  Future<void> _send() async {
    final info = widget.info;
    final missing = _name.text.trim().isEmpty ||
        (info.needPhone && _phone.text.trim().isEmpty) ||
        (info.needReference && _ref.text.trim().isEmpty);
    if (missing) {
      setState(() => _error = 'ow_transfer_fill'.tr);
      return;
    }
    if (_file == null) {
      setState(() => _error = 'ow_transfer_photo_needed'.tr);
      return;
    }
    setState(() => _sending = true);
    final err = await widget.send(
      senderName: _name.text.trim(),
      senderPhone: _phone.text,
      reference: _ref.text,
      fileName: _file!.name,
      filePath: kIsWeb ? null : _file!.path,
      fileBytes: _bytes,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => BkTransferForm(
        info: widget.info,
        amount: widget.amount,
        name: _name,
        phone: _phone,
        reference: _ref,
        photoName: _file?.name,
        error: _error,
        busy: widget.busy || _sending,
        onPick: _pick,
        onSend: _send,
      );
}

/// The proof sheet's body from plain values (the layout harness renders it).
class BkTransferForm extends StatelessWidget {
  const BkTransferForm({
    super.key,
    required this.info,
    required this.name,
    required this.phone,
    required this.reference,
    required this.onPick,
    required this.onSend,
    this.amount,
    this.photoName,
    this.error,
    this.busy = false,
  });

  final BkTransferInfo info;
  final String? amount, photoName, error;
  final TextEditingController name, phone, reference;
  final VoidCallback onPick, onSend;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final kit = col.kit;
    final rows = <(String, String?)>[
      ('ow_transfer_bank'.tr, info.bankName),
      ('ow_transfer_account'.tr, info.accountName),
      ('IBAN', info.iban),
      ('SWIFT', info.swift),
    ].where((r) => (r.$2 ?? '').trim().isNotEmpty).toList();
    return AppSheetContent(
      title: 'ow_transfer_title'.tr,
      icon: Icons.account_balance_outlined,
      subtitle: amount == null ? null : bkFill('ow_transfer_amount', {'amount': amount!}),
      children: [
        if (rows.isEmpty)
          Text('ow_transfer_no_details'.tr, style: AppType.body(context).copyWith(color: col.textMedium))
        else
          for (final r in rows) _BankRow(label: r.$1, value: r.$2!),
        if ((info.instructions ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(info.instructions!, style: AppType.label(context).copyWith(color: col.textMedium)),
        ],
        const SizedBox(height: AppSpace.md),
        AppField(controller: name, label: 'ow_transfer_sender'.tr, required: true, textInputAction: TextInputAction.next),
        if (info.needPhone) ...[
          const SizedBox(height: AppSpace.sm),
          AppField(controller: phone, label: 'ow_transfer_phone'.tr, required: true, ltr: true, keyboard: TextInputType.phone),
        ],
        if (info.needReference) ...[
          const SizedBox(height: AppSpace.sm),
          AppField(controller: reference, label: 'ow_transfer_reference'.tr, required: true, ltr: true),
        ],
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(
          label: photoName == null ? 'ow_transfer_photo'.tr : 'ow_transfer_photo_change'.tr,
          icon: photoName == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_outline_rounded,
          onPressed: busy ? null : onPick,
          expand: true,
        ),
        if (photoName != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(photoName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: col.textMedium)),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(error!, style: AppType.body(context).copyWith(color: kit.error.color)),
        ],
        const SizedBox(height: AppSpace.md),
        AppButton.primary(label: 'ow_transfer_send'.tr, onPressed: busy ? null : onSend, busy: busy, expand: true),
        const SizedBox(height: AppSpace.xs),
        Text('ow_transfer_review_note'.tr, style: AppType.label(context).copyWith(color: col.textMedium)),
        const SizedBox(height: AppSpace.md),
      ],
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.label(context).copyWith(color: col.textMedium)),
            SelectableText(value, style: AppType.body(context)),
          ]),
        ),
        IconButton(
          tooltip: 'ow_transfer_copy'.tr,
          icon: const Icon(Icons.copy_rounded, size: AppIconSize.sm),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            showAppNotice('ow_transfer_copied'.tr);
          },
        ),
      ]),
    );
  }
}
