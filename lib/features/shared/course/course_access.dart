import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart'; // String.tr
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/student/analysis/exam/passcode_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:provider/provider.dart';

import '../passcode/passcode_screen.dart';

/// Opens the course detail screen, asking for the access code first when the
/// course is private.
///
/// The code is checked by the server (POST /api/v1/courses/{id}/unlock, which
/// is rate-limited), so it never has to be sent to the app.
Future<void> openCourse(BuildContext context, CourseModel c) async {
  if (c.isPrivate) {
    final api = context.read<ApiClient>();
    final unlocked = await PasscodeSheet.show(
      context: context,
      title: 'course_passcode_title'.tr,
      hint: 'course_passcode_hint'.tr,
      wrongText: 'course_passcode_wrong'.tr,
      pinLength: 6, // must match the length of your generated access codes
      icon: Icons.vpn_key_rounded,
      verify: (code) async {
        // Succeeds → unlocked. A wrong code / rate limit makes the server
        // answer with an error, which ApiClient throws; its message is
        // shown in the sheet via errorText below.
        // ⚠ ADAPT THIS LINE to your ApiClient's POST signature.
        // await api.post('/api/v1/courses/${c.id}/unlock', {'code': code});
        return true;
      },
      errorText: (e) => e.toString(),
    );
    if (!unlocked || !context.mounted) return;
  }

  Navigator.pushNamed(context, '/course-detail', arguments: c);
}
