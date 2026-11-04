// lib/core/deep_link_service.dart
//
// Share links:  https://nextbrain.site/c/<courseId>?ref=<sharerUserId>
// Opening one lands on `/c/<id>?ref=<uid>` (Flutter's default deep linking feeds it to onGenerateRoute).
// Profile links (D-074): https://nextbrain.site/@<username> → `/@<username>` → the public profile page
// (features/shared/public_profile/; parsed by `profileLinkFrom`).
// Organization links (org-flow overhaul): https://nextbrain.site/j/<CODE> opens the join-by-code page with the code
// filled in; https://nextbrain.site/i/<token> opens an invitation (C1). Both open signed out too (the page asks for the
// sign-in itself); [parseOrg] reads them, and a native cold start keeps one in [setPendingOrg] until the guard runs.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../features/shared/public_profile/public_profile.dart' show ProfileLink, profileLinkFrom, profileUrl;
import '../../main.dart';
import 'app_navigator.dart';

class CourseLink {
  final int courseId;
  final int? ref;
  const CourseLink(this.courseId, this.ref);
}

/// A `/j/<CODE>` join link (`kind` j, `value` = the code, upper-cased) or a `/i/<token>` invitation link (`kind` i).
class OrgLink {
  final String kind;
  final String value;
  const OrgLink(this.kind, this.value);

  /// The in-app location of the link (what the router and SignInReturn open).
  String get location => '/$kind/$value';
}

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const siteBase = 'https://nextbrain.site';

  CourseLink? _pending;
  ProfileLink? _pendingProfile;
  OrgLink? _pendingOrg;

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

  /// `/j/ABCD2345XY`, `/i/<token>` or the full URL → OrgLink, else null.
  static OrgLink? parseOrg(String? routeName) {
    if (routeName == null) return null;
    final seg = Uri.tryParse(routeName)?.pathSegments ?? const <String>[];
    if (seg.length != 2) return null;
    if (seg[0] == 'j') {
      final code = seg[1].toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      return code.length >= 4 && code.length <= 40 ? OrgLink('j', code) : null;
    }
    if (seg[0] == 'i' && RegExp(r'^[A-Za-z0-9_-]{8,200}$').hasMatch(seg[1])) return OrgLink('i', seg[1]);
    return null;
  }

  /// `/@ahmed`, `@Ahmed` or `https://nextbrain.site/@ahmed` → ProfileLink, else null (D-074).
  static ProfileLink? parseProfile(String? routeName) => profileLinkFrom(routeName);

  /// Visitor isn't logged in: remember the link, open it right after login (see _Guard in main.dart).
  void setPending(CourseLink l) {
    _pending = l;
    _pendingProfile = null;
    _pendingOrg = null;
  }

  /// Same for a profile link (the last link opened wins).
  void setPendingProfile(ProfileLink l) {
    _pendingProfile = l;
    _pending = null;
    _pendingOrg = null;
  }

  /// Same for an organization link (the last link opened wins).
  void setPendingOrg(OrgLink l) {
    _pendingOrg = l;
    _pending = null;
    _pendingProfile = null;
  }

  void consumePending() {
    final o = _pendingOrg;
    if (o != null) {
      _pendingOrg = null;
      navigatorKey.currentState?.pushNamed(o.location); // ROUTE: org.join_code / org.invitation (the lead registers /j/:code and /i/:token)
      return;
    }
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
