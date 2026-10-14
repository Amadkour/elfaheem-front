// features/student/certificates/my_certificates_screen.dart
//
// "My certificates" — every certificate of every course of the student.
//   • issued   → preview, download (AR / EN), full-screen view
//   • pending  → waiting for the teacher (can withdraw the request)
//   • available / rejected → "Request certificate" (teacher must approve)
//   • finished courses get their certificate automatically (+ notification)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import 'my_certificate_model.dart';
import 'my_certificates_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class MyCertificatesScreen extends StatelessWidget {
  const MyCertificatesScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => MyCertificatesProvider()..load(),
        child: const _View(),
      );
}

bool _isArabic(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

void _toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
    backgroundColor: error ? context.colors.danger : context.colors.success,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
  ));
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCertificatesProvider>();
    final c = context.colors;

    Widget body;
    if (p.loading && p.items.isEmpty) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.loadFailed && p.items.isEmpty) {
      body = _Message(
        icon: Icons.cloud_off_rounded,
        text: 'certificates_load_failed'.tr,
        action: OutlinedButton(onPressed: p.load, child: Text('retry'.tr)),
      );
    } else if (p.items.isEmpty) {
      body = _Message(icon: Icons.workspace_premium_outlined, text: 'my_certificates_empty'.tr);
    } else {
      body = RefreshIndicator(
        onRefresh: p.load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          itemCount: p.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i == 0) return _Summary(issued: p.issuedCount, total: p.items.length);
            return _CertificateCard(cert: p.items[i - 1]);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('my_certificates'.tr, style: c.h2.copyWith(fontSize: 16)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: context.colors.textLight),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: context.colors.body),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}

class _Summary extends StatelessWidget {
  final int issued;
  final int total;

  const _Summary({required this.issued, required this.total});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: context.colors.primaryGradient,
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        ),
        child: Row(children: [
          const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${'certificates_earned'.tr}: $issued / $total',
              style: const TextStyle(
                  fontFamily: 'tajawal', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      );
}

class _CertificateCard extends StatelessWidget {
  final MyCertificate cert;

  const _CertificateCard({required this.cert});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = _isArabic(context);
    final p = context.watch<MyCertificatesProvider>();
    final busy = p.busyCertIds.contains(cert.certificateId);

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cert.isIssued)
          GestureDetector(
            onTap: () => _openFull(context, cert, ar),
            child: AspectRatio(
              aspectRatio: 1.41,
              child: Image.network(
                cert.urlFor(ar)!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) =>
                    prog == null ? child : const Center(child: AppLoadingIndicator()),
                errorBuilder: (_, _, _) => Center(
                    child: Icon(Icons.broken_image_outlined, color: c.textLight, size: 40)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(cert.title,
                    style: c.h3.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              _StateChip(state: cert.state),
            ]),
            const SizedBox(height: 4),
            Text(cert.courseName(ar), style: c.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (cert.teacherName != null)
              Text(cert.teacherName!, style: c.caption.copyWith(color: c.textLight, fontSize: 11)),
            if (!cert.isIssued) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (cert.progress / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: c.primary.withValues(alpha: 0.12),
                  color: c.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text('${cert.progress.toStringAsFixed(0)}% ${'complete_label'.tr}',
                  style: c.caption.copyWith(fontSize: 11)),
            ],
            if (cert.state == MyCertState.rejected && (cert.rejectionReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${'certificate_rejected_reason'.tr}: ${cert.rejectionReason}',
                  style: c.caption.copyWith(color: c.danger)),
            ],
            const SizedBox(height: 12),
            _Actions(cert: cert, busy: busy),
          ]),
        ),
      ]),
    );
  }

  void _openFull(BuildContext context, MyCertificate cert, bool ar) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(child: Image.network(cert.urlFor(ar)!, fit: BoxFit.contain)),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final MyCertState state;

  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, color) = switch (state) {
      MyCertState.issued => ('cert_state_issued'.tr, c.success),
      MyCertState.pending => ('cert_state_pending'.tr, const Color(0xFFE59A1F)),
      MyCertState.readySoon => ('cert_state_ready_soon'.tr, c.primary),
      MyCertState.rejected => ('cert_state_rejected'.tr, c.danger),
      MyCertState.available => ('cert_state_available'.tr, c.textMedium),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'tajawal', fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _Actions extends StatelessWidget {
  final MyCertificate cert;
  final bool busy;

  const _Actions({required this.cert, required this.busy});

  @override
  Widget build(BuildContext context) {
    final p = context.read<MyCertificatesProvider>();
    final c = context.colors;

    if (busy) {
      return const Center(child: SizedBox(width: 22, height: 22, child: AppLoadingIndicator()));
    }

    switch (cert.state) {
      case MyCertState.issued:
        return _DownloadButton(cert: cert);

      case MyCertState.pending:
        return OutlinedButton.icon(
          onPressed: () async {
            final ok = await p.cancelRequest(cert.certificateId);
            if (context.mounted) {
              _toast(context, ok ? 'certificate_request_cancelled'.tr : 'certificate_action_failed'.tr,
                  error: !ok);
            }
          },
          icon: const Icon(Icons.close_rounded, size: 16),
          label: Text('cancel_certificate_request'.tr),
          style: OutlinedButton.styleFrom(foregroundColor: c.danger),
        );

      case MyCertState.readySoon:
        return Text('certificate_being_prepared'.tr, style: c.caption);

      case MyCertState.rejected:
      case MyCertState.available:
        return Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _askAndRequest(context, p),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text('request_certificate'.tr),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]);
    }
  }

  Future<void> _askAndRequest(BuildContext context, MyCertificatesProvider p) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('request_certificate'.tr),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('request_certificate_hint'.tr),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'certificate_request_note_hint'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('send_btn'.tr)),
        ],
      ),
    );
    final note = controller.text;
    controller.dispose();
    if (confirmed != true) return;

    final status = await p.requestCertificate(cert.certificateId, note: note);
    if (!context.mounted) return;
    if (status == 'issued') {
      _toast(context, 'certificate_issued_now'.tr);
    } else if (status == 'pending') {
      _toast(context, 'certificate_request_sent'.tr);
    } else {
      _toast(context, 'certificate_action_failed'.tr, error: true);
    }
  }
}

class _DownloadButton extends StatelessWidget {
  final MyCertificate cert;

  const _DownloadButton({required this.cert});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCertificatesProvider>();
    final c = context.colors;
    final downloading = p.downloadingIds.contains(cert.certificateId);

    Future<void> go(bool arabic) async {
      final ok = await p.download(cert, arabic: arabic);
      if (context.mounted) {
        _toast(context, ok ? 'certificate_saved'.tr : 'certificate_action_failed'.tr, error: !ok);
      }
    }

    if (downloading) {
      return const Center(child: SizedBox(width: 22, height: 22, child: AppLoadingIndicator()));
    }

    // Only one language exists (older certificates) → single button.
    if (!cert.hasArabic) {
      return ElevatedButton.icon(
        onPressed: () => go(false),
        icon: const Icon(Icons.download_rounded, size: 18),
        label: Text('download_certificate'.tr),
        style: ElevatedButton.styleFrom(backgroundColor: c.primary, foregroundColor: Colors.white),
      );
    }

    return Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () => go(_isArabic(context)),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text('download_certificate'.tr),
          style: ElevatedButton.styleFrom(backgroundColor: c.primary, foregroundColor: Colors.white),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<bool>(
        tooltip: 'certificate_other_language'.tr,
        icon: Icon(Icons.translate_rounded, color: c.primary),
        onSelected: go,
        itemBuilder: (_) => [
          PopupMenuItem(value: true, child: Text('العربية')),
          const PopupMenuItem(value: false, child: Text('English')),
        ],
      ),
    ]);
  }
}
