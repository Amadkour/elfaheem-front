// The chat answer's newer blocks (multi-tenant RAG, FRONT_CONTRACTS "Chat"): `mode`, `chunks`, `actions`, `tool`.
// Pure Dart, defensive: an older server sends none of them (everything defaults to empty / generate) and a block with
// missing keys never throws.
//
//   mode     generate | retrieval | tool | rule | small_talk
//   chunks   [{text, document, document_id, page_from, page_to, section}]   (retrieval: the closest passages)
//   actions  [{page_id, params, label{ar,en}, org_id?}]                       (buttons under the answer, max 4)
//   tool     {name, data}                                                     (name == "refused": plain text)
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/offline/downloads_availability.dart' show kDownloadsAvailable;
import 'package:flutter_education_app/core/routing/app_routes.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, asStr;

enum RagMode { generate, retrieval, tool, rule, smallTalk }

/// The server's `mode` string; anything unknown or absent (an older server) is [RagMode.generate].
RagMode ragModeOf(Object? v) => switch ('${v ?? ''}') {
      'retrieval' => RagMode.retrieval,
      'tool' => RagMode.tool,
      'rule' => RagMode.rule,
      'small_talk' => RagMode.smallTalk,
      _ => RagMode.generate,
    };

/// One passage of a retrieval answer.
class RagChunk {
  const RagChunk({required this.text, this.document = '', this.documentId, this.pageFrom, this.pageTo, this.section = ''});
  final String text;
  final String document;
  final int? documentId;
  final int? pageFrom;
  final int? pageTo;
  final String section;

  factory RagChunk.fromJson(Map<String, dynamic> j) => RagChunk(
        text: asStr(j['text']).trim(),
        document: asStr(j['document']).trim(),
        documentId: _optInt(j['document_id']),
        pageFrom: _optInt(j['page_from']),
        pageTo: _optInt(j['page_to']),
        section: asStr(j['section']).trim(),
      );

  /// "p. 3–4" / "p. 3" (ar: "ص 3–4"); empty when the document has no pages.
  String pageLabel(String lang) {
    final from = pageFrom;
    if (from == null) return '';
    final to = pageTo;
    final range = to != null && to != from ? '$from–$to' : '$from';
    return '${lang == 'ar' ? 'ص' : 'p.'} $range';
  }
}

/// A button under the answer: opens page [pageId] with [params] (D-170), inside organization [orgId] when given.
class RagAction {
  const RagAction({required this.pageId, this.params = const {}, this.labelAr = '', this.labelEn = '', this.orgId});
  final String pageId;
  final Map<String, Object?> params;
  final String labelAr;
  final String labelEn;
  final int? orgId;

  factory RagAction.fromJson(Map<String, dynamic> j) {
    final label = j['label'];
    String ar = '', en = '';
    if (label is Map) {
      ar = asStr(label['ar']).trim();
      en = asStr(label['en']).trim();
    } else if (label is String) {
      ar = en = label.trim();
    }
    return RagAction(
      pageId: asStr(j['page_id']).trim(),
      params: Map<String, Object?>.from(asMap(j['params'])),
      labelAr: ar,
      labelEn: en,
      orgId: _optInt(j['org_id']),
    );
  }

  /// The label in [lang], the other language when it is missing, the page's own description as the last resort.
  String label([String? lang]) {
    final l = lang ?? AppConfig.lang;
    final first = l == 'ar' ? labelAr : labelEn;
    final second = l == 'ar' ? labelEn : labelAr;
    if (first.isNotEmpty) return first;
    if (second.isNotEmpty) return second;
    return AppRoutes.byId(pageId)?.description ?? '';
  }

  /// The URL this button opens ([AppRoutes.location]), or null when it must be hidden: a page id this app does not
  /// know (an older app), a required parameter missing, or a page this platform lacks (Downloads on the web).
  String? get location {
    // a role home on one of its tabs: `home.student/my_courses` → `/dashboard/my-courses` (AppRoutes.tabLocation)
    final slash = pageId.indexOf('/');
    if (slash > 0) {
      final tab = pageId.substring(slash + 1);
      final home = AppRoutes.byId(pageId.substring(0, slash));
      if (home == null || tab.isEmpty || !AppRoutes.homes.any((h) => h.id == home.id)) return null;
      return AppRoutes.tabLocation(home.path, tab);
    }
    final route = AppRoutes.byId(pageId);
    if (route == null) return null;
    if (pageId == AppRoutes.downloads.id && !kDownloadsAvailable) return null;
    for (final p in route.params) {
      final v = params[p];
      if (v == null || '$v'.isEmpty) return null;
    }
    try {
      return AppRoutes.location(pageId, params);
    } catch (_) {
      return null;
    }
  }
}

/// The buttons to draw: those that resolve to a location and have a label, at most [max].
List<RagAction> ragVisibleActions(List<RagAction> actions, {int max = 4}) {
  final out = <RagAction>[];
  for (final a in actions) {
    if (a.location == null || a.label().isEmpty) continue;
    out.add(a);
    if (out.length == max) break;
  }
  return out;
}

/// A tool's result: [name] (`my_subscriptions`, `my_courses`, `my_schedule`, `my_progress`, `refused`, …) and its raw
/// [data]; the cards read it defensively ([ragToolKind]).
class RagTool {
  const RagTool({required this.name, this.data = const {}});
  final String name;
  final Map<String, dynamic> data;

  factory RagTool.fromJson(Map<String, dynamic> j) => RagTool(name: asStr(j['name']).trim(), data: asMap(j['data']));

  bool get refused => name == 'refused';
}

enum RagToolKind { subscriptions, courses, schedule, progress, other }

/// Which card a tool gets, from its name (substring match: `my_subscriptions`, `subscription_status` …).
RagToolKind ragToolKind(String name) {
  final n = name.toLowerCase();
  if (n.contains('subscri')) return RagToolKind.subscriptions;
  if (n.contains('schedule') || n.contains('calendar') || n.contains('timetable')) return RagToolKind.schedule;
  if (n.contains('progress')) return RagToolKind.progress;
  if (n.contains('course')) return RagToolKind.courses;
  return RagToolKind.other;
}

/// Everything beyond the classic answer fields.
class RagAnswerExtras {
  const RagAnswerExtras({this.mode = RagMode.generate, this.chunks = const [], this.actions = const [], this.tool});
  final RagMode mode;
  final List<RagChunk> chunks;
  final List<RagAction> actions;
  final RagTool? tool;

  static const none = RagAnswerExtras();

  factory RagAnswerExtras.fromJson(Map<String, dynamic> j) {
    final tool = j['tool'];
    return RagAnswerExtras(
      mode: ragModeOf(j['mode']),
      chunks: [for (final c in asMapList(j['chunks'])) RagChunk.fromJson(c)]..removeWhere((c) => c.text.isEmpty),
      actions: [for (final a in asMapList(j['actions'])) RagAction.fromJson(a)]..removeWhere((a) => a.pageId.isEmpty),
      tool: tool is Map ? RagTool.fromJson(Map<String, dynamic>.from(tool)) : null,
    );
  }
}

int? _optInt(Object? v) => v == null ? null : asInt(v);

// ── defensive readers for tool data ──────────────────────────────────────────────────────────────────────────

/// The first non-empty string among [keys] of [m] (a `{ar, en}` map is read in the app language).
String ragPickStr(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    if (v is num) return '$v';
    if (v is Map) {
      final s = asStr(v[AppConfig.lang]).trim();
      if (s.isNotEmpty) return s;
      final o = asStr(v['en']).trim();
      if (o.isNotEmpty) return o;
    }
  }
  return '';
}

/// The first parseable instant among [keys] (naive strings are UTC, like every server time).
DateTime? ragPickTime(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) {
      final s = v.trim();
      final zoned = s.endsWith('Z') || s.contains('+') || RegExp(r'\d-\d\d:\d\d$').hasMatch(s);
      final dateOnly = RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(s);
      final d = DateTime.tryParse(zoned ? s : (dateOnly ? '${s}T00:00:00Z' : '${s}Z'));
      if (d != null) return d.toUtc();
    }
  }
  return null;
}

/// A fraction 0..1 from a percentage (0..100) or a fraction; null when absent or not a number.
double? ragPickFraction(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    if (n == null || n.isNaN) continue;
    final f = n > 1 ? n / 100 : n;
    return f.clamp(0.0, 1.0);
  }
  return null;
}

/// The list of maps of a tool's data: `data[key]` for the first of [keys] that is a list, then `items` / `results`;
/// empty otherwise.
List<Map<String, dynamic>> ragToolItems(Map<String, dynamic> data, [List<String> keys = const []]) {
  for (final k in [...keys, 'items', 'results']) {
    final v = data[k];
    if (v is List) return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
  }
  return const [];
}

/// Whole calendar days from [now] to [end] (negative once past), in UTC.
int ragDaysLeft(DateTime end, DateTime now) {
  final a = DateTime.utc(end.toUtc().year, end.toUtc().month, end.toUtc().day);
  final b = DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day);
  return a.difference(b).inDays;
}
