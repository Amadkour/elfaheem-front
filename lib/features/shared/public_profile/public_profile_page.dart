// lib/features/shared/public_profile/public_profile_page.dart
//
// The public profile page behind `https://nextbrain.site/@name` (D-074) and the teacher's "Share my profile link".
//
//   PublicProfileScreen(username:)     loads GET /api/v1/public/u/{username}, draws PublicProfileView; a course card
//                                      opens the usual course page (AppNavigator.openCourse → CourseLinkLoader)
//   shareProfileLink(context, …)       web: the link in a dialog with "Copy link"; apps: the native share sheet
//                                      (copy as the fallback) — the course share link's mechanism
//   ShareMyProfileTile                 the Profile tile, only for a teacher with a CONFIRMED username; kill switches
//                                      `auth.username` + `profile.public_link`
// Routing: main.dart `_router` (`/@name`, signed out → login first, like `/c/<id>`), DeepLinkService, AppNavigator.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_navigator.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/deep_link_service.dart';
import '../../../utils/widget/parent_component.dart';
import '../../admin/admin_common.dart' show t;
import '../../auth/auth_provider.dart';
import '../../auth/username.dart' show kUsernameFeatureKey;
import '../../student/courses/details/components/share_link.dart' show showShareLinkDialog;
import 'public_profile.dart';
import 'public_profile_view.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.username});

  /// With or without "@", any case.
  final String username;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  PublicProfileResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_result != null) setState(() => _result = null);
    final r = await PublicProfileApi.load(widget.username);
    if (mounted) setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final p = _result?.profile;
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
              onPressed: () => shareProfileLink(context, username: p.username, name: p.name),
            ),
        ],
      ),
      child: PublicProfileView(
        result: _result,
        onRetry: _load,
        onBack: () => Navigator.of(context).maybePop(),
        onOpenCourse: (c) {
          final id = int.tryParse(c.id);
          if (id != null) AppNavigator.openCourse(id);
        },
      ),
    );
  }
}

/// Shares `https://nextbrain.site/@username`: on the web the link is shown in a dialog with "Copy link" (the browser
/// has no share sheet), in the apps the native share sheet opens (the link is copied when it cannot).
Future<void> shareProfileLink(BuildContext context, {required String username, required String name}) async {
  if (kIsWeb) {
    await showShareLinkDialog(
      context,
      url: profileUrl(username),
      title: '$name (@$username)',
      heading: t('مشاركة الملف الشخصي', 'Share profile'),
    );
    return;
  }
  final copied = await DeepLinkService.shareProfile(username: username, name: name);
  if (copied) showAppNotice(t('تم نسخ الرابط', 'Link copied'));
}

/// "Share my profile link" in the teacher's Profile (D-074). Nothing for other roles, without a username, or while
/// the username is still the auto-filled, unconfirmed one (it has no public page).
class ShareMyProfileTile extends StatelessWidget {
  const ShareMyProfileTile({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<MyAuthProvider>().currentUser;
    final name = u?.username;
    if (u == null || u.role != 'teacher' || name == null || name.isEmpty || !u.usernameConfirmed) {
      return const SizedBox.shrink();
    }
    if (AppConfig.disableList.contains(kUsernameFeatureKey)) return const SizedBox.shrink();
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
