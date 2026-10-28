// The assistant notices' deep links (lib/features/shared/rag/rag_admin_links.dart): module → page, by role and
// kill switch.
import 'package:flutter_education_app/features/shared/rag/rag_admin_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the assistant notices are mapped', () {
    for (final m in [null, '', 'notifications', 'course', 'rag', 'points']) {
      expect(ragAdminTarget(m, role: 'super-admin'), isNull, reason: '$m');
    }
  });

  test('a platform admin opens the Learning page / the Alerts tab', () {
    for (final role in ['admin', 'super-admin', 'developer']) {
      expect(ragAdminTarget('rag_learning', role: role), RagAdminTarget.learning);
      expect(ragAdminTarget('rag_alerts', role: role), RagAdminTarget.alerts);
    }
  });

  test('anyone else lands on the notifications list', () {
    for (final role in [null, 'student', 'teacher', 'parent', 'org-admin', 'org-staff']) {
      expect(ragAdminTarget('rag_learning', role: role), RagAdminTarget.notifications, reason: '$role');
      expect(ragAdminTarget('rag_alerts', role: role), RagAdminTarget.notifications, reason: '$role');
    }
  });

  test('the kill switches are respected', () {
    expect(ragAdminTarget('rag_learning', role: 'super-admin', disabled: ['rag.learning']),
        RagAdminTarget.notifications);
    expect(ragAdminTarget('rag_alerts', role: 'super-admin', disabled: ['rag.learning']),
        RagAdminTarget.alerts);
    expect(ragAdminTarget('rag_learning', role: 'super-admin', disabled: ['rag.admin']),
        RagAdminTarget.notifications);
    expect(ragAdminTarget('rag_alerts', role: 'admin', disabled: ['rag.admin']),
        RagAdminTarget.notifications);
  });
}
