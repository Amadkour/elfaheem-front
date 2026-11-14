// lib/features/shared/public_profile/public_profile_page.dart
//
// The ONE profile page per person (D-074, D-850 – D-855). Everyone sees the same body (PublicProfileView); only
// who looks changes what is around it:
//
//   PublicProfileScreen(username:, fallback:)   a visitor: GET /api/v1/public/u/{username} (no token, ever). A guest
//                                      gets it straight from the link, with no sign-in and no authenticated call,
//                                      plus the soft "join NextBrain" card; a course opens its public preview
//                                      (`/c/<id>`). Signed in as that very person → MyProfileScreen instead.
//                                      [fallback] replaces "not found" (a course's instructor without a public page)
//   MyProfileScreen                    the owner: GET /api/v1/me/public-profile — the page exactly as visitors see it
//                                      (even while private) under the owner panel: public on / off, which sections
//                                      show, Edit profile, Share, Account & settings, the teacher's documents
//   ProfileOwnerPanel                  that panel, plain values (test/ui/public_profile_stats_test.dart)
//   openPersonProfile(context, …)      a course's instructor → their one page when they have a username, else the
//                                      instructor screen (course_instractor_profile.dart, kept for documents)
//   shareProfileLink(context, …)       the app's one share sheet (D-307): the link, Copy, the system share sheet, QR
//   ShareMyProfileTile / MyProfileTile the Account page's rows (kill switches `auth.username` + `profile.public_link`,
//                                      `profile.my_profile`)
// Routing: main.dart `_router` (`/@name`: guests get this page directly, D-854), DeepLinkService, AppNavigator.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../design/app_kit.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_navigator.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/deep_link_service.dart';
import '../../../utils/widget/parent_component.dart';
import '../../admin/admin_common.dart' show t;
import '../../auth/auth_provider.dart';
import '../../auth/username.dart' show kUsernameFeatureKey, UsernameRules;
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherProfileData;
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import '../../../design/app_share_sheet.dart' show showAppShareSheet, appLinkKindLabel, AppLinkKind;
import '../profile/course_instractor_profile.dart' show InstructorProfileScreen;
import '../profile/update_account_widget.dart' show EditAccountScreen;
import 'public_profile.dart';
import 'public_profile_view.dart';

/// True when the signed-in person is [username] (a confirmed name): their link opens the owner's page.
bool _isMe(BuildContext context, String username) {
  final u = context.read<MyAuthProvider>();
  final me = u.isAuthenticated ? u.currentUser : null;
  final mine = me?.username;
  return me != null && mine != null && me.usernameConfirmed && UsernameRules.normalize(mine) == UsernameRules.normalize(username);
}

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.username, this.fallback});

  /// With or without "@", any case.
  final String username;

  /// Shown instead of "not found" (e.g. a course's instructor whose page is private): the older instructor screen.
  final Widget? fallback;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  PublicProfileResult? _result;
  late final bool _me = _isMe(context, widget.username);

  @override
  void initState() {
    super.initState();
    if (!_me) _load();
  }

  Future<void> _load() async {
    if (_result != null) setState(() => _result = null);
    final r = await PublicProfileApi.load(widget.username); // auth: false — a guest's page never sends a token
    if (mounted) setState(() => _result = r);
  }

  bool get _signedIn => context.read<MyAuthProvider>().isAuthenticated;

  void _openCourse(int id) {
    if (_signedIn) {
      AppNavigator.openCourse(id);
    } else {
      Navigator.of(context).pushNamed('/c/$id'); // the course's public preview + Sign in (D-307)
    }
  }

  void _signIn({required bool register}) {
    // back to this page right after the sign-in / sign-up (DeepLinkService.consumePending in the home's guard)
    DeepLinkService.instance.setPendingProfile(ProfileLink(UsernameRules.normalize(widget.username)));
    Navigator.of(context).pushNamed(register ? '/register' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_me) return const MyProfileScreen();
    final r = _result;
    final fb = widget.fallback;
    if (fb != null && r != null && r.status != PublicProfileStatus.found) return fb;
    final p = r?.profile;
    final guest = !_signedIn;
    return BasePage(
      key: const ValueKey(kPublicLinkFeatureKey),
      enableFooterWidget: false,
      appBar: ScreenAppBar(
        title: p == null ? t('الملف الشخصي', 'Profile') : p.name,
        actions: [
          if (p != null)
            IconButton(
              tooltip: t('مشاركة الرابط', 'Share link'),
              icon: Icon(Icons.ios_share_rounded, color: context.colors.textDark),
              onPressed: () => shareProfileLink(context, username: p.username, name: p.name, teacher: p.isTeacher),
            ),
        ],
      ),
      child: PublicProfileView(
        result: _result,
        onRetry: _load,
        onBack: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null,
        onOpenCourse: (c) {
          final id = int.tryParse(c.id);
          if (id != null) _openCourse(id);
        },
        onOpenCourseId: _openCourse,
        joinCard: guest && p != null
            ? ProfileJoinCard(
                name: p.name,
                teacher: p.isTeacher,
                onJoin: () => _signIn(register: true),
                onSignIn: () => _signIn(register: false),
              )
            : null,
      ),
    );
  }
}

/// The owner's view of the one profile page (D-850): the page as visitors see it under the owner panel.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  MyPublicProfile? _mine;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final m = await PublicProfileApi.mine();
      if (mounted) setState(() => _mine = m);
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  Future<void> _save({bool? isPublic, Map<String, bool>? fields}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final m = await PublicProfileApi.save(isPublic: isPublic, fields: fields);
      if (mounted && m != null) setState(() => _mine = m);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final teacher = context.read<MyAuthProvider>().isTeacher;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditAccountScreen(isTeacher: teacher)));
    if (mounted) _load();
  }

  /// The teacher's documents and credentials (the older instructor screen, owner view) — null when not loaded.
  VoidCallback? _documents() {
    if (!context.read<MyAuthProvider>().isTeacher) return null;
    final home = context.read<TeacherHomeProvider>();
    final TeacherProfileData? me = home.stats.teacher;
    if (me == null) return null;
    return () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InstructorProfileScreen(teacher: me, studentView: false, stats: home.stats),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final m = _mine;
    final p = m?.profile;
    final share = m != null && m.live && m.username != null && p != null
        ? () => shareProfileLink(context, username: m.username!, name: p.name, teacher: p.isTeacher)
        : null;
    final PublicProfileResult? result = m == null
        ? (_error == null ? null : PublicProfileResult(PublicProfileStatus.failed, message: _error))
        : (p == null
            ? const PublicProfileResult(PublicProfileStatus.notFound)
            : PublicProfileResult(PublicProfileStatus.found, profile: p));
    return BasePage(
      key: const ValueKey(kMyProfileFeatureKey),
      enableFooterWidget: false,
      appBar: ScreenAppBar(
        title: t('ملفي الشخصي', 'My profile'),
        actions: [
          if (share != null)
            IconButton(
              tooltip: t('مشاركة الرابط', 'Share link'),
              icon: Icon(Icons.ios_share_rounded, color: context.colors.textDark),
              onPressed: share,
            ),
        ],
      ),
      child: PublicProfileView(
        result: result,
        onRetry: _load,
        onOpenCourse: (c) {
          final id = int.tryParse(c.id);
          if (id != null) AppNavigator.openCourse(id);
        },
        onOpenCourseId: (id) => AppNavigator.openCourse(id),
        ownerPanel: m == null
            ? null
            : ProfileOwnerPanel(
                mine: m,
                busy: _busy,
                onPublic: (v) => _save(isPublic: v),
                onField: (k, v) => _save(fields: {k: v}),
                onEdit: _edit,
                onShare: share,
                onAccount: () => Navigator.of(context).pushNamed('/profile'),
                onDocuments: _documents(),
              ),
      ),
    );
  }
}

/// The section names a person may show, in their words.
String profileSectionLabel(String key) => switch (key) {
      'bio' => t('النبذة', 'About'),
      'stats' => t('الأرقام (الطلاب، الساعات، التقييم…)', 'Figures (students, hours, rating…)'),
      'courses' => t('الكورسات والأكثر انضماماً', 'Courses and most joined'),
      'growth' => t('نمو الطلاب على 12 شهراً', 'Student growth over 12 months'),
      'reviews' => t('التقييمات', 'Ratings'),
      'learning' => t('ملخص التعلّم (المواظبة، المكتمل، الشهادات)', 'Learning summary (streak, completed, certificates)'),
      'completed_courses' => t('الكورسات التي أكملتها', 'Courses I completed'),
      _ => key,
    };

/// The owner panel under the hero (D-850): public on / off with what it means right now, the sections, and the
/// owner's actions. Plain values: the screen does the calls.
class ProfileOwnerPanel extends StatelessWidget {
  const ProfileOwnerPanel({
    super.key,
    required this.mine,
    required this.onPublic,
    required this.onField,
    this.busy = false,
    this.onEdit,
    this.onShare,
    this.onAccount,
    this.onDocuments,
  });

  final MyPublicProfile mine;
  final bool busy;
  final ValueChanged<bool> onPublic;
  final void Function(String key, bool value) onField;
  final VoidCallback? onEdit, onShare, onAccount, onDocuments;

  String _status() {
    final m = mine;
    switch (m.blocked) {
      case 'username_unconfirmed':
        return t('أكّد اسم المستخدم من «تعديل الملف» ليصبح لك رابط عام.',
            'Confirm your username in Edit profile to get a public link.');
      case 'links_disabled':
        return t('روابط الملفات العامة متوقفة حالياً على المنصة.', 'Public profile links are switched off on the platform right now.');
      case 'account_incomplete':
        return t('أكمل تسجيل حسابك ليصبح ملفك عاماً.', 'Finish setting up your account to make your profile public.');
    }
    if (!m.isPublic) return t('ملفك خاص: لا يراه أحد غيرك.', 'Your profile is private: only you can see it.');
    return t('يراه أي شخص معه الرابط، حتى دون حساب.', 'Anyone with the link can see it, even without an account.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = mine;
    final link = m.link;
    final student = m.available.contains('learning');
    return AppSection(
      title: t('من يرى ماذا', 'Who sees what'),
      subtitle: student
          ? t('ملفك خاص افتراضياً، وأنت تختار ما يظهر. لا يظهر أبداً بريدك أو هاتفك أو مدرستك أو صفك أو درجاتك.',
              'Your profile is private by default and you choose what shows. Your e-mail, phone, school, grade and marks never show.')
          : t('هذه صفحتك كما يراها الزوار. لا يظهر أبداً بريدك أو هاتفك، ولا أسماء طلابك.',
              'This is your page as visitors see it. Your e-mail, phone and your students\' names never show.'),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSwitchTile(
            icon: m.live ? Icons.public_rounded : Icons.lock_rounded,
            title: t('ملف عام', 'Public profile'),
            subtitle: _status(),
            value: m.isPublic,
            onChanged: busy ? null : onPublic,
          ),
          if (link != null && m.live) ...[
            const SizedBox(height: AppSpace.xs),
            Text(link.replaceFirst('https://', ''),
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: c.primary)),
          ],
          if (m.available.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            const SizedBox(height: AppSpace.xs),
            Text(t('الأقسام الظاهرة', 'Sections shown'), style: AppType.label(context).copyWith(color: c.textMedium)),
            for (final k in m.available)
              if (k != 'stats' || !AppConfig.disableList.contains(kPublicStatsFeatureKey))
                AppSwitchTile(
                  dense: true,
                  title: profileSectionLabel(k),
                  value: m.fields[k] ?? false,
                  onChanged: busy ? null : (v) => onField(k, v),
                ),
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            if (onEdit != null)
              AppButton.primary(label: t('تعديل الملف', 'Edit profile'), icon: Icons.edit_rounded, onPressed: onEdit, size: AppButtonSize.sm),
            if (onShare != null)
              AppButton.secondary(label: t('مشاركة', 'Share'), icon: Icons.ios_share_rounded, onPressed: onShare, size: AppButtonSize.sm),
            if (onDocuments != null)
              AppButton.ghost(label: t('الوثائق والشهادات', 'Documents & credentials'), icon: Icons.badge_rounded, onPressed: onDocuments, size: AppButtonSize.sm),
            if (onAccount != null)
              AppButton.ghost(label: t('الحساب والإعدادات', 'Account & settings'), icon: Icons.settings_rounded, onPressed: onAccount, size: AppButtonSize.sm),
          ]),
        ]),
      ),
    );
  }
}

/// A course's instructor: their one profile page when they have a public username (D-853), the instructor screen
/// (documents, ratings) when they have none or keep it private.
Future<void> openPersonProfile(BuildContext context, TeacherProfileData teacher) {
  final name = teacher.username;
  final older = InstructorProfileScreen(teacher: teacher);
  final off = AppConfig.disableList.contains(kUsernameFeatureKey) || AppConfig.disableList.contains(kPublicLinkFeatureKey);
  final direct = name == null || off;
  return Navigator.of(context).push(MaterialPageRoute(
    settings: direct ? null : RouteSettings(name: '/@$name'),
    builder: (_) => direct ? older : PublicProfileScreen(username: name, fallback: older),
  ));
}

/// Shares `https://nextbrain.site/@username`: the app's one share sheet (D-307): the link, Copy, the system share
/// sheet (apps) and a QR code.
Future<void> shareProfileLink(BuildContext context, {required String username, required String name, bool teacher = true}) async {
  final (kind, icon) = appLinkKindLabel(AppLinkKind.teacher);
  await showAppShareSheet(context,
      url: profileUrl(username),
      title: name,
      subtitle: '@$username',
      kind: teacher ? kind : t('ملف شخصي', 'Profile'),
      icon: teacher ? icon : Icons.person_rounded);
}

/// The signed-in user's @username when their profile has a public page to share (a teacher with a confirmed
/// username, `auth.username` and the public link switched on); null otherwise. Watches the signed-in user.
/// A student shares from My profile once they made it public (the server knows; this row stays teacher-only).
String? myShareableUsername(BuildContext context) {
  final u = context.watch<MyAuthProvider>().currentUser;
  final name = u?.username;
  if (u == null || u.role != 'teacher' || name == null || name.isEmpty || !u.usernameConfirmed) return null;
  if (AppConfig.disableList.contains(kUsernameFeatureKey) || AppConfig.disableList.contains(kPublicLinkFeatureKey)) {
    return null;
  }
  return name;
}

/// "Share my profile link" in the teacher's Profile (D-074). Nothing for other roles, without a username, or while
/// the username is still the auto-filled, unconfirmed one (it has no public page).
class ShareMyProfileTile extends StatelessWidget {
  const ShareMyProfileTile({super.key});

  @override
  Widget build(BuildContext context) {
    final name = myShareableUsername(context);
    final u = context.read<MyAuthProvider>().currentUser;
    if (u == null || name == null) return const SizedBox.shrink();
    return ParentComponent(
      featureKey: kPublicLinkFeatureKey,
      child: AppSettingsTile(
        icon: Icons.ios_share_rounded,
        color: context.colors.primary,
        label: t('مشاركة رابط ملفي', 'Share my profile link'),
        subtitle: 'nextbrain.site/@$name',
        keywords: 'share profile link username مشاركة رابط ملف',
        onTap: () => shareProfileLink(context, username: name, name: u.name),
      ),
    );
  }
}

/// "My profile" on the Account page (D-850): the one profile page, owner view — teachers and students.
class MyProfileTile extends StatelessWidget {
  const MyProfileTile({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.watch<MyAuthProvider>().currentUser?.role;
    if (role != 'teacher' && role != 'student') return const SizedBox.shrink();
    return AppSettingsTile(
      featureKey: kMyProfileFeatureKey,
      icon: Icons.account_circle_rounded,
      color: context.colors.primary,
      label: t('ملفي الشخصي', 'My profile'),
      subtitle: role == 'teacher'
          ? t('صفحتك العامة وأرقامك ومن يرى ماذا', 'Your public page, your figures, who sees what')
          : t('صفحتك، وأنت تختار ما يظهر', 'Your page, and you choose what shows'),
      keywords: 'my profile public page stats ملفي الشخصي صفحة عامة إحصاءات',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfileScreen())),
    );
  }
}
