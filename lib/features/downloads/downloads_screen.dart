/// lib/features/downloads/downloads_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/design/app_kit.dart'
    show AppListSkeleton, AppRefresh, AppTabs, AppTabItem, AppEmpty, AppStatusBadge, AppTone, AppButton, AppWidth, AppWidthBox,
        AppCard, AppHero, AppTile, AppIconButton, AppAccent, AppArea;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppDeal;
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/course_access.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/video/video_player_screen.dart';
import 'package:flutter_education_app/utils/helpers.dart';

import 'package:flutter_education_app/core/offline/offline_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/offline_attendance_tab.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
// DownloadsScreen — every encrypted video saved on this device.
//   • Opened from Profile → Downloads
//   • Opened automatically at app start when the device is offline
//     (see main.dart), so the student can keep watching.
// Works without any network call.
// ════════════════════════════════════════════════════════════════════════════

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final OfflineVideoService _svc = OfflineVideoService.instance;
  List<OfflineItem> _items = const [];
  bool _loading = true;
  final Set<int> _endedCourses = {}; // courses whose plan ended / was withdrawn (server answer, online only)
  int _tab = 0; // 0 = Downloads, 1 = Attendance (works offline, courses stored locally)

  @override
  void initState() {
    super.initState();
    _svc.downloadedIds.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _svc.downloadedIds.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _svc.listItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    _refreshAccess(items);
  }

  /// Online: ONE bulk call for every downloaded course; a definite "no access" marks its videos "Access ended".
  /// A network error, a timeout or no connection changes nothing (fail open).
  Future<void> _refreshAccess(List<OfflineItem> items) async {
    if (!AppConnectivity.instance.isOnline) return;
    final ids = {for (final i in items) ?i.courseId};
    if (ids.isEmpty) return;
    try {
      final map = await CourseAccessApi().many(ids).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _endedCourses
          ..clear()
          ..addAll([
            for (final e in map.entries)
              if (offlineVerdict(online: true, courseKnown: true, access: e.value) == OfflineVerdict.refuse) e.key,
          ]);
      });
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  SessionMaterialModel _asMaterial(OfflineItem it) => SessionMaterialModel(
        id: it.materialId,
        sessionId: it.sessionId,
        name: it.title,
        description: it.description,
        type: SessionMaterialType.video,
        order: 0,
        createdAt: it.createdAt,
        completed: false,
      );

  void _open(OfflineItem it) {
    HapticFeedback.selectionClick();
    // VideoPlayerScreen sees the local copy and plays it without any API call.
    // The other downloads of the same session are the lecture list / "up next".
    final same = _items.where((o) => o.sessionId == it.sessionId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          material: _asMaterial(it),
          playlist: same.map(_asMaterial).toList(),
        ),
      ),
    );
  }

  Future<void> _delete(OfflineItem it) async {
    final ok = await Helpers.confirmDialog(
      context,
      title: offlineT('dl_delete_title'),
      confirm: 'delete'.tr,
    );
    if (ok == true) await _svc.deleteById(it.id);
  }

  Future<void> _deleteAll() async {
    final ok = await Helpers.confirmDialog(
      context,
      title: offlineT('dl_delete_all_title'),
      confirm: 'delete'.tr,
    );
    if (ok == true) await _svc.deleteAll();
  }

  void _goHome() {
    Navigator.of(context)
        .pushReplacementNamed(context.read<MyAuthProvider>().homeRoute);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '—';
    const mb = 1024 * 1024;
    if (bytes >= 1024 * mb) return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
  }

  String _fmtExpiry(DateTime expiresAt) {
    final days = expiresAt.difference(DateTime.now()).inDays;
    if (days <= 0) return offlineT('dl_expires_today');
    return offlineT('dl_expires_in_days').replaceAll('{n}', '$days');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tc = context.watch<ThemeConfigProvider>();
    final canPop = Navigator.of(context).canPop();
    final totalBytes = _items.fold<int>(0, (s, e) => s + e.sizeBytes);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final tabs = AppTabs(
      expand: true,
      index: _tab,
      onChanged: (v) => setState(() => _tab = v),
      // phones: the three labels alone (with their icons they no longer fit 360 px)
      items: [
        AppTabItem(attT('att_tab_downloads'), icon: wide ? Icons.download_done_rounded : null, count: _items.isEmpty ? null : _items.length),
        AppTabItem(attT('att_tab_attendance'), icon: wide ? Icons.how_to_reg_rounded : null),
        AppTabItem(t('الاختبارات', 'Exams'), icon: wide ? Icons.offline_pin_rounded : null),
      ],
    );
    // the connection line: offline, or back online on the start page
    final Widget? status = tc.serverUnreachable
        ? _StatusCard(
            icon: Icons.wifi_off_rounded,
            danger: true,
            text: offlineT('dl_offline_info'),
            actionLabel: offlineT('dl_retry_connection'),
            loading: tc.isRetrying,
            onAction: () => context.read<ThemeConfigProvider>().reload(),
          )
        : !canPop
            ? _StatusCard(
                icon: Icons.wifi_rounded,
                text: offlineT('dl_back_online'),
                actionLabel: offlineT('dl_go_home'),
                actionIcon: Icons.home_rounded,
                onAction: _goHome,
              )
            : null;

    final Widget body;
    if (_tab != 0) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
          child: AppWidthBox(width: AppWidth.reading, child: tabs),
        ),
        Expanded(child: _tab == 2 ? const OfflineExamsList() : const OfflineAttendanceTab()),
      ]);
    } else {
      final empty = !_loading && _items.isEmpty;
      final card = AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tabs,
          const SizedBox(height: AppSpace.md),
          if (_loading)
            const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
          else if (empty)
            const _EmptyState()
          else ...[
            Row(children: [
              Expanded(child: Text(offlineT('dl_storage_used'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600))),
              Text(appDigits(_fmtSize(totalBytes)), textDirection: TextDirection.ltr, style: AppType.meta(context)),
            ]),
            const SizedBox(height: AppSpace.sm),
            for (final (i, it) in _items.indexed)
              AppDeal(
                index: i,
                group: 'downloads',
                child: _DownloadTile(
                  item: it,
                  index: i,
                  sizeLabel: _fmtSize(it.sizeBytes),
                  expiryLabel: _fmtExpiry(it.expiresAt),
                  expiringSoon: it.expiresAt.difference(DateTime.now()).inDays <= 3,
                  accessEnded: it.courseId != null && _endedCourses.contains(it.courseId),
                  onTap: () => _open(it),
                  onDelete: () => _delete(it),
                ),
              ),
          ],
        ]),
      );
      body = AppRefresh(
        onRefresh: _load,
        child: SdHeroList(
          hero: AppHero(
            title: empty ? 'sd_dl_empty_title'.tr : offlineT('dl_title'),
            subtitle: empty ? 'sd_dl_empty_sub'.tr : 'sd_dl_sub'.tr,
            icon: Icons.download_rounded,
            wipe: false, // the rows are dealt in (M5)
          ),
          children: [
            ?status,
            card,
          ],
        ),
      );
    }

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: SdArea(
        area: AppArea.me,
        child: BasePage(
          appBar: AppHeader(
            title: offlineT('dl_title'),
            // Opened as the start page (nothing to go back to) → home button.
            leading: canPop
                ? null
                : AppIconButton(tooltip: offlineT('dl_go_home'), icon: Icons.home_rounded, onHero: true, onPressed: _goHome),
            actions: [
              const HelpInfoButton(pageId: 'downloads'),
              if (_items.isNotEmpty && _tab == 0)
                AppIconButton(
                  tooltip: offlineT('dl_delete_all'),
                  icon: Icons.delete_sweep_outlined,
                  onHero: true,
                  onPressed: _deleteAll,
                ),
            ],
          ),
          child: ColoredBox(color: c.background, child: body),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Widgets
// ════════════════════════════════════════════════════════════════════════════

/// The connection line on top: a paper card with the tone in its icon well and a tonal action, never a wash.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.refresh_rounded,
    this.danger = false,
    this.loading = false,
  });

  final IconData icon;
  final IconData actionIcon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = danger ? c.danger : c.primary;
    final tint = danger ? c.dangerTint : c.primaryTint;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: danger ? c.danger.withValues(alpha: 0.35) : c.divider, width: AppBorder.hairline),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final mark = Container(
          width: AppSpace.xl + AppSpace.xs,
          height: AppSpace.xl + AppSpace.xs,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, color: c.blockAccentInk(tone, Color.alphaBlend(tint, c.cardBg)), size: AppIconSize.md),
        );
        final label = Text(text, style: AppType.bodyStrong(context).copyWith(fontWeight: FontWeight.w500));
        final action = AppButton.tonal(
          label: actionLabel,
          icon: actionIcon,
          busy: loading,
          onPressed: loading ? null : onAction,
        );
        // wide: one line (mark, text, action at the end); a phone stacks the action under the text
        if (box.maxWidth >= 560) {
          return Row(children: [
            mark,
            const SizedBox(width: AppSpace.sm),
            Expanded(child: label),
            const SizedBox(width: AppSpace.md),
            action,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [mark, const SizedBox(width: AppSpace.sm), Expanded(child: label)]),
          const SizedBox(height: AppSpace.sm),
          Align(alignment: AlignmentDirectional.centerEnd, child: action),
        ]);
      }),
    );
  }
}

/// One saved lesson (Stu2Profile `screen=downloads`): a coloured play thumbnail, the title, its facts (subject,
/// size, quality), the time left as a tag (sky, sun when ≤ 3 days, coral when the plan ended) and a round delete.
class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.item,
    required this.index,
    required this.sizeLabel,
    required this.expiryLabel,
    this.expiringSoon = false,
    this.accessEnded = false,
    required this.onTap,
    required this.onDelete,
  });

  final OfflineItem item;
  final int index;
  final String sizeLabel;
  final String expiryLabel;
  final bool expiringSoon, accessEnded;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = c.kit.accent(AppAccent.values[index % AppAccent.values.length]);
    final facts = [
      if ((item.description ?? '').isNotEmpty) item.description!,
      sizeLabel,
      item.tier.label,
    ].join((AppConfig.lang == 'ar' ? '، ' : ', '));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppTile(
        leading: ExcludeSemantics(
          child: Container(
            decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(AppRadius.glyph)),
            child: Icon(Icons.play_arrow_rounded, color: c.onHero, size: AppIconSize.lg),
          ),
        ),
        title: item.title,
        subtitle: appDigits(facts),
        onTap: onTap,
        trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          AppIconButton(tooltip: 'delete'.tr, icon: Icons.delete_outline_rounded, onPressed: onDelete),
          const SizedBox(height: AppSpace.xxs),
          if (accessEnded)
            AppStatusBadge(label: 'dl_access_ended'.tr, tone: AppTone.danger, dense: true)
          else
            AppStatusBadge(label: appDigits(expiryLabel), tone: expiringSoon ? AppTone.warning : AppTone.info, dense: true),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => AppEmpty(
        icon: Icons.download_rounded,
        title: 'sd_dl_empty_how'.tr,
        message: 'sd_dl_empty_later'.tr,
      );
}
