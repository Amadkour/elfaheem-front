// Course list paging ("with many courses only the first 6 appear; scrolling does not load the next page"):
//   • AppInfiniteScroll (lib/design/app_infinite_scroll.dart) — the next page whenever the end is near: when the
//     pages don't fill the viewport, when a landed page adds no visible row while the person already sits at the end
//     (the catalogue hides enrolled courses), one request at a time while scrolling fast, nothing after the last
//     page, a failure waits for the person to scroll;
//   • CoursesProvider (the catalogue) on the wire — exactly one page, a last partial page, an empty list, a page
//     that repeats known courses, rapid calls, a search / mode switch that starts again at page 1 with the new side;
//   • MeHomeService — `scope` on GET /me/home and the cached home dropped on a context switch; an answer adopted
//     from the instructor home only for the side it was asked for;
//   • MyCoursesProvider — a failed next page waits, then the retry row loads it (no pull-to-refresh needed).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_infinite_scroll.dart';
import 'package:flutter_education_app/features/shared/course/course_scope.dart';
import 'package:flutter_education_app/features/student/courses/list/courses_provider.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> course(int id, {bool enrolled = false}) => {
      'id': id,
      'name_en': 'Course $id',
      'image_url': '',
      'type': 'recorded',
      'is_published': true,
      'is_enrolled': enrolled,
    };

/// A server holding [total] courses (ids 1…total), paged by skip / limit like GET /courses.
Map<String, dynamic> Function(dynamic) catalogue(int total, {bool sendTotal = true, bool Function(int id)? enrolled}) =>
    (o) {
      final skip = int.parse('${o.queryParameters['skip'] ?? 0}');
      final limit = int.parse('${o.queryParameters['limit'] ?? 20}');
      final ids = [for (var i = skip + 1; i <= total && i <= skip + limit; i++) i];
      return {
        'items': [for (final id in ids) course(id, enrolled: enrolled?.call(id) ?? false)],
        if (sendTotal) 'total': total,
        'scope': o.queryParameters['scope'] ?? 'all',
      };
    };

/// A list driven by AppInfiniteScroll the way the course lists use it.
class _Harness extends StatefulWidget {
  const _Harness({required this.load, required this.total, this.visible, this.rowHeight = 100});

  /// Loads the next page; returns how many rows it added.
  final Future<void> Function(_HarnessState s) load;
  final int total;

  /// Which loaded rows are shown (a client-side filter); null = all.
  final bool Function(int id)? visible;
  final double rowHeight;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final scroll = ScrollController();
  final rows = <int>[];
  bool loading = false;
  bool failed = false;
  int calls = 0;

  bool get hasMore => rows.length < widget.total;

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    calls++;
    setState(() => loading = true);
    await widget.load(this);
    if (mounted) setState(() => loading = false);
  }

  void addPage(int n) => rows.addAll([for (var i = rows.length + 1; i <= widget.total && n-- > 0; i++) i]);

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = rows.where(widget.visible ?? (_) => true).toList();
    return MaterialApp(
      home: Scaffold(
        body: AppInfiniteScroll(
          controller: scroll,
          hasMore: hasMore,
          loading: loading,
          failed: failed,
          onLoadMore: loadMore,
          threshold: 200,
          child: ListView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(), // as the course lists: a short list still takes a drag
            children: [
              for (final id in shown) SizedBox(height: widget.rowHeight, child: Text('row $id')),
              SizedBox(height: 40, child: Text(loading ? 'loading' : (hasMore ? '' : 'end'))),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('AppInfiniteScroll', () {
    testWidgets('the first pages do not fill the viewport → it keeps loading until they do', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_Harness(
        total: 100,
        rowHeight: 100,
        load: (s) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          s.addPage(6);
        },
      ));
      await _settle(tester);
      final s = tester.state<_HarnessState>(find.byType(_Harness));
      // 1200 px + the 200 px threshold need ~14 rows: three pages of 6, then it waits for the person to scroll
      expect(s.rows.length, 18);
      expect(s.calls, 3);
    });

    testWidgets('a page that adds no visible row while the person sits at the end → the next one is fetched',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // the catalogue hides enrolled courses: rows 7…30 are "enrolled", only 1…6 and 31+ show
      await tester.pumpWidget(_Harness(
        total: 60,
        rowHeight: 150,
        visible: (id) => id <= 6 || id > 30,
        load: (s) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          s.addPage(6);
        },
      ));
      await _settle(tester);
      final s = tester.state<_HarnessState>(find.byType(_Harness));
      // the 6 visible rows (900 px) overflow 800 px only a little — the end stays within reach, and nothing scrolls
      // while the hidden pages land: it must keep asking by itself until a visible row pushes the end away
      expect(s.rows.length, greaterThan(30), reason: 'pages of hidden rows never stall the list');
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('row 31'), findsOneWidget);
    });

    testWidgets('rapid scrolling: one request in flight at a time; nothing after the last page', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var inFlight = 0, maxInFlight = 0;
      await tester.pumpWidget(_Harness(
        total: 45,
        load: (s) async {
          inFlight++;
          maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          s.addPage(20);
          inFlight--;
        },
      ));
      await _settle(tester);
      final s = tester.state<_HarnessState>(find.byType(_Harness));
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _settle(tester);
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -3000));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _settle(tester);
      expect(maxInFlight, 1);
      expect(s.rows.length, 45);
      expect(s.calls, 3, reason: '20 + 20 + 5, never a fourth call');
      expect(find.text('end'), findsOneWidget);
    });

    testWidgets('a failed page is not retried on its own — only when the person scrolls again', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var fail = true;
      await tester.pumpWidget(_Harness(
        total: 40,
        load: (s) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (fail) {
            s.failed = true;
            return;
          }
          s.failed = false;
          s.addPage(20);
        },
      ));
      await _settle(tester);
      final s = tester.state<_HarnessState>(find.byType(_Harness));
      expect(s.calls, 1);
      await _settle(tester);
      expect(s.calls, 1, reason: 'no request loop on a failing server');
      fail = false;
      await tester.drag(find.byType(ListView), const Offset(0, -50));
      await _settle(tester);
      expect(s.rows, isNotEmpty);
    });
  });

  group('CoursesProvider (catalogue) on the wire', () {
    late AppModeController mode;
    final overview = {
      'items': [
        {
          'organization': {'id': 7, 'name_en': 'Org 7', 'path': '/7/', 'status': 'approved'},
          'role': 'member',
        },
      ],
    };

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      AppConfig.setOrgsEnabled(true);
      AppModeController.applyContext = (_) {};
      mode = AppModeController.instance;
      mode.debugSet(overview, mode: AppMode.individual, orgId: 7);
    });
    tearDown(() => mode.debugSet(const {}, mode: AppMode.individual));

    Future<(FakeApi, CoursesProvider)> open(Map<String, dynamic> Function(dynamic) route,
        {Duration latency = Duration.zero}) async {
      final fake = FakeApi({'GET /api/v1/courses': route}, latency: latency);
      fake.install();
      addTearDown(fake.uninstall);
      final p = CoursesProvider(mode: mode);
      addTearDown(p.dispose);
      return (fake, p);
    }

    test('exactly one page (total = page size): no second request', () async {
      final (fake, p) = await open(catalogue(20));
      await p.fetchCourses();
      expect(p.courses.length, 20);
      expect(p.hasMore, isFalse);
      await p.loadMore();
      expect(fake.calls.length, 1);
    });

    test('exactly one page on an older server without a total: one more request answers empty, then the end',
        () async {
      final (fake, p) = await open(catalogue(20, sendTotal: false));
      await p.fetchCourses();
      expect(p.hasMore, isTrue);
      await p.loadMore();
      expect(p.hasMore, isFalse);
      await p.loadMore();
      expect(fake.calls.map((c) => c.query['skip']).toList(), ['0', '20']);
    });

    test('a last partial page: 20 + 20 + 5, offsets 0 / 20 / 40, every course once', () async {
      final (fake, p) = await open(catalogue(45));
      await p.fetchCourses();
      await p.loadMore();
      await p.loadMore();
      await p.loadMore();
      expect(p.courses.length, 45);
      expect(p.courses.map((c) => c.id).toSet().length, 45);
      expect(p.hasMore, isFalse);
      expect(fake.calls.map((c) => c.query['skip']).toList(), ['0', '20', '40']);
      expect(fake.calls.every((c) => c.query['limit'] == '20'), isTrue);
    });

    test('an empty list: nothing more to ask', () async {
      final (fake, p) = await open(catalogue(0));
      await p.fetchCourses();
      expect(p.courses, isEmpty);
      expect(p.hasMore, isFalse);
      await p.loadMore();
      expect(fake.calls.length, 1);
    });

    test('rapid calls: one page request in flight, the page appended once', () async {
      final (fake, p) = await open(catalogue(60), latency: const Duration(milliseconds: 20));
      await p.fetchCourses();
      await Future.wait([for (var i = 0; i < 5; i++) p.loadMore()]);
      expect(fake.calls.length, 2);
      expect(p.courses.length, 40);
    });

    test('a page that repeats known courses (rows shifted on the server): no duplicate, the offset still moves on',
        () async {
      var shifted = false;
      final (fake, p) = await open((o) {
        final skip = int.parse('${o.queryParameters['skip']}');
        // page 2 starts 5 rows early: a course was published at the top meanwhile
        final from = skip == 0 ? 1 : (shifted ? skip + 1 : skip - 4);
        shifted = skip > 0;
        return {
          'items': [for (var i = from; i < from + 20 && i <= 50; i++) course(i)],
          'total': 50,
        };
      });
      await p.fetchCourses();
      await p.loadMore();
      expect(p.courses.length, 35);
      expect(p.courses.map((c) => c.id).toSet().length, 35);
      await p.loadMore();
      expect(fake.calls.map((c) => c.query['skip']).toList(), ['0', '20', '40']);
    });

    test('Individual mode sends scope=personal; switching to the organization starts again at page 1 with its side',
        () async {
      final (fake, p) = await open(catalogue(45), latency: const Duration(milliseconds: 20));
      await p.fetchCourses(search: 'math');
      expect(fake.calls.single.query, containsPair('scope', 'personal'));
      expect(fake.calls.single.query, containsPair('search', 'math'));
      final late = p.loadMore(); // page 2 of the personal side, still on its way when the mode changes
      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      expect(p.courses, isEmpty, reason: 'the personal courses never flash on the organization\'s page');
      await late;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final last = fake.calls.last.query;
      expect(last, containsPair('scope', 'org'));
      expect(last, containsPair('org_id', '7'));
      expect(last, containsPair('skip', '0'));
      expect(last, containsPair('search', 'math'), reason: 'the same filter, on the new side');
      expect(p.courses.length, 20, reason: 'the late personal page was dropped');
      expect(p.scope, const CourseScope.org(7));
    });

    test('a new search starts again at page 1', () async {
      final (fake, p) = await open(catalogue(45));
      await p.fetchCourses();
      await p.loadMore();
      await p.fetchCourses(search: 'x');
      expect(fake.calls.last.query, containsPair('skip', '0'));
      expect(p.courses.length, 20);
    });

    test('a catalogue never opened makes no request on a mode switch', () async {
      final (fake, _) = await open(catalogue(10));
      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.calls, isEmpty);
    });

    test('My courses: a page of known courses still moves the offset on (no request loop)', () async {
      final fake = FakeApi({
        'GET /api/v1/my-enrolled-courses': (o) => {
              // the server answers page 1 again for page 2
              'items': [for (var i = 1; i <= 20; i++) course(i, enrolled: true)],
              'total': 40,
              'scope': o.queryParameters['scope'] ?? 'all',
            },
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = MyCoursesProvider(mode: mode);
      addTearDown(p.dispose);
      await p.fetchMyEnrollments();
      await p.loadMore();
      await p.loadMore();
      expect(p.allCount, 20);
      expect(p.hasMore, isFalse);
      expect(fake.calls.map((c) => c.query['skip']).toList(), ['0', '20']);
      expect(fake.calls.first.query, containsPair('scope', 'personal'));
    });

    test('My courses: a failed next page waits for the retry row, which loads it (not stuck until a refresh)',
        () async {
      var failing = true;
      final fake = FakeApi({
        'GET /api/v1/my-enrolled-courses': (o) {
          final skip = int.parse('${o.queryParameters['skip']}');
          if (skip > 0 && failing) return const FakeResponse(400, {'detail': {'code': 'boom', 'message': 'boom'}});
          return {
            'items': [for (var i = skip + 1; i <= skip + 20 && i <= 30; i++) course(i, enrolled: true)],
            'total': 30,
          };
        },
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = MyCoursesProvider(mode: mode);
      addTearDown(p.dispose);
      await p.fetchMyEnrollments();
      await p.loadMore();
      expect(p.pageFailed, isTrue);
      final asked = fake.calls.length;
      await p.loadMore(); // scrolling alone does not hammer a failing endpoint
      expect(fake.calls.length, asked);
      failing = false;
      await p.loadMore(retry: true);
      expect(p.pageFailed, isFalse);
      expect(p.allCount, 30);
      expect(p.hasMore, isFalse);
    });
  });

  group('MeHomeService scope', () {
    late AppModeController mode;
    final overview = {
      'items': [
        {
          'organization': {'id': 7, 'name_en': 'Org 7', 'path': '/7/', 'status': 'approved'},
          'role': 'member',
        },
      ],
    };

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      AppConfig.setOrgsEnabled(true);
      AppModeController.applyContext = (_) {};
      mode = AppModeController.instance;
      mode.debugSet(overview, mode: AppMode.individual, orgId: 7);
    });
    tearDown(() => mode.debugSet(const {}, mode: AppMode.individual));

    Map<String, dynamic> payload(String side) => {
          'now': '2026-10-31T09:00:00Z',
          'today_date': '2026-10-31',
          'timezone': 'UTC',
          'role': 'student',
          'courses_progress': [
            {'course_id': side == 'org' ? 2 : 1, 'name_en': side, 'progress': 10},
          ],
        };

    test('GET /me/home carries the mode\'s side; a switch drops the cached home and loads the new side', () async {
      final queries = <Map<String, dynamic>?>[];
      final svc = MeHomeService(
        fetch: (p, {query}) async {
          queries.add(query);
          return payload('${query?['scope']}');
        },
        token: () async => 't',
      );
      await svc.ensure();
      expect(queries.single, {'scope': 'personal'});
      expect(svc.home?.coursesProgress.single.courseId, 1);

      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      svc.onScopeChanged();
      expect(svc.home?.coursesProgress, isEmpty, reason: 'the personal courses are gone at once');
      await pumpEventQueue();
      expect(queries.last, {'scope': 'org', 'org_id': 7});
      expect(svc.home?.coursesProgress.single.courseId, 2);

      // nothing listening: the next ensure() sees the cache is the other side's
      mode.debugSet(overview, mode: AppMode.individual);
      await svc.ensure();
      expect(queries.last, {'scope': 'personal'});
    });

    test('an answer that arrives after a switch loses its courses and the new side is loaded', () async {
      final gate = Completer<void>();
      final queries = <Map<String, dynamic>?>[];
      final svc = MeHomeService(
        fetch: (p, {query}) async {
          queries.add(query);
          if (queries.length == 1) await gate.future;
          return payload('${query?['scope']}');
        },
        token: () async => 't',
      );
      final first = svc.refresh();
      await pumpEventQueue();
      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      gate.complete();
      await first;
      expect(svc.home?.coursesProgress, isEmpty, reason: "the personal answer's courses are never shown");
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(queries.last, {'scope': 'org', 'org_id': 7});
      expect(svc.home?.coursesProgress.single.courseId, 2);
    });

    test('adopt keeps an answer only while the side it was asked for is the current one', () async {
      final svc = MeHomeService(fetch: (p, {query}) async => payload('${query?['scope']}'), token: () async => 't');
      final asked = MeHomeService.scopeQuery(); // personal
      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      expect(svc.adopt(payload('personal'), query: asked), isFalse);
      expect(svc.home, isNull, reason: "the personal home is never cached under the organization's key");
      expect(svc.adopt(payload('org'), query: MeHomeService.scopeQuery()), isTrue);
      expect(svc.home?.coursesProgress.single.courseId, 2);
    });

    test('instructor home: a mode switch while GET /me/home is in flight never caches the old side', () async {
      MeHomeService.instance.clear();
      addTearDown(MeHomeService.instance.clear);
      final fake = FakeApi({
        'GET /api/v1/teacher/dashboard': (o) => <String, dynamic>{},
        'GET /api/v1/me/home': (o) {
          final side = o.queryParameters['scope'] ?? '';
          // the person switches to the organization while the personal answer is on its way
          mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
          return {...payload(side), 'role': 'teacher'};
        },
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = TeacherHomeProvider();
      addTearDown(p.dispose);
      await p.init();
      expect(fake.calls.where((c) => c.path == '/api/v1/me/home').first.query, containsPair('scope', 'personal'));
      expect(MeHomeService.instance.home, isNull,
          reason: "the personal home must not be cached as the organization's (adopt checks the side it asked)");
    });
  });
}
