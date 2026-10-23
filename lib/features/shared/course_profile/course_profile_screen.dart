// lib/features/shared/course_profile/course_profile_screen.dart
//
// THE course profile — one page for external (VOD) and organization courses, for every role:
//   admin / instructor  everything: material (lectures + sections/labs), attendance, certificates, team, archive
//   assistant (TA)      sections/labs by default; lecture content / lecture attendance when the instructor grants it
//   student             material + secured video player, sessions, own attendance, progress, certificates
//   closed course       read-only material behind an archive pass (auto · request · code)
//
// Open with openCourseProfile(context, courseId) or the named route '/course-profile' (arguments: course id).
// The server decides the role and the capabilities (GET /api/v1/course-profile/{id}); tabs come from cpTabs().
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'course_profile_models.dart';
import 'course_profile_parts.dart';

/// Opens the course profile.
Future<void> openCourseProfile(BuildContext context, int courseId) =>
    Navigator.of(context).push(MaterialPageRoute(
      settings: RouteSettings(name: '/course-profile', arguments: courseId),
      builder: (_) => CourseProfileScreen(courseId: courseId),
    ));

class CourseProfileScreen extends StatefulWidget {
  const CourseProfileScreen({super.key, required this.courseId, this.initial, this.initialTab});
  final int courseId;

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
      final r = await ApiClient().get('/api/v1/course-profile/${widget.courseId}');
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (context, box) {
                    final pad = box.maxWidth >= 900 ? 24.0 : 14.0;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
                      children: [
                        CpHeader(profile: p),
                        const SizedBox(height: 12),
                        ..._banners(context, p),
                        _TabsBar(tabs: cpTabs(p), value: _tab, profile: p, onChanged: (v) => setState(() => _tab = v)),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: KeyedSubtree(key: ValueKey(_tab), child: _body(p)),
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

  Widget _body(CourseProfile p) => switch (_tab) {
        'lecture' => CpTrackTab(profile: p, track: 'lecture', onChanged: _load),
        'section' => CpTrackTab(profile: p, track: 'section', onChanged: _load),
        'attendance' => CpAttendanceTab(profile: p),
        'certificates' => CpCertificatesTab(profile: p, onChanged: _load),
        'team' => CpTeamTab(profile: p, onChanged: _load),
        'archive' => CpArchiveTab(profile: p, onChanged: _load),
        _ => CpOverviewTab(profile: p, onOpenTab: (v) => setState(() => _tab = v), onChanged: _load),
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
        'attendance' => (t('الحضور', 'Attendance'), Icons.how_to_reg_rounded),
        'certificates' => (t('الشهادات', 'Certificates'), Icons.workspace_premium_rounded),
        'team' => (t('فريق التدريس', 'Teaching team'), Icons.groups_rounded),
        'archive' => (t('الأرشيف', 'Archive'), Icons.inventory_2_rounded),
        _ => (t('نظرة عامة', 'Overview'), Icons.dashboard_rounded),
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
              label: _label(k).$1,
              icon: _label(k).$2,
              selected: value == k,
              onTap: () => onChanged(k),
            ),
          ),
      ]),
    );
  }
}

/// The hero: course identity, role and the four numbers that matter to this role.
class CpHeader extends StatelessWidget {
  const CpHeader({super.key, required this.profile});
  final CourseProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final ar = AppConfig.lang == 'ar';
    final a = p.analytics;
    final org = p.course['org'] is Map ? Map<String, dynamic>.from(p.course['org'] as Map) : null;
    final term = p.course['term'] is Map ? Map<String, dynamic>.from(p.course['term'] as Map) : null;
    final teacher = p.instructor?['name'] ?? (p.course['teacher'] is Map ? (p.course['teacher'] as Map)['name'] : null);
    final sub = [
      if (p.course['code'] != null) '${p.course['code']}',
      if (org != null) '${(ar ? org['name_ar'] : org['name_en']) ?? org['name_ar'] ?? ''}',
      if (term != null) '${term['year_label'] ?? ''}',
      if (teacher != null) '$teacher',
      cpRoleLabel(p.role),
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    String pct(dynamic v) => v is num ? '${v.round()}%' : '—';
    final stats = p.isStudent
        ? [
            AppHeroStat(icon: Icons.trending_up_rounded, value: pct(p.progress['overall']), label: t('التقدم', 'Progress')),
            AppHeroStat(
                icon: Icons.how_to_reg_rounded,
                value: (a['expected'] ?? 0) == 0 ? '—' : '${a['attended']}/${a['expected']}',
                label: t('الحضور', 'Attendance')),
            AppHeroStat(icon: Icons.co_present_rounded, value: '${a['lectures'] ?? 0}', label: t('محاضرات', 'Lectures')),
            AppHeroStat(icon: Icons.science_rounded, value: '${a['sections'] ?? 0}', label: t('سكاشن', 'Sections')),
          ]
        : p.isStaff
            ? [
                AppHeroStat(icon: Icons.people_alt_rounded, value: '${a['students'] ?? 0}', label: t('الطلاب', 'Students')),
                AppHeroStat(icon: Icons.trending_up_rounded, value: pct(a['avg_progress']), label: t('متوسط التقدم', 'Avg progress')),
                AppHeroStat(icon: Icons.how_to_reg_rounded, value: pct(a['attendance_rate']), label: t('نسبة الحضور', 'Attendance')),
                AppHeroStat(
                    icon: Icons.event_busy_rounded, value: '${a['missed_by_staff'] ?? 0}', label: t('لم تُعقد', 'Not held')),
              ]
            : [
                AppHeroStat(icon: Icons.co_present_rounded, value: '${a['lectures'] ?? 0}', label: t('محاضرات', 'Lectures')),
                AppHeroStat(icon: Icons.science_rounded, value: '${a['sections'] ?? 0}', label: t('سكاشن', 'Sections')),
              ];
    return AppHero(
      title: p.name(ar),
      subtitle: sub,
      icon: p.isOrg ? Icons.account_balance_rounded : Icons.play_lesson_rounded,
      stats: stats,
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
