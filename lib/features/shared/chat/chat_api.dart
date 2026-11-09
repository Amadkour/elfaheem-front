// lib/features/shared/chat/chat_api.dart — NextBrain Messages (D-330): every call, through ApiClient.
library;

import 'package:flutter_education_app/core/api_client.dart';

import 'chat_models.dart';

class ChatConversationPage {
  const ChatConversationPage(this.items, this.hasMore, this.total, this.courses, this.roles, {this.requestCount = 0});
  final List<ChatConversation> items;
  final bool hasMore;
  final int total;
  final List<ChatCourse> courses;
  final List<String> roles;

  /// Message requests waiting on me (`requests.count`, D-370); 0 on an older server.
  final int requestCount;
}

class ChatMessagePage {
  const ChatMessagePage(this.items, this.hasMore);
  final List<ChatMessage> items;
  final bool hasMore;
}

class ChatBlockOptions {
  const ChatBlockOptions(this.levels, this.courses, this.active);
  final List<String> levels;
  final List<ChatCourse> courses;
  final List<ChatBlock> active;
}

class ChatApi {
  ChatApi([ApiClient? client]) : _c = client ?? ApiClient();
  final ApiClient _c;

  static const _b = '/api/v1/chat';

  Map<String, dynamic> _m(dynamic r) => Map<String, dynamic>.from(r as Map);

  Future<ChatConversationPage> conversations({String filter = 'all', int? courseId, String? role, String q = '', int offset = 0, int limit = 40}) async {
    final r = _m(await _c.get('$_b/conversations', queryParams: {
      'filter': filter,
      if (courseId != null) 'course_id': courseId,
      if (role != null) 'role': role,
      if (q.isNotEmpty) 'q': q,
      'offset': offset,
      'limit': limit,
    }));
    final filters = r['filters'] is Map ? _m(r['filters']) : const <String, dynamic>{};
    return ChatConversationPage(
      [for (final x in (r['items'] as List)) ChatConversation.fromJson(_m(x))],
      r['has_more'] == true,
      (r['total'] as num?)?.toInt() ?? 0,
      [for (final x in (filters['courses'] as List? ?? const [])) ?ChatCourse.fromJson(x)],
      [for (final x in (filters['roles'] as List? ?? const [])) '$x'],
      requestCount: r['requests'] is Map ? ((r['requests'] as Map)['count'] as num?)?.toInt() ?? 0 : 0,
    );
  }

  /// The message requests waiting on me (D-370).
  Future<(List<ChatConversation>, bool)> requests({int offset = 0, int limit = 40}) async {
    final r = _m(await _c.get('$_b/requests', queryParams: {'offset': offset, 'limit': limit}));
    return ([for (final x in (r['items'] as List)) ChatConversation.fromJson(_m(x))], r['has_more'] == true);
  }

  Future<ChatConversation> acceptRequest(int id) async => ChatConversation.fromJson(_m(await _c.post('$_b/requests/$id/accept')));

  Future<void> declineRequest(int id) => _c.post('$_b/requests/$id/decline');

  Future<void> blockRequest(int id) => _c.post('$_b/requests/$id/block');

  Future<ChatConversation> thread(int id) async => ChatConversation.fromJson(_m(await _c.get('$_b/conversations/$id')));

  Future<ChatConversation> start({required int peerId, int? courseId, int? orgId}) async => ChatConversation.fromJson(_m(await _c.post('$_b/conversations', body: {
        'peer_id': peerId,
        if (courseId != null) 'course_id': courseId,
        if (orgId != null) 'org_id': orgId,
      })));

  Future<ChatMessagePage> messages(int id, {int? before, int? after, int limit = 30}) async {
    final r = _m(await _c.get('$_b/conversations/$id/messages', queryParams: {
      if (before != null) 'before': before,
      if (after != null) 'after': after,
      'limit': limit,
    }));
    return ChatMessagePage([for (final x in (r['items'] as List)) ChatMessage.fromJson(_m(x))], r['has_more'] == true);
  }

  Future<ChatMessage> send(int id, {required String clientId, String? body, List<int> attachmentIds = const []}) async {
    final r = _m(await _c.post('$_b/conversations/$id/messages', body: {
      'client_id': clientId,
      if (body != null) 'body': body,
      if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
    }));
    return ChatMessage.fromJson(_m(r['message']));
  }

  Future<ChatAttachment> upload(int conversationId, ChatLocalFile f) async {
    final r = await _c.postMultipart('$_b/attachments', fields: {'conversation_id': '$conversationId'}, fileField: 'file', fileName: f.name, filePath: f.path, fileBytes: f.bytes);
    return ChatAttachment.fromJson(_m(r));
  }

  Future<String> attachmentLink(int attachmentId, {bool inline = true}) async =>
      '${_m(await _c.get('$_b/attachments/$attachmentId/link', queryParams: {'inline': inline}))['url']}';

  Future<void> read(int id, int messageId) => _c.post('$_b/conversations/$id/read', body: {'message_id': messageId});

  Future<void> delivered(List<Map<String, int>> items) => _c.post('$_b/delivered', body: {'items': items});

  Future<void> typing(int id, bool typing) => _c.post('$_b/conversations/$id/typing', body: {'typing': typing});

  Future<void> presence(bool online) => _c.post('$_b/presence', body: {'online': online});

  Future<void> prefs(int id, {bool? pinned, String? mute}) => _c.put('$_b/conversations/$id/prefs', body: {
        if (pinned != null) 'pinned': pinned,
        if (mute != null) 'mute': mute,
      });

  Future<ChatConversation> setGroupOpen(int id, bool open) async => ChatConversation.fromJson(_m(await _c.put('$_b/conversations/$id/group', body: {'open': open})));

  Future<List<ChatMemberRow>> members(int id, {String q = ''}) async {
    final r = _m(await _c.get('$_b/conversations/$id/members', queryParams: {if (q.isNotEmpty) 'q': q}));
    return [
      for (final x in (r['items'] as List))
        ChatMemberRow(ChatPerson.fromJson((x as Map)['user']) ?? const ChatPerson(id: 0, name: ''), x['teacher'] == true),
    ];
  }

  Future<List<ChatContact>> contacts({String q = ''}) async {
    final r = _m(await _c.get('$_b/contacts', queryParams: {if (q.isNotEmpty) 'q': q}));
    return [for (final x in (r['items'] as List)) ChatContact.fromJson(_m(x))];
  }

  /// The New message sheet (D-371): recent and suggested people, or anyone by name / @username.
  Future<ChatPeople> people({String q = ''}) async => ChatPeople.fromJson(_m(await _c.get('$_b/people', queryParams: {if (q.isNotEmpty) 'q': q})));

  /// The first message to someone (D-370): a held request, or simply the chat when the two already have a link. Returns the conversation to open.
  Future<ChatConversation> sendRequest({required int peerId, required String clientId, required String body}) async {
    final r = _m(await _c.post('$_b/requests', body: {'peer_id': peerId, 'client_id': clientId, 'body': body}));
    return ChatConversation.fromJson(_m(r['conversation']));
  }

  /// The requests waiting on me: the rows with `last_message` the held message (D-370).
  Future<(List<ChatConversation>, bool)> requests({int offset = 0, int limit = 40}) async {
    final r = _m(await _c.get('$_b/requests', queryParams: {'offset': offset, 'limit': limit}));
    return ([for (final x in (r['items'] as List)) ChatConversation.fromJson(_m(x))], r['has_more'] == true);
  }

  Future<ChatConversation> acceptRequest(int id) async => ChatConversation.fromJson(_m(await _c.post('$_b/requests/$id/accept')));

  Future<void> declineRequest(int id) => _c.post('$_b/requests/$id/decline');

  Future<void> blockRequest(int id) => _c.post('$_b/requests/$id/block');

  Future<List<ChatBlock>> blocks() async {
    final r = _m(await _c.get('$_b/blocks'));
    return [for (final x in (r['items'] as List)) ChatBlock.fromJson(_m(x))];
  }

  Future<ChatBlockOptions> blockOptions(int userId) async {
    final r = _m(await _c.get('$_b/blocks/options', queryParams: {'user_id': userId}));
    return ChatBlockOptions(
      [for (final x in (r['levels'] as List)) '$x'],
      [for (final x in (r['courses'] as List)) ?ChatCourse.fromJson(x)],
      [for (final x in (r['active'] as List)) ChatBlock.fromJson(_m(x))],
    );
  }

  Future<ChatBlock> block({required int userId, required String level, int? courseId, String? reason}) async => ChatBlock.fromJson(_m(await _c.post('$_b/blocks', body: {
        'user_id': userId,
        'level': level,
        if (courseId != null) 'course_id': courseId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      })));

  Future<void> unblock(int blockId) => _c.delete('$_b/blocks/$blockId');

  /// null: this person teaches nothing, so the switch is not for them.
  Future<bool?> teacherStudentDm() async {
    final r = _m(await _c.get('$_b/settings'));
    return r['can_edit'] == true ? r['student_dm'] == true : null;
  }

  Future<void> setTeacherStudentDm(bool on) => _c.put('$_b/settings', body: {'student_dm': on});

  Future<void> report({required int conversationId, int? messageId, required String reason, String? note}) => _c.post('$_b/reports', body: {
        'conversation_id': conversationId,
        if (messageId != null) 'message_id': messageId,
        'reason': reason,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<(List<ChatReport>, int)> adminReports({String? status, int offset = 0, int limit = 30}) async {
    final r = _m(await _c.get('/api/v1/admin/chat/reports', queryParams: {if (status != null) 'status': status, 'offset': offset, 'limit': limit}));
    return ([for (final x in (r['items'] as List)) ChatReport.fromJson(_m(x))], (r['open'] as num?)?.toInt() ?? 0);
  }

  Future<void> reviewReport(int id, {required String status, String? note}) =>
      _c.post('/api/v1/admin/chat/reports/$id/review', body: {'status': status, if (note != null && note.isNotEmpty) 'note': note});
}

class ChatMemberRow {
  const ChatMemberRow(this.person, this.teacher);
  final ChatPerson person;
  final bool teacher;
}
