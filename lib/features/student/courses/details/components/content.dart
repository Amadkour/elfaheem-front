import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
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
        CourseDetailTab.about => ParentComponent(key: const ValueKey('about'), featureKey: 'course_tabs.about', child: const AboutTab()),
        CourseDetailTab.live => ParentComponent(key: const ValueKey('live'), featureKey: 'live_sessions', child: SessionsTab(provider: provider, presented: provider.liveSessions)),
        CourseDetailTab.lessons => ParentComponent(key: const ValueKey('sessions'), featureKey: 'course_tabs.lessons', child: SessionsTab(provider: provider, presented: provider.sessions)),
        CourseDetailTab.exam => ParentComponent(key: const ValueKey('exam'), featureKey: 'exams', child: StudentCourseExamsWidget(callback: provider.refresh, courseId: provider.course.id)),
      },
    );
  }
}