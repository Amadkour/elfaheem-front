// lib/features/org/advising/adv_comm_api.dart — the HTTP client of the Academic Advising Phase 5 (docs/advising/
// PHASE5.md): availability and days off, slots and office hours, appointments (+ .ics), conversations, attachments,
// templates, feedback, the survey and the student hub. Answers are parsed into adv_appt_models.dart; every method
// throws `ApiException` (wrap calls in `orgCall` and show `advErrorText`).
//
// Two bases (backend routers/organization/org_advising_comm_router.py): staff `/org/orgs/{id}/advising` and the
// student's member base `/org/public/{id}/advising`. The routes both share (slots, office hours, appointments,
// threads, attachments) answer the student's own data on the member base — [AdvCommApi.student] picks it.
library;

import 'dart:typed_data';

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asMapList;
import '../org_providers.dart' show orgBase;
import 'adv_appt_models.dart';
import 'adv_models.dart' show AdvNote, AdvNoteDraft, AdvPage;

class AdvCommApi {
  AdvCommApi(this.orgId, {this.student = false, ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;

  /// The student's own routes (the member base) rather than the staff ones.
  final bool student;
  final ApiClient _api;

  String get staffBase => '$orgBase/orgs/$orgId/advising';
  String get memberBase => '$orgBase/public/$orgId/advising';
  String get base => student ? memberBase : staffBase;

  // ── availability (staff: the advisor themself, or manage) ─────────────────

  Future<AdvAvailability> availability(int advisorUserId) async => AdvAvailability.fromJson(asMap(await _api.get('$staffBase/advisors/$advisorUserId/availability')));

  /// The whole weekly list; 422 `advising_rules_overlap` · `advising_bad_time` · `advising_bad_link`.
  Future<AdvAvailability> saveRules(int advisorUserId, List<AdvRule> rules) async => AdvAvailability.fromJson(
      asMap(await _api.put('$staffBase/advisors/$advisorUserId/availability', body: {'rules': [for (final r in rules) r.toJson()]})));

  /// A day off; the answer names the booked appointments inside it (they are not cancelled by it).
  Future<AdvOffResult> addOff(int advisorUserId, DateTime from, DateTime to, String? reason) async => AdvOffResult.fromJson(asMap(await _api.post(
        '$staffBase/advisors/$advisorUserId/off',
        body: {'from': advDayKey(from), 'to': advDayKey(to), 'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim()},
      )));

  Future<void> removeOff(int advisorUserId, int offId) async => _api.delete('$staffBase/advisors/$advisorUserId/off/$offId');

  // ── slots and office hours (both bases) ───────────────────────────────────

  /// Free slots from [from] to [to] (calendar days in the organization's zone, ≤ 31 days). Staff may pass [memberId]
  /// so that student's booking rules apply.
  Future<AdvSlots> slots(int advisorUserId, {required DateTime from, required DateTime to, String? mode, int? memberId}) async =>
      AdvSlots.fromJson(asMap(await _api.get('$base/advisors/$advisorUserId/slots', queryParams: {
        'from': advDayKey(from),
        'to': advDayKey(to),
        'mode': ?mode,
        if (!student) 'member_id': ?memberId,
      })));

  Future<AdvOfficeHours> officeHours(int advisorUserId) async => AdvOfficeHours.fromJson(asMap(await _api.get('$base/advisors/$advisorUserId/office-hours')));

  // ── appointments ──────────────────────────────────────────────────────────

  /// [status] `booked` lists the soonest first, any other filter the newest first. [from] / [to] are instants.
  Future<AdvPage<AdvAppointment>> appointments({int? memberId, int? advisorUserId, String? status, DateTime? from, DateTime? to, int page = 1, int size = 25}) async =>
      AdvPage.fromJson(
        asMap(await _api.get('$base/appointments', queryParams: {
          if (!student) 'member_id': ?memberId,
          'advisor_user_id': ?advisorUserId,
          'status': ?status,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
          'page': page,
          'size': size,
        })),
        AdvAppointment.fromJson,
      );

  /// 409 `advising_slot_taken` · `advising_student_busy` (+ `conflicts`) · `advising_booking_limit`; 422 `advising_bad_slot`.
  Future<AdvAppointment> book(AdvBookDraft d) async => AdvAppointment.fromJson(asMap(await _api.post('$base/appointments', body: d.toJson())));

  Future<AdvAppointment> reschedule(int id, {required DateTime startsAt, required String mode, bool force = false}) async => AdvAppointment.fromJson(asMap(
      await _api.post('$base/appointments/$id/reschedule', body: {'starts_at': startsAt.toUtc().toIso8601String(), 'mode': mode, if (force) 'force': true})));

  /// Staff must give a [reason] (422 `advising_cancel_reason_required`).
  Future<AdvAppointment> cancel(int id, String? reason) async =>
      AdvAppointment.fromJson(asMap(await _api.post('$base/appointments/$id/cancel', body: {'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim()})));

  /// Staff: `completed` · `no_show` (409 `advising_too_early`).
  Future<AdvAppointment> setStatus(int id, String status) async =>
      AdvAppointment.fromJson(asMap(await _api.post('$staffBase/appointments/$id/status', body: {'status': status})));

  /// The RFC 5545 file of one appointment.
  Future<Uint8List> ics(int id) => _api.getBytes('$base/appointments/$id/ics');

  /// A meeting note (the Phase 4 notes route) tied to an appointment and the template it started from.
  Future<AdvNote> addMeetingNote(int memberId, AdvNoteDraft draft, {required int appointmentId, int? templateId}) async => AdvNote.fromJson(asMap(await _api.post(
        '$staffBase/students/$memberId/notes',
        body: {...draft.toJson(), 'appointment_id': appointmentId, 'template_id': ?templateId},
      )));

  // ── conversations ─────────────────────────────────────────────────────────

  Future<AdvThreadList> threads(AdvThreadQuery q, {int size = 25}) async =>
      AdvThreadList.fromJson(asMap(await _api.get('$base/threads', queryParams: student ? ({...q.toQuery(size: size)}..remove('member_id')) : q.toQuery(size: size))));

  /// The thread with its first message (a replayed `client_id` answers the one already made).
  Future<(AdvThread, List<AdvMessage>)> startThread(AdvThreadDraft d) async {
    final j = asMap(await _api.post('$base/threads', body: d.toJson()));
    return (AdvThread.fromJson(j), [for (final m in asMapList(j['messages'])) AdvMessage.fromJson(m)]);
  }

  /// Reading the newest page marks the thread read. [before] = the previous page's `next`.
  Future<AdvThreadDetail> thread(int id, {String? before, int limit = 30}) async =>
      AdvThreadDetail.fromJson(asMap(await _api.get('$base/threads/$id', queryParams: {'before': ?before, 'limit': limit})));

  /// Idempotent by the draft's `client_id`; 409 `advising_thread_closed` · `advising_client_id_conflict`.
  Future<AdvMessage> post(int threadId, AdvMessageDraft d) async => AdvMessage.fromJson(asMap(await _api.post('$base/threads/$threadId/messages', body: d.toJson())));

  /// `open` (reopen) · `closed`.
  Future<AdvThread> setThreadStatus(int threadId, String status, {String? note}) async => AdvThread.fromJson(asMap(
      await _api.post('$base/threads/$threadId/status', body: {'status': status, 'note': (note ?? '').trim().isEmpty ? null : note!.trim()})));

  /// Staff: a governance complaint work item (409 `advising_already_escalated`).
  Future<AdvThread> escalate(int threadId, String? note) async =>
      AdvThread.fromJson(asMap(await _api.post('$staffBase/threads/$threadId/escalate', body: {'note': (note ?? '').trim().isEmpty ? null : note!.trim()})));

  /// Where [AdvCommApi] uploads (multipart `file`).
  String get uploadPath => '$base/attachments';

  /// A 10-minute link (503 `advising_file_unavailable`).
  Future<String> attachmentLink(int id) async => '${asMap(await _api.get('$base/attachments/$id'))['url'] ?? ''}';

  // ── templates (staff) ─────────────────────────────────────────────────────

  /// Manage: every template; an advisor: the active ones.
  Future<List<AdvTemplate>> templates({String? kind}) async =>
      [for (final m in asMapList(asMap(await _api.get('$staffBase/templates', queryParams: {'kind': ?kind}))['items'])) AdvTemplate.fromJson(m)];

  Future<AdvTemplate> addTemplate(AdvTemplateDraft d) async => AdvTemplate.fromJson(asMap(await _api.post('$staffBase/templates', body: d.toJson())));

  /// A system template keeps its kind and names (409 `advising_template_system`).
  Future<AdvTemplate> saveTemplate(int id, AdvTemplateDraft d) async => AdvTemplate.fromJson(asMap(await _api.put('$staffBase/templates/$id', body: d.toJson())));

  Future<void> deleteTemplate(int id) async => _api.delete('$staffBase/templates/$id');

  // ── feedback (staff) and the survey (the student) ─────────────────────────

  /// Manage: any advisor (null = the whole organization); an advisor: their own.
  Future<AdvFeedback> feedback({int? advisorUserId, int? termId}) async =>
      AdvFeedback.fromJson(asMap(await _api.get('$staffBase/feedback', queryParams: {'advisor_user_id': ?advisorUserId, 'term_id': ?termId})));

  /// 404 `advising_survey_gone` for a used / unknown token.
  Future<AdvSurveyInfo> survey(String token) async => AdvSurveyInfo.fromJson(asMap(await _api.get('$memberBase/survey/${Uri.encodeComponent(token)}')), token: token);

  Future<void> answerSurvey(String token, int rating, String? comment) async => _api.post('$memberBase/survey/${Uri.encodeComponent(token)}', body: {
        'rating': rating,
        'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
      });

  // ── the student hub and the counts ────────────────────────────────────────

  Future<AdvHub> hub() async => AdvHub.fromJson(asMap(await _api.get('$memberBase/me')));

  /// The student's hub flag and badge counts (member status).
  Future<AdvMemberHub> memberHub() async => AdvMemberHub.fromJson(asMap(await _api.get('$memberBase/status')));

  /// Staff: my unread messages · today's appointments (the `me` block of `/status`).
  Future<AdvCommCounts> staffCounts() async => AdvCommCounts.fromJson(asMap(asMap(await _api.get('$staffBase/status'))['me']));
}
