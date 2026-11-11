import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
class MyDatePicker extends StatelessWidget {
  const MyDatePicker(
      {super.key,
      required this.onChange,
      required this.selectedDate,
      required this.controller,
      required this.label});

  final void Function(DateTime) onChange;
  final DateTime selectedDate;
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    // The kit's well (warm fill, radius 14, hairline, focus ring) with the calendar mark at the end.
    return TextFormField(
      textDirection: TextDirection.rtl,
      controller: controller,
      style: appFieldTextStyle(context),
      decoration: appFieldDecoration(context, hint: label, suffix: const Icon(CupertinoIcons.calendar)).copyWith(
        hintTextDirection: TextDirection.rtl,
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      textInputAction: TextInputAction.next,
      readOnly: true,
      onTap: () {
        _selectDate(context);
      },
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1960),
      lastDate: DateTime.now().subtract(const Duration(days: 360 * 5)),
      locale: const Locale('ar', 'AR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            primaryColorDark: context.colors.inputBg,
            colorScheme: isDark
                ? ColorScheme.dark(
              primary: context.colors.primary,       // Selected day circle
              onPrimary: context.colors.background, // Selected day text
              surface: context.colors.cardBg,       // Picker background
              onSurface: context.colors.textDark, // Day & header text
            )
                : ColorScheme.light(
              primary: context.colors.primary,       // Selected day circle
              onPrimary: context.colors.background, // Selected day text
              surface: context.colors.cardBg,       // Picker background
              onSurface: context.colors.textDark, // Day & header text
            ),
            textTheme: TextTheme.of(context).copyWith(
              displaySmall: TextStyle(fontFamily: AppFonts.family),
              titleLarge: TextStyle(fontFamily: AppFonts.family),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      onChange(picked);
    }
  }
}
