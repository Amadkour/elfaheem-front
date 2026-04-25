// features/teacher/attendance/teacher_attendance_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'attendance_model.dart';
import 'teacher_attendance_provider.dart';

class TeacherAttendanceScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  const TeacherAttendanceScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  // Navigate and inject the provider at the call site — see analytics_hub_screen.dart
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
      TeacherAttendanceProvider(courseId: courseId)..loadSessions(),
      child: _TeacherAttendanceView(courseTitle: courseTitle),
    );
  }
}

// ── Inner stateless view — reads the provider ────────────────────────────────

class _TeacherAttendanceView extends StatefulWidget {
  final String courseTitle;
  const _TeacherAttendanceView({required this.courseTitle});

  @override
  State<_TeacherAttendanceView> createState() => _TeacherAttendanceViewState();
}

class _TeacherAttendanceViewState extends State<_TeacherAttendanceView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherAttendanceProvider>();
    final isWide = MediaQuery.of(context).size.width > 720;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [_buildAppBar(ctx)],
          body: _buildBody(prov, isWide),
        ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext ctx) => SliverAppBar(
    expandedHeight: 140,
    pinned: true,
    backgroundColor: AppTheme.primary,
    leading: IconButton(
      icon: const Icon(Icons.arrow_forward_ios,
          color: Colors.white, size: 20),
      onPressed: () => Navigator.pop(ctx),
    ),
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              AppTheme.primary,
              AppTheme.primary.withValues(alpha: 0.7)
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('سجل الحضور',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo')),
                Text(widget.courseTitle,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // ── Body ────────────────────────────────────────────────────────────────────
  Widget _buildBody(TeacherAttendanceProvider prov, bool isWide) {
    if (prov.isLoadingSessions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.hasError && prov.sessions.isEmpty) {
      return _buildError(prov.errorMessage, prov.loadSessions);
    }
    return Column(children: [
      _buildSessionSelector(prov),
      if (prov.selectedSession != null) ...[
        if (prov.isLoadingStudents)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (prov.hasError)
          Expanded(
              child: _buildError(
                  prov.errorMessage,
                      () => prov.selectSession(prov.selectedSession!)))
        else ...[
            _buildStats(prov),
            _buildSearchBar(prov),
            Expanded(
              child: isWide
                  ? _buildWideGrid(prov)
                  : _buildList(prov),
            ),
            _buildSaveBar(prov),
          ],
      ],
    ]);
  }

  // ── Error state ─────────────────────────────────────────────────────────────
  Widget _buildError(String? msg, VoidCallback retry) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(msg ?? 'حدث خطأ',
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 14, color: Colors.grey)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: retry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('إعادة المحاولة',
            style: TextStyle(fontFamily: 'Cairo')),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ]),
  );

  // ── Session chip bar ────────────────────────────────────────────────────────
  Widget _buildSessionSelector(TeacherAttendanceProvider prov) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('اختر المحاضرة',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SizedBox(
        height: 42,
        child: prov.sessions.isEmpty
            ? const Center(
            child: Text('لا توجد محاضرات',
                style:
                TextStyle(fontFamily: 'Cairo', color: Colors.grey)))
            : ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: prov.sessions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = prov.sessions[i];
            final sel = prov.selectedSession?.id == s.id;
            return GestureDetector(
              onTap: () => prov.selectSession(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.success : Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                      color: sel
                          ? AppTheme.success
                          : Colors.grey.shade300),
                ),
                child: Text(s.name,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : Colors.grey.shade700)),
              ),
            );
          },
        ),
      ),
    ]),
  );

  // ── Stats row ───────────────────────────────────────────────────────────────
  Widget _buildStats(TeacherAttendanceProvider prov) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(children: [
      _StatCard(
          label: 'إجمالي الطلاب',
          value: '${prov.allStudents.length}',
          icon: Icons.people_rounded,
          color: AppTheme.primary),
      const SizedBox(width: 10),
      _StatCard(
          label: 'حاضر',
          value: '${prov.presentCount}',
          icon: Icons.check_circle_rounded,
          color: AppTheme.success),
      const SizedBox(width: 10),
      _StatCard(
          label: 'غائب',
          value: '${prov.absentCount}',
          icon: Icons.cancel_rounded,
          color: Colors.redAccent),
    ]),
  );

  // ── Search bar ──────────────────────────────────────────────────────────────
  Widget _buildSearchBar(TeacherAttendanceProvider prov) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: TextField(
      controller: _searchCtrl,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        hintText: 'ابحث عن طالب...',
        hintStyle:
        const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
        prefixIcon:
        const Icon(Icons.search_rounded, color: Colors.grey),
        suffixIcon: prov.search.isNotEmpty
            ? IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () {
              _searchCtrl.clear();
              prov.setSearch('');
            })
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: prov.setSearch,
    ),
  );

  // ── List / grid ─────────────────────────────────────────────────────────────
  Widget _buildList(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    if (list.isEmpty) {
      return const Center(
        child: Text('لا توجد نتائج',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: list.length,
      itemBuilder: (_, i) => _StudentTile(
        student: list[i],
        onToggle: (v) => prov.toggleStudent(list[i].id, v),
      ),
    );
  }

  Widget _buildWideGrid(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    return LayoutBuilder(
      builder: (_, c) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: c.maxWidth > 1100 ? 3 : 2,
          childAspectRatio: 3.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _StudentTile(
          student: list[i],
          onToggle: (v) => prov.toggleStudent(list[i].id, v),
          compact: false,
        ),
      ),
    );
  }

  // ── Save bar ────────────────────────────────────────────────────────────────
  Widget _buildSaveBar(TeacherAttendanceProvider prov) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    child: Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: prov.saving || prov.changes.isEmpty
              ? null
              : () async {
            final ok = await prov.saveAttendance(prov.changes);
            prov.clearChanges();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  ok ? 'تم حفظ الحضور بنجاح' : 'فشل الحفظ، حاول مرة أخرى',
                  style:
                  const TextStyle(fontFamily: 'Cairo')),
              backgroundColor:
              ok ? AppTheme.success : Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ));
          },
          icon: prov.saving
              ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, color: Colors.white),
          label: Text(
              prov.saving ? 'جارٍ الحفظ...' : 'حفظ الحضور',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor:  AppTheme.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      const SizedBox(width: 12),
      OutlinedButton(
        onPressed: () async {
          final ok = await prov.markAll(true);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                ok ? 'تم حفظ الحضور بنجاح' : 'فشل الحفظ، حاول مرة أخرى',
                style:
                const TextStyle(fontFamily: 'Cairo')),
            backgroundColor:
            ok ? AppTheme.success : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ));
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.success,
          side: BorderSide(color: AppTheme.success),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
        child: const Text('كل حاضر',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: () => prov.markAll(false),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          side: const BorderSide(color: Colors.redAccent),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
        child: const Text('كل غائب',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
      ),
    ]),
  );
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatCard(
      {required this.label,
        required this.value,
        required this.icon,
        required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: Colors.grey)),
        ]),
      ]),
    ),
  );
}

class _StudentTile extends StatelessWidget {
  final AttendanceStudent student;
  final ValueChanged<bool> onToggle;
  final bool compact;

  const _StudentTile(
      {required this.student,
        required this.onToggle,
        this.compact = true});

  @override
  Widget build(BuildContext context) {
    final present = student.isPresent;
    final statusColor =
    present ? AppTheme.success : Colors.redAccent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: compact ? const EdgeInsets.only(bottom: 10) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: statusColor.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: statusColor.withValues(alpha: 0.12),
          backgroundImage: student.imageUrl != null
              ? NetworkImage(student.imageUrl!)
              : null,
          child: student.imageUrl == null
              ? Text(student.name[0],
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  color: statusColor))
              : null,
        ),
        title: Text(student.name,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: student.durationMinutes != null
            ? Text('مدة الحضور: ${student.durationMinutes} دقيقة',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.grey))
            : Text(present ? 'حاضر' : 'غائب',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: statusColor)),
        trailing: Switch.adaptive(
          value: present,
          activeColor: AppTheme.success,
          inactiveThumbColor: Colors.redAccent,
          onChanged: onToggle,
        ),
      ),
    );
  }
}