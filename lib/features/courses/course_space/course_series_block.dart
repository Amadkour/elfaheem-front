// lib/features/courses/course_space/course_series_block.dart — the course's repeating meetings on its Sessions tab
// (D-1660, QA S17). A series is a meeting, not a lesson, so it gets its own block above the lessons timeline instead
// of being mixed into the course's sessions: each series' title, its rule in one sentence (describeRule) and its
// next dates (AppTime; a cancelled one struck through). Data: GET /me/calendar/series?course_id= (back D-1699).
//
//   CourseSeriesItem / CourseSeriesDate   plain values, parsed from the server answer
//   CourseSeriesBlock                     the block (plain values: pumped by the layout harness)
//   CourseSeriesSection                   loads the course's series and draws the block; nothing while there is none
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart';
import 'package:flutter_education_app/features/calendar/recurrence/series_actions.dart' show showSeriesOccurrenceSheet;

DateTime? _utc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

/// One coming date of a series.
class CourseSeriesDate {
  const CourseSeriesDate({required this.date, required this.start, required this.end, this.cancelled = false});

  /// "YYYY-MM-DD" in the series' zone; [start] / [end] are UTC.
  final String date;
  final DateTime start, end;
  final bool cancelled;
}

class CourseSeriesItem {
  const CourseSeriesItem({
    required this.id,
    required this.title,
    this.rule,
    this.mode,
    this.location,
    this.isOwner = false,
    this.upcoming = const [],
  });

  final int id;
  final String title;
  final RecurrenceRule? rule;
  final String? mode, location;
  final bool isOwner;
  final List<CourseSeriesDate> upcoming;

  static CourseSeriesItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = int.tryParse('${raw['id'] ?? ''}');
    if (id == null) return null;
    final dates = <CourseSeriesDate>[];
    if (raw['upcoming'] is List) {
      for (final x in raw['upcoming'] as List) {
        if (x is! Map) continue;
        final a = _utc(x['starts_at']), b = _utc(x['ends_at']);
        final d = '${x['occurrence_date'] ?? x['date'] ?? ''}';
        if (a == null || d.length < 10) continue;
        dates.add(CourseSeriesDate(
          date: d.substring(0, 10),
          start: a,
          end: b != null && b.isAfter(a) ? b : a.add(const Duration(minutes: 30)),
          cancelled: x['cancelled'] == true,
        ));
      }
    }
    final title = '${raw['title'] ?? ''}'.trim();
    return CourseSeriesItem(
      id: id,
      title: title.isEmpty ? t('اجتماع متكرر', 'Repeating meeting') : title,
      rule: RecurrenceRule.fromJson(raw['rule']),
      mode: raw['mode']?.toString(),
      location: raw['location']?.toString(),
      isOwner: raw['is_owner'] == true,
      upcoming: dates,
    );
  }

  /// The items of `{items: [...]}` (or a bare list).
  static List<CourseSeriesItem> listFrom(dynamic raw) {
    final l = raw is Map ? raw['items'] : raw;
    if (l is! List) return const [];
    return [for (final x in l) ?CourseSeriesItem.fromJson(x)];
  }

  /// A coming date as the calendar's event, for the calendar's own date sheet.
  CalEvent eventOf(CourseSeriesDate d) => CalEvent(
        id: 's$id:${d.date}',
        source: 'meeting',
        title: title,
        start: d.start,
        end: d.end,
        mode: mode,
        location: location,
        isOwner: isOwner,
        cancelled: d.cancelled,
        seriesId: id,
        occurrenceDate: d.date,
      );
}

/// The course's repeating meetings: one card each with the rule sentence and the next [dates] dates.
class CourseSeriesBlock extends StatelessWidget {
  const CourseSeriesBlock({super.key, required this.items, this.dates = 3, this.onDate});

  final List<CourseSeriesItem> items;
  final int dates;

  /// Tap on a coming date (null: the dates are read only).
  final void Function(CourseSeriesItem item, CourseSeriesDate date)? onDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      key: const ValueKey('course_series.block'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t('اجتماعات متكررة', 'Repeating meetings'), style: AppType.overline(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        for (final s in items) ...[
          _SeriesCard(item: s, dates: dates, onDate: onDate),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.item, required this.dates, this.onDate});

  final CourseSeriesItem item;
  final int dates;
  final void Function(CourseSeriesItem item, CourseSeriesDate date)? onDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = item;
    final shown = s.upcoming.take(dates).toList();
    return AppCard(
      key: ValueKey('course_series.${s.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.event_repeat_rounded, size: AppIconSize.lg, color: c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
              if (s.rule != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(describeRule(s.rule!, AppConfig.lang),
                    key: ValueKey('course_series.${s.id}.rule'), style: AppType.meta(context).copyWith(color: c.textMedium)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (shown.isEmpty)
          Text(t('لا مواعيد قادمة', 'No coming dates'), style: AppType.meta(context).copyWith(color: c.textMedium))
        else
          for (final d in shown) _DateRow(item: s, date: d, onTap: onDate == null ? null : () => onDate!(s, d)),
      ]),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.item, required this.date, this.onTap});

  final CourseSeriesItem item;
  final CourseSeriesDate date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = date;
    final text = '${AppTime.date(d.start, pattern: 'EEE d MMM')} · ${AppTime.time(d.start)} – ${AppTime.time(d.end)}';
    final style = AppType.meta(context).copyWith(
      color: d.cancelled ? c.textLight : c.textDark,
      decoration: d.cancelled ? TextDecoration.lineThrough : null,
    );
    return InkWell(
      key: ValueKey('course_series.${item.id}.date.${d.date}'),
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Icon(d.cancelled ? Icons.event_busy_rounded : Icons.event_rounded,
              size: AppIconSize.sm, color: d.cancelled ? c.textLight : c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style)),
          if (d.cancelled) ...[
            const SizedBox(width: AppSpace.xs),
            AppStatusBadge(label: t('أُلغي', 'Cancelled'), tone: AppTone.danger, dense: true),
          ],
        ]),
      ),
    );
  }
}

/// Loads the course's series and draws [CourseSeriesBlock] under [padding]; draws nothing while there is none (or
/// the call fails: the lessons below are the page's main content). Bump [reload] to read them again (after one is
/// created).
class CourseSeriesSection extends StatefulWidget {
  const CourseSeriesSection({
    super.key,
    required this.courseId,
    this.api = const RemoteCalendarApi(),
    this.reload = 0,
    this.padding = EdgeInsets.zero,
  });

  final int courseId;
  final CalendarApi api;
  final int reload;
  final EdgeInsetsGeometry padding;

  @override
  State<CourseSeriesSection> createState() => _CourseSeriesSectionState();
}

class _CourseSeriesSectionState extends State<CourseSeriesSection> {
  List<CourseSeriesItem> _items = const [];
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CourseSeriesSection old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload || old.courseId != widget.courseId) unawaited(_load());
  }

  Future<void> _load() async {
    final gen = ++_gen;
    try {
      final r = CourseSeriesItem.listFrom(await widget.api.courseSeries(widget.courseId));
      if (mounted && gen == _gen) setState(() => _items = r);
    } catch (_) {
      // an older server, the switch off, or no access: the tab shows its lessons as before
    }
  }

  Future<void> _open(CourseSeriesItem s, CourseSeriesDate d) async {
    final changed = await showSeriesOccurrenceSheet(context, api: widget.api, event: s.eventOf(d));
    if (changed && mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty || AppConfig.disableList.contains(kRecurringFeatureKey)) return const SizedBox.shrink();
    return Padding(padding: widget.padding, child: CourseSeriesBlock(items: _items, onDate: _open));
  }
}
