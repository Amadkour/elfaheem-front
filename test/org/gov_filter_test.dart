// Pure governance logic (docs/backend/governance-spec.md): the shared filter ⇄ query string, its chips and counts,
// the error-code texts of spec §2, delegation scope matching, the council tally matrix of §3, and the item /
// agenda models from spec-shaped JSON. The sample JSON here is also what test/ui/gov_layout_test.dart pumps.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_dashboard.dart' show GovDashboardStats, dashboardTileFilter;
import 'package:flutter_education_app/features/org/governance/gov_filter.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// §4 item JSON (`full: true`): routes, events, agenda, legacy ids, a pending approval route and a decision block.
Map<String, dynamic> sampleItemJson({bool full = true, bool decided = false, bool canDecide = true}) => {
      'id': 41,
      'ref': 'W-2026-000041',
      'type': 'request',
      'title': 'طلب تأجيل الامتحان النهائي لمقرر البرمجة — a title long enough to wrap on a narrow phone with large text',
      'body': 'نرجو تأجيل الامتحان أسبوعاً بسبب تعارض مع امتحان آخر.\nThe exam clashes with another one; we ask for a one-week delay.',
      'status': decided ? 'approved' : 'pending_approval',
      'priority': 'high',
      'category': {'id': 3, 'dept_id': 5, 'key': 'exam_delay', 'name_ar': 'تأجيل امتحان', 'name_en': 'Exam delay', 'kind': 'request', 'is_active': true, 'order': 1},
      'source': {
        'dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'kind': 'service'},
        'user': {'id': 9, 'name': 'سارة أحمد'},
        'anonymous': false,
      },
      'owner_dept': {'id': 5, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer Science', 'kind': 'scientific'},
      'assignee': {'id': 7, 'name': 'Dr. Omar'},
      'due_at': '2026-10-30T10:00:00',
      'decided_at': decided ? '2026-10-28T09:00:00' : null,
      'decision': decided ? {'outcome': 'approved', 'by': {'id': 11, 'name': 'Prof. Huda'}, 'at': '2026-10-28T09:00:00', 'note': 'Approved for one week', 'via': 'head'} : null,
      'vote_outcome': decided ? 'approved' : null,
      'attachments': [
        {'name': 'timetable.pdf', 'url': 'https://example.org/f/1', 'type': 'application/pdf', 'size': 20480},
      ],
      'tags': ['exams', 'urgent'],
      'version': 3,
      'created_at': '2026-10-27T08:00:00',
      'updated_at': '2026-10-27T09:30:00',
      'overdue': false,
      'pending_route': decided
          ? null
          : {
              'id': 4,
              'action': 'approval',
              'from': {'dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'kind': 'service'}, 'user': {'id': 9, 'name': 'سارة أحمد'}},
              'to': {'dept': {'id': 5, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer Science', 'kind': 'scientific'}, 'user': null},
              'note': 'للاعتماد من رئيس القسم',
              'due_at': '2026-10-29T10:00:00',
              'status': 'pending',
              'created_at': '2026-10-27T09:00:00',
              'created_by': {'id': 9, 'name': 'سارة أحمد'},
            },
      'can': {'view': true, 'route': true, 'decide': canDecide, 'comment': true, 'edit': true, 'delete': true, 'withdraw': false, 'export': true},
      if (full) ...{
        'payload': {'form_id': 12, 'answers': {'q1': 'yes'}},
        'routes': [
          {
            'id': 3,
            'parent_route_id': null,
            'from': {'dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'kind': 'service'}, 'user': null},
            'to': {'dept': null, 'user': {'id': 7, 'name': 'Dr. Omar'}},
            'action': 'review',
            'note': 'Please check the clash',
            'due_at': null,
            'status': 'answered',
            'answer': 'reviewed',
            'answered_by': {'id': 7, 'name': 'Dr. Omar'},
            'answered_at': '2026-10-27T08:40:00',
            'answer_note': 'Confirmed: the exams overlap',
            'session_id': null,
            'created_at': '2026-10-27T08:10:00',
            'created_by': {'id': 9, 'name': 'سارة أحمد'},
          },
          {
            'id': 4,
            'parent_route_id': 3,
            'from': {'dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'kind': 'service'}, 'user': {'id': 9, 'name': 'سارة أحمد'}},
            'to': {'dept': {'id': 5, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer Science', 'kind': 'scientific'}, 'user': null},
            'action': 'approval',
            'note': 'للاعتماد من رئيس القسم',
            'due_at': '2026-10-29T10:00:00',
            'status': decided ? 'answered' : 'pending',
            'answer': decided ? 'approved' : null,
            'answered_by': decided ? {'id': 11, 'name': 'Prof. Huda'} : null,
            'answered_at': decided ? '2026-10-28T09:00:00' : null,
            'answer_note': null,
            'session_id': null,
            'created_at': '2026-10-27T09:00:00',
            'created_by': {'id': 9, 'name': 'سارة أحمد'},
          },
        ],
        'events': [
          {'id': 1, 'kind': 'created', 'actor': {'id': 9, 'name': 'سارة أحمد'}, 'body': null, 'internal': false, 'data': {}, 'created_at': '2026-10-27T08:00:00'},
          {'id': 2, 'kind': 'routed', 'actor': {'id': 9, 'name': 'سارة أحمد'}, 'body': null, 'internal': false, 'data': {'action': 'review', 'to_name': 'Dr. Omar'}, 'created_at': '2026-10-27T08:10:00'},
          {'id': 3, 'kind': 'comment', 'actor': {'id': 7, 'name': 'Dr. Omar'}, 'body': 'ملاحظة داخلية: الطالبة محقة، الامتحانان في اليوم نفسه. Internal: she is right, both exams fall on the same day.', 'internal': true, 'data': {}, 'created_at': '2026-10-27T08:30:00'},
          {'id': 4, 'kind': 'comment', 'actor': {'id': 9, 'name': 'سارة أحمد'}, 'body': 'شكراً لكم', 'internal': false, 'data': {'attachments': [{'name': 'proof.png', 'url': 'https://example.org/f/2'}]}, 'created_at': '2026-10-27T08:50:00'},
          {'id': 5, 'kind': 'routed', 'actor': {'id': 9, 'name': 'سارة أحمد'}, 'body': null, 'internal': false, 'data': {'action': 'approval', 'to': {'id': 5, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer Science'}}, 'created_at': '2026-10-27T09:00:00'},
          if (decided) {'id': 6, 'kind': 'decided', 'actor': {'id': 11, 'name': 'Prof. Huda'}, 'body': null, 'internal': false, 'data': {'outcome': 'approved', 'note': 'Approved for one week'}, 'created_at': '2026-10-28T09:00:00'},
          if (decided) {'id': 7, 'kind': 'locked_out', 'actor': null, 'body': null, 'internal': false, 'data': {}, 'created_at': '2026-10-28T09:00:01'},
        ],
        'agenda': [
          {'session_id': 8, 'council': {'id': 6, 'name_ar': 'مجلس قسم علوم الحاسب', 'name_en': 'CS Department Council', 'kind': 'council'}, 'status': 'approved', 'approve_count': 6, 'reject_count': 2, 'abstain_count': 1, 'eligible_count': 10, 'approve_pct': 75.0, 'scheduled_at': '2026-10-20T10:00:00'},
        ],
        'legacy': {'complaint_id': null, 'form_response_id': 77},
      },
    };

/// §5 agenda JSON with votes (a manager's view).
Map<String, dynamic> sampleAgendaJson() => {
      'id': 21,
      'order': 2,
      'item': sampleItemJson(full: false),
      'status': 'voting',
      'approve_count': 3,
      'reject_count': 1,
      'abstain_count': 1,
      'eligible_count': 9,
      'approve_pct': 75.0,
      'decided_at': null,
      'note': null,
      'my_vote': 'approve',
      'votes': [
        {'user': {'id': 11, 'name': 'Prof. Huda'}, 'vote': 'approve', 'note': null, 'at': '2026-10-27T10:00:00'},
        {'user': {'id': 7, 'name': 'Dr. Omar'}, 'vote': 'reject', 'note': 'Too late', 'at': '2026-10-27T10:05:00'},
      ],
      'escalated_item_id': null,
    };

/// §4 entity JSON.
Map<String, dynamic> sampleEntityJson({String kind = 'scientific', int id = 5}) => {
      'id': id,
      'code': 'CS',
      'name_ar': 'قسم علوم الحاسب',
      'name_en': 'Computer Science',
      'description': 'Computer science and software engineering programs',
      'kind': kind,
      'program_id': 2,
      'council_id': kind == 'scientific' ? 6 : null,
      'head': {'id': 11, 'name': 'Prof. Huda Al-Sayed'},
      'members': 14,
      'accepts_complaints': kind != 'council',
      'can_submit_to_council': kind == 'scientific',
      'is_active': true,
      'order': 1,
      'features': ['complaints', 'forms'],
      'counts': {'open': 7, 'pending_decision': 3, 'overdue': 1},
      'can': {'manage': true, 'decide': true},
      'categories': [
        {'id': 3, 'dept_id': id, 'key': 'exam_delay', 'name_ar': 'تأجيل امتحان', 'name_en': 'Exam delay', 'kind': 'request', 'is_active': true, 'order': 1, 'form_id': 12},
        {'id': 4, 'dept_id': id, 'key': 'grading', 'name_ar': 'تظلم درجات', 'name_en': 'Grade appeal', 'kind': 'complaint', 'is_active': true, 'order': 2},
      ],
    };

Map<String, dynamic> sampleDelegationJson({String mode = 'scoped', bool revoked = false}) => {
      'id': 5,
      'dept_id': 5,
      'dept': {'id': 5, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer Science', 'kind': 'scientific'},
      'from': {'id': 11, 'name': 'Prof. Huda'},
      'to': {'id': 7, 'name': 'Dr. Omar'},
      'mode': mode,
      'scope': {'types': ['request', 'form'], 'category_ids': [3], 'form_ids': [12], 'council': true},
      'starts_at': '2026-10-01T00:00:00',
      'ends_at': '2026-12-31T00:00:00',
      'revoked_at': revoked ? '2026-10-20T12:00:00' : null,
      'active': !revoked,
      'note': 'During the sabbatical',
      'created_at': '2026-09-28T09:00:00',
    };

/// The error codes of spec §2 (plus the two the app adds).
const specCodes = [
  'entity_not_found', 'entity_kind_invalid', 'category_not_found', 'item_not_found', 'item_forbidden', 'already_decided',
  'stale_version', 'item_closed', 'route_target_required', 'route_not_allowed', 'route_self', 'not_a_decider',
  'delegation_invalid', 'delegation_not_found', 'council_not_found', 'session_not_found', 'session_state', 'not_a_voter',
  'voting_closed', 'no_faculty_council', 'form_not_found', 'assignment_exists', 'filter_name_taken', 'template_not_found',
  'export_forbidden',
];

CouncilSettings _settings({int quorum = 50, String tie = 'reject', bool abstainCounts = false, String noVote = 'ignore'}) =>
    CouncilSettings(quorumPct: quorum, tieRule: tie, abstainCounts: abstainCounts, noVoteRule: noVote);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('ItemFilter', () {
    test('toQuery ↔ fromQuery round trip keeps every axis', () {
      final f = ItemFilter(
        q: 'exam',
        types: const ['complaint', 'request'],
        statuses: const ['open', 'in_review'],
        deptId: 5,
        sourceDeptId: 2,
        sourceUserId: 9,
        assigneeId: 7,
        categoryId: 3,
        outcomes: const ['approved', 'tied'],
        dateFrom: DateTime(2026, 10, 1),
        dateTo: DateTime(2026, 10, 31),
        mine: true,
        toMe: false,
        overdue: true,
        sort: 'due_at',
      );
      final q = f.toQuery();
      expect(q['type'], 'complaint,request');
      expect(q['status'], 'open,in_review');
      expect(q['date_from'], '2026-10-01');
      expect(q['date_to'], '2026-10-31');
      expect(q['mine'], true);
      expect(q.containsKey('to_me'), isFalse);
      expect(q['overdue'], true);
      expect(q['sort'], 'due_at');
      final back = ItemFilter.fromQuery(q);
      expect(back, f);
      expect(back.types, ['complaint', 'request']);
      expect(back.dateFrom, DateTime(2026, 10, 1));
      expect(back.activeCount, f.activeCount);
    });

    test('empty filter sends nothing; default sort omitted; equality by query', () {
      const f = ItemFilter();
      expect(f.toQuery(), isEmpty);
      expect(f.isEmpty, isTrue);
      expect(f.activeCount, 0);
      expect(f.quick, 'all');
      expect(const ItemFilter(q: 'a'), const ItemFilter(q: 'a'));
      expect(const ItemFilter(q: 'a') == const ItemFilter(q: 'b'), isFalse);
    });

    test('fromQuery reads saved-filter JSON (lists as arrays, flags as strings / ints)', () {
      final f = ItemFilter.fromQuery({
        'type': ['memo', 'form'],
        'status': 'closed',
        'to_me': 'true',
        'overdue': 1,
        'mine': 'false',
        'dept_id': '5',
        'date_from': '2026-09-15T13:00:00',
        'sort': 'bogus',
      });
      expect(f.types, ['memo', 'form']);
      expect(f.statuses, ['closed']);
      expect(f.toMe, isTrue);
      expect(f.overdue, isTrue);
      expect(f.mine, isFalse);
      expect(f.deptId, 5);
      expect(f.dateFrom, DateTime(2026, 9, 15));
      expect(f.sort, '-created_at');
    });

    test('quick tabs are exclusive', () {
      final f = const ItemFilter(mine: true).withQuick('to_me');
      expect(f.toMe, isTrue);
      expect(f.mine, isFalse);
      expect(f.quick, 'to_me');
      expect(f.withQuick('all').activeCount, 0);
    });

    test('chips describe the set axes with names and `without` removes one', () {
      final f = ItemFilter(types: const ['complaint'], deptId: 5, assigneeId: 7, categoryId: 3, dateFrom: DateTime(2026, 10, 1), overdue: true);
      final chips = f.chips(deptName: (id) => 'Dept $id', userName: (id) => 'User $id', categoryName: (id) => 'Cat $id');
      expect(chips.map((c) => c.key), ['types', 'deptId', 'assigneeId', 'categoryId', 'dates', 'overdue']);
      expect(chips.firstWhere((c) => c.key == 'deptId').label, contains('Dept 5'));
      expect(chips.firstWhere((c) => c.key == 'assigneeId').label, contains('User 7'));
      expect(chips.firstWhere((c) => c.key == 'categoryId').label, contains('Cat 3'));
      expect(chips.firstWhere((c) => c.key == 'types').label, contains('Complaint'));
      expect(f.activeCount, 6);
      final less = f.without('dates').without('types');
      expect(less.dateFrom, isNull);
      expect(less.types, isEmpty);
      expect(less.activeCount, 4);
      expect(f.cleared(keepDept: true).deptId, 5);
      expect(f.cleared(keepDept: true).overdue, isTrue);
      expect(f.cleared(keepQuick: false).activeCount, 0);
      AppConfig.lang = 'ar';
      expect(f.chips().first.label, contains('شكوى'));
    });

    test('dashboard tiles map to filters', () {
      expect(dashboardTileFilter('pending').statuses, contains('pending_approval'));
      expect(dashboardTileFilter('pending_decision').toMe, isTrue);
      expect(dashboardTileFilter('overdue').overdue, isTrue);
      final d = dashboardTileFilter('decided');
      expect(d.statuses, ['approved', 'rejected']);
      expect(d.dateFrom, isNotNull);
      final s = GovDashboardStats.fromJson({'pending': 4, 'pending_decision': 2, 'overdue': 1, 'decided_30d': 9, 'by_status': {'open': 3, 'closed': 5}, 'by_type': {'complaint': 2}, 'sla': {'on_time_pct': 87.5}});
      expect(s.total, 8);
      expect(s.onTimePct, 87.5);
    });
  });

  group('code texts', () {
    test('every §2 code has a bilingual text', () {
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        final m = govCodeTexts();
        for (final code in specCodes) {
          expect(m[code], isNotNull, reason: '$code missing in $lang');
          expect(m[code], isNotEmpty);
        }
      }
      expect(govCodeTexts()['already_decided'], isNot(govCodeTexts()['stale_version']));
    });
  });

  group('Delegation.covers', () {
    final item = WorkItem.fromJson(sampleItemJson());

    test('global covers everything', () {
      final d = Delegation.fromJson(sampleDelegationJson(mode: 'global'));
      expect(d.isGlobal, isTrue);
      expect(d.covers(item), isTrue);
    });

    test('scoped: every non-empty axis must match', () {
      final d = Delegation.fromJson(sampleDelegationJson());
      expect(d.covers(item), isTrue); // request · category 3 · form 12
      final otherType = WorkItem.fromJson({...sampleItemJson(), 'type': 'complaint'});
      expect(d.covers(otherType), isFalse);
      final otherCat = WorkItem.fromJson({...sampleItemJson(), 'category': {'id': 4, 'kind': 'complaint'}});
      expect(d.covers(otherCat), isFalse);
      final noForm = WorkItem.fromJson({...sampleItemJson(), 'payload': {}});
      expect(d.covers(noForm), isFalse);
      final otherForm = WorkItem.fromJson({...sampleItemJson(), 'payload': {'form_id': 99}});
      expect(d.covers(otherForm), isFalse);
    });

    test('scoped with an empty scope covers everything; dates and revocation', () {
      final d = Delegation.fromJson({...sampleDelegationJson(), 'scope': {}});
      expect(d.scope.isEmpty, isTrue);
      expect(d.covers(WorkItem.fromJson({...sampleItemJson(), 'type': 'memo', 'category': null, 'payload': {}})), isTrue);
      expect(d.activeAt(DateTime(2026, 11, 1)), isTrue);
      expect(d.activeAt(DateTime(2027, 1, 1)), isFalse);
      expect(d.activeAt(DateTime(2026, 9, 1)), isFalse);
      expect(Delegation.fromJson(sampleDelegationJson(revoked: true)).activeAt(DateTime(2026, 11, 1)), isFalse);
      final open = Delegation.fromJson({...sampleDelegationJson(), 'starts_at': null, 'ends_at': null});
      expect(open.activeAt(DateTime(2030, 1, 1)), isTrue);
    });
  });

  group('VoteTally.compute (spec §3)', () {
    test('approved / rejected with the percentage over approve + reject', () {
      final a = VoteTally.compute(approve: 5, reject: 2, abstain: 0, eligible: 10, s: _settings());
      expect(a.outcome, 'approved');
      expect(a.quorumMet, isTrue);
      expect(a.needed, 5);
      expect(a.approvePct, closeTo(71.43, 0.01));
      final r = VoteTally.compute(approve: 2, reject: 5, abstain: 0, eligible: 10, s: _settings());
      expect(r.outcome, 'rejected');
    });

    test('tie → reject / chair / postpone', () {
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: _settings()).outcome, 'rejected');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: _settings(tie: 'chair'), chairVote: 'approve').outcome, 'approved');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: _settings(tie: 'chair'), chairVote: 'reject').outcome, 'rejected');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: _settings(tie: 'chair')).outcome, 'rejected', reason: 'no chair vote → rejected');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: _settings(tie: 'postpone')).outcome, 'postponed');
    });

    test('quorum = ceil(eligible × pct / 100); none with no members', () {
      final nq = VoteTally.compute(approve: 1, reject: 0, abstain: 0, eligible: 10, s: _settings());
      expect(nq.outcome, 'no_quorum');
      expect(nq.quorumMet, isFalse);
      expect(VoteTally.compute(approve: 3, reject: 0, abstain: 0, eligible: 7, s: _settings()).needed, 4);
      expect(VoteTally.compute(approve: 3, reject: 0, abstain: 0, eligible: 7, s: _settings()).outcome, 'no_quorum');
      expect(VoteTally.compute(approve: 4, reject: 0, abstain: 0, eligible: 7, s: _settings()).outcome, 'approved');
      expect(VoteTally.compute(approve: 0, reject: 0, abstain: 0, eligible: 0, s: _settings()).outcome, 'no_quorum');
    });

    test('abstain counts in the denominator only when switched on', () {
      final off = VoteTally.compute(approve: 3, reject: 1, abstain: 4, eligible: 8, s: _settings());
      expect(off.approvePct, 75.0);
      final on = VoteTally.compute(approve: 3, reject: 1, abstain: 4, eligible: 8, s: _settings(abstainCounts: true));
      expect(on.approvePct, 37.5);
      expect(on.outcome, 'approved');
    });

    test('no_vote_rule abstain adds the non-voters to the denominator', () {
      final ignore = VoteTally.compute(approve: 3, reject: 1, abstain: 0, eligible: 8, s: _settings());
      expect(ignore.approvePct, 75.0);
      final abst = VoteTally.compute(approve: 3, reject: 1, abstain: 0, eligible: 8, s: _settings(noVote: 'abstain'));
      expect(abst.approvePct, 37.5);
      expect(abst.quorumMet, isTrue);
      final zero = VoteTally.compute(approve: 0, reject: 0, abstain: 4, eligible: 4, s: _settings());
      expect(zero.approvePct, 0.0);
      expect(zero.outcome, 'rejected');
    });
  });

  group('models from spec JSON', () {
    test('WorkItem (full)', () {
      final it = WorkItem.fromJson(sampleItemJson());
      expect(it.ref, 'W-2026-000041');
      expect(it.status, 'pending_approval');
      expect(it.isDecidable, isTrue);
      expect(it.isOpen, isTrue);
      expect(it.category?.name, 'Exam delay');
      expect(it.sourceUser?.name, 'سارة أحمد');
      expect(it.sourceDept?.kind, 'service');
      expect(it.ownerDept?.id, 5);
      expect(it.ownerDept?.name, 'Computer Science');
      expect(it.assignee?.id, 7);
      expect(it.dueAt, isNotNull);
      expect(it.version, 3);
      expect(it.tags, ['exams', 'urgent']);
      expect(it.attachments.single.size, 20480);
      expect(it.pendingRoute?.action, 'approval');
      expect(it.pendingRoute?.targetName, 'Computer Science');
      expect(it.pendingRoute?.pending, isTrue);
      expect(it.can['decide'], isTrue);
      expect(it.can['withdraw'], isFalse);
      expect(it.can['nope'], isFalse);
      expect(it.payload['form_id'], 12);
      expect(it.routes.length, 2);
      expect(it.routes.first.answer, 'reviewed');
      expect(it.routes.first.sourceName, 'Student affairs');
      expect(it.routes.first.targetName, 'Dr. Omar');
      expect(it.events.length, 5);
      expect(it.events.where((e) => e.internal).length, 1);
      expect(it.agenda.single.approvePct, 75.0);
      expect(it.agenda.single.council?.name, 'CS Department Council');
      expect(it.formResponseId, 77);
      expect(it.complaintId, isNull);
      AppConfig.lang = 'ar';
      expect(it.ownerDept?.name, 'قسم علوم الحاسب');
      expect(it.sourceName, 'سارة أحمد');
    });

    test('WorkItem decided + anonymous source', () {
      final it = WorkItem.fromJson({...sampleItemJson(decided: true), 'source': {'dept': null, 'user': null, 'anonymous': true}});
      expect(it.isDecided, isTrue);
      expect(it.decision?.outcome, 'approved');
      expect(it.decision?.by?.name, 'Prof. Huda');
      expect(it.decision?.via, 'head');
      expect(it.pendingRoute, isNull);
      expect(it.sourceName, 'Anonymous');
      expect(it.events.map((e) => e.kind), contains('locked_out'));
    });

    test('AgendaItem with votes', () {
      final a = AgendaItem.fromJson(sampleAgendaJson());
      expect(a.id, 21);
      expect(a.item.ref, 'W-2026-000041');
      expect(a.voted, 5);
      expect(a.decided, isFalse);
      expect(a.myVote, 'approve');
      expect(a.votes.length, 2);
      expect(a.votes.last.note, 'Too late');
      expect(AgendaItem.fromJson({...sampleAgendaJson(), 'status': 'no_quorum'}).decided, isTrue);
    });

    test('Entity · Delegation · GovPage facets', () {
      final e = Entity.fromJson(sampleEntityJson());
      expect(e.canSubmitToCouncil, isTrue);
      expect(Entity.fromJson(sampleEntityJson(kind: 'service', id: 2)).canSubmitToCouncil, isFalse);
      expect(e.isScientific, isTrue);
      expect(e.councilId, 6);
      expect(e.head?.name, 'Prof. Huda Al-Sayed');
      expect(e.counts.pendingDecision, 3);
      expect(e.can['manage'], isTrue);
      expect(e.categories.length, 2);
      expect(e.categories.first.formId, 12);
      final d = Delegation.fromJson(sampleDelegationJson());
      expect(d.scope.types, ['request', 'form']);
      expect(d.scope.council, isTrue);
      expect(d.to.name, 'Dr. Omar');
      final page = GovPage.from({'items': [sampleItemJson(full: false)], 'total': 1, 'page': 1, 'size': 30, 'pages': 1, 'facets': {'status': {'open': 4}, 'type': {'request': 1}}}, WorkItem.fromJson);
      expect(page.items.single.id, 41);
      expect(page.facet('status', 'open'), 4);
      expect(page.facet('status', 'closed'), 0);
    });
  });
}
