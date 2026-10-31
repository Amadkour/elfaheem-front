// lib/features/org/home/org_home_logic.dart
//
// The organization home (D-103, docs/backend/org-dashboard-spec.md §2 – §3), pure — no widgets, unit-tested in
// test/org/org_home_v3_test.dart:
//   OrgTask / OrgTaskAction / OrgTaskLink   one row of "Needs your attention" (GET …/dashboard `tasks`, GET …/tasks)
//   orgSortTasks                            urgency high → low, then the oldest first (the server's order, kept
//                                           when a client merges pages)
//   OrgTaskPage                             one page of GET …/tasks {items, total, next_cursor}
//   OrgTaskQueue                            the optimistic state of one-tap decisions: a row leaves at once, comes
//                                           back with a message when the call fails, stays gone when someone else
//                                           decided first (409 already_decided / 404 task_not_found)
//   orgTaskOutcome                          an error's status + code → what the queue does with the row
//   OrgDeptTab / OrgTabLevels               `departments[].tabs[]` (view · insert · update) — null on an older
//                                           server, which keeps the department page's `can` caps
//   orgHomeOrder / orgHomeColumns           the three sections in the order of `layout`, and their split into two
//                                           balanced columns on a desktop
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../admin/admin_common.dart' show t;

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
int? _intOrNull(dynamic v) => v == null ? null : (v is int ? v : (v is num ? v.toInt() : int.tryParse('$v')));
String _str(dynamic v) => v == null ? '' : '$v';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// The server's naive-UTC ISO time (no zone suffix) → a UTC instant.
DateTime? orgHomeUtc(dynamic v) {
  final s = _str(v).trim();
  if (s.isEmpty) return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

String _pick(String ar, String en) => t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);

// ─────────────────────────────────────────────────────────────────────────────
//  Tasks
// ─────────────────────────────────────────────────────────────────────────────

/// How a decision asks for a reason: never, optionally (one tap still decides), or always (a sheet first).
enum OrgReasonMode { none, optional, required }

class OrgTaskAction {
  const OrgTaskAction({required this.id, this.style = '', this.reason = OrgReasonMode.none});

  /// approve · reject (others are drawn only when the app knows their label, see [label]).
  final String id;

  /// primary · danger · secondary
  final String style;
  final OrgReasonMode reason;

  bool get isPrimary => style == 'primary' || (style.isEmpty && id == 'approve');

  /// Only a REQUIRED reason opens the sheet: an optional one never blocks the one-tap decision.
  bool get asksReason => reason == OrgReasonMode.required;

  static OrgTaskAction? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = _str(v['id']).trim();
    if (id.isEmpty) return null;
    final r = _str(v['reason']);
    return OrgTaskAction(
      id: id,
      style: _str(v['style']),
      reason: r == 'required' ? OrgReasonMode.required : (r == 'optional' ? OrgReasonMode.optional : OrgReasonMode.none),
    );
  }

  /// The verb on the button; null for an action this app version cannot name (the button is not drawn).
  String? get label => switch (id) {
        'approve' => t('قبول', 'Approve'),
        'reject' => t('رفض', 'Decline'),
        'accept' => t('قبول', 'Accept'),
        'decline' => t('اعتذار', 'Decline'),
        'done' || 'complete' => t('تم', 'Done'),
        _ => null,
      };

  /// What the success notice says.
  String get doneText => switch (id) {
        'approve' || 'accept' => t('تم القبول', 'Approved'),
        'reject' || 'decline' => t('تم الرفض', 'Declined'),
        _ => t('تم', 'Done'),
      };
}

/// Where a row without one-tap actions leads: a section / sub-page of the dashboard, a department, or an app deep
/// link (`kind` + `id`, AppNavigator.openModule).
class OrgTaskLink {
  const OrgTaskLink({this.section, this.sub, this.deptId, this.kind, this.id});
  final String? section, sub, kind;
  final int? deptId, id;

  bool get isEmpty => section == null && kind == null && deptId == null;

  static OrgTaskLink fromJson(dynamic v) {
    final m = _map(v);
    String? s(String k) => _str(m[k]).trim().isEmpty ? null : _str(m[k]).trim();
    return OrgTaskLink(section: s('section'), sub: s('sub'), kind: s('kind'), deptId: _intOrNull(m['dept_id']), id: _intOrNull(m['id']));
  }
}

class OrgTaskPerson {
  const OrgTaskPerson({required this.id, required this.name, this.avatarUrl});
  final int id;
  final String name;
  final String? avatarUrl;

  static OrgTaskPerson? fromJson(dynamic v) {
    if (v is! Map) return null;
    final name = _str(v['name']).trim();
    if (name.isEmpty) return null;
    final url = _str(v['avatar_url'] ?? v['image_url']).trim();
    return OrgTaskPerson(id: _int(v['id']), name: name, avatarUrl: url.isEmpty ? null : url);
  }
}

/// 0 high · 1 medium · 2 low (an unknown word counts as low).
int orgUrgencyRank(String u) => switch (u) { 'high' => 0, 'medium' => 1, _ => 2 };

class OrgTask {
  const OrgTask({
    required this.id,
    required this.kind,
    required this.titleAr,
    required this.titleEn,
    this.subtitleAr = '',
    this.subtitleEn = '',
    this.person,
    this.deptId,
    this.createdAt,
    this.dueAt,
    this.urgency = 'low',
    this.actions = const [],
    this.version,
    this.link = const OrgTaskLink(),
  });

  /// `<kind>:<source id>`, stable.
  final String id;
  final String kind;
  final String titleAr, titleEn, subtitleAr, subtitleEn;
  final OrgTaskPerson? person;
  final int? deptId;
  final DateTime? createdAt, dueAt;
  final String urgency;

  /// Only the actions this app can name (see [OrgTaskAction.label]).
  final List<OrgTaskAction> actions;
  final int? version;
  final OrgTaskLink link;

  String get title => _pick(titleAr, titleEn);
  String get subtitle => _pick(subtitleAr, subtitleEn);
  bool get urgent => urgency == 'high';
  bool get oneTap => actions.isNotEmpty;

  OrgTaskAction? get primary {
    for (final a in actions) {
      if (a.isPrimary) return a;
    }
    return null;
  }

  /// The secondary actions (decline), in the server's order.
  List<OrgTaskAction> get secondary => [for (final a in actions) if (!a.isPrimary) a];

  static OrgTask? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = _str(v['id']).trim();
    if (id.isEmpty) return null;
    final ta = _str(v['title_ar']), te = _str(v['title_en']);
    if (ta.trim().isEmpty && te.trim().isEmpty) return null;
    return OrgTask(
      id: id,
      kind: _str(v['kind']).isEmpty ? id.split(':').first : _str(v['kind']),
      titleAr: ta,
      titleEn: te,
      subtitleAr: _str(v['subtitle_ar']),
      subtitleEn: _str(v['subtitle_en']),
      person: OrgTaskPerson.fromJson(v['person']),
      deptId: _intOrNull(v['dept_id']),
      createdAt: orgHomeUtc(v['created_at']),
      dueAt: orgHomeUtc(v['due_at']),
      urgency: _str(v['urgency']).isEmpty ? 'low' : _str(v['urgency']),
      actions: [
        if (v['actions'] is List)
          for (final a in v['actions'] as List)
            if (OrgTaskAction.fromJson(a) case final x? when x.label != null) x,
      ],
      version: _intOrNull(v['version']),
      link: OrgTaskLink.fromJson(v['link']),
    );
  }

  /// A list (null when [v] is not a list — an older server without `tasks`).
  static List<OrgTask>? listFrom(dynamic v) => v is List ? orgSortTasks([for (final x in v) ?OrgTask.fromJson(x)]) : null;
}

/// Urgency high → low, then the oldest first (no date = last), then the id (stable).
List<OrgTask> orgSortTasks(Iterable<OrgTask> tasks) {
  final list = [...tasks];
  list.sort((a, b) {
    final u = orgUrgencyRank(a.urgency).compareTo(orgUrgencyRank(b.urgency));
    if (u != 0) return u;
    final ad = a.createdAt, bd = b.createdAt;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// One page of GET …/tasks.
class OrgTaskPage {
  const OrgTaskPage({required this.items, required this.total, this.nextCursor});
  final List<OrgTask> items;
  final int total;
  final String? nextCursor;

  static OrgTaskPage fromJson(dynamic v) {
    final m = _map(v);
    final items = [for (final x in (m['items'] is List ? m['items'] as List : const [])) ?OrgTask.fromJson(x)];
    final cur = _str(m['next_cursor']).trim();
    return OrgTaskPage(items: items, total: m['total'] == null ? items.length : _int(m['total']), nextCursor: cur.isEmpty ? null : cur);
  }
}

/// What a failed decision means for its row.
enum OrgTaskOutcome {
  /// decided (the row stays gone)
  done,

  /// someone else decided first, or it no longer exists (the row stays gone, "Someone already handled this")
  handled,

  /// it did not go through: the row comes back with a message and Retry
  failed,
}

OrgTaskOutcome orgTaskOutcome(int? status, String? code) {
  if (code == 'already_decided' || code == 'task_not_found') return OrgTaskOutcome.handled;
  if (status == 409 && (code == null || code.isEmpty)) return OrgTaskOutcome.handled;
  return OrgTaskOutcome.failed;
}

/// The optimistic state of one-tap decisions, shared by Home and the full list: [begin] hides a row at once,
/// [settle] keeps it hidden ([OrgTaskOutcome.done] / [OrgTaskOutcome.handled]) or brings it back with a message
/// ([OrgTaskOutcome.failed]). A fresh payload ([apply]) forgets what it no longer lists.
class OrgTaskQueue extends ChangeNotifier {
  List<OrgTask> _items = const [];
  int _total = 0;
  final Set<String> _hidden = {};
  final Set<String> _busy = {};
  final Map<String, String> _errors = {};

  /// Home's rows (the dashboard's first few), hidden ones left out.
  List<OrgTask> get items => [for (final x in _items) if (!_hidden.contains(x.id)) x];

  /// Everything waiting, less what was decided here since the payload came.
  int get total {
    final gone = _items.where((x) => _hidden.contains(x.id)).length;
    final n = _total - gone;
    return n < 0 ? 0 : n;
  }

  bool isHidden(String id) => _hidden.contains(id);
  bool isBusy(String id) => _busy.contains(id);
  String? errorOf(String id) => _errors[id];

  /// A fresh payload: its rows and total. A hidden row the server no longer lists is forgotten; one it still lists
  /// while its call is in flight stays hidden.
  void apply(List<OrgTask> items, int total) {
    _items = orgSortTasks(items);
    _total = total < items.length ? items.length : total;
    final ids = {for (final x in items) x.id};
    _hidden.removeWhere((id) => !ids.contains(id) && !_busy.contains(id));
    _errors.removeWhere((id, _) => !ids.contains(id));
    notifyListeners();
  }

  /// The tap: the row leaves at once. False when that row is already on its way.
  bool begin(String id) {
    if (_busy.contains(id)) return false;
    _busy.add(id);
    _hidden.add(id);
    _errors.remove(id);
    notifyListeners();
    return true;
  }

  void settle(String id, OrgTaskOutcome outcome, {String? message}) {
    _busy.remove(id);
    if (outcome == OrgTaskOutcome.failed) {
      _hidden.remove(id);
      _errors[id] = message ?? t('لم يكتمل الإجراء', 'That did not go through');
    }
    notifyListeners();
  }

  /// Retry from the row: clears its message (the caller then runs [begin] again).
  void clearError(String id) {
    if (_errors.remove(id) != null) notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Department tabs
// ─────────────────────────────────────────────────────────────────────────────

class OrgTabLevels {
  const OrgTabLevels({this.view = true, this.insert = false, this.update = false});
  final bool view, insert, update;

  static const all = OrgTabLevels(view: true, insert: true, update: true);

  static OrgTabLevels fromJson(dynamic v) {
    if (v is! Map) return const OrgTabLevels();
    return OrgTabLevels(view: v['view'] != false, insert: v['insert'] == true, update: v['update'] == true);
  }
}

/// One department-scoped module the caller may view there (`departments[].tabs[]`).
class OrgDeptTab {
  const OrgDeptTab({required this.key, this.levels = const OrgTabLevels(), this.labelAr = '', this.labelEn = ''});
  final String key;
  final OrgTabLevels levels;
  final String labelAr, labelEn;

  /// The server's label, else the app's own.
  String get label => labelAr.isEmpty && labelEn.isEmpty ? orgDeptTabLabel(key) : _pick(labelAr, labelEn);

  static OrgDeptTab? fromJson(dynamic v) {
    if (v is! Map) return null;
    final key = _str(v['key']).trim();
    if (key.isEmpty) return null;
    final levels = OrgTabLevels.fromJson(v['levels']);
    if (!levels.view) return null;
    return OrgDeptTab(key: key, levels: levels, labelAr: _str(v['label_ar']), labelEn: _str(v['label_en']));
  }

  /// The tabs in the server's order, each key once; null when [v] is not a list (an older server: the page keeps
  /// its `can` caps).
  static List<OrgDeptTab>? listFrom(dynamic v) {
    if (v is! List) return null;
    final seen = <String>{};
    return [
      for (final x in v)
        if (OrgDeptTab.fromJson(x) case final tab? when seen.add(tab.key)) tab,
    ];
  }
}

/// Every key the spec names, in its order.
const orgDeptTabKeys = [
  'courses', 'enrollments', 'team', 'announcements', 'forms', 'complaints', 'materials', 'workflow', 'councils',
  'data_lab', 'certificates',
];

String orgDeptTabLabel(String key) => switch (key) {
      'courses' => t('المقررات', 'Courses'),
      'enrollments' => t('المنضمّون', 'People'),
      'team' => t('الفريق', 'Team'),
      'announcements' => t('الإعلانات', 'News'),
      'forms' => t('النماذج', 'Forms'),
      'complaints' => t('الشكاوى', 'Complaints'),
      'materials' => t('المكتبة', 'Library'),
      'workflow' => t('المعاملات', 'Requests'),
      'councils' => t('المجلس', 'Council'),
      'data_lab' => t('مختبر البيانات', 'Data Lab'),
      'certificates' => t('الشهادات', 'Certificates'),
      _ => key,
    };

/// The tabs of [tabs] the page can draw, keeping the server's order ([renderable] = the keys this app version has a
/// page for).
List<OrgDeptTab> orgRenderableTabs(List<OrgDeptTab> tabs, Set<String> renderable) =>
    [for (final x in tabs) if (renderable.contains(x.key)) x];

/// The levels of [key] in [tabs]; null when the tab is not there (or [tabs] is null: an older server).
OrgTabLevels? orgTabLevelsOf(List<OrgDeptTab>? tabs, String key) {
  if (tabs == null) return null;
  for (final x in tabs) {
    if (x.key == key) return x.levels;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section order and the desktop columns
// ─────────────────────────────────────────────────────────────────────────────

enum OrgHomeSection { departments, attention, insights }

/// `layout` → the sections in reading order. An older server without `layout`: an organization admin reads
/// insights first, everyone else what needs them. Insights only when [canInsights].
List<OrgHomeSection> orgHomeOrder({required String layout, required bool isAdmin, required bool canInsights}) {
  final insightsFirst = layout == 'insights_first' || (layout.isEmpty && isAdmin);
  final order = insightsFirst
      ? const [OrgHomeSection.insights, OrgHomeSection.attention, OrgHomeSection.departments]
      : const [OrgHomeSection.attention, OrgHomeSection.departments, OrgHomeSection.insights];
  return [for (final s in order) if (s != OrgHomeSection.insights || canInsights) s];
}

/// The desktop split: each section, in reading order, goes to the shorter column ([weight] = its rough height in
/// rows; ties go to the start column), so neither column ends far above the other. One section → one column.
(List<OrgHomeSection>, List<OrgHomeSection>) orgHomeColumns(List<OrgHomeSection> order, Map<OrgHomeSection, int> weight) {
  final start = <OrgHomeSection>[], end = <OrgHomeSection>[];
  var a = 0, b = 0;
  for (final s in order) {
    final w = weight[s] ?? 1;
    if (a <= b) {
      start.add(s);
      a += w;
    } else {
      end.add(s);
      b += w;
    }
  }
  return (start, end);
}

/// The rough height of "Needs your attention" in rows: its rows (at least one for the empty line) + the title.
int orgAttentionWeight(int rows) => (rows < 1 ? 1 : rows) + 1;

/// The rough height of the departments section: one row per two cards on a desktop + the title.
int orgDepartmentsWeight(int cards) => (cards < 1 ? 1 : (cards + 1) ~/ 2) + 1;

// ─────────────────────────────────────────────────────────────────────────────
//  Department card meta line
// ─────────────────────────────────────────────────────────────────────────────

/// The one line under a department's name: what waits there for me first, else its size, in plain words.
String orgDeptMeta(Map<String, dynamic> u) {
  final waiting = _int(u['waiting']);
  if (waiting > 0) return waiting == 1 ? t('طلب واحد ينتظرك', '1 waiting for you') : t('$waiting تنتظرك', '$waiting waiting for you');
  if (u['unit_type'] == 'program') {
    final n = _int(u['students']);
    return n == 1 ? t('طالب واحد', '1 student') : t('$n طالب', '$n students');
  }
  final team = _int(u['team']);
  if (team == 0) return t('لا أحد في الفريق بعد', 'No one on the team yet');
  return team == 1 ? t('شخص واحد في الفريق', '1 person on the team') : t('$team في الفريق', '$team on the team');
}
