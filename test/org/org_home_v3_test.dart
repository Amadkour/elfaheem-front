// The organization home's pure logic (D-103, lib/features/org/home/org_home_logic.dart + the model's new keys):
// task parsing and sorting, the optimistic queue of one-tap decisions, error → outcome, department tabs and their
// levels, the section order of `layout` and the balanced desktop columns, the department card's meta line.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/home/org_home_logic.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> task(String id,
        {String urgency = 'medium', String created = '2026-10-30T08:00:00', List<Map<String, dynamic>>? actions, Map<String, dynamic>? person}) =>
    {
      'id': id,
      'kind': id.split(':').first,
      'title_ar': 'طلب $id',
      'title_en': 'Request $id',
      'subtitle_ar': 'شؤون الطلاب',
      'subtitle_en': 'Student affairs',
      'person': person,
      'dept_id': 3,
      'created_at': created,
      'due_at': null,
      'urgency': urgency,
      'actions': actions ??
          [
            {'id': 'approve', 'style': 'primary'},
            {'id': 'reject', 'style': 'danger', 'reason': 'optional'},
          ],
      'version': null,
      'link': {'section': 'people', 'sub': 'join_requests', 'dept_id': null, 'kind': null, 'id': null},
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('OrgTask', () {
    test('parses the spec shape; texts follow the language', () {
      final x = OrgTask.fromJson(task('org_join:123', person: {'id': 9, 'name': 'Ahmed Ali', 'avatar_url': 'https://x/a.png'}))!;
      expect(x.id, 'org_join:123');
      expect(x.kind, 'org_join');
      expect(x.title, 'Request org_join:123');
      expect(x.subtitle, 'Student affairs');
      expect(x.person!.name, 'Ahmed Ali');
      expect(x.person!.avatarUrl, 'https://x/a.png');
      expect(x.createdAt, DateTime.utc(2026, 10, 30, 8)); // naive UTC read as UTC
      expect(x.oneTap, isTrue);
      expect(x.primary!.id, 'approve');
      expect([for (final a in x.secondary) a.id], ['reject']);
      expect(x.link.section, 'people');
      expect(x.link.sub, 'join_requests');
      AppConfig.lang = 'ar';
      expect(x.title, 'طلب org_join:123');
      expect(x.primary!.label, 'قبول');
    });

    test('reason modes: only REQUIRED asks; optional never blocks the one tap', () {
      final x = OrgTask.fromJson(task('form_response:4', actions: [
        {'id': 'approve', 'style': 'primary'},
        {'id': 'reject', 'style': 'danger', 'reason': 'required'},
      ]))!;
      expect(x.secondary.single.reason, OrgReasonMode.required);
      expect(x.secondary.single.asksReason, isTrue);
      final y = OrgTask.fromJson(task('org_join:5'))!;
      expect(y.secondary.single.reason, OrgReasonMode.optional);
      expect(y.secondary.single.asksReason, isFalse);
      expect(y.primary!.asksReason, isFalse);
    });

    test('actions the app cannot name are dropped; no actions → opens its link', () {
      final x = OrgTask.fromJson(task('council_vote:7', actions: [
        {'id': 'teleport', 'style': 'primary'},
      ]))!;
      expect(x.actions, isEmpty);
      expect(x.oneTap, isFalse);
      final y = OrgTask.fromJson({...task('council_vote:8', actions: []), 'link': {'kind': 'org_council', 'id': 55}})!;
      expect(y.link.kind, 'org_council');
      expect(y.link.id, 55);
      expect(y.link.isEmpty, isFalse);
    });

    test('broken rows are skipped; a missing kind comes from the id', () {
      expect(OrgTask.fromJson(null), isNull);
      expect(OrgTask.fromJson({'id': ''}), isNull);
      expect(OrgTask.fromJson({'id': 'x:1'}), isNull); // no title
      final x = OrgTask.fromJson({'id': 'consent:3', 'title_en': 'Approve your timetable'})!;
      expect(x.kind, 'consent');
      expect(x.title, 'Approve your timetable');
      expect(x.urgency, 'low');
    });

    test('sorting: urgency high → low, then the oldest first', () {
      final list = OrgTask.listFrom([
        task('a:1', urgency: 'low', created: '2026-10-01T00:00:00'),
        task('b:2', urgency: 'medium', created: '2026-10-29T00:00:00'),
        task('c:3', urgency: 'high', created: '2026-10-30T00:00:00'),
        task('d:4', urgency: 'medium', created: '2026-10-20T00:00:00'),
        task('e:5', urgency: 'high', created: '2026-10-10T00:00:00'),
        task('f:6', urgency: 'whatever'),
      ])!;
      expect([for (final x in list) x.id], ['e:5', 'c:3', 'd:4', 'b:2', 'a:1', 'f:6']);
      expect(OrgTask.listFrom('nope'), isNull);
    });

    test('OrgTaskPage: items, total, next cursor', () {
      final p = OrgTaskPage.fromJson({'items': [task('a:1'), task('b:2')], 'total': 31, 'next_cursor': 'abc'});
      expect(p.items.length, 2);
      expect(p.total, 31);
      expect(p.nextCursor, 'abc');
      final last = OrgTaskPage.fromJson({'items': [task('a:1')], 'next_cursor': null});
      expect(last.total, 1);
      expect(last.nextCursor, isNull);
    });
  });

  group('optimistic queue', () {
    List<OrgTask> rows() => [for (final id in ['a:1', 'b:2', 'c:3']) OrgTask.fromJson(task(id))!];

    test('a tap hides the row at once and lowers the total; success keeps it gone', () {
      final q = OrgTaskQueue()..apply(rows(), 12);
      expect(q.total, 12);
      expect(q.begin('b:2'), isTrue);
      expect(q.begin('b:2'), isFalse); // a second tap while in flight does nothing
      expect([for (final x in q.items) x.id], ['a:1', 'c:3']);
      expect(q.total, 11);
      expect(q.isBusy('b:2'), isTrue);
      q.settle('b:2', OrgTaskOutcome.done);
      expect(q.isBusy('b:2'), isFalse);
      expect(q.isHidden('b:2'), isTrue);
      expect(q.items.length, 2);
    });

    test('a failure brings the row back with its message; Retry clears it', () {
      final q = OrgTaskQueue()..apply(rows(), 3);
      q.begin('a:1');
      q.settle('a:1', OrgTaskOutcome.failed, message: 'No connection');
      expect([for (final x in q.items) x.id], ['a:1', 'b:2', 'c:3']);
      expect(q.errorOf('a:1'), 'No connection');
      expect(q.total, 3);
      q.clearError('a:1');
      expect(q.errorOf('a:1'), isNull);
    });

    test('409 already_decided / 404 task_not_found: the row stays gone', () {
      expect(orgTaskOutcome(409, 'already_decided'), OrgTaskOutcome.handled);
      expect(orgTaskOutcome(404, 'task_not_found'), OrgTaskOutcome.handled);
      expect(orgTaskOutcome(409, null), OrgTaskOutcome.handled);
      expect(orgTaskOutcome(403, 'org_forbidden'), OrgTaskOutcome.failed);
      expect(orgTaskOutcome(0, null), OrgTaskOutcome.failed);
      final q = OrgTaskQueue()..apply(rows(), 3);
      q.begin('c:3');
      q.settle('c:3', OrgTaskOutcome.handled);
      expect(q.isHidden('c:3'), isTrue);
      expect(q.errorOf('c:3'), isNull);
    });

    test('a fresh payload forgets decided rows it no longer lists, keeps in-flight ones hidden', () {
      final q = OrgTaskQueue()..apply(rows(), 3);
      q.begin('a:1');
      q.settle('a:1', OrgTaskOutcome.done);
      q.begin('b:2'); // still in flight when the reload lands — and the server still lists it
      q.apply([for (final id in ['b:2', 'c:3', 'd:4']) OrgTask.fromJson(task(id))!], 3);
      expect([for (final x in q.items) x.id], ['c:3', 'd:4']);
      expect(q.isHidden('a:1'), isFalse); // forgotten: the server no longer has it
      expect(q.total, 2);
    });

    test('notifies its listeners', () {
      final q = OrgTaskQueue();
      var n = 0;
      q.addListener(() => n++);
      q.apply(rows(), 3);
      q.begin('a:1');
      q.settle('a:1', OrgTaskOutcome.done);
      expect(n, 3);
    });
  });

  group('department tabs', () {
    test('parse in the server order, each key once, view-less ones dropped; null on an older server', () {
      final tabs = OrgDeptTab.listFrom([
        {'key': 'courses', 'levels': {'view': true, 'insert': false, 'update': true}, 'label_ar': 'المقررات', 'label_en': 'Courses'},
        {'key': 'team', 'levels': {'view': true}},
        {'key': 'forms', 'levels': {'view': false}},
        {'key': 'courses', 'levels': {'view': true}},
        {'key': ''},
        'junk',
      ])!;
      expect([for (final x in tabs) x.key], ['courses', 'team']);
      expect(tabs.first.levels.insert, isFalse);
      expect(tabs.first.levels.update, isTrue);
      expect(tabs.first.label, 'Courses');
      expect(tabs[1].label, 'Team'); // the app's own label when the server sends none
      expect(OrgDeptTab.listFrom(null), isNull);
      expect(OrgDeptTab.listFrom(const []), isEmpty);
    });

    test('levels lookup and the renderable filter', () {
      final tabs = OrgDeptTab.listFrom([
        {'key': 'team', 'levels': {'view': true, 'insert': true}},
        {'key': 'councils', 'levels': {'view': true}},
        {'key': 'materials', 'levels': {'view': true, 'update': true}},
      ]);
      expect(orgTabLevelsOf(tabs, 'team')!.insert, isTrue);
      expect(orgTabLevelsOf(tabs, 'forms'), isNull);
      expect(orgTabLevelsOf(null, 'team'), isNull);
      expect([for (final x in orgRenderableTabs(tabs!, {'team', 'materials'})) x.key], ['team', 'materials']);
    });
  });

  group('section order and columns', () {
    test('layout decides; an older server decides from the role; insights only when allowed', () {
      expect(orgHomeOrder(layout: 'insights_first', isAdmin: false, canInsights: true),
          [OrgHomeSection.insights, OrgHomeSection.attention, OrgHomeSection.departments]);
      expect(orgHomeOrder(layout: 'actions_first', isAdmin: true, canInsights: true),
          [OrgHomeSection.attention, OrgHomeSection.departments, OrgHomeSection.insights]);
      expect(orgHomeOrder(layout: 'actions_first', isAdmin: false, canInsights: false),
          [OrgHomeSection.attention, OrgHomeSection.departments]);
      expect(orgHomeOrder(layout: '', isAdmin: true, canInsights: false), [OrgHomeSection.attention, OrgHomeSection.departments]);
      expect(orgHomeOrder(layout: '', isAdmin: false, canInsights: true),
          [OrgHomeSection.attention, OrgHomeSection.departments, OrgHomeSection.insights]);
    });

    test('the desktop split keeps the reading order and balances the heights', () {
      const a = OrgHomeSection.attention, d = OrgHomeSection.departments, i = OrgHomeSection.insights;
      // a record holding lists never equals another: compare each column on its own
      void cols((List<OrgHomeSection>, List<OrgHomeSection>) r, List<OrgHomeSection> start, List<OrgHomeSection> end) {
        expect(r.$1, start);
        expect(r.$2, end);
      }

      // insights empty (weight 0) → it and the queue start, departments beside them
      cols(orgHomeColumns([i, a, d], {i: 0, a: 6, d: 3}), [i, a], [d]);
      // a tall insights block alone on one side
      cols(orgHomeColumns([i, a, d], {i: 8, a: 4, d: 3}), [i], [a, d]);
      cols(orgHomeColumns([a, d], {a: 2, d: 5}), [a], [d]);
      cols(orgHomeColumns([a], {a: 2}), [a], []);
      expect(orgAttentionWeight(0), 2);
      expect(orgDepartmentsWeight(5), 4);
    });
  });

  group('dashboard payload (D-103 keys)', () {
    test('new keys parse; covered attention keys leave the alerts beside tasks', () {
      final d = OrgHomeData.fromJson({
        'my_role': 'teacher',
        'access': 'staff',
        'member_role': 'teacher',
        'layout': 'actions_first',
        'can_insights': true,
        'tasks': [task('b:2', urgency: 'low'), task('a:1', urgency: 'high')],
        'tasks_total': 14,
        'attention': [
          {'key': 'org_join_requests', 'count': 3, 'severity': 'warning'},
          {'key': 'schedule_unplaced', 'count': 2, 'severity': 'warning'},
        ],
      })!;
      expect(d.access, 'staff');
      expect(d.isAdmin, isFalse);
      expect(d.layout, 'actions_first');
      expect(d.canInsights, isTrue);
      expect([for (final x in d.tasks!) x.id], ['a:1', 'b:2']);
      expect(d.tasksTotal, 14);
      expect([for (final a in d.alerts) a.key], ['schedule_unplaced']);
    });

    test('an older server: no tasks → every attention item stays an alert; admin from my_role', () {
      final d = OrgHomeData.fromJson({
        'my_role': 'org_admin',
        'attention': [
          {'key': 'org_join_requests', 'count': 3, 'severity': 'warning'},
        ],
      })!;
      expect(d.tasks, isNull);
      expect(d.isAdmin, isTrue);
      expect(d.layout, '');
      expect(d.canInsights, isFalse);
      expect(d.alerts.single.key, 'org_join_requests');
    });
  });

  test('department meta line: what waits first, else its size, in plain words', () {
    expect(orgDeptMeta({'unit_type': 'dept', 'waiting': 3, 'team': 4}), '3 waiting for you');
    expect(orgDeptMeta({'unit_type': 'dept', 'waiting': 1}), '1 waiting for you');
    expect(orgDeptMeta({'unit_type': 'dept', 'team': 4}), '4 on the team');
    expect(orgDeptMeta({'unit_type': 'dept', 'team': 0}), 'No one on the team yet');
    expect(orgDeptMeta({'unit_type': 'program', 'students': 3000}), '3000 students');
    AppConfig.lang = 'ar';
    expect(orgDeptMeta({'unit_type': 'dept', 'waiting': 3}), '3 تنتظرك');
  });
}
