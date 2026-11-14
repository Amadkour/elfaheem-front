// The pure parts of scripts/web/postbuild.dart: content hash, the renamed main file with its deferred parts, the
// bootstrap patches and which files get a compressed copy. The end-to-end proof (a deferred part still loads after the
// rename, nginx serves it over h2) is in the cold-start notes, not in CI.
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/web/postbuild.dart';

void main() {
  const bootstrap = '_flutter.buildConfig = {"engineRevision":"abc123def456","builds":'
      '[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};\n'
      '_flutter.loader.load();\n';

  test('the hash depends on every chunk and is 8 hex characters', () {
    final a = contentHash([
      [1, 2, 3],
      [4],
    ]);
    expect(a, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(
      contentHash([
        [1, 2, 3],
        [5],
      ]),
      isNot(a),
    );
    expect(
      contentHash([
        [1, 2, 3],
        [4],
      ]),
      a,
    );
    expect(hashedMainName(a), 'main.dart.$a.js');
  });

  test('the main file, its parts and maps are renamed together; other files are not', () {
    const n = 'main.dart.0a1b2c3d.js';
    expect(renamedFile('main.dart.js', n), n);
    expect(renamedFile('main.dart.js_12.part.js', n), '${n}_12.part.js');
    expect(renamedFile('main.dart.js_1.part.js.map', n), '${n}_1.part.js.map');
    expect(renamedFile('main.dart.js.map', n), '$n.map');
    expect(renamedFile('flutter.js', n), 'flutter.js');
    expect(renamedFile('e2ee.worker.dart.js', n), 'e2ee.worker.dart.js');
    expect(renamedFile('main.dart.js.symbols', n), 'main.dart.js.symbols');
    expect(renamedFile(n, n), n, reason: 'a second run leaves a hashed name alone');
  });

  test('the part and map names spelled out inside the code follow the rename', () {
    const n = 'main.dart.0a1b2c3d.js';
    const js = 'deferredPartUris:["main.dart.js_1.part.js","main.dart.js_2.part.js"],\n//# sourceMappingURL=main.dart.js.map';
    final out = rewriteMainRefs(js, n);
    expect(out, contains('"${n}_1.part.js"'));
    expect(out, contains('"${n}_2.part.js"'));
    expect(out, endsWith('sourceMappingURL=$n.map'));
    expect(rewriteMainRefs(out, n), out, reason: 'idempotent');
  });

  test('mainJsPath is patched once', () {
    final once = patchMainJsPath(bootstrap, 'main.dart.0a1b2c3d.js')!;
    expect(once, contains('"mainJsPath":"main.dart.0a1b2c3d.js"'));
    expect(once, isNot(contains('"main.dart.js"')));
    expect(patchMainJsPath(once, 'main.dart.0a1b2c3d.js'), once);
    expect(patchMainJsPath('no config here', 'x.js'), isNull);
  });

  test('CanvasKit base: the revision is read and the loader call gets the config once', () {
    expect(engineRevisionOf(bootstrap), 'abc123def456');
    final bare = patchCanvasKitBase(bootstrap, 'canvaskit/abc123def456/')!;
    expect(bare, contains('_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit/abc123def456/"}});'));
    expect(patchCanvasKitBase(bare, 'canvaskit/abc123def456/'), bare);
    final withArgs = patchCanvasKitBase('_flutter.loader.load({serviceWorkerSettings: {}});', 'canvaskit/r/')!;
    expect(withArgs, '_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit/r/"}, serviceWorkerSettings: {}});');
    expect(patchCanvasKitBase('nothing', 'canvaskit/r/'), isNull);
  });

  test('which files are precompressed', () {
    expect(shouldCompress('main.dart.0a1b2c3d.js', 5000000), isTrue);
    expect(shouldCompress('canvaskit/abc/canvaskit.wasm', 6000000), isTrue);
    expect(shouldCompress('assets/assets/translation.json', 90000), isTrue);
    expect(shouldCompress('assets/AssetManifest.bin', 2000), isTrue);
    expect(shouldCompress('assets/fonts/MaterialIcons-Regular.otf', 1500000), isTrue);
    expect(shouldCompress('flutter.js', 1023), isFalse, reason: 'under 1 KB');
    expect(shouldCompress('icons/Icon-192.png', 50000), isFalse);
    expect(shouldCompress('splash/video.mp4', 5000000), isFalse);
    expect(shouldCompress('main.dart.js.gz', 5000000), isFalse);
    expect(shouldCompress('main.dart.js.br', 5000000), isFalse);
    expect(shouldCompress('assets/NOTICES', 90000), isFalse, reason: 'no extension');
    expect(shouldCompress('a.b/NOTICES', 90000), isFalse, reason: 'the dot is in a folder name');
  });
}
