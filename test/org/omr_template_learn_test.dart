// The bubble-sheet learning flow and the library over the fake backend (D-155, Example 3), answered with REAL engine
// replies (test/fixtures/payloads/omr_templates/):
//   • super admin: upload a blank + a filled sample with the shading description → the learning job (followed by its
//     `job_updated {kind: omr_template}` event, no timer) → "Detected 4 corner marks, 2 answer columns" → step through
//     ("Question 1: … Correct?" → confirm; ← / → keys; jump to 17) → drag a bubble of question 17 → Save the fix (PUT
//     …/boxes in mm = the drag in pixels / zoom / ppm) → re-measured (event) → confirm the clear ones → save → published.
//   • teacher: their unfinished sheet types first, then a new upload → … → "Sent for approval".
//   • the library: approve a pending version, reject one with a reason, the approval switch, Edit → version n + 1.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_sheet_overlay.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_template_learn.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_template_library.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_templates.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _dir = 'test/fixtures/payloads/omr_templates';
Map<String, dynamic> _p(String name) =>
    Map<String, dynamic>.from((jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)['payload'] as Map);

/// The engine's API with the images left out (the fake answers JSON only; the screens draw a plain page then).
class _Api extends OmrTemplatesApi {
  @override
  Future<Uint8List?> image(int id, String kind) async => null;
}

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});
const _b = '/api/v1/exam/omr/templates';

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _frames(tester);
}

String _prompt(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('omr.prompt'))).data!;

Map<String, dynamic> _body(dynamic data) => Map<String, dynamic>.from(data as Map);

Future<void> _pump(WidgetTester tester, Widget page, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
  await _frames(tester);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  final png = File('$_dir/blank_preview.png').readAsBytesSync();
  var picks = 0;
  Future<(String, Uint8List)?> picker({required bool camera}) async => (picks++ == 0 ? 'blank.png' : 'filled.jpg', png);

  testWidgets('super admin: learn → step through → drag fix → save → published', (tester) async {
    picks = 0;
    var steps = _p('steps_queued');
    final puts = <Map<String, dynamic>>[];
    final confirms = <dynamic>[];
    FormData? learnForm;
    final fake = FakeApi({
      'POST $_b/learn': (o) {
        learnForm = o.data as FormData;
        return FakeResponse(202, _p('learn_super_202'));
      },
      'GET $_b/5/steps': (_) => steps,
      'POST $_b/5/confirm': (o) {
        final n = _body(o.data)['numbers'];
        confirms.add(n);
        return n is List && n.length == 1 ? _p('confirm_one') : _p('e2e_confirm_all');
      },
      'PUT $_b/5/boxes': (o) {
        puts.add(_body(o.data));
        steps = _p('boxes_recalibrating');
        return steps;
      },
      'POST $_b/5/validate': (_) => _p('validate_ok'),
      'POST $_b/5/submit': (_) => _p('submit_super_published'),
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);

    await _pump(tester, OmrTemplateLearnPage(isSuperAdmin: true, api: _Api(), pickFile: picker, liveStream: _stream, liveBus: LiveEvents.instance));

    // ── upload: nothing is sent until the description is complete ──
    await _tap(tester, 'omr.learn');
    expect(find.text('Give the sheet type a name'), findsOneWidget);
    expect(fake.calls.where((c) => c.method == 'POST'), isEmpty);
    await _type(tester, 'omr.name', 'Ministry sheet 50');
    await _tap(tester, 'omr.blank.pick');
    await _tap(tester, 'omr.filled.pick');
    await _type(tester, 'omr.questions', '50');
    await _type(tester, 'omr.options', '4');
    await _type(tester, 'omr.per_column', '25');
    await _tap(tester, 'omr.learn');
    expect(find.text('Enter the number of student ID columns (its digits)'), findsOneWidget);
    await _type(tester, 'omr.id_columns', '10');
    await _tap(tester, 'omr.learn');
    final form = learnForm!;
    expect({for (final f in form.fields) f.key: f.value}['name'], 'Ministry sheet 50');
    expect(jsonDecode({for (final f in form.fields) f.key: f.value}['hints']!),
        {'questions': 50, 'options': 4, 'per_column': 25, 'layout': 'columns', 'one_choice_per_question': true, 'id_kind': 'shaded', 'id_columns': 10});
    expect([for (final f in form.files) '${f.key}=${f.value.filename}'], ['blank=blank.png', 'filled=filled.jpg']);

    // ── learning: the event, not a timer ──
    expect(find.text('Reading your sheet…'), findsOneWidget);
    await _frames(tester, 20); // 2 s: below the poll interval while the stream is connected
    expect(fake.calls.where((c) => c.path == '$_b/5/steps'), isEmpty);
    steps = _p('steps_done_super');
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'omr_template', 'id': 99, 'status': 'done'}); // another template: ignored
    await _frames(tester);
    expect(fake.calls.where((c) => c.path == '$_b/5/steps'), isEmpty);
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'omr_template', 'id': 5, 'status': 'done'});
    await _frames(tester);
    expect(find.text('Detected 4 corner marks, 2 answer columns'), findsWidgets);

    // ── step through ──
    await _tap(tester, 'omr.check');
    final s = TemplateSteps.fromJson(steps);
    expect(_prompt(tester), 'Question 1: detected 4 bubbles, filled: ${s.question(1)!.filled.join(', ')}. Correct?');
    await _tap(tester, 'omr.step.primary');
    expect(confirms.single, [1]);
    expect(_prompt(tester), startsWith('Question 2: detected 4 bubbles'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _frames(tester);
    expect(_prompt(tester), startsWith('Question 3:'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _frames(tester);
    expect(_prompt(tester), startsWith('Question 2:'));
    await _tap(tester, 'omr.jump');
    await _tap(tester, 'omr.jump.16');
    expect(_prompt(tester), 'Question 17: detected 4 bubbles, filled: ${s.question(17)!.filled.join(', ')}. Correct?');

    // ── drag bubble A of question 17 by 60 px to the right ──
    await _tap(tester, 'omr.fix');
    await tester.pump(const Duration(seconds: 1)); // the zoom onto the question settles
    await _frames(tester, 3);
    final zoom = tester.state<SheetOverlayState>(find.byType(SheetOverlay)).scale;
    expect(zoom, greaterThan(1));
    await tester.drag(find.byKey(const ValueKey('omr.box.0')), const Offset(60, 0)); // past the pan slop (36 px) of touch
    await _frames(tester, 3);
    await _tap(tester, 'omr.edit.save');
    final put = puts.single;
    expect((put['kind'], put['n']), ('answers', 17));
    final sent = [for (final b in (put['bubbles'] as List).cast<Map>()) OmrBubble.fromJson(Map<String, dynamic>.from(b))];
    // the page holds the last reply (confirm → confirm_one, recorded after the e2e's own +0.4 mm fix of question 17)
    final before = TemplateSteps.fromJson(_p('confirm_one')).question(17)!.bubbles;
    expect(sent.map((b) => b.label), before.map((b) => b.label));
    expect(sent[0].cx - before[0].cx, closeTo(60 / zoom / 4, 0.0015)); // the server's mm, 3 decimals
    expect(sent[0].cy, closeTo(before[0].cy, 0.0006));
    for (var i = 1; i < 4; i++) {
      expect(sent[i].sameAs(before[i]) || (sent[i].cx - before[i].cx).abs() < 6e-4, isTrue);
    }
    expect(find.text('Re-measuring the corrected boxes…'), findsOneWidget);
    steps = _p('steps_after_fix');
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'omr_template', 'id': '5', 'status': 'done'});
    await _frames(tester);
    expect(find.text('Re-measuring the corrected boxes…'), findsNothing);

    // ── keyboard fix: → nudges 0.1 mm, Enter saves ──
    await _tap(tester, 'omr.fix');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _frames(tester);
    expect(puts.length, 2);
    final nudgedSel = (puts[1]['bubbles'] as List).cast<Map>();
    final after17 = TemplateSteps.fromJson(_p('steps_after_fix')).question(17)!;
    final moved = [for (var i = 0; i < 4; i++) ((nudgedSel[i]['cx'] as num) - after17.bubbles[i].cx).abs() > 0.05];
    expect(moved.where((m) => m).length, 1, reason: 'exactly the selected bubble moved by 0.1 mm');
    steps = _p('steps_after_fix');
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'omr_template', 'id': 5, 'status': 'done'});
    await _frames(tester);

    // ── confirm the clear ones, then save ──
    await _tap(tester, 'omr.confirm_clear');
    await tester.tap(find.text('Confirm').last);
    await _frames(tester);
    expect(confirms.last, isA<List>());
    expect((confirms.last as List).length, greaterThan(40));
    await _tap(tester, 'omr.jump');
    await _tap(tester, 'omr.jump.51');
    expect(_prompt(tester), startsWith('Model row: 4 bubbles'));
    await _tap(tester, 'omr.step.next');
    expect(find.text('The sheet is ready'), findsOneWidget);
    await _tap(tester, 'omr.submit');
    expect(find.byKey(const ValueKey('omr.done.published')), findsOneWidget);
    expect(find.text('Version 1 is published'), findsOneWidget);
    expect(fake.unmatched, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('teacher: unfinished types first, then a new upload → "Sent for approval"', (tester) async {
    picks = 0;
    var steps = _p('e2e_steps_done');
    final fake = FakeApi({
      'GET $_b': (_) => _p('library_teacher'),
      'POST $_b/learn': (_) => FakeResponse(202, _p('e2e_learn_202')),
      'GET $_b/5/steps': (_) => steps,
      'POST $_b/5/confirm': (_) => steps = _p('e2e_confirm_all'),
      'POST $_b/5/validate': (_) => _p('e2e_validate_ok'),
      'POST $_b/5/submit': (_) => _p('e2e_submit_pending'),
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);

    await _pump(tester, OmrTemplateLearnPage(api: _Api(), pickFile: picker, liveStream: _stream, liveBus: LiveEvents.instance));
    expect(find.text('Your bubble sheet types'), findsOneWidget);
    expect(find.byKey(const ValueKey('omr.mine.7')), findsOneWidget); // pending approval
    expect(find.byKey(const ValueKey('omr.mine.9')), findsOneWidget); // a draft
    expect(find.byKey(const ValueKey('omr.mine.1')), findsNothing); // the built-ins are not "yours"
    await _tap(tester, 'omr.start.new');
    await _type(tester, 'omr.name', 'School sheet 50');
    await _tap(tester, 'omr.blank.pick');
    await _type(tester, 'omr.questions', '50');
    await _type(tester, 'omr.options', '4');
    await _type(tester, 'omr.id_columns', '10');
    await _tap(tester, 'omr.learn');
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'omr_template', 'id': 5, 'status': 'done'});
    await _frames(tester);
    await _tap(tester, 'omr.check');
    expect(_prompt(tester), 'Question 1: detected 4 bubbles, filled: D. Correct?');
    await _tap(tester, 'omr.confirm_clear');
    await tester.tap(find.text('Confirm').last);
    await _frames(tester);
    await _tap(tester, 'omr.jump');
    await _tap(tester, 'omr.jump.50');
    expect(_prompt(tester), 'Detected 10 columns × 10 digits. Student ID read from the filled sheet: 2024001234. Correct?');
    await _tap(tester, 'omr.step.primary'); // ID ok → the model row
    await _tap(tester, 'omr.step.primary'); // model row ok → save
    expect(find.text('Save and submit'), findsOneWidget);
    await _tap(tester, 'omr.submit');
    expect(find.text('Sent for approval'), findsOneWidget);
    expect(find.byKey(const ValueKey('omr.done.pending_approval')), findsOneWidget);
    expect(fake.unmatched, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a sheet with no corner marks: the reasons with their fix, and Upload again', (tester) async {
    picks = 0;
    final fake = FakeApi({
      'POST $_b/learn': (_) => FakeResponse(202, _p('learn_super_202')),
      'GET $_b/5/steps': (_) => _p('steps_failed'),
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    await _pump(tester, OmrTemplateLearnPage(isSuperAdmin: true, api: _Api(), pickFile: picker, liveStream: _stream, liveBus: LiveEvents.instance));
    await _type(tester, 'omr.name', 'Photo of a page');
    await _tap(tester, 'omr.blank.pick');
    await _type(tester, 'omr.questions', '50');
    await _type(tester, 'omr.options', '4');
    await _type(tester, 'omr.id_columns', '10');
    await _tap(tester, 'omr.learn');
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'omr_template', 'id': 5, 'status': 'done'});
    await _frames(tester);
    expect(find.text('Corner marks not found: tl, tr, bl, br'), findsOneWidget);
    expect(find.textContaining('all four corner marks are fully visible'), findsOneWidget);
    expect(find.byKey(const ValueKey('omr.check')), findsNothing);
    await _tap(tester, 'omr.reupload');
    expect(find.text('Teach the platform your sheet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('library: approve, reject with a reason, the approval switch, Edit → version n + 1', (tester) async {
    final opened = <(int?, bool)>[];
    final bodies = <String, dynamic>{};
    final fake = FakeApi({
      'GET $_b': (_) => _p('library_super'),
      'POST $_b/7/publish': (_) => _p('e2e_publish'),
      'POST $_b/7/reject': (o) {
        bodies['reject'] = o.data;
        return _p('reject_ok');
      },
      'GET /api/v1/exam/admin/omr/settings': (_) => {'require_approval': true, 'smart_photos': true},
      'PUT /api/v1/exam/admin/omr/settings': (o) {
        final b = _body(o.data);
        bodies[b.containsKey('smart_photos') ? 'smart' : 'settings'] = o.data;
        return {'require_approval': b['require_approval'] ?? true, 'smart_photos': b['smart_photos'] ?? true};
      },
      'POST $_b/5/versions': (_) => FakeResponse(201, _p('versions_201')),
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    Future<bool?> open(BuildContext _, {int? templateId, bool readOnly = false}) async {
      opened.add((templateId, readOnly));
      return null;
    }

    await _pump(tester, OmrTemplateLibraryPage(api: _Api(), openTemplate: open), size: const Size(1440, 900));
    expect(find.text('Waiting for your approval'), findsOneWidget);
    expect(find.byKey(const ValueKey('omr.pending.approve.7')), findsOneWidget);
    await _tap(tester, 'omr.pending.approve.7');
    expect(fake.calls.where((c) => c.method == 'POST' && c.path == '$_b/7/publish').length, 1);

    await _tap(tester, 'omr.pending.reject.7');
    expect(find.byKey(const ValueKey('omr.reject.reason')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('omr.reject.send')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('omr.reject.reason')), findsOneWidget, reason: 'no reason: the button is off');
    await tester.enterText(find.byKey(const ValueKey('omr.reject.reason')), 'The corner marks are too close to the edge');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('omr.reject.send')));
    await _frames(tester);
    expect(_body(bodies['reject']), {'reason': 'The corner marks are too close to the edge'});

    await _tap(tester, 'omr.require_approval');
    expect(_body(bodies['settings']), {'require_approval': false});
    // D-163: the rollback switch sends only its own field (the server keeps the other)
    // the notices drawn from here on (the approval one above would sit over the next switch)
    appNoticeTopOverlay = () => tester.state<NavigatorState>(find.byType(Navigator).first).overlay;
    addTearDown(() => appNoticeTopOverlay = null);
    await _tap(tester, 'omr.smart_photos');
    expect(_body(bodies['smart']), {'smart_photos': false});
    // saved: said like the other settings (the switch alone used to move without a word)
    expect(find.text('Saved: smart processing of sheet photos is off — the previous reader is used'), findsOneWidget);

    // a published learned family: Edit makes version n + 1 and opens it
    await tester.tap(find.byKey(ValueKey('omr.family.${OmrTemplateRow.fromJson(_p('learn_super_202')).familyId}')));
    await _frames(tester);
    expect(find.textContaining('Editing creates version 3'), findsOneWidget);
    await _tap(tester, 'omr.version.edit.5');
    expect(fake.calls.where((c) => c.path == '$_b/5/versions').length, 1);
    expect(opened.last, (6, false));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10)); // the notices' own timers
  });
}
