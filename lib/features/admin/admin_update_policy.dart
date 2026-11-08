// lib/features/admin/admin_update_policy.dart — the update policy model, its rules and its provider (D-309).
//
// ONE policy per platform (GET /app/policy, PUT /app/policy/{platform}, routers/version_router.py over
// services/app_update_policy.py): the latest version, the minimum still allowed, the message users read (ar / en)
// and the link the update button opens. It is a view over what existed before — the newest active app_versions row
// on Android / iOS / web, the live release (or the admin's override) on Windows / macOS / Linux — so nothing is lost
// and old apps keep reading GET /app/version-check unchanged.
//
// [updatePolicyAnswer] is the server's rule (routers/version_router.check_version), used by the screen's live
// preview so the admin sees exactly what each version gets:
//   version < minimum           → blocking ("Update required", no Later)
//   minimum <= version < latest → dismissible ("Later" snoozes 3 days)
//   version >= latest           → nothing
// The legacy flags (force_update / recommend_update on an old row) prompted even the newest version; they are still
// mirrored here and cleared by a save.
library;

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'admin_common.dart' show t;
import 'admin_providers.dart' show AdminBase;

/// Every platform the screen shows, in its order.
const kUpdatePlatforms = ['android', 'ios', 'windows', 'macos', 'linux', 'web'];

/// Native platforms whose prompt needs a link to open (the web build is always current and never asks).
bool updateNeedsLink(String platform) => platform != 'web';

String updatePlatformName(String platform) => switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      'web' => t('الويب', 'Web'),
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => platform,
    };

IconData updatePlatformIcon(String platform) => switch (platform) {
      'android' => Icons.android_rounded,
      'ios' || 'macos' => Icons.apple_rounded,
      'web' => Icons.language_rounded,
      'windows' => Icons.window_rounded,
      'linux' => Icons.terminal_rounded,
      _ => Icons.devices_rounded,
    };

final _semver = RegExp(r'^\d+(\.\d+){0,2}([+-][0-9A-Za-z.\-]+)?$');

bool validUpdateVersion(String v) => _semver.hasMatch(v.trim());

/// Compares the numeric part of two versions (`1.2.3+4` → `[1,2,3]`): negative, zero or positive, like `compareTo`.
int compareUpdateVersions(String a, String b) {
  List<int> parts(String v) => v.trim().split(RegExp(r'[+-]')).first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

enum UpdateAsk { blocking, dismissible, none }

/// What a user on [client] gets — the server's rule (see the header).
UpdateAsk updatePolicyAnswer(String client, {required String? latest, String? minimum, bool legacyForce = false, bool legacyRecommend = false}) {
  final l = (latest ?? '').trim(), m = (minimum ?? '').trim();
  if (!validUpdateVersion(client) || !validUpdateVersion(l)) return UpdateAsk.none;
  if (legacyForce || (validUpdateVersion(m) && compareUpdateVersions(client, m) < 0)) return UpdateAsk.blocking;
  if (legacyRecommend || compareUpdateVersions(client, l) < 0) return UpdateAsk.dismissible;
  return UpdateAsk.none;
}

/// One line of "Who sees what".
class UpdateBand {
  const UpdateBand(this.range, this.ask);

  final String range;
  final UpdateAsk ask;
}

/// The bands users fall in: below the minimum · between · the latest and newer (legacy flags fold them).
List<UpdateBand> updateBands({required String? latest, String? minimum, bool legacyForce = false, bool legacyRecommend = false}) {
  final l = (latest ?? '').trim(), m = (minimum ?? '').trim();
  if (!validUpdateVersion(l)) return const [];
  if (legacyForce) return [UpdateBand(t('كل الإصدارات', 'Every version'), UpdateAsk.blocking)];
  final hasMin = validUpdateVersion(m) && compareUpdateVersions(m, l) <= 0 && compareUpdateVersions(m, '0.0.0') > 0;
  final sameAsLatest = hasMin && compareUpdateVersions(m, l) == 0;
  return [
    if (hasMin) UpdateBand(t('أقدم من $m', 'Older than $m'), UpdateAsk.blocking),
    if (!sameAsLatest)
      UpdateBand(hasMin ? t('من $m إلى ما قبل $l', '$m up to before $l') : t('أقدم من $l', 'Older than $l'), UpdateAsk.dismissible),
    UpdateBand(t('$l وأحدث', '$l and newer'), legacyRecommend ? UpdateAsk.dismissible : UpdateAsk.none),
  ];
}

String updateAskLabel(UpdateAsk a) => switch (a) {
      UpdateAsk.blocking => t('محجوب حتى يحدّث', 'Blocked until they update'),
      UpdateAsk.dismissible => t('تظهر له رسالة ويمكنه التأجيل', 'Asked, can choose Later'),
      UpdateAsk.none => t('لا يظهر له شيء', 'Sees nothing'),
    };

class UpdateRelease {
  const UpdateRelease({required this.version, this.build = 0, this.notesAr, this.notesEn, this.channel = 'website', this.source = 'website', this.downloadUrl, this.effectiveMin});

  final String version;
  final int build;
  final String? notesAr, notesEn, downloadUrl, effectiveMin;
  final String channel, source;

  static UpdateRelease? fromJson(dynamic j) {
    if (j is! Map || '${j['version'] ?? ''}'.isEmpty) return null;
    return UpdateRelease(
      version: '${j['version']}',
      build: j['build_number'] is num ? (j['build_number'] as num).toInt() : 0,
      notesAr: _s(j['notes_ar']),
      notesEn: _s(j['notes_en']),
      channel: _s(j['channel']) ?? 'website',
      source: _s(j['source']) ?? 'website',
      downloadUrl: _s(j['download_url']),
      effectiveMin: _s(j['effective_min_supported']),
    );
  }
}

String? _s(dynamic v) {
  final s = v == null ? '' : '$v'.trim();
  return s.isEmpty ? null : s;
}

/// The values a save sends (and the screen edits).
class UpdatePolicyDraft {
  const UpdatePolicyDraft({this.enabled = true, this.latest = '', this.minimum = '', this.messageAr = '', this.messageEn = '', this.storeUrl = ''});

  final bool enabled;
  final String latest, minimum, messageAr, messageEn, storeUrl;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'latest_version': latest.trim().isEmpty ? null : latest.trim(),
        'min_supported': minimum.trim().isEmpty ? null : minimum.trim(),
        'message_ar': messageAr.trim().isEmpty ? null : messageAr.trim(),
        'message_en': messageEn.trim().isEmpty ? null : messageEn.trim(),
        'store_url': storeUrl.trim().isEmpty ? null : storeUrl.trim(),
      };
}

class UpdatePolicy {
  const UpdatePolicy({
    required this.platform,
    this.kind = 'versions',
    this.enabled = false,
    this.latest,
    this.minimum,
    this.messageAr,
    this.messageEn,
    this.storeUrl,
    this.legacyForce = false,
    this.legacyRecommend = false,
    this.linkOk = false,
    this.historyCount = 0,
    this.overridden = false,
    this.release,
    this.suggestion,
  });

  final String platform;

  /// versions (app_versions rows) · releases (desktop: the live release, or the admin's override)
  final String kind;
  final bool enabled;
  final String? latest, minimum, messageAr, messageEn, storeUrl;
  final bool legacyForce, legacyRecommend, linkOk, overridden;
  final int historyCount;
  final UpdateRelease? release;

  /// A newer live build than the prompt: the smart default ({version, message_ar, message_en, min_supported}).
  final UpdatePolicyDraft? suggestion;

  bool get hasReleaseLink => (release?.downloadUrl ?? '').isNotEmpty;

  factory UpdatePolicy.fromJson(Map<String, dynamic> m) {
    final sug = m['suggestion'];
    return UpdatePolicy(
      platform: '${m['platform'] ?? ''}',
      kind: _s(m['kind']) ?? 'versions',
      enabled: m['enabled'] == true,
      latest: _s(m['latest_version']),
      minimum: _s(m['min_supported']),
      messageAr: _s(m['message_ar']),
      messageEn: _s(m['message_en']),
      storeUrl: _s(m['store_url']),
      legacyForce: m['legacy_force'] == true,
      legacyRecommend: m['legacy_recommend'] == true,
      linkOk: m['link_ok'] == true,
      historyCount: m['history_count'] is num ? (m['history_count'] as num).toInt() : 0,
      overridden: m['overridden'] == true,
      release: UpdateRelease.fromJson(m['release']),
      suggestion: sug is Map && _s(sug['version']) != null
          ? UpdatePolicyDraft(
              latest: '${sug['version']}',
              minimum: _s(sug['min_supported']) ?? '',
              messageAr: _s(sug['message_ar']) ?? '',
              messageEn: _s(sug['message_en']) ?? '',
            )
          : null,
    );
  }

  /// The editor's starting values: what is saved, filled with the smart defaults — a newer live build's version,
  /// minimum and notes when the prompt is off or behind it, its release notes when the message is empty.
  UpdatePolicyDraft startDraft() {
    final s = suggestion;
    final useSuggestion = s != null && !enabled;
    final r = release;
    String pick(String? saved, String? fromSug, String? fromRel) =>
        (saved ?? '').isNotEmpty ? saved! : ((fromSug ?? '').isNotEmpty ? fromSug! : (fromRel ?? ''));
    return UpdatePolicyDraft(
      enabled: enabled || s != null,
      latest: useSuggestion ? s.latest : (latest ?? s?.latest ?? ''),
      minimum: useSuggestion ? s.minimum : (minimum ?? ''),
      messageAr: pick(useSuggestion ? null : messageAr, s?.messageAr, r?.notesAr),
      messageEn: pick(useSuggestion ? null : messageEn, s?.messageEn, r?.notesEn),
      storeUrl: storeUrl ?? '',
    );
  }

  /// Where the update button goes for [draft]: the live build's own link wins, else the admin's link.
  String buttonSource(UpdatePolicyDraft draft) {
    if (hasReleaseLink) {
      final r = release!;
      if (r.source == 'store' || r.channel == 'store') return platform == 'android' ? 'google_play' : 'app_store';
      return r.source == 'website' ? 'website' : r.source;
    }
    if (draft.storeUrl.trim().isEmpty) return 'website';
    return switch (platform) { 'android' => 'google_play', 'ios' => 'app_store', _ => 'custom' };
  }
}

/// Field → message for [d] (empty = valid). [hasReleaseLink]: the live build names its own link already.
Map<String, String> validateUpdatePolicy(String platform, UpdatePolicyDraft d, {bool hasReleaseLink = false}) {
  final out = <String, String>{};
  final l = d.latest.trim(), m = d.minimum.trim(), u = d.storeUrl.trim();
  if (l.isNotEmpty && !validUpdateVersion(l)) out['latest_version'] = t('رقم إصدار غير صالح (مثال 1.2.3)', 'Not a valid version (e.g. 1.2.3)');
  if (d.enabled && l.isEmpty) out['latest_version'] = t('أدخل أحدث إصدار', 'Enter the latest version');
  if (m.isNotEmpty && !validUpdateVersion(m)) {
    out['min_supported'] = t('حد أدنى غير صالح (مثال 1.2.3)', 'Not a valid minimum (e.g. 1.2.3)');
  } else if (m.isNotEmpty && validUpdateVersion(l) && compareUpdateVersions(m, l) > 0) {
    out['min_supported'] = t('الحد الأدنى لا يتجاوز أحدث إصدار', 'The minimum can’t be above the latest version');
  }
  if (u.isNotEmpty && (!u.startsWith('https://') || (Uri.tryParse(u)?.host ?? '').isEmpty)) {
    out['store_url'] = t('الرابط يجب أن يبدأ بـ https://', 'The link must start with https://');
  } else if (d.enabled && u.isEmpty && !hasReleaseLink && updateNeedsLink(platform)) {
    out['store_url'] = t('أضف رابط المتجر أو التنزيل، وإلا فلن يفتح زر التحديث شيئاً',
        'Add the store or download link, or the update button opens nothing');
  }
  return out;
}

class AdminUpdatePolicyProvider extends AdminBase {
  List<UpdatePolicy> items = [];
  String? error;

  UpdatePolicy? of(String platform) => items.where((p) => p.platform == platform).firstOrNull;

  Future<void> load() async {
    final r = await run(() => api.get('/app/policy'));
    if (r is Map && r['platforms'] is List) {
      final byPlatform = {
        for (final x in r['platforms'] as List)
          if (x is Map) '${x['platform']}': UpdatePolicy.fromJson(Map<String, dynamic>.from(x)),
      };
      items = [for (final p in kUpdatePlatforms) byPlatform[p] ?? UpdatePolicy(platform: p)];
      error = null;
    } else {
      error = errorMessage ?? t('تعذّر التحميل', 'Could not load');
    }
    notifyListeners();
  }

  /// Saves one platform; null on success, else the server's {field: message}.
  Future<Map<String, String>?> save(String platform, UpdatePolicyDraft d) async {
    Map<String, String>? fieldErr;
    final r = await call(
      () => api.put('/app/policy/$platform', body: d.toJson()),
      ok: t('تم الحفظ', 'Saved'),
      onError: (ApiException e) {
        final detail = e.body is Map ? (e.body as Map)['detail'] : null;
        if (detail is Map && detail['field'] != null) fieldErr = {'${detail['field']}': e.message};
      },
    );
    if (r is Map) {
      final v = UpdatePolicy.fromJson(Map<String, dynamic>.from(r));
      items = [for (final p in items) p.platform == platform ? v : p];
      notifyListeners();
      return null;
    }
    return fieldErr ?? const {'_': ''};
  }
}
