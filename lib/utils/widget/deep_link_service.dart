// lib/core/deep_link_service.dart
//
// Share links:  https://nextbrain.site/c/<courseId>?ref=<sharerUserId>
// Opening one lands on `/c/<id>?ref=<uid>` (Flutter's default deep linking feeds it to onGenerateRoute).
// Profile links (D-074): https://nextbrain.site/@<username> → `/@<username>` → the public profile page
// (features/profile/public_profile/; parsed by `profileLinkFrom`).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile.dart' show ProfileLink, profileLinkFrom, profileUrl;
import '../../main.dart';
import 'app_navigator.dart';

class CourseLink {
  final int courseId;
  final int? ref;
  const CourseLink(this.courseId, this.ref);
}

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const siteBase = 'https://nextbrain.site';

  CourseLink? _pending;
  ProfileLink? _pendingProfile;

  /// `/c/12?ref=5` (or a full URL) → CourseLink, else null.
  static CourseLink? parse(String? routeName) {
    if (routeName == null) return null;
    final uri = Uri.tryParse(routeName);
    if (uri == null) return null;
    final seg = uri.pathSegments;
    if (seg.length == 2 && seg[0] == 'c') {
      final id = int.tryParse(seg[1]);
      if (id != null) return CourseLink(id, int.tryParse(uri.queryParameters['ref'] ?? ''));
    }
    return null;
  }

  /// `/@ahmed`, `@Ahmed` or `https://nextbrain.site/@ahmed` → ProfileLink, else null (D-074).
  static ProfileLink? parseProfile(String? routeName) => profileLinkFrom(routeName);

  /// Visitor isn't logged in: remember the link, open it right after login (see _Guard in main.dart).
  void setPending(CourseLink l) {
    _pending = l;
    _pendingProfile = null;
  }

  /// Same for a profile link (the last link opened wins).
  void setPendingProfile(ProfileLink l) {
    _pendingProfile = l;
    _pending = null;
  }

  void consumePending() {
    final p = _pendingProfile;
    if (p != null) {
      _pendingProfile = null;
      AppNavigator.openProfile(p.username);
      return;
    }
    final l = _pending;
    if (l == null) return;
    _pending = null;
    AppNavigator.openCourse(l.courseId, ref: l.ref);
  }

  /// Records "this user opened a link shared by <ref>". Fire-and-forget; never throws.
  Future<void> recordClick(int courseId, int? ref) async {
    try {
      await ApiClient().post('/api/v1/courses/$courseId/share-click', body: {
        'ref': ?ref,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
      });
    } catch (_) {}
  }

  /// The link carries the SHARER'S user id, which is what the backend stores as `sharer_id`.
  static String buildLink(int courseId, int? myUserId) =>
      '$siteBase/c/$courseId${myUserId != null ? '?ref=$myUserId' : ''}';

  /// A profile link through the native share sheet; falls back to copying it (like [shareCourse]).
  /// Returns true when the link was copied instead of shared.
  static Future<bool> shareProfile({required String username, required String name}) async {
    final link = profileUrl(username);
    try {
      // ignore: deprecated_member_use
      await Share.share('$name\n$link', subject: name);
      return false;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      return true;
    }
  }

  /// Native share sheet; falls back to copying the link (desktop browsers).
  /// Returns true when the link was copied instead of shared.
  static Future<bool> shareCourse({required int courseId, required String courseName}) async {
    final ctx = navigatorKey.currentContext;
    final uid = ctx?.read<MyAuthProvider>().currentUser?.id;
    final link = buildLink(courseId, uid);
    try {
      // ignore: deprecated_member_use
      await Share.share('$courseName\n$link', subject: courseName);
      return false;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      return true;
    }
  }
}
