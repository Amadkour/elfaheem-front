// lib/features/parent/signup/pa_child_api.dart — the parent creates the child's account; the child signs in once with
// a 6-digit code (docs/redesign/api/child_code.md, backend WP7, kill switch `parent.create_child`).
//
//   POST /api/v1/parent/children                      → the child + the first code (shown ONCE)
//   POST /api/v1/parent/children/{id}/login-code      → a new code (the old unused one stops working)
//   GET  /api/v1/parent/children/{id}/login-code      → is a code active, and for how long (never the code)
// [PaChildDraft] keeps what the join flow asked about the child until the parent has a session (the server needs one).
library;

import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kill switch of "add your child" and its codes.
const kParentCreateChildKey = 'parent.create_child';

bool paCreateChildOn() => !AppConfig.disableList.contains(kParentCreateChildKey);

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _str(Object? v) => v == null ? '' : '$v';

/// A sign-in code as the server sends it once.
class PaLoginCode {
  const PaLoginCode({required this.code, required this.display, this.expiresAt, this.ttlSeconds, this.shareAr = '', this.shareEn = ''});

  final String code, display, shareAr, shareEn;
  final DateTime? expiresAt;
  final int? ttlSeconds;

  /// The WhatsApp text in the current language (the other one when it is empty).
  String get share {
    final ar = AppConfig.lang == 'ar';
    final first = ar ? shareAr : shareEn;
    return first.isNotEmpty ? first : (ar ? shareEn : shareAr);
  }

  /// How long it lasts, in whole hours.
  int get hours => ((ttlSeconds ?? 0) / 3600).round();

  static PaLoginCode? tryParse(Object? v) {
    if (v is! Map) return null;
    final code = _str(v['code']);
    if (code.isEmpty) return null;
    return PaLoginCode(
      code: code,
      display: _str(v['code_display']).isEmpty ? code : _str(v['code_display']),
      expiresAt: DateTime.tryParse(_str(v['expires_at']))?.toUtc(),
      ttlSeconds: _int(v['ttl_seconds']),
      shareAr: _str(v['share_text_ar']),
      shareEn: _str(v['share_text_en']),
    );
  }
}

/// The child the parent just created.
class PaCreatedChild {
  const PaCreatedChild({required this.id, required this.name, required this.firstName, this.gradeAr = '', this.gradeEn = '', this.code});

  final int id;
  final String name, firstName, gradeAr, gradeEn;
  final PaLoginCode? code;

  String get grade => AppConfig.lang == 'ar' ? (gradeAr.isNotEmpty ? gradeAr : gradeEn) : (gradeEn.isNotEmpty ? gradeEn : gradeAr);

  static PaCreatedChild? tryParse(Object? v) {
    if (v is! Map) return null;
    final c = v['child'];
    if (c is! Map || _int(c['id']) == null) return null;
    return PaCreatedChild(
      id: _int(c['id'])!,
      name: _str(c['name']),
      firstName: _str(c['first_name']).isEmpty ? _str(c['name']).split(' ').first : _str(c['first_name']),
      gradeAr: _str(c['grade_name_ar']),
      gradeEn: _str(c['grade_name_en']),
      code: PaLoginCode.tryParse(v['login_code']),
    );
  }
}

/// Is a code active for a child (the code itself is never sent back).
class PaCodeStatus {
  const PaCodeStatus({required this.active, this.secondsLeft});

  final bool active;
  final int? secondsLeft;
}

class PaChildApi {
  PaChildApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  /// Throws [ApiException] (422 `child_name_required`, `study_grade_required`, 429 `child_create_limit`, …).
  Future<PaCreatedChild?> create(PaChildDraft d) async =>
      PaCreatedChild.tryParse(await _api.post('/api/v1/parent/children', body: d.toBody()));

  Future<PaLoginCode?> newCode(int childId) async =>
      PaLoginCode.tryParse(await _api.post('/api/v1/parent/children/$childId/login-code', body: const {}));

  Future<PaCodeStatus> status(int childId) async {
    final r = await _api.get('/api/v1/parent/children/$childId/login-code');
    return r is Map ? PaCodeStatus(active: r['active'] == true, secondsLeft: _int(r['seconds_left'])) : const PaCodeStatus(active: false);
  }
}

/// What the parent told us about the child, kept on this device until it is sent (7 days at most, then dropped).
class PaChildDraft {
  PaChildDraft({
    this.firstName = '',
    this.lastName = '',
    this.country,
    this.stageId,
    this.gradeId,
    this.track,
    this.delivery,
    this.gender,
    this.at,
  });

  static const prefsKey = 'pa_child_draft';
  static const ttl = Duration(days: 7);

  String firstName, lastName;
  String? country, track, delivery, gender;
  int? stageId, gradeId;
  DateTime? at;

  bool get ready => firstName.trim().isNotEmpty && stageId != null && gradeId != null;

  Map<String, dynamic> toBody() => {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'curriculum_country_code': ?country,
        'stage_id': ?stageId,
        'grade_id': ?gradeId,
        'track': track,
        'delivery': delivery,
        'gender': gender,
      };

  Map<String, dynamic> toJson() => {...toBody(), 'at': at?.toUtc().toIso8601String()};

  static PaChildDraft fromJson(Map<String, dynamic> j) => PaChildDraft(
        firstName: _str(j['first_name']),
        lastName: _str(j['last_name']),
        country: j['curriculum_country_code'] as String?,
        stageId: _int(j['stage_id']),
        gradeId: _int(j['grade_id']),
        track: j['track'] as String?,
        delivery: j['delivery'] as String?,
        gender: j['gender'] as String?,
        at: DateTime.tryParse(_str(j['at']))?.toUtc(),
      );

  static Future<PaChildDraft?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(prefsKey);
      if (raw == null) return null;
      final d = fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      final at = d.at;
      if (at == null || DateTime.now().toUtc().difference(at) > ttl || !d.ready) {
        await p.remove(prefsKey);
        return null;
      }
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    at = DateTime.now().toUtc();
    try {
      final p = await SharedPreferences.getInstance();
      if (firstName.trim().isEmpty) {
        await p.remove(prefsKey);
      } else {
        await p.setString(prefsKey, jsonEncode(toJson()));
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(prefsKey);
    } catch (_) {}
  }
}
