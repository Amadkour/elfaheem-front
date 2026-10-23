// Timetable health, suggestions and horizon — the pure dashboard numbers, the models and the development mock.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_schedule_optimizer.dart';
import 'package:flutter_education_app/features/org/org_schedule_planning.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher apiCode(String code) => throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('health', () {
    final conflicts = [
      {'severity': 'error', 'type': 'teacher_double_booked', 'text_en': 'The teacher already teaches then'},
      {'severity': 'error', 'type': 'teacher_double_booked', 'text_en': 'The teacher already teaches then'},
      {'severity': 'error', 'type': 'room_too_small', 'text_en': 'The location is too small'},
      {'severity': 'warning', 'type': 'teacher_overloaded'},
      {'severity': 'soft', 'type': 'preference_avoided'},
    ];
    final result = {
      'status': 'partial',
      'unscheduled': [
        {'course_id': 1, 'kind': 'lecture', 'missing': 2},
        {'course_id': 2, 'kind': 'lab', 'missing': 1},
      ],
      'stats': {'sessions_required': 20, 'sessions_placed': 17, 'soft_cost': 4.5},
      'suggestions': [
        {'reason': 'rooms_busy', 'sessions': 3, 'text': 'every fitting room is taken'}
      ],
    };

    test('counts conflicts by severity and unplaced sessions by kind, from the server data only', () {
      final h = ScheduleHealth.from(conflicts: conflicts, result: result);
      expect([h.hard, h.warnings, h.soft, h.remaining], [3, 1, 1, 4]);
      expect([h.unscheduledLectures, h.unscheduledLabs], [2, 1]);
      expect(h.byType['teacher_double_booked'], 2);
      expect(h.byType.containsKey('preference_avoided'), isFalse);
      expect(h.placementRate, closeTo(0.85, 1e-9));
      expect(h.softCost, 4.5);
      expect(h.valid, isFalse);
      expect(h.requiredChanges, containsAll(['The teacher already teaches then × 2', 'every fitting room is taken (3)']));
    });

    test('resolved counts only what applied suggestions reported; unknown stays unknown', () {
      expect(ScheduleHealth.from(conflicts: conflicts, result: result).resolvedByApplied, isNull);
      final h = ScheduleHealth.from(conflicts: conflicts, result: result, suggestions: const [
        ScheduleSuggestion(id: 'a', type: 'reschedule_session', status: 'applied', impact: SuggestionImpact(resolved: 2)),
        ScheduleSuggestion(id: 'b', type: 'reschedule_session', status: 'pending', impact: SuggestionImpact(resolved: 5)),
        ScheduleSuggestion(id: 'c', type: 'add_day', status: 'rejected'),
      ]);
      expect(h.resolvedByApplied, 2);
      expect(h.total, 6);
      expect([h.suggestions['pending'], h.suggestions['applied'], h.suggestions['rejected']], [1, 1, 1]);
    });

    test('no generation report means no quality figures, never a guess', () {
      final h = ScheduleHealth.from(conflicts: const [], result: const {});
      expect(h.placementRate, isNull);
      expect(h.softCost, isNull);
      expect(h.resultStatus, isNull);
      expect(h.valid, isTrue);
    });
  });

  group('models', () {
    test('a suggestion reads the contract, including validation, permission and undo revision', () {
      final s = ScheduleSuggestion.fromJson({
        'suggestion_id': 'sg-1',
        'schedule_id': 42,
        'status': 'applied',
        'type': 'reschedule_session',
        'title_en': 'Move the lab',
        'title_ar': 'نقل السكشن',
        'reason_en': 'The assistant is busy',
        'base_version': 7,
        'changes': [
          {'op': 'move', 'slot_id': 501, 'before': {'day': 'sunday', 'period_id': 3}, 'after': {'day': 'monday', 'period_id': 4}}
        ],
        'impact': {'resolved_conflicts': 1, 'introduced_conflicts': 0, 'remaining_conflicts': 2},
        'validation': {'valid': false, 'hard_constraint_violations': [{'type': 'room_double_booked'}]},
        'requires': {'permission': 'schedule.approve', 'approval': true},
        'result': {'revision_before_id': 90},
      });
      expect([s.id, s.title, s.reason, s.baseVersion], ['sg-1', 'Move the lab', 'The assistant is busy', 7]);
      expect(s.changes.single.after['period_id'], 4);
      expect([s.impact.resolved, s.impact.introduced, s.impact.remaining], [1, 0, 2]);
      expect(s.valid, isFalse);
      expect(s.violations, hasLength(1));
      expect(s.needsApproval, isTrue);
      expect(s.revisionBeforeId, 90);
      expect(s.isStale(7), isFalse);
      expect(s.isStale(8), isTrue);
    });

    test('no explanation or validation from the server stays empty / unknown', () {
      final s = ScheduleSuggestion.fromJson({'id': 'x', 'type': 'add_day', 'status': 'weird'});
      expect(s.reason, isEmpty);
      expect(s.valid, isNull);
      expect(s.status, 'pending');
      expect(s.applicable, isTrue);
      expect(ScheduleSuggestion.fromJson({'id': 'y', 'type': 'add_room', 'applicable': false}).applicable, isFalse);
    });

    test('horizon defaults to flexible and checks days and periods against its limits', () {
      final h = ScheduleHorizon.fromSettings(const {});
      expect(h.mode, 'flexible');
      expect(h.check(5, 6), isNull);
      final strict = ScheduleHorizon.fromSettings({
        'horizon': {'mode': 'forced', 'min_days': 4, 'max_days': 5, 'max_periods_per_day': 6, 'allow_expansion': false}
      });
      expect(strict.mode, 'forced');
      expect(strict.allowExpansion, isFalse);
      expect(strict.check(3, 5), isNotNull);
      expect(strict.check(5, 7), isNotNull);
      expect(strict.check(5, 6), isNull);
      expect(ScheduleHorizon.fromSettings({'horizon': strict.toJson()}).toJson(), strict.toJson());
    });
  });

  group('mock workflow', () {
    var version = 3;
    late MockSuggestionApi api;
    setUp(() {
      version = 3;
      api = MockSuggestionApi((_) => SuggestionContext(
            version: version,
            conflicts: const [
              {'severity': 'error', 'type': 'room_double_booked', 'removable_slot_ids': [11]},
              {'severity': 'error', 'type': 'teacher_double_booked', 'removable_slot_ids': [12]},
            ],
            slots: const [
              {'id': 11, 'course_id': 1, 'day': 'sunday', 'period_id': 1},
              {'id': 12, 'course_id': 2, 'day': 'sunday', 'period_id': 1},
            ],
            days: const ['sunday', 'monday'],
            periodIds: const [1, 2],
            unscheduled: 2,
          ));
    });

    test('suggestions are built from the real conflicts, each to a different free cell, and are marked mock', () async {
      final r = await api.generate(1, version: 3);
      expect(r.mock, isTrue);
      final moves = r.items.where((s) => s.type == 'reschedule_session').toList();
      expect(moves, hasLength(2));
      expect(moves.map((s) => '${s.changes.single.after}').toSet(), hasLength(2));
      expect(r.items.map((s) => s.type), containsAll(['add_day', 'add_period']));
      expect(r.items.firstWhere((s) => s.type == 'add_day').needsApproval, isTrue);
    });

    test('accept applies once; a second accept is refused as a duplicate', () async {
      final s = (await api.generate(1, version: 3)).items.first;
      expect((await api.accept(1, s.id, version: 3)).items.single.status, 'applied');
      expect(() => api.accept(1, s.id, version: 3), apiCode('suggestion_already_applied'));
    });

    test('a stale timetable version is refused instead of applied', () async {
      final s = (await api.generate(1, version: 3)).items.first;
      version = 4; // someone else edited the timetable
      expect(() => api.accept(1, s.id, version: 3), apiCode('stale_version'));
      expect(() => api.accept(1, s.id, version: 4), apiCode('suggestion_stale'));
      expect(() => api.generate(1, version: 3), apiCode('stale_version'));
    });

    test('a rejected suggestion keeps its reason and is not proposed again until the timetable changes', () async {
      final s = (await api.generate(1, version: 3)).items.firstWhere((s) => s.type == 'add_period');
      final r = await api.reject(1, s.id, reason: 'no budget');
      expect([r.status, r.decisionReason], ['rejected', 'no budget']);
      expect(() => api.reject(1, s.id), apiCode('suggestion_not_pending'));
      final again = await api.generate(1, version: 3);
      expect(again.items.where((x) => x.type == 'add_period' && x.status == 'pending'), isEmpty);
      version = 4;
      final changed = await api.generate(1, version: 4);
      expect(changed.items.where((x) => x.type == 'add_period' && x.status == 'pending'), hasLength(1));
    });

    test('batch apply is all or nothing', () async {
      final items = (await api.generate(1, version: 3)).items.where((s) => s.type == 'reschedule_session').toList();
      await api.accept(1, items.first.id, version: 3);
      expect(() => api.applyBatch(1, [items.last.id, items.first.id], version: 3), apiCode('suggestion_already_applied'));
      expect((await api.list(1)).items.firstWhere((s) => s.id == items.last.id).status, 'pending');
      expect((await api.applyBatch(1, [items.last.id], version: 3)).items.single.status, 'applied');
    });

    test('mocks are compiled out unless explicitly requested', () => expect(kOrgSchedulingMocks, isFalse));
  });
}
