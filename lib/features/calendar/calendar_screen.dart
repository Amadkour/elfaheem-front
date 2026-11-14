// lib/features/calendar/calendar_screen.dart — route '/calendar', kept for every caller that knows it (deep
// links, notification taps, AppNavigator `calendar` / `live_lobby`, the org and department dashboards).
//
// The calendar and "My schedule" are ONE page now (D-085): this is a thin name for SchedulePage
// (schedule_page.dart), which owns the views, the data and the actions.
//
//   CalendarScreen()                     my overall schedule
//   CalendarScreen(orgId: o)             only that organization (+ my personal meetings)
//   CalendarScreen(deptId: d)            a department's calendar
//   CalendarScreen(openMeetingId: m)     opens on that meeting's sheet
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalView;
import 'package:flutter_education_app/features/calendar/schedule_page.dart';

export 'package:flutter_education_app/features/calendar/schedule_page.dart' show SchedulePage;

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, this.orgId, this.deptId, this.title, this.openMeetingId, this.api = const RemoteCalendarApi()});
  final int? orgId, deptId, openMeetingId;
  final String? title;
  final CalendarApi api;

  @override
  Widget build(BuildContext context) =>
      SchedulePage(orgId: orgId, deptId: deptId, title: title, openMeetingId: openMeetingId, api: api);
}

/// The schedule body for a given view (kept for older callers and tests): the same page.
class CalendarView extends StatelessWidget {
  const CalendarView({super.key, this.orgId, this.deptId, this.openMeetingId, this.api = const RemoteCalendarApi(), this.initialView});
  final int? orgId, deptId, openMeetingId;
  final CalendarApi api;
  final CalView? initialView;

  @override
  Widget build(BuildContext context) =>
      SchedulePage(orgId: orgId, deptId: deptId, openMeetingId: openMeetingId, api: api, initialView: initialView);
}
