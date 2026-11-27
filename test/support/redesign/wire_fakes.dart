// Phase 9 wiring (rd/fx-wire): fake answers for the routes that got their first screen — a parent's view of each
// child's payments and invoices (WP13, docs/redesign/api/parent_payments.md), the games nickname (WP4,
// api/games.md) and the teacher's booking slots (api/booking.md). On top of FakeApi, next to the group fakes.
import 'dart:typed_data';

import '../fake_api.dart';
import 'pa_fakes.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

DateTime get _now => DateTime.now().toUtc();

// ── parent payments ──────────────────────────────────────────────────────────

/// One row of GET /parent/children/{id}/payments.
Map<String, dynamic> wirePaymentRow(int id, {String status = 'completed', double amount = 449, String currency = 'SAR', String course = 'الرياضيات، مجموعة أ', int daysAgo = 6}) => {
      'id': id,
      'course_id': 1,
      'course_name': course,
      'amount': amount,
      'currency': currency,
      'status': status,
      'method': 'card',
      'paid_at': status == 'completed' || status == 'refunded' ? _iso(_now.subtract(Duration(days: daysAgo))) : null,
      'refunded_at': status == 'refunded' ? _iso(_now.subtract(Duration(days: daysAgo - 1))) : null,
      'created_at': _iso(_now.subtract(Duration(days: daysAgo))),
      'has_invoice': status == 'completed' || status == 'refunded',
      'invoice_number': status == 'completed' || status == 'refunded' ? 'INV-2026-${'$id'.padLeft(6, '0')}' : null,
    };

/// GET /parent/children/{id}/payments: [rows] (default: two paid, one in review, one refunded), filtered by `status`.
Map<String, dynamic> wirePayments(int childId, {List<Map<String, dynamic>>? rows, String? status}) {
  final all = rows ??
      [
        wirePaymentRow(1191),
        wirePaymentRow(1184, amount: 199, course: 'العلوم', daysAgo: 11),
        wirePaymentRow(1172, status: 'pending', amount: 199, course: 'الإنجليزي', daysAgo: 2),
        wirePaymentRow(1150, status: 'refunded', amount: 199, course: 'لغتي', daysAgo: 30),
      ];
  final items = [for (final r in all) if (status == null || status.isEmpty || r['status'] == status) r];
  return {
    'child': {'id': childId, 'name': paChildRow(childId)['name']},
    'items': items,
    'total': items.length,
  };
}

/// GET …/payments/{pid}/invoice. [vat] false = no VAT charged; [taxNumber] null = none set.
Map<String, dynamic> wireInvoice(int childId, int paymentId, {bool vat = true, String? taxNumber = '300123456700003', String status = 'completed', String currency = 'SAR'}) => {
      'invoice_number': 'INV-2026-${'$paymentId'.padLeft(6, '0')}',
      'payment_id': paymentId,
      'status': status,
      'issued_at': _iso(_now.subtract(const Duration(days: 6))),
      'refunded_at': status == 'refunded' ? _iso(_now.subtract(const Duration(days: 5))) : null,
      'currency': currency,
      'seller': {'country': 'SA', 'tax_number': taxNumber},
      'student': {'id': childId, 'name': paChildRow(childId)['name']},
      'billed_to': {'id': 3, 'name': 'أحمد سعد العنزي'},
      'course': {'id': 1, 'name': 'الرياضيات، مجموعة أ'},
      'method': 'card',
      'items': [
        {'key': 'course', 'label': 'الرياضيات، مجموعة أ', 'plan': 'monthly', 'amount': 420.0},
        {'key': 'discount', 'label': 'خصم القسيمة', 'amount': -30.0},
        {'key': 'platform_fee', 'label': 'رسوم الخدمة', 'amount': vat ? 0.43 : 59.0},
      ],
      'subtotal': vat ? 390.43 : 449.0,
      'vat': vat ? [{'label': 'ضريبة القيمة المضافة 15٪', 'percent': 15.0, 'amount': 58.57}] : [],
      'total': 449.0,
      'total_label': '449 ر.س',
    };

/// The parent's payment routes for every CAST child; [notLinked] answers 403 `child_not_linked` for that child.
Map<String, FakeHandler> wireParentRoutes({int? notLinked, bool vat = true, String? taxNumber = '300123456700003'}) => {
      for (final id in [paReem, paFaisal, paSara]) ...{
        'GET /api/v1/parent/children/$id/payments': (o) => id == notLinked
            ? const FakeResponse(403, {'detail': {'code': 'child_not_linked', 'message': 'الابن غير مرتبط بحسابك', 'message_en': 'This child is not linked to you'}})
            : wirePayments(id, status: o.uri.queryParameters['status']),
        'GET /api/v1/parent/children/$id/payments/1172/invoice': (_) =>
            const FakeResponse(409, {'detail': {'code': 'invoice_not_ready', 'message': 'الفاتورة غير جاهزة', 'message_en': 'The invoice is not ready'}}),
        'GET /api/v1/parent/children/$id/payments/*': (o) {
          final pid = int.tryParse(o.uri.pathSegments[o.uri.pathSegments.indexOf('payments') + 1]) ?? 0;
          if (o.uri.path.endsWith('/pdf')) return Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
          return wireInvoice(id, pid, vat: vat, taxNumber: taxNumber, status: pid == 1150 ? 'refunded' : 'completed');
        },
      },
    };

// ── games nickname ───────────────────────────────────────────────────────────

/// GET /me/games/nickname. [lockedDays] > 0 = the name may change only after that many days.
Map<String, dynamic> wireNickname({String nickname = 'صقر الأرقام', int lockedDays = 0, String icon = 'bolt', String color = 'y'}) => {
      'nickname': nickname,
      'avatar': {'icon': icon, 'color': color},
      'source': lockedDays > 0 ? 'custom' : 'generated',
      'can_change_at': lockedDays > 0 ? _iso(_now.add(Duration(days: lockedDays))) : null,
      'icons': ['bolt', 'star', 'rocket', 'moon', 'target', 'crown', 'fire', 'sparkle', 'heart', 'leaf'],
      'colors': ['b', 'y', 'o', 'n', 'p', 't', 'k', 'g'],
    };

/// The nickname routes; a PUT with a name containing a digit run answers 422 `contact`, «نسر نجد» 409 taken.
Map<String, FakeHandler> wireNicknameRoutes({int lockedDays = 0}) => {
      'GET /api/v1/me/games/nickname': (_) => wireNickname(lockedDays: lockedDays),
      'GET /api/v1/me/games/nickname/suggestions': (_) => {
            'items': ['نسر نجد', 'برق الحساب', 'نجم المعادلات', 'فارس الحروف', 'قمر العلوم'],
          },
      'PUT /api/v1/me/games/nickname': (o) {
        final body = o.data is Map ? o.data as Map : const {};
        final name = '${body['nickname'] ?? ''}';
        if (RegExp(r'\d{4,}').hasMatch(name)) {
          return const FakeResponse(422, {'detail': {'code': 'nickname_invalid', 'reason': 'contact', 'message': 'لا تكتب رقماً', 'message_en': 'No numbers'}});
        }
        if (name == 'نسر نجد') {
          return const FakeResponse(409, {'detail': {'code': 'nickname_taken', 'message': 'الاسم مأخوذ', 'suggestions': ['نسر الجنوب', 'نسر الشمال', 'نسر السهول']}});
        }
        final av = body['avatar'] is Map ? body['avatar'] as Map : const {};
        return wireNickname(nickname: name.isEmpty ? 'صقر الأرقام' : name, lockedDays: name.isEmpty ? 0 : 14, icon: '${av['icon'] ?? 'bolt'}', color: '${av['color'] ?? 'y'}');
      },
    };

// ── teacher booking slots ────────────────────────────────────────────────────

/// One TeacherSlot (math = subject 100, grade 21 = second intermediate).
Map<String, dynamic> wireSlot(int id, {int day = 1, int hour = 16, String status = 'open', int subject = 100, int? grade = 21}) {
  final at = DateTime.utc(_now.year, _now.month, _now.day + day, hour);
  return {
    'id': id, 'edu_subject_id': subject, 'grade_id': grade, 'mode': 'remote', 'centre_id': null,
    'starts_at': _iso(at), 'next_at': _iso(at), 'weekly': true, 'minutes': 50, 'status': status,
    'booking_id': status == 'taken' ? 7 : null,
    'student': status == 'taken' ? {'user_id': 41, 'name': 'ريم العنزي'} : null,
  };
}

Map<String, FakeHandler> wireSlotRoutes({List<Map<String, dynamic>>? slots}) => {
      'GET /api/v1/booking/teacher/slots': (_) => {'items': slots ?? [wireSlot(90), wireSlot(91, day: 3, hour: 18, status: 'taken')]},
      'POST /api/v1/booking/teacher/slots': (o) {
        final body = o.data is Map ? o.data as Map : const {};
        return FakeResponse(201, {...wireSlot(92), 'edu_subject_id': body['edu_subject_id'], 'starts_at': body['starts_at']});
      },
      'DELETE /api/v1/booking/teacher/slots/91': (_) =>
          const FakeResponse(409, {'detail': {'code': 'slot_taken', 'message': 'الموعد محجوز لطالب', 'message_en': 'A student booked this time'}}),
      'DELETE /api/v1/booking/teacher/slots/*': (_) => {'ok': true},
    };
