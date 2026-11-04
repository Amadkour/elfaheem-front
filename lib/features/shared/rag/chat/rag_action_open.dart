// Opens an assistant action button (FRONT_CONTRACTS "Chat"): the page id + params become a location through
// `AppRoutes.location` (D-170) and are pushed on the app's navigator exactly like a deep link or a notification tap
// (`AppShellNav.pushTarget() ?? navigatorKey`, the router's `onGenerateRoute` builds the page). `org_id` first puts
// the app in that organization (`AppModeController.openOrg`, which ignores an organization the person is not in).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter_education_app/main.dart' show navigatorKey;

import 'rag_payload.dart';

/// Opens [action]; false when it has no location here (hidden buttons never reach this). [beforeOpen] runs first
/// (the pop-up closes itself so the page is not hidden behind it).
Future<bool> openRagAction(RagAction action, {VoidCallback? beforeOpen}) async {
  final location = action.location;
  if (location == null) return false;
  beforeOpen?.call();
  final org = action.orgId;
  if (org != null && AppConfig.orgsEnabled) {
    try {
      await AppModeController.instance.openOrg(org);
    } catch (_) {/* never block the tap: the page opens as it is */}
  }
  final nav = AppShellNav.pushTarget() ?? navigatorKey.currentState;
  if (nav == null) return false;
  unawaited(nav.pushNamed(location));
  return true;
}
