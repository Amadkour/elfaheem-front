import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:provider/provider.dart';

import '../course_detail_provider.dart';
import '../course_detail_screen.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _s = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CourseDetailProvider>().course;
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(children: [
          ScaleTransition(
              scale: _s,
              child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200, width: 2)),
                  child: const Icon(Icons.radio_button_checked_rounded,
                      color: Colors.redAccent, size: 48))),
          const SizedBox(height: 16),
          const Text('الحصة المباشرة',
              style: AppTheme.h2, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text('انضم إلى الفصل المباشر. سيتم توجيهك خارج التطبيق.',
              style: AppTheme.body, textAlign: TextAlign.center),
          if (c.schedules.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHdr(title: 'مواعيد الحصص الأسبوعية'),
            const SizedBox(height: 12),
            ...c.schedules.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ScheduleChip(schedule: s)))
          ],
          const SizedBox(height: 20),
          GestureDetector(
              onTap: () {},
              child: Text('انضم الآن',
                  style: AppTheme.label.copyWith(
                      color: AppTheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppTheme.primary,
                      fontSize: 16))),
        ]));
  }
}
