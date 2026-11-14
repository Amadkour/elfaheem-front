// Every link the app hands to the OS goes through openExternalLink (lib/core/share/external_link.dart, security S5),
// which allows https only (+ mailto / tel on request). This guard reads lib/ and fails on a raw url_launcher call
// anywhere else. A deliberate exception goes in [_allowed] with the number of calls and the reason; an entry that is
// no longer needed fails too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _raw = RegExp(r'\b(launchUrl|launchUrlString|canLaunchUrl|canLaunch|launch)\s*\(');

/// path (under lib/) → (calls, why).
const _allowed = <String, (int, String)>{
  'core/share/external_link.dart': (1, 'the helper itself'),
  'features/auth/verified_screen.dart':
      (2, "the Telegram app: a fixed tg://resolve probe, and the server's tg:// link checked to be tg:// only"),
};

void main() {
  test('the guard sees every url_launcher entry point', () {
    for (final bad in ['launchUrl(u)', 'await launchUrlString(s)', 'canLaunchUrl(u)', 'canLaunch(s)', 'launch (s)']) {
      expect(_raw.hasMatch(bad), isTrue, reason: bad);
    }
    for (final fine in ['openExternalLink(s)', '_launch(s)', 'onLaunch(x)', 'relaunch(x)']) {
      expect(_raw.hasMatch(fine), isFalse, reason: fine);
    }
  });

  test('no raw launchUrl in lib/ outside openExternalLink', () {
    final problems = <String>[];
    final seen = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final path = f.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^lib/'), '');
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (!_raw.hasMatch(code)) continue;
        seen[path] = (seen[path] ?? 0) + _raw.allMatches(code).length;
        if (!_allowed.containsKey(path)) {
          problems.add('lib/$path:${i + 1} calls url_launcher directly: use openExternalLink (core/share/external_link.dart)');
        }
      }
    }
    for (final MapEntry(key: path, value: (n, why)) in _allowed.entries) {
      if (seen[path] != n) problems.add('allowlist lib/$path expects $n call(s) ($why), found ${seen[path] ?? 0}');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
