import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import 'attendance_model.dart';
import 'teacher_attendance_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────

class TeacherAttendanceScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;
  final int? sessionId;
  const TeacherAttendanceScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    this.sessionId
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
      TeacherAttendanceProvider(courseId: courseId)..loadSessions(sessionId),
      child: _TeacherAttendanceView(courseTitle: courseTitle),
    );
  }
}

// ── Inner view ────────────────────────────────────────────────────────────────

class _TeacherAttendanceView extends StatefulWidget {
  final String courseTitle;
  const _TeacherAttendanceView({required this.courseTitle});

  @override
  State<_TeacherAttendanceView> createState() => _TeacherAttendanceViewState();
}

class _TeacherAttendanceViewState extends State<_TeacherAttendanceView>
    with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late final AnimationController _headerAnim;
  late final Animation<double> _headerFade;

  // Palette
  static const Color _primary = Color(0xFF1565C0);
  static const Color _primaryLight = Color(0xFF42A5F5);
  static const Color _success = Color(0xFF00C853);
  static const Color _danger = Color(0xFFEF5350);
  static const Color _surface = Color(0xFFF8FAFF);
  static const Color _cardBg = Colors.white;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _headerFade =
        CurvedAnimation(parent: _headerAnim, curve: Curves.easeOutCubic);
    _headerAnim.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _headerAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherAttendanceProvider>();
    final isWide = MediaQuery.of(context).size.width > 720;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [_buildSliverHeader(ctx)],
          body: _buildBody(prov, isWide),
        ),
      ),
    );
  }

  // ── Sliver header ─────────────────────────────────────────────────────────
  Widget _buildSliverHeader(BuildContext ctx) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      elevation: 0,
      backgroundColor: _primary,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _GlassButton(
          icon: Icons.arrow_forward_ios_rounded,
          onTap: () => Navigator.pop(ctx),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: FadeTransition(
          opacity: _headerFade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gradient mesh background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D47A1),
                      Color(0xFF1565C0),
                      Color(0xFF1976D2),
                      Color(0xFF42A5F5),
                    ],
                  ),
                ),
              ),
              // Decorative circles
              Positioned(
                top: -30,
                right: -30,
                child: _Circle(size: 160, color: Colors.white.withValues(alpha:.06)),
              ),
              Positioned(
                bottom: 10,
                left: -20,
                child: _Circle(size: 120, color: Colors.white.withValues(alpha:.05)),
              ),
              Positioned(
                top: 40,
                right: 80,
                child: _Circle(size: 60, color: _primaryLight.withValues(alpha:.2)),
              ),
              // Content
              Padding(
                padding:
                const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha:.3), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fact_check_rounded,
                              color: Colors.white, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            'attendance_record'.tr,
                            style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.courseTitle,
                      style: const TextStyle(
                        fontFamily: 'bahji',
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(TeacherAttendanceProvider prov, bool isWide) {
    if (prov.isLoadingSessions) {
      return _buildLoadingState();
    }
    if (prov.hasError && prov.sessions.isEmpty) {
      return _buildError(prov.errorMessage,()async=> prov.loadSessions(null));
    }
    return Column(children: [
      _buildSessionFlagBar(prov),
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
      ] else
        Expanded(child: _buildSelectSessionHint()),
    ]);
  }

  // ── Loading skeleton ──────────────────────────────────────────────────────
  Widget _buildLoadingState() => Expanded(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
              AlwaysStoppedAnimation<Color>(_primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'loading_attendance'.tr,
            style: const TextStyle(
                fontFamily: 'bahji',
                color: Colors.grey,
                fontSize: 14),
          ),
        ],
      ),
    ),
  );

  // ── Select session hint ───────────────────────────────────────────────────
  Widget _buildSelectSessionHint() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _primary.withValues(alpha:.08),
            shape: BoxShape.circle,
          ),
          child:
          Icon(Icons.touch_app_rounded, size: 48, color: _primary.withValues(alpha:.5)),
        ),
        const SizedBox(height: 16),
        Text(
          'select_lecture'.tr,
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        Text(
          'select_session_hint_sub'.tr,
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              color: Colors.grey.shade400),
        ),
      ],
    ),
  );

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError(String? msg, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _danger.withValues(alpha:.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.wifi_off_rounded,
              size: 44, color: _danger.withValues(alpha:.7)),
        ),
        const SizedBox(height: 16),
        Text(
          msg ?? 'something-went-wrong'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'bahji', fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text('retry'.tr,
              style: const TextStyle(fontFamily: 'bahji')),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      ]),
    ),
  );

  // ── Session flag bar ──────────────────────────────────────────────────────
  Widget _buildSessionFlagBar(TeacherAttendanceProvider prov) {
    return Container(
      color: _cardBg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'select_lecture'.tr,
              style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A237E),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Flags
          SizedBox(
            height: 80,
            child: prov.sessions.isEmpty
                ? Center(
              child: Text(
                'no_sessions_available'.tr,
                style: const TextStyle(
                    fontFamily: 'bahji',
                    color: Colors.grey,
                    fontSize: 13),
              ),
            )
                : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: prov.sessions.length,
              separatorBuilder: (_, __) =>
              const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final s = prov.sessions[i];
                final sel = prov.selectedSession?.id == s.id;
                return _SessionFlag(
                  session: s,
                  index: i,
                  isSelected: sel,
                  onTap: () => prov.selectSession(s),
                  primaryColor: _primary,
                  primaryLight: _primaryLight,
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Divider(
              color: Colors.grey.shade100, thickness: 1.5, height: 1),
        ],
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────
  Widget _buildStats(TeacherAttendanceProvider prov) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
        _PremiumStatCard(
          label: 'total_students'.tr,
          value: '${prov.allStudents.length}',
          icon: Icons.people_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
          ),
        ),
        const SizedBox(width: 10),
        _PremiumStatCard(
          label: 'present'.tr,
          value: '${prov.presentCount}',
          icon: Icons.check_circle_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF00897B), Color(0xFF00C853)],
          ),
        ),
        const SizedBox(width: 10),
        _PremiumStatCard(
          label:'absent'.tr,
          value: '${prov.absentCount}',
          icon: Icons.cancel_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
          ),
        ),
      ]),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────
  Widget _buildSearchBar(TeacherAttendanceProvider prov) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        textDirection: TextDirection.rtl,
        style:
        const TextStyle(fontFamily: 'bahji', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'search_student'.tr,
          hintStyle: TextStyle(
              fontFamily: 'bahji',
              color: Colors.grey.shade400,
              fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded,
              color: Colors.grey.shade400, size: 20),
          suffixIcon: prov.search.isNotEmpty
              ? IconButton(
              icon: Icon(Icons.close_rounded,
                  color: Colors.grey.shade400, size: 18),
              onPressed: () {
                _searchCtrl.clear();
                prov.setSearch('');
              })
              : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
        onChanged: prov.setSearch,
      ),
    ),
  );

  // ── Lists ─────────────────────────────────────────────────────────────────
  Widget _buildList(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    if (list.isEmpty) {
      return Center(
        child: Text('no_search_results'.tr,
            style: const TextStyle(
                fontFamily: 'bahji', color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: list.length,
      itemBuilder: (_, i) => _PremiumStudentTile(
        student: list[i],
        onToggle: (v) => prov.toggleStudent(list[i].id, v),
        presentLabel: 'present'.tr,
        absentLabel: 'absent'.tr,
        durationLabel: 'attendance_duration'.tr,
        minutesLabel: 'minutes'.tr,
        successColor: _success,
        dangerColor: _danger,
      ),
    );
  }

  Widget _buildWideGrid(TeacherAttendanceProvider prov) {
    final list = prov.filtered;
    return LayoutBuilder(
      builder: (_, c) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: c.maxWidth > 1100 ? 3 : 2,
          childAspectRatio: 3.4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _PremiumStudentTile(
          student: list[i],
          onToggle: (v) => prov.toggleStudent(list[i].id, v),
          presentLabel: 'present'.tr,
          absentLabel: 'absent'.tr,
          durationLabel: 'attendance_duration'.tr,
          minutesLabel: 'minutes'.tr,
          successColor: _success,
          dangerColor: _danger,
          compact: false,
        ),
      ),
    );
  }

  // ── Save bar ──────────────────────────────────────────────────────────────
  Widget _buildSaveBar(TeacherAttendanceProvider prov) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Row(children: [
        // Save button
        Expanded(
          flex: 3,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton.icon(
              onPressed: prov.saving || prov.changes.isEmpty
                  ? null
                  : () async {
                final ok =
                await prov.saveAttendance(prov.changes);
                prov.clearChanges();
                if (!context.mounted) return;
                _showSnack(
                  ok
                      ? 'attendance_saved'.tr
                      : 'save_failed'.tr,
                  ok ? _success : _danger,
                );
              },
              icon: prov.saving
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded,
                  color: Colors.white, size: 18),
              label: Text(
                prov.saving
                    ? 'saving'.tr
                    : 'save_attendance'.tr,
                style: const TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _success,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // All present
        _QuickActionBtn(
          label: 'mark_all_present'.tr,
          color: _success,
          icon: Icons.done_all_rounded,
          onTap: () async {
            final ok = await prov.markAll(true);
            if (!context.mounted) return;
            _showSnack(
              ok
                  ? 'attendance_saved'.tr
                  : 'save_failed'.tr,
              ok ? _success : _danger,
            );
          },
        ),
        const SizedBox(width: 8),
        // All absent
        _QuickActionBtn(
          label: 'mark_all_absent'.tr,
          color: _danger,
          icon: Icons.remove_done_rounded,
          onTap: () => prov.markAll(false),
        ),
      ]),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'bahji')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable premium widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Decorative circle for header
class _Circle extends StatelessWidget {
  final double size;
  final Color color;
  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
    ),
  );
}

/// Glass icon button for app bar
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withValues(alpha:.3), width: 1),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    ),
  );
}

/// Flag-style session chip (vertical card with number + name)
class _SessionFlag extends StatelessWidget {
  final dynamic session; // AttendanceSession
  final int index;
  final bool isSelected;
  final VoidCallback onTap;
  final Color primaryColor;
  final Color primaryLight;

  const _SessionFlag({
    required this.session,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.primaryColor,
    required this.primaryLight,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 90,
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryColor, primaryLight],
          )
              : null,
          color: isSelected ? null : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.grey.shade200,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: primaryColor.withValues(alpha:.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Number badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha:.25)
                    : primaryColor.withValues(alpha:.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                session.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                  isSelected ? Colors.white : Colors.grey.shade700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient stat card
class _PremiumStatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final LinearGradient gradient;

  const _PremiumStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:
            gradient.colors.first.withValues(alpha:.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                color: Colors.white, size: 14),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'bahji',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 10,
              color: Colors.white.withValues(alpha:.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Premium student list tile
class _PremiumStudentTile extends StatelessWidget {
  final AttendanceStudent student;
  final ValueChanged<bool> onToggle;
  final String presentLabel, absentLabel, durationLabel, minutesLabel;
  final Color successColor, dangerColor;
  final bool compact;

  const _PremiumStudentTile({
    required this.student,
    required this.onToggle,
    required this.presentLabel,
    required this.absentLabel,
    required this.durationLabel,
    required this.minutesLabel,
    required this.successColor,
    required this.dangerColor,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final present = student.isPresent;
    final statusColor = present ? successColor : dangerColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      margin: compact
          ? const EdgeInsets.only(bottom: 10)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: statusColor.withValues(alpha:.2), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:.04),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: statusColor.withValues(alpha:.1),
              backgroundImage: student.imageUrl != null
                  ? NetworkImage(student.imageUrl!)
                  : null,
              child: student.imageUrl == null
                  ? Text(
                student.name[0],
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: statusColor,
                ),
              )
                  : null,
            ),
            Positioned(
              bottom: -2,
              left: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          student.name,
          style: const TextStyle(
            fontFamily: 'bahji',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: student.durationMinutes != null
            ? Text(
          '$durationLabel: ${student.durationMinutes} $minutesLabel',
          style: const TextStyle(
              fontFamily: 'bahji',
              fontSize: 12,
              color: Colors.grey),
        )
            : Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha:.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                present ? presentLabel : absentLabel,
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        trailing: Transform.scale(
          scale: 0.9,
          child: Switch.adaptive(
            value: present,
            activeColor: successColor,
            inactiveThumbColor: dangerColor,
            onChanged: onToggle,
          ),
        ),
      ),
    );
  }
}

/// Quick action button (All Present / All Absent)
class _QuickActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha:.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha:.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}