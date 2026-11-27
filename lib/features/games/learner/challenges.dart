// lib/features/games/learner/challenges.dart — Games v4 T76: friends challenges and the class board (CONTRACT §8,
// kill switch `games.challenges`).
//
//   challengeAFriend(context, levelId)    makes a challenge from a level and opens the share sheet with its link
//   GamesChallengesPage                   My challenges + the class board (my course against the other courses)
//   ChallengePage(code)                   one challenge: who joined, their scores, the week's end, Play
//   challengeCodeFromRoute(route)         `/games/c/<code>` and the server's `/games/challenge/<code>` → the code
//
// A challenge fixes the level and the seed: Play joins it and opens the level with `draw {challenge: code}`, so every
// player gets the same items in the same order; Ghost Duel works on it as on any play. The scores on the board are
// the server's (each member's first play of that draw). The widgets with a View suffix take plain values.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// The kill switch of the challenges and the class board.
const kGamesChallengesKey = 'games.challenges';
bool gamesChallengesOff() => AppConfig.disableList.contains(kGamesChallengesKey);

/// `/games/c/<code>` (the app's own) or `/games/challenge/<code>` (the link the server gives) → the code.
String? challengeCodeFromRoute(String? route) {
  if (route == null) return null;
  final segs = (Uri.tryParse(route)?.pathSegments ?? const <String>[]).where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.first == 'app') segs.removeAt(0);
  if (segs.length == 3 && segs[0] == 'games' && (segs[1] == 'c' || segs[1] == 'challenge')) return segs[2];
  return null;
}

/// When the challenge's week ends: its `closes_at`, else its week start + 7 days (UTC, shown by [AppTime]).
DateTime? challengeEnds(Map<String, dynamic> raw) {
  final c = DateTime.tryParse('${raw['closes_at'] ?? ''}');
  if (c != null) return c.isUtc ? c : DateTime.utc(c.year, c.month, c.day, c.hour, c.minute, c.second);
  final w = DateTime.tryParse('${raw['week_start'] ?? ''}');
  return w == null ? null : DateTime.utc(w.year, w.month, w.day).add(const Duration(days: 7));
}

String _endsText(DateTime? e) => e == null ? '' : t('ينتهي ${AppTime.date(e)}', 'Ends ${AppTime.date(e)}');

String _levelName(V4Level? l) {
  if (l == null) return t('تحدٍّ', 'Challenge');
  final no = l.levelNo > 0 ? t('المستوى ${l.levelNo}', 'Level ${l.levelNo}') : t('مستوى', 'Level');
  final topic = l.topic;
  return topic == null || topic.isEmpty ? no : '$no · $topic';
}

/// Makes a challenge from the level [levelId] and shows its link in the app's share sheet.
Future<V4Challenge?> challengeAFriend(BuildContext context, int levelId, {GamesV4Api? api}) async {
  try {
    final c = await (api ?? GamesV4Api()).createChallenge(levelId);
    if (!context.mounted) return c;
    await shareChallenge(context, c);
    return c;
  } catch (e) {
    showAppNotice(gamesErrorText(e), error: true);
    return null;
  }
}

Future<void> shareChallenge(BuildContext context, V4Challenge c) {
  final url = c.link ?? '${appLinkOrigin()}/games/c/${c.code}';
  return showAppShareSheet(context,
      url: url,
      title: t('تحدّي أصدقائي', 'Challenge my friends'),
      subtitle: _levelName(c.game),
      kind: t('تحدٍّ', 'Challenge'),
      icon: Icons.emoji_events_rounded,
      hint: t('كل من يفتح الرابط يلعب نفس الأسئلة بنفس الترتيب', 'Everyone who opens it plays the same questions in the same order'));
}

/// Opens [c]'s level for play: joins first, then the level with the challenge's seed.
Future<void> playChallenge(BuildContext context, V4Challenge c, {GamesV4Api? api}) async {
  final a = api ?? GamesV4Api();
  final g = c.game;
  if (g == null) return;
  if (!c.joined) await a.joinChallenge(c.code);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    settings: RouteSettings(name: '/games/${g.id}'),
    builder: (_) => GamePlayPage(game: GameSummary.fromJson(g.raw), v4: a, challenge: c.code),
  ));
}

// ---------------------------------------------------------------- shared bits

class _Medal extends StatelessWidget {
  const _Medal(this.rank);
  final int rank;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = AgeThemeScope.of(context).palette;
    final top = rank >= 1 && rank <= 3;
    final color = top ? p.gold : c.divider;
    return Container(
      width: AppTouch.min - AppSpace.xs,
      height: AppTouch.min - AppSpace.xs,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: top ? Color.alphaBlend(p.gold.withValues(alpha: 0.28), c.cardBg) : Colors.transparent,
        border: Border.all(color: color, width: top ? AppBorder.strong : AppBorder.hairline),
      ),
      child: Text('$rank', style: AppType.figure(context)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final col = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: Color.alphaBlend(col.withValues(alpha: 0.14), context.colors.cardBg),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.sm, color: col), const SizedBox(width: AppSpace.xxs)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: col))),
      ]),
    );
  }
}

String _seconds(int ms) => t('${(ms / 1000).round()} ث', '${(ms / 1000).round()} s');

// ---------------------------------------------------------------- one challenge

class ChallengeView extends StatelessWidget {
  const ChallengeView({super.key, required this.challenge, this.ageBand, this.onPlay, this.onShare, this.busy = false});

  final V4Challenge challenge;
  final String? ageBand;
  final VoidCallback? onPlay, onShare;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = AgeTheme.of(context, band: ageBand);
    return AgeThemeScope(theme: theme, child: Builder(builder: (context) {
      final c = context.colors;
      final gold = theme.palette.gold;
      final ch = challenge;
      final board = ch.board;
      final kids = theme.age == GameAge.kids;
      return LayoutBuilder(builder: (context, box) {
        final gutter = AppSpace.gutter(box.maxWidth);
        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xl),
          children: [
            AppCard(
              highlight: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: AppTouch.primary,
                    height: AppTouch.primary,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.alphaBlend(gold.withValues(alpha: 0.25), c.cardBg),
                      border: Border.all(color: gold, width: kids ? AppBorder.strong : AppBorder.hairline),
                    ),
                    child: Icon(Icons.emoji_events_rounded, color: gold, size: AppIconSize.lg),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_levelName(ch.game), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
                      const SizedBox(height: AppSpace.xxs),
                      Text(t('تحدٍّ من ${ch.owner}', 'A challenge from ${ch.owner}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpace.sm),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  _Pill(ch.open ? t('مفتوح', 'Open') : t('انتهى', 'Closed'),
                      color: ch.open ? c.primary : c.textLight, icon: ch.open ? Icons.bolt_rounded : Icons.lock_clock_rounded),
                  if (challengeEnds(ch.raw) != null) _Pill(_endsText(challengeEnds(ch.raw)), color: c.textLight, icon: Icons.event_rounded),
                ]),
                const SizedBox(height: AppSpace.md),
                AppButton.primary(
                  key: const ValueKey('games.challenge.play'),
                  label: !ch.open ? t('انتهى التحدّي', 'Challenge closed') : (ch.joined ? t('العب الآن', 'Play now') : t('انضم والعب', 'Join and play')),
                  icon: Icons.play_arrow_rounded,
                  busy: busy,
                  expand: true,
                  onPressed: ch.open && ch.game != null ? onPlay : null,
                ),
                const SizedBox(height: AppSpace.xs),
                AppButton(
                  key: const ValueKey('games.challenge.share'),
                  label: t('شارك الرابط', 'Share the link'),
                  icon: Icons.ios_share_rounded,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: onShare,
                ),
              ]),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              countText(board.length,
                  ar1: 'لاعب واحد', ar2: 'لاعبان', arFew: '${board.length} لاعبين', arMany: '${board.length} لاعباً', en1: '1 player', en: '${board.length} players'),
              style: AppType.section(context),
            ),
            const SizedBox(height: AppSpace.xs),
            if (board.isEmpty)
              AppEmpty(
                key: const ValueKey('games.challenge.empty'),
                icon: Icons.groups_rounded,
                title: t('لم يلعب أحد بعد', 'No one has played yet'),
                message: t('كن أول من يضع رقماً على اللوحة', 'Be the first to put a score on the board'),
              )
            else
              for (final r in board) ...[_BoardRow(row: r), const SizedBox(height: AppSpace.xs)],
          ],
        );
      });
    }));
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = row['is_me'] == true;
    final score = row['score'];
    final max = row['max_score'];
    final ms = row['duration_ms'];
    final name = '${row['name'] ?? ''}';
    return Semantics(
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.primary),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: me ? Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.cardBg) : c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: me ? c.primary : c.divider, width: me ? AppBorder.strong : AppBorder.hairline),
        ),
        child: Row(children: [
          _Medal(row['rank'] is num ? (row['rank'] as num).toInt() : 0),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me ? '$name · ${t('أنت', 'You')}' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              if (ms is num && ms > 0) Text(_seconds(ms.toInt()), style: AppType.meta(context)),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Text(score == null ? '—' : (max == null ? '$score' : '$score / $max'), style: AppType.figure(context)),
        ]),
      ),
    );
  }
}

/// One challenge by its code (a shared link, a push, My challenges).
class ChallengePage extends StatefulWidget {
  const ChallengePage({super.key, required this.code, this.api, this.ageBand});
  final String code;
  final GamesV4Api? api;
  final String? ageBand;
  @override
  State<ChallengePage> createState() => _ChallengePageState();
}

class _ChallengePageState extends State<ChallengePage> {
  late final GamesV4Api _api = widget.api ?? GamesV4Api();
  V4Challenge? _c;
  String? _band, _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _band = widget.ageBand;
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _api.challenge(widget.code);
      String? band = _band;
      if (band == null) {
        try {
          band = (await _api.profile()).ageBand;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _c = c;
        _band = band;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = gamesErrorText(e));
    }
  }

  Future<void> _play() async {
    final c = _c;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      await playChallenge(context, c, api: _api);
    } catch (e) {
      if (mounted) showAppNotice(gamesErrorText(e), error: true);
    }
    if (mounted) {
      setState(() => _busy = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return SdArea(area: AppArea.games, child: BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('التحدّي', 'Challenge'), helpPageId: 'games.challenges'),
      child: SafeArea(
        child: c == null
            ? (_error != null
                ? AppErrorState(message: _error, onRetry: _load)
                : const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4, padding: EdgeInsets.zero)))
            : AppRefresh(
                onRefresh: _load,
                child: ChallengeView(challenge: c, ageBand: _band, busy: _busy, onPlay: _play, onShare: () => shareChallenge(context, c)),
              ),
      ),
    ));
  }
}

// ---------------------------------------------------------------- my challenges + class board

class MyChallengesView extends StatelessWidget {
  const MyChallengesView({super.key, required this.items, this.ageBand, this.onOpen, this.onNew});
  final List<V4Challenge> items;
  final String? ageBand;
  final ValueChanged<V4Challenge>? onOpen;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final theme = AgeTheme.of(context, band: ageBand);
    return AgeThemeScope(theme: theme, child: Builder(builder: (context) {
      final c = context.colors;
      final gold = theme.palette.gold;
      if (items.isEmpty) {
        return AppEmpty(
          key: const ValueKey('games.challenges.empty'),
          icon: Icons.emoji_events_rounded,
          title: t('لا تحدّيات بعد', 'No challenges yet'),
          message: t('اختر مستوى وتحدَّ أصدقاءك', 'Pick a level and challenge your friends'),
          actionLabel: onNew == null ? null : t('تحدٍّ جديد', 'New challenge'),
          onAction: onNew,
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final ch in items) ...[
          AppCard(
            key: ValueKey('games.challenge.${ch.code}'),
            onTap: onOpen == null ? null : () => onOpen!(ch),
            child: Row(children: [
              Icon(Icons.emoji_events_rounded, color: ch.open ? gold : c.textLight, size: AppIconSize.lg),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_levelName(ch.game), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text('${ch.owner} · ${ch.open ? _endsText(challengeEnds(ch.raw)) : t('انتهى', 'Closed')}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              if (ch.joined) _Pill(t('انضممت', 'Joined'), color: c.primary, icon: Icons.check_rounded),
            ]),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
      ]);
    }));
  }
}

class ClassBoardView extends StatelessWidget {
  const ClassBoardView({super.key, required this.board, this.ageBand});
  final V4ClassBoard board;
  final String? ageBand;

  @override
  Widget build(BuildContext context) {
    final theme = AgeTheme.of(context, band: ageBand);
    return AgeThemeScope(theme: theme, child: Builder(builder: (context) {
      final c = context.colors;
      final ws = DateTime.tryParse(board.weekStart ?? '');
      final mine = board.mine;
      final inList = board.items.any((r) => r['is_mine'] == true);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          ws == null
              ? t('هذا الأسبوع', 'This week')
              : t('أسبوع ${AppTime.wall(ws)}', 'Week of ${AppTime.wall(ws)}'),
          style: AppType.meta(context),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(t('متوسط نقاط الترتيب لكل لاعب نشط', 'Average rank points per active member'), style: AppType.body(context).copyWith(color: c.textLight)),
        const SizedBox(height: AppSpace.sm),
        if (board.items.isEmpty && mine == null)
          AppEmpty(
            key: const ValueKey('games.classboard.empty'),
            icon: Icons.groups_rounded,
            title: t('لا ترتيب بعد هذا الأسبوع', 'No ranking yet this week'),
            message: t('يظهر الصف بعد أن يلعب 3 طلاب ألعاباً مصنَّفة', 'A class appears once 3 students have played ranked games'),
          )
        else ...[
          if (mine != null && !inList) ...[_ClassRow(row: mine), const SizedBox(height: AppSpace.xs)],
          for (final r in board.items) ...[_ClassRow(row: r), const SizedBox(height: AppSpace.xs)],
        ],
      ]);
    }));
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = row['is_mine'] == true;
    final players = row['players'] is num ? (row['players'] as num).toInt() : 0;
    final avg = row['points_avg'] is num ? (row['points_avg'] as num).toDouble() : 0.0;
    final avgText = avg == avg.roundToDouble() ? '${avg.round()}' : avg.toStringAsFixed(1);
    return Container(
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: me ? Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.cardBg) : c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: me ? c.primary : c.divider, width: me ? AppBorder.strong : AppBorder.hairline),
      ),
      child: Row(children: [
        _Medal(row['rank'] is num ? (row['rank'] as num).toInt() : 0),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['title'] ?? ''}${me ? ' · ${t('صفّي', 'My class')}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text(
                countText(players,
                    ar1: 'لاعب نشط واحد', ar2: 'لاعبان نشطان', arFew: '$players لاعبين نشطين', arMany: '$players لاعباً نشطاً', en1: '1 active player', en: '$players active players'),
                style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Text(avgText, style: AppType.figure(context)),
      ]),
    );
  }
}

/// The games tab's "Challenges": My challenges, the class board and "New challenge".
class GamesChallengesPage extends StatefulWidget {
  const GamesChallengesPage({super.key, this.api, this.ageBand});
  final GamesV4Api? api;
  final String? ageBand;
  @override
  State<GamesChallengesPage> createState() => _GamesChallengesPageState();
}

class _GamesChallengesPageState extends State<GamesChallengesPage> {
  late final GamesV4Api _api = widget.api ?? GamesV4Api();
  int _tab = 0;
  List<V4Challenge>? _mine;
  V4ClassBoard? _board;
  List<MeCourseProgress> _courses = const [];
  int? _courseId;
  String? _error, _boardError;
  bool _boardLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMine();
    _loadCourses();
  }

  Future<void> _loadMine() async {
    try {
      final l = await _api.myChallenges();
      if (mounted) {
        setState(() {
        _mine = l;
        _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = gamesErrorText(e));
    }
  }

  Future<void> _loadCourses() async {
    try {
      await MeHomeService.instance.ensure();
    } catch (_) {}
    final cs = MeHomeService.instance.home?.coursesProgress ?? const <MeCourseProgress>[];
    if (!mounted) return;
    setState(() {
      _courses = cs;
      _courseId ??= cs.isEmpty ? null : cs.first.courseId;
    });
    if (_courseId != null) _loadBoard();
  }

  Future<void> _loadBoard() async {
    final id = _courseId;
    if (id == null) return;
    setState(() => _boardLoading = true);
    try {
      final b = await _api.classBoard(id);
      if (mounted) {
        setState(() {
        _board = b;
        _boardError = null;
        _boardLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _boardError = gamesErrorText(e);
        _boardLoading = false;
        });
      }
    }
  }

  Future<void> _new() async {
    final level = await showAppSheet<V4Level>(context, (ctx) => _LevelPicker(api: _api));
    if (level == null || !mounted) return;
    final c = await challengeAFriend(context, level.id, api: _api);
    if (c != null && mounted) _loadMine();
  }

  void _open(V4Challenge c) => Navigator.of(context)
      .push(MaterialPageRoute<void>(settings: RouteSettings(name: '/games/c/${c.code}'), builder: (_) => ChallengePage(code: c.code, api: _api, ageBand: widget.ageBand)))
      .then((_) {
    if (mounted) _loadMine();
  });

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_tab == 0) {
      body = _mine == null
          ? (_error != null
              ? AppErrorState(message: _error, onRetry: _loadMine)
              : const AppListSkeleton(items: 4, padding: EdgeInsets.zero))
          : MyChallengesView(items: _mine!, ageBand: widget.ageBand, onOpen: _open, onNew: _new);
    } else if (_courses.isEmpty) {
      body = AppEmpty(icon: Icons.school_rounded, title: t('لا صفوف بعد', 'No classes yet'), message: t('اشترك في دورة لترى ترتيب صفّك', "Join a course to see your class's ranking"));
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_courses.length > 1) ...[
          AppTabs(
            items: [for (final c in _courses) AppTabItem(AppConfig.lang == 'ar' ? c.nameAr : c.nameEn)],
            index: _courses.indexWhere((c) => c.courseId == _courseId).clamp(0, _courses.length - 1),
            onChanged: (i) {
              setState(() {
                _courseId = _courses[i].courseId;
                _board = null;
              });
              _loadBoard();
            },
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_board != null)
          ClassBoardView(board: _board!, ageBand: widget.ageBand)
        else if (_boardError != null)
          AppErrorState(message: _boardError, onRetry: _loadBoard)
        else
          const AppListSkeleton(items: 4, padding: EdgeInsets.zero),
      ]);
    }
    return SdArea(area: AppArea.games, child: BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('التحدّيات', 'Challenges'), helpPageId: 'games.challenges'),
      child: SdHeroColumn(title: 'sd_h_challenges'.tr, subtitle: 'sd_h_challenges_d'.tr, icon: Icons.bolt_rounded, child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final gutter = AppSpace.gutter(box.maxWidth);
          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xl),
            children: [
              AppTabs(
                items: [AppTabItem(t('تحدّياتي', 'My challenges')), AppTabItem(t('ترتيب الصفوف', 'Class board'))],
                index: _tab,
                expand: true,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: AppSpace.md),
              if (_tab == 0 && (_mine?.isNotEmpty ?? false)) ...[
                AppButton.primary(
                  key: const ValueKey('games.challenges.new'),
                  label: t('تحدٍّ جديد', 'New challenge'),
                  icon: Icons.add_rounded,
                  expand: true,
                  onPressed: _new,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (_boardLoading && _board == null) const SizedBox.shrink() else body,
            ],
          );
        }),
      )),
    ));
  }
}

/// A sheet of the learner's unlocked levels to challenge a friend on.
class _LevelPicker extends StatefulWidget {
  const _LevelPicker({required this.api});
  final GamesV4Api api;
  @override
  State<_LevelPicker> createState() => _LevelPickerState();
}

class _LevelPickerState extends State<_LevelPicker> {
  List<V4Level>? _levels;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.levels().then((l) {
      if (mounted) setState(() => _levels = [for (final x in l) if (!x.locked) x]);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = gamesErrorText(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ls = _levels;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('اختر المستوى', 'Pick the level'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.sm),
      if (ls == null)
        _error != null ? AppErrorState(message: _error, compact: true) : const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
      else if (ls.isEmpty)
        AppEmpty(icon: Icons.hourglass_empty_rounded, title: t('لا مستويات مفتوحة بعد', 'No unlocked levels yet'))
      else
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: ls.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
            itemBuilder: (_, i) => AppCard(
              onTap: () => Navigator.of(context).pop(ls[i]),
              child: Row(children: [
                Icon(Icons.emoji_events_rounded, color: context.colors.primary),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(_levelName(ls[i]), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
              ]),
            ),
          ),
        ),
    ]);
  }
}
