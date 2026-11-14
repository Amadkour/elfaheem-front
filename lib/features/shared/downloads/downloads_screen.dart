/// lib/features/shared/downloads/downloads_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/design/app_kit.dart'
    show AppListSkeleton, AppRefresh, AppTabs, AppTabItem, AppBlock, AppBlockTone, AppEmpty, AppStatusBadge, AppTone, AppButton, AppWidth;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppPressScale, AppReveal;
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

import '../../../core/offline/offline_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/offline_attendance_tab.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart';
import '../../admin/admin_common.dart' show t;
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tc = context.watch<ThemeConfigProvider>();
    final canPop = Navigator.of(context).canPop();
    final totalBytes = _items.fold<int>(0, (s, e) => s + e.sizeBytes);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(

        appBar: AppHeader(
          title: offlineT('dl_title'),
          // Opened as the start page (nothing to go back to) → home button (the header sits on the canvas: ink).
          leading: canPop
              ? null
              : IconButton(
                  tooltip: offlineT('dl_go_home'),
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  icon: Icon(Icons.home_rounded, color: c.textDark),
                  onPressed: _goHome,
                ),
          actions: [
            const HelpInfoButton(pageId: 'downloads'),
            if (_items.isNotEmpty && _tab == 0)
              IconButton(
                tooltip: offlineT('dl_delete_all'),
                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                icon: Icon(Icons.delete_sweep_rounded, color: c.textMedium),
                onPressed: _deleteAll,
              ),
          ],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
              child: AppTabs(
                expand: true,
                index: _tab,
                onChanged: (v) => setState(() => _tab = v),
                // phones: the three labels alone (with their icons they no longer fit 360 px)
                items: [
                  AppTabItem(attT('att_tab_downloads'), icon: wide ? Icons.download_done_rounded : null),
                  AppTabItem(attT('att_tab_attendance'), icon: wide ? Icons.how_to_reg_rounded : null),
                  AppTabItem(t('الاختبارات', 'Exams'), icon: wide ? Icons.offline_pin_rounded : null),
                ],
              ),
            ),
          ),
          Expanded(
            child: _tab == 2
                ? const OfflineExamsList()
                : _tab == 1
                ? const OfflineAttendanceTab()
                : _loading
            ? const AppListSkeleton()
            : AppRefresh(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // Connection status card
                          if (tc.serverUnreachable)
                            _StatusCard(
                              icon: Icons.wifi_off_rounded,
                              danger: true,
                              text: offlineT('dl_offline_info'),
                              actionLabel: offlineT('dl_retry_connection'),
                              loading: tc.isRetrying,
                              onAction: () =>
                                  context.read<ThemeConfigProvider>().reload(),
                            )
                          else if (!canPop)
                            _StatusCard(
                              icon: Icons.wifi_rounded,
                              text: offlineT('dl_back_online'),
                              actionLabel: offlineT('dl_go_home'),
                              actionIcon: Icons.home_rounded,
                              onAction: _goHome,
                            ),

                          if (_items.isEmpty)
                            const _EmptyState()
                          else ...[
                            // ONE entrance: the summary block, then the first rows ripple in after it
                            AppReveal(
                              index: 0,
                              group: 'downloads',
                              child: _SummaryCard(count: _items.length, sizeLabel: _fmtSize(totalBytes)),
                            ),
                            const SizedBox(height: AppSpace.lg),
                            for (final (i, it) in _items.indexed)
                              AppReveal(
                                index: i + 1,
                                group: 'downloads',
                                rise: 8,
                                child: _DownloadTile(
                                  item: it,
                                  sizeLabel: _fmtSize(it.sizeBytes),
                                  expiryLabel: _fmtExpiry(it.expiresAt),
                                  accessEnded: it.courseId != null && _endedCourses.contains(it.courseId),
                                  onTap: () => _open(it),
                                  onDelete: () => _delete(it),
                                ),
                              ),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
          ),
        ]),
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

/// What is saved on this device: the screen's one block (sky = information), the count as the key figure.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.sizeLabel});

  final int count;
  final String sizeLabel;

  @override
  Widget build(BuildContext context) {
    return AppBlock(
      tone: AppBlockTone.sky,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                AppCountUp('$count', memoryKey: 'downloads.count', style: AppType.figureLarge(context).copyWith(color: b.ink)),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(offlineT('dl_videos_count'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: b.ink)),
                ),
              ]),
              const SizedBox(height: AppSpace.xs),
              Row(children: [
                Icon(Icons.sd_storage_rounded, size: AppIconSize.sm, color: b.muted),
                const SizedBox(width: AppSpace.xs - 2),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${offlineT('dl_storage_used')}  '),
                      TextSpan(
                          text: '${String.fromCharCode(0x2068)}$sizeLabel${String.fromCharCode(0x2069)}',
                          style: TextStyle(color: b.ink, fontWeight: FontWeight.w600)),
                    ]),
                    style: AppType.meta(context).copyWith(color: b.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: AppSpace.md),
          // a quiet paper disc with the mark: the block's colour does the talking
          Container(
            width: AppSpace.xxl + AppSpace.xs,
            height: AppSpace.xxl + AppSpace.xs,
            decoration: BoxDecoration(color: context.colors.cardBg, shape: BoxShape.circle),
            child: Icon(Icons.download_done_rounded, color: b.ink, size: AppIconSize.lg),
          ),
        ]);
      }),
    );
  }
}

/// One saved lecture: a paper row on a warm hairline — the play well, the title, its facts, a quiet delete.
class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.item,
    required this.sizeLabel,
    required this.expiryLabel,
    this.accessEnded = false,
    required this.onTap,
    required this.onDelete,
  });

  final OfflineItem item;
  final String sizeLabel;
  final String expiryLabel;
  final bool accessEnded;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final well = Color.alphaBlend(c.primaryTint, c.cardBg);
    final meta = AppType.meta(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppPressScale(
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: c.divider, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
              child: Row(children: [
                // Play well
                Container(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  decoration: BoxDecoration(borderRadius: AppRadius.controlAll, color: well),
                  child: Icon(Icons.play_arrow_rounded, color: c.blockAccentInk(c.primary, well), size: AppIconSize.lg),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                      if ((item.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xxs / 2),
                        Text(item.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta(context)),
                      ],
                      const SizedBox(height: AppSpace.xs),
                      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        _Chip(item.tier.label),
                        Text(sizeLabel, textDirection: TextDirection.ltr, style: meta),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule_rounded, size: AppIconSize.xs - 2, color: c.textLight),
                          const SizedBox(width: AppSpace.xxs / 2),
                          Flexible(child: Text(expiryLabel, style: meta, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                        if (accessEnded) AppStatusBadge(label: 'dl_access_ended'.tr, tone: AppTone.danger, dense: true),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'delete'.tr,
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded, color: c.textLight, size: AppIconSize.md),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The saved quality ("720p") as a quiet chip.
class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 2, vertical: 1),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip - 4)),
      child: Text(label, textDirection: TextDirection.ltr, style: AppType.overline(context)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxl),
        child: AppEmpty(
          icon: Icons.cloud_download_outlined,
          title: offlineT('dl_empty_title'),
          message: offlineT('dl_empty_body'),
          tone: AppBlockTone.sky,
        ),
      );
}
