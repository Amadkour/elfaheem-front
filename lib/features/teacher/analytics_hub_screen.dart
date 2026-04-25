// /// teacher/dashboard/analytics_hub_screen.dart
// /// Tab 3 in TeacherDashboardScreen — courses hub for attendance + exams.
// library;
// import 'package:flutter/material.dart';
// import 'package:flutter_education_app/features/teacher/shared/exams_provider.dart';
// import 'package:provider/provider.dart';
// import '../../../../config/app_theme.dart';
// import 'exam/teacher_exam_screen.dart';
// import 'home/teacher_models.dart';
// import 'home/teacher_provider.dart';
//
// class AnalyticsHubScreen extends StatefulWidget {
//   const AnalyticsHubScreen({super.key});
//
//   @override
//   State<AnalyticsHubScreen> createState() => _State();
// }
//
// class _State extends State<AnalyticsHubScreen>
//     with AutomaticKeepAliveClientMixin {
//   @override
//   bool get wantKeepAlive => true;
//
//   @override
//   Widget build(BuildContext context) {
//     super.build(context);
//     final prov = context.watch<TeacherProvider>();
//     return Directionality(
//         textDirection: TextDirection.rtl,
//         child: Scaffold(
//             backgroundColor: AppTheme.background,
//             body: SafeArea(
//                 child: Column(children: [
//               const Padding(
//                   padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
//                   child: Text('الحضور والاختبارات', style: AppTheme.h1)),
//               const Padding(
//                   padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
//                   child: Text('اختر كورساً لعرض الحضور أو إدارة الاختبارات',
//                       style: AppTheme.body)),
//               Expanded(
//                   child: prov.allCourses.isEmpty
//                       ? const Center(
//                           child:
//                               Text('لا توجد كورسات بعد', style: AppTheme.body))
//                       : ListView.separated(
//                           padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
//                           physics: const BouncingScrollPhysics(),
//                           itemCount: prov.allCourses.length,
//                           separatorBuilder: (_, __) =>
//                               const SizedBox(height: 14),
//                           itemBuilder: (_, i) =>
//                               _CourseCard(course: prov.allCourses[i]))),
//             ]))));
//   }
// }
//
// class _CourseCard extends StatelessWidget {
//   final TeacherCourse course;
//
//   const _CourseCard({required this.course});
//
//   @override
//   Widget build(BuildContext ctx) => Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//           color: AppTheme.cardBg,
//           borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
//           boxShadow: AppTheme.cardShadow),
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         Text(course.title,
//             style: AppTheme.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
//         const SizedBox(height: 3),
//         Text('${course.studentsCount} طالب  •  ${course.sessionsCount} محاضرة',
//             style: AppTheme.caption),
//         const SizedBox(height: 12),
//         Row(children: [
//           Expanded(
//               child: _Btn(
//                   Icons.fact_check_rounded,
//                   'الحضور',
//                   AppTheme.success,
//                   () => ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
//                       content: Text('اختر حصة مباشرة من قائمة الدروس',
//                           style: TextStyle(fontFamily: 'Cairo')),
//                       behavior: SnackBarBehavior.floating)))),
//           const SizedBox(width: 10),
//           Expanded(
//               child: _Btn(
//                   Icons.quiz_rounded,
//                   'الاختبارات',
//                   AppTheme.primary,
//                   () => Navigator.push(
//                       ctx,
//                       MaterialPageRoute(
//                           builder: (_) => ChangeNotifierProvider(
//                               create: (_) => ExamsProvider(),
//                               child: TeacherExamScreen(
//                                   courseId: course.id,
//                                   courseTitle: course.title)))))),
//         ])
//       ]));
// }
//
// class _Btn extends StatelessWidget {
//   final IconData i;
//   final String l;
//   final Color c;
//   final VoidCallback t;
//
//   const _Btn(this.i, this.l, this.c, this.t);
//
//   @override
//   Widget build(BuildContext ctx) => GestureDetector(
//       onTap: t,
//       child: Container(
//           padding: const EdgeInsets.symmetric(vertical: 11),
//           decoration: BoxDecoration(
//               color: c.withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(10),
//               border: Border.all(color: c.withValues(alpha: 0.3))),
//           child: Column(children: [
//             Icon(i, color: c, size: 22),
//             const SizedBox(height: 5),
//             Text(l,
//                 style: TextStyle(
//                     fontFamily: 'Cairo',
//                     fontSize: 12,
//                     color: c,
//                     fontWeight: FontWeight.w700))
//           ])));
// }
