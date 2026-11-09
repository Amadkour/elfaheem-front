// ─────────────────────────────────────────────────────────────────────────────
// add_item_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// FIX: The original used `_` as the builder's context parameter name,
/// which shadowed the outer [context] passed into the function.
/// This caused [Navigator.pop(context)] inside actions to use the OUTER context
/// instead of the dialog's context — potentially popping the wrong route.
/// Fixed by naming the builder parameter [dialogContext] and using it correctly.
Future<void> addItemDialog(
    String hint, void Function(String) onAdd, BuildContext context) async {
  final ctrl = TextEditingController();

  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => Directionality(
      textDirection: Directionality.of(context),
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.colors.radiusMedium)),
        title: Text(hint,
            style: TextStyle(
                fontFamily: AppFonts.display, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textDirection: Directionality.of(context),
          style: TextStyle(fontFamily: AppFonts.display),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: context.colors.caption,
            border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            // FIX: use dialogContext, not outer context
            onPressed: () => Navigator.pop(dialogContext),
            child:  Text('إلغاء',
                style: TextStyle(
                    fontFamily: AppFonts.display, color: context.colors.textMedium)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            // FIX: use dialogContext and pass trimmed text result
            onPressed: () =>
                Navigator.pop(dialogContext, ctrl.text.trim()),
            child: Text('إضافة',
                style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: context.colors.onHero,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );

  if (result != null && result.isNotEmpty) onAdd(result);
}