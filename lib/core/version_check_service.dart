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
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../design/app_notice.dart';
import '../design/app_tokens.dart';
import '../main.dart'; // navigatorKey
import '../features/shared/get_app/get_app_sheet.dart' show getAppLtr;
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
@visibleForTesting
bool updateSnoozed(String? stored, int build, DateTime now) {
  if (stored == null) return false;
  final parts = stored.split(':');
  if (parts.length != 2 || int.tryParse(parts[0]) != build) return false;
  final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[1]) ?? 0);
  return now.difference(at) < kUpdateSnooze && !at.isAfter(now.add(const Duration(days: 1)));
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
    final manifest = await fetchReleasesManifest(releasesManifestUriFor(AppConfig.baseUrl));
    final release = manifest[key];
    final need = updateNeedFor(installedBuild: installed, release: release);
    if (need == UpdateNeed.none || release == null) return;
    if (AppConfig.disableList.contains(kUpdatePromptKey)) return;

    final prefs = await SharedPreferences.getInstance();
    if (need == UpdateNeed.suggest && updateSnoozed(prefs.getString(_laterKey), release.build, DateTime.now())) return;

    String? arch;
    if (key == 'android') {
      try {
        final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
        if (abis.isNotEmpty) arch = abis.first;
      } catch (_) {}
    }
    final file = release.primaryFile(archHint: arch);
    if (file == null) return;

    // the first frame may not be up yet on a fast answer
    for (var i = 0; i < 20 && navigatorKey.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showDialog<void>(
      context: ctx,
      barrierDismissible: need != UpdateNeed.force,
      builder: (dctx) => UpdateDialog(
        force: need == UpdateNeed.force,
        version: release.version,
        size: formatReleaseSize(file.size),
        notes: release.notes(AppConfig.lang),
        onUpdate: () => _open(file.url),
        onLater: () {
          prefs.setString(_laterKey, '${release.build}:${DateTime.now().millisecondsSinceEpoch}');
          Navigator.of(dctx).pop();
        },
      ),
    );
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) showAppNotice('get_app_open_failed'.tr, error: true);
    } catch (_) {
      showAppNotice('get_app_open_failed'.tr, error: true);
    }
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
  });

  final bool force;
  final String version;
  final String size;
  final String notes;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4);
    final body = (force ? 'get_app_update_body_force' : 'get_app_update_body').tr.replaceAll('{v}', getAppLtr(version));
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
            const SizedBox(height: AppSpace.sm),
            Text('get_app_update_hint'.tr, style: meta),
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
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('get_app_update_now'.tr,
                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
