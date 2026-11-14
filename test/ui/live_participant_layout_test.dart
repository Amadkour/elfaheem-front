// The live room's participant tiles and the recording placeholder frame at 320x640 and 1400x900, ar + en,
// textScaler 1.3, pumped without a LiveKit Room (plain-value widgets):
//   • ParticipantTileLayout: a 90 px thumbnail strip, a 150x100 PiP, a full-size tile — camera on (video child),
//     camera off (avatar), speaking, muted, host / guest / you, poor and lost network, encrypted, overlay + stats,
//     screen share, a photo URL (fails in tests → initials), long Arabic and English names.
//   • NoVideoWidget alone at 40x40 and full size; ParticipantInfoWidget at both sizes; ParticipantStatsPanel.
//   • RecordingPlaceholderFrame: host alone · 3 others · 60 others (overflow tile) · long title · no logo.
// Plus the pure helpers: initials and the stable per-name hue.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_avatar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/widgets/no_video.dart';
import 'package:flutter_education_app/features/live/room/widgets/participant.dart';
import 'package:flutter_education_app/features/live/room/widgets/participant_info.dart';
import 'package:flutter_education_app/features/live/room/widgets/participant_stats.dart';
import 'package:flutter_education_app/features/live/room/widgets/recording_placeholder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'الدكتور أحمد حمدي مدكور عبد الرحمن — اسم طويل جدًا للمشارك';
const _longEn = 'Mohamed Abdelrahman El-Sayed Ibrahim (a rather long participant name)';

Widget _video() => const ColoredBox(color: Color(0xFF203040), child: Center(child: Icon(Icons.videocam, color: Colors.white24)));

List<ParticipantTileLayout> _tiles() => [
      ParticipantTileLayout(name: _longAr, camOn: true, isSpeaking: true, audioLevel: 0.7, isHost: true, quality: LiveNetQuality.excellent, encrypted: true, child: _video()),
      const ParticipantTileLayout(name: _longEn, micOn: false, isGuest: true, quality: LiveNetQuality.poor),
      const ParticipantTileLayout(name: 'سارة', isLocal: true, isSpeaking: true, audioLevel: 1, quality: LiveNetQuality.good),
      const ParticipantTileLayout(name: 'Omar Ali', imageUrl: 'https://example.invalid/photo.jpg', quality: LiveNetQuality.lost, micOn: false),
      ParticipantTileLayout(name: 'Screen', isScreenShare: true, camOn: true, child: _video()),
      const ParticipantTileLayout(name: '', micOn: false),
    ];

void main() {
  test('initials: first letters of the first two words, never empty', () {
    expect(liveInitials('Ahmed Hamdy Madkour'), 'AH');
    expect(liveInitials('  سارة   محمود '), 'سم');
    expect(liveInitials('omar'), 'O');
    expect(liveInitials(''), '•');
    expect(liveInitials('   '), '•');
  });

  test('hue: stable per name, case and space insensitive, inside 0..360', () {
    expect(LivePalette.hueFor('Ahmed'), LivePalette.hueFor('  ahmed '));
    expect(LivePalette.hueFor('Ahmed'), isNot(LivePalette.hueFor('Ahmad')));
    for (final n in ['', 'a', 'سارة محمود', _longEn, 'guest:abc123', 'teacher_42']) {
      final h = LivePalette.hueFor(n);
      expect(h, inInclusiveRange(0, 360 - 1e-9), reason: n);
    }
    expect(LivePalette.avatarGradient('x').colors.length, 2);
  });

  test('photo from metadata: image_url / avatar keys, nothing else', () {
    expect(participantPhotoFromMetadata('{"role":"guest"}'), isNull);
    expect(participantPhotoFromMetadata('{"image_url":" https://x/y.png "}'), 'https://x/y.png');
    expect(participantPhotoFromMetadata('{"avatar":"https://x/a.png"}'), 'https://x/a.png');
    expect(participantPhotoFromMetadata('not json'), isNull);
    expect(participantPhotoFromMetadata(null), isNull);
    expect(participantPhotoFromMetadata('[]'), isNull);
  });

  testWidgets('participant tiles never overflow: thumbnail strip, PiP and full size', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ColoredBox(
        color: Colors.black,
        child: Column(children: [
          // 90 px thumbnail strip
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [for (final t in _tiles()) SizedBox(width: 90, child: Padding(padding: const EdgeInsets.all(3), child: t))],
            ),
          ),
          // PiP corner + a small grid cell
          Row(children: [
            SizedBox(width: 150, height: 100, child: _tiles()[2]),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 100, child: _tiles()[1])),
          ]),
          // full tile with overlay + stats
          Expanded(
            child: ParticipantTileLayout(
              name: _longEn,
              isSpeaking: true,
              audioLevel: 0.5,
              micOn: true,
              isHost: true,
              quality: LiveNetQuality.poor,
              encrypted: true,
              overlay: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final i in [Icons.volume_up, Icons.videocam, Icons.speed_rounded])
                  Padding(padding: const EdgeInsets.only(left: 4), child: CircleAvatar(radius: 14, backgroundColor: Colors.black45, child: Icon(i, size: 14, color: Colors.white))),
              ]),
              stats: ParticipantStatsPanel(
                audio: {'rx': '48 kpbs', 'codec': 'opus/48000/2', 'jitter': '0.004 s', 'packets lost': '0'},
                video: {for (var i = 0; i < 14; i++) 'layer-$i': '1280x720 30.0 fps, 1500 kbps — a long value that wraps'},
              ),
            ),
          ),
        ]),
      ),
    );
  });

  testWidgets('camera-on tile swaps to the avatar when the camera goes off', (tester) async {
    var camOn = true;
    late StateSetter set;
    await expectNoLayoutErrors(
      tester,
      () => StatefulBuilder(builder: (context, s) {
        set = s;
        return ParticipantTileLayout(name: 'Omar Ali', camOn: camOn, isSpeaking: !camOn, child: _video());
      }),
      act: (t) async {
        set(() => camOn = false);
        await t.pump(const Duration(milliseconds: 150));
        set(() => camOn = true);
      },
    );
  });

  testWidgets('no-video backdrop and info bar at tiny and full sizes', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        Row(children: [
          const SizedBox(width: 40, height: 40, child: NoVideoWidget(name: 'سارة محمود', isSpeaking: true)),
          const SizedBox(width: 64, height: 48, child: NoVideoWidget(name: 'A')),
          const SizedBox(width: 120, height: 140, child: NoVideoWidget(name: _longEn, imageUrl: 'https://example.invalid/p.png')),
          Expanded(child: SizedBox(height: 140, child: Row(children: const [
            Expanded(child: ParticipantInfoWidget(title: _longAr, isHost: true, audioAvailable: false, quality: LiveNetQuality.lost, enabledE2EE: true)),
            SizedBox(width: 80, child: ParticipantInfoWidget(title: _longEn, isGuest: true, compact: true, quality: LiveNetQuality.poor)),
          ]))),
        ]),
        const Expanded(child: NoVideoWidget(name: _longAr, isSpeaking: true, audioLevel: 0.9)),
        const SizedBox(height: 60, child: ParticipantInfoWidget(title: _longEn, isLocal: true, audioLevel: 0.6, quality: LiveNetQuality.excellent)),
      ]),
    );
  });

  List<PlaceholderParticipant> others(int n) => [
        for (var i = 0; i < n; i++)
          PlaceholderParticipant(
            name: i % 3 == 0 ? _longAr : (i % 3 == 1 ? _longEn : 'طالب $i'),
            micOn: i.isEven,
            isSpeaking: i % 5 == 0,
            isGuest: i % 7 == 0,
            imageUrl: i % 4 == 0 ? 'https://example.invalid/$i.png' : null,
          ),
      ];

  for (final (label, count) in [('host alone', 0), ('3 others', 3), ('60 others (overflow)', 60)]) {
    testWidgets('recording placeholder frame never overflows: $label', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => RecordingPlaceholderFrame(
          host: PlaceholderParticipant(name: count.isEven ? _longAr : _longEn, isHost: true, micOn: count != 3, isSpeaking: true, audioLevel: 0.8),
          others: others(count),
          sessionTitle: 'المحاضرة الثالثة — مقدمة طويلة جدًا في الجبر الخطي والمصفوفات والتحويلات الخطية وتطبيقاتها',
          platformName: 'الفهيم — منصة التعليم الذكي',
          showLogo: count != 3,
          onTapHost: () {},
          onTapOther: (_) {},
          onTapOverflow: () {},
        ),
        scaffold: false,
      );
    });
  }

  testWidgets('recording placeholder frame: guest viewer, no title, no logo', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const RecordingPlaceholderFrame(
        host: PlaceholderParticipant(name: 'Visitor', isGuest: true, micOn: false),
        others: [PlaceholderParticipant(name: 'Host Teacher', isHost: true)],
        showLogo: false,
        live: false,
      ),
      scaffold: false,
    );
  });
}
