/// lib/features/shared/downloads/downloads_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/shared/session/video/video_player_screen.dart';
import 'package:flutter_education_app/utils/helpers.dart';

import '../../../core/offline/offline_strings.dart';
import '../attendance/attendance_strings.dart';
import '../attendance/offline_attendance_tab.dart';
import '../exam_engine/offline/offline_exam_screen.dart';
import '../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/core/display/app_fonts.dart';

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

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(

        appBar: AppBar(
          backgroundColor: c.cardBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: c.textDark),
          // Opened as the start page (nothing to go back to) → home button.
          leading: canPop
              ? null
              : IconButton(
                  tooltip: offlineT('dl_go_home'),
                  icon: const Icon(Icons.home_rounded),
                  onPressed: _goHome,
                ),
          title: Text(offlineT('dl_title'), style: c.h3),
          actions: [
            const HelpInfoButton(pageId: 'downloads'),
            if (_items.isNotEmpty && _tab == 0)
              IconButton(
                tooltip: offlineT('dl_delete_all'),
                icon: Icon(Icons.delete_sweep_rounded, color: c.danger),
                onPressed: _deleteAll,
              ),
          ],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.download_done_rounded, size: 18),
                      label: Text(attT('att_tab_downloads'))),
                  ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                      label: Text(attT('att_tab_attendance'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ButtonSegment(
                      value: 2,
                      icon: const Icon(Icons.offline_pin_rounded, size: 18),
                      label: Text(t('الاختبارات', 'Exams'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    // Connection status card
                    if (tc.serverUnreachable)
                      _StatusCard(
                        icon: Icons.wifi_off_rounded,
                        color: c.danger,
                        text: offlineT('dl_offline_info'),
                        actionLabel: offlineT('dl_retry_connection'),
                        loading: tc.isRetrying,
                        onAction: () =>
                            context.read<ThemeConfigProvider>().reload(),
                      )
                    else if (!canPop)
                      _StatusCard(
                        icon: Icons.wifi_rounded,
                        color: c.primary,
                        text: offlineT('dl_back_online'),
                        actionLabel: offlineT('dl_go_home'),
                        onAction: _goHome,
                      ),

                    if (_items.isEmpty)
                      _EmptyState()
                    else ...[
                      _SummaryCard(
                        count: _items.length,
                        sizeLabel: _fmtSize(totalBytes),
                      ),
                      const SizedBox(height: 12),
                      for (final it in _items)
                        _DownloadTile(
                          item: it,
                          sizeLabel: _fmtSize(it.sizeBytes),
                          expiryLabel: _fmtExpiry(it.expiresAt),
                          onTap: () => _open(it),
                          onDelete: () => _delete(it),
                        ),
                    ],
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.loading = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: c.body.copyWith(color: c.textDark))),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: loading ? null : onAction,
            style: TextButton.styleFrom(
              foregroundColor: color,
              backgroundColor: color.withValues(alpha: 0.10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: color),
                  )
                : Icon(Icons.refresh_rounded, size: 18, color: color),
            label: Text(actionLabel,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.family)),
          ),
        ),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.sizeLabel});

  final int count;
  final String sizeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary, c.primary.withValues(alpha: 0.75)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.primaryShadow,
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.onHero.withValues(alpha: 0.18),
          ),
          child: Icon(Icons.download_done_rounded,
              color: context.colors.onHero, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count ${offlineT('dl_videos_count')}',
                  style: c.h4.copyWith(color: context.colors.onHero)),
              const SizedBox(height: 2),
              Text('${offlineT('dl_storage_used')}: $sizeLabel',
                  style: c.caption.copyWith(color: context.colors.onHeroMuted)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.item,
    required this.sizeLabel,
    required this.expiryLabel,
    required this.onTap,
    required this.onDelete,
  });

  final OfflineItem item;
  final String sizeLabel;
  final String expiryLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.divider.withValues(alpha: 0.6)),
            ),
            child: Row(children: [
              // Play badge
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: c.primary.withValues(alpha: 0.12),
                ),
                child: Icon(Icons.play_circle_fill_rounded,
                    color: c.primary, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: c.bodyBold.copyWith(color: c.textDark)),
                    if ((item.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: c.caption.copyWith(color: c.textLight)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _Chip(item.tier.label, c.primary),
                      _Chip(sizeLabel, c.textMedium),
                      _Chip(expiryLabel, c.textLight),
                    ]),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppConfig.lang == 'ar' ? 'حذف' : 'Delete',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.family)),
      );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.primary.withValues(alpha: 0.10),
          ),
          child: Icon(Icons.cloud_download_outlined,
              color: c.primary, size: 48),
        ),
        const SizedBox(height: 20),
        Text(offlineT('dl_empty_title'),
            style: c.h4, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(offlineT('dl_empty_body'),
              style: c.body.copyWith(color: c.textLight),
              textAlign: TextAlign.center),
        ),
      ]),
    );
  }
}
