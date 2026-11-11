// lib/features/org/org_announcements.dart
//
// Announcements with engagement tracking (point 17): the member-facing feed (views, like/dislike, deep-link
// click-through) and the per-announcement analytics for org admins / department managers.
//
// Contract used by other screens (keep it stable):
//   OrgAnnouncementFeed(orgId: id, limit: 3, compact: true)   // embeddable feed, e.g. on the member dashboard
//   OrgAnnouncementsPage(deptId: d)                             // staff list (create · publish · analytics)
//   showCreateAnnouncementSheet(context, orgId: id, deptId: d)  // create from a department context
//   OrgAnnouncementAnalyticsScreen(orgId: id, announcementId: a)
//
// Server: back/routers/organization/org_announcements_router.py + org_services_router.py (announcements) +
// org_member_router.py (feed). A card's call-to-action is a typed link {kind: form|section|course|url, target, label}
// resolved by [openAnnouncementLink]. Views are recorded when a card has really been on screen (batched).
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_mentions.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import '../student/courses/details/course_link_loader.dart';
import 'org_common.dart';
import 'org_member_pages.dart' show OrgCoursesScreen, OrgTimetableScreen;
import 'org_member_space.dart' show OrgFormFillScreen;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart' show orgParseUtc, orgUtc;
import 'org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import 'org_page_kit.dart' show OrgPageBody, OrgPrimaryAction, orgListInset;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

const _pub = '$orgBase/public';

// ═════════════════════════════════════════════════════════════════════════════
//  Shared vocabulary
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> annCategories() => {
      'news': t('خبر', 'News'),
      'event': t('فعالية', 'Event'),
      'deadline': t('موعد نهائي', 'Deadline'),
      'urgent': t('عاجل', 'Urgent'),
      'job': t('فرصة عمل', 'Job'),
      'alumni': t('خريجون', 'Alumni'),
    };

const annIcons = {
  'news': Icons.campaign_rounded,
  'event': Icons.event_rounded,
  'deadline': Icons.alarm_rounded,
  'urgent': Icons.priority_high_rounded,
  'job': Icons.work_rounded,
  'alumni': Icons.workspace_premium_rounded,
};

/// Places inside the member's organization space a call-to-action can open.
Map<String, String> annSections() => {
      'news': t('الأخبار', 'News'),
      'timetable': t('الجدول الدراسي', 'Timetable'),
      'courses': t('المقررات', 'Courses'),
      'requests': t('الطلبات والنماذج', 'Requests & forms'),
      'complaints': t('الشكاوى', 'Complaints'),
      'departments': t('دليل الإدارات', 'Departments'),
      'regulations': t('اللوائح', 'Regulations'),
      'my_path': t('مساري الأكاديمي', 'My academic path'),
      'join': t('الانضمام لإدارة', 'Join a department'),
    };

const _sectionIcons = {
  'news': Icons.campaign_rounded,
  'timetable': Icons.calendar_month_rounded,
  'courses': Icons.menu_book_rounded,
  'requests': Icons.assignment_rounded,
  'complaints': Icons.support_agent_rounded,
  'departments': Icons.apartment_rounded,
  'regulations': Icons.gavel_rounded,
  'my_path': Icons.route_rounded,
  'join': Icons.group_add_rounded,
};

/// The typed deep link of an announcement: {kind: form|section|course|url, target, label}.
class AnnLink {
  const AnnLink(this.kind, this.target, {this.label, this.title});

  final String kind, target;
  final String? label, title;

  static AnnLink? from(dynamic json) {
    final m = asMap(json);
    final kind = '${m['kind'] ?? ''}';
    final target = '${m['target'] ?? ''}';
    if (kind.isEmpty || target.isEmpty) return null;
    final label = '${m['label'] ?? ''}'.trim();
    return AnnLink(kind, target, label: label.isEmpty ? null : label, title: m['title']?.toString());
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'target': target, if (label != null && label!.isNotEmpty) 'label': label};

  IconData get icon => switch (kind) {
        'form' => Icons.assignment_rounded,
        'course' => Icons.menu_book_rounded,
        'url' => Icons.open_in_new_rounded,
        _ => target.startsWith('dept:') ? Icons.apartment_rounded : (_sectionIcons[target] ?? Icons.arrow_forward_rounded),
      };

  String get sectionName =>
      target.startsWith('dept:') ? (title ?? t('الإدارة', 'the department')) : (annSections()[target] ?? target);

  /// The button text members see.
  String get cta {
    if (label != null && label!.isNotEmpty) return label!;
    return switch (kind) {
      'form' => t('املأ النموذج', 'Fill in the form'),
      'course' => t('افتح المقرر', 'Open the course'),
      'url' => t('افتح الرابط', 'Open the link'),
      _ => t('اذهب إلى $sectionName', 'Go to $sectionName'),
    };
  }

  /// One line for staff ("Opens the form «Housing»").
  String get describe => switch (kind) {
        'form' => t('يفتح النموذج «${title ?? '#$target'}»', 'Opens the form “${title ?? '#$target'}”'),
        'course' => t('يفتح مقرراً', 'Opens a course'),
        'url' => target,
        _ => t('يفتح: $sectionName', 'Opens: $sectionName'),
      };
}

/// Navigates to wherever [link] points. [org] is the announcement's organization ({id, name_ar, …}).
Future<void> openAnnouncementLink(BuildContext context, AnnLink link, {Map<String, dynamic>? org}) async {
  final nav = Navigator.of(context);
  final o = org ?? const <String, dynamic>{};
  final orgId = asInt(o['id']);
  switch (link.kind) {
    case 'url':
      final uri = Uri.tryParse(link.target);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        toast(t('تعذّر فتح الرابط', 'Could not open the link'), error: true);
      }
      return;
    case 'form':
      await nav.push(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: asInt(link.target))));
      return;
    case 'course':
      await nav.push(MaterialPageRoute(builder: (_) => CourseLinkLoader(courseId: asInt(link.target))));
      return;
  }
  // sections
  if (link.target == 'timetable') {
    await nav.push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: orgId == 0 ? null : orgId)));
    return;
  }
  if (orgId == 0) return;
  if (link.target == 'courses') {
    await nav.push(MaterialPageRoute(builder: (_) => OrgCoursesScreen(org: o)));
    return;
  }
  final tab = link.target.startsWith('dept:')
      ? 1
      : const {'news': 0, 'departments': 1, 'requests': 2, 'complaints': 3, 'regulations': 4, 'my_path': 5, 'join': 6}[
              link.target] ??
          0;
  await nav.push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: o, initialTab: tab)));
}

String _errText(Object e) => e is ApiException ? e.message : t('تعذّر الاتصال، حاول مجدداً', 'Connection problem, try again');

// ═════════════════════════════════════════════════════════════════════════════
//  View tracking — batched, only for cards that were really on screen
// ═════════════════════════════════════════════════════════════════════════════

class _ViewTracker {
  _ViewTracker._();
  static final _ViewTracker i = _ViewTracker._();

  final Set<int> _sent = {};
  final Set<int> _pending = {};
  Timer? _timer;

  void seen(int id) {
    if (id <= 0 || _sent.contains(id)) return;
    _pending.add(id);
    _timer ??= Timer(const Duration(milliseconds: 900), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    if (_pending.isEmpty) return;
    final ids = _pending.take(100).toList();
    _pending.removeAll(ids);
    _sent.addAll(ids);
    try {
      await ApiClient().post('$_pub/announcements/views', body: {'ids': ids});
    } catch (_) {
      _sent.removeAll(ids); // retried the next time the card shows
    }
    if (_pending.isNotEmpty) _timer ??= Timer(const Duration(milliseconds: 900), _flush);
  }
}

/// Calls [onSeen] once, after at least half of the child (or 120 px) stayed on screen while its route is on top.
class _SeenProbe extends StatefulWidget {
  const _SeenProbe({required this.onSeen, required this.child});
  final VoidCallback onSeen;
  final Widget child;

  @override
  State<_SeenProbe> createState() => _SeenProbeState();
}

class _SeenProbeState extends State<_SeenProbe> {
  Timer? _timer;
  int _hits = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) => _check());
  }

  void _check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final route = ModalRoute.of(context);
    if (box is! RenderBox || !box.attached || !box.hasSize || (route != null && !route.isCurrent) ||
        !TickerMode.valuesOf(context).enabled) {
      _hits = 0;
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    final visible = math.min(top + box.size.height, screen) - math.max(top, 0);
    if (visible >= math.min(box.size.height * 0.5, 120)) {
      if (++_hits >= 2) {
        _timer?.cancel();
        widget.onSeen();
      }
    } else {
      _hits = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Member feed
// ═════════════════════════════════════════════════════════════════════════════

/// Embeddable announcement feed of one organization for the signed-in member.
/// [limit] caps the items shown (null = all, with paging); [compact] is the dashboard-card variant.
class OrgAnnouncementFeed extends StatefulWidget {
  const OrgAnnouncementFeed({super.key, required this.orgId, this.limit, this.compact = false, this.deptId, this.title});
  final int orgId;

  /// The compact card's heading (default "Latest news"); a page passes its own instead of drawing a second one.
  final String? title;
  final int? deptId;
  final int? limit;
  final bool compact;

  @override
  State<OrgAnnouncementFeed> createState() => _OrgAnnouncementFeedState();
}

class _OrgAnnouncementFeedState extends State<OrgAnnouncementFeed> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false, _more = false, _onlyUnread = false;
  int _page = 1, _pages = 1, _unread = 0, _total = 0;

  int get _size => widget.compact ? (widget.limit ?? 3) : math.min(widget.limit ?? 15, 50);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrgAnnouncementFeed old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId || old.deptId != widget.deptId) _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more) setState(() => _more = true);
    final page = more ? _page + 1 : 1;
    try {
      final r = asMap(await ApiClient().get('$_pub/me/feed', queryParams: {
        'org_id': widget.orgId,
        if (widget.deptId != null) 'dept_id': widget.deptId,
        if (_onlyUnread) 'unread': true,
        'page': page,
        'size': _size,
      }));
      if (!mounted) return;
      final list = asMapList(r['items']);
      setState(() {
        _items = more ? [...?_items, ...list] : list;
        _page = page;
        _pages = asInt(r['pages'], 1);
        _unread = asInt(r['unread']);
        _total = asInt(r['total']);
        _failed = false;
        _more = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = _items == null;
        _more = false;
      });
      if (more || !widget.compact) toast(_errText(e), error: true);
    }
  }

  void _replace(Map<String, dynamic> item) {
    final i = _items?.indexWhere((x) => x['id'] == item['id']) ?? -1;
    if (i >= 0) setState(() => _items![i] = item);
  }

  @override
  Widget build(BuildContext context) => widget.compact ? _compact(context) : _full(context);

  // ── dashboard card ──
  Widget _compact(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.campaign_rounded, color: c.primary, size: AppIconSize.md),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(widget.title ?? t('آخر الأخبار', 'Latest news'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
        ),
        if (_unread > 0) ...[const SizedBox(width: AppSpace.xs), _CountBadge(_unread)],
        const Spacer(),
        if ((items?.isNotEmpty ?? false))
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OrgAnnouncementsFeedScreen(orgId: widget.orgId, deptId: widget.deptId))).then((_) => _load()),
            child: Text(t('عرض الكل', 'See all'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: AppSpace.xs),
      if (items == null && !_failed)
        const SizedBox(height: 170, child: AppListSkeleton(items: 2, padding: EdgeInsets.zero))
      else if (_failed)
        AppBanner(
          icon: Icons.wifi_off_rounded,
          text: t('تعذّر تحميل الأخبار', "Couldn't load the news"),
          action: TextButton(onPressed: _load, child: Text(t('إعادة', 'Retry'))),
        )
      else if (items!.isEmpty)
        AppCard(
          child: Row(children: [
            Icon(Icons.mark_email_read_rounded, color: c.textLight),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(t('لا أخبار جديدة الآن — سنضعها هنا فور نشرها', "No news right now — it'll show up here"),
                  style: AppType.row(context).copyWith(color: c.textMedium)),
            ),
          ]),
        )
      else
        for (final a in items.take(widget.limit ?? 3))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AnnouncementCard(item: a, compact: true, onChanged: _replace),
          ),
    ]);
  }

  // ── full feed ──
  Widget _full(BuildContext context) {
    final c = context.colors;
    final items = _items;
    if (items == null && !_failed) return const AppListSkeleton(items: 4);
    if (_failed) {
      return ListView(children: [
        AppEmpty(
          icon: Icons.wifi_off_rounded,
          title: t('تعذّر تحميل الأخبار', "Couldn't load the news"),
          actionLabel: t('إعادة المحاولة', 'Try again'),
          onAction: _load,
        ),
      ]);
    }
    final canMore = _page < _pages && (widget.limit == null || items!.length < widget.limit!);
    return AppRefresh(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl),
        itemCount: items!.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                AppChoiceChip(
                    label: t('الكل', 'All'),
                    selected: !_onlyUnread,
                    onTap: () {
                      setState(() => _onlyUnread = false);
                      _load();
                    }),
                AppChoiceChip(
                    label: _unread > 0 ? t('غير المقروءة ($_unread)', 'Unread ($_unread)') : t('غير المقروءة', 'Unread'),
                    icon: Icons.mark_email_unread_rounded,
                    selected: _onlyUnread,
                    onTap: () {
                      setState(() => _onlyUnread = true);
                      _load();
                    }),
              ]),
            );
          }
          if (i == items.length + 1) {
            if (items.isEmpty) {
              return AppEmpty(
                icon: _onlyUnread ? Icons.done_all_rounded : Icons.campaign_rounded,
                title: _onlyUnread ? t('قرأت كل شيء 👏', "You're all caught up 👏") : t('لا أخبار بعد', 'No news yet'),
                message: _onlyUnread
                    ? null
                    : t('ستجد هنا إعلانات مؤسستك وإداراتها فور نشرها', "Your institution's news will appear here"),
              );
            }
            if (!canMore) {
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Center(
                  child: Text(t('هذا كل شيء ($_total)', "That's everything ($_total)"),
                      style: AppType.meta(context).copyWith(color: c.textLight)),
                ),
              );
            }
            return Center(
              child: _more
                  ? const Padding(padding: EdgeInsets.all(AppSpace.sm), child: CircularProgressIndicator(strokeWidth: 2.4))
                  : OutlinedButton.icon(
                      onPressed: () => _load(more: true),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(t('عرض المزيد', 'Show more'), style: TextStyle(fontFamily: AppFonts.family)),
                    ),
            );
          }
          final a = items[i - 1];
          return Padding(
            key: ValueKey('ann-${a['id']}'),
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AnnouncementCard(item: a, onChanged: _replace),
          );
        },
      ),
    );
  }
}

/// A pushed page's readable column: the dashboard header keeps the page's full width (its one row needs the room),
/// the content stays as narrow as the older page was.
Widget _readable(double maxWidth, Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: SizedBox.expand(child: child)),
    );

/// "See all" page for the compact feed.
class OrgAnnouncementsFeedScreen extends StatelessWidget {
  const OrgAnnouncementsFeedScreen({super.key, required this.orgId, this.deptId});
  final int orgId;
  final int? deptId;

  @override
  Widget build(BuildContext context) {
    final title = t('الأخبار والإعلانات', 'News & announcements');
    final feed = OrgAnnouncementFeed(orgId: orgId, deptId: deptId);
    // staff of this organization: the dashboard's header (Refresh rebuilds the feed); members keep the app bar
    if (orgUsesDashboardHeader(context, orgId)) return OrgPushedPage(title: title, child: _readable(820, feed));
    return BasePage(
      useWebCard: true,
      maxWith: 820,
      appBar: ScreenAppBar(title: title),
      child: feed,
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(AppRadius.block)),
      child: Text(n > 99 ? '99+' : '$n', style: appText(11, w: FontWeight.w800, c: c.onHero)),
    );
  }
}

/// One announcement for a member: unread highlight, pin, like / dislike with counts, call-to-action.
/// Records its own view once it has been on screen; tap opens the full announcement.
class AnnouncementCard extends StatefulWidget {
  const AnnouncementCard({super.key, required this.item, this.compact = false, this.onChanged});
  final Map<String, dynamic> item;
  final bool compact;
  final ValueChanged<Map<String, dynamic>>? onChanged;

  @override
  State<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<AnnouncementCard> {
  late Map<String, dynamic> a = widget.item;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant AnnouncementCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.item, widget.item)) a = widget.item;
  }

  Map<String, dynamic> get _me => asMap(a['me']);
  int get _id => asInt(a['id']);

  void _set(Map<String, dynamic> next) {
    setState(() => a = next);
    widget.onChanged?.call(next);
  }

  Future<void> _react(String r) async {
    if (_busy) return;
    final before = a;
    final cur = _me['reaction'] as String?;
    final next = cur == r ? null : r;
    // optimistic
    var likes = asInt(a['likes']), dislikes = asInt(a['dislikes']);
    if (cur == 'like') likes--;
    if (cur == 'dislike') dislikes--;
    if (next == 'like') likes++;
    if (next == 'dislike') dislikes++;
    _set({...a, 'likes': math.max(0, likes), 'dislikes': math.max(0, dislikes), 'me': {..._me, 'reaction': next}});
    _busy = true;
    try {
      final s = asMap(await ApiClient().put('$_pub/announcements/$_id/reaction', body: {'reaction': next}));
      if (mounted) _set({...a, 'likes': s['likes'], 'dislikes': s['dislikes'], 'me': {..._me, ...asMap(s['me'])}});
    } catch (e) {
      if (mounted) _set(before);
      toast(_errText(e), error: true);
    } finally {
      _busy = false;
    }
  }

  Future<void> _cta() async {
    var link = AnnLink.from(a['link']);
    if (link == null) return;
    try {
      final r = asMap(await ApiClient().post('$_pub/announcements/$_id/click'));
      link = AnnLink.from(r['link']) ?? link;
      if (mounted) _set({...a, 'me': {..._me, 'clicked': true, 'viewed': true}});
    } catch (_) {/* the click is best effort — never block the member */}
    if (!mounted) return;
    await openAnnouncementLink(context, link!, org: asMap(a['organization']));
  }

  void _open() {
    _ViewTracker.i.seen(_id);
    showAppSheet<void>(context, (ctx) => _AnnouncementDetail(state: this));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = '${a['category'] ?? 'news'}';
    final urgent = cat == 'urgent';
    final unread = _me['viewed'] != true;
    final pinned = a['is_pinned'] == true;
    final dept = asMap(a['department']);
    final source = dept.isEmpty ? orgNameOf(asMap(a['organization'])) : orgNameOf(dept);
    final img = '${a['image_url'] ?? ''}';
    final link = AnnLink.from(a['link']);
    final accent = urgent ? c.danger : c.primary;
    return _SeenProbe(
      onSeen: () => _ViewTracker.i.seen(_id),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.block),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.block),
              border: Border.all(
                  color: urgent
                      ? c.danger.withValues(alpha: 0.55)
                      : unread
                          ? c.primary.withValues(alpha: 0.45)
                          : c.divider,
                  width: unread || urgent ? 1.4 : 1),
              color: unread ? accent.withValues(alpha: 0.06) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (img.isNotEmpty && !widget.compact)
                AspectRatio(
                  aspectRatio: 16 / 8,
                  child: Image.network(orgFileUrl(img), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              Padding(
                padding: EdgeInsets.all(widget.compact ? 12 : 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
                      child: Icon(annIcons[cat] ?? Icons.campaign_rounded, size: AppIconSize.sm, color: accent),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
                    ),
                    if (pinned) ...[Icon(Icons.push_pin_rounded, size: AppIconSize.xs, color: c.warning), const SizedBox(width: AppSpace.xxs)],
                    if (unread) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(AppRadius.block)),
                        child: Text(t('جديد', 'New'), style: appText(10.5, w: FontWeight.w800, c: c.onHero)),
                      ),
                      const SizedBox(width: AppSpace.xs),
                    ],
                    Text(relTime(a['publish_at']), style: AppType.meta(context).copyWith(color: c.textLight)),
                  ]),
                  const SizedBox(height: AppSpace.xs),
                  Text('${a['title']}',
                      maxLines: widget.compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: orgText(context, size: widget.compact ? 14.5 : 15.5, w: FontWeight.w800)),
                  if ('${a['body'] ?? ''}'.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs),
                    MentionText('${a['body']}'.trim(),
                        maxLines: widget.compact ? 2 : 5,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(color: c.textMedium)),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  _ActionsBar(
                    likes: asInt(a['likes']),
                    dislikes: asInt(a['dislikes']),
                    reaction: _me['reaction'] as String?,
                    onReact: _react,
                    link: link,
                    onCta: _cta,
                    dense: widget.compact,
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({
    required this.likes,
    required this.dislikes,
    required this.reaction,
    required this.onReact,
    required this.link,
    required this.onCta,
    this.dense = false,
  });

  final int likes, dislikes;
  final String? reaction;
  final ValueChanged<String> onReact;
  final AnnLink? link;
  final VoidCallback onCta;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      _ReactButton(
          icon: reaction == 'like' ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
          count: likes,
          active: reaction == 'like',
          color: c.success,
          tooltip: t('أعجبني', 'Like'),
          onTap: () => onReact('like')),
      const SizedBox(width: AppSpace.xs),
      _ReactButton(
          icon: reaction == 'dislike' ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
          count: dislikes,
          active: reaction == 'dislike',
          color: c.danger,
          tooltip: t('لم يعجبني', 'Dislike'),
          onTap: () => onReact('dislike')),
      const SizedBox(width: AppSpace.xs),
      const Spacer(),
      if (link != null)
        Flexible(
          flex: 6,
          child: FilledButton.icon(
            onPressed: onCta,
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.onHero,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 6 : 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
            icon: Icon(link!.icon, size: AppIconSize.sm),
            label: Text(link!.cta,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }
}

class _ReactButton extends StatelessWidget {
  const _ReactButton({
    required this.icon,
    required this.count,
    required this.active,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final bool active;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? color.withValues(alpha: 0.14) : c.background,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: active ? color.withValues(alpha: 0.5) : c.divider),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: AppIconSize.sm, color: active ? color : c.textMedium),
              if (count > 0) ...[
                const SizedBox(width: AppSpace.xxs),
                Text('$count', style: appText(12.5, w: FontWeight.w800, c: active ? color : c.textMedium)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Full announcement in a sheet (opening it records the view server-side).
class _AnnouncementDetail extends StatefulWidget {
  const _AnnouncementDetail({required this.state});
  final _AnnouncementCardState state;

  @override
  State<_AnnouncementDetail> createState() => _AnnouncementDetailState();
}

class _AnnouncementDetailState extends State<_AnnouncementDetail> {
  _AnnouncementCardState get s => widget.state;

  @override
  void initState() {
    super.initState();
    ApiClient().post('$_pub/announcements/${s._id}/view').then((r) {
      final m = asMap(r);
      if (s.mounted && m.isNotEmpty) s._set({...s.a, 'me': {...s._me, ...asMap(m['me'])}});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = s.a;
    final img = '${a['image_url'] ?? ''}';
    final link = AnnLink.from(a['link']);
    final at = orgParseUtc(a['publish_at']);
    final dept = asMap(a['department']);
    return StatefulBuilder(builder: (context, set) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSheetHeader(dept.isEmpty ? orgNameOf(asMap(a['organization'])) : orgNameOf(dept)),
          if (img.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 8,
                child: Image.network(orgFileUrl(img), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: 6, runSpacing: 6, children: [
            AppBadgePill(annCategories()['${a['category']}'] ?? '${a['category']}',
                icon: annIcons['${a['category']}'], color: a['category'] == 'urgent' ? c.danger : c.primary),
            if (a['is_pinned'] == true) AppBadgePill(t('مثبّت', 'Pinned'), icon: Icons.push_pin_rounded, color: c.warning),
            if (at != null) AppBadgePill(AppTime.dateTime(at), icon: Icons.schedule_rounded, color: c.textMedium),
          ]),
          const SizedBox(height: AppSpace.sm),
          Text('${a['title']}', style: AppType.section(context)),
          if ('${a['body'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            MentionText('${a['body']}'.trim(), selectable: true, style: AppType.row(context).copyWith(color: c.textMedium)),
          ],
          const SizedBox(height: AppSpace.md),
          _ActionsBar(
            likes: asInt(a['likes']),
            dislikes: asInt(a['dislikes']),
            reaction: asMap(a['me'])['reaction'] as String?,
            onReact: (r) async {
              await s._react(r);
              if (mounted) set(() {});
            },
            link: null,
            onCta: () {},
          ),
          if (link != null) ...[
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(
              label: link.cta,
              icon: link.icon,
              onPressed: () {
                Navigator.pop(context);
                s._cta();
              },
            ),
          ],
        ]),
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff: list · editor
// ═════════════════════════════════════════════════════════════════════════════

/// May the signed-in staff member see the analytics of an announcement of [deptId]?
bool canSeeAnnouncementAnalytics(OrgSession s, int? deptId) =>
    s.can('announcements', 'insert', deptId) || s.can('announcements', 'approve', deptId);

class OrgAnnouncementsPage extends StatelessWidget {
  const OrgAnnouncementsPage({super.key, this.deptId});
  final int? deptId;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/announcements', {'dept_id': deptId})..refresh(),
      child: _AnnList(deptId: deptId),
    );
  }
}

class _AnnList extends StatelessWidget {
  const _AnnList({this.deptId});
  final int? deptId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final p = context.read<OrgPaged>();
    final canPost = s.can('announcements', 'insert', deptId);
    // the page anatomy (D-103, org_page_kit.dart): ONE primary action "New announcement" · the cards
    return OrgPageBody(
      primary: canPost
          ? OrgPrimaryAction(
              id: 'new_announcement',
              icon: Icons.add_rounded,
              label: t('إعلان جديد', 'New announcement'),
              onTap: () => showAnnouncementEditor(context, deptId: deptId, onSaved: p.refresh),
            )
          : null,
      child: PagedList<OrgPaged>(
        // only who may post is invited to post
        emptyText: canPost
            ? t('لا إعلانات بعد — شارك أول خبر مع مجتمعك', 'No announcements yet — share the first news')
            : t('لا إعلانات بعد', 'No announcements yet'),
        itemBuilder: (context, row) => _AnnCard(row: row),
      ),
    );
  }
}

class _AnnCard extends StatelessWidget {
  const _AnnCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final p = context.read<OrgPaged>();
    final dept = row['dept_id'] == null ? null : asInt(row['dept_id']);
    final status = '${row['status']}';
    final cat = '${row['category']}';
    final url = '${s.base}/announcements/${row['id']}';
    final st = asMap(row['stats']);
    final link = AnnLink.from(row['link']);
    final live = status == 'published' || status == 'archived';
    final analytics = live && canSeeAnnouncementAnalytics(s, dept);
    final pubAt = orgParseUtc(row['publish_at']);
    final scheduled = status == 'published' && pubAt != null && pubAt.isAfter(DateTime.now().toUtc());

    void openAnalytics() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OrgAnnouncementAnalyticsScreen(orgId: s.currentId ?? 0, announcementId: asInt(row['id']), initial: row)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: orgListInset, vertical: AppSpace.xxs),
      child: RowCard(
        accent: row['is_pinned'] == true ? c.warning : null,
        onTap: analytics
            ? openAnalytics
            : s.can('announcements', 'update', dept)
                ? () => showAnnouncementEditor(context, deptId: dept, edit: row, onSaved: p.refresh)
                : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(annIcons[cat] ?? Icons.campaign_rounded, cat == 'urgent' ? c.danger : c.primary, size: 42),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (row['is_pinned'] == true) Icon(Icons.push_pin_rounded, size: AppIconSize.xs, color: c.warning),
                Expanded(
                    child: Text('${row['title']}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
              ]),
              if ('${row['body'] ?? ''}'.isNotEmpty)
                Text('${row['body']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusChip(scheduled ? t('مجدول', 'Scheduled') : statusLabel(status),
                    scheduled ? c.accent : statusColor(context, status)),
                OrgPill(annCategories()[cat] ?? cat),
                if (link != null) OrgPill(link.kind == 'form' ? t('نموذج', 'Form') : t('رابط', 'Link'), icon: link.icon, color: c.accent),
                if (row['targeted'] != null)
                  OrgPill('${row['targeted']}', icon: Icons.groups_rounded, color: c.textMedium),
                if (live) OrgPill('${st['viewed'] ?? row['views'] ?? 0}', icon: Icons.visibility_rounded, color: c.primary),
                if (asInt(st['likes']) > 0) OrgPill('${st['likes']}', icon: Icons.thumb_up_alt_rounded, color: c.success),
                if (asInt(st['dislikes']) > 0) OrgPill('${st['dislikes']}', icon: Icons.thumb_down_alt_rounded, color: c.danger),
                if (asInt(st['clicked']) > 0) OrgPill('${st['clicked']}', icon: Icons.ads_click_rounded, color: c.accent),
                OrgPill(relTime(row['publish_at'] ?? row['created_at']), color: c.textLight),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'analytics') return openAnalytics();
              if (v == 'edit') return showAnnouncementEditor(context, deptId: dept, edit: row, onSaved: p.refresh);
              if (v == 'delete') {
                if (!await appConfirm(context,
                    message: t('حذف الإعلان نهائياً؟ ستُحذف معه إحصاءات التفاعل.',
                        'Delete this announcement? Its engagement stats go with it.'),
                    danger: true)) {
                  return;
                }
                if (await OrgApi.i.del(url, t('تم الحذف', 'Deleted')) != null) p.refresh();
                return;
              }
              final r = await OrgApi.i.post('$url/$v', null, v == 'publish' ? t('نُشر الإعلان 🎉', 'Published 🎉') : t('تم', 'Done'));
              if (r is Map) p.replaceRow({...Map<String, dynamic>.from(r), 'stats': st});
            },
            itemBuilder: (_) => [
              if (analytics) PopupMenuItem(value: 'analytics', child: Text(t('التحليلات والتفاعل', 'Analytics'))),
              if (s.can('announcements', 'update', dept) && (status != 'published' || s.can('announcements', 'approve', dept)))
                PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
              if (s.can('announcements', 'approve', dept) && status != 'published')
                PopupMenuItem(value: 'publish', child: Text(t('نشر الآن', 'Publish now'))),
              if (s.can('announcements', 'approve', dept) && status == 'published')
                PopupMenuItem(value: 'unpublish', child: Text(t('إيقاف النشر', 'Unpublish'))),
              if (s.can('announcements', 'approve', dept) && status != 'archived')
                PopupMenuItem(value: 'archive', child: Text(t('أرشفة', 'Archive'))),
              if (s.can('announcements', 'delete', dept))
                PopupMenuItem(value: 'delete', child: Text(t('حذف', 'Delete'), style: TextStyle(color: c.danger))),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Create an announcement from any context (e.g. a department dashboard). [onSaved] runs after a save.
Future<void> showCreateAnnouncementSheet(BuildContext context, {required int orgId, int? deptId, VoidCallback? onSaved}) =>
    showAnnouncementEditor(context, orgId: orgId, deptId: deptId, onSaved: onSaved ?? () {});

/// Create ([edit] null) or edit an announcement. Uses the selected organization unless [orgId] is given.
Future<void> showAnnouncementEditor(BuildContext context,
    {int? orgId, int? deptId, Map<String, dynamic>? edit, required VoidCallback onSaved}) async {
  final s = context.read<OrgSession>();
  final oid = orgId ?? s.currentId ?? 0;
  final base = '$orgBase/orgs/$oid';
  final sameOrg = s.currentId == oid;
  final title = TextEditingController(text: '${edit?['title'] ?? ''}');
  final body = TextEditingController(text: '${edit?['body'] ?? ''}');
  String cat = '${edit?['category'] ?? 'news'}';
  bool pinned = edit?['is_pinned'] == true, notify = edit?['notify'] == true, busy = false;
  String? image = edit?['image_url'] as String?;
  AnnLink? link = AnnLink.from(edit?['link']);
  DateTime? publishAt = orgParseUtc(edit?['publish_at']);
  DateTime? expireAt = orgParseUtc(edit?['expire_at']);
  if (publishAt != null && !publishAt.isAfter(DateTime.now().toUtc())) publishAt = null; // already out → not "scheduled"
  final aud = asMap(edit?['audience']);
  Map<String, dynamic> audience = {
    'roles': [...((aud['roles'] as List?) ?? const [])],
    'sub_orgs': aud['sub_orgs'] != false,
    'dept_ids': [...((aud['dept_ids'] as List?) ?? (deptId != null && edit == null ? [deptId] : const []))],
  };
  // a department manager without org-wide rights cannot publish org-wide — the server checks too
  final canPublish = sameOrg ? s.can('announcements', 'approve', deptId) : false;
  final targets = _LinkTargets(base, deptId);

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> save({bool publish = false}) async {
          if (title.text.trim().length < 2) {
            toast(t('اكتب عنواناً واضحاً', 'Write a clear title'), error: true);
            return;
          }
          if (link != null && link!.target.trim().isEmpty) {
            toast(t('اختر وجهة الزر أو احذفه', 'Pick where the button goes, or remove it'), error: true);
            return;
          }
          set(() => busy = true);
          final b = <String, dynamic>{
            'title': title.text.trim(),
            'body': body.text.trim(),
            'category': cat,
            'is_pinned': pinned,
            'notify': notify,
            'audience': audience,
            'image_url': image,
            'link': link?.toJson(),
            'publish_at': orgUtc(publishAt),
            'expire_at': orgUtc(expireAt),
            if (edit == null) 'dept_id': deptId,
          };
          var r = edit == null
              ? await OrgApi.i.post('$base/announcements', b, publish ? null : t('حُفظت المسودة', 'Draft saved'))
              : await OrgApi.i.put('$base/announcements/${edit['id']}', b, publish ? null : t('تم الحفظ', 'Saved'));
          if (r is Map && publish && '${r['status']}' != 'published') {
            r = await OrgApi.i.post('$base/announcements/${r['id']}/publish', null,
                publishAt != null ? t('جُدول الإعلان ⏰', 'Scheduled ⏰') : t('نُشر الإعلان 🎉', 'Published 🎉'));
          }
          if (!ctx.mounted) return;
          set(() => busy = false);
          if (r != null) {
            onSaved();
            Navigator.pop(ctx);
          }
        }

        Future<DateTime?> pickWhen(DateTime? current) async {
          final now = DateTime.now();
          final local = current?.toLocal() ?? now.add(const Duration(hours: 1));
          final d = await showDatePicker(
              context: ctx, initialDate: local.isBefore(now) ? now : local, firstDate: now, lastDate: now.add(const Duration(days: 365)));
          if (d == null || !ctx.mounted) return null;
          final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(local));
          if (tm == null) return null;
          return DateTime(d.year, d.month, d.day, tm.hour, tm.minute).toUtc();
        }

        final published = '${edit?['status']}' == 'published';
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppSheetHeader(edit == null ? t('إعلان جديد', 'New announcement') : t('تعديل الإعلان', 'Edit announcement')),
            if (published)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppBanner(
                  icon: Icons.info_outline_rounded,
                  text: t('الإعلان منشور: تغيير الجمهور يحدّث قائمة المستهدفين ويُرسل للمنضمين الجدد فقط.',
                      'This is live: changing the audience updates the targeted list and only notifies newcomers.'),
                ),
              ),
            ChoiceRow<String>(label: t('النوع', 'Type'), options: annCategories(), value: cat, onChanged: (v) => set(() => cat = v)),
            Field(controller: title, label: t('العنوان', 'Title')),
            // "@" suggests the organization's members (this announcement's audience once saved), D-075
            Mentions(
              controller: body,
              source: MentionApi.source('announcement', ref: oid, item: int.tryParse('${edit?['id'] ?? ''}')),
              child: Field(controller: body, label: t('التفاصيل', 'Details'), maxLines: 5),
            ),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await orgPickAndUpload('$base/uploads',
                      extensions: const ['png', 'jpg', 'jpeg', 'webp'], context: ctx, cropShape: CropShape.wide);
                  if (f != null) set(() => image = '${f['url']}');
                },
                icon: const Icon(Icons.image_rounded),
                label: Text(image == null ? t('إضافة صورة', 'Add image') : t('تغيير الصورة', 'Change image')),
              ),
              if (image != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Image.network(orgFileUrl(image), width: 52, height: 40, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink())),
                  IconButton(tooltip: t('إزالة', 'Remove'), onPressed: () => set(() => image = null), icon: Icon(Icons.close_rounded, color: c.textLight)),
                ]),
            ]),
            const SizedBox(height: AppSpace.md),
            AppSectionTitle(t('زر الإجراء', 'Call to action'),
                subtitle: t('اختياري: أين يذهب العضو عند الضغط؟ نتتبّع الضغطات وإكمال النماذج.',
                    'Optional: where members go when they tap. Clicks and form completions are tracked.')),
            _LinkEditor(targets: targets, value: link, onChanged: (v) => set(() => link = v)),
            const SizedBox(height: AppSpace.md),
            AppSectionTitle(t('الجمهور', 'Audience')),
            OrgAudiencePicker(
              value: audience,
              onChanged: (v) => set(() => audience = {...audience, 'roles': v['roles'], 'sub_orgs': v['sub_orgs']}),
            ),
            _DeptAudience(
              targets: targets,
              value: [for (final d in (audience['dept_ids'] as List)) asInt(d)],
              onChanged: (ids) => set(() => audience = {...audience, 'dept_ids': ids}),
            ),
            const SizedBox(height: AppSpace.xs),
            AppSwitchTile(
                title: t('تثبيت في الأعلى', 'Pin to the top'),
                icon: Icons.push_pin_rounded,
                value: pinned,
                onChanged: (v) => set(() => pinned = v)),
            AppSwitchTile(
                title: t('إشعار فوري عند النشر', 'Send a push when published'),
                subtitle: t('للأمور المهمة فقط حتى لا نُزعج أحداً', 'Keep it for what matters, so nobody gets spammed'),
                icon: Icons.notifications_active_rounded,
                value: notify,
                onChanged: (v) => set(() => notify = v)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _WhenChip(
                icon: Icons.schedule_send_rounded,
                label: publishAt == null ? t('النشر فوراً', 'Publish immediately') : t('ينشر ${AppTime.dateTime(publishAt!)}', 'Goes out ${AppTime.dateTime(publishAt!)}'),
                active: publishAt != null,
                onTap: () async {
                  final v = await pickWhen(publishAt);
                  if (v != null) set(() => publishAt = v);
                },
                onClear: publishAt == null ? null : () => set(() => publishAt = null),
              ),
              _WhenChip(
                icon: Icons.event_busy_rounded,
                label: expireAt == null ? t('بلا تاريخ انتهاء', 'No end date') : t('يختفي ${AppTime.dateTime(expireAt!)}', 'Hides ${AppTime.dateTime(expireAt!)}'),
                active: expireAt != null,
                onTap: () async {
                  final v = await pickWhen(expireAt);
                  if (v != null) set(() => expireAt = v);
                },
                onClear: expireAt == null ? null : () => set(() => expireAt = null),
              ),
            ]),
            const SizedBox(height: AppSpace.md),
            if (canPublish)
              AppPrimaryButton(
                  busy: busy,
                  label: published
                      ? t('حفظ التعديلات', 'Save changes')
                      : publishAt != null
                          ? t('حفظ وجدولة', 'Save & schedule')
                          : t('حفظ ونشر', 'Save & publish'),
                  icon: Icons.send_rounded,
                  onPressed: () => save(publish: true)),
            if (!published) ...[
              const SizedBox(height: AppSpace.xs),
              OutlinedButton(
                onPressed: busy ? null : () => save(),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control))),
                child: Text(canPublish ? t('حفظ كمسودة', 'Save as draft') : t('حفظ وإرسال للاعتماد', 'Save for approval'),
                    style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        );
      }));
}

class _WhenChip extends StatelessWidget {
  const _WhenChip({required this.icon, required this.label, required this.active, required this.onTap, this.onClear});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = active ? c.primary : c.textMedium;
    return InputChip(
      avatar: Icon(icon, size: AppIconSize.sm, color: col),
      label: Text(label, style: appText(12.5, w: FontWeight.w700, c: col)),
      onPressed: onTap,
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close_rounded, size: AppIconSize.sm),
      backgroundColor: active ? c.primary.withValues(alpha: 0.08) : c.background,
      side: BorderSide(color: active ? c.primary.withValues(alpha: 0.4) : c.divider),
    );
  }
}

/// Forms · departments · courses the call-to-action / audience can point at (loaded once per editor).
class _LinkTargets {
  _LinkTargets(this.base, this.deptId);
  final String base;
  final int? deptId;
  Future<Map<String, dynamic>>? _f;

  Future<Map<String, dynamic>> get data => _f ??= () async {
        try {
          return asMap(await ApiClient().get('$base/announcements/link-targets',
              queryParams: {if (deptId != null) 'dept_id': deptId}));
        } catch (_) {
          return <String, dynamic>{};
        }
      }();
}

class _LinkEditor extends StatefulWidget {
  const _LinkEditor({required this.targets, required this.value, required this.onChanged});
  final _LinkTargets targets;
  final AnnLink? value;
  final ValueChanged<AnnLink?> onChanged;

  @override
  State<_LinkEditor> createState() => _LinkEditorState();
}

class _LinkEditorState extends State<_LinkEditor> {
  late final _url = TextEditingController(text: widget.value?.kind == 'url' ? widget.value!.target : '');
  late final _label = TextEditingController(text: widget.value?.label ?? '');

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  void _emit(String? kind, String target) {
    if (kind == null) return widget.onChanged(null);
    final l = _label.text.trim();
    widget.onChanged(AnnLink(kind, target, label: l.isEmpty ? null : l));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final kind = v?.kind ?? '';
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.targets.data,
      builder: (context, snap) {
        final d = snap.data ?? const <String, dynamic>{};
        final forms = {for (final f in asMapList(d['forms'])) '${f['id']}': '${f['title']}${f['status'] == 'draft' ? ' · ${t('مسودة', 'draft')}' : ''}'};
        final sections = {
          ...annSections(),
          for (final x in asMapList(d['departments'])) 'dept:${x['id']}': '${t('إدارة', 'Dept.')}: ${orgNameOf(x)}',
        };
        final courses = {for (final x in asMapList(d['courses'])) '${x['id']}': orgNameOf(x)};
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ChoiceRow<String>(
            options: {
              '': t('بدون', 'None'),
              'form': t('نموذج', 'Form'),
              'section': t('قسم في التطبيق', 'App section'),
              'course': t('مقرر', 'Course'),
              'url': t('رابط خارجي', 'Web link'),
            },
            value: kind,
            onChanged: (k) {
              if (k == kind) return;
              _emit(k.isEmpty ? null : k, k == 'url' ? _url.text.trim() : '');
            },
          ),
          if (kind == 'form')
            forms.isEmpty && snap.connectionState == ConnectionState.done
                ? AppBanner(
                    icon: Icons.assignment_late_rounded,
                    text: t('لا توجد نماذج مفتوحة بعد — أنشئ نموذجاً من «النماذج» ثم اربطه هنا.',
                        'No open forms yet — create one under “Forms”, then link it here.'))
                : AppPicker<String>(
                    label: t('النموذج', 'Form'),
                    icon: Icons.assignment_rounded,
                    value: v!.target.isEmpty ? null : v.target,
                    options: forms,
                    onChanged: (x) => _emit('form', x ?? ''),
                  ),
          if (kind == 'section')
            AppPicker<String>(
              label: t('القسم', 'Section'),
              icon: Icons.dashboard_customize_rounded,
              value: v!.target.isEmpty ? null : v.target,
              options: sections,
              onChanged: (x) => _emit('section', x ?? ''),
            ),
          if (kind == 'course')
            AppPicker<String>(
              label: t('المقرر', 'Course'),
              icon: Icons.menu_book_rounded,
              value: v!.target.isEmpty ? null : v.target,
              options: courses,
              onChanged: (x) => _emit('course', x ?? ''),
            ),
          if (kind == 'url')
            Field(controller: _url, label: 'https://…', ltr: true, keyboard: TextInputType.url, hint: 'https://example.com')
                ._listen(() => _emit('url', _url.text.trim())),
          if (kind.isNotEmpty)
            Field(controller: _label, label: t('نص الزر (اختياري)', 'Button text (optional)'), hint: v?.cta)
                ._listen(() => _emit(kind, kind == 'url' ? _url.text.trim() : v!.target)),
        ]);
      },
    );
  }
}

extension on Field {
  /// Field has no onChanged — listen to its controller instead (idempotent per controller).
  Widget _listen(VoidCallback f) => _Listen(controller: controller, onChanged: f, child: this);
}

class _Listen extends StatefulWidget {
  const _Listen({required this.controller, required this.onChanged, required this.child});
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Widget child;

  @override
  State<_Listen> createState() => _ListenState();
}

class _ListenState extends State<_Listen> {
  late String _last = widget.controller.text;

  void _on() {
    if (widget.controller.text == _last) return;
    _last = widget.controller.text;
    widget.onChanged();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_on);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_on);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DeptAudience extends StatelessWidget {
  const _DeptAudience({required this.targets, required this.value, required this.onChanged});
  final _LinkTargets targets;
  final List<int> value;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<Map<String, dynamic>>(
      future: targets.data,
      builder: (context, snap) {
        final depts = asMapList(snap.data?['departments']);
        if (depts.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: AppSpace.xxs),
          Text(t('إدارات محددة (اختياري)', 'Specific departments (optional)'), style: AppType.label(context).copyWith(color: c.textLight)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final d in depts)
              FilterChip(
                avatar: Icon(deptIcon(d['icon']), size: AppIconSize.sm, color: hexColor(d['color'], c.primary)),
                label: Text(orgNameOf(d), style: TextStyle(fontFamily: AppFonts.family)),
                selected: value.contains(asInt(d['id'])),
                onSelected: (on) {
                  final n = [...value];
                  on ? n.add(asInt(d['id'])) : n.remove(asInt(d['id']));
                  onChanged(n);
                },
              ),
          ]),
          const SizedBox(height: AppSpace.xxs),
          Text(
              value.isEmpty
                  ? t('بدون اختيار: يصل لكل من يطابق الأدوار أعلاه.', 'None picked: everyone matching the roles above.')
                  : t('يصل فقط لمن انضم لهذه الإدارات أو يعمل بها.', 'Only people who joined or work in these departments.'),
              style: AppType.meta(context).copyWith(color: c.textLight)),
        ]);
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff: analytics
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> annPeopleLists(bool hasForm) => {
      'viewed': t('شاهدوا', 'Viewed'),
      'not_viewed': t('لم يشاهدوا', 'Not viewed'),
      'liked': t('أعجبهم', 'Liked'),
      'disliked': t('لم يعجبهم', 'Disliked'),
      'clicked': t('ضغطوا الزر', 'Clicked'),
      if (hasForm) 'completed': t('أكملوا النموذج', 'Completed'),
      if (hasForm) 'not_completed': t('لم يكملوا', 'Not completed'),
      'reached': t('وصلهم', 'Reached'),
      'not_reached': t('لم يصلهم', 'Not reached'),
      'targeted': t('كل المستهدفين', 'All targeted'),
    };

class OrgAnnouncementAnalyticsScreen extends StatefulWidget {
  const OrgAnnouncementAnalyticsScreen({super.key, required this.orgId, required this.announcementId, this.initial});
  final int orgId, announcementId;
  final Map<String, dynamic>? initial;

  @override
  State<OrgAnnouncementAnalyticsScreen> createState() => _AnalyticsState();
}

class _AnalyticsState extends State<OrgAnnouncementAnalyticsScreen> {
  Map<String, dynamic>? _d;
  bool _failed = false;

  String get _url => '$orgBase/orgs/${widget.orgId}/announcements/${widget.announcementId}/analytics';

  /// The dashboard header's Refresh (it replaces the old refresh icon) reloads the insights in place.
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    _load();
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_url);
    if (!mounted) return;
    setState(() {
      _d = r ?? _d;
      _failed = r == null && _d == null;
    });
    if (r != null) _refresh.markUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final title = '${asMap(_d?['announcement'])['title'] ?? widget.initial?['title'] ?? t('الإعلان', 'Announcement')}';
    // staff only (opened from the announcements page): the dashboard's own header
    return OrgPushedPage(
      title: t('تفاعل الإعلان', 'Announcement insights'),
      subtitle: title,
      refresh: _refresh,
      child: _readable(980, _d == null
          ? (_failed
              ? AppEmpty(
                  icon: Icons.insights_rounded,
                  title: t('تعذّر تحميل التحليلات', "Couldn't load the insights"),
                  actionLabel: t('إعادة المحاولة', 'Try again'),
                  onAction: _load)
              : const AppListSkeleton(items: 5, withAvatar: false))
          : AppRefresh(onRefresh: _load, child: _body(context, title, _d!))),
    );
  }

  Widget _body(BuildContext context, String title, Map<String, dynamic> d) {
    final c = context.colors;
    final tot = asMap(d['totals']);
    final rates = asMap(d['rates']);
    final ann = asMap(d['announcement']);
    final hasForm = d['has_form'] == true;
    final link = AnnLink.from(d['link']);
    final at = orgParseUtc(ann['publish_at']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl),
      children: [
        AppHero(
          title: title,
          subtitle: [
            statusLabel('${ann['status']}'),
            if (at != null) AppTime.dateTime(at),
            if (link != null) link.describe,
          ].join(' · '),
          icon: annIcons['${ann['category']}'] ?? Icons.campaign_rounded,
          stats: [
            AppHeroStat(icon: Icons.groups_rounded, value: '${tot['targeted'] ?? 0}', label: t('مستهدف', 'Targeted')),
            AppHeroStat(icon: Icons.visibility_rounded, value: '${tot['viewed_targeted'] ?? 0}', label: t('شاهد', 'Viewed')),
            AppHeroStat(icon: Icons.thumb_up_alt_rounded, value: '${tot['likes'] ?? 0}', label: t('إعجاب', 'Likes')),
          ],
        ),
        if (d['estimated'] == true) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.info_outline_rounded,
            color: c.warning,
            text: t('قائمة المستهدفين حُسبت بعد النشر (إعلان أقدم من التتبّع أو جمهور مُعدَّل)، فقد تختلف قليلاً عمّن وصلهم فعلاً.',
                'The targeted list was computed after publishing (older announcement or edited audience), so it may differ slightly from who actually got it.'),
          ),
        ],
        if (asInt(tot['late_viewers']) > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.person_add_alt_1_rounded,
            text: t('${tot['late_viewers']} شاهدوه بعد انضمامهم لاحقاً للجمهور (غير محسوبين ضمن المستهدفين).',
                '${tot['late_viewers']} joined the audience later and viewed it (not counted as targeted).'),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('مسار التفاعل', 'Engagement funnel'),
            subtitle: t('من استُهدف حتى من أتمّ المطلوب', 'From who was targeted to who followed through')),
        AppCard(child: _Funnel(steps: asMapList(d['funnel']))),
        const SizedBox(height: AppSpace.md),
        AppGrid(minTile: 150, children: [
          AppStatTile(icon: Icons.mark_email_read_rounded, label: t('نسبة الوصول', 'Reach'), value: '${rates['reach'] ?? 0}%', color: c.accent),
          AppStatTile(icon: Icons.visibility_rounded, label: t('نسبة المشاهدة', 'View rate'), value: '${rates['view'] ?? 0}%', color: c.primary),
          AppStatTile(icon: Icons.ads_click_rounded, label: t('نسبة الضغط', 'Click rate'), value: '${rates['click'] ?? 0}%', color: c.warning),
          if (hasForm)
            AppStatTile(
                icon: Icons.task_alt_rounded, label: t('نسبة الإكمال', 'Completion'), value: '${rates['completion'] ?? 0}%', color: c.success),
          AppStatTile(
              icon: Icons.touch_app_rounded, label: t('إجمالي الضغطات', 'Total clicks'), value: '${tot['clicks_total'] ?? 0}', color: c.textMedium),
        ]),
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('آراء الجمهور', 'How people felt')),
        AppCard(child: _Sentiment(likes: asInt(tot['likes']), dislikes: asInt(tot['dislikes']))),
        if (asMapList(d['timeline']).isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          AppSectionTitle(t('المشاهدات يوماً بيوم', 'Views day by day'), subtitle: t('أول 14 يوماً من النشر', 'First 14 days after publishing')),
          AppCard(child: _Timeline(days: asMapList(d['timeline']))),
        ],
        const SizedBox(height: AppSpace.md),
        _PeopleSection(orgId: widget.orgId, announcementId: widget.announcementId, hasForm: hasForm, title: title),
      ],
    );
  }
}

class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});
  final List<Map<String, dynamic>> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (steps.isEmpty) return const SizedBox.shrink();
    final top = math.max(1, asInt(steps.first['count']));
    final colors = [c.accent, c.primary, c.success, c.warning, c.danger];
    return Column(children: [
      for (var i = 0; i < steps.length; i++) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(children: [
              Icon(Icons.south_rounded, size: AppIconSize.xs, color: c.textLight),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(_drop(asInt(steps[i - 1]['count']), asInt(steps[i]['count'])),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
              ),
            ]),
          ),
        _FunnelBar(
          label: t('${steps[i]['label_ar']}', '${steps[i]['label_en']}'),
          count: asInt(steps[i]['count']),
          ratio: asInt(steps[i]['count']) / top,
          color: colors[i % colors.length],
        ),
      ],
    ]);
  }

  String _drop(int from, int to) {
    if (from <= 0) return t('—', '—');
    final kept = (100 * to / from).toStringAsFixed(0);
    return t('استمر $kept٪ · خرج ${from - to}', '$kept% continued · ${from - to} dropped');
  }
}

class _FunnelBar extends StatelessWidget {
  const _FunnelBar({required this.label, required this.count, required this.ratio, required this.color});
  final String label;
  final int count;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final bar = math.max(36.0, w * ratio.clamp(0.0, 1.0));
      return Stack(alignment: AlignmentDirectional.centerStart, children: [
        Container(height: 42, decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(AppRadius.control))),
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          height: 42,
          width: bar,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText(13, w: FontWeight.w800, c: ratio > 0.35 ? c.onHero : c.textDark)),
            ),
            Text('$count', style: appText(14, w: FontWeight.w900, c: ratio > 0.92 ? c.onHero : c.textDark)),
            const SizedBox(width: AppSpace.xs),
            Text('${(ratio * 100).toStringAsFixed(0)}%',
                style: appText(11.5, w: FontWeight.w700, c: ratio > 0.92 ? c.onHeroMuted : c.textLight)),
          ]),
        ),
      ]);
    });
  }
}

class _Sentiment extends StatelessWidget {
  const _Sentiment({required this.likes, required this.dislikes});
  final int likes, dislikes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = likes + dislikes;
    if (total == 0) {
      return Row(children: [
        Icon(Icons.sentiment_neutral_rounded, color: c.textLight),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(t('لم يتفاعل أحد بعد بإعجاب أو عدم إعجاب', 'No likes or dislikes yet'), style: AppType.row(context).copyWith(color: c.textMedium))),
      ]);
    }
    final p = likes / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.thumb_up_alt_rounded, size: AppIconSize.md, color: c.success),
        const SizedBox(width: AppSpace.xs),
        Text('$likes', style: appText(15, w: FontWeight.w900, c: c.success)),
        const Spacer(),
        Text('${(p * 100).toStringAsFixed(0)}% ${t('إيجابي', 'positive')}', style: AppType.meta(context).copyWith(color: c.textMedium)),
        const Spacer(),
        Text('$dislikes', style: appText(15, w: FontWeight.w900, c: c.danger)),
        const SizedBox(width: AppSpace.xs),
        Icon(Icons.thumb_down_alt_rounded, size: AppIconSize.md, color: c.danger),
      ]),
      const SizedBox(height: AppSpace.xs),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: SizedBox(
          height: 10,
          child: Row(children: [
            if (likes > 0) Expanded(flex: likes, child: Container(color: c.success)),
            if (dislikes > 0) Expanded(flex: dislikes, child: Container(color: c.danger)),
          ]),
        ),
      ),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.days});
  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final peak = days.fold<int>(1, (m, d) => math.max(m, asInt(d['views'])));
    return SizedBox(
      height: 120,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in days)
          Expanded(
            child: Tooltip(
              message: '${d['day']} · ${d['views']} ${t('مشاهدة', 'views')} · ${d['clicks']} ${t('ضغطة', 'clicks')}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs / 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (asInt(d['views']) > 0)
                    FittedBox(child: Text('${d['views']}', style: appText(10, w: FontWeight.w700, c: c.textMedium))),
                  const SizedBox(height: AppSpace.xxs / 2),
                  Container(
                    height: math.max(3.0, 78.0 * asInt(d['views']) / peak),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [c.primary, c.primary.withValues(alpha: 0.45)]),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxs),
                  FittedBox(
                    child: Text('${d['day']}'.length >= 10 ? '${d['day']}'.substring(8, 10) : '${d['day']}',
                        style: appText(10, c: c.textLight)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PeopleSection extends StatefulWidget {
  const _PeopleSection({required this.orgId, required this.announcementId, required this.hasForm, required this.title});
  final int orgId, announcementId;
  final bool hasForm;
  final String title;

  @override
  State<_PeopleSection> createState() => _PeopleSectionState();
}

class _PeopleSectionState extends State<_PeopleSection> {
  String _list = 'viewed';
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _items;
  Map<String, dynamic> _counts = {};
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = false;

  String get _base => '$orgBase/orgs/${widget.orgId}/announcements/${widget.announcementId}/analytics';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    final page = more ? _page + 1 : 1;
    final r = await OrgApi.i.getMap('$_base/people', {
      'list': _list,
      'page': page,
      'size': 40,
      if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r == null) return;
      final list = asMapList(r['items']);
      _items = more ? [...?_items, ...list] : list;
      _page = page;
      _pages = asInt(r['pages'], 1);
      _total = asInt(r['total']);
      _counts = asMap(r['counts']);
    });
  }

  Future<void> _export() async {
    final fmt = await showAppSheet<String>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppSheetHeader(t('تصدير «${annPeopleLists(widget.hasForm)[_list]}»', 'Export “${annPeopleLists(widget.hasForm)[_list]}”')),
            for (final (f, label, icon) in [
              ('xlsx', 'Excel', Icons.table_chart_rounded),
              ('pdf', 'PDF', Icons.picture_as_pdf_rounded),
              ('docx', 'Word', Icons.description_rounded),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, f),
              ),
          ]),
        ));
    if (fmt == null) return;
    final r = await OrgApi.i.getMap('$_base/export', {
      'list': _list,
      'format': fmt,
      if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
    });
    await openFileUrl(r?['url']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final lists = annPeopleLists(widget.hasForm);
    final canExport = s.currentId != widget.orgId || s.can('announcements', 'export') || s.can('announcements', 'approve') || s.canAny('announcements', 'export');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(
        t('الأشخاص', 'People'),
        subtitle: t('مَن شاهد ومَن لم يشاهد، ومَن تفاعل', 'Who saw it, who did not, and who reacted'),
        trailing: canExport
            ? IconButton(
                tooltip: t('تصدير القائمة', 'Export this list'),
                onPressed: _total == 0 ? null : _export,
                icon: Icon(Icons.file_download_rounded, color: c.primary))
            : null,
      ),
      SizedBox(
        height: MediaQuery.textScalerOf(context).scale(42), // the chips grow with the text size
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final e in lists.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: AppChoiceChip(
                label: _counts.containsKey(e.key) ? '${e.value} (${_counts[e.key]})' : e.value,
                selected: _list == e.key,
                onTap: () {
                  if (_list == e.key) return;
                  setState(() {
                    _list = e.key;
                    _items = null;
                  });
                  _load();
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: AppSpace.xs),
      TextField(
        controller: _search,
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), _load);
        },
        style: TextStyle(fontFamily: AppFonts.family),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: t('ابحث بالاسم أو البريد أو الهاتف', 'Search by name, e-mail or phone'),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      if (_items == null)
        const SizedBox(height: 220, child: AppListSkeleton(items: 3, padding: EdgeInsets.zero))
      else if (_items!.isEmpty)
        AppEmpty(
          icon: Icons.person_search_rounded,
          title: _search.text.trim().isNotEmpty ? t('لا نتائج لهذا البحث', 'No one matches this search') : t('لا أحد هنا بعد', 'Nobody here yet'),
        )
      else ...[
        for (final p in _items!) _PersonRow(p: p),
        if (_page < _pages)
          Center(
            child: _loading
                ? const Padding(padding: EdgeInsets.all(AppSpace.sm), child: CircularProgressIndicator(strokeWidth: 2.4))
                : TextButton.icon(
                    onPressed: () => _load(more: true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(t('عرض المزيد (${_total - _items!.length})', 'Show more (${_total - _items!.length})'),
                        style: TextStyle(fontFamily: AppFonts.family)),
                  ),
          ),
      ],
    ]);
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = asMap(p['user']);
    final role = memberRoleLabels()['${p['org_role']}'];
    String? when(String k) {
      final d = orgParseUtc(p[k]);
      return d == null ? null : AppTime.dateTime(d);
    }

    final facts = <(IconData, String, Color)>[
      if (when('viewed_at') != null) (Icons.visibility_rounded, when('viewed_at')!, c.primary),
      if (when('clicked_at') != null)
        (Icons.ads_click_rounded, '${when('clicked_at')}${asInt(p['click_count']) > 1 ? ' ×${p['click_count']}' : ''}', c.accent),
      if (when('completed_at') != null) (Icons.task_alt_rounded, when('completed_at')!, c.success),
      if (p['viewed_at'] == null && p['delivered_at'] != null) (Icons.mark_email_unread_rounded, t('وصله ولم يفتحه', 'Got it, not opened'), c.textLight),
      if (p['delivered_at'] == null && p['in_snapshot'] == true) (Icons.block_rounded, t('لم يصله (غادر قبل الإرسال)', 'Not reached (left before delivery)'), c.danger),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppAvatar(name: '${u['name'] ?? '?'}', url: u['image_url'] as String?, size: 40),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text('${u['name'] ?? '—'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              ),
              if (p['reaction'] == 'like') ...[const SizedBox(width: AppSpace.xs), Icon(Icons.thumb_up_alt_rounded, size: AppIconSize.sm, color: c.success)],
              if (p['reaction'] == 'dislike') ...[const SizedBox(width: AppSpace.xs), Icon(Icons.thumb_down_alt_rounded, size: AppIconSize.sm, color: c.danger)],
              if (p['in_snapshot'] != true) ...[
                const SizedBox(width: AppSpace.xs),
                Tooltip(
                    message: t('انضم للجمهور بعد النشر', 'Joined the audience after publishing'),
                    child: Icon(Icons.person_add_alt_1_rounded, size: AppIconSize.xs, color: c.textLight)),
              ],
            ]),
            if ('${u['email'] ?? ''}'.isNotEmpty || role != null)
              Text([?role, if ('${u['email'] ?? ''}'.isNotEmpty) '${u['email']}'].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
            if (facts.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: 10, runSpacing: 4, children: [
                for (final (icon, text, col) in facts)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: AppIconSize.xs, color: col),
                    const SizedBox(width: AppSpace.xxs),
                    Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium))),
                  ]),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
