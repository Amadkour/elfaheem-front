/// Version check — the native apps, once at start-up (Workstream E of the direct-downloads job).
///
/// Reads the releases manifest (`<site>/releases/releases.json`, the same file the web banner reads, schema in
/// lib/core/get_app/releases_manifest.dart) and compares this app's build number (pubspec `+N` = Android versionCode)
/// with the build published for this platform:
///   • below `min_build`  → a blocking "Please update to continue" dialog (force update);
///   • below `build`      → a gentle "A new version is ready" dialog, "Later" hides it for 3 days for that build;
///   • otherwise, offline, no manifest, nothing published for this platform (iOS today) → nothing.
/// The button opens the file for this device (Android: the APK for the phone's CPU) in the browser, which downloads
/// it; installing it over the app keeps the data (same package, same signing key).
///
/// App versions from the dashboard (D-143): `GET /app/version-check` now also names the live release's `download_url`,
/// `source` (website | google_play | app_store | custom) and `notes` ({ar, en}). When it asks for an update AND names a
/// link, that answer wins ([serverUpdateOffer]): the dialog shows its notes and its button opens the store or the
/// website link. An older server (no `download_url`) or a failed call leaves the manifest rule above in charge.
///
/// App versions through Codemagic (D-144): the answer may name the `channel` (store | website) instead of a `source`.
/// store → the store button (Google Play on Android, the App Store elsewhere); website → `download_url` is the file on
/// our server (Android: the universal APK), opened in the browser to download. A path without a host
/// (`/api/v1/app/downloads/…`) is read against the API base. Without those fields nothing changes.
///
/// It never delays the launch: the check runs in the background and the dialog appears when the answer arrives.
/// Kill switch: `app.update_prompt`. The web build is always current and never checks.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../design/app_tokens.dart';
import '../main.dart'; // navigatorKey
import 'api_client.dart';
import 'cert_pin.dart' show CertPin, kPinUpdateCode;
import '../utils/remote_config_service.dart';
import 'release/app_downloads.dart' show resolveDownloadUrl;
import 'package:flutter_education_app/features/get_app/get_app_sheet.dart' show getAppLtr;
import 'display/app_fonts.dart';
import 'get_app/get_app_service.dart' show fetchReleasesManifest, releasesManifestUriFor;
import 'get_app/releases_manifest.dart';

/// Kill-switch key (services/feature_catalog.py).
const String kUpdatePromptKey = 'app.update_prompt';

/// SharedPreferences key: `<build>:<millis>` of the last "Later".
const String _laterKey = 'update_prompt_later_v1';

/// How long "Later" keeps one build's prompt away.
const Duration kUpdateSnooze = Duration(days: 3);

/// The manifest key of the running native app, or null (web).
String? nativeReleaseKey() {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return null;
}

/// The snooze rule: a suggestion is shown unless "Later" was tapped for this very build less than [kUpdateSnooze] ago.
/// [build] is the manifest's build number, or `v<version>` for a server offer.
@visibleForTesting
bool updateSnoozed(String? stored, Object build, DateTime now) {
  if (stored == null) return false;
  final parts = stored.split(':');
  if (parts.length != 2 || parts[0] != '$build') return false;
  final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[1]) ?? 0);
  return now.difference(at) < kUpdateSnooze && !at.isAfter(now.add(const Duration(days: 1)));
}

/// An update the server asks for and names the link of (D-143).
class ServerUpdateOffer {
  const ServerUpdateOffer({required this.force, required this.version, required this.url, this.source = 'website', this.notes = ''});

  final bool force;
  final String version;
  final String url;

  /// website | google_play | app_store | custom
  final String source;
  final String notes;
}

String _notesIn(Object? v, String lang) {
  if (v is Map) {
    final mine = '${v[lang] ?? ''}'.trim();
    if (mine.isNotEmpty) return mine;
    return '${v[lang == 'ar' ? 'en' : 'ar'] ?? ''}'.trim();
  }
  return v is String ? v.trim() : '';
}

/// The source the dialog's button speaks for: the server's `source`, or its D-144 `channel` (store → Google Play on
/// Android, the App Store elsewhere; website → a file to download).
String updateSourceOf(Map<String, dynamic> r, {String? platform}) {
  final source = '${r['source'] ?? ''}'.trim();
  final channel = '${r['channel'] ?? ''}'.trim();
  final store = platform == 'android' ? 'google_play' : 'app_store';
  if (source == 'store') return store;
  if (source.isNotEmpty && source != 'website') return source; // google_play | app_store | custom
  if (channel == 'store') return store;
  return 'website';
}

/// The update `GET /app/version-check` asks for, when it names an https link (null: no update, an older server
/// without `download_url`, or a link that is not https — the manifest decides then).
@visibleForTesting
ServerUpdateOffer? serverUpdateOffer(Map<String, dynamic> r, {required String lang, String? platform, String? apiBase}) {
  final must = r['must_update'] == true;
  if (!must && r['should_update'] != true) return null;
  final url = resolveDownloadUrl('${r['download_url'] ?? ''}'.trim(), apiBase: apiBase ?? AppConfig.baseUrl);
  final uri = Uri.tryParse(url);
  if (url.isEmpty || uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  var notes = _notesIn(r['notes'], lang);
  if (notes.isEmpty) notes = _notesIn(r['release_notes'], lang);
  return ServerUpdateOffer(
    force: must,
    version: '${r['latest_version'] ?? r['version'] ?? ''}',
    url: url,
    source: updateSourceOf(r, platform: platform),
    notes: notes,
  );
}

/// Why the app must update even though the version check gave no answer, as a translation key — or null.
///   • the version check failed on a refused certificate pin of the API host (D-946: the server shows a key this
///     build does not know), or such a refusal was seen on another call → `tls_pin_update_required`;
///   • the check gave no answer (unreachable) and Remote Config's `force_update_version` (outside the pin) names a
///     higher build than this one → `app_update_required_generic`.
/// A readable server answer always wins over Remote Config.
@visibleForTesting
String? updateBlockWithoutServer({
  required Object? serverAnswer,
  required bool pinFlag,
  required int rcMinBuild,
  required int installedBuild,
}) {
  if (serverAnswer is Map) return null;
  if (pinFlag || (serverAnswer is ApiException && serverAnswer.code == kPinUpdateCode)) return 'tls_pin_update_required';
  if (rcMinBuild > 0 && installedBuild > 0 && installedBuild < rcMinBuild) return 'app_update_required_generic';
  return null;
}

class VersionCheckService {
  VersionCheckService._();
  static final VersionCheckService instance = VersionCheckService._();

  /// Called once in start-up; returns at once (the check runs in the background).
  Future<void> checkOnStartup() async {
    final key = nativeReleaseKey();
    if (key == null) return;
    unawaited(_check(key).catchError((_) {}));
  }

  Future<void> _check(String key) async {
    final info = await PackageInfo.fromPlatform();
    final installed = int.tryParse(info.buildNumber) ?? 0;
    // both asked at once; either may fail on its own
    final asked = await Future.wait<Object?>([
      // the error is kept: a refused certificate pin (D-946) is itself a reason to update
      ApiClient.instance.checkVersion(version: info.version, platform: key).then<Object?>((m) => m, onError: (Object e) => e),
      fetchReleasesManifest(releasesManifestUriFor(AppConfig.baseUrl)).then<Object?>((m) => m, onError: (_) => null),
    ]);
    final server = asked[0] is Map<String, dynamic> ? serverUpdateOffer(asked[0] as Map<String, dynamic>, lang: AppConfig.lang, platform: key) : null;
    // Read outside the pinned client: the manifest (package:http, the system's trust) and Remote Config (Firebase).
    final block = updateBlockWithoutServer(
      serverAnswer: asked[0],
      pinFlag: CertPin.updateRequired,
      rcMinBuild: RemoteConfigService.instance.forceUpdateVersion,
      installedBuild: installed,
    );
    if (block == null && AppConfig.disableList.contains(kUpdatePromptKey)) return;

    final bool force;
    final String version, url, notes, source, snoozeId;
    var size = '';
    var message = '';
    if (server != null) {
      force = server.force;
      version = server.version;
      url = server.url;
      notes = server.notes;
      source = server.source;
      snoozeId = 'v${server.version}';
    } else {
      final manifest = asked[1] is ReleasesManifest ? asked[1] as ReleasesManifest : ReleasesManifest.empty;
      final release = manifest[key];
      final need = block != null ? UpdateNeed.force : updateNeedFor(installedBuild: installed, release: release);
      if (block != null && (release == null || release.build <= installed || release.primaryFile() == null)) {
        // Blocked, and the manifest names nothing newer: a blocking dialog whose button opens the site (Get the app).
        return _show(
          force: true,
          version: '',
          url: Uri.parse(AppConfig.baseUrl).replace(path: '/').toString(),
          source: 'custom',
          snoozeId: 'blocked',
          message: block.tr,
        );
      }
      if (block != null) message = block.tr;
      if (need == UpdateNeed.none || release == null) return;
      String? arch;
      if (key == 'android') {
        try {
          final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
          if (abis.isNotEmpty) arch = abis.first;
        } catch (_) {}
      }
      final file = release.primaryFile(archHint: arch);
      if (file == null) return;
      force = need == UpdateNeed.force;
      version = release.version;
      url = file.url;
      notes = release.notes(AppConfig.lang);
      source = 'website';
      size = formatReleaseSize(file.size);
      snoozeId = '${release.build}';
    }
    return _show(
        force: force, version: version, url: url, source: source, snoozeId: snoozeId, size: size, notes: notes, message: message);
  }

  Future<void> _show({
    required bool force,
    required String version,
    required String url,
    required String source,
    required String snoozeId,
    String size = '',
    String notes = '',
    String message = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force && updateSnoozed(prefs.getString(_laterKey), snoozeId, DateTime.now())) return;

    // the first frame may not be up yet on a fast answer
    for (var i = 0; i < 20 && navigatorKey.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showDialog<void>(
      context: ctx,
      barrierDismissible: !force,
      builder: (dctx) => UpdateDialog(
        force: force,
        version: version,
        size: size,
        notes: notes,
        source: source,
        message: message,
        onUpdate: () => _open(url),
        onLater: () {
          prefs.setString(_laterKey, '$snoozeId:${DateTime.now().millisecondsSinceEpoch}');
          Navigator.of(dctx).pop();
        },
      ),
    );
  }

  Future<void> _open(String url) async {
    await openExternalLink(url, failText: 'get_app_open_failed'.tr);
  }
}

/// The prompt over plain values (test/ui/get_app_test.dart lays it out). Force: no "Later", back does nothing.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.force,
    required this.version,
    required this.onUpdate,
    required this.onLater,
    this.size = '',
    this.notes = '',
    this.source = 'website',
    this.message = '',
  });

  final bool force;
  final String version;
  final String size;
  final String notes;

  /// Replaces the body when set (why the update is needed: a refused certificate pin, D-946).
  final String message;

  /// Where the button goes: website (a file to install) | google_play | app_store | custom (D-143).
  final String source;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4);
    final body = message.isNotEmpty
        ? message
        : (force ? 'get_app_update_body_force' : 'get_app_update_body').tr.replaceAll('{v}', getAppLtr(version));
    return PopScope(
      canPop: !force,
      child: AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        icon: Icon(Icons.system_update_rounded, color: c.primary, size: 32),
        title: Text(
          (force ? 'get_app_update_title_force' : 'get_app_update_title').tr,
          textAlign: TextAlign.center,
          style: AppType.section(context).copyWith(fontFamily: AppFonts.family),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(size.isEmpty ? body : '$body (${getAppLtr(size)})',
                style: AppType.row(context).copyWith(fontFamily: AppFonts.family, height: 1.4)),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text('${'get_app_whats_new'.tr}: $notes', style: meta),
            ],
            // the "open the file to install it" hint is for a downloaded file, not a store page
            if (source == 'website') ...[
              const SizedBox(height: AppSpace.sm),
              Text('get_app_update_hint'.tr, style: meta),
            ],
          ],
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: onLater,
              child: Text('get_app_update_later'.tr, style: TextStyle(fontFamily: AppFonts.family)),
            ),
          FilledButton.icon(
            onPressed: onUpdate,
            style: FilledButton.styleFrom(backgroundColor: c.primary, foregroundColor: c.onHero),
            icon: Icon(
                switch (source) {
                  'google_play' => Icons.shop_rounded,
                  'app_store' => Icons.storefront_rounded,
                  'custom' => Icons.open_in_new_rounded,
                  _ => Icons.download_rounded,
                },
                size: 18),
            label: Text(
                switch (source) {
                  'google_play' => 'get_app_update_open_play',
                  'app_store' => 'get_app_update_open_store',
                  'custom' => 'get_app_update_open_link',
                  _ => 'get_app_update_now',
                }.tr,
                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
