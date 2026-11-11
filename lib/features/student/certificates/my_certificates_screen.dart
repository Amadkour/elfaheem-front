// features/student/certificates/my_certificates_screen.dart
//
// "My certificates" — every certificate of every course of the student.
//   • issued   → preview, download (AR / EN), full-screen view
//   • pending  → waiting for the teacher (can withdraw the request)
//   • available / rejected → "Request certificate" (teacher must approve)
//   • finished courses get their certificate automatically (+ notification)
//
// Editorial theme: "Certificates earned" is the page's one block — gold, because a certificate is an achievement
// (system.md §2) — with the count rolling (AppOdometer); each certificate is a paper card (preview, title, a status
// pill, the course chip, progress filling while it is not issued) with kit buttons.

import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import 'my_certificate_model.dart';
import 'my_certificates_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_verify_logic.dart' show kCertVerifyFeature;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_verify_page.dart' show openCertVerify;

class MyCertificatesScreen extends StatelessWidget {
  const MyCertificatesScreen({super.key, this.embedded = false});

  /// A tab of a page that has its own app bar (Grades and certificates).
  final bool embedded;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => MyCertificatesProvider()..load(),
        child: MyCertificatesView(embedded: embedded),
      );
}

bool _isArabic(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

void _toast(BuildContext context, String msg, {bool error = false}) {
  showAppNotice(msg, error: error);   // was always `error: true`: "saved" showed as an error
}

/// The page body over a [MyCertificatesProvider] in scope (the screen creates one; tests hand it filled values).
class MyCertificatesView extends StatelessWidget {
  const MyCertificatesView({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCertificatesProvider>();

    Widget body;
    if (p.loading && p.items.isEmpty) {
      body = const AppListSkeleton();
    } else if (p.loadFailed && p.items.isEmpty) {
      body = Center(child: AppErrorState(message: 'certificates_load_failed'.tr, onRetry: p.load));
    } else if (p.items.isEmpty) {
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: AppEmpty(icon: Icons.workspace_premium_outlined, title: 'my_certificates_empty'.tr, tone: AppBlockTone.gold),
        ),
      );
    } else {
      body = AppRefresh(
        onRefresh: p.load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
          itemCount: p.items.length + 1,
          // the block leads with more room under it than between the cards (the editorial rhythm)
          separatorBuilder: (_, i) => SizedBox(height: i == 0 ? AppSpace.lg : AppSpace.md),
          itemBuilder: (_, i) {
            if (i == 0) return _Summary(issued: p.issuedCount, total: p.items.length);
            return _CertificateCard(cert: p.items[i - 1]);
          },
        ),
      );
    }

    final centred = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.reading.max), child: body),
    );
    if (embedded) return centred;
    return Scaffold(
      appBar: ScreenAppBar( // the app's back chip + title (L4)
        title: 'my_certificates'.tr,
        actions: [
          ParentComponent(
            featureKey: kCertVerifyFeature,
            child: IconButton(
              tooltip: 'cv_entry_title'.tr,
              icon: const Icon(Icons.verified_user_outlined, size: AppIconSize.lg),
              onPressed: () => openCertVerify(context),
            ),
          ),
        ],
      ),
      body: SafeArea(child: centred),
    );
  }
}

/// "Certificates earned": the page's one block, gold (an achievement), the count rolling to its value.
class _Summary extends StatelessWidget {
  final int issued;
  final int total;

  const _Summary({required this.issued, required this.total});

  @override
  Widget build(BuildContext context) => AppBlock(
        tone: AppBlockTone.gold,
        child: Builder(builder: (context) {
          final c = context.colors;
          final ink = AppBlock.colorsOf(context);
          return Semantics(
            label: '${'certificates_earned'.tr}: $issued / $total',
            excludeSemantics: true,
            child: Row(children: [
              Container(
                width: AppTouch.primary,
                height: AppTouch.primary,
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Icon(Icons.workspace_premium_rounded, color: ink.accentInk(c.accent2), size: AppIconSize.xl),
              ),
              AppSpace.gapMd,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('certificates_earned'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink.muted)),
                  const SizedBox(height: AppSpace.xxs),
                  Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: AppSpace.xs, children: [
                    AppOdometer('$issued', memoryKey: 'my_certificates.issued', style: AppType.figureLarge(context).copyWith(color: ink.ink)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                      child: Text('/ $total', style: AppType.section(context).copyWith(color: ink.muted)),
                    ),
                  ]),
                ]),
              ),
            ]),
          );
        }),
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

    // paper on a warm hairline, no resting shadow (D-612); the preview opens full screen
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cert.isIssued)
          Semantics(
            button: true,
            label: cert.title,
            child: InkWell(
            onTap: () => _openFull(context, cert, ar),
            child: AspectRatio(
              aspectRatio: 1.41,
              child: Image.network(
                cert.urlFor(ar)!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) =>
                    prog == null ? child : AppShimmer(child: ColoredBox(color: c.divider.withValues(alpha: 0.7), child: const SizedBox.expand())),
                errorBuilder: (_, _, _) => Center(
                    child: Icon(Icons.broken_image_outlined, color: c.textLight, size: AppIconSize.hero)),
              ),
            ),
          ),
          ),
        Padding(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(cert.title, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              AppSpace.gapXs,
              Flexible(child: _StateChip(state: cert.state)),
            ]),
            AppSpace.gapXs,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: EntityChip(EntityRef(EntityKind.course, cert.courseId, label: cert.courseNameAr, labelEn: cert.courseNameEn)),
            ),
            if (cert.teacherName != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(cert.teacherName!, style: AppType.meta(context)),
            ],
            if (!cert.isIssued) ...[
              AppSpace.gapSm,
              _ProgressLine(value: (cert.progress / 100).clamp(0.0, 1.0)),
              const SizedBox(height: AppSpace.xxs),
              Text('${cert.progress.toStringAsFixed(0)}% ${'complete_label'.tr}', style: AppType.meta(context)),
            ],
            if (cert.state == MyCertState.rejected && (cert.rejectionReason ?? '').isNotEmpty) ...[
              AppSpace.gapXs,
              Text('${'certificate_rejected_reason'.tr}: ${cert.rejectionReason}',
                  style: AppType.meta(context).copyWith(color: appInk(context, c.danger))),
            ],
            AppSpace.gapMd,
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
        backgroundColor: context.colors.heroShade,
        insetPadding: const EdgeInsets.all(AppSpace.sm),
        child: Stack(children: [
          InteractiveViewer(
            child: Image.network(
              cert.urlFor(ar)!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => SizedBox(
                height: 240,
                child: Center(child: Icon(Icons.broken_image_outlined, color: context.colors.onHeroMuted, size: 40)),
              ),
            ),
          ),
          PositionedDirectional(
            top: AppSpace.xxs,
            end: AppSpace.xxs,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: Icon(Icons.close_rounded, color: context.colors.onHero),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The progress of a certificate that is not issued yet: a thin bar that fills once.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return ExcludeSemantics(
      child: SizedBox(
        height: AppSpace.xs - AppSpace.xxs / 2,
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: radius),
          child: AppFill(
            value: value,
            builder: (context, v) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: c.primary, borderRadius: radius)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final MyCertState state;

  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (state) {
      MyCertState.issued => ('cert_state_issued'.tr, AppTone.success),
      MyCertState.pending => ('cert_state_pending'.tr, AppTone.warning),
      MyCertState.readySoon => ('cert_state_ready_soon'.tr, AppTone.brand),
      MyCertState.rejected => ('cert_state_rejected'.tr, AppTone.danger),
      MyCertState.available => ('cert_state_available'.tr, AppTone.neutral),
    };
    return AppStatusBadge(label: label, tone: tone);
  }
}

class _Actions extends StatelessWidget {
  final MyCertificate cert;
  final bool busy;

  const _Actions({required this.cert, required this.busy});

  @override
  Widget build(BuildContext context) {
    final p = context.read<MyCertificatesProvider>();

    if (busy) {
      return const Center(child: SizedBox(width: AppIconSize.lg, height: AppIconSize.lg, child: AppLoadingIndicator()));
    }

    switch (cert.state) {
      case MyCertState.issued:
        return _DownloadButton(cert: cert);

      case MyCertState.pending:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.danger(
            label: 'cancel_certificate_request'.tr,
            icon: Icons.close_rounded,
            dangerOutline: true,
            onPressed: () async {
              final ok = await p.cancelRequest(cert.certificateId);
              if (context.mounted) {
                _toast(context, ok ? 'certificate_request_cancelled'.tr : 'certificate_action_failed'.tr, error: !ok);
              }
            },
          ),
        );

      case MyCertState.readySoon:
        return Text('certificate_being_prepared'.tr, style: AppType.meta(context));

      case MyCertState.rejected:
      case MyCertState.available:
        return AppButton.primary(
          label: 'request_certificate'.tr,
          icon: Icons.send_rounded,
          expand: true,
          onPressed: () => _askAndRequest(context, p),
        );
    }
  }

  Future<void> _askAndRequest(BuildContext context, MyCertificatesProvider p) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('request_certificate'.tr),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('request_certificate_hint'.tr, style: AppType.body(ctx)),
          AppSpace.gapSm,
          TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 500,
            style: appFieldTextStyle(ctx),
            decoration: appFieldDecoration(ctx, hint: 'certificate_request_note_hint'.tr),
          ),
        ]),
        actions: [
          AppButton.ghost(label: 'cancel'.tr, onPressed: () => Navigator.pop(ctx, false)),
          AppButton.primary(label: 'send_btn'.tr, icon: Icons.send_rounded, onPressed: () => Navigator.pop(ctx, true)),
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

    // the button keeps its width while the file is fetched (its spinner sits over the label)
    final download = AppButton.primary(
      label: 'download_certificate'.tr,
      icon: Icons.download_rounded,
      busy: downloading,
      expand: true,
      onPressed: downloading ? null : () => go(cert.hasArabic ? _isArabic(context) : false),
    );

    // Only one language exists (older certificates) → single button.
    if (!cert.hasArabic) return download;

    return Row(children: [
      Expanded(child: download),
      AppSpace.gapXs,
      PopupMenuButton<bool>(
        tooltip: 'certificate_other_language'.tr,
        enabled: !downloading,
        icon: Icon(Icons.translate_rounded, color: appInk(context, c.primary), size: AppIconSize.lg),
        onSelected: go,
        itemBuilder: (_) => [
          PopupMenuItem(value: true, child: Text('العربية')),
          const PopupMenuItem(value: false, child: Text('English')),
        ],
      ),
    ]);
  }
}
