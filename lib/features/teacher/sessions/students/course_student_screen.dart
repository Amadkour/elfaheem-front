import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/search_text_field.dart';
import '../../../teacher/home/teacher_models.dart';
import 'course_student_provider.dart';

class EnrolledStudentsScreen extends StatefulWidget {
  final TeacherCourse course;

  const EnrolledStudentsScreen({super.key, required this.course});

  @override
  State<EnrolledStudentsScreen> createState() => _EnrolledStudentsScreenState();
}

class _EnrolledStudentsScreenState extends State<EnrolledStudentsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnrolledStudentsProvider>().fetch(widget.course.id);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: Column(
          children: [
            _Header(course: widget.course),
            _StatsBar(),
            MySearchBar(
              controller: _search,
              hint: 'search_student_by_name_email',
              onChanged: context.read<EnrolledStudentsProvider>().setQuery,
            ),
            const Expanded(child: _StudentList()),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final TeacherCourse course;

  const _Header({required this.course});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          bottom: BorderSide(color: context.colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.colors.divider),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 16, color: context.colors.textDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'enrolled_students_title'.tr,
                  style: context.colors.h3.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  course.title,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: context.colors.textMedium,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          _Stat(
            icon: Icons.people_alt_rounded,
            label: 'stat_total'.tr,
            value: '${p.totalCount}',
            color: const Color(0xFF5B8FFF),
          ),
          _Divider(),
          _Stat(
            icon: Icons.trending_up_rounded,
            label: 'stat_avg_progress'.tr,
            value: '${p.avgProgress.toStringAsFixed(0)}%',
            color: const Color(0xFF1DB954),
          ),
          _Divider(),
          _Stat(
            icon: Icons.workspace_premium_rounded,
            label: 'stat_completed'.tr,
            value: '${p.completedCount}',
            color: const Color(0xFFFF9F43),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 0.5,
        height: 36,
        color: context.colors.divider,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.colors.textDark,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 10,
                color: context.colors.textMedium,
              ),
            ),
          ],
        ),
      );
}
// ── List ──────────────────────────────────────────────────────────────────────

class _StudentList extends StatelessWidget {
  const _StudentList();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    if (p.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.colors.primary),
          strokeWidth: 2.5,
        ),
      );
    }

    if (p.students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.divider),
              ),
              child: Icon(Icons.people_outline_rounded,
                  size: 32, color: context.colors.textMedium),
            ),
            const SizedBox(height: 16),
            Text('no_students'.tr, style: context.colors.h3),
            const SizedBox(height: 6),
            Text(
              'no_students_hint'.tr,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                color: context.colors.textMedium,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () async {},
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        itemCount: p.students.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _StudentCard(student: p.students[i]),
      ),
    );
  }
}

// ── Student card ──────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final EnrolledStudent student;

  const _StudentCard({required this.student});

  Color get _progressColor {
    if (student.progressPercentage >= 80) return const Color(0xFF1DB954);
    if (student.progressPercentage >= 40) return const Color(0xFFFF9F43);
    return const Color(0xFF5B8FFF);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          _Avatar(student: student),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        student.name,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${student.progressPercentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _progressColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  student.gmail,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    color: context.colors.textMedium,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: student.progressPercentage / 100,
                    minHeight: 5,
                    backgroundColor: context.colors.divider,
                    valueColor: AlwaysStoppedAnimation(_progressColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${'joined'.tr} ${_formatDate(student.enrolledAt)}',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 10,
                    color: context.colors.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

class _Avatar extends StatelessWidget {
  final EnrolledStudent student;

  const _Avatar({required this.student});

  static const List<Color> _palette = [
    Color(0xFF5B8FFF),
    Color(0xFF1DB954),
    Color(0xFFFF9F43),
    Color(0xFFE84393),
    Color(0xFF9B59B6),
  ];

  Color get _color => _palette[student.id % _palette.length];

  @override
  Widget build(BuildContext context) {
    final url = student.imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials,
        ),
      );
    }
    return _initials;
  }

  Widget get _initials => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            student.initials,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ),
      );
}
