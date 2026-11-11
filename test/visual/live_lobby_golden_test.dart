// Visual review renders of the live lobby, the share link and the joiner's waiting page, compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/live_lobby_golden_test.dart --update-goldens [--plain-name waiting]
//
// → test/visual/goldens/lobby_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   lobby      the host's lobby sheet: the quick guest link (direct, QR off) over two people waiting
//   share      the meeting's share link sheet: the link block with its facts and actions
//   waiting    the joiner's "Waiting for the host…" page
//   rejected   the same page after the host said no
//   record     the meeting's Record sheet: Google Drive chosen, OneDrive to connect, quality, what it holds
//   drives     Settings › Connected drives, with a recording's status card under it
//   info       the room's (i) sheet as the host sees it: the live figures, the link, the admission rules
//   links      the meeting links page (D-307): a live meeting I host, a session later today, a weekly meeting tomorrow
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show showAppSheet;
import 'package:flutter_education_app/features/shared/live/live_lobby_sheets.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/shared/live/meeting_info_sheet.dart';
import 'package:flutter_education_app/features/shared/live/meeting_links.dart';
import 'package:flutter_education_app/features/shared/live/meeting_links_page.dart';
import 'package:flutter_education_app/features/shared/live/meeting_recording.dart';
import 'package:flutter_education_app/features/shared/live/meeting_recording_sheets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

const _link = LiveLink(
  url: 'https://nextbrain.site/live/4f3b1c9e8d7a6b5c4d3e2f1a',
  token: '4f3b1c9e',
  canPublish: true,
  maxGuests: 25,
  hasPin: true,
  direct: true,
);

Widget _lobby() => LobbyBody(
      loading: false,
      error: null,
      waiting: [
        LobbyRequest(id: 'r1', name: tr('محمد عبد الرحمن', 'Mohamed Abdelrahman'), requestedAt: DateTime.now().toUtc()),
        LobbyRequest(id: 'r2', name: tr('ليلى حسن', 'Laila Hassan'), isGuest: true, requestedAt: DateTime.now().toUtc()),
      ],
      everyoneNeedsApproval: true,
      guestsJoinAutomatically: false,
      onAdmit: (_) {},
      onReject: (_) {},
      onAdmitAll: () {},
      onRefresh: () {},
      onEveryoneNeedsApproval: (_) {},
      onGuestsJoinAutomatically: (_) {},
      quickLink: QuickGuestLinkCard(
        loading: false,
        busy: false,
        error: null,
        link: _link,
        onRetry: () {},
        onMakeDirect: () {},
        onDirectChanged: (_) {},
        onCopy: () {},
        onShare: () {},
        onToggleQr: () {},
      ),
    );

Widget _share() => ShareLinkBody(
      loading: false,
      busy: false,
      error: null,
      link: _link,
      canPublish: true,
      maxGuestsController: TextEditingController(text: '25'),
      pinController: TextEditingController(),
      editing: false,
      showQr: true,
      onRetry: () {},
      onCanPublishChanged: (_) {},
      onCreate: () {},
      onCopy: () {},
      onShare: () {},
      onToggleQr: () {},
      onToggleSettings: () {},
      onSaveSettings: () {},
      onRevoke: () {},
    );

class _FakeLinks extends MeetingLinksApi {
  const _FakeLinks();

  @override
  Future<MeetingLinksData> load() async {
    final now = DateTime.now().toUtc();
    return MeetingLinksData([
      MeetingLinkItem(
        kind: 'meeting',
        refId: 1,
        title: tr('مراجعة مشروع التخرج', 'Graduation project review'),
        status: MeetingLinkStatus.live,
        appLink: '/m/1',
        subtitle: tr('د. منى عبد العزيز', 'Dr. Mona Abdelaziz'),
        startsAt: now.subtract(const Duration(minutes: 20)),
        endsAt: now.add(const Duration(minutes: 40)),
        isHost: true,
        guest: const MeetingGuestLink(url: 'https://nextbrain.site/live/4f3b1c9e', direct: true, guestsJoined: 3),
      ),
      MeetingLinkItem(
        kind: 'session',
        refId: 2,
        title: tr('تراكيب البيانات — المحاضرة السابعة', 'Data structures — lecture 7'),
        status: MeetingLinkStatus.scheduled,
        appLink: '/s/2',
        courseId: 9,
        subtitle: tr('تراكيب البيانات', 'Data structures'),
        startsAt: now.add(const Duration(hours: 2)),
        endsAt: now.add(const Duration(hours: 3)),
      ),
      MeetingLinkItem(
        kind: 'meeting',
        refId: 3,
        title: tr('اجتماع القسم الأسبوعي', 'Weekly department meeting'),
        status: MeetingLinkStatus.scheduled,
        appLink: '/m/3',
        subtitle: tr('أ. خالد يوسف', 'Mr. Khaled Youssef'),
        startsAt: now.add(const Duration(days: 1, hours: 1)),
        recurring: true,
        myStatus: 'pending',
      ),
    ]);
  }
}

const _drive = CloudAccount(provider: CloudProvider.googleDrive, configured: true, connected: true, email: 'sara@gmail.com');
const _oneDrive = CloudAccount(provider: CloudProvider.onedrive, configured: true);

Widget _record() => const RecordSetupLayout(accounts: [_drive, _oneDrive], quality: RecordingQuality.p720, selected: CloudProvider.googleDrive);

Widget _info() => MeetingInfoSheet(
      info: MeetingInfo(
        title: tr('مراجعة الوحدة الثالثة', 'Unit 3 review'),
        isMeeting: true,
        role: LiveRoomRole.host,
        hostName: tr('د. منى السيد', 'Dr. Mona Elsayed'),
        recording: LiveInfoRecording.recording,
        elapsed: const Duration(minutes: 41, seconds: 7),
        liveFor: const Duration(minutes: 52, seconds: 18),
        participants: 27,
        linkUrl: 'https://nextbrain.site/live/4f3b1c9e8d7a6b5c',
        admission: LiveAdmission.approve,
        guestAdmission: LiveGuestAdmission.approve,
        freeLeft: const Duration(minutes: 2, seconds: 40),
      ),
      onCopyLink: () {},
    );

/// Connected drives with the latest recording's card under it (the meeting detail's card, for the look).
Widget _drives() => Column(children: [
      const Expanded(child: CloudDrivesLayout(accounts: [_drive, _oneDrive])),
      Padding(
        padding: const EdgeInsets.all(16),
        child: RecordingStatusCard(
          recording: MeetingRecording(
            id: 5,
            status: 'uploading',
            destination: CloudProvider.googleDrive,
            durationSeconds: 3120,
            size: 412000000,
            createdAt: DateTime.now().toUtc(),
          ),
        ),
      ),
    ]);

/// The sheet scenes open through the real showAppSheet (side panel on wide windows, bottom sheet on phones).
Widget _host(String name, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  final sheet = name == 'lobby' || name == 'share' || name == 'record' || name == 'info';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: Builder(builder: (context) {
        if (sheet) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showAppSheet<void>(context, (_) => switch (name) {
                  'lobby' => _lobby(),
                  'record' => _record(),
                  'info' => _info(),
                  _ => _share(),
                });
          });
        }
        return Scaffold(
          backgroundColor: context.colors.background,
          body: sheet
              ? const SizedBox.expand()
              : name == 'links'
                  ? const MeetingLinksPage(api: _FakeLinks())
                  : name == 'drives'
                      ? _drives()
                      : WaitingForHostScreen(
                  state: name == 'waiting' ? WaitingState.waiting : WaitingState.rejected,
                  title: tr('مراجعة مشروع التخرج', 'Graduation project review'),
                  hostName: tr('د. منى عبد العزيز', 'Dr. Mona Abdelaziz'),
                  onCancel: () {},
                ),
        );
      }),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(name, dark: dark));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/lobby_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  testWidgets('lobby', (tester) => _render(tester, 'lobby'));
  testWidgets('share', (tester) => _render(tester, 'share'));
  testWidgets('waiting', (tester) => _render(tester, 'waiting'));
  testWidgets('rejected', (tester) => _render(tester, 'rejected'));
  testWidgets('links', (tester) => _render(tester, 'links'));
  testWidgets('record', (tester) => _render(tester, 'record'));
  testWidgets('drives', (tester) => _render(tester, 'drives'));
  testWidgets('info', (tester) => _render(tester, 'info'));
}
