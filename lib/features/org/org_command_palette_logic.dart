// lib/features/org/org_command_palette_logic.dart
//
// The organization dashboard's command palette (D-103, spec §5) — the PURE part, unit-tested in
// test/org/org_command_palette_test.dart (fixture test/fixtures/payloads/org_search.json):
//
//   OrgPaletteEntry          a page the person can open (the shell's sections and sub-pages, built by the caller)
//   OrgPaletteDept / Person  GET /api/v1/org/orgs/{id}/search hits; OrgSearchResult.fromJson
//   orgPaletteNormalize      Arabic-aware folding (hamza forms · ta marbuta · alef maqsura · diacritics) + lower case
//   orgPaletteScore          exact · prefix · word prefix · contains · group / keywords (lower = better, null = no)
//   orgPaletteFilterPages    the page hits, best first
//   OrgPaletteRecent         what was opened lately (device-local, per organization), orgPaletteRemember
//   OrgPaletteController     the query → page hits at once, server hits 250 ms after typing stops (q ≥ 2, the stale
//                            request cancelled and its answer ignored), the flat row list the arrow keys walk
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;

import 'package:flutter_education_app/config/app_config.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

// ═════════════════════════════════════════════════════════════════════════════
//  Data
// ═════════════════════════════════════════════════════════════════════════════

/// A page in the palette. [key] is stable (e.g. `people/members`): the recent list keeps it.
class OrgPaletteEntry {
  const OrgPaletteEntry({
    required this.key,
    required this.label,
    required this.icon,
    required this.onOpen,
    this.group,
    this.keywords = const [],
  });

  final String key;
  final String label;
  final IconData icon;

  /// The section it lives in ("People"), shown under the label and searched too.
  final String? group;

  /// More words that find it (both languages are fine).
  final List<String> keywords;

  /// Runs after the palette closed.
  final VoidCallback onOpen;
}

class OrgPaletteDept {
  const OrgPaletteDept({required this.id, this.unitType = 'dept', this.nameAr = '', this.nameEn = ''});
  final int id;

  /// dept · program.
  final String unitType;
  final String nameAr, nameEn;

  String get name => _t(nameAr.isNotEmpty ? nameAr : nameEn, nameEn.isNotEmpty ? nameEn : nameAr);
  String get key => '$unitType:$id';

  Map<String, dynamic> toJson() => {'id': id, 'unit_type': unitType, 'name_ar': nameAr, 'name_en': nameEn};

  static OrgPaletteDept? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    if (id == null) return null;
    return OrgPaletteDept(
      id: id,
      unitType: '${j['unit_type'] ?? 'dept'}',
      nameAr: '${j['name_ar'] ?? ''}',
      nameEn: '${j['name_en'] ?? ''}',
    );
  }
}

class OrgPalettePerson {
  const OrgPalettePerson({required this.userId, this.name = '', this.avatarUrl, this.memberRole = '', this.deptId});
  final int userId;
  final String name;
  final String? avatarUrl;

  /// student · teacher · teacher_assistant · admin_assistant · org_admin.
  final String memberRole;
  final int? deptId;

  String get key => 'person:$userId';

  Map<String, dynamic> toJson() =>
      {'user_id': userId, 'name': name, 'avatar_url': avatarUrl, 'member_role': memberRole, 'dept_id': deptId};

  static OrgPalettePerson? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['user_id']);
    if (id == null) return null;
    final url = j['avatar_url'];
    return OrgPalettePerson(
      userId: id,
      name: '${j['name'] ?? ''}',
      avatarUrl: url is String && url.isNotEmpty ? url : null,
      memberRole: '${j['member_role'] ?? ''}',
      deptId: _int(j['dept_id']),
    );
  }
}

/// The member role in words.
String orgPaletteRoleLabel(String role) => switch (role) {
      'student' => _t('طالب', 'Student'),
      'teacher' => _t('مدرس', 'Teacher'),
      'teacher_assistant' => _t('معيد', 'Teaching assistant'),
      'admin_assistant' => _t('مساعد إداري', 'Admin assistant'),
      'org_admin' => _t('مدير المؤسسة', 'Organization admin'),
      _ => role,
    };

class OrgSearchResult {
  const OrgSearchResult({this.departments = const [], this.people = const []});
  final List<OrgPaletteDept> departments;
  final List<OrgPalettePerson> people;

  static const empty = OrgSearchResult();

  factory OrgSearchResult.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    final d = m['departments'], p = m['people'];
    return OrgSearchResult(
      departments: [if (d is List) for (final x in d) ?OrgPaletteDept.fromJson(x)],
      people: [if (p is List) for (final x in p) ?OrgPalettePerson.fromJson(x)],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Matching
// ═════════════════════════════════════════════════════════════════════════════

final _diacritics = RegExp('[\u064B-\u0652\u0670\u0640]');
final _spaces = RegExp(r'\s+');

/// Lower case, Arabic letters folded (أ إ آ ٱ → ا · ة → ه · ى → ي · ؤ → و · ئ → ي), diacritics and tatweel removed,
/// spaces collapsed.
String orgPaletteNormalize(String s) {
  var x = s.toLowerCase().replaceAll(_diacritics, '');
  x = x
      .replaceAll(RegExp('[\u0623\u0625\u0622\u0671]'), '\u0627')
      .replaceAll('\u0629', '\u0647')
      .replaceAll('\u0649', '\u064A')
      .replaceAll('\u0624', '\u0648')
      .replaceAll('\u0626', '\u064A');
  return x.replaceAll(_spaces, ' ').trim();
}

/// How well [query] finds [label]: 0 exact · 1 prefix · 2 a word starts with it · 3 contains · 4 the group or a
/// keyword has it · 5 every word of the query is somewhere; null = no match. Lower is better.
int? orgPaletteScore(String query, String label, {String? group, List<String> keywords = const []}) {
  final q = orgPaletteNormalize(query);
  if (q.isEmpty) return null;
  final l = orgPaletteNormalize(label);
  if (l == q) return 0;
  if (l.startsWith(q)) return 1;
  if (l.split(' ').any((w) => w.startsWith(q))) return 2;
  if (l.contains(q)) return 3;
  final extra = [if (group != null) orgPaletteNormalize(group), for (final k in keywords) orgPaletteNormalize(k)];
  if (extra.any((e) => e.contains(q))) return 4;
  final all = ([l, ...extra]).join(' ');
  final words = q.split(' ');
  if (words.length > 1 && words.every(all.contains)) return 5;
  return null;
}

/// The pages that match [query], best first (score, then the shorter label), at most [max].
List<OrgPaletteEntry> orgPaletteFilterPages(List<OrgPaletteEntry> pages, String query, {int max = 8}) {
  final scored = <(int, int, OrgPaletteEntry)>[];
  for (var i = 0; i < pages.length; i++) {
    final e = pages[i];
    final s = orgPaletteScore(query, e.label, group: e.group, keywords: e.keywords);
    if (s != null) scored.add((s, i, e));
  }
  scored.sort((a, b) => a.$1 != b.$1
      ? a.$1.compareTo(b.$1)
      : (a.$3.label.length != b.$3.label.length ? a.$3.label.length.compareTo(b.$3.label.length) : a.$2.compareTo(b.$2)));
  return [for (final x in scored.take(max)) x.$3];
}

/// The server is asked from this many characters on (422 query_too_short below).
const orgPaletteMinQuery = 2;

/// Wraps around; -1 when there is nothing to select.
int orgPaletteMove(int current, int delta, int count) {
  if (count <= 0) return -1;
  if (current < 0) return delta >= 0 ? 0 : count - 1;
  return ((current + delta) % count + count) % count;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Recent
// ═════════════════════════════════════════════════════════════════════════════

enum OrgPaletteKind { page, dept, person }

/// Something opened from the palette lately. A page is found again by its key among the pages of now (a page I can no
/// longer open drops out); a department / person carries what is needed to open it again.
class OrgPaletteRecent {
  const OrgPaletteRecent({required this.kind, required this.key, this.dept, this.person});

  final OrgPaletteKind kind;

  /// page key · `dept:6` / `program:1` · `person:10`.
  final String key;
  final OrgPaletteDept? dept;
  final OrgPalettePerson? person;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'key': key,
        if (dept != null) 'dept': dept!.toJson(),
        if (person != null) 'person': person!.toJson(),
      };

  static OrgPaletteRecent? fromJson(Object? j) {
    if (j is! Map) return null;
    OrgPaletteKind? kind;
    for (final k in OrgPaletteKind.values) {
      if (k.name == j['kind']) kind = k;
    }
    final key = j['key'];
    if (kind == null || key is! String || key.isEmpty) return null;
    final dept = OrgPaletteDept.fromJson(j['dept']);
    final person = OrgPalettePerson.fromJson(j['person']);
    if (kind == OrgPaletteKind.dept && dept == null) return null;
    if (kind == OrgPaletteKind.person && person == null) return null;
    return OrgPaletteRecent(kind: kind, key: key, dept: dept, person: person);
  }
}

/// [item] first, the same key never twice, at most [max].
List<OrgPaletteRecent> orgPaletteRemember(List<OrgPaletteRecent> list, OrgPaletteRecent item, {int max = 6}) =>
    [item, for (final x in list) if (x.key != item.key) x].take(max).toList();

// ═════════════════════════════════════════════════════════════════════════════
//  Rows and the controller
// ═════════════════════════════════════════════════════════════════════════════

/// One selectable row: a page, a department or a person.
class OrgPaletteRow {
  const OrgPaletteRow.page(OrgPaletteEntry this.page)
      : kind = OrgPaletteKind.page,
        dept = null,
        person = null;
  const OrgPaletteRow.dept(OrgPaletteDept this.dept)
      : kind = OrgPaletteKind.dept,
        page = null,
        person = null;
  const OrgPaletteRow.person(OrgPalettePerson this.person)
      : kind = OrgPaletteKind.person,
        page = null,
        dept = null;

  final OrgPaletteKind kind;
  final OrgPaletteEntry? page;
  final OrgPaletteDept? dept;
  final OrgPalettePerson? person;

  String get key => page?.key ?? dept?.key ?? person!.key;

  OrgPaletteRecent get asRecent => OrgPaletteRecent(kind: kind, key: key, dept: dept, person: person);
}

/// The group titles, in the order they are drawn.
String orgPaletteGroupLabel(OrgPaletteKind k) => switch (k) {
      OrgPaletteKind.page => _t('الصفحات', 'Pages'),
      OrgPaletteKind.dept => _t('الأقسام', 'Departments'),
      OrgPaletteKind.person => _t('الأشخاص', 'People'),
    };

typedef OrgPaletteSearch = Future<OrgSearchResult> Function(String q);

class OrgPaletteController extends ChangeNotifier {
  OrgPaletteController({
    required this.pages,
    this.search,
    this.cancel,
    List<OrgPaletteRecent> recents = const [],
    this.debounce = const Duration(milliseconds: 250),
  }) : _recents = recents;

  final List<OrgPaletteEntry> pages;

  /// The server search; null = pages only.
  final OrgPaletteSearch? search;

  /// Cancels the request in flight (a newer query replaces it).
  final VoidCallback? cancel;
  final Duration debounce;

  List<OrgPaletteRecent> _recents;
  String _query = '';
  List<OrgPaletteEntry> _pageHits = const [];
  OrgSearchResult _server = OrgSearchResult.empty;
  bool _searching = false;
  bool _searchFailed = false;
  int _seq = 0;
  int _active = 0;
  Timer? _timer;
  bool _disposed = false;

  String get query => _query;
  bool get searching => _searching;

  /// The server search failed (the pages still show).
  bool get searchFailed => _searchFailed;
  int get active => _active;
  List<OrgPaletteRecent> get recents => _recents;

  /// Nothing typed: the recent items are shown.
  bool get showingRecent => orgPaletteNormalize(_query).isEmpty;

  /// The rows in drawn order: pages, departments, people (or the recent ones while nothing is typed).
  List<OrgPaletteRow> get rows {
    if (showingRecent) {
      return [
        for (final r in _recents)
          if (r.kind == OrgPaletteKind.page)
            for (final p in pages.where((p) => p.key == r.key).take(1)) OrgPaletteRow.page(p)
          else if (r.kind == OrgPaletteKind.dept)
            OrgPaletteRow.dept(r.dept!)
          else
            OrgPaletteRow.person(r.person!),
      ];
    }
    return [
      for (final p in _pageHits) OrgPaletteRow.page(p),
      for (final d in _server.departments) OrgPaletteRow.dept(d),
      for (final p in _server.people) OrgPaletteRow.person(p),
    ];
  }

  OrgPaletteRow? get activeRow {
    final r = rows;
    return _active >= 0 && _active < r.length ? r[_active] : null;
  }

  void setQuery(String q) {
    if (q == _query) return;
    _query = q;
    _pageHits = orgPaletteFilterPages(pages, q);
    _active = 0;
    _timer?.cancel();
    final seq = ++_seq;
    final norm = orgPaletteNormalize(q);
    if (search == null || norm.length < orgPaletteMinQuery) {
      if (_searching) cancel?.call();
      _server = OrgSearchResult.empty;
      _searching = false;
      _searchFailed = false;
      notifyListeners();
      return;
    }
    // the old server hits stay until the new ones arrive only when they still match what is typed
    _server = OrgSearchResult(
      departments: [
        for (final d in _server.departments)
          if (orgPaletteScore(q, d.nameAr) != null || orgPaletteScore(q, d.nameEn) != null) d,
      ],
      people: [for (final p in _server.people) if (orgPaletteScore(q, p.name) != null) p],
    );
    _searching = true;
    notifyListeners();
    _timer = Timer(debounce, () => _run(q.trim(), seq));
  }

  Future<void> _run(String q, int seq) async {
    cancel?.call();
    try {
      final r = await search!(q);
      if (_disposed || seq != _seq) return; // a newer query took over
      _server = r;
      _searchFailed = false;
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _searchFailed = true;
    }
    _searching = false;
    if (_active >= rows.length) _active = 0;
    notifyListeners();
  }

  void move(int delta) {
    final n = rows.length;
    final next = orgPaletteMove(_active, delta, n);
    if (next != _active) {
      _active = next;
      notifyListeners();
    }
  }

  void setActive(int i) {
    if (i != _active && i >= 0 && i < rows.length) {
      _active = i;
      notifyListeners();
    }
  }

  /// Remembers [row] as the most recent (the caller saves [recents]).
  void remember(OrgPaletteRow row) {
    _recents = orgPaletteRemember(_recents, row.asRecent);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
