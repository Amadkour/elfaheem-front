// The governance screens on the dashboard's pushed-page header (OrgPushedPage, D-103): every screen family's
// plain-values body under Back · a long Arabic title · its context line · the primary action · Refresh · switcher,
// at 320x640 and 1400x900, Arabic and English, text x1.3 — never an overflow, the Back button and the switcher there.
//
// Families: an entity (tabs on top of the body) · the item list (New item in the header) · one item (body + the
// comment composer at the bottom) · a council session (header + agenda) · my votes · the submit form · my items
// (New request in the header) · the routing settings form · the council settings form · delegations.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/governance/gov_council_settings.dart';
import 'package:flutter_education_app/features/org/governance/gov_delegations_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_entities_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_item_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_items_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_member_pages.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_my_votes.dart';
import 'package:flutter_education_app/features/org/governance/gov_session_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_settings_page.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_education_app/features/org/org_page_kit.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../org/gov_council_models_test.dart' show myVotesJson, sessionJson;
import '../org/gov_filter_test.dart' show sampleDelegationJson, sampleEntityJson, sampleItemJson;
import '../support/fake_api.dart';
import 'layout_harness.dart';

const _longAr = 'مجلس قسم علوم الحاسب والذكاء الاصطناعي ونظم المعلومات — مرحلتا البكالوريوس والدراسات العليا';
const _longSub = 'قسم علمي · CSAI · كلية الهندسة والتكنولوجيا وعلوم الحاسب بجامعة النيل الأهلية';

OrgSession _session() => OrgSession()
  ..loaded = true
  ..items = [
    {
      'id': 4,
      'name_ar': 'كلية الهندسة والتكنولوجيا وعلوم الحاسب بجامعة النيل الأهلية',
      'name_en': 'Faculty of Engineering, Technology and Computer Science — Nile National University',
      'type': 'faculty',
      'status': 'approved',
      'my_role': 'org_admin',
      'access': 'admin',
      'depth': 0,
    },
  ]
  ..currentId = 4;

List<Entity> _entities() => [
      Entity.fromJson(sampleEntityJson()),
      Entity.fromJson(sampleEntityJson(kind: 'service', id: 2)),
      Entity.fromJson(sampleEntityJson(kind: 'office', id: 3)),
    ];

/// [child] under OrgPushedPage with the open organization, the way the screens push it.
Widget _pushed(OrgSession s, Widget child, {String title = _longAr, String? subtitle = _longSub, Widget? primary, OrgPageRefresh? refresh}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider<OrgSession>.value(value: s),
      ],
      child: OrgPushedPage(title: title, subtitle: subtitle, primaryAction: primary, refresh: refresh, child: child),
    );

Future<void> _expectHeader(WidgetTester tester) async {
  expect(find.byKey(const ValueKey('org.header.back')), findsOneWidget);
  expect(find.byKey(const ValueKey('org.header.switcher')), findsOneWidget);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  testWidgets('the decision: staff of the open organization get the header, another one / no session keep the app bar', (tester) async {
    final s = _session();
    late bool mine, other;
    await tester.pumpWidget(ChangeNotifierProvider<OrgSession>.value(
      value: s,
      child: Builder(builder: (context) {
        mine = orgUsesDashboardHeader(context, 4);
        other = orgUsesDashboardHeader(context, 77);
        return const SizedBox();
      }),
    ));
    expect(mine, isTrue);
    expect(other, isFalse);
    late bool none;
    await tester.pumpWidget(Builder(builder: (context) {
      none = orgUsesDashboardHeader(context, 4);
      return const SizedBox();
    }));
    expect(none, isFalse);
  });

  testWidgets('entity: the tabs head the body, cards and categories below', (tester) async {
    final s = _session();
    final es = _entities();
    await expectNoLayoutErrors(
      tester,
      () => DefaultTabController(
        length: 3,
        child: _pushed(
          s,
          Column(children: [
            const TabBar(tabs: [Tab(text: 'المعاملات'), Tab(text: 'التصنيفات'), Tab(text: 'التفويض')]),
            Expanded(
              child: ListView(children: [
                GovEntityCard(entity: es[0], onTap: () {}, onChangeKind: () {}),
                GovCategoryTile(category: es[0].categories[0], formTitle: 'Exam delay request form', onEdit: () {}, onDeactivate: () {}),
              ]),
            ),
          ]),
        ),
      ),
      act: _expectHeader,
    );
  });

  testWidgets('item list: New item as the primary action, the cards below', (tester) async {
    final s = _session();
    final it = WorkItem.fromJson(sampleItemJson(full: false));
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        ListView(children: [for (var i = 0; i < 4; i++) GovItemCard(item: it, onTap: () {})]),
        primary: OrgPrimaryButton(action: OrgPrimaryAction(id: 'gov.new_item', icon: Icons.add_rounded, label: 'معاملة جديدة', onTap: () {})),
      ),
      act: (tester) async {
        await _expectHeader(tester);
        expect(find.byKey(const ValueKey('org.page.gov.new_item')), findsOneWidget);
      },
    );
  });

  testWidgets('one item: the body scrolls, the comment composer stays at the bottom', (tester) async {
    final s = _session();
    final refresh = OrgPageRefresh();
    addTearDown(refresh.dispose);
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        Column(children: [
          Expanded(
            child: GovItemBody(
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
          ),
          GovCommentComposer(onSend: (_, _) async => true, allowInternal: true),
        ]),
        title: 'REQ-2026-000123',
        subtitle: 'طلب · قيد المراجعة · إدارة شؤون الطلاب والخريجين والدراسات العليا',
        refresh: refresh,
      ),
      act: (tester) async {
        await _expectHeader(tester);
        expect(find.byKey(const ValueKey('org.header.updated')), findsWidgets);
      },
    );
  });

  testWidgets('council session: header and agenda', (tester) async {
    final s = _session();
    final voting = CouncilSession.fromJson(sessionJson());
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        ListView(children: [
          SessionHeader(session: voting, now: DateTime.utc(2026, 11, 16, 7)),
          for (final a in voting.agenda) AgendaRow(agenda: a, sessionStatus: 'voting', canVote: true, showResult: true, onVote: (_, _) async {}),
        ]),
        subtitle: 'جلسة دورية · التصويت مفتوح',
      ),
      act: _expectHeader,
    );
  });

  testWidgets('my votes: the groups', (tester) async {
    final s = _session();
    final groups = groupMyVotes([for (final x in myVotesJson()) MyVoteEntry.fromJson(x)]);
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        ListView(children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: MyVoteGroupCard(group: g, now: DateTime.utc(2026, 11, 16, 7), onVote: (_, _, _) async {}, onOpenSession: () {}),
            ),
        ]),
        title: 'تصويتاتي في كل مجالس الكلية والأقسام العلمية',
        subtitle: null,
      ),
      act: _expectHeader,
    );
  });

  testWidgets('submit form, and my items with New request in the header', (tester) async {
    final s = _session();
    final title = TextEditingController(text: 'طلب تأجيل امتحان منتصف الفصل بسبب تعارض'), body = TextEditingController(text: 'التفاصيل');
    addTearDown(title.dispose);
    addTearDown(body.dispose);
    final es = _entities();
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: GovSubmitForm(
            entities: es,
            entity: es.first,
            category: es.first.categories.first,
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
        ),
        title: 'معاملة جديدة إلى إدارة شؤون الطلاب والخريجين',
        subtitle: null,
      ),
      act: _expectHeader,
    );
    final it = WorkItem.fromJson(sampleItemJson(full: false));
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        ListView(children: [for (var i = 0; i < 3; i++) GovItemCard(item: it, member: true, onTap: () {})]),
        title: 'معاملاتي وما أُحيل إليّ شخصياً من كل الجهات',
        subtitle: null,
        primary: OrgHeaderButton(icon: Icons.add_rounded, label: 'معاملة جديدة', onTap: () {}),
      ),
      act: _expectHeader,
    );
  });

  testWidgets('routing settings and council settings forms', (tester) async {
    final s = _session();
    final gs = GovSettings(mode: 'rules', rules: [RoutingRule(fromKind: 'service', toKind: 'scientific'), RoutingRule()], email: 'always');
    await expectNoLayoutErrors(
      tester,
      () => _pushed(s, GovSettingsForm(settings: gs, onChanged: () {}, onSave: () {}), title: 'إعدادات الطلبات والإحالات بين الجهات والمجالس', subtitle: null),
      act: _expectHeader,
    );
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          child: GovCouncilSettingsForm(
            settings: CouncilSettings(tieRule: 'chair', noVoteRule: 'abstain', abstainCounts: true),
            onSave: (_) {},
            members: const {1: 'أ.د. عميد الكلية', 2: 'Dr. Second Member with a long name'},
            headName: 'أ.د. عميد الكلية',
          ),
        ),
        subtitle: 'إعدادات المجلس',
      ),
      act: _expectHeader,
    );
  });

  testWidgets('delegations: active and past cards', (tester) async {
    final s = _session();
    await expectNoLayoutErrors(
      tester,
      () => _pushed(
        s,
        ListView(children: [
          GovDelegationCard(delegation: Delegation.fromJson(sampleDelegationJson()), onRevoke: () {}, categoryName: (id) => 'Category $id', formTitle: (id) => 'Form $id'),
          GovDelegationCard(delegation: Delegation.fromJson(sampleDelegationJson(mode: 'global', revoked: true)), showEntity: true),
        ]),
        title: 'التفويض',
        subtitle: 'إدارة شؤون الطلاب والخريجين والدراسات العليا بكلية الهندسة',
      ),
      act: _expectHeader,
    );
  });
}
