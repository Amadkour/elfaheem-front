// lib/features/live/meeting_links_page.dart — "Meeting links" (D-307): every room the person can open, on one
// page, ready to join or hand out — live now first, then the next ones by day, the last 7 days at the end.
//
// Each room: Join (its pre-join page, D-106) or Open (the meeting's detail / the course page), Copy and Share (the
// share sheet with the QR code) of its member link `https://alfheemacademy.com/s/meeting|session/<id>` (D-307), and for
// the host the guest link (`/live/<token>`, no account needed; marked expired once the room ended). Filters (All ·
// Live now · Upcoming · I host · Guest links · Past) and a search box; "Meet now" is the page's primary action.
//
// Data: ONE `GET /api/v1/me/meeting-links` (meeting_links.dart), reloaded on pull-to-refresh, Refresh and the live
// events `meeting_live` / `session_live` / `calendar_updated` (no timer). Route `/meeting-links` (route registry id
// `meetings.links`); entries: the Schedule page's header, the teacher home's header, the org dashboard's Home. Kill
// switch `live.meeting_links`. Parts (plain values, layout-tested): meeting_links_parts.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/courses/student/details/course_live_join.dart' show openCourseLiveRoom;
import 'package:flutter_education_app/features/calendar/calendar_api.dart' show RemoteCalendarApi;
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show openMeetingRoom, startQuickMeeting;
import 'package:flutter_education_app/features/courses/course_profile/course_profile_hub.dart' show CoursePageLoader;
import 'package:flutter_education_app/features/live/meeting_links.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2HeroPage;
import 'package:flutter_education_app/features/live/meeting_links_parts.dart';

/// The kill switch of the page and of every entry to it.
const kMeetingLinksFeatureKey = 'live.meeting_links';

/// The route of the page (route registry id `meetings.links`).
const kMeetingLinksRoute = '/meeting-links';

void openMeetingLinks(BuildContext context) => Navigator.of(context).pushNamed(kMeetingLinksRoute);

/// The entry icon: a plain icon button for an app bar / toolbar (the Schedule page), the home header's tinted square
/// with [chrome] (the teacher home, next to the calendar).
class MeetingLinksIcon extends StatelessWidget {
  const MeetingLinksIcon({super.key, this.chrome = false});
  final bool chrome;

  @override
  Widget build(BuildContext context) {
    final label = t('روابط الاجتماعات', 'Meeting links');
    return ParentComponent(
      featureKey: kMeetingLinksFeatureKey,
      child: chrome
          ? ChromeIconButton(key: const ValueKey('meeting_links.entry'), icon: Icons.link_rounded, label: label, onTap: () => openMeetingLinks(context))
          : IconButton(
              key: const ValueKey('meeting_links.entry'),
              tooltip: label,
              onPressed: () => openMeetingLinks(context),
              icon: Icon(Icons.link_rounded, color: context.colors.textMedium),
            ),
    );
  }
}

/// The rooms as a ListView on a plain page, as a Column inside a card that already scrolls (the teacher's page).
Widget _wrap(bool inset, EdgeInsets pad, List<Widget> children) =>
    inset ? ListView(padding: pad, children: children) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);

class MeetingLinksPage extends StatefulWidget {
  const MeetingLinksPage({super.key, this.api = const MeetingLinksApi()});
  final MeetingLinksApi api;

  @override
  State<MeetingLinksPage> createState() => _MeetingLinksPageState();
}

class _MeetingLinksPageState extends State<MeetingLinksPage> {
  MeetingLinksData? _data;
  String? _error;
  DateTime? _loadedAt;
  MeetingLinksFilter _filter = MeetingLinksFilter.all;
  String _query = '';
  StreamSubscription<LiveEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = LiveEvents.instance.listen({LiveEvents.meetingLive, LiveEvents.sessionLive, LiveEvents.calendarUpdated}, (_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = appErrorMessage(e));
    }
  }

  // ── actions ────────────────────────────────────────────────────────────────
  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    showAppNotice(t('تم نسخ الرابط', 'Link copied'));
  }

  void _share(MeetingLinkItem i) => shareAppLink(context, i.link,
      title: i.title,
      subtitle: [if (i.startsAt != null) AppTime.dateTime(i.startsAt!), ?i.subtitle].join(' · '),
      hint: t('يفتحه المدعوون وطلاب الكورس بعد تسجيل الدخول. للضيوف بلا حساب استخدم رابط الضيوف.',
          'Invitees and course students open it after signing in. For guests without an account, use the guest link.'));

  void _shareGuest(MeetingLinkItem i) => showAppShareSheet(context,
      url: i.guest!.url,
      title: i.title,
      subtitle: i.startsAt == null ? null : AppTime.dateTime(i.startsAt!),
      kind: t('رابط الضيوف', 'Guest link'),
      icon: Icons.public_rounded,
      hint: i.guest!.hasPin
          ? t('أي شخص لديه الرابط ورمز PIN يمكنه طلب الدخول، دون حساب.', 'Anyone with the link and the PIN can ask to join, no account needed.')
          : t('أي شخص لديه الرابط يمكنه طلب الدخول، دون حساب.', 'Anyone with the link can ask to join, no account needed.'));

  Future<void> _open(MeetingLinkItem i) async {
    if (i.isMeeting) {
      await Navigator.of(context).pushNamed('/calendar', arguments: {'meeting_id': i.refId});
    } else if (i.courseId != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        settings: RouteSettings(name: '/course-detail', arguments: i.courseId),
        builder: (_) => CoursePageLoader(courseId: i.courseId!, tab: 'sessions'),
      ));
    }
    if (mounted) unawaited(_load());
  }

  /// Into the room: a meeting's pre-join page (host or invitee), a live course session's for a student. A session I
  /// host opens in its course (Go live / Rejoin live there), so it has no Join here.
  VoidCallback? _joinOf(MeetingLinkItem i) {
    if (i.isMeeting) {
      return () async {
        await openMeetingRoom(context,
            api: const RemoteCalendarApi(),
            meeting: {
              'id': i.refId,
              'title': i.title,
              'mode': 'online',
              'is_owner': i.isHost,
              'starts_at': i.startsAt?.toIso8601String(),
              'owner': {'name': ?i.subtitle},
            },
            isHost: i.isHost);
        if (mounted) unawaited(_load());
      };
    }
    if (i.isHost || i.status != MeetingLinkStatus.live || i.courseId == null) return null;
    return () => openCourseLiveRoom(context, sessionId: i.refId, courseId: i.courseId!, sessionName: i.title);
  }

  Future<void> _meetNow() async {
    await startQuickMeeting(context);
    if (mounted) unawaited(_load());
  }

  // ── layout ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final d = _data;
    // a student's links page is the schedule area (redesign S-C, Stu2Schedule?screen=links)
    final role = Provider.of<MyAuthProvider?>(context, listen: false)?.currentUser?.role;
    final student = role == 'student';
    if (role == 'teacher') return _teacherPage(context, d);
    final page = AdminPage(
      title: t('روابط الاجتماعات', 'Meeting links'),
      subtitle: t('كل روابط حصصك واجتماعاتك في مكان واحد: انضم، انسخ، شارك.',
          'Every session and meeting link in one place: join, copy, share.'),
      icon: Icons.link_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      primaryAction: AppConfig.disableList.contains('live.quick_meeting')
          ? null
          : AppButton.primary(
              key: const ValueKey('links.meet_now'),
              label: t('اجتمع الآن', 'Meet now'),
              icon: Icons.video_call_rounded,
              onPressed: _meetNow,
            ),
      search: d == null || d.items.isEmpty
          ? null
          : AppSearchField(
              hint: t('ابحث بالعنوان أو الدورة أو المضيف', 'Search by title, course or host'),
              onChanged: (v) => setState(() => _query = v),
            ),
      body: d == null
          ? (_error == null
              ? const AppListSkeleton(items: 4)
              : AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load))
          : AppRefresh(onRefresh: _load, child: _list(context, d)),
    );
    return student ? AppAreaScope(area: AppArea.sched, child: page) : page;
  }

  /// A teacher's page (redesign T1, Tea1Home?screen=meetings): the teacher hero with "Meet now" as its call to
  /// action, the search, the filters and the rooms in one paper card riding up over it.
  Widget _teacherPage(BuildContext context, MeetingLinksData? d) {
    final meetOn = !AppConfig.disableList.contains('live.quick_meeting');
    final Widget body;
    if (d == null) {
      body = _error == null
          ? const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
          : AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else {
      body = _list(context, d, inset: false);
    }
    return T2HeroPage(
      title: t('روابط الاجتماعات', 'Meeting links'),
      onRefresh: _load,
      width: AppWidth.content,
      hero: AppHero(
        title: t('روابط الاجتماعات', 'Meeting links'),
        subtitle: 't1_hm_links_sub'.tr,
        actions: [
          if (meetOn)
            AppButton.hot(key: const ValueKey('links.meet_now'), label: 't1_hm_meet_now'.tr, icon: Icons.video_call_rounded, onPressed: _meetNow),
        ],
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d != null && d.items.isNotEmpty) ...[
              AppSearchField(
                hint: 't1_hm_links_search'.tr,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            body,
          ]),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, MeetingLinksData d, {bool inset = true}) {
    final pad = inset ? AdminPage.bodyPadding(context) : EdgeInsets.zero;
    if (d.items.isEmpty) {
      return _wrap(inset, pad, [
        const SizedBox(height: AppSpace.xl),
        AppEmpty(
          icon: Icons.link_rounded,
          title: t('لا روابط بعد', 'No links yet'),
          message: t('ستظهر هنا حصصك المباشرة واجتماعاتك القادمة، مع روابطها جاهزة للنسخ والمشاركة.',
              'Your live sessions and upcoming meetings show here, with their links ready to copy and share.'),
          actionLabel: AppConfig.disableList.contains('live.quick_meeting') ? null : t('اجتمع الآن', 'Meet now'),
          onAction: AppConfig.disableList.contains('live.quick_meeting') ? null : _meetNow,
        ),
      ]);
    }
    final shown = filterMeetingLinks(d.items, _filter, _query);
    final now = DateTime.now().toUtc();
    final counts = {for (final f in MeetingLinksFilter.values) f: d.count(f)};
    final groups = <(String, List<MeetingLinkItem>, bool)>[];
    final live = shown.where((i) => i.status == MeetingLinkStatus.live).toList();
    if (live.isNotEmpty) groups.add((t('مباشر الآن', 'Live now'), live, true));
    String? day;
    for (final i in shown.where((i) => i.status == MeetingLinkStatus.scheduled)) {
      final label = i.startsAt == null ? t('بلا موعد', 'No time set') : meetingLinkDayLabel(i.startsAt!, now);
      if (label != day) {
        groups.add((label, [], false));
        day = label;
      }
      groups.last.$2.add(i);
    }
    final past = shown.where((i) => i.status == MeetingLinkStatus.ended).toList();
    if (past.isNotEmpty) groups.add((t('آخر 7 أيام', 'Last 7 days'), past, true));

    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 680 ? 2 : 1);
      Widget card(MeetingLinkItem i, bool showDay) => MeetingLinkCard(
            key: ValueKey('links.card.${i.key}'),
            item: i,
            now: now,
            showDay: showDay,
            onOpen: () => _open(i),
            onJoin: _joinOf(i),
            onCopy: () => _copy(i.link.url(appLinkOrigin())),
            onShare: () => _share(i),
            onCopyGuest: i.guest == null ? null : () => _copy(i.guest!.url),
            onShareGuest: i.guest == null ? null : () => _shareGuest(i),
          );
      // the page's one entrance: the first cards rise in reading order, once per visit (AppReveal caps at 8)
      var shownAt = 0;
      Widget revealed(Widget w) => AppReveal(index: shownAt++, group: 'links', child: w);
      return _wrap(inset, pad, [
        if (inset) ...[
        MeetingLinksSummary(
          live: counts[MeetingLinksFilter.live] ?? 0,
          upcoming: counts[MeetingLinksFilter.upcoming] ?? 0,
          guestLinks: d.items.where((i) => i.guest?.active == true).length,
          onFilter: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: AppSpace.md),
        ],
        MeetingLinksFilterBar(value: _filter, counts: counts, onChanged: (f) => setState(() => _filter = f)),
        const SizedBox(height: AppSpace.md),
        if (shown.isEmpty)
          AppEmpty(
            icon: Icons.filter_alt_off_rounded,
            title: t('لا شيء يطابق', 'Nothing matches'),
            message: t('جرّب فلتراً آخر أو بحثاً أقصر.', 'Try another filter or a shorter search.'),
            actionLabel: t('عرض الكل', 'Show all'),
            onAction: () => setState(() {
              _filter = MeetingLinksFilter.all;
            }),
          ),
        for (final (g, (label, items, showDay)) in groups.indexed) ...[
          // the editorial rhythm: more room above a day's heading than under it (the first sits close to the filters)
          Padding(
            padding: EdgeInsetsDirectional.only(top: g == 0 ? AppSpace.xs : AppSpace.lg, bottom: AppSpace.sm),
            child: Semantics(header: true, child: Text(label, style: AppType.section(context))),
          ),
          if (cols == 1)
            for (final i in items) ...[revealed(card(i, showDay)), const SizedBox(height: AppSpace.sm)]
          else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                for (final i in items)
                  SizedBox(
                    width: (box.maxWidth - pad.horizontal - AppSpace.sm * (cols - 1)) / cols,
                    child: revealed(card(i, showDay)),
                  ),
              ]),
            ),
        ],
      ]);
    });
  }
}
