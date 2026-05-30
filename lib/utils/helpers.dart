/// Helper utility functions.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../main.dart';

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
  static void showMessage( String message, {bool isError = false}) {
    if(navigatorKey.currentContext==null) {
      return;
    }
    BuildContext context= navigatorKey.currentContext!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          !isError ? Icons.check_circle_rounded : Icons.error_rounded,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 10),
        Text(
   message,
          style: const TextStyle(
              fontFamily: 'Tajawal',
              color: Colors.white,
              fontWeight: FontWeight.w600),
        ),
      ]),
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
                fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
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
                    fontFamily: 'Tajawal', color: context.colors.textMedium)),
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
