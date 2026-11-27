// lib/features/booking/booking_api.dart
//
// The booking routes (docs/redesign/api/booking.md), the payment methods for this payer (payments.md §1) and the
// subject's assistant gate (meetings_bot.md). Steps 1 – 3 and the methods work signed out; quote, confirm, pay,
// cancel and notify need a signed-in student (a guest never sends a write: ApiClient refuses it on the device).
// A parent books for a linked child by passing the child's id ([BookingApi.studentId], owner 2026-11-27; the server
// answers 403 `child_not_linked` for anyone else). A bank transfer: confirm / pay with `bank_transfer`, then
// [BookingApi.sendTransfer] uploads the proof the team reviews.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';

/// The kill switches (enforced on the server too).
const String kBookingKey = 'booking';
const String kBookingInPersonKey = 'booking.in_person';
const String kBookingIndividualKey = 'booking.individual';
const String kBookingProposalsKey = 'booking.proposals';

bool bookingOff() => AppConfig.disableList.contains(kBookingKey);

/// The server's bilingual message for a booking error.
String bkErrorText(Object e) {
  final x = ApiException.from(e);
  final d = apiErrorDetail(x);
  if (AppConfig.lang != 'ar' && d['message_en'] is String) return d['message_en'] as String;
  if (d['message'] is String) return d['message'] as String;
  return apiErrorText(x);
}

/// The server's error code (`group_full`, `slot_taken` …), or null.
String? bkErrorCode(Object e) {
  final x = ApiException.from(e);
  final d = apiErrorDetail(x);
  return (d['code'] as String?) ?? x.code;
}

class BookingApi {
  BookingApi({ApiClient? client, this.studentId}) : _c = client ?? ApiClient();

  final ApiClient _c;
  static const _b = '/api/v1/booking';

  /// The linked child a parent books for; null = the signed-in student.
  final int? studentId;

  Map<String, dynamic> _q(Map<String, Object?> m) => {
        for (final e in {...m, 'student_id': studentId}.entries)
          if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
      };

  Map<String, dynamic> _body(Map<String, dynamic> m) => {...m, 'student_id': ?studentId};

  Future<BkOptions> options({required int subjectId, required int gradeId, String? gender}) async => BkOptions.fromJson(
        await _c.get('$_b/options', queryParams: _q({'subject_id': subjectId, 'grade_id': gradeId, 'gender': gender})),
      );

  Future<BkCentres> centres() async => BkCentres.fromJson(await _c.get('$_b/centres', queryParams: _q({})));

  Future<BkGroups> groups({
    required int subjectId,
    required int gradeId,
    required String mode,
    int? centreId,
    String? gender,
  }) async =>
      BkGroups.fromJson(await _c.get('$_b/groups',
          queryParams: _q({'subject_id': subjectId, 'grade_id': gradeId, 'mode': mode, 'centre_id': centreId, 'gender': gender})));

  Future<List<BkSlotTeacher>> slots({
    required int subjectId,
    required int gradeId,
    required String mode,
    int? centreId,
    String? gender,
  }) async {
    final r = await _c.get('$_b/slots',
        queryParams: _q({'subject_id': subjectId, 'grade_id': gradeId, 'mode': mode, 'centre_id': centreId, 'gender': gender}));
    return [for (final m in bkMaps(bkMap(r)['items'])) BkSlotTeacher.fromJson(m)];
  }

  Future<BkQuote> quote(BkRequest r) async => BkQuote.fromJson(await _c.post('$_b/quote', body: _body(r.toJson())));

  Future<BkConfirmResult> confirm(BkRequest r, {String? provider, String? coupon}) async =>
      BkConfirmResult.fromJson(await _c.post('$_b/confirm', body: _body({
        ...r.toJson(),
        'provider': ?provider,
        'coupon_code': ?coupon,
        'lang': AppConfig.lang,
      })));

  Future<List<BkBooking>> mine({int? subjectId}) async {
    final r = await _c.get('$_b/me', queryParams: _q({'subject_id': subjectId}));
    final items = r is List ? r : bkMap(r)['items'];
    return [for (final m in bkMaps(items)) BkBooking.fromJson(m)];
  }

  Future<BkConfirmResult> pay(int bookingId, {String? provider}) async => BkConfirmResult.fromJson(
      await _c.post('$_b/$bookingId/pay', body: _body({'provider': ?provider, 'lang': AppConfig.lang})));

  Future<BkBooking> cancel(int bookingId) async =>
      BkBooking.fromJson(bkMap(await _c.post('$_b/$bookingId/cancel', body: _body({})))['booking']);

  /// The bank-transfer proof of a held seat (multipart). The answer: the booking with `transfer.status: pending`.
  Future<BkBooking> sendTransfer(
    int bookingId, {
    required String senderName,
    String? senderPhone,
    String? reference,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async =>
      BkBooking.fromJson(bkMap(await _c.postMultipart(
        '$_b/$bookingId/transfer',
        fields: {
          'sender_name': senderName,
          if ((senderPhone ?? '').trim().isNotEmpty) 'sender_phone': senderPhone!.trim(),
          if ((reference ?? '').trim().isNotEmpty) 'transfer_reference': reference!.trim(),
          if (studentId != null) 'student_id': '$studentId',
        },
        fileField: 'proof_image',
        fileName: fileName,
        filePath: filePath,
        fileBytes: fileBytes,
      ))['booking']);

  Future<BkBooking> notifyGroup(int groupId) async => BkBooking.fromJson(
      bkMap(await _c.post('$_b/groups/$groupId/notify', queryParams: _q({})))['booking']);

  Future<void> unnotifyGroup(int groupId) => _c.delete('$_b/groups/$groupId/notify', queryParams: _q({}));

  Future<BkBooking> notifyOtherTime({
    required int subjectId,
    required int gradeId,
    required String mode,
    int? centreId,
    String? gender,
  }) async =>
      BkBooking.fromJson(bkMap(await _c.post('$_b/notify-other-time', body: _body({
        'subject_id': subjectId,
        'grade_id': gradeId,
        'mode': mode,
        'centre_id': ?centreId,
        'gender': ?gender,
      })))['booking']);

  /// The methods this payer can use, VAT and the "≈" amount (sign-in optional).
  Future<BkPayInfo> payMethods({double? amount}) async => BkPayInfo.fromJson(await _c.get('/api/v1/payments/methods',
      queryParams: _q({'amount': amount, 'lang': AppConfig.lang})));
}

/// GET /me/assistant/subject: may the subject page show its assistant, and with which scope.
class BkAssistantGate {
  const BkAssistantGate({required this.on, this.reason, this.message, this.courseId, this.orgId, this.title});

  factory BkAssistantGate.fromJson(Object? raw) {
    final m = bkMap(raw);
    final ar = AppConfig.lang == 'ar';
    final s = bkMap(m['scope']);
    return BkAssistantGate(
      on: m['state'] == 'on',
      reason: bkStr(m['reason']),
      message: ar ? bkStr(m['message_ar']) ?? bkStr(m['message_en']) : bkStr(m['message_en']) ?? bkStr(m['message_ar']),
      courseId: bkInt(s['course_id']),
      orgId: bkInt(s['org_id']),
      title: ar ? bkStr(m['title_ar']) ?? bkStr(m['title_en']) : bkStr(m['title_en']) ?? bkStr(m['title_ar']),
    );
  }

  final bool on;

  /// feature_off | not_subscribed | not_enrolled
  final String? reason;
  final String? message, title;
  final int? courseId, orgId;
}

Future<BkAssistantGate> fetchSubjectAssistant(int courseId, {ApiClient? client}) async =>
    BkAssistantGate.fromJson(await (client ?? ApiClient()).get('/api/v1/me/assistant/subject',
        queryParams: {'course_id': '$courseId'}));
