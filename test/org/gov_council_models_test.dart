// Council models and pure logic of the governance module: CouncilSettings (defaults, whole-object round trip),
// CouncilSession / AgendaItem from the spec-shaped JSON (my_votes map, agenda votes, pendingMyVotes), the tally rule
// matrix behind the settings preview, the /me/votes grouping, and the small time helpers.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_council_ui.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_my_votes.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GET …/sessions/{sid}` as spec §5 describes it.
Map<String, dynamic> sessionJson({String status = 'voting'}) => {
      'id': 71,
      'council': {
        'id': 5,
        'dept': {'id': 40, 'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'Computer Science Department Council', 'kind': 'council'},
        'parent_dept': {'id': 12, 'name_ar': 'قسم الحاسبات', 'name_en': 'Computer Science', 'kind': 'scientific'},
        'level': 'department',
        'chair': {'id': 9, 'name': 'د. أحمد'},
        'members': 7,
        'session_day': 15,
        'session_time': '10:00',
        'next_session': {'id': 71, 'scheduled_at': '2026-11-15T08:00:00', 'status': status},
        'settings': {'session_day': 15, 'session_time': '10:00', 'quorum_pct': 50, 'tie_rule': 'chair', 'voting_deadline_hours': 48},
        'can': {'manage': true, 'vote': true},
      },
      'kind': 'regular',
      'title': 'جلسة نوفمبر — a title long enough to wrap on a narrow phone with large text',
      'scheduled_at': '2026-11-15T08:00:00',
      'status': status,
      'published_at': '2026-11-13T08:00:00',
      'voting_opens_at': '2026-11-15T08:00:00',
      'voting_closes_at': '2026-11-17T08:00:00',
      'closed_at': status == 'closed' ? '2026-11-17T08:00:00' : null,
      'eligible_count': 7,
      'version': 3,
      'results_visible': status == 'closed',
      'notes': 'Bring the lab reports',
      'my_votes': {'301': 'approve'},
      'minutes': status == 'closed' ? minutesJson() : null,
      'can': {'manage': true, 'vote': true, 'export_votes': true},
      'agenda': [
        agendaJson(301, 1, status: status == 'closed' ? 'approved' : 'voting', myVote: 'approve', approve: 4, reject: 2, abstain: 1),
        agendaJson(302, 2, status: status == 'closed' ? 'rejected' : 'voting', approve: 2, reject: 4),
        agendaJson(303, 3, status: status == 'closed' ? 'no_quorum' : 'voting', approve: 1, reject: 1, note: 'decided_elsewhere'),
        agendaJson(304, 4, status: status == 'closed' ? 'postponed' : 'voting', approve: 3, reject: 3, escalated: 900),
        agendaJson(305, 5, status: 'withdrawn'),
      ],
    };

Map<String, dynamic> agendaJson(int id, int order, {String status = 'voting', String? myVote, int approve = 0, int reject = 0, int abstain = 0, String? note, int? escalated}) => {
      'id': id,
      'order': order,
      'item': {
        'id': 1000 + id,
        'ref': 'W-2026-00$id',
        'type': order.isEven ? 'request' : 'complaint',
        'title': 'بند $order — Agenda item number $order with a reasonably long title to wrap',
        'status': note == 'decided_elsewhere' ? 'approved' : 'in_council',
        'priority': 'high',
        'source': {
          'dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'kind': 'service'},
          'user': {'id': 77, 'name': 'Mona Ali'},
          'anonymous': false,
        },
        'owner_dept': {'id': 40, 'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'CS Department Council', 'kind': 'council'},
        'version': 2,
        'can': {'view': true},
        if (note == 'decided_elsewhere') 'decision': {'outcome': 'approved', 'via': 'head', 'by': {'id': 9, 'name': 'د. أحمد'}},
      },
      'status': status,
      'approve_count': approve,
      'reject_count': reject,
      'abstain_count': abstain,
      'eligible_count': 7,
      'approve_pct': approve + reject == 0 ? null : approve / (approve + reject) * 100,
      'outcome': status,
      'decided_at': status == 'voting' || status == 'pending' ? null : '2026-11-17T08:00:00',
      'note': note,
      'my_vote': myVote,
      'escalated_item_id': escalated,
      'votes': [
        for (var i = 0; i < approve; i++) {'user': {'id': 10 + i, 'name': 'Member $i'}, 'vote': 'approve', 'note': i == 0 ? 'With the budget cap' : null, 'at': '2026-11-15T09:0$i:00'},
        for (var i = 0; i < reject; i++) {'user': {'id': 20 + i, 'name': 'عضو $i'}, 'vote': 'reject', 'at': '2026-11-15T10:00:00'},
        for (var i = 0; i < abstain; i++) {'user': {'id': 30 + i, 'name': 'Abstainer $i'}, 'vote': 'abstain', 'at': '2026-11-15T11:00:00'},
      ],
    };

Map<String, dynamic> minutesJson() => {
      'generated_at': '2026-11-17T08:00:05',
      'council': {'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'Computer Science Department Council'},
      'session': {'title': 'جلسة نوفمبر', 'scheduled_at': '2026-11-15T08:00:00'},
      'date': '2026-11-15T08:00:00',
      'present': [
        {'id': 10, 'name': 'Member 0'},
        {'id': 11, 'name': 'Member 1'},
        'عضو 0',
      ],
      'summary': {'approved': 1, 'rejected': 1, 'no_quorum': 1, 'postponed': 1},
      'items': [
        {'order': 1, 'ref': 'W-2026-00301', 'title': 'Budget of the new lab', 'approve': 4, 'reject': 2, 'abstain': 1, 'eligible': 7, 'approve_pct': 66.7, 'outcome': 'approved', 'decision': {'outcome': 'approved', 'text': 'Approved with the budget cap'}},
        {'order': 2, 'item': {'ref': 'W-2026-00302', 'title': 'Change of the exam date'}, 'votes': {'approve': 2, 'reject': 4, 'abstain': 0, 'eligible': 7, 'approve_pct': 33.3, 'outcome': 'rejected'}, 'decision': 'Rejected'},
        {'order': 3, 'ref': 'W-2026-00303', 'title': 'Carried over', 'approve': 1, 'reject': 1, 'abstain': 0, 'eligible': 7, 'approve_pct': 50, 'outcome': 'no_quorum'},
      ],
    };

/// `GET …/me/votes` rows: the nested `session` shape and the flat shape.
List<Map<String, dynamic>> myVotesJson() => [
      {
        ...agendaJson(401, 2, approve: 1),
        'session': {'id': 71, 'title': null, 'kind': 'regular', 'status': 'voting', 'scheduled_at': '2026-11-15T08:00:00', 'voting_closes_at': '2026-11-17T08:00:00', 'council': {'id': 5, 'dept': {'id': 40, 'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'CS Council', 'kind': 'council'}}},
      },
      {
        ...agendaJson(402, 1, myVote: 'reject'),
        'session': {'id': 71, 'kind': 'regular', 'status': 'voting', 'scheduled_at': '2026-11-15T08:00:00', 'voting_closes_at': '2026-11-17T08:00:00', 'council': {'id': 5, 'dept': {'id': 40, 'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'CS Council', 'kind': 'council'}}},
      },
      {
        ...agendaJson(403, 1),
        'session_id': 80,
        'session_title': 'Extraordinary: accreditation file',
        'session_kind': 'extraordinary',
        'voting_closes_at': '2026-11-16T08:00:00',
        'council': {'id': 60, 'name_ar': 'مجلس الكلية', 'name_en': 'Faculty Council', 'kind': 'council'},
      },
      {...agendaJson(404, 1)},
    ];

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('CouncilSettings', () {
    test('defaults match the spec and the whole object round-trips', () {
      final d = CouncilSettings();
      expect(d.sessionDay, isNull);
      expect(d.sessionTime, '10:00');
      expect(d.cutoffDays, 2);
      expect(d.votingDeadlineHours, 72);
      expect(d.quorumPct, 50);
      expect(d.tieRule, 'reject');
      expect(d.abstainCounts, isFalse);
      expect(d.noVoteRule, 'ignore');
      expect(d.holidayRule, 'next_day');
      expect(d.autoAgenda, isTrue);
      expect(d.timezone, isNull);
      final j = d.toJson();
      expect(j.keys, containsAll(['chair_user_id', 'session_day', 'session_time', 'cutoff_days', 'voting_deadline_hours', 'quorum_pct', 'tie_rule', 'abstain_counts', 'no_vote_rule', 'holidays', 'holiday_rule', 'auto_agenda', 'auto_agenda_rules', 'timezone']));
      expect(j['auto_agenda_rules'], {'types': <String>[], 'category_ids': <int>[]});

      final s = CouncilSettings.fromJson({
        'chair_user_id': 9,
        'session_day': 15,
        'session_time': '09:30',
        'cutoff_days': 3,
        'voting_deadline_hours': 48,
        'quorum_pct': 60,
        'tie_rule': 'chair',
        'abstain_counts': true,
        'no_vote_rule': 'abstain',
        'holidays': ['2026-11-05', '2026-12-25'],
        'holiday_rule': 'next_week',
        'auto_agenda': false,
        'auto_agenda_rules': {'types': ['request', 'memo'], 'category_ids': [3, 4]},
        'timezone': 'Africa/Cairo',
      });
      expect(CouncilSettings.fromJson(s.toJson()).toJson(), s.toJson());
      expect(s.copy().toJson(), s.toJson());
      expect(s.autoAgendaTypes, ['request', 'memo']);
      expect(s.autoAgendaCategoryIds, [3, 4]);
      // unknown enum values fall back to the defaults instead of breaking the PUT
      final bad = CouncilSettings.fromJson({'tie_rule': 'coin', 'no_vote_rule': 'x', 'holiday_rule': 'y'});
      expect([bad.tieRule, bad.noVoteRule, bad.holidayRule], ['reject', 'ignore', 'next_day']);
    });
  });

  group('CouncilSession', () {
    test('parses the spec JSON: council, times, my_votes, agenda votes, pendingMyVotes', () {
      final s = CouncilSession.fromJson(sessionJson());
      expect(s.id, 71);
      expect(s.council?.name, 'Computer Science Department Council');
      expect(s.council?.parentDept?.id, 12);
      expect(s.council?.settings?.tieRule, 'chair');
      expect(s.isVoting, isTrue);
      expect(s.votingClosesAt, isNotNull);
      expect(s.votingClosesAt!.toUtc(), DateTime.utc(2026, 11, 17, 8));
      expect(s.eligibleCount, 7);
      expect(s.version, 3);
      expect(s.myVotes, {301: 'approve'});
      expect(s.can['manage'], isTrue);
      expect(s.can['export_votes'], isTrue);
      expect(s.agenda.length, 5);
      final a = s.agenda.first;
      expect(a.item.ref, 'W-2026-00301');
      expect(a.myVote, 'approve');
      expect(a.approve, 4);
      expect(a.voted, 7);
      expect(a.votes.length, 7);
      expect(a.votes.first.note, 'With the budget cap');
      expect(a.decided, isFalse);
      expect(s.agenda[3].escalatedItemId, 900);
      // 302 · 303 · 304 are voting without my vote; 301 has one; 305 is withdrawn
      expect(s.pendingMyVotes, 3);
      AppConfig.lang = 'ar';
      expect(s.council?.name, 'مجلس قسم الحاسبات');
    });

    test('a closed session: decided agenda, results visible, minutes, no pending votes', () {
      final s = CouncilSession.fromJson(sessionJson(status: 'closed'));
      expect(s.isClosed, isTrue);
      expect(s.resultsVisible, isTrue);
      expect(s.minutes, isNotNull);
      expect(s.pendingMyVotes, 0);
      expect([for (final a in s.agenda) a.status], ['approved', 'rejected', 'no_quorum', 'postponed', 'withdrawn']);
      expect(s.agenda[0].decided, isTrue);
      expect(s.agenda[0].approvePct, closeTo(66.7, 0.1));
      expect(s.agenda[2].item.decision?.via, 'head');
    });
  });

  group('VoteTally', () {
    final base = CouncilSettings();

    test('majority, quorum and the percentage denominator', () {
      final ok = VoteTally.compute(approve: 4, reject: 2, abstain: 1, eligible: 7, s: base);
      expect(ok.outcome, 'approved');
      expect(ok.quorumMet, isTrue);
      expect(ok.needed, 4);
      expect(ok.approvePct, closeTo(66.67, 0.01));

      expect(VoteTally.compute(approve: 2, reject: 4, abstain: 0, eligible: 7, s: base).outcome, 'rejected');

      final nq = VoteTally.compute(approve: 2, reject: 1, abstain: 0, eligible: 10, s: base);
      expect(nq.outcome, 'no_quorum');
      expect(nq.quorumMet, isFalse);
      expect(nq.needed, 5);

      // abstentions in the denominator
      final abs = VoteTally.compute(approve: 4, reject: 2, abstain: 2, eligible: 8, s: CouncilSettings(abstainCounts: true));
      expect(abs.approvePct, closeTo(50, 0.01));
      // non-voters as abstentions
      final nv = VoteTally.compute(approve: 4, reject: 2, abstain: 0, eligible: 8, s: CouncilSettings(noVoteRule: 'abstain'));
      expect(nv.approvePct, closeTo(50, 0.01));
      // both
      final both = VoteTally.compute(approve: 4, reject: 2, abstain: 1, eligible: 10, s: CouncilSettings(abstainCounts: true, noVoteRule: 'abstain'));
      expect(both.approvePct, closeTo(40, 0.01));
      // nothing to divide
      expect(VoteTally.compute(approve: 0, reject: 0, abstain: 5, eligible: 5, s: base).approvePct, 0);
      // no members at all is never a quorum
      expect(VoteTally.compute(approve: 0, reject: 0, abstain: 0, eligible: 0, s: base).outcome, 'no_quorum');
    });

    test('tie rules: reject · chair (with and without a chair vote) · postpone', () {
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: CouncilSettings(tieRule: 'reject')).outcome, 'rejected');
      final chair = CouncilSettings(tieRule: 'chair');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: chair, chairVote: 'approve').outcome, 'approved');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: chair, chairVote: 'reject').outcome, 'rejected');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: chair).outcome, 'rejected');
      expect(VoteTally.compute(approve: 3, reject: 3, abstain: 0, eligible: 6, s: CouncilSettings(tieRule: 'postpone')).outcome, 'postponed');
      // quorum is checked before the tie rule
      expect(VoteTally.compute(approve: 1, reject: 1, abstain: 0, eligible: 10, s: CouncilSettings(tieRule: 'postpone')).outcome, 'no_quorum');
      // quorum percentage rounds up
      expect(VoteTally.compute(approve: 2, reject: 1, abstain: 0, eligible: 5, s: CouncilSettings(quorumPct: 51)).quorumMet, isTrue);
      expect(VoteTally.compute(approve: 2, reject: 0, abstain: 0, eligible: 5, s: CouncilSettings(quorumPct: 51)).quorumMet, isFalse);
    });
  });

  group('my votes', () {
    test('entries read both session shapes and group by session, soonest deadline first', () {
      final rows = [for (final x in myVotesJson()) MyVoteEntry.fromJson(x)];
      expect(rows[0].sessionId, 71);
      expect(rows[0].council?.name, 'CS Council');
      expect(rows[0].closesAt!.toUtc(), DateTime.utc(2026, 11, 17, 8));
      expect(rows[0].sessionLabel, 'Regular session');
      expect(rows[2].sessionId, 80);
      expect(rows[2].sessionKind, 'extraordinary');
      expect(rows[2].council?.name, 'Faculty Council');
      expect(rows[2].sessionLabel, 'Extraordinary: accreditation file');
      expect(rows[3].sessionId, isNull);

      final groups = groupMyVotes(rows);
      expect([for (final g in groups) g.sessionId], [80, 71, null]);
      final s71 = groups[1];
      expect([for (final e in s71.entries) e.agenda.id], [402, 401]); // agenda order
      expect(s71.pending, 1); // 402 already voted
      expect(groups[0].pending, 1);
    });
  });

  group('time helpers', () {
    test('countdown text', () {
      final now = DateTime(2026, 11, 15, 10);
      expect(countdownText(now.add(const Duration(days: 2, hours: 3)), now: now), '2 d 3 h');
      expect(countdownText(now.add(const Duration(hours: 3, minutes: 12)), now: now), '3 h 12 m');
      expect(countdownText(now.add(const Duration(minutes: 12, seconds: 5)), now: now), '12 m 05 s');
      expect(countdownText(now.subtract(const Duration(minutes: 1)), now: now), 'ended');
      AppConfig.lang = 'ar';
      expect(countdownText(now.add(const Duration(hours: 1)), now: now), '1 س 0 د');
    });

    test('next regular date clamps the day and rolls to the next month', () {
      expect(nextRegularDate(15, '10:30', from: DateTime(2026, 11, 3)), DateTime(2026, 11, 15, 10, 30));
      expect(nextRegularDate(15, '10:30', from: DateTime(2026, 11, 15, 10, 30)), DateTime(2026, 12, 15, 10, 30));
      expect(nextRegularDate(28, '09:00', from: DateTime(2026, 2, 1)), DateTime(2026, 2, 28, 9));
      expect(nextRegularDate(28, '09:00', from: DateTime(2026, 12, 29)), DateTime(2027, 1, 28, 9));
    });
  });
}
