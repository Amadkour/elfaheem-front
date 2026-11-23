// Games v4 T85: the ayah timing tool: the draft rules (prefix marks, contiguous starts, nudges, the save body) and the
// editor and surah list lay out at 320 and 1400 px, ar + en, text 1.3 (expectNoLayoutErrors).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/v4/timing_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  test('draft: marks fill from the top and starts follow the previous end', () {
    final d = TimingDraft(3, start0: 1200);
    expect(d.mark(1000), isFalse); // before the start
    expect(d.mark(5000), isTrue);
    expect(d.mark(9000), isTrue);
    expect(d.startOf(1), 5000);
    expect(d.nextToMark, 2);
    expect(d.toBody(), [
      {'ayah': 1, 'start_ms': 1200, 'end_ms': 5000},
      {'ayah': 2, 'start_ms': 5000, 'end_ms': 9000},
    ]);
    expect(d.mark(9000), isFalse); // a zero-length ayah
  });

  test('draft: nudges move a shared edge and never cross a neighbour', () {
    final d = TimingDraft(3, ends: [5000, 9000, null]);
    expect(d.nudgeEnd(0, 100), isTrue);
    expect(d.startOf(1), 5100);
    expect(d.nudgeEnd(0, 4000), isFalse); // would reach the end of ayah 2
    expect(d.nudgeEnd(1, -3900), isFalse); // would reach the start of ayah 2
    expect(d.nudgeEnd(2, 100), isFalse); // not marked
    expect(d.nudgeStart0(100), isTrue);
    expect(d.nudgeStart0(-200), isFalse); // below zero
    d.clearFrom(1);
    expect(d.marked, 1);
  });

  test('draft from the server keeps the leading run and the first start', () {
    final d = TimingDraft.fromServer([
      {'ayah': 1, 'start_ms': 700, 'end_ms': 3000},
      {'ayah': 2, 'start_ms': null, 'end_ms': null},
      {'ayah': 3, 'start_ms': 4000, 'end_ms': 6000},
    ]);
    expect((d.start0, d.marked), (700, 1));
  });

  final ayat = [
    for (var i = 1; i <= 6; i++) {'ayah': i, 'text': 'نص آية طويل جداً لاختبار الالتفاف في الشاشات الضيقة رقم $i'}
  ];

  testWidgets('editor: empty, part marked, complete', (tester) async {
    await expectNoLayoutErrors(tester, () => SizedBox(height: 900, child: TimingEditorBody(ayat: ayat, draft: TimingDraft(6), positionMs: 0, durationMs: 0, playing: false)));
    await expectNoLayoutErrors(
      tester,
      () => SizedBox(
        height: 900,
        child: TimingEditorBody(
          ayat: ayat,
          draft: TimingDraft(6, start0: 900, ends: [4000, 8000, 12500, null, null, null]),
          positionMs: 83250,
          durationMs: 240000,
          playing: true,
          dirty: true,
          onToggle: () {},
          onSeek: (_) {},
          onMark: () {},
          onNudgeEnd: (_, _) {},
          onNudgeStart: (_) {},
          onClearFrom: (_) {},
          onReplay: (_) {},
          onSave: () {},
        ),
      ),
    );
    await expectNoLayoutErrors(tester, () => SizedBox(height: 900, child: TimingEditorBody(ayat: ayat, draft: TimingDraft(6, ends: [1, 2, 3, 4, 5, 6]), positionMs: 10, durationMs: 100, playing: false)));
  });

  testWidgets('surah list', (tester) async {
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 700, child: TimingSurahsBody(items: [], onOpen: _noop)));
    await expectNoLayoutErrors(
      tester,
      () => SizedBox(
        height: 700,
        child: TimingSurahsBody(items: [
          {'surah': 1, 'name_ar': 'الفاتحة', 'ayat': 7, 'marked': 7},
          {'surah': 2, 'name_ar': 'البقرة', 'ayat': 286, 'marked': 12},
          {'surah': 112, 'name_ar': 'الإخلاص', 'ayat': 4, 'marked': 0},
        ], onOpen: _noop),
      ),
    );
  });

  test('timingClock', () => expect(timingClock(83250), '1:23.250'));
}

void _noop(Map<String, dynamic> _) {}
