// The governance screens' presentational widgets must lay out at every size and language (320×640 · 1400×900, ar
// · en, text scale 1.3): the shared filter bar (and its inline controls / sheet), the item card, the item body
// (staff with the decision bar, member, decided), the comment composer, the route form, the delegation form and
// card, the acting banner, the entity card, the category tile, the dashboard body, the form-assignment form and
// lists, and the member submit form. Sample values come from test/org/gov_filter_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/governance/gov_dashboard.dart';
import 'package:flutter_education_app/features/org/governance/gov_delegations_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_entities_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_filter.dart';
import 'package:flutter_education_app/features/org/governance/gov_forms_assign.dart';
import 'package:flutter_education_app/features/org/governance/gov_item_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_items_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_member_pages.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_route_sheet.dart';
import 'package:flutter_education_app/features/org/governance/gov_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/gov_filter_test.dart' show sampleDelegationJson, sampleEntityJson, sampleItemJson;
import 'layout_harness.dart';

List<Entity> _entities() => [
      Entity.fromJson(sampleEntityJson()),
      Entity.fromJson(sampleEntityJson(kind: 'service', id: 2)),
      Entity.fromJson(sampleEntityJson(kind: 'office', id: 3)),
      Entity.fromJson(sampleEntityJson(kind: 'council', id: 6)),
    ];

ItemFilter _busyFilter() => ItemFilter(
      q: 'exam',
      types: const ['complaint', 'request'],
      statuses: const ['open', 'in_review'],
      deptId: 5,
      assigneeId: 7,
      categoryId: 3,
      outcomes: const ['approved'],
      dateFrom: DateTime(2026, 10, 1),
      dateTo: DateTime(2026, 10, 31),
      toMe: true,
    );

FormAssignment _assignment(int id, String status, {bool overdue = false}) => FormAssignment.fromJson({
      'user': {'id': id, 'name': 'Member number $id with a fairly long name'},
      'status': status,
      'due_at': overdue ? '2020-01-01T10:00:00' : '2030-01-01T10:00:00',
      'remind_count': overdue ? 3 : 0,
    });

void main() {
  testWidgets('ItemFilterBar: empty and busy, inline controls on the wide window / the sheet on a phone', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          ItemFilterBar(filter: const ItemFilter(), onChanged: (_) {}, entities: _entities(), savedFilters: const []),
          const SizedBox(height: 16),
          ItemFilterBar(
            filter: _busyFilter(),
            onChanged: (_) {},
            entities: _entities(),
            people: const {7: 'Dr. Omar', 9: 'Sara Ahmed'},
            categories: _entities().first.categories,
            savedFilters: [SavedFilter.fromJson({'id': 1, 'name': 'Overdue complaints', 'scope': 'items', 'query': {'overdue': true}})],
            onSaveFilter: (_, _) async {},
            onDeleteFilter: (_) async {},
          ),
          const SizedBox(height: 16),
          ItemFilterBar(filter: _busyFilter().copyWith(deptId: null), onChanged: (_) {}, showEntity: false, showQuick: false),
        ]),
      ),
      act: (tester) async {
        // wide: expands the inline controls; phone: opens the sheet with the same controls
        await tester.tap(find.byIcon(Icons.tune_rounded).first, warnIfMissed: false);
      },
    );
  });

  testWidgets('ItemFilterControls alone', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ItemFilterControls(filter: _busyFilter(), onChanged: (_) {}, entities: _entities(), people: const {7: 'Dr. Omar'}, categories: _entities().first.categories),
      ),
    );
  });

  testWidgets('GovItemCard: plain, selected, member, decided, overdue', (tester) async {
    final it = WorkItem.fromJson(sampleItemJson(full: false));
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          GovItemCard(item: it, onTap: () {}),
          GovItemCard(item: it, selectMode: true, selected: true),
          GovItemCard(item: it, member: true),
          GovItemCard(item: WorkItem.fromJson(sampleItemJson(full: false, decided: true))),
          GovItemCard(item: WorkItem.fromJson({...sampleItemJson(full: false), 'overdue': true, 'due_at': '2020-01-01T10:00:00', 'source': {'dept': null, 'user': null, 'anonymous': true}})),
        ]),
      ),
    );
  });

  testWidgets('GovItemBody: staff with the decision bar, pending route and every action', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => GovItemBody(
        item: WorkItem.fromJson(sampleItemJson()),
        currentUserId: 11,
        onDecide: (_) {},
        onRoute: () {},
        onEscalate: () {},
        onAssign: () {},
        onStatus: () {},
        onEdit: () {},
        onDelete: () {},
        onAnswerRoute: (_) {},
        onOpenAttachment: (_) {},
      ),
    );
  });

  testWidgets('GovItemBody: decided item, and the member view with withdraw', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        Expanded(child: GovItemBody(item: WorkItem.fromJson(sampleItemJson(decided: true)), onStatus: () {})),
        Expanded(
          child: GovItemBody(
            item: WorkItem.fromJson({...sampleItemJson(), 'can': {'view': true, 'comment': true, 'withdraw': true}}),
            member: true,
            currentUserId: 9,
            onWithdraw: () {},
          ),
        ),
        GovCommentComposer(onSend: (_, _) async => true, allowInternal: true),
        GovCommentComposer(onSend: (_, _) async => true, busy: true),
      ]),
    );
  });

  testWidgets('GovRouteForm: entity target, person target, error', (tester) async {
    final note = TextEditingController(text: 'Please look at this before Thursday — a note long enough to wrap');
    final dept = _entities().first.dept;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          GovRouteForm(
            entities: _entities(),
            target: RouteTarget(dept: dept),
            toPerson: false,
            action: 'approval',
            note: note,
            dueAt: DateTime(2026, 10, 30, 10),
            onTargetDept: (_) {},
            onPickPerson: () {},
            onToPerson: (_) {},
            onAction: (_) {},
            onDue: (_) {},
            onSubmit: () {},
          ),
          const Divider(height: 32),
          GovRouteForm(
            entities: _entities(),
            target: const RouteTarget(user: GovUser(id: 7, name: 'Dr. Omar Abdulrahman')),
            toPerson: true,
            action: 'vote',
            note: note,
            dueAt: null,
            busy: true,
            error: 'This route is not allowed by the organization rules — a long error sentence',
            onTargetDept: (_) {},
            onPickPerson: () {},
            onToPerson: (_) {},
            onAction: (_) {},
            onDue: (_) {},
            onSubmit: () {},
          ),
          GovEntityPickField(label: 'Entity', entities: _entities(), value: null, onChanged: (_) {}),
        ]),
      ),
    );
  });

  testWidgets('GovDelegationForm (scoped and global), cards and the acting banner', (tester) async {
    final note = TextEditingController();
    final cats = _entities().first.categories;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          GovDelegationForm(
            mode: 'scoped',
            person: const GovUser(id: 7, name: 'Dr. Omar'),
            types: const ['request'],
            categoryIds: const [3],
            formIds: const [12],
            council: true,
            startsAt: DateTime(2026, 10, 1),
            endsAt: DateTime(2026, 12, 31),
            note: note,
            categories: cats,
            forms: const [(id: 12, title: 'Exam delay request form'), (id: 13, title: 'Leave')],
            hasCouncil: true,
            onPickPerson: () {},
            onTypes: (_) {},
            onCategories: (_) {},
            onForms: (_) {},
            onCouncil: (_) {},
            onStarts: (_) {},
            onEnds: (_) {},
            onSubmit: () {},
          ),
          const Divider(height: 32),
          GovDelegationForm(
            mode: 'global',
            person: null,
            types: const [],
            categoryIds: const [],
            formIds: const [],
            council: false,
            startsAt: null,
            endsAt: null,
            note: note,
            error: 'Invalid delegation',
            onPickPerson: () {},
            onTypes: (_) {},
            onCategories: (_) {},
            onForms: (_) {},
            onCouncil: (_) {},
            onStarts: (_) {},
            onEnds: (_) {},
            onSubmit: () {},
          ),
          GovDelegationCard(delegation: Delegation.fromJson(sampleDelegationJson()), onRevoke: () {}, categoryName: (id) => 'Category $id', formTitle: (id) => 'Form $id'),
          GovDelegationCard(delegation: Delegation.fromJson(sampleDelegationJson(mode: 'global', revoked: true)), showEntity: true),
          GovActingBannerBody(delegations: [
            Delegation.fromJson({...sampleDelegationJson(), 'starts_at': null, 'ends_at': '2030-01-01T00:00:00'}),
            Delegation.fromJson({...sampleDelegationJson(mode: 'global'), 'starts_at': null, 'ends_at': null}),
          ]),
        ]),
      ),
    );
  });

  testWidgets('GovEntityCard and GovCategoryTile', (tester) async {
    final es = _entities();
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          GovEntityCard(entity: es[0], council: es[3], onTap: () {}, onChangeKind: () {}, onOpenCouncil: () {}),
          GovEntityCard(entity: Entity.fromJson({...sampleEntityJson(kind: 'service', id: 2), 'head': null, 'accepts_complaints': false, 'is_active': false})),
          GovEntityCard(entity: es[3]),
          GovCategoryTile(category: es[0].categories[0], formTitle: 'Exam delay request form', onEdit: () {}, onDeactivate: () {}),
          GovCategoryTile(category: Category.fromJson({...sampleEntityJson()['categories'][1] as Map<String, dynamic>, 'is_active': false, 'description': 'Appeals against a published grade, within two weeks of publication'})),
        ]),
      ),
    );
  });

  testWidgets('GovDashboardBody: full numbers, compact, and empty', (tester) async {
    final full = GovDashboardStats.fromJson({
      'pending': 14,
      'pending_decision': 3,
      'overdue': 2,
      'decided_30d': 27,
      'by_status': {'open': 6, 'in_review': 4, 'pending_approval': 3, 'in_council': 1, 'approved': 20, 'rejected': 7, 'closed': 30},
      'by_type': {'complaint': 20, 'request': 40, 'form': 11},
      'sla': {'on_time_pct': 82.0},
    });
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          GovDashboardBody(stats: full, onTile: (_) {}),
          const Divider(height: 32),
          GovDashboardBody(stats: full, compact: true),
          const Divider(height: 32),
          const GovDashboardBody(stats: GovDashboardStats()),
        ]),
      ),
    );
  });

  testWidgets('GovFormAssignForm and GovAssignmentsBody', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: GovFormAssignForm(
              people: const [GovUser(id: 7, name: 'Dr. Omar'), GovUser(id: 9, name: 'Sara Ahmed with a long name')],
              deptIds: const [5],
              roles: const ['teacher'],
              dueAt: DateTime(2026, 11, 1, 9),
              must: true,
              entities: _entities().where((e) => !e.isCouncil).toList(),
              onAddPerson: () {},
              onRemovePerson: (_) {},
              onDepts: (_) {},
              onRoles: (_) {},
              onDue: (_) {},
              onMust: (_) {},
              onSubmit: () {},
            ),
          ),
        ),
        Expanded(
          child: GovAssignmentsBody(
            submitted: [_assignment(1, 'submitted'), _assignment(2, 'submitted')],
            pending: [_assignment(3, 'pending'), _assignment(4, 'pending', overdue: true)],
            waived: [_assignment(5, 'waived')],
            dueAt: DateTime(2026, 11, 1, 9),
            onRemindAll: () {},
            onWaive: (_) {},
            onOpenResponse: (_) {},
          ),
        ),
      ]),
    );
  });

  testWidgets('GovSubmitForm: nothing picked, an entity with categories, a form-backed category with attachments', (tester) async {
    final title = TextEditingController(text: 'A request title'), body = TextEditingController(text: 'Details');
    final es = _entities().where((e) => !e.isCouncil).toList();
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          GovSubmitForm(
            entities: es,
            entity: null,
            category: null,
            type: 'request',
            title: title,
            body: body,
            priority: 'medium',
            anonymous: false,
            attachments: const [],
            onEntity: (_) {},
            onCategory: (_) {},
            onType: (_) {},
            onPriority: (_) {},
            onAnonymous: (_) {},
            onAddAttachment: () {},
            onRemoveAttachment: (_) {},
            onSubmit: () {},
          ),
          const Divider(height: 32),
          GovSubmitForm(
            entities: es,
            entity: es.first,
            category: es.first.categories.first,
            type: 'request',
            title: title,
            body: body,
            priority: 'urgent',
            anonymous: true,
            attachments: const [GovAttachment(name: 'proof-of-the-clash-with-a-long-file-name.pdf', url: 'https://example.org/f/1')],
            uploading: true,
            error: 'Choose an entity or a person',
            onEntity: (_) {},
            onCategory: (_) {},
            onType: (_) {},
            onPriority: (_) {},
            onAnonymous: (_) {},
            onAddAttachment: () {},
            onRemoveAttachment: (_) {},
            onSubmit: () {},
          ),
        ]),
      ),
    );
  });

  testWidgets('GovSettingsForm (rules mode with two routes, SLA fields, e-mail switch)', (tester) async {
    final s = GovSettings(mode: 'rules', rules: [RoutingRule(fromKind: 'service', toKind: 'scientific'), RoutingRule()], email: 'always');
    await expectNoLayoutErrors(tester, () => GovSettingsForm(settings: s, onChanged: () {}, onSave: () {}));
  });
}
