// lib/features/games/admin/v4/analytics_page.dart — SUPER ADMIN: Games analytics (Games v4 T70, CONTRACT §10).
//
//   GamesAnalyticsPage   loads overview + levels + hardest questions for 7 / 30 / 90 days
//   GamesAnalyticsBody   plain values: four KPI cards, plays by day (app_charts), the levels (a table when wide, cards
//                        on phones, sortable by plays / completion / score), the hardest questions (tap = the editor)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/admin_more_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/item_editor.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json, itemTypeName;

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _pct(Object? v) => '${_n(v).round()}%';
String _secs(Object? ms) => '${(_n(ms) / 1000).toStringAsFixed(1)}s';
String _title(Json l) => '${AppConfig.lang == 'ar' ? l['title_ar'] : l['title_en']}'.trim();
const SizedBox _tiny = SizedBox(height: AppSpace.xxs);

class GamesAnalyticsPage extends StatefulWidget {
  const GamesAnalyticsPage({super.key, this.api});
  final GamesAdminMoreApi? api;

  @override
  State<GamesAnalyticsPage> createState() => _GamesAnalyticsPageState();
}

class _GamesAnalyticsPageState extends State<GamesAnalyticsPage> {
  late final GamesAdminMoreApi _api = widget.api ?? GamesAdminMoreApi();
  int _days = 30;
  String _sort = 'plays';
  Json? _overview;
  List<Json> _levels = const [], _hardest = const [];
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final o = await _api.overview(_days);
      final l = await _api.levels(_days, _sort);
      final h = await _api.hardest();
      if (!mounted || seq != _seq) return;
      setState(() {
        _overview = o;
        _levels = l;
        _hardest = h;
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = adminMoreErrorText(e));
    }
  }

  Future<void> _resort(String s) async {
    setState(() => _sort = s);
    try {
      final l = await _api.levels(_days, s);
      if (mounted && _sort == s) setState(() => _levels = l);
    } catch (e) {
      showAppNotice(adminMoreErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: t('إحصاءات الألعاب', 'Games analytics'),
        subtitle: t('كم لُعب وكم أنهى الطلاب وأين يتعثرون', 'How much is played, finished, and where learners struggle'),
        icon: Icons.insights_rounded,
        onRefresh: _load,
        body: GamesAnalyticsBody(
          overview: _overview,
          levels: _levels,
          hardest: _hardest,
          error: _overview == null ? _error : null,
          onRetry: _load,
          days: _days,
          onDays: (d) {
            setState(() => _days = d);
            _load();
          },
          sort: _sort,
          onSort: _resort,
          onOpenItem: (id) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemEditorPage(itemId: id))),
        ),
      );
}

class GamesAnalyticsBody extends StatelessWidget {
  const GamesAnalyticsBody({
    super.key,
    required this.overview,
    this.levels = const [],
    this.hardest = const [],
    this.error,
    this.onRetry,
    this.days = 30,
    this.onDays,
    this.sort = 'plays',
    this.onSort,
    this.onOpenItem,
  });
  final Json? overview;
  final List<Json> levels, hardest;
  final String? error;
  final VoidCallback? onRetry;
  final int days;
  final ValueChanged<int>? onDays;
  final String sort;
  final ValueChanged<String>? onSort;
  final ValueChanged<int>? onOpenItem;

  @override
  Widget build(BuildContext context) {
    if (error != null) return AppErrorState(message: error!, onRetry: onRetry);
    final o = overview;
    if (o == null) return const AppListSkeleton(items: 4);
    final byDay = o['by_day'] is List ? [for (final d in o['by_day'] as List) if (d is Map) Map<String, dynamic>.from(d)] : <Json>[];
    final labels = [for (final d in byDay) '${d['day']}'.length >= 10 ? '${d['day']}'.substring(5) : '${d['day']}'];
    final kpis = [
      AppStatTile(icon: Icons.play_circle_rounded, label: t('مرات اللعب', 'Plays'), value: appCompactNumber(_n(o['plays']))),
      AppStatTile(icon: Icons.groups_rounded, label: t('اللاعبون', 'Players'), value: appCompactNumber(_n(o['players']))),
      AppStatTile(icon: Icons.flag_rounded, label: t('نسبة الإنهاء', 'Finished'), value: _pct(o['completion_pct'])),
      AppStatTile(icon: Icons.grade_rounded, label: t('متوسط الدرجة', 'Average score'), value: _pct(o['avg_score_pct'])),
    ];
    return ListView(padding: AdminPage.bodyPadding(context), children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final d in const [7, 30, 90]) AppChoiceChip(label: t('$d يوماً', 'Last $d days'), selected: days == d, onTap: () => onDays?.call(d)),
      ]),
      AppSpace.gapMd,
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 420 ? 2 : 1);
        final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
        return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final k in kpis) SizedBox(width: w, child: k)]);
      }),
      AppSpace.gapLg,
      Text(t('اللعب يوماً بيوم', 'Plays by day'), style: AppType.section(context)),
      AppSpace.gapXs,
      AppCard(
        child: byDay.isEmpty
            ? Padding(padding: const EdgeInsets.all(AppSpace.md), child: Text(t('لا بيانات في هذه الفترة', 'No data in this period'), style: AppType.meta(context)))
            : AppBarChart(
                title: t('اللعب يوماً بيوم', 'Plays by day'),
                labels: labels,
                integerAxis: true,
                series: [
                  AppChartSeries(t('بدأ', 'Started'), [for (final d in byDay) _n(d['starts']).toDouble()]),
                  AppChartSeries(t('أنهى', 'Finished'), [for (final d in byDay) _n(d['finishes']).toDouble()]),
                ],
              ),
      ),
      AppSpace.gapLg,
      Text(t('المستويات', 'Levels'), style: AppType.section(context)),
      AppSpace.gapXs,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final s in const ['plays', 'completion', 'score'])
          AppChoiceChip(
            label: switch (s) {
              'plays' => t('الأكثر لعباً', 'Most played'),
              'completion' => t('الإنهاء', 'Completion'),
              _ => t('الدرجة', 'Score'),
            },
            selected: sort == s,
            onTap: () => onSort?.call(s),
          ),
      ]),
      AppSpace.gapSm,
      if (levels.isEmpty)
        AppEmpty(icon: Icons.stairs_rounded, title: t('لا مستويات لُعبت بعد', 'No level has been played yet'))
      else
        LayoutBuilder(builder: (context, box) => box.maxWidth >= 720 ? _LevelsTable(levels: levels) : _LevelCards(levels: levels)),
      AppSpace.gapLg,
      Text(t('أصعب الأسئلة', 'Hardest questions'), style: AppType.section(context)),
      AppSpace.gapXs,
      Text(t('الأسئلة التي يخطئ فيها الطلاب أكثر. افتح السؤال لتعديله.', 'The questions learners miss most. Open one to edit it.'), style: AppType.meta(context)),
      AppSpace.gapSm,
      if (hardest.isEmpty)
        AppEmpty(icon: Icons.quiz_rounded, title: t('لا أسئلة كافية بعد', 'Not enough answers yet'))
      else
        for (final h in hardest)
          AppCard(
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            onTap: onOpenItem == null ? null : () => onOpenItem!(_n(h['id']).toInt()),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h['prompt'] ?? ''}', style: AppType.body(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                  _tiny,
                  Text(
                    [itemTypeName('${h['type']}'), '${h['subject'] ?? ''}', '${h['topic'] ?? ''}', t('عُرض ${_n(h['shown'])} مرة', 'Shown ${_n(h['shown'])} times')]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: AppType.meta(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              AppSpace.gapSm,
              AppStatusBadge(label: t('${_pct(h['correct_pct'])} صحيح', '${_pct(h['correct_pct'])} right'), tone: AppTone.danger, dense: true),
            ]),
          ),
    ]);
  }
}

class _LevelsTable extends StatelessWidget {
  const _LevelsTable({required this.levels});
  final List<Json> levels;

  @override
  Widget build(BuildContext context) {
    Widget cell(String s, {int flex = 1, TextStyle? style}) =>
        Expanded(flex: flex, child: Text(s, style: style ?? AppType.body(context), maxLines: 1, overflow: TextOverflow.ellipsis));
    final h = AppType.meta(context);
    return AppCard(
      child: Column(children: [
        Row(children: [
          cell(t('المستوى', 'Level'), flex: 4, style: h),
          cell(t('بدأ', 'Started'), style: h),
          cell(t('أنهى', 'Finished'), style: h),
          cell(t('الإنهاء', 'Completion'), style: h),
          cell(t('الدرجة', 'Score'), style: h),
          cell(t('الوقت', 'Time'), style: h),
        ]),
        for (final l in levels)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Row(children: [
              cell(_title(l), flex: 4),
              cell('${_n(l['starts'])}'),
              cell('${_n(l['finishes'])}'),
              cell(_pct(l['completion_pct'])),
              cell(_pct(l['avg_score_pct'])),
              cell(_secs(l['avg_ms'])),
            ]),
          ),
      ]),
    );
  }
}

class _LevelCards extends StatelessWidget {
  const _LevelCards({required this.levels});
  final List<Json> levels;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final l in levels)
          AppCard(
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(l), style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              _tiny,
              Text(
                t('بدأ ${_n(l['starts'])} · أنهى ${_n(l['finishes'])} · إنهاء ${_pct(l['completion_pct'])}',
                    'Started ${_n(l['starts'])} · finished ${_n(l['finishes'])} · completion ${_pct(l['completion_pct'])}'),
                style: AppType.meta(context),
              ),
              Text(t('الدرجة ${_pct(l['avg_score_pct'])} · الوقت ${_secs(l['avg_ms'])}', 'Score ${_pct(l['avg_score_pct'])} · time ${_secs(l['avg_ms'])}'),
                  style: AppType.meta(context)),
            ]),
          ),
      ]);
}
