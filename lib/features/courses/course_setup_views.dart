// lib/features/courses/course_setup_views.dart — the course setup, drawn from plain values (D-1314):
//   CourseSetupSection   the teacher's form block: targets (removable chips), subject, delivery mode, area + address
//   CourseSetupLoadError the form block's place when the course's detail failed to load (an error line + Retry)
//   CourseWhoWhereBlock  the course page's compact "Who it's for / Where" block (target chips, delivery badge, areas)
// Neither reads a provider or makes a request: the caller loads the catalog and hands over the values.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:flutter_education_app/features/courses/course_setup.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space_parts.dart' show CourseInfoSection;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The delivery mode's name.
String courseDeliveryLabel(String mode) => switch (mode) {
      'in_person' => _t('حضوري', 'In person'),
      'both' => _t('أونلاين وحضوري', 'Online and in person'),
      _ => _t('أونلاين', 'Online'),
    };

IconData _deliveryIcon(String mode) => switch (mode) {
      'in_person' => Icons.place_outlined,
      'both' => Icons.swap_horiz_rounded,
      _ => Icons.videocam_outlined,
    };

/// The bilingual text of the server's 422 `course_area_required`.
String courseAreaRequiredText() => _t('اختر المحافظة أو المنطقة للكورس الحضوري', 'Pick the area for an in-person course');

/// A 48 px pill that is selected or not.
class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? c.primaryTint : c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.chipAll,
            side: BorderSide(color: selected ? c.primary : c.controlEdge, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          child: InkWell(
            borderRadius: AppRadius.chipAll,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon, size: AppIconSize.sm, color: selected ? c.primary : c.textLight),
                    const SizedBox(width: AppSpace.xs),
                  ],
                  Flexible(
                    child: Text(label,
                        style: AppType.row(context)
                            .copyWith(color: selected ? c.primary : c.textDark, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chosen target with its remove button.
class _TargetChip extends StatelessWidget {
  const _TargetChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${_t('إزالة', 'Remove')} $label',
      child: ExcludeSemantics(
        child: Material(
          color: c.primaryTint,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.primary, width: AppBorder.hairline)),
          child: InkWell(
            borderRadius: AppRadius.chipAll,
            onTap: onRemove,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(label, style: AppType.row(context).copyWith(color: c.primary, fontWeight: FontWeight.w700))),
                  const SizedBox(width: AppSpace.xs),
                  Icon(Icons.close_rounded, size: AppIconSize.sm, color: c.primary),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The form block. [targets] are the chosen audiences; [onToggleTarget] adds one that is missing and removes one that
/// is there (a whole stage is `gradeId: null`). The area tile shows only for in-person and both.
class CourseSetupSection extends StatefulWidget {
  const CourseSetupSection({
    super.key,
    required this.stages,
    required this.subjects,
    required this.targets,
    required this.onToggleTarget,
    required this.subjectId,
    required this.onSubject,
    required this.deliveryMode,
    required this.onDeliveryMode,
    required this.loadAreas,
    required this.onArea,
    required this.address,
    this.area1,
    this.area2,
    this.labels = const EduGeoLabels(),
    this.areaMissing = false,
  });

  final List<EduStage> stages;
  final List<EduSubject> subjects;
  final List<CourseTarget> targets;
  final void Function(CourseTarget target) onToggleTarget;
  final int? subjectId;
  final ValueChanged<int?> onSubject;
  final String deliveryMode;
  final ValueChanged<String> onDeliveryMode;
  final EduAreaLoader loadAreas;
  final void Function(EduArea level1, EduArea? level2) onArea;
  final EduArea? area1, area2;
  final EduGeoLabels labels;
  final TextEditingController address;

  /// The save was refused for want of an area: the tile says so.
  final bool areaMissing;

  @override
  State<CourseSetupSection> createState() => _CourseSetupSectionState();
}

class _CourseSetupSectionState extends State<CourseSetupSection> {
  int? _stageId;

  EduStage? get _stage {
    for (final s in widget.stages) {
      if (s.id == _stageId) return s;
    }
    return null;
  }

  CourseTarget _target(EduStage s, EduGrade? g) => CourseTarget(
        stageId: s.id,
        gradeId: g?.id,
        stageAr: s.nameAr,
        stageEn: s.nameEn,
        gradeAr: g?.nameAr ?? '',
        gradeEn: g?.nameEn ?? '',
      );

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final inPerson = widget.deliveryMode != 'online';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(_t('لمن هذا الكورس', "Who it's for")),
        if (widget.targets.isNotEmpty) ...[
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final t in widget.targets) _TargetChip(label: t.label, onRemove: () => widget.onToggleTarget(t)),
          ]),
          const SizedBox(height: AppSpace.sm),
        ],
        if (widget.stages.isEmpty)
          Text(_t('المراحل الدراسية غير متاحة الآن', 'Study levels are not available right now'), style: AppType.meta(context))
        else ...[
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in widget.stages)
              _Pick(label: s.name, selected: s.id == _stageId, onTap: () => setState(() => _stageId = s.id == _stageId ? null : s.id)),
          ]),
          if (stage != null) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              _Pick(
                label: _t('المرحلة كاملة', 'Whole stage'),
                selected: widget.targets.contains(_target(stage, null)),
                onTap: () => widget.onToggleTarget(_target(stage, null)),
              ),
              if (stage.hasGrades)
                for (final g in stage.grades)
                  _Pick(
                    label: g.name,
                    selected: widget.targets.contains(_target(stage, g)),
                    onTap: () => widget.onToggleTarget(_target(stage, g)),
                  ),
            ]),
          ],
        ],
        const SizedBox(height: AppSpace.lg),
        AppFieldLabel(_t('المادة', 'Subject')),
        if (widget.subjects.isEmpty)
          Text(_t('المواد غير متاحة الآن', 'Subjects are not available right now'), style: AppType.meta(context))
        else
          AppDropdown<int?>(
            value: widget.subjects.any((s) => s.id == widget.subjectId) ? widget.subjectId : null,
            decoration: InputDecoration(labelText: _t('المادة (اختياري)', 'Subject (optional)')),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(_t('بدون مادة', 'No subject'))),
              for (final s in widget.subjects) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: widget.onSubject,
          ),
        const SizedBox(height: AppSpace.lg),
        AppFieldLabel(_t('طريقة التدريس', 'How it is taught')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final m in const ['online', 'in_person', 'both'])
            _Pick(
              label: courseDeliveryLabel(m),
              icon: _deliveryIcon(m),
              selected: widget.deliveryMode == m,
              onTap: () => widget.onDeliveryMode(m),
            ),
        ]),
        if (inPerson) ...[
          const SizedBox(height: AppSpace.lg),
          EduAreaPicker(
            loadAreas: widget.loadAreas,
            level1: widget.area1,
            level2: widget.area2,
            labels: widget.labels,
            address: widget.address,
            required: true,
            onChanged: widget.onArea,
          ),
          if (widget.areaMissing && widget.area1 == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(courseAreaRequiredText(), style: AppType.meta(context).copyWith(color: context.colors.danger)),
            ),
        ],
      ],
    );
  }
}

/// Shown instead of [CourseSetupSection] when the edit form could not load the course's detail: editing the section
/// then would send nothing, so the teacher retries first (D-1315).
class CourseSetupLoadError extends StatelessWidget {
  const CourseSetupLoadError({super.key, required this.onRetry, this.busy = false});
  final VoidCallback onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.sm,
        runSpacing: AppSpace.xs,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: AppIconSize.sm, color: c.danger),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(_t('تعذّر تحميل «لمن هذا الكورس وأين».', 'Could not load "Who it\'s for / Where".'),
                  style: AppType.meta(context).copyWith(color: c.danger)),
            ),
          ]),
          AppButton.secondary(label: _t('إعادة المحاولة', 'Retry'), icon: Icons.refresh_rounded, onPressed: busy ? null : onRetry),
        ],
      ),
    );
  }
}

/// The course page block. Draws nothing for a course with nothing to say (an older server, an online course with no
/// targets), so the page never shows an empty card.
class CourseWhoWhereBlock extends StatelessWidget {
  const CourseWhoWhereBlock({super.key, required this.setup});
  final CourseSetup setup;

  @override
  Widget build(BuildContext context) {
    if (setup.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final area = setup.area;
    final where = area == null ? null : [area.name, if (area.parent != null) area.parent!.name].join(_t('، ', ', '));
    return CourseInfoSection(
      title: _t("لمن هذا الكورس وأين", "Who it's for / Where"),
      icon: Icons.groups_2_outlined,
      children: [
        if (setup.targets.isNotEmpty)
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final t in setup.targets) AppStatusBadge(label: t.label, tone: AppTone.brand),
          ]),
        if (setup.subject != null) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Icon(Icons.menu_book_outlined, size: AppIconSize.sm, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(setup.subject!.name, style: AppType.row(context))),
          ]),
        ],
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppStatusBadge(label: courseDeliveryLabel(setup.deliveryMode), icon: _deliveryIcon(setup.deliveryMode)),
        ),
        if (setup.inPerson && where != null) ...[
          const SizedBox(height: AppSpace.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.place_outlined, size: AppIconSize.sm, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(where, style: AppType.row(context))),
          ]),
        ],
        if (setup.inPerson && setup.address != null) ...[
          const SizedBox(height: AppSpace.xs),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.signpost_outlined, size: AppIconSize.sm, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(setup.address!, style: AppType.meta(context))),
          ]),
        ],
      ],
    );
  }
}
