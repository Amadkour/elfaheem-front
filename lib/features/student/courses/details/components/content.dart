import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../analysis/exam/student_course_exams_widget.dart';
import '../../../models.dart';
import '../course_detail_provider.dart';
import 'about.dart';
import 'session.dart'; // uses the SessionsTab defined above

class TabContent extends StatelessWidget {
  const TabContent({super.key, required this.activeTab, required this.courseId});

  final CourseDetailTab activeTab;
  final String courseId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: switch (activeTab) {
        CourseDetailTab.about => const AboutTab(key: ValueKey('about')),
        CourseDetailTab.live =>  SessionsTab(key: ValueKey('live'),provider:provider,presented:provider.liveSessions),
        CourseDetailTab.lessons =>  SessionsTab(key: ValueKey('sessions'),provider:provider,presented:provider.sessions),
        CourseDetailTab.exam =>  StudentCourseExamsWidget(courseId:courseId ,),
      },
    );
  }
}