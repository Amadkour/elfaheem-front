// lib/features/home/student/home_live.dart — the home's "Live now" banner, wired (student · instructor · org member).
//
//   HomeLiveNow(rooms:, now:)    the live banner over MeHomeService.liveNow (or the given rooms), each Join in the
//                                redesign's words (ادخل الحصة / ادخل الاجتماع, S-A2): one card per room
//                                I'm invited to that is live — Join opens the pre-join page, where the person
//                                presses Join (D-106: never by itself). It appears and leaves on its own: the service
//                                reloads the home on `session_live` / `meeting_live` (no timer, no extra request on
//                                open or pull-to-refresh).
//   joinHomeLiveRoom(context, r) a course session → openCourseLiveRoom · a meeting → openMeetingRoom
//   homeLiveItemsOf(context, …)  MeLiveRoom → HomeLiveItem (plain values; layout / render tests)
//
// Kill switch: a session room hides with `live_sessions` (the course page's live entries hide with it too).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/features/calendar/calendar_api.dart' show RemoteCalendarApi;
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show openMeetingRoom;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/courses/student/details/course_live_join.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';

/// The feature key that hides a course session's live entries.
const kLiveSessionsFeatureKey = 'live_sessions';

/// Into the room of [r]: its pre-join page (camera / microphone check, then the person presses Join, D-106).
Future<void> joinHomeLiveRoom(BuildContext context, MeLiveRoom r) async {
  if (GuestState.active) return;
  if (r.isMeeting) {
    await openMeetingRoom(
      context,
      api: const RemoteCalendarApi(),
      meeting: {
        'id': r.id,
        'title': r.title,
        'mode': 'online',
        'is_owner': false,
        'owner': {'name': ?r.hostName},
      },
      canRecord: false,
      isHost: false,
    );
    return;
  }
  await openCourseLiveRoom(
    context,
    sessionId: r.id,
    courseId: r.courseId ?? 0,
    sessionName: r.title.isEmpty ? null : r.title,
    hostName: r.hostName,
  );
}

/// A tap on the card itself: the course page (session) · the calendar on that meeting.
void openHomeLiveRoom(BuildContext context, MeLiveRoom r) {
  if (r.isMeeting) {
    Navigator.of(context).pushNamed('/calendar', arguments: {'meeting_id': r.id, 'org_id': ?r.orgId});
  } else if (r.courseId != null) {
    AppNavigator.openCourse(r.courseId!);
  }
}

/// The rooms as banner items (the kill switch applied).
List<HomeLiveItem> homeLiveItemsOf(
  BuildContext context,
  List<MeLiveRoom> rooms, {
  void Function(MeLiveRoom r)? onJoin,
  void Function(MeLiveRoom r)? onOpen,
}) => [
  for (final r in rooms)
    if (r.isMeeting || !AppConfig.disableList.contains(kLiveSessionsFeatureKey))
      HomeLiveItem(
        title: r.title,
        kindLabel: (r.isMeeting ? 'home_live_meeting' : 'sa_live_class').tr, // redesign vocabulary: حصة, never جلسة
        subtitle: r.subtitle,
        hostName: r.hostName,
        hostImageUrl: r.hostImageUrl,
        startedAt: r.startedAt,
        onJoin: () => onJoin == null ? joinHomeLiveRoom(context, r) : onJoin(r),
        onOpen: () => onOpen == null ? openHomeLiveRoom(context, r) : onOpen(r),
      ),
];

/// The banner over [rooms], or — null — over MeHomeService.liveNow (listened: it updates by itself). [orgId] keeps
/// only that organization's meetings and the personal course sessions out (Organization mode).
class HomeLiveNow extends StatelessWidget {
  const HomeLiveNow({super.key, this.rooms, this.now, this.orgId, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<MeLiveRoom>? rooms;
  final DateTime? now;
  final int? orgId;
  final EdgeInsetsGeometry padding;

  List<MeLiveRoom> _scoped(List<MeLiveRoom> all) => orgId == null ? all : [for (final r in all) if (r.orgId == orgId) r];

  Widget _banner(BuildContext context, List<MeLiveRoom> all) {
    final scoped = _scoped(all);
    final items = homeLiveItemsOf(context, scoped);
    // the redesign's wording on the Join (StuHome: "ادخل الحصة" / "ادخل الاجتماع", S-A2), one per room in order
    final labels = [
      for (final r in scoped)
        if (r.isMeeting || !AppConfig.disableList.contains(kLiveSessionsFeatureKey))
          (r.isMeeting ? 'sa_live_join_meeting' : 'sa_live_join_class').tr,
    ];
    return _LiveNowBanner(items: items, labels: labels, now: now, padding: padding);
  }

  @override
  Widget build(BuildContext context) {
    if (rooms != null) return _banner(context, rooms!);
    final svc = MeHomeService.instance;
    return ListenableBuilder(listenable: svc, builder: (context, _) => _banner(context, svc.liveNow));
  }
}

/// [HomeLiveBanner]'s list with each Join in the redesign's words ([labels], one per item). HomeLiveItem has no
/// action label of its own yet (lib/design/home_kit.dart, a kit request); the rest is the kit's AppLiveBanner, the
/// same "live for" clock ticking every second while shown, and the same plain-values layout.
class _LiveNowBanner extends StatefulWidget {
  const _LiveNowBanner({required this.items, required this.labels, required this.now, required this.padding});
  final List<HomeLiveItem> items;
  final List<String> labels;
  final DateTime? now;
  final EdgeInsetsGeometry padding;

  @override
  State<_LiveNowBanner> createState() => _LiveNowBannerState();
}

class _LiveNowBannerState extends State<_LiveNowBanner> {
  Timer? _tick;

  void _sync() {
    final want = widget.now == null && widget.items.any((x) => x.startedAt != null);
    if (want && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!want) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_LiveNowBanner old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Widget _card(BuildContext context, HomeLiveItem x, String label, DateTime now, int index) {
    final sep = AppConfig.lang == 'ar' ? '، ' : ' · ';
    final since = x.startedAt == null ? null : homeLiveFor(now.difference(x.startedAt!));
    final who = [
      if (x.hostName != null && x.hostName!.isNotEmpty) 'home_live_with'.tr.replaceAll('{name}', x.hostName!),
      if (x.subtitle != null && x.subtitle!.isNotEmpty) x.subtitle!,
    ].join(sep);
    final title = x.title.isEmpty ? (x.kindLabel ?? 'home_live'.tr) : x.title;
    final name = (x.hostName ?? title).trim();
    final u = x.hostImageUrl;
    return Semantics(
      container: true,
      label: [x.kindLabel ?? 'home_live'.tr, title, if (who.isNotEmpty) who].join(', '),
      child: AppLiveBanner(
        index: index,
        title: title,
        subtitle: who.isEmpty ? null : who,
        tag: [x.kindLabel ?? 'home_live_badge'.tr, ?since].join(sep),
        host: u != null && u.startsWith('http')
            ? AppNetworkImage(url: u, width: AppDashSize.ringSm, height: AppDashSize.ringSm)
            : null,
        hostInitial: name.isEmpty ? null : name.characters.first.toUpperCase(),
        actionLabel: label,
        onAction: x.onJoin,
        onTap: x.onOpen ?? x.onJoin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final now = widget.now ?? DateTime.now().toUtc();
    return AnimatedSize(
      duration: still ? Duration.zero : AppMotion.of(context).base,
      curve: AppMotion.curve,
      alignment: AlignmentDirectional.topCenter,
      child: items.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: widget.padding,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpace.xs),
                  _card(context, items[i], i < widget.labels.length ? widget.labels[i] : 'home_live_join'.tr, now, i),
                ],
              ]),
            ),
    );
  }
}
