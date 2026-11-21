// lib/features/games/shell/game_shell.dart — the frame every game is played in (Learning Hub v2 §3, D-1580..D-1582):
//
//   GameShell            a calm header on the game's theme tint (steps bar, "3 of 8", the score so far with the
//                        stars it is worth, the sound toggle), the engine under it, and a short right / wrong
//                        response: the feedback chip pops (AppBump) and a right answer throws a light burst of
//                        particles drawn by ONE CustomPainter. Under Reduce motion nothing moves; the chip still
//                        says it.
//   GameShellController  what the engine reports (`report(done:, score:, correct:)`); the header listens to it, the
//                        engine is never rebuilt by it
//   GameShellScope       hands the controller to the engine: `GameShellScope.maybeOf(context)` (no dependency). An
//                        engine outside a shell (a test, the nahw exercises) draws its own progress header
//   GameFeedback         the sound / vibration cue and the per-device mute (SharedPreferences `games.muted`). No
//                        audio package is in the app (D-1582), so the cue is a light vibration where the device has
//                        one; the toggle is labelled "Sound and vibration" so a later sound file needs no new switch
//   GameTheme            `sand | sea | night | garden` as block tones of the live theme (never a fixed colour):
//                        sand = peach, sea = sage, night = the forest hero (cream ink), garden = emerald
//   GameFinishView       the end: stars filling in one by one, the score, the points earned, new badges, the save
//                        state, Play again / Back (keys `learn.result.*`, as the learn kit's result)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme
// ─────────────────────────────────────────────────────────────────────────────

/// The game themes the server stores (`theme`).
const List<String> kGameThemes = ['sand', 'sea', 'night', 'garden'];

String gameThemeName(String key) => switch (key) {
      'sea' => t('البحر', 'Sea'),
      'night' => t('الليل', 'Night'),
      'garden' => t('الحديقة', 'Garden'),
      _ => t('الرمال', 'Sand'),
    };

/// The block tone a theme is drawn in (an unknown or empty theme is sand).
AppBlockTone gameThemeTone(String? key) => switch (key) {
      'sea' => AppBlockTone.sky,
      'night' => AppBlockTone.forest,
      'garden' => AppBlockTone.emerald,
      _ => AppBlockTone.peach,
    };

AppBlockColors gameThemeColors(BuildContext context, String? key) => AppBlockColors.of(context, gameThemeTone(key));

// ─────────────────────────────────────────────────────────────────────────────
//  Sound / vibration
// ─────────────────────────────────────────────────────────────────────────────

class GameFeedback {
  GameFeedback._();

  static final GameFeedback instance = GameFeedback._();

  static const String _key = 'games.muted';

  /// True = no cue. Read from the device once, the first time a shell opens.
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      muted.value = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> setMuted(bool v) async {
    muted.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }

  /// The cue for one answer (nothing when muted).
  void cue(bool correct) {
    if (muted.value) return;
    if (correct) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.lightImpact();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Controller + scope
// ─────────────────────────────────────────────────────────────────────────────

/// One round's running state as the header draws it.
class GameShellController extends ChangeNotifier {
  GameShellController({this.total = 0});

  /// Steps in the round (questions, pairs, items, words).
  int total;
  int done = 0, score = 0;

  /// Bumps on every right / wrong answer; [lastCorrect] says which.
  final ValueNotifier<int> feedback = ValueNotifier<int>(0);
  bool? lastCorrect;

  /// The engine's report: steps done, the score so far, and whether this answer was right (null = no answer, e.g. an
  /// item placed but not checked yet).
  void report({int? done, int? score, bool? correct}) {
    if (done != null) this.done = done.clamp(0, math.max(total, done));
    if (score != null) this.score = score;
    if (correct != null) {
      lastCorrect = correct;
      GameFeedback.instance.cue(correct);
      feedback.value++;
    }
    notifyListeners();
  }

  void reset({int? total}) {
    if (total != null) this.total = total;
    done = score = 0;
    lastCorrect = null;
    notifyListeners();
  }

  @override
  void dispose() {
    feedback.dispose();
    super.dispose();
  }
}

class GameShellScope extends InheritedWidget {
  const GameShellScope({super.key, required this.controller, required super.child});

  final GameShellController controller;

  /// The shell around [context], or null (no dependency: a report never rebuilds the engine).
  static GameShellController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GameShellScope>()?.controller;

  @override
  bool updateShouldNotify(GameShellScope old) => old.controller != controller;
}

// ─────────────────────────────────────────────────────────────────────────────
//  The shell
// ─────────────────────────────────────────────────────────────────────────────

class GameShell extends StatefulWidget {
  const GameShell({super.key, required this.controller, required this.child, this.theme, this.showMute = true});

  final GameShellController controller;

  /// `sand | sea | night | garden`.
  final String? theme;
  final Widget child;

  /// The sound toggle (off in the editor's preview).
  final bool showMute;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  @override
  void initState() {
    super.initState();
    GameFeedback.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return GameShellScope(
      controller: widget.controller,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(clipBehavior: Clip.none, children: [
          RepaintBoundary(
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => GameShellHeader(
                theme: widget.theme,
                done: widget.controller.done,
                total: widget.controller.total,
                score: widget.controller.score,
                feedbackSeq: widget.controller.feedback.value,
                lastCorrect: widget.controller.lastCorrect,
                showMute: widget.showMute,
              ),
            ),
          ),
          Positioned.fill(child: IgnorePointer(child: GameBurst(controller: widget.controller))),
        ]),
        const SizedBox(height: AppSpace.md),
        widget.child,
      ]),
    );
  }
}

/// The header with plain values (the layout harness pumps it directly).
class GameShellHeader extends StatelessWidget {
  const GameShellHeader({
    super.key,
    this.theme,
    required this.done,
    required this.total,
    required this.score,
    this.feedbackSeq = 0,
    this.lastCorrect,
    this.showMute = true,
  });

  final String? theme;
  final int done, total, score, feedbackSeq;
  final bool? lastCorrect;
  final bool showMute;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = gameThemeColors(context, theme);
    final value = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final right = lastCorrect;
    return Container(
      key: const ValueKey('games.shell.header'),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.md),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: AppRadius.cardAll,
        border: b.border == null ? null : Border.all(color: b.border!),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(
                total <= 0 ? t('جولة', 'Round') : t('$done من $total', '$done of $total'),
                style: AppType.section(context).copyWith(color: b.ink),
              ),
              AppBump(
                trigger: score,
                child: Text(t('النقاط $score', 'Score $score'),
                    key: const ValueKey('games.shell.score'), style: AppType.label(context).copyWith(color: b.muted)),
              ),
              if (total > 0) LearnStars(stars: learnStars(score, total), size: AppIconSize.sm),
              if (right != null)
                AppBump(
                  key: const ValueKey('games.shell.feedback'),
                  trigger: feedbackSeq,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                    decoration: BoxDecoration(
                      color: c.cardBg,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(right ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: AppIconSize.sm, color: right ? c.success : c.danger),
                      const SizedBox(width: AppSpace.xxs),
                      Text(right ? t('صحيح', 'Right') : t('ليس تماماً', 'Not quite'),
                          style: AppType.label(context).copyWith(color: c.textDark)),
                    ]),
                  ),
                ),
            ]),
          ),
          if (showMute) _MuteButton(color: b.ink),
        ]),
        const SizedBox(height: AppSpace.xs),
        Semantics(
          label: t('التقدم $done من $total', 'Progress $done of $total'),
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: AppSpace.xs,
              child: AppFill(
                value: value,
                duration: AppMotion.of(context).slow,
                builder: (context, v) => Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: b.ink.withValues(alpha: 0.14)),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: v,
                    child: ColoredBox(color: b.accentInk(c.primary)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GameFeedback.instance.muted,
      builder: (context, muted, _) => IconButton(
        key: const ValueKey('games.shell.mute'),
        tooltip: muted ? t('تشغيل الصوت والاهتزاز', 'Turn sound and vibration on') : t('كتم الصوت والاهتزاز', 'Mute sound and vibration'),
        icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
        color: color,
        onPressed: () => GameFeedback.instance.setMuted(!muted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The burst
// ─────────────────────────────────────────────────────────────────────────────

/// A light burst of particles over the header after a right answer: one-shot (560 ms), one CustomPainter, nothing
/// under Reduce motion.
class GameBurst extends StatefulWidget {
  const GameBurst({super.key, required this.controller});

  final GameShellController controller;

  @override
  State<GameBurst> createState() => _GameBurstState();
}

class _GameBurstState extends State<GameBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.controller.feedback.addListener(_onFeedback);
  }

  @override
  void didUpdateWidget(GameBurst old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.feedback.removeListener(_onFeedback);
      widget.controller.feedback.addListener(_onFeedback);
    }
  }

  void _onFeedback() {
    if (!mounted || widget.controller.lastCorrect != true || appMotionOff(context)) return;
    _c
      ..duration = AppMotion.of(context).slow * 2 // the burst: two slow beats
      ..forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.feedback.removeListener(_onFeedback);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colors = [c.success, appToneColor(context, AppTone.gold), c.primary];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => _c.isAnimating
            ? CustomPaint(painter: GameBurstPainter(t: _c.value, colors: colors, seed: widget.controller.feedback.value))
            : const SizedBox.expand(),
      ),
    );
  }
}

/// [t] 0..1: 16 particles fly out from the centre, shrink and fade.
class GameBurstPainter extends CustomPainter {
  GameBurstPainter({required this.t, required this.colors, this.seed = 0});

  final double t;
  final List<Color> colors;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1 || colors.isEmpty) return;
    final r = math.Random(seed);
    final centre = Offset(size.width / 2, size.height / 2);
    final reach = math.min(size.width, size.height * 3) * 0.45;
    final ease = Curves.easeOutCubic.transform(t);
    final paint = Paint();
    for (var i = 0; i < 16; i++) {
      final a = (i / 16) * math.pi * 2 + r.nextDouble() * 0.4;
      final d = reach * (0.5 + r.nextDouble() * 0.5) * ease;
      paint.color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(centre + Offset(math.cos(a) * d, math.sin(a) * d * 0.6), 2 + 3 * (1 - t), paint);
    }
  }

  @override
  bool shouldRepaint(GameBurstPainter old) => old.t != t || old.seed != seed;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Finish
// ─────────────────────────────────────────────────────────────────────────────

/// One thing earned (a badge) for [GameFinishView].
typedef GameEarned = ({IconData icon, String label});

class GameFinishView extends StatelessWidget {
  const GameFinishView({
    super.key,
    required this.score,
    required this.max,
    this.stars,
    this.theme,
    this.points = 0,
    this.badges = const [],
    this.saving = false,
    this.saveError,
    this.onRetrySave,
    this.note,
    this.onReplay,
    this.onDone,
  });

  final int score, max;

  /// The server's stars (null = from the score).
  final int? stars;
  final String? theme;
  final int points;
  final List<GameEarned> badges;
  final bool saving;
  final String? saveError;
  final VoidCallback? onRetrySave, onReplay, onDone;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = gameThemeColors(context, theme);
    final s = (stars ?? learnStars(score, max)).clamp(0, 3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const ValueKey('games.finish'),
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: AppRadius.cardAll,
          border: b.border == null ? null : Border.all(color: b.border!),
        ),
        child: Column(children: [
          GameStarsFill(stars: s),
          const SizedBox(height: AppSpace.sm),
          Text(learnResultTitle(s), textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: b.ink)),
          const SizedBox(height: AppSpace.xxs),
          Text('$score / $max · ${learnPercent(score, max)}%',
              key: const ValueKey('learn.result.score'),
              textAlign: TextAlign.center,
              style: AppType.section(context).copyWith(color: b.muted)),
          if (points > 0) ...[
            const SizedBox(height: AppSpace.sm),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stars_rounded, color: b.accentInk(appToneColor(context, AppTone.gold)), size: AppIconSize.md),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: AppCountUp('+$points', style: AppType.section(context).copyWith(color: b.ink)),
              ),
              const SizedBox(width: AppSpace.xxs),
              Text(t('نقطة', 'points'), style: AppType.label(context).copyWith(color: b.muted)),
            ]),
          ],
          if (badges.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(t('شارات جديدة', 'New badges'), style: AppType.label(context).copyWith(color: b.muted)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.center, children: [
              for (final e in badges) AppPopIn(child: LearnBadgeChip(icon: e.icon, label: e.label)),
            ]),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(note!, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: b.muted)),
          ],
        ]),
      ),
      if (saving) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('جارٍ حفظ النتيجة…', 'Saving your result…'), textAlign: TextAlign.center, style: AppType.meta(context)),
      ] else if (saveError != null) ...[
        const SizedBox(height: AppSpace.sm),
        Text(saveError!, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.danger)),
        if (onRetrySave != null)
          Align(
            child: AppButton.ghost(
              key: const ValueKey('learn.result.retry'),
              label: t('أعد المحاولة', 'Try again'),
              icon: Icons.refresh_rounded,
              onPressed: onRetrySave,
            ),
          ),
      ],
      const SizedBox(height: AppSpace.md),
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, alignment: WrapAlignment.center, children: [
        if (onReplay != null)
          AppButton.primary(
            key: const ValueKey('learn.result.replay'),
            label: t('العب مرة أخرى', 'Play again'),
            icon: Icons.replay_rounded,
            onPressed: onReplay,
          ),
        AppButton.secondary(key: const ValueKey('learn.result.done'), label: t('رجوع', 'Back'), onPressed: onDone),
      ]),
    ]);
  }
}

/// Three stars that fill in one after another (150 ms apart); all at once under Reduce motion.
class GameStarsFill extends StatelessWidget {
  const GameStarsFill({super.key, required this.stars, this.size = 44});

  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = appToneColor(context, AppTone.gold);
    final still = appMotionOff(context);
    Widget star(int i) {
      final on = i < stars;
      final icon = Icon(on ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: on ? gold : c.textLight);
      if (!on || still) return icon;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 320 + 150 * i),
        curve: Curves.easeOutBack,
        builder: (context, v, child) {
          // each star waits its turn: the first 150 ms × i of its own timeline are the delay
          final start = (150 * i) / (320 + 150 * i);
          final k = v <= start ? 0.0 : ((v - start) / (1 - start)).clamp(0.0, 1.2);
          return Stack(alignment: Alignment.center, children: [
            Icon(Icons.star_outline_rounded, size: size, color: c.textLight),
            Transform.scale(scale: k, child: child),
          ]);
        },
        child: icon,
      );
    }

    return Semantics(
      label: t('$stars من 3 نجوم', '$stars of 3 stars'),
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 3; i++) star(i)]),
    );
  }
}
