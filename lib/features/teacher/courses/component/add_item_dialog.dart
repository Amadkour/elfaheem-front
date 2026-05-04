// ─────────────────────────────────────────────────────────────────────────────
// add_item_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';

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
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.colors.radiusMedium)),
        title: Text(hint,
            style: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontFamily: 'Cairo'),
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
                    fontFamily: 'Cairo', color: context.colors.textMedium)),
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
            child: const Text('إضافة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );

  if (result != null && result.isNotEmpty) onAdd(result);
}