// lib/features/shared/course_profile/course_profile_screen.dart
//
// THE course profile — one page for external (VOD) and organization courses, for every role:
//   admin / instructor  everything: material (lectures + sections/labs), attendance, certificates, team, archive
//   assistant (TA)      sections/labs by default; lecture content / lecture attendance when the instructor grants it
//   student             material + secured video player, sessions, own attendance, progress, certificates
//   closed course       read-only material behind an archive pass (auto · request · code)
//   earlier version     staff open a past run (term) from Archive → Versions: read-only (runId)
//
// Since D-112 the course profile lives INSIDE the course page (course_profile_hub.dart): openCourseProfile and the
// '/course-profile' route open that page; this screen remains for an earlier version (runId, read-only) and as the
// fallback when the course page itself cannot be opened.
// The server decides the role and the capabilities (GET /api/v1/course-profile/{id}[?run_id=]) and enforces them on
// every write; tabs come from cpTabs(). The header is identity only — each role's numbers live on its overview.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../rag/rag_chat_screen.dart';

import '../../admin/admin_common.dart' show t;
import 'course_profile_announcements.dart';
import 'course_profile_hub.dart' show CoursePageLoader;
import 'course_profile_models.dart';
import 'course_profile_parts.dart';

/// At or above this width the page shows a side rail (next session · announcements · team).
const double kCpRailBreak = 1000;

/// Opens the course on its ONE page (D-112: the profile's parts are tabs of the course page), at [tab] (a profile
/// tab name: announcements · attendance · team · archive …). An earlier version ([runId]) still opens this read-only
/// profile screen.
Future<void> openCourseProfile(BuildContext context, int courseId, {int? runId, String? tab}) =>
    Navigator.of(context).push(MaterialPageRoute(
      settings: RouteSettings(name: '/course-profile', arguments: courseId),
      builder: (_) => runId != null
          ? CourseProfileScreen(courseId: courseId, runId: runId)
          : CoursePageLoader(courseId: courseId, tab: tab),
    ));

class CourseProfileScreen extends StatefulWidget {
  const CourseProfileScreen({super.key, required this.courseId, this.initial, this.initialTab, this.runId});
  final int courseId;

  /// An earlier run (version) of the course, read-only. Null = the current one.
  final int? runId;

  /// Optional preloaded payload (tests, or a caller that already fetched it).
  final Map<String, dynamic>? initial;
  final String? initialTab;

  @override
  State<CourseProfileScreen> createState() => _CourseProfileScreenState();
}

class _CourseProfileScreenState extends State<CourseProfileScreen> {
  CourseProfile? _p;
  String? _error;
  String _tab = 'overview';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab ?? 'overview';
    if (widget.initial != null) {
      _p = CourseProfile(widget.initial!);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get('/api/v1/course-profile/${widget.courseId}',
          queryParams: widget.runId == null ? null : {'run_id': widget.runId});
      if (!mounted) return;
      setState(() {
        _p = CourseProfile(Map<String, dynamic>.from(r as Map));
        _error = null;
        if (!cpTabs(_p!).contains(_tab)) _tab = 'overview';
      });
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final ar = AppConfig.lang == 'ar';
    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(
        title: p == null ? t('ملف المقرر', 'Course profile') : p.name(ar),
        actions: [
          ParentComponent(
            featureKey: 'rag.assistant',
            child: IconButton(
              tooltip: t('اسأل مستندات المقرر', 'Ask the course documents'),
              icon: const Icon(Icons.auto_stories_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RagChatScreen(courseId: widget.courseId, title: p == null ? null : p.name(ar)))),
            ),
          ),
          IconButton(
            tooltip: t('تحديث', 'Refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      child: _error != null && p == null
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'),
              onAction: () {
                setState(() => _error = null);
                _load();
              })
          : p == null
              ? const AppListSkeleton(items: 5)
              : AppRefresh(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (context, box) {
                    final wide = box.maxWidth >= kCpRailBreak;
                    final pad = box.maxWidth >= 900 ? 24.0 : 14.0;
                    final tabs = cpTabs(p);
                    final main = AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      child: KeyedSubtree(key: ValueKey(_tab), child: _body(p, wide)),
                    );
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                          sliver: SliverList.list(children: [
                            CpHeader(profile: p),
                            const SizedBox(height: 12),
                            ..._banners(context, p),
                          ]),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _TabsDelegate(
                            pad: pad,
                            child: _TabsBar(tabs: tabs, value: _tab, profile: p, onChanged: (v) => setState(() => _tab = v)),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
                          sliver: SliverToBoxAdapter(
                            child: wide
                                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Expanded(child: main),
                                    const SizedBox(width: 18),
                                    SizedBox(
                                      width: 300,
                                      child: CpSideRail(profile: p, onOpenTab: (v) => setState(() => _tab = v)),
                                    ),
                                  ])
                                : main,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
    );
  }

  List<Widget> _banners(BuildContext context, CourseProfile p) {
    final c = context.colors;
    final out = <Widget>[];
    if (p.pastVersion) {
      final term = p.course['term'] is Map ? Map<String, dynamic>.from(p.course['term'] as Map) : const <String, dynamic>{};
      final label = cpTermLabel(term, AppConfig.lang == 'ar');
      return [
        AppBanner(
          icon: Icons.history_rounded,
          color: c.accent,
          text: t('نسخة سابقة من المقرر ($label) — للاطلاع فقط، ارجع للنسخة الحالية بزر الرجوع',
              'An earlier version of the course ($label) — view only; go back for the current one'),
        ),
        const SizedBox(height: 10),
      ];
    }
    if (p.closed && p.isStudent) {
      final granted = p.archiveState == 'granted';
      out.add(AppBanner(
        icon: granted ? Icons.inventory_2_rounded : Icons.lock_rounded,
        color: granted ? c.primary : c.warning,
        text: granted
            ? t('المقرر مؤرشف — المحتوى متاح للقراءة فقط (بدون حضور أو بث مباشر)',
                'This course is archived — material is read-only (no attendance or live sessions)')
            : t('المقرر مؤرشف — افتح تبويب «الأرشيف» لطلب الوصول', 'This course is archived — open the “Archive” tab to get access'),
        action: granted ? null : TextButton(onPressed: () => setState(() => _tab = 'archive'), child: Text(t('الأرشيف', 'Archive'))),
      ));
    } else if (p.closed && p.isStaff) {
      out.add(AppBanner(
          icon: Icons.inventory_2_rounded,
          color: c.warning,
          text: t('المقرر مغلق ومؤرشف — لا حضور ولا بث مباشر', 'The course is closed and archived — no attendance or live sessions')));
    }
    final live = [...p.lectures, ...p.sections].where((s) => s.liveNow).toList();
    if (live.isNotEmpty && p.caps.live) {
      out.add(AppBanner(
        icon: Icons.sensors_rounded,
        color: c.danger,
        text: t('بث مباشر الآن: ${live.first.name}', 'Live now: ${live.first.name}'),
      ));
    }
    if (p.role == 'visitor') {
      out.add(AppBanner(
          icon: Icons.info_outline_rounded,
          text: t('اشترك في المقرر لفتح المحتوى', 'Enroll in the course to open its material')));
    }
    return [for (final w in out) Padding(padding: const EdgeInsets.only(bottom: 10), child: w)];
  }

  Widget _body(CourseProfile p, bool wide) => switch (_tab) {
        'lecture' => CpTrackTab(profile: p, track: 'lecture', onChanged: _load),
        'section' => CpTrackTab(profile: p, track: 'section', onChanged: _load),
        'attendance' => CpAttendanceTab(profile: p, onChanged: _load),
        'announcements' => CpAnnouncementsTab(profile: p, onChanged: _load, load: widget.initial == null),
        'certificates' => CpCertificatesTab(profile: p, onChanged: _load),
        'team' => CpTeamTab(profile: p, onChanged: _load),
        'archive' => CpArchiveTab(profile: p, onChanged: _load),
        _ => CpOverviewTab(profile: p, onOpenTab: (v) => setState(() => _tab = v), onChanged: _load, withRail: wide),
      };
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.tabs, required this.value, required this.onChanged, required this.profile});
  final List<String> tabs;
  final String value;
  final ValueChanged<String> onChanged;
  final CourseProfile profile;

  (String, IconData) _label(String k) => switch (k) {
        'lecture' => (t('المحاضرات', 'Lectures'), Icons.co_present_rounded),
        'section' => (t('السكاشن والمعامل', 'Sections & labs'), Icons.science_rounded),
        'announcements' => (t('الإعلانات', 'Announcements'), Icons.campaign_rounded),
        'attendance' => (t('الحضور', 'Attendance'), Icons.how_to_reg_rounded),
        'certificates' => (t('الشهادات', 'Certificates'), Icons.workspace_premium_rounded),
        'team' => (t('فريق التدريس', 'Teaching team'), Icons.groups_rounded),
        'archive' => (t('الأرشيف', 'Archive'), Icons.inventory_2_rounded),
        _ => (t('نظرة عامة', 'Overview'), Icons.dashboard_rounded),
      };

  int? _count(String k) => switch (k) {
        'lecture' => profile.lectures.length,
        'section' => profile.sections.length,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final k in tabs)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: AppChoiceChip(
              label: _count(k) == null ? _label(k).$1 : '${_label(k).$1} · ${_count(k)}',
              icon: _label(k).$2,
              selected: value == k,
              onTap: () => onChanged(k),
            ),
          ),
      ]),
    );
  }
}

/// Keeps the tab bar visible (pinned) while the page scrolls.
class _TabsDelegate extends SliverPersistentHeaderDelegate {
  _TabsDelegate({required this.child, required this.pad});
  final Widget child;
  final double pad;

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: overlapsContent || shrinkOffset > 0 ? Border(bottom: BorderSide(color: c.divider)) : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsDelegate old) => old.child != child || old.pad != pad;
}

/// The hero: who and what this course is — code · status · role chips, the name, organization · term, the instructor.
/// Numbers are on the overview, per role.
class CpHeader extends StatelessWidget {
  const CpHeader({super.key, required this.profile});
  final CourseProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final org = p.course['org'] is Map ? Map<String, dynamic>.from(p.course['org'] as Map) : null;
    final term = p.course['term'] is Map ? Map<String, dynamic>.from(p.course['term'] as Map) : null;
    final teacher = p.instructor?['name'] ?? (p.course['teacher'] is Map ? (p.course['teacher'] as Map)['name'] : null);
    final orgName = org == null ? '' : '${(ar ? org['name_ar'] : org['name_en']) ?? org['name_ar'] ?? ''}';
    final where = [orgName, if (term != null) cpTermLabel(term, ar)].where((s) => s.trim().isNotEmpty).join(' · ');

    final (statusLabel, statusColor) = switch (cpStatus(p)) {
      'archived' => (t('مؤرشف', 'Archived'), c.warning),
      'live' => (t('مباشر الآن', 'Live now'), c.danger),
      'upcoming' => (t('لم يبدأ بعد', 'Starts soon'), c.accent),
      _ => (t('جارٍ', 'In progress'), c.success),
    };

    Widget chip(String label, {Color? dot, IconData? icon}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.colors.onHero.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.colors.heroGlassBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            if (icon != null) ...[Icon(icon, size: 13, color: context.colors.onHero), const SizedBox(width: 5)],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: appText(11.5, w: FontWeight.w700, c: context.colors.onHero)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          colors: p.pastVersion ? [c.textMedium, c.textDark] : [c.primary, c.primaryDark],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: c.primaryShadow,
      ),
      child: LayoutBuilder(builder: (context, box) {
        final roomy = box.maxWidth >= 640;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (p.course['code'] != null) chip('${p.course['code']}', icon: Icons.tag_rounded),
            if (p.pastVersion)
              chip(t('نسخة سابقة', 'Earlier version'), icon: Icons.history_rounded)
            else
              chip(statusLabel, dot: statusColor),
            chip(cpRoleLabel(p.role), icon: Icons.badge_rounded),
          ]),
          const SizedBox(height: 10),
          Text(p.name(ar), maxLines: 3, overflow: TextOverflow.ellipsis,
              style: appText(roomy ? 23 : 19, w: FontWeight.w800, c: context.colors.onHero, h: 1.3)),
          if (where.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(where, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: context.colors.onHeroMuted)),
          ],
          if (teacher != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              AppAvatar(name: '$teacher', url: p.instructor?['image_url']?.toString(), size: 28),
              const SizedBox(width: 8),
              Flexible(
                child: Text('$teacher', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: appText(13, w: FontWeight.w700, c: context.colors.onHero)),
              ),
            ]),
          ],
        ]);
      }),
    );
  }
}

String cpRoleLabel(String role) => switch (role) {
      'admin' => t('إدارة', 'Admin'),
      'instructor' => t('أستاذ المقرر', 'Instructor'),
      'ta' => t('معيد', 'Teaching assistant'),
      'student' => t('طالب', 'Student'),
      _ => t('زائر', 'Visitor'),
    };

/// Error → user text (server codes mapped in both languages).
String cpErrorMessage(Object e) {
  final err = ApiException.from(e);
  final m = cpErrorText(err.code);
  return m == null ? err.message : t(m.$1, m.$2);
}

/// Runs a call, toasts the result. Returns the response, or null on error.
Future<dynamic> cpCall(Future<dynamic> Function() fn, {String? ok}) async {
  try {
    final r = await fn();
    if (ok != null) appToast(ok);
    return r ?? true;
  } catch (e) {
    appToast(cpErrorMessage(e), error: true);
    return null;
  }
}
