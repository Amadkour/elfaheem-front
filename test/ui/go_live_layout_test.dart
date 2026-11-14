// "Go live" on the instructor home (D-091, lib/features/teacher/home/go_live_sheet.dart): the header pill and the
// sheet at phone and web sizes, Arabic and English, text scale 1.3 — no overflow; then the sheet's flow over a fake
// API (a new session is created with the default title, a scheduled one is started as it is, Record turned on).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/teacher/home/go_live.dart';
import 'package:flutter_education_app/features/teacher/home/go_live_sheet.dart';
import 'package:flutter_education_app/features/sessions/teacher/model/live_response_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _now = DateTime.utc(2026, 10, 29, 10, 0);

class FakeGoLiveApi implements GoLiveApi {
  FakeGoLiveApi(this.rows, {this.failCreate = false});
  final List<GoLiveSession> rows;
  final bool failCreate;
  final calls = <String>[];
  String? createdTitle;
  bool? createdRecord;
  DateTime? createdAt;

  @override
  Future<List<GoLiveSession>> sessions(int courseId) async {
    calls.add('sessions $courseId');
    return rows;
  }

  @override
  Future<int> create({required int courseId, required String title, required DateTime startsAt, int minutes = 60, required bool record}) async {
    calls.add('create $courseId');
    if (failCreate) throw Exception('boom');
    createdTitle = title;
    createdRecord = record;
    createdAt = startsAt;
    return 77;
  }

  @override
  Future<void> setRecord(int sessionId, bool record) async => calls.add('record $sessionId $record');

  @override
  Future<LiveResponseModel> start(int sessionId, {bool? record}) async => LiveResponseModel(sessionId: sessionId, url: '', token: '');

  @override
  Future<void> end(int sessionId) async {}
}

const _courses = [
  GoLiveCourse(id: 1, title: 'Artificial intelligence and machine learning for engineers', students: 1610),
  GoLiveCourse(id: 2, title: 'Networks lab', students: 380),
  GoLiveCourse(id: 3, title: 'Draft course', students: 0, published: false),
];

final _scheduled = GoLiveSuggestion(sessionId: 9, title: 'Lecture 7: neural networks and back propagation', startsAt: _now.add(const Duration(minutes: 12)), minutes: 90);
final _running = GoLiveSuggestion(sessionId: 9, title: 'Lecture 7', startsAt: _now.subtract(const Duration(minutes: 20)), minutes: 90, live: true);

Widget _view({
  List<GoLiveCourse> courses = _courses,
  bool loading = false,
  GoLiveSuggestion? suggestion,
  bool useSuggestion = true,
  String? error,
  bool busy = false,
  bool meetNow = true,
}) =>
    GoLiveSheetView(
      courses: courses,
      courseId: courses.isEmpty ? null : courses.first.id,
      onCourse: (_) {},
      title: TextEditingController(),
      titleHint: 'Live class · Thu 29 Oct · 12:00 PM',
      loadingSessions: loading,
      suggestion: suggestion,
      useSuggestion: useSuggestion,
      onUseSuggestion: (_) {},
      onRecord: (_) {},
      onCamera: (_) {},
      onMic: (_) {},
      error: error,
      busy: busy,
      now: _now,
      onGo: () {},
      onClose: () {},
      onMeetNow: meetNow ? () {} : null,
      onNewCourse: () {},
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('header pill: Go live · Return to live · busy · compact, beside a long name', (tester) async {
    for (final b in const [
      GoLiveButton(),
      GoLiveButton(live: true),
      GoLiveButton(busy: true),
      GoLiveButton(compact: true, live: true),
    ]) {
      await expectNoLayoutErrors(
        tester,
        () => Padding(
          padding: const EdgeInsets.all(20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // the home's header row (home_screen.dart): the context switcher and the pill share the line
            const Flexible(child: Text('Personal · A very long organization name that wraps', maxLines: 1, overflow: TextOverflow.ellipsis)),
            Flexible(child: Padding(padding: const EdgeInsetsDirectional.only(start: 12), child: b)),
          ]),
        ),
      );
    }
    // the tap target is 48 px tall whatever the pill
    await tester.pumpWidget(layoutHost(Center(child: GoLiveButton(onTap: () {}))));
    expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sheet: loading · scheduled · live (Rejoin, no Record) · new · error · busy', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(loading: true));
    await expectNoLayoutErrors(tester, () => _view(suggestion: _scheduled));
    AppConfig.lang = 'en';
    await expectNoLayoutErrors(tester, () => _view(suggestion: _running));
    await tester.pumpWidget(layoutHost(_view(suggestion: _running)));
    expect(find.text('Rejoin the live'), findsOneWidget);
    expect(find.text('Record this session'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await expectNoLayoutErrors(tester, () => _view(suggestion: _scheduled, useSuggestion: false));
    await expectNoLayoutErrors(tester, () => _view(error: 'The server could not start the session. Try again in a moment.'));
    await expectNoLayoutErrors(tester, () => _view(busy: true, meetNow: false));
  });

  testWidgets('sheet: the Record switch uses the app primary track, only its dot is red (M22)', (tester) async {
    await tester.pumpWidget(layoutHost(_view(suggestion: _scheduled)));
    final tile = tester.widget<AppSwitchTile>(find.widgetWithText(AppSwitchTile, 'Record this session'));
    expect(tile.activeColor, isNull, reason: 'no red track: AppSwitch falls back to the primary colour');
    final ctx = tester.element(find.byType(AppSwitchTile));
    expect(tile.iconColor, ctx.colors.danger);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sheet: one course · no course (add a course + Meet now)', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(courses: const [GoLiveCourse(id: 5, title: 'Only course')]));
    await expectNoLayoutErrors(tester, () => _view(courses: const []));
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(_view(courses: const [])));
    expect(find.text('No course yet'), findsOneWidget);
    expect(find.text('Go live now'), findsNothing);
    expect(find.text('Meet now, without a course'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  Future<Object?> openSheet(WidgetTester tester, GoLiveSheet sheet, Future<void> Function() act) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Object? result = 'none';
    await tester.pumpWidget(layoutHost(Builder(
      builder: (context) => Center(
        child: TextButton(onPressed: () async => result = await showGoLiveSheet(context, sheet), child: const Text('open')),
      ),
    ), scale: 1));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await act();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return result;
  }

  testWidgets('flow: a new session gets the default title and the Record switch; camera / mic carried', (tester) async {
    final api = FakeGoLiveApi(const []);
    final r = await openSheet(
      tester,
      GoLiveSheet(courses: _courses, initialCourseId: 2, api: api, now: _now, prefs: const GoLivePrefs(camera: false)),
      () async {
        expect(api.calls, ['sessions 2']);
        await tester.tap(find.text('Go live now'));
      },
    );
    expect(api.calls, ['sessions 2', 'create 2']);
    expect(api.createdTitle, ''); // no name: the server stores its neutral title (title_auto)
    expect((r as GoLiveLaunch).title, goLiveDefaultTitle(_now));
    expect(api.createdRecord, isTrue);
    expect(api.createdAt, _now);
    expect(r, isA<GoLiveLaunch>());
    final go = r;
    expect(go.sessionId, 77);
    expect(go.courseId, 2);
    expect(go.record, isTrue);
    expect(go.camera, isFalse);
    expect(go.mic, isTrue);
  });

  testWidgets('flow: the scheduled session is started as it is; turning Record on goes through the session', (tester) async {
    final api = FakeGoLiveApi([
      GoLiveSession(id: 9, name: 'Lecture 7', startsAt: _now.add(const Duration(minutes: 5)), minutes: 60, recordEnabled: false),
    ]);
    final r = await openSheet(tester, GoLiveSheet(courses: _courses, initialCourseId: 1, api: api, now: _now), () async {
      expect(find.text('Lecture 7'), findsOneWidget);
      await tester.tap(find.text('Record this session'));
      await tester.pump();
      await tester.tap(find.text('Go live now'));
    });
    expect(api.calls, ['sessions 1', 'record 9 true']);
    final go = r as GoLiveLaunch;
    expect(go.sessionId, 9);
    expect(go.title, 'Lecture 7');
    expect(go.record, isTrue);
  });

  testWidgets('flow: switching course loads its sessions once; a failed create stays in the sheet with the reason', (tester) async {
    final api = FakeGoLiveApi(const [], failCreate: true);
    final r = await openSheet(tester, GoLiveSheet(courses: _courses, initialCourseId: 1, api: api, now: _now), () async {
      await tester.tap(find.text('Networks lab'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Go live now'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(GoLiveSheetView), findsOneWidget);
    });
    expect(api.calls, ['sessions 1', 'sessions 2', 'create 2']);
    expect(r, 'none');
  });

  testWidgets('flow: Meet now closes the sheet with its marker', (tester) async {
    final r = await openSheet(tester, GoLiveSheet(courses: _courses, initialCourseId: 1, api: FakeGoLiveApi(const []), now: _now), () async {
      await tester.tap(find.text('Meet now, without a course'));
    });
    expect(r, GoLiveSheet.meetNow);
  });
}
