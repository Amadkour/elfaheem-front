// lib/features/profile/compalints/complaints_hub_model.dart
//
// The pure part of the profile's Complaints page (D-086): ONE row shape for the two kinds of complaint the app
// has — platform complaints (`/api/v1/complaints`, the app team / a course's teacher) and organization complaints
// (`/api/v1/org/…/complaints`, a department of the person's organization) — and the rules the page shows them by:
//
//   My complaints   unread replies first, then the latest change first
//   To resolve      still open first; overdue, then the nearest reply-by (a platform complaint has no SLA on the
//                   server: its priority's usual window from its creation is used for the ORDER only, never shown);
//                   priority; unread; oldest first
//
// Filters, counts, the SLA chip, the quick actions and the "x ago" label are functions of plain values (and of
// `now`) so they are unit-tested without a server (test/org/complaints_hub_test.dart).
library;

import 'package:flutter_education_app/config/app_config.dart';

import 'package:flutter_education_app/features/profile/compalints/complaint_model.dart';

enum HubSource { platform, org }

/// open · in progress · waiting (an organization's "waiting for your answer") · resolved · closed.
enum HubStatus {
  open,
  inProgress,
  waiting,
  resolved,
  closed;

  static HubStatus parse(String? v) => switch (v) {
        'in_progress' => inProgress,
        'waiting' => waiting,
        'resolved' => resolved,
        'closed' => closed,
        _ => open,
      };

  String get wire => switch (this) {
        inProgress => 'in_progress',
        waiting => 'waiting',
        resolved => 'resolved',
        closed => 'closed',
        open => 'open',
      };

  bool get active => this == open || this == inProgress || this == waiting;
}

enum HubSegment { mine, toResolve }

/// The status chips. [mineFilters] / [toResolveFilters] say which ones each list offers.
enum HubFilter { all, open, inProgress, resolved, closed, active, overdue, unread }

const List<HubFilter> mineFilters = [HubFilter.all, HubFilter.open, HubFilter.inProgress, HubFilter.resolved, HubFilter.closed];
const List<HubFilter> toResolveFilters = [HubFilter.active, HubFilter.overdue, HubFilter.unread, HubFilter.resolved, HubFilter.closed];

HubFilter defaultFilter(HubSegment s) => s == HubSegment.mine ? HubFilter.all : HubFilter.active;

/// A name in both languages (organizations and departments carry both); [text] follows the app language.
class HubName {
  const HubName(this.ar, this.en);
  final String ar;
  final String en;

  String get text {
    final a = ar.trim(), e = en.trim();
    if (AppConfig.lang == 'ar') return a.isNotEmpty ? a : e;
    return e.isNotEmpty ? e : a;
  }

  bool get isEmpty => ar.trim().isEmpty && en.trim().isEmpty;

  static HubName? of(Object? m) {
    if (m is! Map) return null;
    final n = HubName('${m['name_ar'] ?? ''}', '${m['name_en'] ?? ''}');
    return n.isEmpty ? null : n;
  }
}

/// One complaint on the page, whatever its source.
class HubRow {
  const HubRow({
    required this.source,
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.snippet = '',
    this.ref,
    this.priority = 'medium',
    this.dueAt,
    this.unread = false,
    this.replies = 0,
    this.attachments = 0,
    this.orgId,
    this.org,
    this.department,
    this.about,
    this.category,
    this.sender,
    this.senderImage,
    this.anonymous = false,
    this.canAct = false,
    this.mine = true,
  });

  final HubSource source;
  final int id;
  final String title;
  final String snippet;
  final String? ref;
  final HubStatus status;

  /// low · medium · high · urgent
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The organization's reply-by (naive UTC on the wire); null for a platform complaint.
  final DateTime? dueAt;

  /// Something new for ME: a reply on my complaint, or (to resolve) a complaint / follow-up nobody on staff opened.
  final bool unread;
  final int replies;
  final int attachments;
  final int? orgId;
  final HubName? org;
  final HubName? department;

  /// What / who a platform complaint is about (a course, a teacher …).
  final String? about;
  final String? category;

  /// Who sent it (to resolve); null with [anonymous] when the organization hides the identity.
  final String? sender;
  final String? senderImage;
  final bool anonymous;

  /// The server lets ME change it (to resolve).
  final bool canAct;
  final bool mine;

  String get key => '${source.name}:$id';

  HubRow copyWith({HubStatus? status, bool? unread, DateTime? updatedAt}) => HubRow(
        source: source,
        id: id,
        title: title,
        snippet: snippet,
        ref: ref,
        status: status ?? this.status,
        priority: priority,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        dueAt: dueAt,
        unread: unread ?? this.unread,
        replies: replies,
        attachments: attachments,
        orgId: orgId,
        org: org,
        department: department,
        about: about,
        category: category,
        sender: sender,
        senderImage: senderImage,
        anonymous: anonymous,
        canAct: canAct,
        mine: mine,
      );

  /// A platform complaint (`ComplaintOut`). [mine]: the caller filed it.
  factory HubRow.fromPlatform(ComplaintModel m, {required bool mine}) {
    final about = (m.targetType != null && m.targetType != 'general' && (m.targetLabel ?? '').isNotEmpty)
        ? m.targetLabel
        : m.courseTitle;
    return HubRow(
      source: HubSource.platform,
      id: m.id,
      title: m.title,
      snippet: m.description,
      status: HubStatus.parse(m.status.toJson()),
      priority: m.priority.toJson(),
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
      unread: mine ? !m.isReadByUser : !m.isReadByAdmin,
      replies: m.repliesCount,
      attachments: m.attachments.length,
      about: about,
      category: m.category.toJson(),
      sender: mine ? null : m.userName,
      senderImage: mine ? null : m.userImage,
      canAct: !mine,
      mine: mine,
    );
  }

  /// An organization complaint (`complaint_dict` + `department` / `org` / `can_act`). [orgNames]: names of the
  /// person's organizations by id, for the rows that carry only `org_id` (`GET /org/public/me/complaints`).
  factory HubRow.fromOrg(Map<String, dynamic> j, {required bool mine, Map<int, HubName> orgNames = const {}}) {
    final user = j['user'] is Map ? j['user'] as Map : const {};
    final orgId = _int(j['org_id']) ?? _int((j['org'] is Map ? j['org'] as Map : const {})['id']);
    final hidden = !mine && user['id'] == null;
    final updated = j['updated_at'] ?? j['created_at'];
    return HubRow(
      source: HubSource.org,
      id: _int(j['id']) ?? 0,
      ref: (j['ref'] ?? '').toString().isEmpty ? null : '${j['ref']}',
      title: '${j['subject'] ?? ''}',
      snippet: '${j['body'] ?? ''}',
      status: HubStatus.parse('${j['status'] ?? 'open'}'),
      priority: '${j['priority'] ?? 'medium'}',
      createdAt: complaintUtc(j['created_at']),
      updatedAt: complaintUtc(updated),
      dueAt: j['due_at'] == null ? null : complaintUtc(j['due_at']),
      unread: j['unread'] == true,
      attachments: j['attachments'] is List ? (j['attachments'] as List).length : 0,
      orgId: orgId,
      org: HubName.of(j['org']) ?? (orgId == null ? null : orgNames[orgId]),
      department: HubName.of(j['department']),
      category: j['category']?.toString(),
      sender: mine || hidden ? null : user['name']?.toString(),
      senderImage: mine || hidden ? null : user['image_url']?.toString(),
      anonymous: hidden, // the server sends no sender id when department staff may not see who it is
      canAct: !mine && j['can_act'] == true,
      mine: mine,
    );
  }
}

int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');

// ── order ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// Hours an organization gives each priority to answer (the server's SLA_HOURS). Used to ORDER platform complaints,
/// which have no reply-by of their own.
int slaHours(String priority) => switch (priority) {
      'urgent' => 24,
      'high' => 48,
      'low' => 120,
      _ => 72,
    };

int priorityRank(String p) => switch (p) {
      'urgent' => 0,
      'high' => 1,
      'medium' => 2,
      _ => 3,
    };

DateTime effectiveDue(HubRow r) => r.dueAt ?? r.createdAt.add(Duration(hours: slaHours(r.priority)));

bool isOverdue(HubRow r, DateTime now) => r.status.active && r.dueAt != null && r.dueAt!.isBefore(now);

/// My complaints: unread first, then the latest change first.
List<HubRow> sortMine(Iterable<HubRow> rows) {
  final out = rows.toList();
  out.sort((a, b) {
    if (a.unread != b.unread) return a.unread ? -1 : 1;
    final c = b.updatedAt.compareTo(a.updatedAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  return out;
}

/// To resolve: most urgent first (see the file header); finished ones after, latest change first.
List<HubRow> sortToResolve(Iterable<HubRow> rows, DateTime now) {
  final out = rows.toList();
  out.sort((a, b) {
    if (a.status.active != b.status.active) return a.status.active ? -1 : 1;
    if (!a.status.active) return b.updatedAt.compareTo(a.updatedAt);
    final ao = effectiveDue(a).isBefore(now), bo = effectiveDue(b).isBefore(now);
    if (ao != bo) return ao ? -1 : 1;
    final d = effectiveDue(a).compareTo(effectiveDue(b));
    if (d != 0) return d;
    final p = priorityRank(a.priority).compareTo(priorityRank(b.priority));
    if (p != 0) return p;
    if (a.unread != b.unread) return a.unread ? -1 : 1;
    return a.createdAt.compareTo(b.createdAt);
  });
  return out;
}

/// Platform + organization rows of one list, without duplicates (a refresh may race an optimistic update).
List<HubRow> mergeRows(Iterable<HubRow> a, Iterable<HubRow> b) {
  final seen = <String>{};
  return [
    for (final r in [...a, ...b])
      if (seen.add(r.key)) r,
  ];
}

// ── filters ─────────────────────────────────────────────────────────────────────────────────────────────────────

bool matchesFilter(HubRow r, HubFilter f, DateTime now) => switch (f) {
      HubFilter.all => true,
      HubFilter.open => r.status == HubStatus.open,
      HubFilter.inProgress => r.status == HubStatus.inProgress || r.status == HubStatus.waiting,
      HubFilter.resolved => r.status == HubStatus.resolved,
      HubFilter.closed => r.status == HubStatus.closed,
      HubFilter.active => r.status.active,
      HubFilter.overdue => isOverdue(r, now),
      HubFilter.unread => r.unread && r.status.active,
    };

/// Case-insensitive match on the title, text, reference, sender, organization, department and subject.
bool matchesQuery(HubRow r, String q) {
  final s = q.trim().toLowerCase();
  if (s.isEmpty) return true;
  final hay = [
    r.title,
    r.snippet,
    r.ref ?? '',
    r.sender ?? '',
    r.about ?? '',
    r.org?.ar ?? '',
    r.org?.en ?? '',
    r.department?.ar ?? '',
    r.department?.en ?? '',
  ].join('\n').toLowerCase();
  return hay.contains(s);
}

List<HubRow> visibleRows(List<HubRow> rows, HubSegment seg, HubFilter f, String q, DateTime now) {
  final kept = rows.where((r) => matchesFilter(r, f, now) && matchesQuery(r, q));
  return seg == HubSegment.mine ? sortMine(kept) : sortToResolve(kept, now);
}

Map<HubFilter, int> filterCounts(List<HubRow> rows, List<HubFilter> filters, DateTime now) => {
      for (final f in filters) f: rows.where((r) => matchesFilter(r, f, now)).length,
    };

/// The number on the "To resolve" segment: everything still open there.
int toResolveBadge(List<HubRow> rows) => rows.where((r) => r.status.active).length;

/// The number on the "My complaints" segment: my complaints with an unread reply.
int mineBadge(List<HubRow> rows) => rows.where((r) => r.unread).length;

/// "To resolve" is offered to everyone but students and parents, and to anyone who has something there.
bool offersToResolve({required String? role, required bool hasRows}) =>
    hasRows || !(role == null || role == 'student' || role == 'parent');

// ── SLA chip · quick actions · time label ───────────────────────────────────────────────────────────────────────

/// The organization's reply-by of an open complaint: [overdue] + how long ago / how long left.
class HubSla {
  const HubSla({required this.overdue, required this.span});
  final bool overdue;
  final Duration span;

  /// Due within 12 hours (and not yet late).
  bool get soon => !overdue && span.inHours < 12;
}

HubSla? slaOf(HubRow r, DateTime now) {
  if (!r.status.active || r.dueAt == null) return null;
  final left = r.dueAt!.difference(now);
  return left.isNegative ? HubSla(overdue: true, span: -left) : HubSla(overdue: false, span: left);
}

enum HubAction { reply, start, resolve }

/// What the row offers without opening it (to resolve, when the server lets me act on it).
List<HubAction> quickActionsFor(HubRow r) {
  if (r.mine || !r.canAct || !r.status.active) return const [];
  return r.status == HubStatus.open
      ? const [HubAction.reply, HubAction.start, HubAction.resolve]
      : const [HubAction.reply, HubAction.resolve];
}

/// The status a quick action moves the complaint to (null: it opens the thread instead).
HubStatus? statusAfter(HubAction a) => switch (a) {
      HubAction.start => HubStatus.inProgress,
      HubAction.resolve => HubStatus.resolved,
      HubAction.reply => null,
    };

String _n(String key, int n) => key.tr.replaceAll('{n}', '$n');

/// A compact span: 45 min · 5 h · 3 d.
String spanLabel(Duration d) {
  if (d.inMinutes < 60) return _n('chub_span_min', d.inMinutes.clamp(1, 59));
  if (d.inHours < 48) return _n('chub_span_h', d.inHours);
  return _n('chub_span_d', d.inDays);
}

/// "just now" · "12 min ago" · "5 h ago" · "3 d ago"; older → null (the caller shows the date through AppTime).
String? agoLabel(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'chub_just_now'.tr;
  if (d.inMinutes < 60) return _n('chub_ago_min', d.inMinutes);
  if (d.inHours < 24) return _n('chub_ago_h', d.inHours);
  if (d.inDays < 7) return _n('chub_ago_d', d.inDays);
  return null;
}
