/// teacher_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../student/dashboard/dashboard_screen.dart';
import '../analytics_hub_screen.dart';
import '../courses/courses_screen.dart';
import '../home/home_screen.dart';
import '../home/teacher_provider.dart';
import '../profile/profile_screen.dart';
import '../schedules/schedules_provider.dart';
import '../schedules/schedules_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _State();
}

class _State extends State<TeacherDashboardScreen> {
  int _index = 0;

  @override
  void initState() {
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   await context.read<TeacherProvider>().init();
    // });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: IndexedStack(index: _index, children: const [
          TeacherHomeScreen(),
          TeacherCoursesScreen(),
          _TeacherScheduleTab(), // ← Schedule tab
          AnalyticsHubScreen(), // Attendance & Exams hub
          TeacherProfileScreen(),
        ]),
        bottomNavigationBar: _NavBar(
            currentIndex: _index, onTap: (i) => setState(() => _index = i)),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: AppTheme.cardBg, boxShadow: AppTheme.bottomNavShadow),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.cardBg,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textLight,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded, size: 26), label: 'الرئيسية'),
            BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_rounded, size: 26),
                label: 'كورساتي'),
            BottomNavigationBarItem(
                icon: Icon(Icons.calendar_month_rounded, size: 26),
                label: 'جدولي'),
            BottomNavigationBarItem(
                icon: Icon(Icons.analytics_rounded, size: 26),
                label: 'الحضور والاختبارات'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded, size: 26), label: 'ملفي'),
          ],
        ),
      );
}
class _TeacherScheduleTab extends StatefulWidget {
  const _TeacherScheduleTab();

  @override
  State<_TeacherScheduleTab> createState() => _StudentScheduleTabState();
}

class _StudentScheduleTabState extends State<_TeacherScheduleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TeacherScheduleOverviewProvider _prov = TeacherScheduleOverviewProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await    _prov.fetchOnce();
    });

  }

  @override
  void dispose() {
    _prov.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScheduleTabBody(
      provider: _prov,
      getData: () => _prov.data,
      onRefresh: _prov.fetch,
      title: 'جدولي الأسبوعي',
      emptyMessage: 'لا توجد مواعيد مضافة للكورسات بعد',
      getLastFetched:()=> _prov.lastFetched,
    );
  }
}
