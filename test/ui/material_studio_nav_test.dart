// The Studio on a session material (D-315): opening it (from the card, from the player) and leaving it again.
// The bug: the material page AND the Studio inside it each had a PopScope that popped, so one Back closed the Studio
// and the course page under it (with a bool route popped with a List).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/records/material_studio_api.dart';
import 'package:flutter_education_app/features/records/material_studio_page.dart';
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/records/records_share_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _Api implements MaterialStudioApi {
  @override
  Future<MaterialStudioOpen?> open(int sessionId, int materialId) async => MaterialStudioOpen(
        source: RecordItem.fromJson({'id': materialId, 'title': 'Lecture 1', 'status': 'done', 'duration_seconds': 120})!,
      );
  @override
  Future<RecordPlay> playSource(int sessionId, int materialId) async => throw Exception('no player in tests');
  @override
  Future<RecordFrames> frames(int sessionId, int materialId, {int n = 0}) async => const RecordFrames(status: 'unavailable');
  @override
  Future<List<MaterialDraft>> sessionDrafts(int sessionId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Home → the course page (with "play" and "studio") → the player stand-in (with "Open in Studio").
Widget _app(_Api api, void Function(bool) done) => layoutHost(
      scaffold: false,
      scale: 1,
      Builder(
        builder: (home) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(home).push(MaterialPageRoute<void>(builder: (course) {
              final nav = Navigator.of(course);
              return Scaffold(
                body: Column(children: [
                  const Text('course page'),
                  TextButton(
                    onPressed: () async => done(await openMaterialStudio(course, sessionId: 1, materialId: 7, api: api)),
                    child: const Text('studio'),
                  ),
                  TextButton(
                    onPressed: () => nav.push(MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: TextButton(
                          onPressed: () async => done(await openMaterialStudio(null,
                              navigator: nav, replaceTop: true, sessionId: 1, materialId: 7, api: api)),
                          child: const Text('Open in Studio'),
                        ),
                      ),
                    )),
                    child: const Text('play'),
                  ),
                ]),
              );
            })),
            child: const Text('home'),
          ),
        ),
      ),
    );

/// A few frames (the Studio's skeleton shimmers forever: no pumpAndSettle).
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  Future<void> backToCoursePage(WidgetTester t) async {
    await t.binding.handlePopRoute(); // the system / app-bar Back
    await _settle(t);
    expect(find.byKey(const ValueKey('records.studio')), findsNothing);
    expect(find.text('course page'), findsOneWidget); // ONE route popped, not the course page too
    expect(t.takeException(), isNull);
  }

  testWidgets("the player's Open in Studio replaces the player by the Studio; Back returns to the course page", (t) async {
    bool? result;
    await t.pumpWidget(_app(_Api(), (v) => result = v));
    await t.tap(find.text('home'));
    await _settle(t);
    await t.tap(find.text('play'));
    await _settle(t);
    await t.tap(find.text('Open in Studio'));
    await _settle(t);
    expect(find.byKey(const ValueKey('records.studio')), findsOneWidget);
    expect(find.text('Open in Studio'), findsNothing); // the player is gone
    await backToCoursePage(t);
    expect(result, isFalse);
  });

  testWidgets("the card's Studio opens on top; Back pops it alone", (t) async {
    bool? result;
    await t.pumpWidget(_app(_Api(), (v) => result = v));
    await t.tap(find.text('home'));
    await _settle(t);
    await t.tap(find.text('studio'));
    await _settle(t);
    expect(find.byKey(const ValueKey('records.studio')), findsOneWidget);
    await backToCoursePage(t);
    expect(result, isFalse);
  });
}
