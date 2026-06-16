import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';
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
    return Material(
      shadowColor:  Color.fromRGBO(0, 0, 0, 0.25),
      color: context.themeConfig.inputBg(isDark:context.colors.isDark),
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: TextFormField(
        textDirection: TextDirection.rtl,
        controller: controller,
        style:  TextStyle(
            fontFamily: 'tajawal',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: context.themeConfig.textDark),
        decoration: InputDecoration(
            hintTextDirection: TextDirection.rtl,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            fillColor: context.themeConfig.inputBg(isDark:context.colors.isDark),
            hint: Text(
              label,
              style:  TextStyle(
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w600,
                  color: context.themeConfig.textMedium),
              textDirection: TextDirection.rtl,
            ),
            border: const OutlineInputBorder(borderSide: BorderSide.none),
            suffixIcon: const Icon(CupertinoIcons.calendar)),
        textInputAction: TextInputAction.next,
        readOnly: true,
        onTap: () {
          _selectDate(context);
        },
      ),
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
            primaryColorDark: context.themeConfig.inputBg(isDark:context.colors.isDark),
            colorScheme: isDark
                ? ColorScheme.dark(
              primary: context.themeConfig.accent,       // Selected day circle
              onPrimary: context.themeConfig.background, // Selected day text
              surface: context.themeConfig.cardBg,       // Picker background
              onSurface: context.themeConfig.textDark, // Day & header text
            )
                : ColorScheme.light(
              primary: context.themeConfig.accent,       // Selected day circle
              onPrimary: context.themeConfig.background, // Selected day text
              surface: context.themeConfig.cardBg,       // Picker background
              onSurface: context.themeConfig.textDark, // Day & header text
            ),
            textTheme: TextTheme.of(context).copyWith(
              displaySmall: const TextStyle(fontFamily: 'tajawal'),
              titleLarge: const TextStyle(fontFamily: 'tajawal'),
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
