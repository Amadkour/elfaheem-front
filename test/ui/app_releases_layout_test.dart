// No overflow on any screen size (layout_harness: 320×640 and 1400×900, ar / en, text ×1.3) for App versions (D-143):
// the build server strip, the list grouped by platform (and empty), the New version page on every platform with the
// store link and its note, the release page (building with its log, ready with files, failed), the token sheet, the
// web "new version" strip and the update dialog with a store source. D-144: the channel cards, the readiness box
// (ready / not ready / checking / the check failed), a Codemagic release (link, files, store note), the Codemagic
// strip of the list, and the website download strip + sheet (every offer kind).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/release/web_release_watch.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_detail.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_form.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_models.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_view.dart';
import 'package:flutter_education_app/features/shared/get_app/app_download_banner.dart';
import 'package:flutter_education_app/features/shared/get_app/get_app_banner.dart' show GetAppBannerView;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_releases_samples.dart';
import 'layout_harness.dart';

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  testWidgets('list: builder strip + groups', (tester) async {
    final releases = sampleReleases();
    await expectNoLayoutErrors(
      tester,
      () => _scroll(Column(children: [
        BuilderStatusBanner(status: BuilderStatus.fromJson(builderJson()), onRotateToken: () {}, onOpenBusy: () {}),
        const SizedBox(height: 16),
        AppReleasesView(releases: releases, platform: null, status: null, onPlatform: (_) {}, onStatus: (_) {}, onOpen: (_) {}, hasMore: true, onMore: () {}),
      ])),
    );
  });

  testWidgets('list: offline builder, filtered and empty', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll(Column(children: [
        BuilderStatusBanner(status: BuilderStatus.fromJson(builderJson(online: false, busy: false)), onRotateToken: () {}),
        const BuilderStatusBanner(status: null),
        AppReleasesView(releases: const [], onNew: () {}),
        AppReleasesView(releases: const [], platform: 'linux', status: 'failed', onPlatform: (_) {}),
      ])),
    );
  });

  final latest = {for (final r in sampleReleases()) if (r.isLive) r.platform: r};
  final config = ReleaseConfig.fromJson(releaseConfigJson());
  for (final p in kReleasePlatformOrder) {
    for (final ch in releaseChannelsFor(p)) {
      testWidgets('form: $p · $ch', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => NewAppReleasePage(latest: latest, initialPlatform: p, initialChannel: ch, config: config, askPassword: (_) async => null),
          scaffold: false,
        );
      });
    }
  }

  testWidgets('form: Google Play ready (a real package) with the field errors', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => NewAppReleasePage(
          latest: latest,
          initialChannel: 'store',
          config: ReleaseConfig.fromJson(releaseConfigJson(notReady: const {}, packageName: 'com.doubley.nextbrain')),
          askPassword: (_) async => null),
      scaffold: false,
      act: (tester) async {
        await tester.enterText(find.byKey(const ValueKey('release.version')), '1.4');
        await tester.enterText(find.byKey(const ValueKey('release.branch')), 'bad branch!');
        await tester.enterText(find.byKey(const ValueKey('release.store_url')), 'http://x');
        await _tapVisible(tester, 'release.submit');
        await tester.pump(const Duration(seconds: 4)); // the notice goes
      },
    );
  });

  testWidgets('form: Codemagic not set up at all (every channel misses the token)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => NewAppReleasePage(latest: latest, initialPlatform: 'web', config: ReleaseConfig.fromJson(releaseConfigJson(codemagic: false)), askPassword: (_) async => null),
      scaffold: false,
    );
  });

  testWidgets('readiness box: every state', (tester) async {
    final notReady = ReleaseConfig.fromJson(releaseConfigJson(codemagic: false, notReady: const {
      'android:store': ['PLAY_PACKAGE_NAME', 'package_name_example', 'CODEMAGIC_WORKFLOW_ANDROID_STORE', 'SOMETHING_NEW_ON_THE_SERVER'],
    })).readiness('android', 'store');
    await expectNoLayoutErrors(
      tester,
      () => _scroll(Column(children: [
        ReleaseReadinessBox(builds: true, readiness: notReady, what: 'Android · Google Play'),
        const SizedBox(height: 8),
        const ReleaseReadinessBox(builds: true, readiness: ReleaseReadiness.ok, what: 'Android · My website'),
        const SizedBox(height: 8),
        const ReleaseReadinessBox(builds: true, readiness: null, loading: true, what: 'Web'),
        const SizedBox(height: 8),
        ReleaseReadinessBox(builds: true, readiness: null, error: 'Service unavailable', onRetry: () {}, what: 'Web'),
        const SizedBox(height: 8),
        CodemagicStatusBanner(config: ReleaseConfig.fromJson(releaseConfigJson())),
        const SizedBox(height: 8),
        CodemagicStatusBanner(config: ReleaseConfig.fromJson(releaseConfigJson(codemagic: false))),
      ])),
    );
  });

  testWidgets('detail: a Codemagic store release and a website release with its files', (tester) async {
    final store = AppRelease.fromJson(codemagicReleaseJson(channel: 'store', status: 'live', isLive: true, progress: 100, config: {'track': 'production', 'package_name': 'com.doubley.nextbrain'}));
    final site = AppRelease.fromJson(codemagicReleaseJson(status: 'uploading', progress: 92, artifacts: codemagicApkArtifacts, log: sampleLog(8)));
    for (final r in [store, site]) {
      await expectNoLayoutErrors(
          tester, () => ReleaseDetailView(release: r, codemagicLink: r.codemagicLink(), onOpenLink: (_) {}, onDownload: (_) {}, onRollback: r.canRollback ? () {} : null));
    }
  });

  final downloads = parseAppDownloads(downloadsJson(), apiBase: 'https://nextbrain.site/api');
  for (final os in const [GetAppOs.android, GetAppOs.windows, GetAppOs.linux, GetAppOs.ios, GetAppOs.macos]) {
    testWidgets('download strip + sheet: ${os.name}', (tester) async {
      final offer = appDownloadOfferFor(GetAppEnv(isWeb: true, os: os, iosSafari: os == GetAppOs.ios), downloads)!;
      final w = appDownloadStripText(offer, downloads);
      await expectNoLayoutErrors(
        tester,
        () => Column(children: [
          GetAppBannerView(
            icon: w.icon,
            title: w.title,
            meta: w.meta,
            actionLabel: w.action,
            onAction: () {},
            onDismiss: () {},
            detailsLabel: offer.kind == AppDownloadOfferKind.browse ? null : 'Other downloads',
            onDetails: offer.kind == AppDownloadOfferKind.browse ? null : () {},
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(child: AppDownloadsSheetBody(releases: downloads, offer: offer, iosSafari: false, onDownload: (_) {})),
            ),
          ),
        ]),
      );
    });
  }

  testWidgets('detail: building with the log tail', (tester) async {
    final r = AppRelease.fromJson(releaseJson(progress: 46, step: 'flutter build apk --release (arm64-v8a)', log: sampleLog(60)));
    await expectNoLayoutErrors(tester, () => ReleaseDetailView(release: r, onCancel: () {}, onDownload: (_) {}));
  });

  testWidgets('detail: ready on Google Play with the files', (tester) async {
    final r = AppRelease.fromJson(releaseJson(
      status: 'ready',
      source: 'google_play',
      storeUrl: 'https://play.google.com/store/apps/details?id=com.doubley.nextbrain',
      autoPublish: false,
      progress: 100,
      log: sampleLog(12),
      artifacts: [...apkArtifacts, {'name': 'NextBrain-1.4.1-53.aab', 'size': 52000000, 'kind': 'aab'}],
    ));
    await expectNoLayoutErrors(tester, () => ReleaseDetailView(release: r, onPublish: () {}, onDownload: (_) {}, busy: 'artifact:NextBrain-1.4.1-53.aab'));
  });

  testWidgets('detail: failed, live, record only', (tester) async {
    final failed = AppRelease.fromJson(releaseJson(status: 'failed', progress: 18, error: 'The gate failed: 2 analyzer warnings', log: sampleLog(5)));
    final live = AppRelease.fromJson(releaseJson(status: 'live', isLive: true, policy: 'must', progress: 100, artifacts: apkArtifacts));
    final ios = AppRelease.fromJson(releaseJson(platform: 'ios', status: 'live', isLive: true));
    for (final r in [failed, live, ios]) {
      await expectNoLayoutErrors(tester, () => ReleaseDetailView(release: r, onRetry: r.canRetry ? () {} : null, onRollback: r.canRollback ? () {} : null));
    }
  });

  testWidgets('token sheet', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const Align(
        alignment: Alignment.bottomCenter,
        child: Material(child: BuilderTokenSheet(token: 'nbb_6f1d0c5e2a9b47d8a3c1e0f9b8a7d6c5e4f3a2b1c0d9e8f7')),
      ),
    );
  });

  testWidgets('web strip: must and recommended', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        WebReleaseStrip(must: true, version: '1.4.1', onReload: () {}),
        WebReleaseStrip(must: false, version: '1.4.1', onReload: () {}, onDismiss: () {}),
      ]),
    );
  });

  testWidgets('update dialog: store sources', (tester) async {
    for (final source in const ['google_play', 'app_store', 'custom', 'website']) {
      await expectNoLayoutErrors(
        tester,
        () => UpdateDialog(force: source == 'app_store', version: '1.4.1', notes: 'Faster lessons', source: source, onUpdate: () {}, onLater: () {}),
      );
    }
  });
}
