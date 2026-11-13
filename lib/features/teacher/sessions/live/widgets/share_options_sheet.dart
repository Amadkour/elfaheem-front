// share_options_sheet.dart — the share flow's first step: what is shown. Two tabs when the whiteboard is offered
// (D-087, feature key live.whiteboard):
//   Screen      "Detail" for slides / text, "Motion" for video (see SharePreset) and whether the device's audio goes
//               with it (Android 10+; on the web the tab / system audio in Chromium browsers; otherwise a note says
//               only the mic is heard; on Android 14+ a second line says device audio is every app's media, also in
//               a single-app share). iOS / desktop ([qualityChoice] false): no modes, the system picker comes next.
//               A phone browser ([screenAvailable] false) cannot share a screen: the tab says so.
//   Whiteboard  the page format (landscape · portrait · continuous, D-093), a background (white · blackboard · grid ·
//               lined) and Start whiteboard: a board of vector strokes and text everyone sees instead of a screen (no
//               video track).
// ShareOptionsLayout takes plain values (test/ui/share_options_layout_test.dart); showShareOptionsSheet holds the
// choices.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/live/live_room_words.dart';
import '../whiteboard/board_protocol.dart' show BoardBackground, BoardFormat;
import '../whiteboard/board_toolbar.dart' show BoardBackgroundPicker, BoardFormatPicker;
import 'share_presets.dart';

/// What the presenter picked: a screen ([quality], [deviceAudio]) or, when [whiteboard] is set, a whiteboard on
/// that background, in [boardFormat].
class ShareChoice {
  const ShareChoice({required this.quality, required this.deviceAudio, this.whiteboard, this.boardFormat = BoardFormat.continuous});

  final ShareQuality quality;
  final bool deviceAudio;
  final BoardBackground? whiteboard;
  final BoardFormat boardFormat;

  bool get isWhiteboard => whiteboard != null;
}

enum ShareTab { screen, whiteboard }

/// [web]: the browser's share (tab / system audio, the browser's own picker next) instead of Android's.
/// [deviceAudioNote]: a second line under the device-audio switch (Android 14+: shareDeviceAudioScopeNote).
/// [whiteboard]: offer the whiteboard tab. [screenAvailable]: false in a phone browser. [qualityChoice]: false on
/// iOS / desktop, where the system's picker decides.
Future<ShareChoice?> showShareOptionsSheet(
  BuildContext context, {
  required bool deviceAudioSupported,
  bool web = false,
  String? deviceAudioNote,
  bool whiteboard = false,
  bool screenAvailable = true,
  bool qualityChoice = true,
  BoardBackground background = BoardBackground.white,
}) =>
    showAppSheet<ShareChoice>(
        context,
        (ctx) => _ShareOptionsSheet(
              deviceAudioSupported: deviceAudioSupported,
              web: web,
              deviceAudioNote: deviceAudioNote,
              whiteboard: whiteboard,
              screenAvailable: screenAvailable,
              qualityChoice: qualityChoice,
              background: background,
            ));

class _ShareOptionsSheet extends StatefulWidget {
  const _ShareOptionsSheet({
    required this.deviceAudioSupported,
    this.web = false,
    this.deviceAudioNote,
    this.whiteboard = false,
    this.screenAvailable = true,
    this.qualityChoice = true,
    this.background = BoardBackground.white,
  });

  final bool deviceAudioSupported;
  final bool web;
  final String? deviceAudioNote;
  final bool whiteboard;
  final bool screenAvailable;
  final bool qualityChoice;
  final BoardBackground background;

  @override
  State<_ShareOptionsSheet> createState() => _ShareOptionsSheetState();
}

class _ShareOptionsSheetState extends State<_ShareOptionsSheet> {
  ShareQuality _quality = ShareQuality.detail;
  late bool _audio = widget.deviceAudioSupported;
  late ShareTab _tab = widget.whiteboard && !widget.screenAvailable ? ShareTab.whiteboard : ShareTab.screen;
  late BoardBackground _bg = widget.background;

  /// D-314: the continuous page, on every device — it fills the stage's whole width and height for the presenter and
  /// for every viewer (a fixed 16:9 or 3:4 sheet is letterboxed wherever the screen has another shape). Landscape and
  /// portrait stay one tap away (a slide for a projector, a sheet of paper).
  BoardFormat _format = BoardFormat.continuous;

  // Scrolls: the Whiteboard tab (page format + backgrounds) is taller than a small phone's sheet.
  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: _layout(context));

  Widget _layout(BuildContext context) => ShareOptionsLayout(
        quality: _quality,
        deviceAudio: _audio,
        deviceAudioSupported: widget.deviceAudioSupported,
        web: widget.web,
        deviceAudioNote: widget.deviceAudioNote,
        whiteboard: widget.whiteboard,
        screenAvailable: widget.screenAvailable,
        qualityChoice: widget.qualityChoice,
        tab: _tab,
        background: _bg,
        boardFormat: _format,
        onTab: (v) => setState(() => _tab = v),
        onBackground: (b) => setState(() => _bg = b),
        onBoardFormat: (f) => setState(() => _format = f),
        onQuality: (q) => setState(() => _quality = q),
        onDeviceAudio: (v) => setState(() => _audio = v),
        onStart: () => Navigator.pop(
          context,
          ShareChoice(quality: _quality, deviceAudio: _audio && widget.deviceAudioSupported),
        ),
        onStartWhiteboard: () => Navigator.pop(
          context,
          ShareChoice(quality: _quality, deviceAudio: false, whiteboard: _bg, boardFormat: _format),
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
    this.whiteboard = false,
    this.screenAvailable = true,
    this.qualityChoice = true,
    this.tab = ShareTab.screen,
    this.background = BoardBackground.white,
    this.boardFormat = BoardFormat.landscape,
    this.onTab,
    this.onBackground,
    this.onBoardFormat,
    this.onQuality,
    this.onDeviceAudio,
    this.onStart,
    this.onStartWhiteboard,
  });

  final ShareQuality quality;
  final bool deviceAudio;

  /// Android 10 / API 29+: other apps' audio can be captured; web: a Chromium browser (tab / system audio).
  final bool deviceAudioSupported;

  /// The browser's share: the audio texts speak of the tab and the browser's own dialog.
  final bool web;

  /// A second line under the device-audio switch (Android 14+: device audio is every app's media).
  final String? deviceAudioNote;

  /// The Whiteboard tab is offered.
  final bool whiteboard;

  /// This device can share its screen (not in a phone browser).
  final bool screenAvailable;

  /// Detail / Motion and device audio are chosen here (Android, web); false: the system picker (iOS, desktop).
  final bool qualityChoice;
  final ShareTab tab;
  final BoardBackground background;
  final BoardFormat boardFormat;
  final ValueChanged<ShareTab>? onTab;
  final ValueChanged<BoardBackground>? onBackground;
  final ValueChanged<BoardFormat>? onBoardFormat;
  final ValueChanged<ShareQuality>? onQuality;
  final ValueChanged<bool>? onDeviceAudio;
  final VoidCallback? onStart;
  final VoidCallback? onStartWhiteboard;

  @override
  Widget build(BuildContext context) {
    final shown = whiteboard ? tab : ShareTab.screen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(tone: AppTone.brand, icon: Icons.share_rounded, whiteboard ? t('مشاركة', 'Share') : t('مشاركة الشاشة', 'Share your screen')),
        if (whiteboard) ...[
          _ShareTabs(value: shown, onChanged: onTab),
          const SizedBox(height: 14),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: shown == ShareTab.whiteboard ? _whiteboard(context) : _screen(context),
        ),
      ]),
    );
  }

  Widget _screen(BuildContext context) {
    final c = context.colors;
    if (!screenAvailable) {
      return Column(key: const ValueKey('share.screen_tab'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppBanner(
          key: const ValueKey('share.no_screen'),
          icon: Icons.desktop_access_disabled_rounded,
          color: c.warning,
          text: t('مشاركة الشاشة غير متاحة في متصفح الهاتف. اعرض سبورة بيضاء بدلاً منها، أو شارك من التطبيق أو من حاسوب.',
              "A phone browser can't share its screen. Present a whiteboard instead, or share from the app or a computer."),
        ),
      ]);
    }
    if (!qualityChoice) {
      return Column(key: const ValueKey('share.screen_tab'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ShareModeTile(
          icon: Icons.screen_share_rounded,
          title: t('شاشتك كاملة', 'Your whole screen'),
          subtitle: t('يطلب الجهاز الإذن في الخطوة التالية', 'Your device asks for permission next'),
          selected: true,
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          key: const ValueKey('share.start'),
          label: t('ابدأ المشاركة', 'Start sharing'),
          icon: Icons.screen_share_rounded,
          onPressed: onStart,
        ),
      ]);
    }
    return Column(key: const ValueKey('share.screen_tab'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
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
    ]);
  }

  Widget _whiteboard(BuildContext context) {
    final c = context.colors;
    return Column(key: const ValueKey('share.whiteboard_tab'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSectionTitle(t('شكل الصفحة', 'Page')),
      const SizedBox(height: 8),
      BoardFormatPicker(value: boardFormat, onChanged: onBoardFormat),
      const SizedBox(height: 14),
      AppSectionTitle(t('اختر الخلفية', 'Pick a background')),
      const SizedBox(height: 8),
      BoardBackgroundPicker(value: background, onChanged: onBackground),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.auto_awesome_rounded, size: 20, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              liveT(null,
                  ar: 'قلم وقلم تظليل وأشكال ونص بالعربية والإنجليزية وصفحات متعددة. يراها الجميع بوضوح تام، وتُسجَّل مع الحصة.',
                  en: 'Pen, highlighter, shapes, Arabic and English text and several pages. Crisp for everyone, and recorded with the class.',
                  meetingAr: 'قلم وقلم تظليل وأشكال ونص بالعربية والإنجليزية وصفحات متعددة. يراها الجميع بوضوح تام، وتُسجَّل مع الاجتماع.',
                  meetingEn: 'Pen, highlighter, shapes, Arabic and English text and several pages. Crisp for everyone, and recorded with the meeting.'),
              style: appText(12.5, c: c.textMedium, h: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      AppPrimaryButton(
        key: const ValueKey('share.start_whiteboard'),
        label: t('ابدأ السبورة', 'Start whiteboard'),
        icon: Icons.draw_rounded,
        onPressed: onStartWhiteboard,
      ),
    ]);
  }
}

/// Screen | Whiteboard.
class _ShareTabs extends StatelessWidget {
  const _ShareTabs({required this.value, this.onChanged});

  final ShareTab value;
  final ValueChanged<ShareTab>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(ShareTab tab, IconData icon, String label) {
      final on = tab == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('share.tab.${tab.name}'),
            onTap: onChanged == null ? null : () => onChanged!(tab),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: on ? c.cardShadow : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 19, color: on ? c.primary : c.textMedium),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appText(14, w: on ? FontWeight.w800 : FontWeight.w600, c: on ? c.textDark : c.textMedium)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        seg(ShareTab.screen, Icons.screen_share_rounded, t('الشاشة', 'Screen')),
        const SizedBox(width: 4),
        seg(ShareTab.whiteboard, Icons.draw_rounded, t('سبورة بيضاء', 'Whiteboard')),
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
