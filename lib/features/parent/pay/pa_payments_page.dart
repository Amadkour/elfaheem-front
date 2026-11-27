// lib/features/parent/pay/pa_payments_page.dart — "Payments and invoices" (Pa2Pay `screen=payments|invoice`, WP13,
// docs/redesign/api/parent_payments.md). Kill switch `parent.payments` (403 `feature_disabled` on the server too).
//
//   ParentPaymentsPage  one child at a time (the switcher; the dashboard's child, else the first): GET
//                       /parent/children/{id}/payments?skip=&limit=20&status= — All / Paid / In review / Refunded is
//                       the server's status filter, "Show more" the next page. A row with an invoice opens
//                       PaInvoicePage; one without (pending, failed) the receipt sheet. 403 `child_not_linked` says
//                       the child is no longer linked.
//   PaInvoicePage       GET …/payments/{pid}/invoice → PaInvoiceView (plain values): the lines, VAT only when sent,
//                       the seller's tax number only when set, a Refunded mark; "Download PDF" from …/invoice/pdf
//                       (the share sheet on a phone, a download on the web). 409 `invoice_not_ready` for a pending
//                       or failed payment.
//   PaReceiptSheet      a payment as the list sent it (no tax lines it was not sent).
library;

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../pa_kit.dart';

/// The kill switch of the parent's payments and invoices.
const kParentPaymentsKey = 'parent.payments';

DateTime? _utc(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return null;
  return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
}

/// One row of GET /parent/children/{id}/payments (older /my-payments rows parse too).
class PaPayment {
  const PaPayment({
    required this.id,
    required this.amount,
    required this.status,
    this.method = '',
    this.courseId,
    this.courseName = '',
    this.at,
    this.currency = '',
    this.transactionId = '',
    this.hasInvoice = false,
    this.invoiceNumber = '',
  });

  final int id;
  final double amount;
  final String status, method, currency, transactionId, courseName, invoiceNumber;
  final int? courseId;
  final DateTime? at;
  final bool hasInvoice;

  /// paid · review · refunded · other (failed, cancelled …).
  String get group => switch (status.toLowerCase()) {
        'completed' || 'paid' || 'success' || 'succeeded' => 'paid',
        'pending' || 'review' || 'under_review' || 'processing' => 'review',
        'refunded' || 'refund' => 'refunded',
        _ => 'other',
      };

  static PaPayment? tryParse(Object? v) {
    if (v is! Map || v['id'] is! num) return null;
    final meta = v['meta_data'] is Map ? v['meta_data'] as Map : const {};
    return PaPayment(
      id: (v['id'] as num).toInt(),
      amount: (v['amount'] as num?)?.toDouble() ?? 0,
      status: '${v['status'] ?? ''}',
      method: '${v['method'] ?? v['payment_method'] ?? ''}',
      courseId: (v['course_id'] as num?)?.toInt(),
      courseName: '${v['course_name'] ?? ''}',
      at: _utc(v['paid_at'] ?? v['created_at']),
      currency: '${v['currency'] ?? meta['currency'] ?? ''}',
      transactionId: '${v['transaction_id'] ?? ''}',
      hasInvoice: v['has_invoice'] == true,
      invoiceNumber: '${v['invoice_number'] ?? ''}',
    );
  }
}

String _amount(double a, String currency) =>
    appDigits('${a.toStringAsFixed(a == a.roundToDouble() ? 0 : 2)}${currency.isEmpty ? '' : ' $currency'}');

String _money(PaPayment p) => _amount(p.amount, p.currency);

AppTone _tone(String group) => switch (group) {
      'paid' => AppTone.success,
      'review' => AppTone.warning,
      'refunded' => AppTone.info,
      _ => AppTone.danger,
    };

Map<String, String> get _langHeader => {'Accept-Language': paIsAr() ? 'ar' : 'en'};

class ParentPaymentsPage extends StatefulWidget {
  const ParentPaymentsPage({super.key, this.api, this.childId});

  final ApiClient? api;

  /// The child shown first (default: the dashboard's pick, else the first child).
  final int? childId;

  @override
  State<ParentPaymentsPage> createState() => _ParentPaymentsPageState();
}

class _ParentPaymentsPageState extends State<ParentPaymentsPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  static const _pageSize = 20;
  static const _tabs = ['all', 'paid', 'review', 'refunded'];
  static const _status = {'paid': 'completed', 'review': 'pending', 'refunded': 'refunded'};

  List<PaKid>? _ownKids;
  int? _child;
  List<PaPayment>? _items;
  int _total = 0, _allTotal = 0, _tab = 0, _seq = 0;
  bool _more = false, _notLinked = false, _off = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _child = widget.childId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  List<PaKid> get _kids {
    final shared = PaKids.maybeOf(context, listen: false);
    return shared != null && shared.kids.isNotEmpty ? shared.kids : (_ownKids ?? const []);
  }

  Future<void> _start() async {
    if (!mounted) return;
    final shared = PaKids.maybeOf(context, listen: false);
    if (shared == null || shared.kids.isEmpty) {
      try {
        final r = await _api.get('/api/v1/parent/children');
        final list = r is List ? r : (r is Map ? (r['items'] as List? ?? const []) : const []);
        _ownKids = [
          for (final x in list)
            if (x is Map && x['id'] is num) PaKid(id: (x['id'] as num).toInt(), name: '${x['name'] ?? ''}', grade: '${x['grade_name'] ?? ''}'),
        ];
      } catch (e) {
        if (mounted) setState(() => _error = ApiException.from(e).message);
        return;
      }
    }
    if (!mounted) return;
    final kids = _kids;
    _child ??= shared?.selected ?? (kids.isEmpty ? null : kids.first.id);
    if (_child == null) {
      setState(() => _items = const []);
      return;
    }
    await _load();
  }

  Future<void> _load({bool more = false}) async {
    final id = _child;
    if (id == null) return _start();
    final seq = ++_seq;
    if (!more) {
      setState(() {
        _items = null;
        _error = null;
        _notLinked = false;
      });
    }
    final status = _status[_tabs[_tab]];
    try {
      final r = await _api.get('/api/v1/parent/children/$id/payments',
          queryParams: {'skip': more ? (_items?.length ?? 0) : 0, 'limit': _pageSize, 'status': ?status}, headers: _langHeader);
      if (!mounted || seq != _seq) return;
      final m = r is Map ? r : const {};
      final page = [for (final x in (m['items'] as List? ?? const [])) ?PaPayment.tryParse(x)];
      final total = (m['total'] as num?)?.toInt() ?? page.length;
      setState(() {
        final all = [if (more) ...?_items, ...page];
        _items = all;
        _total = total;
        if (status == null) _allTotal = total;
        _more = page.length == _pageSize && all.length < total;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      final x = ApiException.from(e);
      setState(() {
        if (x.code == 'child_not_linked') {
          _notLinked = true;
          _items = const [];
        } else if (x.code == 'feature_disabled') {
          _off = true;
        } else if (more) {
          showAppNotice(x.message, error: true);
        } else {
          _error = x.message;
        }
      });
    }
  }

  void _pick(int? id) {
    if (id == null || id == _child) return;
    setState(() {
      _child = id;
      _allTotal = 0;
    });
    _load();
  }

  void _open(PaPayment p) {
    final id = _child;
    if (id == null) return;
    if (p.hasInvoice) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => paRole(PaInvoicePage(childId: id, paymentId: p.id, api: widget.api)),
      ));
    } else {
      showAppSheet<void>(context, (_) => paRole(PaReceiptSheet(payment: p)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = _off || AppConfig.disableList.contains(kParentPaymentsKey);
    final kids = _kids;
    PaKid? kid;
    for (final k in kids) {
      if (k.id == _child) kid = k;
    }
    final items = _items;
    final hero = AppHero(
      kicker: 'pa_payments'.tr,
      title: kid == null ? 'pa_payments'.tr : paFmt('pa_pay_child_title', {'name': kid.firstName}),
      subtitle: 'pa_pay_child_sub'.tr,
      stats: [
        AppHeroStat(label: 'pa_pay_list'.tr, value: items == null && _allTotal == 0 ? '—' : appDigits('$_allTotal')),
      ],
    );
    final Widget list;
    if (_notLinked) {
      list = AppEmpty(icon: Icons.link_off_rounded, title: 'pa_pay_not_linked'.tr, message: 'pa_pay_not_linked_sub'.tr);
    } else if (_error != null && items == null) {
      list = ErrorRetry(message: _error!, onRetry: _load);
    } else if (items == null) {
      list = const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    } else if (_child == null) {
      list = AppEmpty(icon: Icons.family_restroom_rounded, title: 'pa_pay_no_kids'.tr);
    } else if (items.isEmpty) {
      list = AppEmpty(icon: Icons.receipt_long_outlined, title: 'pa_pay_none'.tr, message: 'pa_pay_none_child'.tr);
    } else {
      list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, p) in items.indexed) ...[
          if (i > 0) Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: context.colors.kit.line),
          _PaymentRow(key: ValueKey('pa.pay.${p.id}'), payment: p, onTap: () => _open(p)),
        ],
        if (_more) ...[
          const SizedBox(height: AppSpace.sm),
          AppButton.ghost(key: const ValueKey('pa.pay.more'), label: 'pa_pay_more'.tr, onPressed: () => _load(more: true)),
        ],
      ]);
    }
    return BasePage(
      key: const ValueKey(kParentPaymentsKey),
      appBar: ScreenAppBar(title: 'pa_payments'.tr),
      child: off
          ? Center(child: AppEmpty(icon: Icons.lock_outline_rounded, title: 'pa_pay_off'.tr))
          : PaHeroPage(
              onRefresh: _load,
              width: AppWidth.reading,
              hero: hero,
              body: PaStack(children: [
                if (kids.length > 1)
                  PaKidSwitcher(kids: kids, selected: _child, showAll: false, onHero: false, onSelect: _pick),
                AppCard(
                  title: 'pa_pay_list'.tr,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    AppTabs(
                      expand: true,
                      items: [for (final t in _tabs) AppTabItem('pa_pay_tab_$t'.tr)],
                      index: _tab,
                      onChanged: (i) {
                        setState(() => _tab = i);
                        _load();
                      },
                    ),
                    const SizedBox(height: AppSpace.sm),
                    list,
                  ]),
                ),
                if (items != null && items.isNotEmpty && _total > 0)
                  PaNote(icon: Icons.info_outline_rounded, text: 'pa_pay_invoice_note'.tr),
              ]),
            ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({super.key, required this.payment, required this.onTap});

  final PaPayment payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final title = p.courseName.isNotEmpty ? p.courseName : appDigits('#${p.id}');
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
                if (p.invoiceNumber.isNotEmpty)
                  Text(p.invoiceNumber, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                if (p.at != null) Text(AppTime.date(p.at!), style: AppType.meta(context)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_money(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              AppStatusBadge(label: 'pa_pay_status_${p.group}'.tr, tone: _tone(p.group)),
            ])),
          ]),
        ),
      ),
    );
  }
}

/// The receipt of one payment that has no invoice (yet), as the server sent it: no tax lines it did not send.
class PaReceiptSheet extends StatelessWidget {
  const PaReceiptSheet({super.key, required this.payment});

  final PaPayment payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return AppSheetContent(
      title: 'pa_receipt'.tr,
      icon: Icons.receipt_long_outlined,
      children: [
        _Box(children: [
          AppStatusBadge(label: 'pa_pay_status_${p.group}'.tr, tone: _tone(p.group)),
          const SizedBox(height: AppSpace.xs),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('pa_receipt_no'.tr, style: AppType.meta(context)),
            Text(appDigits('#${p.id}'), textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
            if (p.at != null) Text(AppTime.dateTime(p.at!), style: AppType.meta(context)),
          ]),
        ]),
        const SizedBox(height: AppSpace.sm),
        _Box(children: [
          if (p.courseName.isNotEmpty) _Line(label: 'pa_invoice_course'.tr, value: p.courseName),
          _Line(label: 'pa_receipt_amount'.tr, value: _money(p)),
          if (p.method.isNotEmpty) _Line(label: 'pa_receipt_method'.tr, value: p.method),
          if (p.transactionId.isNotEmpty) _Line(label: 'pa_receipt_ref'.tr, value: p.transactionId),
        ]),
        const SizedBox(height: AppSpace.sm),
        PaNote(icon: Icons.info_outline_rounded, text: p.group == 'review' ? 'pa_invoice_not_ready_sub'.tr : 'pa_receipt_note'.tr),
        const SizedBox(height: AppSpace.md),
        AppButton.secondary(label: 'pa_close'.tr, expand: true, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: c.kit.line, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.label, required this.value, this.strong = false, this.ltr = false});

  final String label, value;
  final bool strong, ltr;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: strong ? AppType.tileTitle(context) : AppType.meta(context))),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: ltr ? TextDirection.ltr : null,
              style: strong ? AppType.section(context) : AppType.row(context).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}

// ── the invoice ──────────────────────────────────────────────────────────────

/// One line of an invoice (`items[]` or `vat[]`).
@immutable
class PaInvoiceLine {
  const PaInvoiceLine({required this.key, required this.label, required this.amount, this.percent});

  final String key, label;
  final double amount;
  final double? percent;
}

/// GET …/payments/{pid}/invoice.
@immutable
class PaInvoice {
  const PaInvoice({
    required this.number,
    required this.paymentId,
    required this.status,
    required this.currency,
    this.issuedAt,
    this.refundedAt,
    this.taxNumber,
    this.studentName = '',
    this.billedTo = '',
    this.courseName = '',
    this.method = '',
    this.items = const [],
    this.vat = const [],
    this.subtotal = 0,
    this.total = 0,
    this.totalLabel = '',
  });

  final String number, status, currency, studentName, billedTo, courseName, method, totalLabel;
  final int paymentId;
  final DateTime? issuedAt, refundedAt;

  /// The seller's tax number, null when the super admin set none (no row then).
  final String? taxNumber;
  final List<PaInvoiceLine> items;

  /// Empty when no VAT was charged (no VAT row then).
  final List<PaInvoiceLine> vat;
  final double subtotal, total;

  bool get refunded => status == 'refunded';

  static String _name(Object? v) => v is Map ? '${v['name'] ?? ''}' : '';

  static List<PaInvoiceLine> _lines(Object? v) => [
        for (final x in (v is List ? v : const []))
          if (x is Map)
            PaInvoiceLine(
              key: '${x['key'] ?? ''}',
              label: '${x['label'] ?? ''}',
              amount: (x['amount'] as num?)?.toDouble() ?? 0,
              percent: (x['percent'] as num?)?.toDouble(),
            ),
      ];

  factory PaInvoice.fromJson(Map<String, dynamic> j) {
    final seller = j['seller'] is Map ? j['seller'] as Map : const {};
    final tax = '${seller['tax_number'] ?? ''}'.trim();
    return PaInvoice(
      number: '${j['invoice_number'] ?? ''}',
      paymentId: (j['payment_id'] as num?)?.toInt() ?? 0,
      status: '${j['status'] ?? ''}',
      currency: '${j['currency'] ?? ''}',
      issuedAt: _utc(j['issued_at']),
      refundedAt: _utc(j['refunded_at']),
      taxNumber: tax.isEmpty ? null : tax,
      studentName: _name(j['student']),
      billedTo: _name(j['billed_to']),
      courseName: _name(j['course']),
      method: '${j['method'] ?? ''}',
      items: _lines(j['items']),
      vat: _lines(j['vat']),
      subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
      total: (j['total'] as num?)?.toDouble() ?? 0,
      totalLabel: '${j['total_label'] ?? ''}',
    );
  }
}

/// Saves a PDF: the share sheet on a phone (save to Files, send on WhatsApp), a download on the web.
Future<void> paSavePdf(Uint8List bytes, String name) async {
  if (kIsWeb) {
    await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
    return;
  }
  try {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '$name.pdf')],
      fileNameOverrides: ['$name.pdf'],
    ));
  } catch (_) {
    await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
  }
}

class PaInvoicePage extends StatefulWidget {
  const PaInvoicePage({super.key, required this.childId, required this.paymentId, this.api});

  final int childId, paymentId;
  final ApiClient? api;

  @override
  State<PaInvoicePage> createState() => _PaInvoicePageState();
}

class _PaInvoicePageState extends State<PaInvoicePage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  PaInvoice? _invoice;
  String? _error, _code;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _code = null;
    });
    try {
      final r = await _api.get('/api/v1/parent/children/${widget.childId}/payments/${widget.paymentId}/invoice', headers: _langHeader);
      if (mounted) setState(() => _invoice = PaInvoice.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {}));
    } catch (e) {
      final x = ApiException.from(e);
      if (mounted) {
        setState(() {
          _code = x.code;
          _error = x.message;
        });
      }
    }
  }

  Future<void> _pdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await _api.getBytes('/api/v1/parent/children/${widget.childId}/payments/${widget.paymentId}/invoice/pdf', headers: _langHeader);
      final inv = _invoice;
      await paSavePdf(bytes, inv == null || inv.number.isEmpty ? 'invoice-${widget.paymentId}' : inv.number);
      if (kIsWeb) showAppNotice('pa_invoice_saved'.tr);
    } catch (e) {
      final x = e is ApiException ? e : null;
      showAppNotice(x == null || x.code == 'invoice_pdf_failed' ? 'pa_invoice_pdf_failed'.tr : x.message, error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    final Widget body;
    if (inv != null) {
      body = PaInvoiceView(invoice: inv, onPdf: _pdf, pdfBusy: _pdfBusy);
    } else if (_code == 'invoice_not_ready') {
      body = AppEmpty(icon: Icons.hourglass_top_rounded, title: 'pa_invoice_not_ready'.tr, message: 'pa_invoice_not_ready_sub'.tr);
    } else if (_code == 'child_not_linked') {
      body = AppEmpty(icon: Icons.link_off_rounded, title: 'pa_pay_not_linked'.tr, message: 'pa_pay_not_linked_sub'.tr);
    } else if (_error != null) {
      body = ErrorRetry(message: _error!, onRetry: _load);
    } else {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    }
    return BasePage(
      key: const ValueKey(kParentPaymentsKey),
      appBar: ScreenAppBar(title: 'pa_invoice'.tr),
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          Center(
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.reading.max), child: body),
          ),
        ],
      ),
    );
  }
}

/// The invoice with plain values (the layout tests, the goldens).
class PaInvoiceView extends StatelessWidget {
  const PaInvoiceView({super.key, required this.invoice, this.onPdf, this.pdfBusy = false});

  final PaInvoice invoice;
  final VoidCallback? onPdf;
  final bool pdfBusy;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final cur = inv.currency;
    final line = context.colors.kit.line;
    return PaStack(children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppStatusBadge(
              key: ValueKey('pa.invoice.${inv.refunded ? 'refunded' : 'paid'}'),
              label: (inv.refunded ? 'pa_invoice_refunded' : 'pa_pay_status_paid').tr,
              tone: inv.refunded ? AppTone.info : AppTone.success,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text('pa_invoice_no'.tr, style: AppType.meta(context)),
          Text(inv.number, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
          if (inv.issuedAt != null) Text(AppTime.dateTime(inv.issuedAt!), style: AppType.meta(context)),
          if (inv.refunded && inv.refundedAt != null) ...[
            const SizedBox(height: AppSpace.xs),
            PaNote(icon: Icons.undo_rounded, text: paFmt('pa_invoice_refunded_at', {'date': AppTime.date(inv.refundedAt!)})),
          ],
          const SizedBox(height: AppSpace.sm),
          _Box(children: [
            if (inv.studentName.isNotEmpty) _Line(label: 'pa_invoice_student'.tr, value: inv.studentName),
            if (inv.billedTo.isNotEmpty) _Line(label: 'pa_invoice_billed'.tr, value: inv.billedTo),
            if (inv.courseName.isNotEmpty) _Line(label: 'pa_invoice_course'.tr, value: inv.courseName),
            if (inv.method.isNotEmpty) _Line(label: 'pa_receipt_method'.tr, value: inv.method),
            if (inv.taxNumber != null)
              _Line(key: const ValueKey('pa.invoice.tax_number'), label: 'pa_invoice_tax_no'.tr, value: inv.taxNumber!, ltr: true),
          ]),
        ]),
      ),
      AppCard(
        title: 'pa_invoice_lines'.tr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in inv.items) _Line(label: l.label, value: _amount(l.amount, cur)),
          if (inv.vat.isNotEmpty) ...[
            Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: line),
            _Line(label: 'pa_invoice_subtotal'.tr, value: _amount(inv.subtotal, cur)),
            for (final (i, v) in inv.vat.indexed) _Line(key: ValueKey('pa.invoice.vat.$i'), label: v.label, value: _amount(v.amount, cur)),
          ],
          Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: line),
          _Line(label: 'pa_invoice_total'.tr, value: inv.totalLabel.isNotEmpty ? appDigits(inv.totalLabel) : _amount(inv.total, cur), strong: true),
        ]),
      ),
      if (onPdf != null)
        AppButton.primary(
          key: const ValueKey('pa.invoice.pdf'),
          label: 'pa_invoice_pdf'.tr,
          icon: Icons.picture_as_pdf_outlined,
          expand: true,
          busy: pdfBusy,
          onPressed: onPdf,
        ),
    ]);
  }
}
