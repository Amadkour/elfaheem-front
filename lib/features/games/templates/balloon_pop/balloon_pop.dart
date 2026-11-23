// lib/features/games/templates/balloon_pop/balloon_pop.dart — Balloon Pop (Games v4 T38, CONTRACT §2 `balloon_pop`).
//
//   select_all   the balloons rise with the options on them; pop every right one. A pop is final. Check (or popping every
//                right one) sends the picked option indices ONCE as the trace's `a` (CONTRACT §5); the score is hits minus
//                wrong picks. The rest of the balloons float away and the next question rises.
//
// sacred_allowed is FALSE, fixed in code: [BalloonPopTemplate.refuses] is true for a draw that holds a sacred item, and then
// the page shows a notice and NEVER reports an answer (the server filters such items out anyway, CONTRACT §2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/floating_tokens.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';

class BalloonPopTemplate extends GameTemplate {
  const BalloonPopTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => 'balloon_pop';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.selectAll};
  @override
  Set<ItemType> get accepts => const {ItemType.selectAll};

  /// Fixed in code (CONTRACT §2): no route can change it.
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'فرقعة البالونات';
  @override
  String get nameEn => 'Balloon Pop';
  @override
  IconData get icon => Icons.bubble_chart_rounded;

  /// True when [s] must not be played here: a sacred draw, or an item of the Quran or the Hadith.
  static bool refuses(GameSession s) =>
      s.sacred || s.items.any((i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith');

  @override
  Widget build(GameSession s) => refuses(s) ? const BalloonPopRefused() : BalloonPopView(session: s, silent: silent);
}

void registerBalloonPopTemplate() => registerGameTemplate(const BalloonPopTemplate());

/// What a sacred draw gets.
class BalloonPopRefused extends StatelessWidget {
  const BalloonPopRefused({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: 44, color: c.textMedium),
          AppSpace.gapSm,
          Text(
            t('هذه اللعبة لا تعرض النصوص المقدسة', 'This game never shows sacred text'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMedium, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

/// One question as balloons: the label on every balloon (in the draw's `show` order) and which of them are right.
class BalloonRound {
  BalloonRound._(this.labels, this.option, this.answers);

  /// Balloon `k` shows [labels]`[k]` and reports the option index [option]`[k]`.
  final List<String> labels;
  final List<int> option;
  final Set<int> answers;

  factory BalloonRound.of(GameItem item) {
    final opts = [for (final o in (item.body['options'] as List? ?? const [])) '${(o as Map)['text']}'];
    final order = item.show.where((i) => i >= 0 && i < opts.length).toList();
    return BalloonRound._([for (final i in order) opts[i]], order, item.intList('answers').toSet());
  }

  bool isRight(int balloon) => answers.contains(option[balloon]);
}

class BalloonPopView extends StatefulWidget {
  const BalloonPopView({super.key, required this.session, this.silent = false});
  final GameSession session;
  final bool silent;

  @override
  State<BalloonPopView> createState() => BalloonPopViewState();
}

class BalloonPopViewState extends State<BalloonPopView> {
  FloatingTokensGame? _game;
  AgeTheme? _theme;
  BalloonRound? _round;
  int _item = -1;
  final List<int> _picked = [];
  int _right = 0;
  bool _hint = false, _sent = false, _ready = false;

  GameSession get s => widget.session;
  FloatingTokensGame get game => _game!;
  BalloonRound? get round => _round;
  int get itemIndex => _item;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_game != null) return;
    final scope = AgeThemeScope.of(context);
    var age = scope.age;
    if (s.settings.theme != 'auto') age = GameAge.values.firstWhere((a) => a.name == s.settings.theme, orElse: () => scope.age);
    _theme = scope.age == age ? scope : AgeTheme.build(age, calm: scope.calm, night: scope.night, primary: context.colors.primary);
    _game = FloatingTokensGame(theme: _theme!, speed: s.settings.speed)
      ..onTap = _onTap
      ..onGone = _onGone;
    s.addListener(_onSession);
    _next();
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (s.finished) _game?.pauseEngine();
  }

  void _next() {
    for (var i = _item + 1; i < s.items.length; i++) {
      if (s.items[i].type != ItemType.selectAll) continue;
      _item = i;
      _round = BalloonRound.of(s.items[i]);
      _picked.clear();
      _right = 0;
      _hint = false;
      _sent = false;
      _game!.setTokens(_round!.labels);
      _refresh();
      return;
    }
    _item = s.items.length;
    _round = null;
    if (!s.finished) s.finish('done');
    _refresh();
  }

  void _refresh() {
    if (mounted && _ready) setState(() {});
  }

  void _onTap(int balloon) {
    final r = _round;
    if (r == null || _sent || s.finished || s.paused) return;
    final good = r.isRight(balloon);
    _picked.add(r.option[balloon]);
    _game!.pop(balloon, good: good);
    GameFeedback.instance.answer(good, sacred: false, silent: widget.silent);
    if (good) _right++;
    if (_right >= r.answers.length) check();
  }

  /// Sends the pick (once) and lets the other balloons float away.
  void check() {
    final r = _round;
    if (r == null || _sent || s.finished) return;
    _sent = true;
    final picks = [..._picked]..sort();
    final res = s.answer(_item, picks, hint: _hint);
    if (res == null && !s.finished) {
      // paused: nothing was recorded, so the question stays
      _sent = false;
      return;
    }
    _game!.release();
    _refresh();
  }

  void _onGone() {
    if (s.finished) return;
    if (_sent) _next();
  }

  void _hintPressed() {
    final r = _round;
    if (r == null || _sent) return;
    for (var k = 0; k < r.labels.length; k++) {
      if (r.isRight(k) && _game!.isAlive(k) && !_picked.contains(r.option[k])) {
        _hint = true;
        _game!.hintToken(k);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _ready = true;
    final theme = _theme!;
    final r = _round;
    final p = theme.palette;
    final prompt = r == null ? '' : s.items[_item].prompt.of(AppConfig.lang);
    return GameSessionShell(
      session: s,
      kinds: const {MechanicKind.selectAll},
      onHint: _hintPressed,
      silent: widget.silent,
      onScene: theme.onSky,
      overlay: true,
      child: Stack(children: [
        Positioned.fill(
          child: FloatingTokensView(game: _game!, semanticLabel: t('فرقعة البالونات: اختر كل الإجابات الصحيحة', 'Balloon pop: pop every right answer')),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs + GameSessionShell.barHeight + MediaQuery.paddingOf(context).top, AppSpace.sm, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.paper.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: Color.lerp(p.paper, p.accent, 0.45)!, width: 2),
                  boxShadow: [BoxShadow(color: p.ink.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(prompt,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: appText(18, w: FontWeight.w700, c: p.ink, h: 1.5)),
                    if (r != null && s.settings.hints)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xxs),
                        child: Text(
                          t('اختر ${r.answers.length}', 'Pick ${r.answers.length}'),
                          style: appText(13, w: FontWeight.w600, c: p.ink.withValues(alpha: 0.65)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: FilledButton.icon(
              key: const ValueKey('balloon.check'),
              onPressed: (r == null || _sent || s.finished) ? null : check,
              icon: const Icon(Icons.check_rounded),
              label: Text(t('تحقق', 'Check'), style: appText(15, w: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }
}
