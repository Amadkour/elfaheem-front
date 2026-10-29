// Admin "Live performance" page body (D-089, LiveSettingsView): at 320x640 and 1400x900, Arabic + English,
// textScaler 1.3 — the recommended set, a far-from-recommended draft with unsaved changes (client recording, so the
// engine cards are disabled), and a tap on a choice card / a segment / a switch.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/live_settings/live_settings_page.dart';
import 'package:flutter_education_app/features/admin/live_settings/live_settings_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const far = LiveSettingsDraft(
  videoCodec: 'vp9',
  weakNetwork: 'audio_first',
  cameraMaxHost: '360p',
  cameraMaxParticipant: '540p',
  cameraFps: 30,
  screenFpsMax: 30,
  screenBitrateKbps: 6000,
  audioDtx: false,
  audioRed: false,
  participantsCameraDefaultOff: false,
  pauseHiddenVideo: false,
  recordingMode: 'client',
  serverRecordingEngine: 'media',
  serverRecordingTiers: 'all',
);

void main() {
  testWidgets('recommended, nothing to save', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => LiveSettingsView(
        draft: LiveSettingsDraft.recommended,
        saved: LiveSettingsDraft.recommended,
        envRecordingMode: 'client',
        onChanged: (_) {},
        onSave: () {},
        onReset: () {},
      ),
    );
  });

  testWidgets('far from recommended, unsaved, saving', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => LiveSettingsView(
        draft: far,
        saved: LiveSettingsDraft.recommended,
        stored: const {'recording_mode'},
        saving: true,
        onChanged: (_) {},
        onSave: () {},
        onReset: () {},
        onDiscard: () {},
      ),
    );
  });

  testWidgets('choices change the draft', (tester) async {
    var draft = LiveSettingsDraft.recommended;
    await expectNoLayoutErrors(
      tester,
      () {
        draft = LiveSettingsDraft.recommended; // every size / language starts from the recommended set
        return StatefulBuilder(
          builder: (context, set) => LiveSettingsView(
            draft: draft,
            saved: LiveSettingsDraft.recommended,
            onChanged: (d) => set(() => draft = d),
            onSave: () {},
            onReset: () {},
            onDiscard: () => set(() => draft = LiveSettingsDraft.recommended),
          ),
        );
      },
      act: (tester) async {
        final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('H.264'), 200, scrollable: list);
        await tester.ensureVisible(find.text('H.264').first);
        await tester.pump();
        await tester.tap(find.text('H.264').first);
        await tester.pump();
        await tester.scrollUntilVisible(find.text('30 fps'), 200, scrollable: list);
        await tester.ensureVisible(find.text('30 fps'));
        await tester.pump();
        await tester.tap(find.text('30 fps'));
        await tester.pump();
      },
    );
    expect(draft.videoCodec, 'h264');
    expect(draft.cameraFps, 30);
  });
}
