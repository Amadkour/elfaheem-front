// lib/features/home/student/home_live.dart — the home's "Live now" banner, wired (student · instructor · org member).
//
//   HomeLiveNow(rooms:, now:)    HomeLiveBanner over MeHomeService.liveNow (or the given rooms): one card per room
//                                I'm invited to that is live — Join opens the pre-join page, where the person
//                                presses Join (D-106: never by itself). It appears and leaves on its own: the service
//                                reloads the home on `session_live` / `meeting_live` (no timer, no extra request on
//                                open or pull-to-refresh).
//   joinHomeLiveRoom(context, r) a course session → openCourseLiveRoom · a meeting → openMeetingRoom
//   homeLiveItemsOf(context, …)  MeLiveRoom → HomeLiveItem (plain values; layout / render tests)
//
// Kill switch: a session room hides with `live_sessions` (the course page's live entries hide with it too).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/home_kit.dart';
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
        kindLabel: (r.isMeeting ? 'home_live_meeting' : 'home_live_session').tr,
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

  @override
  Widget build(BuildContext context) {
    if (rooms != null) return HomeLiveBanner(items: homeLiveItemsOf(context, _scoped(rooms!)), now: now, padding: padding);
    final svc = MeHomeService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) => HomeLiveBanner(items: homeLiveItemsOf(context, _scoped(svc.liveNow)), now: now, padding: padding),
    );
  }
}
