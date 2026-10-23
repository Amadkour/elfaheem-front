// lib/features/shared/inbox/unified_inbox.dart
//
// ONE way to show requests, forms, announcements and ads to every role (point 14) — the "Inbox" pattern:
//
//   segments      To do · Announcements · Offers · Done       (counts on each, horizontally scrollable)
//   order         overdue → due soon → new → rest  (mandatory first, nearest deadline, newest)   [sortInbox]
//   cards         dense but calm: kind icon, title, where it comes from, status / urgency chips, a live countdown
//                 rendered with AppTime ("Due in 2 d · 14 Oct, 3:00 PM"), overdue highlighted
//   actions       tap → the right screen (fill the form, the availability grid, the ack sheet, the approval page …);
//                 swipe an announcement / offer away to hide it (remembered on the device)
//   states        skeleton while loading, a friendly empty state per segment, retry on failure
//
// Data: GET /api/v1/me/inbox[?org_id=] (backend routers/organization/org_me_router.py). The same widget is used by
// the student, teacher (and assistant), parent and organization-member homes:
//   InboxPreviewCard   compact block for a home screen (summary + the 3 most urgent items) → opens InboxScreen
//   InboxScreen        the full page
//   UnifiedInbox       the embeddable list (segments + cards)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseModel;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList;
import '../../ads/ads_pages.dart' show AdCard;
import '../../org/home_org_mix.dart' show showPlatformRequirement;
import '../../org/org_academic_pages.dart' show MyAcademicPathPage;
import '../../org/org_availability_pages.dart' show AvailabilityRequestScreen;
import '../../org/org_member_dashboard.dart' show openOrgApproval;
import '../../org/org_member_space.dart' show OrgFormFillScreen, OrgMemberSpace;
import '../../org/org_terms_pages.dart' show TermCard;
import '../../org/org_v3.dart' show orgParseUtc;

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
    if (left.isNegative) return x.kind == 'ad' ? 'normal' : 'overdue';
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
      _ => '',
    };

/// Approvals are counted server-side; the human sentence is built here (both languages).
String _title(InboxItem x) {
  if (x.kind != 'approval') return x.title;
  final n = '${asInt(x.data['count'])}';
  final key = switch ('${x.action['what']}') {
    'complaints' => 'inbox_appr_complaints',
    'join_requests' => 'inbox_appr_join',
    'unit_requests' => 'inbox_appr_units',
    _ => 'inbox_appr_forms',
  };
  return key.tr.replaceAll('{n}', n);
}

(String, Color)? _statusChip(BuildContext context, InboxItem x) {
  final c = context.colors;
  return switch (x.status) {
    'submitted' || 'in_review' || 'pending' => ('inbox_status_review'.tr, c.warning),
    'approved' => ('inbox_status_approved'.tr, c.success),
    'rejected' => ('inbox_status_rejected'.tr, c.danger),
    'resolved' || 'closed' => ('inbox_status_closed'.tr, c.success),
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
          borderRadius: BorderRadius.circular(c.radiusLarge - 4),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: overdue ? Color.alphaBlend(c.danger.withValues(alpha: 0.05), c.cardBg) : c.cardBg,
              borderRadius: BorderRadius.circular(c.radiusLarge - 4),
              border: Border.all(color: overdue ? c.danger.withValues(alpha: 0.45) : c.divider),
              boxShadow: c.cardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                  child: Icon(_kindIcon(x), color: tone, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(_kindLabel(x),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appText(11.5, w: FontWeight.w700, c: c.textLight)),
                      ),
                      if (u == 'new' && x.segment != InboxSegment.done)
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 2),
                    Text(_title(x), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
                    if (where.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                      ),
                    if (x.subtitle.isNotEmpty && x.kind != 'approval')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(x.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium, h: 1.35)),
                      ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (overdue) AppTag('inbox_overdue'.tr, c.danger, icon: Icons.error_outline_rounded),
                      if (u == 'due_soon' && x.kind != 'ad') AppTag('inbox_due_soon'.tr, c.warning, icon: Icons.schedule_rounded),
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
                const SizedBox(width: 6),
                if (count > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 26),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(20)),
                    child: Text('$count', textAlign: TextAlign.center, style: appText(12, w: FontWeight.w800, c: Colors.white)),
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
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: appText(11.5, w: FontWeight.w600, c: color)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final s in segments)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Semantics(
              selected: s == value,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: s == value ? c.primary : c.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s == value ? c.primary : c.divider),
                    boxShadow: s == value ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))] : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_segmentIcon(s), size: 17, color: s == value ? Colors.white : c.textMedium),
                    const SizedBox(width: 6),
                    Text(inboxSegmentLabel(s), style: appText(13, w: FontWeight.w800, c: s == value ? Colors.white : c.textMedium)),
                    if ((counts[s] ?? 0) > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: s == value ? Colors.white.withValues(alpha: 0.25) : c.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${counts[s]}', style: appText(11.5, w: FontWeight.w800, c: s == value ? Colors.white : c.primary)),
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

  Widget _empty(InboxSegment s) {
    final (icon, title, msg) = switch (s) {
      InboxSegment.todo => (Icons.celebration_rounded, 'inbox_empty_todo_title'.tr, 'inbox_empty_todo_msg'.tr),
      InboxSegment.news => (Icons.campaign_rounded, 'inbox_empty_news_title'.tr, 'inbox_empty_news_msg'.tr),
      InboxSegment.offers => (Icons.local_offer_rounded, 'inbox_empty_offers_title'.tr, 'inbox_empty_offers_msg'.tr),
      InboxSegment.done => (Icons.inventory_2_rounded, 'inbox_empty_done_title'.tr, 'inbox_empty_done_msg'.tr),
    };
    return AppEmpty(icon: icon, title: title, message: msg);
  }

  Widget _row(InboxItem x) {
    if (x.kind == 'ad') {
      final ad = {...x.data, 'id': x.action['id'], 'title': x.title, 'body': x.subtitle};
      return Dismissible(
        key: ValueKey(x.key),
        onDismissed: (_) => _c.hide(x),
        background: _swipeBg(context),
        child: LayoutBuilder(builder: (context, box) {
          return AspectRatio(
            aspectRatio: box.maxWidth > 600 ? 16 / 5.6 : 16 / 8.5,
            child: AdCard(ad: ad, onTap: () => _open(x)),
          );
        }),
      );
    }
    final card = InboxCard(item: x, onTap: () => _open(x));
    if (x.segment == InboxSegment.news) {
      return Dismissible(key: ValueKey(x.key), onDismissed: (_) => _c.hide(x), background: _swipeBg(context), child: card);
    }
    return card;
  }

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
          padding: const EdgeInsets.only(bottom: 12),
          child: InboxSegments(
            value: _seg,
            segments: segs,
            counts: {for (final s in segs) s: _c.countOf(s)},
            onChanged: (s) => setState(() => _seg = s),
          ),
        );
        Widget body;
        if (_c.loading && _c.items.isEmpty) {
          body = SizedBox(height: 260, child: AppListSkeleton(items: 3, padding: const EdgeInsets.symmetric(horizontal: 16)));
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _row(x),
              ),
          ]);
        }
        final content = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey('${_seg.name}-${list.length}-${_c.loading}'), child: body),
        );
        if (widget.shrinkWrap) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, content]);
        }
        return RefreshIndicator(
          onRefresh: _c.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 12, bottom: 40),
            children: [header, content],
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
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(c.radiusLarge - 4)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.visibility_off_rounded, color: c.textMedium, size: 20),
      const SizedBox(width: 6),
      Text('inbox_hide'.tr, style: appText(13, w: FontWeight.w700, c: c.textMedium)),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Full page
// ═════════════════════════════════════════════════════════════════════════════

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, this.orgId, this.initial = InboxSegment.todo, this.title});
  final int? orgId;
  final InboxSegment initial;
  final String? title;

  @override
  Widget build(BuildContext context) => BasePage(
        useWebCard: true,
        maxWith: 820,
        appBar: ScreenAppBar(title: title ?? 'inbox_title'.tr),
        child: UnifiedInbox(orgId: orgId, initial: initial),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Home preview
// ═════════════════════════════════════════════════════════════════════════════

/// Compact inbox block for a home screen: a calm summary line + the 3 most urgent to-dos → the full inbox.
/// Hidden entirely when nothing at all is in the inbox (no empty box on a fresh account).
class InboxPreviewCard extends StatefulWidget {
  const InboxPreviewCard({super.key, this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16), this.orgId});
  final EdgeInsetsGeometry padding;
  final int? orgId;

  @override
  State<InboxPreviewCard> createState() => _InboxPreviewCardState();
}

class _InboxPreviewCardState extends State<InboxPreviewCard> {
  late final InboxController _c = InboxController(orgId: widget.orgId)..load();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _openAll([InboxSegment s = InboxSegment.todo]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: widget.orgId, initial: s)));
    if (mounted) _c.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (_c.loading && _c.items.isEmpty) {
          return Padding(padding: widget.padding, child: const SizedBox(height: 92, child: AppListSkeleton(items: 1, padding: EdgeInsets.zero)));
        }
        final todo = _c.of(InboxSegment.todo);
        final news = _c.countOf(InboxSegment.news), offers = _c.countOf(InboxSegment.offers);
        if (_c.failed || (todo.isEmpty && news == 0 && offers == 0)) return const SizedBox.shrink();
        final overdue = _c.overdue, soon = _c.dueSoon;
        final tone = overdue > 0 ? c.danger : (soon > 0 ? c.warning : c.primary);
        final summary = todo.isEmpty
            ? 'inbox_preview_clear'.tr
            : [
                'inbox_preview_todo'.tr.replaceAll('{n}', '${todo.length}'),
                if (overdue > 0) 'inbox_preview_overdue'.tr.replaceAll('{n}', '$overdue'),
                if (soon > 0) 'inbox_preview_soon'.tr.replaceAll('{n}', '$soon'),
              ].join(' · ');
        return Padding(
          padding: widget.padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openAll,
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.inbox_rounded, color: tone),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('inbox_title'.tr, style: appText(15, w: FontWeight.w800, c: c.textDark)),
                          Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: todo.isEmpty ? c.textMedium : tone)),
                        ]),
                      ),
                      Text('inbox_see_all'.tr, style: appText(12.5, w: FontWeight.w700, c: c.primary)),
                      Icon(Icons.chevron_right_rounded, color: c.primary, size: 20),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  for (final x in todo.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InboxCard(item: x, onTap: () async {
                        if (await openInboxItem(context, x) && mounted) {
                          _c.load();
                          AppModeController.instance.refresh();
                        }
                      }),
                    ),
                  if (todo.isEmpty || news + offers > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        if (news > 0)
                          AppPill(icon: Icons.campaign_rounded, label: '${'inbox_seg_news'.tr} · $news', onTap: () => _openAll(InboxSegment.news)),
                        if (offers > 0)
                          AppPill(icon: Icons.local_offer_rounded, label: '${'inbox_seg_offers'.tr} · $offers', onTap: () => _openAll(InboxSegment.offers)),
                      ]),
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
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
      final sent = await nav.push<bool>(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: asInt(a['id']))));
      return sent == true;
    case 'availability':
      await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AvailabilityRequestScreen(requestId: asInt(a['id']))));
      return true;
    case 'department_choice':
      await nav.push(MaterialPageRoute(
          builder: (_) => BasePage(
              useWebCard: true,
              maxWith: 760,
              appBar: ScreenAppBar(title: 'inbox_kind_department_choice'.tr),
              child: MyAcademicPathPage(orgId: asInt(a['org_id'])))));
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
      await nav.push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: orgBrief, initialTab: 3)));
      return true;
    case 'approval':
      await openOrgApproval(context, asInt(a['org_id']), '${a['what']}');
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
    case 'parent_link':
      if (await nav.maybePop() == false) nav.pushNamed('/parent_dashboard');
      return false;
  }
  return false;
}

Future<void> _showRequest(BuildContext context, InboxItem x) => showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final st = _statusChip(ctx, x);
      final sent = orgParseUtc(x.data['submitted_at']);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.title, style: appText(18, w: FontWeight.w800, c: c.textDark)),
          if (_orgLine(x).isNotEmpty) Text(_orgLine(x), style: appText(12.5, c: c.textMedium)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (st != null) AppTag(st.$1, st.$2),
            if ('${x.data['ref'] ?? ''}'.isNotEmpty) AppTag('${'inbox_ref'.tr} ${x.data['ref']}', c.primary, icon: Icons.tag_rounded),
          ]),
          if (sent != null) ...[
            const SizedBox(height: 12),
            AppInfoRow(icon: Icons.send_rounded, label: 'inbox_sent_on'.tr, value: AppTime.dateTime(sent.toUtc())),
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (img.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                    aspectRatio: 16 / 8,
                    child: Image.network(img, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
              ),
            ),
          if (_orgLine(x).isNotEmpty) Text(_orgLine(x), style: appText(12.5, w: FontWeight.w700, c: c.primary)),
          Text(x.title, style: appText(18, w: FontWeight.w800, c: c.textDark)),
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
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: {...x.organization, 'id': x.orgId})));
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
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => CourseDetailScreen(course: CourseModel.fromJson(Map<String, dynamic>.from(r)))));
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
