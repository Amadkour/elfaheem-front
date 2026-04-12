import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/features/student/courses/details/components/session.dart';
import 'package:provider/provider.dart';

import '../../../models.dart';
import '../course_detail_provider.dart';
import 'about.dart';
import 'live.dart';

class TabContent extends StatelessWidget {
  const TabContent({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = context.watch<CourseDetailProvider>().activeTab;
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: switch (tab) {
          CourseDetailTab.about => const AboutTab(key: ValueKey('about')),
          CourseDetailTab.live => const LiveTab(key: ValueKey('live')),
          CourseDetailTab.lessons =>
            const SessionsTab(key: ValueKey('sessions'))
        });
  }
}
