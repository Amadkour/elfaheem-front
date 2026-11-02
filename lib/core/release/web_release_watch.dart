// lib/core/release/web_release_watch.dart
//
// The web app's "a new version is live" strip (D-143, docs/release/APP_RELEASES.md "Platforms": web "Must update" =
// open tabs are told to reload). When `app_release_live` arrives for platform `web` and the running build is older
// (the build number from version.json via package_info, else the x.y.z version), the strip above every page says so:
// After a rollback (an OLDER web build goes live) the reload is offered too.
//   • must update (`must`, policy `must`, or this build is below `min_supported`): "A new version is live — Reload", without
//     a close button (it stays, it never blocks the page: the person finishes what they type, then reloads);
//   • recommended: the same with a close button;
//   • optional: nothing (the next visit loads the new build anyway).
// The decision is the pure [webReleaseNeed]; [WebReleaseBanner] is mounted once in main.dart's builder and does
// nothing off the web. It only listens to the bus — the live stream is opened by whoever binds it (AttentionService
// while signed in), so a tab with no session simply gets the new build on its next load.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_tokens.dart';
import '../../utils/live_events.dart';
import '../display/app_fonts.dart';
import 'page_reload_stub.dart' if (dart.library.js_interop) 'page_reload_web.dart' as page;

enum WebReleaseNeed { none, suggest, must }

int _cmp(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[+-]')).first.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// What a live release ([event] = the `app_release_live` fields) means for the running web build.
WebReleaseNeed webReleaseNeed({required String runningVersion, required int runningBuild, required Map<String, dynamic> event}) {
  if ('${event['platform'] ?? ''}' != 'web') return WebReleaseNeed.none;
  final version = '${event['version'] ?? ''}';
  final build = int.tryParse('${event['build_number'] ?? event['build'] ?? ''}');
  final byBuild = build != null && runningBuild > 0;
  final differs = byBuild ? build != runningBuild : (version.isNotEmpty && _cmp(version, runningVersion) != 0);
  if (!differs) return WebReleaseNeed.none;
  if (event['must'] == true || '${event['must']}' == 'true') return WebReleaseNeed.must;
  final min = '${event['min_supported'] ?? ''}';
  if (min.isNotEmpty && _cmp(runningVersion, min) < 0) return WebReleaseNeed.must;
  final newer = byBuild ? build > runningBuild : _cmp(version, runningVersion) > 0;
  // an OLDER live build is a rollback: the running one was taken down, so reloading is offered at least
  if (!newer) return '${event['policy'] ?? ''}' == 'must' ? WebReleaseNeed.must : WebReleaseNeed.suggest;
  return switch ('${event['policy'] ?? ''}') {
    'must' => WebReleaseNeed.must,
    'recommended' => WebReleaseNeed.suggest,
    _ => WebReleaseNeed.none,
  };
}

/// The live web release this tab should reload for (null when there is none).
class WebReleaseOffer {
  const WebReleaseOffer({required this.version, required this.must});

  final String version;
  final bool must;
}

class WebReleaseWatch extends ChangeNotifier {
  WebReleaseWatch({LiveEvents? bus, this.running, this.reload = page.reloadPage}) : _bus = bus ?? LiveEvents.instance;

  static final WebReleaseWatch instance = WebReleaseWatch();

  final LiveEvents _bus;

  /// The running build (version, build number); read from package_info when null.
  final (String, int)? running;
  final VoidCallback reload;

  StreamSubscription<LiveEvent>? _sub;
  (String, int)? _running;
  WebReleaseOffer? _offer;
  String? _dismissed;

  WebReleaseOffer? get offer => _offer;

  /// Listens to `app_release_live` (idempotent).
  void start() {
    if (_sub != null) return;
    _running = running;
    if (_running == null) {
      PackageInfo.fromPlatform().then((i) => _running = (i.version, int.tryParse(i.buildNumber) ?? 0)).catchError((_) => _running = ('', 0));
    }
    _sub = _bus.listen({LiveEvents.appReleaseLive}, _onLive);
  }

  @visibleForTesting
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onLive(LiveEvent e) {
    final r = _running;
    if (r == null || (r.$1.isEmpty && r.$2 == 0)) return;
    final need = webReleaseNeed(runningVersion: r.$1, runningBuild: r.$2, event: e.data);
    if (need == WebReleaseNeed.none) return;
    final version = '${e.data['version'] ?? ''}';
    final must = need == WebReleaseNeed.must;
    if (!must && _dismissed == version) return;
    // a later "recommended" never softens a "must" already shown
    if (_offer != null && _offer!.must && !must) return;
    _offer = WebReleaseOffer(version: version, must: must);
    notifyListeners();
  }

  /// "Later" on a recommended update (a must update cannot be closed).
  void dismiss() {
    final o = _offer;
    if (o == null || o.must) return;
    _dismissed = o.version;
    _offer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Puts the strip above [child] while an offer stands (web only; elsewhere it is [child]).
class WebReleaseBanner extends StatefulWidget {
  const WebReleaseBanner({super.key, required this.child, this.watch, this.enabled = kIsWeb});

  final Widget child;
  final WebReleaseWatch? watch;

  /// Tests turn it on off the web.
  final bool enabled;

  @override
  State<WebReleaseBanner> createState() => _WebReleaseBannerState();
}

class _WebReleaseBannerState extends State<WebReleaseBanner> {
  WebReleaseWatch get _w => widget.watch ?? WebReleaseWatch.instance;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _w.start();
    _w.addListener(_changed);
  }

  @override
  void dispose() {
    if (widget.enabled) _w.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final o = _w.offer;
    final motion = AppMotion.of(context);
    return Column(children: [
      AnimatedSize(
        duration: motion.base,
        curve: AppMotion.curve,
        alignment: AlignmentDirectional.topCenter,
        child: o == null
            ? const SizedBox(width: double.infinity)
            : WebReleaseStrip(must: o.must, version: o.version, onReload: _w.reload, onDismiss: o.must ? null : _w.dismiss),
      ),
      // Keyed so the Navigator keeps its state when the strip comes and goes.
      Expanded(
        key: const ValueKey('app_content_web_release'),
        child: MediaQuery.removePadding(context: context, removeTop: o != null, child: widget.child),
      ),
    ]);
  }
}

/// The strip from plain values: a calm line, Reload, and a close button only for a recommended update.
class WebReleaseStrip extends StatelessWidget {
  const WebReleaseStrip({super.key, required this.must, required this.version, required this.onReload, this.onDismiss});

  final bool must;
  final String version;
  final VoidCallback onReload;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final title = ar ? 'نسخة جديدة متاحة الآن' : 'A new version is live';
    final meta = must
        ? (ar ? 'أعد تحميل الصفحة لمتابعة العمل على الإصدار $version' : 'Reload the page to keep working on version $version')
        : (ar ? 'أعد التحميل متى شئت للحصول على الإصدار $version' : 'Reload when convenient to get version $version');
    final col = must ? c.warning : c.primary;
    return Semantics(
      container: true,
      liveRegion: true,
      label: title,
      child: Material(
        color: c.cardBg,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider), top: BorderSide(color: col, width: 3))),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
              child: LayoutBuilder(builder: (context, box) {
                final tight = box.maxWidth < 380;
                return Row(children: [
                  if (!tight) ...[
                    ExcludeSemantics(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
                        child: Icon(Icons.system_update_alt_rounded, size: 20, color: col),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                  ],
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontSize: 13.5)),
                      Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  // a long label (large text) shortens instead of pushing the message out
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.38),
                    child: FilledButton(
                      key: const ValueKey('web_release.reload'),
                      onPressed: onReload,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: c.onHero,
                        minimumSize: const Size(48, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        padding: EdgeInsets.symmetric(horizontal: tight ? AppSpace.sm : AppSpace.md),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!tight) ...[const Icon(Icons.refresh_rounded, size: 18), const SizedBox(width: AppSpace.xxs)],
                        Flexible(
                          child: Text(ar ? 'إعادة التحميل' : 'Reload',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      key: const ValueKey('web_release.dismiss'),
                      tooltip: ar ? 'لاحقاً' : 'Later',
                      onPressed: onDismiss,
                      icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20),
                    )
                  else
                    const SizedBox(width: AppSpace.sm),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}
