// lib/features/admin/app_releases/app_release_detail.dart
//
// One release (D-143): the progress bar and the build server's current step, the live log tail, the artifacts with
// their download (the AAB goes to the Play Console by hand in phase 1), the actions — Cancel (until the upload),
// Retry (failed / canceled), Make live (ready; password), Rollback (the live one; password) — and the facts: branch,
// commit, gate, source, policy, who created it, the dates (AppTime).
//
// Live: `app_release_updated {id, status, progress, step, …}` through EventOrPoll (event_wait.dart). The event's fields
// are drawn at once; while the status stays the same only the new log lines are fetched (GET …/log?after=<last>),
// a new status reloads the whole release. Without the stream: a poll every 3 s while it builds, every minute after.
// [ReleaseDetailView] draws plain values (test/ui/app_releases_layout_test.dart).
//
// D-144 (Codemagic): the channel (store | website) and the per-version settings (workflow, Play track, package name),
// a link to the Codemagic build, the files the website channel uploaded (with their sizes), and for a store version the
// note that Play production / the App Store still review it ("Live" = submitted).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
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
import '../admin_money_p8.dart' show p8SaveBytes;
import 'app_release_form.dart' show ReleasePasswordPrompt, askReleasePassword;
import 'app_releases_api.dart';
import 'app_releases_models.dart';
import 'app_releases_text.dart';
import 'app_releases_view.dart';

/// Saves a downloaded artifact (tests pass their own).
typedef ReleaseFileSaver = Future<void> Function(Uint8List bytes, String name);

Future<void> _saveFile(Uint8List bytes, String name) => p8SaveBytes(bytes, name);

/// Opens a link outside the app (the Codemagic build page, a published file).
Future<void> openReleaseLink(String url) async {
  final uri = Uri.tryParse(url);
  try {
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('not opened');
  } catch (_) {
    showAppNotice(t('تعذّر فتح الرابط', 'Could not open the link'), error: true);
  }
}

/// True when [e] is about release [id] (`id` or `release_id`).
bool releaseEventMatches(LiveEvent e, int id) =>
    (e.type == LiveEvents.appReleaseUpdated || e.type == LiveEvents.appReleaseLive) &&
    ('${e.data['id'] ?? ''}' == '$id' || '${e.data['release_id'] ?? ''}' == '$id');

class AppReleaseDetailPage extends StatefulWidget {
  const AppReleaseDetailPage({
    super.key,
    required this.id,
    this.initial,
    this.api = const AppReleasesApi(),
    this.stream,
    this.bus,
    this.askPassword = askReleasePassword,
    this.saveFile = _saveFile,
    this.codemagicAppId,
    this.openLink = openReleaseLink,
  });

  final int id;

  /// The Codemagic application id (from `GET …/config`), for the build link when the release carries none.
  final String? codemagicAppId;
  final ValueChanged<String> openLink;

  /// Drawn at once while the full release (with its log) loads.
  final AppRelease? initial;
  final AppReleasesApi api;
  final LiveStreamHandle? stream;
  final LiveEvents? bus;
  final ReleasePasswordPrompt askPassword;
  final ReleaseFileSaver saveFile;

  @override
  State<AppReleaseDetailPage> createState() => AppReleaseDetailPageState();
}

class AppReleaseDetailPageState extends State<AppReleaseDetailPage> {
  late AppRelease? _r = widget.initial;
  String? _error;
  String? _busy;
  EventOrPoll? _poller;
  bool? _pollActive;

  /// The last trigger was an event that left the status as it was: only the new log lines are fetched.
  bool _logOnly = false;

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
    final active = _r?.active ?? true;
    if (_pollActive == active && _poller != null) return;
    _pollActive = active;
    _poller?.dispose();
    _poller = EventOrPoll(
      poll: _tick,
      every: active ? const Duration(seconds: 3) : const Duration(minutes: 1),
      fallbackEvery: active ? const Duration(seconds: 20) : const Duration(minutes: 5),
      names: const {LiveEvents.appReleaseUpdated, LiveEvents.appReleaseLive},
      match: (e) => releaseEventMatches(e, widget.id),
      onEvent: _onEvent,
      bus: widget.bus,
      stream: widget.stream,
    )..start();
  }

  void _onEvent(LiveEvent e) {
    final r = _r;
    if (r == null || !mounted) return;
    final next = r.withEvent(e.data);
    _logOnly = next.status == r.status && e.type == LiveEvents.appReleaseUpdated;
    setState(() => _r = next);
  }

  Future<void> _tick() async {
    final logOnly = _logOnly;
    _logOnly = false;
    final r = _r;
    if (logOnly && r != null) {
      try {
        final more = await _api.log(widget.id, after: r.log.isEmpty ? 0 : r.log.last.n);
        if (mounted && more.isNotEmpty) setState(() => _r = _r?.withLog(more));
      } catch (_) {/* the next tick tries again */}
      return;
    }
    await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await _api.get(widget.id);
      if (!mounted) return;
      setState(() {
        _r = r;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent || _r == null) setState(() => _error = ReleaseFailure.from(e).message);
    }
    if (mounted) _syncPoller();
  }

  Future<void> _run(String what, Future<AppRelease?> Function() call, String done) async {
    if (_busy != null) return;
    setState(() => _busy = what);
    try {
      final r = await call();
      if (!mounted) return;
      if (r != null) setState(() => _r = r);
      showAppNotice(done);
    } catch (e) {
      if (mounted) showAppNotice(ReleaseFailure.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    await _load(silent: true);
  }

  Future<void> _cancel() async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('إلغاء البناء', 'Cancel the build'),
        message: t('إلغاء بناء ${_r!.label}؟ يتوقف خادم البناء ولا يُنشر شيء.', 'Cancel the build of ${_r!.label}? The build server stops and nothing is published.'));
    if (!ok) return;
    await _run('cancel', () => _api.cancel(widget.id), t('أُلغي البناء', 'Build canceled'));
  }

  Future<void> _retry() => _run('retry', () => _api.retry(widget.id), t('أُعيد البناء إلى الطابور', 'The build is queued again'));

  Future<void> _publish() async {
    final r = _r!;
    final ok = await appConfirm(context,
        confirmLabel: t('انشره الآن', 'Make live'),
        message: t('نشر ${releasePlatformShort(r.platform)} ${r.label} الآن؟ ${releasePolicyHint(r.policy)}.',
            'Make ${releasePlatformShort(r.platform)} ${r.label} live now? ${releasePolicyHint(r.policy)}.'));
    if (!ok || !mounted) return;
    final pw = await widget.askPassword(context);
    if (pw == null || pw.isEmpty) return;
    await _run('publish', () => _api.publish(widget.id, password: pw), t('${r.label} منشور الآن', '${r.label} is live now'));
  }

  Future<void> _rollback() async {
    final r = _r!;
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('ارجع للسابق', 'Roll back'),
        message: t('الرجوع عن ${r.label}؟ يعود الإصدار المنشور السابق لـ${releasePlatformShort(r.platform)}.',
            'Roll back ${r.label}? The previous live version of ${releasePlatformShort(r.platform)} goes live again.'));
    if (!ok || !mounted) return;
    final pw = await widget.askPassword(context);
    if (pw == null || pw.isEmpty) return;
    await _run('rollback', () => _api.rollback(widget.id, password: pw), t('عاد الإصدار السابق', 'The previous version is live again'));
  }

  Future<void> _download(ReleaseArtifact a) async {
    if (_busy != null) return;
    // a website-channel file is already public (GET /app/downloads/<platform>/<name>): the browser downloads it
    if (a.url != null && a.url!.startsWith('https://')) {
      widget.openLink(a.url!);
      return;
    }
    setState(() => _busy = 'artifact:${a.name}');
    try {
      final bytes = await _api.artifact(widget.id, a.name);
      await widget.saveFile(bytes, a.name);
    } catch (e) {
      if (mounted) showAppNotice(ReleaseFailure.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return BasePage(
      key: const ValueKey('admin.app_releases'),
      appBar: ScreenAppBar(
        title: r == null ? t('الإصدار', 'Version') : '${releasePlatformShort(r.platform)} ${r.label}',
        actions: [AppRefreshAction(onRefresh: _load)],
      ),
      child: _error != null && r == null
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : r == null
              ? const AppListSkeleton(items: 4, withAvatar: false)
              : ReleaseDetailView(
                  release: r,
                  busy: _busy,
                  onCancel: r.canCancel ? _cancel : null,
                  onRetry: r.canRetry ? _retry : null,
                  onPublish: r.canPublish ? _publish : null,
                  onRollback: r.canRollback ? _rollback : null,
                  onDownload: _download,
                  codemagicLink: r.codemagicLink(appId: widget.codemagicAppId),
                  onOpenLink: widget.openLink,
                ),
    );
  }
}

/// The release drawn from plain values.
class ReleaseDetailView extends StatelessWidget {
  const ReleaseDetailView({
    super.key,
    required this.release,
    this.busy,
    this.onCancel,
    this.onRetry,
    this.onPublish,
    this.onRollback,
    this.onDownload,
    this.codemagicLink,
    this.onOpenLink,
  });

  final AppRelease release;

  /// The Codemagic build page of this release (D-144), when known.
  final String? codemagicLink;
  final ValueChanged<String>? onOpenLink;

  /// The action running now: 'cancel', 'publish', 'artifact:' + the file name, …
  final String? busy;
  final VoidCallback? onCancel, onRetry, onPublish, onRollback;
  final ValueChanged<ReleaseArtifact>? onDownload;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final main = [
        _Header(
          release: release,
          busy: busy,
          onCancel: onCancel,
          onRetry: onRetry,
          onPublish: onPublish,
          onRollback: onRollback,
          codemagicLink: codemagicLink,
          onOpenLink: onOpenLink,
        ),
        const SizedBox(height: AppSpace.md),
        if (release.builds) ReleaseLogCard(lines: release.log, running: release.active, codemagic: release.viaCodemagic),
      ];
      final side = [
        _Facts(release: release),
        if (release.artifacts.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _Artifacts(release: release, busy: busy, onDownload: onDownload),
        ],
        const SizedBox(height: AppSpace.md),
        _Notes(release: release),
      ];
      final pad = EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl);
      if (!wide) {
        return ListView(padding: pad, children: [...main, const SizedBox(height: AppSpace.md), ...side]);
      }
      return SingleChildScrollView(
        padding: pad,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: main)),
              const SizedBox(width: AppSpace.md),
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: side)),
            ]),
          ),
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.release,
    this.busy,
    this.onCancel,
    this.onRetry,
    this.onPublish,
    this.onRollback,
    this.codemagicLink,
    this.onOpenLink,
  });

  final AppRelease release;
  final String? busy;
  final VoidCallback? onCancel, onRetry, onPublish, onRollback;
  final String? codemagicLink;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = release;
    final col = releaseStatusColor(context, r.shownStatus);
    final pct = r.progress?.round();
    // the server sends no step: while it builds, the newest log line says what it does
    final stepText = r.step ??
        (r.active && r.log.isNotEmpty ? r.log.last.text : null) ??
        switch (r.status) {
          'queued' => r.viaCodemagic ? t('في طابور Codemagic', 'Waiting in the Codemagic queue') : t('ينتظر خادم البناء', 'Waiting for the build server'),
          'building' || 'testing' || 'uploading' => releaseStatusName(r.status),
          'ready' => r.autoPublish && (r.viaCodemagic || r.source != 'google_play') ? t('يُنشر الآن', 'Publishing') : t('جاهز — اضغط «انشره الآن»', 'Ready — press Make live'),
          'live' when !r.current => t('استبدله إصدار أحدث', 'A newer version replaced it'),
          'live' => r.liveAt == null ? t('منشور', 'Live') : t('منشور منذ ${AppTime.dateTime(r.liveAt!)}', 'Live since ${AppTime.dateTime(r.liveAt!)}'),
          _ => null,
        };
    Widget action(String key, String label, IconData icon, VoidCallback? onTap, {bool filled = false, Color? color}) {
      final running = busy == key;
      final child = Row(mainAxisSize: MainAxisSize.min, children: [
        running
            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: filled ? c.onHero : (color ?? c.primary)))
            : Icon(icon, size: 18),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600))),
      ]);
      final onPressed = busy == null ? onTap : null;
      return filled
          ? FilledButton(
              key: ValueKey('release.action.$key'),
              onPressed: onPressed,
              style: FilledButton.styleFrom(backgroundColor: color ?? c.primary, foregroundColor: c.onHero, minimumSize: const Size(48, AppTouch.min)),
              child: child)
          : OutlinedButton(
              key: ValueKey('release.action.$key'),
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(foregroundColor: color ?? c.primary, minimumSize: const Size(48, AppTouch.min)),
              child: child);
    }

    final actions = [
      if (onPublish != null) action('publish', t('انشره الآن', 'Make live'), Icons.rocket_launch_rounded, onPublish, filled: true),
      if (onRetry != null) action('retry', t('أعد المحاولة', 'Retry'), Icons.replay_rounded, onRetry, filled: onPublish == null),
      if (onCancel != null) action('cancel', t('إلغاء', 'Cancel'), Icons.stop_circle_outlined, onCancel, color: c.danger),
      if (onRollback != null) action('rollback', t('ارجع للسابق', 'Roll back'), Icons.history_rounded, onRollback, color: c.danger),
    ];

    return AppCard(
      key: const ValueKey('release.header'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: AppRadius.cardAll),
            child: Icon(releasePlatformIcon(r.platform), color: c.primary, size: 26),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(releasePlatformName(r.platform), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family)),
              Text(r.label, textDirection: TextDirection.ltr, style: AppType.pageTitle(context).copyWith(fontFamily: AppFonts.family)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                releaseChipOf(r),
                if (r.isLive && r.status != 'live') AppBadgePill(t('منشور', 'Live'), color: c.success, icon: Icons.check_circle_rounded),
                AppBadgePill(releasePolicyName(r.policy), color: r.policy == 'must' ? c.danger : c.textMedium),
                AppBadgePill(releaseChannelName(r.platform, r.channel), color: c.textMedium, icon: releaseChannelIcon(r.platform, r.channel)),
              ]),
            ]),
          ),
        ]),
        if (r.active || r.status == 'ready' || r.progress != null) ...[
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Expanded(child: AppProgressBar(key: const ValueKey('release.progress'), value: r.status == 'live' || r.status == 'ready' ? 100 : (r.progress ?? 0), color: col, height: 8)),
            if (pct != null) ...[
              const SizedBox(width: AppSpace.sm),
              Text('$pct%', textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ]),
        ],
        if (stepText != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(stepText, key: const ValueKey('release.step'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontFamily: AppFonts.family, color: c.textMedium)),
        ],
        if (r.status == 'failed' && r.error != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: releaseErrorText(r.error, r.error!)),
        ],
        if (r.isStore && r.viaCodemagic && r.status != 'failed' && r.status != 'canceled') ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(key: const ValueKey('release.store_note'), icon: Icons.gavel_rounded, color: c.warning, text: releaseStoreReviewNote(r.platform)),
        ],
        if (!r.viaCodemagic && r.source == 'google_play' && r.platform == 'android' && (r.status == 'ready' || r.status == 'live')) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.back_hand_outlined,
            color: c.warning,
            text: t('نزّل ملف AAB من الملفات وارفعه في Play Console، ثم اضغط «انشره الآن».',
                'Download the AAB from the files, upload it in the Play Console, then press Make live.'),
          ),
        ],
        if (actions.isNotEmpty || codemagicLink != null) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ...actions,
            if (codemagicLink != null)
              TextButton.icon(
                key: const ValueKey('release.codemagic'),
                onPressed: onOpenLink == null ? null : () => onOpenLink!(codemagicLink!),
                style: TextButton.styleFrom(foregroundColor: c.primary, minimumSize: const Size(48, AppTouch.min)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(t('البناء على Codemagic', 'The build on Codemagic'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// The build server's log, newest at the bottom; it follows new lines while the reader is at the bottom.
class ReleaseLogCard extends StatefulWidget {
  const ReleaseLogCard({super.key, required this.lines, this.running = false, this.codemagic = false});

  final List<ReleaseLogLine> lines;
  final bool running;

  /// Built on Codemagic: the steps arrive from its status sync (the full log is on the build's page).
  final bool codemagic;

  @override
  State<ReleaseLogCard> createState() => _ReleaseLogCardState();
}

class _ReleaseLogCardState extends State<ReleaseLogCard> {
  final _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _follow = p.pixels >= p.maxScrollExtent - 24;
    });
    _toBottom();
  }

  @override
  void didUpdateWidget(covariant ReleaseLogCard old) {
    super.didUpdateWidget(old);
    final grew = widget.lines.isNotEmpty && (old.lines.isEmpty || widget.lines.last.n != old.lines.last.n);
    if (grew && _follow) _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = widget.lines;
    final style = appText(12, c: c.textDark, h: 1.45).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return AppCard(
      key: const ValueKey('release.log'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.receipt_long_rounded, size: 20, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('سجل البناء', 'Build log'), style: AppType.section(context).copyWith(fontFamily: AppFonts.family))),
          if (widget.running)
            AppBadgePill(t('مباشر', 'Live tail'), color: c.success, icon: Icons.fiber_manual_record_rounded),
          IconButton(
            tooltip: t('نسخ السجل', 'Copy the log'),
            onPressed: lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: lines.map((l) => l.text).join('\n')));
                    showAppNotice(t('نُسخ السجل', 'Log copied'));
                  },
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Container(
          height: 340,
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
          child: lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Text(
                        widget.running
                            ? (widget.codemagic ? t('ينتظر أول خطوة من Codemagic…', 'Waiting for the first step from Codemagic…') : t('ينتظر أول سطر من خادم البناء…', 'Waiting for the first line from the build server…'))
                            : t('لا سجل', 'No log'),
                        textAlign: TextAlign.center, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family)),
                  ),
                )
              : Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectionArea(
                    child: Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpace.xs),
                        itemCount: lines.length,
                        itemBuilder: (_, i) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 44,
                            child: Text('${lines[i].n}', style: style.copyWith(color: c.textLight), textAlign: TextAlign.end),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(child: Text(lines[i].text, style: style)),
                        ]),
                      ),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final rows = <(IconData, String, String, bool)>[
      (releaseChannelIcon(r.platform, r.channel), t('قناة التنزيل', 'Download channel'), releaseChannelName(r.platform, r.channel), false),
      if (r.builds) ...[
        (Icons.account_tree_outlined, t('الفرع', 'Branch'), r.branch ?? '—', true),
        if (r.workflow != null) (Icons.route_rounded, t('سير العمل', 'Workflow'), r.workflow!, true),
        if (r.track != null) (Icons.alt_route_rounded, t('مسار Google Play', 'Play track'), r.track!, true),
        if (r.packageName != null) (Icons.inventory_2_outlined, t('اسم الحزمة', 'Package name'), r.packageName!, true),
        (Icons.commit_rounded, t('الإيداع', 'Commit'), r.shortCommit ?? t('يُحدَّد عند بدء البناء', 'Pinned when the build starts'), r.shortCommit != null),
        (Icons.fact_check_outlined, t('الفحص', 'Gate'), releaseGateName(r.gate), false),
      ],
      if (r.storeUrl != null) (Icons.link_rounded, t('الرابط', 'Link'), r.storeUrl!, true),
      if (r.downloadUrl != null && r.downloadUrl != r.storeUrl) (Icons.download_outlined, t('رابط التحديث', 'Update link'), r.downloadUrl!, true),
      if ((r.attempt ?? 1) > 1) (Icons.replay_rounded, t('المحاولة', 'Attempt'), '${r.attempt}', false),
      (Icons.system_update_rounded, t('سياسة التحديث', 'Update policy'), releasePolicyName(r.policy), false),
      if (r.minSupported != null) (Icons.low_priority_rounded, t('أقل إصدار مدعوم', 'Minimum supported'), r.minSupported!, true),
      (Icons.rocket_launch_outlined, t('النشر التلقائي', 'Auto publish'), r.autoPublish ? t('نعم', 'Yes') : t('لا', 'No'), false),
      if (r.createdBy != null) (Icons.person_outline_rounded, t('أنشأه', 'Created by'), r.createdBy!, false),
      if (r.createdAt != null) (Icons.event_outlined, t('أُنشئ', 'Created'), AppTime.dateTime(r.createdAt!), false),
      if (r.startedAt != null) (Icons.play_circle_outline_rounded, t('بدأ', 'Started'), AppTime.dateTime(r.startedAt!), false),
      if (r.finishedAt != null) (Icons.flag_outlined, t('انتهى', 'Finished'), AppTime.dateTime(r.finishedAt!), false),
      if (r.liveAt != null) (Icons.check_circle_outline_rounded, t('نُشر', 'Went live'), AppTime.dateTime(r.liveAt!), false),
    ];
    return AppCard(
      key: const ValueKey('release.facts'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('التفاصيل', 'Details'), style: AppType.section(context).copyWith(fontFamily: AppFonts.family)),
        const SizedBox(height: AppSpace.xs),
        for (final (icon, label, value, ltr) in rows) _FactRow(icon: icon, label: label, value: value, ltr: ltr),
      ]),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.label, required this.value, this.ltr = false});

  final IconData icon;
  final String label, value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: c.textLight),
        const SizedBox(width: AppSpace.xs),
        Expanded(flex: 2, child: Text(label, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family))),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          flex: 3,
          // a branch / commit / link stays left-to-right, still at the row's end
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(value,
                textDirection: ltr ? TextDirection.ltr : null,
                textAlign: ltr ? TextAlign.left : TextAlign.end,
                style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontSize: 13.5)),
          ),
        ),
      ]),
    );
  }
}

class _Artifacts extends StatelessWidget {
  const _Artifacts({required this.release, this.busy, this.onDownload});

  final AppRelease release;
  final String? busy;
  final ValueChanged<ReleaseArtifact>? onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      key: const ValueKey('release.artifacts'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(release.channel == 'website' && release.viaCodemagic ? t('الملفات على خادمنا', 'Files on our server') : t('الملفات', 'Files'),
            style: AppType.section(context).copyWith(fontFamily: AppFonts.family)),
        const SizedBox(height: AppSpace.xs),
        for (final a in release.artifacts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(
                  switch (a.kind) {
                    'aab' => Icons.shop_rounded,
                    'apk' => Icons.android_rounded,
                    'zip' || 'tar.gz' || 'gz' || 'tar' => Icons.folder_zip_outlined,
                    'deb' => Icons.terminal_rounded,
                    _ => Icons.insert_drive_file_outlined,
                  },
                  size: 20,
                  color: c.primary),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontSize: 13)),
                  if (a.size != null || a.sha256 != null)
                    Text([releaseBytes(a.size), if (a.sha256 != null) 'sha256 ${a.sha256!.substring(0, a.sha256!.length.clamp(0, 12))}…'].where((s) => s.isNotEmpty).join(' · '),
                        textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, fontSize: 11.5)),
                ]),
              ),
              busy == 'artifact:${a.name}'
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      key: ValueKey('release.download.${a.name}'),
                      tooltip: t('تنزيل', 'Download'),
                      onPressed: onDownload == null || busy != null ? null : () => onDownload!(a),
                      icon: Icon(Icons.download_rounded, color: c.primary),
                    ),
            ]),
          ),
      ]),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = release.notesAr.trim(), en = release.notesEn.trim();
    final first = AppConfig.lang == 'ar' ? [(ar, true), (en, false)] : [(en, false), (ar, true)];
    return AppCard(
      key: const ValueKey('release.notes'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('ما الجديد', "What's new"), style: AppType.section(context).copyWith(fontFamily: AppFonts.family)),
        const SizedBox(height: AppSpace.xs),
        if (ar.isEmpty && en.isEmpty)
          Text(t('لا ملاحظات', 'No notes'), style: AppType.meta(context).copyWith(fontFamily: AppFonts.family))
        else
          for (final (text, rtl) in first)
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Text(text,
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    style: AppType.row(context)
                        .copyWith(fontFamily: AppFonts.family, fontFamilyFallback: AppFonts.fallback, color: c.textMedium, height: 1.5)),
              ),
      ]),
    );
  }
}
