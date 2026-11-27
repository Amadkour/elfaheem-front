// lib/features/attendance/student_ui/student_attend_page.dart
//
// The student's "حضوري" page of one course: the open attendance (the same window the course entry reads: the server
// online, the stored copy offline, refreshed by the teacher's push), and the student's own record
// (GET /sessions/{course}/course_attendance/me). Pushed with MaterialPageRoute from the subject page.
//
//   Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAttendancePage(courseId: id, courseTitle: …)))
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_api.dart';
import 'package:flutter_education_app/features/attendance/attendance_models.dart';
import 'package:flutter_education_app/features/attendance/attendance_offline_sync.dart';
import 'package:flutter_education_app/features/attendance/attendance_push.dart';
import 'package:flutter_education_app/features/attendance/attendance_store.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_attend_view.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_checkin_view.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

class StudentAttendancePage extends StatefulWidget {
  const StudentAttendancePage({
    super.key,
    required this.courseId,
    this.courseTitle,
    this.kicker,
    this.lessonNow,
    this.teacherName,
    this.api,
  });

  final int courseId;

  /// The course's title (the hero's kicker when [kicker] is null).
  final String? courseTitle;

  /// "الرياضيات، ثاني ثانوي".
  final String? kicker;

  /// The class happening now and its teacher, for the open card's line.
  final String? lessonNow;
  final String? teacherName;
  final StudentAnalyticsApi? api;

  @override
  State<StudentAttendancePage> createState() => _StudentAttendancePageState();
}

class _StudentAttendancePageState extends State<StudentAttendancePage> {
  OpenWindow? _window;
  List<StudentAttendRow> _rows = const [];
  bool _loading = true;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_loadWindow);
    AttendancePush.instance.events.addListener(_onPush);
    _load();
    // the "closes in 8 minutes" line follows the clock, and the card leaves when the window runs out
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_loadWindow);
    AttendancePush.instance.events.removeListener(_onPush);
    _tick?.cancel();
    super.dispose();
  }

  void _onPush() {
    final e = AttendancePush.instance.events.value;
    if (e == null || (e.courseId != null && e.courseId != widget.courseId)) return;
    if (e.closed && mounted) setState(() => _window = null);
    _loadWindow(force: true);
  }

  Future<void> _load() => Future.wait([_loadWindow(), _loadRows()]);

  Future<void> _loadWindow({bool force = false}) async {
    OpenWindow? w;
    try {
      w = AppConnectivity.instance.isOnline
          ? await AttendanceOfflineSync.instance.warm(courseId: widget.courseId, force: force)
          : await AttendanceStore.instance.windowForCourse(widget.courseId);
    } catch (_) {}
    if (mounted) setState(() => _window = (w == null || w.isOver) ? null : w);
  }

  Future<void> _loadRows() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await (widget.api ?? StudentAnalyticsApi()).fetchMyCourseAttendance(widget.courseId);
      if (mounted) setState(() => _rows = studentAttendRows(list));
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? get _minutesLeft {
    final end = _window == null ? null : DateTime.tryParse('${_window!.expiresAt}Z');
    if (end == null) return null;
    final left = end.difference(DateTime.now().toUtc());
    return left.isNegative ? 0 : (left.inSeconds / 60).ceil();
  }

  Future<void> _checkIn() async {
    await showStudentAttendCheckIn(context, courseId: widget.courseId, title: widget.courseTitle);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final w = _window;
    // the web shows the open attendance only when the teacher allowed it for this class
    final showOpen = w != null && !w.isOver && (!kIsWeb || w.allowWeb);
    return BasePage(
      enableFooterWidget: false,
      child: StudentAttendView(
        kicker: widget.kicker ?? widget.courseTitle,
        open: showOpen
            ? StudentAttendOpen(lesson: widget.lessonNow, teacherName: widget.teacherName, minutesLeft: _minutesLeft)
            : null,
        onCheckIn: _checkIn,
        rows: _rows,
        loading: _loading,
        error: _error,
        onRetry: _loadRows,
        onRefresh: _load,
        onBack: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
      ),
    );
  }
}
