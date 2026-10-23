// Organizations v3 — what the screens show for a given server answer (no network: only initial renders).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_dynamic_form.dart';
import 'package:flutter_education_app/features/org/org_join_pages.dart';
import 'package:flutter_education_app/features/org/org_timetable_parts.dart';
import 'package:flutter_education_app/features/org/org_timetable_wizard.dart' show GenerationRunCard;
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Map<String, dynamic> unit({String method = 'auto', String? my, bool full = false, List<Map<String, dynamic>> fields = const []}) => {
      'unit_type': 'dept',
      'unit_id': 3,
      'kind': 'service',
      'name_ar': 'الإرشاد',
      'name_en': 'Advising',
      'my_status': my,
      'full': full,
      'policy': {'configured': true, 'method': method, 'code_required': method == 'code', 'needs_approval': method == 'approval', 'fields': fields},
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('student join screen', () {
    testWidgets('no code box and no approval wording for automatic joining', (tester) async {
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit())));
      expect(find.text('Join code'), findsNothing);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Send request'), findsNothing);
    });

    testWidgets('a code box only when the unit is joined by code', (tester) async {
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit(method: 'code'))));
      expect(find.text('Join code'), findsOneWidget);
    });

    testWidgets('approval units send a request', (tester) async {
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit(method: 'approval'))));
      expect(find.text('Send request'), findsOneWidget);
    });

    testWidgets('members and pending applicants can\'t submit again', (tester) async {
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit(my: 'member'))));
      expect(find.textContaining('already a member'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit(my: 'pending'))));
      expect(find.textContaining('being reviewed'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('a full unit says so and offers nothing', (tester) async {
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit(full: true))));
      expect(find.text('This unit is full.'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('the eligibility form comes from the policy; empty required fields are flagged before any request', (tester) async {
      await tester.pumpWidget(host(OrgUnitJoinScreen(orgId: 1, unit: unit(fields: [
        {'key': 'year', 'label': 'Your year', 'type': 'select', 'required': true, 'options': ['1', '2', '3', '4'], 'bind': 'academic_level'},
      ]))));
      expect(find.text('Your year *'), findsOneWidget);
      expect(find.text('Can I join?'), findsOneWidget);
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
    });
  });

  group('dynamic field', () {
    testWidgets('select options, optional hint and an error', (tester) async {
      final answers = OrgFormAnswers();
      await tester.pumpWidget(host(Column(children: [
        OrgDynamicField(field: const {'key': 'y', 'label': 'Year', 'type': 'select', 'required': true, 'options': ['First', 'Second']}, answers: answers, onChanged: () {}, error: 'Required'),
        OrgDynamicField(field: const {'key': 'n', 'label': 'Note', 'type': 'text', 'required': false}, answers: answers, onChanged: () {}),
      ])));
      expect(find.text('Year *'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);
      await tester.tap(find.text('Second'));
      expect(answers.values['y'], 'Second');
    });
  });

  group('generation & results', () {
    testWidgets('a running job can be cancelled; a finished one cannot', (tester) async {
      await tester.pumpWidget(host(GenerationRunCard(run: const {'status': 'running', 'progress': 40}, onCancel: () {})));
      expect(find.text('Generating'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpWidget(host(const GenerationRunCard(run: {'status': 'succeeded', 'result_status': 'partial'})));
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Partial — some sessions not placed'), findsOneWidget);
    });

    testWidgets('a partial result lists what is missing, why, and the suggestions', (tester) async {
      await tester.pumpWidget(host(SingleChildScrollView(
        child: ScheduleResultView(
          result: const {
            'status': 'partial',
            'unscheduled': [
              {'course_id': 1, 'kind': 'lab', 'missing': 2, 'reason': 'no_room_fits', 'blocking': {'rooms_busy': 3}}
            ],
            'relaxed': [],
            'suggestions': [
              {'reason': 'no_room_fits', 'sessions': 2, 'text': 'Add a lab with computers'}
            ],
            'stats': {'sessions_required': 10, 'sessions_placed': 8, 'soft_cost': 12.5},
          },
          courseNames: const {1: 'Databases'},
          people: const {},
        ),
      )));
      expect(find.text('Partial — some sessions not placed'), findsOneWidget);
      expect(find.textContaining('8 of 10 sessions'), findsOneWidget);
      expect(find.textContaining('Databases · lab — 2 missing'), findsOneWidget);
      expect(find.text('Add a lab with computers'), findsOneWidget);
    });

    testWidgets('relaxed preferences name the person (feasible_relaxed)', (tester) async {
      await tester.pumpWidget(host(SingleChildScrollView(
        child: ScheduleResultView(
          result: const {
            'status': 'feasible_relaxed',
            'unscheduled': [],
            'relaxed': [
              {'user_id': 7, 'avoided_cell_used': 1, 'experience_level': 2}
            ],
            'suggestions': [],
          },
          courseNames: const {},
          people: const {7: 'Dr. Salma'},
        ),
      )));
      expect(find.text('Complete — some preferences relaxed'), findsOneWidget);
      expect(find.text('Dr. Salma'), findsOneWidget);
      expect(find.textContaining('Recorded experience: 2'), findsOneWidget);
    });

    testWidgets('hard conflicts are listed before warnings', (tester) async {
      await tester.pumpWidget(host(const ConflictList(conflicts: [
        {'severity': 'warning', 'type': 'room_kind_mismatch', 'day': 'sunday', 'course_ids': []},
        {'severity': 'error', 'type': 'students_clash', 'day': 'monday', 'course_ids': [1, 2]},
      ], courseNames: {1: 'A', 2: 'B'})));
      final titles = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
      expect(titles.first, 'Students have overlapping required sessions');
      expect(titles.last, 'Room type differs from the requested one');
    });
  });
}
