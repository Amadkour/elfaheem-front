// lib/features/shared/inbox/unified_inbox.dart
//
// ONE way to show requests, forms, announcements and ads to every role (point 14) — the "Inbox" pattern:
//
//   segments      To do · Announcements · Offers · Done       (the server's `segment` of each row)
//   the page      InboxPage (inbox_page.dart): ONE page with the tabs To do · Notifications · Announcements & offers
//                 · Done — the segments mapped onto them (news + offers share one tab) and the notifications list as
//                 a tab of the same page; the bell, the home entry and the old routes open it on the right tab
//   order         overdue → due soon → new → rest  (mandatory first, nearest deadline, newest)   [sortInbox]
//   cards         dense but calm: kind icon, title, where it comes from, status / urgency chips, a live countdown
//                 rendered with AppTime ("Due in 2 d · 14 Oct, 3:00 PM"), overdue highlighted
//   actions       tap → the right screen (fill the form, the availability grid, the ack sheet, the approval page …);
//                 swipe an announcement / offer away to hide it (remembered on the device)
//   states        skeleton while loading, a friendly empty state per segment, retry on failure
//
// Data: GET /api/v1/me/inbox[?org_id=] (backend routers/organization/org_me_router.py). The same widget is used by
// the student, teacher (and assistant), parent and organization-member homes:
//   InboxEntry         a home's door to the inbox: ONE slim tappable row (icon · "Inbox" · "3 to do · 1 overdue" ·
//                      count · chevron) over counts the home already has (/me/home) → opens InboxScreen
//   InboxEntryCard     the same entry loading its own counts (GET /me/inbox): the parent's Children tab, an older server
//   InboxScreen        the full page (InboxPage, on a tab)
//   InboxSegmentList   one tab's list (one or more segments, cards)
//   UnifiedInbox       the embeddable list (segment chips + cards)
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/inbox_badge.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseModel;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList;
import '../../ads/ads_pages.dart' show AdCard;
import '../../org/home_org_mix.dart' show showPlatformRequirement;
import '../../org/org_terms_pages.dart' show TermCard;
import '../../org/org_v3.dart' show orgParseUtc;
import '../../parent/parent_dashboard_screen.dart' show ParentTabProvider;
import '../notification/notifications_provider.dart' show NotificationsProvider;
import 'inbox_page.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Model + pure logic (unit-tested)
// ═════════════════════════════════════════════════════════════════════════════

enum InboxSegment { todo, news, offers, done }

InboxSegment _segmentOf(String? s) => switch (s) {
      'news' => InboxSegment.news,
      'offers' => InboxSegment.offers,
      'done' => InboxSegment.done,
      _ => InboxSegment.todo,
    };

class InboxItem {
  InboxItem(this.raw)
      : key = '${raw['key'] ?? ''}',
        kind = '${raw['kind'] ?? ''}',
        segment = _segmentOf('${raw['segment'] ?? ''}'),
        title = '${raw['title'] ?? ''}',
        subtitle = (raw['subtitle'] ?? '').toString().trim(),
        orgId = raw['org_id'] == null ? null : asInt(raw['org_id']),
        organization = asMap(raw['organization']),
        department = asMap(raw['department']),
        dueAt = orgParseUtc(raw['due_at']),
        createdAt = orgParseUtc(raw['created_at']),
        status = '${raw['status'] ?? ''}',
        mandatory = raw['mandatory'] == true,
        blocking = raw['blocking'] == true,
        serverUrgency = '${raw['urgency'] ?? 'normal'}',
        action = asMap(raw['action']),
        data = asMap(raw['data']);

  final Map<String, dynamic> raw;
  final String key, kind, title, subtitle, status, serverUrgency;
  final InboxSegment segment;
  final int? orgId;
  final Map<String, dynamic> organization, department, action, data;
  final DateTime? dueAt, createdAt;
  final bool mandatory, blocking;

  bool get required => mandatory || blocking;
}

/// overdue · due_soon · new · normal — recomputed on the device so a screen left open stays true.
/// Offers never become "overdue" (an ended offer simply disappears on the next load).
String inboxUrgency(InboxItem x, DateTime now) {
  final due = x.dueAt;
  if (x.kind == 'approval' && x.serverUrgency == 'overdue') return 'overdue';
  if (due != null) {
    final left = due.difference(now);
    if (left.isNegative) return x.kind == 'ad' || x.kind == 'exam' ? 'normal' : 'overdue'; // an exam that started is on now
    if (left <= const Duration(hours: 72)) return 'due_soon';
  }
  final created = x.createdAt;
  if (created != null && now.difference(created) <= const Duration(hours: 72)) return 'new';
  return 'normal';
}

const _rank = {'overdue': 0, 'due_soon': 1, 'new': 2, 'normal': 3};

/// overdue → due soon → new → rest; inside a bucket: required first, nearest deadline, then newest.
List<InboxItem> sortInbox(List<InboxItem> items, DateTime now) {
  final out = [...items];
  out.sort((a, b) {
    final r = _rank[inboxUrgency(a, now)]!.compareTo(_rank[inboxUrgency(b, now)]!);
    if (r != 0) return r;
    if (a.required != b.required) return a.required ? -1 : 1;
    final da = a.dueAt, db = b.dueAt;
    if (da != null || db != null) {
      if (da == null) return 1;
      if (db == null) return -1;
      final d = da.compareTo(db);
      if (d != 0) return d;
    }
    final ca = a.createdAt, cb = b.createdAt;
    if (ca == null && cb == null) return 0;
    if (ca == null) return 1;
    if (cb == null) return -1;
    return cb.compareTo(ca);
  });
  return out;
}

/// "3 min" · "5 h" · "2 d" (translated units).
String inboxSpan(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 60) return 'inbox_unit_m'.tr.replaceAll('{n}', '${m < 1 ? 1 : m}');
  final h = d.inHours.abs();
  if (h < 48) return 'inbox_unit_h'.tr.replaceAll('{n}', '$h');
  return 'inbox_unit_d'.tr.replaceAll('{n}', '${d.inDays.abs()}');
}

/// "Due in 5 h" / "Overdue by 2 d" / "Ends in 3 d" — null when there is no deadline.
String? inboxCountdown(InboxItem x, DateTime now) {
  final due = x.dueAt;
  if (due == null) return null;
  final left = due.difference(now);
  if (x.kind == 'ad') return left.isNegative ? null : 'inbox_ends_in'.tr.replaceAll('{t}', inboxSpan(left));
  if (x.kind == 'exam') return left.isNegative ? null : 'inbox_starts_in'.tr.replaceAll('{t}', inboxSpan(left));
  return left.isNegative
      ? 'inbox_overdue_by'.tr.replaceAll('{t}', inboxSpan(left))
      : 'inbox_due_in'.tr.replaceAll('{t}', inboxSpan(left));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Controller
// ═════════════════════════════════════════════════════════════════════════════

class InboxController extends ChangeNotifier {
  InboxController({this.orgId});
  final int? orgId;

  static const _path = '/api/v1/me/inbox';
  static final Map<String, Map<String, dynamic>> _cache = {};     // instant paint on re-open, then refresh
  static const _hiddenKey = 'inbox_hidden_v1';

  List<InboxItem> items = const [];
  Map<String, dynamic> counts = const {};
  Set<String> hidden = {};
  bool loading = true, failed = false;
  bool _disposed = false;

  String get _cacheKey => '${orgId ?? 'all'}';

  Future<void> load() async {
    final cached = _cache[_cacheKey];
    if (cached != null && items.isEmpty) _apply(cached);
    if (hidden.isEmpty) {
      try {
        final p = await SharedPreferences.getInstance();
        hidden = (p.getStringList(_hiddenKey) ?? const []).toSet();
      } catch (_) {}
    }
    try {
      final r = await ApiClient().get(_path, queryParams: {if (orgId != null) 'org_id': orgId});
      if (r is Map) {
        final m = Map<String, dynamic>.from(r);
        _cache[_cacheKey] = m;
        _apply(m);
        failed = false;
        // the whole inbox (never an organization's slice) is the bell's To do count
        if (orgId == null) InboxBadge.instance.setTodo(countOf(InboxSegment.todo));
      }
    } catch (_) {
      failed = items.isEmpty;
    }
    loading = false;
    _notify();
  }

  void _apply(Map<String, dynamic> m) {
    items = asMapList(m['items']).map(InboxItem.new).toList();
    counts = asMap(m['counts']);
    loading = false;
  }

  List<InboxItem> of(InboxSegment s) =>
      sortInbox(items.where((x) => x.segment == s && !hidden.contains(x.key)).toList(), DateTime.now());

  int countOf(InboxSegment s) => items.where((x) => x.segment == s && !hidden.contains(x.key)).length;

  int get overdue => of(InboxSegment.todo).where((x) => inboxUrgency(x, DateTime.now()) == 'overdue').length;
  int get dueSoon => of(InboxSegment.todo).where((x) => inboxUrgency(x, DateTime.now()) == 'due_soon').length;

  Future<void> hide(InboxItem x) async {
    hidden = {...hidden, x.key};
    _notify();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_hiddenKey, hidden.take(400).toList());
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Visual language
// ═════════════════════════════════════════════════════════════════════════════

String inboxSegmentLabel(InboxSegment s) => switch (s) {
      InboxSegment.todo => 'inbox_seg_todo'.tr,
      InboxSegment.news => 'inbox_seg_news'.tr,
      InboxSegment.offers => 'inbox_seg_offers'.tr,
      InboxSegment.done => 'inbox_seg_done'.tr,
    };

IconData _segmentIcon(InboxSegment s) => switch (s) {
      InboxSegment.todo => Icons.task_alt_rounded,
      InboxSegment.news => Icons.campaign_rounded,
      InboxSegment.offers => Icons.local_offer_rounded,
      InboxSegment.done => Icons.inventory_2_rounded,
    };

IconData _kindIcon(InboxItem x) => switch (x.kind) {
      'form' => x.data['kind'] == 'survey' ? Icons.poll_rounded : Icons.edit_document,
      'availability' => Icons.event_available_rounded,
      'terms' => Icons.gavel_rounded,
      'department_choice' => Icons.how_to_vote_rounded,
      'platform' => Icons.verified_user_rounded,
      'request' => Icons.receipt_long_rounded,
      'complaint_reply' => Icons.mark_chat_unread_rounded,
      'approval' => switch ('${x.action['what']}') {
          'complaints' => Icons.support_agent_rounded,
          'join_requests' => Icons.person_add_alt_1_rounded,
          'unit_requests' => Icons.group_add_rounded,
          _ => Icons.fact_check_rounded,
        },
      'announcement' => x.data['is_pinned'] == true ? Icons.push_pin_rounded : Icons.campaign_rounded,
      'ad' => Icons.local_offer_rounded,
      'parent_link' => Icons.family_restroom_rounded,
      'exam' => Icons.event_note_rounded,
      _ => Icons.notifications_rounded,
    };

String _kindLabel(InboxItem x) => switch (x.kind) {
      'form' => x.data['kind'] == 'survey' ? 'inbox_kind_survey'.tr : 'inbox_kind_form'.tr,
      'availability' => 'inbox_kind_availability'.tr,
      'terms' => 'inbox_kind_terms'.tr,
      'department_choice' => 'inbox_kind_department_choice'.tr,
      'platform' => 'inbox_kind_platform'.tr,
      'request' => 'inbox_kind_request'.tr,
      'complaint_reply' => 'inbox_kind_complaint_reply'.tr,
      'approval' => 'inbox_kind_approval'.tr,
      'announcement' => 'inbox_kind_announcement'.tr,
      'ad' => 'inbox_kind_ad'.tr,
      'parent_link' => 'inbox_kind_parent_link'.tr,
      'exam' => 'inbox_kind_exam'.tr,
      _ => '',
    };

/// Approvals are counted server-side; the human sentence is built here (both languages).
String _title(InboxItem x) {
  if (x.kind == 'exam') {
    final m = asMap(x.data['course']);
    final ar = '${m['name_ar'] ?? ''}', en = '${m['name_en'] ?? ''}';
    final name = AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
    return name.isEmpty ? x.title : name;
  }
  if (x.kind != 'approval') return x.title;
  return approvalCountText('${x.action['what']}', asInt(x.data['count']));
}

/// "3 requests waiting for your review" with the right plural form (L2: "1 طلبات" / "1 requests").
String approvalCountText(String what, int n, {String? lang}) => switch (what) {
      'complaints' => countText(n,
          ar1: 'شكوى واحدة مفتوحة في نطاقك', ar2: 'شكويان مفتوحتان في نطاقك', arFew: '{n} شكاوى مفتوحة في نطاقك',
          arMany: '{n} شكوى مفتوحة في نطاقك', en1: '1 open complaint in your area', en: '{n} open complaints in your area',
          lang: lang),
      'join_requests' => countText(n,
          ar1: 'طلب انضمام واحد للمؤسسة', ar2: 'طلبا انضمام للمؤسسة', arFew: '{n} طلبات انضمام للمؤسسة',
          arMany: '{n} طلب انضمام للمؤسسة', en1: '1 person asking to join', en: '{n} people asking to join', lang: lang),
      'unit_requests' => countText(n,
          ar1: 'طلب انضمام واحد لقسم', ar2: 'طلبا انضمام لأقسام', arFew: '{n} طلبات انضمام لأقسام',
          arMany: '{n} طلب انضمام لأقسام', en1: '1 department join request', en: '{n} department join requests',
          lang: lang),
      _ => countText(n,
          ar1: 'طلب واحد ينتظر مراجعتك', ar2: 'طلبان ينتظران مراجعتك', arFew: '{n} طلبات تنتظر مراجعتك',
          arMany: '{n} طلبًا تنتظر مراجعتك', en1: '1 request waiting for your review',
          en: '{n} requests waiting for your review', lang: lang),
    };

(String, Color)? _statusChip(BuildContext context, InboxItem x) {
  final c = context.colors;
  return switch (x.status) {
    'submitted' || 'in_review' || 'pending' => ('inbox_status_review'.tr, c.warning),
    'approved' => ('inbox_status_approved'.tr, c.success),
    'rejected' => ('inbox_status_rejected'.tr, c.danger),
    'resolved' || 'closed' => ('inbox_status_closed'.tr, c.success),
    'invigilator' when x.kind == 'exam' => ('inbox_exam_invigilate'.tr, c.primary),
    _ => null,
  };
}

Color _urgencyColor(BuildContext context, String u) {
  final c = context.colors;
  return switch (u) {
    'overdue' => c.danger,
    'due_soon' => c.warning,
    'new' => c.primary,
    _ => c.textLight,
  };
}

String _orgLine(InboxItem x) {
  String name(Map<String, dynamic> m) {
    final ar = '${m['name_ar'] ?? ''}', en = '${m['name_en'] ?? ''}';
    return AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  return [
    if (x.organization.isNotEmpty) name(x.organization),
    if (x.department.isNotEmpty) name(x.department),
  ].where((s) => s.isNotEmpty).join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Card
// ═════════════════════════════════════════════════════════════════════════════

class InboxCard extends StatelessWidget {
  const InboxCard({super.key, required this.item, required this.onTap});
  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final x = item;
    final u = inboxUrgency(x, now);
    final tone = u == 'normal' ? c.primary : _urgencyColor(context, u);
    final countdown = inboxCountdown(x, now);
    final status = _statusChip(context, x);
    final where = _orgLine(x);
    final count = x.kind == 'approval' ? asInt(x.data['count']) : 0;
    final overdue = u == 'overdue';
    return Semantics(
      button: true,
      label: _title(x),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: onTap,
          child: Ink(
            // paper on a warm hairline, no resting shadow (D-612); an overdue row says so with a danger edge
            decoration: BoxDecoration(
              color: overdue ? Color.alphaBlend(c.danger.withValues(alpha: 0.05), c.cardBg) : c.cardBg,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: overdue ? c.danger.withValues(alpha: 0.45) : c.divider, width: AppBorder.hairline),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.md),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: AppTouch.min - AppSpace.xxs,
                  height: AppTouch.min - AppSpace.xxs,
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Icon(_kindIcon(x), color: appInk(context, tone), size: AppIconSize.md + 2),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(_kindLabel(x),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta(context)),
                      ),
                      if (u == 'new' && x.segment != InboxSegment.done)
                        Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(_title(x), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w600, c: c.textDark, h: 1.3)),
                    if (where.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
                        child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                      ),
                    if (x.subtitle.isNotEmpty && x.kind != 'approval')
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xxs),
                        child: Text(x.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium, h: 1.4)),
                      ),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs + 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (overdue) AppTag('inbox_overdue'.tr, c.danger, icon: Icons.error_outline_rounded),
                      if (u == 'due_soon' && x.kind != 'ad' && x.kind != 'exam') AppTag('inbox_due_soon'.tr, c.warning, icon: Icons.schedule_rounded),
                      if (x.required && x.segment == InboxSegment.todo) AppTag('inbox_mandatory'.tr, c.danger, icon: Icons.priority_high_rounded),
                      if (status != null) AppTag(status.$1, status.$2),
                      if (x.kind == 'approval' && asInt(x.data['assigned_to_me']) > 0)
                        AppTag('inbox_assigned_to_me'.tr.replaceAll('{n}', '${asInt(x.data['assigned_to_me'])}'), c.primary,
                            icon: Icons.person_pin_rounded),
                      if (countdown != null)
                        _Meta(icon: Icons.timer_outlined, text: countdown, color: overdue ? c.danger : c.textMedium),
                      if (x.dueAt != null && x.kind != 'ad')
                        _Meta(icon: Icons.event_rounded, text: AppTime.dateTime(x.dueAt!.toUtc()), color: c.textLight),
                      if (x.dueAt == null && x.createdAt != null)
                        _Meta(icon: Icons.access_time_rounded, text: relTime(x.createdAt!.toUtc().toIso8601String()), color: c.textLight),
                      if ('${x.data['ref'] ?? ''}'.isNotEmpty)
                        _Meta(icon: Icons.tag_rounded, text: '${x.data['ref']}', color: c.textLight, ltr: true),
                    ]),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                if (count > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: AppSpace.lg + 2),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs - 1),
                    decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('$count', textAlign: TextAlign.center, style: appText(12, w: FontWeight.w600, c: context.colors.onHero)),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: c.textLight),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.color, this.ltr = false});
  final IconData icon;
  final String text;
  final Color color;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.xs, color: color),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: appText(11.5, w: FontWeight.w500, c: color)),
        ),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Segmented filter
// ═════════════════════════════════════════════════════════════════════════════

class InboxSegments extends StatelessWidget {
  const InboxSegments({super.key, required this.value, required this.counts, required this.onChanged, this.segments = InboxSegment.values});
  final InboxSegment value;
  final Map<InboxSegment, int> counts;
  final ValueChanged<InboxSegment> onChanged;
  final List<InboxSegment> segments;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: Row(children: [
        for (final s in segments)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
            child: Semantics(
              selected: s == value,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () => onChanged(s),
                // the chosen pill solid emerald, the rest paper on a hairline: tone, not a glow (D-614)
                child: AnimatedContainer(
                  duration: AppMotion.of(context).base,
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xxs),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                  decoration: BoxDecoration(
                    color: s == value ? c.primary : c.cardBg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: s == value ? c.primary : c.divider, width: AppBorder.hairline),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_segmentIcon(s), size: AppIconSize.sm, color: s == value ? context.colors.onHero : c.textMedium),
                    const SizedBox(width: AppSpace.xs - 2),
                    Text(inboxSegmentLabel(s), style: appText(13, w: FontWeight.w600, c: s == value ? context.colors.onHero : c.textMedium)),
                    if ((counts[s] ?? 0) > 0) ...[
                      const SizedBox(width: AppSpace.xs - 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2, vertical: 1),
                        decoration: BoxDecoration(
                          color: s == value ? context.colors.onHero.withValues(alpha: 0.22) : c.blockEmerald,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('${counts[s]}', style: appText(11.5, w: FontWeight.w600, c: s == value ? context.colors.onHero : c.blockAccentInk(c.primary, c.blockEmerald))),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Embeddable list
// ═════════════════════════════════════════════════════════════════════════════

/// Segments + cards. [shrinkWrap] = inside another scroll view (a home); otherwise it scrolls itself.
class UnifiedInbox extends StatefulWidget {
  const UnifiedInbox({super.key, this.orgId, this.initial = InboxSegment.todo, this.shrinkWrap = false, this.limit, this.controller});
  final int? orgId;
  final InboxSegment initial;
  final bool shrinkWrap;
  final int? limit;
  final InboxController? controller;

  @override
  State<UnifiedInbox> createState() => _UnifiedInboxState();
}

class _UnifiedInboxState extends State<UnifiedInbox> {
  late InboxSegment _seg = widget.initial;
  late final InboxController _c = widget.controller ?? InboxController(orgId: widget.orgId);

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _c.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  List<InboxSegment> get _segments =>
      widget.orgId == null ? InboxSegment.values : const [InboxSegment.todo, InboxSegment.news, InboxSegment.done];

  Future<void> _open(InboxItem x) async {
    final changed = await openInboxItem(context, x);
    if (changed && mounted) {
      await _c.load();
      AppModeController.instance.refresh();
    }
  }

  Widget _empty(InboxSegment s) => _segmentEmpty(s);

  Widget _row(InboxItem x) => _inboxRow(context, _c, x, () => _open(x));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final segs = _segments;
        if (!segs.contains(_seg)) _seg = segs.first;
        final all = _c.of(_seg);
        final list = widget.limit == null ? all : all.take(widget.limit!).toList();
        final header = Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: InboxSegments(
            value: _seg,
            segments: segs,
            counts: {for (final s in segs) s: _c.countOf(s)},
            onChanged: (s) => setState(() => _seg = s),
          ),
        );
        Widget body;
        if (_c.loading && _c.items.isEmpty) {
          body = SizedBox(height: 260, child: const AppListSkeleton(items: 3, padding: EdgeInsets.symmetric(horizontal: AppSpace.md)));
        } else if (_c.failed) {
          body = AppEmpty(
            icon: Icons.wifi_off_rounded,
            title: 'inbox_failed'.tr,
            actionLabel: 'inbox_retry'.tr,
            onAction: () => _c.load(),
          );
        } else if (list.isEmpty) {
          body = _empty(_seg);
        } else {
          body = Column(children: [
            for (final x in list)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                child: _row(x),
              ),
          ]);
        }
        final content = AnimatedSwitcher(
          duration: AppMotion.of(context).base,
          child: KeyedSubtree(key: ValueKey('${_seg.name}-${list.length}-${_c.loading}'), child: body),
        );
        if (widget.shrinkWrap) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, content]);
        }
        return AppRefresh(
          onRefresh: _c.load,
          child: ListView(
            padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxl),
            children: [header, content],
          ),
        );
      },
    );
  }
}

/// One row: an offer as its ad card, everything else as an [InboxCard]; an announcement / offer swipes away (hidden
/// on this device).
Widget _inboxRow(BuildContext context, InboxController c, InboxItem x, VoidCallback onOpen) {
  if (x.kind == 'ad') {
    final ad = {...x.data, 'id': x.action['id'], 'title': x.title, 'body': x.subtitle};
    return Dismissible(
      key: ValueKey(x.key),
      onDismissed: (_) => c.hide(x),
      background: _swipeBg(context),
      child: LayoutBuilder(builder: (context, box) {
        return AspectRatio(
          aspectRatio: box.maxWidth > 600 ? 16 / 5.6 : 16 / 8.5,
          child: AdCard(ad: ad, onTap: onOpen),
        );
      }),
    );
  }
  final card = InboxCard(item: x, onTap: onOpen);
  if (x.segment == InboxSegment.news) {
    return Dismissible(key: ValueKey(x.key), onDismissed: (_) => c.hide(x), background: _swipeBg(context), child: card);
  }
  return card;
}

/// The empty state of a segment.
Widget _segmentEmpty(InboxSegment s) {
  final (icon, title, msg) = switch (s) {
    InboxSegment.todo => (Icons.celebration_rounded, 'inbox_empty_todo_title'.tr, 'inbox_empty_todo_msg'.tr),
    InboxSegment.news => (Icons.campaign_rounded, 'inbox_empty_news_title'.tr, 'inbox_empty_news_msg'.tr),
    InboxSegment.offers => (Icons.local_offer_rounded, 'inbox_empty_offers_title'.tr, 'inbox_empty_offers_msg'.tr),
    InboxSegment.done => (Icons.inventory_2_rounded, 'inbox_empty_done_title'.tr, 'inbox_empty_done_msg'.tr),
  };
  return AppEmpty(icon: icon, title: title, message: msg);
}

// ═════════════════════════════════════════════════════════════════════════════
//  One tab's list
// ═════════════════════════════════════════════════════════════════════════════

/// The rows of one tab of [InboxPage] over a shared [controller]: [segments] in that order (announcements, then
/// offers), each under a small heading when more than one of them has rows. Skeleton while the first answer is on
/// its way, a retry on failure, [empty] (else the first segment's) when there is nothing; pull to refresh.
class InboxSegmentList extends StatelessWidget {
  const InboxSegmentList({super.key, required this.controller, required this.segments, this.empty, this.onChanged});

  final InboxController controller;
  final List<InboxSegment> segments;
  final Widget? empty;

  /// Something was answered / decided through a row (the page reloads, the home's counts follow).
  final VoidCallback? onChanged;

  Future<void> _open(BuildContext context, InboxItem x) async {
    final changed = await openInboxItem(context, x);
    if (!changed) return;
    await controller.load();
    AppModeController.instance.refresh();
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final groups = [for (final s in segments) (s, c.of(s))];
        final filled = groups.where((g) => g.$2.isNotEmpty).toList();
        final Widget body;
        if (c.loading && c.items.isEmpty) {
          body = const AppListSkeleton(items: 3, padding: EdgeInsets.symmetric(horizontal: AppSpace.md));
        } else if (c.failed) {
          body = AppEmpty(icon: Icons.wifi_off_rounded, title: 'inbox_failed'.tr, actionLabel: 'inbox_retry'.tr, onAction: c.load);
        } else if (filled.isEmpty) {
          body = empty ?? _segmentEmpty(segments.first);
        } else {
          body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (gi, (s, rows)) in filled.indexed) ...[
              if (filled.length > 1)
                Padding(
                  // editorial rhythm: more air above a heading than under it
                  padding: EdgeInsetsDirectional.fromSTEB(AppSpace.md + AppSpace.xxs, gi == 0 ? AppSpace.xs : AppSpace.lg, AppSpace.md, AppSpace.sm),
                  child: Semantics(
                    header: true,
                    child: Text(inboxSegmentLabel(s), style: AppType.section(context)),
                  ),
                ),
              for (final (i, x) in rows.indexed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                  // ONE entrance: the first rows of the first group rise in once per route
                  child: gi == 0
                      ? AppReveal(index: i, group: 'inbox-${s.name}', cap: 5, child: _inboxRow(context, c, x, () => _open(context, x)))
                      : _inboxRow(context, c, x, () => _open(context, x)),
                ),
            ],
          ]);
        }
        return AppRefresh(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxl),
            children: [body],
          ),
        );
      },
    );
  }
}

Widget _swipeBg(BuildContext context) {
  final c = context.colors;
  return Container(
    alignment: AlignmentDirectional.centerEnd,
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
    decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.visibility_off_rounded, color: c.textMedium, size: AppIconSize.md),
      const SizedBox(width: AppSpace.xs),
      Text('inbox_hide'.tr, style: appText(13, w: FontWeight.w600, c: c.textMedium)),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Full page
// ═════════════════════════════════════════════════════════════════════════════

/// The inbox page ([InboxPage]) — on the tab of [initial] (To do by default), or on [tab] when given (the
/// Notifications tab, for instance). [orgId] = that organization's inbox only (titled [title]).
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, this.orgId, this.initial = InboxSegment.todo, this.title, this.tab});
  final int? orgId;
  final InboxSegment initial;
  final String? title;
  final InboxTab? tab;

  @override
  Widget build(BuildContext context) => InboxPage(orgId: orgId, initial: tab ?? inboxTabOfSegment(initial), title: title);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Home entry
// ═════════════════════════════════════════════════════════════════════════════

/// What a home's inbox entry says: the to-dos (how many are overdue / due soon) and what else waits.
typedef InboxEntryCounts = ({int todo, int overdue, int dueSoon, int news, int offers});

/// The entry's counts: the server's [counts] where it sent them (`inbox_counts` of GET /me/home, or an organization's
/// `todo` block: `todo` · `overdue` · `due_soon` · `news` · `offers`), never fewer than the preview [rows] show
/// (they also carry work an organization's overview leaves out, and an older server sends no counts).
InboxEntryCounts inboxEntryCounts(List<InboxItem> rows, {Map<String, int> counts = const {}, DateTime? now}) {
  final t = now ?? DateTime.now();
  final todo = rows.where((x) => x.segment == InboxSegment.todo).toList();
  int n(String key, int fromRows) {
    final v = counts[key] ?? 0;
    return v > fromRows ? v : fromRows;
  }

  return (
    todo: n('todo', todo.length),
    overdue: n('overdue', todo.where((x) => inboxUrgency(x, t) == 'overdue').length),
    dueSoon: n('due_soon', todo.where((x) => inboxUrgency(x, t) == 'due_soon').length),
    news: n('news', rows.where((x) => x.segment == InboxSegment.news).length),
    offers: n('offers', rows.where((x) => x.segment == InboxSegment.offers).length),
  );
}

/// Something in the inbox to look at (a to-do, an unread notification, an announcement, an offer). The homes draw
/// the entry only then, as they drew the preview before it: no empty door on a fresh account, the greeting already
/// says "all caught up".
bool inboxEntryHasAny(InboxEntryCounts c, {int unread = 0}) => c.todo + unread + c.news + c.offers > 0;

/// Whether a home draws its inbox entry: something to look at ([inboxEntryHasAny]) and the inbox not switched off
/// (kill switch `student_home.inbox`, [kInboxFeatureKey]).
bool inboxEntryShown(InboxEntryCounts c, {int unread = 0}) =>
    !AppConfig.disableList.contains(kInboxFeatureKey) && inboxEntryHasAny(c, unread: unread);

/// The entry's one line: "3 to do · 2 unread · 1 overdue · 2 due soon"; with nothing to do, "You're all caught up"
/// and what else is new ("· 2 announcements · 1 offer").
String inboxEntrySummary(InboxEntryCounts c, {int unread = 0}) {
  if (c.todo > 0 || unread > 0) {
    return [
      if (c.todo > 0) 'inbox_preview_todo'.tr.replaceAll('{n}', '${c.todo}'),
      if (unread > 0) 'inbox_preview_unread'.tr.replaceAll('{n}', '$unread'),
      if (c.overdue > 0) 'inbox_preview_overdue'.tr.replaceAll('{n}', '${c.overdue}'),
      if (c.dueSoon > 0) 'inbox_preview_soon'.tr.replaceAll('{n}', '${c.dueSoon}'),
    ].join(' · ');
  }
  return [
    'inbox_empty_todo_title'.tr,
    if (c.news > 0)
      countText(c.news, ar1: 'إعلان واحد', ar2: 'إعلانان', arFew: '{n} إعلانات', arMany: '{n} إعلانًا', en1: '1 announcement', en: '{n} announcements'),
    if (c.offers > 0)
      countText(c.offers, ar1: 'عرض واحد', ar2: 'عرضان', arFew: '{n} عروض', arMany: '{n} عرضًا', en1: '1 offer', en: '{n} offers'),
  ].join(' · ');
}

/// A home's door to the inbox, in place of the block that listed its rows (the rows live on InboxScreen): ONE slim
/// card row — the inbox icon (on the brand gradient while something is to do, a quiet tint otherwise), "Inbox", the
/// one line that matters ([inboxEntrySummary]; the danger ink when something is overdue), the ACTIONABLE count —
/// to-dos plus [unread] notifications ([inboxActionableCount]; announcements and offers never count) — in its tone
/// (danger overdue · warning due soon · primary) and a chevron that follows the reading direction. Plain values in;
/// [onTap] opens the inbox on its To do tab. The caller decides whether to draw it ([inboxEntryShown]).
class InboxEntry extends StatelessWidget {
  const InboxEntry({super.key, required this.counts, this.unread = 0, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 20)});

  final InboxEntryCounts counts;

  /// Unread notifications (they live on the same page, its Notifications tab).
  final int unread;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = counts;
    final actionable = inboxActionableCount(todo: k.todo, unread: unread);
    final busy = actionable > 0;
    final tone = k.overdue > 0 ? c.danger : (k.dueSoon > 0 ? c.warning : c.primary);
    final ink = appInk(context, tone);
    final summary = inboxEntrySummary(k, unread: unread);
    final radius = AppRadius.cardAll;
    return Padding(
      padding: padding,
      child: Semantics(
        button: true,
        label: '${'inbox_title'.tr}, $summary',
        hint: 'inbox_entry_hint'.tr,
        onTap: onTap,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, boxShadow: AppShadow.card(context)),
          child: Material(
            color: c.cardBg,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                // paper on the hairline of every home card; what waits shows in the emerald well, never a wash
                borderRadius: radius,
                border: Border.all(color: c.divider, width: AppBorder.hairline),
              ),
              child: InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min + AppSpace.md),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xs, AppSpace.sm),
                    child: Row(children: [
                      Container(
                        width: AppIconSize.hero,
                        height: AppIconSize.hero,
                        decoration: BoxDecoration(
                          color: busy ? c.primary : c.blockEmerald,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: Icon(Icons.inbox_rounded, size: AppIconSize.md, color: busy ? c.onHero : c.blockAccentInk(c.primary, c.blockEmerald)),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('inbox_title'.tr,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w600, c: c.textDark, h: 1.3)),
                          const SizedBox(height: 2),
                          Text(summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appText(12.5,
                                  w: k.overdue > 0 ? FontWeight.w500 : FontWeight.w400,
                                  c: k.overdue > 0 ? appInk(context, c.danger) : c.textMedium,
                                  h: 1.3)),
                        ]),
                      ),
                      if (busy) ...[
                        const SizedBox(width: AppSpace.xs),
                        Container(
                          constraints: const BoxConstraints(minWidth: AppSpace.lg + AppSpace.xxs),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs - 1),
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(actionable > 99 ? '99+' : '$actionable',
                              textAlign: TextAlign.center,
                              style: appText(13, w: FontWeight.w600, c: ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                      ],
                      const SizedBox(width: AppSpace.xxs),
                      // chevron_right mirrors by itself in Arabic
                      Icon(Icons.chevron_right_rounded, size: 22, color: c.textLight),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [InboxEntry] that loads its own counts — GET /me/inbox[?org_id=], the one call the old preview card made — for
/// a screen without the /me/home payload (the parent's Children tab, an older server). Draws nothing while it
/// loads, on a failure or with an empty inbox; reloads when the inbox page closes.
class InboxEntryCard extends StatefulWidget {
  const InboxEntryCard({super.key, this.orgId, this.title, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final int? orgId;

  /// The inbox page's title (an organization's name); null → "Inbox".
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  State<InboxEntryCard> createState() => _InboxEntryCardState();
}

class _InboxEntryCardState extends State<InboxEntryCard> {
  late final InboxController _c = InboxController(orgId: widget.orgId)..load();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: widget.orgId, title: widget.title)));
    if (!mounted) return;
    _c.load();
    AppModeController.instance.refresh();
  }

  /// The unread notifications the shell already counts (its one GET /notifications); an organization's own inbox has
  /// no Notifications tab, so none there.
  int _unread(BuildContext context) {
    if (widget.orgId != null) return 0;
    try {
      return context.select<NotificationsProvider, int>((p) => p.unreadCount);
    } catch (_) {
      return 0; // no provider above (a test)
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          if (_c.loading && _c.items.isEmpty) return const SizedBox.shrink();
          final counts = (
            todo: _c.countOf(InboxSegment.todo),
            overdue: _c.overdue,
            dueSoon: _c.dueSoon,
            news: _c.countOf(InboxSegment.news),
            offers: _c.countOf(InboxSegment.offers),
          );
          final unread = _unread(context);
          if (_c.failed || !inboxEntryShown(counts, unread: unread)) return const SizedBox.shrink();
          return InboxEntry(counts: counts, unread: unread, onTap: _open, padding: widget.padding);
        },
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Actions
// ═════════════════════════════════════════════════════════════════════════════

/// Opens what an item points to. Returns true when the inbox should reload (something was answered / decided).
Future<bool> openInboxItem(BuildContext context, InboxItem x) async {
  final nav = Navigator.of(context);
  final a = x.action;
  final orgBrief = {...x.organization, if (x.orgId != null) 'id': x.orgId};
  switch ('${a['type']}') {
    case 'form':
      final sent = await nav.push<bool>(MaterialPageRoute(builder: (_) => deferredOrgFormFill(asInt(a['id']))));
      return sent == true;
    case 'availability':
      await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => deferredAvailabilityRequest(asInt(a['id']))));
      return true;
    case 'department_choice':
      await nav.push(MaterialPageRoute(
          builder: (_) => BasePage(
              useWebCard: true,
              width: AppWidth.reading,
              appBar: ScreenAppBar(title: 'inbox_kind_department_choice'.tr),
              child: deferredMyAcademicPath(asInt(a['org_id'])))));
      return true;
    case 'platform':
      await showPlatformRequirement(context, x.data);
      return true;
    case 'terms':
      try {
        final r = await ApiClient().get('/api/v1/org/public/${a['org_id']}/terms');
        final item = asMapList(r is Map ? r['items'] : null).where((t) => asInt(t['id']) == asInt(a['id'])).toList();
        if (item.isNotEmpty && context.mounted) {
          await showAppSheet<void>(
              context,
              (c2) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), child: TermCard(item: item.first, onAcked: () => Navigator.pop(c2))));
        }
      } catch (_) {}
      return true;
    case 'complaint':
      await nav.push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: orgBrief, initialTab: 3)));
      return true;
    case 'approval':
      await openOrgApprovalDeferred(context, asInt(a['org_id']), '${a['what']}');
      return true;
    case 'request':
      await _showRequest(context, x);
      return false;
    case 'announcement':
      await _showAnnouncement(context, x);
      return false;
    case 'ad':
      await _openAd(context, x);
      return false;
    case 'exam':
      await nav.push(MaterialPageRoute(builder: (_) => deferredMyExams(orgId: a['org_id'] == null ? null : asInt(a['org_id']))));
      return false;
    case 'parent_link':
      // inside the parent dashboard → its "Link" tab; from the full inbox page → back to the dashboard
      try {
        context.read<ParentTabProvider>().onChangeTab(3);
      } catch (_) {
        if (nav.canPop()) nav.pop();
      }
      return false;
  }
  return false;
}

Future<void> _showRequest(BuildContext context, InboxItem x) => showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final st = _statusChip(ctx, x);
      final sent = orgParseUtc(x.data['submitted_at']);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.title, style: AppType.headline(ctx)),
          if (_orgLine(x).isNotEmpty) Text(_orgLine(x), style: appText(12.5, c: c.textMedium)),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (st != null) AppTag(st.$1, st.$2),
            if ('${x.data['ref'] ?? ''}'.isNotEmpty) AppTag('${'inbox_ref'.tr} ${x.data['ref']}', c.primary, icon: Icons.tag_rounded),
          ]),
          if (sent != null) ...[
            const SizedBox(height: 12),
            AppInfoRow(Icons.send_rounded, '${'inbox_sent_on'.tr}: ${AppTime.dateTime(sent.toUtc())}'),
          ],
          if (x.subtitle.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppBanner(icon: Icons.chat_bubble_outline_rounded, text: '${'inbox_reviewer_note'.tr}: ${x.subtitle}',
                color: x.status == 'rejected' ? c.danger : c.primary),
          ],
        ]),
      );
    });

Future<void> _showAnnouncement(BuildContext context, InboxItem x) => showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final img = '${x.data['image_url'] ?? ''}';
      final link = '${x.data['link_url'] ?? ''}';
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (img.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.block),
                child: AspectRatio(
                    aspectRatio: 16 / 8,
                    child: Image.network(img, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
              ),
            ),
          if (_orgLine(x).isNotEmpty) Text(_orgLine(x), style: appText(12.5, w: FontWeight.w600, c: appInk(ctx, c.primary))),
          Text(x.title, style: AppType.headline(ctx)),
          if (x.createdAt != null) Text(AppTime.dateTime(x.createdAt!.toUtc()), style: appText(12, c: c.textLight)),
          if (x.subtitle.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(x.subtitle, style: appText(14, c: c.textMedium, h: 1.55)),
          ],
          if (link.isNotEmpty) ...[
            const SizedBox(height: 14),
            AppPill(
                icon: Icons.open_in_new_rounded,
                label: 'inbox_details'.tr,
                onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication)),
          ],
          if (x.orgId != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: {...x.organization, 'id': x.orgId})));
              },
              icon: const Icon(Icons.campaign_rounded),
              label: Text('inbox_all_news'.tr),
            ),
          ],
        ]),
      );
    });

Future<void> _openAd(BuildContext context, InboxItem x) async {
  final id = asInt(x.action['id']);
  Map<String, dynamic> target = {'target_type': x.data['target_type'], 'target_value': x.data['target_value']};
  try {
    final r = await ApiClient().post('/api/v1/ads/$id/click');
    if (r is Map) target = Map<String, dynamic>.from(r);
  } catch (_) {}
  if (!context.mounted) return;
  final type = '${target['target_type']}', value = '${target['target_value'] ?? ''}';
  if (type == 'url' && value.isNotEmpty) {
    await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  } else if (type == 'course' && int.tryParse(value) != null) {
    try {
      final r = await ApiClient().get('/api/v1/courses/$value');
      if (r is Map && context.mounted) {
        final course = CourseModel.fromJson(Map<String, dynamic>.from(r));
        await Navigator.of(context).push(MaterialPageRoute(
            settings: RouteSettings(name: '/course-detail', arguments: course), builder: (_) => CourseDetailScreen(course: course)));
      }
    } catch (_) {
      appToast('inbox_open_failed'.tr, error: true);
    }
  } else if (type == 'page' && value.startsWith('/')) {
    Navigator.of(context).pushNamed(value);
  } else if (x.data['media_type'] == 'video' && '${x.data['media_url'] ?? ''}'.isNotEmpty) {
    await launchUrl(Uri.parse('${x.data['media_url']}'), mode: LaunchMode.externalApplication);
  }
}
