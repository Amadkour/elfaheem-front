// The chat answer's newer blocks (mode, chunks, actions, tool): parsing every mode, an older server, action
// resolution, the tool rows and the answer stream.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart' show SseEvent, SseParser;
import 'package:flutter_education_app/features/shared/rag/chat/assistant_page_context.dart';
import 'package:flutter_education_app/features/shared/rag/chat/rag_payload.dart';
import 'package:flutter_education_app/features/shared/rag/chat/rag_stream.dart';
import 'package:flutter_education_app/features/shared/rag/chat/rag_answer_extras.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> row(Map<String, dynamic> extra) =>
    {'id': 5, 'state': 'done', 'question': 'q', 'found': true, 'answer': 'a', 'citations': [], ...extra};

SseEvent ev(String name, Object data) => SseEvent(name: name, data: jsonEncode(data));

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('payload modes', () {
    test('an older server sends none of the blocks', () {
      final a = RagAnswer.fromJson(row({}));
      expect(a.mode, RagMode.generate);
      expect(a.chunks, isEmpty);
      expect(a.actions, isEmpty);
      expect(a.tool, isNull);
    });

    test('generate / rule / small_talk', () {
      expect(RagAnswer.fromJson(row({'mode': 'generate'})).mode, RagMode.generate);
      expect(RagAnswer.fromJson(row({'mode': 'small_talk'})).mode, RagMode.smallTalk);
      final rule = RagAnswer.fromJson(row({
        'mode': 'rule',
        'actions': [
          {'page_id': 'account.change_password', 'params': {}, 'label': {'ar': 'تغيير', 'en': 'Change'}}
        ],
      }));
      expect(rule.mode, RagMode.rule);
      expect(rule.actions.single.label('ar'), 'تغيير');
      expect(rule.actions.single.label('en'), 'Change');
    });

    test('retrieval chunks', () {
      final a = RagAnswer.fromJson(row({
        'mode': 'retrieval',
        'generator': 'none:retrieval',
        'chunks': [
          {'text': 'Devices …', 'document': 'Terms', 'document_id': 7, 'page_from': 3, 'page_to': 4, 'section': 'Devices'},
          {'text': '', 'document': 'empty is dropped'},
          {'text': 'No pages'},
        ],
      }));
      expect(a.mode, RagMode.retrieval);
      expect(a.chunks.length, 2);
      expect(a.chunks.first.document, 'Terms');
      expect(a.chunks.first.documentId, 7);
      expect(a.chunks.first.pageLabel('en'), 'p. 3–4');
      expect(a.chunks.first.pageLabel('ar'), 'ص 3–4');
      expect(a.chunks.last.pageLabel('en'), '');
    });

    test('a gate refusal has no chunks', () {
      final a = RagAnswer.fromJson(row({'mode': 'retrieval', 'found': false, 'chunks': [], 'follow_ups': ['x']}));
      expect(a.found, false);
      expect(a.chunks, isEmpty);
      expect(a.followUps, ['x']);
    });

    test('tool and refused', () {
      final a = RagAnswer.fromJson(row({
        'mode': 'tool',
        'tool': {'name': 'my_subscriptions', 'data': {'items': [1, 2]}},
      }));
      expect(a.tool!.name, 'my_subscriptions');
      expect(a.tool!.refused, false);
      expect(RagAnswer.fromJson(row({'mode': 'tool', 'tool': {'name': 'refused'}})).tool!.refused, true);
      expect(RagAnswer.fromJson(row({'mode': 'tool', 'tool': 'garbage'})).tool, isNull);
    });

    test('garbage blocks never throw', () {
      final a = RagAnswer.fromJson(row({'mode': 7, 'chunks': 'x', 'actions': [1, null, {}], 'tool': []}));
      expect(a.mode, RagMode.generate);
      expect(a.chunks, isEmpty);
      expect(a.actions, isEmpty);
    });

    test('extras survive a rating copy', () {
      final a = RagAnswer.fromJson(row({'mode': 'retrieval', 'chunks': [{'text': 't'}]}));
      // ragAnswerRated is in rag_learning.dart; its copy carries `extras`
      expect(a.extras.chunks.length, 1);
    });
  });

  group('actions', () {
    RagAction act(String id, [Map<String, Object?> p = const {}, int? org]) =>
        RagAction(pageId: id, params: p, labelAr: 'ع', labelEn: 'E', orgId: org);

    test('a known id resolves through AppRoutes.location', () {
      expect(act('account.change_password').location, '/change-password');
      expect(act('course', {'courseId': 12}).location, '/courses/12');
      expect(act('account.subscription').location, '/subscription');
    });

    test('an unknown id is hidden', () => expect(act('no.such.page').location, isNull));

    test('a missing parameter is hidden', () {
      expect(act('course').location, isNull);
      expect(act('course', {'courseId': ''}).location, isNull);
    });

    test('a home tab id resolves to the tab URL', () {
      expect(act('home.student/my_courses').location, '/dashboard/my-courses');
      expect(act('nothome/my_courses').location, isNull);
      expect(act('account.edit/x').location, isNull);
    });

    test('visible actions: resolved, labelled, at most four', () {
      final list = [
        act('no.such.page'),
        act('course'),
        act('calendar'),
        act('inbox'),
        act('account.edit'),
        act('account.profile'),
        act('account.subscription'),
        const RagAction(pageId: 'exports'),
      ];
      final shown = ragVisibleActions(list);
      expect(shown.map((a) => a.pageId), ['calendar', 'inbox', 'account.edit', 'account.profile']);
    });

    test('the label falls back to the other language, then the page description', () {
      expect(const RagAction(pageId: 'calendar', labelAr: 'تقويم').label('en'), 'تقويم');
      expect(const RagAction(pageId: 'calendar').label('en'), isNotEmpty);
      expect(const RagAction(pageId: 'no.such.page').label('en'), '');
    });

    test('org_id is read', () {
      final a = RagAction.fromJson({'page_id': 'course', 'params': {'courseId': 12}, 'label': {'ar': 'a', 'en': 'e'}, 'org_id': 5});
      expect(a.orgId, 5);
      expect(a.location, '/courses/12');
    });
  });

  group('tool rows', () {
    final now = DateTime.utc(2026, 11, 4, 10);

    test('subscriptions: plan, end date and days left', () {
      final rows = ragSubscriptionRows({
        'items': [
          {'plan': 'Pro', 'ends_at': '2026-11-14T00:00:00'},
          {'name': {'ar': 'خطة', 'en': 'Plan B'}, 'end_date': '2026-11-01'},
          {'junk': true},
        ]
      }, now);
      expect(rows.length, 2);
      expect(rows[0].title, 'Pro');
      expect(rows[0].detail, contains('10 days left'));
      expect(rows[0].warn, false);
      expect(rows[1].title, 'Plan B');
      expect(rows[1].detail, startsWith('Ended'));
      expect(rows[1].warn, true);
    });

    test('subscriptions: a single object without items', () {
      final rows = ragSubscriptionRows({'plan': 'Free', 'expires_at': '2026-11-06T00:00:00Z'}, now);
      expect(rows.single.warn, true); // 2 days left
    });

    test('courses: progress as a fraction or a percentage', () {
      final rows = ragCourseRows({
        'courses': [
          {'title': 'Math', 'progress': 0.4},
          {'name': 'Physics', 'percent': 75},
          {'title': ''},
        ]
      });
      expect(rows.map((r) => r.title), ['Math', 'Physics']);
      expect(rows[0].progress, 0.4);
      expect(rows[1].progress, 0.75);
      expect(rows[1].detail, '75%');
    });

    test('schedule: the next items with times', () {
      final rows = ragScheduleRows({
        'items': [
          {'title': 'Algebra', 'starts_at': '2026-11-05T09:00:00'},
          {'course': 'No time'},
        ]
      });
      expect(rows.length, 2);
      expect(rows[0].detail, isNotEmpty);
      expect(rows[1].detail, '');
    });

    test('progress: overall bar first', () {
      final rows = ragProgressRows({'overall': 50, 'courses': [{'title': 'A', 'progress': 10}]});
      expect(rows.length, 2);
      expect(rows[0].progress, 0.5);
    });

    test('empty or malformed data gives no rows and never throws', () {
      expect(ragSubscriptionRows({}, now), isEmpty);
      expect(ragCourseRows({'items': 'x'}), isEmpty);
      expect(ragScheduleRows({'items': [1, null]}), isEmpty);
      expect(ragProgressRows({}), isEmpty);
    });

    test('at most five rows', () {
      final rows = ragCourseRows({'items': [for (var i = 0; i < 9; i++) {'title': 'c$i'}]});
      expect(rows.length, kRagToolMaxRows);
    });

    test('tool kinds', () {
      expect(ragToolKind('my_subscriptions'), RagToolKind.subscriptions);
      expect(ragToolKind('my_courses'), RagToolKind.courses);
      expect(ragToolKind('my_schedule'), RagToolKind.schedule);
      expect(ragToolKind('my_progress'), RagToolKind.progress);
      expect(ragToolKind('weather'), RagToolKind.other);
    });
  });

  group('page context', () {
    test('the starter question', () {
      expect(ragPageQuestion(pageId: 'calendar', pageTitle: 'Schedule'), 'Ask about this page: Schedule');
      expect(ragPageQuestion(pageId: 'calendar'), 'Ask about this page: calendar');
      AppConfig.lang = 'ar';
      expect(ragPageQuestion(pageId: 'x', pageTitle: 'الجدول'), 'اسأل عن هذه الصفحة: الجدول');
    });
  });

  group('SSE state', () {
    test('delta appends, replace rewrites, done carries the payload', () {
      final s = RagStreamState();
      expect(s.apply(ev('delta', {'text': 'Hel'})), true);
      expect(s.apply(ev('delta', {'text': 'lo'})), true);
      expect(s.text, 'Hello');
      expect(s.apply(ev('delta', {'text': '', 'replace': 'Hi there'})), true);
      expect(s.text, 'Hi there');
      expect(s.apply(ev('ping', {})), false);
      expect(s.finished, false);
      s.apply(ev('done', {'id': 5, 'state': 'done'}));
      expect(s.finished, true);
      expect(s.finalPayload!['id'], 5);
      expect(s.apply(ev('delta', {'text': 'late'})), false); // nothing after the end
      expect(s.text, 'Hi there');
    });

    test('error', () {
      final s = RagStreamState()..apply(ev('error', {'code': 'stream_timeout', 'message': 'm'}));
      expect(s.errorCode, 'stream_timeout');
      expect(s.finalPayload, isNull);
      expect(RagStreamState()..apply(ev('error', {})), isA<RagStreamState>().having((x) => x.errorCode, 'code', 'query_failed'));
    });

    test('frames split anywhere parse the same through SseParser', () {
      const wire = ': ping\n\nevent: delta\ndata: {"text":"Hel"}\n\nevent: delta\ndata: {"text":"lo"}\n\n: ping\n\nevent: done\ndata: {"id":9,"state":"done"}\n\n';
      for (final cut in [1, 7, 20, 41, wire.length - 3]) {
        final p = SseParser();
        final s = RagStreamState();
        for (final chunk in [wire.substring(0, cut), wire.substring(cut)]) {
          for (final e in p.feed(chunk)) {
            s.apply(e);
          }
        }
        expect(s.text, 'Hello', reason: 'cut at $cut');
        expect(s.finalPayload!['id'], 9);
      }
    });
  });

  group('stream client', () {
    http.Client streaming(int status, List<String> chunks, {String type = 'text/event-stream', bool hang = false}) =>
        MockClient.streaming((req, body) async {
          final ctl = StreamController<List<int>>();
          () async {
            for (final c in chunks) {
              ctl.add(utf8.encode(c));
              await Future<void>.delayed(Duration.zero);
            }
            if (!hang) await ctl.close();
          }();
          return http.StreamedResponse(ctl.stream, status, headers: {'content-type': type});
        });

    RagStreamClient client(http.Client c, {Duration stall = const Duration(seconds: 5)}) =>
        RagStreamClient(clientFactory: () => c, token: () async => 't', baseUrl: 'https://x.test', stallAfter: stall);

    test('delivers the text live and the final payload', () async {
      final texts = <String>[];
      final r = await client(streaming(200, [
        'event: delta\ndata: {"text":"Hel"}\n\n',
        'event: delta\ndata: {"text":"lo"}\n\nevent: do',
        'ne\ndata: {"id":5,"state":"done","answer":"Hello"}\n\n',
      ])).follow(5, onText: texts.add);
      expect(texts, ['Hel', 'Hello']);
      expect(r!['answer'], 'Hello');
    });

    test('sends the bearer token and asks for an event stream', () async {
      http.BaseRequest? seen;
      final c = MockClient.streaming((req, body) async {
        seen = req;
        return http.StreamedResponse(Stream.value(utf8.encode('event: done\ndata: {"id":1}\n\n')), 200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'});
      });
      await client(c).follow(1, onText: (_) {});
      expect(seen!.url.toString(), 'https://x.test/api/v1/rag/queries/1/stream');
      expect(seen!.headers['Authorization'], 'Bearer t');
      expect(seen!.headers['Accept'], 'text/event-stream');
    });

    test('an older server (404), a wrong content type and an error event all mean "poll"', () async {
      expect(await client(streaming(404, [])).follow(1, onText: (_) {}), isNull);
      expect(await client(streaming(200, ['{}'], type: 'application/json')).follow(1, onText: (_) {}), isNull);
      expect(await client(streaming(200, ['event: error\ndata: {"code":"query_failed"}\n\n'])).follow(1, onText: (_) {}), isNull);
    });

    test('a stream that ends without done means "poll"', () async {
      final texts = <String>[];
      expect(await client(streaming(200, ['event: delta\ndata: {"text":"a"}\n\n'])).follow(1, onText: texts.add), isNull);
      expect(texts, ['a']);
    });

    test('a stalled stream gives up', () async {
      final r = await client(streaming(200, [': ping\n\n'], hang: true), stall: const Duration(milliseconds: 80)).follow(1, onText: (_) {});
      expect(r, isNull);
    });

    test('a connection failure means "poll"', () async {
      final c = MockClient.streaming((req, body) async => throw http.ClientException('down'));
      expect(await client(c).follow(1, onText: (_) {}), isNull);
    });
  });

  group('RagApi.waitForLive', () {
    test('an answer already done is returned without opening a stream', () async {
      var opened = false;
      final api = RagApi();
      final r = await api.waitForLive(5, row({}), stream: RagStreamClient(clientFactory: () {
        opened = true;
        return MockClient.streaming((_, _) async => http.StreamedResponse(const Stream.empty(), 404));
      }));
      expect(r.ok, true);
      expect(opened, false);
    });

    test('the streamed final payload is the result and the draft reaches onUpdate', () async {
      final updates = <RagAnswer>[];
      final c = MockClient.streaming((req, body) async => http.StreamedResponse(
          Stream.value(utf8.encode(
              'event: delta\ndata: {"text":"Hi"}\n\nevent: done\ndata: ${jsonEncode(row({'answer': 'Hi', 'mode': 'retrieval', 'chunks': [{'text': 'c'}]}))}\n\n')),
          200,
          headers: {'content-type': 'text/event-stream'}));
      final r = await RagApi().waitForLive(5, row({'state': 'queued'}),
          onUpdate: updates.add, stream: RagStreamClient(clientFactory: () => c, token: () async => 't', baseUrl: 'https://x.test'));
      expect(updates.single.partial, 'Hi');
      expect(updates.single.provisional, true);
      final a = RagAnswer.fromJson(r.map);
      expect(a.done, true);
      expect(a.chunks.length, 1);
    });
  });

  group('real server tool shapes', () {
    final now = DateTime.utc(2026, 11, 4, 10);
    test('subscriptions: platform plans and course subscriptions', () {
      final rows = ragSubscriptionRows({
        'platform': [
          {'kind': 'platform', 'plan_code': 'pro', 'plan_name': {'ar': 'احترافي', 'en': 'Pro'}, 'status': 'active', 'starts_at': '2026-10-01T00:00:00Z', 'ends_at': '2026-11-10T00:00:00Z', 'days_left': 6}
        ],
        'has_active': true,
        'courses': [
          {'course_id': 3, 'title': {'ar': 'رياضيات', 'en': 'Math'}, 'plan': 'x', 'ends_at': '2026-10-20T00:00:00Z', 'expired': true, 'days_left': null}
        ],
        'now': '2026-11-04T10:00:00Z',
      }, now);
      expect(rows.map((r) => r.title), ['Pro', 'Math']);
      expect(rows[0].detail, contains('6 days left'));
      expect(rows[0].warn, true);
      expect(rows[1].warn, true);
    });
    test('courses: teacher and null progress', () {
      final rows = ragCourseRows({
        'courses': [
          {'course_id': 1, 'title': {'ar': 'أ', 'en': 'A'}, 'teacher': 'Dr X', 'progress': 40},
          {'course_id': 2, 'title': {'ar': 'ب', 'en': 'B'}, 'teacher': null, 'progress': null},
        ],
        'org_id': null,
      });
      expect(rows[0].detail, 'Dr X · 40%');
      expect(rows[0].progress, 0.4);
      expect(rows[1].progress, isNull);
    });
    test('schedule items with course and location', () {
      final rows = ragScheduleRows({
        'items': [
          {'source': 'session', 'title': 'Lesson 1', 'title_auto': false, 'course': 'Math', 'starts_at': '2026-11-05T09:00:00Z', 'ends_at': '2026-11-05T10:00:00Z', 'mode': 'online', 'location': 'Room 2'}
        ],
        'truncated': false,
      });
      expect(rows.single.detail, allOf(contains('Math'), contains('Room 2')));
    });
    test('progress: done/total and the next exam', () {
      final rows = ragProgressRows({
        'courses': [
          {'course_id': 1, 'title': {'ar': 'أ', 'en': 'A'}, 'done': 3, 'total': 10, 'progress': 30, 'last_activity': null,
           'upcoming_exams': [{'exam_id': 1, 'title': 'Final', 'starts_at': '2026-11-20T09:00:00Z'}]}
        ]
      });
      expect(rows.single.detail, startsWith('3 / 10 · Exam: Final'));
      expect(rows.single.progress, 0.3);
    });
  });
}
