/// Version check service — called once at app startup.
///
/// • Reads the current app version from [package_info_plus].
/// • Hits GET /app/version-check on the backend.
/// • If [must_update] → shows a blocking dialog with a store deep-link.
/// • If [should_update] → shows a dismissible suggestion dialog.
/// • If up-to-date → silent, no UI shown.
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';           // navigatorKey
import 'api_client.dart';

class VersionCheckService {
  VersionCheckService._();
  static final VersionCheckService instance = VersionCheckService._();

  // ── Store URLs — update with your real app store IDs ─────────────────────
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.elfaheem.app';
  static const _appStoreUrl =
      'https://apps.apple.com/app/id000000000'; // replace with real ID

  // ── Public entry point ────────────────────────────────────────────────────

  /// Call once inside [_initCore] before [_runApp].
  /// Silently skips if the network call fails so a bad connection never
  /// prevents the app from starting.
  Future<void> checkOnStartup() async {
    try {
      final info     = await PackageInfo.fromPlatform();
      final version  = info.version;                          // e.g. "1.2.3"
      final platform = _platform();

      final result = await ApiClient.instance.checkVersion(
        version:  version,
        platform: platform,
      );

      final mustUpdate   = result['must_update']   == true;
      final shouldUpdate = result['should_update'] == true;
      final latest       = result['latest_version'] as String? ?? '';
      final notesMap     = result['release_notes'] as Map<String, dynamic>? ?? {};
      final notes        = (notesMap['ar'] ?? notesMap['en'] ?? '') as String;
      if (!mustUpdate && !shouldUpdate) return;

      final ctx = navigatorKey.currentContext;

      if (ctx == null || !ctx.mounted) return;

      await _showDialog(
        ctx,
        mustUpdate:  mustUpdate,
        latest:      latest,
        notes:       notes,
        storeUrl:    platform == 'ios' ? _appStoreUrl : _playStoreUrl,
      );

    } catch (_) {
      // Never block startup on a version-check failure
    }
  }

  // ── Dialog ────────────────────────────────────────────────────────────────

  Future<void> _showDialog(
    BuildContext context, {
    required bool   mustUpdate,
    required String latest,
    required String notes,
    required String storeUrl,
  }) {
    return showDialog(
      context:    context,
      barrierDismissible: !mustUpdate,   // force-update cannot be dismissed
      builder: (_) => WillPopScope(
        onWillPop: () async => !mustUpdate,
        child: AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Directionality(
            textDirection: Helpers.pageDirection,
            child: Row(
              children: [
                const Icon(Icons.system_update_rounded,
                    color: Color(0xFF5B8FFF), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mustUpdate ? 'تحديث إلزامي' : 'تحديث متاح',
                    style: const TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: Directionality(
            textDirection: Helpers.pageDirection,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mustUpdate
                      ? 'يجب تحديث التطبيق إلى الإصدار $latest للمتابعة.'
                      : 'يتوفر إصدار جديد ($latest). هل تريد التحديث الآن؟',
                  style: const TextStyle(fontFamily: 'bahji', fontSize: 14),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'ما الجديد:\n$notes',
                    style: const TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!mustUpdate)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3.0),
                  child: const Text('لاحقاً',
                      style: TextStyle(fontFamily: 'bahji')),
                ),
              ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B8FFF),
                padding: EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _openStore(storeUrl),
              icon: const Icon(Icons.download_rounded,
                  color: Colors.white, size: 18),
              label: const Text('تحديث الآن',
                  style: TextStyle(
                    fontFamily: 'bahji',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _openStore(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }
}
