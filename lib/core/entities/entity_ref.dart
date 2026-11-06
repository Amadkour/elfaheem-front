// lib/core/entities/entity_ref.dart — the four connected entities (D-290) and the reference to one of them.
//
//   EntityRef(EntityKind.student, 12, label: 'Sara Ali')     a student, with what a list row already knows
//   ref.toToken()                                            'student:12' (the `?open=` value of a list URL)
//   EntityRef.tryParse('course:5')                          EntityRef(course, 5), null for anything else
//   EntityLinkRequest.offer('/admin_dashboard/admin-students?open=student:12')
//                                                            a list URL opened with `?open=`: the next master-detail
//                                                            list that mounts takes it ([EntityLinkRequest.take])
//   ?open=course:5,student:12                                the same, opened from that course (it stays the context)
//
// Pure Dart (plus the app language for [EntityRef.name]): main.dart's router reads it, so it stays light.
library;

import 'package:flutter_education_app/config/app_config.dart';

/// The entities of the connected detail views (`/api/v1/entities/<plural>/<id>`, D-290).
enum EntityKind {
  student('students'),
  course('courses'),
  teacher('teachers'),
  category('categories');

  const EntityKind(this.plural);

  /// The server's path segment.
  final String plural;

  static EntityKind? tryParse(String? name) {
    for (final k in values) {
      if (k.name == name || k.plural == name) return k;
    }
    return null;
  }
}

/// One student / course / teacher / category. Equal by kind + id; the label and image are only what the caller
/// already knows (a list row's name), drawn at once while the summary loads.
class EntityRef {
  const EntityRef(this.kind, this.id, {this.label, this.labelEn, this.imageUrl});

  final EntityKind kind;
  final int id;

  /// The name (a person's name; a course's or category's Arabic name).
  final String? label;

  /// A course's or category's English name (null for people).
  final String? labelEn;
  final String? imageUrl;

  /// The name in the app language, falling back to the other one.
  String get name {
    final ar = label?.trim() ?? '', en = labelEn?.trim() ?? '';
    if (AppConfig.lang == 'en') return en.isNotEmpty ? en : ar;
    return ar.isNotEmpty ? ar : en;
  }

  bool get isPerson => kind == EntityKind.student || kind == EntityKind.teacher;

  String toToken() => '${kind.name}:$id';

  /// `student:12` → the ref; null for anything else (a typo in a URL opens nothing).
  static EntityRef? tryParse(String? token) {
    if (token == null) return null;
    final i = token.indexOf(':');
    if (i <= 0) return null;
    final kind = EntityKind.tryParse(token.substring(0, i));
    final id = int.tryParse(token.substring(i + 1));
    if (kind == null || id == null || id <= 0) return null;
    return EntityRef(kind, id);
  }

  EntityRef withLabel({String? label, String? labelEn, String? imageUrl}) => EntityRef(kind, id,
      label: label ?? this.label, labelEn: labelEn ?? this.labelEn, imageUrl: imageUrl ?? this.imageUrl);

  @override
  bool operator ==(Object other) => other is EntityRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => toToken();
}

/// A list URL opened with `?open=<kind>:<id>` (a refresh, a shared link, the browser's Forward): the router offers it
/// here and the first master-detail list that mounts within [maxAge] opens that panel. Forgotten after one take.
/// `?open=<from>,<kind>:<id>` also names what it was opened from.
class EntityLinkRequest {
  EntityLinkRequest._();

  static const Duration maxAge = Duration(seconds: 30);
  static EntityRef? _pending;
  static EntityRef? _pendingFrom;
  static DateTime _at = DateTime.now();

  /// The value of `open` for [ref], opened from [from].
  static String token(EntityRef ref, {EntityRef? from}) =>
      from == null ? ref.toToken() : '${from.toToken()},${ref.toToken()}';

  /// Reads `open` from [location] (a path with its query, or a full URL); nothing when it names no entity.
  static void offer(String? location) {
    final uri = location == null ? null : Uri.tryParse(location);
    final parts = (uri?.queryParameters['open'] ?? '').split(',');
    final ref = EntityRef.tryParse(parts.last);
    if (ref == null) return;
    _pending = ref;
    _pendingFrom = parts.length > 1 ? EntityRef.tryParse(parts.first) : null;
    _at = DateTime.now();
  }

  /// What the pending ref was opened from: read before [take].
  static EntityRef? get takeFrom => _pendingFrom;

  /// The pending ref (once), or null.
  static EntityRef? take() {
    final p = _pending;
    _pending = null;
    if (p == null || DateTime.now().difference(_at) > maxAge) return null;
    return p;
  }

  static EntityRef? get peek => _pending;
}
