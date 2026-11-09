// lib/features/admin/admin_payouts_page.dart
//   Requests  — approve (auto-transfers Moyasar/Paymob), mark paid (manual), reject, retry, sync, resolve
//   Teachers  — who may withdraw: follow global · allow · block, and which methods
//   Settings  — allow all teachers · allowed methods · minimum · automatic transfer on/off
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart' show EntityKind;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/outline_button.dart';
import '../../utils/widget/primary_button.dart';
import '../teacher/profile/payout/teacher_payouts_screen.dart' as tp show statusLabel;
import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_money_p8.dart' show numText, parseAmountLoose;
import 'admin_page.dart';
import 'admin_providers.dart';
import 'admin_table_export.dart' show adminWithdrawalsExport, exportFetched;
import 'receipt_viewer.dart';

class AdminPayoutsPage extends StatefulWidget {
  const AdminPayoutsPage({super.key});

  @override
  State<AdminPayoutsPage> createState() => _AdminPayoutsPageState();
}

class _AdminPayoutsPageState extends State<AdminPayoutsPage> {
  final _requests = AdminPayoutRequestsProvider();
  final _teachers = AdminPayoutTeachersProvider();
  final _settings = AdminPayoutSettingsProvider();
  final _visited = <int>{0};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _requests.refresh();
  }

  @override
  void dispose() {
    _requests.dispose();
    _teachers.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i == _tab) return;
    setState(() {
      _tab = i;
      if (_visited.add(i)) _load(i);
    });
  }

  void _load(int i) {
    switch (i) {
      case 0:
        _requests.refresh();
      case 1:
        _teachers.refresh();
      default:
        _settings.load();
    }
  }

  Future<void> _export() async {
    await exportFetched(
      context,
      fetch: (job) => _requests.fetchEvery(),
      build: adminWithdrawalsExport,
      filters: {if (_requests.status != null) t('الحالة', 'Status'): _requests.status!},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminPayoutRequestsProvider>.value(value: _requests),
        ChangeNotifierProvider<AdminPayoutTeachersProvider>.value(value: _teachers),
        ChangeNotifierProvider<AdminPayoutSettingsProvider>.value(value: _settings),
      ],
      child: ListenableBuilder(
        listenable: _requests,
        builder: (context, _) => AdminPage(
          width: AppWidth.wide,
          title: 'admin_teacher_payouts'.tr,
          icon: Icons.account_balance_wallet_rounded,
          onRefresh: () => _load(_tab),
          updatedAt: _tab == 0 ? _requests.loadedAt : null,
          primaryAction: _tab == 0
              ? AppButton.primary(
                  label: t('تصدير', 'Export'),
                  icon: Icons.ios_share_rounded,
                  onPressed: _requests.loaded && _requests.rows.isNotEmpty ? _export : null,
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSpace.gutter(MediaQuery.sizeOf(context).width),
                  AppSpace.md,
                  AppSpace.gutter(MediaQuery.sizeOf(context).width),
                  AppSpace.xs,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppTabs(
                    index: _tab,
                    onChanged: _go,
                    items: [
                      AppTabItem('admin_requests'.tr, count: _requests.pendingCount > 0 ? _requests.pendingCount : null),
                      AppTabItem('admin_teachers'.tr),
                      AppTabItem('admin_settings'.tr),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    const _RequestsView(),
                    _visited.contains(1) ? const _TeachersView() : const SizedBox.shrink(),
                    _visited.contains(2) ? const _SettingsView() : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Requests
// ═════════════════════════════════════════════════════════════════════════════

AppTone _statusTone(String s) => switch (s) {
      'paid' => AppTone.success,
      'rejected' => AppTone.danger,
      'approved' => AppTone.brand,
      _ => AppTone.warning,
    };

String _stateLabel(String state) => switch (state) {
      'paid' => 'admin_provider_paid'.tr,
      'processing' => 'admin_processing_at_provider'.tr,
      'failed' => 'admin_transfer_failed'.tr,
      'unknown' => 'admin_unconfirmed'.tr,
      _ => '',
    };

AppTone _stateTone(String state) => switch (state) {
      'paid' => AppTone.success,
      'processing' => AppTone.brand,
      'failed' => AppTone.danger,
      'unknown' => AppTone.warning,
      _ => AppTone.neutral,
    };

/// "1,200 EGP": the amount of a withdrawal with the currency the server pays it out in.
String _amountText(Withdrawal w) => money(w.amount, w.currency);

class _RequestsView extends StatelessWidget {
  const _RequestsView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminPayoutRequestsProvider>();
    final rows = p.visible;
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    final summary = p.pendingCount > 0
        ? Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xs, gutter, AppSpace.xs),
            child: _PendingSummary(p),
          )
        : const SizedBox.shrink();

    Widget table() => Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xs, gutter, AppSpace.md),
            child: AppDataTable<Withdrawal>(
              state: (!p.loaded && p.isLoading)
                  ? AppTableState.loading
                  : (p.error != null && p.rows.isEmpty)
                      ? AppTableState.error
                      : AppTableState.ready,
              errorText: p.error,
              onRetry: p.refresh,
              rows: rows,
              searchHint: t('ابحث عن معلم…', 'Search a teacher…'),
              onSearch: p.setQuery,
              filters: [
                AppTableFilter(
                  label: t('الحالة', 'Status'),
                  value: p.status,
                  options: [
                    ('pending', 'admin_pending_3'.tr),
                    ('approved', 'admin_approved'.tr),
                    ('paid', 'admin_paid_2'.tr),
                    ('rejected', 'admin_rejected'.tr),
                  ],
                  onChanged: p.setStatus,
                ),
              ],
              onClearFilters: () => p.setStatus(null),
              empty: AppEmpty(
                icon: Icons.account_balance_wallet_outlined,
                title: 'admin_no_requests'.tr,
              ),
              columns: [
                AppTableColumn<Withdrawal>(
                  key: 'teacher',
                  label: 'admin_teachers'.tr,
                  primary: true,
                  flex: 3,
                  cell: (ctx, w) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      adminEntityCell(ctx, EntityKind.teacher, {'id': w.teacherId, 'name': w.teacherName}),
                      if (w.teacherGmail.isNotEmpty)
                        Text(
                          w.teacherGmail,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.meta(ctx),
                        ),
                    ],
                  ),
                ),
                AppTableColumn<Withdrawal>(
                  key: 'amount',
                  label: t('المبلغ', 'Amount'),
                  numeric: true,
                  align: AppColAlignment.end,
                  cell: (ctx, w) => Text(_amountText(w), style: AppType.figure(ctx), textDirection: TextDirection.ltr),
                ),
                AppTableColumn<Withdrawal>.text(
                  key: 'method',
                  label: t('الطريقة', 'Method'),
                  text: (w) => payoutMethodLabel(w.method),
                ),
                AppTableColumn<Withdrawal>(
                  key: 'status',
                  label: t('الحالة', 'Status'),
                  flex: 2,
                  cell: (ctx, w) => Wrap(
                    spacing: AppSpace.xxs,
                    runSpacing: AppSpace.xxs,
                    children: [
                      AppStatusBadge(label: tp.statusLabel(w.status), tone: _statusTone(w.status), dense: true),
                      if (w.state != 'none' && _stateLabel(w.state).isNotEmpty)
                        AppStatusBadge(label: _stateLabel(w.state), tone: _stateTone(w.state), dense: true),
                      if (p.busy.contains(w.id))
                        AppStatusBadge(label: t('جارٍ التنفيذ…', 'Working…'), tone: AppTone.info, dense: true),
                    ],
                  ),
                ),
                AppTableColumn<Withdrawal>.text(
                  key: 'requested',
                  label: 'admin_requested'.tr,
                  text: (w) => shortDateTime(w.requestedAt),
                ),
              ],
              onRowTap: (w) => _showDetails(context, w),
              rowActions: (w) => _actionsFor(context, p, w),
              onLoadMore: p.loadMore,
              hasMore: p.hasMore,
              loadingMore: p.loadingMore,
            ),
          );

    // A tall window: the money waiting on top, the table fills the rest. A short one (a phone) scrolls the page and
    // gives the table a fixed height, so the summary never squeezes the table to nothing.
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight >= 760) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [summary, Expanded(child: table())]);
      }
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [summary, SizedBox(height: 560, child: table())]),
      );
    });
  }
}

/// The money waiting for the admin: how many requests and, per currency, how much.
class _PendingSummary extends StatelessWidget {
  const _PendingSummary(this.p);

  final AdminPayoutRequestsProvider p;

  @override
  Widget build(BuildContext context) {
    final entries = p.pendingMoney.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return AppKpiGrid(
      maxColumns: 3,
      children: [
        AppKpiCard(
          label: t('طلبات بانتظار القرار', 'Requests waiting'),
          value: '${p.pendingCount}',
          icon: Icons.pending_actions_rounded,
        ),
        for (var i = 0; i < entries.length; i++)
          AppKpiCard(
            label: entries[i].key.isEmpty
                ? t('مبالغ بانتظار الاعتماد', 'Money waiting')
                : '${t('مبالغ بانتظار الاعتماد', 'Money waiting')} · ${entries[i].key}',
            value: money(entries[i].value, entries[i].key),
            icon: Icons.payments_rounded,
            highlight: i == 0,
            footnote: p.pendingCount > 200 ? t('أول ٢٠٠ طلب', 'First 200 requests') : null,
          ),
      ],
    );
  }
}

List<AppRowAction<Withdrawal>> _actionsFor(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) {
  if (p.busy.contains(w.id)) return const [];
  final approvedAuto = w.status == 'approved' && w.provider != null;
  return [
    if (w.status == 'pending')
      AppRowAction(
        icon: Icons.check_rounded,
        label: w.automatic ? 'admin_approve_send'.tr : 'request_approve'.tr,
        onTap: () => _approve(context, p, w),
      ),
    if (w.status == 'pending')
      AppRowAction(icon: Icons.close_rounded, label: 'request_reject'.tr, danger: true, onTap: () => _reject(context, p, w)),
    if (w.status == 'approved' && w.state == 'processing')
      AppRowAction(icon: Icons.sync_rounded, label: 'admin_sync_status'.tr, onTap: () => p.sync(w.id)),
    if (approvedAuto && (w.state == 'failed' || w.state == 'unknown' || w.state == 'none'))
      AppRowAction(icon: Icons.replay_rounded, label: 'retry'.tr, onTap: () => _retry(context, p, w)),
    if (approvedAuto && w.state == 'unknown')
      AppRowAction(icon: Icons.rule_rounded, label: 'admin_resolve'.tr, onTap: () => _resolve(context, p, w)),
    if (w.status == 'approved' && w.state != 'processing')
      AppRowAction(icon: Icons.price_check_rounded, label: 'admin_mark_paid_manual'.tr, onTap: () => _markPaid(context, p, w)),
    if (w.status == 'approved' && w.state != 'processing' && w.state != 'unknown')
      AppRowAction(icon: Icons.close_rounded, label: 'request_reject'.tr, danger: true, onTap: () => _reject(context, p, w)),
    if (w.receiptUrl != null)
      AppRowAction(icon: Icons.receipt_long_rounded, label: 'admin_view_receipt'.tr, onTap: () => _openReceipt(context, p, w)),
  ];
}

String _who(Withdrawal w) => w.teacherName.isEmpty ? '#${w.teacherId}' : w.teacherName;

/// Approve. This moves REAL money for an automatic method, so the question names the teacher, the amount WITH its
/// currency and the method.
Future<void> _approve(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) async {
  final head = '${_who(w)} · ${_amountText(w)} · ${payoutMethodLabel(w.method)}';
  final body = w.automatic
      ? trp('admin_approving_sends_right_now_via_continue', {
          'amount': _amountText(w),
          'method': payoutMethodLabel(w.method),
        })
      : 'admin_approve_this_request_you_will_transfer'.tr;
  final ok = await appConfirm(context, message: '$head\n\n$body', confirmLabel: 'request_approve'.tr);
  if (ok) await p.approve(w.id);
}

Future<void> _reject(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) async {
  final reason = await askText(context, title: 'rejection_reason_title'.tr, multiline: true);
  if (reason != null && reason.isNotEmpty) await p.reject(w.id, reason);
}

Future<void> _retry(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) async {
  final head = '${_who(w)} · ${_amountText(w)} · ${payoutMethodLabel(w.method)}';
  final ok = await appConfirm(
    context,
    message: '$head\n\n${w.state == 'unknown' ? 'admin_it_is_re_sent_with_the_same'.tr : 'admin_send_the_transfer_again'.tr}',
  );
  if (ok) await p.retry(w.id);
}

Future<void> _openReceipt(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) async {
  final link = await p.receiptLink(w.id);
  if (!context.mounted) return;
  await openReceipt(context, link);
}

Future<void> _markPaid(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) async {
  final result = await showDialog<_PaidInput>(
    context: context,
    builder: (_) => const _MarkPaidDialog(),
  );
  if (result == null) return;
  // 1) upload the receipt first — if it fails nothing is marked paid
  final uploaded = await p.uploadReceipt(
    w.id,
    fileName: result.fileName,
    filePath: result.filePath,
    bytes: result.bytes,
  );
  if (!uploaded) return;
  // 2) then confirm the transfer
  await p.markPaid(w.id, result.reference);
}

Future<void> _resolve(BuildContext context, AdminPayoutRequestsProvider p, Withdrawal w) async {
  final r = await showDialog<_ResolveInput>(
    context: context,
    builder: (_) => const _ResolveDialog(),
  );
  if (r == null) return;
  if (!r.sent) {
    await p.resolve(w.id, sent: false);
  } else {
    await p.resolve(w.id, sent: true, reference: r.reference);
  }
}

/// Everything about one request that does not fit a row (account, provider status and references, notes, errors).
void _showDetails(BuildContext context, Withdrawal w) {
  final c = context.colors;
  showAppSheet<void>(
    context,
    (ctx) => AppSheetContent(
      title: _who(w),
      children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xxs,
          children: [
            AppStatusBadge(label: tp.statusLabel(w.status), tone: _statusTone(w.status)),
            AppStatusBadge(label: payoutMethodLabel(w.method), tone: AppTone.neutral),
            if (w.state != 'none' && _stateLabel(w.state).isNotEmpty)
              AppStatusBadge(label: _stateLabel(w.state), tone: _stateTone(w.state)),
          ],
        ),
        AppSpace.gapSm,
        KeyValue(t('المبلغ', 'Amount'), _amountText(w)),
        if (w.teacherGmail.isNotEmpty) KeyValue('admin_teachers'.tr, w.teacherGmail),
        KeyValue('account'.tr, payoutDestinationSummary(w.destination)),
        if (w.providerStatus != null) KeyValue('admin_provider'.tr, w.providerStatus!),
        if (w.providerReference != null) KeyValue('admin_reference'.tr, w.providerReference!),
        if (w.bankReference != null) KeyValue('admin_transfer_ref'.tr, w.bankReference!),
        if (w.note != null) KeyValue('admin_teacher_note'.tr, w.note!),
        if (w.rejectedReason != null) KeyValue('admin_reason'.tr, w.rejectedReason!),
        KeyValue('admin_requested'.tr, shortDateTime(w.requestedAt)),
        if (w.error != null && w.state != 'paid')
          Container(
            margin: const EdgeInsets.only(top: AppSpace.xs),
            padding: const EdgeInsets.all(AppSpace.xs),
            decoration: BoxDecoration(color: c.dangerTint, borderRadius: AppRadius.chipAll),
            child: Text(w.error!, style: AppType.meta(ctx).copyWith(color: c.danger)),
          ),
      ],
    ),
  );
}

class _ResolveInput {
  const _ResolveInput(this.sent, this.reference);

  final bool sent;
  final String reference;
}

/// The controller lives in this State so it is disposed only after the dialog's
/// closing animation has finished (disposing it right after `showDialog` returns
/// caused "TextEditingController was used after being disposed").
class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog();

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: dir,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          'admin_resolve_unconfirmed_transfer'.tr,
          style: TextStyle(fontFamily: AppFonts.family),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'admin_check_the_provider_dashboard_did_the'.tr,
              style: TextStyle(fontFamily: AppFonts.family),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'admin_reference_if_sent'.tr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('exam_cancel'.tr),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _ResolveInput(false, '')),
            child: Text('admin_not_sent'.tr),
          ),
          TextButton(
            onPressed: () {
              final ref = _ctrl.text.trim();
              if (ref.isEmpty) {
                toast('admin_enter_the_reference'.tr, error: true);
                return;
              }
              Navigator.pop(context, _ResolveInput(true, ref));
            },
            child: Text('admin_sent'.tr),
          ),
        ],
      ),
    );
  }
}

class _PaidInput {
  const _PaidInput(this.reference, this.fileName, {this.filePath, this.bytes});

  final String reference;
  final String fileName;
  final String? filePath; // mobile / desktop
  final Uint8List? bytes; // web (no file path there)
}

/// Confirm a manual transfer: transfer reference + required receipt (image / PDF).
class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog();

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  static const _maxBytes = 10 * 1024 * 1024;
  final _ref = TextEditingController();
  PlatformFile? _file;
  Uint8List? _bytes; // web only (no file path there)

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  bool get _isPdf => (_file?.extension ?? '').toLowerCase() == 'pdf';

  Future<void> _pick() async {
    // file_picker v12+: pickFile() returns PlatformFile? (null if cancelled).
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (f == null) return;

    // Web has no file path — the bytes are the only way to read it.
    Uint8List? bytes;
    if (kIsWeb) {
      try {
        bytes = await f.readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (kIsWeb ? bytes == null : f.path == null) {
      toast('admin_receipt_read_failed'.tr, error: true);
      return;
    }

    // PlatformFile.size was removed in v12 — length is now a method.
    final size = bytes?.length ?? f.lengthSync() ?? await f.length() ?? 0;
    if (size > _maxBytes) {
      toast('admin_receipt_too_large'.tr, error: true);
      return;
    }
    setState(() {
      _file = f;
      _bytes = bytes;
    });
  }

  Widget _preview(PlatformFile f) {
    Widget broken(BuildContext _, Object _, StackTrace? _) =>
        const Center(child: Icon(Icons.broken_image_rounded, size: 40));
    if (kIsWeb) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        cacheWidth: 600,
        errorBuilder: broken,
      );
    }
    return Image.file(
      File(f.path!),
      fit: BoxFit.cover,
      cacheWidth: 600,
      errorBuilder: broken,
    );
  }

  void _submit() {
    if (_ref.text.trim().isEmpty) {
      toast('admin_enter_the_reference'.tr, error: true);
      return;
    }
    if (_file == null) {
      toast('admin_receipt_required'.tr, error: true);
      return;
    }
    final f = _file!;
    Navigator.pop(
      context,
      kIsWeb
          ? _PaidInput(_ref.text.trim(), f.name, bytes: _bytes)
          : _PaidInput(_ref.text.trim(), f.name, filePath: f.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: dir,
      child: AlertDialog(
        title: Text(
          'admin_transfer_reference_bank_instapay'.tr,
          style: TextStyle(fontFamily: AppFonts.family),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ref,
                decoration: InputDecoration(hintText: 'admin_transfer_ref'.tr),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlineButton(
                    color: context.colors.primary,
                    icon: Icons.attach_file_rounded,
                    label: _file == null
                        ? 'admin_attach_receipt'.tr
                        : 'admin_change_receipt'.tr,

                    onPressed: _pick,
                  ),
                ],
              ),
              if (_file != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        _isPdf
                            ? Icons.picture_as_pdf_rounded
                            : Icons.image_rounded,
                        color: c.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _file!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_file != null && !_isPdf)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  // FIXED size on purpose: AlertDialog measures its content with IntrinsicWidth, and an
                  // Image with width: double.infinity (or a full-resolution photo decode) there is what
                  // blanked the screen. cacheWidth keeps a 12 MP camera photo from being decoded in full.
                  child: SizedBox(
                    width: 232,
                    height: 140,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _preview(_file!),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('exam_cancel'.tr),
          ),
          TextButton(
            onPressed: _submit,
            child: Text('admin_confirm_transfer'.tr),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Teachers (who may withdraw)
// ═════════════════════════════════════════════════════════════════════════════

class _TeachersView extends StatelessWidget {
  const _TeachersView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminPayoutTeachersProvider>();
    return PagedList<AdminPayoutTeachersProvider>(
      header: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: SearchBox(
              hint: 'admin_search_teachers'.tr,
              onChanged: p.setSearch,
            ),
          ),
          FilterChips<String>(
            value: p.only ?? 'all',
            options: {
              'all': 'filter_all'.tr,
              'allowed': 'admin_allowed_2'.tr,
              'blocked': 'admin_blocked_2'.tr,
            },
            onChanged: (v) => p.setOnly(v == 'all' ? null : v),
          ),
          const SizedBox(height: 6),
        ],
      ),
      emptyText: 'admin_no_teachers'.tr,
      itemBuilder: (ctx, row) => _TeacherTile(row),
    );
  }
}

class _TeacherTile extends StatelessWidget {
  const _TeacherTile(this.row);

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminPayoutTeachersProvider>();
    final allowed = asBool(row['effective_allowed']);
    final override = row['override_enabled']; // true | false | null
    final methods = (row['effective_methods'] is List)
        ? (row['effective_methods'] as List).map((e) => '$e').toList()
        : <String>[];

    return RowCard(
      onTap: () => _sheet(context, p),
      child: Row(
        children: [
          Icon(
            allowed ? Icons.check_circle_rounded : Icons.block_rounded,
            color: allowed ? c.success : c.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asStr(row['name']),
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                Text(
                  asStr(row['gmail']),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusChip(
                      override == null
                          ? 'admin_follows_global'.tr
                          : (override == true
                          ? 'admin_allowed'.tr
                          : 'admin_blocked'.tr),
                      override == null
                          ? c.textLight
                          : (override == true ? c.success : c.danger),
                    ),
                    if (allowed)
                      StatusChip(
                        '${methods.length} ${'admin_methods'.tr}',
                        c.primary,
                      ),
                    StatusChip(
                      '${asInt(row['accounts_count'])} ${'admin_accounts'.tr}',
                      c.charcoal,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ],
      ),
    );
  }

  Future<void> _sheet(BuildContext context, AdminPayoutTeachersProvider p) {
    const all = ['bank_account', 'instapay', 'moyasar', 'paymob'];
    dynamic enabled = row['override_enabled'];
    bool restrict = row['override_methods'] != null;
    final chosen = <String>{
      ...(row['override_methods'] is List
          ? (row['override_methods'] as List).map((e) => '$e')
          : all),
    };
    bool busy = false;

    return showAdminSheet(context, (ctx) {
      return StatefulBuilder(
        builder: (ctx, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(asStr(row['name'])),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChoiceRow<dynamic>(
                        label: 'admin_withdrawal_permission'.tr,
                        options: {
                          null: 'admin_follow_global_setting'.tr,
                          true: 'admin_allow'.tr,
                          false: 'admin_block'.tr,
                        },
                        value: enabled,
                        onChanged: (v) => setS(() => enabled = v),
                      ),
                      AppSwitchTile(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        title: 'admin_custom_methods_for_this_teacher'.tr,
                        value: restrict,
                        onChanged: (v) => setS(() => restrict = v),
                      ),
                      if (restrict)
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final m in all)
                              FilterChip(
                                label: Text(
                                  payoutMethodLabel(m),
                                  style: TextStyle(fontFamily: AppFonts.family),
                                ),
                                selected: chosen.contains(m),
                                onSelected: (s) => setS(
                                      () => s ? chosen.add(m) : chosen.remove(m),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'save'.tr,
                        isLoading: busy,
                        onPressed: () async {
                          if (restrict && chosen.isEmpty) {
                            toast(
                              'admin_pick_at_least_one_method'.tr,
                              error: true,
                            );
                            return;
                          }
                          setS(() => busy = true);
                          // Both keys are always sent: null RESETS a field to "follow the global setting".
                          final ok = await p.save(asInt(row['id']), {
                            'enabled': enabled,
                            'allowed_methods': restrict
                                ? (all.where(chosen.contains).toList())
                                : null,
                          });
                          if (ctx.mounted) {
                            setS(() => busy = false);
                            if (ok) Navigator.pop(ctx);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Settings
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  final _min = TextEditingController();
  String? _filledFrom; // the server's minimum the field was last filled with
  bool _busy = false; // a save is in flight: the switches ignore taps (no double fire)

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  /// One save at a time; the settings provider replaces its data with the server's answer.
  Future<void> _save(AdminPayoutSettingsProvider p, Map<String, dynamic> body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await p.save(body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAll(AdminPayoutSettingsProvider p, bool v) async {
    final ok = await appConfirm(
      context,
      message: v
          ? t('سيتمكن كل المعلمين من إضافة حساب وطلب سحب أرباحهم. متابعة؟',
              'Every teacher will be able to add an account and withdraw their earnings. Continue?')
          : t('لن يتمكن إلا المعلمون الذين تسمح لهم واحدًا واحدًا من طلب السحب. متابعة؟',
              'Only the teachers you allow one by one will be able to request a withdrawal. Continue?'),
    );
    if (ok) await _save(p, {'payouts_enabled_for_all': v});
  }

  Future<void> _toggleAuto(AdminPayoutSettingsProvider p, bool v) async {
    final ok = await appConfirm(
      context,
      danger: v,
      message: v
          ? t('عند اعتماد طلب سحب عبر Moyasar أو Paymob سيُرسل المال للمعلم تلقائيًا فورًا. تفعيل التحويل التلقائي؟',
              'Approving a Moyasar or Paymob request will send the money to the teacher right away, automatically. Turn automatic transfer on?')
          : t('سيكتفي اعتماد الطلب بتسجيله، وتحوّل المبلغ بنفسك ثم تؤكد التحويل. إيقاف التحويل التلقائي؟',
              'Approving a request will only record it; you transfer the money yourself and then confirm. Turn automatic transfer off?'),
    );
    if (ok) await _save(p, {'payout_auto_enabled': v});
  }

  Future<void> _saveMin(AdminPayoutSettingsProvider p) async {
    final txt = _min.text.trim();
    final v = txt.isEmpty ? null : parseAmountLoose(txt);
    if (txt.isNotEmpty && (v == null || v < 0)) {
      toast('admin_invalid_amount'.tr, error: true);
      return;
    }
    await _save(p, {'payout_min_amount': v});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminPayoutSettingsProvider>();
    if (p.data.isEmpty) {
      return p.isLoading
          ? const AppLoadingState(shape: AppLoadingShape.form)
          : AppErrorState(message: p.error ?? 'admin_could_not_load'.tr, onRetry: p.load);
    }
    // (re)fill the field whenever the server's value changed: first load, a reload, or the answer to a save
    final serverMin = numText(p.minAmount);
    if (_filledFrom != serverMin) {
      _filledFrom = serverMin;
      _min.text = serverMin;
    }
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.md, gutter, AppSpace.lg),
      children: [
        AppCard(
          child: Column(
            children: [
              AppSwitchTile(
                title: 'admin_allow_all_teachers_to_withdraw'.tr,
                subtitle: p.all
                    ? 'admin_every_teacher_can_add_an_account_and'.tr
                    : 'admin_off_only_teachers_you_allow_one_by_one'.tr,
                value: p.all,
                onChanged: _busy ? null : (v) => _toggleAll(p, v),
              ),
              const Divider(),
              AppSwitchTile(
                title: 'admin_automatic_transfer_moyasar_paymob'.tr,
                subtitle: 'admin_on_approval_the_money_is_sent'.tr,
                value: p.auto,
                onChanged: _busy ? null : (v) => _toggleAuto(p, v),
              ),
            ],
          ),
        ),
        AppSpace.gapMd,
        AppSection(
          title: 'admin_available_payout_methods'.tr,
          child: AppCard(
            child: Column(
              children: [
                for (final m in p.methods)
                  AppSwitchTile(
                    title: t(asStr(m['label_ar']), asStr(m['label_en'])),
                    subtitle: asBool(m['automatic'])
                        ? (asBool(m['configured'])
                            ? '${'admin_ready'.tr} • ${asStr(m['currency'])}'
                            : 'admin_not_configured_on_the_server_falls'.tr)
                        : null,
                    value: p.allowed.contains(asStr(m['id'])),
                    onChanged: _busy
                        ? null
                        : (v) {
                            final next = <String>{...p.allowed};
                            v ? next.add(asStr(m['id'])) : next.remove(asStr(m['id']));
                            if (next.isEmpty) {
                              toast('admin_keep_at_least_one_method'.tr, error: true);
                              return;
                            }
                            _save(p, {'payout_allowed_methods': next.toList()});
                          },
                  ),
              ],
            ),
          ),
        ),
        AppSpace.gapMd,
        AppSection(
          title: 'admin_minimum_withdrawal'.tr,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppNumberField(
                  controller: _min,
                  label: '${'admin_amount_empty_default'.tr} ${money(p.defaultMin)})',
                  min: 0,
                  decimals: 2,
                  onSubmitted: (_) => _saveMin(p),
                ),
                AppSpace.gapSm,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton.primary(
                    label: 'save'.tr,
                    busy: _busy,
                    onPressed: _busy ? null : () => _saveMin(p),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
