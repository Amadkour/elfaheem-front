/// Helper utility functions.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../features/student/models.dart';
import '../features/teacher/home/teacher_models.dart';
import '../features/teacher/sessions/components/session_form_sheet.dart';
import '../features/teacher/sessions/sessions_provider.dart';
import '../main.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Saudi Arabia Timezone  (AST = UTC+3, no DST)
// ══════════════════════════════════════════════════════════════════════════════

/// The fixed UTC+3 offset used in Saudi Arabia (and Egypt Standard Time).
const Duration _kAstOffset = Duration(hours: 3);

/// Extension on [String] — drop-in replacement for [DateTime.parse] that
/// returns a [DateTime] in Saudi Arabia / Egypt local time (UTC+3).
///
/// Usage:
///   final dt = '2025-06-01T10:00:00Z'.toLocalSaTime();
///   // dt is 2025-06-01 13:00:00.000+03:00
extension SaudiDateTimeString on String {
  /// Parse this ISO-8601 string and convert to AST (UTC+3).
  /// Returns [DateTime.now()] in AST if parsing fails.
  DateTime get toLocalSaTime{
    try {
      final parsed = DateTime.parse(this);
      return parsed.toAst();
    } catch (_) {
      return DateTime.now().toAst();
    }
  }
}

/// Extension on [DateTime] for Saudi Arabia / Egypt time conversions.
extension SaudiDateTime on DateTime {
  static final _astTimeZone = DateTime.now().timeZoneOffset; // unused – kept for docs

  /// Convert any [DateTime] (UTC or local) to AST (UTC+3).
  DateTime toAst() {
    final utc = isUtc ? this : toUtc();
    return utc.add(_kAstOffset);
  }

  /// Format this datetime in AST and return a display string.
  /// Falls back to the raw value if [pattern] is invalid.
  String toAstString([String pattern = 'MMM dd, yyyy hh:mm a']) {
    return DateFormat(pattern).format(toAst());
  }

  /// true if this datetime is in AST (offset == +03:00).
  bool get isAst => timeZoneOffset == _kAstOffset;
}

class Helpers {
  /// Format date to readable string (AST)
  static String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date.toAst());
  }

  /// Format datetime to readable string (AST)
  static String formatDateTime(DateTime date) {
    return DateFormat('MMM dd, yyyy hh:mm a').format(date.toAst());
  }

  /// Format time (AST)
  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date.toAst());
  }

  /// Format currency
  static String formatCurrency(double amount) {
    return '${amount.toStringAsFixed(2)} \$';
  }

  /// Format duration (seconds to HH:MM:SS)
  static String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Get relative time (e.g., "2 hours ago")
  static String getRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return formatDate(date);
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  /// Show snackbar message
  static void showMessage( String message, {bool isError = false}) {
    if(navigatorKey.currentContext==null) {
      return;
    }
    BuildContext context= navigatorKey.currentContext!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Directionality(
        textDirection: pageDirection,
        child: Wrap(children: [
            Icon(
              !isError ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              message,
              style: const TextStyle(
                  fontFamily: 'tajawal',
                  color: Colors.white,
                  fontWeight: FontWeight.w600),
            ),
          ]),
      ),
      backgroundColor:
      !isError ? context.colors.success : context.colors.danger,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }


  static TextDirection get pageDirection => AppConfig.lang=='ar'? TextDirection.rtl:TextDirection.ltr;

  static Future<bool?> confirmDialog(BuildContext context,{
    String? title,
    String? confirm,
    String? cancel,
    void Function()? onConfirm,
    void Function()? onCancel
  }) => showDialog<bool>(
    context: context,
    builder: (_) => Directionality(
      textDirection: Helpers.pageDirection,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.colors.radiusMedium)),
        title:  Text(confirm?? 'logout'.tr,
            style: const TextStyle(
                fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
        content:  Text(title??'هل أنت متأكد أنك تريد تسجيل الخروج؟',
            style: TextStyle(fontFamily: 'bahji')),
        actions: [
          TextButton(
            onPressed: () {
              if(onConfirm!=null){
                onConfirm.call();
              }else{
                Navigator.pop(context, false);
              }            },
            child:  Text(cancel??'cancel'.tr,
                style:  TextStyle(
                    fontFamily: 'tajawal', color: context.colors.textMedium)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if(onConfirm!=null){
                onConfirm.call();
              }else{
                Navigator.pop(context, true);
              }
            },
            child:  Text(confirm??'exit'.tr,
                style: const TextStyle(
                    fontFamily: 'tajawal',
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );

  static double  calculateRemainingWidth(BuildContext context,{double? maxWith}) {
    return context.width >= 1100 ? (maxWith??900) : context.width >= 900 ? 650: context.width >=
        900 ? 500 : context.width >= 600 ? context.width - 70 : context.width;
  }

  static void showAddSessionSheet(BuildContext context, TeacherCourse course,
      {TeacherSessionItem? existing,bool? openLive}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<TeacherCourseScreenProvider>(),
        child: SessionFormSheet(existing: existing, courseId: course.id,openLive:openLive),
      ),
    );
  }

}