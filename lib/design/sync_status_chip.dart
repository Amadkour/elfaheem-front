// lib/design/sync_status_chip.dart — what the offline outbox is doing, in the chrome (D-1351).
//
//   const SyncStatusChip()          the shell's top bar tools and the student Home header (phones); NEVER the phone's
//                                   bottom bar (D-1340)
//   SyncStatusChipView(snapshot:)   the plain-values part the layout harness pumps
//
// Hidden while online with nothing waiting. Offline: a cloud-off plate with the count of waiting writes; syncing:
// a turning sync arrow (parked under Reduce motion through syncMotionLoop); online with writes waiting: an upload
// cloud with the count. A tap says the same in words (showAppNotice) and, online, runs the engine.
library;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../core/offline/sync/sync_engine.dart';
import '../core/offline/sync/sync_status.dart';
import '../core/plural.dart';
import 'app_display.dart' show syncMotionLoop;
import 'app_notice.dart';
import 'app_tokens.dart';
import 'chrome_button.dart';

class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, this.status});

  /// The status to draw (the app's [SyncStatus.instance] unless given).
  final SyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status ?? SyncStatus.instance;
    return ValueListenableBuilder<SyncSnapshot>(
      valueListenable: s,
      builder: (context, v, _) => SyncStatusChipView(
        snapshot: v,
        onTap: () {
          showAppNotice(syncStatusSentence(v));
          if (v.phase == SyncPhase.online && v.pending > 0) SyncEngine.instance.kick();
        },
      ),
    );
  }
}

/// "3 changes wait to be sent" in the open language.
String syncPendingText(int n) => countText(n,
    ar1: 'تغيير واحد ينتظر الإرسال',
    ar2: 'تغييران ينتظران الإرسال',
    arFew: '{n} تغييرات تنتظر الإرسال',
    arMany: '{n} تغييراً ينتظر الإرسال',
    en1: '1 change waits to be sent',
    en: '{n} changes wait to be sent');

/// The chip's state in one sentence (its screen-reader label and the tap's notice).
String syncStatusSentence(SyncSnapshot v) {
  final ar = AppConfig.lang == 'ar';
  switch (v.phase) {
    case SyncPhase.offline:
      final head = 'sync_status_offline'.tr;
      return v.pending == 0 ? head : '$head${ar ? '، ' : ', '}${syncPendingText(v.pending)}';
    case SyncPhase.syncing:
      return 'sync_status_syncing'.tr;
    case SyncPhase.online:
      return v.pending == 0 ? 'sync_status_done'.tr : syncPendingText(v.pending);
  }
}

class SyncStatusChipView extends StatefulWidget {
  const SyncStatusChipView({super.key, required this.snapshot, this.onTap});

  final SyncSnapshot snapshot;
  final VoidCallback? onTap;

  @override
  State<SyncStatusChipView> createState() => _SyncStatusChipViewState();
}

class _SyncStatusChipViewState extends State<SyncStatusChipView> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  bool get _syncing => widget.snapshot.phase == SyncPhase.syncing;

  void _syncLoop() {
    if (_syncing) {
      syncMotionLoop(context, _spin, rest: 0);
    } else {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(SyncStatusChipView old) {
    super.didUpdateWidget(old);
    if (old.snapshot.phase != widget.snapshot.phase) _syncLoop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.snapshot;
    if (v.quiet) return const SizedBox.shrink();
    final c = context.colors;
    final onBar = ChromeBar.of(context);
    final k = ChromePlate.colorsOf(context, onHero: onBar);
    final ink = v.phase == SyncPhase.offline && !onBar ? c.warning : k.ink;
    final Widget glyph = switch (v.phase) {
      SyncPhase.offline => Icon(Icons.cloud_off_rounded, size: AppIconSize.md, color: ink),
      SyncPhase.syncing => RotationTransition(
          turns: Tween<double>(begin: 0, end: -1).animate(_spin),
          child: Icon(Icons.sync_rounded, size: AppIconSize.md, color: ink),
        ),
      SyncPhase.online => Icon(Icons.cloud_upload_outlined, size: AppIconSize.md, color: ink),
    };
    final label = syncStatusSentence(v);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey('sync.status.chip'),
        button: true,
        liveRegion: true,
        label: label,
        excludeSemantics: true,
        child: ChromePlate(
          onHero: onBar,
          onTap: widget.onTap,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            glyph,
            if (v.pending > 0 && v.phase != SyncPhase.syncing)
              PositionedDirectional(
                top: AppSpace.xxs / 2,
                end: AppSpace.xxs / 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: AppIconSize.sm, minHeight: AppIconSize.sm),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: ChromePlate.badgeRing(context, onHero: onBar), width: AppBorder.strong),
                  ),
                  child: Text(
                    chromeBadgeText(v.pending),
                    maxLines: 1,
                    style: AppType.overline(context).copyWith(color: c.onHero, height: 1.2, letterSpacing: 0),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
