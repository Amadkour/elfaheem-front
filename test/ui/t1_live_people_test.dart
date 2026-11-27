// The host's roster (WP1, D-1950): GET …/people rows, the optimistic stage flip and its rollback, the server's
// nb.hand / nb.ask messages, and the paths.

import 'package:flutter_education_app/features/live/live_controls_api.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/live_room_people.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_data_route.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(String id,
        {int? user, bool guest = false, bool host = false, bool companion = false, bool priv = true, bool stage = false, bool hand = false}) =>
    {
      'identity': id,
      'user_id': user,
      'name': 'name $id',
      'guest': guest,
      'host': host,
      'companion': companion,
      'private': priv,
      'on_stage': stage,
      'hand_raised': hand,
    };

void main() {
  test('the paths', () {
    const ref = LiveRoomRef.session(41);
    expect(LiveControlsApi.peoplePath(ref), '/api/v1/live/session/41/people');
    expect(LiveControlsApi.stagePath(ref, 'student_5'), '/api/v1/live/session/41/participants/student_5/stage');
    expect(LiveControlsApi.stageBody(true), {'on': true});
  });

  test('rows parse, hidden people are counted, hosts and phones are not students', () async {
    final c = LivePeopleController(
      fetch: () async => [
        _row('teacher_1', host: true, priv: false),
        _row('student_5', user: 5, hand: true),
        _row('student_6', user: 6, stage: true),
        _row('guest:a', guest: true),
        _row('companion:x', companion: true, priv: false),
        {'name': 'no identity'},
      ],
      stage: (id, on) async => on,
    );
    await c.refresh();
    expect(c.items.length, 5);
    expect(c.studentsPresent, 2);
    expect(c.guestsPresent, 1);
    expect(c.handsUp, 1);
    expect(c.byUserId(5)?.identity, 'student_5');
    expect(c.byIdentity('teacher_1')!.canStage, isFalse);
    expect(c.byIdentity('student_5')!.canStage, isTrue);
    expect(c.byIdentity('companion:x')!.canStage, isFalse);
  });

  test('bring on stage flips at once and keeps what the server applied', () async {
    final calls = <(String, bool)>[];
    final c = LivePeopleController(
      fetch: () async => [_row('student_5', user: 5)],
      stage: (id, on) async {
        calls.add((id, on));
        return on;
      },
    );
    await c.refresh();
    expect(await c.setStage('student_5', true), isTrue);
    expect(c.byIdentity('student_5')!.onStage, isTrue);
    expect(calls, [('student_5', true)]);
    expect(await c.setStage('student_5', false), isTrue);
    expect(c.byIdentity('student_5')!.onStage, isFalse);
  });

  test('a failed stage call puts the row back', () async {
    final c = LivePeopleController(fetch: () async => [_row('student_5', user: 5)], stage: (id, on) async => throw StateError('x'));
    await c.refresh();
    expect(await c.setStage('student_5', true), isFalse);
    expect(c.byIdentity('student_5')!.onStage, isFalse);
    expect(c.staging, isEmpty);
  });

  test('a failed roster keeps the last one', () async {
    var fail = false;
    final c = LivePeopleController(
      fetch: () async {
        if (fail) throw StateError('x');
        return [_row('student_5', user: 5)];
      },
      stage: (id, on) async => on,
    );
    await c.refresh();
    fail = true;
    await c.refresh();
    expect(c.items.length, 1);
  });

  test('server signals: a hand, a question, junk', () {
    final h = parseLiveServerSignal({'type': 'hand', 'identity': 'student_5', 'raised': true, 'name': 'فيصل'});
    expect(h!.isHand, isTrue);
    expect(h.raised, isTrue);
    expect(h.name, 'فيصل');
    final a = parseLiveServerSignal({'type': 'ask', 'identity': 'student_5', 'text': ' ما الناتج؟ ', 'at': 5});
    expect(a!.isHand, isFalse);
    expect(a.text, 'ما الناتج؟');
    expect(parseLiveServerSignal({'type': 'ask', 'identity': 'student_5', 'text': ' '}), isNull);
    expect(parseLiveServerSignal({'type': 'hand', 'raised': true}), isNull);
    expect(parseLiveServerSignal({'type': 'zzz', 'identity': 'x'}), isNull);
  });

  test('the server topics route to the host signal handler', () {
    expect(liveDataRoute(kLiveServerHandTopic), LiveDataRoute.serverSignal);
    expect(liveDataRoute(kLiveServerAskTopic), LiveDataRoute.serverSignal);
  });
}
