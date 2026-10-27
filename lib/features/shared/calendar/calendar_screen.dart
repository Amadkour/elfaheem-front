// lib/features/shared/calendar/calendar_screen.dart — the smart calendar (route '/calendar').
//
//   CalendarScreen()                     my overall calendar: every organization / department I belong to, my
//                                        timetable, exams, course sessions and meetings, one colour per source
//   CalendarScreen(orgId: o)             only that organization (+ my personal meetings)
//   CalendarScreen(deptId: d)            a department's calendar (its meetings; new ones belong to the department)
//
// Day · week · month; tap a free slot to add a meeting; drag your own meetings to move them (instant check against
// your other events, then the server's "invitees busy" check); a tap on a meeting shows answers / join / respond.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t, asMap;
import 'calendar_api.dart';
import 'calendar_meeting.dart';
import 'calendar_models.dart';
import 'calendar_views.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, this.orgId, this.deptId, this.title, this.openMeetingId, this.api = const RemoteCalendarApi()});
  final int? orgId, deptId, openMeetingId;
  final String? title;
  final CalendarApi api;

  @override
  Widget build(BuildContext context) => BasePage(
        appBar: ScreenAppBar(title: title ?? (deptId != null ? t('تقويم الإدارة', 'Department calendar') : t('التقويم', 'Calendar'))),
        child: CalendarView(orgId: orgId, deptId: deptId, openMeetingId: openMeetingId, api: api),
      );
}

class CalendarView extends StatefulWidget {
  const CalendarView({super.key, this.orgId, this.deptId, this.openMeetingId, this.api = const RemoteCalendarApi(), this.initialView});
  final int? orgId, deptId, openMeetingId;
  final CalendarApi api;
  final CalView? initialView;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  CalView? _view;
  DateTime _anchor = calDay(AppTime.toZone(DateTime.now().toUtc()));
  List<CalEvent> _events = const [];
  bool _loaded = false, _loading = false;
  String? _error;
  int _pending = 0, _req = 0;
  final _hidden = <String>{};

  bool get _dept => widget.deptId != null;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _view ??= MediaQuery.sizeOf(context).width >= 700 ? CalView.week : CalView.day;
      await _load();
      if (widget.openMeetingId != null && mounted) _openMeeting(widget.openMeetingId!);
    });
  }

  Future<void> _load() async {
    final view = _view ?? CalView.week;
    final n = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    final (s, e) = calFetchRange(view, _anchor);
    try {
      final r = await widget.api.feed(s.toUtc().toIso8601String(), e.toUtc().toIso8601String(),
          orgId: widget.orgId, deptId: widget.deptId);
      if (!mounted || n != _req) return;
      setState(() {
        _events = CalEvent.listFrom(r);
        _pending = (asMap(r)['pending_invites'] as num?)?.toInt() ?? 0;
        _loaded = true;
        _loading = false;
      });
    } catch (err) {
      if (!mounted || n != _req) return;
      setState(() {
        _error = calErrorText(err);
        _loading = false;
      });
    }
  }

  void _go(CalView v, DateTime anchor) {
    setState(() {
      _view = v;
      _anchor = calDay(anchor);
    });
    _load();
  }

  Future<void> _openMeeting(int id) async {
    if (await showMeetingSheet(context, api: widget.api, meetingId: id)) _load();
  }

  Future<void> _tapEvent(CalEvent e) async {
    if (e.meetingId != null) return _openMeeting(e.meetingId!);
    await showAppSheet<void>(context, (ctx) => _EventSheet(event: e));
  }

  Future<void> _add([DateTime? wall]) async {
    var start = wall;
    if (start == null) {
      final n = AppTime.toZone(DateTime.now().toUtc());
      final base = _anchor == calDay(n) ? n : DateTime(_anchor.year, _anchor.month, _anchor.day, 9);
      start = DateTime(base.year, base.month, base.day, base.hour + (base == n ? 1 : 0));
    }
    final r = await showMeetingForm(context, api: widget.api, start: start, orgId: widget.orgId, deptId: widget.deptId);
    if (r != null) {
      appToast(r['visibility'] == 'private' ? t('أُضيف إلى تقويمك', 'Added to your calendar') : t('أُرسلت الدعوات', 'Invitations sent'));
      _load();
    }
  }

  Future<void> _move(CalEvent e, DateTime wallStart) async {
    final s = AppTime.fromZone(wallStart).toUtc();
    final en = s.add(e.duration);
    if (s == e.start || e.meetingId == null) return;
    final clash = calConflicts(_events.where((x) => !_hidden.contains(x.source)), e, s, en);
    if (clash.isNotEmpty) {
      final ok = await appConfirm(context,
          message: '${t('يتعارض مع', 'This overlaps')}: ${clash.take(3).map((x) => x.title).join('، ')}'
              '${clash.length > 3 ? ' +${clash.length - 3}' : ''}',
          confirmLabel: t('انقل رغم ذلك', 'Move anyway'));
      if (!ok || !mounted) return;
    }
    final before = _events;
    setState(() => _events = [for (final x in _events) x.id == e.id ? x.moved(s, en) : x]);
    Future<void> send(bool force) => widget.api.update(e.meetingId!, {
          'starts_at': s.toIso8601String(),
          'ends_at': en.toIso8601String(),
          'force': force,
        });
    try {
      await send(false);
      appToast(t('نُقل الاجتماع وأُبلغ المدعوون', 'Meeting moved — invitees notified'));
    } catch (err) {
      final busy = calBusyOf(err);
      var done = false;
      if (busy.isNotEmpty && mounted) {
        final go = await appConfirm(context,
            message: '${t('مشغولون في هذا الوقت', 'Busy at this time')}: ${busy.map((b) => asMap(b['user'])['name']).join('، ')}',
            confirmLabel: t('انقل رغم ذلك', 'Move anyway'));
        if (go) {
          try {
            await send(true);
            done = true;
          } catch (e2) {
            appToast(calErrorText(e2), error: true);
          }
        }
      } else {
        appToast(calErrorText(err), error: true);
      }
      if (!done && mounted) setState(() => _events = before);
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final view = _view;
    final shown = [for (final e in _events) if (!_hidden.contains(e.source)) e];
    final counts = <String, int>{for (final e in _events) e.source: 0};
    for (final e in _events) {
      counts[e.source] = counts[e.source]! + 1;
    }
    return Stack(children: [
      Column(children: [
        _Toolbar(
          view: view ?? CalView.week,
          title: view == null ? '' : calTitleFor(view, _anchor),
          loading: _loading && _loaded,
          onView: (v) => _go(v, _anchor),
          onPrev: () => _go(view!, calShift(view, _anchor, -1)),
          onNext: () => _go(view!, calShift(view, _anchor, 1)),
          onToday: () => _go(view ?? CalView.day, AppTime.toZone(DateTime.now().toUtc())),
          onRefresh: _load,
        ),
        if (!_dept && counts.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final s in calSources)
                  if (counts.containsKey(s))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(radius: 5, backgroundColor: calSourceColor(c, s)),
                        label: Text('${calSourceLabel(s)} · ${counts[s]}', style: appText(12, w: FontWeight.w600, c: c.textDark)),
                        selected: !_hidden.contains(s),
                        showCheckmark: false,
                        selectedColor: calSourceColor(c, s).withValues(alpha: 0.14),
                        backgroundColor: c.cardBg,
                        side: BorderSide(color: _hidden.contains(s) ? c.divider : calSourceColor(c, s).withValues(alpha: 0.5)),
                        onSelected: (on) => setState(() => on ? _hidden.remove(s) : _hidden.add(s)),
                      ),
                    ),
              ],
            ),
          ),
        if (_pending > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: AppBanner(
              icon: Icons.mark_email_unread_rounded,
              color: c.warning,
              text: t('لديك $_pending ${_pending == 1 ? 'دعوة' : 'دعوات'} بانتظار ردك', 'You have $_pending invitation${_pending == 1 ? '' : 's'} awaiting your answer'),
              action: _firstPending == null
                  ? null
                  : IconButton(tooltip: t('عرض', 'Open'), onPressed: () => _openMeeting(_firstPending!.meetingId!), icon: const Icon(Icons.open_in_new_rounded)),
            ),
          ),
        Expanded(child: AppRefresh(onRefresh: _load, child: _body(context, view, shown))),
      ]),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'cal_add',
          onPressed: () => _add(),
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text(t('اجتماع', 'Meeting'), style: appText(14, w: FontWeight.w700, c: Colors.white)),
        ),
      ),
    ]);
  }

  CalEvent? get _firstPending {
    for (final e in _events) {
      if (e.myStatus == 'pending' && e.meetingId != null) return e;
    }
    return null;
  }

  Widget _body(BuildContext context, CalView? view, List<CalEvent> shown) {
    final c = context.colors;
    if (view == null || (!_loaded && _error == null)) return const AppListSkeleton(items: 6, withAvatar: false);
    if (_error != null && !_loaded) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        AppBanner(
          icon: Icons.cloud_off_rounded,
          text: _error!,
          color: c.danger,
          action: IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ),
      ]);
    }
    final days = calVisibleDays(view, _anchor);
    final grid = switch (view) {
      CalView.month => CalMonthGrid(
          month: _anchor,
          days: days,
          events: shown,
          onTapDay: (d) => _go(CalView.day, d),
          onTapEvent: _tapEvent,
          onMove: _move,
        ),
      _ => CalTimeGrid(
          key: ValueKey('${view.name}-${days.first}'),
          days: days,
          events: shown,
          onTapEvent: _tapEvent,
          onTapSlot: _add,
          onMove: _move,
          onOpenDay: view == CalView.week ? (d) => _go(CalView.day, d) : null,
        ),
    };
    return Column(children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: AppBanner(
              icon: Icons.cloud_off_rounded,
              text: _error!,
              color: c.danger,
              action: IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))),
        ),
      if (shown.isEmpty && view == CalView.day)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: AppBanner(
              icon: Icons.event_available_rounded,
              color: c.success,
              text: t('يوم فارغ — اضغط على أي وقت لإضافة اجتماع', 'A free day — tap any time to add a meeting')),
        ),
      Expanded(child: grid),
    ]);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.view,
    required this.title,
    required this.loading,
    required this.onView,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    this.onRefresh,
  });

  final CalView view;
  final String title;
  final bool loading;
  final ValueChanged<CalView> onView;
  final VoidCallback onPrev, onNext, onToday;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final views = Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (v, label) in [
        (CalView.day, t('يوم', 'Day')),
        (CalView.week, t('أسبوع', 'Week')),
        (CalView.month, t('شهر', 'Month')),
      ])
        AppChoiceChip(label: label, selected: view == v, onTap: () => onView(v)),
    ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
      child: LayoutBuilder(builder: (context, box) {
        final nav = Row(children: [
          IconButton(
              tooltip: t('السابق', 'Previous'),
              onPressed: onPrev,
              icon: Icon(rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded)),
          IconButton(
              tooltip: t('التالي', 'Next'),
              onPressed: onNext,
              icon: Icon(rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded)),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.textDark)),
          ),
          if (loading) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
          if (onRefresh != null && !loading) AppRefreshAction(onRefresh: onRefresh!, size: 20),
          TextButton.icon(
            onPressed: onToday,
            icon: const Icon(Icons.today_rounded, size: 18),
            label: Text(t('اليوم', 'Today')),
          ),
        ]);
        if (box.maxWidth >= 700) {
          return Row(children: [Expanded(child: nav), const SizedBox(width: 8), views]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          nav,
          Padding(padding: const EdgeInsetsDirectional.only(start: 8, bottom: 2), child: views),
        ]);
      }),
    );
  }
}

/// Details of a non-meeting event (timetable slot, exam, special period, course session).
class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.event});
  final CalEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final color = calEventColor(c, e);
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(icon, size: 18, color: c.textLight),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: appText(14, c: c.textDark))),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(e.title),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppTag(calSourceLabel(e.source), color, icon: calSourceIcon(e.source)),
          if (e.kind == 'lab') AppTag(t('معمل', 'Lab'), color),
          if (e.kind == 'midterm') AppTag(t('منتصف الفصل', 'Midterm'), color),
          if (e.kind == 'final') AppTag(t('نهائي', 'Final'), color),
        ]),
        const SizedBox(height: 10),
        line(Icons.schedule_rounded,
            '${AppTime.date(e.start, pattern: 'EEEE d MMM')} · ${AppTime.time(e.start)} – ${AppTime.time(e.end)}'),
        if ((e.location ?? '').isNotEmpty) line(Icons.place_rounded, e.location!),
        if ((e.subtitle ?? '').isNotEmpty) line(Icons.person_rounded, e.subtitle!),
        if ((e.orgName ?? '').isNotEmpty) line(Icons.apartment_rounded, e.orgName!),
        if (e.courseId != null) ...[
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: t('فتح المقرر', 'Open course'),
            icon: Icons.menu_book_rounded,
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              unawaited(nav.pushNamed('/course-profile', arguments: e.courseId));
            },
          ),
        ],
      ]),
    );
  }
}
