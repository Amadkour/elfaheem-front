// lib/features/admin/app_releases/app_releases_page.dart
//
// The super admin's "App versions" page (إصدارات التطبيق, D-143, docs/release/APP_RELEASES.md): the build server's
// status, the releases grouped by platform (status chips, the live one marked), filters by platform and status,
// "New version" (app_release_form.dart, a full page), a release's page (app_release_detail.dart), and a new build
// server token (shown once, with a copy button). Kill switch `admin.app_releases` (services hub tile + this page).
//
// Data: GET /api/v1/admin/app-releases (+ /builder/status) on open, pull-to-refresh and on `app_release_updated` /
// `app_release_live` through EventOrPoll — a poll every 10 s while a build moves and the stream is down, every minute
// otherwise (4–6 × that while the stream is up).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../core/live/event_wait.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../../utils/live_events.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../admin_common.dart' show t;
import 'app_release_detail.dart';
import 'app_release_form.dart';
import 'app_releases_api.dart';
import 'app_releases_models.dart';
import 'app_releases_view.dart';

/// Kill-switch key (services/feature_catalog.py).
const String kAppReleasesFeatureKey = 'admin.app_releases';

class AppReleasesPage extends StatefulWidget {
  const AppReleasesPage({super.key, this.api = const AppReleasesApi(), this.stream, this.bus, this.askPassword = askReleasePassword});

  static const routeName = '/app_releases';

  final AppReleasesApi api;
  final LiveStreamHandle? stream;
  final LiveEvents? bus;
  final ReleasePasswordPrompt askPassword;

  @override
  State<AppReleasesPage> createState() => AppReleasesPageState();
}

class AppReleasesPageState extends State<AppReleasesPage> {
  ReleasePage? _page;
  BuilderStatus? _builder;

  /// D-144: the Codemagic setup; null on an older server (the D-143 build server strip is shown then).
  ReleaseConfig? _config;
  String? _error;
  String? _platform, _status;
  int _pages = 1;
  EventOrPoll? _poller;
  bool? _pollActive;

  AppReleasesApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poller?.dispose();
    super.dispose();
  }

  void _syncPoller() {
    final active = (_page?.items.any((r) => r.active) ?? false) || (_builder?.busy ?? false);
    if (_pollActive == active && _poller != null) return;
    _pollActive = active;
    _poller?.dispose();
    _poller = EventOrPoll(
      poll: () => _load(silent: true),
      every: active ? const Duration(seconds: 10) : const Duration(minutes: 1),
      fallbackEvery: active ? const Duration(seconds: 40) : const Duration(minutes: 6),
      names: const {LiveEvents.appReleaseUpdated, LiveEvents.appReleaseLive},
      bus: widget.bus,
      stream: widget.stream,
    )..start();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _page == null) setState(() => _error = null);
    try {
      final f = await Future.wait<Object?>([
        _list(),
        _api.config().then<Object?>((c) => c, onError: (_) => _config),
        if (_config == null) _api.builderStatus().then<Object?>((b) => b, onError: (_) => _builder),
      ]);
      if (!mounted) return;
      setState(() {
        _page = f[0] as ReleasePage;
        _config = f[1] as ReleaseConfig?;
        if (f.length > 2) _builder = f[2] as BuilderStatus?;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent || _page == null) setState(() => _error = ReleaseFailure.from(e).message);
    }
    if (mounted) _syncPoller();
  }

  /// Pages 1 … [_pages] of the current filter, as one page (page_size ≤ 100 on the server).
  Future<ReleasePage> _list() async {
    final pages = await Future.wait([for (var i = 1; i <= _pages; i++) _api.list(platform: _platform, status: _status, page: i)]);
    final first = pages.first;
    return ReleasePage([for (final p in pages) ...p.items], total: first.total, live: first.live, nextBuild: first.nextBuild);
  }

  void _filter({String? platform, String? status, bool platformSet = false, bool statusSet = false}) {
    setState(() {
      if (platformSet) _platform = platform;
      if (statusSet) _status = status;
      _pages = 1;
      _page = null;
    });
    _load();
  }

  /// The newest release of each platform in what is loaded (the form prefills from it). With a filter on, the
  /// unfiltered list is fetched first so the prefill does not miss a newer one.
  Future<(Map<String, AppRelease>, Map<String, int>)> _latest() async {
    var items = _page?.items ?? const <AppRelease>[];
    var next = _page?.nextBuild ?? const <String, int>{};
    if (_platform != null || _status != null) {
      try {
        final all = await _api.list();
        items = all.items;
        next = all.nextBuild;
      } catch (_) {}
    }
    final out = <String, AppRelease>{};
    for (final r in items) {
      final cur = out[r.platform];
      if (cur == null || (r.buildNumber ?? 0) > (cur.buildNumber ?? 0) || compareReleaseVersions(r.version, cur.version) > 0) out[r.platform] = r;
    }
    return (out, next);
  }

  Future<void> _new() async {
    final (latest, next) = await _latest();
    if (!mounted) return;
    final created = await Navigator.of(context).push<AppRelease>(MaterialPageRoute(
      settings: const RouteSettings(name: '/app_releases/new'),
      builder: (_) => NewAppReleasePage(api: _api, latest: latest, nextBuild: next, initialPlatform: _platform ?? 'android', askPassword: widget.askPassword),
      // the form checks the setup itself (fresh), so a stale page never enables Create
    ));
    if (!mounted) return;
    await _load(silent: true);
    if (created != null && mounted) await _open(created);
  }

  Future<void> _open(AppRelease r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      settings: RouteSettings(name: '/app_releases/${r.id}'),
      builder: (_) => AppReleaseDetailPage(
          id: r.id, initial: r, api: _api, stream: widget.stream, bus: widget.bus, askPassword: widget.askPassword, codemagicAppId: _config?.appId),
    ));
    if (mounted) await _load(silent: true);
  }

  Future<void> _rotate() async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('رمز جديد', 'New token'),
        message: t('إنشاء رمز جديد لمشغّل البناء؟ يتوقف الرمز الحالي فوراً، فضع الجديد في tools/runner/runner.env على كل جهاز يبني.',
            'Create a new build runner token? The current one stops working at once, so put the new one in tools/runner/runner.env on every machine that builds.'));
    if (!ok || !mounted) return;
    final pw = await widget.askPassword(context);
    if (pw == null || pw.isEmpty || !mounted) return;
    try {
      final token = await _api.rotateBuilderToken(password: pw);
      if (!mounted) return;
      await showAppSheet<void>(context, (_) => BuilderTokenSheet(token: token));
    } catch (e) {
      if (mounted) showAppNotice(ReleaseFailure.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final page = _page;
    return BasePage(
      key: const ValueKey(kAppReleasesFeatureKey),
      appBar: ScreenAppBar(helpPageId: 'admin.app_releases', 
        title: t('إصدارات التطبيق', 'App versions'),
        actions: [AppRefreshAction(onRefresh: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'app_releases_new',
        key: const ValueKey('releases.new'),
        backgroundColor: c.primary,
        onPressed: _new,
        icon: Icon(Icons.add_rounded, color: c.onHero),
        label: Text(t('إصدار جديد', 'New version'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero, fontWeight: FontWeight.w700)),
      ),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 96),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_config != null && _config!.supportsRunner) ...[
                    RunnerStatusCard(runners: _config!.runners, onNewToken: _rotate),
                    const SizedBox(height: AppSpace.xs),
                    CodemagicStatusBanner(config: _config!, optional: true),
                  ] else if (_config != null)
                    CodemagicStatusBanner(config: _config!)
                  else
                    // an older server (no Codemagic config): the D-143 build server strip
                    BuilderStatusBanner(
                      status: _builder,
                      onRotateToken: _rotate,
                      onOpenBusy: _builder?.busyRelease == null
                          ? null
                          : () => _open(page?.items.where((r) => r.id == _builder!.busyRelease).firstOrNull ??
                              AppRelease(id: _builder!.busyRelease!, platform: 'android', version: '')),
                    ),
                  const SizedBox(height: AppSpace.md),
                  if (_error != null && page == null)
                    AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
                  else if (page == null)
                    const AppListSkeleton(items: 5, padding: EdgeInsets.zero)
                  else
                    AppReleasesView(
                      releases: page.items,
                      platform: _platform,
                      status: _status,
                      onPlatform: (p) => _filter(platform: p, platformSet: true),
                      onStatus: (s) => _filter(status: s, statusSet: true),
                      onOpen: _open,
                      onNew: _new,
                      hasMore: page.hasMore,
                      onMore: () {
                        setState(() => _pages += 1);
                        _load(silent: true);
                      },
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The new build server token, shown once: the server keeps only its hash.
class BuilderTokenSheet extends StatelessWidget {
  const BuilderTokenSheet({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(t('رمز مشغّل البناء الجديد', 'New build runner token')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppBanner(
              icon: Icons.visibility_outlined,
              color: c.warning,
              text: t('يظهر هذا الرمز مرة واحدة فقط. انسخه الآن وضعه في tools/runner/runner.env كـ NB_BUILDER_TOKEN=…',
                  'This token is shown once only. Copy it now and put it in tools/runner/runner.env as NB_BUILDER_TOKEN=…'),
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
              child: SelectableText(token,
                  key: const ValueKey('releases.token'),
                  textDirection: TextDirection.ltr,
                  style: appText(13.5, w: FontWeight.w600, c: c.textDark).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            const SizedBox(height: AppSpace.sm),
            AppPrimaryButton(
              key: const ValueKey('releases.token.copy'),
              label: t('نسخ الرمز', 'Copy the token'),
              icon: Icons.copy_rounded,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: token));
                showAppNotice(t('نُسخ الرمز', 'Token copied'));
              },
            ),
          ]),
        ),
      ),
    ]);
  }
}
