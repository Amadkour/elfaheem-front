// lib/features/admin/models/model_download_bar.dart
//
// The floating model-download indicator (D-152, requirement 7.7): drawn above every page from the MaterialApp.builder
// stack (lib/main.dart), so it stays while the super admin moves around the app; never blocks the screen.
//
//   ModelDownloadsHost   watches ModelDownloads.instance for a super admin (not in view-as, kill switch
//                        `models.admin` off), places the bar at the bottom start corner above the role's bottom tab
//                        bar, opens the AI Models page on a tap, and says when a download finished or failed.
//   ModelDownloadBar     plain values (test/ui/models_hub_layout_test.dart): the card "Downloading… 43% · 12 MB/s ·
//                        2 min left" with pause / resume / cancel / minimise, or the small pill (ring + percent).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/models_hub/model_downloads.dart';
import '../../../core/models_hub/models_hub_api.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_shell_nav.dart';
import '../../../design/app_tokens.dart';
import '../../../utils/top_route_observer.dart';
import '../../../utils/widget/view_as_state.dart';
import '../../auth/auth_provider.dart';
import '../admin_common.dart' show t;
import 'ai_models_page.dart';
import 'models_hub_text.dart';

/// Roles the hub lets in (../back modelhub/auth.py takes super-admin / super_admin / superadmin / developer).
bool hubAdminRole(String? role) => const {'super-admin', 'super_admin', 'superadmin', 'developer'}.contains(role);

class ModelDownloadsHost extends StatefulWidget {
  const ModelDownloadsHost({super.key, required this.navigatorKey, required this.child, this.downloads, this.signedInRole});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Defaults to [ModelDownloads.instance].
  final ModelDownloads? downloads;

  /// Tests: the signed-in role without a MyAuthProvider above (the app passes nothing: the provider's user).
  final String? signedInRole;

  @override
  State<ModelDownloadsHost> createState() => _ModelDownloadsHostState();
}

class _ModelDownloadsHostState extends State<ModelDownloadsHost> {
  ModelDownloads get _d => widget.downloads ?? ModelDownloads.instance;
  StreamSubscription<HubDownload>? _ended;
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _ended = _d.ended.listen(_onEnded);
  }

  @override
  void dispose() {
    _ended?.cancel();
    super.dispose();
  }

  void _onEnded(HubDownload d) {
    final name = hubDownloadName(d);
    if (d.status == 'done') {
      showAppNotice(d.activateAfter
          ? t('اكتمل تنزيل $name — يبدأ اختبار السلامة الآن', '$name downloaded — the health test runs next')
          : t('اكتمل تنزيل $name', '$name downloaded'));
    } else if (d.status == 'failed') {
      showAppNotice(t('فشل تنزيل $name', 'The download of $name failed') + (d.error == null ? '' : ': ${d.error}'), error: true);
    }
  }

  void _sync(bool allowed) {
    if (_allowed == allowed) return;
    _allowed = allowed;
    // never notify listeners from inside a build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _allowed != allowed) return;
      allowed ? _d.watch() : _d.unwatch();
    });
  }

  void _open() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null || topRouteObserver.topRoute.value?.settings.name == AiModelsPage.routeName) return;
    nav.push(MaterialPageRoute(settings: const RouteSettings(name: AiModelsPage.routeName), builder: (_) => const AiModelsPage()));
  }

  Future<void> _act(Future<HubDownload?> Function() f) async {
    try {
      await f();
    } catch (e) {
      showAppNotice(HubFailure.from(e).message, error: true);
    }
  }

  Future<void> _cancel(HubDownload d) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;
    final ok = await appConfirm(ctx,
        danger: true,
        confirmLabel: t('إلغاء التنزيل', 'Cancel download'),
        message: t('إلغاء تنزيل ${hubDownloadName(d)}؟ يُحذف الجزء الذي نُزّل.',
            'Cancel the download of ${hubDownloadName(d)}? The part already downloaded is deleted.'));
    if (ok) await _act(() => _d.cancel(d));
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.signedInRole ?? context.select<MyAuthProvider, String?>((a) => a.isAuthenticated ? a.currentUser?.role : null);
    return ListenableBuilder(
      listenable: Listenable.merge([_d, ViewAsState.instance, AppShellNav.changes]),
      builder: (context, _) {
        final allowed = hubAdminRole(role) && !ViewAsState.active && !AppConfig.disableList.contains(kModelsAdminFeatureKey);
        _sync(allowed);
        final d = allowed ? _d.current : null;
        final mq = MediaQuery.of(context);
        final start = AppShellNav.sideChromeWidth() + AppSpace.md;
        final bottom = math.max(mq.padding.bottom, AppShellNav.bottomBarHeight()) + mq.viewInsets.bottom + AppSpace.sm;
        // the child keeps slot 0 whether the bar shows or not: the Navigator below is never rebuilt by it
        return Stack(fit: StackFit.expand, children: [
          widget.child,
          if (d != null && _d.visible)
            PositionedDirectional(
              start: start,
              bottom: bottom,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.max(0, math.min(400, mq.size.width - start - AppSpace.md))),
                child: ModelDownloadBar(
                  download: d,
                  more: _d.live.length - 1,
                  minimised: _d.minimised || mq.viewInsets.bottom > 0,
                  onToggle: () => _d.minimised = !_d.minimised,
                  onOpen: _open,
                  onPause: () => _act(() => _d.pause(d)),
                  onResume: () => _act(() => _d.resume(d)),
                  onCancel: () => _cancel(d),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

/// The bar from plain values.
class ModelDownloadBar extends StatelessWidget {
  const ModelDownloadBar({
    super.key,
    required this.download,
    this.more = 0,
    this.minimised = false,
    this.name,
    this.onToggle,
    this.onOpen,
    this.onPause,
    this.onResume,
    this.onCancel,
  });

  final HubDownload download;

  /// Other downloads queued / running / paused besides this one.
  final int more;
  final bool minimised;

  /// The model's name (default: from the download's ref).
  final String? name;
  final VoidCallback? onToggle, onOpen, onPause, onResume, onCancel;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    return AnimatedSwitcher(
      duration: motion.base,
      switchInCurve: AppMotion.curve,
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, alignment: AlignmentDirectional.bottomStart, child: child)),
      child: minimised ? _pill(context) : _card(context),
    );
  }

  String get _name => name ?? hubDownloadName(download);

  Widget _ring(BuildContext context, double size, {double stroke = 3}) {
    final c = context.colors;
    final f = download.fraction;
    final col = download.paused ? c.warning : c.primary;
    final indeterminate = f == null && !AppMotion.of(context).off;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: indeterminate ? null : (f ?? 0),
          strokeWidth: stroke,
          color: col,
          backgroundColor: appTintOn(context, col),
        ),
        Icon(download.paused ? Icons.pause_rounded : Icons.download_rounded, size: size * 0.48, color: col),
      ]),
    );
  }

  Widget _pill(BuildContext context) {
    final c = context.colors;
    final f = download.fraction;
    final pct = f == null ? '' : hubLtr('${(f * 100).floor()}%');
    return Semantics(
      key: const ValueKey('model_download_pill'),
      button: true,
      label: '${hubDownloadLine(download)} · $_name',
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        elevation: 6,
        shadowColor: c.shadowTone.withValues(alpha: 0.25),
        shape: StadiumBorder(side: BorderSide(color: c.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ring(context, 32),
                if (pct.isNotEmpty) ...[
                  const SizedBox(width: AppSpace.xs),
                  Text(pct, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                ],
                if (more > 0) ...[
                  const SizedBox(width: AppSpace.xxs),
                  Text('+$more', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
                ],
                const SizedBox(width: AppSpace.xxs),
                Icon(Icons.expand_less_rounded, size: AppIconSize.md, color: c.textMedium),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.colors;
    final role = download.role == null ? '' : hubRoleName(download.role!);
    Widget action(IconData icon, String label, VoidCallback? onTap, {Color? color}) => IconButton(
          tooltip: null,
          onPressed: onTap,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          style: IconButton.styleFrom(foregroundColor: color ?? c.textMedium),
          icon: Icon(icon, size: AppIconSize.lg, semanticLabel: label),
        );
    return Material(
      key: const ValueKey('model_download_card'),
      color: c.cardBg,
      elevation: 8,
      shadowColor: c.shadowTone.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet), side: BorderSide(color: c.divider)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.sm),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _ring(context, 36),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                  Text(
                    [role, if (more > 0) t('و$more غيره', '+$more more')].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(color: c.textMedium),
                  ),
                ]),
              ),
              if (download.paused)
                action(Icons.play_arrow_rounded, t('استئناف', 'Resume'), onResume, color: c.primary)
              else
                action(Icons.pause_rounded, t('إيقاف مؤقت', 'Pause'), download.status == 'running' ? onPause : null),
              action(Icons.close_rounded, t('إلغاء التنزيل', 'Cancel download'), onCancel),
              action(Icons.expand_more_rounded, t('تصغير', 'Minimise'), onToggle),
            ]),
            const SizedBox(height: AppSpace.xs),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: download.fraction ?? (AppMotion.of(context).off ? 0 : null),
                  color: download.paused ? c.warning : c.primary,
                  backgroundColor: c.divider,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: Text(hubDownloadLine(download),
                  key: const ValueKey('model_download_line'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
            ),
          ]),
        ),
      ),
    );
  }
}
