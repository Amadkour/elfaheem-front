// lib/features/certificates/issue/cert_verify_view.dart
//
// What a visitor sees on the verification page (D-420), plain values only: the entry card (type a number or scan), and
// the result: Real or Fake first, then valid / expired / revoked and the expiry, then every public fact. The verdict
// is the server's; nothing here reads the device clock. `cert_verify_page.dart` owns the state and the calls.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_issue_parts.dart' show IssueErrorBox;

enum VerifyState { entry, loading, found, notFound, foreign, error }

/// Amber is too light for white words on the hero, or for coloured words on a light card.
Color _deepAmber(Color warning) {
  final hsl = HSLColor.fromColor(warning);
  return hsl.withLightness(hsl.lightness.clamp(0.0, 0.34)).toColor();
}

class CertVerifyEntry extends StatelessWidget {
  const CertVerifyEntry({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.onScan,
    this.fieldError,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;

  /// Null where there is no camera path (web, desktop): the card says so and typing is the way in.
  final VoidCallback? onScan;
  final String? fieldError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.verified_user_outlined, color: c.primary, size: AppIconSize.xl),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text('cv_entry_title'.tr, textAlign: TextAlign.center, style: AppType.pageTitle(context)),
        const SizedBox(height: AppSpace.xxs),
        Text('cv_entry_sub'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.lg),
        AppField(
          key: const ValueKey('cv.number'),
          controller: controller,
          label: 'cv_number_label'.tr,
          hint: 'NB-2026-ABC234',
          ltr: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSubmit(),
        ),
        if (fieldError != null) ...[
          Text(fieldError!, key: const ValueKey('cv.error'), style: AppType.meta(context).copyWith(color: c.danger)),
          const SizedBox(height: AppSpace.sm),
        ],
        AppButton.primary(
          key: const ValueKey('cv.verify'),
          onPressed: onSubmit,
          icon: Icons.verified_outlined,
          label: 'cv_verify'.tr,
          expand: true,
        ),
        const SizedBox(height: AppSpace.sm),
        if (onScan != null)
          AppButton.secondary(
            key: const ValueKey('cv.scan'),
            onPressed: onScan,
            icon: Icons.qr_code_scanner_rounded,
            label: 'cv_scan'.tr,
            expand: true,
          )
        else
          Text('cv_no_camera'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
      ]),
    );
  }
}

class CertVerifyView extends StatelessWidget {
  const CertVerifyView({
    super.key,
    required this.state,
    this.result,
    this.lang,
    this.onLang,
    this.onRetry,
    this.errorText,
    this.imageBuilder,
    this.entry,
    this.queried,
    this.foreignHost,
    this.onAnother,
  });

  final VerifyState state;
  final VerifyResult? result;
  final String? lang;
  final ValueChanged<String>? onLang;
  final VoidCallback? onRetry;
  final String? errorText;

  /// Draws the certificate image (network in the app; the layout test passes a box).
  final Widget Function(String url)? imageBuilder;

  /// [VerifyState.entry]: the form.
  final Widget? entry;

  /// The number that was checked (a fake answer repeats it).
  final String? queried;

  /// [VerifyState.foreign]: the host the code points at, never a link.
  final String? foreignHost;
  final VoidCallback? onAnother;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = switch (state) {
      VerifyState.entry => entry ?? const SizedBox.shrink(),
      VerifyState.loading => const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero),
      VerifyState.notFound => _fake(context),
      VerifyState.foreign => _hero(context, c.danger, Icons.gpp_bad_rounded, 'cv_foreign_title'.tr,
          (foreignHost ?? '').isEmpty ? 'cv_foreign_sub_nohost'.tr : 'cv_foreign_sub'.tr.replaceAll('{host}', foreignHost!)),
      VerifyState.error => IssueErrorBox(message: errorText ?? 'ci_verify_error'.tr, onRetry: onRetry),
      VerifyState.found => _found(context, result!),
    };
    final showAnother = onAnother != null && (state == VerifyState.found || state == VerifyState.notFound || state == VerifyState.foreign);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            content,
            if (showAnother) ...[
              const SizedBox(height: AppSpace.md),
              AppButton.secondary(
                key: const ValueKey('cv.another'),
                onPressed: onAnother,
                icon: Icons.refresh_rounded,
                label: 'cv_another'.tr,
                expand: true,
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, Color col, IconData icon, String title, String sub) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppMeshSurface(
        color: col,
        seed: 11,
        radius: AppRadius.cardAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: c.heroGlass,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.heroGlassBorder),
                ),
                child: Icon(icon, color: c.onHero, size: AppIconSize.hero),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(title, textAlign: TextAlign.center, style: AppType.pageTitle(context).copyWith(color: c.onHero)),
            const SizedBox(height: AppSpace.xs),
            Text(sub, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.onHero, height: 1.5)),
          ]),
        ),
      ),
    );
  }

  Widget _fake(BuildContext context) {
    final c = context.colors;
    final byNumber = (queried ?? '').isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _hero(context, c.danger, Icons.gpp_bad_rounded, 'cv_fake'.tr, byNumber ? 'cv_fake_sub_number'.tr : 'cv_fake_sub_link'.tr),
      if (byNumber) ...[
        const SizedBox(height: AppSpace.md),
        AppCard(child: _fact(context, Icons.tag_rounded, 'cv_number_checked'.tr, queried!, ltr: true)),
      ],
    ]);
  }

  Widget _found(BuildContext context, VerifyResult r) {
    final c = context.colors;
    final (Color tone, IconData icon, String title, String sub) = switch (r.state) {
      CertVerifyStatus.valid => (c.success, Icons.verified_rounded, 'cv_real'.tr, 'cv_real_valid_sub'.tr),
      CertVerifyStatus.expired => (_deepAmber(c.warning), Icons.verified_rounded, 'cv_real'.tr, 'cv_real_expired_sub'.tr),
      CertVerifyStatus.revoked => (c.danger, Icons.block_rounded, 'cv_real_revoked'.tr, r.replaced ? 'cv_replaced_sub'.tr : 'cv_real_revoked_sub'.tr),
    };
    final langs = r.imageLangs;
    final shown = langs.contains(lang) ? lang! : (langs.isEmpty ? null : langs.first);
    final facts = <(IconData, String, String, bool)>[
      (Icons.person_outline_rounded, 'ci_verify_recipient'.tr, r.recipientName, false),
      if (r.title != null) (Icons.workspace_premium_outlined, 'ci_verify_cert'.tr, r.title!, false),
      if (r.courseName != null) (Icons.menu_book_outlined, 'cv_course'.tr, r.courseName!, false),
      if (r.issuer != null) (Icons.apartment_rounded, 'ci_verify_issuer'.tr, r.issuer!, false),
      if (r.organization != null && r.organization != r.issuer) (Icons.account_balance_outlined, 'cv_org'.tr, r.organization!, false),
      if (r.teacherName != null) (Icons.school_outlined, 'cv_teacher'.tr, r.teacherName!, false),
      if (r.issuedAt != null) (Icons.event_outlined, 'ci_verify_date'.tr, AppTime.date(r.issuedAt!), false),
      if (r.revoked && r.revokedAt != null) (Icons.block_rounded, 'ci_verify_revoked_on'.tr, AppTime.date(r.revokedAt!), false),
      for (final d in r.details) (_detailIcon(d.key), d.label, d.value, false),
      (Icons.tag_rounded, 'ci_verify_serial'.tr, r.serial, true),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _hero(context, tone, icon, title, sub),
      const SizedBox(height: AppSpace.md),
      _StatusRow(result: r),
      const SizedBox(height: AppSpace.md),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final f in facts) _fact(context, f.$1, f.$2, f.$3, ltr: f.$4),
        ]),
      ),
      if (r.nameMasked || (shown == null && r.byNumber)) ...[
        const SizedBox(height: AppSpace.md),
        AppBanner(
          icon: Icons.qr_code_2_rounded,
          color: c.textMedium,
          text: r.nameMasked ? 'cv_masked_note'.tr : 'cv_number_only_note'.tr,
        ),
      ],
      if (shown != null) ...[
        const SizedBox(height: AppSpace.md),
        if (langs.length > 1 && onLang != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final l in langs) ButtonSegment(value: l, label: Text(certLangLabel(l)))],
              selected: {shown},
              onSelectionChanged: (s) => onLang!(s.first),
            ),
          ),
        const SizedBox(height: AppSpace.sm),
        Opacity(
          opacity: r.valid ? 1 : 0.55,
          child: ClipRRect(
            borderRadius: AppRadius.cardAll,
            child: (imageBuilder ?? _networkImage)(r.images[shown]!),
          ),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      AppBanner(icon: Icons.info_outline_rounded, color: c.textMedium, text: 'cv_proof_note'.tr),
    ]);
  }

  static IconData _detailIcon(String key) => switch (key) {
        'hours' => Icons.schedule_rounded,
        'grade' || 'score' || 'rank' => Icons.military_tech_outlined,
        'program' || 'department' => Icons.account_tree_outlined,
        'event_name' => Icons.celebration_outlined,
        'start_date' || 'end_date' => Icons.date_range_outlined,
        _ => Icons.notes_rounded,
      };

  Widget _fact(BuildContext context, IconData icon, String label, String value, {bool ltr = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs + 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.sm, color: c.textMedium),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.meta(context)),
            SelectableText(value,
                textDirection: ltr ? TextDirection.ltr : null,
                // an Arabic name on an English page, and the reverse
                style: AppType.row(context).copyWith(fontFamilyFallback: AppFonts.fallback)),
          ]),
        ),
      ]),
    );
  }

  static Widget _networkImage(String url) => Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const AspectRatio(aspectRatio: 1.414, child: Center(child: Icon(Icons.broken_image_outlined))),
        loadingBuilder: (ctx, child, p) => p == null
            ? child
            : AppShimmer(child: AspectRatio(aspectRatio: 1.414, child: AppSkeletonBox(width: double.infinity, height: double.infinity, radius: AppRadius.card))),
      );
}

/// Valid / expired / revoked next to the expiry, side by side when there is room.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.result});

  final VerifyResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final amber = Theme.of(context).brightness == Brightness.dark ? c.warning : _deepAmber(c.warning);
    final status = _Tile(
      icon: switch (r.state) {
        CertVerifyStatus.valid => Icons.check_circle_rounded,
        CertVerifyStatus.expired => Icons.hourglass_bottom_rounded,
        CertVerifyStatus.revoked => Icons.block_rounded,
      },
      color: switch (r.state) {
        CertVerifyStatus.valid => c.success,
        CertVerifyStatus.expired => amber,
        CertVerifyStatus.revoked => c.danger,
      },
      label: 'cv_status_label'.tr,
      value: switch (r.state) {
        CertVerifyStatus.valid => 'cv_valid'.tr,
        CertVerifyStatus.expired => 'cv_expired'.tr,
        CertVerifyStatus.revoked => 'cv_revoked'.tr,
      },
    );
    final expiresAt = r.expiresAt;
    final expiry = _Tile(
      icon: expiresAt == null ? Icons.all_inclusive_rounded : Icons.event_available_outlined,
      color: r.expired ? amber : c.textMedium,
      label: expiresAt == null || r.revoked ? 'cv_expiry_label'.tr : (r.expired ? 'cv_expired_on'.tr : 'cv_valid_until'.tr),
      value: expiresAt == null ? 'cv_no_expiry'.tr : AppTime.date(expiresAt),
    );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 420) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [status, const SizedBox(height: AppSpace.sm), expiry]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: status),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: expiry),
        ]),
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label, value;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: AppIconSize.md),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: AppType.meta(context)),
              Text(value, style: AppType.section(context).copyWith(color: color)),
            ]),
          ),
        ]),
      );
}
