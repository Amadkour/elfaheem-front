// lib/features/teacher/data_lab/data_lab_columns_sheet.dart
// One simple list to decide, for EVERY column:
//   • its place      – drag the handle to reorder (saved for the sheet, the exports and the students' profile)
//   • "In table"     – show / hide it in the sheet
//   • "Students"     – show / hide it on the students' analytics profile
//   • 📌             – pin it on the side of the sheet (with the student details you choose)
// Changes apply immediately. The pencil opens the full column editor (name, formula, lock, delete …).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import '../../../design/app_switch.dart';
import 'data_lab_column_sheet.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_screen.dart' show showPinSheet;
import 'data_lab_widgets.dart';

Future<void> showColumnsSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _ColumnsSheet(p: p));

class _ColumnsSheet extends StatelessWidget {
  const _ColumnsSheet({required this.p});

  final DataLabProvider p;

  Future<void> _flag(DlColumn c, {bool? hidden, bool? students}) async {
    final err = await p.setColumnFlags(c, hidden: hidden, students: students);
    if (err != null) toast(err, error: true);
  }

  Future<void> _move(int from, int to) async {
    final err = await p.reorderColumns(from, to);
    if (err != null) toast(err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final cols = p.columns;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader('dl_columns'.tr),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              itemCount: cols.length,
              onReorder: _move,
              proxyDecorator: (child, _, anim) => AnimatedBuilder(
                animation: anim,
                builder: (_, __) => Material(
                  color: Colors.transparent,
                  elevation: 8 * anim.value,
                  shadowColor: c.heroShade.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  child: child,
                ),
              ),
              header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('dl_columns_sub'.tr, style: dlText(12.5, c: c.textMedium, h: 1.55)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.drag_indicator_rounded, size: 15, color: c.textLight),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(dlTr('dl_columns_drag', 'Drag the handle to change the order.'),
                        style: dlText(11.5, c: c.textLight)),
                  ),
                ]),
                const SizedBox(height: 10),
                // column captions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: [
                    const Expanded(child: SizedBox()),
                    SizedBox(width: 70, child: Center(child: Text('dl_col_in_table'.tr, style: dlText(11, w: FontWeight.w800, c: c.textMedium)))),
                    SizedBox(width: 70, child: Center(child: Text('dl_col_students'.tr, style: dlText(11, w: FontWeight.w800, c: c.textMedium)))),
                    const SizedBox(width: 72),
                  ]),
                ),
                const SizedBox(height: 6),
              ]),
              itemBuilder: (context, i) {
                final col = cols[i];
                return Container(
                  key: ValueKey(col.key),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsetsDirectional.only(start: 2, end: 2, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: col.isHidden ? c.inputBg : c.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.divider),
                  ),
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                          child: Icon(Icons.drag_indicator_rounded, size: 20, color: c.textLight),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(col.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: dlText(13.5, w: FontWeight.w800, c: col.isHidden ? c.textLight : c.textDark)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(
                            col.isCalculated ? Icons.functions_rounded : (col.isBuiltin ? Icons.auto_awesome_rounded : Icons.edit_note_rounded),
                            size: 12,
                            color: c.textLight,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              col.isCalculated ? 'dl_kind_calc'.tr : (col.isBuiltin ? 'dl_kind_auto'.tr : 'dl_kind_manual_short'.tr),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: dlText(10.5, c: c.textLight),
                            ),
                          ),
                          if (col.isLocked) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.lock_rounded, size: 12, color: c.warning),
                          ],
                        ]),
                      ]),
                    ),
                    SizedBox(
                      width: 70,
                      child: Center(child: AppSwitch(value: !col.isHidden, activeColor: c.primary, onChanged: (v) => _flag(col, hidden: !v))),
                    ),
                    SizedBox(
                      width: 70,
                      child: Center(child: AppSwitch(value: col.visibleToStudents, activeColor: c.success, onChanged: (v) => _flag(col, students: v))),
                    ),
                    SizedBox(
                      width: 36,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: p.isFrozen(col.key) ? dlTr('dl_unpin', 'Unpin') : dlTr('dl_pin', 'Pin to the side'),
                        icon: Icon(p.isFrozen(col.key) ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            size: 18, color: p.isFrozen(col.key) ? c.primary : c.textLight),
                        onPressed: col.isHidden
                            ? null
                            : () {
                          if (!p.toggleFrozen(col.key)) toast(dlTr('dl_pin_keep_one', 'Keep at least one pinned column'), error: true);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'dl_menu_edit'.tr,
                        icon: Icon(Icons.edit_outlined, size: 18, color: c.textMedium),
                        onPressed: () => showColumnEditor(context, p, column: col),
                      ),
                    ),
                  ]),
                );
              },
              footer: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(color: c.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: p.hiddenCount == 0
                          ? null
                          : () async {
                        for (final col in cols.where((x) => x.isHidden).toList()) {
                          await _flag(col, hidden: false);
                        }
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: Text('dl_show_all'.tr, style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(color: c.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => showPinSheet(context, p),
                      icon: const Icon(Icons.push_pin_rounded, size: 18),
                      label: Text(dlTr('dl_pinned_title', 'Pinned columns'), style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: c.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => showColumnEditor(context, p),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('dl_new_column'.tr, style: dlText(13, w: FontWeight.w800, c: c.onHero)),
                ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
