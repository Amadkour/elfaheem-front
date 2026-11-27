// lib/features/onboarding/join/join_draft.dart — the join flow's answers (Learning Hub F5, D-1323, PLAN §3.3), kept in
// SharedPreferences under `join_draft` so a reload, the login and the registration find them again:
//   role · country · stage + grade (+ track) or a teacher's teaching levels · online / in-person · area (+ address)
//   · name + phone · a parent's child code · a student's interests (category ids, owner 2026-11-27).
// [filters] is what the explorer sends to GET /courses (CONTRACT §4); [studyProfile] prefills the registration's
// study step. Kept on this device only and never sent before the account is created; a draft older than 7 days (or
// without `at`) is dropped unread, logout clears it, and a parent's name / phone / child code go once the child is
// linked (D-1326).
library;

import 'dart:convert';

import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/auth/register_levels_step.dart' show TeachingLevel;
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart' show StudyProfile;
import 'package:shared_preferences/shared_preferences.dart';

/// The roles `/join?role=` accepts (an organization goes to `/start/institution`).
const kJoinRoles = ['student', 'teacher', 'parent'];

/// `online` · `in_person` · null = either.
const kJoinDeliveries = ['online', 'in_person'];

Map<String, dynamic> _areaJson(EduArea a) =>
    {'id': a.id, 'key': a.key, 'name_ar': a.nameAr, 'name_en': a.nameEn, 'level': a.level, 'has_children': a.hasChildren};

EduArea? _area(Object? j) => j is Map && j['id'] is num ? EduArea.fromJson(Map<String, dynamic>.from(j)) : null;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String _str(Object? v) => v is String ? v : '';

class JoinDraft {
  JoinDraft({
    this.role = 'student',
    this.country,
    this.stageId,
    this.gradeId,
    this.trackKey,
    List<TeachingLevel>? teachingLevels,
    this.delivery,
    this.area1,
    this.area2,
    this.address = '',
    this.name = '',
    this.phone = '',
    this.childCode = '',
    this.at,
    List<int>? interestIds,
  })  : teachingLevels = teachingLevels ?? [],
        interestIds = interestIds ?? [];

  static const prefsKey = 'join_draft';

  /// How long a draft is kept on the device.
  static const ttl = Duration(days: 7);

  /// Test hooks.
  static Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance;
  static DateTime Function() clock = DateTime.now;

  /// When it was last saved (UTC); set by [save].
  DateTime? at;

  String role;
  String? country;
  int? stageId, gradeId;
  String? trackKey;
  List<TeachingLevel> teachingLevels;
  String? delivery;
  EduArea? area1, area2;
  String address, name, phone, childCode;

  /// The fields a student picked (sent with the registration's study profile).
  List<int> interestIds;

  bool get isTeacher => role == 'teacher';
  bool get isParent => role == 'parent';

  /// The chosen area: the city when there is one, else the governorate.
  EduArea? get area => area2 ?? area1;

  /// A teacher's levels, or the student's (child's) stage.
  bool get hasLevels => isTeacher ? teachingLevels.isNotEmpty : stageId != null;

  void setCountry(String? c) {
    if (c == country) return;
    country = c;
    // the levels and the areas are the country's own rows
    stageId = gradeId = null;
    trackKey = null;
    teachingLevels = [];
    area1 = area2 = null;
  }

  /// GET /courses filters (CONTRACT §4). A teacher's draft filters by the first stage they teach.
  Map<String, dynamic> get filters {
    final stage = isTeacher ? (teachingLevels.isEmpty ? null : teachingLevels.first.stageId) : stageId;
    final grade = isTeacher
        ? (teachingLevels.length == 1 ? teachingLevels.first.gradeId : null)
        : gradeId;
    return {
      'country': ?country,
      'stage_id': ?stage,
      'grade_id': ?grade,
      'delivery': ?delivery,
      'area_id': ?area?.id,
    };
  }

  /// The registration's study step, prefilled (a student only).
  /// `governorate` carries the level-1 area's key so the study step can name a city (it looks the city up under it).
  StudyProfile get studyProfile => StudyProfile(
      countryCode: country, stageId: stageId, gradeId: gradeId, areaId: area?.id, governorate: area1?.key, track: trackKey,
      interestIds: interestIds.isEmpty ? null : List.of(interestIds));

  Map<String, dynamic> toJson() => {
        'role': role,
        'country': country,
        'stage_id': stageId,
        'grade_id': gradeId,
        'track': trackKey,
        'teaching_levels': [for (final l in teachingLevels) l.toJson()],
        'delivery': delivery,
        'area1': area1 == null ? null : _areaJson(area1!),
        'area2': area2 == null ? null : _areaJson(area2!),
        'address': address,
        'name': name,
        'phone': phone,
        'child_code': childCode,
        'interest_ids': interestIds,
        'at': at?.toUtc().toIso8601String(),
      };

  static JoinDraft fromJson(Object? j) {
    if (j is! Map) return JoinDraft();
    final role = _str(j['role']);
    final delivery = _str(j['delivery']);
    final tl = j['teaching_levels'];
    return JoinDraft(
      role: kJoinRoles.contains(role) ? role : 'student',
      country: _str(j['country']).isEmpty ? null : _str(j['country']).toUpperCase(),
      stageId: _int(j['stage_id']),
      gradeId: _int(j['grade_id']),
      trackKey: _str(j['track']).isEmpty ? null : _str(j['track']),
      teachingLevels: tl is List
          ? [for (final e in tl) if (e is Map) TeachingLevel.fromJson(Map<String, dynamic>.from(e))]
          : null,
      delivery: kJoinDeliveries.contains(delivery) ? delivery : null,
      area1: _area(j['area1']),
      area2: _area(j['area2']),
      address: _str(j['address']),
      name: _str(j['name']),
      phone: _str(j['phone']),
      childCode: _str(j['child_code']),
      at: DateTime.tryParse(_str(j['at']))?.toUtc(),
      interestIds: j['interest_ids'] is List ? [for (final x in j['interest_ids'] as List) ?_int(x)] : null,
    );
  }

  // ── Store ────────────────────────────────────────────────────────────────────

  /// The saved draft, or null when there is none, it cannot be read, or it is older than [ttl] (or has no `at`): such
  /// a draft is removed.
  static Future<JoinDraft?> load() async {
    try {
      final p = await prefs();
      final raw = p.getString(prefsKey);
      if (raw == null) return null;
      JoinDraft? d;
      try {
        d = fromJson(jsonDecode(raw));
      } catch (_) {}
      final at = d?.at;
      if (d == null || at == null || clock().toUtc().difference(at) > ttl) {
        await p.remove(prefsKey);
        return null;
      }
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    at = clock().toUtc();
    try {
      await (await prefs()).setString(prefsKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await prefs()).remove(prefsKey);
    } catch (_) {}
  }
}
