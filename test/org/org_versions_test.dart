// Timetable versions — relaxation priority, ranking, diffs, member copies, copy freshness and CSV export.
import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_optimizer.dart';
import 'package:flutter_education_app/features/org/org_schedule_versions.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> slot(int id, int course, String day, int period, {int? room, int? teacher, int? asst, String kind = 'lecture', int group = 1}) =>
    {'id': id, 'course_id': course, 'day': day, 'period_id': period, 'room_id': room, 'teacher_id': teacher, 'assistant_id': asst, 'kind': kind, 'group_no': group};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('relaxation priority', () {
    test('default order relaxes students first and teachers last; unknown tiers are ignored', () {
      final p = RelaxationPolicy.fromSettings({'relaxation_priority': ['rooms', 'bogus']});
      expect(p.order.first, 'rooms');
      expect(p.order, hasLength(relaxTiers.length));
      expect(RelaxationPolicy.standard.order.last, 'teacher_prefs');
      expect(RelaxationPolicy.standard.protectedFirst.first, 'teacher_prefs');
      expect(RelaxationPolicy.standard.move('teacher_prefs', -1).order.last, 'other_soft');
    });

    test('a version with fewer unplaced sessions never wins by relaxing a more protected tier first', () {
      const teacherRelaxed = VersionMetrics(sessions: 10, hardConflicts: 0, relaxBy: {'teacher_prefs': 12});
      const assistantRelaxed = VersionMetrics(sessions: 10, hardConflicts: 0, relaxBy: {'assistant_prefs': 80});
      expect(rankVersions([teacherRelaxed, assistantRelaxed], RelaxationPolicy.standard), [1, 0]);
      // hard conflicts / unplaced come before any relaxation
      const conflicted = VersionMetrics(sessions: 10, hardConflicts: 2);
      const unknown = VersionMetrics(sessions: 10); // never validated: not reported feasible
      expect(unknown.feasible, isFalse);
      expect(rankVersions([conflicted, teacherRelaxed, unknown], RelaxationPolicy.standard).first, 1);
      // ties are broken by fewer changes
      expect(rankVersions([assistantRelaxed, assistantRelaxed], RelaxationPolicy.standard, changes: [5, 1]), [1, 0]);
    });

    test('metrics read unplaced by kind, relaxation by role, room use and staff load', () {
      final m = VersionMetrics.of(
        slots: [slot(1, 7, 'sunday', 1, room: 1, teacher: 10), slot(2, 7, 'monday', 1, room: 1, teacher: 10, asst: 20)],
        summary: {
          'unscheduled': [
            {'kind': 'lab', 'missing': 2},
            {'kind': 'lecture', 'missing': 1}
          ],
          'relaxed': [
            {'user_id': 10, 'avoided_cell_used': 1},
            {'user_id': 20, 'outside_preferred': 1}
          ],
          'stats': {'soft_cost': 52.0},
        },
        conflicts: const [],
        roleOf: {10: 'teacher', 20: 'teacher_assistant'},
        roomCount: 1,
        days: ['sunday', 'monday'],
        periodIds: [1, 2],
      );
      expect([m.unplacedLectures, m.unplacedLabs, m.hardConflicts], [1, 2, 0]);
      expect(m.relaxBy, {'teacher_prefs': relaxWeightAvoid, 'assistant_prefs': relaxWeightNotPreferred});
      expect(m.roomUse, 0.5);
      expect(m.load, {10: 2, 20: 1});
      expect(m.feasible, isFalse);
    });
  });

  group('diff', () {
    test('matches sessions by course · kind · group and reports time, room, staff and day changes', () {
      final a = [slot(1, 7, 'sunday', 1, room: 1, teacher: 10), slot(2, 8, 'sunday', 2, room: 2, teacher: 11)];
      final b = [slot(9, 7, 'thursday', 1, room: 1, teacher: 10), slot(8, 8, 'sunday', 2, room: 3, teacher: 12), slot(7, 8, 'monday', 1, kind: 'lab')];
      final d = diffVersions(a, b);
      expect(d.timeChanged.single.$2['id'], 9);
      expect(d.roomChanged.single.$2['id'], 8);
      expect(d.staffChanged.single.$2['id'], 8);
      expect(d.added.single['kind'], 'lab');
      expect(d.removed, isEmpty);
      expect(d.daysAdded, containsAll(['thursday', 'monday']));
      expect(d.total, 3);
      expect(diffVersions(a, [...a.reversed]).isEmpty, isTrue);
    });

    test('identical sessions give the same fingerprint whatever their ids or order', () {
      final a = [slot(1, 7, 'sunday', 1, room: 1), slot(2, 8, 'monday', 2)];
      final b = [slot(20, 8, 'monday', 2), slot(10, 7, 'sunday', 1, room: 1)];
      expect(versionFingerprint(a), versionFingerprint(b));
      expect(versionFingerprint(a) == versionFingerprint([slot(1, 7, 'sunday', 2, room: 1), slot(2, 8, 'monday', 2)]), isFalse);
    });
  });

  group('member copies', () {
    final all = [
      slot(1, 7, 'monday', 2, room: 1, teacher: 10),
      slot(2, 7, 'sunday', 1, room: 1, teacher: 10, asst: 20),
      slot(3, 7, 'sunday', 3, room: 2, asst: 20, kind: 'lab', group: 2),
      slot(4, 8, 'tuesday', 1, room: 2, teacher: 11),
    ];

    test('each member gets exactly their own sessions, in week order', () {
      expect(memberTimetable(all, const TimetableMember('teacher', 10)).map((s) => s['id']), [2, 1]);
      expect(memberTimetable(all, const TimetableMember('assistant', 20)).map((s) => s['id']), [2, 3]);
      expect(memberTimetable(all, const TimetableMember('group', 7, groupNo: 2, sessionKind: 'lab')).map((s) => s['id']), [3]);
      expect(memberTimetable(all, const TimetableMember('room', 2)).map((s) => s['id']), [3, 4]);
      expect(memberTimetable(all, const TimetableMember('teacher', 99)), isEmpty);
    });

    test('the member list covers everyone once, and every session belongs to some member', () {
      final ms = timetableMembers(all);
      expect(ms.where((m) => m.kind == 'teacher').map((m) => m.id).toSet(), {10, 11});
      expect(ms.toSet().length, ms.length);
      for (final s in all) {
        expect(ms.where((m) => m.kind == 'group').any((m) => m.has(s)), isTrue);
      }
    });

    test('a copy records its source version; it is outdated once the live version moves on', () {
      final cp = TimetableCopy.fromJson({
        'id': 5,
        'label': 'Final',
        'source': 'manual',
        'summary': {'version': 12},
        'items': all,
      });
      expect(cp.version, 12);
      expect(cp.outdated(liveVersion: 12, liveSlots: const []), isFalse);
      expect(cp.outdated(liveVersion: 13, liveSlots: all), isTrue);
      // no version recorded: the sessions decide, and unknown stays unknown
      final old = TimetableCopy.fromJson({'id': 6, 'items': all});
      expect(old.outdated(liveVersion: 13, liveSlots: all), isFalse);
      expect(old.outdated(liveVersion: 13, liveSlots: all.take(2).toList()), isTrue);
      expect(old.outdated(liveVersion: 13, liveSlots: all, detailLoaded: false), isNull);
    });
  });

  group('export', () {
    test('CSV has a BOM, the source header, one row per session and neutralised formulas', () {
      final bytes = timetableCsv(
        [slot(1, 7, 'sunday', 1, room: 1, teacher: 10)],
        const TimetableNames(courses: {7: '=HYPERLINK("x")'}, people: {10: 'Dr, A'}, rooms: {1: 'Hall 1'}, periods: {
          1: {'label': 'P1', 'start_time': '08:00', 'end_time': '09:00'}
        }),
        header: ['Copy #5 · version 12'],
      );
      final csv = utf8.decode(bytes); // the decoder drops the BOM
      final lines = csv.replaceFirst('﻿', '').trim().split('\n');
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(lines.first, '# Copy #5 · version 12');
      expect(lines, hasLength(3));
      expect(lines.last, contains('Sunday,P1,08:00,09:00'));
      expect(lines.last, contains('"\'=HYPERLINK(""x"")"'));
      expect(lines.last, contains('"Dr, A"'));
    });
  });

  group('server suggestion contract', () {
    test('violations sent as rule names are kept; a configuration change carries its run', () {
      final s = ScheduleSuggestion.fromJson({
        'suggestion_id': '4',
        'type': 'add_period',
        'validation': {'valid': false, 'hard_constraint_violations': ['room_double_booked']},
        'config': {
          'periods': {
            'add': [
              {'label': 'P7', 'start_time': '15:00', 'end_time': '16:00'}
            ]
          }
        },
        'impact': {'soft_cost_before': 10, 'soft_cost_after': 14},
      });
      expect(s.violations.single['type'], 'room_double_booked');
      expect(s.expandsConfig, isTrue);
      expect(suggestionTradeOff(s), allOf(contains('Breaks a hard rule'), contains('relaxes soft preferences (cost +4.0)')));
    });
  });
}
