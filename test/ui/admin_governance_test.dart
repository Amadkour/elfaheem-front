// Admin governance (docs/redesign/api/governance.md): the plain-values parts of the publish queue, the audit log and
// the roles editor at 320x640 and 1400x900, Arabic + English, textScaler 1.3; the parsing of the server's answers.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/governance/admin_roles_page.dart';
import 'package:flutter_education_app/features/admin/governance/audit_log_page.dart';
import 'package:flutter_education_app/features/admin/governance/gov_api.dart';
import 'package:flutter_education_app/features/admin/governance/publish_queue_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة في الرياضيات التطبيقية والإحصاء الحيوي للمرحلة الثانوية مع تمارين محلولة ومراجعات أسبوعية';

final _now = DateTime.utc(2026, 11, 27, 12);

final _pending = PublishItem.fromJson({
  'course_id': 7,
  'name_ar': _long,
  'name_en': 'A complete introduction to applied mathematics and biostatistics with solved exercises',
  'teacher': {'id': 3, 'name': 'أ. ماجد عبد الرحمن الشهري القحطاني'},
  'review_status': 'pending_review',
  'submitted_at': '2026-11-23T08:00:00Z',
});

final _rejected = PublishItem.fromJson({
  'course_id': 8,
  'name_ar': 'دورة ب',
  'teacher': {'id': 3, 'name': 'أ. ماجد'},
  'review_status': 'rejected',
  'review_reason': 'الصورة غير واضحة والوصف قصير جداً، أضف أهداف الدورة ومحتوى كل وحدة قبل إعادة الإرسال',
  'decided_at': '2026-11-26T08:00:00Z',
});

final _row = AuditRow.fromJson({
  'id': 1,
  'at': '2026-11-27T09:30:00Z',
  'actor': {'id': 1, 'name': 'سارة المديرة العامة للمنصة التعليمية', 'role': 'super-admin'},
  'method': 'PUT',
  'path': '/api/v1/admin/booking/centres/{centre_id}',
  'action': 'PUT /admin/booking/centres/{centre_id}',
  'target': {'type': 'centres', 'id': '12'},
  'status_code': 422,
  'ip': '2001:db8:85a3::8a2e:370:7334',
  'user_agent': 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Mobile',
  'summary': 'name_ar=مركز النرجس, district_id=4, password=***',
  'changes': {'name_ar': 'مركز النرجس', 'password': '***'},
});

final _catalog = RolesOverview.fromJson({
  'catalog': [
    {
      'id': 'courses',
      'title_ar': 'الدورات',
      'title_en': 'Courses',
      'items': [
        {'key': 'courses.review', 'title_ar': 'مراجعة نشر الدورات', 'title_en': 'Review course publishing'},
        {'key': 'courses.manage', 'title_ar': 'تعديل الدورات وحذفها', 'title_en': 'Edit and delete courses'},
      ],
    },
    {
      'id': 'oversight',
      'title_ar': 'الرقابة',
      'title_en': 'Oversight',
      'items': [
        {'key': 'audit.view', 'title_ar': 'سجل عمليات الإدارة', 'title_en': 'Admin activity log'},
      ],
    },
  ],
}).catalog;

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('parsing', () {
    expect(_pending.courseId, 7);
    expect(_pending.submittedAt, DateTime.utc(2026, 11, 23, 8));
    expect(_rejected.reason, startsWith('الصورة'));
    expect(_row.ok, isFalse);
    expect(_row.target, 'centres #12');
    const f = AuditFilter(actorId: 2, action: 'roles');
    expect(f.query(), {'actor_id': 2, 'action': 'roles'});
    expect(AuditFilter(from: DateTime(2026, 1, 5), to: DateTime(2026, 2, 9)).query(),
        {'date_from': '2026-01-05', 'date_to': '2026-02-09'});
    expect(_catalog.map((g) => g.items.length), [2, 1]);
  });

  testWidgets('publish queue cards', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        PublishQueueCard(item: _pending, now: _now, onApprove: () {}, onReject: () {}),
        PublishQueueCard(item: _rejected, now: _now),
      ]),
    );
  });

  testWidgets('audit log row and details', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [AuditLogTile(row: _row, onTap: () {}), AuditLogDetails(row: _row)]),
    );
  });

  testWidgets('role permissions editor', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: RolePermissionsEditor(catalog: _catalog, selected: const {'courses.review'}, onChanged: (_, _) {}),
      ),
    );
  });
}
