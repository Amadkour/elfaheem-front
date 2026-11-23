// lib/features/games/core/game_template.dart — the template interface of Games v4 (Games v4 T12, PLAN §1, CONTRACT §2).
//
//   MechanicKind       choose | select_all | sequence | classify | pair | fraction | program | combine
//   GameTemplate       a template imports only core/ and bases/: it draws the game from a GameSession and reports
//                      `s.answer(i, a)`
//   kGameTemplates     the app's registry (key = `games.engine`); registerGameTemplate also adds the template to
//                      kGameEngines through an adapter, so GamePlayPage, the leaderboard and the "needs a newer
//                      version" fallback keep working. The adapter reads the draw from `config['draw']`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_engine.dart';

import 'game_items.dart';
import 'game_session.dart';

enum MechanicKind { choose, selectAll, sequence, classify, pair, fraction, program, combine }

abstract class GameTemplate {
  const GameTemplate();

  /// `games.engine` of a level.
  String get key;
  /// Every mechanic the template plays (CONTRACT §2 "Kinds": `car_race` is choose + sequence).
  Set<MechanicKind> get kinds;
  Set<ItemType> get accepts;

  /// Fixed in code (CONTRACT §2); no route can change it.
  bool get sacredAllowed;

  String get nameAr => key;
  String get nameEn => key;
  IconData get icon => Icons.extension_rounded;

  Widget build(GameSession s);

  /// The sacred lock, one rule for every template (G3): a template with [sacredAllowed] false never shows a sacred
  /// draw or an item of the Quran or the Hadith, whatever its own page checks.
  bool locks(GameSession s) =>
      !sacredAllowed && (s.sacred || s.items.any((i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith'));

  /// What the play page and the host draw: [build], or the lock.
  Widget play(GameSession s) => locks(s) ? const SacredLocked() : build(s);
}

/// What a sacred draw gets on a template that never shows sacred text.
class SacredLocked extends StatelessWidget {
  const SacredLocked({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: AppIconSize.xl, color: muted),
          const SizedBox(height: AppSpace.sm),
          Text(t('هذه اللعبة لا تعرض النصوص المقدسة', 'This game never shows sacred text'),
              textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: muted)),
        ]),
      ),
    );
  }
}

/// The templates this app plays, by key.
final Map<String, GameTemplate> kGameTemplates = {};

/// Registers [template] in [kGameTemplates] and, through an adapter, in [kGameEngines].
void registerGameTemplate(GameTemplate template) {
  kGameTemplates[template.key] = template;
  kGameEngines[template.key] = GameEngineSpec(
    key: template.key,
    nameAr: template.nameAr,
    nameEn: template.nameEn,
    icon: template.icon,
    steps: (c) => c['draw'] is Map ? ((c['draw'] as Map)['items'] as List?)?.length ?? 0 : 0,
    build: (c, done, r) => GameTemplateHost(template: template, draw: c['draw'], onFinished: done),
  );
}

/// Plays [template] over the draw: makes the session, starts it and reports (score, max) once when it ends. A draw
/// the app cannot read shows "needs a newer version".
class GameTemplateHost extends StatefulWidget {
  const GameTemplateHost({super.key, required this.template, required this.draw, required this.onFinished});
  final GameTemplate template;
  final Object? draw;
  final GameFinished onFinished;

  @override
  State<GameTemplateHost> createState() => _GameTemplateHostState();
}

class _GameTemplateHostState extends State<GameTemplateHost> {
  GameSession? _session;

  @override
  void initState() {
    super.initState();
    final d = widget.draw;
    if (d is Map) {
      _session = GameSession.fromDraw(d, onFinished: (s) => widget.onFinished(s.score, s.maxScore))?..start();
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) return Center(child: Text(t('تحتاج هذه اللعبة إلى إصدار أحدث من التطبيق', 'This game needs a newer version of the app')));
    return widget.template.play(s);
  }
}
