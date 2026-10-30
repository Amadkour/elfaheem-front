// features/teacher/certificates/certificate_requests_screen.dart
//
// Teacher inbox: approve → the student gets the certificate automatically
// (email + in-app notification); reject → the student is notified.

import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import 'certificate_requests_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppEmpty;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/core/display/app_fonts.dart';

class CertificateRequestsScreen extends StatelessWidget {
  const CertificateRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => CertificateRequestsProvider()..load(),
        child: const _View(),
      );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateRequestsProvider>();

    final body = CertificateRequestsBody(
      loading: p.loading,
      error: p.hasError ? (p.errorMessage ?? 'pl_requests_load_failed'.tr) : null,
      count: p.items.length,
      onRefresh: p.load,
      itemBuilder: (_, i) => _RequestCard(item: p.items[i]),
    );

    return Scaffold(
      appBar: ScreenAppBar(title: 'certificate_requests'.tr), // the app's back chip + title (L4)
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
        ),
      ),
    );
  }
}

/// The page body from plain values (loading · error · empty · list), so the layout harness can pump it.
class CertificateRequestsBody extends StatelessWidget {
  const CertificateRequestsBody({
    super.key,
    required this.loading,
    required this.error,
    required this.count,
    required this.onRefresh,
    required this.itemBuilder,
  });

  final bool loading;
  final String? error;
  final int count;
  final Future<void> Function() onRefresh;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (loading && count == 0) return const AppListSkeleton();
    // A failed first load used to show "no requests" — say it failed and offer a retry instead.
    if (error != null && count == 0) return ErrorRetry(message: error!, onRetry: () => onRefresh());
    if (count == 0) {
      return AppRefresh(
        onRefresh: onRefresh,
        scrollable: false,
        child: AppEmpty(icon: Icons.mark_email_read_outlined, title: 'no_certificate_requests'.tr),
      );
    }
    return AppRefresh(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final CertificateRequestItem item;

  const _RequestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final p = context.read<CertificateRequestsProvider>();
    final busy = context.watch<CertificateRequestsProvider>().busyIds.contains(item.requestId);

    void toast(String m, {bool error = false}) => showAppNotice(m, error: true);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: c.primary.withValues(alpha: 0.12),
            backgroundImage: (item.studentImageUrl ?? '').isNotEmpty
                ? NetworkImage(item.studentImageUrl!)
                : null,
            child: (item.studentImageUrl ?? '').isEmpty
                ? Text(item.studentName.isNotEmpty ? item.studentName[0].toUpperCase() : '?',
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w800))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.studentName,
                  style: TextStyle(
                      fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w800)),
              Text('${item.courseName(ar)} · ${item.certificateTitle}',
                  style: c.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (item.progress / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: c.primary.withValues(alpha: 0.12),
            color: c.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text('${item.progress.toStringAsFixed(0)}% ${'complete_label'.tr}',
            style: c.caption.copyWith(fontSize: 11)),
        if ((item.note ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('“${item.note}”', style: c.body.copyWith(fontSize: 13)),
        ],
        const SizedBox(height: 12),
        if (busy)
          const Center(child: SizedBox(width: 22, height: 22, child: AppLoadingIndicator()))
        else
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final reason = await _askReason(context);
                  if (reason == null) return;
                  final ok = await p.reject(item.requestId, reason: reason);
                  toast(ok ? 'certificate_request_rejected'.tr : 'certificate_action_failed'.tr,
                      error: !ok);
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text('reject'.tr),
                style: OutlinedButton.styleFrom(foregroundColor: c.danger),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ok = await p.approve(item.requestId);
                  toast(ok ? 'certificate_request_approved'.tr : 'certificate_action_failed'.tr,
                      error: !ok);
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text('approve_and_send'.tr),
                style: ElevatedButton.styleFrom(backgroundColor: c.success, foregroundColor: c.onHero),
              ),
            ),
          ]),
      ]),
    );
  }

  /// Returns the (possibly empty) reason, or null when the dialog was cancelled.
  Future<String?> _askReason(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('reject_certificate_request'.tr),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'rejection_reason_optional'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('reject'.tr)),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    return ok == true ? text : null;
  }
}
