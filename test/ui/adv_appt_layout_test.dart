// The Phase 5 advising screens must lay out at every size and language (320×640 · 1400×900, ar · en, text scale 1.3):
// the booking form (loading · slots · chosen · busy student · failed), the appointment cards and list (upcoming,
// live video, past, cancelled late, staff actions), the cancel form, the 360's Meetings pane, the availability editor
// (rules · empty · rule form · day off form), the thread list (every state), the thread (messages, offline, refused,
// closed), the new-conversation form (complaint about the advisor), the templates (list, form), the survey form,
// the ratings (shown · hidden), the student hub (wide · phone · no advisor · no office hours) and the workspace strip.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/advising/adv_appointments.dart';
import 'package:flutter_education_app/features/org/advising/adv_appt_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_availability_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_comm_entries.dart' show AdvCommStripView;
import 'package:flutter_education_app/features/org/advising/adv_message_store.dart' show AdvQueuedMessage;
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_hub.dart';
import 'package:flutter_education_app/features/org/advising/adv_survey_sheet.dart';
import 'package:flutter_education_app/features/org/advising/adv_templates_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_threads.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_appt_models_test.dart';
import 'layout_harness.dart';

const _err = 'The server could not be reached. Check the connection and try again.';

Widget _sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

AdvAppointment _appt(Map<String, dynamic> j) => AdvAppointment.fromJson(j);
AdvSlots get _slots => AdvSlots.fromJson(sampleAdvSlotsJson());
List<AdvTemplate> get _templates => [for (final m in (sampleAdvTemplatesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvTemplate.fromJson(m)];
AdvThreadList get _threads => AdvThreadList.fromJson(sampleAdvThreadsJson());
AdvThreadDetail _detail({String status = 'open'}) => AdvThreadDetail.fromJson(sampleAdvThreadDetailJson(status: status));

const _actions = AdvApptActions();
final _allActions = AdvApptActions(onJoin: (_) {}, onCalendar: (_) {}, onReschedule: (_) {}, onCancel: (_) {}, onComplete: (_) {}, onNoShow: (_) {}, onNote: (_) {}, onChat: (_) {}, onOpenStudent: (_) {});

AdvBookingForm _booking({AdvLoad load = AdvLoad.ready, bool chosen = true, bool staff = false, bool offerForce = false, String? error, bool two = true}) {
  final s = _slots;
  final by = s.byDay();
  final day = DateTime(2026, 11, 10);
  final list = by['2026-11-10'] ?? const <AdvSlot>[];
  return AdvBookingForm(
    advisors: two ? const [(12, 'د. منى خليل'), (13, 'Dr Omar Saleh')] : const [(12, 'د. منى خليل')],
    advisorUserId: 12,
    days: [for (var i = 0; i < 14; i++) DateTime(2026, 11, 9 + i)],
    counts: {for (final e in by.entries) e.key: e.value.length},
    slots: list,
    modes: s.modes,
    reason: TextEditingController(text: 'أريد مناقشة خطة الفصل القادم'),
    day: day,
    slot: chosen ? list.first : null,
    mode: chosen ? 'in_person' : null,
    load: load,
    staff: staff,
    studentName: staff ? 'سارة أحمد' : null,
    offerForce: offerForce,
    error: error,
    onAdvisor: (_) {},
    onDay: (_) {},
    onPrev: () {},
    onNext: () {},
    onSlot: (_) {},
    onMode: (_) {},
    onForce: (_) {},
    onRetry: () {},
    onSubmit: () {},
  );
}

void main() {
  testWidgets('booking form: chosen, nothing chosen, loading, failed, staff with a busy student', (tester) async {
    await expectNoLayoutErrors(tester, () => _sheet(_booking()));
    await expectNoLayoutErrors(tester, () => _sheet(_booking(chosen: false, two: false)));
    await expectNoLayoutErrors(tester, () => _sheet(_booking(load: AdvLoad.loading)));
    await expectNoLayoutErrors(tester, () => _sheet(_booking(load: AdvLoad.failed)));
    await expectNoLayoutErrors(tester, () => _sheet(_booking(staff: true, offerForce: true, error: 'The student has a class from 9:00 AM to 10:30 AM')));
  });

  testWidgets('appointment cards and lists', (tester) async {
    await expectNoLayoutErrors(tester, () => _sheet(Column(children: [
          AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson()), actions: _allActions, now: advApptNow),
          AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 2, mode: 'video', dayOffset: 0, hour: 8)), actions: _allActions, now: advApptNow),
          AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 3, past: true, staff: true)), actions: _allActions, staff: true, now: advApptNow),
          AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 4, status: 'cancelled', cancelledBy: 'student', late: true, cancelReason: 'ظرف عائلي طارئ')), now: advApptNow),
          AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 5, past: true, status: 'no_show', staff: true, mode: 'phone')), actions: _allActions, staff: true, now: advApptNow),
        ])));
    final hub = AdvHub.fromJson(sampleAdvHubJson());
    await expectNoLayoutErrors(tester, () => _sheet(AdvAppointmentList(upcoming: hub.upcoming, past: hub.past, actions: _actions, now: advApptNow)));
    await expectNoLayoutErrors(tester, () => _sheet(const AdvAppointmentList(upcoming: [], past: [])));
    await expectNoLayoutErrors(tester, () => _sheet(AdvMeetingsPane(
          meetings: AdvMeetings.fromJson({'upcoming': [sampleAdvAppointmentJson(staff: true)], 'past': [sampleAdvAppointmentJson(id: 9, past: true, staff: true)], 'no_shows': 2}),
          actions: _allActions,
          onBook: () {},
          now: advApptNow,
        )));
  });

  testWidgets('cancel form: student late, staff', (tester) async {
    final a = _appt(sampleAdvAppointmentJson());
    await expectNoLayoutErrors(tester, () => _sheet(AdvCancelForm(appointment: a, reason: TextEditingController(), late: true, onSubmit: () {})));
    await expectNoLayoutErrors(tester, () => _sheet(AdvCancelForm(appointment: a, reason: TextEditingController(text: 'سفر'), staff: true, error: _err, onSubmit: () {})));
  });

  testWidgets('availability: rules, empty, failed, rule form, day off form', (tester) async {
    final a = AdvAvailability.fromJson(sampleAdvAvailabilityJson());
    AdvAvailabilityView view({AdvLoad load = AdvLoad.ready, bool empty = false}) => AdvAvailabilityView(
          load: load,
          rules: empty ? const [] : a.rules,
          off: empty ? const [] : a.off,
          timezone: a.timezone,
          advisorName: empty ? null : 'د. منى خليل',
          dirty: !empty,
          error: empty ? null : 'Two windows overlap on Monday — change one of them',
          errorText: _err,
          onRetry: () {},
          onAdd: (_) {},
          onEdit: (_) {},
          onRemove: (_) {},
          onSave: () {},
          onAddOff: () {},
          onRemoveOff: (_) {},
        );
    await expectNoLayoutErrors(tester, () => view());
    await expectNoLayoutErrors(tester, () => view(empty: true));
    await expectNoLayoutErrors(tester, () => view(load: AdvLoad.failed));
    await expectNoLayoutErrors(tester, () => _sheet(AdvRuleForm(
          rule: a.rules[2],
          location: TextEditingController(),
          link: TextEditingController(text: 'https://meet.example.edu/mona'),
          error: 'The meeting link must start with https://',
          editing: true,
          onWeekday: (_) {},
          onStart: () {},
          onEnd: () {},
          onSlot: (_) {},
          onMode: (_) {},
          onValidFrom: () {},
          onValidTo: () {},
          onSubmit: () {},
        )));
    await expectNoLayoutErrors(tester, () => _sheet(AdvDayOffForm(from: DateTime(2026, 11, 19), to: DateTime(2026, 11, 21), reason: TextEditingController(text: 'مؤتمر'), onFrom: () {}, onTo: () {}, onSubmit: () {})));
  });

  testWidgets('thread list in every state', (tester) async {
    AdvThreadsView view({AdvLoad load = AdvLoad.ready, List<AdvThread>? items, bool staff = true, AdvThreadQuery query = const AdvThreadQuery()}) => AdvThreadsView(
          load: load,
          query: query,
          threads: items ?? _threads.page.items,
          unreadTotal: 3,
          staff: staff,
          errorText: _err,
          onRetry: () {},
          onSearch: staff ? (_) {} : null,
          onFilter: (_) {},
          onOpen: (_) {},
          onNew: staff ? null : () {},
          onMore: () {},
        );
    await expectNoLayoutErrors(tester, () => view());
    await expectNoLayoutErrors(tester, () => view(staff: false));
    await expectNoLayoutErrors(tester, () => view(items: const []));
    await expectNoLayoutErrors(tester, () => view(items: const [], staff: false));
    await expectNoLayoutErrors(tester, () => view(items: const [], query: const AdvThreadQuery(overdue: true)));
    await expectNoLayoutErrors(tester, () => view(load: AdvLoad.loading));
    await expectNoLayoutErrors(tester, () => view(load: AdvLoad.offline));
  });

  testWidgets('thread: messages, offline queue, refused, closed, loading', (tester) async {
    final d = _detail();
    final composer = AdvMessageComposer(
      body: TextEditingController(text: 'سأرسل لكِ النموذج بعد التوقيع.'),
      attachments: const [AdvAttachment(id: 7, name: 'very-long-attachment-name-for-the-registration-form-2026.pdf', size: 1200000)],
      offline: true,
      onAttach: () {},
      onRemoveAttachment: (_) {},
      onTemplate: () {},
      onSend: () {},
    );
    final queued = [
      const AdvQueuedMessage(userId: 1, orgId: 1, threadId: 5, student: false, draft: AdvMessageDraft(body: 'Waiting to be sent', clientId: 'a')),
      const AdvQueuedMessage(userId: 1, orgId: 1, threadId: 5, student: false, draft: AdvMessageDraft(body: 'Refused one', clientId: 'b'), error: 'advising_thread_closed', message: 'The conversation is closed — reopen it first'),
    ];
    await expectNoLayoutErrors(tester, () => AdvThreadView(load: AdvLoad.ready, thread: d.thread, messages: d.messages, queued: queued, composer: composer, hasOlder: true, onOlder: () {}, onOpenAttachment: (_) {}, onDiscardQueued: (_) {}, onReopenQueued: (_) {}));
    final closed = _detail(status: 'closed');
    await expectNoLayoutErrors(tester, () => AdvThreadView(load: AdvLoad.ready, thread: closed.thread, messages: closed.messages, staff: false, onReopen: () {}));
    await expectNoLayoutErrors(tester, () => const AdvThreadView(load: AdvLoad.loading));
    await expectNoLayoutErrors(tester, () => AdvThreadView(load: AdvLoad.failed, errorText: _err, onRetry: () {}));
    await expectNoLayoutErrors(tester, () => _sheet(AdvThreadHeader(thread: AdvThread.fromJson(sampleAdvThreadJson(kind: 'complaint', about: 'advisor', status: 'escalated', priority: 'urgent', workItem: 314, overdue: true)))));
  });

  testWidgets('new conversation: student complaint about the advisor, staff message', (tester) async {
    await expectNoLayoutErrors(tester, () => _sheet(AdvNewThreadForm(
          draft: const AdvThreadDraft(kind: 'complaint', about: 'advisor', priority: 'urgent', attachments: [AdvAttachment(id: 1, name: 'evidence.png', size: 4000)]),
          subject: TextEditingController(text: 'لم يرد المرشد على طلبي'),
          body: TextEditingController(),
          advisors: const [(12, 'د. منى خليل'), (13, 'Dr Omar Saleh')],
          error: _err,
          onKind: (_) {},
          onAbout: (_) {},
          onAboutUser: (_) {},
          onPriority: (_) {},
          onAttach: () {},
          onRemoveAttachment: (_) {},
          onSubmit: () {},
        )));
    await expectNoLayoutErrors(tester, () => _sheet(AdvNewThreadForm(
          draft: const AdvThreadDraft(memberId: 7),
          subject: TextEditingController(),
          body: TextEditingController(),
          student: false,
          studentName: 'سارة أحمد',
          onAttach: () {},
          onSubmit: () {},
        )));
  });

  testWidgets('templates: list, empty kind, form (built-in and new)', (tester) async {
    await expectNoLayoutErrors(tester, () => AdvTemplatesView(load: AdvLoad.ready, templates: _templates, manage: true, onKind: (_) {}, onAdd: () {}, onEdit: (_) {}));
    await expectNoLayoutErrors(tester, () => AdvTemplatesView(load: AdvLoad.ready, templates: const [], kind: 'outreach', onKind: (_) {}));
    final x = _templates.first;
    await expectNoLayoutErrors(tester, () => _sheet(AdvTemplateForm(
          draft: AdvTemplateDraft.of(x),
          nameAr: TextEditingController(text: x.nameAr),
          nameEn: TextEditingController(text: x.nameEn),
          bodyAr: TextEditingController(text: x.bodyAr),
          bodyEn: TextEditingController(text: x.bodyEn),
          system: true,
          creating: false,
          onActive: (_) {},
          onPlaceholder: (_, _) {},
          onSubmit: () {},
        )));
    await expectNoLayoutErrors(tester, () => _sheet(AdvTemplateForm(
          draft: const AdvTemplateDraft(),
          nameAr: TextEditingController(),
          nameEn: TextEditingController(),
          bodyAr: TextEditingController(),
          bodyEn: TextEditingController(),
          error: _err,
          onKind: (_) {},
          onActive: (_) {},
          onPlaceholder: (_, _) {},
          onSubmit: () {},
          onDelete: () {},
        )));
  });

  testWidgets('survey form and ratings', (tester) async {
    await expectNoLayoutErrors(tester, () => _sheet(AdvSurveyForm(info: AdvSurveyInfo.fromJson({'advisor_name': 'د. منى خليل', 'date': '2026-11-03'}), rating: 4, comment: TextEditingController(text: 'لقاء مفيد'), error: _err, onRating: (_) {}, onSubmit: () {})));
    await expectNoLayoutErrors(tester, () => _sheet(AdvFeedbackView(feedback: AdvFeedback.fromJson(sampleAdvFeedbackJson()))));
    await expectNoLayoutErrors(tester, () => _sheet(AdvFeedbackView(feedback: AdvFeedback.fromJson(sampleAdvFeedbackJson(count: 3)))));
  });

  testWidgets('student hub: full, booking closed, no office hours, no advisor, loading', (tester) async {
    AdvHubView view(Map<String, dynamic> j, {AdvLoad load = AdvLoad.ready}) => AdvHubView(
          load: load,
          hub: AdvHub.fromJson(j),
          now: advApptNow,
          errorText: _err,
          onRetry: () {},
          onBook: (_) {},
          onMessage: (_) {},
          onThreads: () {},
          onSurvey: (_) {},
          onAllAppointments: () {},
          apptActions: _allActions,
        );
    await expectNoLayoutErrors(tester, () => view(sampleAdvHubJson()));
    await expectNoLayoutErrors(tester, () => view(sampleAdvHubJson(canBook: false)));
    await expectNoLayoutErrors(tester, () => view(sampleAdvHubJson(noHours: true)));
    await expectNoLayoutErrors(tester, () => view(const {}));
    await expectNoLayoutErrors(tester, () => view(const {}, load: AdvLoad.loading));
  });

  testWidgets('workspace strip', (tester) async {
    await expectNoLayoutErrors(tester, () => _sheet(AdvCommStripView(counts: const AdvCommCounts(threadsUnread: 12, appointmentsToday: 3), onMessages: () {}, onAppointments: () {})));
    await expectNoLayoutErrors(tester, () => _sheet(const AdvCommStripView(counts: AdvCommCounts())));
  });
}
