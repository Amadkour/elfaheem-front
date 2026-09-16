// course_student_screen.dart
//
// PREMIUM REDESIGN
// ─────────────────────────────────────────────────────────────────────────────
// One bold moment, everything else quiet:
//   • Hero banner (gradient) with the course's *average progress* rendered as
//     a big ring + number — the one thing on this screen worth making bold.
//   • A floating stat card (total / completed) overlaps the hero's bottom
//     edge, tying the two sections together instead of stacking two
//     disconnected boxes.
//   • Each student is a single-row card: a progress *ring* wraps the avatar
//     (replacing the old separate name + progress-bar block), with a compact
//     trailing certificate action instead of a full-width button per card.
//   • Responsive: a plain list on phone widths, a 2–3 column grid once the
//     viewport is wide enough (web / tablet) — same card, no separate
//     "web version" to maintain.
//   • One staggered fade/slide-in on first load; no per-hover motion spam.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<EnrolledStudentsProvider>();
    await provider.fetch(widget.course.id);
    if (!mounted || widget.course.certificates.isEmpty) return;
    await provider.loadIssuedForCertificates(
      widget.course.certificates.map((c) => c.id).toList(),
    );
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
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _HeroHeader(course: widget.course),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: -30,
                      child: const _FloatingStatsCard(),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 46)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: MySearchBar(
                    controller: _search,
                    hint: 'search_student_by_name_email',
                    onChanged: context.read<EnrolledStudentsProvider>().setQuery,
                  ),
                ),
              ),
              _StudentsSliver(course: widget.course),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero — gradient banner with the average-progress ring as the focal number.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final TeacherCourse course;

  const _HeroHeader({required this.course});

  @override
  Widget build(BuildContext context) {
    final avg = context.watch<EnrolledStudentsProvider>().avgProgress;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 46),
      decoration: BoxDecoration(
        gradient: context.colors.primaryGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CircleBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'enrolled_students_title'.tr,
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Center(child: _ProgressRing(value: avg)),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double value; // 0..100

  const _ProgressRing({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 128,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 128,
            height: 128,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value.clamp(0, 100)) / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, animated, __) => CircularProgressIndicator(
                value: animated,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'stat_avg_progress'.tr,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating stats card — overlaps the hero's bottom edge.
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingStatsCard extends StatelessWidget {
  const _FloatingStatsCard();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.people_alt_rounded,
              label: 'stat_total'.tr,
              value: '${p.totalCount}',
              color: const Color(0xFF5B8FFF),
            ),
          ),
          Container(width: 1, height: 34, color: context.colors.divider),
          Expanded(
            child: _StatTile(
              icon: Icons.workspace_premium_rounded,
              label: 'stat_completed'.tr,
              value: '${p.completedCount}',
              color: const Color(0xFFFF9F43),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.colors.textDark,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 10,
                color: context.colors.textMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body — responsive: list on phone widths, grid once there's room (web/tablet).
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsSliver extends StatelessWidget {
  final TeacherCourse course;

  const _StudentsSliver({required this.course});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    if (p.isLoading && p.totalCount == 0) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: AppLoadingIndicator()),
      );
    }

    if (p.students.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(isFiltered: p.totalCount > 0),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1200 ? 3 : (width >= 760 ? 2 : 1);

    if (columns == 1) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        sliver: SliverList.separated(
          itemCount: p.students.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _StaggeredEntrance(
            index: i,
            child: _StudentCard(student: p.students[i], course: course),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 10,
          crossAxisSpacing: 14,
          mainAxisExtent: 106,
        ),
        delegate: SliverChildBuilderDelegate(
              (_, i) => _StaggeredEntrance(
            index: i,
            child: _StudentCard(student: p.students[i], course: course),
          ),
          childCount: p.students.length,
        ),
      ),
    );
  }
}

class _StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 12)) * 35;
    return TweenAnimationBuilder<double>(
      key: ValueKey('entrance-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isFiltered;

  const _EmptyState({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.divider),
              ),
              child: Icon(
                isFiltered ? Icons.search_off_rounded : Icons.people_outline_rounded,
                size: 32,
                color: context.colors.textMedium,
              ),
            ),
            const SizedBox(height: 16),
            Text('no_students'.tr, style: context.colors.h3),
            const SizedBox(height: 6),
            Text(
              'no_students_hint'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 13,
                color: context.colors.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student card — ring-avatar + name/email, compact trailing certificate action.
// ─────────────────────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;

  const _StudentCard({required this.student, required this.course});

  Color get _progressColor {
    if (student.progressPercentage >= 80) return const Color(0xFF1DB954);
    if (student.progressPercentage >= 40) return const Color(0xFFFF9F43);
    return const Color(0xFF5B8FFF);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          _RingAvatar(student: student, color: _progressColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        student.name,
                        style: TextStyle(
                          fontFamily: 'tajawal',
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
                        fontFamily: 'tajawal',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _progressColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  student.gmail,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 11,
                    color: context.colors.textMedium,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${'joined'.tr} ${_formatDate(student.enrolledAt)}',
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 10,
                    color: context.colors.textLight,
                  ),
                ),
              ],
            ),
          ),
          if (course.certificates.isNotEmpty) ...[
            const SizedBox(width: 8),
            _CertificateAction(student: student, course: course),
          ],
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = raw.toLocalSaTime;
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

class _RingAvatar extends StatelessWidget {
  final EnrolledStudent student;
  final Color color;

  const _RingAvatar({required this.student, required this.color});

  static const List<Color> _palette = [
    Color(0xFF5B8FFF),
    Color(0xFF1DB954),
    Color(0xFFFF9F43),
    Color(0xFFE84393),
    Color(0xFF9B59B6),
  ];

  Color get _avatarColor => _palette[student.id % _palette.length];

  @override
  Widget build(BuildContext context) {
    final url = student.imageUrl;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: student.progressPercentage.clamp(0, 100) / 100),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                backgroundColor: context.colors.divider,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: ClipOval(
              child: (url != null && url.isNotEmpty)
                  ? Image.network(
                url,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initials,
              )
                  : _initials,
            ),
          ),
        ],
      ),
    );
  }

  Widget get _initials => Container(
    width: 42,
    height: 42,
    color: _avatarColor.withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: Text(
      student.initials,
      style: TextStyle(
        fontFamily: 'tajawal',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _avatarColor,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact certificate action — send / sending / sent, with a picker when the
// course has more than one certificate.
// ─────────────────────────────────────────────────────────────────────────────

class _CertificateAction extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;

  const _CertificateAction({required this.student, required this.course});

  Future<void> _handleTap(BuildContext context) async {
    final provider = context.read<EnrolledStudentsProvider>();
    final certs = course.certificates;

    CourseCertificate? target;
    if (certs.length == 1) {
      target = certs.first;
    } else {
      target = await showModalBottomSheet<CourseCertificate>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _CertificatePickerSheet(certificates: certs),
      );
    }
    if (target == null || !context.mounted) return;

    final success = await provider.sendCertificate(target.id, student.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'certificate_sent_success'.tr : 'certificate_send_failed'.tr,
          style: const TextStyle(fontFamily: 'bahji', color: Colors.white),
        ),
        backgroundColor: success ? context.colors.success : context.colors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EnrolledStudentsProvider>();
    final singleCert = course.certificates.length == 1 ? course.certificates.first : null;
    final isSending = singleCert != null &&
        provider.isSendingCertificate(singleCert.id, student.id);
    final isSent = singleCert != null &&
        provider.isCertificateIssued(singleCert.id, student.id);

    if (isSending) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: AppLoadingIndicator(),
        ),
      );
    }

    return Tooltip(
      message: isSent ? 'certificate_sent_label'.tr : 'send_certificate_btn'.tr,
      child: GestureDetector(
        onTap: isSent ? null : () => _handleTap(context),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isSent
                ? context.colors.success.withValues(alpha: 0.12)
                : const Color(0xFFFFD700).withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSent ? Icons.check_circle_rounded : Icons.workspace_premium_rounded,
            size: 16,
            color: isSent ? context.colors.success : const Color(0xFFB8860B),
          ),
        ),
      ),
    );
  }
}

class _CertificatePickerSheet extends StatelessWidget {
  final List<CourseCertificate> certificates;

  const _CertificatePickerSheet({required this.certificates});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'choose_certificate_title'.tr,
              style: context.colors.h3.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
            ...certificates.map(
                  (c) => Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700)),
                  title: Text(c.title, style: const TextStyle(fontFamily: 'tajawal', fontSize: 13)),
                  onTap: () => Navigator.pop(context, c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}