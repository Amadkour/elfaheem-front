// lib/features/teacher/todo/teacher_todo_models.dart — the teacher's automatic to-do list (D-303), pure.
//
// The server derives every item from live data (GET /api/v1/me/todo, the core; GET /api/v1/exam/me/todo, the Exam
// Engine's review queues) — nothing is typed in. One item says WHAT to do (title), WHY it is there (the evidence),
// how urgent it is (priority · score), and where it is done (action → teacher_todo_actions.dart). What the teacher
// did to an item lives in the core's `states` map ({key: {state: done | snooze | dismiss, fp, until?}}): a done or
// dismissed item comes back only when its evidence fingerprint `fp` changes, a snoozed one when `until` passes.
// The core applies the states to its own items; [mergeTodo] applies the same rule to the engine's.
library;

import '../../../config/app_config.dart';

/// What a row's menu asked for.
enum TodoMenu { done, snooze1, snooze3, snooze7, dismiss }

/// The filter groups of the full page (and the icon family of a row).
enum TodoGroup { grading, students, schedule, content, requests }

/// One to-do item (the same shape from the core and the engine).
class TodoItem {
  const TodoItem({
    required this.key,
    required this.kind,
    required this.priority,
    required this.score,
    required this.titleAr,
    required this.titleEn,
    this.whyAr = '',
    this.whyEn = '',
    this.count = 1,
    this.courseId,
    this.courseName,
    this.orgId,
    this.examId,
    this.at,
    this.when,
    this.fp = '',
    this.students = const [],
    this.action = const {},
    this.state = 'open',
    this.until,
    this.returned = false,
  });

  final String key;
  final String kind;

  /// high · medium · low.
  final String priority;
  final int score;
  final String titleAr, titleEn, whyAr, whyEn;
  final int count;
  final int? courseId;
  final String? courseName;
  final int? orgId;
  final int? examId;

  /// How old the evidence is (UTC); null when it has no age (a clash).
  final DateTime? at;

  /// An upcoming moment (UTC): the start of a clash.
  final DateTime? when;
  final String fp;

  /// at_risk: the students and why ({id, name, reasons: absent | scores | inactive}).
  final List<TodoStudent> students;

  /// {type: course | transfers | complaints | calendar | exam_review | exam_appeals | omr_review, …}.
  final Map<String, dynamic> action;

  /// open · done · snooze · dismiss.
  final String state;
  final DateTime? until;

  /// The teacher had closed it and its evidence changed since.
  final bool returned;

  String get title => AppConfig.lang == 'ar' ? (titleAr.isEmpty ? titleEn : titleAr) : (titleEn.isEmpty ? titleAr : titleEn);
  String get why => AppConfig.lang == 'ar' ? (whyAr.isEmpty ? whyEn : whyAr) : (whyEn.isEmpty ? whyAr : whyEn);
  String get actionType => '${action['type'] ?? ''}';
  bool get isHigh => priority == 'high';

  TodoGroup get group => todoGroupOf(kind);

  TodoItem withState(String s, {DateTime? until, bool returned = false}) => TodoItem(
        key: key,
        kind: kind,
        priority: priority,
        score: score,
        titleAr: titleAr,
        titleEn: titleEn,
        whyAr: whyAr,
        whyEn: whyEn,
        count: count,
        courseId: courseId,
        courseName: courseName,
        orgId: orgId,
        examId: examId,
        at: at,
        when: when,
        fp: fp,
        students: students,
        action: action,
        state: s,
        until: until,
        returned: returned,
      );

  static TodoItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final key = '${j['key'] ?? ''}';
    if (key.isEmpty) return null;
    int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return TodoItem(
      key: key,
      kind: '${j['kind'] ?? ''}',
      priority: const {'high', 'medium', 'low'}.contains(j['priority']) ? '${j['priority']}' : 'medium',
      score: n(j['score']) ?? 0,
      titleAr: '${j['title_ar'] ?? ''}',
      titleEn: '${j['title_en'] ?? ''}',
      whyAr: '${j['why_ar'] ?? ''}',
      whyEn: '${j['why_en'] ?? ''}',
      count: n(j['count']) ?? 1,
      courseId: n(j['course_id']),
      courseName: j['course_name'] == null ? (j['exam_title'] == null ? null : '${j['exam_title']}') : '${j['course_name']}',
      orgId: n(j['org_id']),
      examId: n(j['exam_id']),
      at: todoUtc(j['at']),
      when: todoUtc(j['when']),
      fp: '${j['fp'] ?? ''}',
      students: [
        for (final s in j['students'] is List ? j['students'] as List : const []) ?TodoStudent.fromJson(s),
      ],
      action: j['action'] is Map ? Map<String, dynamic>.from(j['action'] as Map) : const {},
      state: '${j['state'] ?? 'open'}',
      until: todoUtc(j['until']),
      returned: j['returned'] == true,
    );
  }
}

class TodoStudent {
  const TodoStudent({required this.id, required this.name, this.reasons = const []});
  final int id;
  final String name;
  final List<String> reasons;

  static TodoStudent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] is num ? (raw['id'] as num).toInt() : int.tryParse('${raw['id']}');
    if (id == null) return null;
    return TodoStudent(
      id: id,
      name: '${raw['name'] ?? ''}',
      reasons: [for (final r in raw['reasons'] is List ? raw['reasons'] as List : const []) '$r'],
    );
  }
}

/// The teacher's stored choice on one item.
class TodoState {
  const TodoState({required this.state, this.fp = '', this.until});
  final String state;
  final String fp;
  final DateTime? until;

  static TodoState? fromJson(Object? raw) => raw is Map
      ? TodoState(state: '${raw['state'] ?? ''}', fp: '${raw['fp'] ?? ''}', until: todoUtc(raw['until']))
      : null;
}

/// The server's naive-UTC ISO string → a UTC DateTime (null when absent / unreadable).
DateTime? todoUtc(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s.length > 10 ? s.substring(10) : '');
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

/// Is an item with fingerprint [fp] hidden by [st] at [now]? (the server's `hidden_by`).
bool todoHidden(TodoState? st, String fp, DateTime now) {
  if (st == null) return false;
  if (st.state == 'snooze') return st.until != null && st.until!.isAfter(now);
  return (st.state == 'done' || st.state == 'dismiss') && st.fp == fp;
}

TodoGroup todoGroupOf(String kind) => switch (kind) {
      'grading' || 'exam_grading' || 'exam_appeals' || 'exam_scan_review' => TodoGroup.grading,
      'at_risk' || 'low_engagement' => TodoGroup.students,
      'conflict' || 'quiet_course' => TodoGroup.schedule,
      'attendance_missing' || 'materials_missing' || 'recording_missing' => TodoGroup.content,
      _ => TodoGroup.requests, // enrollment_requests · complaints · anything newer
    };

/// One loaded list: the open items, the hidden ones, the stored states.
class TodoList {
  const TodoList({this.items = const [], this.hidden = const [], this.states = const {}, this.enabled = true, this.total, this.high});

  final List<TodoItem> items;
  final List<TodoItem> hidden;
  final Map<String, TodoState> states;
  final bool enabled;

  /// The server's counts (the home block carries only the top items); null = count [items].
  final int? total, high;

  int get totalCount => total ?? items.length;
  int get highCount => high ?? items.where((x) => x.isHigh).length;

  static const empty = TodoList();

  /// The core's answer (GET /me/todo) or the /me/home `todo` block.
  static TodoList fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final counts = raw['counts'] is Map ? raw['counts'] as Map : const {};
    final states = <String, TodoState>{
      if (raw['states'] is Map)
        for (final e in (raw['states'] as Map).entries) '${e.key}': ?TodoState.fromJson(e.value),
    };
    return TodoList(
      enabled: raw['enabled'] != false,
      items: [for (final x in raw['items'] is List ? raw['items'] as List : const []) ?TodoItem.fromJson(x)],
      hidden: [for (final x in raw['hidden'] is List ? raw['hidden'] as List : const []) ?TodoItem.fromJson(x)],
      states: states,
      total: counts['total'] is num ? (counts['total'] as num).toInt() : null,
      high: counts['high'] is num ? (counts['high'] as num).toInt() : null,
    );
  }

  /// Without the items of [keys] (an optimistic done / snooze / dismiss), the counts following.
  TodoList without(Set<String> keys) {
    final gone = items.where((x) => keys.contains(x.key)).toList();
    return TodoList(
      items: [for (final x in items) if (!keys.contains(x.key)) x],
      hidden: hidden,
      states: states,
      enabled: enabled,
      total: total == null ? null : (total! - gone.length).clamp(0, 1 << 30),
      high: high == null ? null : (high! - gone.where((x) => x.isHigh).length).clamp(0, 1 << 30),
    );
  }
}

/// The core's list + the engine's items (the core's [TodoList.states] applied to them), highest score first.
TodoList mergeTodo(TodoList core, List<TodoItem> engine, {DateTime? now}) {
  final t = now ?? DateTime.now().toUtc();
  final open = [...core.items], hidden = [...core.hidden];
  final known = {for (final x in open) x.key, for (final x in hidden) x.key};
  for (final x in engine) {
    if (known.contains(x.key)) continue;
    final st = core.states[x.key];
    if (todoHidden(st, x.fp, t)) {
      hidden.add(x.withState(st!.state, until: st.until));
    } else {
      open.add(st != null && st.state != 'snooze' ? x.withState('open', returned: true) : x);
    }
  }
  open.sort(todoOrder);
  return TodoList(items: open, hidden: hidden, states: core.states, enabled: core.enabled);
}

/// Highest score first; then the oldest evidence; then the key (stable).
int todoOrder(TodoItem a, TodoItem b) {
  final s = b.score.compareTo(a.score);
  if (s != 0) return s;
  final ta = a.at, tb = b.at;
  if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
  return a.key.compareTo(b.key);
}

/// The page's filter: null = every item; 'high' = the urgent ones; else a [TodoGroup] name.
List<TodoItem> todoFiltered(List<TodoItem> items, String? filter) {
  if (filter == null) return items;
  if (filter == 'high') return [for (final x in items) if (x.isHigh) x];
  return [for (final x in items) if (x.group.name == filter) x];
}
