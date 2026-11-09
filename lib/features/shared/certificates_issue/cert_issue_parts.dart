// lib/features/shared/certificates_issue/cert_issue_parts.dart
//
// The presentational pieces of certificate issuing: they take plain values and callbacks and read no provider and
// no API, so test/ui/cert_issue_layout_test.dart pumps each of them on a phone and a wide window, Arabic and
// English, text ×1.3. The screens (cert_issue_flow.dart, cert_issue_history.dart, cert_issue_lists.dart,
// cert_verify_page.dart) own the state and the calls.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_tokens.dart';
import 'cert_issue_logic.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Steps
// ─────────────────────────────────────────────────────────────────────────────

/// "1 How · 2 Who · 3 Preview · 4 Issue": numbered dots on phones, dots + labels when there is room.
class IssueStepper extends StatelessWidget {
  const IssueStepper({super.key, required this.labels, required this.current, this.onTap});

  final List<String> labels;
  final int current;

  /// Tapping an earlier step goes back to it (null = not tappable).
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final showLabels = box.maxWidth >= 520;
      final items = <Widget>[];
      for (var i = 0; i < labels.length; i++) {
        final done = i < current;
        final active = i == current;
        final col = active || done ? c.primary : c.textLight;
        final dot = Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? c.primary : (done ? c.primary.withValues(alpha: 0.12) : c.cardBg),
            border: Border.all(color: col, width: 1.4),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 16, color: c.primary)
              : Text('${i + 1}', style: appText(12, w: FontWeight.w600, c: active ? c.onHero : col)),
        );
        final tappable = onTap != null && i < current;
        items.add(Semantics(
          button: tappable,
          selected: active,
          label: '${i + 1}. ${labels[i]}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: tappable ? () => onTap!(i) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  dot,
                  if (showLabels) ...[
                    const SizedBox(width: AppSpace.xs),
                    Text(labels[i],
                        style: appText(13, w: active ? FontWeight.w600 : FontWeight.w500, c: active ? c.textDark : c.textMedium)),
                  ],
                ]),
              ),
            ),
          ),
        ));
        if (i < labels.length - 1) {
          items.add(Expanded(
            child: Container(
              height: 1.4,
              margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              color: i < current ? c.primary : c.divider,
            ),
          ));
        }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: items),
        if (!showLabels)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text('${current + 1}/${labels.length} · ${labels[current]}',
                style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ]);
    });
  }
}

/// The step's bottom bar: Back · (the review summary) · the primary action.
class IssueStepBar extends StatelessWidget {
  const IssueStepBar({
    super.key,
    required this.nextLabel,
    required this.onNext,
    this.onBack,
    this.summary,
    this.nextIcon = Icons.arrow_forward_rounded,
    this.busy = false,
  });

  final String nextLabel;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final String? summary;
  final IconData nextIcon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
        child: Row(children: [
          if (onBack != null)
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('ci_back'.tr),
            ),
          Expanded(
            flex: 3,
            child: summary == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                    child: Text(summary!, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center),
                  ),
          ),
          Flexible(
            flex: 4,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min * 2, AppTouch.min)),
              onPressed: busy ? null : onNext,
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(nextIcon, size: 18),
              label: Text(nextLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One big choice card (icon · title · one line).
class IssueChoiceCard extends StatelessWidget {
  const IssueChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: AppSpace.card,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: AppRadius.chipAll),
                child: Icon(icon, color: c.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.section(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(subtitle, style: AppType.meta(context)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? c.primary : c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Step 1: link to a course, or standalone.
class IssueModeStep extends StatelessWidget {
  const IssueModeStep({super.key, required this.mode, required this.onMode, this.courseArea});

  final IssueMode? mode;
  final ValueChanged<IssueMode> onMode;

  /// The course picker + the values shared by everyone, shown under the course choice.
  final Widget? courseArea;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_mode_title'.tr, style: AppType.pageTitle(context)),
      const SizedBox(height: AppSpace.xxs),
      Text('ci_mode_sub'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.md),
      IssueChoiceCard(
        icon: Icons.person_add_alt_1_rounded,
        title: 'ci_mode_standalone'.tr,
        subtitle: 'ci_mode_standalone_sub'.tr,
        selected: mode == IssueMode.standalone,
        onTap: () => onMode(IssueMode.standalone),
      ),
      const SizedBox(height: AppSpace.sm),
      IssueChoiceCard(
        icon: Icons.school_rounded,
        title: 'ci_mode_course'.tr,
        subtitle: 'ci_mode_course_sub'.tr,
        selected: mode == IssueMode.course,
        onTap: () => onMode(IssueMode.course),
      ),
      if (mode == IssueMode.course && courseArea != null) ...[
        const SizedBox(height: AppSpace.md),
        courseArea!,
      ],
    ]);
  }
}

/// A selectable course row list (course mode).
class IssueCourseList extends StatelessWidget {
  const IssueCourseList({
    super.key,
    required this.courses,
    required this.selectedId,
    required this.onPick,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  /// (id, name, students?)
  final List<({int id, String name, int? students})> courses;
  final int? selectedId;
  final ValueChanged<int> onPick;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) return const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero);
    if (error != null) return IssueErrorBox(message: error!, onRetry: onRetry);
    if (courses.isEmpty) {
      return AppEmpty(icon: Icons.school_outlined, title: 'ci_no_courses'.tr, message: 'ci_no_courses_sub'.tr);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final co in courses)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Material(
            color: co.id == selectedId ? c.primary.withValues(alpha: 0.07) : c.cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.chipAll,
              side: BorderSide(color: co.id == selectedId ? c.primary : c.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPick(co.id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  child: Row(children: [
                    Icon(co.id == selectedId ? Icons.check_circle_rounded : Icons.menu_book_rounded,
                        size: 20, color: co.id == selectedId ? c.primary : c.textMedium),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(co.name, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    if (co.students != null) ...[
                      const SizedBox(width: AppSpace.xs),
                      Text('ci_students_n'.tr.replaceAll('{n}', '${co.students}'), style: AppType.meta(context)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Values printed the same on every certificate (course mode's extra columns, or a title).
class IssueConstantsForm extends StatelessWidget {
  const IssueConstantsForm({super.key, required this.columns, required this.controllers, this.title, this.subtitle});

  final List<IssueColumn> columns;
  final Map<String, TextEditingController> controllers;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(title ?? 'ci_same_for_all'.tr, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(subtitle ?? 'ci_same_for_all_sub'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      for (final col in columns)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: TextField(
            controller: controllers[col.key],
            decoration: InputDecoration(labelText: col.label, hintText: 'ci_optional'.tr),
          ),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipients: columns, paste, upload, search
// ─────────────────────────────────────────────────────────────────────────────

/// The expected columns, in order, as chips (shown BEFORE any input).
class IssueColumnChips extends StatelessWidget {
  const IssueColumnChips({super.key, required this.columns, this.showExample = true});

  final List<IssueColumn> columns;
  final bool showExample;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_columns_title'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (var i = 0; i < columns.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              '${i + 1}. ${columns[i].label}${columns[i].required ? '' : ' (${'ci_optional'.tr})'}',
              style: appText(12, w: FontWeight.w600, c: c.primary),
            ),
          ),
      ]),
      if (showExample && columns.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ci_example_line'.tr, style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xxs),
            SelectableText(certExampleLine(columns), style: appText(13, w: FontWeight.w500, c: c.textDark)),
          ]),
        ),
      ],
    ]);
  }
}

/// Paste tab: the columns, an example, a big text area and the live check status.
class IssuePastePanel extends StatelessWidget {
  const IssuePastePanel({
    super.key,
    required this.columns,
    required this.controller,
    required this.onChanged,
    this.checking = false,
    this.error,
    this.parsedCount,
  });

  final List<IssueColumn> columns;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool checking;
  final String? error;
  final int? parsedCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      IssueColumnChips(columns: columns),
      const SizedBox(height: AppSpace.sm),
      EnterSubmits.none(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'ci_paste_label'.tr,
            hintText: 'ci_paste_hint'.tr,
            alignLabelWithHint: true,
          ),
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      Row(children: [
        if (checking) ...[
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text('ci_checking'.tr, style: AppType.meta(context))),
        ] else if (error != null)
          Expanded(child: Text(error!, style: appText(12, w: FontWeight.w500, c: c.danger)))
        else if (parsedCount != null)
          Expanded(
            child: Text('ci_lines_read'.tr.replaceAll('{n}', '$parsedCount'), style: AppType.meta(context)),
          )
        else
          Expanded(child: Text('ci_paste_tip'.tr, style: AppType.meta(context))),
      ]),
    ]);
  }
}

/// Upload tab: sample sheets with exactly the template's columns, then pick an .xlsx / .csv.
class IssueUploadPanel extends StatelessWidget {
  const IssueUploadPanel({
    super.key,
    required this.columns,
    required this.onPick,
    required this.onSample,
    this.fileName,
    this.busy = false,
    this.error,
    this.parsedCount,
  });

  final List<IssueColumn> columns;
  final VoidCallback? onPick;

  /// 'xlsx' or 'csv'.
  final ValueChanged<String>? onSample;
  final String? fileName;
  final bool busy;
  final String? error;
  final int? parsedCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      IssueColumnChips(columns: columns, showExample: false),
      const SizedBox(height: AppSpace.md),
      Text('ci_sample_title'.tr, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text('ci_sample_sub'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        OutlinedButton.icon(
          onPressed: onSample == null ? null : () => onSample!('xlsx'),
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: Text('ci_sample_xlsx'.tr),
        ),
        OutlinedButton.icon(
          onPressed: onSample == null ? null : () => onSample!('csv'),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: Text('ci_sample_csv'.tr),
        ),
      ]),
      const SizedBox(height: AppSpace.md),
      Material(
        color: c.primary.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.primary.withValues(alpha: 0.35))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPick,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (busy)
                SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary))
              else
                Icon(Icons.upload_file_rounded, size: 32, color: c.primary),
              const SizedBox(height: AppSpace.xs),
              Text(busy ? 'ci_checking'.tr : (fileName ?? 'ci_pick_file'.tr),
                  textAlign: TextAlign.center, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppSpace.xxs),
              Text('ci_pick_file_sub'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
            ]),
          ),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(error!, style: appText(12, w: FontWeight.w500, c: c.danger)),
      ] else if (parsedCount != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text('ci_lines_read'.tr.replaceAll('{n}', '$parsedCount'), style: AppType.meta(context)),
      ],
    ]);
  }
}

/// Search tab: a search box, an optional filter (the course on a personal account), results with check boxes and
/// "Select all".
class IssueSearchPanel extends StatelessWidget {
  const IssueSearchPanel({
    super.key,
    required this.controller,
    required this.onQuery,
    required this.results,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
    this.filter,
    this.loading = false,
    this.error,
    this.onRetry,
    this.needsFilter = false,
    this.total,
  });

  final TextEditingController controller;
  final ValueChanged<String> onQuery;
  final List<StudentBrief> results;
  final Set<int> selected;
  final void Function(StudentBrief s, bool on) onToggle;
  final VoidCallback? onSelectAll;

  /// e.g. the course dropdown.
  final Widget? filter;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  /// No filter chosen yet (a personal account searches one course's students).
  final bool needsFilter;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allOn = results.isNotEmpty && results.every((s) => selected.contains(s.id));
    Widget body;
    if (needsFilter) {
      body = AppEmpty(icon: Icons.filter_list_rounded, title: 'ci_search_pick_course'.tr, message: 'ci_search_pick_course_sub'.tr);
    } else if (loading && results.isEmpty) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = IssueErrorBox(message: error!, onRetry: onRetry);
    } else if (results.isEmpty) {
      body = AppEmpty(icon: Icons.person_search_rounded, title: 'ci_search_empty'.tr, message: 'ci_search_empty_sub'.tr);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        for (final s in results)
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              value: selected.contains(s.id),
              onChanged: (v) => onToggle(s, v == true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, end: AppSpace.xs),
              secondary: AppAvatar(name: s.name, url: s.imageUrl, size: 36),
              title: Text(s.name, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: s.hint.isEmpty
                  ? null
                  : Text(s.hint, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (filter != null) ...[filter!, const SizedBox(height: AppSpace.sm)],
      TextField(
        controller: controller,
        onChanged: onQuery,
        enabled: !needsFilter,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: 'ci_search_hint'.tr,
          isDense: true,
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      if (!needsFilter && results.isNotEmpty)
        Row(children: [
          Expanded(
            child: Text(
              'ci_selected_n'.tr.replaceAll('{n}', '${selected.length}') +
                  (total != null && total! > results.length ? ' · ${'ci_showing_n'.tr.replaceAll('{n}', '${results.length}').replaceAll('{t}', '$total')}' : ''),
              style: AppType.meta(context),
            ),
          ),
          TextButton.icon(
            onPressed: onSelectAll,
            icon: Icon(allOn ? Icons.deselect_rounded : Icons.select_all_rounded, size: 18, color: c.primary),
            label: Text(allOn ? 'ci_unselect_all'.tr : 'ci_select_all'.tr),
          ),
        ]),
      body,
    ]);
  }
}

/// The three ways to add people, as a segmented control.
enum RecipientTab { search, paste, upload }

class IssueRecipientTabs extends StatelessWidget {
  const IssueRecipientTabs({super.key, required this.tab, required this.onTab});

  final RecipientTab tab;
  final ValueChanged<RecipientTab> onTab;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RecipientTab>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: RecipientTab.search, icon: const Icon(Icons.person_search_rounded, size: 18), label: Text('ci_tab_search'.tr)),
        ButtonSegment(value: RecipientTab.paste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: Text('ci_tab_paste'.tr)),
        ButtonSegment(value: RecipientTab.upload, icon: const Icon(Icons.upload_file_rounded, size: 18), label: Text('ci_tab_upload'.tr)),
      ],
      selected: {tab},
      onSelectionChanged: (s) => onTab(s.first),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Review
// ─────────────────────────────────────────────────────────────────────────────

enum ReviewFilter { all, attention, ready, skipped }

/// "12 ready · 3 need attention" + the filter chips + manual recipients switch + "Remove duplicates".
class IssueReviewHeader extends StatelessWidget {
  const IssueReviewHeader({
    super.key,
    required this.summary,
    required this.filter,
    required this.onFilter,
    required this.manualDefault,
    required this.onManualDefault,
    this.onRemoveDuplicates,
    this.onClear,
  });

  final IssueSummary summary;
  final ReviewFilter filter;
  final ValueChanged<ReviewFilter> onFilter;
  final bool manualDefault;
  final ValueChanged<bool> onManualDefault;
  final VoidCallback? onRemoveDuplicates;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget chip(ReviewFilter f, String label, int n, Color col) => AppChoiceChip(
          label: '$label · $n',
          selected: filter == f,
          onTap: () => onFilter(f),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text('ci_review_title'.tr, style: AppType.section(context))),
        if (onClear != null && summary.total > 0)
          TextButton.icon(
            onPressed: onClear,
            icon: Icon(Icons.clear_all_rounded, size: 18, color: c.textMedium),
            label: Text('ci_clear'.tr, style: appText(13, c: c.textMedium)),
          ),
      ]),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        _CountChip(icon: Icons.check_circle_rounded, text: '${summary.ready} ${'ci_ready'.tr}', color: c.success),
        if (summary.attention > 0)
          _CountChip(icon: Icons.error_outline_rounded, text: '${summary.attention} ${'ci_attention'.tr}', color: c.warning),
        if (summary.skipped > 0)
          _CountChip(icon: Icons.block_rounded, text: '${summary.skipped} ${'ci_skipped'.tr}', color: c.textMedium),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        chip(ReviewFilter.all, 'ci_filter_all'.tr, summary.total, c.primary),
        chip(ReviewFilter.attention, 'ci_attention'.tr, summary.attention, c.warning),
        chip(ReviewFilter.ready, 'ci_ready'.tr, summary.ready, c.success),
        if (summary.skipped > 0) chip(ReviewFilter.skipped, 'ci_skipped'.tr, summary.skipped, c.textMedium),
      ]),
      if (summary.unmatched > 0) ...[
        const SizedBox(height: AppSpace.xs),
        AppSwitchTile(
          value: manualDefault,
          onChanged: onManualDefault,
          title: 'ci_manual_all'.tr,
          subtitle: countText(summary.unmatched,
              ar1: 'اسم واحد لم يطابق طالبًا: يحصل صاحبه على شهادة بالاسم فقط.',
              ar2: 'اسمان لم يطابقا طالبًا: يحصلان على شهادة بالاسم فقط.',
              arFew: '{n} أسماء لم تطابق طالبًا: يحصلون على شهادات بالاسم فقط.',
              arMany: '{n} اسمًا لم تطابق طالبًا: يحصلون على شهادات بالاسم فقط.',
              en1: '1 name did not match a student: they get a certificate by name only.',
              en: '{n} names did not match a student: they get a certificate by name only.'),
          padding: EdgeInsets.zero,
        ),
      ],
      if (summary.duplicates > 0 && onRemoveDuplicates != null) ...[
        const SizedBox(height: AppSpace.xs),
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xs, AppSpace.xxs),
          decoration: BoxDecoration(
            color: c.warning.withValues(alpha: 0.08),
            borderRadius: AppRadius.chipAll,
            border: Border.all(color: c.warning.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.copy_all_rounded, size: 18, color: c.warning),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text('ci_duplicates_n'.tr.replaceAll('{n}', '${summary.duplicates}'), style: AppType.row(context)),
              ),
            ]),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onRemoveDuplicates,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: Text('ci_remove_duplicates'.tr),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

String _stateLabel(RowState s) => switch (s) {
      RowState.ready => 'ci_ready'.tr,
      RowState.attention => 'ci_attention'.tr,
      RowState.skipped => 'ci_skipped'.tr,
    };

/// One recipient in the review: name, state, who it matched, problems, the other values and the actions.
class IssueReviewRow extends StatelessWidget {
  const IssueReviewRow({
    super.key,
    required this.row,
    required this.state,
    required this.issues,
    required this.columns,
    required this.manual,
    required this.onEdit,
    required this.onRemove,
    required this.onPickCandidate,
    required this.onManual,
  });

  final RecipientRow row;
  final RowState state;
  final List<RowIssue> issues;
  final List<IssueColumn> columns;
  final bool manual;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final ValueChanged<StudentBrief> onPickCandidate;
  final ValueChanged<bool> onManual;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = switch (state) {
      RowState.ready => c.success,
      RowState.attention => c.warning,
      RowState.skipped => c.textLight,
    };
    final others = [
      for (final k in columns)
        if (k.key != 'student_name' && (row.values[k.key] ?? '').trim().isNotEmpty) '${k.label}: ${row.values[k.key]!.trim()}',
    ];
    final name = row.name.isNotEmpty ? row.name : (row.student?.name ?? 'ci_no_name'.tr);
    // a searched student arrives with the name only: say which values the next step's defaults (or an edit) fill
    final missing = row.source == RowSource.search
        ? [for (final k in columns) if (k.required && k.key != 'student_name' && (row.values[k.key] ?? '').trim().isEmpty) k.label]
        : const <String>[];
    return Container(
      decoration: BoxDecoration(
        color: state == RowState.attention ? c.warning.withValues(alpha: 0.06) : c.cardBg,
        borderRadius: AppRadius.chipAll,
        border: Border.all(color: state == RowState.attention ? c.warning.withValues(alpha: 0.5) : c.divider),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Icon(
              state == RowState.ready
                  ? Icons.check_circle_rounded
                  : (state == RowState.attention ? Icons.error_outline_rounded : Icons.block_rounded),
              size: 18,
              color: col,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(name, style: AppType.row(context)),
                  if (row.line != null) Text('ci_line_n'.tr.replaceAll('{n}', '${row.line}'), style: AppType.meta(context)),
                ]),
                const SizedBox(height: AppSpace.xxs),
                _matchLine(context),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(others.join(' · '), style: AppType.meta(context), maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text('ci_missing_values'.tr.replaceAll('{cols}', missing.join(AppConfig.lang == 'ar' ? '، ' : ', ')),
                      style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                for (final i in issues)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Text('• ${i.text(columns)}', style: appText(12, w: FontWeight.w500, c: c.danger)),
                  ),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'ci_edit'.tr,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20, color: c.textMedium),
          ),
          IconButton(
            tooltip: 'ci_remove'.tr,
            onPressed: onRemove,
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.textMedium),
          ),
        ]),
        if (row.match == MatchState.ambiguous && row.candidates.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26, end: AppSpace.xs),
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final s in row.candidates)
                AppChoiceChip(
                  icon: Icons.person_rounded,
                  label: s.hint.isEmpty ? s.name : '${s.name} · ${s.hint}',
                  selected: row.student?.id == s.id,
                  onTap: () => onPickCandidate(s),
                ),
            ]),
          ),
        ],
        if (row.match == MatchState.unmatched)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26),
            child: AppSwitchTile(
              value: manual,
              onChanged: onManual,
              title: 'ci_manual_one'.tr,
              padding: EdgeInsets.zero,
            ),
          ),
      ]),
    );
  }

  Widget _matchLine(BuildContext context) {
    final c = context.colors;
    final (IconData icon, String text, Color col) = switch (row.match) {
      _ when row.student != null => (
          Icons.verified_user_outlined,
          row.source == RowSource.search || row.student!.hint.isEmpty
              ? 'ci_on_platform'.tr
              : '${'ci_matched_to'.tr} ${row.student!.name} · ${row.student!.hint}',
          c.success,
        ),
      MatchState.ambiguous => (Icons.people_outline_rounded, 'ci_ambiguous'.tr.replaceAll('{n}', '${row.candidates.length}'), c.warning),
      _ => (Icons.person_outline_rounded, manual ? 'ci_manual_recipient'.tr : 'ci_unmatched'.tr, c.textMedium),
    };
    return Row(children: [
      Icon(icon, size: 14, color: col),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(text, style: appText(12, w: FontWeight.w500, c: col), maxLines: 2, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: AppSpace.xs),
      Text(_stateLabel(state), style: appText(11, w: FontWeight.w600, c: c.textLight)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview
// ─────────────────────────────────────────────────────────────────────────────

/// The first recipient's certificate in each language (tabs), with skeleton / error states.
class IssuePreviewPanel extends StatelessWidget {
  const IssuePreviewPanel({
    super.key,
    required this.langs,
    required this.lang,
    required this.onLang,
    required this.images,
    this.loading = false,
    this.error,
    this.onRetry,
    this.recipientName,
  });

  final List<String> langs;
  final String lang;
  final ValueChanged<String> onLang;
  final Map<String, Uint8List> images;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String? recipientName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final img = images[lang];
    Widget body;
    if (loading) {
      body = AppShimmer(
        child: AspectRatio(aspectRatio: 1.414, child: AppSkeletonBox(width: double.infinity, height: double.infinity, radius: AppRadius.card)),
      );
    } else if (error != null) {
      body = IssueErrorBox(message: error!, onRetry: onRetry);
    } else if (img == null) {
      body = AppEmpty(icon: Icons.image_outlined, title: 'ci_preview_none'.tr);
    } else {
      body = ClipRRect(
        borderRadius: AppRadius.chipAll,
        child: Container(
          color: c.inputBg,
          child: Image.memory(img, fit: BoxFit.contain, gaplessPlayback: true, semanticLabel: 'ci_preview_title'.tr),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('ci_preview_title'.tr, style: AppType.section(context)),
        if (langs.length > 1)
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final l in langs) ButtonSegment(value: l, label: Text(certLangLabel(l)))],
            selected: {lang},
            onSelectionChanged: (s) => onLang(s.first),
          ),
      ]),
      if (recipientName != null && recipientName!.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text('ci_preview_for'.tr.replaceAll('{name}', recipientName!), style: AppType.meta(context)),
      ],
      const SizedBox(height: AppSpace.sm),
      body,
    ]);
  }
}

/// Languages to issue (chips) — at least one stays on.
class IssueLangPicker extends StatelessWidget {
  const IssueLangPicker({super.key, required this.available, required this.selected, required this.onChanged});

  final List<String> available;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_langs_title'.tr, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text('ci_langs_sub'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final l in available)
          AppChoiceChip(
            icon: Icons.translate_rounded,
            label: certLangLabel(l),
            selected: selected.contains(l),
            onTap: () {
              final next = Set<String>.of(selected);
              if (next.contains(l)) {
                if (next.length > 1) next.remove(l);
              } else {
                next.add(l);
              }
              onChanged(next);
            },
          ),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress, history rows
// ─────────────────────────────────────────────────────────────────────────────

/// A batch while it runs and once it finished: bar, counts, downloads.
class IssueBatchProgressCard extends StatelessWidget {
  const IssueBatchProgressCard({
    super.key,
    required this.batch,
    this.onZip,
    this.onPdf,
    this.onViewIssued,
    this.onIssueMore,
    this.downloading,
  });

  final IssueBatch batch;
  final VoidCallback? onZip;
  final VoidCallback? onPdf;
  final VoidCallback? onViewIssued;
  final VoidCallback? onIssueMore;

  /// 'zip' / 'pdf' while its link is being fetched.
  final String? downloading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = batch.status == 'done';
    final failed = batch.status == 'failed';
    final col = failed ? c.danger : (done ? c.success : c.primary);
    final title = failed
        ? 'ci_batch_failed'.tr
        : (done ? 'ci_batch_done'.tr : (batch.status == 'queued' ? 'ci_batch_queued'.tr : 'ci_batch_running'.tr));
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(failed ? Icons.error_outline_rounded : (done ? Icons.workspace_premium_rounded : Icons.hourglass_top_rounded), color: col),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.section(context)),
              if (batch.title != null) Text(batch.title!, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Semantics(
          value: '${(batch.progress * 100).round()}%',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: LinearProgressIndicator(
              value: batch.finished ? 1 : (batch.total == 0 ? null : batch.progress),
              minHeight: 8,
              color: col,
              backgroundColor: c.divider,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
          Text('ci_progress_n'.tr.replaceAll('{d}', '${batch.done}').replaceAll('{t}', '${batch.total}'), style: AppType.row(context)),
          if (batch.failed > 0) Text('ci_failed_n'.tr.replaceAll('{n}', '${batch.failed}'), style: appText(13, w: FontWeight.w500, c: c.danger)),
          if (batch.email && batch.emailed > 0) Text('ci_emailed_n'.tr.replaceAll('{n}', '${batch.emailed}'), style: AppType.meta(context)),
          if (batch.email && batch.emailFailed > 0)
            Text('ci_email_failed_n'.tr.replaceAll('{n}', '${batch.emailFailed}'), style: appText(12, w: FontWeight.w500, c: c.warning)),
        ]),
        if (failed && batch.error != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text('ci_batch_failed_sub'.tr, style: AppType.meta(context)),
        ],
        if (done) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (batch.hasZip)
              FilledButton.icon(
                onPressed: downloading != null ? null : onZip,
                icon: downloading == 'zip'
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_zip_outlined, size: 18),
                label: Text('ci_download_zip'.tr),
              ),
            if (batch.hasPdf)
              OutlinedButton.icon(
                onPressed: downloading != null ? null : onPdf,
                icon: downloading == 'pdf'
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text('ci_download_pdf'.tr),
              ),
            if (onViewIssued != null)
              OutlinedButton.icon(
                onPressed: onViewIssued,
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: Text('ci_view_issued'.tr),
              ),
          ]),
        ],
        if (batch.finished && onIssueMore != null) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onIssueMore,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('ci_issue_more'.tr),
            ),
          ),
        ],
      ]),
    );
  }
}

String _statusText(IssueBatch b) => certBatchStatusLabel(b.status);

/// One batch in the history list.
class IssueBatchTile extends StatelessWidget {
  const IssueBatchTile({super.key, required this.batch, required this.onTap, this.selected = false, this.byYou = false});

  final IssueBatch batch;
  final VoidCallback onTap;
  final bool selected;
  final bool byYou;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = switch (batch.status) {
      'done' => c.success,
      'failed' => c.danger,
      _ => c.primary,
    };
    final when = batch.createdAt == null ? '' : AppTime.dateTime(batch.createdAt!);
    return Material(
      color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: selected ? c.primary : c.divider)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: AppRadius.chipAll),
              child: Icon(batch.isCourse ? Icons.school_rounded : Icons.workspace_premium_rounded, color: c.primary, size: 20),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(batch.title ?? 'ci_untitled'.tr, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  [certModeLabel(batch.mode), if (when.isNotEmpty) when, if (byYou) 'ci_by_you'.tr].join(' · '),
                  style: AppType.meta(context),
                ),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  AppBadgePill(_statusText(batch), color: col),
                  Text('ci_progress_n'.tr.replaceAll('{d}', '${batch.done}').replaceAll('{t}', '${batch.total}'), style: AppType.meta(context)),
                  if (batch.failed > 0) Text('ci_failed_n'.tr.replaceAll('{n}', '${batch.failed}'), style: appText(12, c: c.danger)),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
      ),
    );
  }
}

/// One issued certificate in a batch.
class IssuedCertTile extends StatelessWidget {
  const IssuedCertTile({
    super.key,
    required this.cert,
    this.onView,
    this.onCopyLink,
    this.onRevoke,
    this.onReissue,
    this.onWord,
  });

  final IssuedCert cert;
  final VoidCallback? onView;
  final VoidCallback? onCopyLink;
  final VoidCallback? onRevoke;
  final VoidCallback? onReissue;

  /// Downloads the certificate as an editable Word file (cert_issue_word.dart).
  final VoidCallback? onWord;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = cert.createdAt == null ? '' : AppTime.date(cert.createdAt!);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: AppAvatar(name: cert.recipientName, size: 36),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cert.recipientName, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpace.xxs),
            Text([cert.serial, if (when.isNotEmpty) when].join(' · '), style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              AppBadgePill(cert.revoked ? 'ci_revoked'.tr : 'ci_valid'.tr, color: cert.revoked ? c.danger : c.success),
              if (cert.studentId == null) AppBadgePill('ci_manual_recipient'.tr, color: c.textMedium),
              if (cert.emailed) AppBadgePill('ci_emailed'.tr, color: c.primary, icon: Icons.mail_outline_rounded),
            ]),
            if (cert.expiresAt != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text('${'cv_valid_until'.tr}: ${AppTime.date(cert.expiresAt!)}', style: AppType.meta(context)),
            ],
            if (cert.revoked && (cert.revokedReason ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text('${'ci_reason'.tr}: ${cert.revokedReason}', style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        if (onView != null)
          IconButton(tooltip: 'ci_view'.tr, onPressed: onView, icon: Icon(Icons.visibility_outlined, size: 20, color: c.textMedium)),
        PopupMenuButton<String>(
          tooltip: 'ci_more'.tr,
          icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
          onSelected: (v) {
            if (v == 'link') onCopyLink?.call();
            if (v == 'revoke') onRevoke?.call();
            if (v == 'reissue') onReissue?.call();
            if (v == 'word') onWord?.call();
          },
          itemBuilder: (_) => [
            if (onWord != null)
              PopupMenuItem(value: 'word', child: _menuRow(Icons.description_outlined, 'ci_word'.tr)),
            if (onCopyLink != null)
              PopupMenuItem(value: 'link', child: _menuRow(Icons.link_rounded, 'ci_copy_link'.tr)),
            if (onReissue != null)
              PopupMenuItem(value: 'reissue', child: _menuRow(Icons.refresh_rounded, 'ci_reissue'.tr)),
            if (onRevoke != null && !cert.revoked)
              PopupMenuItem(value: 'revoke', child: _menuRow(Icons.block_rounded, 'ci_revoke'.tr)),
          ],
        ),
      ]),
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpace.sm),
        Flexible(child: Text(label)),
      ]);
}

/// A saved list row.
class IssueSavedListTile extends StatelessWidget {
  const IssueSavedListTile({super.key, required this.list, required this.onTap, this.trailing, this.selected = false});

  final RecipientListInfo list;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: selected ? c.primary : c.divider)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
            child: Row(children: [
              Icon(Icons.groups_2_outlined, color: c.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(list.name, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      'ci_people_n'.tr.replaceAll('{n}', '${list.count}'),
                      if (list.updatedAt != null) AppTime.date(list.updatedAt!),
                    ].join(' · '),
                    style: AppType.meta(context),
                  ),
                ]),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs + 2, AppSpace.sm, AppSpace.xxs + 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpace.xxs + 2),
          Flexible(child: Text(text, style: appText(12, w: FontWeight.w600, c: context.colors.textDark))),
        ]),
      );
}

/// A friendly error with a retry button.
class IssueErrorBox extends StatelessWidget {
  const IssueErrorBox({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.06),
        borderRadius: AppRadius.chipAll,
        border: Border.all(color: c.danger.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.cloud_off_rounded, color: c.danger),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(message, style: AppType.row(context))),
        ]),
        if (onRetry != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text('ci_retry'.tr)),
          ),
      ]),
    );
  }
}
