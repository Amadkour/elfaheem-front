// lib/features/org/org_member_changes.dart — one-date changes of a member's sessions (substitute · online / offline ·
// cancelled), as /public/schedule/me reports them in `changes`, and what members do with them:
//
//   OccurrenceChange            pure model of one change; orgChangesOn / orgUpcomingChanges pick them per day
//   OccurrenceCard              the change with the students' answers; Accept / Reject (students), Undo (its staff)
//   switchSessionMode           the teacher / assistant switches ONE date online (asks the link) or back offline —
//                               POST /public/{org}/schedule/slots/{slot_id}/occurrences; students are notified
//   respondToChange             POST /public/schedule/occurrences/{id}/respond {decision}
//
// A published timetable reaches members through that feed and the calendar, both of which apply these changes.
// Pure parts are tested in test/org/org_reassign_test.dart; the card in test/ui/reassign_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart' show orgBase;
import 'org_schedule_versions.dart' show calendarDate;
import 'org_ui.dart' show orgText;
import 'org_v3.dart' show orgCall, orgErrorText;

class OccurrenceChange {
  const OccurrenceChange({required this.id, required this.slotId, required this.date, this.day = '', this.mode, this.onlineUrl, this.cancelled = false, this.note, this.courseId, this.course, this.kind = 'lecture', this.startTime, this.endTime, this.teacherId, this.teacher, this.substitute = false, this.assistant, this.room, this.accept = 0, this.reject = 0, this.myResponse, this.canRespond = false, this.canEdit = false});
  final int id, slotId;
  final String date, day, kind;
  final String? mode, onlineUrl, note, course, teacher, assistant, room, startTime, endTime, myResponse;
  final bool cancelled, substitute, canRespond, canEdit;
  final int? courseId, teacherId;
  final int accept, reject;

  bool get online => mode == 'online';

  /// what changed, in words
  String get label => cancelled
      ? t('أُلغيت الحصة', 'Session cancelled')
      : online
          ? t('الحصة أونلاين', 'Held online')
          : mode == 'offline'
              ? t('الحصة حضورياً', 'Held in person')
              : substitute
                  ? t('مدرس بديل', 'Substitute teacher')
                  : t('تغيير في الحصة', 'Session change');

  factory OccurrenceChange.of(Map<String, dynamic> m) => OccurrenceChange(
        id: asInt(m['id']),
        slotId: asInt(m['slot_id']),
        date: '${m['date'] ?? ''}',
        day: '${m['day'] ?? ''}',
        mode: m['mode'] as String?,
        onlineUrl: m['online_url'] as String?,
        cancelled: m['cancelled'] == true,
        note: m['note'] as String?,
        courseId: m['course_id'] == null ? null : asInt(m['course_id']),
        course: m['course'] as String?,
        kind: '${m['kind'] ?? 'lecture'}',
        startTime: m['start_time'] as String?,
        endTime: m['end_time'] as String?,
        teacherId: m['teacher_id'] == null ? null : asInt(m['teacher_id']),
        teacher: m['teacher'] as String?,
        substitute: m['substitute'] == true,
        assistant: m['assistant'] as String?,
        room: m['room'] as String?,
        accept: asInt(asMap(m['responses'])['accept']),
        reject: asInt(asMap(m['responses'])['reject']),
        myResponse: m['my_response'] as String?,
        canRespond: m['can_respond'] == true,
        canEdit: m['can_edit'] == true,
      );
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Every change of the member's timetables (`/schedule/me` items), soonest first.
List<OccurrenceChange> orgUpcomingChanges(List<Map<String, dynamic>> timetables) {
  final out = [for (final s in timetables) for (final x in asMapList(s['changes'])) OccurrenceChange.of(x)];
  out.sort((a, b) => '${a.date}|${a.startTime}'.compareTo('${b.date}|${b.startTime}'));
  return out;
}

/// The changes dated [day], keyed by slot id — so today's agenda can tag its sessions.
Map<int, OccurrenceChange> orgChangesOn(List<Map<String, dynamic>> timetables, DateTime day) {
  final iso = _iso(day);
  return {for (final x in orgUpcomingChanges(timetables)) if (x.date == iso) x.slotId: x};
}

/// One change of a session: what, when, who; the students' answers; Accept / Reject for a student of the course,
/// Undo for its staff, Open link when online.
class OccurrenceCard extends StatelessWidget {
  const OccurrenceCard({super.key, required this.change, this.onRespond, this.onUndo, this.onOpenLink, this.busy = false});
  final OccurrenceChange change;
  final void Function(String decision)? onRespond;
  final VoidCallback? onUndo, onOpenLink;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = change;
    final col = x.cancelled ? c.danger : (x.online ? c.primary : c.warning);
    final icon = x.cancelled ? Icons.event_busy_rounded : (x.online ? Icons.videocam_rounded : (x.substitute ? Icons.person_pin_rounded : Icons.event_note_rounded));
    final when = [calendarDate(x.date), if (x.startTime != null) AppTime.clockRange(x.startTime, x.endTime)].join(' · ');
    final spinner = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textMedium));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: col.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: col, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x.label} · ${x.course ?? ''}', style: orgText(context, w: FontWeight.w800)),
              Text(when, style: orgText(context, size: 12, color: c.textMedium)),
              Text(
                [
                  if (x.teacher != null) '${x.substitute ? t('البديل', 'substitute') : t('المدرس', 'teacher')}: ${x.teacher}',
                  if (x.room != null && !x.online) x.room!,
                  if (x.note != null && x.note!.isNotEmpty) x.note!,
                ].join(' · '),
                style: orgText(context, size: 12, color: c.textMedium),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
            child: Text(t('قبِل ${x.accept} · رفض ${x.reject}', '${x.accept} accepted · ${x.reject} rejected'), style: orgText(context, size: 11.5, color: c.textMedium)),
          ),
          if (x.online && x.onlineUrl != null && onOpenLink != null)
            FilledButton.tonalIcon(onPressed: onOpenLink, icon: const Icon(Icons.link_rounded, size: 16), label: Text(t('رابط الحصة', 'Session link')), style: FilledButton.styleFrom(visualDensity: VisualDensity.compact)),
          if (x.canRespond && onRespond != null) ...[
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => onRespond!('accept'),
              icon: busy ? spinner : Icon(x.myResponse == 'accept' ? Icons.check_circle_rounded : Icons.check_rounded, size: 16),
              label: Text(x.myResponse == 'accept' ? t('قبلت', 'Accepted') : t('قبول', 'Accept')),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, backgroundColor: x.myResponse == 'accept' ? c.success.withValues(alpha: 0.18) : null),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => onRespond!('reject'),
              icon: Icon(x.myResponse == 'reject' ? Icons.cancel_rounded : Icons.close_rounded, size: 16),
              label: Text(x.myResponse == 'reject' ? t('رفضت', 'Rejected') : t('رفض', 'Reject')),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: x.myResponse == 'reject' ? c.danger : c.textMedium),
            ),
          ],
          if (x.canEdit && onUndo != null)
            TextButton.icon(onPressed: busy ? null : onUndo, icon: const Icon(Icons.undo_rounded, size: 16), label: Text(t('إلغاء التغيير', 'Undo the change')), style: TextButton.styleFrom(visualDensity: VisualDensity.compact)),
        ]),
      ]),
    );
  }
}

/// A student answers a change. True when saved.
Future<bool> respondToChange(int occurrenceId, String decision) async {
  final r = await orgCall(() => ApiClient().post('$orgBase/public/schedule/occurrences/$occurrenceId/respond', body: {'decision': decision}),
      ok: decision == 'accept' ? t('سُجّل قبولك', 'Your acceptance was recorded') : t('سُجّل رفضك', 'Your rejection was recorded'));
  return r.ok;
}

/// The session's staff take it back to what the timetable says. True when done.
Future<bool> undoChange(int orgId, int occurrenceId) async {
  final r = await orgCall(() => ApiClient().delete('$orgBase/public/$orgId/schedule/occurrences/$occurrenceId'), ok: t('عادت الحصة كما في الجدول', 'Back to the timetable'));
  return r.ok;
}

/// The teacher / assistant switches one date of a session online (asks for the link) or back to in person.
/// Students and the other staff are notified by the server. True when saved.
Future<bool> switchSessionMode(BuildContext context, {required int orgId, required int slotId, required DateTime date, required bool online, String? currentUrl}) async {
  String? url;
  if (online) {
    url = await askText(context, title: t('رابط الحصة الأونلاين (اختياري)', 'Online session link (optional)'), hint: 'https://…');
    if (url == null) return false;
    url = url.trim();
    if (url.isNotEmpty && !url.startsWith('http')) {
      toast(t('الرابط يجب أن يبدأ بـ http', 'The link must start with http'), error: true);
      return false;
    }
  }
  final r = await orgCall(
      () => ApiClient().post('$orgBase/public/$orgId/schedule/slots/$slotId/occurrences', body: {
            'date': _iso(date),
            'mode': online ? 'online' : 'offline',
            if (online && url!.isNotEmpty) 'online_url': url,
          }),
      quiet: true);
  if (!r.ok) {
    toast(orgErrorText(r.error!), error: true);
    return false;
  }
  toast(online ? t('تحوّلت الحصة إلى أونلاين وأُبلغ الطلاب', 'Switched online — students were told') : t('عادت الحصة حضورياً وأُبلغ الطلاب', 'Back in person — students were told'));
  return true;
}

/// Ask whether to hold the session online or in person on [date]; null = nothing chosen.
Future<bool?> askSessionMode(BuildContext context, {required String title, required DateTime date, bool onlineNow = false}) {
  return showAdminSheet<bool>(context, (ctx) {
    final c = ctx.colors;
    Widget option(bool online, IconData icon, Color col, String t1, String t2) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            tileColor: c.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.divider)),
            leading: Icon(icon, color: col),
            title: Text(t1, style: orgText(ctx, w: FontWeight.w800)),
            subtitle: Text(t2, style: orgText(ctx, size: 12, color: c.textMedium)),
            onTap: () => Navigator.pop(ctx, online),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(title),
        Text(calendarDate(_iso(date)), style: orgText(ctx, size: 12.5, color: c.textMedium)),
        const SizedBox(height: 10),
        if (!onlineNow) option(true, Icons.videocam_rounded, c.primary, t('تحويل الحصة إلى أونلاين', 'Hold it online'), t('يُبلَّغ الطلاب فوراً ويمكنهم القبول أو الرفض', 'Students are told at once and may accept or reject')),
        if (onlineNow) option(false, Icons.meeting_room_rounded, c.success, t('إعادة الحصة حضورياً', 'Back to in person'), t('يُبلَّغ الطلاب فوراً', 'Students are told at once')),
      ]),
    );
  });
}
