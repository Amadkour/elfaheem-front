/// core/device_id_service.dart
///
/// Stable per-install device identity sent to the server as `X-Device-Id`.
///   pubspec.yaml ->  device_info_plus: ^10.0.0
///                    android_id: ^0.4.0
///                    flutter_secure_storage: ^9.0.0
///                    uuid: ^4.0.0
library;

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  DeviceIdService._();
  static final DeviceIdService instance = DeviceIdService._();

  static const _kKey = 'device_uuid_v1';
  final _storage = const FlutterSecureStorage();

  String? _id;
  String? _name;

  Future<String> id() async {
    if (_id != null) return _id!;
    String? hw;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        hw = await const AndroidId().getId(); // survives reinstall
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        hw = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } catch (_) {}
    if (hw != null && hw.isNotEmpty) return _id = 'hw-$hw';

    var saved = await _storage.read(key: _kKey);
    if (saved == null || saved.isEmpty) {
      saved = const Uuid().v4();
      await _storage.write(key: _kKey, value: saved);
    }
    return _id = 'app-$saved';
  }

  Future<String> name() async {
    if (_name != null) return _name!;
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        _name = (await info.webBrowserInfo).browserName.name;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await info.androidInfo;
        _name = '${a.manufacturer} ${a.model}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        _name = (await info.iosInfo).utsname.machine;
      }
    } catch (_) {}
    return _name ??= 'Unknown device';
  }

  /// Merge these into EVERY authenticated request.
  Future<Map<String, String>> headers() async => {
        'X-Device-Id': await id(),
        // header values must be latin-1; encode the name to be safe
        'X-Device-Name': Uri.encodeComponent(await name()),
      };
}
