import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../models.dart';
import '../course_detail_provider.dart';
import 'about.dart';
import 'session.dart'; // uses the SessionsTab defined above

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
        CourseDetailTab.live => const AboutTab(key: ValueKey('live')),
        CourseDetailTab.lessons => const SessionsTab(key: ValueKey('sessions'))
      },
    );
  }
}