// The institutions workflow round (D-890 – D-893): parsing a forward of an approved item (council · outside party ·
// person with actions and answers), an external request's outside party, the forward body and its checks, the
// council's majority in the settings object and in the mirrored tally (no votes = no quorum).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gov_requests_test.dart' show sampleRequestItemJson;

/// An approved external request forwarded to a person (review + execute, review answered) and to an outside party,
/// as `GET …/items/{id}` returns it.
Map<String, dynamic> sampleForwardedItemJson() => {
      ...sampleRequestItemJson(),
      'status': 'approved',
      'pending_route': null,
      'external_source': {
        'name': 'وزارة التعليم العالي',
        'organization': 'الإدارة العامة للبعثات',
        'reference': 'MOHE-77',
        'contact': '+20 100 000 0000',
        'received_at': '2026-11-10T09:00:00',
      },
      'can': {'view': true, 'comment': true, 'forward': true},
      'routes': [
        {
          'id': 41,
          'item_id': 1,
          'from': {'dept': {'id': 3, 'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'CS Council', 'kind': 'council'}, 'user': {'id': 7, 'name': 'Dr. Omar'}},
          'to': {'dept': null, 'user': {'id': 9, 'name': 'سارة أحمد'}},
          'action': 'review',
          'status': 'pending',
          'due_at': '2026-11-20T09:00:00',
          'note': 'راجع الخطة ونفّذ',
          'created_at': '2026-11-13T09:00:00',
          'forward': {
            'kind': 'user',
            'actions': ['review', 'execute'],
            'open_actions': ['execute'],
            'external': null,
            'decision': {'outcome': 'approved', 'via': 'council', 'session_id': 5, 'tally': {'approve': 3, 'reject': 0, 'eligible': 3}},
            'responses': [
              {'action': 'review', 'answer': 'reviewed', 'note': 'الخطة سليمة', 'by': {'id': 9, 'name': 'سارة أحمد'}, 'at': '2026-11-14T10:00:00'},
            ],
          },
        },
        {
          'id': 42,
          'item_id': 1,
          'from': {'dept': {'id': 3, 'name_ar': 'مجلس قسم الحاسبات', 'name_en': 'CS Council', 'kind': 'council'}, 'user': {'id': 7, 'name': 'Dr. Omar'}},
          'to': {'dept': null, 'user': null},
          'action': 'info',
          'status': 'closed',
          'created_at': '2026-11-13T10:00:00',
          'forward': {
            'kind': 'external',
            'actions': [],
            'open_actions': [],
            'external': {'name': 'وزارة التعليم العالي', 'reference': 'OUT-12'},
            'decision': {'outcome': 'approved', 'via': 'council'},
            'responses': [],
          },
        },
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('forward of an approved item (D-890)', () {
    test('routes parse the forward block, the answers and what is still open', () {
      final it = WorkItem.fromJson(sampleForwardedItemJson());
      final person = it.routes.first, outside = it.routes.last;
      expect(person.forward!.kind, 'user');
      expect(person.forward!.actions, ['review', 'execute']);
      expect(person.forward!.openActions, ['execute']);
      expect(person.forward!.responses.single.by!.id, 9);
      expect(person.forward!.decision['via'], 'council');
      expect(person.forward!.answersFor('execute'), ['executed']);
      expect(person.forward!.answersFor('review'), isEmpty);
      expect(person.awaits(9), isTrue);
      expect(person.awaits(7), isFalse);
      expect(outside.forward!.kind, 'external');
      expect(outside.targetName, 'وزارة التعليم العالي');
      expect(outside.awaits(9), isFalse);
      expect(it.can['forward'], isTrue);
    });

    test('a route without a forward stays an ordinary route', () {
      final it = WorkItem.fromJson(sampleRequestItemJson());
      expect(it.routes.every((r) => r.forward == null), isTrue);
      expect(it.externalSource, isNull);
    });

    test('forwardBody sends only what the target needs', () {
      final due = DateTime.utc(2026, 11, 20, 9);
      final user = forwardBody(to: 'user', userId: 9, actions: ['approval', 'execute'], note: '  please  ', dueAt: due);
      expect(user['to'], 'user');
      expect(user['user_id'], 9);
      expect(user['actions'], ['approval', 'execute']);
      expect(user['note'], 'please');
      expect(user.containsKey('due_at'), isTrue);
      expect(user.containsKey('external'), isFalse);
      final ext = forwardBody(to: 'external', external: {'name': ' Ministry ', 'organization': '', 'reference': 'R-1'});
      expect(ext['external'], {'name': 'Ministry', 'reference': 'R-1'});
      expect(ext.containsKey('actions'), isFalse);
      final up = forwardBody(to: 'council', dueAt: due);
      expect(up.keys, ['to']);
    });

    test('forwardProblem mirrors the server checks', () {
      expect(forwardProblem(to: 'user', actions: ['review']), isNotNull); // no person
      expect(forwardProblem(to: 'user', userId: 9), govCodeTexts()['forward_actions_invalid']);
      expect(forwardProblem(to: 'user', userId: 9, actions: ['info', 'execute']), govCodeTexts()['forward_actions_invalid']);
      expect(forwardProblem(to: 'user', userId: 9, actions: ['info']), isNull);
      expect(forwardProblem(to: 'external', externalName: ' '), govCodeTexts()['external_name_required']);
      expect(forwardProblem(to: 'council'), isNull);
    });

    test('every answer a forwarded person may give has a label, in both languages', () {
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final a in forwardActions) {
          expect(forwardActionLabel(a), isNot(a));
          for (final ans in forwardAnswers[a]!) {
            expect(routeAnswerLabel(ans), isNot(ans));
          }
        }
        for (final k in forwardKinds) {
          expect(forwardKindLabel(k), isNot(k));
        }
      }
    });

    test('the new server codes have texts', () {
      for (final code in ['not_approved', 'forward_actions_invalid', 'forward_not_higher', 'external_name_required', 'external_conflict',
        'route_action_required', 'route_answer_invalid', 'route_answered', 'comment_required', 'due_in_past', 'council_no_members']) {
        expect(govCodeTexts()[code], isNotNull, reason: code);
      }
    });
  });

  group('external request (D-891)', () {
    test('the outside party is the source', () {
      final it = WorkItem.fromJson(sampleForwardedItemJson());
      expect(it.externalSource!.reference, 'MOHE-77');
      expect(it.externalSource!.label, 'وزارة التعليم العالي · الإدارة العامة للبعثات');
      expect(it.externalSource!.receivedAt, isNotNull);
    });
  });

  group('council majority and quorum (D-892, D-893)', () {
    test('majority_pct round-trips in the whole settings object', () {
      final s = CouncilSettings.fromJson({'quorum_pct': 50, 'majority_pct': 67});
      expect(s.majorityPct, 67);
      expect(s.toJson()['majority_pct'], 67);
      final simple = CouncilSettings.fromJson({'quorum_pct': 50});
      expect(simple.majorityPct, isNull);
      expect(simple.toJson().containsKey('majority_pct'), isTrue); // PUT replaces every field
    });

    test('the mirrored tally applies the majority and never decides without a vote', () {
      final twoThirds = CouncilSettings(majorityPct: 67);
      expect(VoteTally.compute(approve: 2, reject: 1, abstain: 0, eligible: 3, s: twoThirds).outcome, 'rejected');
      expect(VoteTally.compute(approve: 3, reject: 0, abstain: 0, eligible: 3, s: twoThirds).outcome, 'approved');
      expect(VoteTally.compute(approve: 2, reject: 1, abstain: 0, eligible: 3, s: CouncilSettings()).outcome, 'approved');
      expect(VoteTally.compute(approve: 0, reject: 0, abstain: 0, eligible: 3, s: CouncilSettings(quorumPct: 0)).outcome, 'no_quorum');
      expect(VoteTally.compute(approve: 0, reject: 0, abstain: 0, eligible: 0, s: CouncilSettings()).outcome, 'no_quorum');
    });
  });
}
