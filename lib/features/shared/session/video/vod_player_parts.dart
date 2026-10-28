// Pure pieces of the course video player (no VideoPlayerController): resume logic, playlist helpers and the
// overlay widgets (next-up card, lecture list, resume chip, volume/brightness HUD, captions, skeleton).
// Kept apart from video_player_screen.dart so they can be layout-tested without a platform player.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../../design/app_kit.dart';
import '../../../admin/admin_common.dart' show t;
import '../material/session_material_model.dart';

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
  static const Color textMid = Color(0xB3FFFFFF);
  static const Color textSoft = Color(0x99FFFFFF);
  static const Color textLow = Color(0x66FFFFFF);
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

TextStyle _w(double size, {FontWeight w = FontWeight.w600, Color c = VodInk.textHigh}) =>
    TextStyle(color: c, fontSize: size, fontWeight: w, fontFamily: 'tajawal');

// ── Next up ────────────────────────────────────────────────────────────────

class VodNextUpCard extends StatelessWidget {
  const VodNextUpCard({super.key, required this.next, required this.seconds, required this.onPlay, required this.onCancel, this.maxWidth = 360});

  final SessionMaterialModel next;

  /// Countdown left before auto-play; null = countdown cancelled.
  final int? seconds;
  final VoidCallback onPlay, onCancel;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VodInk.shade(0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: VodInk.ink(0.14)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(seconds == null ? t('التالي', 'Up next') : t('التالي خلال $seconds ث', 'Up next in ${seconds}s'),
              style: _w(12, c: VodInk.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(next.name, style: _w(15, w: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (next.durationSeconds != null)
            Text(vodFmt(Duration(seconds: next.durationSeconds!)), style: _w(12, c: VodInk.textSoft)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            if (seconds != null)
              TextButton(onPressed: onCancel, child: Text(t('إلغاء', 'Cancel'), style: _w(13, c: VodInk.textMid))),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.primary, foregroundColor: VodInk.textHigh),
              onPressed: onPlay,
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: Text(t('تشغيل الآن', 'Play now'), style: _w(13, w: FontWeight.w700)),
            ),
          ]),
        ]),
        ),
      ),
    );
  }
}

// ── Lecture list ───────────────────────────────────────────────────────────

class VodLectureList extends StatelessWidget {
  const VodLectureList({super.key, required this.items, required this.currentId, required this.onSelect});

  final List<SessionMaterialModel> items;
  final int currentId;
  final void Function(SessionMaterialModel) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (items.isEmpty) return AppEmpty(icon: Icons.video_library_outlined, title: t('لا توجد محاضرات', 'No lectures'));
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final m = items[i];
        final on = m.id == currentId;
        return Material(
          color: on ? c.primary.withValues(alpha: 0.12) : c.cardBg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: on ? null : () => onSelect(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? c.primary : c.divider.withValues(alpha: 0.6),
                  ),
                  child: on
                      ? const Icon(Icons.equalizer_rounded, color: VodInk.textHigh, size: 18)
                      : Text('${i + 1}', style: appText(12, w: FontWeight.w700, c: c.textDark)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name,
                        style: appText(13.5, w: on ? FontWeight.w800 : FontWeight.w600, c: c.textDark),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (m.durationSeconds != null)
                      Text(vodFmt(Duration(seconds: m.durationSeconds!)), style: appText(11.5, c: c.textMedium)),
                  ]),
                ),
                if (m.completed) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, color: c.success, size: 18),
                ],
              ]),
            ),
          ),
        );
      },
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
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: VodInk.shade(0.7),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: VodInk.ink(0.16)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.history_rounded, color: VodInk.textHigh, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(t('استكمال من ${vodFmt(at)}', 'Resumed at ${vodFmt(at)}'),
              style: _w(12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        TextButton(
          onPressed: onStartOver,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: Text(t('من البداية', 'Start over'), style: _w(12, w: FontWeight.w800, c: context.colors.primary)),
        ),
      ]),
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
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: VodInk.shade(0.65), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: VodInk.textHigh, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 4,
              color: context.colors.primary,
              backgroundColor: VodInk.glassBorder,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: VodInk.shade(0.7), borderRadius: BorderRadius.circular(6)),
        child: Text(text, textAlign: TextAlign.center, style: _w(15, w: FontWeight.w600, c: VodInk.textHigh), maxLines: 3),
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
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (onBack == null)
                const SizedBox(width: 36)
              else
                IconButton(
                  tooltip: t('رجوع', 'Back'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VodInk.textHigh, size: 20),
                ),
              Expanded(
                child: title == null
                    ? const Align(alignment: AlignmentDirectional.centerStart, child: _Bar(width: 160, height: 14))
                    : Text(title!, style: _w(15, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const Spacer(),
            const Center(child: _Bar(width: 72, height: 72, radius: 36)),
            const Spacer(),
            const _Bar(height: 4),
            const SizedBox(height: 12),
            const Row(children: [_Bar(width: 70, height: 10), Spacer(), _Bar(width: 90, height: 22, radius: 11)]),
          ]),
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
