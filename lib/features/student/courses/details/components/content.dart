import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../models.dart';
import '../course_detail_provider.dart';
import 'about.dart';
import 'session.dart'; // uses the SessionsTab defined above

class TabContent extends StatelessWidget {
  const TabContent({super.key, required this.activeTab});

  final CourseDetailTab activeTab;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: switch (activeTab) {
        CourseDetailTab.about => const AboutTab(key: ValueKey('about')),
        CourseDetailTab.live => const AboutTab(key: ValueKey('live')),
        CourseDetailTab.lessons => const SessionsTab(key: ValueKey('sessions'))
      },
    );
  }
}