// lib/features/games/games_tab.dart — the student's Games tab (Learning Hub Phase 6, D-1346; kill switch
// `student_tab_games`): short educational games (quiz, match, order) for the student's level and subject.
//
//   GamesTab         the tab: GET /api/v1/games with THE course filter bar (CourseFilters / CourseFilterBar, stage →
//                    grade and subject only, remembered with the courses' filters) and an engine row; the header's
//                    "My progress" opens the stars and badges page (signed in). Loads nothing until the tab opens
//                    (LazyTabStack), so the student home's requests do not change. GET /api/v1/module-settings/games
//                    tells whether a play can earn points (shown on the cards only when it can).
//   GamesBrowseView  the tab's body with plain values (test/ui/games_layout_test.dart)
//                    Learning Hub v2 (D-1588): a category and a difficulty filter (server side, `?category&difficulty`)
//                    Games v3 (D-1771): the champions strip on top (the list call's `champions` block, no request of
//                    its own) and the app bar's Hall of Champions (kill switch `games.champions`)
//   GameCard         one game: its cover (decoded small, only when drawn) or the engine's glyph, the title, the
//                    difficulty, the stars so far (or "New"), the points it can earn
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/champions/champions_page.dart' show HallOfChampionsPage;
import 'package:flutter_education_app/features/games/champions/champions_strip.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/games_progress.dart';
import 'package:flutter_education_app/features/games/learner/games_home_v4.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

String gamesCountText(int n) => countText(n,
    ar1: 'لعبة واحدة',
    ar2: 'لعبتان',
    arFew: '$n ألعاب',
    arMany: '$n لعبة',
    en1: '1 game',
    en: '$n games',
    ar0: 'لا توجد ألعاب',
    en0: 'No games');

/// Whether a play can earn points here: the module setting `games.points_rewards` (GET /module-settings/games) and
/// the `games.rewards` switch. The server decides what it pays; this only says whether to show the reward.
Future<bool> gamesRewardsOn([ApiClient? api]) async {
  if (AppConfig.disableList.contains('games.rewards')) return false;
  try {
    final r = await (api ?? ApiClient()).get('/api/v1/module-settings/games');
    final v = r is Map ? r['values'] : null;
    return v is Map && v['points_rewards'] == true;
  } catch (_) {
    return false;
  }
}

class GamesTab extends StatefulWidget {
  const GamesTab({super.key, this.api});

  final GamesApi? api;

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  late final GamesApi _api = widget.api ?? GamesApi();

  CourseFilters _filters = CourseFilters.empty;
  CourseFilterEdu? _edu;
  String _user = 'guest';
  String? _engine;
  String? _category, _difficulty;
  bool _rewards = false;

  /// Games v4 (T72): the levels home is the tab's first view unless the kill switch `games.templates_v4` hides it (or
  /// the server refuses it); the classic list stays one tap away.
  bool _classic = false, _v4Refused = false;

  List<GameSummary> _items = const [];
  ChampionsStripData? _champions;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    GamesBus.revision.addListener(_reload);
    _start();
    gamesRewardsOn().then((on) {
      if (mounted && on) setState(() => _rewards = true);
    });
  }

  @override
  void dispose() {
    GamesBus.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  /// The courses' remembered filters (level + subject) are the games' start too: one set of choices per person.
  Future<void> _start() async {
    final u = await CourseFilterStore.user();
    var f = courseFiltersOff() ? CourseFilters.empty : await CourseFilterStore.initial(u.id);
    f = CourseFilters(country: f.country, stageId: f.stageId, gradeId: f.gradeId, subjectId: f.subjectId);
    if (!mounted) return;
    setState(() {
      _user = u.id;
      _filters = f;
    });
    _load();
    CourseFilterEdu.load(f.country, storedOnly: true).then((e) {
      if (mounted && e != null) setState(() => _edu = e);
    });
  }

  Future<CourseFilterEdu?> _loadEdu() async {
    final edu = await CourseFilterEdu.load(_filters.country);
    if (mounted && edu != null) setState(() => _edu = edu);
    return edu;
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final off = courseFiltersOff();
    try {
      final r = await _api.games(
        country: _filters.country,
        stageId: off ? null : _filters.stageId,
        gradeId: off ? null : _filters.gradeId,
        subjectId: off ? null : _filters.subjectId,
        category: _category,
        difficulty: _difficulty,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = r.items;
        _champions = ChampionsStripData.maybe(r.champions);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = gamesErrorText(e);
      });
    }
  }

  void _onFilters(CourseFilters f) {
    setState(() => _filters = f);
    // the courses keep their own delivery / area: only the level and the subject come from here
    CourseFilterStore.initial(_user).then((saved) => CourseFilterStore.save(
        _user,
        CourseFilters(
            country: f.country ?? saved.country,
            stageId: f.stageId,
            gradeId: f.gradeId,
            subjectId: f.subjectId,
            delivery: saved.delivery,
            areaId: saved.areaId,
            areaAr: saved.areaAr,
            areaEn: saved.areaEn)));
    _load();
  }

  void _open(GameSummary g) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/games/${g.id}'),
        builder: (_) => GamePlayPage(game: g, api: _api),
      ));

  /// The Hall of Champions (Games v3), on the strip's board.
  void _openHall([ChampionScope? scope]) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/games/champions'),
        builder: (_) => HallOfChampionsPage(scope: scope),
      ));

  void _openProgress() => GuestGuard.run(
      context,
      () => Navigator.of(context).push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/games/progress'),
            builder: (_) => GamesProgressPage(api: _api),
          )));

  @override
  Widget build(BuildContext context) {
    final v4 = !GuestState.active && !gamesV4Off() && !_v4Refused;
    final classic = GamesBrowseView(
        filters: _filters,
        edu: _edu,
        loadEdu: _loadEdu,
        onFilters: _onFilters,
        engine: _engine,
        onEngine: (e) => setState(() => _engine = e),
        category: _category,
        difficulty: _difficulty,
        onCategory: (v) {
          setState(() => _category = v);
          _load();
        },
        onDifficulty: (v) {
          setState(() => _difficulty = v);
          _load();
        },
        items: _items,
        champions: GuestState.active || championsOff() ? null : _champions,
        onChampions: () => _openHall(_champions?.scope),
        loading: _loading,
        error: _error,
        rewards: _rewards,
        onOpen: _open,
        onRetry: _load,
        onRefresh: _load,
      );
    return BasePage(
      width: AppWidth.wide,
      appBar: ScreenAppBar(
        title: t('الألعاب', 'Games'),
        showBack: false,
        actions: [
          if (!GuestState.active)
            ParentComponent(
              featureKey: kGamesChampionsKey,
              child: IconButton(
                key: const ValueKey('games.hall'),
                tooltip: t('لوحة الأبطال', 'Hall of Champions'),
                icon: const Icon(Icons.military_tech_rounded),
                onPressed: () => _openHall(_champions?.scope),
              ),
            ),
          if (!GuestState.active)
            IconButton(
              key: const ValueKey('games.progress'),
              tooltip: t('تقدّمي وشاراتي', 'My progress and badges'),
              icon: const Icon(Icons.emoji_events_rounded),
              onPressed: _openProgress,
            ),
        ],
      ),
      child: SafeArea(
        child: !v4
            ? classic
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                  child: Row(children: [
                    AppChoiceChip(key: const ValueKey('games.view.levels'), label: t('المستويات', 'Levels'), icon: Icons.route_rounded, selected: !_classic, onTap: () => setState(() => _classic = false)),
                    const SizedBox(width: AppSpace.xs),
                    AppChoiceChip(key: const ValueKey('games.view.classic'), label: t('ألعاب كلاسيكية', 'Classic games'), icon: Icons.extension_rounded, selected: _classic, onTap: () => setState(() => _classic = true)),
                  ]),
                ),
                Expanded(
                  child: _classic
                      ? classic
                      : GamesHomeV4(
                          champions: GuestState.active || championsOff() ? null : _champions,
                          onChampions: () => _openHall(_champions?.scope),
                          onUnavailable: () => setState(() => _v4Refused = true),
                        ),
                ),
              ]),
      ),
    );
  }
}

/// The browse body with plain values. [engine] filters the list on the device (null = every engine).
class GamesBrowseView extends StatelessWidget {
  const GamesBrowseView({
    super.key,
    required this.filters,
    required this.onFilters,
    required this.items,
    this.edu,
    this.loadEdu,
    this.engine,
    this.onEngine,
    this.category,
    this.difficulty,
    this.onCategory,
    this.onDifficulty,
    this.loading = false,
    this.error,
    this.rewards = false,
    this.onOpen,
    this.onRetry,
    this.onRefresh,
    this.champions,
    this.onChampions,
  });

  /// Games v3: today's top 3 of my board (the `champions` block of GET /games); null = no strip.
  final ChampionsStripData? champions;
  final VoidCallback? onChampions;

  final CourseFilters filters;
  final ValueChanged<CourseFilters> onFilters;
  final CourseFilterEdu? edu;
  final Future<CourseFilterEdu?> Function()? loadEdu;
  final String? engine;
  final ValueChanged<String?>? onEngine;

  /// The server-side filters (null = every category / difficulty).
  final String? category, difficulty;
  final ValueChanged<String?>? onCategory, onDifficulty;
  final List<GameSummary> items;
  final bool loading;
  final String? error;
  final bool rewards;
  final ValueChanged<GameSummary>? onOpen;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final engines = {for (final g in items) g.engine}.toList();
    final shown = engine == null ? items : [for (final g in items) if (g.engine == engine) g];
    final head = <Widget>[
      if (champions != null) ...[
        ChampionsStrip(data: champions!, onOpen: onChampions),
        const SizedBox(height: AppSpace.sm),
      ],
      ParentComponent(
        featureKey: kCourseFiltersKey,
        child: CourseFilterBar(
          value: filters,
          edu: edu,
          loadEdu: loadEdu,
          resultCount: loading ? null : shown.length,
          withPlace: false,
          countLabel: gamesCountText,
          sheetTitle: t('تصفية الألعاب', 'Filter the games'),
          applyLabel: t('عرض الألعاب', 'Show games'),
          onChanged: onFilters,
        ),
      ),
      if (onCategory != null || onDifficulty != null) ...[
        const SizedBox(height: AppSpace.sm),
        Row(key: const ValueKey('games.filters'), children: [
          if (onCategory != null)
            Expanded(
              child: AppDropdown<String>(
                key: const ValueKey('games.filter.category'),
                decoration: InputDecoration(labelText: t('التصنيف', 'Category')),
                value: category ?? '',
                items: [
                  DropdownMenuItem(value: '', child: Text(t('كل التصنيفات', 'Every category'), overflow: TextOverflow.ellipsis)),
                  for (final k in kGameCategories)
                    DropdownMenuItem(value: k, child: Text(gameCategoryName(k), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => onCategory!(v == null || v.isEmpty ? null : v),
              ),
            ),
          if (onCategory != null && onDifficulty != null) const SizedBox(width: AppSpace.sm),
          if (onDifficulty != null)
            Expanded(
              child: AppDropdown<String>(
                key: const ValueKey('games.filter.difficulty'),
                decoration: InputDecoration(labelText: t('الصعوبة', 'Difficulty')),
                value: difficulty ?? '',
                items: [
                  DropdownMenuItem(value: '', child: Text(t('كل المستويات', 'Any difficulty'), overflow: TextOverflow.ellipsis)),
                  for (final k in kGameDifficulties)
                    DropdownMenuItem(value: k, child: Text(gameDifficultyName(k), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => onDifficulty!(v == null || v.isEmpty ? null : v),
              ),
            ),
        ]),
      ],
      if (engines.length > 1) ...[
        const SizedBox(height: AppSpace.sm),
        SingleChildScrollView(
          key: const ValueKey('games.engines'),
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            AppChoiceChip(label: t('كل الألعاب', 'All games'), selected: engine == null, onTap: () => onEngine?.call(null)),
            for (final e in engines) ...[
              const SizedBox(width: AppSpace.xs),
              AppChoiceChip(
                key: ValueKey('games.engine.$e'),
                icon: gameEngineIcon(e),
                label: gameEngineName(e),
                selected: e == engine,
                onTap: () => onEngine?.call(e == engine ? null : e),
              ),
            ],
          ]),
        ),
      ],
      const SizedBox(height: AppSpace.md),
    ];
    final Widget body;
    if (loading && items.isEmpty) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (shown.isEmpty) {
      body = AppEmpty(
        key: const ValueKey('games.empty'),
        icon: Icons.extension_rounded,
        title: filters.hasLevel
            ? t('لا توجد ألعاب لهذه الاختيارات بعد', 'No games for these choices yet')
            : t('لا توجد ألعاب بعد', 'No games yet'),
        message: filters.hasLevel ? t('غيّر الاختيارات أو امسح التصفية.', 'Change the choices or clear the filters.') : null,
        actionLabel: filters.hasLevel ? t('اعرض كل المستويات', 'Show every level') : null,
        onAction: filters.hasLevel ? () => onFilters(filters.withLevel(null, null)) : null,
      );
    } else {
      body = AppGrid(
        minTile: 280,
        padding: EdgeInsets.zero,
        children: [for (final g in shown) GameCard(game: g, rewards: rewards, onTap: () => onOpen?.call(g))],
      );
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [...head, body, const SizedBox(height: AppSpace.lg)],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

/// One game: the engine's glyph in a tinted well, the title, the engine's name, the stars so far (or "New") and the
/// points a play can earn (only when [rewards]).
class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.game, this.rewards = false, this.onTap});

  final GameSummary game;
  final bool rewards;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = game.progress;
    final well = AppBlockColors.of(context, AppBlockTone.forKey(game.engine, among: AppBlockTone.coverTones));
    return Semantics(
      button: true,
      label: [
        game.title,
        gameEngineName(game.engine),
        if (p == null || p.plays == 0) t('جديدة', 'new') else t('${p.stars} من 3 نجوم', '${p.stars} of 3 stars'),
      ].join(', '),
      excludeSemantics: true,
      child: AppCard(
        key: ValueKey('games.card.${game.id}'),
        onTap: onTap,
        child: Row(children: [
          GameCover(game: game, well: well),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AutoDirText(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(gameEngineName(game.engine), style: AppType.meta(context)),
                if (game.difficulty.isNotEmpty) Text('· ${gameDifficultyName(game.difficulty)}', style: AppType.meta(context)),
                if (p == null || p.plays == 0)
                  AppStatusBadge(label: t('جديدة', 'New'), tone: AppTone.brand, dense: true)
                else
                  LearnStars(stars: p.stars, size: AppIconSize.sm),
                if (rewards && game.pointsReward > 0)
                  AppStatusBadge(
                      label: countText(game.pointsReward,
                          ar1: '+1 نقطة', ar2: '+نقطتان', arFew: '+${game.pointsReward} نقاط', arMany: '+${game.pointsReward} نقطة',
                          en1: '+1 point', en: '+${game.pointsReward} points'),
                      tone: AppTone.gold,
                      dense: true),
              ]),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
      ),
    );
  }
}

/// A game's cover in the card's well: the image decoded at the well's size (lazy: only when the card is drawn), the
/// engine's glyph while it loads, when it fails and when there is none.
class GameCover extends StatelessWidget {
  const GameCover({super.key, required this.game, required this.well});

  final GameSummary game;
  final AppBlockColors well;

  @override
  Widget build(BuildContext context) {
    final glyph = Container(
      width: AppTouch.primary,
      height: AppTouch.primary,
      decoration: BoxDecoration(color: well.surface, borderRadius: AppRadius.cardAll),
      child: Icon(gameEngineIcon(game.engine), color: well.ink, size: AppIconSize.lg),
    );
    final url = game.coverUrl;
    if (url == null) return glyph;
    final px = (AppTouch.primary * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: AppRadius.cardAll,
      child: Image.network(
        url,
        width: AppTouch.primary,
        height: AppTouch.primary,
        fit: BoxFit.cover,
        cacheWidth: px,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, sync) => frame == null && !sync ? glyph : child,
        errorBuilder: (context, error, stack) => glyph,
      ),
    );
  }
}
