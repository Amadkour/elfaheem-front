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

import 'package:provider/provider.dart';

import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/outline_button.dart';
import '../../utils/widget/primary_button.dart';
import '../teacher/profile/payout/teacher_payouts_screen.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'receipt_viewer.dart';
import 'admin_providers.dart';

class AdminPayoutsPage extends StatelessWidget {
  const AdminPayoutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DefaultTabController(
      length: 3,
      child: BasePage(
        useWebCard: true,
        appBar: AppBar(
          title: Text(
            'admin_teacher_payouts'.tr,
            style: const TextStyle(fontFamily: 'tajawal'),
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: 'admin_requests'.tr),
              Tab(text: 'admin_teachers'.tr),
              Tab(text: 'admin_settings'.tr),
            ],
          ),
        ),
        child: const TabBarView(
          children: [_RequestsTab(), _TeachersTab(), _SettingsTab()],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Requests
// ═════════════════════════════════════════════════════════════════════════════

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminPayoutRequestsProvider()..refresh(),
    child: const _RequestsView(),
  );
}

class _RequestsView extends StatefulWidget {
  const _RequestsView();

  @override
  State<_RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<_RequestsView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        context.read<AdminPayoutRequestsProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminPayoutRequestsProvider>();

    Widget list;
    if (!p.loaded && p.isLoading) {
      list = const Center(child: AppLoadingIndicator());
    } else if (p.error != null && p.rows.isEmpty) {
      list = ErrorRetry(message: p.error!, onRetry: p.refresh);
    } else if (p.rows.isEmpty) {
      list = EmptyState('admin_no_requests'.tr);
    } else {
      final items = p.items;
      list = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 60),
        itemCount: items.length + 1,
        itemBuilder: (ctx, i) => i == items.length
            ? (p.loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: AppLoadingIndicator()),
                    )
                  : const SizedBox(height: 30))
            : _RequestCard(items[i]),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        FilterChips<String>(
          value: p.status ?? 'all',
          options: {
            'pending': 'admin_pending_3'.tr,
            'approved': 'admin_approved'.tr,
            'paid': 'admin_paid_2'.tr,
            'rejected': 'admin_rejected'.tr,
            'all': 'filter_all'.tr,
          },
          onChanged: (v) => p.setStatus(v == 'all' ? null : v),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: RefreshIndicator(onRefresh: p.refresh, child: list),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.w);

  final Withdrawal w;

  Color _stateColor(BuildContext context) {
    final c = context.colors;
    switch (w.state) {
      case 'paid':
        return c.success;
      case 'processing':
        return c.primary;
      case 'failed':
        return c.danger;
      case 'unknown':
        return c.warning;
    }
    return c.textLight;
  }

  String get _stateLabel {
    switch (w.state) {
      case 'paid':
        return 'admin_provider_paid'.tr;
      case 'processing':
        return 'admin_processing_at_provider'.tr;
      case 'failed':
        return 'admin_transfer_failed'.tr;
      case 'unknown':
        return 'admin_unconfirmed'.tr;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminPayoutRequestsProvider>();
    final busy = p.busy.contains(w.id);
    final approvedAuto = w.status == 'approved' && w.provider != null;

    return RowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  w.teacherName.isEmpty ? '#${w.teacherId}' : w.teacherName,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
              ),
              Text(
                money(w.amount),
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: c.primary,
                ),
              ),
            ],
          ),
          Text(
            w.teacherGmail,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 12,
              color: c.textLight,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusChip(
                statusLabel(w.status),
                w.status == 'paid'
                    ? c.success
                    : (w.status == 'rejected'
                          ? c.danger
                          : (w.status == 'approved' ? c.primary : c.warning)),
              ),
              StatusChip(payoutMethodLabel(w.method), c.charcoal),
              if (w.state != 'none')
                StatusChip(_stateLabel, _stateColor(context)),
            ],
          ),
          const SizedBox(height: 8),
          KeyValue('account'.tr, payoutDestinationSummary(w.destination)),
          if (w.providerStatus != null)
            KeyValue('admin_provider'.tr, w.providerStatus!),
          if (w.providerReference != null)
            KeyValue('admin_reference'.tr, w.providerReference!),
          if (w.bankReference != null)
            KeyValue('admin_transfer_ref'.tr, w.bankReference!),
          if (w.receiptUrl != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: Text('admin_view_receipt'.tr),
                onPressed: () async {
                  final p = context.read<AdminPayoutRequestsProvider>();
                  final link = await p.receiptLink(w.id);
                  if (!context.mounted) return;
                  await openReceipt(context, link);
                },
              ),
            ),
          if (w.note != null) KeyValue('admin_teacher_note'.tr, w.note!),
          if (w.rejectedReason != null)
            KeyValue('admin_reason'.tr, w.rejectedReason!),
          if (w.error != null && w.state != 'paid')
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                w.error!,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 12,
                  color: c.danger,
                ),
              ),
            ),
          KeyValue('admin_requested'.tr, shortDateTime(w.requestedAt)),
          const SizedBox(height: 10),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(6),
                child: AppLoadingIndicator(),
              ),
            )
          else ...[
            if (w.status == 'pending')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.success,
                      ),
                      icon: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                      ),
                      label: Text(
                        w.automatic
                            ? 'admin_approve_send'.tr
                            : 'request_approve'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'tajawal',
                        ),
                      ),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          message: w.automatic
                              ? trp(
                                  'admin_approving_sends_right_now_via_continue',
                                  {
                                    'amount': money(w.amount),
                                    'method': payoutMethodLabel(w.method),
                                  },
                                )
                              : 'admin_approve_this_request_you_will_transfer'
                                    .tr,
                          confirmLabel: 'request_approve'.tr,
                        );
                        if (ok) await p.approve(w.id);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlineButton(
                    color: context.colors.danger,
                    label: 'request_reject'.tr,
                    onPressed: () async {
                      final reason = await askText(
                        context,
                        title: 'rejection_reason_title'.tr,
                        multiline: true,
                      );
                      if (reason != null && reason.isNotEmpty)
                        await p.reject(w.id, reason);
                    },
                    icon: Icons.close_rounded,
                  ),
                ],
              ),
            if (w.status == 'approved' && w.state == 'processing')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.sync_rounded),
                      label: Text('admin_sync_status'.tr),
                      onPressed: () => p.sync(w.id),
                    ),
                  ),
                ],
              ),
            if (approvedAuto &&
                (w.state == 'failed' ||
                    w.state == 'unknown' ||
                    w.state == 'none'))
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.replay_rounded,
                        color: Colors.white,
                      ),
                      label: Text(
                        'retry'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'tajawal',
                        ),
                      ),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          message: w.state == 'unknown'
                              ? 'admin_it_is_re_sent_with_the_same'.tr
                              : 'admin_send_the_transfer_again'.tr,
                        );
                        if (ok) await p.retry(w.id);
                      },
                    ),
                  ),
                  if (w.state == 'unknown') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _resolveDialog(context, p),
                        child: Text('admin_resolve'.tr),
                      ),
                    ),
                  ],
                ],
              ),
            if (w.status == 'approved' && w.state != 'processing')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    OutlineButton(
                      color: context.colors.primary,
                      label: 'admin_mark_paid_manual'.tr,
                      onPressed: () async {
                        await _markPaid(context, p);
                      },
                      icon: Icons.price_check_rounded,
                    ),

                    if (w.state != 'unknown') ...[
                      const SizedBox(width: 8),
                      OutlineButton(
                        color: context.colors.danger,
                        label: 'request_reject'.tr,
                        onPressed: () async {
                          final reason = await askText(
                            context,
                            title: 'rejection_reason_title'.tr,
                            multiline: true,
                          );
                          if (reason != null && reason.isNotEmpty) {
                            await p.reject(w.id, reason);
                          }
                        },
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _markPaid(
    BuildContext context,
    AdminPayoutRequestsProvider p,
  ) async {
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

  Future<void> _resolveDialog(
    BuildContext context,
    AdminPayoutRequestsProvider p,
  ) async {
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
        title: Text(
          'admin_resolve_unconfirmed_transfer'.tr,
          style: const TextStyle(fontFamily: 'tajawal'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'admin_check_the_provider_dashboard_did_the'.tr,
              style: const TextStyle(fontFamily: 'tajawal'),
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

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  bool get _isPdf => (_file?.extension ?? '').toLowerCase() == 'pdf';

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData:
          kIsWeb, // web has no file path — the bytes are the only way to read it
    );
    final f = res?.files.single;
    if (f == null) return;
    if (kIsWeb ? f.bytes == null : f.path == null) {
      toast('admin_receipt_read_failed'.tr, error: true);
      return;
    }
    if (f.size > _maxBytes) {
      toast('admin_receipt_too_large'.tr, error: true);
      return;
    }
    setState(() => _file = f);
  }

  Widget _preview(PlatformFile f) {
    Widget broken(BuildContext _, Object __, StackTrace? ___) =>
        const Center(child: Icon(Icons.broken_image_rounded, size: 40));
    if (kIsWeb) {
      return Image.memory(
        f.bytes!,
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
          ? _PaidInput(_ref.text.trim(), f.name, bytes: f.bytes)
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
          style: const TextStyle(fontFamily: 'tajawal'),
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
                          style: const TextStyle(
                            fontFamily: 'tajawal',
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

class _TeachersTab extends StatelessWidget {
  const _TeachersTab();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminPayoutTeachersProvider()..refresh(),
    child: const _TeachersView(),
  );
}

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
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                Text(
                  asStr(row['gmail']),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'admin_custom_methods_for_this_teacher'.tr,
                          style: const TextStyle(fontFamily: 'tajawal'),
                        ),
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
                                  style: const TextStyle(fontFamily: 'tajawal'),
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

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminPayoutSettingsProvider()..load(),
    child: const _SettingsView(),
  );
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  final _min = TextEditingController();
  bool _filled = false;
  bool busy = false;

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminPayoutSettingsProvider>();
    final c = context.colors;
    if (p.data.isEmpty) {
      return p.isLoading
          ? const Center(child: AppLoadingIndicator())
          : ErrorRetry(
              message: p.error ?? 'admin_could_not_load'.tr,
              onRetry: p.load,
            );
    }
    if (!_filled) {
      _filled = true;
      _min.text = p.minAmount?.toString() ?? '';
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: p.all ? c.primary : c.divider,
              width: p.all ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'admin_allow_all_teachers_to_withdraw'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                subtitle: Text(
                  p.all
                      ? 'admin_every_teacher_can_add_an_account_and'.tr
                      : 'admin_off_only_teachers_you_allow_one_by_one'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
                value: p.all,
                activeTrackColor: c.primary,
                onChanged: (v) => p.save({'payouts_enabled_for_all': v}),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'admin_automatic_transfer_moyasar_paymob'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                subtitle: Text(
                  'admin_on_approval_the_money_is_sent'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
                value: p.auto,
                activeTrackColor: c.primary,
                onChanged: (v) => p.save({'payout_auto_enabled': v}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Section(
          title: 'admin_available_payout_methods'.tr,
          child: Column(
            children: [
              for (final m in p.methods)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: p.allowed.contains(asStr(m['id'])),
                  title: Text(
                    t(asStr(m['label_ar']), asStr(m['label_en'])),
                    style: const TextStyle(fontFamily: 'tajawal'),
                  ),
                  subtitle: asBool(m['automatic'])
                      ? Text(
                          asBool(m['configured'])
                              ? '${'admin_ready'.tr} • ${asStr(m['currency'])}'
                              : 'admin_not_configured_on_the_server_falls'.tr,
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            fontSize: 12,
                            color: asBool(m['configured'])
                                ? c.success
                                : c.warning,
                          ),
                        )
                      : null,
                  onChanged: (v) {
                    final next = <String>{...p.allowed};
                    v == true
                        ? next.add(asStr(m['id']))
                        : next.remove(asStr(m['id']));
                    if (next.isEmpty) {
                      toast('admin_keep_at_least_one_method'.tr, error: true);
                      return;
                    }
                    p.save({'payout_allowed_methods': next.toList()});
                  },
                ),
            ],
          ),
        ),
        Section(
          title: 'admin_minimum_withdrawal'.tr,
          child: Column(
            children: [
              Field(
                controller: _min,
                label:
                    '${'admin_amount_empty_default'.tr} ${money(p.defaultMin)})',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              PrimaryButton(
                label: 'save'.tr,
                isLoading: busy,
                onPressed: () async {
                  final txt = _min.text.trim();
                  final v = txt.isEmpty ? null : double.tryParse(txt);
                  if (txt.isNotEmpty && (v == null || v < 0)) {
                    toast('admin_invalid_amount'.tr, error: true);
                    return;
                  }
                  setState(() => busy = true);
                  await p.save({'payout_min_amount': v});
                  if (mounted) setState(() => busy = false);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
