// The sizes and themes a visual review renders at: the file's own, unless GOLDEN_SIZES (e.g. "320x640,1400x900") and
// GOLDEN_THEMES ("light", "dark" or "light,dark") say otherwise for one run.
//
//   GOLDEN_SIZES=320x640,1400x900 GOLDEN_THEMES=light flutter test test/visual/exam_take_golden_test.dart --update-goldens
import 'dart:io';
import 'dart:ui';

List<Size> goldenSizes(List<Size> own) {
  final raw = Platform.environment['GOLDEN_SIZES'];
  if (raw == null || raw.trim().isEmpty) return own;
  return [
    for (final p in raw.split(','))
      if (p.contains('x')) Size(double.parse(p.split('x')[0].trim()), double.parse(p.split('x')[1].trim())),
  ];
}

List<bool> goldenThemes() {
  final raw = Platform.environment['GOLDEN_THEMES'];
  if (raw == null || raw.trim().isEmpty) return const [false, true];
  return [for (final p in raw.split(',')) p.trim() == 'dark'];
}
