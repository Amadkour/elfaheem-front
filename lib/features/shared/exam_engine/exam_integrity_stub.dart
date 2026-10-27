// Mobile / desktop: the lifecycle observer in exam_integrity.dart does the work; nothing platform-specific here.
import '../../admin/admin_common.dart' show t;

void attach(void Function(String kind, Map<String, dynamic> meta) onEvent) {}

void detach() {}

List<String> capabilities() => [
      t('يُسجَّل خروج التطبيق إلى الخلفية', 'Leaving the app (background) is recorded'),
      t('لا تُمنع لقطات الشاشة على كل الأجهزة — تُسجَّل فقط حيث يسمح النظام', 'Screenshots cannot be blocked on every device — recorded only where the system allows'),
    ];
