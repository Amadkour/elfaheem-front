// lib/features/games/admin/v4/hub_page.dart — SUPER ADMIN: the Games hub (Games v4, T64). Today's numbers, the
// "waiting for review" count and a card for every admin page: Templates, Subjects, the pages other tasks register in
// [kGamesHubExtraLinks] (bank, review, levels, analytics, …) and the classic games editor. Kill switch
// `admin.games_content`; the classic editor keeps `admin.games`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/games_admin_api.dart' show gamesAdminOff;
import 'package:flutter_education_app/features/games/admin/games_admin_page.dart' show GamesAdminPage;
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/subjects_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/templates_page.dart';

class GamesHubPage extends StatefulWidget {
  const GamesHubPage({super.key, this.api});

  final GamesV4AdminApi? api;

  @override
  State<GamesHubPage> createState() => _GamesHubPageState();
}

class _GamesHubPageState extends State<GamesHubPage> {
  late final GamesV4AdminApi _api = widget.api ?? GamesV4AdminApi();
  GamesHub? _hub;
  String? _error;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final h = await _api.hub();
      if (!mounted) return;
      setState(() {
        _hub = h;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = gamesV4ErrorText(e));
    }
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final links = <GamesHubLink>[
      for (final l in kGamesHubExtraLinks)
        GamesHubLink(
          id: l.id,
          titleAr: l.titleAr,
          titleEn: l.titleEn,
          subAr: l.subAr,
          subEn: l.subEn,
          icon: l.icon,
          sort: l.sort,
          badge: l.id == 'review' ? (_hub?.pendingReview ?? 0) : l.badge,
          open: (c) => l.open(c),
        ),
      GamesHubLink(
        id: 'templates',
        titleAr: 'قوالب الألعاب',
        titleEn: 'Game templates',
        subAr: 'شغّل أو أوقف كل لعبة واضبط إعداداتها',
        subEn: 'Switch each game on or off and set its defaults',
        icon: Icons.dashboard_customize_rounded,
        sort: 10,
        open: (_) => _push(GamesTemplatesPage(api: _api)),
      ),
      GamesHubLink(
        id: 'subjects',
        titleAr: 'المواد',
        titleEn: 'Subjects',
        subAr: 'مواد الألعاب والمراجعة وربطها بمواد الدورات',
        subEn: 'Game subjects, review and the course subjects they follow',
        icon: Icons.menu_book_rounded,
        sort: 20,
        open: (_) => _push(GamesSubjectsPage(api: _api)),
      ),
      if (!gamesAdminOff())
        GamesHubLink(
          id: 'classic',
          titleAr: 'الألعاب الكلاسيكية',
          titleEn: 'Classic games',
          subAr: 'المحرر القديم للألعاب: محتواها وترتيبها ونشرها',
          subEn: 'The earlier games editor: content, order and publishing',
          icon: Icons.extension_rounded,
          sort: 1000,
          open: (_) => _push(const GamesAdminPage()),
        ),
    ]..sort((a, b) => a.sort.compareTo(b.sort));
    return AdminPage(
      width: AppWidth.content,
      title: t('ألعاب التعلّم', 'Learning games'),
      subtitle: t('نظرة سريعة على اللعب اليوم، وكل صفحات إدارة الألعاب في مكان واحد.',
          'A quick look at today\'s play, and every games admin page in one place.'),
      icon: Icons.sports_esports_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: GamesHubBody(hub: _hub, error: _error, onRetry: _load, links: links),
      ),
    );
  }
}

/// The hub over plain values: KPI cards, the review banner and the page links.
class GamesHubBody extends StatelessWidget {
  const GamesHubBody({super.key, required this.hub, required this.links, this.error, this.onRetry});

  /// Null: loading.
  final GamesHub? hub;
  final String? error;
  final VoidCallback? onRetry;
  final List<GamesHubLink> links;

  static String pct(double v) => '${v.round()}%';

  @override
  Widget build(BuildContext context) {
    final h = hub;
    return ListView(
      key: const ValueKey('games.hub.list'),
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: [
        if (error != null && h == null)
          AppErrorState(message: error, onRetry: onRetry, compact: true)
        else if (h == null)
          const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
        else ...[
          AppKpiGrid(maxColumns: 4, children: [
            AppKpiCard(
              key: const ValueKey('games.hub.kpi.plays'),
              label: t('لعبات اليوم', 'Plays today'),
              value: '${h.playsToday}',
              icon: Icons.play_circle_rounded,
              highlight: true,
            ),
            AppKpiCard(label: t('لاعبون اليوم', 'Players today'), value: '${h.playersToday}', icon: Icons.groups_rounded),
            AppKpiCard(label: t('نسبة الإنهاء', 'Completion'), value: pct(h.completionPct), icon: Icons.flag_rounded),
            AppKpiCard(label: t('متوسط النتيجة', 'Average score'), value: pct(h.avgScorePct), icon: Icons.stars_rounded),
          ]),
          AppSpace.gapMd,
          if (h.pendingReview > 0) ...[
            AppBanner(
              key: const ValueKey('games.hub.pending'),
              icon: Icons.rule_rounded,
              text: countText(h.pendingReview,
                  ar1: 'سؤال واحد ينتظر المراجعة',
                  ar2: 'سؤالان ينتظران المراجعة',
                  arFew: '${h.pendingReview} أسئلة تنتظر المراجعة',
                  arMany: '${h.pendingReview} سؤالاً ينتظر المراجعة',
                  en1: '1 question is waiting for review',
                  en: '${h.pendingReview} questions are waiting for review'),
            ),
            AppSpace.gapMd,
          ],
          Text(
            t('${h.itemsTotal} سؤال · ${h.levelsPublished} مستوى منشور', '${h.itemsTotal} questions · ${h.levelsPublished} published levels'),
            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
          ),
        ],
        AppSectionTitle(t('إدارة الألعاب', 'Manage games')),
        for (final l in links)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppActionCard(
              key: ValueKey('games.hub.link.${l.id}'),
              icon: l.icon,
              title: t(l.titleAr, l.titleEn),
              subtitle: t(l.subAr, l.subEn),
              badge: l.badge,
              onTap: () => l.open(context),
            ),
          ),
      ],
    );
  }
}
