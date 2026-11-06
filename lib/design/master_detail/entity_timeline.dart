// lib/design/master_detail/entity_timeline.dart — one student's history in one course (D-290, phase 4).
//
//   EntityTimelineList(studentId:, courseId:)     the history, newest first, paged, under month labels
//   showEntityTimelineSheet(context, …)           the same in a sheet (the History button of a course's student row)
//   groupTimeline(events)                         lessons finished in one sitting read as one entry
//
// The server sends the events (`GET /entities/students/{id}/courses/{course_id}/timeline`) and the app words them:
// entity_specs.dart holds the sentences, icons and tones. Reused by the student detail, a course opened from a student
// and a learner's own course.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../app_kit.dart';
import 'entity_detail_view.dart' show entityErrorText;
import 'entity_specs.dart';

/// A student's history in one course as a sheet.
Future<void> showEntityTimelineSheet(BuildContext context,
        {required int studentId, required int courseId, String title = ''}) =>
    showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(
        title: title.isEmpty ? 'md_history'.tr : '${'md_history'.tr} · $title',
        children: [EntityTimelineList(studentId: studentId, courseId: courseId)],
      ),
    );

/// One line of the timeline: an event, or several lessons finished in a row on one day.
class EntityTimelineEntry {
  const EntityTimelineEntry(this.events);

  /// Newest first, at least one.
  final List<EntityTimelineEvent> events;

  EntityTimelineEvent get first => events.first;
  bool get isGroup => events.length > 1;
}

/// [events] (newest first) as timeline entries: lessons finished one after the other on the same day fold into one
/// entry, so a sitting of twelve lessons does not bury the exam next to it. [dayOf] names an instant's day (default:
/// the date in the platform timezone).
List<EntityTimelineEntry> groupTimeline(List<EntityTimelineEvent> events, {String Function(DateTime utc)? dayOf}) {
  final day = dayOf ?? (DateTime utc) => AppTime.date(utc);
  final out = <List<EntityTimelineEvent>>[];
  for (final e in events) {
    final last = out.isEmpty ? null : out.last;
    final at = e.at, lastAt = last?.first.at;
    if (last != null &&
        e.type == 'material_completed' &&
        last.first.type == 'material_completed' &&
        at != null &&
        lastAt != null &&
        day(at) == day(lastAt)) {
      last.add(e);
    } else {
      out.add([e]);
    }
  }
  return [for (final g in out) EntityTimelineEntry(g)];
}

/// One student's history in one course, newest first, [pageSize] at a time.
class EntityTimelineList extends StatefulWidget {
  const EntityTimelineList({super.key, required this.studentId, required this.courseId, this.pageSize = 20});

  final int studentId;
  final int courseId;
  final int pageSize;

  @override
  State<EntityTimelineList> createState() => _EntityTimelineListState();
}

class _EntityTimelineListState extends State<EntityTimelineList> {
  final _events = <EntityTimelineEvent>[];
  int _page = 0;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await EntitiesApi.instance
          .timeline(widget.studentId, widget.courseId, page: _page + 1, size: widget.pageSize);
      if (!mounted) return;
      setState(() {
        _events.addAll(p.items);
        _page = p.page;
        _total = p.total;
        _hasMore = p.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  String _month(EntityTimelineEntry e) => e.first.at == null ? '' : AppTime.date(e.first.at!, pattern: 'MMMM y');

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      if (_loading) return const AppListSkeleton(items: 3, padding: EdgeInsets.symmetric(vertical: AppSpace.xxs));
      if (_error != null) return AppErrorState(message: entityErrorText(_error), onRetry: _next, compact: true);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Text('md_timeline_empty'.tr, textAlign: TextAlign.center, style: AppType.body(context)),
      );
    }
    final entries = groupTimeline(_events);
    final spansMonths = entries.map(_month).toSet().length > 1;
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final month = _month(entries[i]);
      final next = i + 1 < entries.length ? entries[i + 1] : null;
      if (spansMonths && month.isNotEmpty && (i == 0 || _month(entries[i - 1]) != month)) {
        rows.add(_MonthLabel(month, first: i == 0));
      }
      rows.add(EntityTimelineTile(
        entries[i],
        // the rail stops at a month label and at the very end
        last: next == null ? !_hasMore : spansMonths && _month(next) != month,
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...rows,
      if (_error != null) AppErrorState(message: entityErrorText(_error), onRetry: _next, compact: true),
      if (_hasMore && _error == null)
        Center(
          child: AppButton.ghost(
            label: '${'md_load_more'.tr} · ${mdText('md_shown_of', {'n': '${_events.length}', 'total': '$_total'})}',
            icon: Icons.expand_more_rounded,
            busy: _loading,
            size: AppButtonSize.sm,
            onPressed: _next,
          ),
        ),
    ]);
  }
}

class _MonthLabel extends StatelessWidget {
  const _MonthLabel(this.text, {required this.first});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 0 : AppSpace.sm, bottom: AppSpace.xs),
        child: Semantics(header: true, child: Text(text, style: AppType.label(context))),
      );
}

/// One line of a student's history: the icon on its tone, the sentence, the date, and what the event adds (the exam's
/// result, a rating and its review, why they withdrew, who acted).
class EntityTimelineTile extends StatelessWidget {
  const EntityTimelineTile(this.entry, {super.key, this.last = false});

  final EntityTimelineEntry entry;

  /// Nothing under it: the rail stops here.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final event = entry.first;
    final milestone = const {'enrolled', 'completed', 'withdrawn'}.contains(event.type);
    final text = entry.isGroup
        ? countText(entry.events.length,
            ar1: 'أنهى درساً واحداً', ar2: 'أنهى درسين', arFew: 'أنهى {n} دروس', arMany: 'أنهى {n} درساً',
            en1: 'Finished 1 lesson', en: 'Finished {n} lessons')
        : mdTimelineText(event);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: AppSpace.xl,
          child: Column(children: [
            entityToneIcon(context, mdTimelineIcon(event.type), mdTimelineTone(event), size: AppSpace.xl),
            if (!last)
              Expanded(
                child: Container(
                  width: AppBorder.strong,
                  margin: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                  color: c.divider,
                ),
              ),
          ]),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: AppSpace.xxs, bottom: last ? AppSpace.xxs : AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: milestone ? AppType.bodyStrong(context) : AppType.row(context)),
              Text(entry.isGroup ? mdDate(event.at) : mdDateTime(event.at), style: AppType.meta(context)),
              ..._details(context),
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _details(BuildContext context) {
    final event = entry.first;
    final meta = AppType.meta(context);
    final d = event.data;
    Widget quoted(String text) => Text('“$text”', maxLines: 3, overflow: TextOverflow.ellipsis, style: meta);
    if (entry.isGroup) {
      final titles = [for (final e in entry.events) ?entityString(e.data['title'])];
      if (titles.isEmpty) return const [];
      return [
        const SizedBox(height: AppSpace.xxs),
        Text(titles.take(3).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: meta),
        if (titles.length > 3) Text(mdText('md_p4_tl_more', {'n': '${titles.length - 3}'}), style: meta),
      ];
    }
    switch (event.type) {
      case 'exam_submitted':
        final passed = d['passed'];
        if (passed is! bool) return const [];
        return [
          const SizedBox(height: AppSpace.xxs),
          AppStatusBadge(
              label: passed ? 'md_passed'.tr : 'md_failed'.tr,
              tone: passed ? AppTone.success : AppTone.warning,
              dense: true),
        ];
      case 'rated':
        final review = entityString(d['review']);
        return [
          const SizedBox(height: AppSpace.xxs),
          EntityStars(entityInt(d['value'])),
          if (review != null) ...[const SizedBox(height: AppSpace.xxs), quoted(review)],
        ];
      case 'withdrawn':
        final reason = entityString(d['reason']);
        return reason == null ? const [] : [const SizedBox(height: AppSpace.xxs), quoted(reason)];
      case 'subscription':
        final actor = mdActorText(entityString(d['actor']));
        final reason = entityString(d['reason']);
        return [
          if (actor != null) Text(actor, style: meta),
          if (reason != null) quoted(reason),
        ];
      default:
        return const [];
    }
  }
}

/// A rating out of five as stars.
class EntityStars extends StatelessWidget {
  const EntityStars(this.value, {super.key});

  final int value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: mdText('md_tl_rated', {'v': '$value'}),
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= value ? Icons.star_rounded : Icons.star_border_rounded,
              size: AppIconSize.sm, color: i <= value ? c.warning : c.textLight),
      ]),
    );
  }
}
