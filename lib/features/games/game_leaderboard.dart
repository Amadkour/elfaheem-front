// lib/features/games/game_leaderboard.dart — a game's leaderboard (Learning Hub v2 §3 + C9, D-1587): This week / All
// time, the top players by best score (then time) shown by first name and last initial with no avatar, the caller's
// own row pinned on top when it is not on the page, and "Show me on leaderboards" (PUT /me/games/leaderboard; a
// hidden student still sees their own rank). Kill switch `games.leaderboard` (the page does not draw it).
//
//   GameLeaderboardSection  loads GET /api/v1/games/{id}/leaderboard the first time it is drawn (never with the game),
//                           one load per period, again when [refresh] changes (a saved play)
//   GameLeaderboardView     the body with plain values (test/ui/games_v2_layout_test.dart)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

const List<String> kLeaderboardPeriods = ['week', 'all'];

class GameLeaderboardSection extends StatefulWidget {
  const GameLeaderboardSection({super.key, required this.gameId, required this.api, this.refresh = 0});

  final int gameId;
  final GamesApi api;

  /// Bump to load again (after a play was saved).
  final int refresh;

  @override
  State<GameLeaderboardSection> createState() => _GameLeaderboardSectionState();
}

class _GameLeaderboardSectionState extends State<GameLeaderboardSection> {
  int _period = 0;
  final Map<int, GameLeaderboard> _boards = {};
  String? _error;
  bool _loading = false;

  /// The caller's "Show me" (null = not known yet: the first board says).
  bool? _visible;
  bool _savingVisible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GameLeaderboardSection old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh || old.gameId != widget.gameId) {
      _boards.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final p = _period;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.api.leaderboard(widget.gameId, period: kLeaderboardPeriods[p]);
      if (!mounted) return;
      setState(() {
        _boards[p] = b;
        _visible ??= b.visible;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || p != _period) return;
      setState(() {
        _loading = false;
        _error = gamesErrorText(e);
      });
    }
  }

  void _onPeriod(int i) {
    if (i == _period) return;
    setState(() => _period = i);
    if (!_boards.containsKey(i)) _load();
  }

  Future<void> _setVisible(bool v) async {
    final before = _visible;
    setState(() {
      _visible = v;
      _savingVisible = true;
    });
    try {
      await widget.api.setLeaderboardVisible(v);
      if (!mounted) return;
      setState(() => _savingVisible = false);
      showAppNotice(v ? t('اسمك يظهر في لوحات المتصدرين', 'Your name shows on leaderboards') : t('اسمك مخفي عن الآخرين', 'Your name is hidden from others'));
      _boards.clear();
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _visible = before;
        _savingVisible = false;
      });
      showAppNotice(gamesErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => GameLeaderboardView(
        period: _period,
        onPeriod: _onPeriod,
        board: _boards[_period],
        loading: _loading && !_boards.containsKey(_period),
        error: _error,
        onRetry: _load,
        visible: _visible,
        onVisible: _savingVisible ? null : _setVisible,
      );
}

/// `1:05` from [seconds] (null = nothing).
String? gameTimeText(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class GameLeaderboardView extends StatelessWidget {
  const GameLeaderboardView({
    super.key,
    required this.period,
    required this.onPeriod,
    this.board,
    this.loading = false,
    this.error,
    this.onRetry,
    this.visible,
    this.onVisible,
  });

  /// 0 = this week, 1 = all time.
  final int period;
  final ValueChanged<int> onPeriod;
  final GameLeaderboard? board;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  /// "Show me on leaderboards" (null = not drawn).
  final bool? visible;
  final ValueChanged<bool>? onVisible;

  @override
  Widget build(BuildContext context) {
    final b = board;
    final Widget body;
    if (loading || (b == null && error == null)) {
      body = const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    } else if (b == null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (b.items.isEmpty && b.me == null) {
      body = AppEmpty(
        key: const ValueKey('games.board.empty'),
        icon: Icons.leaderboard_rounded,
        title: period == 0 ? t('لم يلعب أحد هذا الأسبوع بعد', 'Nobody has played this week yet') : t('لم يلعب أحد بعد', 'Nobody has played yet'),
        message: t('العب جولة لتظهر هنا.', 'Play a round to show up here.'),
      );
    } else {
      final me = b.me;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (me != null && !b.meListed) ...[
          GameLeaderRowTile(key: const ValueKey('games.board.me'), row: me, me: true),
          const SizedBox(height: AppSpace.xs),
        ],
        for (final r in b.items) ...[
          GameLeaderRowTile(
            key: ValueKey('games.board.row.${r.rank}'),
            row: r,
            me: me != null && r.rank == me.rank && r.name == me.name,
          ),
          const SizedBox(height: AppSpace.xxs),
        ],
      ]);
    }
    final v = visible;
    return Column(key: const ValueKey('games.board'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('لوحة المتصدرين', 'Leaderboard'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      AppTabs(
        items: [AppTabItem(t('هذا الأسبوع', 'This week')), AppTabItem(t('كل الأوقات', 'All time'))],
        index: period,
        onChanged: onPeriod,
        expand: true,
      ),
      const SizedBox(height: AppSpace.sm),
      body,
      if (v != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppSwitchTile(
          key: const ValueKey('games.board.visible'),
          title: t('أظهرني في لوحات المتصدرين', 'Show me on leaderboards'),
          subtitle: t('عند الإخفاء ترى ترتيبك وحدك.', 'When hidden, only you see your rank.'),
          icon: v ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          value: v,
          onChanged: onVisible,
        ),
      ],
    ]);
  }
}

/// One player: rank, the name as the server sends it (first name + last initial), stars, best score and time.
/// [me] = the caller's row.
class GameLeaderRowTile extends StatelessWidget {
  const GameLeaderRowTile({super.key, required this.row, this.me = false});

  final GameLeaderRow row;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = row.name.isEmpty ? t('طالب', 'Student') : row.name;
    final time = gameTimeText(row.durationS);
    return Semantics(
      label: [
        t('المركز ${row.rank}', 'Rank ${row.rank}'),
        if (me) t('أنت', 'You') else name,
        t('أفضل نتيجة ${row.bestScore}', 'Best score ${row.bestScore}'),
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: me ? c.primaryWash : c.cardBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: me ? c.primary : c.divider, width: AppBorder.hairline),
        ),
        child: Row(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: AppTouch.min),
            child: Text('${row.rank}', textAlign: TextAlign.center, style: AppType.section(context).copyWith(color: c.textMedium)),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me ? t('أنت · $name', 'You · $name') : name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              LearnStars(stars: row.stars, size: AppIconSize.sm),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${row.bestScore}', style: AppType.section(context)),
            if (time != null) Text(time, style: AppType.meta(context)),
          ]),
        ]),
      ),
    );
  }
}
