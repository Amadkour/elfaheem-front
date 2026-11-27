// VISUAL review renders of the teacher's live screens (Tea1Live: prejoin, room + host chrome, lobby, ended): 390x844
// and 1360x900, Arabic and English, light, CAST demo data (the maths class, أ. ماجد الشهري). Compared by eye with
// D:/platform/redesign-ref/ref/teacher/04{6..9}_Tea1Live_*.png. Not a CI suite. The room itself needs a LiveKit Room;
// what is rendered here is its host chrome (LiveTopRow, the hands strip, LiveControlBar) over a stand-in stage.
//
//   flutter test test/visual/redesign/t1/t1_live_golden_test.dart --update-goldens [--plain-name prejoin]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart' show LobbyBody;
import 'package:flutter_education_app/features/live/live_room.dart' show LobbyRequest;
import 'package:flutter_education_app/features/live/live_self_view.dart' show SelfViewShape;
import 'package:flutter_education_app/features/live/room/prejoin_teacher.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_teacher_ended.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_top_row.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _prejoin() => TeacherPreJoinLayout(
      lessonTitle: _t('المتتابعات الهندسية', 'Geometric sequences'),
      userName: _t('أ. ماجد الشهري', 'Mr Majed Alshehri'),
      classLine: _t('الرياضيات ٣ ثانوي، مجموعة أ', 'Maths, grade 12, group A'),
      timeLine: _t('اليوم ٧:٣٠ م', 'Today 7:30 pm'),
      liveNow: true,
      waitingCount: 7,
      micOn: true,
      camOn: false,
      micLevel: 0.7,
      onToggleMic: () {},
      onToggleCam: () {},
      busy: false,
      onJoin: () {},
      onBack: () {},
      joinLabel: _t('ادخل الحين', 'Enter now'),
      mics: const [('a', 'AirPods Pro'), ('b', 'Built-in microphone')],
      cams: const [('c', 'FaceTime HD'), ('d', 'USB camera')],
      selectedMic: 'a',
      selectedCam: 'c',
      onMicChanged: (_) {},
      onCamChanged: (_) {},
      previewShape: SelfViewShape.box,
      onPreviewShape: (_) {},
      recordingNote: true,
    );

/// The teacher's board on the stage (the real room draws the board / share / camera here).
class _Board extends StatelessWidget {
  const _Board();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.hero)),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('المتتابعة الهندسية', 'The geometric sequence'), style: AppType.headline(context)),
          const SizedBox(height: AppSpace.lg),
          Text('aₙ = a₁ · rⁿ⁻¹', style: AppType.section(context)),
          const SizedBox(height: AppSpace.md),
          Text('3, 6, 12, 24, …  ⇒  r = 2', style: AppType.section(context)),
          const SizedBox(height: AppSpace.md),
          Text('Sₙ = a₁(rⁿ − 1) / (r − 1)', style: AppType.section(context)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.name, {this.hand = false, this.muted = true});

  final String name;
  final bool hand, muted;

  @override
  Widget build(BuildContext context) => Container(
        width: 140,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: LivePalette.surface,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: LivePalette.glassBorder, width: AppBorder.hairline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(radius: AppSpace.lg, backgroundColor: LivePalette.avatarColor(name), child: Text(name.characters.first)),
                if (hand) const PositionedDirectional(top: -AppSpace.sm, start: -AppSpace.sm, child: Text('✋')),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: LivePalette.textHigh)),
            Icon(muted ? Icons.mic_off_outlined : Icons.mic_none_rounded, size: AppIconSize.sm, color: LivePalette.textMid),
          ],
        ),
      );
}

List<LiveControlAction> _actions() => [
      LiveControlAction(key: const ValueKey('live_room.mic'), icon: Icons.mic_none_rounded, label: _t('الميكروفون', 'Microphone'), active: true, onTap: () {}),
      LiveControlAction(key: const ValueKey('live_room.camera'), icon: Icons.videocam_outlined, label: _t('الكاميرا', 'Camera'), active: true, onTap: () {}),
      LiveControlAction(key: const ValueKey('live_room.share'), icon: Icons.present_to_all_rounded, label: _t('مشاركة', 'Share'), active: true, onTap: () {}),
      LiveControlAction(key: const ValueKey('live_room.hand'), icon: Icons.back_hand_outlined, label: _t('الأيدي', 'Hands'), badge: 2, onTap: () {}),
    ];

Widget _room({bool lobby = false}) => ColoredBox(
      color: LivePalette.bg,
      child: SafeArea(
        child: Column(
          children: [
            LiveTopRow(
              onInfo: () {},
              peopleCount: 9,
              onPeople: () {},
              waitingCount: lobby ? 0 : 3,
              onWaiting: () {},
              liveFor: const Duration(minutes: 24, seconds: 13),
              netLowered: lobby,
              recording: LiveTopRecording(
                phase: LiveRecPhase.recording,
                elapsed: const Duration(minutes: 24, seconds: 13),
                onRecord: () {},
                onPause: () {},
              ),
              onMinimize: () {},
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: SizedBox(height: 360, child: const _Board()),
            ),
            SizedBox(
              height: 130,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                children: [
                  _Tile(_t('راكان الحربي', 'Rakan'), muted: false),
                  const SizedBox(width: AppSpace.sm),
                  _Tile(_t('فيصل العنزي', 'Faisal')),
                  const SizedBox(width: AppSpace.sm),
                  _Tile(_t('ليث الدوسري', 'Laith'), hand: true),
                ],
              ),
            ),
            const Spacer(),
            LiveControlBar(
              primary: _actions(),
              end: LiveControlAction(key: const ValueKey('live_room.end'), icon: Icons.call_end_rounded, label: _t('إنهاء', 'End'), onTap: () {}),
              onLobby: () {},
              waitingCount: 3,
            ),
          ],
        ),
      ),
    );

Widget _lobbyOverRoom() => Stack(
      children: [
        _room(lobby: true),
        Align(
          alignment: Alignment.bottomCenter,
          child: Builder(
            builder: (context) => Container(
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
              ),
              child: Material(
                color: Colors.transparent,
                child: LobbyBody(
                  loading: false,
                  error: null,
                  courseClass: true,
                  waiting: [
                    LobbyRequest(id: 'r1', name: _t('خالد الحربي', 'Khalid'), isGuest: true, requestedAt: DateTime.now().toUtc()),
                    LobbyRequest(id: 'r2', name: _t('تركي السبيعي', 'Turki'), requestedAt: DateTime.now().toUtc()),
                    LobbyRequest(id: 'r3', name: _t('أ. عبدالرحمن', 'Mr Abdulrahman'), isGuest: true),
                  ],
                  everyoneNeedsApproval: false,
                  guestsJoinAutomatically: false,
                  onAdmit: (_) {},
                  onReject: (_) {},
                  onAdmitAll: () {},
                  onRefresh: () {},
                  onEveryoneNeedsApproval: (_) {},
                  onGuestsJoinAutomatically: (_) {},
                ),
              ),
            ),
          ),
        ),
      ],
    );

Widget _ended() => TeacherEndedView(
      summary: LiveEndSummary(
        title: _t('المتتابعات الهندسية', 'Geometric sequences'),
        subtitle: _t('الرياضيات ٣ ثانوي، مجموعة أ', 'Maths, grade 12, group A'),
        duration: const Duration(minutes: 50),
        attended: 7,
        guests: 2,
        recorded: true,
      ),
      onBack: () {},
      onAddMaterials: () {},
    );

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build, {bool grow = true}) =>
      kitRender(tester, 't1/live_$name', build, storage: storage, modes: const [false], scaffold: true, grow: grow);

  testWidgets('t1 live prejoin', (t) => render(t, 'prejoin', _prejoin));
  testWidgets('t1 live room', (t) => render(t, 'room', _room, grow: false));
  testWidgets('t1 live lobby', (t) => render(t, 'lobby', _lobbyOverRoom, grow: false));
  testWidgets('t1 live ended', (t) => render(t, 'ended', _ended, grow: false));
}
