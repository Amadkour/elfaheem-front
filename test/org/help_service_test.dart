// HelpService (f3): cache + version logic over a fake transport.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/help/help_models.dart';
import 'package:flutter_education_app/features/help/help_service.dart';
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

  test('no request until a tap: the bundled index and the cache are read locally', () async {
    final s = HelpService(remote: remote, clock: () => now, indexLoader: () async => '{"version":1,"pages":[["home.student","student"],["org.members","org_admin"]]}');
    await s.loadLocal(userKey: '7', helpRole: 'org_admin');
    expect(s.has('home.student'), isTrue); // from the bundled index (org_admin falls back to student)
    expect(s.has('org.members'), isTrue);
    expect(s.has('nope'), isFalse);
    expect(s.entry('home.student'), isNull); // no content yet: the tour waits
    expect(remote.pageCalls + remote.versionCalls, 0);
    await s.ensure(userKey: '7'); // the tap
    expect(remote.pageCalls, 1);
    expect(s.entry('home.student'), isNotNull);
    expect(s.has('org.members'), isFalse); // the cached catalogue overrides the index
    expect(s.has('home.student'), isTrue);
  });

  test('a cached catalogue from an earlier session is used without any request', () async {
    await make().ensure(userKey: '7');
    remote.pageCalls = remote.versionCalls = 0;
    final s2 = HelpService(remote: remote, clock: () => now, indexLoader: () async => '{"pages":[["other","student"]]}');
    await s2.loadLocal(userKey: '7', helpRole: 'student');
    expect(s2.has('home.student'), isTrue);
    expect(s2.has('other'), isFalse);
    expect(s2.entry('home.student'), isNotNull);
    expect(remote.pageCalls + remote.versionCalls, 0);
    await s2.ensure(userKey: '7'); // first tap of the session: version check, 304 keeps
    expect(remote.versionCalls, 1);
    expect(remote.pageCalls, 0);
  });

  test('a missing or damaged index shows nothing and never throws', () async {
    final s = HelpService(remote: remote, indexLoader: () async => throw Exception('no asset'));
    await s.loadLocal(userKey: '7', helpRole: 'student');
    expect(s.has('home.student'), isFalse);
  });

  test('help role resolution follows the server', () {
    String r(String? p, {bool o = false, bool a = false}) => HelpService.helpRoleOf(p, inOrg: o, orgAdmin: a);
    for (final p in ['admin', 'super-admin', 'developer']) {
      expect(r(p), 'super_admin');
      expect(r(p, o: true, a: true), 'super_admin'); // a platform admin stays super_admin inside an org
    }
    expect(r('teacher'), 'teacher');
    expect(r('parent'), 'parent');
    expect(r('student'), 'student');
    expect(r(null), 'student');
    expect(r('org-admin'), 'org_admin');
    expect(r('org-staff'), 'org_member');
    expect(r('teacher', o: true), 'org_member');
    expect(r('student', o: true), 'org_member');
    expect(r('student', o: true, a: true), 'org_admin');
    expect(HelpService.helpFallback('super_admin'), ['super_admin', 'org_admin']);
    expect(HelpService.helpFallback('org_admin'), ['org_admin', 'org_member', 'student']);
    expect(HelpService.helpFallback('org_member'), ['org_member', 'student']);
    expect(HelpService.helpFallback('teacher'), ['teacher', 'student']);
    expect(HelpService.helpFallback('parent'), ['parent', 'student']);
    expect(HelpService.helpFallback('student'), ['student']);
  });

  test('has() is role-aware with the fallback chains', () async {
    const idx = '{"pages":[["p.student","student"],["p.member","org_member"],["p.admin","org_admin"],["p.sa","super_admin"],["p.teacher","teacher"],["p.parent","parent"]]}';
    Future<HelpService> as(String role) async {
      final s = HelpService(remote: remote, indexLoader: () async => idx);
      await s.loadLocal(userKey: '7', helpRole: role);
      await s.loadIndex();
      return s;
    }

    final student = await as('student');
    expect([for (final p in ['p.student', 'p.member', 'p.admin', 'p.sa', 'p.teacher', 'p.parent']) student.has(p)], [true, false, false, false, false, false]);
    final teacher = await as('teacher');
    expect([for (final p in ['p.student', 'p.member', 'p.admin', 'p.sa', 'p.teacher', 'p.parent']) teacher.has(p)], [true, false, false, false, true, false]);
    final parent = await as('parent');
    expect([for (final p in ['p.student', 'p.member', 'p.admin', 'p.sa', 'p.teacher', 'p.parent']) parent.has(p)], [true, false, false, false, false, true]);
    final member = await as('org_member');
    expect([for (final p in ['p.student', 'p.member', 'p.admin', 'p.sa', 'p.teacher', 'p.parent']) member.has(p)], [true, true, false, false, false, false]);
    final admin = await as('org_admin');
    expect([for (final p in ['p.student', 'p.member', 'p.admin', 'p.sa', 'p.teacher', 'p.parent']) admin.has(p)], [true, true, true, false, false, false]);
    final sa = await as('super_admin');
    expect([for (final p in ['p.student', 'p.member', 'p.admin', 'p.sa', 'p.teacher', 'p.parent']) sa.has(p)], [false, false, true, true, false, false]);
    final unknown = HelpService(remote: remote, indexLoader: () async => idx);
    await unknown.loadIndex();
    expect(unknown.has('p.student'), isFalse); // role not known yet: no button
  });

  test('the real bundled index loads', () async {
    final s = HelpService(remote: remote);
    await s.loadLocal(userKey: '7', helpRole: 'student');
    await s.loadIndex();
    expect(s.has('home.student'), isTrue);
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
