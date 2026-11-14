// lib/features/profile/public_profile/public_profile.dart
//
// Profile links by username (D-074): `https://alfheemacademy.com/@ahmed` opens that person's public profile, the way a
// course share link `https://alfheemacademy.com/c/<id>?ref=<uid>` opens a course (DeepLinkService).
//
//   ProfileLink / profileLinkFrom   `/@ahmed`, `@Ahmed`, `https://alfheemacademy.com/@ahmed` → the normalized username
//   profileUrl(username)            the link a person shares
//   PublicProfile.fromJson          GET /api/v1/public/u/{username}, read defensively (missing keys never throw)
//   PublicProfileApi.load           → PublicProfileResult (found · notFound · disabled · failed)
//   PublicTeacherStats / PublicLearning / PublicCourseBrief / PublicGrowthPoint   the figures of the ONE profile
//                                   page (D-850 – D-855): a teacher's aggregates, a student's opt-in learning summary
//   MyPublicProfile + PublicProfileApi.mine / save   the owner's view: GET / PUT /api/v1/me/public-profile (who
//                                   sees what, the page as visitors see it)
//
// Pure apart from PublicProfileApi; tests: test/auth/profile_link_test.dart, test/ui/public_profile_stats_test.dart.
// The page: public_profile_page.dart.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/username.dart' show UsernameRules;
import 'package:flutter_education_app/features/home/student/models.dart' show CourseModel;

/// Kill switch of the "Share my profile link" and of the profile page (also `auth.username`).
const kPublicLinkFeatureKey = 'profile.public_link';

/// Kill switch of a teacher's figures on the profile page (the server drops them too, D-852).
const kPublicStatsFeatureKey = 'profile.public_stats';

/// Kill switch of the Account page's "My profile" row (the one profile page, owner view, D-850).
const kMyProfileFeatureKey = 'profile.my_profile';

/// The host a profile link may point at (the course links' `DeepLinkService.siteBase`).
const kProfileSiteBase = 'https://alfheemacademy.com';
const _siteHosts = {'alfheemacademy.com', 'www.alfheemacademy.com'};

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

/// `/@ahmed`, `@Ahmed`, `/@ahmed/`, `%40ahmed`, `https://alfheemacademy.com/@ahmed?x=1`, and the web app's own
/// `/app/@ahmed` / `https://alfheemacademy.com/app/@ahmed` (D-270 base path, D-854) → ProfileLink('ahmed'); anything
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
  List<String> seg;
  try {
    seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  } catch (_) {
    return null; // a malformed %-escape
  }
  if (seg.length == 2 && seg.first == 'app') seg = seg.sublist(1); // the web app's base path (D-270)
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
    this.stats,
    this.growth = const [],
    this.learning,
    this.completedCourses = const [],
    this.sections = const {},
  });

  /// "teacher" (full profile + courses + figures), "student" (opt-in sections); any other kind gets the minimal card.
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

  /// A teacher's figures (null: switched off by the teacher or the platform, or an older server).
  final PublicTeacherStats? stats;

  /// A teacher's new students per month, oldest first (empty = not shown).
  final List<PublicGrowthPoint> growth;

  /// A student's learning summary (null unless the student chose to show it).
  final PublicLearning? learning;

  /// The published courses a student finished (only when the student chose to show them).
  final List<PublicCourseBrief> completedCourses;

  /// Which sections the person shows ({bio: true, stats: false, …}); empty from an older server.
  final Map<String, bool> sections;

  bool get isTeacher => kind == 'teacher';
  bool get isStudent => kind == 'student';

  String? specialization(String lang) {
    final ar = specializationAr, en = specializationEn;
    final v = lang == 'ar' ? (ar ?? en) : (en ?? ar);
    return (v == null || v.trim().isEmpty) ? headline : v;
  }

  /// A teacher's course card of the payload; the `teacher` block is dropped (the profile owner IS the teacher) and a
  /// card that does not parse is skipped rather than failing the page.
  static CourseModel? _course(Object? j) {
    if (j is! Map) return null;
    try {
      final m = Map<String, dynamic>.from(j)..remove('teacher');
      return CourseModel.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  static List _list(Object? v) => v is List ? v : const [];

  static PublicProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _pInt(j['id']);
    final raw = _pStr(j['username']);
    final username = raw == null ? '' : UsernameRules.normalize(raw);
    if (id <= 0 || username.isEmpty) return null;
    final spec = j['specialization'] is Map ? j['specialization'] as Map : const {};
    final courses = <CourseModel>[for (final c in _list(j['courses'])) ?_course(c)];
    return PublicProfile(
      kind: _pStr(j['kind']) ?? 'person',
      id: id,
      name: _pStr(j['name']) ?? '@$username',
      username: username,
      imageUrl: _pStr(j['image_url']),
      bio: _pStr(j['bio']),
      headline: _pStr(j['headline']),
      specializationAr: _pStr(spec['name_ar']),
      specializationEn: _pStr(spec['name_en']),
      experienceYears: _pInt(j['experience_years']),
      coursesCount: j['courses_count'] == null ? courses.length : _pInt(j['courses_count']),
      courses: courses,
      stats: PublicTeacherStats.fromJson(j['stats']),
      growth: [for (final g in _list(j['growth'])) ?PublicGrowthPoint.fromJson(g)],
      learning: PublicLearning.fromJson(j['learning']),
      completedCourses: [for (final c in _list(j['completed_courses'])) ?PublicCourseBrief.fromJson(c)],
      sections: _bools(j['sections']),
    );
  }
}

Map<String, bool> _bools(Object? j) =>
    j is Map ? {for (final e in j.entries) if (e.value is bool) '${e.key}': e.value as bool} : const {};

int _pInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

double? _pDouble(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

String? _pStr(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// A course named on the profile page: a teacher's top course (with its students) or a course a student finished.
class PublicCourseBrief {
  const PublicCourseBrief({required this.id, this.nameAr, this.nameEn, this.imageUrl, this.students = 0});

  final int id;
  final String? nameAr, nameEn, imageUrl;
  final int students;

  String name(String lang) => (lang == 'ar' ? (nameAr ?? nameEn) : (nameEn ?? nameAr)) ?? '';

  static PublicCourseBrief? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _pInt(j['id']);
    if (id <= 0) return null;
    return PublicCourseBrief(
      id: id,
      nameAr: _pStr(j['name_ar']),
      nameEn: _pStr(j['name_en']),
      imageUrl: _pStr(j['image_url']),
      students: _pInt(j['students']),
    );
  }
}

/// One month of a teacher's growth: [month] is "YYYY-MM", [students] the new students that month.
class PublicGrowthPoint {
  const PublicGrowthPoint(this.month, this.students);

  final String month;
  final int students;

  /// The 15th of that month in UTC (for AppTime's month name), null when the month does not parse.
  DateTime? get date {
    final p = month.split('-');
    if (p.length != 2) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return (y == null || m == null || m < 1 || m > 12) ? null : DateTime.utc(y, m, 15);
  }

  static PublicGrowthPoint? fromJson(Object? j) {
    if (j is! Map || j['month'] is! String) return null;
    return PublicGrowthPoint(j['month'] as String, _pInt(j['students']));
  }
}

/// A teacher's figures, computed and cached on the server (aggregates only, never a student's name, D-852).
class PublicTeacherStats {
  const PublicTeacherStats({
    this.studentsTaught = 0,
    this.activeLearners = 0,
    this.courses = 0,
    this.lessons = 0,
    this.hours = 0,
    this.rating,
    this.ratingsCount = 0,
    this.reviewsCount = 0,
    this.completionRate,
    this.certificates = 0,
    this.liveSessions = 0,
    this.responseHours,
    this.topCourses = const [],
    this.since,
    this.isNew = false,
  });

  final int studentsTaught, activeLearners, courses, lessons, ratingsCount, reviewsCount, certificates, liveSessions;
  final double hours;

  /// null = no rating yet, or the teacher hides reviews.
  final double? rating;

  /// Percent; null = too few enrollments to say.
  final int? completionRate;

  /// Median first-reply time in hours; null = too few replies to say.
  final double? responseHours;
  final List<PublicCourseBrief> topCourses;

  /// The year the account started.
  final int? since;

  /// A young account (or no student yet): the page says "New" instead of a misleading 0.
  final bool isNew;

  static PublicTeacherStats? fromJson(Object? j) {
    if (j is! Map) return null;
    final since = _pInt(j['since']);
    return PublicTeacherStats(
      studentsTaught: _pInt(j['students_taught']),
      activeLearners: _pInt(j['active_learners']),
      courses: _pInt(j['courses']),
      lessons: _pInt(j['lessons']),
      hours: _pDouble(j['hours']) ?? 0,
      rating: _pDouble(j['rating']),
      ratingsCount: _pInt(j['ratings_count']),
      reviewsCount: _pInt(j['reviews_count']),
      completionRate: _pDouble(j['completion_rate'])?.round(),
      certificates: _pInt(j['certificates']),
      liveSessions: _pInt(j['live_sessions']),
      responseHours: _pDouble(j['response_hours']),
      topCourses: [for (final c in PublicProfile._list(j['top_courses'])) ?PublicCourseBrief.fromJson(c)],
      since: since > 0 ? since : null,
      isNew: j['is_new'] == true,
    );
  }
}

/// A student's learning summary, shown only when the student chose to (D-851).
class PublicLearning {
  const PublicLearning({
    this.streakDays = 0,
    this.coursesCompleted = 0,
    this.coursesInProgress = 0,
    this.certificates = 0,
    this.since,
  });

  final int streakDays, coursesCompleted, coursesInProgress, certificates;
  final int? since;

  static PublicLearning? fromJson(Object? j) {
    if (j is! Map) return null;
    final since = _pInt(j['since']);
    return PublicLearning(
      streakDays: _pInt(j['streak_days']),
      coursesCompleted: _pInt(j['courses_completed']),
      coursesInProgress: _pInt(j['courses_in_progress']),
      certificates: _pInt(j['certificates']),
      since: since > 0 ? since : null,
    );
  }
}

/// The owner's view of their one profile page (GET / PUT /api/v1/me/public-profile, D-850).
class MyPublicProfile {
  const MyPublicProfile({
    required this.isPublic,
    required this.fields,
    required this.available,
    this.username,
    this.usernameConfirmed = false,
    this.live = false,
    this.link,
    this.blocked,
    this.profile,
  });

  /// The person's choice (visitors see the page only when [live]).
  final bool isPublic;
  final Map<String, bool> fields;

  /// The sections this role may show, in page order.
  final List<String> available;
  final String? username;
  final bool usernameConfirmed;

  /// Visitors can open the page now.
  final bool live;
  final String? link;

  /// Why the page cannot be public yet: `username_unconfirmed` · `links_disabled` · `account_incomplete` · null.
  final String? blocked;

  /// The page exactly as visitors see it (built even while private, so the owner previews it).
  final PublicProfile? profile;

  static MyPublicProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final st = j['settings'] is Map ? j['settings'] as Map : const {};
    return MyPublicProfile(
      isPublic: st['is_public'] == true,
      fields: _bools(st['fields']),
      available: [for (final a in PublicProfile._list(j['available'])) if (a is String) a],
      username: _pStr(j['username']),
      usernameConfirmed: j['username_confirmed'] == true,
      live: j['live'] == true,
      link: _pStr(j['link']),
      blocked: _pStr(j['blocked']),
      profile: PublicProfile.fromJson(j['profile']),
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

  static const _mine = '/api/v1/me/public-profile';

  /// GET /api/v1/me/public-profile — the owner's page and who-sees-what. Throws ApiException.
  static Future<MyPublicProfile?> mine({ApiClient? api}) async =>
      MyPublicProfile.fromJson(await (api ?? ApiClient()).get(_mine));

  /// PUT /api/v1/me/public-profile — only the given parts change. Throws ApiException.
  static Future<MyPublicProfile?> save({bool? isPublic, Map<String, bool>? fields, ApiClient? api}) async =>
      MyPublicProfile.fromJson(await (api ?? ApiClient()).put(_mine, body: {
        'is_public': ?isPublic,
        'fields': ?fields,
      }));
}
