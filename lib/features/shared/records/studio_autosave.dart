// lib/features/shared/records/studio_autosave.dart — where the Studio's work in progress is kept (D-826).
//
//   The server copy   GET|PUT …/project, as before (D-593), now with a revision: every doc carries `rev`, a save sends
//                     the `base` it was made from, and a server that holds a newer one answers 409 project_conflict
//                     with it (two tabs or two devices no longer overwrite each other in silence).
//   The device copy   every save is written here FIRST (SharedPreferences, ≤ 512 KB like the server's), marked
//                     `dirty` until the server has it. A lost connection, a closed tab or a crash keeps the work; the
//                     next open sends it.
//   studioPickProject which copy opens the Studio; studioProjectConflict when the person must choose (D-831);
//   studioConflictOf what a 409 carries (D-832). Pure: test/org/studio_project_test.dart.
library;

import 'dart:convert';

import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:shared_preferences/shared_preferences.dart';

/// The device copy of one project.
class StudioLocalCopy {
  const StudioLocalCopy({required this.doc, required this.dirty, this.base = 0});

  final Map<String, dynamic> doc;

  /// Not on the server yet.
  final bool dirty;

  /// The server revision it was made from.
  final int base;
}

/// A doc's revision (0: none).
int studioDocRev(Map<String, dynamic>? doc) {
  final v = doc?['rev'];
  return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
}

/// Which copy the Studio opens: the device copy when it holds work the server never got and the server has nothing
/// newer than what that work was made from; otherwise the server's. (doc, fromDevice)
(Map<String, dynamic>?, bool) studioPickProject({Map<String, dynamic>? server, StudioLocalCopy? local, bool serverFailed = false}) {
  if (local != null && local.dirty && (serverFailed || server == null || studioDocRev(server) <= local.base)) return (local.doc, true);
  if (serverFailed && local != null) return (local.doc, true);
  return (server, false);
}

/// Unsent device work that the server has moved past (edited offline here, saved on another device since): neither copy
/// may simply win — the person chooses, as on a 409 (D-831).
bool studioProjectConflict({Map<String, dynamic>? server, StudioLocalCopy? local, bool serverFailed = false}) =>
    !serverFailed && server != null && local != null && local.dirty && studioDocRev(server) > local.base;

/// The export jobs a saved doc remembers (`export.jobs`, D-905).
List<int> studioDocJobs(Map<String, dynamic>? doc) {
  final x = doc?['export'];
  final j = x is Map ? x['jobs'] : null;
  return j is List ? [for (final v in j) if (v is num) v.toInt() else ?int.tryParse('$v')] : const [];
}

/// What a 409 project_conflict carries: the stored doc and its revision (null rev: the answer could not be read —
/// the caller must not guess a revision from it, D-832). [body] may be a Map or a JSON string.
({Map<String, dynamic>? doc, int? rev}) studioConflictOf(dynamic body) {
  final m = ApiException.asMap(body);
  final d = m == null ? null : (m['detail'] is Map ? m['detail'] as Map : m);
  final doc = d != null && d['doc'] is Map ? Map<String, dynamic>.from(d['doc'] as Map) : null;
  return (doc: doc, rev: doc == null ? null : studioDocRev(doc));
}

abstract final class StudioLocalStore {
  static const _max = 512 * 1024;
  static String _key(String kind, int id) => 'studio.project.$kind.$id';

  static Future<StudioLocalCopy?> read(String kind, int id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(kind, id));
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map || j['doc'] is! Map) return null;
      return StudioLocalCopy(
        doc: Map<String, dynamic>.from(j['doc'] as Map),
        dirty: j['dirty'] == true,
        base: j['base'] is num ? (j['base'] as num).toInt() : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// The exports started on this source and not yet seen through (D-905): a reload, a crash or closing the tab finds
  /// them again and follows them.
  static Future<List<int>> readJobs(String kind, int id) async {
    try {
      final p = await SharedPreferences.getInstance();
      return [for (final v in p.getStringList('studio.jobs.$kind.$id') ?? const <String>[]) ?int.tryParse(v)];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeJobs(String kind, int id, List<int> jobs) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (jobs.isEmpty) {
        await p.remove('studio.jobs.$kind.$id');
      } else {
        await p.setStringList('studio.jobs.$kind.$id', [for (final j in jobs) '$j']);
      }
    } catch (_) {/* the project doc keeps them too */}
  }

  static Future<void> write(String kind, int id, Map<String, dynamic>? doc, {required bool dirty, required int base}) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (doc == null) {
        await p.remove(_key(kind, id));
        return;
      }
      final raw = jsonEncode({'doc': doc, 'dirty': dirty, 'base': base});
      if (raw.length > _max) return;
      await p.setString(_key(kind, id), raw);
    } catch (_) {/* a full or blocked store: the server copy still goes */}
  }
}
