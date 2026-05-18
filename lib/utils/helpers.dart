/// Helper utility functions.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../config/app_config.dart';
import '../config/app_theme.dart';

class Helpers {
  /// Format date to readable string
  static String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  /// Format datetime to readable string
  static String formatDateTime(DateTime date) {
    return DateFormat('MMM dd, yyyy hh:mm a').format(date);
  }

  /// Format time
  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
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
  static void showMessage(context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static TextDirection get pageDirection => AppConfig.lang=='ar'? TextDirection.rtl:TextDirection.ltr;

  static Future<bool?> confirmLogout(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (_) => Directionality(
      textDirection: Helpers.pageDirection,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.colors.radiusMedium)),
        title:  Text('logout'.tr,
            style: const TextStyle(
                fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
        content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:  Text('cancel'.tr,
                style:  TextStyle(
                    fontFamily: 'Tajawal', color: context.colors.textMedium)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child:  Text('exit'.tr,
                style: const TextStyle(
                    fontFamily: 'Tajawal',
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
}
