import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../shared/attendance_provider.dart';
import '../shared/live_models.dart';

class TeacherAttendanceScreen extends StatefulWidget {
  final int sessionId;
  final int courseId;
  final String sessionName;

  const TeacherAttendanceScreen({
    super.key,
    required this.sessionId,
    required this.courseId,
    required this.sessionName,
  });

  @override
  State<TeacherAttendanceScreen> createState() =>
      _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceProvider>().fetchList(widget.sessionId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AttendanceProvider>();
    final total = prov.list.length;
    final pct = total > 0 ? (prov.presentCount / total * 100).round() : 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
            child: Column(children: [
          ScreenAppBar(title: 'الحضور — ${widget.sessionName}'),

          // ── Stats strip ──────────────────────────────────────────────────
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                _StatCard('الكل', '$total', context.colors.primary),
                const SizedBox(width: 8),
                _StatCard(
                    'حضر', '${prov.presentCount}', context.colors.success),
                const SizedBox(width: 8),
                _StatCard('غاب', '${prov.absentCount}', context.colors.danger),
                const SizedBox(width: 8),
                _StatCard('النسبة', '$pct%', context.colors.accent),
              ]),
            ),

          // ── Tab strip ────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 40,
            decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius:
                    BorderRadius.circular(context.colors.radiusMedium)),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  borderRadius:
                      BorderRadius.circular(context.colors.radiusMedium)),
              labelColor: Colors.white,
              unselectedLabelColor: context.colors.textMedium,
              labelStyle: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'الكل'),
                Tab(text: 'حضر'),
                Tab(text: 'غاب')
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
              child: prov.listLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(context.colors.primary)))
                  : prov.list.isEmpty
                      ? _EmptyState()
                      : TabBarView(controller: _tabs, children: [
                          _AttendanceList(
                              records: prov.list,
                              sessionId: widget.sessionId,
                              onRefresh: () =>
                                  prov.fetchList(widget.sessionId)),
                          _AttendanceList(
                              records:
                                  prov.list.where((r) => r.isPresent).toList(),
                              sessionId: widget.sessionId,
                              onRefresh: () =>
                                  prov.fetchList(widget.sessionId)),
                          _AttendanceList(
                              records:
                                  prov.list.where((r) => !r.isPresent).toList(),
                              sessionId: widget.sessionId,
                              onRefresh: () =>
                                  prov.fetchList(widget.sessionId)),
                        ])),
        ])),
      ),
    );
  }
}

// ── Attendance list with pull-to-refresh ──────────────────────────────────────

class _AttendanceList extends StatelessWidget {
  final List<AttendanceDetail> records;
  final int sessionId;
  final Future<void> Function() onRefresh;

  const _AttendanceList({
    required this.records,
    required this.sessionId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return _EmptyState();
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _AttendanceCard(record: records[i], sessionId: sessionId),
      ),
    );
  }
}

// ── Attendance card ───────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final AttendanceDetail record;
  final int sessionId;

  const _AttendanceCard({required this.record, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow: context.colors.cardShadow,
        border: record.isPresent
            ? Border.all(color: context.colors.success.withValues(alpha: 0.25))
            : null,
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: record.isPresent
                  ? context.colors.success.withValues(alpha: 0.12)
                  : context.colors.textLight.withValues(alpha: 0.12),
              border: Border.all(
                  color: record.isPresent
                      ? context.colors.success.withValues(alpha: 0.3)
                      : context.colors.divider)),
          child: Icon(Icons.person_rounded,
              color: record.isPresent
                  ? context.colors.success
                  : context.colors.textLight,
              size: 24),
        ),
        const SizedBox(width: 12),

        // Info
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record.studentName,
              style: context.colors.h3.copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          if (record.isPresent)
            Wrap(spacing: 12, runSpacing: 4, children: [
              if (record.checkInDate != null)
                _TimeChip(Icons.login_rounded, 'دخل', record.checkInLabel,
                    context.colors.success),
              if (record.checkOutDate != null)
                _TimeChip(Icons.logout_rounded, 'خرج', record.checkOutLabel,
                    context.colors.danger),
              if (record.durationMinutes != null)
                _TimeChip(
                    Icons.timer_rounded,
                    'المدة',
                    '${record.durationMinutes!.round()} د',
                    context.colors.primary),
            ])
          else
            Text('لم يحضر',
                style: context.colors.caption
                    .copyWith(color: context.colors.danger)),
        ])),

        // Badge + manual check-in
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: (record.isPresent
                      ? context.colors.success
                      : context.colors.danger)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: (record.isPresent
                          ? context.colors.success
                          : context.colors.danger)
                      .withValues(alpha: 0.35)),
            ),
            child: Text(record.isPresent ? 'حضر' : 'غاب',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: record.isPresent
                        ? context.colors.success
                        : context.colors.danger,
                    fontWeight: FontWeight.w700)),
          ),
          // Manual override for absent
          if (!record.isPresent) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _manualCheckIn(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: context.colors.primary.withValues(alpha: 0.35))),
                child: Text('تحضير',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: context.colors.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Future<void> _manualCheckIn(BuildContext context) async {
    final ok = await context
        .read<AttendanceProvider>()
        .manualCheckIn(sessionId, record.studentId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'تم تحضير ${record.studentName} ✓' : 'حدث خطأ',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: ok ? context.colors.success : context.colors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }
}

class _TimeChip extends StatelessWidget {
  final IconData i;
  final String l, v;
  final Color c;

  const _TimeChip(this.i, this.l, this.v, this.c);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 12, color: c),
        const SizedBox(width: 3),
        Text('$l: $v',
            style:
                context.colors.caption.copyWith(color: context.colors.textDark))
      ]);
}

class _StatCard extends StatelessWidget {
  final String l, v;
  final Color c;

  const _StatCard(this.l, this.v, this.c);

  @override
  Widget build(BuildContext context) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(context.colors.radiusMedium),
              border: Border.all(color: c.withValues(alpha: 0.25))),
          child: Column(children: [
            Text(v,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c)),
            Text(l, style: context.colors.caption.copyWith(fontSize: 10)),
          ])));
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.people_outline_rounded,
            size: 64, color: context.colors.textLight),
        const SizedBox(height: 12),
        Text('لا يوجد سجل حضور', style: context.colors.body)
      ]));
}
