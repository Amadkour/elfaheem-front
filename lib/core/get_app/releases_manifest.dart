// lib/core/get_app/releases_manifest.dart — the releases manifest, `<site>/releases/releases.json` (pure Dart, unit-tested
// in test/ui/get_app_test.dart). It is written by scripts/release/publish_release.py and read by the web banner
// (which build to offer) and by the native apps on launch (is there a newer build, must they update).
//
//   {
//     "schema": 1,
//     "updated_at": "2026-10-31T21:40:00Z",
//     "platforms": {
//       "android": {
//         "version": "1.0.0", "build": 1, "min_build": 1, "released_at": "2026-10-31", "min_os": "Android 7.0",
//         "notes": {"ar": "…", "en": "…"},
//         "primary": "arm64-v8a",                    // the file the banner's button downloads ("pwa" = install the web app)
//         "files": [{"arch": "arm64-v8a", "kind": "apk", "url": "https://…/Alfaheem-1.0.0-1-arm64-v8a.apk",
//                    "size": 48700000, "sha256": "…"}, …],
//         "pwa": false                               // also offer installing the web app from the browser
//       },
//       "ios": {"pwa": true}, "windows": {"pwa": true}, "macos": {"pwa": true}, "linux": {…}
//     }
//   }
//
// A platform that is missing, has no usable file and no `pwa` is not offered (never a guessed link). File URLs must be
// https (a relative URL is resolved against the manifest's own URL); anything else is dropped.
library;

/// The manifest's platform keys. iPadOS reads `ios`.
const List<String> kReleasePlatforms = ['android', 'ios', 'windows', 'macos', 'linux'];

/// One downloadable file.
class ReleaseFile {
  const ReleaseFile({required this.arch, required this.kind, required this.url, this.size, this.sha256});

  /// `universal`, `arm64-v8a`, `armeabi-v7a`, `x64`, `arm64`, …
  final String arch;

  /// `apk`, `deb`, `tar.gz`, `AppImage`, `msix`, `exe`, `dmg`, `zip`, …
  final String kind;
  final String url;

  /// Bytes, when known.
  final int? size;

  /// Lower-case hex SHA-256, when known.
  final String? sha256;

  /// The file name at the end of the URL.
  String get fileName {
    final segs = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    return segs.isEmpty ? url : segs.last;
  }
}

/// What is published for one platform.
class PlatformRelease {
  const PlatformRelease({
    required this.platform,
    this.version = '',
    this.build = 0,
    this.minBuild = 0,
    this.releasedAt,
    this.minOs = '',
    this.notesAr = '',
    this.notesEn = '',
    this.primary = '',
    this.files = const [],
    this.pwa = false,
  });

  final String platform;
  final String version;
  final int build;

  /// Installed builds below this one must update (0 = no forced update).
  final int minBuild;
  final DateTime? releasedAt;
  final String minOs;
  final String notesAr;
  final String notesEn;

  /// The `arch` of the file the banner's button downloads, or `pwa` to offer the web app first.
  final String primary;
  final List<ReleaseFile> files;

  /// Installing the web app from the browser is offered on this platform.
  final bool pwa;

  bool get hasFiles => files.isNotEmpty;

  /// Something can be offered at all.
  bool get offered => hasFiles || pwa;

  /// The web app is the first thing offered (no file, or `primary: "pwa"` with `pwa: true`).
  bool get pwaFirst => pwa && (!hasFiles || primary == 'pwa');

  String notes(String lang) => lang == 'ar' ? (notesAr.isNotEmpty ? notesAr : notesEn) : (notesEn.isNotEmpty ? notesEn : notesAr);

  /// The file the main button downloads: the one built for [archHint] (the device's CPU, when the browser says),
  /// else the `primary` arch, else `universal`, else the first file. Null when there is none.
  ReleaseFile? primaryFile({String? archHint}) {
    if (files.isEmpty) return null;
    if (archHint != null && archHint.isNotEmpty) {
      for (final f in files) {
        if (f.arch == archHint) return f;
      }
    }
    for (final f in files) {
      if (primary.isNotEmpty && f.arch == primary) return f;
    }
    for (final f in files) {
      if (f.arch == 'universal') return f;
    }
    return files.first;
  }
}

/// The parsed manifest.
class ReleasesManifest {
  const ReleasesManifest(this.platforms, {this.updatedAt});

  static const ReleasesManifest empty = ReleasesManifest({});

  final Map<String, PlatformRelease> platforms;
  final DateTime? updatedAt;

  /// The release for a manifest key (`android`, `ios`, …); null when nothing usable is published.
  PlatformRelease? operator [](String platform) {
    final r = platforms[platform];
    return r != null && r.offered ? r : null;
  }

  bool get isEmpty => !platforms.values.any((r) => r.offered);
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

String _str(Object? v) => v is String ? v.trim() : '';

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Reads the manifest JSON. [base] is the manifest's own URL (relative file URLs resolve against it). Never throws:
/// anything malformed gives [ReleasesManifest.empty] or drops the bad part.
ReleasesManifest parseReleasesManifest(Object? json, {Uri? base}) {
  if (json is! Map) return ReleasesManifest.empty;
  final plats = json['platforms'];
  if (plats is! Map) return ReleasesManifest.empty;
  final out = <String, PlatformRelease>{};
  for (final key in kReleasePlatforms) {
    final p = plats[key];
    if (p is! Map) continue;
    final files = <ReleaseFile>[];
    final rawFiles = p['files'];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        if (f is! Map) continue;
        final url = _safeUrl(_str(f['url']), base);
        if (url == null) continue;
        final sha = _str(f['sha256']).toLowerCase();
        final size = _int(f['size']);
        files.add(ReleaseFile(
          arch: _str(f['arch']).isEmpty ? 'universal' : _str(f['arch']),
          kind: _str(f['kind']),
          url: url,
          size: size > 0 ? size : null,
          sha256: _hex64.hasMatch(sha) ? sha : null,
        ));
      }
    }
    final notes = p['notes'];
    out[key] = PlatformRelease(
      platform: key,
      version: _str(p['version']),
      build: _int(p['build']),
      minBuild: _int(p['min_build']),
      releasedAt: DateTime.tryParse(_str(p['released_at'])),
      minOs: _str(p['min_os']),
      notesAr: notes is Map ? _str(notes['ar']) : '',
      notesEn: notes is Map ? _str(notes['en']) : '',
      primary: _str(p['primary']),
      files: files,
      pwa: p['pwa'] == true,
    );
  }
  return ReleasesManifest(out, updatedAt: DateTime.tryParse(_str(json['updated_at'])));
}

/// An absolute https URL with a host, or null.
String? _safeUrl(String raw, Uri? base) {
  if (raw.isEmpty) return null;
  var uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (!uri.hasScheme && base != null) uri = base.resolveUri(uri);
  if (uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.toString();
}

/// What the running native app should do about [release] (the manifest entry of its own platform).
enum UpdateNeed { none, suggest, force }

/// [installedBuild] is the app's build number (pubspec `+N`, Android versionCode). Unknown (≤ 0) never prompts.
UpdateNeed updateNeedFor({required int installedBuild, PlatformRelease? release}) {
  if (release == null || !release.hasFiles || installedBuild <= 0 || release.build <= 0) return UpdateNeed.none;
  if (release.minBuild > 0 && installedBuild < release.minBuild) return UpdateNeed.force;
  if (installedBuild < release.build) return UpdateNeed.suggest;
  return UpdateNeed.none;
}

/// "48.7 MB", "820 KB" (decimal units, like the browsers' download bars). Digits stay Latin in both languages.
String formatReleaseSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes >= 1000 * 1000 * 1000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
  return '${(bytes / 1e3).ceil()} KB';
}
