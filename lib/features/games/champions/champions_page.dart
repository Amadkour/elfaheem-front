// lib/features/games/champions/champions_page.dart — the Hall of Champions (Games v3 §2.4, CONTRACT §6; kill switch
// `games.champions`, help page `games.champions`).
//
//   HallOfChampionsPage  the page: the scope chips (Everyone · a category · My organization, from the server's
//                        `scopes`), Today / This week / Past winners. Today and This week load GET
//                        /games/champions/standings once per scope and period; Past winners GET /games/champions
//                        (10 periods a page). The countdown to the period's end ticks every 30 s.
//   HallOfChampionsView  the body with plain values (test/ui/champions_layout_test.dart)
//   ChampionsPodium      the top 3: an initial in a theme tone on a step (no avatar, D-1770)
//   ChampionRowTile      one row of the standings (rank · "First L." · games · points); mine is tinted
//
// Tone (ANALYSIS.md): modest. No "you lost your place", no red for a low rank; what I still lack to enter is said
// plainly ("2 more games today").
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_api.dart';
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/games_models.dart' show kGameCategories;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// The chips before the server named them: Everyone and the five categories (an organization chip comes with the
/// first answer of GET /games/champions).
final List<ChampionScope> kDefaultChampionScopes = [
  ChampionScope.platform,
  for (final k in kGameCategories) ChampionScope(scope: 'category', key: k),
];

String championsGamesText(int n) => countText(n,
    ar1: 'لعبة واحدة', ar2: 'لعبتان', arFew: '$n ألعاب', arMany: '$n لعبة', en1: '1 game', en: '$n games');

String championsPointsText(int n) => countText(n,
    ar1: 'نقطة واحدة', ar2: 'نقطتان', arFew: '$n نقاط', arMany: '$n نقطة', en1: '1 point', en: '$n points');

String championsDaysText(int n) => countText(n,
    ar1: 'يوم واحد', ar2: 'يومان', arFew: '$n أيام', arMany: '$n يوماً', en1: '1 day', en: '$n days');

/// "Ends in 5 h 12 min" (days for a week), or "Ended".
String championsCountdownText(Duration left) {
  if (left <= Duration.zero) return t('انتهت الفترة', 'This period has ended');
  final d = left.inDays, h = left.inHours % 24, m = left.inMinutes % 60;
  if (d > 0) return t('تنتهي بعد $d ي $h س', 'Ends in $d d $h h');
  if (h > 0) return t('تنتهي بعد $h س $m د', 'Ends in $h h $m min');
  return t('تنتهي بعد ${m < 1 ? 1 : m} د', 'Ends in ${m < 1 ? 1 : m} min');
}

/// What I still lack to enter, in one sentence (null = nothing).
String? championsNeedsText(ChampionStandings s) {
  if (s.eligible || s.me == null) return null;
  final parts = [
    if (s.needGames > 0) t('${championsGamesText(s.needGames)} أخرى', '${championsGamesText(s.needGames)} more'),
    if (s.needDays > 0) t('${championsDaysText(s.needDays)} لعب أخرى', '${championsDaysText(s.needDays)} of play more'),
  ];
  if (parts.isEmpty) return null;
  return s.period == 'weekly'
      ? t('لتدخل لوحة هذا الأسبوع: ${parts.join(' و')}', 'To enter this week\'s board: ${parts.join(' and ')}')
      : t('لتدخل لوحة اليوم: ${parts.join(' و')}', 'To enter today\'s board: ${parts.join(' and ')}');
}

class HallOfChampionsPage extends StatefulWidget {
  const HallOfChampionsPage({super.key, this.api, this.scope, this.tab = 0});

  final ChampionsApi? api;

  /// The scope to open on (a notification names it), else Everyone.
  final ChampionScope? scope;

  /// 0 = Today, 1 = This week, 2 = Past winners.
  final int tab;

  @override
  State<HallOfChampionsPage> createState() => _HallOfChampionsPageState();
}

class _HallOfChampionsPageState extends State<HallOfChampionsPage> {
  late final ChampionsApi _api = widget.api ?? ChampionsApi();
  late ChampionScope _scope = widget.scope ?? ChampionScope.platform;
  late int _tab = widget.tab.clamp(0, 2);
  String _pastPeriod = 'daily';
  List<ChampionScope> _scopes = kDefaultChampionScopes;

  final Map<String, ChampionStandings> _boards = {};
  final Map<String, ChampionHistory> _past = {};
  String? _error;
  bool _loading = false, _loadingMore = false;
  Timer? _clock;
  StreamSubscription<LiveEvent>? _events;

  String get _boardKey => '${_scope.id}|${kChampionPeriods[_tab.clamp(0, 1)]}';
  String get _pastKey => '${_scope.id}|$_pastPeriod';

  @override
  void initState() {
    super.initState();
    _load();
    // the scope chips: the first page of past winners names them (an organization chip only comes from there)
    if (_tab != 2) _loadPast(chipsOnly: true);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // a period was computed (I or someone else won): the boards are stale
    _events = LiveEvents.instance.listen({LiveEvents.gamesChampions}, (_) {
      _boards.clear();
      _past.clear();
      _load();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _events?.cancel();
    super.dispose();
  }

  Future<void> _load() async => _tab == 2 ? _loadPast() : _loadBoard();

  Future<void> _loadBoard() async {
    final key = _boardKey;
    if (_boards.containsKey(key)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await _api.standings(_scope, period: kChampionPeriods[_tab]);
      if (!mounted) return;
      setState(() {
        _boards[key] = b;
        if (key == _boardKey) _loading = false;
      });
    } catch (e) {
      if (!mounted || key != _boardKey) return;
      setState(() {
        _loading = false;
        _error = championsErrorText(e);
      });
    }
  }

  Future<void> _loadPast({bool chipsOnly = false, bool more = false}) async {
    final key = _pastKey;
    final had = _past[key];
    if (had != null && !more) return;
    if (!chipsOnly) {
      setState(() {
        if (more) {
          _loadingMore = true;
        } else {
          _loading = true;
        }
        _error = null;
      });
    }
    try {
      final h = await _api.history(_scope, period: _pastPeriod, page: more ? (had?.page ?? 1) + 1 : 1);
      if (!mounted) return;
      setState(() {
        if (h.scopes.isNotEmpty) _scopes = h.scopes;
        _past[key] = more && had != null
            ? ChampionHistory(items: [...had.items, ...h.items], page: h.page, total: h.total, hasMore: h.hasMore, scopes: h.scopes)
            : h;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || chipsOnly) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (more) {
          showAppNotice(championsErrorText(e), error: true);
        } else {
          _error = championsErrorText(e);
        }
      });
    }
  }

  Future<void> _refresh() async {
    if (_tab == 2) {
      _past.remove(_pastKey);
    } else {
      _boards.remove(_boardKey);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final board = _tab == 2 ? null : _boards[_boardKey];
    final past = _tab == 2 ? _past[_pastKey] : null;
    return SdArea(area: AppArea.games, child: BasePage(
      key: const ValueKey(kGamesChampionsKey),
      width: AppWidth.content,
      appBar: ScreenAppBar(title: t('لوحة الأبطال', 'Hall of Champions'), helpPageId: 'games.champions'),
      child: SdHeroColumn(title: 'sd_h_champions'.tr, subtitle: 'sd_h_champions_d'.tr, icon: Icons.emoji_events_outlined, child: SafeArea(
        child: HallOfChampionsView(
          scopes: _scopes,
          scope: _scope,
          onScope: (s) {
            if (s == _scope) return;
            setState(() => _scope = s);
            _load();
          },
          tab: _tab,
          onTab: (i) {
            if (i == _tab) return;
            setState(() => _tab = i);
            _load();
          },
          standings: board,
          history: past,
          pastPeriod: _pastPeriod,
          onPastPeriod: (p) {
            if (p == _pastPeriod) return;
            setState(() => _pastPeriod = p);
            _loadPast();
          },
          loading: _loading && (_tab == 2 ? past == null : board == null),
          loadingMore: _loadingMore,
          error: (_tab == 2 ? past == null : board == null) ? _error : null,
          onRetry: _load,
          onRefresh: _refresh,
          onMore: past != null && past.hasMore && !_loadingMore ? () => _loadPast(more: true) : null,
          now: DateTime.now().toUtc(),
        ),
      )),
    ));
  }
}

class HallOfChampionsView extends StatelessWidget {
  const HallOfChampionsView({
    super.key,
    required this.scopes,
    required this.scope,
    required this.tab,
    required this.now,
    this.onScope,
    this.onTab,
    this.standings,
    this.history,
    this.pastPeriod = 'daily',
    this.onPastPeriod,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.onRetry,
    this.onRefresh,
    this.onMore,
  });

  final List<ChampionScope> scopes;
  final ChampionScope scope;
  final ValueChanged<ChampionScope>? onScope;

  /// 0 = Today, 1 = This week, 2 = Past winners.
  final int tab;
  final ValueChanged<int>? onTab;
  final ChampionStandings? standings;
  final ChampionHistory? history;
  final String pastPeriod;
  final ValueChanged<String>? onPastPeriod;
  final bool loading, loadingMore;
  final String? error;
  final VoidCallback? onRetry, onMore;
  final Future<void> Function()? onRefresh;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final head = <Widget>[
      SingleChildScrollView(
        key: const ValueKey('champions.scopes'),
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final s in scopes) ...[
            AppChoiceChip(
              key: ValueKey('champions.scope.${s.id}'),
              label: s.name,
              icon: s.scope == 'org' ? Icons.account_balance_rounded : (s.scope == 'platform' ? Icons.public_rounded : null),
              selected: s == scope,
              onTap: () => onScope?.call(s),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      AppTabs(
        items: [
          AppTabItem(t('اليوم', 'Today')),
          AppTabItem(t('هذا الأسبوع', 'This week')),
          AppTabItem(t('الأبطال السابقون', 'Past winners')),
        ],
        index: tab,
        onChanged: (i) => onTab?.call(i),
        expand: true,
      ),
      const SizedBox(height: AppSpace.md),
    ];
    final Widget body;
    if (loading) {
      body = const AppListSkeleton(items: 5, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (tab == 2) {
      body = _PastWinners(history: history, period: pastPeriod, onPeriod: onPastPeriod, onMore: onMore, loadingMore: loadingMore);
    } else {
      final s = standings;
      body = s == null ? const SizedBox.shrink() : ChampionStandingsView(standings: s, now: now);
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [...head, body, const SizedBox(height: AppSpace.lg)],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

/// The running period: the countdown, the podium, my status, the standings (my row pinned when it is not listed).
class ChampionStandingsView extends StatelessWidget {
  const ChampionStandingsView({super.key, required this.standings, required this.now});

  final ChampionStandings standings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = standings;
    final c = context.colors;
    final end = s.periodEnd;
    final weekly = s.period == 'weekly';
    final needs = championsNeedsText(s);
    final me = s.me;
    final rest = s.items.skip(3).toList();
    return Column(key: const ValueKey('champions.standings'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (end != null)
        Semantics(
          liveRegion: false,
          child: Row(children: [
            Icon(Icons.schedule_rounded, size: AppIconSize.sm, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                '${championsCountdownText(end.difference(now))} · ${weekly ? AppTime.dateTime(end) : AppTime.time(end)}',
                key: const ValueKey('champions.countdown'),
                style: AppType.meta(context),
              ),
            ),
          ]),
        ),
      const SizedBox(height: AppSpace.sm),
      if (s.items.isEmpty)
        AppEmpty(
          key: const ValueKey('champions.empty'),
          icon: Icons.emoji_events_rounded,
          tone: AppBlockTone.gold,
          title: weekly ? t('لا بطل لهذا الأسبوع بعد', 'No champion this week yet') : t('لا بطل لليوم بعد', 'No champion today yet'),
          message: weekly
              ? t('العب ${championsGamesText(s.minGames)} مختلفة في ${championsDaysText(s.minDays)} على الأقل لتدخل اللوحة.',
                  'Play ${championsGamesText(s.minGames)} on at least ${championsDaysText(s.minDays)} to enter the board.')
              : t('العب ${championsGamesText(s.minGames)} مختلفة اليوم لتدخل اللوحة.', 'Play ${championsGamesText(s.minGames)} today to enter the board.'),
        )
      else
        ChampionsPodium(rows: s.podium),
      if (needs != null || (me != null && s.eligible) || !s.visible) ...[
        const SizedBox(height: AppSpace.md),
        AppCard(
          key: const ValueKey('champions.me'),
          child: Row(children: [
            Icon(s.eligible ? Icons.military_tech_rounded : Icons.flag_rounded,
                color: s.eligible ? appToneColor(context, AppTone.gold) : c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (me != null && s.eligible && me.rank != null)
                  Text(t('ترتيبك الآن: ${me.rank} من ${s.total}', 'You are number ${me.rank} of ${s.total} now'),
                      style: AppType.bodyStrong(context)),
                if (needs != null) Text(needs, style: AppType.body(context)),
                if (!s.visible)
                  Text(t('اسمك مخفي عن الآخرين، فلا تدخل لوحة الأبطال.', 'Your name is hidden from others, so you are not on the champions\' board.'),
                      style: AppType.meta(context)),
              ]),
            ),
          ]),
        ),
      ],
      if (rest.isNotEmpty || (me != null && !s.meListed && s.items.isNotEmpty)) ...[
        const SizedBox(height: AppSpace.md),
        Text(t('الترتيب', 'Standings'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        if (me != null && !s.meListed) ...[
          ChampionRowTile(key: const ValueKey('champions.row.me'), row: me),
          const SizedBox(height: AppSpace.xs),
        ],
        for (final r in rest) ...[
          ChampionRowTile(key: ValueKey('champions.row.${r.rank}'), row: r),
          const SizedBox(height: AppSpace.xxs),
        ],
      ],
    ]);
  }
}

/// The podium tone of a rank: gold for the first (achievements only), then sage and peach.
AppBlockTone championTone(int? rank) => switch (rank) {
      1 => AppBlockTone.gold,
      2 => AppBlockTone.sage,
      _ => AppBlockTone.peach,
    };

/// The top 3 on steps: 2 · 1 · 3 (the first in the middle and highest). Fewer than 3 rows draw what there is.
class ChampionsPodium extends StatelessWidget {
  const ChampionsPodium({super.key, required this.rows});

  final List<ChampionRow> rows;

  @override
  Widget build(BuildContext context) {
    ChampionRow? at(int i) => i < rows.length ? rows[i] : null;
    final order = [at(1), at(0), at(2)];
    const steps = [AppSpace.xl, AppSpace.xxl + AppSpace.md, AppSpace.lg];
    return Semantics(
      container: true,
      label: t('المنصة', 'Podium'),
      child: Row(
        key: const ValueKey('champions.podium'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: order[i] == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                      child: _PodiumStep(row: order[i]!, step: steps[i], first: i == 1),
                    ),
            ),
        ],
      ),
    );
  }
}

class _PodiumStep extends StatelessWidget {
  const _PodiumStep({required this.row, required this.step, required this.first});

  final ChampionRow row;
  final double step;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = AppBlockColors.of(context, championTone(row.rank));
    final size = first ? AppTouch.primary + AppSpace.sm : AppTouch.primary;
    final name = row.name.isEmpty ? t('طالب', 'Student') : row.name;
    return Semantics(
      label: [
        t('المركز ${row.rank ?? ''}', 'Rank ${row.rank ?? ''}'),
        if (row.isMe) t('أنت', 'You') else name,
        championsPointsText(row.points),
      ].join(', '),
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (first) Icon(Icons.emoji_events_rounded, color: appToneColor(context, AppTone.gold), size: AppIconSize.lg),
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.surface,
            shape: BoxShape.circle,
            border: Border.all(color: row.isMe ? c.primary : (tone.border ?? c.divider), width: row.isMe ? AppBorder.focus : AppBorder.hairline),
          ),
          child: Text(row.initial, style: AppType.headline(context).copyWith(color: tone.ink)),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(row.isMe ? t('أنت', 'You') : name,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.row(context)),
        Text(championsPointsText(row.points),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xs),
        Container(
          height: step,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.control)),
            border: Border.all(color: tone.border ?? c.divider, width: AppBorder.hairline),
          ),
          child: Text('${row.rank ?? ''}', style: AppType.section(context).copyWith(color: tone.ink)),
        ),
      ]),
    );
  }
}

/// One player of the standings: rank, "First L." (or "You · …"), the games played, the points.
class ChampionRowTile extends StatelessWidget {
  const ChampionRowTile({super.key, required this.row});

  final ChampionRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = row.name.isEmpty ? t('طالب', 'Student') : row.name;
    final me = row.isMe;
    return Semantics(
      label: [
        if (row.rank != null) t('المركز ${row.rank}', 'Rank ${row.rank}'),
        if (me) t('أنت', 'You') else name,
        championsGamesText(row.games),
        championsPointsText(row.points),
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: me ? c.primaryWash : c.cardBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: me ? c.primary : c.divider, width: AppBorder.hairline),
        ),
        child: Row(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: AppTouch.min),
            child: Text(row.rank == null ? '–' : '${row.rank}',
                textAlign: TextAlign.center, style: AppType.section(context).copyWith(color: c.textMedium)),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me ? t('أنت · $name', 'You · $name') : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              Text(championsGamesText(row.games), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            flex: 0,
            child: Text('${row.points}', style: AppType.section(context)),
          ),
        ]),
      ),
    );
  }
}

class _PastWinners extends StatelessWidget {
  const _PastWinners({required this.history, required this.period, this.onPeriod, this.onMore, this.loadingMore = false});

  final ChampionHistory? history;
  final String period;
  final ValueChanged<String>? onPeriod;
  final VoidCallback? onMore;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final h = history;
    final c = context.colors;
    return Column(key: const ValueKey('champions.past'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(
            key: const ValueKey('champions.past.daily'),
            label: t('أبطال الأيام', 'Daily'),
            selected: period == 'daily',
            onTap: () => onPeriod?.call('daily')),
        AppChoiceChip(
            key: const ValueKey('champions.past.weekly'),
            label: t('أبطال الأسابيع', 'Weekly'),
            selected: period == 'weekly',
            onTap: () => onPeriod?.call('weekly')),
      ]),
      const SizedBox(height: AppSpace.sm),
      if (h == null || h.items.isEmpty)
        AppEmpty(
          key: const ValueKey('champions.past.empty'),
          icon: Icons.emoji_events_outlined,
          tone: AppBlockTone.gold,
          title: t('لا أبطال سابقون بعد', 'No past winners yet'),
          message: t('يظهر هنا أبطال كل فترة بعد انتهائها.', 'Each period\'s winners show here once it ends.'),
        )
      else
        for (final p in h.items) ...[
          AppCard(
            key: ValueKey('champions.period.${p.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                p.kind == 'weekly' && p.start != null && p.end != null
                    ? '${AppTime.date(p.start!)} – ${AppTime.date(p.end!.subtract(const Duration(minutes: 1)))}'
                    : (p.start == null ? '' : AppTime.date(p.start!)),
                style: AppType.bodyStrong(context),
              ),
              const SizedBox(height: AppSpace.xs),
              if (p.empty)
                Text(t('لا بطل: لم يكتمل عدد اللاعبين', 'No champion: not enough players'),
                    style: AppType.meta(context).copyWith(color: c.textMedium))
              else
                for (final w in p.winners)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Row(children: [
                      Icon(Icons.military_tech_rounded, size: AppIconSize.sm, color: AppBlockColors.of(context, championTone(w.rank)).ink),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          '${w.rank ?? ''}. ${w.isMe ? t('أنت · ${w.name}', 'You · ${w.name}') : w.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.row(context),
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Text(championsPointsText(w.points), style: AppType.meta(context)),
                    ]),
                  ),
            ]),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
      if (onMore != null || loadingMore)
        AppButton.ghost(
          key: const ValueKey('champions.past.more'),
          label: t('عرض المزيد', 'Show more'),
          busy: loadingMore,
          onPressed: onMore,
        ),
    ]);
  }
}
