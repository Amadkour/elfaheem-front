/// teacher_transfers_screen.dart — teacher's "Payment requests" screen:
/// review bank-transfer / InstaPay proofs and accept or reject them.
///
/// Open from the teacher dashboard:
///   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTransfersScreen()));
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../student/enrollment/enrollment_models.dart';
import 'teacher_transfers_provider.dart';

class TeacherTransfersScreen extends StatelessWidget {
  const TeacherTransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TeacherTransfersProvider()..load(),
      child: const _TransfersView(),
    );
  }
}

class _TransfersView extends StatelessWidget {
  const _TransfersView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherTransfersProvider>();
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: const ScreenAppBar(title: 'طلبات الدفع بالتحويل'),
      body: RefreshIndicator(
        onRefresh: p.load,
        child: p.isLoading && p.items.isEmpty
            ? const Center(child: AppLoadingIndicator())
            : p.items.isEmpty
            ? ListView(children: [
          const SizedBox(height: 120),
          Center(
            child: Column(children: [
              Icon(Icons.inbox_rounded, size: 48, color: c.textLight),
              const SizedBox(height: 12),
              Text('لا توجد طلبات بانتظار المراجعة', style: c.body),
            ]),
          ),
        ])
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: p.items.length,
          itemBuilder: (_, i) => _TransferCard(transfer: p.items[i]),
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final PendingTransfer transfer;
  const _TransferCard({required this.transfer});

  Future<void> _confirmReject(BuildContext context) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب الرفض'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'اكتب سبب رفض هذا الطلب'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await context.read<TeacherTransfersProvider>().reject(transfer.paymentId, reason);
  }

  void _openImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(transfer.proofImageUrl))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = context.watch<TeacherTransfersProvider>().isProcessing(transfer.paymentId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(transfer.isBankTransfer ? 'تحويل بنكي' : 'إنستاباي',
                style: c.caption.copyWith(color: c.primary, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Text('${transfer.amount.toStringAsFixed(2)} ${transfer.currency}',
              style: c.h3.copyWith(fontSize: 15, color: c.primary)),
        ]),
        const SizedBox(height: 10),
        Text(transfer.courseName, style: c.label.copyWith(fontWeight: FontWeight.w700)),
        Text('الطالب: ${transfer.studentName}', style: c.caption),
        const SizedBox(height: 8),
        Text('المُرسِل: ${transfer.senderName}', style: c.body.copyWith(fontSize: 13)),
        if (transfer.senderPhone?.isNotEmpty ?? false)
          Text('هاتف المُرسِل: ${transfer.senderPhone}', style: c.caption),
        if (transfer.transferReference?.isNotEmpty ?? false)
          Text('رقم المرجع: ${transfer.transferReference}', style: c.caption),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _openImage(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(transfer.proofImageUrl, height: 140, width: double.infinity, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : () => _confirmReject(context),
              style: OutlinedButton.styleFrom(foregroundColor: c.danger,side: BorderSide(color:  c.danger)),
              child: const Text('رفض'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : () => context.read<TeacherTransfersProvider>().approve(transfer.paymentId),
              style: FilledButton.styleFrom(backgroundColor: c.success),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: AppLoadingIndicator())
                  : const Text('قبول'),
            ),
          ),
        ]),
      ]),
    );
  }
}