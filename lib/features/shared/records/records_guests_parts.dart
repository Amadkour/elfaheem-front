// lib/features/shared/records/records_guests_parts.dart — the plain-values widgets of guests by e-mail (D-315): no
// API, no player, no provider, so test/ui/records_guests_layout_test.dart pumps them with the layout harness.
//
//   RecordGuestRow        a guest in the Share sheet's people list: a mail avatar, the address (LTR), a Guest badge,
//                         opened / views / e-mail state / expiry, Copy link, and ⋯ (Resend · Revoke)
//   RecordGuestsInvite    "Guests by e-mail": the addresses slot, the message slot, how long the link works
//                         (7 days · 30 days · never), Invite; the server-can't-send banner
//   GuestRecordView       the guest's own page (no account): loading · not available · the card (title, who shared
//                         it, length, message, expiry) with the player slot or Play
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart' show mmss;
import 'records_guests_api.dart';

/// The small "Guest" badge next to a guest's address.
class RecordGuestBadge extends StatelessWidget {
  const RecordGuestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
      decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Text(t('ضيف', 'Guest'), style: appText(11, w: FontWeight.w700, c: appInk(context, c.warning))),
    );
  }
}

enum RecordGuestAction { resend, revoke }

class RecordGuestRow extends StatelessWidget {
  const RecordGuestRow({super.key, required this.guest, this.busy = false, this.onCopy, this.onResend, this.onRevoke});

  final RecordGuest guest;
  final bool busy;
  final VoidCallback? onCopy;
  final VoidCallback? onResend;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = guest;
    final status = g.status();
    final until = g.expiresAt == null || g.expired ? null : t('حتى ${AppTime.date(g.expiresAt!)}', 'Until ${AppTime.date(g.expiresAt!)}');
    return ConstrainedBox(
      key: ValueKey('records.share.guest.${g.id}'),
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(Icons.mail_outline_rounded, size: AppIconSize.md, color: appInk(context, c.warning)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(
                  child: Text(g.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                ),
                const SizedBox(width: AppSpace.xxs),
                const RecordGuestBadge(),
              ]),
              Text([status, ?until].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appText(12, c: g.expired || g.emailStatus == 'failed' ? c.danger : c.textMedium, h: 1.35)),
            ]),
          ),
          IconButton(
            key: ValueKey('records.share.guest.copy.${g.id}'),
            tooltip: t('نسخ الرابط', 'Copy link'),
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            icon: Icon(Icons.copy_rounded, color: c.textMedium, size: AppIconSize.md),
            onPressed: busy || g.link == null ? null : onCopy,
          ),
          PopupMenuButton<RecordGuestAction>(
            key: ValueKey('records.share.guest.more.${g.id}'),
            tooltip: t('المزيد', 'More'),
            enabled: !busy,
            icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
            onSelected: (a) => (a == RecordGuestAction.resend ? onResend : onRevoke)?.call(),
            itemBuilder: (_) => [
              if (!g.expired)
                PopupMenuItem(
                  value: RecordGuestAction.resend,
                  child: Text(t('إعادة إرسال البريد', 'Resend the e-mail')),
                ),
              PopupMenuItem(
                value: RecordGuestAction.revoke,
                child: Text(t('إلغاء رابط هذا الضيف', "Revoke this guest's link"), style: TextStyle(color: c.danger)),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class RecordGuestsInvite extends StatelessWidget {
  const RecordGuestsInvite({
    super.key,
    required this.emails,
    required this.message,
    this.expiresDays = 30,
    this.problem,
    this.busy = false,
    this.mailUnavailable = false,
    this.onExpiry,
    this.onInvite,
  });

  /// The addresses field (the sheet owns its controller).
  final Widget emails;

  /// The optional message field.
  final Widget message;
  final int? expiresDays;

  /// Why the typed addresses cannot be sent (null: they can, or nothing typed yet).
  final String? problem;
  final bool busy;

  /// The server said it cannot send e-mail: the links must be copied by hand.
  final bool mailUnavailable;
  final ValueChanged<int?>? onExpiry;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('ضيوف بالبريد', 'Guests by e-mail'), style: AppType.section(context)),
      const SizedBox(height: 2),
      Text(
        t('لمن ليس لديه حساب: يصله بريد برابط شخصي يشغّل التسجيل في المتصفح دون تسجيل دخول.',
            'For people without an account: each gets an e-mail with a personal link that plays it in the browser, no sign-in.'),
        style: appText(12.5, c: c.textMedium, h: 1.45),
      ),
      const SizedBox(height: AppSpace.xs),
      emails,
      if (problem != null) ...[
        const SizedBox(height: 2),
        Text(problem!, key: const ValueKey('records.share.guests.problem'), style: appText(12, c: c.danger, h: 1.35)),
      ],
      const SizedBox(height: AppSpace.xs),
      message,
      const SizedBox(height: AppSpace.xs),
      Text(t('صلاحية الرابط', 'The link works for'), style: appText(12.5, w: FontWeight.w600, c: c.textDark)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final d in recordGuestExpiries)
          AppChoiceChip(
            key: ValueKey('records.share.guests.expiry.${d ?? 'never'}'),
            label: recordGuestExpiryLabel(d),
            selected: d == expiresDays,
            onTap: () => busy ? null : onExpiry?.call(d),
          ),
      ]),
      if (mailUnavailable) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(
          key: const ValueKey('records.share.guests.unavailable'),
          icon: Icons.mark_email_unread_outlined,
          color: c.warning,
          text: t('إرسال البريد غير متاح على الخادم الآن — انسخ رابط كل ضيف وأرسله بنفسك.',
              "This server can't send e-mail right now — copy each guest's link and send it yourself."),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      AppButton(
        key: const ValueKey('records.share.guests.invite'),
        label: t('دعوة', 'Invite'),
        icon: Icons.forward_to_inbox_rounded,
        variant: AppButtonVariant.tonal,
        busy: busy,
        expand: true,
        onPressed: busy || problem != null ? null : onInvite,
      ),
    ]);
  }
}

/// The guest's page body. [player] is the video slot once Play was pressed (the page owns the controller).
class GuestRecordView extends StatelessWidget {
  const GuestRecordView({super.key, this.card, this.error, this.player, this.starting = false, this.onPlay, this.onRetry, this.showImage = true});

  final GuestRecordCard? card;
  final String? error;
  final Widget? player;
  final bool starting;
  final VoidCallback? onPlay;
  final VoidCallback? onRetry;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = card;
    final Widget body;
    if (error != null) {
      body = AppEmpty(
        icon: Icons.link_off_rounded,
        title: t('الرابط غير متاح', 'Link not available'),
        message: error,
        actionLabel: onRetry == null ? null : t('إعادة المحاولة', 'Try again'),
        onAction: onRetry,
      );
    } else if (r == null) {
      body = const AppListSkeleton(items: 2);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: c.heroShade,
              child: player ??
                  Stack(fit: StackFit.expand, children: [
                    if (showImage && r.coverUrl != null)
                      Image.network(r.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    Center(
                      child: starting
                          ? CircularProgressIndicator(color: c.onHero)
                          : Semantics(
                              button: true,
                              label: t('تشغيل', 'Play'),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: const ValueKey('records.guest.play'),
                                  customBorder: const CircleBorder(),
                                  onTap: onPlay,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(color: c.heroGlass, shape: BoxShape.circle, border: Border.all(color: c.heroGlassBorder)),
                                    child: Icon(r.audio ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: c.onHero, size: 40),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(r.title, style: appText(19, w: FontWeight.w700, c: c.textDark, h: 1.3)),
        const SizedBox(height: AppSpace.xxs),
        Text(
          [
            if (r.ownerName.isNotEmpty) t('شاركه معك ${r.ownerName}', 'Shared with you by ${r.ownerName}'),
            if (r.durationSeconds > 0) mmss(r.durationSeconds),
          ].join(' · '),
          style: appText(13, c: c.textMedium, h: 1.4),
        ),
        if (r.message != null) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.divider),
            ),
            child: Text(r.message!, style: appText(13.5, c: c.textDark, h: 1.5)),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(
          r.expiresAt == null
              ? t('هذا الرابط شخصي لك — لا تشاركه.', "This link is personal — please don't forward it.")
              : t('الرابط شخصي لك وصالح حتى ${AppTime.date(r.expiresAt!)}.', 'This personal link works until ${AppTime.date(r.expiresAt!)}.'),
          style: appText(12, c: c.textLight, h: 1.4),
        ),
      ]);
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
        child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: body),
      ),
    );
  }
}
