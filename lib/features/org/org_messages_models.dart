// lib/features/org/org_messages_models.dart
//
// Institutions S4, messaging (plan docs/institutions/PLAN.md item 13, contract docs/institutions/CONTRACT_S4.md,
// back D-975 – D-978, features/org/core/messaging.py). The pure half — no widgets, unit-tested directly:
//   orgMessagesFeatureKey · orgMustAckFeatureKey · orgMessagesEnabled() · orgMustAckEnabled()
//   MsgDelivery                 normal · push · must_ack (wire, label, one sentence)
//   MsgOptions                  GET …/messages/options (what I may send, today's must-acknowledge count)
//   OrgMessage · MsgStats · MsgPerson · MsgReply · MsgRecipient   the staff and member message JSON
//   MustAckState                GET /me/must-ack · the `next` of an acknowledge
//   MsgDraft                    the composer's state → the POST body (dry_run for the "N recipients" line)
//   msgCodeTexts · msgErrorText the server codes in Arabic + English (ack_rate_limit with its wait, …)
//   MsgApi                      one method per route (staff by organization, the member routes static)
// The staff screens are in org_messages.dart, the recipient's (the must-acknowledge card and host, the messages
// list) in org_must_ack.dart.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;

import '../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'org_providers.dart' show orgBase;
import 'org_v3.dart' show OrgCall, orgCall, orgErrorText, orgParseUtc, orgUtc;

/// Everything (the Messages section, the member's list, the card) — back `feature_catalog.py`.
const orgMessagesFeatureKey = 'org.messages';

/// The must-acknowledge delivery and the card.
const orgMustAckFeatureKey = 'org.messages.must_ack';

bool orgMessagesEnabled() => !AppConfig.disableList.contains(orgMessagesFeatureKey) && AppConfig.orgsEnabled;

bool orgMustAckEnabled() => orgMessagesEnabled() && !AppConfig.disableList.contains(orgMustAckFeatureKey);

/// The default and the longest life of a must-acknowledge message (days).
const msgAckDefaultDays = 3;
const msgAckMaxDays = 7;

// ═════════════════════════════════════════════════════════════════════════════
//  Delivery
// ═════════════════════════════════════════════════════════════════════════════

enum MsgDelivery { normal, push, mustAck }

MsgDelivery msgDeliveryOf(Object? v) => switch ('$v') {
      'push' => MsgDelivery.push,
      'must_ack' => MsgDelivery.mustAck,
      _ => MsgDelivery.normal,
    };

String msgDeliveryWire(MsgDelivery d) => switch (d) {
      MsgDelivery.normal => 'normal',
      MsgDelivery.push => 'push',
      MsgDelivery.mustAck => 'must_ack',
    };

String msgDeliveryLabel(MsgDelivery d) => switch (d) {
      MsgDelivery.normal => t('رسالة', 'Message'),
      MsgDelivery.push => t('رسالة + إشعار', 'Message + notification'),
      MsgDelivery.mustAck => t('إقرار إلزامي', 'Must acknowledge'),
    };

String msgDeliverySentence(MsgDelivery d) => switch (d) {
      MsgDelivery.normal => t('تظهر في رسائل المؤسسة لدى الطالب دون تنبيه على الهاتف.',
          'Shows in the student\'s organization messages, without a phone alert.'),
      MsgDelivery.push => t('تظهر في رسائل المؤسسة ويصل معها إشعار على الهاتف.',
          'Shows in the organization messages and sends a phone notification.'),
      MsgDelivery.mustAck => t('تغطي شاشة الطالب حتى يقرّ بقراءتها.',
          'It covers the student\'s screen until they confirm they have read it.'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Options
// ═════════════════════════════════════════════════════════════════════════════

class MsgOptions {
  const MsgOptions({
    this.canSend = true,
    this.canMustAck = false,
    this.mustAckScope,
    this.headDeptIds = const {},
    this.myDeptIds = const {},
    this.ackLimit = 3,
    this.ackUsedToday = 0,
    this.ackMaxDays = msgAckMaxDays,
    this.maxRecipients = 5000,
  });

  factory MsgOptions.fromJson(Map<String, dynamic> j) => MsgOptions(
        canSend: j['can_send'] != false,
        canMustAck: j['can_must_ack'] == true,
        mustAckScope: j['must_ack_scope'] == null ? null : asStr(j['must_ack_scope']),
        headDeptIds: {for (final v in (j['head_dept_ids'] as List?) ?? const []) asInt(v)},
        myDeptIds: {for (final v in (j['my_dept_ids'] as List?) ?? const []) asInt(v)},
        ackLimit: asInt(j['ack_limit'], 3),
        ackUsedToday: asInt(j['ack_used_today']),
        ackMaxDays: asInt(j['ack_max_days'], msgAckMaxDays).clamp(1, msgAckMaxDays),
        maxRecipients: asInt(j['max_recipients'], 5000),
      );

  final bool canSend, canMustAck;

  /// `all` (admin, dean, vice deans) · `departments` (a head: their departments' students only) · null.
  final String? mustAckScope;
  final Set<int> headDeptIds, myDeptIds;
  final int ackLimit, ackUsedToday, ackMaxDays, maxRecipients;

  int get ackLeft => (ackLimit - ackUsedToday).clamp(0, ackLimit);

  /// The Must acknowledge card is drawn only when the server says I may send one (and the switch is on).
  bool get showMustAck => canMustAck && orgMustAckEnabled();

  bool get headOnly => mustAckScope == 'departments';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Messages
// ═════════════════════════════════════════════════════════════════════════════

class MsgPerson {
  const MsgPerson({this.id, this.name = '', this.avatar, this.anonymous = false});

  factory MsgPerson.fromJson(Object? v) {
    final j = asMap(v);
    return MsgPerson(
      id: j['id'] == null ? null : asInt(j['id']),
      name: asStr(j['name']),
      avatar: j['avatar'] == null ? null : asStr(j['avatar']),
      anonymous: j['anonymous'] == true,
    );
  }

  final int? id;
  final String name;
  final String? avatar;
  final bool anonymous;

  String get shown => anonymous || name.isEmpty ? t('مقدّم مجهول', 'Anonymous submitter') : name;
}

class MsgStats {
  const MsgStats({this.recipients = 0, this.read = 0, this.acknowledged = 0, this.pending = 0});

  factory MsgStats.fromJson(Object? v) {
    final j = asMap(v);
    return MsgStats(recipients: asInt(j['recipients']), read: asInt(j['read']), acknowledged: asInt(j['acknowledged']), pending: asInt(j['pending']));
  }

  final int recipients, read, acknowledged, pending;
}

/// Where a recipient answers: the org chat with the sender, or the complaint / request thread.
class MsgReply {
  const MsgReply({required this.kind, this.peerId, this.orgId, this.complaintId, this.workItemId});

  static MsgReply? fromJson(Object? v) {
    final j = asMap(v);
    final k = asStr(j['kind']);
    if (k != 'chat' && k != 'item') return null;
    int? n(String key) => j[key] == null ? null : asInt(j[key]);
    return MsgReply(kind: k, peerId: n('peer_id'), orgId: n('org_id'), complaintId: n('complaint_id'), workItemId: n('work_item_id'));
  }

  final String kind;
  final int? peerId, orgId, complaintId, workItemId;

  bool get isChat => kind == 'chat' && peerId != null;
  bool get isItem => kind == 'item';
}

class OrgMessage {
  const OrgMessage({
    required this.id,
    this.orgId,
    this.delivery = MsgDelivery.normal,
    this.title = '',
    this.body = '',
    this.reason,
    this.sender = const MsgPerson(),
    this.deptName,
    this.complaintId,
    this.workItemId,
    this.expiresAt,
    this.expired = false,
    this.createdAt,
    this.stats,
    this.orgName,
    this.readAt,
    this.ackedAt,
    this.needsAck = false,
    this.reply,
  });

  factory OrgMessage.fromJson(Map<String, dynamic> j) {
    final dept = asMap(j['dept']);
    final org = asMap(j['org']);
    String? name(Map<String, dynamic> m) {
      if (m.isEmpty) return null;
      final ar = asStr(m['name_ar']), en = asStr(m['name_en']);
      final s = AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
      return s.isEmpty ? (m['name'] == null ? null : asStr(m['name'])) : s;
    }

    int? n(String key) => j[key] == null ? null : asInt(j[key]);
    return OrgMessage(
      id: asInt(j['id']),
      orgId: n('org_id') ?? (org['id'] == null ? null : asInt(org['id'])),
      delivery: msgDeliveryOf(j['delivery']),
      title: asStr(j['title']),
      body: asStr(j['body']),
      reason: j['reason'] == null || asStr(j['reason']).isEmpty ? null : asStr(j['reason']),
      sender: MsgPerson.fromJson(j['sender']),
      deptName: name(dept),
      complaintId: n('complaint_id'),
      workItemId: n('work_item_id'),
      expiresAt: orgParseUtc(j['expires_at']),
      expired: j['expired'] == true,
      createdAt: orgParseUtc(j['created_at']),
      stats: j['stats'] == null ? null : MsgStats.fromJson(j['stats']),
      orgName: name(org),
      readAt: orgParseUtc(j['read_at']),
      ackedAt: orgParseUtc(j['acked_at']),
      needsAck: j['needs_ack'] == true,
      reply: MsgReply.fromJson(j['reply']),
    );
  }

  final int id;
  final int? orgId;
  final MsgDelivery delivery;
  final String title, body;
  final String? reason;
  final MsgPerson sender;
  final String? deptName;
  final int? complaintId, workItemId;

  /// Local time (the server's naive UTC read through orgParseUtc).
  final DateTime? expiresAt, createdAt;
  final bool expired;
  final MsgStats? stats;

  // the member's view
  final String? orgName;
  final DateTime? readAt, ackedAt;
  final bool needsAck;
  final MsgReply? reply;

  bool get mustAck => delivery == MsgDelivery.mustAck;
  bool get linked => complaintId != null || workItemId != null;
  bool get unread => readAt == null;

  /// Who it is from on the card: the department when there is one, else the sender.
  String get fromLine => [if (sender.name.isNotEmpty) sender.name, ?deptName, ?orgName].join(' · ');
}

class MsgRecipient {
  const MsgRecipient({required this.user, this.readAt, this.ackedAt});

  factory MsgRecipient.fromJson(Map<String, dynamic> j) =>
      MsgRecipient(user: MsgPerson.fromJson(j['user']), readAt: orgParseUtc(j['read_at']), ackedAt: orgParseUtc(j['acked_at']));

  final MsgPerson user;
  final DateTime? readAt, ackedAt;
}

/// The names sheet's filter (`?status=`).
enum MsgRecipientFilter { all, acknowledged, pending, unread }

String? msgFilterWire(MsgRecipientFilter f) => f == MsgRecipientFilter.all ? null : f.name;

/// The sent message with its stats and one page of recipients (GET …/messages/{mid}).
class MsgDetail {
  const MsgDetail({required this.message, this.total = 0, this.recipients = const []});

  factory MsgDetail.fromJson(Map<String, dynamic> j) {
    final r = asMap(j['recipients']);
    return MsgDetail(
      message: OrgMessage.fromJson(j),
      total: asInt(r['total']),
      recipients: [for (final x in asMapList(r['items'])) MsgRecipient.fromJson(x)],
    );
  }

  final OrgMessage message;
  final int total;
  final List<MsgRecipient> recipients;
}

/// GET /me/must-ack, or the `next` of an acknowledge: the ONE message to show now and how many wait behind it.
class MustAckState {
  const MustAckState({this.item, this.queued = 0});

  factory MustAckState.fromJson(Object? v) {
    final j = asMap(v);
    final it = asMap(j['item']);
    return MustAckState(item: it.isEmpty ? null : OrgMessage.fromJson(it), queued: asInt(j['queued']));
  }

  final OrgMessage? item;
  final int queued;

  static const none = MustAckState();
}

/// Whether the card may cover the app right now: never inside a live exam or a live room (D-977).
bool mustAckMayShow({required bool examOpen, required bool roomOpen}) => !examOpen && !roomOpen;

/// Whether the app should ask GET /me/must-ack at all.
bool mustAckShouldAsk({required bool signedIn, required bool viewAs, bool? enabled}) =>
    signedIn && !viewAs && (enabled ?? orgMustAckEnabled());

/// "2 more are waiting" under the card.
String mustAckQueuedText(int n) => countText(n,
    ar1: 'رسالة أخرى تنتظر بعد هذه', ar2: 'رسالتان أخريان تنتظران', arFew: '{n} رسائل أخرى تنتظر', arMany: '{n} رسالة أخرى تنتظر',
    en1: '1 more message is waiting', en: '{n} more messages are waiting');

String msgRecipientsText(int n) => countText(n,
    ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', ar0: 'لا أحد', en1: '1 student', en: '{n} students', en0: 'No one');

// ═════════════════════════════════════════════════════════════════════════════
//  Composer draft
// ═════════════════════════════════════════════════════════════════════════════

class MsgPick {
  const MsgPick(this.id, this.name);
  final int id;
  final String name;

  @override
  bool operator ==(Object other) => other is MsgPick && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MsgDraft {
  MsgDraft({this.complaintId, this.workItemId});

  MsgDelivery delivery = MsgDelivery.normal;
  String title = '', body = '', reason = '';
  int expiryDays = msgAckDefaultDays;
  final List<MsgPick> students = [];
  MsgPick? dept, course;

  /// A message about a complaint / request goes to its submitter only (the server picks them).
  final int? complaintId, workItemId;

  bool get linked => complaintId != null || workItemId != null;
  bool get hasAudience => linked || students.isNotEmpty || dept != null || course != null;

  /// A local check with the server's codes (so orgErrorText / msgErrorText words it), null when it may be sent.
  String? problem([MsgOptions options = const MsgOptions()]) {
    if (!hasAudience) return 'no_recipients';
    if (title.trim().isEmpty && body.trim().isEmpty) return 'message_empty';
    if (delivery == MsgDelivery.mustAck) {
      if (!options.showMustAck) return 'ack_not_allowed';
      if (options.ackLeft <= 0) return 'ack_rate_limit';
      if (reason.trim().length < 3) return 'ack_reason_required';
      if (expiryDays < 1) return 'ack_expiry_required';
      if (expiryDays > options.ackMaxDays) return 'ack_expiry_too_far';
    }
    return null;
  }

  Map<String, dynamic> get to => linked
      ? {'complaint_id': ?complaintId, 'work_item_id': ?workItemId}
      : {
          if (students.isNotEmpty) 'user_ids': [for (final s in students) s.id],
          'dept_id': ?dept?.id,
          'course_id': ?course?.id,
        };

  /// The POST body; [now] is the send time (tests pass one), the expiry is sent in UTC.
  Map<String, dynamic> toBody({bool dryRun = false, DateTime? now}) {
    final ack = delivery == MsgDelivery.mustAck;
    final title0 = title.trim(), body0 = body.trim();
    return {
      'delivery': msgDeliveryWire(delivery),
      'title': title0.isEmpty ? _titleFrom(body0) : title0,
      'body': body0.isEmpty ? title0 : body0,
      if (ack) 'reason': reason.trim(),
      if (ack) 'expires_at': orgUtc((now ?? DateTime.now()).add(Duration(days: expiryDays))),
      'to': to,
      'dry_run': dryRun,
    };
  }

  /// The count line only needs the audience: a dry run with placeholder text never fails on an empty title.
  Map<String, dynamic> dryRunBody() => {'delivery': 'normal', 'title': '-', 'body': '-', 'to': to, 'dry_run': true};

  static String _titleFrom(String body) {
    final first = body.split('\n').first.trim();
    return first.length <= 80 ? first : '${first.substring(0, 79)}…';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Error texts
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> msgCodeTexts() => {
      'not_org_staff': t('إرسال الرسائل لفريق عمل المؤسسة فقط', 'Only the organization\'s staff can send messages'),
      'ack_not_allowed': t('الإقرار الإلزامي للعميد ووكلائه ومدير المؤسسة ورؤساء الأقسام فقط',
          'Must acknowledge is for the dean, the vice deans, the organization admin and department heads only'),
      'ack_out_of_audience': t('يمكنك إرسال الإقرار الإلزامي لطلاب أقسامك فقط', 'You can send must acknowledge only to your departments\' students'),
      'not_dept_team': t('مراسلة مقدّم الطلب لفريق الجهة التي تتولاه فقط', 'Only the team of the department that holds it can message the submitter'),
      'not_org_student': t('بعض المستلمين ليسوا طلاباً في هذه المؤسسة', 'Some recipients are not students of this organization'),
      'bad_audience': t('رسالة الشكوى أو الطلب تُرسل لمقدّمه وحده', 'A message about a complaint or request goes to its submitter alone'),
      'no_recipients': t('اختر مستلماً واحداً على الأقل', 'Pick at least one recipient'),
      'too_many_recipients': t('عدد المستلمين أكبر من المسموح', 'Too many recipients'),
      'message_empty': t('اكتب عنوان الرسالة أو نصها', 'Write the message\'s title or text'),
      'bad_expiry': t('موعد الانتهاء في الماضي', 'The expiry is in the past'),
      'ack_reason_required': t('اكتب سبب الإقرار الإلزامي (3 أحرف على الأقل)', 'Type the reason for must acknowledge (3 characters at least)'),
      'ack_expiry_required': t('حدّد موعد انتهاء الإقرار', 'Set when the acknowledgement expires'),
      'ack_expiry_too_far': t('موعد الانتهاء 7 أيام على الأكثر', 'The expiry is 7 days at most'),
      'ack_rate_limit': t('أرسلت الحد الأقصى من رسائل الإقرار (3 في 24 ساعة)', 'You have sent the most must-acknowledge messages allowed (3 in 24 hours)'),
      'dept_not_found': t('هذه الإدارة غير موجودة', 'This department does not exist'),
      'course_not_found': t('هذا المقرر غير موجود في المؤسسة', 'This course is not in the organization'),
      'item_not_found': t('هذه الشكوى أو الطلب غير موجود', 'This complaint or request does not exist'),
      'message_not_found': t('هذه الرسالة غير متاحة', 'This message is not available'),
      'message_expired': t('انتهت صلاحية هذه الرسالة', 'This message has expired'),
      'not_must_ack': t('هذه الرسالة لا تحتاج إلى إقرار', 'This message does not need an acknowledgement'),
    };

/// The text of a local [MsgDraft.problem] code.
String msgCodeText(String code) => msgCodeTexts()[code] ?? code;

/// A messaging error: these codes first (`bad_audience` means something else in the S1 audience editor), with the
/// extras the server sends (the wait of `ack_rate_limit`, the cap of `too_many_recipients`), then orgErrorText.
String msgErrorText(ApiException e) {
  final c = e.code;
  final txt = c == null ? null : msgCodeTexts()[c];
  if (txt == null) return orgErrorText(e);
  final d = asMap(ApiException.asMap(e.body)?['detail']);
  if (c == 'ack_rate_limit') {
    final s = asInt(d['retry_after']);
    if (s > 0) {
      final h = (s / 3600).ceil();
      return '$txt — ${s < 3600 ? t('حاول بعد ${(s / 60).ceil()} دقيقة', 'try again in ${(s / 60).ceil()} min') : t('حاول بعد $h ساعة', 'try again in $h h')}';
    }
  }
  if (c == 'too_many_recipients') {
    final m = asInt(d['max']);
    if (m > 0) return '$txt (${t('الحد $m', 'max $m')})';
  }
  if (c == 'not_org_student') {
    final n = ((d['user_ids'] as List?) ?? const []).length;
    if (n > 0) return '$txt (${msgRecipientsText(n)})';
  }
  return txt;
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

class MsgApi {
  MsgApi(this.orgId, {ApiClient? client}) : _c = client ?? ApiClient();

  final int orgId;
  final ApiClient _c;

  Future<OrgCall> options() => orgCall(() => _c.get('$orgBase/orgs/$orgId/messages/options'), quiet: true);

  /// The send (or its dry run): 201 `{id, recipients, queued, delivery}`.
  Future<OrgCall> send(Map<String, dynamic> body) => orgCall(() => _c.post('$orgBase/orgs/$orgId/messages', body: body), quiet: true);

  Future<OrgCall> sent({int limit = 50, int offset = 0, int? complaintId, int? workItemId}) => orgCall(
      () => _c.get('$orgBase/orgs/$orgId/messages', queryParams: {
            'limit': limit,
            'offset': offset,
            'complaint_id': ?complaintId,
            'work_item_id': ?workItemId,
          }),
      quiet: true);

  Future<OrgCall> detail(int mid, {MsgRecipientFilter filter = MsgRecipientFilter.all, int limit = 200}) => orgCall(
      () => _c.get('$orgBase/orgs/$orgId/messages/$mid', queryParams: {'status': ?msgFilterWire(filter), 'limit': limit}), quiet: true);

  // ── the member's routes ──

  static Future<MustAckState> mustAck({ApiClient? client}) async {
    final r = await orgCall(() => (client ?? ApiClient()).get('/api/v1/me/must-ack'), quiet: true);
    return r.ok ? MustAckState.fromJson(r.map) : MustAckState.none;
  }

  static Future<OrgCall> myMessages({int? orgId, int limit = 50, int offset = 0, ApiClient? client}) => orgCall(
      () => (client ?? ApiClient()).get('/api/v1/me/org-messages', queryParams: {'org_id': ?orgId, 'limit': limit, 'offset': offset}),
      quiet: true);

  /// One message (the server marks it read).
  static Future<OrgCall> myMessage(int mid, {ApiClient? client}) =>
      orgCall(() => (client ?? ApiClient()).get('/api/v1/me/org-messages/$mid'), quiet: true);

  static Future<OrgCall> markRead(int mid, {ApiClient? client}) =>
      orgCall(() => (client ?? ApiClient()).post('/api/v1/me/org-messages/$mid/read', body: const {}), quiet: true);

  /// `{id, acked_at, next: {item, queued}}`.
  static Future<OrgCall> acknowledge(int mid, {ApiClient? client}) =>
      orgCall(() => (client ?? ApiClient()).post('/api/v1/me/org-messages/$mid/acknowledge', body: const {}), quiet: true);
}
