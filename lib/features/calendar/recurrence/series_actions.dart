// lib/features/calendar/recurrence/series_actions.dart — changing one date of a repeating meeting (D-1573).
//
//   askSeriesScope          "This meeting only" / "This and following" (move or cancel)
//   seriesMove              move a date: PATCH …/occurrences/{date}, or the series' clock from that date on
//                           (PATCH …/series/{id} with `from_date`); a 409 `attendees_busy` asks once and sends
//                           again with `force`
//   seriesCancel            cancel a date (DELETE …/occurrences/{date}) or end the series from that date
//                           (DELETE …/series/{id}?from_date=)
//   showSeriesOccurrenceSheet  the sheet of a virtual date (feed id `s<series>:<date>`, no meeting row yet); Join
//                           opens its row first (POST …/occurrences/{date}/open, contract C5)
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show asMap, t;
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show openMeetingRoom;
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart';
import 'package:flutter_education_app/features/calendar/recurrence/series_guest_link.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show kLiveShareLinkFeatureKey;

/// Which dates a change of one occurrence reaches.
enum SeriesScope { one, following }

/// The scope sheet's panel from plain values (public so the layout harness pumps it). Pops a [SeriesScope].
class SeriesScopeSheet extends StatelessWidget {
  const SeriesScopeSheet({super.key, required this.cancel});

  /// Cancelling (true) or moving (false): only the wording changes.
  final bool cancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option(SeriesScope s, IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Material(
            color: c.inputBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              key: ValueKey('series_scope.${s.name}'),
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: () => Navigator.pop(context, s),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.primary),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  child: Row(children: [
                    Icon(icon, size: AppIconSize.lg, color: cancel ? c.danger : c.primary),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(title, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                        Text(sub, style: appText(12, c: c.textLight)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(cancel ? 'cal_series_cancel_title'.tr : 'cal_series_edit_title'.tr),
        option(SeriesScope.one, Icons.event_rounded, 'cal_series_this_only'.tr,
            cancel ? 'cal_series_this_only_cancel_hint'.tr : 'cal_series_this_only_hint'.tr),
        option(SeriesScope.following, Icons.repeat_rounded, 'cal_series_following'.tr,
            cancel ? 'cal_series_following_cancel_hint'.tr : 'cal_series_following_hint'.tr),
      ]),
    );
  }
}

Future<SeriesScope?> askSeriesScope(BuildContext context, {required bool cancel}) =>
    showAppSheet<SeriesScope>(context, (ctx) => SeriesScopeSheet(cancel: cancel));

/// Moves the [date] ("YYYY-MM-DD") of series [seriesId] to [startUtc]–[endUtc] after asking the scope. "This and
/// following" changes the series' clock (its rule's from–to) from today on. True when the server took it.
Future<bool> seriesMove(BuildContext context, CalendarApi api,
    {required int seriesId, required String date, required DateTime startUtc, required DateTime endUtc}) async {
  final scope = await askSeriesScope(context, cancel: false);
  if (scope == null || !context.mounted) return false;
  Future<dynamic> send(bool force) async {
    if (scope == SeriesScope.one) {
      return api.updateOccurrence(seriesId, date, {
        'starts_at': startUtc.toUtc().toIso8601String(),
        'ends_at': endUtc.toUtc().toIso8601String(),
        'force': force,
      });
    }
    final rule = RecurrenceRule.fromJson(asMap(await api.series(seriesId))['rule']);
    if (rule == null) throw StateError('no rule');
    return api.updateSeries(seriesId, {'rule': seriesRuleAtClock(rule, startUtc, endUtc).toJson(), 'force': force},
        fromDate: date);
  }

  try {
    await send(false);
  } catch (err) {
    final busy = calBusyOf(err);
    if (busy.isEmpty || !context.mounted) {
      showAppNotice(err is StateError ? 'cal_series_load_failed'.tr : calErrorText(err), error: true);
      return false;
    }
    final go = await appConfirm(context,
        message: '${'cal_series_busy'.tr}: ${busy.map((b) => asMap(b['user'])['name']).join('، ')}',
        confirmLabel: 'cal_series_move_anyway'.tr);
    if (!go) return false;
    try {
      await send(true);
    } catch (e2) {
      showAppNotice(calErrorText(e2), error: true);
      return false;
    }
  }
  showAppNotice(scope == SeriesScope.one ? 'cal_series_moved_one'.tr : 'cal_series_moved_following'.tr);
  return true;
}

/// [rule] with its clock set to [startUtc]–[endUtc] read in the RULE's zone (its `tz`, D-1645): the wall times are
/// in that zone, which may differ from the viewer's AppTime zone.
RecurrenceRule seriesRuleAtClock(RecurrenceRule rule, DateTime startUtc, DateTime endUtc) {
  final s = AppTime.toZone(startUtc, zone: rule.tz), e = AppTime.toZone(endUtc, zone: rule.tz);
  return rule.copyWith(allDay: false, startTime: s.hour * 60 + s.minute, endTime: e.hour * 60 + e.minute);
}

/// Cancels the [date] of series [seriesId], or ends the series, after asking the scope. True when done.
Future<bool> seriesCancel(BuildContext context, CalendarApi api, {required int seriesId, required String date}) async {
  final scope = await askSeriesScope(context, cancel: true);
  if (scope == null || !context.mounted) return false;
  // the scope says WHAT; a second, named step says it really happens and who hears of it (D-1662): one tap on a
  // scope row used to cancel at once and notify every attendee
  final day = recurrenceDateParse(date);
  final when = day == null ? date : AppTime.wall(day, pattern: 'EEE d MMM');
  final sure = await appConfirm(context,
      danger: true,
      message: scope == SeriesScope.one
          ? t('إلغاء اجتماع $when؟ يُبلَّغ المدعوون، وتبقى بقية المواعيد كما هي.',
              'Cancel the meeting on $when? The invitees are told; the other dates stay as they are.')
          : t('إنهاء السلسلة من $when؟ تختفي المواعيد القادمة ويُبلَّغ المدعوون، وتبقى السابقة.',
              'End the series from $when? The coming dates disappear and the invitees are told; earlier ones stay.'),
      confirmLabel: scope == SeriesScope.one ? t('ألغِ هذا الموعد', 'Cancel this date') : t('أنهِ السلسلة', 'End the series'));
  if (!sure || !context.mounted) return false;
  try {
    if (scope == SeriesScope.one) {
      await api.cancelOccurrence(seriesId, date);
    } else {
      await api.endSeries(seriesId, fromDate: date);
    }
  } catch (e) {
    showAppNotice(calErrorText(e), error: true);
    return false;
  }
  showAppNotice(scope == SeriesScope.one ? 'cal_series_cancelled_one'.tr : 'cal_series_ended'.tr);
  return true;
}

/// The date of [event]'s series as "YYYY-MM-DD" (local in the series' zone): the feed's `occurrence_date`, else the
/// virtual id's `s<series>:<date>`, else its wall date.
String seriesDateOf(CalEvent event) {
  final d = event.occurrenceDate;
  if (d != null && d.length >= 10) return d.substring(0, 10);
  final m = RegExp(r'^s\d+:(\d{4}-\d{2}-\d{2})$').firstMatch(event.id);
  return m?.group(1) ?? recurrenceDateWire(event.wallStart);
}

/// Into the room of a virtual date: its meeting row first (idempotent), then the normal meeting join.
Future<void> joinSeriesOccurrence(BuildContext context, CalendarApi api, CalEvent event) async {
  final id = event.seriesId;
  if (id == null) return;
  try {
    final r = asMap(await api.openOccurrence(id, seriesDateOf(event)));
    final mid = int.tryParse('${r['meeting_id'] ?? ''}');
    if (mid == null || !context.mounted) return;
    await openMeetingRoom(context,
        api: api,
        meeting: {'id': mid, 'title': event.title, 'mode': 'online', 'is_owner': event.isOwner, 'starts_at': event.start.toIso8601String()},
        canRecord: event.isOwner);
  } catch (e) {
    showAppNotice(calErrorText(e), error: true);
  }
}

/// The sheet of a series date that has no meeting row yet. True when something changed (the calendar reloads).
Future<bool> showSeriesOccurrenceSheet(BuildContext context, {required CalendarApi api, required CalEvent event}) async =>
    await showAppSheet<bool>(context, (ctx) => SeriesOccurrenceSheet(api: api, event: event)) ?? false;

class SeriesOccurrenceSheet extends StatefulWidget {
  const SeriesOccurrenceSheet({super.key, required this.api, required this.event});
  final CalendarApi api;
  final CalEvent event;

  @override
  State<SeriesOccurrenceSheet> createState() => _SeriesOccurrenceSheetState();
}

class _SeriesOccurrenceSheetState extends State<SeriesOccurrenceSheet> {
  RecurrenceRule? _rule;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRule();
  }

  Future<void> _loadRule() async {
    final id = widget.event.seriesId;
    if (id == null) return;
    try {
      final r = RecurrenceRule.fromJson(asMap(await widget.api.series(id))['rule']);
      if (mounted) setState(() => _rule = r);
    } catch (_) {
      // the summary is a hint; the date's own facts are on the sheet already
    }
  }

  Future<void> _move() async {
    final e = widget.event;
    final s = e.wallStart;
    final tod = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.hour, minute: s.minute));
    if (tod == null || !mounted) return;
    final ns = AppTime.fromZone(DateTime(s.year, s.month, s.day, tod.hour, tod.minute)).toUtc();
    setState(() => _busy = true);
    final ok = await seriesMove(context, widget.api,
        seriesId: e.seriesId!, date: seriesDateOf(e), startUtc: ns, endUtc: ns.add(e.duration));
    if (!mounted) return;
    if (ok) return Navigator.pop(context, true);
    setState(() => _busy = false);
  }

  Future<void> _cancel() async {
    final e = widget.event;
    setState(() => _busy = true);
    final ok = await seriesCancel(context, widget.api, seriesId: e.seriesId!, date: seriesDateOf(e));
    if (!mounted) return;
    if (ok) return Navigator.pop(context, true);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = widget.event;
    final owner = e.isOwner && e.seriesId != null && !e.cancelled;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(e.title),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppTag('cal_recur_tag'.tr, c.primary, icon: Icons.repeat_rounded),
          if (e.cancelled) AppTag('cal_series_cancelled_tag'.tr, c.danger, icon: Icons.event_busy_rounded),
          if (e.mode == 'online') AppTag('cal_series_online'.tr, c.primary, icon: Icons.videocam_rounded),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(
          '${AppTime.date(e.start, pattern: 'EEEE d MMMM')} · ${AppTime.time(e.start)} – ${AppTime.time(e.end)}',
          style: appText(14, w: FontWeight.w600, c: e.cancelled ? c.textLight : c.textDark)
              .copyWith(decoration: e.cancelled ? TextDecoration.lineThrough : null),
        ),
        if ((e.location ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(e.location!, style: appText(13, c: c.textMedium)),
        ],
        if (_rule != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.repeat_rounded, color: c.primary, text: describeRule(_rule!, AppConfig.lang)),
        ],
        if (e.mode == 'online' && !e.cancelled && !e.ended) ...[
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(
            key: const ValueKey('series_occurrence.join'),
            label: 'cal_series_join'.tr,
            icon: Icons.videocam_rounded,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await joinSeriesOccurrence(context, widget.api, e);
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ],
        if (owner) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppPill(
                key: const ValueKey('series_occurrence.move'),
                icon: Icons.edit_calendar_rounded,
                label: 'cal_series_change_time'.tr,
                onTap: _busy ? null : _move),
            AppPill(
                key: const ValueKey('series_occurrence.cancel'),
                icon: Icons.event_busy_rounded,
                label: 'cal_series_cancel'.tr,
                color: c.danger,
                onTap: _busy ? null : _cancel),
            // the series' ONE guest link (D-1720): the same URL for every date
            if (e.mode == 'online' && !AppConfig.disableList.contains(kLiveShareLinkFeatureKey))
              AppPill(
                  key: const ValueKey('series_occurrence.copy_link'),
                  icon: Icons.link_rounded,
                  label: 'series_link_copy'.tr,
                  onTap: _busy ? null : () => copySeriesGuestLink(e.seriesId!)),
          ]),
        ],
      ]),
    );
  }
}
