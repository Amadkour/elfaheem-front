// lib/features/games/games_progress.dart — stars, badges and games played (D-1346), for the student and for a parent.
//
//   GamesProgressPage      the student's page: GET /api/v1/me/games/progress (reloads after a saved play)
//   ParentChildGamesPage   a parent's view of one linked child: GET /api/v1/parent/children/{id}/games (the light
//                          summary, CONTRACT §8: time and games finished for 7 / 30 days; no game list, no badges)
//   GamesProgressView      the student's body with plain values (test/ui/games_layout_test.dart): totals, every badge
//                          (earned in gold, the rest locked with what earns them), and each game's best score and stars
//   ParentGamesSummaryView the parent's body with plain values (test/ui/games_layout_test.dart)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/features/parent/parent_consent.dart' show ParentConsentRequired, isConsentRequired;
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

/// A parent's view of one linked child's games: the light summary only (CONTRACT §8). A 403 (the kill switch or the
/// `parent_summary` setting off) hides the section; a minor without consent gets the consent state.
class ParentChildGamesPage extends StatefulWidget {
  const ParentChildGamesPage({super.key, required this.studentId, required this.studentName, this.api});

  final int studentId;
  final String studentName;
  final GamesV4Api? api;

  @override
  State<ParentChildGamesPage> createState() => _ParentChildGamesPageState();
}

class _ParentChildGamesPageState extends State<ParentChildGamesPage> {
  late final GamesV4Api _api = widget.api ?? GamesV4Api();
  V4ParentGames? _summary;
  String? _error;
  bool _loading = true;

  /// 403 without `consent_required`: the summary is switched off, so the section is not drawn at all.
  bool _hidden = false;

  /// 403 `consent_required`: a minor whose parent has not consented yet (D-1371).
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _consent = false;
      _hidden = false;
    });
    try {
      final r = await _api.parentGames(widget.studentId);
      if (!mounted) return;
      setState(() {
        _summary = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _consent = isConsentRequired(e);
        _hidden = !_consent && e is ApiException && e.statusCode == 403;
        _error = _hidden ? null : gamesErrorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        width: AppWidth.content,
        // the short tab name as the title, the child under it: "ألعاب <a long name>" wrapped and was clipped at 360
        appBar: ScreenAppBar(
          title: gamesLabel(),
          subtitle: widget.studentName.isEmpty ? null : widget.studentName,
        ),
        child: SafeArea(
          child: _consent
              ? ParentConsentRequired(studentId: widget.studentId, childName: widget.studentName, onGranted: _load)
              : _hidden
                  ? const SizedBox.shrink()
                  : ParentGamesSummaryView(summary: _summary, loading: _loading, error: _error, onRetry: _load, onRefresh: _load),
        ),
      );
}

/// The parent's light summary with plain values: time played and games finished, for the last 7 or 30 days.
class ParentGamesSummaryView extends StatefulWidget {
  const ParentGamesSummaryView({super.key, this.summary, this.loading = false, this.error, this.onRetry, this.onRefresh});

  final V4ParentGames? summary;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  @override
  State<ParentGamesSummaryView> createState() => _ParentGamesSummaryViewState();
}

class _ParentGamesSummaryViewState extends State<ParentGamesSummaryView> {
  /// 0 = the last 7 days, 1 = the last 30 days.
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final Widget body;
    if (widget.loading && s == null) {
      body = const AppListSkeleton(items: 2, padding: EdgeInsets.zero);
    } else if (widget.error != null && s == null) {
      body = AppErrorState(message: widget.error, onRetry: widget.onRetry);
    } else if (s == null) {
      body = AppEmpty(
        key: const ValueKey('games.summary.empty'),
        icon: Icons.emoji_events_rounded,
        title: t('لم يلعب أي لعبة بعد', 'No games played yet'),
        message: t('تظهر هنا مدة اللعب والألعاب المنجزة.', 'Time played and games finished show here.'),
      );
    } else {
      final long = _range == 1;
      final minutes = long ? s.minutes30d : s.minutes7d;
      final finished = long ? s.finished30d : s.finished7d;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTabs(
          key: const ValueKey('games.summary.range'),
          items: [AppTabItem(t('آخر 7 أيام', 'Last 7 days')), AppTabItem(t('آخر 30 يومًا', 'Last 30 days'))],
          index: _range,
          onChanged: (i) => setState(() => _range = i),
          expand: true,
        ),
        const SizedBox(height: AppSpace.sm),
        AppGrid(
          minTile: 150,
          padding: EdgeInsets.zero,
          children: [
            AppStatTile(
              key: const ValueKey('games.summary.time'),
              icon: Icons.timer_rounded,
              label: t('وقت اللعب', 'Time played'),
              value: gamesMinutesText(minutes),
            ),
            AppStatTile(
              key: const ValueKey('games.summary.finished'),
              icon: Icons.extension_rounded,
              label: t('ألعاب منجزة', 'Games finished'),
              value: finished,
            ),
          ],
        ),
      ]);
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [body, const SizedBox(height: AppSpace.lg)],
    );
    return widget.onRefresh == null ? list : AppRefresh(onRefresh: widget.onRefresh!, child: list);
  }
}

/// A play time in words: "50 min" · "2 h" · "1 h 20 min" (Arabic plural forms through countText).
String gamesMinutesText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) {
    return countText(m, ar1: 'دقيقة', ar2: 'دقيقتان', arFew: '$m دقائق', arMany: '$m دقيقة', en1: '1 min', en: '$m min');
  }
  if (m == 0) {
    return countText(h, ar1: 'ساعة', ar2: 'ساعتان', arFew: '$h ساعات', arMany: '$h ساعة', en1: '1 h', en: '$h h');
  }
  return t('$h س $m د', '$h h $m min');
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
  });

  final GamesReport? report;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

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
          title: t('لم تلعب أي لعبة بعد', 'You have not played a game yet'),
          message: t('العب لعبة من تبويب الألعاب لتجمع النجوم والشارات.', 'Play a game from the Games tab to collect stars and badges.'),
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
