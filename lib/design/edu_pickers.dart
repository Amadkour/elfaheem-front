// lib/design/edu_pickers.dart — the education-level pickers (D-1303). Plain values in, callbacks out: no provider, no
// request here (the caller loads `EduCatalog` and hands over `stages` / a `loadAreas` function), so they test with
// fake data and degrade to a short muted note when the catalog is empty.
//   EduStageGradePicker  stage chips, then the grade chips of that stage (+ the track chips when a grade has tracks)
//   EduAreaPicker        one tile that opens a searchable sheet: level 1 (governorate) then level 2 (city), with an
//                        optional street-address field under it
//   EduCountryPicker     the country dropdown (AppDropdown)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/app_kit.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// One selectable pill: a 48 px touch target, the primary wash when selected (the course filter bar uses it too).
class EduChoiceChip extends StatelessWidget {
  const EduChoiceChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

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
                child: Center(
                  widthFactor: 1,
                  child: Text(label,
                      style: AppType.row(context).copyWith(
                          color: selected ? c.primary : c.textDark, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EduGroup extends StatelessWidget {
  const _EduGroup({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFieldLabel(label),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: children),
        ],
      );
}

/// Stage → grade (→ track). [onChanged] gets the new ids: picking another stage clears the grade and the track; a
/// stage without grades (university) is complete by itself.
class EduStageGradePicker extends StatelessWidget {
  const EduStageGradePicker({
    super.key,
    required this.stages,
    required this.onChanged,
    this.stageId,
    this.gradeId,
    this.trackKey,
    this.stageLabel,
    this.gradeLabel,
    this.trackLabel,
  });

  final List<EduStage> stages;
  final int? stageId, gradeId;
  final String? trackKey;
  final void Function(int? stageId, int? gradeId, String? trackKey) onChanged;
  final String? stageLabel, gradeLabel, trackLabel;

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Text(_t('المراحل الدراسية غير متاحة الآن', 'Study levels are not available right now'),
            style: AppType.meta(context)),
      );
    }
    EduStage? stage;
    for (final s in stages) {
      if (s.id == stageId) stage = s;
    }
    EduGrade? grade;
    if (stage != null) {
      for (final g in stage.grades) {
        if (g.id == gradeId) grade = g;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EduGroup(
          label: stageLabel ?? _t('المرحلة', 'Stage'),
          children: [
            for (final s in stages)
              EduChoiceChip(label: s.name, selected: s.id == stageId, onTap: () => onChanged(s.id, null, null)),
          ],
        ),
        if (stage != null && stage.hasGrades && stage.grades.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _EduGroup(
            label: gradeLabel ?? _t('الصف', 'Grade'),
            children: [
              for (final g in stage.grades)
                EduChoiceChip(label: g.name, selected: g.id == gradeId, onTap: () => onChanged(stage!.id, g.id, null)),
            ],
          ),
        ],
        if (grade != null && grade.tracks.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _EduGroup(
            label: trackLabel ?? _t('الشعبة', 'Track'),
            children: [
              for (final t in grade.tracks)
                EduChoiceChip(label: t.name, selected: t.key == trackKey, onTap: () => onChanged(stage!.id, grade!.id, t.key)),
            ],
          ),
        ],
      ],
    );
  }
}

/// A country dropdown over `{code, name}` pairs. Hidden when there is one country or none.
class EduCountryPicker extends StatelessWidget {
  const EduCountryPicker({super.key, required this.countries, required this.value, required this.onChanged, this.label});

  /// code → display name.
  final Map<String, String> countries;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (countries.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(label ?? _t('الدولة', 'Country')),
        AppDropdown<String>(
          value: countries.containsKey(value) ? value : null,
          decoration: InputDecoration(labelText: label ?? _t('الدولة', 'Country')),
          items: [for (final e in countries.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

typedef EduAreaLoader = Future<List<EduArea>> Function(int? parentId);

/// The area field. Shows the chosen "level 2, level 1" (or a hint); a tap opens a searchable sheet that lists level 1
/// and, for an area with children, its level 2. [onChanged] gets the level-1 area and the level-2 one (null when the
/// level-1 area has none). [address] adds a free-text street address under the tile.
class EduAreaPicker extends StatelessWidget {
  const EduAreaPicker({
    super.key,
    required this.loadAreas,
    required this.onChanged,
    this.level1,
    this.level2,
    this.labels = const EduGeoLabels(),
    this.address,
    this.label,
    this.required = false,
  });

  final EduAreaLoader loadAreas;
  final EduArea? level1, level2;
  final EduGeoLabels labels;
  final void Function(EduArea level1, EduArea? level2) onChanged;
  final TextEditingController? address;
  final String? label;
  final bool required;

  Future<void> _open(BuildContext context) async {
    final r = await showAppSheet<(EduArea, EduArea?)>(
      context,
      (_) => _EduAreaSheet(loadAreas: loadAreas, labels: labels, selectedId: (level2 ?? level1)?.id),
    );
    if (r != null) onChanged(r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = level1 == null ? null : [if (level2 != null) level2!.name, level1!.name].join(_t('، ', ', '));
    final title = label ?? '${labels.level1} / ${labels.level2}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(title, required: required),
        Semantics(
          button: true,
          label: '$title ${text ?? ''}',
          child: ExcludeSemantics(
            child: Material(
              color: c.inputBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: BorderSide(color: c.fieldEdge, width: AppBorder.hairline)),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => _open(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: AppIconSize.md, color: c.textLight),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(text ?? _t('اختر المنطقة', 'Choose an area'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.row(context).copyWith(color: text == null ? c.textLight : c.textDark)),
                        ),
                        Icon(Icons.expand_more, size: AppIconSize.md, color: c.textLight),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (address != null) ...[
          const SizedBox(height: AppSpace.md),
          AppField(
            controller: address!,
            label: _t('العنوان بالتفصيل (اختياري)', 'Street address (optional)'),
            icon: Icons.signpost_outlined,
          ),
        ],
      ],
    );
  }
}

class _EduAreaSheet extends StatefulWidget {
  const _EduAreaSheet({required this.loadAreas, required this.labels, this.selectedId});
  final EduAreaLoader loadAreas;
  final EduGeoLabels labels;
  final int? selectedId;

  @override
  State<_EduAreaSheet> createState() => _EduAreaSheetState();
}

class _EduAreaSheetState extends State<_EduAreaSheet> {
  List<EduArea>? _items;
  EduArea? _parent;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  Future<void> _load(EduArea? parent) async {
    setState(() {
      _items = null;
      _parent = parent;
      _q = '';
    });
    List<EduArea> r;
    try {
      r = await widget.loadAreas(parent?.id);
    } catch (_) {
      r = const [];
    }
    if (mounted) setState(() => _items = r);
  }

  void _pick(EduArea a) {
    if (_parent == null && a.hasChildren) {
      _load(a);
    } else {
      Navigator.of(context).pop((_parent ?? a, _parent == null ? null : a));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lvl = _parent == null ? widget.labels.level1 : widget.labels.level2;
    final items = _items;
    final shown = items == null
        ? const <EduArea>[]
        : [
            for (final a in items)
              if (_q.isEmpty || a.nameAr.contains(_q) || a.nameEn.toLowerCase().contains(_q.toLowerCase())) a
          ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSheetHeader(_parent?.name ?? lvl, subtitle: _parent == null ? null : lvl),
            const SizedBox(height: AppSpace.sm),
            if (_parent != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _load(null),
                  icon: const Icon(Icons.arrow_back, size: AppIconSize.sm),
                  label: Text(widget.labels.level1),
                ),
              ),
            AppSearchField(hint: _t('بحث', 'Search'), debounce: Duration.zero, onChanged: (v) => setState(() => _q = v.trim())),
            const SizedBox(height: AppSpace.sm),
            Flexible(
              child: items == null
                  ? const AppListSkeleton(items: 4, withAvatar: false)
                  : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpace.lg),
                          child: Text(_t('لا توجد نتائج', 'No results'), textAlign: TextAlign.center, style: AppType.meta(context)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final a = shown[i];
                            final sel = a.id == widget.selectedId;
                            return ListTile(
                              minTileHeight: AppTouch.min,
                              title: Text(a.name, style: AppType.row(context).copyWith(color: sel ? c.primary : c.textDark)),
                              trailing: sel
                                  ? Icon(Icons.check, color: c.primary, size: AppIconSize.md)
                                  : (a.hasChildren && _parent == null
                                      ? Icon(Icons.chevron_right, color: c.textLight, size: AppIconSize.md)
                                      : null),
                              onTap: () => _pick(a),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
