import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../shared/session/session_material_widget.dart';
import '../../student/models.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/sessions/components/session_form_sheet.dart';
import '../../teacher/sessions/sessions_provider.dart';
import '../home/teacher_provider.dart';

class TeacherSessionsScreen extends StatefulWidget {
  final TeacherCourse course;

  const TeacherSessionsScreen({super.key, required this.course});

  @override
  State<TeacherSessionsScreen> createState() => _TeacherSessionsScreenState();
}

class _TeacherSessionsScreenState extends State<TeacherSessionsScreen> {
  late TeacherCourse _course;

  @override
  void initState() {
    super.initState();
    _course = widget.course;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherSessionsProvider>().fetchSessions(widget.course.id);
      _refreshCourse();
    });
  }

  Future<void> _refreshCourse() async {
    final updated =
        await context.read<TeacherProvider>().fetchCourseById(widget.course.id);
    if (updated != null && mounted) {
      if(mounted) setState(() => _course = updated);
    }
  }

  void _openAddSheet() => _openSheet(context);

  void _openSheet(BuildContext ctx, {TeacherSessionItem? existing}) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: ctx.read<TeacherSessionsProvider>(),
        child: SessionFormSheet(existing: existing, courseId: _course.id),
      ),
    );
  }

  Future<void> _openEditCourse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseFormScreen(course: _course)),
    );
    _refreshCourse();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      child: SafeArea(
          child: _SessionsList(
            course: _course,
            onAdd: _openAddSheet,
            onEditCourse: _openEditCourse,
            onRefreshCourse: _refreshCourse,
          ),
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main scrollable body
// ─────────────────────────────────────────────────────────────────────────────

class _SessionsList extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onAdd;
  final VoidCallback onEditCourse;
  final Future<void> Function() onRefreshCourse;

  const _SessionsList({
    required this.course,
    required this.onAdd,
    required this.onEditCourse,
    required this.onRefreshCourse,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();

    return RefreshIndicator(
      color: context.colors.primary,
      backgroundColor: context.colors.surface,
      onRefresh: () async {
        await Future.wait([
          provider.fetchSessions(course.id),
          onRefreshCourse(),
        ]);
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _CourseHero(
              course: course,
              onBack: () => Navigator.maybePop(context),
              onEditCourse: onEditCourse,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:  const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: RatingWidget(
                type: RateType.course,
                sourceId: course.id.toString(),
                canEdit: false,
                compact: false,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _StatsRow(
              course: course,
              sessionCount: provider.sessions.length,
            ),
          ),
          SliverToBoxAdapter(
            child: _CourseDetailsSection(course: course),
          ),
          SliverToBoxAdapter(
            child: _SectionHeader(onAdd: onAdd),
          ),
          if (provider.isLoading && provider.sessions.isEmpty)
            const SliverFillRemaining(child: _LoadingState()),
          if (!provider.isLoading && provider.sessions.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(
                onAdd: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => ChangeNotifierProvider.value(
                    value: context.read<TeacherSessionsProvider>(),
                    child: SessionFormSheet(courseId: course.id),
                  ),
                ),
              ),
            ),
          if (provider.sessions.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverList.builder(
                itemCount: provider.sessions.length,
                itemBuilder: (_, i) => SessionMaterialCard(
                  session: provider.sessions[i],
                  course: course,
                  isTeacher: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Course Details Section
// ─────────────────────────────────────────────────────────────────────────────

class _CourseDetailsSection extends StatelessWidget {
  final TeacherCourse course;

  const _CourseDetailsSection({required this.course});

  bool get _hasAny =>
      course.schedules.isNotEmpty ||
      course.prerequisites.isNotEmpty ||
      course.tools.isNotEmpty ||
      course.certificates.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasAny) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'course_details'.tr,
                style: context.colors.h3.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (course.schedules.isNotEmpty)
            _DetailCard(
              icon: Icons.calendar_month_rounded,
              title: 'weekly_schedule'.tr,
              color: const Color(0xFF4DA6FF),
              children: course.schedules
                  .map((s) => _ScheduleRow(schedule: s))
                  .toList(),
            ),
          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.checklist_rounded,
              title: 'prerequisites'.tr,
              color: const Color(0xFFFF9F43),
              children: course.prerequisites
                  .map((p) => _BulletRow(text: p.title))
                  .toList(),
            ),
          ],
          if (course.tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.build_rounded,
              title: 'required_tools'.tr,
              color: const Color(0xFF1DB954),
              children:
                  course.tools.map((t) => _BulletRow(text: t.name)).toList(),
            ),
          ],
          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.workspace_premium_rounded,
              title: 'certificates'.tr,
              color: const Color(0xFFFFD700),
              children: course.certificates
                  .map((c) => _CertificateRow(cert: c))
                  .toList(),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable detail card
// ─────────────────────────────────────────────────────────────────────────────

class _DetailCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;

  const _DetailCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  State<_DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<_DetailCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if(mounted) setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? widget.color.withValues(alpha: 0.35)
              : context.colors.divider,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _expanded
                ? widget.color.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textDark,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.children.length}',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: widget.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: context.colors.textMedium,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _anim,
            child: Column(
              children: [
                Divider(
                  height: 1,
                  color: widget.color.withValues(alpha: 0.15),
                  indent: 14,
                  endIndent: 14,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  child: Column(
                    children: widget.children
                        .map((child) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: child,
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row widgets for each detail type
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleRow extends StatelessWidget {
  final CourseSchedule schedule;

  const _ScheduleRow({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF4DA6FF).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            schedule.dayLabel,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4DA6FF),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.access_time_rounded,
            size: 13, color: context.colors.textMedium),
        const SizedBox(width: 4),
        Text(
          '${schedule.startTime} – ${schedule.endTime}',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textDark,
          ),
        ),
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  final String text;

  const _BulletRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 6, color: context.colors.textMedium),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: context.colors.textDark,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _CertificateRow extends StatelessWidget {
  final CourseCertificate cert;

  const _CertificateRow({required this.cert});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFD700)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cert.title,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textDark,
                ),
              ),
              if (cert.description != null && cert.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  cert.description!,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    color: context.colors.textMedium,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero banner
// ─────────────────────────────────────────────────────────────────────────────

class _CourseHero extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onBack;
  final VoidCallback onEditCourse;

  const _CourseHero({
    required this.course,
    required this.onBack,
    required this.onEditCourse,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 260,
          width: double.infinity,
          child: _buildBackground(),
        ),
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
              _CircleBtn(
                icon: Icons.edit_rounded,
                onTap: onEditCourse,
                label: 'update'.tr,
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (course.categoryName != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    course.categoryName ?? course.type,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              Text(
                course.title,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (course.description != null &&
                  course.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  course.description!,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.80),
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackground() {
    final imageUrl = course.imageUrl;
    if (imageUrl.isNotEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1F3A), Color(0xFF2D3461)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.25),
                Colors.black.withValues(alpha: 0.75),
              ],
            ),
          ),
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _GradientBackground(),
          ),
        ),
      );
    }
    return _GradientBackground();
  }
}

class _GradientBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1F3A), Color(0xFF2D3461)],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.school_rounded,
            size: 72,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  const _CircleBtn({required this.icon, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label!,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final TeacherCourse course;
  final int sessionCount;

  const _StatsRow({required this.course, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    final stats = <_StatItem>[
      _StatItem(
        icon: Icons.people_alt_rounded,
        label: 'student'.tr,
        value: '${course.studentsCount}',
        color: const Color(0xFF4DA6FF),
      ),
      _StatItem(
        icon: Icons.play_lesson_rounded,
        label: 'sessions'.tr,
        value: '$sessionCount',
        color: context.colors.primary,
      ),
      _StatItem(
        icon: Icons.sell_rounded,
        label: 'cost'.tr,
        value: course.price == 0 ? 'free'.tr : '${course.price} ج',
        color: const Color(0xFF1DB954),
      ),
      _StatItem(
        icon: Icons.timer_rounded,
        label: 'duration'.tr,
        value: '${course.totalHours} ${'h'.tr}',
        color: const Color(0xFFFF9F43),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children:
            stats.map((s) => Expanded(child: _StatChip(item: s))).toList(),
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _StatChip extends StatelessWidget {
  final _StatItem item;

  const _StatChip({required this.item});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.colors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 10,
              color: context.colors.textMedium,
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final VoidCallback onAdd;

  const _SectionHeader({required this.onAdd});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('sessions'.tr,
                  style: context.colors.h3.copyWith(fontSize: 15)),
            ),
            _AddButton(onTap: onAdd),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.colors.primary),
              strokeWidth: 3,
              backgroundColor: context.colors.primaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Text('جاري تحميل الدروس...', style: context.colors.body),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: context.colors.primaryShadow,
              ),
              child: const Icon(Icons.video_library_rounded,
                  size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text('لا توجد دروس بعد',
                style:
                    context.colors.h3.copyWith(color: context.colors.textDark)),
            const SizedBox(height: 8),
            Text('أضف أول درس لتبدأ في تنظيم مواد الكورس',
                style: context.colors.body, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: context.colors.primaryShadow),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('أضف أول درس',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Tajawal',
                          fontSize: 15)),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(10),
            boxShadow: context.colors.primaryShadow,
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text('إضافة درس',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Tajawal',
                    fontSize: 12)),
          ]),
        ),
      );
}
