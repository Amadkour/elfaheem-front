// The council screens' presentational widgets must lay out at 320×640 and 1400×900, Arabic and English, text
// scale 1.3: the council and session cards, the settings form (with the live rule preview), the session header,
// the agenda rows with every result outcome, the my-vote row, the voters, the minutes, the candidate picker, the
// session edit body, the new-session sheet body and the my-votes group card. Samples come from
// test/org/gov_council_models_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_council_settings.dart';
import 'package:flutter_education_app/features/org/governance/gov_councils_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_my_votes.dart';
import 'package:flutter_education_app/features/org/governance/gov_session_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/gov_council_models_test.dart' show agendaJson, minutesJson, myVotesJson, sessionJson;
import 'layout_harness.dart';

Council facultyCouncil() => Council.fromJson({
      'id': 60,
      'dept': {'id': 61, 'name_ar': 'مجلس الكلية', 'name_en': 'Faculty Council', 'kind': 'council'},
      'level': 'faculty',
      'chair': {'id': 1, 'name': 'أ.د. عميد الكلية — a long chair name that wraps'},
      'members': 23,
      'session_day': 1,
      'session_time': '12:00',
      'next_session': {'id': 90, 'scheduled_at': '2026-12-01T10:00:00', 'status': 'draft'},
      'settings': {'session_day': 1, 'session_time': '12:00', 'tie_rule': 'postpone', 'holidays': ['2026-11-05', '2026-12-25'], 'auto_agenda_rules': {'types': ['request'], 'category_ids': [3]}},
      'can': {'manage': true, 'vote': true},
    });

Council deptCouncil() => Council.fromJson(sessionJson()['council'] as Map<String, dynamic>);

void main() {
  testWidgets('GovCouncilCard and GovSessionCard', (tester) async {
    final voting = CouncilSession.fromJson(sessionJson());
    final closed = CouncilSession.fromJson(sessionJson(status: 'closed'));
    final noSettings = Council.fromJson({'id': 3, 'dept': {'id': 4, 'name_ar': 'مجلس قسم الفيزياء', 'name_en': 'Physics Department Council'}, 'members': 0});
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          GovCouncilCard(council: facultyCouncil(), openVotes: 120, onTap: () {}),
          GovCouncilCard(council: deptCouncil(), openVotes: 2, onTap: () {}),
          GovCouncilCard(council: noSettings),
          GovSessionCard(session: voting, onTap: () {}),
          GovSessionCard(session: closed, onTap: () {}),
          GovSessionCard(session: CouncilSession.fromJson({...sessionJson(status: 'draft'), 'title': null})),
        ]),
      ),
    );
  });

  testWidgets('GovCouncilSettingsForm: every section, editable and read-only, with the rule preview', (tester) async {
    final s = facultyCouncil().settings!;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          GovCouncilSettingsForm(
            settings: s,
            onSave: (_) {},
            members: const {1: 'أ.د. عميد الكلية', 2: 'Dr. Second Member with a long name'},
            categories: const {3: 'Study leave', 4: 'تظلم من نتيجة'},
            headName: 'أ.د. عميد الكلية',
          ),
          GovCouncilSettingsForm(settings: CouncilSettings(tieRule: 'chair', noVoteRule: 'abstain', abstainCounts: true), onSave: (_) {}, section: GovSettingsSection.session, busy: true),
          GovCouncilSettingsForm(settings: s, onSave: (_) {}, section: GovSettingsSection.rules, canEdit: false),
        ]),
      ),
      act: (tester) async {
        // the chair tie rule shows the chair-vote chips of the preview; a stepper tap re-computes it
        await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).first, warnIfMissed: false);
      },
    );
  });

  testWidgets('VoteResultView: compact and full, every outcome, live and undecided', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (final compact in [false, true]) ...[
              for (final o in voteOutcomes) VoteResultView(approve: 4, reject: 2, abstain: 1, eligible: 7, approvePct: 66.7, outcome: o, compact: compact),
              VoteResultView(approve: 0, reject: 0, abstain: 0, eligible: 0, compact: compact),
              VoteResultView(approve: 3, reject: 1, abstain: 0, eligible: 9, compact: compact, live: true),
              VoteResultView(approve: 12, reject: 3, abstain: 2, eligible: 10, compact: compact, outcome: 'approved'),
            ],
          ]),
        ),
      ),
    );
  });

  testWidgets('SessionHeader: voting, closed, draft, cancelled', (tester) async {
    final now = DateTime.utc(2026, 11, 16, 7, 30);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          SessionHeader(session: CouncilSession.fromJson(sessionJson()), now: now),
          SessionHeader(session: CouncilSession.fromJson(sessionJson(status: 'closed'))),
          SessionHeader(session: CouncilSession.fromJson({...sessionJson(status: 'draft'), 'title': null, 'notes': null, 'published_at': null, 'voting_opens_at': null, 'voting_closes_at': null, 'eligible_count': null})),
          SessionHeader(session: CouncilSession.fromJson({...sessionJson(status: 'cancelled'), 'council': null})),
        ]),
      ),
    );
  });

  testWidgets('AgendaRow: manager live, member voting, closed with voters, draft with a drag handle', (tester) async {
    final voting = CouncilSession.fromJson(sessionJson());
    final closed = CouncilSession.fromJson(sessionJson(status: 'closed'));
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          // manager, live results, can vote, has voted
          AgendaRow(agenda: voting.agenda[0], sessionStatus: 'voting', myVote: 'approve', showResult: true, showVoters: true, canVote: true, manager: true, onVote: (_, _) async {}, onOpenItem: () {}, onPostpone: () {}, onEscalate: () {}),
          // member, no results yet, not voted, busy
          AgendaRow(agenda: voting.agenda[1], sessionStatus: 'voting', canVote: true, voteBusy: true, onVote: (_, _) async {}),
          // decided elsewhere + escalated
          AgendaRow(agenda: voting.agenda[2], sessionStatus: 'voting', showResult: true, compactResult: true, manager: true, onPostpone: () {}),
          AgendaRow(agenda: voting.agenda[3], sessionStatus: 'voting', showResult: true, manager: true, canEscalate: false, onEscalate: () {}),
          // closed: every outcome with voters
          for (final a in closed.agenda) AgendaRow(agenda: a, sessionStatus: 'closed', myVote: closed.myVotes[a.id], showResult: true, showVoters: true, onOpenItem: () {}),
          // draft with a drag handle and remove
          AgendaRow(agenda: AgendaItem.fromJson(agendaJson(9, 1, status: 'pending')), sessionStatus: 'draft', manager: true, onRemove: () {}, dragHandle: const Icon(Icons.drag_indicator_rounded)),
        ]),
      ),
    );
  });

  testWidgets('MyVoteRow: empty enabled, voted enabled (note opens), voted disabled, not voted disabled', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MyVoteRow(value: null, enabled: true, onVote: (_, _) async {}),
            MyVoteRow(value: 'approve', enabled: true, onVote: (_, _) async {}, note: 'I agree, with the cap on the budget'),
            MyVoteRow(value: 'reject', enabled: false, onVote: null, busy: true),
            const MyVoteRow(value: null, enabled: false, onVote: null),
            MyVoteRow(value: 'abstain', enabled: true, withNote: false, onVote: (_, _) async {}),
          ]),
        ),
      ),
      act: (tester) async {
        await tester.tap(find.text(AppConfig.lang == 'ar' ? 'ملاحظة' : 'Note').first, warnIfMissed: false);
      },
    );
  });

  testWidgets('VotersList and GovMinutesView', (tester) async {
    final closed = CouncilSession.fromJson(sessionJson(status: 'closed'));
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            VotersList(votes: closed.agenda[0].votes),
            const SizedBox(height: 12),
            GovMinutesView(minutes: minutesJson(), textAr: 'محضر الجلسة\nالبند 1: موافقة', textEn: 'Minutes\nItem 1: approved'),
            const SizedBox(height: 12),
            const GovMinutesView(minutes: {}, textEn: 'Only a plain text came back from the server, long enough to wrap on a phone screen', title: 'Draft minutes'),
            const GovMinutesView(minutes: {}),
          ]),
        ),
      ),
    );
  });

  testWidgets('AgendaCandidatePicker, SessionEditBody and NewSessionSheetBody', (tester) async {
    final items = [for (var i = 1; i <= 8; i++) WorkItem.fromJson(agendaJson(500 + i, i)['item'] as Map<String, dynamic>)];
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            AgendaCandidatePicker(items: items, onConfirm: (_) {}, initial: {501, 503}),
            AgendaCandidatePicker(items: const [], onConfirm: (_) {}),
            SessionEditBody(title: 'جلسة نوفمبر', scheduledAt: DateTime(2026, 11, 15, 10), notes: 'Bring the lab reports', onSave: ({title, scheduledAt, notes}) {}),
            SessionEditBody(onSave: ({title, scheduledAt, notes}) {}, busy: true),
            NewSessionSheetBody(council: deptCouncil(), candidates: items.take(3).toList(), onCreate: ({required kind, required scheduledAt, title, required itemIds}) {}),
            NewSessionSheetBody(council: Council.fromJson({'id': 3, 'dept': {'id': 4, 'name_en': 'Physics Council'}, 'settings': {}}), candidates: const [], onCreate: ({required kind, required scheduledAt, title, required itemIds}) {}, busy: true),
          ]),
        ),
      ),
    );
  });

  testWidgets('MyVoteGroupCard: open with a countdown, ended, no session', (tester) async {
    final rows = [for (final x in myVotesJson()) MyVoteEntry.fromJson(x)];
    final groups = groupMyVotes(rows);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (final g in groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MyVoteGroupCard(group: g, now: DateTime.utc(2026, 11, 16, 7), votes: const {401: 'abstain'}, busy: const {403}, onVote: (_, _, _) async {}, onOpenSession: g.sessionId == null ? null : () {}, onOpenItem: (_) {}),
              ),
            MyVoteGroupCard(group: groups.first, now: DateTime.utc(2026, 12, 1)),
          ]),
        ),
      ),
    );
  });
}
