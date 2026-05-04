import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
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
      color: context.colors.inputBg,
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: TextFormField(
        textDirection: TextDirection.rtl,
        controller: controller,
        style:  TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: context.colors.textDark),
        decoration: InputDecoration(
            hintTextDirection: TextDirection.rtl,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            fillColor: context.colors.inputBg,
            hint: Text(
              label,
              style:  TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w600,
                  color: context.colors.textMedium),
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
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      // Refer step 1
      firstDate: DateTime(1960),
      lastDate: DateTime.now().subtract(const Duration(days: 360 * 5)),
      locale: const Locale('ar', 'AR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:  ColorScheme.light(
              primary: context.colors.accent, // Primary color
              onPrimary: context.colors.background, // Selected day text
              onSurface: Colors.black, // Header background
            ),
            textTheme: TextTheme.of(context).copyWith(
              displaySmall: const TextStyle(fontFamily: 'Tajawal'),
              titleLarge: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
          child: child!,
        );
      }, // Set the locale to Arabic
    );
    if (picked != null && picked != selectedDate) {
      onChange(picked);
    }
  }
}
