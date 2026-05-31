// components/course_details_section.dart
//
// Expandable detail cards: schedule · prerequisites · tools · certificates.
// Purely presentational — receives a [TeacherCourse] and renders itself.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../../../config/app_theme.dart';
import '../../../../config/app_config.dart';
import '../../home/teacher_models.dart';

class CourseDetailsSection extends StatelessWidget {
  final TeacherCourse course;

  const CourseDetailsSection({super.key, required this.course});

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
          // ── Section label ──────────────────────────────────────────────
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

          // ── Cards ──────────────────────────────────────────────────────
          if (course.schedules.isNotEmpty)
            DetailCard(
              expanded: false,
              icon: Icons.calendar_month_rounded,
              title: 'weekly_schedule'.tr,
              color: const Color(0xFF4DA6FF),
              children: course.schedules
                  .map((s) => _ScheduleRow(schedule: s))
                  .toList(),
            ),

          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            DetailCard(
              expanded: false,
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
            DetailCard(
              expanded: false,
              icon: Icons.build_rounded,
              title: 'required_tools'.tr,
              color: const Color(0xFF1DB954),
              children: course.tools
                  .map((t) => _BulletRow(text: t.name))
                  .toList(),
            ),
          ],

          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            DetailCard(
              expanded: false,
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
// Expandable card
// ─────────────────────────────────────────────────────────────────────────────

class DetailCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;
  final bool expanded;

  const DetailCard({super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
    required this.expanded,
  });

  @override
  State<DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<DetailCard>
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
    print("----------------->${widget.expanded}");
    if (widget.expanded) {
      _expanded = true;
      _ctrl.forward();
    } else {
      _expanded = false;
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
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
          // ── Header row ─────────────────────────────────────────────────
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
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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

          // ── Expandable body ────────────────────────────────────────────
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
                        .map(
                          (child) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: child,
                          ),
                        )
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
// Row sub-widgets
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
        Icon(
          Icons.access_time_rounded,
          size: 13,
          color: context.colors.textMedium,
        ),
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
