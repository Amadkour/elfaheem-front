// Chat sessions (Track E.5, lib/features/rag/rag_chat.dart): the conversation model, the title a new chat
// gets from its first question, the retention notice (ar / en), relative times, the deep-link module, the API
// bodies / query strings through a recording client, and the older-server decision.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what RagApi hands to ApiClient (a singleton; this stands in through its interface).
class _RecordingApi implements ApiClient {
  final calls = <(Symbol, String, Map<String, dynamic>?, Object?)>[];
  Map<String, dynamic> reply = {};
  Object? error;

  @override
  dynamic noSuchMethod(Invocation i) {
    final path = i.positionalArguments.isEmpty ? '' : '${i.positionalArguments.first}';
    calls.add((i.memberName, path, i.namedArguments[#queryParams] as Map<String, dynamic>?, i.namedArguments[#body]));
    if (error != null) return Future<dynamic>.error(error!);
    return Future<dynamic>.value(reply);
  }
}

Map<String, dynamic> _conv({int id = 7, String title = 'Refund policy', int turns = 3}) => {
      'id': id,
      'title': title,
      'scope': {'app': true, 'org_id': 4, 'course_id': null},
      'created_at': '2026-10-27T08:00:00',
      'last_at': '2026-10-28T09:30:00Z',
      'turns': turns,
    };

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  group('conversation model', () {
    test('parses the list row: scope, times (naive UTC and Z), turns', () {
      final c = RagConversation.fromJson(_conv());
      expect(c.id, 7);
      expect(c.title, 'Refund policy');
      expect(c.app, isTrue);
      expect(c.orgId, 4);
      expect(c.courseId, isNull);
      expect(c.turns, 3);
      expect(c.createdAt, DateTime.utc(2026, 10, 27, 8));
      expect(c.lastAt, DateTime.utc(2026, 10, 28, 9, 30));
      expect(c.displayTitle, 'Refund policy');
    });

    test('an untitled conversation shows "New chat" in the UI language; last_at falls back to created_at', () {
      final c = RagConversation.fromJson({'id': 1, 'title': '', 'created_at': '2026-10-27T08:00:00'});
      expect(c.displayTitle, 'New chat');
      expect(c.lastAt, DateTime.utc(2026, 10, 27, 8));
      AppConfig.lang = 'ar';
      expect(c.displayTitle, 'محادثة جديدة');
      expect(RagConversation.fromJson({'id': 2}).lastAt, isNull);
    });

    test('copyWith keeps the scope', () {
      final c = RagConversation.fromJson(_conv()).copyWith(title: 'Fees', turns: 4);
      expect((c.id, c.title, c.turns, c.orgId, c.app), (7, 'Fees', 4, 4, true));
    });

    test('the list and retention_days of the conversations call; has_more of a messages page', () {
      final r = EngineResult.ok({'items': [_conv(), _conv(id: 8, title: 'Devices')], 'retention_days': 90});
      expect(RagApi.conversationItems(r).map((c) => c.id).toList(), [7, 8]);
      expect(RagApi.retentionDays(r), 90);
      expect(RagApi.retentionDays(EngineResult.ok({'items': []})), isNull);
      expect(RagApi.hasMore(EngineResult.ok({'items': [], 'has_more': true})), isTrue);
      expect(RagApi.hasMore(EngineResult.ok({'items': []})), isFalse);
    });

    test('the answer row carries conversation_id and a curated citation its kind and deep link', () {
      final a = RagAnswer.fromJson({
        'id': 3, 'state': 'done', 'question': 'q', 'answer': 'a [1]', 'conversation_id': 7, 'generator': 'qa',
        'citations': [
          {'n': 1, 'document_id': 0, 'title': 'How do I download a lecture?', 'kind': 'qa', 'quote': 'Open…', 'deep_link': '/downloads'},
        ],
      });
      expect(a.conversationId, 7);
      expect(a.citations.single.isQa, isTrue);
      expect(a.citations.single.deepLink, '/downloads');
      expect(RagAnswer.fromJson({'id': 3}).conversationId, isNull);
      expect(RagCitation.fromJson({'n': 1, 'document_id': 2, 'deep_link': '  '}).deepLink, isNull);
    });
  });

  group('title from the first question', () {
    test('short questions are the title; whitespace collapses', () {
      expect(conversationTitleFrom('  How do I   subscribe\nto a course? '), 'How do I subscribe to a course?');
    });

    test('long questions are cut at a word with an ellipsis, at most 40 characters', () {
      final t = conversationTitleFrom('How do I change the device that is linked to my account after I bought a new phone?');
      expect(t.length, lessThanOrEqualTo(40));
      expect(t, endsWith('…'));
      expect(t, startsWith('How do I change the device'));
      expect(t.contains('  '), isFalse);
      final ar = conversationTitleFrom('كيف أغيّر الجهاز المرتبط بحسابي بعد أن اشتريت هاتفاً جديداً من المتجر؟');
      expect(ar.length, lessThanOrEqualTo(40));
      expect(ar, endsWith('…'));
    });

    test('a single long word is cut hard', () {
      final t = conversationTitleFrom('x' * 100);
      expect(t.length, 40);
      expect(t, endsWith('…'));
    });

    test('an empty question gets "New chat" in the asked language', () {
      expect(conversationTitleFrom('   ', lang: 'en'), 'New chat');
      expect(conversationTitleFrom('', lang: 'ar'), 'محادثة جديدة');
    });
  });

  group('retention text', () {
    test('ar / en with the number of days; empty when the server keeps chats', () {
      expect(retentionText(90, 'en'), 'Chats are deleted automatically after 90 days');
      expect(retentionText(30, 'ar'), 'تُحذف المحادثات تلقائياً بعد 30 يوماً');
      expect(retentionText(null, 'en'), '');
      expect(retentionText(0, 'ar'), '');
    });
  });

  group('relative time', () {
    final now = DateTime.utc(2026, 10, 28, 12);
    test('just now · minutes · hours · yesterday · days · the date', () {
      expect(ragRelativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
      expect(ragRelativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(ragRelativeTime(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(ragRelativeTime(now.subtract(const Duration(hours: 30)), now: now), 'Yesterday');
      expect(ragRelativeTime(now.subtract(const Duration(days: 4)), now: now), '4 days ago');
      expect(ragRelativeTime(now.subtract(const Duration(days: 20)), now: now), contains('2026'));
      expect(ragRelativeTime(null, now: now), '');
      AppConfig.lang = 'ar';
      expect(ragRelativeTime(now.subtract(const Duration(minutes: 5)), now: now), 'منذ 5 د');
      expect(ragRelativeTime(now.subtract(const Duration(hours: 30)), now: now), 'أمس');
    });
  });

  group('deep link', () {
    test('a route loses its leading slash, a feature key stays, blanks are nothing', () {
      expect(ragDeepLinkModule('/downloads'), 'downloads');
      expect(ragDeepLinkModule('profile'), 'profile');
      expect(ragDeepLinkModule(' /calendar '), 'calendar');
      expect(ragDeepLinkModule('/'), isNull);
      expect(ragDeepLinkModule(''), isNull);
      expect(ragDeepLinkModule(null), isNull);
      // the web has no Downloads page: no "Open" button for it there
      expect(ragDeepLinkModule('/downloads', downloadsAvailable: false), isNull);
      expect(ragDeepLinkModule('/calendar', downloadsAvailable: false), 'calendar');
    });
  });

  group('stage and codes', () {
    test('the qa stage has a label; the session codes have texts', () {
      expect(ragStageText('qa'), 'Answered from the curated Q&A');
      AppConfig.lang = 'ar';
      expect(ragStageText('qa'), 'أُجيب من الأسئلة والأجوبة المعتمدة');
      expect(ragCodeText('conversation_not_found', 'x'), 'هذه المحادثة لم تعد موجودة');
      expect(ragCodeText('not_owner', 'x'), isNot('x'));
    });
  });

  group('API calls', () {
    late _RecordingApi client;
    late RagApi api;
    setUp(() {
      client = _RecordingApi();
      api = RagApi(client);
    });

    test('conversations: scope, limit and the before cursor as query parameters', () async {
      await api.conversations(app: true, orgId: 4, limit: 10, before: 99);
      final (m, path, q, _) = client.calls.single;
      expect(m, #get);
      expect(path, '/api/v1/rag/conversations');
      expect(q, {'app': true, 'org_id': 4, 'limit': 10, 'before': 99});
      client.calls.clear();
      await api.conversations(courseId: 12);
      expect(client.calls.single.$3, {'app': false, 'course_id': 12, 'limit': 30});
    });

    test('create: scope and a trimmed title (none when blank)', () async {
      await api.createConversation(app: true, orgId: 4, title: '  Refunds ');
      final (m, path, _, body) = client.calls.single;
      expect((m, path), (#post, '/api/v1/rag/conversations'));
      expect(body, {'app': true, 'org_id': 4, 'title': 'Refunds'});
      client.calls.clear();
      await api.createConversation(courseId: 3, title: ' ');
      expect(client.calls.single.$4, {'app': false, 'course_id': 3});
    });

    test('rename · delete · messages', () async {
      await api.renameConversation(7, ' Fees ');
      await api.deleteConversation(7);
      await api.messages(7, before: 41, limit: 20);
      expect(client.calls.map((c) => (c.$1, c.$2)).toList(), [
        (#patch, '/api/v1/rag/conversations/7'),
        (#delete, '/api/v1/rag/conversations/7'),
        (#get, '/api/v1/rag/conversations/7/messages'),
      ]);
      expect(client.calls[0].$4, {'title': 'Fees'});
      expect(client.calls[2].$3, {'limit': 20, 'before': 41});
    });

    test('ask sends conversation_id only when given (an older server ignores it); the rating sends the comment', () async {
      await api.ask('q', app: true, conversationId: 7);
      expect(client.calls.single.$4, {'question': 'q', 'app': true, 'conversation_id': 7});
      client.calls.clear();
      await api.ask('q', orgId: 4);
      expect(client.calls.single.$4, {'question': 'q', 'org_id': 4});
      client.calls.clear();
      await api.rate(5, helpful: false, comment: 'wrong article');
      expect(client.calls.single.$4, {'helpful': false, 'comment': 'wrong article'});
    });
  });

  group('older server', () {
    test('a bare 404 / 405 on the conversations routes keeps the flat history; a coded error or success means sessions', () {
      expect(ragSessionsSupported(EngineResult.fail(404, null, 'Not Found')), isFalse);
      expect(ragSessionsSupported(EngineResult.fail(405, null, 'Method Not Allowed')), isFalse);
      expect(ragSessionsSupported(EngineResult.ok({'items': []})), isTrue);
      expect(ragSessionsSupported(EngineResult.fail(403, 'not_owner', 'x')), isTrue);
      expect(ragSessionsSupported(EngineResult.fail(404, 'conversation_not_found', 'x')), isTrue);
      expect(ragSessionsSupported(EngineResult.fail(403, 'orgs_disabled', 'x')), isTrue);
    });

    test('the recording client reports a bare 404 as unavailable through engineCall', () async {
      final client = _RecordingApi()..error = const ApiException(statusCode: 404, message: 'Not Found');
      final r = await RagApi(client).conversations(app: true);
      expect(r.unavailable, isTrue);
      expect(ragSessionsSupported(r), isFalse);
    });
  });
}
