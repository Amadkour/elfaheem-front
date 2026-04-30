import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/component/time_text_field.dart';

import '../../../../config/app_theme.dart';

Future<void> addScheduleDialog(
    BuildContext context,
    void Function(String? selectedDay, String? startTime, String? endTime)
        onPressed) async {
  String? selectedDay;
  final startCtrl = TextEditingController(text: '10:00');
  final endCtrl = TextEditingController(text: '12:00');

  const days = [
    ('monday', 'الإثنين'),
    ('tuesday', 'الثلاثاء'),
    ('wednesday', 'الأربعاء'),
    ('thursday', 'الخميس'),
    ('friday', 'الجمعة'),
    ('saturday', 'السبت'),
    ('sunday', 'الأحد'),
  ];

  await showDialog<void>(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
          title: const Text('إضافة موعد أسبوعي',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Day picker
              DropdownButtonFormField<String>(
                initialValue: selectedDay,
                decoration: InputDecoration(
                  labelText: 'اليوم',
                  labelStyle: AppTheme.caption,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: days
                    .map((d) => DropdownMenuItem(
                          value: d.$1,
                          child: Text(d.$2,
                              style: const TextStyle(fontFamily: 'Cairo')),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedDay = v),
              ),
              const SizedBox(height: 12),
              // Times
              Row(
                children: [
                  Expanded(
                      child: TimeField(label: 'من', controller: startCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: TimeField(label: 'إلى', controller: endCtrl)),
                ],
              ),
            ],
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
              onPressed: () {
                onPressed(selectedDay, startCtrl.text, endCtrl.text);
              },
              child: const Text('إضافة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ),
  );
}
