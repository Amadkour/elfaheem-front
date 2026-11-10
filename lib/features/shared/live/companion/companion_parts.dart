// lib/features/shared/live/companion/companion_parts.dart — the companion device's widgets, plain values only (D-520),
// so the layout harness pumps them without a Room:
//   CompanionChooserBody      the "Your phone" sheet: what the phone provides, asking, waiting + QR, connected
//   PreJoinPhoneRow           the pre-join page's row
//   CompanionIncomingLayout   the call-style prompt on the phone
//   CompanionPhoneLayout      the compact screen while the phone is in use
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/display/app_fonts.dart';
import '../../../../design/app_kit.dart';
import '../../../admin/admin_common.dart' show t;
import '../../../teacher/sessions/live/widgets/live_palette.dart';
import 'companion_core.dart';
import 'companion_link.dart' show CompanionStage;

IconData companionSourceIcon(CompanionSource s) => switch (s) {
      CompanionSource.camera => Icons.videocam_rounded,
      CompanionSource.microphone => Icons.mic_rounded,
      CompanionSource.speaker => Icons.volume_up_rounded,
    };

String companionSourceName(CompanionSource s) => switch (s) {
      CompanionSource.camera => t('الكاميرا', 'Camera'),
      CompanionSource.microphone => t('الميكروفون', 'Microphone'),
      CompanionSource.speaker => t('السماعة', 'Speaker'),
    };

String companionSourceHint(CompanionSource s) => switch (s) {
      CompanionSource.camera => t('تحل كاميرا هاتفك محل كاميرا هذا الجهاز.', 'Your phone\'s camera replaces this device\'s.'),
      CompanionSource.microphone => t('يتوقف ميكروفون هذا الجهاز ويُسمع صوتك من الهاتف.', 'This device\'s microphone stops and you are heard from the phone.'),
      CompanionSource.speaker => t('يصمت هذا الجهاز وتسمع الجلسة من الهاتف.', 'This device goes silent and you hear the room on the phone.'),
    };

/// `Camera and Microphone`, in the language of the app.
String companionSourcesText(Iterable<CompanionSource> sources) {
  final names = [for (final s in CompanionSource.values) if (sources.contains(s)) companionSourceName(s)];
  if (names.length < 2) return names.join();
  final and = t(' و', ' and ');
  return '${names.sublist(0, names.length - 1).join(t('، ', ', '))}$and${names.last}';
}

class _EchoNote extends StatelessWidget {
  const _EchoNote();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.16), borderRadius: AppRadius.cardAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.hearing_rounded, size: 18, color: c.warning),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            t('لتجنّب الصدى: اجعل الميكروفون والسماعة على جهاز واحد، أو استخدم سماعة رأس.',
                'To avoid echo keep the microphone and speaker on one device, or wear a headset.'),
            style: AppType.meta(context).copyWith(color: c.textDark),
          ),
        ),
      ]),
    );
  }
}

class CompanionChooserBody extends StatelessWidget {
  const CompanionChooserBody({
    super.key,
    required this.stage,
    required this.sources,
    required this.onToggle,
    required this.onAsk,
    required this.onCancel,
    required this.onStop,
    this.qrUrl,
    this.noPhone = false,
    this.error,
    this.busy = false,
    this.showQr = false,
    this.onShowQr,
  });

  final CompanionStage stage;
  final Set<CompanionSource> sources;
  final ValueChanged<CompanionSource> onToggle;
  final VoidCallback onAsk;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  /// The link the QR carries, once a request runs.
  final String? qrUrl;

  /// The server has no phone to push to: the QR is the way in.
  final bool noPhone;
  final String? error;
  final bool busy;
  final bool showQr;
  final VoidCallback? onShowQr;

  bool get _waiting => stage == CompanionStage.ringing || stage == CompanionStage.connecting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = stage == CompanionStage.active;
    final title = active ? t('هاتفك متصل', 'Your phone is connected') : t('استخدم هاتفك', 'Use your phone');
    final canAsk = sources.isNotEmpty && !_waiting && !active;
    return AppSheetContent(
      title: title,
      children: [
        if (!active && !_waiting) ...[
          Text(
            t('اختر ما تريد استخدامه من هاتفك في هذه الجلسة.', 'Choose what your phone provides in this session.'),
            style: AppType.body(context).copyWith(color: c.textMedium),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        for (final s in CompanionSource.values)
          AppSwitchTile(
            key: ValueKey('live_companion.source.${s.wire}'),
            icon: companionSourceIcon(s),
            title: companionSourceName(s),
            subtitle: companionSourceHint(s),
            value: sources.contains(s),
            // While the phone rings the choice is frozen; while it is connected each switch applies at once, and one
            // source must stay (stopping is the button below).
            onChanged: _waiting || (active && sources.length == 1 && sources.contains(s)) ? null : (_) => onToggle(s),
          ),
        if (companionSplitsAudio(sources)) ...[const SizedBox(height: AppSpace.xs), const _EchoNote()],
        if (error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(error!, key: const ValueKey('live_companion.error'), style: AppType.meta(context).copyWith(color: c.danger)),
        ],
        const SizedBox(height: AppSpace.md),
        if (_waiting) ...[
          _WaitingCard(connecting: stage == CompanionStage.connecting, noPhone: noPhone),
          const SizedBox(height: AppSpace.sm),
          if (qrUrl != null && (showQr || noPhone)) _QrCard(url: qrUrl!) else if (qrUrl != null)
            TextButton.icon(
              key: const ValueKey('live_companion.show_qr'),
              onPressed: onShowQr,
              icon: const Icon(Icons.qr_code_rounded, size: 18),
              label: Text(t('لم يرن هاتفك؟ امسح الرمز', 'Phone didn\'t ring? Scan a code')),
            ),
          const SizedBox(height: AppSpace.sm),
          AppButton(
            key: const ValueKey('live_companion.cancel'),
            label: t('إلغاء الطلب', 'Cancel request'),
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: onCancel,
          ),
        ] else if (active)
          AppButton(
            key: const ValueKey('live_companion.stop'),
            label: t('إيقاف استخدام الهاتف', 'Stop using my phone'),
            icon: Icons.phonelink_erase_rounded,
            variant: AppButtonVariant.secondary,
            dangerOutline: true,
            expand: true,
            onPressed: onStop,
          )
        else
          AppButton(
            key: const ValueKey('live_companion.ask'),
            label: t('اطلب من هاتفي', 'Ask my phone'),
            icon: Icons.phonelink_ring_rounded,
            expand: true,
            busy: busy,
            onPressed: canAsk ? onAsk : null,
          ),
      ],
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.connecting, required this.noPhone});
  final bool connecting;
  final bool noPhone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = connecting
        ? t('وافقت من هاتفك، جارٍ الاتصال…', 'Accepted on your phone, connecting…')
        : noPhone
            ? t('لم نجد هاتفًا مسجَّلًا فيه دخولك. امسح الرمز بهاتفك.', 'No phone is signed in to your account. Scan the code with your phone.')
            : t('أرسلنا الطلب إلى هاتفك. افتحه واضغط «قبول».', 'We asked your phone. Open it and tap Accept.');
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.cardAll),
      child: Row(children: [
        SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.primary)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(line, style: AppType.bodyStrong(context))),
      ]),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(AppSpace.xs),
          child: QrImageView(key: const ValueKey('live_companion.qr'), data: url, size: 164, gapless: true),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          t('امسح الرمز بكاميرا هاتفك. يعمل لحسابك فقط ولبضع دقائق.', 'Scan with your phone\'s camera. It works only for your account, for a few minutes.'),
          textAlign: TextAlign.center,
          style: AppType.meta(context),
        ),
      ]),
    );
  }
}

/// The pre-join page's entry (web / desktop): opens the chooser, says what was picked.
class PreJoinPhoneRow extends StatelessWidget {
  const PreJoinPhoneRow({super.key, required this.selected, required this.onTap});
  final Set<CompanionSource> selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picked = selected.isNotEmpty;
    final title = picked
        ? t('هاتفك: ${companionSourcesText(selected)}', 'Your phone: ${companionSourcesText(selected)}')
        : t('استخدم هاتفك', 'Use your phone');
    final subtitle = picked
        ? t('نطلب ذلك من هاتفك عند الانضمام.', 'Your phone will be asked when you join.')
        : t('كاميرا أو ميكروفون أو سماعة هاتفك.', 'Its camera, microphone or speaker.');
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('prejoin.phone'),
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardAll,
            color: picked ? c.primaryTint : null,
            border: Border.all(color: picked ? c.primary : c.divider),
          ),
          child: Row(children: [
            Icon(Icons.phonelink_ring_rounded, size: 20, color: picked ? c.primary : c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: AppType.bodyStrong(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textMedium),
          ]),
        ),
      ),
    );
  }
}

/// The phone's prompt, the look of an incoming call.
class CompanionIncomingLayout extends StatelessWidget {
  const CompanionIncomingLayout({
    super.key,
    required this.sources,
    required this.secondsLeft,
    required this.onAccept,
    required this.onDecline,
    this.originLabel,
    this.roomTitle,
    this.busy = false,
    this.note,
  });

  final Set<CompanionSource> sources;
  final int secondsLeft;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final String? originLabel;
  final String? roomTitle;
  final bool busy;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final where = originLabel == null || originLabel!.isEmpty ? t('جهازك الآخر', 'your other device') : originLabel!;
    TextStyle s(double size, Color color, {FontWeight w = FontWeight.w500}) =>
        TextStyle(fontFamily: AppFonts.family, fontSize: size, color: color, fontWeight: w, height: 1.3);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17233F), Color(0xFF0B1020)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final compact = box.maxHeight < 560;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(children: [
                      SizedBox(height: compact ? 0 : AppSpace.xxl),
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LivePalette.glass,
                          border: Border.all(color: LivePalette.glassBorder),
                        ),
                        child: const Icon(Icons.phonelink_ring_rounded, color: LivePalette.textHigh, size: 52),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(t('استخدام هذا الهاتف في جلستك؟', 'Use this phone in your session?'),
                          textAlign: TextAlign.center, style: s(24, LivePalette.textHigh, w: FontWeight.w700)),
                      const SizedBox(height: AppSpace.xs),
                      Text(t('طلب من $where', 'Asked from $where'),
                          textAlign: TextAlign.center, style: s(15, LivePalette.textMid)),
                      if (roomTitle != null && roomTitle!.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xxs),
                        Text(roomTitle!, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: s(14, LivePalette.textSoft)),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                        for (final src in CompanionSource.values)
                          if (sources.contains(src))
                            _Chip(icon: companionSourceIcon(src), label: companionSourceName(src), style: s(14, LivePalette.textHigh)),
                      ]),
                      if (note != null) ...[
                        const SizedBox(height: AppSpace.md),
                        Text(note!, textAlign: TextAlign.center, style: s(13, LivePalette.textMid)),
                      ],
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.lg),
                      child: Column(children: [
                        Text(t('ينتهي الطلب خلال $secondsLeft ثانية', 'Expires in $secondsLeft s'),
                            style: s(12, LivePalette.textSoft)),
                        const SizedBox(height: AppSpace.md),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          _CallButton(
                            key: const ValueKey('live_companion.decline'),
                            icon: Icons.close_rounded,
                            color: LivePalette.danger,
                            label: t('رفض', 'Decline'),
                            style: s(13, LivePalette.textHigh),
                            onTap: busy ? null : onDecline,
                          ),
                          _CallButton(
                            key: const ValueKey('live_companion.accept'),
                            icon: Icons.check_rounded,
                            color: LivePalette.success,
                            label: t('قبول', 'Accept'),
                            style: s(13, LivePalette.textHigh),
                            busy: busy,
                            onTap: busy ? null : onAccept,
                          ),
                        ]),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.style});
  final IconData icon;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: LivePalette.glass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: LivePalette.textHigh),
          const SizedBox(width: AppSpace.xxs),
          Text(label, style: style),
        ]),
      );
}

class _CallButton extends StatelessWidget {
  const _CallButton({super.key, required this.icon, required this.color, required this.label, required this.style, required this.onTap, this.busy = false});
  final IconData icon;
  final Color color;
  final String label;
  final TextStyle style;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        enabled: onTap != null,
        excludeSemantics: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 72,
                child: busy
                    ? const Center(child: SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 3, color: LivePalette.textHigh)))
                    : Icon(icon, color: LivePalette.textHigh, size: 32),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(label, style: style),
        ]),
      );
}

/// One state of the companion screen.
enum CompanionPhoneState { connecting, connected, reconnecting }

/// The compact screen on the phone. Everything is a plain value; [preview] is the camera (null: an avatar).
class CompanionPhoneLayout extends StatelessWidget {
  const CompanionPhoneLayout({
    super.key,
    required this.state,
    required this.originLabel,
    required this.sources,
    required this.micOn,
    required this.camOn,
    required this.speakerOn,
    required this.onLeave,
    this.preview,
    this.onToggleMic,
    this.onToggleCam,
    this.onFlip,
    this.onToggleSpeaker,
    this.notice,
    this.mutedByHost = false,
  });

  final CompanionPhoneState state;
  final String originLabel;
  final Set<CompanionSource> sources;
  final bool micOn;
  final bool camOn;
  final bool speakerOn;
  final Widget? preview;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleCam;
  final VoidCallback? onFlip;
  final VoidCallback? onToggleSpeaker;
  final VoidCallback onLeave;
  final String? notice;
  final bool mutedByHost;

  @override
  Widget build(BuildContext context) {
    TextStyle s(double size, Color color, {FontWeight w = FontWeight.w500}) =>
        TextStyle(fontFamily: AppFonts.family, fontSize: size, color: color, fontWeight: w, height: 1.3);
    final status = switch (state) {
      CompanionPhoneState.connecting => t('جارٍ الاتصال بجلستك…', 'Connecting to your session…'),
      CompanionPhoneState.reconnecting => t('جارٍ إعادة الاتصال…', 'Reconnecting…'),
      CompanionPhoneState.connected => t('متصل بجلستك على $originLabel', 'Connected to your session on $originLabel'),
    };
    final hasMic = sources.contains(CompanionSource.microphone);
    final hasCam = sources.contains(CompanionSource.camera);
    return ColoredBox(
      color: const Color(0xFF0B1020),
      child: Stack(fit: StackFit.expand, children: [
        if (preview != null && camOn)
          Positioned.fill(child: preview!)
        else
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.phone_iphone_rounded, size: 72, color: LivePalette.textLow),
              const SizedBox(height: AppSpace.sm),
              Text(camOn || !hasCam ? companionSourcesText(sources) : t('الكاميرا متوقفة', 'Camera is off'),
                  textAlign: TextAlign.center, style: s(16, LivePalette.textMid)),
            ]),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state == CompanionPhoneState.connected ? LivePalette.success : LivePalette.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(status, key: const ValueKey('live_companion.status'), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: s(14, LivePalette.textHigh, w: FontWeight.w600)),
                    ),
                  ),
                ]),
                if (notice != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.sm),
                    decoration: BoxDecoration(color: LivePalette.scrimLight, borderRadius: AppRadius.cardAll),
                    child: Text(notice!, style: s(13, LivePalette.textHigh)),
                  ),
                ],
              ]),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  if (hasMic)
                    _PhoneBtn(
                      key: const ValueKey('live_companion.mic'),
                      icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      label: micOn ? t('كتم', 'Mute') : t('إلغاء الكتم', 'Unmute'),
                      style: s(12, LivePalette.textHigh),
                      warm: !micOn,
                      onTap: onToggleMic,
                    ),
                  if (hasCam)
                    _PhoneBtn(
                      key: const ValueKey('live_companion.camera'),
                      icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                      label: t('الكاميرا', 'Camera'),
                      style: s(12, LivePalette.textHigh),
                      warm: !camOn,
                      onTap: onToggleCam,
                    ),
                  if (hasCam)
                    _PhoneBtn(
                      key: const ValueKey('live_companion.flip'),
                      icon: Icons.cameraswitch_rounded,
                      label: t('قلب', 'Flip'),
                      style: s(12, LivePalette.textHigh),
                      onTap: camOn ? onFlip : null,
                    ),
                  if (sources.contains(CompanionSource.speaker))
                    _PhoneBtn(
                      key: const ValueKey('live_companion.speaker'),
                      icon: speakerOn ? Icons.volume_up_rounded : Icons.phone_android_rounded,
                      label: speakerOn ? t('مكبر', 'Speaker') : t('السماعة', 'Earpiece'),
                      style: s(12, LivePalette.textHigh),
                      onTap: onToggleSpeaker,
                    ),
                  _PhoneBtn(
                    key: const ValueKey('live_companion.leave'),
                    icon: Icons.call_end_rounded,
                    label: t('مغادرة', 'Leave'),
                    style: s(12, LivePalette.textHigh),
                    danger: true,
                    onTap: onLeave,
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PhoneBtn extends StatelessWidget {
  const _PhoneBtn({super.key, required this.icon, required this.label, required this.style, this.onTap, this.warm = false, this.danger = false});
  final IconData icon;
  final String label;
  final TextStyle style;
  final VoidCallback? onTap;
  final bool warm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? LivePalette.danger : (warm ? LivePalette.warning : LivePalette.glass);
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      excludeSemantics: true,
      child: SizedBox(
        width: 72,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: bg.withValues(alpha: onTap == null ? 0.4 : 1),
            shape: const CircleBorder(side: BorderSide(color: LivePalette.glassBorder)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(dimension: 56, child: Icon(icon, color: LivePalette.textHigh)),
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: style),
        ]),
      ),
    );
  }
}
