// Partial answers of the assistant (Track E.8, lib/features/shared/rag/rag_chat.dart): `answer_partial` read from the
// query row, shown only while the question runs, replaced by the final answer; what counts as a visible change for
// the pending card; and the poll pacing while a draft grows.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({String state = 'running', String? stage = 'write', Object? partial, String answer = ''}) => {
      'id': 7,
      'state': state,
      'stage': stage,
      'question': 'How many devices?',
      'found': state == 'done' ? true : null,
      'answer': answer,
      'citations': const [],
      'follow_ups': const [],
      'generator': state == 'done' ? 'llm:qwen3' : null,
      'app': true,
      'answer_partial': partial,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('answer_partial is read while running and is a draft only then', () {
    final a = RagAnswer.fromJson(_row(partial: 'You can use your account on two'));
    expect(a.partial, 'You can use your account on two');
    expect(a.provisional, isTrue);
    expect(a.done, isFalse);

    final finished = RagAnswer.fromJson(_row(state: 'done', stage: null, partial: 'stale draft', answer: 'Two devices. [1]'));
    expect(finished.provisional, isFalse); // the final answer replaces it even if a stale field came along
    expect(finished.answer, 'Two devices. [1]');

    expect(RagAnswer.fromJson(_row(state: 'failed', partial: 'x y z')).provisional, isFalse);
  });

  test('an older server (no field), null, blank or a non-string: no draft', () {
    final old = _row()..remove('answer_partial');
    expect(RagAnswer.fromJson(old).partial, isNull);
    expect(RagAnswer.fromJson(old).provisional, isFalse);
    expect(RagAnswer.fromJson(_row(partial: null)).provisional, isFalse);
    expect(RagAnswer.fromJson(_row(partial: '   ')).provisional, isFalse);
    expect(RagAnswer.fromJson(_row(partial: 42)).partial, isNull);
  });

  test('ragAnswerChanged: stage, state and a growing or retracted draft count; the same draft does not', () {
    RagAnswer r({String state = 'running', String? stage = 'write', String? partial}) =>
        RagAnswer.fromJson(_row(state: state, stage: stage, partial: partial));
    expect(ragAnswerChanged(r(partial: 'You can use'), r(partial: 'You can use')), isFalse);
    expect(ragAnswerChanged(r(partial: 'You can use'), r(partial: 'You can use your')), isTrue);
    expect(ragAnswerChanged(r(partial: 'You can use'), r()), isTrue); // retracted
    expect(ragAnswerChanged(r(stage: 'retrieve'), r(stage: 'write')), isTrue);
    expect(ragAnswerChanged(r(), r(state: 'done', stage: null)), isTrue);
    expect(ragAnswerChanged(r(partial: '  '), r()), isFalse); // a blank draft is no draft
  });

  test('ragNextPoll: 1 s growing to 4 s, at most 1.5 s while a draft grows', () {
    var every = const Duration(seconds: 1);
    final seen = <int>[];
    for (var i = 0; i < 8; i++) {
      every = ragNextPoll(every);
      seen.add(every.inMilliseconds);
    }
    expect(seen, [1500, 2000, 2500, 3000, 3500, 4000, 4000, 4000]);
    expect(ragNextPoll(const Duration(seconds: 4), writing: true), const Duration(milliseconds: 1500));
    expect(ragNextPoll(const Duration(seconds: 1), writing: true), const Duration(seconds: 1));
  });
}
