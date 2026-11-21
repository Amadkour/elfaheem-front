// lib/features/games/games_progress.dart — stars, badges and games played (D-1346), for the student and for a parent.
//
//   GamesProgressPage      the student's page: GET /api/v1/me/games/progress (reloads after a saved play)
//   ParentChildGamesPage   a parent's view of one linked child: GET /api/v1/parent/children/{id}/games
//   GamesProgressView      the body with plain values (test/ui/games_layout_test.dart): totals, every badge (earned in
//                          gold, the rest locked with what earns them), and each game's best score and stars
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// What earns [b] ("Play 10 rounds"), from its rule `{type: plays | stars | perfect | games, count}`.
String gameBadgeRuleText(GameBadge b) {
  final n = (b.rule['count'] is num) ? (b.rule['count'] as num).toInt() : 1;
  return switch ('${b.rule['type']}') {
    'plays' => countText(n,
        ar1: 'العب جولة واحدة', ar2: 'العب جولتين', arFew: 'العب $n جولات', arMany: 'العب $n جولة', en1: 'Play 1 round', en: 'Play $n rounds'),
    'stars' => countText(n,
        ar1: 'اجمع نجمة واحدة', ar2: 'اجمع نجمتين', arFew: 'اجمع $n نجوم', arMany: 'اجمع $n نجمة', en1: 'Collect 1 star', en: 'Collect $n stars'),
    'perfect' => countText(n,
        ar1: 'جولة كاملة العلامة', ar2: 'جولتان كاملتا العلامة', arFew: '$n جولات كاملة العلامة', arMany: '$n جولة كاملة العلامة',
        en1: '1 perfect round', en: '$n perfect rounds'),
    'games' => countText(n,
        ar1: 'العب لعبة واحدة', ar2: 'العب لعبتين مختلفتين', arFew: 'العب $n ألعاب مختلفة', arMany: 'العب $n لعبة مختلفة',
        en1: 'Play 1 game', en: 'Play $n different games'),
    _ => '',
  };
}

class GamesProgressPage extends StatefulWidget {
  const GamesProgressPage({super.key, this.api});

  final GamesApi? api;

  @override
  State<GamesProgressPage> createState() => _GamesProgressPageState();
}

class _GamesProgressPageState extends State<GamesProgressPage> {
  late final GamesApi _api = widget.api ?? GamesApi();
  GamesReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    GamesBus.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    GamesBus.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.myProgress();
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = gamesErrorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        width: AppWidth.content,
        appBar: ScreenAppBar(title: t('تقدّمي في الألعاب', 'My games progress')),
        child: SafeArea(
          child: GamesProgressView(report: _report, loading: _loading, error: _error, onRetry: _load, onRefresh: _load),
        ),
      );
}

/// A parent's view of one linked child's games.
class ParentChildGamesPage extends StatefulWidget {
  const ParentChildGamesPage({super.key, required this.studentId, required this.studentName, this.api});

  final int studentId;
  final String studentName;
  final GamesApi? api;

  @override
  State<ParentChildGamesPage> createState() => _ParentChildGamesPageState();
}

class _ParentChildGamesPageState extends State<ParentChildGamesPage> {
  late final GamesApi _api = widget.api ?? GamesApi();
  GamesReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.childProgress(widget.studentId);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = gamesErrorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        width: AppWidth.content,
        appBar: ScreenAppBar(title: t('ألعاب ${widget.studentName}', '${widget.studentName}\'s games')),
        child: SafeArea(
          child: GamesProgressView(
            report: _report,
            loading: _loading,
            error: _error,
            onRetry: _load,
            onRefresh: _load,
            forParent: true,
          ),
        ),
      );
}

/// The progress body with plain values.
class GamesProgressView extends StatelessWidget {
  const GamesProgressView({
    super.key,
    this.report,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onRefresh,
    this.forParent = false,
  });

  final GamesReport? report;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  /// Words for a parent ("hasn't played yet") instead of the student's own ("Play your first game").
  final bool forParent;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final Widget body;
    if (loading && r == null) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null && r == null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (r == null || r.empty) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppEmpty(
          key: const ValueKey('games.progress.empty'),
          icon: Icons.emoji_events_rounded,
          title: forParent ? t('لم يلعب أي لعبة بعد', 'No games played yet') : t('لم تلعب أي لعبة بعد', 'You have not played a game yet'),
          message: forParent
              ? t('تظهر هنا النجوم والشارات بعد أول لعبة.', 'Stars and badges show here after the first game.')
              : t('العب لعبة من تبويب الألعاب لتجمع النجوم والشارات.', 'Play a game from the Games tab to collect stars and badges.'),
        ),
        if (r != null && r.badges.isNotEmpty) _Badges(badges: r.badges),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppGrid(
          minTile: 150,
          padding: EdgeInsets.zero,
          children: [
            AppStatTile(icon: Icons.play_circle_rounded, label: t('جولات', 'Rounds'), value: r.plays),
            AppStatTile(icon: Icons.star_rounded, label: t('نجوم', 'Stars'), value: r.stars, color: appToneColor(context, AppTone.gold)),
            AppStatTile(icon: Icons.extension_rounded, label: t('ألعاب', 'Games'), value: r.gamesPlayed),
            AppStatTile(icon: Icons.emoji_events_rounded, label: t('علامة كاملة', 'Perfect'), value: r.perfect, color: context.colors.success),
          ],
        ),
        if (r.badges.isNotEmpty) _Badges(badges: r.badges),
        if (r.games.isNotEmpty)
          AppSection(
            title: t('الألعاب', 'Games'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < r.games.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.xs),
                _GameRow(row: r.games[i]),
              ],
            ]),
          ),
      ]);
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [body, const SizedBox(height: AppSpace.lg)],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.badges});

  final List<GameBadge> badges;

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((b) => b.earned).length;
    return AppSection(
      title: t('الشارات', 'Badges'),
      subtitle: t('$earned من ${badges.length}', '$earned of ${badges.length}'),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final b in badges)
          LearnBadgeChip(
            key: ValueKey('games.badge.${b.key}'),
            icon: b.iconData,
            label: b.name,
            earned: b.earned,
            caption: b.earned ? AppTime.date(b.earnedAt!) : gameBadgeRuleText(b),
          ),
      ]),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.row});

  final GameProgressRow row;

  @override
  Widget build(BuildContext context) {
    final p = row.progress;
    return AppCard(
      child: Row(children: [
        Icon(gameEngineIcon(row.engine), color: context.colors.primary, size: AppIconSize.lg),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.title, style: AppType.row(context)),
            Text(
              [
                gameEngineName(row.engine),
                countText(p.plays, ar1: 'جولة واحدة', ar2: 'جولتان', arFew: '${p.plays} جولات', arMany: '${p.plays} جولة', en1: '1 round', en: '${p.plays} rounds'),
                t('أفضل نتيجة ${p.bestScore}', 'best ${p.bestScore}'),
              ].join(' · '),
              style: AppType.meta(context),
            ),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        LearnStars(stars: p.stars, size: AppIconSize.sm),
      ]),
    );
  }
}
