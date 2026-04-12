import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/dashboard/component/student_home_tab.dart';
import 'package:flutter_education_app/features/student/dashboard/component/student_schedule_tab.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import '../../../config/app_config.dart' as Helpers;
import '../courses/my_courses/my_courses_screen.dart';
import '../../notification/notifications_provider.dart';
import '../profile/profile_screen.dart';
import 'component/student_exam_tab.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {});
    super.initState();
  }

  int _currentIndex = 0;

  // 5 tabs: Home | MyCourses | Schedule | MyExams | Profile
  static const List<Widget> _screens = [
    StudentHomeTab(),
    MyCoursesScreen(),
    StudentScheduleTab(),
    StudentExamsTab(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: Helpers.pageDirection,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: _NavBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i)),
        ),
      );
}

class _NavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;
    return Container(
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
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded, size: 26), label: 'الرئيسية'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_rounded, size: 26), label: 'كورساتي'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded, size: 26),
              label: 'جدولي'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.quiz_rounded, size: 26), label: 'اختباراتي'),
          BottomNavigationBarItem(
              label: 'حسابي',
              icon: Stack(clipBehavior: Clip.none, children: [
                const Icon(Icons.person_rounded, size: 26),
                if (unread > 0)
                  Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                              color: AppTheme.danger, shape: BoxShape.circle),
                          child: Center(
                              child: Text('$unread',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800))))),
              ])),
        ],
      ),
    );
  }
}

// ── Student Schedule Tab ──────────────────────────────────────────────────────

// ── Student Exam Tab ──────────────────────────────────────────────────────
