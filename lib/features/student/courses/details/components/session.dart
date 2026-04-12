import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:flutter_education_app/features/student/courses/details/components/session_card.dart';
import 'package:provider/provider.dart';

import '../../../../teacher/sessions/components/session_card.dart';
import '../course_detail_provider.dart';

class SessionsTab extends StatelessWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    final sessions = provider.course.sessions;
    if (provider.isLoadingSession) {
      return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.primary))));
    }
    if (sessions.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.video_library_outlined,
                size: 64, color: AppTheme.textLight),
            SizedBox(height: 12),
            Text('لا توجد دروس بعد', style: AppTheme.body)
          ])));
    }
    return Column(children: [
      // Filter hint
      ...List.generate(
          sessions.length,
          (i) => Padding(
            padding: const EdgeInsets.all(8.0),
            child: StudentSessionCard(
                  session: sessions[i],
                  isCheckedIn: false,
                  onCheckIn: () {},
                  onCheckOut: () {},
                ),
          ))
      // ...List.generate( sessions.length,(i) => _SessionTile(session: sessions[i])),
    ]);
  }
}
