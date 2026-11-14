// Master-detail phase 9, gaps B (D-290): the mentions converted on admin, organization and shared screens are links
// to the record only when the server says so (`POST /entities/access`, faked through `EntityAccess.debugAsk`), and a
// payload without the new fields (an older server) keeps the plain text.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entity_access.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart' show PendingTransfer;
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/org_services_pages.dart';
import 'package:flutter_education_app/features/parent/parent_org_view.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_issue_lists.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_issue_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../org/adv_case_models_test.dart' show sampleAdvProfileJson;
import '../layout_harness.dart';

const _wide = Size(1200, 900);

late List<List<String>> _asked;

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.binding.setSurfaceSize(_wide);
  t.view.physicalSize = _wide;
  t.view.devicePixelRatio = 1;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(layoutHost(child, scaffold: true));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The review queue with its rows already loaded (the screen reads only these).
class _Transfers extends TeacherTransfersProvider {
  _Transfers(this._rows) {
    hasLoaded = true;
  }
  final List<PendingTransfer> _rows;

  @override
  List<PendingTransfer> get items => _rows;

  @override
  Future<void> ensureLoaded() async {}
}

/// The guarded chips drawn as links (the server allowed them).
Iterable<EntityGuardedChip> _chips(WidgetTester t) => t.widgetList<EntityGuardedChip>(find.byType(EntityGuardedChip));

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    _asked = [];
    EntityAccess.instance
      ..clear()
      ..debugAsk = (tokens) async {
        _asked.add(tokens);
        return {'student:7', 'course:40'};
      };
  });
  tearDown(() => EntityAccess.instance.debugAsk = null);

  testWidgets('transfer requests: the student and the course are guarded chips, asked once', (t) async {
    final prov = _Transfers([
      PendingTransfer.fromJson({
        'payment_id': 1, 'course_id': 40, 'student_id': 7, 'course_name': 'Algebra', 'student_name': 'Sara',
        'method': 'instapay', 'amount': 100, 'currency': 'EGP', 'sender_name': 'Sara', 'proof_image_url': '',
        'submitted_at': '2026-11-06T10:00:00Z', 'status': 'pending',
      }),
    ]);
    await _pump(t, ChangeNotifierProvider<TeacherTransfersProvider>.value(value: prov, child: const TeacherTransfersScreen()));
    expect(_chips(t).map((c) => c.ref.toToken()), ['student:7', 'course:40']);
    expect(_asked, [
      ['student:7', 'course:40'],
    ]);
  });

  testWidgets('certificate list: a person on the platform is a guarded student chip, a newcomer plain text', (t) async {
    const list = RecipientListInfo(id: 1, name: 'October', rows: [
      {'values': {'student_name': 'Sara'}, 'student_id': 7},
      {'values': {'student_name': 'Guest Person'}},
    ]);
    await _pump(t, const CertListBody(list: list, columns: []));
    expect(_chips(t).map((c) => c.ref.toToken()), ['student:7']);
    expect(find.text('Guest Person'), findsOneWidget);
  });

  testWidgets('parent organization view: course_id makes the grade a guarded course chip; an older server keeps text', (t) async {
    final view = ParentOrgView.parse({
      'org': {'id': 3, 'name_en': 'Uni'},
      'grades': [
        {'course_id': 40, 'course_name': 'Algebra', 'grade': 'A'},
        {'course_name': 'Physics', 'grade': 'B'},
      ],
    });
    expect([for (final g in view.grades) g.courseId], [40, null]);
    await _pump(t, ParentOrgBody(view: view, childName: 'Sara'));
    expect(_chips(t).map((c) => c.ref.toToken()), ['course:40']);
    expect(find.text('Physics'), findsOneWidget);
  });

  testWidgets('org form response / complaint: person_kind draws the guarded chip; a hidden identity stays text', (t) async {
    expect(OrgPersonFrom.refOf({'id': 7, 'name': 'Sara', 'person_kind': 'student'})?.toToken(), 'student:7');
    expect(OrgPersonFrom.refOf({'id': 9, 'name': 'Dr. Omar', 'person_kind': 'teacher'})?.toToken(), 'teacher:9');
    expect(OrgPersonFrom.refOf({'id': 5, 'name': 'Staff', 'person_kind': null}), isNull);
    expect(OrgPersonFrom.refOf({'id': null, 'name': 'Hidden'}), isNull);
    await _pump(
        t,
        const Column(children: [
          OrgPersonFrom('From', {'id': 7, 'name': 'Sara', 'person_kind': 'student'}),
          OrgPersonFrom('From', {'id': null, 'name': 'Hidden', 'person_kind': null}),
        ]));
    expect(_chips(t).map((c) => c.ref.toToken()), ['student:7']);
    expect(find.text('Hidden'), findsOneWidget);
  });

  testWidgets('advising student 360: the header links the student record (guarded)', (t) async {
    final p = AdvCaseProfile.fromJson(sampleAdvProfileJson(manage: false));
    await _pump(t, SingleChildScrollView(child: AdvStudentHeader(profile: p)));
    expect(_chips(t).map((c) => c.ref.toToken()), ['student:${p.userId}']);
  });
}
