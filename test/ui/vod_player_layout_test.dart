import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/shared/session/video/video_player_screen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_player_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

SessionMaterialModel _m(int id, {SessionMaterialType type = SessionMaterialType.video, String? name}) =>
    SessionMaterialModel(
      id: id,
      sessionId: 7,
      name: name ?? 'المحاضرة $id — مقدمة طويلة جدًا في الجبر الخطي والمصفوفات والتحويلات',
      type: type,
      order: id,
      createdAt: DateTime(2026),
      completed: id.isEven,
      durationSeconds: 3725,
    );

void main() {
  _screenTests();
  final list = [_m(1), _m(2, type: SessionMaterialType.pdf), _m(3), _m(4)];

  test('playlist keeps playable lectures and finds the next one', () {
    final p = vodPlaylist(list);
    expect(p.map((m) => m.id), [1, 3, 4]);
    expect(vodNextOf(p, list[0])?.id, 3);
    expect(vodNextOf(p, list[3]), isNull);
    expect(vodNextOf(p, _m(99)), isNull);
  });

  test('resume ignores the first seconds and the very end', () {
    const total = Duration(minutes: 10);
    expect(VodResume.pick(const Duration(seconds: 5), total), isNull);
    expect(VodResume.pick(const Duration(minutes: 3), total), const Duration(minutes: 3));
    expect(VodResume.pick(total - const Duration(seconds: 5), total), isNull);
  });

  testWidgets('player overlays never overflow', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          const VodPlayerSkeleton(title: 'عنوان المحاضرة الطويل جدًا جدًا جدًا جدًا جدًا'),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: VodNextUpCard(next: list[2], seconds: 4, maxWidth: 288, onPlay: () {}, onCancel: () {}),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              VodResumeChip(at: const Duration(minutes: 42, seconds: 7), onStartOver: () {}),
              const SizedBox(height: 8),
              const VodLevelHud(brightness: true, value: 0.4),
              const SizedBox(height: 8),
              const VodLevelHud(brightness: false, value: 0),
              const SizedBox(height: 8),
              const VodCaption(text: 'هذا نص ترجمة طويل يشرح المعادلة التالية بالتفصيل الممل خطوة بخطوة'),
            ]),
          ),
        ]),
      ),
    );
  });

  testWidgets('lecture list never overflows', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => VodLectureList(items: vodPlaylist(list), currentId: 3, onSelect: (_) {}),
    );
  });

  testWidgets('lecture list sheet opens', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showVodLectureList(context, items: vodPlaylist(list), currentId: 1, onSelect: (_) {}),
            child: const Text('open'),
          ),
        ),
      ),
      act: (t) => t.tap(find.text('open')),
    );
  });
}

// The whole screen can't play in a test (no platform player), but its skeleton and error states must still lay out.
void _screenTests() {
  testWidgets('VideoPlayerScreen error state never overflows', (tester) async {
    // The Android PiP plugin polls with a timer that outlives the widget in tests; iOS has no PiP branch.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await expectNoLayoutErrors(
        tester,
        () => VideoPlayerScreen(material: _m(5, name: 'محاضرة بدون رابط فيديو — حالة الخطأ وإعادة المحاولة')),
        scaffold: false,
        frames: 8,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
