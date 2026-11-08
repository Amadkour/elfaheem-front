// lib/features/shared/live/meeting_links.dart — the person's meeting links (D-307): every online room they can open
// from 7 days back to 60 days ahead — their calendar meetings (owned or accepted / pending invitations) and the live
// sessions of the courses they teach or study — with its status, its app link and, for the host, the guest link.
// ONE call, `GET /api/v1/me/meeting-links` (../back/routers/share_links_router.py); pure parsing and filtering here,
// the page is meeting_links_page.dart. Tests: test/org/meeting_links_test.dart.
library;

import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import '../../../core/share/app_links.dart';

enum MeetingLinkStatus {
  live,
  scheduled,
  ended;

  static MeetingLinkStatus parse(Object? v) => switch ('$v') {
        'live' => live,
        'ended' => ended,
        _ => scheduled,
      };
}

/// The guest link of a room the person hosts (`/live/<token>`, no account needed).
class MeetingGuestLink {
  const MeetingGuestLink({
    required this.url,
    this.hasPin = false,
    this.direct = false,
    this.canPublish = false,
    this.guestsJoined = 0,
    this.active = true,
  });

  final String url;
  final bool hasPin, direct, canPublish;
  final int guestsJoined;

  /// False once the room ended (`link_status: expired`): the link no longer lets anyone in.
  final bool active;

  static MeetingGuestLink? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = '${j['url'] ?? ''}';
    if (url.isEmpty) return null;
    return MeetingGuestLink(
      url: url,
      hasPin: j['has_pin'] == true,
      direct: j['direct'] == true,
      canPublish: j['can_publish'] == true,
      guestsJoined: j['guests_joined'] is num ? (j['guests_joined'] as num).toInt() : 0,
      active: '${j['link_status'] ?? 'active'}' != 'expired',
    );
  }
}

class MeetingLinkItem {
  const MeetingLinkItem({
    required this.kind,
    required this.refId,
    required this.title,
    required this.status,
    required this.appLink,
    this.subtitle,
    this.courseId,
    this.orgName,
    this.startsAt,
    this.endsAt,
    this.isHost = false,
    this.recurring = false,
    this.myStatus,
    this.guest,
  });

  /// `meeting` (a calendar meeting) · `session` (a course's live session).
  final String kind;
  final int refId;
  final String title;
  final String? subtitle;
  final int? courseId;
  final String? orgName;
  final DateTime? startsAt, endsAt;
  final MeetingLinkStatus status;
  final bool isHost, recurring;

  /// owner · accepted · pending · proposed (an invitation), null for a course session I study.
  final String? myStatus;
  final String appLink;
  final MeetingGuestLink? guest;

  bool get isMeeting => kind == 'meeting';
  String get key => '$kind:$refId';

  /// The link of the one scheme (D-307) — what Copy / Share hand out to members.
  AppLink get link => isMeeting ? AppLink.meeting(refId) : AppLink.session(refId);

  static DateTime? _date(Object? v) {
    final s = '${v ?? ''}';
    if (s.isEmpty || s == 'null') return null;
    final d = DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
    return d?.toUtc();
  }

  static MeetingLinkItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = '${j['kind'] ?? ''}';
    final id = j['ref_id'] is num ? (j['ref_id'] as num).toInt() : 0;
    if ((kind != 'meeting' && kind != 'session') || id <= 0) return null;
    final ar = AppConfig.lang == 'ar';
    final org = j['org'];
    final orgName = org is Map ? '${(ar ? org['name_ar'] : org['name_en']) ?? org['name_ar'] ?? org['name_en'] ?? ''}' : '';
    final title = j['title_auto'] == true
        ? (ar ? 'حصة مباشرة' : 'Live session')
        : '${j['title'] ?? ''}'.trim();
    final sub = '${j['subtitle'] ?? ''}'.trim();
    return MeetingLinkItem(
      kind: kind,
      refId: id,
      title: title.isEmpty ? (kind == 'meeting' ? (ar ? 'اجتماع' : 'Meeting') : (ar ? 'حصة مباشرة' : 'Live session')) : title,
      subtitle: sub.isEmpty || sub == 'null' ? null : sub,
      courseId: j['course_id'] is num ? (j['course_id'] as num).toInt() : null,
      orgName: orgName.isEmpty || orgName == 'null' ? null : orgName,
      startsAt: _date(j['starts_at']),
      endsAt: _date(j['ends_at']),
      status: MeetingLinkStatus.parse(j['status']),
      isHost: j['is_host'] == true,
      recurring: j['recurring'] == true,
      myStatus: j['my_status'] is String ? j['my_status'] as String : null,
      appLink: '${j['app_link'] ?? ''}',
      guest: MeetingGuestLink.fromJson(j['guest_link']),
    );
  }
}

class MeetingLinksData {
  const MeetingLinksData(this.items);
  final List<MeetingLinkItem> items;

  int count(MeetingLinksFilter f) => filterMeetingLinks(items, f, '').length;

  static MeetingLinksData fromJson(Object? j) {
    final raw = j is Map ? j['items'] : null;
    return MeetingLinksData([
      if (raw is List)
        for (final x in raw) ?MeetingLinkItem.fromJson(x),
    ]);
  }
}

/// The page's filter chips.
enum MeetingLinksFilter { all, live, upcoming, hosting, guestLinks, past }

/// [items] kept by [filter] and the search [query] (title, course / host name, organization), in the server's order
/// (live first, then the next ones by time, the ended ones last, newest first).
List<MeetingLinkItem> filterMeetingLinks(List<MeetingLinkItem> items, MeetingLinksFilter filter, String query) {
  final q = query.trim().toLowerCase();
  bool keep(MeetingLinkItem i) => switch (filter) {
        MeetingLinksFilter.all => true,
        MeetingLinksFilter.live => i.status == MeetingLinkStatus.live,
        MeetingLinksFilter.upcoming => i.status == MeetingLinkStatus.scheduled,
        MeetingLinksFilter.hosting => i.isHost,
        MeetingLinksFilter.guestLinks => i.guest != null,
        MeetingLinksFilter.past => i.status == MeetingLinkStatus.ended,
      };
  bool match(MeetingLinkItem i) =>
      q.isEmpty ||
      [i.title, i.subtitle, i.orgName].any((s) => s != null && s.toLowerCase().contains(q));
  return [for (final i in items) if (keep(i) && match(i)) i];
}

/// The one call of the page.
class MeetingLinksApi {
  const MeetingLinksApi();

  Future<MeetingLinksData> load() async =>
      MeetingLinksData.fromJson(await ApiClient().get('/api/v1/me/meeting-links'));
}
