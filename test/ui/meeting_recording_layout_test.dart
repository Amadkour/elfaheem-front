// Meeting recordings → cloud drives (docs/backend/live-rooms-spec.md §5 / §6): the presentational widgets on
// every screen size and language, the setup sheet's flow against a fake API (destination · connect · quality ·
// Start → RecordingStart with the chosen quality), the status card's actions, and the settings entry's gating
// (feature key profile.cloud_drives, never for a guest or while viewing as someone else).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppPrimaryButton;
import 'package:flutter_education_app/design/app_notice.dart' show appNoticeTopOverlay;
import 'package:flutter_education_app/features/shared/live/meeting_recording.dart';
import 'package:flutter_education_app/features/shared/live/meeting_recording_sheets.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _google = CloudAccount(provider: CloudProvider.googleDrive, configured: true, connected: true, email: 'me@gmail.com');
const _googleOff = CloudAccount(provider: CloudProvider.googleDrive, configured: true, connected: false);
const _googleUnset = CloudAccount(provider: CloudProvider.googleDrive);
const _oneOff = CloudAccount(provider: CloudProvider.onedrive, configured: true, connected: false);
const _none = CloudAccount(provider: CloudProvider.onedrive);

const _unsetText = "Google Drive isn't set up on this server yet. Ask the platform admin to set it up.";

MeetingRecording _rec(String status, {String? url, String? error}) => MeetingRecording(
      id: 5,
      refId: 7,
      status: status,
      quality: RecordingQuality.p1080,
      destination: CloudProvider.googleDrive,
      size: 734003200,
      durationSeconds: 5400,
      remoteUrl: url,
      error: error,
      createdAt: DateTime.utc(2026, 10, 27, 9),
      finishedAt: status == 'done' ? DateTime.utc(2026, 10, 27, 10, 30) : null,
    );

class _Api implements MeetingRecordingApi {
  _Api(this.accounts);
  List<CloudAccount> accounts;
  final calls = <String>[];
  RecordingQuality? startedWith;
  CloudProvider? startedTo;
  Object? startError;
  Object? connectError;

  @override
  Future<List<CloudAccount>> cloud() async {
    calls.add('cloud');
    return accounts;
  }

  @override
  Future<String> connect(CloudProvider p) async {
    calls.add('connect ${p.wire}');
    final e = connectError;
    if (e != null) throw e;
    return '';
  }

  @override
  Future<void> disconnect(CloudProvider p) async => calls.add('disconnect ${p.wire}');

  @override
  Future<RecordingStart> start(String kind, int id, {required RecordingQuality quality, required CloudProvider destination}) async {
    calls.add('start $kind/$id');
    final e = startError;
    if (e != null) throw e;
    startedWith = quality;
    startedTo = destination;
    return const RecordingStart(recordingId: 9, chunkPath: '/api/v1/live/recordings/9/chunk');
  }

  @override
  Future<void> stop(int rid) async => calls.add('stop $rid');

  @override
  Future<MeetingRecording?> get(int rid) async => _rec('uploading');

  @override
  Future<MeetingRecording?> retry(int rid) async {
    calls.add('retry $rid');
    return _rec('uploading');
  }

  @override
  Future<List<MeetingRecording>> list(String kind, int id) async {
    calls.add('list $kind/$id');
    return [_rec('done', url: 'https://drive.google.com/x')];
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  tearDown(() {
    ViewAsState.instance.stop();
    AppConfig.disableList = [];
  });

  group('layout', () {
    testWidgets('setup: loading, one connected + one to connect, none available, error', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
            const RecordSetupLayout(accounts: null, quality: RecordingQuality.p720),
            RecordSetupLayout(
                accounts: const [_google, _oneOff],
                selected: CloudProvider.googleDrive,
                quality: RecordingQuality.p1080,
                onPick: (_) {},
                onConnect: (_) {},
                onQuality: (_) {},
                onStart: () {}),
            RecordSetupLayout(
                accounts: const [_oneOff, _oneOff],
                connecting: CloudProvider.onedrive,
                quality: RecordingQuality.audio,
                error: 'A recording of this meeting is already running'),
            const RecordSetupLayout(accounts: [_none, _none], quality: RecordingQuality.p480, busy: true),
          ])));
    });

    testWidgets('status card in every state', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
            for (final s in recordingStatuses)
              RecordingStatusCard(
                recording: _rec(s, url: s == 'done' ? 'https://drive.google.com/x' : null, error: s == 'failed' ? 'Drive quota exceeded for this account' : null),
                onOpen: () {},
                onRetry: () {},
              ),
          ])));
    });

    testWidgets('connected drives page body', (t) async {
      await expectNoLayoutErrors(t, () => CloudDrivesLayout(accounts: const [_google, _oneOff], onConnect: (_) {}, onDisconnect: (_) {}));
      await expectNoLayoutErrors(t, () => const CloudDrivesLayout(accounts: [], loading: true));
      await expectNoLayoutErrors(t, () => CloudDrivesLayout(accounts: const [_none, _none], error: 'Network down', onRetry: () {}, connecting: CloudProvider.onedrive));
    });

    testWidgets('a provider the server has not set up: greyed with the admin line, no Connect', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
            RecordSetupLayout(accounts: const [_googleUnset, _oneOff], quality: RecordingQuality.p720, onPick: (_) {}, onConnect: (_) {}),
            const RecordSetupLayout(accounts: [_googleUnset, _none], quality: RecordingQuality.p720),
          ])));
      await expectNoLayoutErrors(t, () => CloudDrivesLayout(accounts: const [_googleUnset, _oneOff], onConnect: (_) {}, onDisconnect: (_) {}));
      await expectNoLayoutErrors(t, () => const CloudDrivesLayout(accounts: [_googleUnset, _none]));

      await t.pumpWidget(layoutHost(CloudDrivesLayout(accounts: const [_googleUnset, _oneOff], onConnect: (_) {}), scale: 1));
      expect(find.text(_unsetText), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget, reason: 'only OneDrive offers Connect');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('settings group', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: CloudDrivesGroup(onTap: () {})));
    });
  });

  group('setup sheet flow', () {
    testWidgets('preselects the usable drive, Start sends the chosen quality and returns RecordingStart', (t) async {
      final api = _Api([_google, _oneOff]);
      RecordingStart? result;
      await t.pumpWidget(layoutHost(Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showRecordSetupSheet(context, kind: 'meeting', id: 7, api: api),
          child: const Text('go'),
        ),
      ), scale: 1));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(api.calls, ['cloud']);
      expect(find.text('me@gmail.com'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      final start = find.byKey(const ValueKey('record_setup.start'));
      expect(start, findsOneWidget);
      await t.tap(start);
      await t.pumpAndSettle();
      expect(api.calls.last, 'start meeting/7');
      expect(api.startedTo, CloudProvider.googleDrive);
      expect(api.startedWith, RecordingQuality.p720);
      expect(result?.recordingId, 9);
      expect(result?.chunkPath, '/api/v1/live/recordings/9/chunk');
      expect(result?.quality, RecordingQuality.p720);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('nothing connected → Start stays off; a server refusal is shown in place', (t) async {
      final api = _Api([_oneOff, _oneOff]);
      await t.pumpWidget(layoutHost(RecordSetupSheet(kind: 'meeting', id: 7, api: api, initialAccounts: api.accounts), scale: 1));
      await t.pumpAndSettle();
      final button = t.widget<AppPrimaryButton>(find.byKey(const ValueKey('record_setup.start')));
      expect(button.onPressed, isNull);

      api.accounts = [_google, _oneOff];
      api.startError = const ApiException(statusCode: 409, message: 'x', type: ApiErrorType.conflict, code: 'recording_active');
      await t.pumpWidget(const SizedBox()); // a fresh sheet, not the same State with its old accounts
      await t.pumpWidget(layoutHost(RecordSetupSheet(kind: 'meeting', id: 7, api: api, initialAccounts: api.accounts), scale: 1));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('record_setup.start')));
      await t.pumpAndSettle();
      expect(find.text('A recording of this meeting is already running'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Connect asks the server for the auth URL; an empty one is reported, not polled', (t) async {
      final api = _Api([_oneOff, _oneOff]);
      await t.pumpWidget(layoutHost(RecordSetupSheet(kind: 'meeting', id: 7, api: api, initialAccounts: api.accounts), scale: 1));
      await t.pumpAndSettle();
      await t.tap(find.text('Connect').first);
      await t.pumpAndSettle();
      expect(api.calls, ['connect onedrive']);
      expect(find.text('Connecting the account failed, try again'), findsOneWidget);
      await t.pump(const Duration(seconds: 7));
      expect(api.calls.where((c) => c == 'cloud'), isEmpty, reason: 'no poll without an open auth page');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('unconfigured provider', () {
    Future<void> notices(WidgetTester t) async {
      // the notice goes to the root Navigator's overlay in the app; here: the test app's own
      appNoticeTopOverlay = () => t.state<NavigatorState>(find.byType(Navigator).first).overlay;
      addTearDown(() => appNoticeTopOverlay = null);
    }

    const unconfigured = ApiException(
      statusCode: 503,
      message: 'x',
      type: ApiErrorType.server,
      code: 'cloud_provider_unconfigured',
      body: {
        'detail': {'code': 'cloud_provider_unconfigured', 'message': 'x', 'provider': 'google_drive'},
      },
    );

    testWidgets('setup sheet: a 503 on Connect is a notice, the tile greys out, nothing is opened or polled', (t) async {
      final api = _Api([_googleOff, _oneOff])..connectError = unconfigured;
      await t.pumpWidget(layoutHost(RecordSetupSheet(kind: 'meeting', id: 7, api: api, initialAccounts: api.accounts), scale: 1));
      await notices(t);
      await t.pumpAndSettle();
      expect(find.text('Connect'), findsNWidgets(2));
      await t.tap(find.text('Connect').first);
      await t.pump();
      expect(api.calls, ['connect google_drive']);
      expect(find.text(_unsetText), findsNWidgets(2), reason: 'the notice + the greyed tile');
      expect(find.text('Connect'), findsOneWidget, reason: 'Google Drive no longer offers Connect');
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing, reason: 'no error banner, the notice says it');
      expect(find.text('Finish signing in in the browser — this sheet follows automatically.'), findsNothing);
      await t.pump(const Duration(seconds: 7));
      expect(api.calls.where((c) => c == 'cloud'), isEmpty, reason: 'no poll: no auth page was opened');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('connected drives page: the same 503 is a notice and greys the tile', (t) async {
      final api = _Api([_googleOff, _oneOff])..connectError = unconfigured;
      await t.pumpWidget(layoutHost(CloudDrivesPage(api: api), scale: 1, scaffold: false));
      await notices(t);
      await t.pump();
      await t.pump();
      expect(api.calls, ['cloud']);
      await t.tap(find.text('Connect').first);
      await t.pump();
      expect(api.calls, ['cloud', 'connect google_drive']);
      expect(find.text(_unsetText), findsNWidgets(2));
      expect(find.text('Connect'), findsOneWidget);
      await t.pump(const Duration(seconds: 7));
      await t.pumpWidget(const SizedBox());
    });
  });

  group('status card actions', () {
    testWidgets('Open only when done with a link; Retry only when failed', (t) async {
      var opened = 0, retried = 0;
      Widget card(MeetingRecording r) => RecordingStatusCard(recording: r, onOpen: () => opened++, onRetry: () => retried++);
      await t.pumpWidget(layoutHost(card(_rec('done', url: 'https://drive.google.com/x')), scale: 1));
      await t.tap(find.byKey(const ValueKey('recording.open')));
      expect(find.byKey(const ValueKey('recording.retry')), findsNothing);
      expect(opened, 1);
      await t.pumpWidget(layoutHost(card(_rec('failed', error: 'quota')), scale: 1));
      expect(find.byKey(const ValueKey('recording.open')), findsNothing);
      expect(find.text('quota'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('recording.retry')));
      expect(retried, 1);
      await t.pumpWidget(layoutHost(card(_rec('uploading')), scale: 1));
      expect(find.byKey(const ValueKey('recording.open')), findsNothing);
      expect(find.byKey(const ValueKey('recording.retry')), findsNothing);
      expect(find.text('Uploading to the drive'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('MeetingRecordingStatus loads the latest recording when the detail has none', (t) async {
      final api = _Api([]);
      await t.pumpWidget(layoutHost(MeetingRecordingStatus(meetingId: 7, api: api), scale: 1));
      await t.pump();
      expect(api.calls, ['list meeting/7']);
      expect(find.byKey(const ValueKey('recording.5')), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a recording in progress is re-read; Retry posts the retry', (t) async {
      final api = _Api([]);
      await t.pumpWidget(layoutHost(MeetingRecordingStatus(meetingId: 7, api: api, initial: _rec('failed', error: 'x')), scale: 1));
      await t.pump();
      expect(api.calls, isEmpty, reason: 'the detail already carried it');
      await t.tap(find.byKey(const ValueKey('recording.retry')));
      await t.pump();
      expect(api.calls, ['retry 5']);
      expect(find.text('Uploading to the drive'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(recordingStatusPoll + const Duration(seconds: 1));
    });
  });

  group('settings entry', () {
    testWidgets('shown by default and opens the page', (t) async {
      final api = _Api([_google, _oneOff]);
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: CloudDrivesSettingsEntry(api: api)), scale: 1));
      await t.pump();
      expect(find.byKey(const ValueKey('cloud_drives.entry')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cloud_drives.entry')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(CloudDrivesPage), findsOneWidget);
      await t.pump();
      expect(api.calls, ['cloud']);
      expect(find.text('me@gmail.com'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('hidden by the profile.cloud_drives kill-switch', (t) async {
      AppConfig.disableList = ['profile.cloud_drives'];
      await t.pumpWidget(layoutHost(const SingleChildScrollView(child: CloudDrivesSettingsEntry()), scale: 1));
      await t.pump();
      expect(find.byKey(const ValueKey('cloud_drives.entry')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('never while viewing as someone else', (t) async {
      ViewAsState.instance.start(id: 9, name: 'x', role: 'admin');
      await t.pumpWidget(layoutHost(const SingleChildScrollView(child: CloudDrivesSettingsEntry()), scale: 1));
      await t.pump();
      expect(find.byKey(const ValueKey('cloud_drives.entry')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
