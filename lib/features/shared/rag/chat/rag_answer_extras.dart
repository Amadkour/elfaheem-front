// The chat answer's newer blocks, presentational (plain values + callbacks, tested by the layout harness):
//   [RagChunkList] / [RagChunkCard]  a retrieval answer: the closest passages (document, pages, section, text with
//                                    expand, copy) instead of prose
//   [RagToolCards]                   a tool answer: a compact card per tool (subscriptions, courses, schedule, progress)
//   [RagActionRow]                   up to four buttons under the answer that open a page of the app
// Texts are bilingual through `t(ar, en)`; times go through AppTime; the colours come from `context.colors`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show daysText;
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppFill;

import '../../../admin/admin_common.dart' show t;
import 'rag_payload.dart';

// ── retrieval: the closest passages ──────────────────────────────────────────────────────────────────────────

/// The passages of a retrieval answer, one card each.
class RagChunkList extends StatelessWidget {
  const RagChunkList({super.key, required this.chunks, this.onCopy});
  final List<RagChunk> chunks;

  /// Called after a passage's text was copied (null = the default toast).
  final ValueChanged<RagChunk>? onCopy;

  @override
  Widget build(BuildContext context) {
    if (chunks.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < chunks.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.xs),
          child: RagChunkCard(chunk: chunks[i], onCopy: onCopy),
        ),
    ]);
  }
}

/// A passage longer than this many characters is cut to a few lines with "Show more".
const int kRagChunkPreviewChars = 220;

class RagChunkCard extends StatefulWidget {
  const RagChunkCard({super.key, required this.chunk, this.onCopy});
  final RagChunk chunk;
  final ValueChanged<RagChunk>? onCopy;

  @override
  State<RagChunkCard> createState() => _RagChunkCardState();
}

class _RagChunkCardState extends State<RagChunkCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ch = widget.chunk;
    final long = ch.text.length > kRagChunkPreviewChars;
    final pages = ch.pageLabel(AppConfig.lang);
    final meta = [if (ch.section.isNotEmpty) ch.section, if (pages.isNotEmpty) pages].join(' · ');
    // a passage slip: paper on a warm hairline (the answer around it sits on the canvas), the document's name over
    // the quoted text
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xxs, AppSpace.xxs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
            child: SizedBox.square(
              dimension: AppIconSize.xl,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
                child: Icon(Icons.description_outlined, size: AppIconSize.sm + AppBorder.focus, color: c.textMedium),
              ),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ch.document.isEmpty ? t('مستند', 'Document') : ch.document,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              if (meta.isNotEmpty)
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
            ]),
          ),
          IconButton(
            tooltip: t('نسخ', 'Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ch.text));
              if (widget.onCopy != null) {
                widget.onCopy!(ch);
              } else {
                appToast(t('تم النسخ', 'Copied'));
              }
            },
            icon: Icon(Icons.copy_rounded, size: AppIconSize.sm, color: c.textLight),
          ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: AnimatedSize(
            duration: AppMotion.of(context).base,
            curve: AppEase.out,
            alignment: AlignmentDirectional.topStart,
            child: Text(ch.text,
                maxLines: long && !_open ? 4 : null,
                overflow: long && !_open ? TextOverflow.ellipsis : TextOverflow.visible,
                style: AppType.body(context).copyWith(color: c.textDark, height: 1.6)),
          ),
        ),
        if (long)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open ? t('عرض أقل', 'Show less') : t('عرض المزيد', 'Show more')),
            ),
          )
        else
          const SizedBox(height: AppSpace.xs),
      ]),
      ),
    );
  }
}

// ── tools: a compact card per result ─────────────────────────────────────────────────────────────────────────

/// The card of a tool answer, or nothing for a refused / unknown / empty result (the answer text says it).
class RagToolCards extends StatelessWidget {
  const RagToolCards({super.key, required this.tool, this.now});
  final RagTool tool;

  /// The clock, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (tool.refused) return const SizedBox.shrink();
    final at = now ?? DateTime.now().toUtc();
    final rows = switch (ragToolKind(tool.name)) {
      RagToolKind.subscriptions => ragSubscriptionRows(tool.data, at),
      RagToolKind.courses => ragCourseRows(tool.data),
      RagToolKind.schedule => ragScheduleRows(tool.data),
      RagToolKind.progress => ragProgressRows(tool.data),
      RagToolKind.other => const <RagToolRow>[],
    };
    if (rows.isEmpty) return const SizedBox.shrink();
    final icon = switch (ragToolKind(tool.name)) {
      RagToolKind.subscriptions => Icons.workspace_premium_outlined,
      RagToolKind.courses => Icons.menu_book_outlined,
      RagToolKind.schedule => Icons.event_outlined,
      _ => Icons.trending_up_rounded,
    };
    final c = context.colors;
    // the asker's own data on one paper card, rows parted by warm hairlines
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
          Padding(padding: const EdgeInsets.all(AppSpace.sm), child: _ToolRowView(row: rows[i], icon: icon)),
        ],
      ]),
    );
  }
}

/// One line of a tool card: a [title], a [detail] under it and an optional [progress] bar (0..1).
class RagToolRow {
  const RagToolRow(this.title, {this.detail = '', this.progress, this.warn = false});
  final String title;
  final String detail;
  final double? progress;

  /// Draw the detail as a warning (a subscription ending in a few days or already ended).
  final bool warn;
}

/// How many rows a card shows.
const int kRagToolMaxRows = 5;

/// Subscriptions (`{platform:[{plan_name, ends_at, days_left}], courses:[{title, plan, ends_at, expired, days_left}]}`):
/// plan, end date and days left. An older shape (`items`, or one flat object) is still read.
List<RagToolRow> ragSubscriptionRows(Map<String, dynamic> data, DateTime now) {
  var items = [
    ...ragToolItems({'x': data['platform']}, const ['x']),
    ...ragToolItems({'x': data['courses']}, const ['x']),
    if (data['platform'] is! List && data['courses'] is! List) ...ragToolItems(data, const ['subscriptions']),
  ];
  if (items.isEmpty && data.keys.any(const {'plan', 'plan_name', 'ends_at', 'end_date', 'expires_at'}.contains)) items = [data];
  final out = <RagToolRow>[];
  for (final s in items) {
    final plan = ragPickStr(s, const ['plan_name', 'title', 'plan', 'name', 'course_title', 'course']);
    final end = ragPickTime(s, const ['ends_at', 'end_date', 'expires_at', 'end', 'valid_until', 'expiry']);
    if (plan.isEmpty && end == null) continue;
    var detail = '';
    var warn = false;
    if (end != null) {
      final left = ragDaysLeft(end, now);
      final date = AppTime.date(end);
      if (left < 0 || s['expired'] == true) {
        detail = t('انتهى في $date', 'Ended $date');
        warn = true;
      } else {
        detail = t('ينتهي $date · متبقي ${daysText(left)}', 'Ends $date · ${daysText(left)} left');
        warn = left <= 7;
      }
    }
    out.add(RagToolRow(plan.isEmpty ? t('اشتراك', 'Subscription') : plan, detail: detail, warn: warn));
    if (out.length == kRagToolMaxRows) break;
  }
  return out;
}

/// Courses (`{courses:[{title, teacher, progress 0..100|null}]}`): title, teacher, progress bar.
List<RagToolRow> ragCourseRows(Map<String, dynamic> data) {
  final out = <RagToolRow>[];
  for (final c in ragToolItems(data, const ['courses'])) {
    final title = ragPickStr(c, const ['title', 'name', 'course_title']);
    if (title.isEmpty) continue;
    final p = ragPickFraction(c, const ['progress', 'progress_percent', 'percent', 'completion']);
    final teacher = ragPickStr(c, const ['teacher']);
    final detail = [if (teacher.isNotEmpty) teacher, if (p != null) '${(p * 100).round()}%'].join(' · ');
    out.add(RagToolRow(title, detail: detail, progress: p));
    if (out.length == kRagToolMaxRows) break;
  }
  return out;
}

/// Schedule (`{items:[{title, course, starts_at, location}]}`): the next items with their times.
List<RagToolRow> ragScheduleRows(Map<String, dynamic> data) {
  final out = <RagToolRow>[];
  for (final s in ragToolItems(data, const ['items', 'sessions', 'events', 'schedule', 'upcoming'])) {
    final title = ragPickStr(s, const ['title', 'name', 'course_title', 'course', 'subject']);
    final at = ragPickTime(s, const ['starts_at', 'start_at', 'start', 'start_time', 'at', 'time', 'scheduled_at', 'date']);
    if (title.isEmpty && at == null) continue;
    final course = ragPickStr(s, const ['course']);
    final place = ragPickStr(s, const ['location']);
    final detail = [if (at != null) AppTime.dateTime(at), if (course.isNotEmpty && course != title) course, if (place.isNotEmpty) place].join(' · ');
    out.add(RagToolRow(title.isEmpty ? t('موعد', 'Event') : title, detail: detail));
    if (out.length == kRagToolMaxRows) break;
  }
  return out;
}

/// Progress (`{courses:[{title, done, total, progress, upcoming_exams:[{title, starts_at}]}]}`): a bar per course
/// with "done / total" and the next exam; an overall bar first when the data carries one.
List<RagToolRow> ragProgressRows(Map<String, dynamic> data) {
  final out = <RagToolRow>[];
  final overall = ragPickFraction(data, const ['overall']);
  if (overall != null) out.add(RagToolRow(t('التقدّم العام', 'Overall progress'), detail: '${(overall * 100).round()}%', progress: overall));
  for (final c in ragToolItems(data, const ['courses'])) {
    if (out.length == kRagToolMaxRows) break;
    final title = ragPickStr(c, const ['title', 'name', 'course_title']);
    if (title.isEmpty) continue;
    final p = ragPickFraction(c, const ['progress', 'progress_percent', 'percent', 'completion']);
    final done = c['done'], total = c['total'];
    final exams = ragToolItems(c, const ['upcoming_exams']);
    final exam = exams.isEmpty ? null : exams.first;
    final examAt = exam == null ? null : ragPickTime(exam, const ['starts_at']);
    final examTitle = exam == null ? '' : ragPickStr(exam, const ['title']);
    final detail = [
      if (done is num && total is num) '${done.toInt()} / ${total.toInt()}' else if (p != null) '${(p * 100).round()}%',
      if (examTitle.isNotEmpty) '${t('امتحان', 'Exam')}: $examTitle${examAt == null ? '' : ' ${AppTime.dateTime(examAt)}'}',
    ].join(' · ');
    out.add(RagToolRow(title, detail: detail, progress: p));
  }
  return out;
}

class _ToolRowView extends StatelessWidget {
  const _ToolRowView({required this.row, required this.icon});
  final RagToolRow row;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = row.warn ? appInk(context, c.warning) : c.textLight;
    final p = row.progress;
    return Semantics(
      container: true,
      label: [row.title, if (row.detail.isNotEmpty) row.detail].join(', '),
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs / 2, end: AppSpace.sm),
            child: Icon(icon, size: AppIconSize.md, color: appInk(context, c.primary)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(row.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              if (row.detail.isNotEmpty)
                Text(row.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(color: tone, fontWeight: row.warn ? FontWeight.w600 : FontWeight.w400)),
              if (p != null) ...[
                const SizedBox(height: AppSpace.xs),
                // the progress fills once from empty, in the emerald of "done"
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    height: AppSpace.xxs + AppBorder.focus,
                    child: ColoredBox(
                      color: c.inputBg,
                      child: AppFill(
                        value: p.clamp(0.0, 1.0),
                        builder: (context, v) => FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: v.clamp(0.0, 1.0),
                          child: ColoredBox(color: c.primary),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── actions: buttons that open a page ────────────────────────────────────────────────────────────────────────

/// Up to four buttons under the answer. Actions whose page this app does not know (an older app) or that lack a
/// parameter are not drawn ([ragVisibleActions]); [onOpen] opens the one tapped (see `openRagAction`).
class RagActionRow extends StatelessWidget {
  const RagActionRow({super.key, required this.actions, required this.onOpen});
  final List<RagAction> actions;
  final ValueChanged<RagAction> onOpen;

  @override
  Widget build(BuildContext context) {
    final shown = ragVisibleActions(actions);
    if (shown.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final maxWidth = box.maxWidth.isFinite ? box.maxWidth : 320.0;
      return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final a in shown)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: OutlinedButton.icon(
              key: ValueKey('rag_action_${a.pageId}'),
              onPressed: () => onOpen(a),
              icon: Icon(DirIcons.arrowOutward, size: 16),
              label: Text(a.label(), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
      ]);
    });
  }
}
