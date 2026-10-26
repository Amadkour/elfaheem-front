// lib/features/org/org_creation_fee.dart
//
// The organization-creation fee (super-admin setting, point 9). Shown above the "send the request" button of the
// institution application and when an org admin creates a new root organization.
//
//   GET  /api/v1/org/creation-fee?email=&token=   {required, amount, currency, methods, payment, can_submit, transfer_details}
//   POST /api/v1/org/creation-fee/checkout         {method: moyasar|paymob, email?} → {checkout_url, token}
//   POST /api/v1/org/creation-fee/transfer         multipart (bank_transfer | instapay + receipt) → review by the platform
//
// The server enforces it: POST /applications and a root POST /orgs answer 402 org_fee_required until a payment is
// usable. One payment = one request; a rejected request keeps its payment for re-submission.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import 'org_v3.dart';

const _feePath = '/api/v1/org/creation-fee';
const _kTokenKey = 'org_fee_token_v1';

String money(dynamic amount, String currency) {
  final v = (amount is num) ? amount : num.tryParse('$amount') ?? 0;
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  return '$s $currency';
}

/// The text of a refused checkout / transfer. 409 `fee_already_paid` / `fee_under_review` carry the existing
/// `payment`; for a caller without an account the server leaves its `token` out (an e-mail proves nothing), so a
/// device that does not hold the token itself ([haveToken]) cannot use that payment: say where it can be used
/// instead of "you can send the request". Everything else → [orgErrorText].
String feeConflictText(OrgCall r, {required bool haveToken}) {
  final code = r.code;
  final p = r.detail['payment'];
  if (!haveToken && (code == 'fee_already_paid' || code == 'fee_under_review') && p is Map && p['token'] == null) {
    return code == 'fee_already_paid'
        ? t('هذا البريد دفع رسوم الإنشاء بالفعل من جهاز أو متصفح آخر. أرسل الطلب من الجهاز الذي دفعت منه، أو سجّل الدخول بالحساب الذي دفعت به، أو تواصل مع الدعم.',
            'This e-mail has already paid the fee from another device or browser. Send the request from the device you paid on, sign in with the account you paid with, or contact support.')
        : t('إيصال تحويل لهذا البريد قيد المراجعة بالفعل. تابعه من الجهاز الذي أرسلته منه، أو تواصل مع الدعم.',
            'A transfer receipt for this e-mail is already being reviewed. Follow it on the device you sent it from, or contact support.');
  }
  return r.error == null ? '' : orgErrorText(r.error!);
}

/// Fee status + payment. [email] is read when the applicant has no account yet (the payment is tied to it);
/// [onReady] reports whether a request may be sent now and the payment token to send with it.
class OrgCreationFeePanel extends StatefulWidget {
  const OrgCreationFeePanel({super.key, this.email, required this.onReady, this.loggedIn = false});
  final String Function()? email;
  final void Function(bool canSubmit, String? token) onReady;
  final bool loggedIn;

  @override
  State<OrgCreationFeePanel> createState() => OrgCreationFeePanelState();
}

class OrgCreationFeePanelState extends State<OrgCreationFeePanel> {
  Map<String, dynamic>? _s;
  String? _token;
  bool _busy = false;
  String? _method;

  String get _email => (widget.email?.call() ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_kTokenKey);
    } catch (_) {}
    await reload();
  }

  Future<void> _remember(String? token) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove(_kTokenKey);
      } else {
        await prefs.setString(_kTokenKey, token);
      }
    } catch (_) {}
  }

  /// Re-reads the status (after paying in the browser, after a receipt review …).
  Future<void> reload() async {
    final r = await orgCall(
        () => ApiClient().get(_feePath, auth: widget.loggedIn, queryParams: {
              if (_email.contains('@')) 'email': _email,
              if (_token != null) 'token': _token,
            }),
        quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      // older server without the route → nothing to pay; anything else → let the server decide on submit
      setState(() => _s = {'required': false});
      widget.onReady(true, null);
      return;
    }
    final s = r.map;
    final p = asMap(s['payment']);
    if (p['token'] != null && p['token'] != _token) await _remember('${p['token']}');
    final methods = asMapList(s['methods']);
    setState(() {
      _s = s;
      _method ??= methods.isEmpty ? null : '${methods.first['id']}';
    });
    widget.onReady(s['can_submit'] == true, p['usable'] == true ? '${p['token']}' : _token);
  }

  Future<void> _payCard() async {
    if (!widget.loggedIn && !_email.contains('@')) {
      return appToast(t('اكتب بريدك الإلكتروني أولاً — تُربط الدفعة به', 'Enter your e-mail first — the payment is tied to it'), error: true);
    }
    setState(() => _busy = true);
    final r = await orgCall(
        () => ApiClient().post('$_feePath/checkout', auth: widget.loggedIn, body: {
              'method': _method,
              if (_email.contains('@')) 'email': _email,
            }),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      appToast(feeConflictText(r, haveToken: _token != null), error: true);
      if (r.code == 'fee_already_paid' || r.code == 'fee_under_review') await reload();
      return;
    }
    await _remember('${r.map['token']}');
    final url = Uri.tryParse('${r.map['checkout_url'] ?? ''}');
    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
    if (mounted) setState(() {});
  }

  Future<void> _payTransfer() async {
    if (!widget.loggedIn && !_email.contains('@')) {
      return appToast(t('اكتب بريدك الإلكتروني أولاً — تُربط الدفعة به', 'Enter your e-mail first — the payment is tied to it'), error: true);
    }
    final ok = await showAppSheet<bool>(context, (ctx) => _TransferSheet(
          method: _method!,
          details: asMap(_s?['transfer_details']),
          amount: money(_s?['amount'], '${_s?['currency'] ?? ''}'),
          email: _email,
          loggedIn: widget.loggedIn,
          haveToken: _token != null,
          onToken: _remember,
        ));
    if (ok == true) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _s;
    if (s == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: AppSkeletonBox(width: double.infinity, height: 90));
    }
    if (s['required'] != true) return const SizedBox.shrink();
    final p = asMap(s['payment']);
    final status = '${p['status'] ?? ''}';
    final usable = p['usable'] == true;
    final methods = asMapList(s['methods']);
    final price = money(s['amount'], '${s['currency']}');
    final isCard = methods.any((m) => m['id'] == _method && m['kind'] == 'card');

    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.receipt_long_rounded, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('رسوم إنشاء المؤسسة', 'Organization fee'), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: appText(15, w: FontWeight.w800, c: c.textDark)),
              Text(t('تُدفع مرة واحدة قبل إرسال الطلب', 'Paid once, before sending the request'),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
            ]),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(price, style: appText(17, w: FontWeight.w900, c: c.primary)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (usable)
          AppBanner(
              icon: Icons.verified_rounded,
              color: c.success,
              text: t('تم الدفع ✓ يمكنك إرسال الطلب الآن. إن رُفض الطلب تبقى الدفعة صالحة لإعادة الإرسال.',
                  'Paid ✓ You can send the request now. If it is turned down, the payment stays valid for re-submission.'))
        else if (status == 'review')
          AppBanner(
              icon: Icons.hourglass_top_rounded,
              color: c.warning,
              text: t('استلمنا إيصال التحويل وهو قيد المراجعة. سنخبرك فور اعتماده.',
                  'We received your receipt and it is being reviewed. We\'ll let you know once it\'s approved.'),
              action: TextButton(onPressed: reload, child: Text(t('تحديث', 'Refresh'))))
        else ...[
          if (status == 'rejected' || status == 'failed')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(
                  icon: Icons.info_outline_rounded,
                  color: c.danger,
                  text: status == 'rejected'
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
            Text(t('اختر طريقة الدفع', 'Choose how to pay'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in methods)
                AppChoiceChip(
                  label: t('${m['label_ar']}', '${m['label_en']}'),
                  icon: m['kind'] == 'card' ? Icons.credit_card_rounded : Icons.account_balance_rounded,
                  selected: _method == m['id'],
                  onTap: () => setState(() => _method = '${m['id']}'),
                ),
            ]),
            const SizedBox(height: 12),
            AppPrimaryButton(
              label: isCard ? t('ادفع $price', 'Pay $price') : t('أرسل إيصال التحويل', 'Send the transfer receipt'),
              icon: isCard ? Icons.lock_rounded : Icons.upload_rounded,
              busy: _busy,
              onPressed: _busy || _method == null ? null : (isCard ? _payCard : _payTransfer),
            ),
            if (status == 'pending' && _token != null) ...[
              const SizedBox(height: 6),
              Center(
                child: TextButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(t('أكملت الدفع؟ تحقّق الآن', 'Finished paying? Check now')),
                ),
              ),
            ],
          ],
        ],
      ]),
    );
  }
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.method, required this.details, required this.amount, required this.email,
      required this.loggedIn, required this.onToken, this.haveToken = false});
  final String method, amount, email;
  final Map<String, dynamic> details;
  final bool loggedIn;

  /// this device already holds a fee token (see [feeConflictText])
  final bool haveToken;
  final Future<void> Function(String?) onToken;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _name = TextEditingController(), _phone = TextEditingController(), _ref = TextEditingController();
  XFile? _image;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_name.text.trim().isEmpty) return appToast(t('اكتب اسم صاحب التحويل', 'Enter the sender\'s name'), error: true);
    if (_image == null) return appToast(t('أرفق صورة الإيصال', 'Attach the receipt image'), error: true);
    setState(() => _busy = true);
    final bytes = await _image!.readAsBytes();
    final r = await orgCall(
        () => ApiClient().postMultipart('$_feePath/transfer',
            auth: widget.loggedIn,
            fields: {
              'method': widget.method,
              'sender_name': _name.text.trim(),
              if (_phone.text.trim().isNotEmpty) 'sender_phone': _phone.text.trim(),
              if (_ref.text.trim().isNotEmpty) 'transfer_reference': _ref.text.trim(),
              if (widget.email.contains('@')) 'email': widget.email,
            },
            fileField: 'proof_image',
            fileName: _image!.name,
            fileBytes: bytes),
        ok: t('أُرسل الإيصال للمراجعة', 'Receipt sent for review'),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) appToast(feeConflictText(r, haveToken: widget.haveToken), error: true);
    if (r.ok) {
      await widget.onToken('${r.map['token']}');
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.details;
    final bank = widget.method == 'bank_transfer';
    final rows = <(String, String?)>[
      if (bank) (t('البنك', 'Bank'), d['bank_name'] as String?),
      if (bank) (t('اسم الحساب', 'Account name'), d['account_name'] as String?),
      if (bank) ('IBAN', d['iban'] as String?),
      if (!bank) (t('حساب إنستاباي', 'InstaPay address'), d['instapay_id'] as String?),
    ].where((r) => (r.$2 ?? '').isNotEmpty).toList();
    final note = (bank ? d['bank_instructions'] : d['instapay_instructions']) as String?;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(bank ? t('تحويل بنكي', 'Bank transfer') : t('إنستاباي', 'InstaPay')),
        AppBanner(icon: Icons.payments_rounded, text: t('حوّل ${widget.amount} ثم أرفق صورة الإيصال.', 'Transfer ${widget.amount}, then attach the receipt.')),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(flex: 2, child: Text(r.$1, style: appText(12.5, c: c.textLight))),
              Expanded(flex: 3, child: SelectableText(r.$2!, style: appText(13, w: FontWeight.w700, c: c.textDark))),
            ]),
          ),
        if ((note ?? '').isNotEmpty) Text(note!, style: appText(12, c: c.textMedium, h: 1.5)),
        const SizedBox(height: 10),
        AppField(controller: _name, label: t('اسم صاحب التحويل', 'Sender\'s name')),
        AppField(controller: _phone, label: t('هاتف المحوِّل (اختياري)', 'Sender\'s phone (optional)'), keyboard: TextInputType.phone, ltr: true),
        AppField(controller: _ref, label: t('رقم العملية (اختياري)', 'Reference number (optional)'), ltr: true),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 2000);
            if (x != null) setState(() => _image = x);
          },
          icon: Icon(_image == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded,
              color: _image == null ? c.primary : c.success),
          label: Text(_image == null ? t('أرفق صورة الإيصال', 'Attach the receipt') : _image!.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 14),
        AppPrimaryButton(label: t('إرسال للمراجعة', 'Send for review'), icon: Icons.send_rounded, busy: _busy, onPressed: _busy ? null : _send),
      ]),
    );
  }
}
