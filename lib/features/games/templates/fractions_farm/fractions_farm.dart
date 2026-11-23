// lib/features/games/templates/fractions_farm/fractions_farm.dart — Fractions Farm (Games v4 T55, CONTRACT §2): `fraction`
// items. A shape item (`{shape, n, d}`) is a pizza, a bar or a field cut into `d` parts: tap parts to top / fill / plant
// them, then Check; the answer is `[parts chosen, d]`. An operation item (`{op, a, b}`) shows the two fractions as bars
// and the learner builds the result with two steppers, `[n, d]`. The server grades by equivalent fraction (cross
// multiplication, never reduced), so 2/4 is as good as 1/2 for an `add` / `sub` result.
//
//   - the scene is the progress bar: a row of garden beds, a carrot grows in every bed answered right;
//   - a right answer harvests: the chosen parts are lifted off the board; a wrong one shakes the board once and rings
//     the parts that were needed (nothing else is lost), then the next item comes;
//   - sacred_allowed is FALSE, fixed in code: [FractionsFarmTemplate.refuses] and the page never reports an answer.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/question_stage.dart' show StageClosing;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/templates/fractions_farm/farm_art.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

class FractionsFarmTemplate extends GameTemplate {
  const FractionsFarmTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => 'fractions_farm';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.fraction};
  @override
  Set<ItemType> get accepts => const {ItemType.fraction};

  /// Fixed in code (CONTRACT §2): no route can change it.
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'مزرعة الكسور';
  @override
  String get nameEn => 'Fractions Farm';
  @override
  IconData get icon => Icons.local_pizza_rounded;

  /// True when [s] must not be played here: a sacred draw, or an item of the Quran or the Hadith.
  static bool refuses(GameSession s) =>
      s.sacred || s.items.any((i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith');

  @override
  Widget build(GameSession s) => refuses(s) ? const FractionsFarmRefused() : FractionsFarmGame(session: s, silent: silent);
}

const FractionsFarmTemplate kFractionsFarm = FractionsFarmTemplate();

class FractionsFarmRefused extends StatelessWidget {
  const FractionsFarmRefused({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: 44, color: c.textMedium),
          AppSpace.gapSm,
          Text(t('هذه اللعبة لا تعرض النصوص المقدسة', 'This game never shows sacred text'),
              textAlign: TextAlign.center, style: appText(16, w: FontWeight.w600, c: c.textMedium)),
        ]),
      ),
    );
  }
}

int _gcd(int a, int b) => b == 0 ? a.abs() : _gcd(b, a % b);
int _int(Object? v, int d) => v is num ? v.toInt() : d;
List<int> _frac(Object? v) => v is List && v.length >= 2 ? [_int(v[0], 0).clamp(0, 99), _int(v[1], 1).clamp(1, 12)] : [0, 1];

/// One `fraction` item in plain values.
class FractionTask {
  FractionTask._(this.shape, this.n, this.d, this.op, this.a, this.b);

  /// `pizza` / `bar` / `field`; `op` items have no shape.
  final String shape;
  final int n, d;

  /// `add` / `sub`, null for a shape item.
  final String? op;
  final List<int> a, b;

  factory FractionTask.of(GameItem it) {
    final b = it.body;
    final op = b['op'];
    if (op == 'add' || op == 'sub') return FractionTask._('', 0, 1, op as String, _frac(b['a']), _frac(b['b']));
    final shape = b['shape'] == 'bar' || b['shape'] == 'field' ? b['shape'] as String : 'pizza';
    final d = _int(b['d'], 4).clamp(2, 12);
    return FractionTask._(shape, _int(b['n'], 1).clamp(1, d), d, null, const [0, 1], const [0, 1]);
  }

  bool get isOp => op != null;

  /// The answer as a fraction, reduced for showing it (the grader never reduces).
  List<int> get answer {
    if (!isOp) return [n, d];
    var rn = op == 'add' ? a[0] * b[1] + b[0] * a[1] : a[0] * b[1] - b[0] * a[1];
    final rd = a[1] * b[1];
    if (rn < 0) rn = 0;
    final g = _gcd(rn, rd);
    return g <= 1 ? [rn, rd] : [rn ~/ g, rd ~/ g];
  }

  int get commonDenominator => a[1] * b[1] ~/ _gcd(a[1], b[1]);

  String defaultPrompt() => switch (op) {
        'add' => t('اجمع الكسرين', 'Add the two fractions'),
        'sub' => t('اطرح الكسر الثاني من الأول', 'Subtract the second fraction from the first'),
        _ => switch (shape) {
            'bar' => t('املأ $n/$d من القطعة', 'Fill $n/$d of the bar'),
            'field' => t('ازرع $n/$d من الحقل', 'Plant $n/$d of the field'),
            _ => t('ضع الإضافات على $n/$d من البيتزا', 'Top $n/$d of the pizza'),
          },
      };
}

class FractionsFarmGame extends StatefulWidget {
  const FractionsFarmGame({super.key, required this.session, this.silent = false, this.advanceMs = 1500});
  final GameSession session;
  final bool silent;

  /// How long an answered item stays before the next one comes (a wrong one stays 700 ms longer).
  final int advanceMs;

  @override
  State<FractionsFarmGame> createState() => _FractionsFarmGameState();
}

class _FractionsFarmGameState extends State<FractionsFarmGame> {
  late final List<int> _results = List.filled(widget.session.items.length, 0);
  final Set<int> _picked = {};
  Set<int> _reveal = {};
  Timer? _timer;
  int _i = 0, _n = 0, _d = 1, _hint = -1;
  int _popIndex = -1, _popSeq = 0;
  bool _locked = false, _done = false, _hinted = false;
  FarmPhase _phase = FarmPhase.play;
  GameMood _mood = GameMood.idle;
  String _note = '';

  GameSession get s => widget.session;
  GameItem get item => s.items[_i];
  FractionTask get task => FractionTask.of(item);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _later(int ms, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: appMotionOff(context) ? ms ~/ 4 : ms), () {
      if (mounted) f();
    });
  }

  void _tick() => stageTick(silent: widget.silent);

  void _toggle(int k) {
    if (_locked || _done || s.finished) return;
    HapticFeedback.selectionClick();
    _tick();
    setState(() {
      if (!_picked.remove(k)) _picked.add(k);
      _popIndex = k;
      _popSeq++;
      if (_hint == k) _hint = -1;
    });
  }

  void _step(bool numerator, int by) {
    if (_locked || _done || s.finished) return;
    HapticFeedback.selectionClick();
    _tick();
    setState(() {
      if (numerator) {
        _n = (_n + by).clamp(0, 99);
      } else {
        _d = (_d + by).clamp(1, 99);
      }
    });
  }

  void _hintNow() {
    if (_locked || _done || _hinted) return;
    final tk = task;
    setState(() {
      _hinted = true;
      if (tk.isOp) {
        _d = tk.commonDenominator.clamp(1, 99);
      } else {
        for (var k = 0; k < tk.d; k++) {
          if (!_picked.contains(k)) {
            _hint = k;
            break;
          }
        }
      }
    });
  }

  bool get _canCheck => !_locked && !_done && (task.isOp || _picked.isNotEmpty);

  void _check() {
    if (!_canCheck) return;
    final tk = task;
    final a = tk.isOp ? [_n, _d] : [_picked.length, tk.d];
    final r = s.answer(_i, a, hint: _hinted);
    if (r == null) return;
    final right = r.points > 0;
    final want = tk.answer;
    final reveal = <int>{};
    if (!right && !tk.isOp) reveal.addAll([for (var k = 0; k < tk.d && k < tk.n; k++) k]);
    HapticFeedback.mediumImpact();
    setState(() {
      _locked = true;
      _results[_i] = right ? 1 : 2;
      _phase = right ? FarmPhase.right : FarmPhase.wrong;
      _reveal = reveal;
      _hint = -1;
      _mood = right ? GameMood.happy : GameMood.sad;
      _note = right
          ? t('حصاد رائع!', 'A great harvest!')
          : t('ليس تمامًا، كان الجواب ${want[0]}/${want[1]}', 'Not quite, it was ${want[0]}/${want[1]}');
    });
    _later(right ? widget.advanceMs : widget.advanceMs + 700, _advance);
  }

  void _advance() {
    if (s.finished) {
      setState(() => _done = true);
      return;
    }
    if (_i + 1 >= s.items.length) {
      setState(() => _done = true);
      s.finish('done');
      return;
    }
    setState(() {
      _i++;
      _picked.clear();
      _reveal = {};
      _locked = false;
      _hinted = false;
      _hint = -1;
      _popIndex = -1;
      _phase = FarmPhase.play;
      _mood = GameMood.idle;
      _note = '';
      _n = 0;
      _d = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StageFrame(
      session: s,
      kinds: kFractionsFarm.kinds,
      silent: widget.silent,
      onHint: _hintNow,
      child: Builder(builder: (context) {
        final theme = AgeThemeScope.of(context);
        final sf = StageSurface(theme, context);
        if (_done || s.finished && _locked == false && _results.every((e) => e != 0)) {
          return StageClosing(session: s, theme: theme, sf: sf);
        }
        if (_done) return StageClosing(session: s, theme: theme, sf: sf);
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760;
          final content = wide ? _wide(context, sf, theme, box) : _phone(context, sf, theme, box);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? AppWidth.wide.max : AppWidth.reading.max), child: content),
          );
        });
      }),
    );
  }

  // ───────────────────────────────────── layouts ─────────────────────────────────────

  Widget _phone(BuildContext context, StageSurface sf, AgeTheme theme, BoxConstraints box) {
    final tall = box.maxHeight >= 640;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _trail(sf),
        AppSpace.gapSm,
        _promptCard(context, sf, theme, withFarmer: theme.age == GameAge.kids && tall),
        AppSpace.gapSm,
        Expanded(child: _stage(context, sf)),
        AppSpace.gapSm,
        _note.isEmpty ? _checkButton(sf) : _noteBar(sf),
      ]),
    );
  }

  Widget _wide(BuildContext context, StageSurface sf, AgeTheme theme, BoxConstraints box) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.lg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _stage(context, sf)),
        AppSpace.gapLg,
        SizedBox(
          width: 340,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _trail(sf),
            AppSpace.gapMd,
            _promptCard(context, sf, theme, withFarmer: false, big: true),
            AppSpace.gapMd,
            Expanded(
              child: Center(
                child: SizedBox.square(dimension: 150, child: GameCharacter(theme: theme, mood: _mood, size: 150)),
              ),
            ),
            _note.isEmpty ? _checkButton(sf) : _noteBar(sf),
          ]),
        ),
      ]),
    );
  }

  Widget _trail(StageSurface sf) {
    final total = _results.length;
    final done = _results.where((e) => e == 1).length;
    final colors = FarmColors(sf);
    return Semantics(
      label: t('$done من $total', '$done of $total'),
      excludeSemantics: true,
      child: SizedBox(
        height: 36,
        child: Row(children: [
          Expanded(child: CustomPaint(painter: FarmTrailPainter(results: _results, current: _i, colors: colors), size: const Size(double.infinity, 36))),
          AppSpace.gapSm,
          Text('${math.min(_i + 1, total)} / $total', textDirection: TextDirection.ltr, style: appText(15, w: FontWeight.w700, c: sf.onSky)),
        ]),
      ),
    );
  }

  Widget _promptCard(BuildContext context, StageSurface sf, AgeTheme theme, {required bool withFarmer, bool big = false}) {
    final tk = task;
    final text = item.prompt.of(AppConfig.lang).isNotEmpty ? item.prompt.of(AppConfig.lang) : tk.defaultPrompt();
    // an operation shows its two fractions on the board, so the card only says what to do
    final Widget? label = tk.isOp ? null : FractionLabel(n: tk.n, d: tk.d, color: sf.ink, size: big ? 44 : 34);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(color: sf.paper, borderRadius: BorderRadius.circular(sf.radius), boxShadow: sf.lift(blur: 18, dy: 6)),
      child: big
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              ?label,
              if (label != null) AppSpace.gapSm,
              _promptText(text, sf, 18),
              if ((item.media.image ?? '').isNotEmpty) ...[AppSpace.gapSm, _image(sf)],
            ])
          : Row(children: [
              if (withFarmer) ...[
                SizedBox.square(dimension: 64, child: GameCharacter(theme: theme, mood: _mood, size: 64)),
                AppSpace.gapSm,
              ],
              ?label,
              if (label != null) AppSpace.gapMd,
              Expanded(child: _promptText(text, sf, 17)),
              if ((item.media.image ?? '').isNotEmpty) ...[AppSpace.gapSm, _image(sf, h: 52, w: 52)],
            ]),
    );
  }

  Widget _image(StageSurface sf, {double h = 96, double w = 160}) => ClipRRect(
        borderRadius: BorderRadius.circular(sf.radius - AppSpace.xxs),
        child: AppNetworkImage(url: item.media.image!, width: w, height: h, fit: BoxFit.cover),
      );

  Widget _promptText(String text, StageSurface sf, double size) => Text(
        text,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        textDirection: textDirectionOf(text, Directionality.of(context)),
        style: appText(size, w: FontWeight.w700, c: sf.ink, h: 1.35),
      );

  Widget _noteBar(StageSurface sf) {
    final good = _phase == FarmPhase.right;
    return Container(
      key: const ValueKey('ff-note'),
      height: AppTouch.primary,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      decoration: BoxDecoration(color: sf.tint(good ? sf.right : sf.gold, 0.22), borderRadius: BorderRadius.circular(sf.radius)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(_note, style: appText(17, w: FontWeight.w800, c: sf.ink), textDirection: textDirectionOf(_note, Directionality.of(context))),
      ),
    );
  }

  Widget _checkButton(StageSurface sf) {
    final can = _canCheck;
    return SizedBox(
      height: AppTouch.primary,
      child: FilledButton(
        key: const ValueKey('ff-check'),
        style: FilledButton.styleFrom(
          backgroundColor: sf.accent,
          foregroundColor: sf.paper,
          disabledBackgroundColor: sf.tint(sf.ink, 0.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sf.radius)),
        ),
        onPressed: can ? _check : null,
        child: Text(task.isOp ? t('تحقّق', 'Check') : t('احصد', 'Harvest'), style: appText(17, w: FontWeight.w700, c: can ? sf.paper : sf.ink.withValues(alpha: 0.5))),
      ),
    );
  }

  // ────────────────────────────────────── the stage ──────────────────────────────────────

  Widget _stage(BuildContext context, StageSurface sf) {
    final tk = task;
    final card = tk.isOp ? _opPanel(context, sf, tk) : _board(context, sf, tk);
    return KeyedSubtree(key: ValueKey('ff-item-$_i'), child: card);
  }

  Widget _board(BuildContext context, StageSurface sf, FractionTask tk) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(sf.radius + AppSpace.xxs),
        border: Border.all(color: sf.ink.withValues(alpha: 0.18), width: 1.5),
        boxShadow: sf.lift(blur: 22, dy: 8),
      ),
      clipBehavior: Clip.antiAlias,
      child: FarmBoard(
        key: const ValueKey('ff-board'),
        scene: FarmScene(shape: tk.shape, d: tk.d, picked: Set.of(_picked), reveal: _reveal, hint: _hint, phase: _phase),
        surface: sf,
        popIndex: _popIndex,
        popSeq: _popSeq,
        onSlice: _toggle,
      ),
    );
  }

  Widget _opPanel(BuildContext context, StageSurface sf, FractionTask tk) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final colors = FarmColors(sf);
    Widget bars(List<int> f, {double w = 120}) => SizedBox(
          width: w,
          height: 24,
          child: CustomPaint(painter: FractionBarsPainter(n: f[0], d: f[1], fill: colors.honey, empty: colors.dough, edge: sf.ink.withValues(alpha: 0.5), rtl: rtl)),
        );
    Widget term(List<int> f) => Column(mainAxisSize: MainAxisSize.min, children: [
          FractionLabel(n: f[0], d: f[1], color: sf.ink, size: 40),
          AppSpace.gapXs,
          bars(f),
        ]);
    final good = _phase == FarmPhase.right;
    final reveal = _phase == FarmPhase.wrong;
    final ans = tk.answer;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(sf.radius + AppSpace.xxs),
        border: Border.all(color: sf.ink.withValues(alpha: 0.18), width: 1.5),
        boxShadow: sf.lift(blur: 22, dy: 8),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: FarmWoodPainter(colors),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
              term(tk.a),
              Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), child: Text(tk.op == 'add' ? '+' : '−', style: appText(40, w: FontWeight.w800, c: sf.paper))),
              term(tk.b),
            ]),
            AppSpace.gapMd,
            Text('=', style: appText(34, w: FontWeight.w800, c: sf.paper)),
            AppSpace.gapSm,
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: sf.paper,
                borderRadius: BorderRadius.circular(sf.radius),
                border: Border.all(color: reveal ? sf.gold : (good ? sf.right : Colors.transparent), width: 3),
                boxShadow: sf.lift(blur: 14, dy: 5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _stepper(sf, numerator: true),
                Container(height: 4, width: 150, margin: const EdgeInsets.symmetric(vertical: AppSpace.xs), decoration: BoxDecoration(color: sf.ink, borderRadius: BorderRadius.circular(AppBorder.focus))),
                _stepper(sf, numerator: false),
              ]),
            ),
            AppSpace.gapSm,
            bars([_n, _d], w: 200),
            if (reveal) ...[
              AppSpace.gapSm,
              Text('${ans[0]}/${ans[1]}', textDirection: TextDirection.ltr, style: appText(22, w: FontWeight.w800, c: sf.gold)),
            ],
          ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepper(StageSurface sf, {required bool numerator}) {
    final v = numerator ? _n : _d;
    final k = numerator ? 'n' : 'd';
    Widget btn(IconData icon, int by, String id) => StageTile(
          key: ValueKey('ff-$k-$id'),
          surface: sf,
          expand: false,
          minHeight: AppTouch.primary,
          semanticsLabel: '${numerator ? t('البسط', 'Numerator') : t('المقام', 'Denominator')} ${by > 0 ? '+' : '-'}',
          onTap: () => _step(numerator, by),
          child: Icon(icon, size: 26, color: sf.ink),
        );
    return Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
      btn(Icons.remove_rounded, -1, 'down'),
      SizedBox(
        width: 72,
        child: Text('$v', key: ValueKey('ff-$k-value'), textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: appText(40, w: FontWeight.w800, c: sf.ink)),
      ),
      btn(Icons.add_rounded, 1, 'up'),
    ]);
  }
}

/// A stacked fraction: numerator over a bar over the denominator.
class FractionLabel extends StatelessWidget {
  const FractionLabel({super.key, required this.n, required this.d, required this.color, this.size = 34});
  final int n, d;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = appText(size, w: FontWeight.w800, c: color, h: 1.05);
    final w = math.max('$n'.length, '$d'.length) * size * 0.62 + 8;
    return Semantics(
      label: '$n/$d',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$n', textDirection: TextDirection.ltr, style: style),
        Container(width: w, height: math.max(3, size * 0.09), margin: const EdgeInsets.symmetric(vertical: AppBorder.focus), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppBorder.focus))),
        Text('$d', textDirection: TextDirection.ltr, style: style),
      ]),
    );
  }
}

/// The painted shape with its animations (cut, pop, harvest, shake) and the taps: plain values only.
class FarmBoard extends StatefulWidget {
  const FarmBoard({super.key, required this.scene, required this.surface, required this.onSlice, this.popIndex = -1, this.popSeq = 0});
  final FarmScene scene;
  final StageSurface surface;
  final ValueChanged<int> onSlice;

  /// The part that was just toggled and a counter that changes with every toggle (restarts the pop).
  final int popIndex, popSeq;

  @override
  State<FarmBoard> createState() => _FarmBoardState();
}

class _FarmBoardState extends State<FarmBoard> with TickerProviderStateMixin {
  late final AnimationController _cut = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);
  late final AnimationController _harvest = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800));
  late final Listenable _all = Listenable.merge([_cut, _pop, _harvest, _shake, _loop]);
  FarmGeometry? _geo;
  late FarmColors _colors = FarmColors(widget.surface);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colors = FarmColors(widget.surface);
    final off = appMotionOff(context);
    if (!_started) {
      _started = true;
      if (off) {
        _cut.value = 1;
      } else {
        _cut.forward(from: 0);
      }
    }
    _syncLoop();
  }

  void _syncLoop() {
    final needs = widget.scene.shape == 'field' || widget.scene.hint >= 0 || widget.scene.phase == FarmPhase.wrong;
    if (needs) {
      syncMotionLoop(context, _loop);
    } else {
      _loop.stop();
    }
  }

  @override
  void didUpdateWidget(FarmBoard old) {
    super.didUpdateWidget(old);
    final off = appMotionOff(context);
    if (old.popSeq != widget.popSeq) {
      if (off) {
        _pop.value = 1;
      } else {
        _pop.forward(from: 0);
      }
    }
    if (old.scene.phase != widget.scene.phase) {
      if (widget.scene.phase == FarmPhase.right) {
        if (off) {
          _harvest.value = 1;
        } else {
          _harvest.forward(from: 0);
        }
      } else if (widget.scene.phase == FarmPhase.wrong && !off) {
        _shake.forward(from: 0);
      }
    }
    _syncLoop();
  }

  @override
  void dispose() {
    _cut.dispose();
    _pop.dispose();
    _harvest.dispose();
    _shake.dispose();
    _loop.dispose();
    super.dispose();
  }

  FarmGeometry _geometry(Size size, bool rtl) {
    final g = _geo;
    if (g != null && g.size == size && g.shape == widget.scene.shape && g.d == widget.scene.d && g.rtl == rtl) return g;
    return _geo = FarmGeometry(widget.scene.shape, widget.scene.d, size, rtl: rtl);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sc = widget.scene;
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth.isFinite ? box.maxWidth : 320, box.maxHeight.isFinite ? box.maxHeight : 320);
      final geo = _geometry(size, rtl);
      final painter = FarmBoardPainter(
        scene: sc,
        geo: geo,
        colors: _colors,
        motion: () => FarmMotion(cut: _cut.value, pop: _pop.value, popIndex: widget.popIndex, harvest: _harvest.value, loop: _loop.value),
        onSlice: widget.onSlice,
        labelOf: (k, on) => farmPartLabel(sc.shape, k, sc.d, on),
        repaint: _all,
      );
      return AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = _shake.isAnimating ? math.sin(t * math.pi * 7) * (1 - t) * 9 : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final k = geo.hit(d.localPosition);
            if (k != null) widget.onSlice(k);
          },
          child: RepaintBoundary(child: CustomPaint(size: size, painter: painter)),
        ),
      );
    });
  }
}
