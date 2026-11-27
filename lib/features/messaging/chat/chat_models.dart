// lib/features/messaging/chat/chat_models.dart — Alfaheem Messages (D-330): the wire shapes, pure.
//
// Times arrive as naive UTC ISO strings (`chatUtc`). Nothing here holds a phone number or an e-mail: the server only
// ever sends {id, name, image_url, role} for a person.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';

DateTime chatUtc(Object? iso) {
  final raw = '${iso ?? ''}';
  if (raw.isEmpty) return DateTime.now().toUtc();
  return DateTime.tryParse(raw.endsWith('Z') || raw.contains('+') ? raw : '${raw}Z')?.toUtc() ?? DateTime.now().toUtc();
}

int? _intOf(Object? v) => v == null ? null : int.tryParse('$v');

class ChatPerson {
  const ChatPerson({required this.id, required this.name, this.imageUrl, this.role = '', this.username});
  final int id;
  final String name;
  final String? imageUrl;
  final String role;

  /// A confirmed @username; the server leaves it out everywhere else (D-371).
  final String? username;

  static ChatPerson? fromJson(Object? j) {
    if (j is! Map) return null;
    return ChatPerson(
      id: _intOf(j['id']) ?? 0,
      name: '${j['name'] ?? ''}',
      imageUrl: (j['image_url'] as String?)?.isNotEmpty == true ? j['image_url'] as String : null,
      role: '${j['role'] ?? ''}',
      username: (j['username'] as String?)?.isNotEmpty == true ? j['username'] as String : null,
    );
  }
}

class ChatCourse {
  const ChatCourse({required this.id, required this.name, this.nameEn = '', this.imageUrl, this.teacherId});
  final int id;
  final String name, nameEn;
  final String? imageUrl;
  final int? teacherId;

  String get label => AppConfig.lang == 'ar' ? (name.isNotEmpty ? name : nameEn) : (nameEn.isNotEmpty ? nameEn : name);

  static ChatCourse? fromJson(Object? j) {
    if (j is! Map) return null;
    return ChatCourse(
      id: _intOf(j['id']) ?? 0,
      name: '${j['name'] ?? ''}',
      nameEn: '${j['name_en'] ?? ''}',
      imageUrl: (j['image_url'] as String?)?.isNotEmpty == true ? j['image_url'] as String : null,
      teacherId: _intOf(j['teacher_id']),
    );
  }
}

class ChatLastMessage {
  const ChatLastMessage({required this.id, required this.kind, this.body = '', this.senderId, this.senderName, required this.createdAt, this.deleted = false});
  final int id;
  final String kind, body;
  final int? senderId;
  final String? senderName;
  final DateTime createdAt;
  final bool deleted;

  static ChatLastMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    return ChatLastMessage(
      id: _intOf(j['id']) ?? 0,
      kind: '${j['kind'] ?? 'text'}',
      body: '${j['body'] ?? ''}',
      senderId: _intOf(j['sender_id']),
      senderName: j['sender_name'] as String?,
      createdAt: chatUtc(j['created_at']),
      deleted: j['deleted'] == true,
    );
  }
}

/// The message a reply quotes (D-540): what the small block on top of the bubble needs.
class ChatReplyRef {
  const ChatReplyRef({required this.id, this.kind = 'text', this.body = '', this.senderId, this.senderName, this.deleted = false});
  final int id;
  final String kind, body;
  final int? senderId;
  final String? senderName;
  final bool deleted;

  static ChatReplyRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _intOf(j['id']);
    if (id == null) return null;
    return ChatReplyRef(
      id: id,
      kind: '${j['kind'] ?? 'text'}',
      body: '${j['body'] ?? ''}',
      senderId: _intOf(j['sender_id']),
      senderName: j['sender_name'] as String?,
      deleted: j['deleted'] == true,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'body': body, 'sender_id': senderId, 'sender_name': senderName, 'deleted': deleted};

  /// Quoting a message on screen. Null for one the server does not know yet.
  static ChatReplyRef? of(ChatMessage m) {
    final id = m.id;
    if (id == null) return null;
    final body = m.body ?? '';
    return ChatReplyRef(id: id, kind: m.kind, body: body.length > 200 ? body.substring(0, 200) : body, senderId: m.senderId, senderName: m.senderName, deleted: m.deleted);
  }
}

/// What the composer may do (the server decides; `services/chat/rules.py`).
enum ChatComposerState { open, blocked, youBlocked, closed, ended, disabled, requestSent, requestReceived }

ChatComposerState chatComposerState(Object? raw) => switch ('$raw') {
      'open' => ChatComposerState.open,
      'blocked' => ChatComposerState.blocked,
      'you_blocked' => ChatComposerState.youBlocked,
      'closed' => ChatComposerState.closed,
      'disabled' => ChatComposerState.disabled,
      'request_sent' => ChatComposerState.requestSent,
      'request_received' => ChatComposerState.requestReceived,
      _ => ChatComposerState.ended,
    };

/// A chat that began as a message request (D-370). `mine`: I sent it. The sender of a declined one reads `pending`.
class ChatRequestInfo {
  const ChatRequestInfo({required this.state, required this.mine});
  final String state;
  final bool mine;

  bool get pending => state == 'pending';

  static ChatRequestInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    return ChatRequestInfo(state: '${j['state'] ?? 'pending'}', mine: j['mine'] == true);
  }
}

/// The inbox's calm "Message requests" line (D-370).
class ChatRequestsSummary {
  const ChatRequestsSummary({this.count = 0, this.latestAt});
  final int count;
  final DateTime? latestAt;

  static ChatRequestsSummary fromJson(Object? j) {
    if (j is! Map) return const ChatRequestsSummary();
    return ChatRequestsSummary(count: _intOf(j['count']) ?? 0, latestAt: j['latest_at'] == null ? null : chatUtc(j['latest_at']));
  }
}

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.kind,
    this.peer,
    this.online = false,
    this.course,
    this.child,
    this.orgName,
    this.orgId,
    this.last,
    required this.lastAt,
    this.unread = 0,
    this.pinned = false,
    this.muted = false,
    this.lastReadId,
    this.peerReadId,
    this.peerDeliveredId,
    this.composer,
    this.composerReason = '',
    this.composerReasonEn = '',
    this.request,
    this.groupOpen = true,
    this.canManage = false,
    this.memberCount,
    this.announceOnly = false,
    this.privateReply = false,
    this.canBlock = true,
    this.attachmentsOn = true,
    this.reportOn = true,
  }) : loadedLastId = last?.id;

  final int id;
  final String kind;
  final ChatPerson? peer;
  bool online;
  final ChatCourse? course;
  final ChatPerson? child;
  final String? orgName;
  final int? orgId;
  ChatLastMessage? last;
  DateTime lastAt;
  int unread;
  bool pinned, muted;
  int? lastReadId, peerReadId, peerDeliveredId;
  ChatComposerState? composer;

  /// Why the composer is not open, in both languages (the server says it; shown before the person writes).
  String composerReason, composerReasonEn;
  ChatRequestInfo? request;
  bool groupOpen, canManage, canBlock, attachmentsOn, reportOn;
  int? memberCount;

  /// The course group as a learner sees it (privacy D-1950, O-5): the teacher's announcements only; a reply goes to
  /// the teacher alone ([privateReply]). Staff never get it.
  bool announceOnly, privateReply;

  /// The newest message the server had counted when this row was loaded: an event at or below it is a replay.
  final int? loadedLastId;

  bool get isGroup => kind == 'course_group';

  /// What the row and the header call this chat.
  String get title => isGroup ? (course?.label ?? '') : (peer?.name ?? '');

  /// The short line under the name: the course, the child, or the organization.
  String get contextLine => course?.label ?? orgName ?? '';

  static ChatConversation fromJson(Map<String, dynamic> j) {
    final composer = j['composer'];
    return ChatConversation(
      id: _intOf(j['id']) ?? 0,
      kind: '${j['kind'] ?? 'direct'}',
      peer: ChatPerson.fromJson(j['peer']),
      online: j['online'] == true,
      course: ChatCourse.fromJson(j['course']),
      child: ChatPerson.fromJson(j['child']),
      orgName: (j['org'] is Map) ? '${(j['org'] as Map)['name'] ?? ''}' : null,
      orgId: (j['org'] is Map) ? _intOf((j['org'] as Map)['id']) : null,
      last: ChatLastMessage.fromJson(j['last_message']),
      lastAt: chatUtc(j['last_message_at']),
      unread: _intOf(j['unread']) ?? 0,
      pinned: j['pinned'] == true,
      muted: j['muted'] == true,
      lastReadId: _intOf(j['last_read_id']),
      peerReadId: _intOf(j['peer_read_id']),
      peerDeliveredId: _intOf(j['peer_delivered_id']),
      composer: composer is Map ? chatComposerState(composer['state']) : null,
      composerReason: composer is Map ? '${composer['reason'] ?? ''}' : '',
      composerReasonEn: composer is Map ? '${composer['reason_en'] ?? ''}' : '',
      request: ChatRequestInfo.fromJson(j['request']),
      groupOpen: j['group_open'] != false,
      canManage: j['can_manage'] == true,
      canBlock: j['can_block'] != false,
      memberCount: _intOf(j['member_count']),
      announceOnly: j['announce_only'] == true,
      privateReply: j['private_reply'] == true,
      attachmentsOn: j['attachments_on'] != false,
      reportOn: j['report_on'] != false,
    );
  }
}

class ChatAttachment {
  const ChatAttachment({required this.id, required this.name, required this.mime, required this.ext, this.size = 0, this.width, this.height, this.image = false});
  final int id;
  final String name, mime, ext;
  final int size;
  final int? width, height;
  final bool image;

  static ChatAttachment fromJson(Map j) => ChatAttachment(
        id: _intOf(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        mime: '${j['mime'] ?? ''}',
        ext: '${j['ext'] ?? ''}',
        size: _intOf(j['size']) ?? 0,
        width: _intOf(j['width']),
        height: _intOf(j['height']),
        image: j['image'] == true,
      );
}

/// A file picked in the composer that is not uploaded yet (bytes on the web, a path on phones).
class ChatLocalFile {
  ChatLocalFile({required this.name, this.bytes, this.path, this.size = 0});
  final String name;
  final Uint8List? bytes;
  final String? path;
  final int size;

  /// The file can still be read and sent: bytes in memory, or a path (a web page's bytes die with the page).
  bool get readable => bytes != null || (path != null && path!.isNotEmpty);

  bool get isImage => const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'}.contains(name.split('.').last.toLowerCase());

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'size': size};

  static ChatLocalFile fromJson(Map j) => ChatLocalFile(name: '${j['name'] ?? 'file'}', path: j['path'] as String?, size: _intOf(j['size']) ?? 0);
}

enum ChatSendState { sent, sending, queued, failed }

class ChatMessage {
  ChatMessage({
    this.id,
    required this.clientId,
    required this.conversationId,
    this.kind = 'text',
    this.body,
    this.senderId,
    this.senderName,
    this.senderImage,
    this.senderIsTeacher = false,
    this.attachments = const [],
    this.local = const [],
    this.uploaded = const [],
    required this.createdAt,
    this.deleted = false,
    this.sendState = ChatSendState.sent,
    this.autoRetry = false,
    this.error,
    this.replyTo,
  });

  /// [error] of a message whose picked file is gone (a web page was reloaded): no retry can send it.
  static const lostFileError = 'chat_attachment_lost';

  int? id;
  final String clientId;
  final int conversationId;
  String kind;
  String? body;
  final int? senderId;
  final String? senderName, senderImage;
  final bool senderIsTeacher;
  List<ChatAttachment> attachments;
  List<ChatLocalFile> local;

  /// Server ids of the [local] files already uploaded, so a retry never uploads one twice.
  List<int> uploaded;
  DateTime createdAt;
  final bool deleted;
  ChatSendState sendState;

  /// Sent from the teacher's announcements: it went to the teacher alone (the server's `redirected`).
  bool privateReply = false;

  /// It failed only because the server was not reached: a reconnect retries it by itself.
  bool autoRetry;
  String? error;

  /// The message this one answers (D-540).
  ChatReplyRef? replyTo;

  bool get hasImages => attachments.any((a) => a.image);

  static ChatMessage fromJson(Map<String, dynamic> j) {
    final sender = j['sender'];
    return ChatMessage(
      id: _intOf(j['id']),
      clientId: '${j['client_id'] ?? 's${j['id']}'}',
      conversationId: _intOf(j['conversation_id']) ?? 0,
      kind: '${j['kind'] ?? 'text'}',
      body: j['body'] as String?,
      senderId: _intOf(j['sender_id']),
      senderName: sender is Map ? sender['name'] as String? : null,
      senderImage: sender is Map ? sender['image_url'] as String? : null,
      senderIsTeacher: j['sender_is_teacher'] == true,
      attachments: [for (final a in (j['attachments'] as List? ?? const [])) if (a is Map) ChatAttachment.fromJson(a)],
      createdAt: chatUtc(j['created_at']),
      deleted: j['deleted'] == true,
      replyTo: ChatReplyRef.fromJson(j['reply_to']),
    );
  }
}

class ChatContact {
  const ChatContact({required this.user, this.course, this.child, this.orgName, this.orgId, this.conversationId});
  final ChatPerson user;
  final ChatCourse? course;
  final ChatPerson? child;
  final String? orgName;
  final int? orgId;
  final int? conversationId;

  String get linkLine => course?.label ?? orgName ?? '';

  static ChatContact fromJson(Map<String, dynamic> j) => ChatContact(
        user: ChatPerson.fromJson(j['user']) ?? const ChatPerson(id: 0, name: ''),
        course: ChatCourse.fromJson(j['course']),
        child: ChatPerson.fromJson(j['child']),
        orgName: (j['org'] is Map) ? '${(j['org'] as Map)['name'] ?? ''}' : null,
        orgId: (j['org'] is Map) ? _intOf((j['org'] as Map)['id']) : null,
        conversationId: _intOf(j['conversation_id']),
      );
}

/// How a chat with this person would start: `state` is thread | direct | request | request_sent | request_received | unavailable.
class ChatReach {
  const ChatReach({required this.state, this.conversationId, this.reason = '', this.reasonEn = ''});
  final String state;
  final int? conversationId;
  final String reason, reasonEn;

  String get reasonText => AppConfig.lang == 'ar' ? reason : (reasonEn.isNotEmpty ? reasonEn : reason);
  bool get unavailable => state == 'unavailable';
  bool get needsRequest => state == 'request';

  static ChatReach fromJson(Object? j) {
    if (j is! Map) return const ChatReach(state: 'unavailable');
    return ChatReach(state: '${j['state'] ?? 'unavailable'}', conversationId: _intOf(j['conversation_id']), reason: '${j['reason'] ?? ''}', reasonEn: '${j['reason_en'] ?? ''}');
  }
}

/// One person the New message sheet offers (D-371, `GET /chat/people`).
class ChatPersonRow {
  const ChatPersonRow({required this.user, this.course, this.child, this.orgName, this.orgId, this.relation = 'none', required this.reach});
  final ChatPerson user;
  final ChatCourse? course;
  final ChatPerson? child;
  final String? orgName;
  final int? orgId;
  final String relation;
  final ChatReach reach;

  static ChatPersonRow fromJson(Map<String, dynamic> j) => ChatPersonRow(
        user: ChatPerson.fromJson(j['user']) ?? const ChatPerson(id: 0, name: ''),
        course: ChatCourse.fromJson(j['course']),
        child: ChatPerson.fromJson(j['child']),
        orgName: (j['org'] is Map) ? '${(j['org'] as Map)['name'] ?? ''}' : null,
        orgId: (j['org'] is Map) ? _intOf((j['org'] as Map)['id']) : null,
        relation: '${j['relation'] ?? 'none'}',
        reach: ChatReach.fromJson(j['reach']),
      );

  /// What the chat page's start call needs (it opens `conversationId`, or starts the direct chat).
  ChatContact toContact() => ChatContact(user: user, course: course, child: child, orgName: orgName, orgId: orgId, conversationId: reach.conversationId);
}

class ChatPeople {
  const ChatPeople({this.recent = const [], this.suggested = const [], this.results = const [], this.requestsLeft = 0, this.requestsPerDay = 0, this.requestsOn = true});
  final List<ChatPersonRow> recent, suggested, results;
  final int requestsLeft, requestsPerDay;
  final bool requestsOn;

  static ChatPeople fromJson(Map<String, dynamic> j) {
    List<ChatPersonRow> rows(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) ChatPersonRow.fromJson(Map<String, dynamic>.from(x))];
    return ChatPeople(
      recent: rows(j['recent']),
      suggested: rows(j['suggested']),
      results: rows(j['results']),
      requestsLeft: _intOf(j['requests_left']) ?? 0,
      requestsPerDay: _intOf(j['requests_per_day']) ?? 0,
      requestsOn: j['requests_on'] != false,
    );
  }
}

class ChatBlock {
  const ChatBlock({required this.id, required this.user, required this.level, this.course, this.reason, required this.createdAt});
  final int id;
  final ChatPerson user;
  final String level;
  final ChatCourse? course;
  final String? reason;
  final DateTime createdAt;

  static ChatBlock fromJson(Map<String, dynamic> j) => ChatBlock(
        id: _intOf(j['id']) ?? 0,
        user: ChatPerson.fromJson(j['user']) ?? const ChatPerson(id: 0, name: ''),
        level: '${j['level'] ?? 'person'}',
        course: ChatCourse.fromJson(j['course']),
        reason: j['reason'] as String?,
        createdAt: chatUtc(j['created_at']),
      );
}

class ChatReport {
  const ChatReport({
    required this.id,
    this.reporter,
    this.target,
    required this.reason,
    this.note,
    this.snapshot = const [],
    required this.status,
    this.messageId,
    required this.createdAt,
  });
  final int id;
  final ChatPerson? reporter, target;
  final String reason, status;
  final String? note;
  final List<Map<String, dynamic>> snapshot;
  final int? messageId;
  final DateTime createdAt;

  static ChatReport fromJson(Map<String, dynamic> j) => ChatReport(
        id: _intOf(j['id']) ?? 0,
        reporter: ChatPerson.fromJson(j['reporter']),
        target: ChatPerson.fromJson(j['target']),
        reason: '${j['reason'] ?? ''}',
        note: j['note'] as String?,
        snapshot: [for (final s in (j['snapshot'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)],
        status: '${j['status'] ?? 'open'}',
        messageId: _intOf(j['message_id']),
        createdAt: chatUtc(j['created_at']),
      );
}

/// A contract note, used by both directions of a new message: a client id unique per send on this device.
String chatNewClientId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return 'c${now.toRadixString(36)}${(_seq++).toRadixString(36)}${_rand.nextInt(1 << 30).toRadixString(36)}';
}

int _seq = 0;
final _rand = Random();
