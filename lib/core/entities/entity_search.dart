// lib/core/entities/entity_search.dart — phase 8 of D-290: global search hits, saved list views and shareable list
// links (contract: ../back/docs/master_detail/CONTRACT.md "Phase 8 additions").
//
//   EntitySearchResult.fromJson(GET /entities/search)   groups of hits, each a ref the viewer may open
//   EntitySavedView.fromJson(GET /entities/views item)  one person's named query of one list
//   entityQueryParams(query) / entityQueryFromParams(…)  a list's query on its URL (`q`, `sort`, `f.<key>`): the
//                                                        shareable link of a filtered list
library;

import 'entity_models.dart';
import 'entity_ref.dart';

/// One hit of the global search: the ref (name, image) and a second line.
class EntitySearchHit {
  const EntitySearchHit(this.ref, {this.sub});

  final EntityRef ref;

  /// @username of a person, the teacher of a course.
  final String? sub;
}

class EntitySearchGroup {
  const EntitySearchGroup(this.kind, this.total, this.items);

  final EntityKind kind;
  final int total;
  final List<EntitySearchHit> items;
}

class EntitySearchResult {
  const EntitySearchResult(this.query, this.groups);

  final String query;
  final List<EntitySearchGroup> groups;

  bool get isEmpty => groups.every((g) => g.items.isEmpty);

  /// Every hit in display order (the keyboard walks this list).
  List<EntitySearchHit> get flat => [for (final g in groups) ...g.items];

  factory EntitySearchResult.fromJson(Object? json) {
    final j = entityMap(json) ?? const {};
    final groups = <EntitySearchGroup>[];
    for (final g in entityMaps(j['groups'])) {
      final kind = EntityKind.values.where((k) => k.name == g['kind']).firstOrNull;
      if (kind == null) continue; // a kind this app does not know yet
      final items = <EntitySearchHit>[];
      for (final i in entityMaps(g['items'])) {
        final id = entityIntOrNull(i['id']);
        if (id == null) continue;
        final person = kind == EntityKind.student || kind == EntityKind.teacher;
        final ref = person
            ? EntityRef(kind, id, label: entityString(i['name']), imageUrl: entityString(i['image_url']))
            : EntityRef(kind, id,
                label: entityString(i['name_ar']), labelEn: entityString(i['name_en']), imageUrl: entityString(i['image_url']));
        final user = entityString(i['username']);
        items.add(EntitySearchHit(ref, sub: person ? (user == null ? null : '@$user') : entityString(i['teacher_name'])));
      }
      if (items.isNotEmpty) groups.add(EntitySearchGroup(kind, entityIntOrNull(g['total']) ?? items.length, items));
    }
    return EntitySearchResult(entityString(j['query']) ?? '', groups);
  }
}

/// One saved view of a list.
class EntitySavedView {
  const EntitySavedView({required this.id, required this.listId, required this.name, required this.query});

  final int id;
  final String listId;
  final String name;

  /// search, sort, filter (page 1, the list's own page size).
  final EntityListQuery query;

  factory EntitySavedView.fromJson(Map<String, dynamic> j) {
    final q = entityMap(j['query']) ?? const {};
    final f = entityMap(q['filter']) ?? const {};
    return EntitySavedView(
      id: entityIntOrNull(j['id']) ?? 0,
      listId: entityString(j['list_id']) ?? '',
      name: entityString(j['name']) ?? '',
      query: EntityListQuery(
        search: entityString(q['search']) ?? '',
        sort: entityString(q['sort']),
        filter: {for (final e in f.entries) e.key: '${e.value}'},
      ),
    );
  }

  /// What POST /entities/views stores of [q].
  static Map<String, dynamic> queryJson(EntityListQuery q) => {
        if (q.search.trim().isNotEmpty) 'search': q.search.trim(),
        if (q.sort != null && q.sort!.isNotEmpty) 'sort': q.sort,
        if (q.filter.isNotEmpty) 'filter': q.filter,
      };
}

/// Prefix of a filter on a list's URL: `?f.state=active`.
const entityFilterParam = 'f.';

/// [q] as URL parameters (empty values left out; [defaultSort] is not written).
Map<String, String> entityQueryParams(EntityListQuery q, {String? defaultSort}) => {
      if (q.search.trim().isNotEmpty) 'q': q.search.trim(),
      if (q.sort != null && q.sort!.isNotEmpty && q.sort != defaultSort) 'sort': q.sort!,
      for (final e in q.filter.entries)
        if (e.value.isNotEmpty) '$entityFilterParam${e.key}': e.value,
    };

/// The list's query from URL [params], or null when they name none. [sorts] / [filterKeys] are what the list knows:
/// anything else is ignored (a hand-edited link opens the list, never an error).
EntityListQuery? entityQueryFromParams(Map<String, String> params, EntityListQuery base,
    {List<String> sorts = const [], Set<String> filterKeys = const {}}) {
  final search = params['q']?.trim() ?? '';
  final sort = params['sort'];
  final filter = <String, String>{
    for (final e in params.entries)
      if (e.key.startsWith(entityFilterParam) &&
          filterKeys.contains(e.key.substring(entityFilterParam.length)) &&
          e.value.isNotEmpty)
        e.key.substring(entityFilterParam.length): e.value,
  };
  final knownSort = sort != null && sorts.contains(sort);
  if (search.isEmpty && !knownSort && filter.isEmpty) return null;
  return base.copyWith(search: search, sort: knownSort ? sort : base.sort, filter: filter, page: 1);
}

/// The value of `list` on a list's URL for [q] (null when [q] is the default: no parameter).
String? entityListToken(EntityListQuery q, {String? defaultSort}) {
  final p = entityQueryParams(q, defaultSort: defaultSort);
  return p.isEmpty ? null : Uri(queryParameters: p).query;
}

/// The parameters packed in a `list` value (empty for null or garbage).
Map<String, String> entityListParams(String? token) {
  if (token == null || token.isEmpty) return const {};
  try {
    return Uri.splitQueryString(token);
  } catch (_) {
    return const {};
  }
}
