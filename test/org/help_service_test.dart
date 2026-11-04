// HelpService (f3): cache + version logic over a fake transport.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/shared/help/help_models.dart';
import 'package:flutter_education_app/features/shared/help/help_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRemote implements HelpRemote {
  int serverVersion = 1;
  bool offline = false;
  int versionCalls = 0, pageCalls = 0;
  String? lastEtag;
  int? lastOrg;
  Map<String, dynamic> entry = jsonDecode(File('test/fixtures/help_entry_home_student.json').readAsStringSync());

  @override
  Future<int?> version({String? etag}) async {
    versionCalls++;
    lastEtag = etag;
    if (offline) throw Exception('offline');
    return etag == '"help-$serverVersion"' ? null : serverVersion; // 304 = null
  }

  @override
  Future<Map<String, dynamic>> pages({int? orgId}) async {
    pageCalls++;
    lastOrg = orgId;
    if (offline) throw Exception('offline');
    return {'version': serverVersion, 'role': 'student', 'pages': [entry]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRemote remote;
  late DateTime now;
  HelpService make() => HelpService(remote: remote, clock: () => now);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remote = FakeRemote();
    now = DateTime(2026, 11, 4, 9);
  });

  test('first ask fetches the pages and exposes the entry', () async {
    final s = make();
    await s.ensure(userKey: '7', orgId: 3);
    expect(remote.pageCalls, 1);
    expect(remote.lastOrg, 3);
    expect(s.version, 1);
    expect(s.entry('home.student')?.title.of('en'), 'Home');
    expect(s.entry('nope'), isNull);
    expect(s.entry('home.student')!.hasTour, isTrue);
  });

  test('same start: the version is checked once, then not again within the hour', () async {
    final s = make();
    await s.ensure(userKey: '7');
    await s.ensure(userKey: '7');
    now = now.add(const Duration(minutes: 59));
    await s.ensure(userKey: '7');
    expect(remote.pageCalls, 1);
    expect(remote.versionCalls, 0); // the first ask loaded pages, no version call needed
  });

  test('a restart uses the cache and a 304 keeps it (no refetch)', () async {
    await make().ensure(userKey: '7');
    final s2 = make(); // new app start: empty memory, device cache present
    await s2.ensure(userKey: '7');
    expect(s2.entry('home.student'), isNotNull);
    expect(remote.versionCalls, 1);
    expect(remote.lastEtag, '"help-1"');
    expect(remote.pageCalls, 1); // only the first start fetched
  });

  test('a new server version refetches after the hour', () async {
    final s = make();
    await s.ensure(userKey: '7');
    remote.serverVersion = 2;
    (remote.entry['title'] as Map)['en'] = 'Home v2';
    now = now.add(const Duration(hours: 1, minutes: 1));
    await s.ensure(userKey: '7');
    expect(remote.versionCalls, 1);
    expect(remote.pageCalls, 2);
    expect(s.version, 2);
    expect(s.entry('home.student')!.title.of('en'), 'Home v2');
  });

  test('offline keeps the cached copy and retries only after a minute', () async {
    await make().ensure(userKey: '7');
    remote.offline = true;
    final s2 = make();
    await s2.ensure(userKey: '7');
    expect(s2.entry('home.student'), isNotNull);
    expect(remote.versionCalls, 1);
    await s2.ensure(userKey: '7'); // inside the retry window
    expect(remote.versionCalls, 1);
    now = now.add(const Duration(minutes: 2));
    await s2.ensure(userKey: '7');
    expect(remote.versionCalls, 2);
    expect(s2.entry('home.student'), isNotNull);
  });

  test('offline with no cache: no entries, no throw', () async {
    remote.offline = true;
    final s = make();
    await s.ensure(userKey: '9');
    expect(s.count, 0);
  });

  test('another person or organization context has its own cache', () async {
    final s = make();
    await s.ensure(userKey: '7');
    await s.ensure(userKey: '8');
    expect(remote.pageCalls, 2);
    await s.ensure(userKey: '8', orgId: 5);
    expect(remote.pageCalls, 3);
  });

  test('the tour is remembered per person per page', () async {
    final s = make();
    expect(await s.tourSeen('7', 'home.student'), isFalse);
    await s.markTourSeen('7', 'home.student');
    expect(await s.tourSeen('7', 'home.student'), isTrue);
    expect(await s.tourSeen('8', 'home.student'), isFalse);
    expect(await s.tourSeen('7', 'course'), isFalse);
  });

  test('HelpText falls back to the other language', () {
    expect(const HelpText('', 'x').of('ar'), 'x');
    expect(const HelpText('a', 'x').of('ar'), 'a');
  });
}
