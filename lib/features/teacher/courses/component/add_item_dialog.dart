import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';

Future<void> addItemDialog(String hint, void Function(String) onAdd,BuildContext context) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
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
            hintStyle: AppTheme.caption,
            border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppTheme.textMedium)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
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
