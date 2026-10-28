// Deep links of the platform admins' assistant notices: the core's POST /internal/v1/notify/platform-admins takes a
// `module` (routers/internal_router.AdminNotice), carried in the push data and returned by
// GET /notifications/{id}/target for the list's tap.
//   rag_learning → the Learning page (the monthly LoRA readiness, rag_service/learning/lora.py)
//   rag_alerts   → the assistant console's Alerts tab (rag_service/alerts.py)
// Only a platform admin (admin · super-admin · developer) is taken there, and only while the kill switches allow it
// (`rag.admin` for the console, plus `rag.learning` for the Learning page); anyone else lands on the notifications
// list. AppNavigator.openModule hands these modules to [openRagAdminModule]; the decision is the pure
// [ragAdminTarget] (test/org/rag_admin_links_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import 'rag_admin_console.dart' show RagAdminConsole;
import 'rag_learning.dart' show kRagLearningFeatureKey;
import 'rag_learning_page.dart' show RagLearningPage;

const kRagLearningModule = 'rag_learning';
const kRagAlertsModule = 'rag_alerts';
const kRagAdminFeatureKey = 'rag.admin';

/// The roles the core sends these notices to (routers/internal_router.PLATFORM_ADMIN_ROLES).
const kPlatformAdminRoles = {'admin', 'super-admin', 'developer'};

enum RagAdminTarget { learning, alerts, notifications }

/// Where a tap on [module] goes; null when [module] is not one of these notices.
RagAdminTarget? ragAdminTarget(
  String? module, {
  required String? role,
  Iterable<String> disabled = const [],
}) {
  if (module != kRagLearningModule && module != kRagAlertsModule) return null;
  if (!kPlatformAdminRoles.contains(role) || disabled.contains(kRagAdminFeatureKey)) {
    return RagAdminTarget.notifications;
  }
  if (module == kRagAlertsModule) return RagAdminTarget.alerts;
  return disabled.contains(kRagLearningFeatureKey)
      ? RagAdminTarget.notifications
      : RagAdminTarget.learning;
}

/// Opens the page of [module] on [nav]. False when [module] is not an assistant notice (the caller routes it).
Future<bool> openRagAdminModule(
  NavigatorState nav,
  String? module, {
  required String? role,
}) async {
  switch (ragAdminTarget(module, role: role, disabled: AppConfig.disableList)) {
    case null:
      return false;
    case RagAdminTarget.notifications:
      await nav.pushNamed('/notifications');
    case RagAdminTarget.learning:
      await nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/rag_learning'),
        builder: (_) => const RagLearningPage(),
      ));
    case RagAdminTarget.alerts:
      await nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/rag_alerts'),
        builder: (_) => const RagAdminConsole(initialTab: RagAdminConsole.alertsTab),
      ));
  }
  return true;
}
