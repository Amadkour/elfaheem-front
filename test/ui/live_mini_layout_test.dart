// The minimized live-room box (LiveMiniBoxLayout) at its real sizes — 150×94 on a phone, 240×150 on a wide window —
// in Arabic and English, text scale 1.3: no overflow with the avatar backdrop, with a "video", with a long name,
// with and without the mic / leave buttons.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/live_mini_box.dart';
import 'package:flutter_education_app/features/shared/live/live_room_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _boxed(Widget child) => LayoutBuilder(builder: (context, c) {
      final size = liveMiniSize(Size(c.maxWidth, c.maxHeight));
      return Center(child: SizedBox(width: size.width, height: size.height, child: child));
    });

void main() {
  testWidgets('avatar backdrop, every button', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _boxed(LiveMiniBoxLayout(
              name: 'الدكتور عبد الرحمن محمود عبد العزيز الشناوي',
              speaking: true,
              micOn: false,
              onExpand: () {},
              onToggleMic: () {},
              onLeave: () {},
            )));
  });

  testWidgets('a video, a screen share, no mic button (listen-only)', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _boxed(LiveMiniBoxLayout(
              name: 'Professor Elizabeth Montgomery-Whitfield',
              screenShare: true,
              video: const ColoredBox(color: Colors.blueGrey),
              onExpand: () {},
              onLeave: () {},
            )));
  });

  testWidgets('the smallest box: photo avatar, no extra buttons', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _boxed(LiveMiniBoxLayout(
              name: 'A',
              imageUrl: 'https://example.invalid/photo.jpg',
              onExpand: () {},
            )));
  });
}
