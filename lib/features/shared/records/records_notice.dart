// lib/features/shared/records/records_notice.dart — the notice after a meeting recording stopped (D-311): the file
// is being assembled and lands in Records; "Open" goes there (AppNavigator module `records`). Called by the meeting
// recorder once its stop reached the server (room_recorder.dart `_postStop`), so it shows after "End for everyone"
// and after a plain Stop alike. Kept apart from records_page.dart so the recorder does not import the player.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';

import '../../admin/admin_common.dart' show t;
import '../guest/guest_state.dart';
import 'records_api.dart' show kRecordsFeatureKey;

void showRecordsSavingNotice() {
  if (AppConfig.disableList.contains(kRecordsFeatureKey) || GuestState.active || ViewAsState.active) return;
  showAppNotice(
    t('جارٍ حفظ تسجيلك في «التسجيلات»', 'Saving your recording to Records'),
    icon: Icons.video_library_rounded,
    actionLabel: t('فتح', 'Open'),
    onAction: () => unawaited(AppNavigator.openModule('records')),
  );
}
