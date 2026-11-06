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
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/search_text_field.dart';
import '../../../teacher/home/teacher_models.dart';
import 'course_student_provider.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_username.dart';

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

  bool _onScrollNotification(ScrollNotification n) {
    // Fire loadMore a little before the true end, so the next page is
    // already in flight by the time the user reaches the bottom.
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
      context.read<EnrolledStudentsProvider>().loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: AppRefresh(
          onRefresh: _load,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _SendToAllButton(course: widget.course),
                  ),
                ),
                _StudentsSliver(course: widget.course, onRetry: _load),
              ],
            ),
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
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'enrolled_students_title'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.colors.onHero,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (AppConfig.lang=='ar'? course.titleAr:course.titleEn)??'',

                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 12,
                        color: context.colors.onHero.withValues(alpha: 0.78),
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
              builder: (_, animated, _) => CircularProgressIndicator(
                value: animated,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                backgroundColor: context.colors.onHero.withValues(alpha: 0.22),
                valueColor: AlwaysStoppedAnimation(context.colors.onHero),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: context.colors.onHero,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'stat_avg_progress'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colors.onHero.withValues(alpha: 0.85),
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: context.colors.onHero.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.onHero.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, size: 16, color: context.colors.onHero, semanticLabel: MaterialLocalizations.of(context).backButtonTooltip),
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
            color: context.colors.heroShade.withValues(alpha: 0.10),
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
              color: context.colors.primaryLight,
            ),
          ),
          Container(width: 1, height: 34, color: context.colors.divider),
          Expanded(
            child: _StatTile(
              icon: Icons.workspace_premium_rounded,
              label: 'stat_completed'.tr,
              value: '${p.completedCount}',
              color: context.colors.warning,
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
                fontFamily: AppFonts.family,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.colors.textDark,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.family,
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
  final VoidCallback onRetry;

  const _StudentsSliver({required this.course, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    if (p.isLoading && p.students.isEmpty) {
      return const SliverToBoxAdapter(child: AppListSkeleton());
    }

    // A failed first load used to show "no students yet": say it failed and offer a retry.
    if (p.students.isEmpty && p.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorRetry(message: p.errorMessage ?? 'failed_to_load'.tr, onRetry: onRetry),
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
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverList.separated(
              itemCount: p.students.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _StaggeredEntrance(
                index: i,
                child: _StudentCard(student: p.students[i], course: course),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            SliverToBoxAdapter(child: _LoadMoreFooter(provider: p)),
          ],
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverGrid(
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
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          SliverToBoxAdapter(child: _LoadMoreFooter(provider: p)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small footer under the list — a spinner while the next page loads, or a
// quiet "you've reached the end" once the server has nothing more to give.
// ─────────────────────────────────────────────────────────────────────────────

class _LoadMoreFooter extends StatelessWidget {
  final EnrolledStudentsProvider provider;

  const _LoadMoreFooter({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: AppLoadingIndicator()),
        ),
      );
    }
    if (!provider.hasMore && provider.students.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'end_of_list'.tr,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 11,
              color: context.colors.textLight,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
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
                fontFamily: AppFonts.family,
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

  Color _progressColor(BuildContext context) {
    if (student.progressPercentage >= 80) return context.colors.success;
    if (student.progressPercentage >= 40) return context.colors.warning;
    return context.colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showStudentDialog(context, student, course, _progressColor(context)),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              _RingAvatar(student: student, color: _progressColor(context)),
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
                              fontFamily: AppFonts.family,
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
                            fontFamily: AppFonts.family,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _progressColor(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (student.username != null) AppUsernameLine(student.username, fontSize: 11),
                    Text(
                      student.gmail,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
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
                        fontFamily: AppFonts.family,
                        fontSize: 10,
                        color: context.colors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CertificateAction(student: student, course: course),
            ],
          ),
        ),
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

  // One stable colour per student, from the theme's roles.
  Color _avatarColor(BuildContext context) {
    final c = context.colors;
    final palette = [c.primary, c.success, c.warning, c.accent2, c.purple];
    return palette[student.id % palette.length];
  }

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
            builder: (_, v, _) => SizedBox(
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
                errorBuilder: (_, _, _) => _initials(context),
              )
                  : _initials(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials(BuildContext context) => Container(
    width: 42,
    height: 42,
    color: _avatarColor(context).withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: Text(
      student.initials,
      style: TextStyle(
        fontFamily: AppFonts.family,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _avatarColor(context),
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
    final target = await _pickCertificate(context, course.certificates);
    if (target == null || !context.mounted) return;

    final success = await provider.sendCertificate(target.id, student.id);
    if (!context.mounted) return;
    _showResultSnack(context, success, 'certificate_sent_success'.tr);
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

    // Always visible, labeled button. After a send it turns green and reads
    // "Resend", but stays tappable so the certificate can go out again.
    final color = isSent ? context.colors.success : context.colors.accent2;
    return GestureDetector(
      onTap: provider.isBulkSending ? null : () => _handleTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSent ? Icons.replay_rounded : Icons.send_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              isSent ? 'resend_certificate_btn'.tr : 'send_btn'.tr,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
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
                  leading: Icon(Icons.workspace_premium_rounded, color: context.colors.accent2),
                  title: Text(c.title, style: TextStyle(fontFamily: AppFonts.family, fontSize: 13)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the only certificate directly, or lets the teacher pick one.
Future<CourseCertificate?> _pickCertificate(
    BuildContext context, List<CourseCertificate> certs) async {
  if (certs.isEmpty) {
    showAppNotice('no_certificate_for_course'.tr, error: true);
    return null;
  }
  if (certs.length == 1) return certs.first;
  return showModalBottomSheet<CourseCertificate>(
      useSafeArea: true,
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _CertificatePickerSheet(certificates: certs),
  );
}

void _showResultSnack(BuildContext context, bool success, String okMessage) {
  showAppNotice(success ? okMessage : 'certificate_send_failed'.tr, error: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// "Send certificate to all students" — one click, with a confirmation step.
// ─────────────────────────────────────────────────────────────────────────────

class _SendToAllButton extends StatelessWidget {
  final TeacherCourse course;

  const _SendToAllButton({required this.course});

  Future<void> _onTap(BuildContext context) async {
    final provider = context.read<EnrolledStudentsProvider>();

    final cert = await _pickCertificate(context, course.certificates);
    if (cert == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('send_to_all_title'.tr,
            style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
        content: Text(
          '${'send_to_all_confirm'.tr}\n\n${cert.title} · ${provider.totalCount} ${'students'.tr}',
          style: TextStyle(fontFamily: AppFonts.family, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('cancel'.tr)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('send_btn'.tr)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final sent = await provider.sendCertificateToAll(cert.id);
    if (!context.mounted) return;
    _showResultSnack(context, sent >= 0, '${'send_to_all_success'.tr} ($sent)');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();
    final busy = p.isBulkSending;
    final gold = context.colors.accent2;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: (busy || p.totalCount == 0) ? null : () => _onTap(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: BorderSide(color: gold.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: AppLoadingIndicator())
            : const Icon(Icons.send_rounded, size: 18),
        label: Text(
          busy ? 'sending_label'.tr : 'send_to_all_students_btn'.tr,
          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student details dialog — opens when a student card is tapped.
// The dialog lives on the root navigator, so the provider is re-supplied.
// ─────────────────────────────────────────────────────────────────────────────

void _showStudentDialog(
    BuildContext context, EnrolledStudent student, TeacherCourse course, Color color) {
  final provider = context.read<EnrolledStudentsProvider>();
  showDialog<void>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: provider,
      child: _StudentDetailsDialog(student: student, course: course, color: color),
    ),
  );
}

class _StudentDetailsDialog extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;
  final Color color;

  const _StudentDetailsDialog({
    required this.student,
    required this.course,
    required this.color,
  });

  String _formatDate(String raw) {
    try {
      final dt = raw.toLocalSaTime;
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final provider = context.watch<EnrolledStudentsProvider>();
    final pct = student.progressPercentage.clamp(0, 100).toDouble();

    return Dialog(
      backgroundColor: c.cardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(Icons.close_rounded, size: 20, color: c.textMedium, semanticLabel: 'close'.tr),
                  ),
                ),
              ),
              _RingAvatar(student: student, color: color),
              const SizedBox(height: 12),
              Text(
                student.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.textDark,
                ),
              ),
              const SizedBox(height: 16),
              // their progress and history in my courses (D-290)
              Center(child: EntityChip(EntityRef(EntityKind.student, student.id, label: student.name))),
              _InfoRow(icon: Icons.email_outlined, label: 'email'.tr, value: student.gmail),
              _InfoRow(
                icon: Icons.event_available_outlined,
                label: 'joined'.tr,
                value: _formatDate(student.enrolledAt),
              ),
              _InfoRow(
                icon: Icons.flag_outlined,
                label: 'status'.tr,
                value: student.status,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('stat_avg_progress'.tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium)),
                  const Spacer(),
                  Text('${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 8,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              ...[
                const SizedBox(height: 20),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('certificates'.tr,
                      style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.textDark)),
                ),
                const SizedBox(height: 8),
                if (course.certificates.isEmpty)
                  Text('no_certificate_for_course'.tr,
                      style: TextStyle(
                          fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium))
                else
                  for (final cert in course.certificates)
                    _CertificateRow(cert: cert, student: student, provider: provider),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textMedium),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One certificate inside the dialog: title, "sent N×" info, and a
/// send / resend button (always enabled, so it can be sent again).
class _CertificateRow extends StatelessWidget {
  final CourseCertificate cert;
  final EnrolledStudent student;
  final EnrolledStudentsProvider provider;

  const _CertificateRow({
    required this.cert,
    required this.student,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = provider.issuedCount(cert.id, student.id);
    final sending = provider.isSendingCertificate(cert.id, student.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, color: context.colors.accent2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cert.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textDark)),
                if (count > 0)
                  Text('${'certificate_sent_label'.tr} · $count×',
                      style: TextStyle(
                          fontFamily: AppFonts.family, fontSize: 11, color: c.success)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          sending
              ? const SizedBox(width: 24, height: 24, child: AppLoadingIndicator())
              : TextButton.icon(
            onPressed: provider.isBulkSending
                ? null
                : () async {
              final ok = await provider.sendCertificate(cert.id, student.id);
              if (!context.mounted) return;
              _showResultSnack(context, ok, 'certificate_sent_success'.tr);
            },
            icon: Icon(count > 0 ? Icons.replay_rounded : Icons.send_rounded, size: 16),
            label: Text(
              count > 0 ? 'resend_certificate_btn'.tr : 'send_certificate_btn'.tr,
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}