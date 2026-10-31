// lib/features/shared/course_profile/course_profile_hub.dart
//
// The course profile INSIDE the one course page (D-111). The student's course details and the teacher's course
// studio (both CourseSpace) carry the profile's parts as tabs of their own instead of opening a second page:
//
//   student   Announcements (unread count) · Progress (progress per part · attendance · grade · certificates)
//             · Archive (a closed course: read-only access by code / request) · the teaching team in About
//   staff     Announcements (post: a TA to sections & labs unless granted) · Class (open attendance · by hand ·
//             numbers · the attendance report · certificate rules) · Team (assistants and their grants) ·
//             Archive (access policy · requests · earlier versions)
//
// The profile (GET /api/v1/course-profile/{id}) is loaded LAZILY: when one of those tabs (or About's team block) is
// first built — the page's open costs no extra request — or up front when the page was opened from an old entry
// point (openCourseProfile / the '/course-profile' route / a course_profile notification) through
// [CoursePageLoader], which needs it to know the person's role. The server decides every capability (CpCaps) and
// enforces it on each write; an archived course is read-only. An earlier run (Archive → Versions) still opens the
// read-only CourseProfileScreen.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../design/app_kit.dart';
import '../../admin/admin_common.dart' show t;
import '../../student/courses/details/course_detail_screen.dart' show CourseDetailScreen;
import '../../student/models.dart' show CourseModel;
import '../../teacher/home/teacher_models.dart' show TeacherCourse;
import '../../teacher/sessions/sessions_provider.dart' show TeacherCourseScreenProvider;
import '../../teacher/sessions/sessions_screen.dart' show TeacherSessionsScreen;
import '../course/course_space/course_space.dart';
import '../rag/rag_chat_screen.dart' show RagChatScreen;
import 'course_profile_announcements.dart';
import 'course_profile_models.dart';
import 'course_profile_parts.dart';
import 'course_profile_screen.dart' show CourseProfileScreen, cpErrorMessage;

/// Tab ids the profile adds to the course page.
const kCpTabAnnouncements = 'announcements';
const kCpTabProgress = 'progress';
const kCpTabClass = 'class';
const kCpTabTeam = 'team';
const kCpTabArchive = 'archive';

/// The page's own copy of the course profile: loaded once on demand, reloaded after a write / pull-to-refresh.
class CourseProfileHub extends ChangeNotifier {
  CourseProfileHub(this.courseId, {Map<String, dynamic>? initial}) {
    if (initial != null) _p = CourseProfile(initial);
    _seenLoad();
  }

  final int courseId;
  CourseProfile? _p;
  String? _error;
  bool _loading = false;
  bool _disposed = false;

  CourseProfile? get profile => _p;
  String? get error => _error;
  bool get loading => _loading;

  /// Loads the profile the first time something needs it.
  void ensure() {
    if (_p != null || _loading || _error != null) return;
    load();
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final r = await ApiClient().get('/api/v1/course-profile/$courseId');
      _p = CourseProfile(Map<String, dynamic>.from(r as Map));
    } catch (e) {
      _error = cpErrorMessage(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Pull-to-refresh: reload only what was already loaded.
  Future<void> refresh() async {
    if (_p != null || _error != null) await load();
  }

  // ── announcements: "unread" = newer than the last one this person saw here (kept on the device) ──

  static const _seenKey = 'cp_announcements_seen';
  SharedPreferences? _prefs;
  int? _seen;

  String _uid(SharedPreferences p) {
    try {
      final raw = p.getString('current_user');
      return raw == null ? '0' : '${(jsonDecode(raw) as Map)['id']}';
    } catch (_) {
      return '0';
    }
  }

  void _seenLoad() {
    SharedPreferences.getInstance().then((p) {
      _prefs = p;
      final prefix = '${_uid(p)}:$courseId:';
      for (final e in p.getStringList(_seenKey) ?? const <String>[]) {
        if (e.startsWith(prefix)) _seen = int.tryParse(e.substring(prefix.length));
      }
      _notify();
    }).catchError((Object _) {});
  }

  /// Announcements newer than the last one seen on this device (from the profile's latest ones).
  int get unread {
    final p = _p;
    if (p == null || p.pastVersion) return 0;
    return p.announcements.where((a) => (a['id'] is num ? (a['id'] as num).toInt() : 0) > (_seen ?? 0)).length;
  }

  /// The Announcements tab was opened: everything up to its newest is seen.
  void markSeen(Iterable<Map<String, dynamic>> items) {
    var top = _seen ?? 0;
    for (final a in items) {
      final id = a['id'] is num ? (a['id'] as num).toInt() : 0;
      if (id > top) top = id;
    }
    if (top == (_seen ?? 0)) return;
    _seen = top;
    _notify();
    final p = _prefs;
    if (p == null) return;
    final prefix = '${_uid(p)}:$courseId:';
    final list = [for (final e in p.getStringList(_seenKey) ?? const <String>[]) if (!e.startsWith(prefix)) e, '$prefix$top'];
    p.setStringList(_seenKey, list.length > 400 ? list.sublist(list.length - 400) : list).catchError((Object _) => false);
  }

  /// Where an old entry point lands when it did not ask for a tab: a closed course's archive (student), the
  /// announcements while some are unread, else the page's own first tab (null).
  String? smartTab() {
    final p = _p;
    if (p == null) return null;
    if (p.closed && p.isStudent && p.archiveState != 'granted') return kCpTabArchive;
    if (unread > 0) return kCpTabAnnouncements;
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Maps a course-profile tab name (old deep links: overview · lecture · section · attendance · certificates …) to
/// the one page's tab.
String? cpMergedTab(String? old, {required bool staff}) => switch (old) {
  null || 'overview' => null,
  'lecture' || 'section' => 'sessions',
  'attendance' || 'certificates' => staff ? kCpTabClass : kCpTabProgress,
  'announcements' || 'team' || 'archive' || 'progress' || 'class' => old,
  _ => null,
};

/// The profile's tabs for the course page. [staff]: the studio (instructor / TA / org admin), else the student's
/// details. [org]: an organization course (team and archive exist there). [enrolled]: the student is in the course.
/// [onOpenTab] switches the page's tab (the profile's own links: "attendance", "announcements" …).
List<CourseSpaceTab> courseProfileTabs({
  required CourseProfileHub hub,
  required bool staff,
  required bool org,
  required bool enrolled,
  required ValueChanged<String> onOpenTab,
  String? forced,
}) {
  final p = hub.profile;
  final role = p?.role;
  final visitor = role == 'visitor';
  final student = !staff;
  void open(String old) => onOpenTab(cpMergedTab(old, staff: staff) ?? 'sessions');

  final showAnn = p == null ? (staff || enrolled) : !visitor && (p.caps.announce || p.announcements.isNotEmpty || p.isStudent);
  final showProgress = student && (p == null ? enrolled : p.isStudent);
  final showClass = staff && (p == null || p.isStaff);
  final showTeam = staff && (p == null ? org : (p.caps.manageStaff || p.role == 'ta') && (org || p.assistants.isNotEmpty));
  final showArchive = p == null
      ? (staff && org) || forced == kCpTabArchive
      : p.caps.manageArchive || p.caps.approveArchive || p.caps.viewVersions || (p.closed && p.isStudent);

  return [
    if (showAnn || forced == kCpTabAnnouncements)
      CourseSpaceTab(
        id: kCpTabAnnouncements,
        label: t('الإعلانات', 'Announcements'),
        icon: Icons.campaign_rounded,
        count: hub.unread > 0 ? hub.unread : null,
        builder: (_) => CourseProfileTabBody(
          hub: hub,
          builder: (p) => _AnnouncementsBody(hub: hub, profile: p),
        ),
      ),
    if (showProgress || forced == kCpTabProgress)
      CourseSpaceTab(
        id: kCpTabProgress,
        label: t('تقدّمي', 'Progress'),
        icon: Icons.insights_rounded,
        builder: (_) => CourseProfileTabBody(
          hub: hub,
          builder: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CpOverviewTab(profile: p, onOpenTab: open, onChanged: hub.load, merged: true),
              if (p.caps.viewAttendance) ...[
                AppSectionTitle(t('حضوري', 'My attendance')),
                const SizedBox(height: 8),
                CpAttendanceTab(profile: p, onChanged: hub.load),
              ],
              if (p.certificates.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppSectionTitle(t('الشهادات', 'Certificates')),
                const SizedBox(height: 8),
                CpCertificatesTab(profile: p, onChanged: hub.load),
              ],
            ],
          ),
        ),
      ),
    if (showClass || forced == kCpTabClass)
      CourseSpaceTab(
        id: kCpTabClass,
        label: t('الحضور', 'Attendance'),
        icon: Icons.how_to_reg_rounded,
        builder: (_) => CourseProfileTabBody(
          hub: hub,
          builder: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CpOverviewTab(profile: p, onOpenTab: open, onChanged: hub.load, merged: true),
              if (p.caps.viewAttendance) ...[
                AppSectionTitle(t('سجل الحضور', 'Attendance')),
                const SizedBox(height: 8),
                CpAttendanceTab(profile: p, onChanged: hub.load),
              ],
              if (p.certificates.isNotEmpty || p.caps.manageCertificates) ...[
                const SizedBox(height: 12),
                AppSectionTitle(t('الشهادات', 'Certificates'),
                    subtitle: t('عن أي جزء تُمنح وكيف تُرسل', 'What each certifies and how it is sent')),
                const SizedBox(height: 8),
                CpCertificatesTab(profile: p, onChanged: hub.load),
              ],
            ],
          ),
        ),
      ),
    if (showTeam || forced == kCpTabTeam)
      CourseSpaceTab(
        id: kCpTabTeam,
        label: t('الفريق', 'Team'),
        icon: Icons.groups_2_rounded,
        builder: (_) => CourseProfileTabBody(hub: hub, builder: (p) => CpTeamTab(profile: p, onChanged: hub.load)),
      ),
    if (showArchive || forced == kCpTabArchive)
      CourseSpaceTab(
        id: kCpTabArchive,
        label: t('الأرشيف', 'Archive'),
        icon: Icons.inventory_2_rounded,
        builder: (_) => CourseProfileTabBody(hub: hub, builder: (p) => CpArchiveTab(profile: p, onChanged: hub.load)),
      ),
  ];
}

/// A profile tab's body: asks the hub for the profile on first build, then draws [builder] in the page's gutter.
class CourseProfileTabBody extends StatefulWidget {
  const CourseProfileTabBody({super.key, required this.hub, required this.builder});

  final CourseProfileHub hub;
  final Widget Function(CourseProfile p) builder;

  @override
  State<CourseProfileTabBody> createState() => _CourseProfileTabBodyState();
}

class _CourseProfileTabBodyState extends State<CourseProfileTabBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.hub.ensure();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.hub,
    builder: (context, _) {
      final h = widget.hub;
      final p = h.profile;
      final Widget child;
      if (p != null) {
        child = widget.builder(p);
      } else if (h.error != null) {
        child = AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: h.error!,
          actionLabel: t('إعادة المحاولة', 'Retry'),
          onAction: h.load,
        );
      } else {
        child = const SizedBox(height: 320, child: AppListSkeleton(items: 4));
      }
      return Padding(padding: const EdgeInsets.fromLTRB(kCourseGutter, 8, kCourseGutter, 8), child: child);
    },
  );
}

class _AnnouncementsBody extends StatefulWidget {
  const _AnnouncementsBody({required this.hub, required this.profile});

  final CourseProfileHub hub;
  final CourseProfile profile;

  @override
  State<_AnnouncementsBody> createState() => _AnnouncementsBodyState();
}

class _AnnouncementsBodyState extends State<_AnnouncementsBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.hub.markSeen(widget.profile.announcements);
    });
  }

  @override
  Widget build(BuildContext context) => CpAnnouncementsTab(profile: widget.profile, onChanged: widget.hub.load);
}

/// The archive / read-only state of the course, as the page's first spotlight card (once the profile is known).
class CourseArchiveSpot extends StatelessWidget {
  const CourseArchiveSpot({super.key, required this.hub, required this.onOpenTab});

  final CourseProfileHub hub;
  final ValueChanged<String> onOpenTab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hub,
    builder: (context, _) {
      final p = hub.profile;
      if (p == null || !p.closed) return const SizedBox.shrink();
      final c = context.colors;
      final granted = p.archiveState == 'granted';
      if (p.isStudent) {
        return CourseSpotlightCard(
          icon: granted ? Icons.inventory_2_rounded : Icons.lock_rounded,
          color: c.warning,
          title: t('المقرر مؤرشف', 'This course is archived'),
          subtitle: granted
              ? t('المحتوى متاح للقراءة فقط — بدون حضور أو بث مباشر', 'Material is read-only — no attendance or live sessions')
              : t('افتح الأرشيف لطلب الوصول للقراءة فقط', 'Open the archive to ask for read-only access'),
          actionLabel: granted ? null : t('الأرشيف', 'Archive'),
          onAction: granted ? null : () => onOpenTab(kCpTabArchive),
        );
      }
      return CourseSpotlightCard(
        icon: Icons.inventory_2_rounded,
        color: c.warning,
        title: t('المقرر مغلق ومؤرشف', 'The course is closed and archived'),
        subtitle: t('للقراءة فقط — لا حضور ولا بث مباشر', 'Read-only — no attendance or live sessions'),
      );
    },
  );
}

/// The teaching team in the student's About tab (instructor + assistants), from the profile (loaded when About opens).
class CourseTeamBlock extends StatefulWidget {
  const CourseTeamBlock({super.key, required this.hub});

  final CourseProfileHub hub;

  @override
  State<CourseTeamBlock> createState() => _CourseTeamBlockState();
}

class _CourseTeamBlockState extends State<CourseTeamBlock> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.hub.ensure();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.hub,
    builder: (context, _) {
      final p = widget.hub.profile;
      if (p == null || p.assistants.isEmpty) return const SizedBox.shrink(); // the instructor is the hero's
      final c = context.colors;
      Widget person(Map<String, dynamic> u, String role) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AppAvatar(name: '${u['name'] ?? ''}', url: u['image_url']?.toString(), size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${u['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: appText(14, w: FontWeight.w500, c: c.textDark)),
                  Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                ],
              ),
            ),
          ],
        ),
      );
      final ins = p.instructor;
      return Padding(
        padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, 8),
        child: CourseInfoGroup(
          children: [
            CourseInfoSection(
              title: t('فريق التدريس', 'Teaching team'),
              icon: Icons.groups_2_rounded,
              color: c.accent2,
              children: [
                if (ins != null) person(ins, t('أستاذ المقرر', 'Instructor')),
                for (final a in p.assistants)
                  person(
                    a['user'] is Map ? Map<String, dynamic>.from(a['user'] as Map) : const <String, dynamic>{},
                    t('معيد — السكاشن والمعامل', 'Assistant — sections & labs'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Old entry points → the one page
// ═════════════════════════════════════════════════════════════════════════════

/// Opens a course on its one page knowing only its id, at [tab] (a course-profile tab name is mapped). Used by
/// openCourseProfile, the '/course-profile' route and course_profile notifications.
class CoursePageLoader extends StatefulWidget {
  const CoursePageLoader({super.key, required this.courseId, this.tab});

  final int courseId;
  final String? tab;

  @override
  State<CoursePageLoader> createState() => _CoursePageLoaderState();
}

class _CoursePageLoaderState extends State<CoursePageLoader> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (mounted) setState(() => _error = null);
    final api = ApiClient();
    Map<String, dynamic> profile;
    try {
      profile = Map<String, dynamic>.from(await api.get('/api/v1/course-profile/${widget.courseId}') as Map);
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
      return;
    }
    final p = CourseProfile(profile);
    final hub = CourseProfileHub(widget.courseId, initial: profile);
    final staff = p.isStaff;
    final tab = cpMergedTab(widget.tab, staff: staff) ?? hub.smartTab();
    Widget page;
    try {
      final json = Map<String, dynamic>.from(await api.get('/api/v1/courses/${widget.courseId}') as Map);
      if (staff) {
        final course = TeacherCourse.fromJson(json);
        page = ChangeNotifierProvider(
          create: (_) => TeacherCourseScreenProvider(initialCourse: course),
          child: TeacherSessionsScreen(profileHub: hub, initialTab: tab),
        );
      } else {
        page = CourseDetailScreen(course: CourseModel.fromJson(json), profileHub: hub, initialTab: tab);
      }
    } catch (_) {
      // the course page itself is not reachable (e.g. a closed organization course): the profile alone still is
      page = CourseProfileScreen(courseId: widget.courseId, initial: profile, initialTab: widget.tab);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(settings: const RouteSettings(name: '/course-detail'), builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background,
    body: SafeArea(
      child: _error == null
          ? const CourseSpaceSkeleton()
          : AppEmpty(
              icon: Icons.cloud_off_rounded,
              title: _error!,
              actionLabel: t('إعادة المحاولة', 'Retry'),
              onAction: _run,
            ),
    ),
  );
}

/// The ⋮ entry "Ask the course documents" (RAG), kept from the old profile's header.
CourseSpaceTopAction courseAskDocsAction(BuildContext context, int courseId, String title) => CourseSpaceTopAction(
  icon: Icons.auto_stories_outlined,
  tooltip: t('اسأل مستندات المقرر', 'Ask the course documents'),
  featureKey: 'rag.assistant',
  overflow: true,
  onTap: () => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => RagChatScreen(courseId: courseId, title: title)),
  ),
);
