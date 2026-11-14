// App versions (D-143, docs/release/APP_RELEASES.md) over the fake backend:
//   • New version: the password is asked (re-auth) and sent with the request; the form's own checks send nothing;
//     the server's refusals land where they belong (version_exists → the version field, branch_invalid → the branch
//     field, reauth_failed / build_running → the strip above the button).
//   • A release's page follows `app_release_updated`: the event's step is drawn at once, only the new log lines are
//     fetched while the status stays, a new status reloads the release — no timer.
//   • Cancel / Retry / Make live (password) / Rollback (password) call their routes.
//   • The build server token is shown once.
//   • The version check: GET /app/version-check with and without the new download_url / source / notes.
//   • The web "new version is live" strip: must vs recommended vs older / other platforms.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/release/web_release_watch.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppPrimaryButton;
import 'package:flutter_education_app/features/admin/app_releases/app_release_detail.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_form.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_models.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_text.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_releases_samples.dart';
import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _b = '/api/v1/admin/app-releases';
final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Map<String, dynamic> _body(dynamic data) => Map<String, dynamic>.from(data is String ? jsonDecode(data) as Map : data as Map);

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _frames(tester, 4); // a focused field may still be scrolling itself into view
  await tester.ensureVisible(f);
  await _frames(tester, 3);
  await tester.tap(f);
  await _frames(tester);
}

Future<void> _tapKey(WidgetTester tester, String key) => _tap(tester, find.byKey(ValueKey(key)));

Future<void> _confirmDialog(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('app.confirm.ok')));

Future<void> _pump(WidgetTester tester, Widget page, {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
  await _frames(tester);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// Opens [page] on top of a home, so its pop (with the created release) can be seen.
class _Opener extends StatefulWidget {
  const _Opener(this.page, this.onResult);
  final Widget page;
  final void Function(Object?) onResult;
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => widget.page));
      widget.onResult(r);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('home'));
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  final latest = {for (final r in sampleReleases()) if (r.isLive) r.platform: r};

  group('New version', () {
    testWidgets('prefills from the live one + 1, asks the password and sends it', (tester) async {
      Map<String, dynamic>? sent;
      final fake = FakeApi({
        'GET $_b/config': (_) => releaseConfigJson(),
        'POST $_b': (o) {
          sent = _body(o.data);
          return FakeResponse(201, releaseJson(id: 12, status: 'queued'));
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      var asked = 0;
      Object? result;
      await _pump(
          tester,
          _Opener(NewAppReleasePage(latest: latest, askPassword: (_) async {
            asked++;
            return 'secret-pw';
          }), (r) => result = r));

      expect(tester.widget<TextField>(find.byKey(const ValueKey('release.version'))).controller!.text, '1.4.1');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('release.build'))).controller!.text, '53');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('release.branch'))).controller!.text, 'production');
      expect(find.textContaining('organizations'), findsOneWidget, reason: 'the live-site branch hint');

      await tester.enterText(find.byKey(const ValueKey('release.notes_en')), 'Faster lessons');
      await _tapKey(tester, 'release.policy.must');
      await _tapKey(tester, 'release.gate.direct');
      await _tapKey(tester, 'release.submit');
      await _frames(tester, 10);

      expect(asked, 1);
      expect(sent, isNotNull);
      expect(sent!['password'], 'secret-pw');
      expect(sent!['platform'], 'android');
      expect(sent!['version'], '1.4.1');
      expect(sent!['build_number'], 53);
      expect(sent!['policy'], 'must');
      expect(sent!['gate'], 'direct');
      expect(sent!['branch'], 'production');
      expect(sent!['source'], 'website');
      expect(sent!['channel'], 'website');
      expect(sent!['config'], {'branch': 'production', 'workflow': 'android-website'});
      expect(sent!['auto_publish'], isTrue);
      expect(sent!['notes_en'], 'Faster lessons');
      expect(result, isA<AppRelease>());
      expect((result as AppRelease).id, 12);
      await tester.pump(const Duration(seconds: 5));
      await _end(tester);
    });

    testWidgets('its own checks send nothing; a dismissed password sends nothing', (tester) async {
      final fake = FakeApi({'GET $_b/config': (_) => releaseConfigJson(notReady: const {}), 'POST $_b': (_) => FakeResponse(201, releaseJson())},
          latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => null));
      await _tapKey(tester, 'release.channel.store');
      await tester.enterText(find.byKey(const ValueKey('release.version')), '1.4');
      await tester.enterText(find.byKey(const ValueKey('release.branch')), 'bad branch!');
      await tester.enterText(find.byKey(const ValueKey('release.store_url')), 'http://play.google.com/x');
      await _tapKey(tester, 'release.submit');
      expect(find.text(releaseFieldError('version_format')), findsOneWidget);
      expect(find.text(releaseFieldError('branch_invalid')), findsOneWidget);
      expect(find.text(releaseFieldError('url_https')), findsOneWidget);
      expect(fake.calls.where((c) => c.method == 'POST'), isEmpty);

      await tester.enterText(find.byKey(const ValueKey('release.version')), '1.4.1');
      await tester.enterText(find.byKey(const ValueKey('release.branch')), 'production');
      await tester.enterText(find.byKey(const ValueKey('release.store_url')), 'https://play.google.com/store/apps/details?id=x');
      await _tapKey(tester, 'release.submit');
      expect(fake.calls.where((c) => c.method == 'POST'), isEmpty, reason: 'the password sheet was dismissed');
      await tester.pump(const Duration(seconds: 5));
      await _end(tester);
    });

    for (final (status, code, field) in const [
      (409, 'version_exists', 'version'),
      (400, 'branch_invalid', 'branch'),
      (400, 'branch_not_found', 'branch'),
      (403, 'reauth_failed', null),
      (409, 'build_running', null),
    ]) {
      testWidgets('the server refuses: $code', (tester) async {
        final fake = FakeApi({
          'GET $_b/config': (_) => releaseConfigJson(),
          'POST $_b': (_) => FakeResponse(status, {
                'detail': {'code': code, 'message': 'refused: $code'},
              }),
        }, latency: const Duration(milliseconds: 20))
          ..install();
        addTearDown(fake.uninstall);
        await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => 'pw'));
        await _tapKey(tester, 'release.submit');
        await _frames(tester, 10);
        expect(fake.calls.where((c) => c.method == 'POST'), hasLength(1));
        final text = releaseErrorText(code, '');
        if (field != null) {
          // under its field (the notice says it too)
          final input = tester.widget<TextField>(find.byKey(ValueKey('release.$field')));
          expect(input.decoration!.errorText, text);
        } else {
          expect(find.descendant(of: find.byKey(const ValueKey('release.error')), matching: find.text(text)), findsOneWidget);
        }
        expect(find.byType(NewAppReleasePage), findsOneWidget, reason: 'the form stays open');
        await tester.pump(const Duration(seconds: 5));
        await _end(tester);
      });
    }
  });

  group('Codemagic channels (D-144)', () {
    AppPrimaryButton submit(WidgetTester tester) => tester.widget<AppPrimaryButton>(find.byKey(const ValueKey('release.submit')));

    testWidgets('a channel that is not set up: Create is off and the box lists what is missing; nothing is sent', (tester) async {
      final fake = FakeApi({
        'GET $_b/config': (_) => releaseConfigJson(),
        'POST $_b': (_) => FakeResponse(201, releaseJson()),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => 'pw'));
      expect(submit(tester).onPressed, isNotNull, reason: 'Android on our website is ready');
      expect(find.textContaining('Ready: Codemagic builds Android'), findsOneWidget);

      await _tapKey(tester, 'release.channel.store');
      expect(submit(tester).onPressed, isNull, reason: 'the package name is still com.example.*');
      expect(find.byKey(const ValueKey('release.readiness.missing.package_name_example')), findsOneWidget);
      expect(find.text('From the server: package_name_example'), findsOneWidget, reason: "the server's own line");
      expect(find.byKey(const ValueKey('release.store_note')), findsOneWidget, reason: 'the store review note');
      expect(find.byKey(const ValueKey('release.submit.hint')), findsOneWidget);
      // prefilled from the server's defaults, editable
      expect(tester.widget<TextField>(find.byKey(const ValueKey('release.workflow'))).controller!.text, 'android-store');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('release.package_name'))).controller!.text, 'com.example.flutter_education_app');
      await _tapKey(tester, 'release.submit');
      expect(fake.calls.where((c) => c.method == 'POST'), isEmpty);

      // the iPhone store: the env names are shown for the owner
      await _tapKey(tester, 'release.platform.ios');
      await _tapKey(tester, 'release.channel.store');
      expect(find.text('APP_STORE_APP_ID'), findsOneWidget);
      expect(submit(tester).onPressed, isNull);
      // the iPhone web app is recorded only: always possible
      await _tapKey(tester, 'release.channel.website');
      expect(submit(tester).onPressed, isNotNull);
      await _end(tester);
    });

    testWidgets('a real package name typed for this version covers package_name_example; the config is sent', (tester) async {
      Map<String, dynamic>? sent;
      final fake = FakeApi({
        'GET $_b/config': (_) => releaseConfigJson(),
        'POST $_b': (o) {
          sent = _body(o.data);
          return FakeResponse(201, codemagicReleaseJson(id: 31, channel: 'store', status: 'queued'));
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => 'pw'));
      await _tapKey(tester, 'release.channel.store');
      expect(submit(tester).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('release.package_name')), 'com.doubley.nextbrain');
      await _frames(tester, 3);
      expect(submit(tester).onPressed, isNotNull, reason: 'the server re-checks with the same override');
      await tester.enterText(find.byKey(const ValueKey('release.store_url')), 'https://play.google.com/store/apps/details?id=com.doubley.nextbrain');
      await _tapKey(tester, 'release.submit');
      await _frames(tester, 10);
      expect(sent, isNotNull);
      expect(sent!['channel'], 'store');
      expect(sent!['source'], 'google_play');
      expect(sent!['config'], {
        'branch': 'production',
        'workflow': 'android-store',
        'track': 'internal',
        'package_name': 'com.doubley.nextbrain',
        'store_url': 'https://play.google.com/store/apps/details?id=com.doubley.nextbrain',
      });
      expect(sent!.containsKey('password'), isTrue);
      await tester.pump(const Duration(seconds: 5));
      await _end(tester);
    });

    testWidgets('the server refuses with channel_not_configured: its list lands in the box, Create goes off', (tester) async {
      final fake = FakeApi({
        'GET $_b/config': (_) => releaseConfigJson(notReady: const {}),
        'POST $_b': (_) => FakeResponse(400, {
              'detail': {
                'code': 'channel_not_configured',
                'message': 'هذه القناة غير جاهزة على الخادم بعد',
                'message_en': 'This channel is not configured on the server yet',
                'missing': ['APP_RELEASE_UPLOAD_SECRET'],
                'reasons_ar': ['مفتاح الرفع ناقص'],
                'reasons_en': ['upload key missing'],
              },
            }),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => 'pw'));
      expect(submit(tester).onPressed, isNotNull);
      await _tapKey(tester, 'release.submit');
      await _frames(tester, 10);
      expect(fake.calls.where((c) => c.method == 'POST'), hasLength(1));
      expect(find.byKey(const ValueKey('release.readiness.missing.APP_RELEASE_UPLOAD_SECRET')), findsOneWidget);
      expect(find.text('APP_RELEASE_UPLOAD_SECRET'), findsOneWidget);
      expect(find.text('upload key missing'), findsOneWidget, reason: 'the refusal brings its own lines');
      expect(submit(tester).onPressed, isNull, reason: 'a stale form cannot slip through twice');
      expect(find.byType(NewAppReleasePage), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await _end(tester);
    });

    testWidgets('the setup cannot be read: Create is off for a built channel until Retry works', (tester) async {
      var fail = true;
      final fake = FakeApi({
        'GET $_b/config': (_) => fail ? FakeResponse(503, {'detail': 'busy'}) : releaseConfigJson(notReady: const {}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => 'pw'));
      expect(submit(tester).onPressed, isNull);
      expect(find.byKey(const ValueKey('release.readiness.retry')), findsOneWidget);
      fail = false;
      await _tapKey(tester, 'release.readiness.retry');
      await _frames(tester, 4);
      expect(submit(tester).onPressed, isNotNull);
      await _end(tester);
    });

    test('channels, the old source, the defaults and the form checks', () {
      expect(releaseChannelsFor('android'), ['website', 'store']);
      expect(releaseChannelsFor('web'), ['website']);
      expect(releaseChannelsFor('windows'), ['website', 'store']);
      expect(releaseChannelBuilds('windows', 'store'), isFalse, reason: 'the Microsoft Store is recorded only in phase 1');
      expect(releaseChannelBuilds('ios', 'website'), isFalse, reason: 'the iPhone web app is recorded only');
      expect(releaseChannelBuilds('windows', 'website'), isTrue);
      expect(releaseChannelBuilds('macos', 'store'), isFalse);
      expect(AppRelease.fromJson(releaseJson(source: 'google_play')).channel, 'store', reason: 'an older reply: the source decides');
      expect(AppRelease.fromJson(releaseJson(source: 'custom')).channel, 'website');
      final r = AppRelease.fromJson(codemagicReleaseJson(channel: 'store'));
      expect(r.isStore, isTrue);
      expect(r.viaCodemagic, isTrue);
      expect(r.workflow, 'android-store');
      expect(r.codemagicLink(), startsWith('https://codemagic.io/app/'));
      final legacy = AppRelease.fromJson({...releaseJson(), 'codemagic_build_id': 'b1', 'executor': 'codemagic'});
      expect(legacy.codemagicLink(appId: 'a1'), 'https://codemagic.io/app/a1/build/b1');

      final cfg = ReleaseConfig.fromJson(releaseConfigJson());
      expect(cfg.appId, '6544a1c2e8b4f0b7d1a9c3e2');
      expect(cfg.defaultsFor('android', 'store').workflow, 'android-store');
      expect(cfg.defaultsFor('android', 'website').workflow, 'android-website');
      expect(cfg.defaultsFor('android', 'store').track, 'internal');
      expect(cfg.readiness('android', 'website').ready, isTrue);
      expect(cfg.readiness('android', 'store').missing, ['package_name_example']);
      expect(cfg.readiness('macos', 'store').ready, isTrue, reason: 'recorded only');
      final off = ReleaseConfig.fromJson(releaseConfigJson(codemagic: false));
      expect(off.readiness('web', 'website').missing, ['CODEMAGIC_API_TOKEN'], reason: 'Codemagic itself, once');
      expect(off.readiness('web', 'website').reasonFor('CODEMAGIC_API_TOKEN', 'en'), 'From the server: CODEMAGIC_API_TOKEN',
          reason: "the channel's sentence fills the Codemagic block's empty one");
      expect(AppRelease.fromJson(codemagicReleaseJson(channel: 'store', status: 'live', isLive: true)).canRollback, isFalse);
      expect(off.readiness('ios', 'website').ready, isTrue);
      expect(cfg.readiness('android', 'store').without(const {'package_name_example'}).ready, isTrue);
      expect(cfg.readiness('android', 'store').reasonFor('package_name_example', 'en'), 'From the server: package_name_example');

      AppReleaseDraft d({String channel = 'store', String? pkg, String? url, String? wf}) =>
          AppReleaseDraft(platform: 'android', version: '1.4.1', channel: channel, packageName: pkg, storeUrl: url, workflow: wf);
      expect(validateReleaseDraft(d(pkg: 'com.example.app'))['package_name'], 'package_name_example');
      expect(validateReleaseDraft(d(pkg: 'not a package'))['package_name'], 'package_name_invalid');
      expect(validateReleaseDraft(d(url: 'http://play'))['store_url'], 'url_https');
      expect(validateReleaseDraft(d(wf: 'bad workflow!'))['workflow'], 'workflow_invalid');
      expect(validateReleaseDraft(d()), isEmpty, reason: 'a built store version falls back to the server URL');
      expect(validateReleaseDraft(AppReleaseDraft(platform: 'macos', version: '1.0.0', channel: 'store'))['store_url'], 'url_https');
      final json = d(channel: 'website', pkg: 'x.y', url: 'https://ignored').toJson(password: 'pw');
      expect(json['channel'], 'website');
      expect(json['config'], {'branch': 'production'}, reason: 'no Play fields and no store link on the website channel');
      expect(json.containsKey('store_url'), isFalse);
      final ios = AppReleaseDraft(platform: 'ios', version: '1.0.0').toJson(password: 'pw');
      expect(ios['gate'], 'direct', reason: 'the iPhone web app is not built');
      expect(ios['config'], isEmpty);
    });

    test('the version check reads the channel and a server path', () {
      final store = serverUpdateOffer({'should_update': true, 'latest_version': '1.4.1', 'channel': 'store', 'download_url': 'https://play.google.com/x'},
          lang: 'en', platform: 'android')!;
      expect(store.source, 'google_play');
      expect(serverUpdateOffer({'should_update': true, 'channel': 'store', 'download_url': 'https://apps.apple.com/x'}, lang: 'en', platform: 'ios')!.source,
          'app_store');
      final site = serverUpdateOffer({'must_update': true, 'channel': 'website', 'source': 'website', 'download_url': '/api/v1/app/downloads/android/x-universal.apk'},
          lang: 'en', platform: 'android', apiBase: 'https://nextbrain.site/api')!;
      expect(site.source, 'website');
      expect(site.url, 'https://nextbrain.site/api/api/v1/app/downloads/android/x-universal.apk');
      expect(updateSourceOf({'source': 'custom', 'channel': 'website'}), 'custom');
      expect(updateSourceOf({}), 'website', reason: 'nothing said: the old behaviour');
    });
  });

  group('Release page', () {
    testWidgets('follows app_release_updated: step at once, new log lines only, a new status reloads', (tester) async {
      var release = releaseJson(id: 9, progress: 46, log: sampleLog(40));
String lineAt(int n) => '${sampleLog(1, from: n).single['line']}';
String stepText() => tester.widget<Text>(find.byKey(const ValueKey('release.step'))).data!;
      final fake = FakeApi({
        'GET $_b/9': (_) => release,
        'GET $_b/9/log': (o) {
          final after = int.parse('${o.queryParameters['after']}');
          return {'lines': sampleLog(3, from: after + 1), 'log_count': after + 3, 'status': 'building', 'progress': 72};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, AppReleaseDetailPage(id: 9, stream: _stream, bus: LiveEvents.instance));
      expect(fake.calls.where((c) => c.path == '$_b/9'), hasLength(1));
      expect(stepText(), lineAt(40), reason: 'no step from the server: the newest log line');

      LiveEvents.instance.emit(LiveEvents.appReleaseUpdated, {'id': 9, 'platform': 'android', 'status': 'building', 'progress': 72, 'current': false});
      await _frames(tester, 4);
            expect(find.text('72%'), findsOneWidget);
      final logCalls = fake.calls.where((c) => c.path == '$_b/9/log').toList();
      expect(logCalls, hasLength(1));
      expect('${logCalls.single.query['after']}', '40');
      expect(fake.calls.where((c) => c.path == '$_b/9'), hasLength(1), reason: 'same status: the log only');
      expect(stepText(), lineAt(43));

      // another release's event is not this page's
      LiveEvents.instance.emit(LiveEvents.appReleaseUpdated, {'id': '77', 'status': 'failed'});
      await _frames(tester, 4);
      expect(fake.calls.where((c) => c.path.startsWith('$_b/9')), hasLength(2));

      release = releaseJson(id: 9, status: 'ready', autoPublish: false, progress: 100, log: sampleLog(43), artifacts: apkArtifacts);
      LiveEvents.instance.emit(LiveEvents.appReleaseUpdated, {'id': '9', 'status': 'ready', 'progress': 100});
      await _frames(tester, 4);
      expect(fake.calls.where((c) => c.path == '$_b/9'), hasLength(2), reason: 'a new status reloads the release');
      expect(find.byKey(const ValueKey('release.action.publish')), findsOneWidget);
      expect(find.byKey(const ValueKey('release.artifacts')), findsOneWidget);
      await _end(tester);
    });

    testWidgets('Cancel, Retry, Make live (password), Rollback (password)', (tester) async {
      final posts = <String, Map<String, dynamic>?>{};
      var status = 'building';
      final fake = FakeApi({
        'GET $_b/9': (_) => releaseJson(id: 9, status: status, isLive: status == 'live', progress: 50, log: sampleLog(3)),
        'GET $_b/9/log': (_) => {'lines': []},
        'POST $_b/9/cancel': (o) {
          posts['cancel'] = null;
          status = 'canceled';
          return releaseJson(id: 9, status: 'canceled');
        },
        'POST $_b/9/retry': (o) {
          posts['retry'] = null;
          status = 'ready';
          return releaseJson(id: 9, status: 'queued');
        },
        'POST $_b/9/publish': (o) {
          posts['publish'] = _body(o.data);
          status = 'live';
          return releaseJson(id: 9, status: 'live', isLive: true);
        },
        'POST $_b/9/rollback': (o) {
          posts['rollback'] = _body(o.data);
          status = 'rolled_back';
          return releaseJson(id: 9, status: 'rolled_back');
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      var asked = 0;
      await _pump(tester, AppReleaseDetailPage(id: 9, stream: _stream, bus: LiveEvents.instance, askPassword: (_) async {
        asked++;
        return 'pw-$asked';
      }));

      await _tapKey(tester, 'release.action.cancel');
      await _confirmDialog(tester);
      expect(posts.containsKey('cancel'), isTrue);
      expect(find.byKey(const ValueKey('release.action.retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('release.action.cancel')), findsNothing);

      await _tapKey(tester, 'release.action.retry');
      expect(posts.containsKey('retry'), isTrue);
      await _frames(tester);
      expect(find.byKey(const ValueKey('release.action.publish')), findsOneWidget);

      await _tapKey(tester, 'release.action.publish');
      await _confirmDialog(tester);
      expect(posts['publish'], {'password': 'pw-1'});
      await _frames(tester);
      expect(find.byKey(const ValueKey('release.action.rollback')), findsOneWidget);

      await _tapKey(tester, 'release.action.rollback');
      await _confirmDialog(tester);
      expect(posts['rollback'], {'password': 'pw-2'});
      expect(asked, 2, reason: 'cancel and retry ask no password');
      await tester.pump(const Duration(seconds: 5));
      await _end(tester);
    });
  });

  group('Build runner (D-146)', () {
    AppPrimaryButton submit(WidgetTester tester) => tester.widget<AppPrimaryButton>(find.byKey(const ValueKey('release.submit')));

    test('the config: executors, the default, the runners, readiness per executor', () {
      final cfg = ReleaseConfig.fromJson(releaseConfigJson(codemagic: false, runner: true, runners: [
        runnerJson(),
        runnerJson(name: 'wsl', os: 'linux', platforms: const ['linux', 'android', 'web'], online: false),
      ]));
      expect(cfg.supportsRunner, isTrue);
      expect(cfg.defaultExecutor, 'runner');
      expect(cfg.runners.items.map((r) => r.name), ['office-pc', 'wsl']);
      expect(cfg.runners.online.map((r) => r.name), ['office-pc']);
      expect(cfg.runners.onlineFor('windows'), isTrue);
      expect(cfg.runners.onlineFor('linux'), isFalse, reason: 'the Linux runner is off');
      expect(cfg.runners.tokenSet, isTrue);
      expect(cfg.readiness('android', 'website').ready, isFalse, reason: 'Codemagic has no token');
      expect(cfg.readiness('android', 'website', executor: 'runner').ready, isTrue, reason: 'the runner needs none');
      expect(cfg.readiness('android', 'store', executor: 'runner').missing, ['runner_channel']);
      expect(cfg.readiness('ios', 'website', executor: 'runner').ready, isTrue, reason: 'the PWA record');
      final old = ReleaseConfig.fromJson(releaseConfigJson());
      expect(old.supportsRunner, isFalse);
      expect(old.runners.items, isEmpty);
      final r = AppRelease.fromJson({...codemagicReleaseJson(), 'executor': 'runner', 'codemagic_build_id': null, 'codemagic_url': null});
      expect(r.viaRunner && !r.viaCodemagic && r.builds, isTrue);
      const d = AppReleaseDraft(platform: 'windows', version: '1.0.1', executor: 'runner');
      expect(d.toJson(password: 'x')['executor'], 'runner');
      const rec = AppReleaseDraft(platform: 'macos', version: '1.0.1', executor: 'runner');
      expect(rec.toJson(password: 'x').containsKey('executor'), isFalse, reason: 'a recorded version is built by nobody');
    });

    testWidgets('the form starts on My computer, says when no runner is on, and sends the executor', (tester) async {
      Map<String, dynamic>? sent;
      final fake = FakeApi({
        'GET $_b/config': (_) => releaseConfigJson(codemagic: false, runner: true, runners: [
              runnerJson(name: 'wsl', os: 'linux', platforms: const ['linux', 'android', 'web']),
            ]),
        'POST $_b': (o) {
          sent = _body(o.data);
          return FakeResponse(201, {...releaseJson(), 'executor': 'runner'});
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, NewAppReleasePage(latest: latest, askPassword: (_) async => 'pw'));
      expect(find.byKey(const ValueKey('release.executor.runner')), findsOneWidget);
      expect(submit(tester).onPressed, isNotNull, reason: 'Codemagic is not set up, yet the runner can build Android');
      expect(find.textContaining('Ready: My computer (free) builds Android'), findsOneWidget);
      expect(find.byKey(const ValueKey('release.runner_off')), findsNothing, reason: 'the WSL runner builds Android');

      await _tapKey(tester, 'release.platform.windows');
      expect(find.byKey(const ValueKey('release.runner_off')), findsOneWidget, reason: 'no runner builds Windows now');
      expect(submit(tester).onPressed, isNotNull, reason: 'it may still be created: it waits in the queue');

      await _tapKey(tester, 'release.executor.codemagic');
      expect(submit(tester).onPressed, isNull, reason: 'Codemagic still needs its token');
      expect(find.byKey(const ValueKey('release.readiness.missing.CODEMAGIC_API_TOKEN')), findsOneWidget);
      await _tapKey(tester, 'release.executor.runner');
      expect(submit(tester).onPressed, isNotNull);

      // a store channel is Codemagic's: no picker, Codemagic's readiness
      await _tapKey(tester, 'release.platform.android');
      await _tapKey(tester, 'release.channel.store');
      expect(find.byKey(const ValueKey('release.executor.runner')), findsNothing);
      expect(submit(tester).onPressed, isNull);
      await _tapKey(tester, 'release.channel.website');

      await _tapKey(tester, 'release.submit');
      await _frames(tester);
      expect(sent?['executor'], 'runner');
      expect(sent?['platform'], 'android');
      expect(sent?['password'], 'pw');
      await _end(tester);
    });

    testWidgets('the page: the runner card and its token; Codemagic is optional', (tester) async {
      var rotations = 0;
      final fake = FakeApi({
        'GET $_b': (_) => releasesListJson(),
        'GET $_b/config': (_) => releaseConfigJson(codemagic: false, runner: true, runners: [runnerJson(busy: 9)]),
        'POST $_b/builder/token': (o) {
          rotations++;
          return {'token': 'nbb_runner_$rotations'};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, AppReleasesPage(stream: _stream, bus: LiveEvents.instance, askPassword: (_) async => 'pw'));
      expect(find.text('Build runner on'), findsOneWidget);
      expect(find.textContaining('office-pc'), findsWidgets);
      expect(find.text('Codemagic not connected (optional)'), findsOneWidget);
      expect(fake.calls.where((c) => c.path == '$_b/builder/status').length, lessThanOrEqualTo(1), reason: 'only the first load asks (an older server has no config)');
      await _tapKey(tester, 'releases.runner.token');
      await _confirmDialog(tester);
      expect(find.text('nbb_runner_1'), findsOneWidget);
      expect(find.textContaining('NB_BUILDER_TOKEN'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await _frames(tester);
      expect(rotations, 1);
      await tester.pump(const Duration(seconds: 5));
      await _end(tester);
    });

    test('runner failures read as sentences', () {
      expect(releaseErrorText('runner_lost: the build runner stopped reporting', ''), contains('stopped reporting'));
      expect(releaseErrorText('runner: signing_key_missing: set NB_KEY_PROPERTIES', ''), contains('Android release key'));
      expect(releaseErrorText('runner: step "Gate": exit 1', ''), 'Build runner: step "Gate": exit 1');
      expect(releaseErrorText('upload_missing: x', ''), isNot(contains('Codemagic')));
      expect(releaseMissingText('runner_channel'), contains('Codemagic only'));
    });
  });

  testWidgets('list: grouped, the builder status, a new token is shown once', (tester) async {
    var rotations = 0;
    final tokenPasswords = <Object?>[];
    final fake = FakeApi({
      'GET $_b': (_) => releasesListJson(),
      'GET $_b/builder/status': (_) => builderJson(),
      'POST $_b/builder/token': (o) {
        tokenPasswords.add(_body(o.data)['password']);
        rotations++;
        return {'token': 'nbb_secret_$rotations'};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    await _pump(tester, AppReleasesPage(stream: _stream, bus: LiveEvents.instance, askPassword: (_) async => 'pw'));
    expect(find.text('Build server online'), findsOneWidget);
    expect(find.text('Live: 1.4.0 (52)'), findsNWidgets(3), reason: 'the android, iPhone and web live releases are marked');
    expect(find.byKey(const ValueKey('releases.row.9')), findsOneWidget);

    // a release moved → the list reloads on the event, not on a timer
    final before = fake.calls.where((c) => c.path == _b).length;
    LiveEvents.instance.emit(LiveEvents.appReleaseUpdated, {'id': '9', 'status': 'testing'});
    await _frames(tester, 4);
    expect(fake.calls.where((c) => c.path == _b).length, before + 1);

    await _tapKey(tester, 'releases.rotate');
    await _confirmDialog(tester);
    expect(find.text('nbb_secret_1'), findsOneWidget);
    expect(find.byKey(const ValueKey('releases.token.copy')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await _frames(tester);
    expect(find.text('nbb_secret_1'), findsNothing, reason: 'shown once: the page keeps no copy');
    expect(rotations, 1);
    expect(tokenPasswords, ['pw'], reason: 'the token is created with the account password');
    await tester.pump(const Duration(seconds: 5));
    await _end(tester);
  });

  group('version check', () {
    test('a new server names the link, the source and the notes', () {
      final o = serverUpdateOffer({
        'must_update': false,
        'should_update': true,
        'latest_version': '1.4.1',
        'release_notes': {'ar': 'قديم', 'en': 'old'},
        'download_url': 'https://play.google.com/store/apps/details?id=com.nextbrain',
        'source': 'google_play',
        'notes': {'ar': 'دروس أسرع', 'en': 'Faster lessons'},
      }, lang: 'en')!;
      expect(o.force, isFalse);
      expect(o.version, '1.4.1');
      expect(o.source, 'google_play');
      expect(o.notes, 'Faster lessons');
      expect(serverUpdateOffer({'must_update': true, 'download_url': 'https://x.site/a.apk', 'notes': {'ar': 'عربي'}}, lang: 'en')!.notes, 'عربي',
          reason: 'the other language when mine is missing');
      expect(serverUpdateOffer({'must_update': true, 'download_url': 'https://x.site/a.apk'}, lang: 'ar')!.force, isTrue);
    });

    test('an older answer (no download_url), no update, or a non-https link leaves the manifest in charge', () {
      expect(serverUpdateOffer({'must_update': true, 'should_update': true, 'latest_version': '2.0.0', 'release_notes': {'en': 'x'}}, lang: 'en'), isNull);
      expect(serverUpdateOffer({'must_update': false, 'should_update': false, 'download_url': 'https://x.site/a.apk'}, lang: 'en'), isNull);
      expect(serverUpdateOffer({'should_update': true, 'download_url': 'http://x.site/a.apk'}, lang: 'en'), isNull);
    });

    test('the snooze keys of both kinds', () {
      final now = DateTime(2026, 11, 2, 12);
      final at = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      expect(updateSnoozed('v1.4.1:$at', 'v1.4.1', now), isTrue);
      expect(updateSnoozed('v1.4.0:$at', 'v1.4.1', now), isFalse);
      expect(updateSnoozed('52:$at', 52, now), isTrue);
    });

    testWidgets('the dialog: store button + notes with the new fields, the download button without', (tester) async {
      var opened = 0;
      await _pump(
          tester,
          UpdateDialog(force: false, version: '1.4.1', notes: 'Faster lessons', source: 'google_play', onUpdate: () => opened++, onLater: () {}),
          size: const Size(390, 844));
      expect(find.text('Open Google Play'), findsOneWidget);
      expect(find.textContaining('Faster lessons'), findsOneWidget);
      expect(find.textContaining('install it over the current app'), findsNothing, reason: 'no file to install from a store');
      await tester.tap(find.text('Open Google Play'));
      expect(opened, 1);

      await _pump(tester, UpdateDialog(force: true, version: '1.4.1', onUpdate: () {}, onLater: () {}), size: const Size(390, 844));
      expect(find.text('Download update'), findsOneWidget);
      expect(find.textContaining('install it over the current app'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      await _end(tester);
    });
  });

  group('web: a new version is live', () {
    test('the rule', () {
      Map<String, dynamic> ev(String policy, {String platform = 'web', int build = 53, String version = '1.4.1', String? min}) =>
          {'platform': platform, 'version': version, 'build_number': build, 'policy': policy, 'min_supported': ?min};
      WebReleaseNeed need(Map<String, dynamic> e) => webReleaseNeed(runningVersion: '1.4.0', runningBuild: 52, event: e);
      expect(need(ev('must')), WebReleaseNeed.must);
      expect(need(ev('recommended')), WebReleaseNeed.suggest);
      expect(need(ev('optional')), WebReleaseNeed.none);
      expect(need(ev('optional', min: '1.4.1')), WebReleaseNeed.must, reason: 'below the minimum supported');
      expect(need(ev('must', platform: 'android')), WebReleaseNeed.none);
      expect(need(ev('must', build: 52, version: '1.4.0')), WebReleaseNeed.none, reason: 'this very build');
      expect(webReleaseNeed(runningVersion: '1.4.0', runningBuild: 0, event: {'platform': 'web', 'version': '1.4.1', 'policy': 'must'}),
          WebReleaseNeed.must, reason: 'no build number: the version decides');
      expect(need({'platform': 'web', 'version': '1.4.1', 'build_number': 53, 'policy': 'optional', 'must': true}), WebReleaseNeed.must, reason: 'the server says must');
      expect(need({'platform': 'web', 'version': '1.3.9', 'build_number': 51, 'policy': 'recommended', 'must': false}), WebReleaseNeed.suggest,
          reason: 'a rollback: the running build was taken down');
    });

    testWidgets('must stays, recommended can be closed; Reload reloads', (tester) async {
      var reloads = 0;
      final bus = LiveEvents.instance;
      final watch = WebReleaseWatch(bus: bus, running: ('1.4.0', 52), reload: () => reloads++);
      addTearDown(watch.dispose);
      await _pump(tester, WebReleaseBanner(enabled: true, watch: watch, child: const Scaffold(body: Text('page'))), size: const Size(390, 844));
      expect(find.byType(WebReleaseStrip), findsNothing);

      bus.emit(LiveEvents.appReleaseLive, {'platform': 'web', 'version': '1.4.1', 'build_number': '53', 'policy': 'recommended'});
      await _frames(tester, 4);
      expect(find.text('A new version is live'), findsOneWidget);
      await _tapKey(tester, 'web_release.dismiss');
      expect(find.byType(WebReleaseStrip), findsNothing);

      bus.emit(LiveEvents.appReleaseLive, {'platform': 'web', 'version': '1.4.2', 'build_number': '54', 'policy': 'must'});
      await _frames(tester, 4);
      expect(find.byKey(const ValueKey('web_release.dismiss')), findsNothing);
      await _tapKey(tester, 'web_release.reload');
      expect(reloads, 1);
      expect(find.text('page'), findsOneWidget);
      await _end(tester);
    });
  });
}
