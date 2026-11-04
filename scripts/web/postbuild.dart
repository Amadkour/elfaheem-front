// Post-build step for the Flutter web release (cold start: cacheable file names, precompressed files).
//
//   dart run scripts/web/postbuild.dart build/web [--self-host-canvaskit] [--no-hash] [--no-compress]
//
// What it does, in this order; every step is idempotent (a second run on the same folder changes nothing):
//   0. scripts/web/prune_font_manifest.dart, when that file exists, rewrites assets/FontManifest.json first,
//      so the hash and the compressed copies are of the final bytes.
//   1. main.dart.js is renamed to main.dart.<hash8>.js and `mainJsPath` in flutter_bootstrap.js is patched, so the
//      file can be cached `immutable`. dart2js writes the names of the deferred parts INTO the main file
//      (`deferredPartUris:["main.dart.js_1.part.js"]`, resolved against the main script's own URL), so renaming only
//      the main file would break every `deferred as` import: the parts are renamed with it
//      (main.dart.<hash8>.js_1.part.js) and those names (and the source-map names) are rewritten inside the files.
//      The hash covers the main file and all parts, so a changed part always changes every name.
//   2. --self-host-canvaskit (default off): the CanvasKit runtime moves to canvaskit/<engineRevision>/ and the loader
//      is pointed at it with `canvasKitBaseUrl`, so it can be cached `immutable` and does not depend on gstatic.
//   3. Every compressible file of 1 KB or more gets a .gz (level 9) and, when the `brotli` command exists, a .br
//      (quality 11; --brotli-quality=N lowers it: 11 takes minutes on the 18 MB main script, a lower one is much faster and a little bigger)
//      next to it, for nginx `gzip_static` / `brotli_static`. A size table is printed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Extensions worth compressing (png, jpg, webp, mp4 and woff2 are already compressed and are left alone).
const compressibleExtensions = {
  '.js', '.mjs', '.wasm', '.json', '.ttf', '.otf', '.css', '.html', '.svg', '.txt', '.bin', '.map', '.xml',
};

/// Smaller files cost more in headers than they save.
const minCompressBytes = 1024;

/// The first [length] hex characters of the SHA-256 of [chunks] taken one after the other.
String contentHash(Iterable<List<int>> chunks, {int length = 8}) {
  final all = BytesBuilder(copy: false);
  for (final c in chunks) {
    all.add(c);
  }
  return sha256.convert(all.takeBytes()).toString().substring(0, length);
}

/// `main.dart.<hash>.js`.
String hashedMainName(String hash) => 'main.dart.$hash.js';

final _mainRef = RegExp(r'main\.dart\.js(_\d+\.part\.js(?:\.map)?|\.map)?');

// The loader code is inlined in the bootstrap and spells canvasKitBaseUrl itself: only our own value counts.
const _selfHosted = 'canvasKitBaseUrl: "canvaskit/';

String _stem(String newMain) => newMain.substring(0, newMain.length - 3);

/// The new name of a build-folder file: `main.dart.js` -> [newMain]; `main.dart.js_3.part.js` and the `.map` files
/// keep their suffix on [newMain]; every other file keeps its name.
String renamedFile(String file, String newMain) {
  final m = _mainRef.firstMatch(file);
  if (m == null || m.start != 0 || m.end != file.length) return file;
  return '${_stem(newMain)}.js${m.group(1) ?? ''}';
}

/// Rewrites the part and map names that a main / part file spells out in its own text.
String rewriteMainRefs(String js, String newMain) =>
    js.replaceAllMapped(_mainRef, (m) => '${_stem(newMain)}.js${m.group(1) ?? ''}');

/// Patches `"mainJsPath":"<old>"` in the generated bootstrap. Returns the text unchanged when it already names
/// [newMain] (a second run) and null when there is no mainJsPath to patch.
String? patchMainJsPath(String bootstrap, String newMain) {
  final re = RegExp(r'"mainJsPath"\s*:\s*"([^"]*)"');
  final m = re.firstMatch(bootstrap);
  if (m == null) return null;
  if (m.group(1) == newMain) return bootstrap;
  return bootstrap.replaceFirst(re, '"mainJsPath":"$newMain"');
}

/// The engine revision from the generated build config (`"engineRevision":"<sha>"`), or null.
String? engineRevisionOf(String bootstrap) =>
    RegExp(r'"engineRevision"\s*:\s*"([0-9a-fA-F]+)"').firstMatch(bootstrap)?.group(1);

/// Points the loader at a CanvasKit folder: a bare `_flutter.loader.load()` becomes
/// `_flutter.loader.load({config: {canvasKitBaseUrl: "<base>"}})` (an existing argument object gets the key added).
/// Idempotent; null when no such call is found.
String? patchCanvasKitBase(String bootstrap, String base) {
  if (bootstrap.contains(_selfHosted)) return bootstrap;
  final cfg = 'config: {canvasKitBaseUrl: "$base"}';
  const bare = '_flutter.loader.load()';
  if (bootstrap.contains(bare)) return bootstrap.replaceFirst(bare, '_flutter.loader.load({$cfg})');
  const withArgs = '_flutter.loader.load({';
  if (bootstrap.contains(withArgs)) return bootstrap.replaceFirst(withArgs, '$withArgs$cfg, ');
  return null;
}

/// Whether [relPath] (forward slashes, relative to the build folder) gets a compressed copy.
bool shouldCompress(String relPath, int size) {
  if (size < minCompressBytes) return false;
  if (relPath.endsWith('.gz') || relPath.endsWith('.br')) return false;
  final dot = relPath.lastIndexOf('.');
  if (dot < 0 || relPath.lastIndexOf('/') > dot) return false;
  return compressibleExtensions.contains(relPath.substring(dot).toLowerCase());
}

String _rel(Directory root, FileSystemEntity e) {
  var p = e.path.substring(root.path.length).replaceAll('\\', '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  return p;
}

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.length != 1) {
    stderr.writeln('usage: dart run scripts/web/postbuild.dart <build/web> [--self-host-canvaskit] [--no-hash] [--no-compress] [--brotli-quality=N]');
    exit(2);
  }
  final root = Directory(paths.single);
  if (!root.existsSync()) {
    stderr.writeln('no such folder: ${root.path}');
    exit(2);
  }

  // 0. the font-manifest prune step (written by another change; absent is fine)
  final scriptDir = File.fromUri(Platform.script).parent.path;
  final prune = File('$scriptDir/prune_font_manifest.dart');
  if (prune.existsSync()) {
    stdout.writeln('prune: ${prune.path}');
    final r = await Process.run(Platform.resolvedExecutable, ['run', prune.path, root.path]);
    stdout.write(r.stdout);
    if (r.exitCode != 0) {
      stderr.write(r.stderr);
      stderr.writeln('prune_font_manifest failed (exit ${r.exitCode}); continuing without it');
    }
  }

  final bootstrapFile = File('${root.path}/flutter_bootstrap.js');
  if (!bootstrapFile.existsSync()) {
    stderr.writeln('${bootstrapFile.path} is missing: is this a flutter build web output?');
    exit(1);
  }
  var bootstrap = bootstrapFile.readAsStringSync();

  // 1. content-hashed main file
  if (!flags.contains('--no-hash')) {
    if (File('${root.path}/main.dart.js').existsSync()) {
      final siblings = [
        for (final e in root.listSync())
          if (e is File && renamedFile(e.uri.pathSegments.last, 'x.js') != e.uri.pathSegments.last) e,
      ]..sort((a, b) => a.path.compareTo(b.path));
      final code = siblings.where((e) => !e.path.endsWith('.map'));
      final name = hashedMainName(contentHash(code.map((e) => e.readAsBytesSync())));
      for (final e in siblings) {
        final text = rewriteMainRefs(e.readAsStringSync(), name);
        File('${root.path}/${renamedFile(e.uri.pathSegments.last, name)}').writeAsStringSync(text);
        e.deleteSync();
      }
      final patched = patchMainJsPath(bootstrap, name);
      if (patched == null) {
        stderr.writeln('flutter_bootstrap.js has no mainJsPath: the build config was not injected');
        exit(1);
      }
      bootstrap = patched;
      stdout.writeln('main: main.dart.js -> $name (${siblings.length - 1} parts / maps renamed with it)');
    } else {
      stdout.writeln('main: no main.dart.js (already hashed)');
    }
    bootstrapFile.writeAsStringSync(bootstrap); // before anything else can fail: the renamed files and this belong together
  }

  // 2. CanvasKit from the build
  if (flags.contains('--self-host-canvaskit')) {
    final rev = engineRevisionOf(bootstrap);
    final dir = Directory('${root.path}/canvaskit');
    if (rev == null) {
      stderr.writeln('no engineRevision in flutter_bootstrap.js; CanvasKit left on the CDN');
    } else if (bootstrap.contains(_selfHosted)) {
      stdout.writeln('canvaskit: already self-hosted');
    } else if (!dir.existsSync()) {
      stderr.writeln('build/web/canvaskit is missing: build with --no-web-resources-cdn');
      exit(1);
    } else {
      final patched = patchCanvasKitBase(bootstrap, 'canvaskit/$rev/');
      if (patched == null) {
        stderr.writeln('flutter_bootstrap.js has no _flutter.loader.load( call to configure');
        exit(1);
      }
      bootstrap = patched;
      final entries = dir.listSync();
      final target = Directory('${dir.path}/$rev')..createSync();
      for (final e in entries) {
        e.renameSync('${target.path}/${e.uri.pathSegments.where((s) => s.isNotEmpty).last}');
      }
      stdout.writeln('canvaskit: canvaskit/$rev/');
    }
  }
  bootstrapFile.writeAsStringSync(bootstrap);

  // 3. precompress
  if (!flags.contains('--no-compress')) {
    final selfHosted = bootstrap.contains(_selfHosted);
    final q = flags.where((f) => f.startsWith('--brotli-quality=')).map((f) => int.tryParse(f.split('=')[1])).firstOrNull;
    final brotliQuality = (q ?? 11).clamp(1, 11);
    final hasBrotli = await _hasBrotli();
    if (!hasBrotli) stdout.writeln('brotli: command not found, only .gz written');
    final rows = <List<String>>[];
    var raw = 0, gz = 0, br = 0;
    final files = root.listSync(recursive: true).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final rel = _rel(root, file);
      // the build folder always holds canvaskit/, but without --self-host-canvaskit nothing serves it (gstatic does)
      if (!selfHosted && rel.startsWith('canvaskit/')) continue;
      final size = file.lengthSync();
      if (!shouldCompress(rel, size)) continue;
      final gzBytes = GZipCodec(level: 9).encode(file.readAsBytesSync());
      File('${file.path}.gz').writeAsBytesSync(gzBytes);
      var brSize = -1;
      if (hasBrotli) {
        final r = await Process.run('brotli', ['-q', '$brotliQuality', '-f', '-o', '${file.path}.br', file.path]);
        if (r.exitCode == 0) brSize = File('${file.path}.br').lengthSync();
      }
      raw += size;
      gz += gzBytes.length;
      if (brSize >= 0) br += brSize;
      rows.add([rel, '$size', '${gzBytes.length}', brSize >= 0 ? '$brSize' : '-']);
    }
    rows.sort((a, b) => int.parse(b[1]).compareTo(int.parse(a[1])));
    stdout.writeln('\n${'file'.padRight(52)} ${'raw'.padLeft(10)} ${'gzip'.padLeft(10)} ${'brotli'.padLeft(10)}');
    for (final r in rows.take(25)) {
      stdout.writeln('${r[0].padRight(52)} ${r[1].padLeft(10)} ${r[2].padLeft(10)} ${r[3].padLeft(10)}');
    }
    if (rows.length > 25) stdout.writeln('... ${rows.length - 25} more');
    stdout.writeln('${'TOTAL (${rows.length} files)'.padRight(52)} ${'$raw'.padLeft(10)} ${'$gz'.padLeft(10)} ${(hasBrotli ? '$br' : '-').padLeft(10)}');
  }
  stdout.writeln(jsonEncode({'postbuild': 'ok'}));
}

Future<bool> _hasBrotli() async {
  try {
    return (await Process.run('brotli', ['--version'])).exitCode == 0;
  } catch (_) {
    return false;
  }
}
