// lib/features/shared/data_lab/data_lab_columns_sheet.dart
// One simple list to decide, for EVERY column:
//   • "In table"  – show / hide it in the sheet
//   • "Students"  – show / hide it on the students' analytics profile
// Changes apply immediately. The pencil opens the full column editor (name, weights, delete …).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import 'data_lab_column_sheet.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
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
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text('dl_columns_sub'.tr, style: dlText(12.5, c: c.textMedium, h: 1.55)),
                const SizedBox(height: 12),
                // column captions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: [
                    const Expanded(child: SizedBox()),
                    SizedBox(width: 76, child: Center(child: Text('dl_col_in_table'.tr, style: dlText(11, w: FontWeight.w800, c: c.textMedium)))),
                    SizedBox(width: 76, child: Center(child: Text('dl_col_students'.tr, style: dlText(11, w: FontWeight.w800, c: c.textMedium)))),
                    const SizedBox(width: 36),
                  ]),
                ),
                const SizedBox(height: 6),
                for (final col in cols)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsetsDirectional.only(start: 14, end: 2, top: 4, bottom: 4),
                    decoration: BoxDecoration(
                      color: col.isHidden ? c.inputBg : c.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.divider),
                    ),
                    child: Row(children: [
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
                            Text(
                              col.isCalculated ? 'dl_kind_calc'.tr : (col.isBuiltin ? 'dl_kind_auto'.tr : 'dl_kind_manual_short'.tr),
                              style: dlText(10.5, c: c.textLight),
                            ),
                          ]),
                        ]),
                      ),
                      SizedBox(
                        width: 76,
                        child: Switch(value: !col.isHidden, activeTrackColor: c.primary, onChanged: (v) => _flag(col, hidden: !v)),
                      ),
                      SizedBox(
                        width: 76,
                        child: Switch(value: col.visibleToStudents, activeTrackColor: c.success, onChanged: (v) => _flag(col, students: v)),
                      ),
                      SizedBox(
                        width: 36,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.edit_outlined, size: 18, color: c.textMedium),
                          onPressed: () => showColumnEditor(context, p, column: col),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 8),
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
                      onPressed: () => showColumnEditor(context, p),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('dl_new_column'.tr, style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ]);
      },
    );
  }
}
