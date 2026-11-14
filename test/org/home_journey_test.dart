// The student home's journey card (D-120, amended 2026-10-31 "personal context"): it shows in the personal context
// with the server's block — also for a student who is ALSO an organization member — and never in Organization mode,
// for an organization login, with the switch off, or without a clear interest (no block). Data: the REAL /me/home
// payload of ../back/tests/contract/dump_payloads.py (test/fixtures/payloads/me_home_student_journey.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/features/courses/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/home/student/home_journey.dart';
import 'package:flutter_education_app/features/home/student/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _home() => Map<String, dynamic>.from(
      (jsonDecode(File('test/fixtures/payloads/me_home_student_journey.json').readAsStringSync()) as Map)['payload'] as Map,
    );

const _member = {
  'items': [
    {
      'organization': {'id': 7, 'name_ar': 'جامعة', 'name_en': 'Uni', 'status': 'approved'},
      'role': 'member',
    },
  ],
};

/// What the home draws in the journey slot: the card, or nothing.
Widget _slot(Map<String, dynamic>? raw, {String role = 'student'}) {
  final j = homeJourney(raw, role: role);
  return j == null ? const SizedBox.shrink() : HomeJourneyCard(journey: j, onTap: () {});
}

void main() {
  late AppModeController mode;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    mode = AppModeController.instance;
    mode.debugSet(_member, mode: AppMode.individual, orgId: 7);
  });
  tearDown(() {
    AppConfig.disableList = [];
    mode.debugSet(const {}, mode: AppMode.individual);
  });

  test('the fixture is a real card (a block with its next step)', () {
    final raw = MeHome.fromJson(_home()).journey;
    expect(raw, isNotNull);
    expect(Journey.fromJson(raw), isNotNull);
  });

  testWidgets('personal context, a member of an organization, with data: the card shows on the home body', (t) async {
    expect(mode.available, isTrue, reason: 'the student IS an organization member');
    expect(mode.isOrg, isFalse);
    final home = MeHome.fromJson(_home());
    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: StudentHomeBody(data: StudentHomeData(home: home, now: DateTime.utc(2026, 10, 31, 9)), onTab: (_) {}, onOpenJourney: () {}),
    )));
    await t.pump();
    expect(find.byType(HomeJourneyCard), findsOneWidget);
    expect(homeJourney(home.journey), isNotNull);
    expect(roadmapOrgAccount('student'), isFalse, reason: 'membership alone no longer hides the roadmap');
  });

  testWidgets('Organization mode: no card', (t) async {
    final raw = MeHome.fromJson(_home()).journey;
    await t.pumpWidget(layoutHost(_slot(raw)));
    expect(find.byType(HomeJourneyCard), findsOneWidget);
    mode.debugSet(_member, mode: AppMode.organization, orgId: 7);
    expect(mode.isOrg, isTrue);
    await t.pumpWidget(layoutHost(_slot(raw)));
    expect(find.byType(HomeJourneyCard), findsNothing);
    expect(homeJourney(raw), isNull);
    expect(roadmapOrgAccount('student'), isTrue);
  });

  testWidgets('no clear interest yet (the server sends no block): no card — the one "no data" reason', (t) async {
    await t.pumpWidget(layoutHost(_slot(null)));
    expect(find.byType(HomeJourneyCard), findsNothing);
    // a block without a next step is no card either
    expect(homeJourney(const {'source': 'interest', 'next': <String, dynamic>{}}), isNull);
    final home = MeHome.fromJson({..._home()}..remove('journey'));
    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: StudentHomeBody(data: StudentHomeData(home: home, now: DateTime.utc(2026, 10, 31, 9)), onTab: (_) {}),
    )));
    await t.pump();
    expect(find.byType(HomeJourneyCard), findsNothing);
  });

  test('an organization login or a switch off: no card', () {
    final raw = MeHome.fromJson(_home()).journey;
    expect(homeJourney(raw, role: 'org-admin'), isNull);
    expect(homeJourney(raw, role: 'org-staff'), isNull);
    AppConfig.disableList = [kRoadmapJourneyKey];
    expect(homeJourney(raw), isNull);
    AppConfig.disableList = [kRoadmapKey];
    expect(homeJourney(raw), isNull);
    AppConfig.disableList = [];
    expect(homeJourney(raw), isNotNull);
  });

  // ── D-309 ──
  test('the home block carries the whole path, so the page needs no call', () {
    final j = Journey.fromJson(MeHome.fromJson(_home()).journey)!;
    expect(j.steps, isNotEmpty);
    expect(j.steps.where((s) => s.current).single.id, j.next.id);
    expect(journeyComplete(j), isTrue);
    expect(journeyComplete(Journey.fromJson({...MeHome.fromJson(_home()).journey!}..remove('steps'))), isFalse,
        reason: 'an older server: the page asks /me/journey');
  });

  testWidgets('the card: Continue opens the next course, the card opens the path', (t) async {
    final home = MeHome.fromJson(_home());
    int? opened;
    var path = 0;
    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: StudentHomeBody(
        data: StudentHomeData(home: home, now: DateTime.utc(2026, 10, 31, 9)),
        onTab: (_) {},
        onOpenCourse: (id) => opened = id,
        onOpenJourney: () => path++,
      ),
    )));
    await t.pump();
    // the phone home puts the shortcut grid above it (D-631): bring the card into view first
    await t.ensureVisible(find.byKey(const ValueKey('home_journey.continue')));
    await t.tap(find.byKey(const ValueKey('home_journey.continue')));
    expect(opened, homeJourney(home.journey)!.next.id);
    await t.tap(find.text(homeJourney(home.journey)!.title));
    expect(path, 1);
  });

  testWidgets('no journey + the hint from the server: the "pick your interests" invite', (t) async {
    final raw = {..._home(), 'journey': null, 'journey_hint': 'pick_interests'};
    final home = MeHome.fromJson(raw);
    expect(home.journeyHint, 'pick_interests');
    var picked = 0;
    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: StudentHomeBody(data: StudentHomeData(home: home, now: DateTime.utc(2026, 10, 31, 9)), onTab: (_) {}, onPickInterests: () => picked++),
    )));
    await t.pump();
    expect(find.byType(HomeJourneyInvite), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('home_journey.pick')));
    await t.tap(find.byKey(const ValueKey('home_journey.pick')));
    expect(picked, 1);
    // recommendations off, Organization mode, or no hint: nothing
    AppConfig.disableList = [kRoadmapRecsKey];
    expect(homeJourneyInvite(home.journeyHint), isFalse);
    AppConfig.disableList = [];
    expect(homeJourneyInvite(null), isFalse);
    expect(homeJourneyInvite('pick_interests', role: 'org-staff'), isFalse);
  });
}
