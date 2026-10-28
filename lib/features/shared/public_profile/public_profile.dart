// lib/features/shared/public_profile/public_profile.dart
//
// Profile links by username (D-074): `https://nextbrain.site/@ahmed` opens that person's public profile, the way a
// course share link `https://nextbrain.site/c/<id>?ref=<uid>` opens a course (DeepLinkService).
//
//   ProfileLink / profileLinkFrom   `/@ahmed`, `@Ahmed`, `https://nextbrain.site/@ahmed` → the normalized username
//   profileUrl(username)            the link a teacher shares
//   PublicProfile.fromJson          GET /api/v1/public/u/{username}, read defensively (missing keys never throw)
//   PublicProfileApi.load           → PublicProfileResult (found · notFound · disabled · failed)
//
// Pure apart from PublicProfileApi; tests: test/auth/profile_link_test.dart. The page: public_profile_page.dart.
library;

import '../../../core/api_client.dart';
import '../../auth/username.dart' show UsernameRules;
import '../../student/models.dart' show CourseModel;

/// Kill switch of the teacher's "Share my profile link" and of the profile page (also `auth.username`).
const kPublicLinkFeatureKey = 'profile.public_link';

/// The host a profile link may point at (the course links' `DeepLinkService.siteBase`).
const kProfileSiteBase = 'https://nextbrain.site';
const _siteHosts = {'nextbrain.site', 'www.nextbrain.site'};

class ProfileLink {
  const ProfileLink(this.username);

  /// Normalized: lower-case, no "@".
  final String username;

  @override
  bool operator ==(Object other) => other is ProfileLink && other.username == username;

  @override
  int get hashCode => username.hashCode;

  @override
  String toString() => 'ProfileLink(@$username)';
}

/// `/@ahmed`, `@Ahmed`, `/@ahmed/`, `%40ahmed`, `https://nextbrain.site/@ahmed?x=1` → ProfileLink('ahmed'); anything
/// else (a course link, `/ahmed`, another host, an invalid or reserved name, extra path segments) → null.
ProfileLink? profileLinkFrom(String? routeName) {
  final raw = routeName?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.hasScheme) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (!_siteHosts.contains(uri.host.toLowerCase())) return null;
  }
  final List<String> seg;
  try {
    seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  } catch (_) {
    return null; // a malformed %-escape
  }
  if (seg.length != 1 || !seg.first.startsWith('@')) return null;
  final name = seg.first.substring(1).toLowerCase(); // exactly one "@"
  if (name.startsWith('@') || !UsernameRules.isValid(name)) return null;
  return ProfileLink(name);
}

/// The public link of [username] (with or without "@").
String profileUrl(String username) => '$kProfileSiteBase/@${UsernameRules.normalize(username)}';

class PublicProfile {
  const PublicProfile({
    required this.kind,
    required this.id,
    required this.name,
    required this.username,
    this.imageUrl,
    this.bio,
    this.headline,
    this.specializationAr,
    this.specializationEn,
    this.experienceYears = 0,
    this.coursesCount = 0,
    this.courses = const [],
  });

  /// "teacher" (full profile + courses); any other kind gets the minimal card.
  final String kind;
  final int id;
  final String name;
  final String username;
  final String? imageUrl;
  final String? bio;
  final String? headline;
  final String? specializationAr;
  final String? specializationEn;
  final int experienceYears;
  final int coursesCount;
  final List<CourseModel> courses;

  bool get isTeacher => kind == 'teacher';

  String? specialization(String lang) {
    final ar = specializationAr, en = specializationEn;
    final v = lang == 'ar' ? (ar ?? en) : (en ?? ar);
    return (v == null || v.trim().isEmpty) ? headline : v;
  }

  static String? _str(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// A course card of the payload; the `teacher` block is dropped (the profile owner IS the teacher) and a card
  /// that does not parse is skipped rather than failing the page.
  static CourseModel? _course(Object? j) {
    if (j is! Map) return null;
    try {
      final m = Map<String, dynamic>.from(j)..remove('teacher');
      return CourseModel.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  static PublicProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    final raw = _str(j['username']);
    final username = raw == null ? '' : UsernameRules.normalize(raw);
    if (id <= 0 || username.isEmpty) return null;
    final spec = j['specialization'] is Map ? j['specialization'] as Map : const {};
    final courses = <CourseModel>[
      for (final c in (j['courses'] is List ? j['courses'] as List : const [])) ?_course(c),
    ];
    return PublicProfile(
      kind: _str(j['kind']) ?? 'person',
      id: id,
      name: _str(j['name']) ?? '@$username',
      username: username,
      imageUrl: _str(j['image_url']),
      bio: _str(j['bio']),
      headline: _str(j['headline']),
      specializationAr: _str(spec['name_ar']),
      specializationEn: _str(spec['name_en']),
      experienceYears: _int(j['experience_years']),
      coursesCount: j['courses_count'] == null ? courses.length : _int(j['courses_count']),
      courses: courses,
    );
  }
}

enum PublicProfileStatus { found, notFound, disabled, failed }

class PublicProfileResult {
  const PublicProfileResult(this.status, {this.profile, this.message});

  final PublicProfileStatus status;
  final PublicProfile? profile;

  /// The server's message for [PublicProfileStatus.failed] (already user-safe).
  final String? message;
}

class PublicProfileApi {
  PublicProfileApi._();

  /// GET /api/v1/public/u/{username} — sent without the account's token (a public page; a 401 must never send the
  /// visitor to the login screen). 404 → notFound (also an older server without the route), 403
  /// `public_profiles_disabled` → disabled.
  static Future<PublicProfileResult> load(String username, {ApiClient? api}) async {
    final name = UsernameRules.normalize(username);
    try {
      final j = await (api ?? ApiClient()).get('/api/v1/public/u/${Uri.encodeComponent(name)}', auth: false);
      final p = PublicProfile.fromJson(j);
      return p == null
          ? const PublicProfileResult(PublicProfileStatus.notFound)
          : PublicProfileResult(PublicProfileStatus.found, profile: p);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const PublicProfileResult(PublicProfileStatus.notFound);
      if (e.statusCode == 403 && e.code == 'public_profiles_disabled') {
        return const PublicProfileResult(PublicProfileStatus.disabled);
      }
      return PublicProfileResult(PublicProfileStatus.failed, message: e.message);
    }
  }
}
