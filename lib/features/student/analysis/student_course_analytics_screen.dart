import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import '../../teacher/analysis/attendance/attendance_model.dart';
import 'attendance/student_attendance_model.dart';
import 'student_analytics_provider.dart';

class StudentCourseAnalyticsScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  const StudentCourseAnalyticsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => StudentCourseAnalyticsProvider(courseId: courseId)
          ..loadAll(),
        child: _CourseAnalyticsView(courseTitle: courseTitle),
      );
}

// ── Inner stateful view ───────────────────────────────────────────────────────

class _CourseAnalyticsView extends StatefulWidget {
  final String courseTitle;
  const _CourseAnalyticsView({required this.courseTitle});

  @override
  State<_CourseAnalyticsView> createState() => _CourseAnalyticsViewState();
}

class _CourseAnalyticsViewState extends State<_CourseAnalyticsView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentCourseAnalyticsProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [_buildAppBar(ctx, prov)],
          body: TabBarView(
            controller: _tab,
            children: [
              _AttendanceTab(prov: prov),
              _ExamsTab(prov: prov),
            ],
          ),
        ),
      ),
    );
  }

  // ── Expanded app bar with hero stats + tabs ──────────────────────────────
  Widget _buildAppBar(
          BuildContext ctx, StudentCourseAnalyticsProvider prov) =>
      SliverAppBar(
        expandedHeight: 210,
        pinned: true,
        backgroundColor: context.colors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward_ios,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(ctx),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: prov.loadAll,
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration:  BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF1565C0), context.colors.primary],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.courseTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  const Text('سجل حضورك ونتائجك',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  // Hero stats row
                  Row(children: [
                    _HeroStat(
                      value: '${prov.attendanceRate.toStringAsFixed(0)}%',
                      label: 'نسبة الحضور',
                      icon: Icons.check_circle_rounded,
                      color: Colors.greenAccent,
                    ),
                    _HeroStat(
                      value: '${prov.passedCount}/${prov.attemptedCount}',
                      label: 'اجتاز',
                      icon: Icons.emoji_events_rounded,
                      color: Colors.amberAccent,
                    ),
                    _HeroStat(
                      value: '${prov.avgScore.toStringAsFixed(0)}%',
                      label: 'متوسط الدرجات',
                      icon: Icons.bar_chart_rounded,
                      color: Colors.lightBlueAccent,
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.fact_check_rounded, size: 18), text: 'الحضور'),
            Tab(icon: Icon(Icons.quiz_rounded, size: 18), text: 'الاختبارات'),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1 — Attendance
// ══════════════════════════════════════════════════════════════════════════════

class _AttendanceTab extends StatelessWidget {
  final StudentCourseAnalyticsProvider prov;
  const _AttendanceTab({required this.prov});

  @override
  Widget build(BuildContext context) {
    if (prov.loadingAtt) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.attError != null) {
      return _ErrorRetry(message: prov.attError!, onRetry: prov.loadAttendance);
    }
    if (prov.attendance.isEmpty) {
      return const Center(
        child: Text('لا توجد محاضرات بعد',
            style:
                TextStyle(fontFamily: 'Cairo', fontSize: 15, color: Colors.grey)),
      );
    }
    return Column(children: [
      // Summary ring card
      _AttendanceSummaryCard(
        present: prov.presentCount,
        total: prov.totalSessions,
        rate: prov.attendanceRate,
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: prov.loadAttendance,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: prov.attendance.length,
            itemBuilder: (_, i) => _AttendanceTile(record: prov.attendance[i]),
          ),
        ),
      ),
    ]);
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  final int present, total;
  final double rate;
  const _AttendanceSummaryCard(
      {required this.present, required this.total, required this.rate});

  Color get _color => rate >= 75
      ? AppTheme.success
      : rate >= 50
          ? Colors.orange
          : Colors.redAccent;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(children: [
          // Ring
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: rate / 100,
                strokeWidth: 8,
                backgroundColor: Colors.grey.shade100,
                color: _color,
              ),
              Text('${rate.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _color)),
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('إجمالي الحضور',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              _BarRow('حضر', present, total, context.colors.success),
              const SizedBox(height: 6),
              _BarRow('غاب', total - present, total, Colors.redAccent),
            ]),
          ),
        ]),
      );
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value, total;
  final Color color;
  const _BarRow(this.label, this.value, this.total, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
            width: 36,
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : value / total,
              backgroundColor: color.withValues(alpha: 0.1),
              color: color,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$value',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color)),
      ]);
}

class _AttendanceTile extends StatelessWidget {
  final FullAttendance record;
  const _AttendanceTile({required this.record});

  @override
  Widget build(BuildContext context) {

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: record.attendance.first.isPresent
              ? context.colors.success.withValues(alpha: 0.3)
              : Colors.redAccent.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: record.attendance.first.isPresent
                ? context.colors.success.withValues(alpha: 0.1)
                : Colors.redAccent.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            record.attendance.first.isPresent
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: record.attendance.first.isPresent ? context.colors.success : Colors.redAccent,
            size: 24,
          ),
        ),
        title: Text(record.sessions.name,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: record.sessions.scheduledAt != null
            ? Text(_fmtDate(record.sessions.scheduledAt!),
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 12, color: Colors.grey))
            : null,
        trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  record.attendance.first.isPresent ? 'حاضر' : 'غائب',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: record.attendance.first.isPresent
                          ? context.colors.success
                          : Colors.redAccent)),
              if (record.attendance.first.duration != null)
                Text('${record.attendance.first.duration} دقيقة',
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
            ]),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${_weekday(d.weekday)}  ${d.day}/${d.month}/${d.year}';
  String _weekday(int w) => const [
        '',
        'الإثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد'
      ][w];
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2 — Exams
// ══════════════════════════════════════════════════════════════════════════════

class _ExamsTab extends StatelessWidget {
  final StudentCourseAnalyticsProvider prov;
  const _ExamsTab({required this.prov});

  @override
  Widget build(BuildContext context) {
    if (prov.loadingExams) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.examsError != null) {
      return _ErrorRetry(message: prov.examsError!, onRetry: prov.loadExams);
    }
    if (prov.exams.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('لا توجد اختبارات حتى الآن',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 15, color: Colors.grey)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: prov.loadExams,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: prov.exams.length,
        itemBuilder: (_, i) => _ExamTile(exam: prov.exams[i]),
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  final StudentExamSummary exam;
  const _ExamTile({required this.exam});

  Color get _color => exam.passed == true
      ? AppTheme.success
      : exam.passed == false
          ? Colors.redAccent
          : Colors.blueGrey;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(children: [
          // Header strip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(Icons.quiz_rounded, color: _color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(exam.examName,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w700))),
              _Badge(exam.statusLabel, _color),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(children: [
              Row(children: [
                _InfoChip(Icons.timer_outlined,
                    '${exam.duration ?? 0} دقيقة', Colors.teal),
                if (exam.startDate != null) ...[
                  const SizedBox(width: 12),
                  _InfoChip(Icons.calendar_today_outlined,
                      _fmtDate(exam.startDate!), Colors.orange),
                ],
              ]),
              if (exam.attempted && exam.percentage != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'درجتي: ${exam.marksObtained?.toStringAsFixed(0)} / ${exam.totalMarks?.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.grey)),
                    Text('${exam.percentage!.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _color)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: exam.percentage! / 100,
                    backgroundColor: Colors.grey.shade100,
                    color: _color,
                    minHeight: 8,
                  ),
                ),
              ],
            ]),
          ),
        ]),
      );

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _HeroStat(
      {required this.value,
      required this.label,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo')),
          Text(label,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 10, fontFamily: 'Cairo')),
        ]),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: Colors.grey)),
      ]);
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
      );
}
