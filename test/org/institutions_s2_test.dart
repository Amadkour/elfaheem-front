// Institutions S2 (councils, D-965 – D-970): the new payload fields (result chip, decision number, conflicts,
// named results, weights, meeting, review deadline, roster), the status labels in both languages, the weight cap
// and reminder rules, and the layout of the new widgets (results sheet, agenda row, roster card, write item,
// meeting step) through the layout harness. Payload shapes: docs/institutions/CONTRACT_S2.md.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_council_s2.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_session_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'gov_council_models_test.dart' show agendaJson, sessionJson;

Map<String, dynamic> _voter(int id, String name, String vote, {int weight = 1, String? note}) => {
      'user_id': id,
      'name': name,
      'user': {'id': id, 'name': name},
      'vote': vote,
      'weight': weight,
      'note': note,
      'at': '2026-11-20T09:3$id:00',
    };

Map<String, dynamic> resultsRow({String status = 'approved', String? result = 'approved_partial', bool visible = true, bool myCoi = false}) => {
      ...agendaJson(5, 2, status: status, approve: 3, reject: 1, abstain: 1),
      'decision_no': '1/2/2026',
      'template_key': null,
      'result': result,
      'coi_count': 1,
      'my_coi': myCoi,
      'council_written': true,
      'voters': visible
          ? [
              _voter(1, 'أ.د. سامي عبد الرحمن — a long member name that wraps', 'approve', weight: 2, note: 'Agreed, with the committee note attached'),
              _voter(2, 'Dr. Mona', 'approve'),
              _voter(3, 'Dr. Karim', 'approve'),
              _voter(4, 'Dr. Hany', 'reject', note: 'Needs another review'),
              _voter(5, 'Dr. Laila', 'abstain'),
            ]
          : null,
      'non_responders': visible
          ? [
              {'user_id': 6, 'name': 'Dr. Omar', 'user': {'id': 6, 'name': 'Dr. Omar'}, 'weight': 3},
            ]
          : null,
      'weights': visible ? {'approve_w': 4, 'reject_w': 1, 'abstain_w': 1, 'eligible_w': 9, 'voted_w': 6, 'needed_w': 5} : null,
    };

Map<String, dynamic> rosterJson({bool canEdit = true}) => {
      'council_id': 40,
      'total_weight': 6,
      'cap_pct': 40,
      'secretary_user_id': 4,
      'chair_user_id': 3,
      'items': [
        {'user_id': 3, 'user': {'id': 3, 'name': 'أ.د. رئيس القسم — a long chair name'}, 'weight': 2, 'is_head': true, 'is_chair': true, 'is_secretary': false, 'title': null},
        {'user_id': 4, 'user': {'id': 4, 'name': 'Dr. Secretary'}, 'weight': 1, 'is_head': false, 'is_chair': false, 'is_secretary': true, 'title': 'أمين'},
        {'user_id': 5, 'user': {'id': 5, 'name': 'Dr. Five'}, 'weight': 1},
        {'user_id': 6, 'user': {'id': 6, 'name': 'Dr. Six'}, 'weight': 1},
        {'user_id': 7, 'user': {'id': 7, 'name': 'Dr. Seven'}, 'weight': 1},
      ],
      'can': {'roster': canEdit},
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('payload parsing', () {
    test('agenda row: result, decision number, conflicts, voters, non-responders, weights', () {
      final a = AgendaItem.fromJson(resultsRow());
      expect(a.result, 'approved_partial');
      expect(a.chip, 'approved_partial');
      expect(a.decisionNo, '1/2/2026');
      expect(a.coiCount, 1);
      expect(a.myCoi, isFalse);
      expect(a.councilWritten, isTrue);
      expect(a.resultsVisible, isTrue);
      expect(a.voters!.length, 5);
      expect(a.voters!.first.weight, 2);
      expect(a.voters!.first.note, 'Agreed, with the committee note attached');
      expect(a.voters!.first.at, isNotNull);
      expect(a.nonResponders!.single.name, 'Dr. Omar');
      expect(a.nonResponders!.single.vote, isNull);
      expect(a.nonResponders!.single.weight, 3);
      expect(a.weights!.approveW, 4);
      expect(a.weights!.neededW, 5);
      final g = AgendaResultGroups.of(a);
      expect(g.approved.map((v) => v.userId), [1, 2, 3]);
      expect(g.rejected.map((v) => v.userId), [4]);
      expect(g.abstained.map((v) => v.userId), [5]);
      expect(g.notResponded.map((v) => v.userId), [6]);
    });

    test('hidden results, a live row and an older server', () {
      final hidden = AgendaItem.fromJson(resultsRow(status: 'voting', result: 'pending', visible: false, myCoi: true));
      expect(hidden.resultsVisible, isFalse);
      expect(hidden.voters, isNull);
      expect(hidden.weights, isNull);
      expect(hidden.myCoi, isTrue);
      expect(AgendaResultGroups.of(hidden).isEmpty, isTrue);
      final live = AgendaItem.fromJson({...resultsRow(status: 'voting', result: 'pending'), 'weights': {'approve_w': 1, 'reject_w': 0, 'abstain_w': 0, 'eligible_w': 4, 'voted_w': 1, 'needed_w': null}});
      expect(live.weights!.neededW, isNull);
      // no `result` key (older server): derived like the server's result_status
      final old = AgendaItem.fromJson(agendaJson(1, 1, status: 'approved', approve: 4));
      expect(old.result, isNull);
      expect(old.decisionNo, isNull);
      expect(old.chip, 'approved_full');
      expect(AgendaItem.fromJson(agendaJson(2, 2, status: 'approved', approve: 3, reject: 1)).chip, 'approved_partial');
      expect(AgendaItem.fromJson(agendaJson(3, 3, status: 'no_quorum')).chip, 'no_quorum');
      expect(AgendaItem.fromJson(agendaJson(4, 4, status: 'voting')).chip, 'pending');
      expect(AgendaItem.fromJson(agendaJson(5, 5, status: 'postponed')).chip, 'postponed');
      expect(AgendaItem.fromJson({...agendaJson(6, 6, status: 'rejected'), 'result': 'rejected'}).chip, 'rejected');
      expect(AgendaItem.fromJson({...agendaJson(7, 7), 'result': 'bogus'}).result, isNull);
    });

    test('council, session and settings: secretary, weights, meeting, review deadline', () {
      final c = Council.fromJson({
        ...sessionJson()['council'] as Map<String, dynamic>,
        'secretary': {'id': 4, 'name': 'Dr. Secretary'},
        'total_weight': 6,
        'settings': {'quorum_pct': 50, 'meeting_mode': 'online', 'meeting_location': null, 'meeting_link': 'https://meet.example.com/x'},
        'can': {'manage': true, 'roster': false, 'vote': true},
      });
      expect(c.secretary!.name, 'Dr. Secretary');
      expect(c.totalWeight, 6);
      expect(c.can['manage'], isTrue);
      expect(c.can['roster'], isFalse);
      final st = c.settings!;
      expect(st.meetingMode, 'online');
      expect(st.meetingLink, 'https://meet.example.com/x');
      final j = st.toJson();
      expect(j['meeting_mode'], 'online');
      expect(j.containsKey('meeting_location'), isTrue);
      expect(st.copy().toJson(), j);
      expect(CouncilSettings.fromJson({'meeting_mode': 'zoom'}).meetingMode, isNull);

      final s = CouncilSession.fromJson({
        ...sessionJson(),
        'review_deadline': '2026-11-25T10:00:00',
        'manual_reminded_at': '2026-11-20T08:00:00',
        'meeting': {'mode': 'online', 'location': null, 'link': null, 'cal_meeting_id': 12, 'room': true},
        'can': {'manage': true, 'remind': true, 'write_item': true, 'declare_conflict': true},
      });
      expect(s.reviewDeadline, isNotNull);
      expect(s.manualRemindedAt, isNotNull);
      expect(s.meeting!.calMeetingId, 12);
      expect(s.meeting!.room, isTrue);
      expect(s.meeting!.text, contains('غرفة اجتماعات المنصة'));
      expect(s.can['remind'] && s.can['write_item'] && s.can['declare_conflict'], isTrue);
      expect(const SessionMeeting(mode: 'in_person', location: 'Hall 3').text, 'حضورياً · Hall 3');
      expect(const SessionMeeting().text, '');
    });

    test('roster, the weight cap and the PUT body', () {
      final r = CouncilRoster.fromJson(rosterJson());
      expect(r.members.length, 5);
      expect(r.members.first.isChair, isTrue);
      expect(r.members[1].isSecretary, isTrue);
      expect(r.secretaryUserId, 4);
      expect(r.canEdit, isTrue);
      expect(r.capPct, 40);
      expect(CouncilRoster.fromJson(rosterJson(canEdit: false)).canEdit, isFalse);

      expect(weightCapUser({1: 1, 2: 1}), isNull); // equal weights are never capped
      expect(weightCapUser({1: 2, 2: 1, 3: 1, 4: 1}), isNull); // 2 / 5 = 40 %: allowed
      expect(weightCapUser({1: 3, 2: 1, 3: 1, 4: 1, 5: 1}), 1); // 3 / 7 > 40 %
      expect(weightCapUser({1: 1, 2: 3, 3: 1}), 2);
      expect(weightCapUser({}), isNull);

      expect(rosterBody(secretaryUserId: null), {'secretary_user_id': null});
      expect(rosterBody(weights: {3: 2, 4: 1}, secretaryUserId: 4), {
        'members': [
          {'user_id': 3, 'weight': 2},
          {'user_id': 4, 'weight': 1},
        ],
        'secretary_user_id': 4,
      });
      expect(weightCapText(r, 3), contains('أ.د. رئيس القسم'));
      AppConfig.lang = 'en';
      expect(weightCapText(r, 99), "No member may hold more than 40% of the council's total weight.");
    });

    test('remind once an hour', () {
      final now = DateTime(2026, 11, 20, 10, 0);
      expect(remindWait(null, now: now), isNull);
      expect(remindWait(DateTime(2026, 11, 20, 8, 59), now: now), isNull);
      expect(remindWait(DateTime(2026, 11, 20, 9, 30), now: now), const Duration(minutes: 30));
      AppConfig.lang = 'en';
      expect(remindWaitText(const Duration(minutes: 30)), contains('30 minutes'));
      expect(remindWaitText(const Duration(seconds: 20)), contains('1 minute'));
      expect(remindDoneText(0), 'Everyone has voted — nobody to remind');
      expect(remindDoneText(3), 'Reminded 3 members');
      AppConfig.lang = 'ar';
      expect(remindDoneText(3), 'ذُكِّر 3 أعضاء');
    });
  });

  group('labels', () {
    test('status chips in Arabic and English', () {
      expect(agendaResultLabel('approved_full'), 'موافقة بالإجماع');
      expect(agendaResultLabel('approved_partial'), 'موافقة بالأغلبية');
      expect(agendaResultLabel('rejected'), 'رفض');
      expect(agendaResultLabel('no_quorum'), 'لم يكتمل النصاب');
      expect(agendaResultLabel('pending'), 'قيد التصويت');
      expect(agendaResultLabel('postponed'), agendaStatusLabel('postponed'));
      AppConfig.lang = 'en';
      expect([for (final r in agendaResults) agendaResultLabel(r)], ['Approved unanimously', 'Approved by majority', 'Rejected', 'No quorum', 'Voting pending']);
      expect(meetingModeLabel('in_person'), 'In person');
      expect(meetingModeLabel(null), 'Not set');
    });

    test('every new server code has both texts', () {
      final ar = govCodeTexts();
      AppConfig.lang = 'en';
      final en = govCodeTexts();
      for (final code in const ['weight_cap', 'weight_invalid', 'not_staff_member', 'council_settings_invalid', 'remind_too_soon', 'conflict_declared', 'title_required', 'template_key_invalid']) {
        expect(ar[code], isNotNull, reason: code);
        expect(en[code], isNotNull, reason: code);
        expect(ar[code], isNot(en[code]), reason: code);
      }
      expect(eventKindLabel('conflict'), 'Declared a conflict of interest');
    });
  });

  group('layout', () {
    testWidgets('AgendaResultsView: visible, hidden and empty', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            AgendaResultsView(agenda: AgendaItem.fromJson(resultsRow())),
            AgendaResultsView(agenda: AgendaItem.fromJson(resultsRow(status: 'voting', result: 'pending', visible: false))),
            AgendaResultsView(agenda: AgendaItem.fromJson({...resultsRow(status: 'voting', result: 'pending'), 'voters': [], 'non_responders': [], 'coi_count': 0, 'decision_no': null})),
          ]),
        ),
      );
    });

    testWidgets('the results sheet opens from the chip', (tester) async {
      final a = AgendaItem.fromJson(resultsRow());
      await expectNoLayoutErrors(
        tester,
        () => Builder(builder: (context) => Center(child: AgendaResultChip(agenda: a, onTap: () => showAgendaResultsSheet(context, a)))),
        act: (tester) async {
          await tester.tap(find.byType(AgendaResultChip));
        },
      );
    });

    testWidgets('AgendaRow: chips, decision number, conflict action, excused, results button', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            AgendaRow(agenda: AgendaItem.fromJson(resultsRow()), sessionStatus: 'closed', showResult: true, onResults: () {}),
            AgendaRow(agenda: AgendaItem.fromJson(resultsRow(status: 'voting', result: 'pending', visible: false)), sessionStatus: 'voting', canVote: true, onVote: (v, n) async {}, onConflict: () {}),
            AgendaRow(agenda: AgendaItem.fromJson(resultsRow(status: 'voting', result: 'pending', myCoi: true)), sessionStatus: 'voting', manager: true, onResults: () {}, onPostpone: () {}, onEscalate: () {}),
            for (final r in const ['rejected', 'no_quorum', 'approved_full'])
              AgendaRow(agenda: AgendaItem.fromJson({...resultsRow(status: r == 'approved_full' ? 'approved' : r, result: r)}), sessionStatus: 'closed', showResult: true, compactResult: true),
          ]),
        ),
      );
    });

    testWidgets('CouncilRosterCard: editable, over the cap, read-only', (tester) async {
      final capped = rosterJson();
      (capped['items'] as List)[0] = {...(capped['items'] as List)[0] as Map<String, dynamic>, 'weight': 3};
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            CouncilRosterCard(roster: CouncilRoster.fromJson(rosterJson()), onSave: (w, s) {}),
            CouncilRosterCard(roster: CouncilRoster.fromJson(capped), onSave: (w, s) {}, busy: true),
            CouncilRosterCard(roster: CouncilRoster.fromJson(rosterJson(canEdit: false)), onSave: (w, s) {}),
            CouncilRosterCard(roster: CouncilRoster.fromJson({'council_id': 1, 'items': [], 'can': {'roster': true}}), onSave: (w, s) {}),
          ]),
        ),
      );
    });

    testWidgets('WriteAgendaItemBody and GovMeetingStep', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            WriteAgendaItemBody(onSave: (title, body) {}),
            GovMeetingStep(onChanged: (m, l, k) {}),
            GovMeetingStep(mode: 'in_person', location: 'قاعة مجلس الكلية — the long hall name', onChanged: (m, l, k) {}),
            GovMeetingStep(mode: 'online', link: 'http://insecure.example.com', onChanged: (m, l, k) {}),
            GovMeetingStep(mode: 'online', link: 'https://meet.example.com/abc', enabled: false, onChanged: (m, l, k) {}),
          ]),
        ),
      );
    });

    testWidgets('SessionHeader with the meeting, review deadline and last reminder', (tester) async {
      final s = CouncilSession.fromJson({
        ...sessionJson(),
        'review_deadline': '2026-11-25T10:00:00',
        'manual_reminded_at': '2026-11-20T08:00:00',
        'meeting': {'mode': 'in_person', 'location': 'قاعة الاجتماعات الكبرى بمبنى الإدارة — Main admin building hall', 'link': null, 'cal_meeting_id': 3, 'room': false},
      });
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: SessionHeader(session: s, now: DateTime(2026, 11, 20))));
    });
  });
}
