// Pure pieces of the course video player (no VideoPlayerController): resume logic, playlist helpers and the
// overlay widgets (next-up card, lecture list, resume chip, volume/brightness HUD, captions, skeleton).
// Kept apart from video_player_screen.dart so they can be layout-tested without a platform player.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/core/display/display_settings.dart';

String vodFmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Where a lecture was left, per material. Positions too close to the start or the end are not worth resuming.
class VodResume {
  static String _key(int sessionId, int id) => 'vod_pos_${sessionId}_$id';

  static Duration? pick(Duration saved, Duration total) {
    if (saved < const Duration(seconds: 10)) return null;
    if (total > Duration.zero && saved > total - const Duration(seconds: 15)) return null;
    return saved;
  }

  static Future<Duration?> load(int sessionId, int id) async {
    if (id == 0) return null;
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_key(sessionId, id));
      return ms == null ? null : Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(int sessionId, int id, Duration pos, Duration total) async {
    if (id == 0) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (pick(pos, total) == null) {
        await p.remove(_key(sessionId, id));
      } else {
        await p.setInt(_key(sessionId, id), pos.inMilliseconds);
      }
    } catch (_) {}
  }
}

bool vodPlayable(SessionMaterialModel m) =>
    m.type == SessionMaterialType.video || m.type == SessionMaterialType.recorded;

/// The playable lectures of [all] in order, and the one after [current] (null at the end).
List<SessionMaterialModel> vodPlaylist(List<SessionMaterialModel> all) => all.where(vodPlayable).toList();

SessionMaterialModel? vodNextOf(List<SessionMaterialModel> list, SessionMaterialModel current) {
  final i = list.indexWhere((m) => m.id == current.id && m.sessionId == current.sessionId);
  return i < 0 || i + 1 >= list.length ? null : list[i + 1];
}

/// Ink of the player chrome. Everything here is drawn OVER the video (controls, HUD, captions, next-up card), so it
/// is fixed white / black at set alphas — readable on any frame in both app themes; the theme's primary still
/// colours buttons and progress. [letterbox] is the pure black behind the picture (bars around a 4:3 video) and stays
/// black on purpose. Every colour of the player goes through this class or context.colors, never Colors.*.
class VodInk {
  VodInk._();
  static const Color letterbox = Color(0xFF000000);
  static const Color textHigh = Color(0xFFFFFFFF);
  // high contrast (Display & reading) lifts the dimmer labels: time, chapter, hints
  static Color get textMid => _hc ? const Color(0xE6FFFFFF) : const Color(0xB3FFFFFF);
  static Color get textSoft => _hc ? const Color(0xD9FFFFFF) : const Color(0x99FFFFFF);
  static Color get textLow => _hc ? const Color(0xB3FFFFFF) : const Color(0x66FFFFFF);
  static bool get _hc => DisplaySettings.instance.prefs.highContrast;
  static const Color glass = Color(0x1AFFFFFF);
  static const Color glassFaint = Color(0x0DFFFFFF);
  static const Color glassBorder = Color(0x3DFFFFFF);
  static const Color hairline = Color(0x14FFFFFF);
  static const Color scrim = Color(0x99000000);
  static const Color scrimLight = Color(0x8A000000);
  static const Color scrimHeavy = Color(0xB3000000);
  static const Color tooltipBg = Color(0xF0101420);

  /// Black / white at [a]: scrims, shadows and glass over the video.
  static Color shade(double a) => letterbox.withValues(alpha: a);
  static Color ink(double a) => textHigh.withValues(alpha: a);
}

/// A kit text role ([AppType]) in the chrome's ink: everything here is drawn over the picture.
TextStyle vodText(TextStyle role, [Color ink = VodInk.textHigh]) => role.copyWith(color: ink);

/// Times and counts in the chrome: tabular, so a running clock never jitters.
const List<FontFeature> vodTabular = [FontFeature.tabularFigures()];

/// The glass the chrome's floating pieces sit on (next up, resume, HUD, captions): a deep scrim with a faint ink
/// hairline, a radius by hierarchy.
BoxDecoration vodGlass({double radius = AppRadius.card, double alpha = 0.72, bool lifted = false}) => BoxDecoration(
      color: VodInk.shade(alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: VodInk.ink(0.14), width: AppBorder.hairline),
      boxShadow: lifted ? [BoxShadow(color: VodInk.shade(0.35), blurRadius: AppSpace.lg, offset: const Offset(0, AppSpace.xs))] : null,
    );

// ── Next up ────────────────────────────────────────────────────────────────

/// The card that offers the next lecture when this one ends: the next title in the editorial face, its length, and
/// a thin emerald line along the top that drains with the auto-play countdown.
class VodNextUpCard extends StatelessWidget {
  const VodNextUpCard({
    super.key,
    required this.next,
    required this.seconds,
    required this.onPlay,
    required this.onCancel,
    this.maxWidth = 360,
    this.total = 5,
  });

  final SessionMaterialModel next;

  /// Countdown left before auto-play; null = countdown cancelled.
  final int? seconds;
  final VoidCallback onPlay, onCancel;
  final double maxWidth;

  /// The countdown's length in seconds (the line is full at [total]).
  final int total;

  @override
  Widget build(BuildContext context) {
    final s = seconds;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: vodGlass(radius: AppRadius.block, alpha: 0.8, lifted: true),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.block),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s != null) _Countdown(fraction: total <= 0 ? 0 : ((s - 1) / total).clamp(0.0, 1.0).toDouble()),
              Padding(
                padding: EdgeInsets.fromLTRB(AppSpace.md, s == null ? AppSpace.md : AppSpace.sm, AppSpace.md, AppSpace.md),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.skip_next_rounded, color: VodInk.textMid, size: AppIconSize.sm),
                    const SizedBox(width: AppSpace.xxs),
                    Flexible(
                      child: Text(s == null ? t('التالي', 'Up next') : t('التالي خلال $s ث', 'Up next in ${s}s'),
                          style: vodText(AppType.label(context), VodInk.textMid).copyWith(fontFeatures: vodTabular),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.xs),
                  Text(next.name, style: vodText(AppType.section(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (next.durationSeconds != null) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Text(vodFmt(Duration(seconds: next.durationSeconds!)),
                        textDirection: TextDirection.ltr,
                        style: vodText(AppType.meta(context), VodInk.textSoft).copyWith(fontFeatures: vodTabular)),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Wrap(
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.xs,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (s != null)
                        TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: VodInk.textMid,
                            minimumSize: const Size(AppTouch.min, AppTouch.min),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
                          ),
                          child: Text(t('إلغاء', 'Cancel'), style: vodText(AppType.label(context), VodInk.textMid)),
                        ),
                      AppButton.primary(label: t('تشغيل الآن', 'Play now'), icon: Icons.skip_next_rounded, onPressed: onPlay),
                    ],
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The next-up countdown: a 3 px emerald line that drains linearly, one second per step (still under Reduce motion).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final off = AppMotion.of(context).off;
    return SizedBox(
      height: AppSpace.xxs - 1,
      child: ColoredBox(
        color: VodInk.ink(0.10),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: fraction),
          duration: off ? Duration.zero : const Duration(seconds: 1),
          builder: (context, v, _) => FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: v,
            child: ColoredBox(color: context.colors.primary),
          ),
        ),
      ),
    );
  }
}

// ── Lecture list ───────────────────────────────────────────────────────────

/// The lectures of the playlist as a numbered reading list: the one playing is an emerald block with an equaliser
/// glyph, the finished ones carry a quiet check, the rest are paper rows on warm hairlines.
class VodLectureList extends StatelessWidget {
  const VodLectureList({super.key, required this.items, required this.currentId, required this.onSelect});

  final List<SessionMaterialModel> items;
  final int currentId;
  final void Function(SessionMaterialModel) onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return AppEmpty(icon: Icons.video_library_outlined, title: t('لا توجد محاضرات', 'No lectures'));
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (_, i) => _LectureRow(lecture: items[i], number: i + 1, on: items[i].id == currentId, onSelect: onSelect),
    );
  }
}

class _LectureRow extends StatelessWidget {
  const _LectureRow({required this.lecture, required this.number, required this.on, required this.onSelect});

  final SessionMaterialModel lecture;
  final int number;
  final bool on;
  final void Function(SessionMaterialModel) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = lecture;
    final surface = on ? c.blockEmerald : c.cardBg;
    final muted = c.blockMuted(surface);
    return Semantics(
      selected: on,
      child: AppPressScale(
        enabled: !on,
        child: Material(
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: on ? BorderSide.none : BorderSide(color: c.divider, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: on ? null : () => onSelect(m),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(children: [
                  SizedBox(
                    width: AppSpace.xl,
                    child: on
                        ? Icon(Icons.equalizer_rounded, color: c.blockAccentInk(c.primary, surface), size: AppIconSize.md)
                        : Text(number.toString().padLeft(2, '0'),
                            textDirection: TextDirection.ltr,
                            style: AppType.label(context).copyWith(color: muted, fontFeatures: vodTabular)),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name,
                          style: AppType.row(context).copyWith(
                              color: c.blockInk, fontWeight: on ? FontWeight.w600 : FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (m.durationSeconds != null) ...[
                        const SizedBox(height: AppSpace.xxs / 2),
                        Text(vodFmt(Duration(seconds: m.durationSeconds!)),
                            textDirection: TextDirection.ltr,
                            style: AppType.meta(context).copyWith(color: muted, fontFeatures: vodTabular)),
                      ],
                    ]),
                  ),
                  if (m.completed) ...[
                    const SizedBox(width: AppSpace.xs),
                    Icon(Icons.check_circle_rounded,
                        color: c.blockAccentInk(c.success, surface), size: AppIconSize.md, semanticLabel: 'completed'.tr),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showVodLectureList(BuildContext context,
    {required List<SessionMaterialModel> items, required int currentId, required void Function(SessionMaterialModel) onSelect}) =>
    showAppSheet<void>(
      context,
      (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('المحاضرات', 'Lectures')),
        Flexible(
          child: VodLectureList(
            items: items,
            currentId: currentId,
            onSelect: (m) {
              Navigator.pop(ctx);
              onSelect(m);
            },
          ),
        ),
      ]),
    );

// ── Resume chip ────────────────────────────────────────────────────────────

class VodResumeChip extends StatelessWidget {
  const VodResumeChip({super.key, required this.at, required this.onStartOver});

  final Duration at;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: vodGlass(radius: AppRadius.pill, alpha: 0.72),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xxs, 0),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.history_rounded, color: VodInk.textHigh, size: AppIconSize.sm),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(t('استكمال من ${vodFmt(at)}', 'Resumed at ${vodFmt(at)}'),
                style: vodText(AppType.label(context)).copyWith(fontFeatures: vodTabular),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: onStartOver,
            style: TextButton.styleFrom(
              foregroundColor: VodInk.textHigh,
              minimumSize: const Size(AppTouch.min, AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              shape: const StadiumBorder(),
            ),
            // the theme's primary is too dark on the scrim: the action reads as an underlined ink link
            child: Text(t('من البداية', 'Start over'),
                style: vodText(AppType.label(context)).copyWith(
                    fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: VodInk.textSoft)),
          ),
        ]),
      ),
    );
  }
}

// ── Volume / brightness HUD ────────────────────────────────────────────────

class VodLevelHud extends StatelessWidget {
  const VodLevelHud({super.key, required this.brightness, required this.value});

  final bool brightness;
  final double value;

  @override
  Widget build(BuildContext context) {
    final icon = brightness
        ? (value < 0.35 ? Icons.brightness_low_rounded : Icons.brightness_high_rounded)
        : (value == 0 ? Icons.volume_off_rounded : (value < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded));
    final v = value.clamp(0.0, 1.0).toDouble();
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: vodGlass(radius: AppRadius.pill, alpha: 0.68),
      child: Row(children: [
        Icon(icon, color: VodInk.textHigh, size: AppIconSize.md),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: AppSpace.xxs,
              child: ColoredBox(
                color: VodInk.glassBorder,
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: v,
                  child: const ColoredBox(color: VodInk.textHigh),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Captions ───────────────────────────────────────────────────────────────

class VodCaption extends StatelessWidget {
  const VodCaption({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final role = AppType.bodyStrong(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
        decoration: BoxDecoration(color: VodInk.shade(0.72), borderRadius: AppRadius.chipAll),
        // subtitles are read while watching, from further away: the body role a step up
        child: Text(text,
            textAlign: TextAlign.center,
            style: vodText(role).copyWith(fontSize: (role.fontSize ?? 14) + 2, height: 1.4),
            maxLines: 3),
      ),
    );
  }
}

// ── Skeleton (first load) ──────────────────────────────────────────────────

class VodPlayerSkeleton extends StatelessWidget {
  const VodPlayerSkeleton({super.key, this.title, this.onBack});

  final String? title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VodInk.letterbox,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (onBack == null)
                const SizedBox(width: AppTouch.min)
              else
                VodBackButton(onPressed: onBack!),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: title == null
                    ? const Align(alignment: AlignmentDirectional.centerStart, child: _Bar(width: 160, height: 14))
                    : Text(title!, style: vodText(AppType.section(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const Spacer(),
            const Center(child: _Bar(width: 72, height: 72, radius: 36)),
            const Spacer(),
            const _Bar(height: AppSpace.xxs),
            const SizedBox(height: AppSpace.sm),
            const Row(children: [_Bar(width: 70, height: 10), Spacer(), _Bar(width: 90, height: 22, radius: AppRadius.chip)]),
          ]),
        ),
      ),
    );
  }
}

/// The player's back button: a glass disc in a 48 px target (the arrow mirrors in Arabic by itself).
class VodBackButton extends StatelessWidget {
  const VodBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      VodGlassButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: t('رجوع', 'Back'), onTap: onPressed, bright: true);
}

/// A round glass button of the player chrome: a 40 px disc in a 48 px target, press depth, the tooltip as its label.
class VodGlassButton extends StatelessWidget {
  const VodGlassButton({super.key, required this.icon, required this.onTap, this.tooltip, this.bright = false, this.child});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Full-white icon (navigation); the others sit a step back.
  final bool bright;

  /// Drawn instead of the icon (a download ring).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tip = tooltip ?? '';
    return Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        label: tip.isEmpty ? null : tip,
        excludeSemantics: tip.isNotEmpty,
        onTap: onTap,
        child: AppPressScale(
          scale: 0.92,
          child: InkResponse(
            onTap: onTap,
            radius: AppTouch.min / 2,
            child: SizedBox.square(
              dimension: AppTouch.min,
              child: Center(
                child: Container(
                  width: AppSpace.xl + AppSpace.xs,
                  height: AppSpace.xl + AppSpace.xs,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VodInk.ink(0.10),
                    border: Border.all(color: VodInk.ink(0.16), width: AppBorder.hairline),
                  ),
                  child: child ?? Icon(icon, color: bright ? VodInk.textHigh : VodInk.textMid, size: AppIconSize.md - 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatefulWidget {
  const _Bar({this.width, required this.height, this.radius = 6});
  final double? width;
  final double height, radius;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c, reverse: true); // reduce motion parks this decorative loop
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 0.8).animate(_c),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(color: VodInk.glassBorder, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

// ── Stream switching (quality / audio) and listen-only (D-104) ─────────────

/// What picking a stream does: nothing (it is the one playing), refuse (no link for it), or switch.
enum VodSwitch { same, unavailable, go }

VodSwitch vodSwitchDecision(MaterialVariant from, MaterialVariant to) {
  final url = to.url;
  if (url == null || url.isEmpty) return VodSwitch.unavailable;
  if (url == from.url) return VodSwitch.same;
  return VodSwitch.go;
}

/// What a stream switch carries from the old stream to the new one: the place, play / pause, speed and captions.
/// A switch never starts the lecture over and never closes the player; when the new stream fails, the old one
/// simply goes on.
class VodCarry {
  const VodCarry({required this.position, required this.playing, this.speed = 1.0, this.captionsOn = false});

  final Duration position;
  final bool playing;
  final double speed;
  final bool captionsOn;

  /// [position] inside a stream [total] long: another file of the same lecture may be a little shorter (the audio
  /// track, a re-encoded tier), so the end is kept half a second inside it. An unknown length keeps the position.
  Duration seekIn(Duration total) {
    if (position <= Duration.zero) return Duration.zero;
    if (total <= Duration.zero) return position;
    final last = total - const Duration(milliseconds: 500);
    if (last <= Duration.zero) return Duration.zero;
    return position > last ? last : position;
  }
}

/// The stream listen-only mode plays: no picture to decode when the lecture has an audio track (the one paired with
/// the quality on screen first), else the lightest video tier (the least data while nobody watches). An offline copy
/// is the only stream there is, and a stream already audio stays.
MaterialVariant vodListenVariant(SessionMaterialModel m, MaterialVariant current, {bool offline = false}) {
  if (current.isAudio || offline) return current;
  bool ok(MaterialVariant v) => v.url != null && v.url!.isNotEmpty;
  final audio = m.audioVariants.where(ok).toList();
  if (audio.isNotEmpty) {
    final paired = current.tier == QualityTier.high ? QualityTier.high : QualityTier.medium;
    return audio.firstWhere((v) => v.tier == paired, orElse: () => audio.first);
  }
  final video = m.videoVariants.where(ok).toList(); // low → high
  return video.isEmpty ? current : video.first;
}

/// Where the listen-only bar's progress line is, 0…1 ([dragging] wins while the finger is on it).
double vodFraction(Duration position, Duration total, {double? dragging}) {
  if (dragging != null) return dragging.clamp(0.0, 1.0).toDouble();
  if (total <= Duration.zero) return 0;
  return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();
}

/// The lecture is at its end (the replay button replaces play).
bool vodFinished(Duration position, Duration total, {required bool playing}) =>
    !playing && total > Duration.zero && position >= total - const Duration(milliseconds: 300);

/// The listen bar's speed chip: the next of [steps] after [current] (a speed between two steps goes to the next one
/// above it; past the last one, back to the first).
double vodNextChipSpeed(double current, List<double> steps) {
  for (final s in steps) {
    if (s > current + 0.001) return s;
  }
  return steps.first;
}

/// "1×", "1.5×", "0.75×" — the speed as the bar's chip shows it.
String vodSpeedLabel(double s) => '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString()}×';

/// Opens a picker sheet (quality, speed, …) over the player and returns what was picked (null when dismissed).
///
/// The sheet is closed with ITS OWN context. Inside a role shell (D-081) a bottom sheet goes to the ROOT navigator
/// while the player is a page of the tab's navigator, so `Navigator.pop(playerContext)` closed the player instead of
/// the sheet: that was "switching the quality closes the video".
///
/// The sheet takes no tap until it has finished sliding in ([VodSheetSettle]): its last row ("Audio only", which
/// closes the player into the bar) rises right under the chip that opened it, so a second tap on the chip, or a
/// tap while the sheet is still moving, picked that row (seen on the S24, round 7).
Future<T?> showVodPicker<T>(BuildContext context, Widget Function(BuildContext sheetContext, void Function(T value) pick) builder) =>
    showAppModalSheet<T>(
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => VodSheetSettle(child: builder(sheetContext, (v) => Navigator.of(sheetContext).pop(v))),
    );

/// Ignores pointers until the enclosing route's entrance animation has completed (a sheet still sliding in).
class VodSheetSettle extends StatefulWidget {
  const VodSheetSettle({super.key, required this.child});

  final Widget child;

  @override
  State<VodSheetSettle> createState() => _VodSheetSettleState();
}

class _VodSheetSettleState extends State<VodSheetSettle> {
  Animation<double>? _animation;

  bool get _settled => _animation == null || _animation!.status == AnimationStatus.completed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (identical(a, _animation)) return;
    _animation?.removeStatusListener(_onStatus);
    _animation = a?..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(ignoring: !_settled, child: widget.child);
}

/// "Listen only" in the player's top bar: a glass pill over the video — the headphones and a short label (from
/// 400 px), the icon alone below. The tooltip says what happens.
class VodListenButton extends StatelessWidget {
  const VodListenButton({super.key, required this.onTap, required this.tooltip, this.label});

  final VoidCallback onTap;
  final String tooltip;
  final String? label;

  @override
  Widget build(BuildContext context) =>
      VodGlassPill(icon: Icons.headphones_rounded, tooltip: tooltip, label: label, labelMax: 96, onTap: onTap);
}

/// A glass pill of the top bar: an icon and, when there is room, a short label; a 40 px pill in a 48 px target.
class VodGlassPill extends StatelessWidget {
  const VodGlassPill({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.labelMax = 120,
    this.tapKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? label;
  final double labelMax;

  /// The key of the tappable part (tests find the button by it).
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final l = label;
    const side = AppSpace.xl + AppSpace.xs; // 40
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onTap, // screen readers and the web semantics tree activate the button through this
        child: AppPressScale(
          scale: 0.95,
          child: InkResponse(
            key: tapKey,
            onTap: onTap,
            radius: AppTouch.min / 2 + 2,
            child: SizedBox(
              height: AppTouch.min,
              child: Center(
                child: Container(
                  height: side,
                  constraints: const BoxConstraints(minWidth: side),
                  padding: EdgeInsetsDirectional.only(start: l == null ? 0 : AppSpace.sm, end: l == null ? 0 : AppSpace.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    color: VodInk.ink(0.10),
                    border: Border.all(color: VodInk.ink(0.16), width: AppBorder.hairline),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: VodInk.textHigh, size: AppIconSize.md - 2),
                    if (l != null) ...[
                      const SizedBox(width: AppSpace.xs - 2),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: labelMax),
                        child: Text(l,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: vodText(AppType.label(context)).copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the quality sheet answers for its "Audio only" row.
const Object vodAudioOnlyChoice = #vodAudioOnly;

/// The quality sheet's last row: "Audio only — close the video and keep listening (also in the background)". A sky
/// block (information, a different way to follow the lecture), its headphones mark on a paper disc.
class VodAudioOnlyTile extends StatelessWidget {
  const VodAudioOnlyTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final block = c.blockSky;
    return Semantics(
      button: true,
      label: '${'vod_audio_only_title'.tr}. ${'vod_audio_only_sub'.tr}',
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: AppPressScale(
          child: Material(
            color: block,
            borderRadius: AppRadius.cardAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('vod_audio_only'),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.primary),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  child: Row(children: [
                    Container(
                      width: AppSpace.xl + AppSpace.xxs,
                      height: AppSpace.xl + AppSpace.xxs,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
                      child: Icon(Icons.headphones_rounded, size: AppIconSize.md - 2, color: c.blockInk),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('vod_audio_only_title'.tr, style: AppType.bodyStrong(context).copyWith(color: c.blockInk)),
                        const SizedBox(height: AppSpace.xxs / 2),
                        Text('vod_audio_only_sub'.tr, style: AppType.meta(context).copyWith(color: c.blockMuted(block))),
                      ]),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Icon(Icons.arrow_forward_rounded, size: AppIconSize.md - 2, color: c.blockMuted(block)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Caller actions on the top bar ─────────────────────────────────────────

/// A button a caller adds to the player's top bar (Records, D-312: "Open in Studio", "Share"). [onTap] runs as is;
/// the caller decides whether the player closes first.
class VodAction {
  const VodAction({required this.icon, required this.label, required this.onTap, this.id});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Becomes the button's key (`vod.action.<id>`), for tests.
  final String? id;
}

/// The glass pill of a [VodAction]: the icon, plus the label when [showLabel] (wide screens).
class VodActionButton extends StatelessWidget {
  const VodActionButton({super.key, required this.action, this.showLabel = false});

  final VodAction action;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final a = action;
    return VodGlassPill(
      tapKey: a.id == null ? null : ValueKey('vod.action.${a.id}'),
      icon: a.icon,
      tooltip: a.label,
      label: showLabel ? a.label : null,
      onTap: a.onTap,
    );
  }
}
