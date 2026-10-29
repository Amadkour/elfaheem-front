// share_options_sheet.dart — the share flow's first step on Android and the web: what is shown
// ("Detail" for slides / text, "Motion" for video, see SharePreset) and whether the device's audio
// goes with it (Android 10+; on the web the tab / system audio in Chromium browsers; otherwise a
// note says only the mic is heard; on Android 14+ a second line says device audio is every app's
// media, also in a single-app share). ShareOptionsLayout takes plain values
// (test/ui/share_options_layout_test.dart); showShareOptionsSheet holds the two choices.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import 'share_presets.dart';

/// What the presenter picked.
class ShareChoice {
  const ShareChoice({required this.quality, required this.deviceAudio});

  final ShareQuality quality;
  final bool deviceAudio;
}

/// [web]: the browser's share (tab / system audio, the browser's own picker next) instead of Android's.
/// [deviceAudioNote]: a second line under the device-audio switch (Android 14+: shareDeviceAudioScopeNote).
Future<ShareChoice?> showShareOptionsSheet(BuildContext context,
        {required bool deviceAudioSupported, bool web = false, String? deviceAudioNote}) =>
    showAppSheet<ShareChoice>(
        context,
        (ctx) => _ShareOptionsSheet(
            deviceAudioSupported: deviceAudioSupported, web: web, deviceAudioNote: deviceAudioNote));

class _ShareOptionsSheet extends StatefulWidget {
  const _ShareOptionsSheet({required this.deviceAudioSupported, this.web = false, this.deviceAudioNote});

  final bool deviceAudioSupported;
  final bool web;
  final String? deviceAudioNote;

  @override
  State<_ShareOptionsSheet> createState() => _ShareOptionsSheetState();
}

class _ShareOptionsSheetState extends State<_ShareOptionsSheet> {
  ShareQuality _quality = ShareQuality.detail;
  late bool _audio = widget.deviceAudioSupported;

  @override
  Widget build(BuildContext context) => ShareOptionsLayout(
        quality: _quality,
        deviceAudio: _audio,
        deviceAudioSupported: widget.deviceAudioSupported,
        web: widget.web,
        deviceAudioNote: widget.deviceAudioNote,
        onQuality: (q) => setState(() => _quality = q),
        onDeviceAudio: (v) => setState(() => _audio = v),
        onStart: () => Navigator.pop(
          context,
          ShareChoice(quality: _quality, deviceAudio: _audio && widget.deviceAudioSupported),
        ),
      );
}

class ShareOptionsLayout extends StatelessWidget {
  const ShareOptionsLayout({
    super.key,
    required this.quality,
    required this.deviceAudio,
    required this.deviceAudioSupported,
    this.web = false,
    this.deviceAudioNote,
    this.onQuality,
    this.onDeviceAudio,
    this.onStart,
  });

  final ShareQuality quality;
  final bool deviceAudio;

  /// Android 10 / API 29+: other apps' audio can be captured; web: a Chromium browser (tab / system audio).
  final bool deviceAudioSupported;

  /// The browser's share: the audio texts speak of the tab and the browser's own dialog.
  final bool web;

  /// A second line under the device-audio switch (Android 14+: device audio is every app's media).
  final String? deviceAudioNote;
  final ValueChanged<ShareQuality>? onQuality;
  final ValueChanged<bool>? onDeviceAudio;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('مشاركة الشاشة', 'Share your screen')),
        AppSectionTitle(t('ماذا ستعرض؟', 'What are you showing?')),
        const SizedBox(height: 8),
        ShareModeTile(
          key: const ValueKey('share.mode.detail'),
          icon: Icons.slideshow_rounded,
          title: t('شرائح ونصوص', 'Slides and text'),
          subtitle: t('أوضح نص، حتى 1080p و15 إطاراً في الثانية', 'Sharpest text, up to 1080p at 15 fps'),
          selected: quality == ShareQuality.detail,
          onTap: onQuality == null ? null : () => onQuality!(ShareQuality.detail),
        ),
        const SizedBox(height: 8),
        ShareModeTile(
          key: const ValueKey('share.mode.motion'),
          icon: Icons.movie_rounded,
          title: t('فيديو وحركة', 'Video and motion'),
          subtitle: t('حركة سلسة، 720p و30 إطاراً في الثانية', 'Smooth motion, 720p at 30 fps'),
          selected: quality == ShareQuality.motion,
          onTap: onQuality == null ? null : () => onQuality!(ShareQuality.motion),
        ),
        const SizedBox(height: 12),
        if (deviceAudioSupported)
          AppSwitchTile(
            key: const ValueKey('share.device_audio'),
            icon: Icons.volume_up_rounded,
            title: t('مشاركة صوت الجهاز', 'Share device audio'),
            subtitle: web
                ? t('يسمع الحضور صوت التبويب أو الجهاز. فعّل «مشاركة الصوت» في نافذة المتصفح التالية',
                    'Viewers hear the tab or system sound. Tick "Share audio" in the browser\'s next dialog')
                : t('يسمع الحضور صوت الفيديو والتطبيقات، ولا يُلتقط صوت المكالمات',
                    'Viewers hear videos and apps; call audio is never captured'),
            subtitleWidget: (deviceAudioNote ?? '').isEmpty
                ? null
                : Text(deviceAudioNote!,
                    key: const ValueKey('share.device_audio.scope'), style: appText(12, c: c.textMedium, h: 1.35)),
            value: deviceAudio,
            onChanged: onDeviceAudio,
          )
        else
          AppBanner(
            key: const ValueKey('share.no_device_audio'),
            icon: Icons.volume_off_rounded,
            color: c.warning,
            text: web
                ? t('هذا المتصفح لا يشارك صوت الجهاز: سيسمع الحضور الميكروفون فقط. استخدم Chrome أو Edge لمشاركة صوت التبويب.',
                    'This browser cannot share device audio: viewers hear your microphone only. Use Chrome or Edge to share tab audio.')
                : t('مشاركة صوت الجهاز تحتاج أندرويد 10 أو أحدث: سيسمع الحضور الميكروفون فقط.',
                    'Sharing device audio needs Android 10 or later: viewers hear your microphone only.'),
          ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          key: const ValueKey('share.start'),
          label: t('ابدأ المشاركة', 'Start sharing'),
          icon: Icons.screen_share_rounded,
          onPressed: onStart,
        ),
      ]),
    );
  }
}

/// One of the two modes: icon, name, what it is for; the selected one is outlined.
class ShareModeTile extends StatelessWidget {
  const ShareModeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = selected ? c.primary : c.textMedium;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: appText(14, w: FontWeight.w700, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: appText(12, c: c.textMedium), maxLines: 3, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, color: c.primary),
            ],
          ]),
        ),
      ),
    );
  }
}
