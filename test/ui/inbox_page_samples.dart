// Sample answers for the inbox page (lib/features/messaging/inbox/inbox_page.dart) on the fake backend
// (test/support/fake_api.dart): GET /me/inbox (the real row shape of routers/organization/org_me_router.py) and
// GET /notifications (the list's real shape, with the server's `unread`). Realistic Arabic / English text, picked by
// AppConfig.lang when the request is answered. Used by test/ui/inbox_page_test.dart and the visual renders
// (test/visual/inbox_golden_test.dart).
import 'package:flutter_education_app/config/app_config.dart';

import '../support/fake_api.dart';

String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;
String _iso(DateTime d) => d.toUtc().toIso8601String();

const _uni = {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'};
const _affairs = {'id': 11, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs'};

Map<String, dynamic> _row(String key, String kind, String segment, String ar, String en,
        {String subAr = '', String subEn = '', Duration? due, Duration created = const Duration(hours: 30), bool mandatory = false,
        String status = '', Map<String, dynamic> action = const {}, Map<String, dynamic> data = const {}, bool org = true}) =>
    {
      'key': key,
      'kind': kind,
      'segment': segment,
      'title': _tr(ar, en),
      'subtitle': _tr(subAr, subEn),
      'org_id': org ? 4 : null,
      'organization': org ? _uni : null,
      'department': org && kind != 'ad' ? _affairs : null,
      'due_at': due == null ? null : _iso(DateTime.now().add(due)),
      'created_at': _iso(DateTime.now().subtract(created)),
      'status': status,
      'mandatory': mandatory,
      'urgency': 'normal',
      'action': action,
      'data': data,
    };

/// Two to-dos (one overdue, one due soon), a new announcement, an offer and two done requests.
Map<String, dynamic> inboxSample() {
  final items = [
    _row('form:1', 'form', 'todo', 'استمارة تحديث البيانات', 'Update your details form',
        subAr: 'مطلوبة قبل التسجيل للفصل القادم', subEn: 'Needed before you register for next term',
        due: const Duration(hours: -5), mandatory: true, action: {'type': 'form', 'id': 1}),
    _row('availability:2', 'availability', 'todo', 'حدد مواعيدك المتاحة للأسبوع القادم', 'Pick your free slots for next week',
        due: const Duration(hours: 30), action: {'type': 'availability', 'id': 2}),
    _row('announcement:3', 'announcement', 'news', 'تعديل موعد امتحان الإحصاء', 'Statistics exam moved',
        subAr: 'يُعقد الامتحان يوم الأحد في القاعة 3 بدلًا من الخميس.',
        subEn: 'The exam is now on Sunday in hall 3 instead of Thursday.',
        created: const Duration(hours: 4), action: {'type': 'announcement', 'id': 3}),
    _row('ad:9', 'ad', 'offers', 'خصم 30% على دورة تحليل البيانات', '30% off the Data Analysis course',
        subAr: 'العرض سارٍ حتى نهاية الأسبوع', subEn: 'Until the end of the week',
        due: const Duration(days: 4), org: false,
        action: {'type': 'ad', 'id': 9}, data: {'target_type': 'none', 'media_type': 'none', 'likes': 12, 'dislikes': 1}),
    _row('request:5', 'request', 'done', 'طلب إفادة قيد', 'Enrolment letter request',
        subAr: 'جاهزة للاستلام من شؤون الطلاب', subEn: 'Ready to collect at Student affairs',
        status: 'approved', created: const Duration(days: 3), action: {'type': 'request', 'id': 5}, data: {'ref': 'R-000005'}),
    _row('request:6', 'request', 'done', 'طلب تغيير المجموعة', 'Group change request',
        status: 'rejected', created: const Duration(days: 8), action: {'type': 'request', 'id': 6}, data: {'ref': 'R-000006'}),
  ];
  return {
    'items': items,
    'counts': {'todo': 2, 'news': 1, 'offers': 1, 'done': 2, 'overdue': 1, 'due_soon': 1, 'mandatory': 1},
  };
}

Map<String, dynamic> _notif(int id, String ar, String en, String msgAr, String msgEn, String type, String related,
        {bool read = false, Duration ago = const Duration(hours: 1)}) =>
    {
      'id': id,
      'title': _tr(ar, en),
      'message': _tr(msgAr, msgEn),
      'is_read': read,
      'type': type,
      'related_type': related,
      'related_id': 1,
      'created_at': DateTime.now().subtract(ago).toIso8601String(),
    };

/// Three unread notifications today and two read ones from yesterday.
Map<String, dynamic> notificationsSample() => {
      'items': [
        _notif(1, 'بدأت محاضرة قواعد البيانات', 'Databases lecture has started', 'انضم الآن من صفحة المقرر.',
            'Join now from the course page.', 'session_started', 'session', ago: const Duration(minutes: 8)),
        _notif(2, 'تم رصد درجة اختبار الوحدة الثانية', 'Unit 2 quiz is graded', 'حصلت على 18 من 20.', 'You scored 18 out of 20.',
            'exam_graded', 'exam', ago: const Duration(hours: 2)),
        _notif(3, 'رد جديد على شكواك', 'New reply to your complaint', 'ردّ فريق الدعم الفني على شكواك رقم 41.',
            'The support team replied to complaint #41.', 'complaint_reply', 'complaint', ago: const Duration(hours: 3)),
        _notif(4, 'تسجيل محاضرة الإحصاء متاح', 'Statistics recording is ready', 'يمكنك مشاهدته الآن.', 'You can watch it now.',
            'recording_ready', 'session', read: true, ago: const Duration(days: 1, hours: 2)),
        _notif(5, 'تم تجديد اشتراكك', 'Your plan was renewed', 'تم خصم 150 جنيهًا.', 'EGP 150 was charged.', 'payment_success',
            'payment', read: true, ago: const Duration(days: 1, hours: 6)),
      ],
      'total': 5,
      'unread': 3,
    };

/// The routes the inbox page touches.
Map<String, FakeHandler> inboxRoutes({bool empty = false}) => {
      'GET /api/v1/me/inbox': (_) => empty ? {'items': [], 'counts': {}} : inboxSample(),
      'GET /api/v1/notifications': (_) => empty ? {'items': [], 'total': 0, 'unread': 0} : notificationsSample(),
      'PUT /api/v1/notifications/read-all': (_) => {'ok': true},
    };
