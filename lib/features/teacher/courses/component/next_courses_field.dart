// components/next_courses_field.dart
//
// Ordered multi-select for the course's forward "roadmap" (next_course_ids).
// Unlike RecommendedCoursesField (unordered set), order matters here — it's
// the sequence students see on their roadmap — so each chosen course is
// shown as a numbered, reorderable row (up/down arrows) rather than a plain
// removable chip.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';

class NextCoursesField extends StatelessWidget {
  /// Already-chosen steps, in roadmap order — [{'id': int, 'text': String}]
  final List<Map<String, dynamic>> selected;

  /// Options not yet chosen (picker only offers these).
  final List<Map<String, dynamic>> availableOptions;

  final ValueChanged<Map<String, dynamic>> onAdd;
  final ValueChanged<int> onRemoveAt;
  final void Function(int from, int to) onReorder;

  const NextCoursesField({
    super.key,
    required this.selected,
    required this.availableOptions,
    required this.onAdd,
    required this.onRemoveAt,
    required this.onReorder,
  });

  Future<void> _openPicker(BuildContext context) async {
    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _NextCoursePickerSheet(options: availableOptions),
    );
    if (choice != null) onAdd(choice);
  }

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.next_courses',
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isNotEmpty)
          ...selected.asMap().entries.map(
                (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StepRow(
                index: e.key,
                course: e.value,
                isFirst: e.key == 0,
                isLast: e.key == selected.length - 1,
                onRemove: () => onRemoveAt(e.key),
                onMoveUp: () => onReorder(e.key, e.key - 1),
                onMoveDown: () => onReorder(e.key, e.key + 1),
              ),
            ),
          ),
        GestureDetector(
          onTap: availableOptions.isEmpty ? null : () => _openPicker(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.colors.primary.withValues(alpha: 0.4),
                width: 1.2,
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 18, color: context.colors.primary),
                const SizedBox(width: 6),
                Text(
                  selected.isEmpty
                      ? (availableOptions.isEmpty
                      ? 'no_other_courses_yet'.tr
                      : 'add_roadmap_step_btn'.tr)
                      : 'add_another_roadmap_step_btn'.tr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> course;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _StepRow({
    required this.index,
    required this.course,
    required this.isFirst,
    required this.isLast,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.divider, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: context.colors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.colors.onHero,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              course['text'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textDark,
              ),
            ),
          ),
          IconButton(
            tooltip: 'pl_move_up'.tr,
            onPressed: isFirst ? null : onMoveUp,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
            iconSize: 20,
            color: isFirst ? context.colors.textLight.withValues(alpha: 0.4) : context.colors.textMedium,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            tooltip: 'pl_move_down'.tr,
            onPressed: isLast ? null : onMoveDown,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            iconSize: 20,
            color: isLast ? context.colors.textLight.withValues(alpha: 0.4) : context.colors.textMedium,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            tooltip: 'remove'.tr,
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, color: context.colors.danger),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }
}

class _NextCoursePickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> options;

  const _NextCoursePickerSheet({required this.options});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'choose_next_course'.tr,
              style: context.colors.h3.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) => Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      options[i]['text'] as String,
                      style: const TextStyle(fontFamily: 'tajawal', fontSize: 13),
                    ),
                    onTap: () => Navigator.pop(context, options[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}