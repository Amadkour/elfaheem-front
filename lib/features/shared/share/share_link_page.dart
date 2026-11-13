// lib/features/shared/share/share_link_page.dart — where a share link of the one scheme lands (D-307,
// core/share/app_links.dart): `/s/<kind>/<id>` and `/s/page/<pageId>?…` (main.dart's router; `/c/<id>` keeps its own
// loader when signed in).
//
//   signed in   the target opens in this page's place: a course (its loader, which records the share click), a
//               roadmap (the course page on its Path tab), a lesson / session (the course page on Sessions), a
//               meeting (the Schedule page with its detail), a teacher (the public profile), a page of the route
//               registry (by name), a shared recording (`/s/record/<token>`, D-312: the Records player, or "not
//               available" when the person may not watch it). Every target applies its own permission rules.
//   signed out  a public preview (`GET /api/v1/public/share/{kind}/{id}`, auth: false): what a visitor of the catalogue
//   / guest     could see already — a public course's name, picture and teacher; a meeting or a private course shows
//               only its kind — with Sign in / Create account. The link is kept (SignInReturn), so the person lands
//               on the target right after signing in.
//
// The preview body is the plain-values [ShareLinkPreviewView] (test/ui/share_link_preview_layout_test.dart).
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../core/routing/app_routes.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_icons.dart';
import '../../../design/app_share_sheet.dart';
import '../../../utils/web_entry_route.dart' show SignInReturn;
import '../../admin/admin_common.dart' show t;
import '../../auth/auth_provider.dart';
import '../../student/courses/details/course_link_loader.dart';
import '../course_profile/course_profile_hub.dart' show CoursePageLoader;
import '../guest/guest_state.dart';
import '../public_profile/public_profile_page.dart' show PublicProfileScreen;
import '../live/companion/companion_incoming.dart' show CompanionIncoming;
import '../records/record_guest_page.dart' show GuestMediaKind, GuestRecordPage;
import '../records/records_share.dart' show SharedRecordPage;

/// The public card of a link (`GET /api/v1/public/share/{kind}/{id}`).
class ShareLinkPreview {
  const ShareLinkPreview({this.isPublic = false, this.title, this.subtitle, this.description, this.imageUrl, this.courseId, this.username});

  final bool isPublic;
  final String? title, subtitle, description, imageUrl, username;
  final int? courseId;

  static String? _s(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  factory ShareLinkPreview.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return ShareLinkPreview(
      isPublic: m['public'] == true,
      title: _s(m['title']),
      subtitle: _s(m['subtitle']),
      description: _s(m['description']),
      imageUrl: _s(m['image_url']),
      courseId: m['course_id'] is num ? (m['course_id'] as num).toInt() : null,
      username: _s(m['username']),
    );
  }

  static Future<ShareLinkPreview> load(AppLink link, {ApiClient? api}) async => ShareLinkPreview.fromJson(
      await (api ?? ApiClient()).get('/api/v1/public/share/${link.kind.segment}/${link.kind == AppLinkKind.record ? link.token : link.id}',
          auth: false));
}

/// The pages a `/s/page/<id>` link may open: every registry page but the sign-in pages and the role homes (a link
/// never opens another role's home; the person's own home is the fallback).
bool sharePageAllowed(String id) =>
    AppRoutes.byId(id) != null && !id.startsWith('auth.') && !id.startsWith('home.') && !id.startsWith('link.');

class ShareLinkPage extends StatefulWidget {
  const ShareLinkPage({super.key, required this.link});
  final AppLink link;

  @override
  State<ShareLinkPage> createState() => _ShareLinkPageState();
}

class _ShareLinkPageState extends State<ShareLinkPage> {
  ShareLinkPreview? _preview;
  String? _error;
  bool _loading = true;

  AppLink get _link => widget.link;

  bool get _signedIn => context.read<MyAuthProvider>().isAuthenticated && !GuestState.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_signedIn) return _openTarget();
    if (_link.kind == AppLinkKind.video) return _openTarget(); // a guest link: the player, signed in or not
    if (_link.kind == AppLinkKind.page || _link.kind == AppLinkKind.companion) {
      setState(() => _loading = false);
      return;
    }
    try {
      final p = await ShareLinkPreview.load(_link);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _loading = false;
      });
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _error = e is StateError ? t('هذا الرابط غير متاح', 'This link is not available') : appErrorMessage(e);
      _loading = false;
    });
  }

  void _replace(Widget page, {String? name, Object? arguments}) => Navigator.of(context).pushReplacement(
      MaterialPageRoute(settings: RouteSettings(name: name, arguments: arguments), builder: (_) => page));

  Future<void> _openTarget() async {
    final nav = Navigator.of(context);
    final home = context.read<MyAuthProvider>().homeRoute;
    final id = _link.id ?? 0;
    switch (_link.kind) {
      case AppLinkKind.course:
        return _replace(CourseLinkLoader(courseId: id, ref: _link.ref), name: '/course-by-id');
      case AppLinkKind.roadmap:
        return _replace(CoursePageLoader(courseId: id, tab: 'path'), name: '/course-detail', arguments: id);
      case AppLinkKind.meeting:
        nav.pushReplacementNamed('/calendar', arguments: {'meeting_id': id});
        return;
      case AppLinkKind.record:
        return _replace(SharedRecordPage(token: _link.token ?? ''), name: '/records/shared');
      case AppLinkKind.video: // main.dart's router opens a video guest link itself; kept for a direct push
        return _replace(GuestRecordPage(token: _link.token ?? '', kind: GuestMediaKind.video), name: '/s/video');
      case AppLinkKind.companion:
        final secret = _link.token ?? '';
        nav.pushReplacementNamed(home);
        unawaited(CompanionIncoming.instance.openFromLink(secret).catchError((Object e) {
          showAppNotice(appErrorMessage(e), error: true);
        }));
        return;
      case AppLinkKind.page:
        final pid = _link.pageId ?? '';
        String? to;
        if (sharePageAllowed(pid)) {
          try {
            to = AppRoutes.location(pid, _link.params, _extraQuery(pid));
          } on ArgumentError {
            to = null;
          }
        }
        nav.pushReplacementNamed(to ?? home);
        return;
      case AppLinkKind.material:
      case AppLinkKind.session:
      case AppLinkKind.teacher:
        try {
          final p = await ShareLinkPreview.load(_link);
          if (!mounted) return;
          if (_link.kind == AppLinkKind.teacher) {
            if (p.username == null) throw StateError('no profile');
            return _replace(PublicProfileScreen(username: p.username!), name: '/@${p.username}');
          }
          final cid = p.courseId;
          if (cid == null) throw StateError('no course');
          return _replace(CoursePageLoader(courseId: cid, tab: 'sessions'), name: '/course-detail', arguments: cid);
        } catch (e) {
          _fail(e);
        }
    }
  }

  /// The parameters of a page link that are not path parameters of the page (its query, e.g. `?tab=`).
  Map<String, String>? _extraQuery(String pid) {
    final names = AppRoutes.byId(pid)?.params ?? const [];
    final q = {for (final e in _link.params.entries) if (!names.contains(e.key)) e.key: e.value};
    return q.isEmpty ? null : q;
  }

  void _signIn(String route) {
    SignInReturn.pending = _link.route; // back here after the sign-in, then on to the target
    if (GuestState.active) GuestState.instance.stop();
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final (kind, icon) = appLinkKindLabel(_link.kind);
    final p = _preview;
    final signedIn = context.read<MyAuthProvider>().isAuthenticated && !GuestState.active;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: signedIn && _error == null
            ? const AppListSkeleton(items: 3)
            : ShareLinkPreviewView(
                kind: kind,
                icon: icon,
                loading: _loading,
                error: _error,
                title: p?.title,
                subtitle: p?.subtitle,
                description: p?.description,
                imageUrl: p?.imageUrl,
                isPublic: p?.isPublic ?? false,
                note: _link.kind == AppLinkKind.meeting
                    ? t('معك رابط ضيوف؟ افتحه للانضمام دون حساب.', 'Have a guest link? Open it to join without an account.')
                    : null,
                onRetry: _run,
                onSignIn: signedIn ? null : () => _signIn('/login'),
                onRegister: signedIn ? null : () => _signIn('/register'),
                onHome: signedIn ? () => Navigator.of(context).pushReplacementNamed(context.read<MyAuthProvider>().homeRoute) : null,
              ),
      ),
    );
  }
}

/// The preview of a link from plain values: the kind, the public card (or "Sign in to see it"), Sign in / Create
/// account (signed out), Home (signed in, when the target could not be opened).
class ShareLinkPreviewView extends StatelessWidget {
  const ShareLinkPreviewView({
    super.key,
    required this.kind,
    required this.icon,
    this.loading = false,
    this.error,
    this.title,
    this.subtitle,
    this.description,
    this.imageUrl,
    this.isPublic = false,
    this.note,
    this.onRetry,
    this.onSignIn,
    this.onRegister,
    this.onHome,
  });

  final String kind;
  final IconData icon;
  final bool loading, isPublic;
  final String? error, title, subtitle, description, imageUrl, note;
  final VoidCallback? onRetry, onSignIn, onRegister, onHome;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    final heading = title ?? (error != null ? t('هذا الرابط غير متاح', 'This link is not available') : t('سجّل الدخول لعرضه', 'Sign in to see it'));
    final body = loading
        ? const SizedBox(height: 220, child: AppListSkeleton(items: 2))
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (imageUrl != null && error == null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: c.inputBg)),
                ),
              )
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.card)),
                  child: Icon(error != null ? Icons.link_off_rounded : icon, color: ink, size: AppIconSize.lg),
                ),
              ),
            const SizedBox(height: AppSpace.md),
            Text(kind, style: AppType.overline(context).copyWith(color: ink)),
            const SizedBox(height: AppSpace.xxs),
            Text(heading, style: AppType.headline(context)),
            if (subtitle != null && error == null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(subtitle!, style: AppType.bodyStrong(context)),
            ],
            if (description != null && error == null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(description!, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
            ],
            const SizedBox(height: AppSpace.sm),
            Text(
              error ??
                  (isPublic
                      ? t('سجّل الدخول أو أنشئ حساباً مجانياً لتكمل إليه مباشرة.', 'Sign in or create a free account to continue straight to it.')
                      : t('هذا المحتوى خاص بأعضائه. سجّل الدخول بالحساب المدعو لفتحه.', 'This is for its members. Sign in with the invited account to open it.')),
              style: AppType.body(context),
            ),
            if (note != null && error == null) ...[
              const SizedBox(height: AppSpace.sm),
              AppBanner(icon: Icons.public_rounded, text: note!, color: c.primary),
            ],
            const SizedBox(height: AppSpace.lg),
            if (onSignIn != null)
              AppButton.primary(
                key: const ValueKey('share_link.sign_in'),
                label: t('تسجيل الدخول للمتابعة', 'Sign in to continue'),
                icon: DirIcons.login,
                expand: true,
                size: AppButtonSize.lg,
                onPressed: onSignIn,
              ),
            if (onRegister != null) ...[
              const SizedBox(height: AppSpace.xs),
              AppButton.secondary(
                key: const ValueKey('share_link.register'),
                label: t('إنشاء حساب جديد', 'Create an account'),
                icon: Icons.person_add_alt_1_rounded,
                expand: true,
                onPressed: onRegister,
              ),
            ],
            if (error != null && onRetry != null) ...[
              const SizedBox(height: AppSpace.xs),
              AppButton.ghost(label: t('إعادة المحاولة', 'Retry'), icon: Icons.refresh_rounded, expand: true, onPressed: onRetry),
            ],
            if (onHome != null) ...[
              const SizedBox(height: AppSpace.xs),
              AppButton.secondary(label: t('الرئيسية', 'Home'), icon: Icons.home_rounded, expand: true, onPressed: onHome),
            ],
          ]);
    return LayoutBuilder(builder: (context, box) {
      final g = AppSpace.gutter(box.maxWidth);
      // centred in the window; scrolls when it does not fit (a phone in landscape, a large text size)
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: g, vertical: AppSpace.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? (box.maxHeight - AppSpace.xl * 2).clamp(0, double.infinity) : 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppCard(padding: const EdgeInsets.all(AppSpace.lg), child: body),
            ),
          ),
        ),
      );
    });
  }
}
