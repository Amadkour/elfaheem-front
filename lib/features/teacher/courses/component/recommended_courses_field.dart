// components/recommended_courses_field.dart
//
// "Dropdown-styled" multi-select for recommended courses: looks and sits
// like the other form dropdowns (MyPrimaryMenu), but since Flutter has no
// built-in multi-select dropdown, tapping it opens a checklist sheet
// instead of expanding inline. Selected courses show as removable chips
// under the field.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';

class RecommendedCoursesField extends StatelessWidget {
  final List<Map<String, dynamic>> options; // [{'id': int, 'text': String}]
  final Set<int> selectedIds;
  final ValueChanged<int> onToggle;

  const RecommendedCoursesField({
    super.key,
    required this.options,
    required this.selectedIds,
    required this.onToggle,
  });

  List<Map<String, dynamic>> get _selectedOptions =>
      options.where((o) => selectedIds.contains(o['id'])).toList();

  Future<void> _openPicker(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _RecommendedCoursesPicker(
        options: options,
        selectedIds: selectedIds,
        onToggle: onToggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: options.isEmpty ? null : () => _openPicker(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.divider, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(Icons.playlist_add_check_rounded,
                    size: 18, color: context.colors.textMedium),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected.isEmpty
                        ? (options.isEmpty
                        ? 'no_other_courses_yet'.tr
                        : 'choose_recommended_courses'.tr)
                        : '${selected.length} ${'courses_selected_count'.tr}',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 13,
                      color: selected.isEmpty
                          ? context.colors.textLight
                          : context.colors.textDark,
                      fontWeight:
                      selected.isEmpty ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: context.colors.textMedium),
              ],
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selected
                .map(
                  (c) => Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c['text'] as String,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onToggle(c['id'] as int),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: context.colors.primary),
                    ),
                  ],
                ),
              ),
            )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _RecommendedCoursesPicker extends StatefulWidget {
  final List<Map<String, dynamic>> options;
  final Set<int> selectedIds;
  final ValueChanged<int> onToggle;

  const _RecommendedCoursesPicker({
    required this.options,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  State<_RecommendedCoursesPicker> createState() =>
      _RecommendedCoursesPickerState();
}

class _RecommendedCoursesPickerState extends State<_RecommendedCoursesPicker> {
  late Set<int> _local = Set.of(widget.selectedIds);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'choose_recommended_courses'.tr,
                      style: context.colors.h3.copyWith(fontSize: 15),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('done_btn'.tr,
                        style: TextStyle(
                            fontFamily: 'tajawal',
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.divider),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.options.length,
                itemBuilder: (_, i) {
                  final o = widget.options[i];
                  final id = o['id'] as int;
                  final checked = _local.contains(id);
                  return Material(
                    // color: Colors.transparent,
                    child: CheckboxListTile(
                      value: checked,
                      title: Text(
                        o['text'] as String,
                        style: const TextStyle(fontFamily: 'tajawal', fontSize: 13),
                      ),
                      activeColor: context.colors.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (_) {
                        widget.onToggle(id);
                        setState(() {
                          if (!_local.remove(id)) _local.add(id);
                        });
                      },
                    ),
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