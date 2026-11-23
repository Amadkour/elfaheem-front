// lib/features/games/shell/game_shell.dart — the frame every game is played in (Learning Hub v2 §3, D-1580..D-1582):
//
//   GameShell            a calm header on the game's theme tint (steps bar, "3 of 8", the score so far with the
//                        stars it is worth, the sound toggle), the engine under it, and a short right / wrong
//                        response: the feedback chip pops (AppBump) and a right answer throws a light burst of
//                        particles drawn by ONE CustomPainter. Under Reduce motion nothing moves; the chip still
//                        says it.
//   GameShellController  what the engine reports (`report(done:, score:, correct:)`); the header listens to it, the
//                        engine is never rebuilt by it. Games v3: the run of right answers (`streak`, the ×3 combo
//                        chip and a bigger burst, no points), the ranked round's trace (`record(i, a)`, CONTRACT §3:
//                        content indices, ms since the engine first showed) and the round's sounds (`sound(s)`)
//   GameShellScope       hands the controller to the engine: `GameShellScope.maybeOf(context)` (no dependency). An
//                        engine outside a shell (a test, the nahw exercises) draws its own progress header
//   GameFeedback         the sound + vibration and the per-device mute: game_sounds.dart (Games v3 §11, D-1741),
//                        exported from here
//   GameTheme            `sand | sea | night | garden` as block tones of the live theme (never a fixed colour):
//                        sand = peach, sea = sage, night = the forest hero (cream ink), garden = emerald
//   GameFinishView       the end: stars filling in one by one, the score, the points earned, new badges, the save
//                        state, Play again / Back (keys `learn.result.*`, as the learn kit's result); Games v3: a
//                        second burst and the "Rank 4 today" line of a ranked round
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/core/game_fx.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart' show MechanicKind;
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

export 'package:flutter_education_app/features/games/shell/game_sounds.dart';

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

// GameFeedback: game_sounds.dart (exported above).

// ─────────────────────────────────────────────────────────────────────────────
//  Controller + scope
// ─────────────────────────────────────────────────────────────────────────────

/// One round's running state as the header draws it.
class GameShellController extends ChangeNotifier {
  GameShellController({this.total = 0, this.category = '', this.silent = false});

  /// Steps in the round (questions, pairs, items, words).
  int total;
  int done = 0, score = 0;

  /// Right answers in a row (a wrong one resets it). From [kGameComboFrom] the header shows the combo chip.
  int streak = 0;

  /// The game's category: `quran` / `tajweed` are [sacred].
  final String category;

  /// No sound (the editor's preview).
  final bool silent;

  /// A quran / tajweed game: nothing is drawn over the text, no tile shakes, no `wrong` sound (§1, §11).
  bool get sacred => category == 'quran' || category == 'tajweed';

  /// The ranked round's trace (CONTRACT §3): `{i, a, ms}` in the order things happened, content indices only.
  final List<Map<String, Object>> trace = [];
  final Stopwatch _clock = Stopwatch()..start();

  /// Milliseconds since the engine first showed.
  int get elapsedMs => _clock.elapsedMilliseconds;

  /// One trace entry; [hint] marks a word_puzzle check after a hint (`h: true`); [ms] pins the time (order's Check).
  void record(int i, Object a, {bool hint = false, int? ms}) =>
      trace.add({'i': i, 'a': a, 'ms': ms ?? elapsedMs, if (hint) 'h': true});

  /// A sound of the round that is not an answer (a pick, a drop, a flip).
  void sound(GameSound s) => GameFeedback.instance.play(s, sacred: sacred, silent: silent);

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
      streak = correct ? streak + 1 : 0;
      GameFeedback.instance.answer(correct, streak: streak, sacred: sacred, silent: silent);
      feedback.value++;
    }
    notifyListeners();
  }

  void reset({int? total}) {
    if (total != null) this.total = total;
    done = score = streak = 0;
    lastCorrect = null;
    trace.clear();
    _clock
      ..reset()
      ..start();
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
    GameFeedback.instance.attach();
  }

  @override
  void dispose() {
    GameFeedback.instance.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameShellScope(
      controller: widget.controller,
      // the web's sounds wait for a first touch (the autoplay rule)
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => GameFeedback.instance.userGesture(),
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
                streak: widget.controller.streak,
                showMute: widget.showMute,
              ),
            ),
          ),
          Positioned.fill(child: IgnorePointer(child: GameBurst(controller: widget.controller))),
        ]),
        const SizedBox(height: AppSpace.md),
        widget.child,
      ]),
      ),
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
    this.streak = 0,
    this.showMute = true,
  });

  final String? theme;
  final int done, total, score, feedbackSeq, streak;
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
                // lining figures: the editorial face's old-style zero reads as an "o" (N20)
                style: AppType.section(context).copyWith(color: b.ink, fontFeatures: const [FontFeature.liningFigures(), FontFeature.tabularFigures()]),
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
              GameComboChip(streak: streak),
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
            ? CustomPaint(
                painter: GameBurstPainter(
                  t: _c.value,
                  colors: colors,
                  seed: widget.controller.feedback.value,
                  // a combo throws the bigger burst (§1: 16 -> 24 particles)
                  count: widget.controller.streak >= kGameComboFrom ? GameBurstPainter.maxCount : GameBurstPainter.baseCount,
                ))
            : const SizedBox.expand(),
      ),
    );
  }
}

/// [t] 0..1: [count] particles (16, a combo 24, never more: §1) fly out from the centre, shrink and fade.
class GameBurstPainter extends CustomPainter {
  GameBurstPainter({required this.t, required this.colors, this.seed = 0, int count = baseCount}) : count = count.clamp(0, maxCount);

  static const int baseCount = 16, maxCount = 24;

  final double t;
  final List<Color> colors;
  final int seed, count;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1 || colors.isEmpty) return;
    final r = math.Random(seed);
    final centre = Offset(size.width / 2, size.height / 2);
    final reach = math.min(size.width, size.height * 3) * 0.45;
    final ease = Curves.easeOutCubic.transform(t);
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final a = (i / count) * math.pi * 2 + r.nextDouble() * 0.4;
      final d = reach * (0.5 + r.nextDouble() * 0.5) * ease;
      paint.color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(centre + Offset(math.cos(a) * d, math.sin(a) * d * 0.6), 2 + 3 * (1 - t), paint);
    }
  }

  @override
  bool shouldRepaint(GameBurstPainter old) => old.t != t || old.seed != seed || old.count != count;
}

/// One burst of [GameBurstPainter.maxCount] particles when it first shows (the finish view's second burst); nothing
/// under Reduce motion or when [play] is false.
class GameBurstOnce extends StatefulWidget {
  const GameBurstOnce({super.key, this.play = true});

  final bool play;

  @override
  State<GameBurstOnce> createState() => _GameBurstOnceState();
}

class _GameBurstOnceState extends State<GameBurstOnce> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final m = GameMotion.of(context);
    if (!widget.play || m.off) return;
    _c
      ..duration = m.celebrate
      ..forward(from: 0);
  }

  @override
  void dispose() {
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
            ? CustomPaint(painter: GameBurstPainter(t: _c.value, colors: colors, seed: 7, count: GameBurstPainter.maxCount))
            : const SizedBox.expand(),
      ),
    );
  }
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
    this.rankToday,
  });

  final int score, max;

  /// A ranked round's place in today's standings (`rank_today`, CONTRACT §2); null = not ranked.
  final int? rankToday;

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
          // the second burst sits behind the stars, inside the card (never over the text below)
          Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Positioned.fill(child: IgnorePointer(child: GameBurstOnce(play: s > 0))),
            GameStarsFill(stars: s),
          ]),
          const SizedBox(height: AppSpace.sm),
          Text(learnResultTitle(s), textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: b.ink)),
          const SizedBox(height: AppSpace.xxs),
          Text('$score / $max · ${learnPercent(score, max)}%',
              key: const ValueKey('learn.result.score'),
              textAlign: TextAlign.center,
              style: AppType.section(context).copyWith(color: b.muted, fontFeatures: const [FontFeature.liningFigures(), FontFeature.tabularFigures()])),
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
          if (rankToday != null) ...[
            const SizedBox(height: AppSpace.xs),
            Row(key: const ValueKey('games.finish.rank'), mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events_rounded, color: b.accentInk(appToneColor(context, AppTone.gold)), size: AppIconSize.md),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(t('المركز $rankToday اليوم', 'Rank $rankToday today'),
                    style: AppType.label(context).copyWith(color: b.ink, fontFeatures: const [FontFeature.liningFigures()])),
              ),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Games v4 (T26): the session shell
// ─────────────────────────────────────────────────────────────────────────────

/// True when a template with these [kinds] can give a hint (a program or a combine round has nothing to point at).
bool gameKindsGiveHints(Set<MechanicKind> kinds) => kinds.any((k) => const {
      MechanicKind.choose,
      MechanicKind.selectAll,
      MechanicKind.sequence,
      MechanicKind.classify,
      MechanicKind.pair,
      MechanicKind.fraction,
    }.contains(k));

/// The frame of a Games v4 round: lives, the timer, pause, quit and a hint button over the template's game, with the
/// effects of [GameFxLayer] (sound through [GameFeedback]). A calm session (sacred content) shows no timer, no red,
/// plays no buzzer and no explosion; a wrong answer is a quiet "try again" and costs nothing. The round ends through
/// `session.finish` (`timer`, `lives`, `quit`, `done`: the end entry is the session's).
class GameSessionShell extends StatefulWidget {
  const GameSessionShell({super.key, required this.session, required this.child, this.kinds = const {}, this.onHint, this.silent = false});

  final GameSession session;
  final Widget child;

  /// The template's mechanics ([GameTemplate.kinds]); decides whether the hint button is offered.
  final Set<MechanicKind> kinds;

  /// Called when the player asks for a hint; the template marks the next answer with `hint: true`.
  final VoidCallback? onHint;
  final bool silent;

  @override
  State<GameSessionShell> createState() => _GameSessionShellState();
}

class _GameSessionShellState extends State<GameSessionShell> with SingleTickerProviderStateMixin {
  final GameFxController _fx = GameFxController();
  late final GameFxSession _bind;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _retry = false;
  int _hintsUsed = 0;

  GameSession get s => widget.session;
  bool get _calm => s.calm || s.sacred;

  @override
  void initState() {
    super.initState();
    _bind = GameFxSession(s, _fx);
    _fx.addListener(_onFx);
    s.addListener(_onSession);
  }

  void _onFx() {
    final k = _fx.last?.kind;
    if (k == null) return;
    final sound = GameFeedback.instance;
    switch (k) {
      case GameFxKind.correct:
      case GameFxKind.combo:
        sound.answer(true, streak: _bind.streak, sacred: s.sacred, silent: widget.silent);
      case GameFxKind.wrong:
        if (_calm) {
          // sacred: no buzzer, no shake; the gentle retry line only
          setState(() => _retry = true);
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (mounted) setState(() => _retry = false);
          });
        } else {
          sound.answer(false, sacred: false, silent: widget.silent);
        }
      case GameFxKind.finish:
        if (!_calm) sound.play(GameSound.finish, sacred: s.sacred, silent: widget.silent);
      case GameFxKind.levelUp:
        sound.play(GameSound.champion, sacred: s.sacred, silent: widget.silent);
    }
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _fx.removeListener(_onFx);
    _bind.dispose();
    _fx.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String _clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  Future<void> _pause() async {
    s.pause();
    final quit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t('إيقاف مؤقت', 'Paused')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('إنهاء', 'Quit'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('متابعة', 'Resume'))),
        ],
      ),
    );
    s.resume();
    if (quit == true) s.finish('quit');
  }

  @override
  Widget build(BuildContext context) {
    final low = s.hasTimer && !_calm && s.remainingS <= 10 && !s.finished;
    // the low-time pulse is a decorative loop: syncMotionLoop parks it under Reduce motion
    if (low) {
      syncMotionLoop(context, _pulse, reverse: true, rest: 0);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
    final c = context.colors;
    final canHint = s.settings.hints && widget.onHint != null && gameKindsGiveHints(widget.kinds) && !s.finished;
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (s.hasLives)
          Semantics(
            label: t('الأرواح ${s.lives}', 'Lives ${s.lives}'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < s.settings.lives; i++)
                Icon(i < s.lives ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20, color: c.danger),
            ]),
          ),
        if (s.hasTimer && !_calm) ...[
          if (s.hasLives) AppSpace.gapSm,
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Opacity(opacity: low ? 1 - 0.35 * _pulse.value : 1, child: child),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer_outlined, size: 18, color: low ? c.danger : c.textMedium),
              AppSpace.gapXs,
              Text(_clock(s.remainingS), style: TextStyle(color: low ? c.danger : c.textMedium, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
            ]),
          ),
        ),
        if (canHint)
          IconButton(
            tooltip: t('تلميح', 'Hint'),
            onPressed: () {
              setState(() => _hintsUsed++);
              widget.onHint!();
            },
            icon: Badge(isLabelVisible: _hintsUsed > 0, label: Text('$_hintsUsed'), child: const Icon(Icons.lightbulb_outline_rounded)),
          ),
        IconButton(tooltip: t('إيقاف مؤقت', 'Pause'), onPressed: s.finished ? null : _pause, icon: const Icon(Icons.pause_rounded)),
      ]),
    );
    return Column(children: [
      bar,
      if (_retry)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text(t('حاول مرة أخرى', 'Try again'), style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
          ),
        ),
      Expanded(child: GameFxLayer(controller: _fx, calm: _calm, child: widget.child)),
    ]);
  }
}
