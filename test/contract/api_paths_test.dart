// API drift guard (Phase 9, D-026): every path the Exam Engine and RAG clients build on `$base` must exist in the
// backend's route snapshot (`test/contract/api_paths.json`, written by ../back/scripts/contract/export_api_paths.py
// --front, checked against the routers by the backend CI). A renamed or removed route fails here, not in production.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _call = RegExp(r'''_api\.(get|post|put|patch|delete|getBytes|postForBytes|postFiles|postForm|postMultipart)\s*(?:<[^>]*>)?\(\s*['"]\$base(/[^'"?]*)''');
final _param = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*');
final _serverParam = RegExp(r'\{[^}]*\}');

String _method(String m) => switch (m) {
      'getBytes' => 'GET',
      'postForBytes' || 'postFiles' || 'postForm' || 'postMultipart' => 'POST',
      _ => m.toUpperCase(),
    };

void main() {
  test('every engine / RAG call matches a backend route (method + path)', () {
    final snap = jsonDecode(File('test/contract/api_paths.json').readAsStringSync()) as Map<String, dynamic>;
    final known = <String>{
      for (final v in snap.values) for (final r in (v as List)) '$r'.replaceAll(_serverParam, '{}'),
    };
    final missing = <String>[];
    var checked = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      final baseLine = RegExp(r'static const base = ([^;]+);').firstMatch(src)?.group(1);
      if (baseLine == null) continue;
      final prefix = baseLine.contains('rag') ? '/api/v1/rag' : (baseLine.contains('exam') || baseLine.contains('ExamEngineApi') ? '/api/v1/exam' : null);
      if (prefix == null) continue;
      for (final m in _call.allMatches(src)) {
        final path = prefix + m.group(2)!.replaceAll(_param, '{}');
        final key = '${_method(m.group(1)!)} $path';
        checked++;
        if (!known.contains(key)) missing.add('$key  (${f.path})');
      }
    }
    expect(checked, greaterThan(20), reason: 'the scan found the clients');
    expect(missing, isEmpty, reason: 'calls with no backend route — the API changed or a path is mistyped:\n${missing.join('\n')}');
  });
}
