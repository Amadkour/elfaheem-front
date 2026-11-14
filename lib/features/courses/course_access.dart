import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart'; // String.tr
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/home/student/models.dart';

import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/profile/passcode/passcode_screen.dart';
import 'package:flutter_education_app/core/api_error_text.dart';

/// Opens the course detail screen, asking for the access code first when the
/// course is private.
///
/// The code is checked by the server (POST /api/v1/courses/{id}/unlock, which
/// is rate-limited), so it never has to be sent to the app.
Future<void> openCourse(BuildContext context, CourseModel c,ApiClient api) async {
  if (c.isPrivate) {
    // The access code is checked by a POST (needs an account) → a guest logs in first.
    if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_private')) return;
    final unlocked = await PasscodeSheet.show(
      context: context,
      title: 'course_passcode_title'.tr,
      hint: 'course_passcode_hint'.tr,
      wrongText: 'course_passcode_wrong'.tr,
      pinLength: 6,
      // must match the length of your generated access codes
      icon: Icons.vpn_key_rounded,
      verify: (code) async {
        // Succeeds → unlocked. A wrong code / rate limit makes the server
        // answer with an error, which ApiClient throws; its message is
        // shown in the sheet via errorText below.
        // ⚠ ADAPT THIS LINE to your ApiClient's POST signature.
        dynamic r= await api.post(
          '/api/v1/courses/${c.id}/unlock',
          body: {'code': code},
          auth: true,
        );
        return  r['unlocked']??false;
      },
      errorText: (e) => apiErrorText(ApiException.from(e)),
    );

    if (!unlocked || !context.mounted) return;
  }

  Navigator.pushNamed(context, '/course-detail', arguments: c);
}