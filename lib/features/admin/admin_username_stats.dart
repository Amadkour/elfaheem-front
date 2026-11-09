// lib/features/admin/admin_username_stats.dart
//
// Admin → Support & security → "Usernames" (D-076): is the optional @username (D-071 / D-073) being used?
//
//   GET /api/v1/admin/usernames/stats?days=7|30|90  (admin / super admin; server: services/username_stats.py)
//
//   UsernameStats.fromJson   the payload, every key optional (an older / partial server reads as zeros)
//   usernameTrend            the daily series folded into at most [kUsernameTrendBars] bars (pure, unit-tested)
//   UsernameStatsContent     plain values → the page body (window chips, snapshot tiles + donut, prompt answers,
//                            sign-in methods, daily trend); what the layout harness pumps
//   AdminUsernameStatsPage   loads, AppListSkeleton while loading, AppEmpty + retry on an error, a "needs a server
//                            update" banner on a bare 404 / 405
//
// Kill switch `admin.username_stats` (the hub entry). Tests: test/org/username_stats_test.dart,
// test/ui/username_stats_layout_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/plural.dart' show daysText;

import '../org/org_v3.dart' show orgCall, orgErrorText;
import 'admin_common.dart' show asMap, t;
import 'admin_page.dart';

const kUsernameStatsFeatureKey = 'admin.username_stats';
const kUsernameStatsPath = '/api/v1/admin/usernames/stats';
const kUsernameStatsWindows = [7, 30, 90];
const kUsernameTrendBars = 10;

// ── Model ────────────────────────────────────────────────────────────────────

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

Map<String, int> _counts(dynamic v) => {for (final e in asMap(v).entries) e.key: _int(e.value)};

class UsernameStatsDay {
  const UsernameStatsDay({required this.date, this.events = const {}, this.logins = const {}});

  factory UsernameStatsDay.fromJson(Map<String, dynamic> j) =>
      UsernameStatsDay(date: '${j['date'] ?? ''}', events: _counts(j['events']), logins: _counts(j['logins']));

  /// "YYYY-MM-DD" (a UTC day).
  final String date;
  final Map<String, int> events;
  final Map<String, int> logins;

  int event(String k) => events[k] ?? 0;

  /// The keep-or-change prompt answered (kept · changed · removed).
  int get answered => event('confirmed_kept') + event('confirmed_changed') + event('confirmed_removed');

  /// A name the person typed: at sign-up or later in the profile.
  int get newNames => event('chosen_at_signup') + event('set_in_profile');

  int get usernameLogins => logins['username'] ?? 0;
}

class UsernameStats {
  const UsernameStats({
    this.days = 30,
    this.usersTotal = 0,
    this.withUsername = 0,
    this.confirmed = 0,
    this.pending = 0,
    this.without = 0,
    this.flows = const {},
    this.logins = const {},
    this.daily = const [],
    this.promptConversion,
  });

  factory UsernameStats.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['snapshot']);
    final conv = j['prompt_conversion'];
    return UsernameStats(
      days: j['days'] == null ? 30 : _int(j['days']),
      usersTotal: _int(s['users_total']),
      withUsername: _int(s['with_username']),
      confirmed: _int(s['confirmed']),
      pending: _int(s['unconfirmed_pending']),
      without: _int(s['without']),
      flows: _counts(j['flows']),
      logins: _counts(j['logins_by_kind']),
      daily: [
        for (final d in (j['daily'] is List ? j['daily'] as List : const []))
          if (d is Map) UsernameStatsDay.fromJson(asMap(d)),
      ],
      promptConversion: conv is num ? conv.toDouble().clamp(0.0, 1.0) : null,
    );
  }

  final int days;
  final int usersTotal, withUsername, confirmed, pending, without;
  final Map<String, int> flows;
  final Map<String, int> logins;
  final List<UsernameStatsDay> daily;

  /// 0–1; null when nobody was ever asked (the server leaves it out).
  final double? promptConversion;

  int flow(String k) => flows[k] ?? 0;
  int login(String k) => logins[k] ?? 0;
  int get answered => flow('kept') + flow('changed') + flow('removed');
  int get loginsTotal => logins.values.fold(0, (a, b) => a + b);

  /// Share of accounts with a username, 0–1 (0 without accounts).
  double get usernameShare => usersTotal <= 0 ? 0 : withUsername / usersTotal;
}

/// One bar of the trend: the first day it covers and its sums.
class UsernameTrendBar {
  const UsernameTrendBar(this.firstDate, this.answered, this.newNames, this.usernameLogins);
  final String firstDate;
  final int answered, newNames, usernameLogins;
}

/// [days] folded into at most [maxBars] bars of equal length (oldest first; the last bar may be shorter).
List<UsernameTrendBar> usernameTrend(List<UsernameStatsDay> days, {int maxBars = kUsernameTrendBars}) {
  if (days.isEmpty) return const [];
  final size = (days.length / math.max(1, maxBars)).ceil();
  return [
    for (var i = 0; i < days.length; i += size)
      () {
        final part = days.sublist(i, math.min(i + size, days.length));
        return UsernameTrendBar(
          part.first.date,
          part.fold(0, (a, d) => a + d.answered),
          part.fold(0, (a, d) => a + d.newNames),
          part.fold(0, (a, d) => a + d.usernameLogins),
        );
      }(),
  ];
}

/// "2026-10-28" → "28 Oct" / "28 أكتوبر" (a UTC calendar day; noon keeps it on the same date in every zone).
String usernameDayLabel(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return AppTime.date(DateTime.utc(d.year, d.month, d.day, 12), pattern: 'd MMM');
}

String _pct(double v) => '${(v * 100).round()}%';

// ── Page ─────────────────────────────────────────────────────────────────────

class AdminUsernameStatsPage extends StatefulWidget {
  const AdminUsernameStatsPage({super.key});

  @override
  State<AdminUsernameStatsPage> createState() => _AdminUsernameStatsPageState();
}

class _AdminUsernameStatsPageState extends State<AdminUsernameStatsPage> {
  int _days = 30;
  UsernameStats? _stats;
  String? _error;
  bool _missing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final days = _days;
    final r = await orgCall(() => ApiClient().get(kUsernameStatsPath, queryParams: {'days': days}), quiet: true);
    if (!mounted || days != _days) return;
    setState(() {
      _loading = false;
      _missing = !r.ok && r.endpointMissing;
      _error = r.ok || _missing ? null : orgErrorText(r.error!);
      if (r.ok) _stats = UsernameStats.fromJson(r.map);
    });
  }

  void _pick(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = t('أسماء المستخدمين', 'Usernames');
    Widget body;
    if (_missing) {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        AppBanner(
          icon: Icons.system_update_alt_rounded,
          text: t('هذه الصفحة تحتاج تحديث الخادم.', 'This page needs a server update.'),
        ),
      ]);
    } else if (_error != null && _stats == null) {
      body = AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: t('إعادة المحاولة', 'Try again'),
        onAction: _load,
      );
    } else if (_stats == null) {
      body = const AppListSkeleton(items: 5, withAvatar: false);
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          if (_error != null) ...[
            AppBanner(icon: Icons.error_outline_rounded, text: _error!),
            const SizedBox(height: 12),
          ],
          UsernameStatsContent(stats: _stats!, days: _days, onDays: _pick, loading: _loading),
        ]),
      );
    }
    return AdminPage(
      width: AppWidth.wide,
      title: title,
      subtitle: t('هل يستخدم الناس اسم المستخدم الاختياري؟', 'Are people using the optional @username?'),
      icon: Icons.alternate_email_rounded,
      onRefresh: _loading ? null : _load,
      body: body,
    );
  }
}

// ── Content (plain values) ───────────────────────────────────────────────────

class UsernameStatsContent extends StatelessWidget {
  const UsernameStatsContent({
    super.key,
    required this.stats,
    required this.days,
    required this.onDays,
    this.loading = false,
  });

  final UsernameStats stats;
  final int days;
  final ValueChanged<int> onDays;

  /// A new window is on its way: the figures fade a little.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final trend = usernameTrend(s.daily);
    final windowLabel = t('آخر ${daysText(days)}', 'Last ${daysText(days)}');

    final chips = Wrap(spacing: 8, runSpacing: 8, children: [
      for (final d in kUsernameStatsWindows)
        AppChoiceChip(label: daysText(d), selected: d == days, onTap: () => onDays(d)),
    ]);

    final tiles = AppGrid(padding: EdgeInsets.zero, minTile: 160, children: [
      AppStatTile(
          icon: Icons.people_alt_rounded, label: t('كل الحسابات', 'All accounts'), value: appCompactNumber(s.usersTotal)),
      AppStatTile(
          icon: Icons.alternate_email_rounded,
          label: t('لديهم اسم مستخدم', 'Have a username'),
          value: '${appCompactNumber(s.withUsername)} · ${_pct(s.usernameShare)}'),
      AppStatTile(
          icon: Icons.verified_rounded, label: t('أسماء مؤكدة', 'Confirmed'), value: appCompactNumber(s.confirmed)),
      AppStatTile(
          icon: Icons.hourglass_top_rounded,
          label: t('بانتظار رد صاحبه', 'Waiting for an answer'),
          value: appCompactNumber(s.pending)),
      AppStatTile(
          icon: Icons.person_off_rounded, label: t('بلا اسم مستخدم', 'No username'), value: appCompactNumber(s.without)),
    ]);

    final trendTiles = AppGrid(padding: EdgeInsets.zero, minTile: 220, children: [
      AppTrendTile(
        label: t('ردوا على الاسم المقترح', 'Answered the suggested name'),
        value: appCompactNumber(s.answered),
        icon: Icons.task_alt_rounded,
        spark: [for (final b in trend) b.answered.toDouble()],
      ),
      AppTrendTile(
        label: t('نسبة الرد على الاقتراح', 'Answer rate'),
        value: s.promptConversion == null ? '—' : _pct(s.promptConversion!),
        icon: Icons.percent_rounded,
      ),
      AppTrendTile(
        label: t('دخول باسم المستخدم', 'Sign-ins with a username'),
        value: appCompactNumber(s.login('username')),
        icon: DirIcons.login,
        spark: [for (final b in trend) b.usernameLogins.toDouble()],
      ),
    ]);

    final snapshot = _Section(
      title: t('الحالة الآن', 'Right now'),
      subtitle: t('من كل الحسابات، دون اعتبار للمدة', 'Across every account, whatever the period'),
      child: Center(
        child: AppDonut(
          title: t('أسماء المستخدمين الآن', 'Usernames right now'),
          parts: [
            AppChartPart(t('مؤكد', 'Confirmed'), s.confirmed.toDouble()),
            AppChartPart(t('بانتظار الرد', 'Waiting'), s.pending.toDouble()),
            AppChartPart(t('بلا اسم', 'None'), s.without.toDouble()),
          ],
        ),
      ),
    );

    final flowKeys = <(String, String)>[
      ('kept', t('أبقوه', 'Kept')),
      ('changed', t('غيّروه', 'Changed')),
      ('removed', t('حذفوه', 'Removed')),
      ('set_at_signup', t('عند التسجيل', 'At sign-up')),
      ('set_later', t('لاحقاً', 'Later')),
      ('admin_set', t('ضبطته الإدارة', 'Set by admin')),
      ('admin_cleared', t('أزالته الإدارة', 'Cleared by admin')),
    ];
    final flows = _Section(
      title: t('ماذا فعل الناس', 'What people did'),
      subtitle: windowLabel,
      child: AppBarChart(
        title: t('تغييرات اسم المستخدم', 'Username changes'),
        labels: [for (final f in flowKeys) f.$2],
        series: [
          AppChartSeries(t('أشخاص', 'People'), [for (final f in flowKeys) s.flow(f.$1).toDouble()]),
        ],
      ),
    );

    final loginKeys = <(String, String)>[
      ('email', t('البريد', 'E-mail')),
      ('phone', t('الهاتف', 'Phone')),
      ('username', t('اسم المستخدم', 'Username')),
      ('id', t('رقم الطالب', 'Student ID')),
      ('google', 'Google'),
    ];
    final logins = _Section(
      title: t('طرق تسجيل الدخول', 'How people sign in'),
      subtitle: windowLabel,
      child: s.loginsTotal == 0
          ? _Quiet(t('لا تسجيلات دخول في هذه المدة بعد.', 'No sign-ins in this period yet.'))
          : Center(
              child: AppDonut(
                title: t('تسجيلات الدخول', 'Sign-ins'),
                parts: [for (final k in loginKeys) AppChartPart(k.$2, s.login(k.$1).toDouble())],
              ),
            ),
    );

    final daily = _Section(
      title: t('على مدار الأيام', 'Day by day'),
      subtitle: trend.length < s.daily.length
          ? t('كل عمود ${daysText((s.daily.length / math.max(1, trend.length)).ceil())}', 'Each bar is '
              '${daysText((s.daily.length / math.max(1, trend.length)).ceil())}')
          : windowLabel,
      child: trend.isEmpty
          ? _Quiet(t('لا بيانات بعد.', 'No data yet.'))
          : AppBarChart(
              title: t('أسماء جديدة وردود', 'New names and answers'),
              labels: [for (final b in trend) usernameDayLabel(b.firstDate)],
              series: [
                AppChartSeries(t('أسماء اختاروها', 'Names they chose'), [for (final b in trend) b.newNames.toDouble()]),
                AppChartSeries(t('ردود على الاقتراح', 'Answers to the suggestion'),
                    [for (final b in trend) b.answered.toDouble()]),
              ],
            ),
    );

    return AnimatedOpacity(
      opacity: loading ? 0.55 : 1,
      duration: AppMotion.of(context).fast,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        Widget pair(Widget a, Widget b) => wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: 16),
                Expanded(child: b),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          chips,
          const SizedBox(height: 16),
          tiles,
          const SizedBox(height: 16),
          trendTiles,
          const SizedBox(height: 16),
          pair(snapshot, flows),
          const SizedBox(height: 16),
          pair(logins, daily),
        ]);
      }),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSectionTitle(title, subtitle: subtitle),
        const SizedBox(height: 4),
        child,
      ]),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text, textAlign: TextAlign.center, style: appText(13, c: c.textLight)),
    );
  }
}
