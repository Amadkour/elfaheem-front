// The unified student file's pure parts (lib/features/org/students/student_file_models.dart, D-1400 phase 1).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_roadmap.dart';
import 'package:flutter_education_app/features/org/students/student_file_models.dart';
import 'package:flutter_education_app/features/org/students/students_models.dart' show enrolLabel;
import 'package:flutter_test/flutter_test.dart';

/// The §4.2 example payload (a full right set unless [can] replaces it).
Map<String, dynamic> sampleFileJson({Map<String, dynamic>? can, String name = 'أحمد محمد علي', String nameEn = 'Ahmed Mohamed Ali'}) => {
      'student': {
        'user': {'id': 812, 'name': name, 'name_en': nameEn, 'image_url': null, 'username': 'ahmed.m'},
        'member_id': 5531,
        'member_status': 'active',
        'student_code': '20261234',
        'program': {'id': 7, 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer Science'},
        'level': '2',
        'cohort': 'current',
        'type_key': 'student_new',
        'nid_last4': '4821',
        'enrol_status': 'enrolled',
        'enrol_until': null,
        'acad_standing': 'carrying',
        'flags': ['transferred_in', 'struggling'],
        'intake': {'case_id': 3310, 'status': 'active', 'label': 'missing', 'conditional': true, 'due_at': '2026-12-15T00:00:00'},
        'missing_count': 3,
        'chip': {'dimension': 'intake', 'value': 'missing'},
        'email': 'a@example.com',
        'phone': '+201000000000',
        'joined_at': '2026-09-20T08:00:00',
        'birth_date': '2008-03-11',
        'gender': 'm',
        'nationality': 'EG',
      },
      'academic': {
        'stage': 'program', 'cgpa': 2.41, 'earned_credits': 36.0, 'attempted_credits': 42.0, 'legacy_standing': 'good',
        'probations': 1, 'study_system': 'credit_hours', 'advisor': {'id': 90, 'name': 'د. سارة'}, 'graduated_at': null,
      },
      'intake': {
        'case_id': 3310, 'type_key': 'student_new', 'type_label_ar': 'طالب مستجد', 'type_label_en': 'New student',
        'status': 'active', 'label': 'missing', 'conditional': true, 'due_at': '2026-12-15T00:00:00', 'missing_count': 3,
        'activated_at': '2026-09-20T08:00:00',
      },
      'journey': [
        {'key': 'applied', 'label_ar': 'تقديم الملف', 'label_en': 'Applied', 'state': 'done', 'at': '2026-09-01T10:00:00'},
        {'key': 'accepted', 'label_ar': 'القبول', 'label_en': 'Accepted', 'state': 'done', 'at': '2026-09-20T08:00:00'},
        {'key': 'level:1', 'label_ar': 'الفرقة الأولى', 'label_en': 'Year 1', 'state': 'done', 'at': null},
        {'key': 'level:2', 'label_ar': 'الفرقة الثانية', 'label_en': 'Year 2', 'state': 'current', 'at': '2027-07-01T00:00:00'},
        {'key': 'graduated', 'label_ar': 'التخرج', 'label_en': 'Graduation', 'state': 'todo', 'at': null},
      ],
      'open': {'asks': 1, 'requests': 2, 'complaints': 1, 'next_meeting': {'id': 4, 'starts_at': '2026-11-25T09:00:00', 'mode': 'online', 'title': 'Advising meeting'}},
      'can': can ??
          {
            'academic': true, 'documents': true, 'case': true, 'requests': true, 'complaints': true, 'advising': true,
            'access_log': true, 'status_view': true, 'status_change': false, 'ask': false, 'meeting': false,
          },
      'logged': true,
    };

/// One item of every timeline kind, newest first, across two academic years and several days.
List<TimelineItem> sampleTimeline() {
  final at = [
    '2026-11-20T10:00:00', '2026-11-20T08:00:00', '2026-11-02T09:00:00', '2026-10-02T09:14:00', '2026-09-20T08:00:00',
    '2026-09-01T10:00:00', '2026-08-30T10:00:00', '2026-06-30T00:00:00', '2026-02-01T00:00:00', '2025-10-01T00:00:00',
    '2025-09-15T00:00:00',
  ];
  return [
    for (final (i, k) in kTimelineKinds.indexed)
      TimelineItem.fromJson({
        'id': '$k:$i',
        'kind': k,
        'at': at[i],
        'actor': i.isEven ? {'id': 44, 'name': 'منى السيد'} : null,
        'title_ar': 'حدث من نوع $k بعنوان طويل جداً حتى يلتف السطر على الشاشات الصغيرة',
        'title_en': 'An event of kind $k with a rather long title so the line wraps on small screens',
        'detail_ar': i % 3 == 0 ? 'تفاصيل إضافية' : null,
        'detail_en': i % 3 == 0 ? 'More detail' : null,
        'reason': k == 'status' ? 'illness' : null,
        'decision_no': k == 'status' ? '2026/114' : null,
        'source': {'type': 'case', 'id': 3310},
        'can_undo': false,
        'undone': k == 'record',
      }),
  ];
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('StudentFile', () {
    test('parses the §4.2 payload', () {
      final f = StudentFile.fromJson(sampleFileJson());
      expect(f.userId, 812);
      expect(f.row.memberId, 5531);
      expect(f.row.chip.dimension, 'intake');
      expect(f.row.chip.value, 'missing');
      expect(f.row.missingCount, 3);
      expect(f.hasMissing, isTrue);
      expect(f.displayName, 'Ahmed Mohamed Ali');
      expect(f.otherName, 'أحمد محمد علي');
      expect(f.programLine, 'Computer Science · Level 2');
      expect(f.email, 'a@example.com');
      expect(f.birthDate, DateTime(2008, 3, 11));
      expect(f.academic!.cgpa, 2.41);
      expect(f.academic!.advisorName, 'د. سارة');
      expect(f.intake!.caseId, 3310);
      expect(f.intake!.typeLabel, 'New student');
      expect(f.journey.length, 5);
      expect(f.journey[3].state, AppRoadmapState.current);
      expect(f.open.complaints, 1);
      expect(f.open.nextMeeting!.id, 4);
      expect(f.can.kase, isTrue);
      expect(f.can.statusChange, isFalse);
      expect(f.logged, isTrue);
      AppConfig.lang = 'ar';
      expect(f.displayName, 'أحمد محمد علي');
      expect(f.otherName, 'Ahmed Mohamed Ali');
      expect(f.programLine, 'علوم الحاسب · المستوى 2');
    });

    test('a thin payload: sensitive values null, complaints hidden, no case', () {
      final j = sampleFileJson(can: {'academic': false});
      final s = j['student'] as Map<String, dynamic>;
      for (final k in ['email', 'phone', 'birth_date', 'nationality', 'intake', 'missing_count', 'program', 'level']) {
        s[k] = null;
      }
      j['intake'] = null;
      j['academic'] = null;
      j['open'] = {'asks': 0, 'requests': 0, 'complaints': null, 'next_meeting': null};
      final f = StudentFile.fromJson(j);
      expect(f.email, isNull);
      expect(f.intake, isNull);
      expect(f.academic, isNull);
      expect(f.open.complaints, isNull);
      expect(f.open.nextMeeting, isNull);
      expect(f.programLine, isNull);
      expect(f.hasMissing, isFalse);
    });

    test('the journey: unknown state reads as to do; a node becomes a roadmap node', () {
      expect(journeyState('warn'), AppRoadmapState.warn);
      expect(journeyState('nope'), AppRoadmapState.todo);
      final n = JourneyNode.fromJson({'key': 'graduated', 'label_ar': 'التخرج', 'label_en': 'Graduation', 'state': 'todo'});
      final r = n.toRoadmapNode();
      expect(r.title, 'Graduation');
      expect(r.id, 'graduated');
      expect(r.caption, isNull);
    });
  });

  test('the nationality reads its name in the app language, else the code', () {
    final j = sampleFileJson();
    final s = Map<String, dynamic>.from(j['student'] as Map)
      ..['nationality'] = 'EG'
      ..['nationality_label_ar'] = 'مصر'
      ..['nationality_label_en'] = 'Egypt';
    AppConfig.lang = 'ar';
    expect(StudentFile.fromJson({...j, 'student': s}).nationalityText, 'مصر');
    AppConfig.lang = 'en';
    expect(StudentFile.fromJson({...j, 'student': s}).nationalityText, 'Egypt');
    s.remove('nationality_label_ar');
    s.remove('nationality_label_en');
    expect(StudentFile.fromJson({...j, 'student': s}).nationalityText, 'EG');
  });

  group('journey by enrolment', () {
    List<JourneyNode> nodes() => [
          for (final e in const [('applied', 'done'), ('year1', 'current'), ('graduated', 'todo')])
            JourneyNode.fromJson({'key': e.$1, 'label_ar': e.$1, 'label_en': e.$1, 'state': e.$2}),
        ];

    test('enrolled: the rail picks its own next stop', () {
      final j = studentJourney(nodes(), 'enrolled');
      expect(j.next, isNull);
      expect(j.nodes[1].state, AppRoadmapState.current);
    });

    test('a student who left: no "in progress", no next, the stop reads the final state', () {
      final j = studentJourney(nodes(), 'withdrawn');
      expect(j.next, -1);
      expect(j.nodes.where((n) => n.state == AppRoadmapState.current), isEmpty);
      expect(j.nodes[1].state, AppRoadmapState.warn);
      expect(j.nodes[1].caption, enrolLabel('withdrawn'));
    });

    test('a graduate: the stop is done', () {
      final j = studentJourney(nodes(), 'graduated');
      expect(j.next, -1);
      expect(j.nodes[1].state, AppRoadmapState.done);
    });

    test('paused: the stop stays, reads the pause, no next', () {
      final j = studentJourney(nodes(), 'suspended');
      expect(j.next, -1);
      expect(j.nodes[1].state, AppRoadmapState.current);
      expect(j.nodes[1].caption, enrolLabel('suspended'));
    });
  });

  group('tabs', () {
    test('every right on: every tab, in order', () {
      final f = StudentFile.fromJson(sampleFileJson());
      expect(studentFileTabs(f.can), StudentFileTab.values);
    });

    test('no extra right: overview and timeline only', () {
      expect(studentFileTabs(const StudentCan()), [StudentFileTab.overview, StudentFileTab.timeline]);
    });

    test('each right shows its tab', () {
      expect(studentFileTabs(const StudentCan(documents: true)), contains(StudentFileTab.documents));
      expect(studentFileTabs(const StudentCan(kase: true)), contains(StudentFileTab.documents));
      expect(studentFileTabs(const StudentCan(complaints: true)), contains(StudentFileTab.requests));
      expect(studentFileTabs(const StudentCan(accessLog: true)), contains(StudentFileTab.accessLog));
      expect(studentFileTabs(const StudentCan(accessLog: true)), isNot(contains(StudentFileTab.advising)));
    });

    test('every tab has words in both languages', () {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        final texts = {for (final x in StudentFileTab.values) studentFileTabText(x)};
        expect(texts.length, StudentFileTab.values.length);
      }
    });
  });

  group('timeline', () {
    test('every kind has its own words (both languages) and icon', () {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final k in kTimelineKinds) {
          expect(timelineKindText(k), isNot(k), reason: '$lang $k');
        }
      }
      expect({for (final k in kTimelineKinds) timelineIcon(k)}.length, kTimelineKinds.length);
      expect(kTimelineFilterKinds.every(kTimelineKinds.contains), isTrue);
    });

    test('a page parses items, next_before and hidden_kinds', () {
      final p = TimelinePage.fromJson({
        'items': [
          {'id': 'case_event:9912', 'kind': 'documents', 'at': '2026-10-02T09:14:00', 'actor': {'id': 44, 'name': 'Mona'},
           'title_ar': 'تم التحقق من مستند', 'title_en': 'Document verified', 'source': {'type': 'case', 'id': 3310}},
          {'id': 'audit:1', 'kind': 'record', 'at': '2026-09-01T00:00:00', 'actor': null},
        ],
        'next_before': '2026-09-01T00:00:00',
        'hidden_kinds': ['complaints'],
      });
      expect(p.items.length, 2);
      expect(p.items.first.title, 'Document verified');
      expect(p.items.first.actor, 'Mona');
      expect(p.items.first.sourceId, 3310);
      expect(p.items.last.actor, 'System');
      expect(p.items.last.title, timelineKindText('record'));
      expect(p.nextBefore, '2026-09-01T00:00:00');
      expect(p.hiddenKinds, ['complaints']);
    });

    test('merging a page drops the items already shown', () {
      const a = TimelineItem(id: 'a', kind: 'record'), b = TimelineItem(id: 'b', kind: 'record');
      const c = TimelineItem(id: 'c', kind: 'record');
      expect([for (final i in mergeTimeline([a, b], [b, c])) i.id], ['a', 'b', 'c']);
    });

    test('academic years start in September; days group inside them; undated last', () {
      DateTime wall(DateTime utc) => utc.toUtc();
      final items = [
        ...sampleTimeline(),
        const TimelineItem(id: 'x', kind: 'record'),
      ];
      final groups = groupTimelineByYear(items, wallOf: wall);
      expect([for (final g in groups) g.startYear], [2026, 2025, null]);
      expect(groups.first.days.first.items.length, 2); // two on 20 Nov 2026
      expect(groups.first.days.first.day, DateTime(2026, 11, 20));
      expect(groups.fold<int>(0, (n, g) => n + g.count), items.length);
      expect(groups.first.label, 'Academic year 2026/2027');
      expect(groups.last.label, 'No date');
      expect(academicYearOf(DateTime(2026, 8, 31)), 2025);
      expect(academicYearOf(DateTime(2026, 9, 1)), 2026);
    });
  });

  test('open lifecycle requests: parsed newest first, labels by language, entries without an id dropped', () {
    final o = StudentOpen.fromJson({
      'requests': 2,
      'lifecycle_requests': [
        {'id': 9, 'ref': 'S-2026-0009', 'request': 'suspend', 'label_ar': 'إيقاف قيد', 'label_en': 'Suspension', 'status': 'under_review',
          'status_label_ar': 'قيد المراجعة', 'status_label_en': 'Under review', 'stage': 'review', 'origin': 'student', 'created_at': '2026-11-20T10:00:00'},
        {'ref': 'no id'},
      ],
    });
    expect(o.requests, 2);
    expect(o.lifecycleRequests.length, 1);
    final x = o.lifecycleRequests.single;
    expect((x.id, x.ref, x.label, x.statusLabel, x.stage), (9, 'S-2026-0009', 'Suspension', 'Under review', 'review'));
    expect(x.createdAt!.toUtc(), DateTime.utc(2026, 11, 20, 10));
    AppConfig.lang = 'ar';
    expect(StudentOpen.fromJson({'lifecycle_requests': [{'id': 1, 'label_en': 'Only English'}]}).lifecycleRequests.single.label, 'Only English');
    expect(StudentOpen.fromJson({'requests': 1}).lifecycleRequests, isEmpty); // an older server
  });
}
