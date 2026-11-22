// The update offer's installer per platform (Learning Hub Phase 9, N5): Windows opens the setup .exe, macOS the .dmg,
// Linux the kind the app was installed from, Android the APK for the phone's CPU; the Play .aab is never offered
// (lib/core/get_app/releases_manifest.dart, lib/core/version_check_service.dart).
import 'package:flutter_education_app/core/get_app/releases_manifest.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'https://alfheemacademy.com/releases';

Map<String, Object?> _file(String arch, String kind, String name) =>
    {'arch': arch, 'kind': kind, 'url': '$_base/$name', 'size': 1000, 'sha256': 'a' * 64};

Map<String, Object?> _entry(String primary, List<Map<String, Object?>> files) =>
    {'version': '1.4.0', 'build': 40, 'min_build': 0, 'primary': primary, 'files': files, 'pwa': false};

final ReleasesManifest _manifest = parseReleasesManifest({
  'schema': 1,
  'platforms': {
    'android': _entry('arm64-v8a', [
      _file('universal', 'aab', 'android/Alfaheem-1.4.0-40.aab'),
      _file('arm64-v8a', 'apk', 'android/Alfaheem-1.4.0-40-arm64-v8a.apk'),
      _file('armeabi-v7a', 'apk', 'android/Alfaheem-1.4.0-40-armeabi-v7a.apk'),
      _file('universal', 'apk', 'android/Alfaheem-1.4.0-40-universal.apk'),
    ]),
    'windows': _entry('x64', [
      _file('x64', 'zip', 'windows/Alfaheem-1.4.0-40-windows-x64.zip'),
      _file('x64', 'exe', 'windows/Alfaheem-1.4.0-windows-x64-setup.exe'),
    ]),
    'macos': _entry('universal', [
      _file('universal', 'zip', 'macos/Alfaheem-1.4.0-40-macos.zip'),
      _file('universal', 'dmg', 'macos/Alfaheem-1.4.0-40-macos.dmg'),
    ]),
    'linux': _entry('x64', [
      _file('x64', 'deb', 'linux/Alfaheem-1.4.0-40-x64.deb'),
      _file('x64', 'tar.gz', 'linux/Alfaheem-1.4.0-40-x64.tar.gz'),
      _file('x64', 'AppImage', 'linux/Alfaheem-1.4.0-40-x64.AppImage'),
    ]),
  },
});

void main() {
  test('the aab is dropped from the manifest, never offered', () {
    final android = _manifest['android']!;
    expect(android.files.map((f) => f.kind), everyElement('apk'));
    expect(android.files.length, 3);
    final listedFalse = parseReleasesManifest({
      'platforms': {
        'android': _entry('universal', [
          {..._file('universal', 'apk', 'a.apk'), 'listed': false},
        ]),
      },
    });
    expect(listedFalse['android'], isNull);
  });

  test('android: the APK for the phone CPU, else the primary', () {
    final r = _manifest['android'];
    expect(updateFileFor('android', r, archHint: 'armeabi-v7a')!.fileName, 'Alfaheem-1.4.0-40-armeabi-v7a.apk');
    expect(updateFileFor('android', r, archHint: 'x86_64')!.fileName, 'Alfaheem-1.4.0-40-arm64-v8a.apk');
    expect(updateFileFor('android', r)!.kind, 'apk');
  });

  test('windows: the setup exe before the zip', () {
    final r = _manifest['windows'];
    expect(updateFileFor('windows', r, archHint: 'x64')!.fileName, 'Alfaheem-1.4.0-windows-x64-setup.exe');
    // an arm64 PC with only x64 files falls back to the primary arch, still the installer
    expect(updateFileFor('windows', r, archHint: 'arm64')!.kind, 'exe');
  });

  test('macos: the dmg before the zip', () {
    expect(updateFileFor('macos', _manifest['macos'], archHint: 'arm64')!.kind, 'dmg');
  });

  test('linux: the kind the app was installed from, the AppImage by default', () {
    final r = _manifest['linux'];
    expect(updateFileFor('linux', r, archHint: 'x64')!.kind, 'AppImage');
    expect(updateFileFor('linux', r, archHint: 'x64', linuxKind: 'deb')!.kind, 'deb');
    expect(updateFileFor('linux', r, archHint: 'x64', linuxKind: 'tar.gz')!.kind, 'tar.gz');
    expect(linuxInstalledKind(environment: {'APPIMAGE': '/home/a/Alfaheem.AppImage'}, executable: '/tmp/.mount_x/nextbrain'),
        'AppImage');
    expect(linuxInstalledKind(environment: const {}, executable: '/opt/nextbrain/nextbrain'), 'deb');
    expect(linuxInstalledKind(environment: const {}, executable: '/home/a/nextbrain/nextbrain'), 'tar.gz');
  });

  test('the CPU from Platform.version', () {
    expect(archFromDartVersion('3.9.0 (stable) (Tue) on "windows_x64"'), 'x64');
    expect(archFromDartVersion('3.9.0 (stable) (Tue) on "macos_arm64"'), 'arm64');
    expect(archFromDartVersion('3.9.0 (stable) on "linux_riscv64"'), isNull);
    expect(archFromDartVersion(''), isNull);
  });

  test('nothing published for the platform gives no file', () {
    expect(updateFileFor('windows', null), isNull);
    expect(updateFileFor('ios', _manifest['ios']), isNull);
  });
}
