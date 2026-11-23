// lib/features/games/learner/games_home_v4.dart — the learner's Games tab v4 (Games v4 T72, kill switch
// `games.templates_v4`): subjects → a level map per subject, a Review chip when spaced repetition has due items, the
// coins pill, the champions strip, and the settings sheet (reciter + age band + credits).
//
//   GamesHomeV4      the stateful body: ONE `GET /games/v4/home`, then `GET /games?v=4&game_subject_id=` for the
//                    subject on screen (cached per subject); asks the age band once (`needs_age`); a 403
//                    `feature_disabled` tells the tab ([onUnavailable]) to fall back to the classic list.
//   GamesHomeV4View  plain values (test/ui/games_home_v4_test.dart, the goldens): a phone is one column, a wide window
//                    puts the subjects on the left and the map on the right.
//   The champions strip comes from the classic list's `champions` block (the tab already loads it): no request here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/champions/champions_strip.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/learner/games_settings_sheet.dart';
import 'package:flutter_education_app/features/games/learner/challenges.dart';
import 'package:flutter_education_app/features/games/learner/level_map.dart';
import 'package:flutter_education_app/features/games/learner/wardrobe.dart';

const kGamesTemplatesV4Key = 'games.templates_v4';
bool gamesV4Off() => AppConfig.disableList.contains(kGamesTemplatesV4Key);

/// A subject's glyph (the server sends a Material icon name); anything unknown is a puzzle piece.
IconData subjectIcon(String? name) => switch (name) {
      'menu_book' => Icons.menu_book_rounded,
      'calculate' || 'functions' => Icons.calculate_rounded,
      'science' => Icons.science_rounded,
      'translate' || 'language' => Icons.translate_rounded,
      'history_edu' => Icons.history_edu_rounded,
      'public' || 'map' => Icons.public_rounded,
      'format_quote' => Icons.format_quote_rounded,
      'code' => Icons.code_rounded,
      'palette' => Icons.palette_rounded,
      'mosque' => Icons.mosque_rounded,
      _ => Icons.extension_rounded,
    };

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String subjectName(V4Subject s) => t(s.nameAr.isEmpty ? s.nameEn : s.nameAr, s.nameEn.isEmpty ? s.nameAr : s.nameEn);

/// A subject's levels as map nodes, in play order.
List<LevelNode> levelNodes(List<V4Level> levels) {
  final sorted = [...levels]..sort((a, b) => a.levelNo != b.levelNo ? a.levelNo.compareTo(b.levelNo) : a.id.compareTo(b.id));
  return [
    for (var i = 0; i < sorted.length; i++)
      LevelNode(
        id: sorted[i].id,
        no: sorted[i].levelNo,
        title: GameSummary.fromJson(sorted[i].raw).title,
        stars: GameSummary.fromJson(sorted[i].raw).progress?.stars ?? 0,
        locked: sorted[i].locked,
        sacred: sorted[i].sacred,
        unlockMinStars: sorted[i].unlock['min_stars'] is num ? (sorted[i].unlock['min_stars'] as num).toInt() : 1,
        previousNo: i > 0 ? sorted[i - 1].levelNo : null,
      ),
  ];
}

class GamesHomeV4 extends StatefulWidget {
  const GamesHomeV4({super.key, this.api, this.champions, this.onChampions, this.onUnavailable});

  final GamesV4Api? api;
  final ChampionsStripData? champions;
  final VoidCallback? onChampions;

  /// The v4 home is refused (kill switch / feature off): the tab shows the classic list instead.
  final VoidCallback? onUnavailable;

  @override
  State<GamesHomeV4> createState() => _GamesHomeV4State();
}

class _GamesHomeV4State extends State<GamesHomeV4> {
  late final GamesV4Api _api = widget.api ?? GamesV4Api();
  V4Home? _home;
  int? _subjectId;
  final Map<int, List<V4Level>> _levels = {};
  bool _loading = true, _levelsLoading = false, _asked = false;
  String? _error;
  int _seq = 0;

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
    final seq = ++_seq;
    if (_home == null) setState(() => _loading = true);
    try {
      final h = await _api.home();
      if (!mounted || seq != _seq) return;
      final ids = {for (final s in h.subjects) s.id};
      final pick = ids.contains(_subjectId) ? _subjectId : (h.continueLevel?.subjectId ?? (h.subjects.isEmpty ? null : h.subjects.first.id));
      setState(() {
        _home = h;
        _loading = false;
        _error = null;
        _levels.clear();
        _subjectId = pick;
      });
      if (pick != null) _loadLevels(pick);
      if (h.profile.needsAge && !_asked) {
        _asked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final p = await showAgeBandAsk(context, api: _api);
          if (p != null && mounted) _load();
        });
      }
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (e is ApiException && (e.code == 'feature_disabled' || e.statusCode == 403)) {
        widget.onUnavailable?.call();
        return;
      }
      setState(() {
        _loading = false;
        _error = gamesErrorText(e);
      });
    }
  }

  Future<void> _loadLevels(int id) async {
    if (_levels.containsKey(id)) return;
    setState(() => _levelsLoading = true);
    try {
      final l = await _api.levels(subjectId: id);
      if (!mounted) return;
      setState(() {
        _levels[id] = l;
        _levelsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _levelsLoading = false);
      showAppNotice(gamesErrorText(e), error: true);
    }
  }

  void _subject(int id) {
    setState(() => _subjectId = id);
    _loadLevels(id);
  }

  void _play(V4Level l, {bool review = false}) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/games/${l.id}'),
        builder: (_) => GamePlayPage(game: GameSummary.fromJson(l.raw), v4: _api, review: review),
      ));

  /// The review round: the level with the most items due.
  Future<void> _review() async {
    final h = _home;
    if (h == null) return;
    if (h.reviewLevels.isEmpty) {
      showAppNotice(t('لا توجد مراجعة الآن', 'Nothing to review right now'));
      return;
    }
    final due = [...h.reviewLevels.entries]..sort((a, b) => b.value.compareTo(a.value));
    try {
      final all = await _api.levels();
      if (!mounted) return;
      for (final e in due) {
        final hit = all.where((l) => l.id == e.key);
        if (hit.isNotEmpty) return _play(hit.first, review: true);
      }
      showAppNotice(t('لا توجد مراجعة الآن', 'Nothing to review right now'));
    } catch (e) {
      if (mounted) showAppNotice(gamesErrorText(e), error: true);
    }
  }

  Future<void> _settings() async {
    final h = _home;
    if (h == null) return;
    await showGamesSettingsSheet(context, profile: h.profile, api: _api);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = _home;
    if (h == null) {
      return _loading
          ? const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4, padding: EdgeInsets.zero))
          : AppErrorState(message: _error, onRetry: _load);
    }
    final id = _subjectId;
    final cont = h.continueLevel;
    return AppRefresh(
      onRefresh: _load,
      child: GamesHomeV4View(
        home: h,
        levels: id == null ? null : _levels[id],
        levelsLoading: _levelsLoading,
        subjectId: id,
        onSubject: _subject,
        onOpen: _play,
        onContinue: cont == null || cont.locked ? null : () => _play(cont),
        onReview: _review,
        onSettings: _settings,
        onChallenges: gamesChallengesOff() ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/games/challenges'), builder: (_) => GamesChallengesPage(api: _api, ageBand: h.profile.ageBand))),
        onWardrobe: () => showWardrobe(context, api: _api, ageBand: h.profile.ageBand).then((_) { if (mounted) _load(); }),
        champions: widget.champions,
        onChampions: widget.onChampions,
      ),
    );
  }
}

/// The body with plain values.
class GamesHomeV4View extends StatelessWidget {
  const GamesHomeV4View({
    super.key,
    required this.home,
    required this.levels,
    required this.subjectId,
    this.levelsLoading = false,
    this.onSubject,
    this.onOpen,
    this.onContinue,
    this.onReview,
    this.onSettings,
    this.onWardrobe,
    this.champions,
    this.onChampions,
    this.showCoins,
    this.onChallenges,
  });

  final V4Home home;

  /// The levels of [subjectId] (null = not loaded yet).
  final List<V4Level>? levels;
  final int? subjectId;
  final bool levelsLoading;
  final ValueChanged<int>? onSubject;
  final ValueChanged<V4Level>? onOpen;
  final VoidCallback? onContinue, onReview, onSettings, onChampions;

  /// Opens the wardrobe (T73); shown beside the coins while `games.cosmetics` is on.
  final VoidCallback? onWardrobe;
  final ChampionsStripData? champions;

  /// Null = follow the `games.cosmetics` kill switch.
  final bool? showCoins;

  /// Opens the challenges page (T76); the chip shows while `games.challenges` is on.
  final VoidCallback? onChallenges;

  @override
  Widget build(BuildContext context) {
    final p = home.profile;
    final theme = AgeTheme.of(context, band: p.ageBand);
    return AgeThemeScope(
      theme: theme,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final gutter = AppSpace.gutter(box.maxWidth);
        final subjects = home.subjects;
        V4Subject? cur;
        for (final s in subjects) {
          if (s.id == subjectId) cur = s;
        }
        final header = _Header(
          coins: (showCoins ?? !AppConfig.disableList.contains('games.cosmetics')) ? p.coins : null,
          // the chip counts only what its tap can open (the levels with items due), so it is never a dead tap
          reviewDue: home.reviewLevels.values.fold(0, (a, b) => a + b),
          onReview: onReview,
          onSettings: onSettings,
          onWardrobe: onWardrobe,
          onChallenges: onChallenges,
        );
        final cont = home.continueLevel;
        final contCard = cont == null || cont.locked
            ? null
            : _ContinueCard(level: cont, subject: [for (final s in subjects) if (s.id == cont.subjectId) s].firstOrNull, onTap: onContinue);
        final strip = champions == null ? null : ChampionsStrip(data: champions!, onOpen: onChampions);
        final map = _MapCard(subject: cur, levels: levels, loading: levelsLoading, home: home, onOpen: onOpen);
        final rail = wide
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final s in subjects) ...[
                  _SubjectTile(subject: s, selected: s.id == subjectId, onTap: () => onSubject?.call(s.id), wide: true),
                  const SizedBox(height: AppSpace.xs),
                ],
              ])
            : SizedBox(
                height: _SubjectTile.height(context),
                child: ListView.separated(
                  key: const ValueKey('games.v4.subjects'),
                  scrollDirection: Axis.horizontal,
                  itemCount: subjects.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
                  itemBuilder: (_, i) => _SubjectTile(subject: subjects[i], selected: subjects[i].id == subjectId, onTap: () => onSubject?.call(subjects[i].id)),
                ),
              );
        final Widget body;
        if (subjects.isEmpty) {
          body = AppEmpty(key: const ValueKey('games.v4.empty'), icon: Icons.extension_rounded, title: t('لا توجد مواد بعد', 'No subjects yet'));
        } else if (wide) {
          body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [rail, if (strip != null) ...[const SizedBox(height: AppSpace.sm), strip]])),
            const SizedBox(width: AppSpace.lg),
            Expanded(child: map),
          ]);
        } else {
          body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rail,
            const SizedBox(height: AppSpace.md),
            map,
            if (strip != null) ...[const SizedBox(height: AppSpace.md), strip],
          ]);
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xl),
          children: [
            header,
            if (contCard != null) ...[const SizedBox(height: AppSpace.md), contCard],
            const SizedBox(height: AppSpace.md),
            body,
          ],
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.coins, this.reviewDue = 0, this.onReview, this.onSettings, this.onWardrobe, this.onChallenges});
  final int? coins;
  final int reviewDue;
  final VoidCallback? onReview, onSettings, onWardrobe, onChallenges;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final age = AgeThemeScope.of(context);
    final gold = age.palette.gold;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(t('العب وتعلّم', 'Play and learn'), style: AppType.headline(context))),
        IconButton(
          key: const ValueKey('games.v4.settings'),
          tooltip: t('إعدادات الألعاب', 'Games settings'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(Icons.tune_rounded, color: c.textDark),
          onPressed: onSettings,
        ),
      ]),
      if (coins != null || reviewDue > 0 || onChallenges != null) ...[
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (coins != null)
            Semantics(
              label: t('$coins عملة', '$coins coins'),
              excludeSemantics: true,
              child: Container(
                key: const ValueKey('games.v4.coins'),
                constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(gold.withValues(alpha: 0.22), c.cardBg),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: gold, width: age.age == GameAge.kids ? AppBorder.strong : AppBorder.hairline),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.monetization_on_rounded, color: gold, size: AppIconSize.md),
                  const SizedBox(width: AppSpace.xs),
                  Text('$coins', style: AppType.figure(context)),
                ]),
              ),
            ),
          if (coins != null && onWardrobe != null)
            Material(
              color: Color.alphaBlend(age.palette.accent.withValues(alpha: 0.14), c.cardBg),
              shape: StadiumBorder(side: BorderSide(color: age.palette.accent, width: AppBorder.strong)),
              child: InkWell(
                key: const ValueKey('games.v4.wardrobe'),
                customBorder: const StadiumBorder(),
                onTap: onWardrobe,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.checkroom_rounded, color: age.palette.accent, size: AppIconSize.md),
                      const SizedBox(width: AppSpace.xs),
                      Text(t('خزانتي', 'Wardrobe'), style: AppType.row(context)),
                    ]),
                  ),
                ),
              ),
            ),
          if (onChallenges != null)
            Material(
              color: Color.alphaBlend(age.palette.accent.withValues(alpha: 0.14), c.cardBg),
              shape: StadiumBorder(side: BorderSide(color: age.palette.accent, width: AppBorder.strong)),
              child: InkWell(
                key: const ValueKey('games.v4.challenges'),
                customBorder: const StadiumBorder(),
                onTap: onChallenges,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.emoji_events_rounded, color: age.palette.accent, size: AppIconSize.md),
                      const SizedBox(width: AppSpace.xs),
                      Text(t('التحدّيات', 'Challenges'), style: AppType.row(context)),
                    ]),
                  ),
                ),
              ),
            ),
          if (reviewDue > 0)
            Semantics(
              button: true,
              label: t('مراجعة، $reviewDue ينتظر', 'Review, $reviewDue due'),
              excludeSemantics: true,
              child: Material(
                color: Color.alphaBlend(age.palette.accent.withValues(alpha: 0.14), c.cardBg),
                shape: StadiumBorder(side: BorderSide(color: age.palette.accent, width: AppBorder.strong)),
                child: InkWell(
                  key: const ValueKey('games.v4.review'),
                  customBorder: const StadiumBorder(),
                  onTap: onReview,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.replay_circle_filled_rounded, color: age.palette.accent, size: AppIconSize.md),
                        const SizedBox(width: AppSpace.xs),
                        Text('${t('مراجعة', 'Review')} · $reviewDue', style: AppType.row(context)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ],
    ]);
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.level, this.subject, this.onTap});
  final V4Level level;
  final V4Subject? subject;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final age = AgeThemeScope.of(context);
    final g = GameSummary.fromJson(level.raw);
    return Semantics(
      button: true,
      label: '${t('تابع', 'Continue')}, ${g.title}',
      excludeSemantics: true,
      child: AppCard(
        key: const ValueKey('games.v4.continue'),
        highlight: true,
        onTap: onTap,
        child: Row(children: [
          Container(
            width: AppTouch.primary,
            height: AppTouch.primary,
            decoration: BoxDecoration(shape: BoxShape.circle, color: age.palette.accent),
            child: Icon(Icons.play_arrow_rounded, color: age.palette.paper, size: AppIconSize.xl),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('تابع من حيث وقفت', 'Pick up where you left off'), style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              if (subject != null) Text('${subjectName(subject!)} · ${t('المستوى', 'Level')} ${level.levelNo}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.subject, required this.selected, this.onTap, this.wide = false});
  final V4Subject subject;
  final bool selected, wide;
  final VoidCallback? onTap;

  static double height(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return AppSpace.sm * 2 + AppTouch.min - AppSpace.xs + AppSpace.xs + s.scale(14) * 1.5 + AppSpace.xxs * 2 + AppSpace.xs + s.scale(12) * 1.5 + AppBorder.line * 2;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final age = AgeThemeScope.of(context);
    final tint = parseHexColor(subject.color) ?? age.palette.accent;
    final frac = subject.levels == 0 ? 0.0 : (subject.done / subject.levels).clamp(0.0, 1.0);
    final border = selected ? tint : c.divider;
    final ring = age.age == GameAge.kids ? AppBorder.line : AppBorder.strong;
    final icon = Container(
      width: AppTouch.min - AppSpace.xs,
      height: AppTouch.min - AppSpace.xs,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Color.alphaBlend(tint.withValues(alpha: 0.18), c.cardBg)),
      child: Icon(subjectIcon(subject.icon), color: tint, size: AppIconSize.lg),
    );
    final progress = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(subjectName(subject), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
      const SizedBox(height: AppSpace.xxs),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: LinearProgressIndicator(value: frac, minHeight: AppSpace.xs, color: tint, backgroundColor: c.divider.withValues(alpha: 0.6)),
      ),
      const SizedBox(height: AppSpace.xxs),
      Row(children: [
        Flexible(child: Text('${subject.done}/${subject.levels} · ${subject.stars}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
        const SizedBox(width: AppSpace.xxs),
        Icon(Icons.star_rounded, size: AppIconSize.xs, color: age.palette.gold),
      ]),
    ]);
    return Semantics(
      button: true,
      selected: selected,
      label: '${subjectName(subject)}, ${subject.done}/${subject.levels}',
      excludeSemantics: true,
      child: Material(
        color: selected ? Color.alphaBlend(tint.withValues(alpha: 0.08), c.cardBg) : c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: border, width: selected ? ring : AppBorder.hairline)),
        child: InkWell(
          key: ValueKey('games.v4.subject.${subject.id}'),
          borderRadius: AppRadius.cardAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: wide
                ? Row(children: [icon, const SizedBox(width: AppSpace.sm), Expanded(child: progress)])
                : SizedBox(width: 132, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(height: AppSpace.xs), progress])),
          ),
        ),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.subject, required this.levels, required this.loading, required this.home, this.onOpen});
  final V4Subject? subject;
  final List<V4Level>? levels;
  final bool loading;
  final V4Home home;
  final ValueChanged<V4Level>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final age = AgeThemeScope.of(context);
    final s = subject;
    final tint = parseHexColor(s?.color) ?? age.palette.accent;
    final ls = levels;
    final nodes = ls == null ? const <LevelNode>[] : levelNodes(ls);
    final cont = home.continueLevel?.id;
    final Widget content;
    if (ls == null || (loading && ls.isEmpty)) {
      content = const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    } else if (ls.isEmpty) {
      content = AppEmpty(key: const ValueKey('games.v4.noLevels'), icon: Icons.hourglass_empty_rounded, title: t('لا مستويات لك هنا بعد', 'No levels for you here yet'));
    } else {
      content = LevelMap(
        key: ValueKey('games.v4.map.${s?.id}'),
        nodes: nodes,
        currentId: currentNodeId(nodes, preferred: cont),
        tint: tint,
        equipped: home.profile.equipped,
        onOpen: (n) => onOpen?.call(ls.firstWhere((l) => l.id == n.id)),
        onLocked: (n) => showAppNotice(n.unlockText),
      );
    }
    final quran = s != null && (s.key.contains('quran') || (ls?.any((l) => (l.topic ?? '').startsWith('juz') || (l.topic ?? '').startsWith('surah')) ?? false));
    final bleed = content is LevelMap;
    final side = bleed ? 0.0 : AppSpace.md;
    Widget pad(Widget w) => bleed ? Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), child: w) : w;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.blockAll,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(tint.withValues(alpha: age.age == GameAge.kids ? 0.16 : 0.08), c.cardBg), c.cardBg],
        ),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      // the map runs edge to edge (its landscape fills the card); the title and the credit keep the side padding
      child: ClipRRect(
        borderRadius: AppRadius.blockAll,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, bleed && !quran ? 0 : AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s != null) ...[
              pad(Text(subjectName(s), style: AppType.pageTitle(context))),
              const SizedBox(height: AppSpace.xxs),
              pad(Row(children: [
                Icon(Icons.star_rounded, size: AppIconSize.sm, color: age.palette.gold),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(t('${s.done} من ${s.levels} مستوى · ${s.stars} نجمة', '${s.done} of ${s.levels} levels · ${s.stars} stars'),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ),
              ])),
              const SizedBox(height: AppSpace.md),
            ],
            content,
            if (quran) ...[const SizedBox(height: AppSpace.xs), pad(const TanzilCredit())],
          ]),
        ),
      ),
    );
  }
}
