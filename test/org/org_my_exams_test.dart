// My exams (GET /org/public/me/exams) and the weekly-timetable pause during published exam windows: pure logic.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_my_exams.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> exam(int id, String startsAt, String endsAt, {String role = 'student', int course = 1, int? myRoom}) => {
      'id': id,
      'org_id': 7,
      'course_id': course,
      'course': {'id': course, 'name_ar': 'جبر', 'name_en': 'Algebra'},
      'kind': 'final',
      'role': role,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'rooms': [
        {'id': 1, 'name': 'Hall A'},
        {'id': 2, 'name': 'Hall B'},
      ],
      'invigilators': [
        {'id': 10, 'name': 'T1'},
      ],
      'my_room_id': ?myRoom,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('parse: naive UTC instants, sorted by start, names by language, invigilator room', () {
    final list = parseMyExams({
      'items': [
        exam(2, '2026-12-02T07:00:00', '2026-12-02T09:00:00', role: 'invigilator', myRoom: 2),
        exam(1, '2026-12-01T07:00:00', '2026-12-01T09:00:00'),
        {'id': 3, 'starts_at': null},
      ],
    });
    expect(list.map((e) => e.id), [1, 2]);
    expect(list.first.start, DateTime.utc(2026, 12, 1, 7));
    expect(list.first.start!.isUtc, isTrue);
    expect(list.first.courseName, 'Algebra');
    AppConfig.lang = 'ar';
    expect(list.first.courseName, 'جبر');
    expect(list[1].invigilating, isTrue);
    expect(list[1].myRoomName, 'Hall B');
    expect(list.first.roomNames, ['Hall A', 'Hall B']);
  });

  test('next exam: the running one, else the first ahead; null when all are over', () {
    final list = parseMyExams({
      'items': [
        exam(1, '2026-12-01T07:00:00', '2026-12-01T09:00:00'),
        exam(2, '2026-12-03T07:00:00', '2026-12-03T09:00:00'),
      ],
    });
    expect(nextExam(list, DateTime.utc(2026, 11, 30))?.id, 1);
    expect(nextExam(list, DateTime.utc(2026, 12, 1, 8))?.id, 1, reason: 'on now');
    expect(nextExam(list, DateTime.utc(2026, 12, 1, 9, 1))?.id, 2);
    expect(nextExam(list, DateTime.utc(2026, 12, 4)), isNull);
  });

  test('countdown: days / hours / minutes / seconds; running → zero', () {
    final e = parseMyExams({'items': [exam(1, '2026-12-03T07:00:00', '2026-12-03T09:00:00')]}).first;
    expect(examCountdown(e, DateTime.utc(2026, 12, 1, 4, 29, 50)), (false, 2, 2, 30, 10));
    expect(examCountdown(e, DateTime.utc(2026, 12, 3, 7, 30)), (true, 0, 0, 0, 0));
  });

  test('grouped by the wall-clock day of the zone (an exam after midnight local moves to the next day)', () {
    final list = parseMyExams({
      'items': [
        exam(1, '2026-12-01T21:30:00', '2026-12-01T23:00:00'),
        exam(2, '2026-12-01T07:00:00', '2026-12-01T09:00:00'),
        exam(3, '2026-12-02T07:00:00', '2026-12-02T09:00:00'),
      ],
    });
    DateTime plus3(DateTime u) => u.add(const Duration(hours: 3));
    final g = groupExamsByDay(list, plus3);
    expect([for (final (d, _) in g) d], [DateTime(2026, 12, 1), DateTime(2026, 12, 2)]);
    expect([for (final (_, xs) in g) xs.map((e) => e.id).toList()], [
      [2],
      [1, 3],
    ]);
    final utc = groupExamsByDay(list, (u) => u);
    expect(utc.first.$2.map((e) => e.id), [2, 1]);
  });

  test('weekly pause: inclusive window, active windows, text', () {
    final pauses = [
      {'exam_schedule_id': 2, 'start_date': '2026-12-20', 'end_date': '2026-12-31'},
      {'exam_schedule_id': 1, 'start_date': '2026-11-01', 'end_date': '2026-11-07'},
    ];
    expect(examPauseOn(DateTime(2026, 11, 1), pauses)?['exam_schedule_id'], 1);
    expect(examPauseOn(DateTime(2026, 11, 7), pauses)?['exam_schedule_id'], 1);
    expect(examPauseOn(DateTime(2026, 11, 8), pauses), isNull);
    expect(examPauseOn(DateTime(2026, 12, 31), pauses)?['exam_schedule_id'], 2);
    expect(activeExamPauses(pauses, DateTime(2026, 11, 3)).map((p) => p['exam_schedule_id']), [1, 2]);
    expect(activeExamPauses(pauses, DateTime(2026, 11, 8)).map((p) => p['exam_schedule_id']), [2]);
    expect(activeExamPauses(pauses, DateTime(2027, 1, 1)), isEmpty);
    expect(examPausesOf({'exam_pauses': pauses}), hasLength(2));
    expect(examPausesOf(null), isEmpty);
    expect(examPauseText(pauses[1]), startsWith('Classes paused for exams from '));
  });

  test('inbox exam items: a started exam is never "overdue"; countdown says when it starts', () {
    final now = DateTime.now();
    String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');
    InboxItem item(DateTime due) => InboxItem({'key': 'exam:1', 'kind': 'exam', 'segment': 'todo', 'title': 'x', 'due_at': iso(due)});
    expect(inboxUrgency(item(now.subtract(const Duration(minutes: 30))), now), 'normal');
    expect(inboxCountdown(item(now.subtract(const Duration(minutes: 30))), now), isNull);
    expect(inboxUrgency(item(now.add(const Duration(hours: 5))), now), 'due_soon');
    expect(inboxCountdown(item(now.add(const Duration(hours: 5))), now), isNotNull);
  });
}
