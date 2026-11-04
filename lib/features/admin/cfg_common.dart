// lib/features/admin/cfg_common.dart
//
// Small helpers shared by the Configuration hub pages (platform settings, live settings, recommendations, features,
// data lab, flags, versions, content, theme): the "this feature needs a server update" error state for a route the
// server does not have yet, the one Save button every settings page puts in its header, and a number helper.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../org/org_v3.dart' show orgEndpointMissing, orgErrorText;
import 'admin_common.dart' show t;
import 'admin_money_p8.dart' show parseAmountLoose;

/// True for FastAPI's bare 404 "Not Found" / 405: the server has no such route yet (not "this record is missing").
bool cfgEndpointMissing(Object? error) => error is ApiException && orgEndpointMissing(error);

/// The text of a failed call: the coded org text when there is one, else the server's own message.
String cfgErrorMessage(Object? error) =>
    error is ApiException ? orgErrorText(error) : appErrorMessage(error);

/// The error state of a page: "needs a server update" for a missing route, the normal error otherwise.
Widget cfgErrorState(Object? error, {VoidCallback? onRetry}) {
  if (cfgEndpointMissing(error)) {
    return AppErrorState(
      title: t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update'),
      message: t('الخادم الحالي لا يدعم هذه الصفحة بعد. حدّث الخادم ثم حاول مرة أخرى.',
          'The current server does not support this page yet. Update the server, then try again.'),
      onRetry: onRetry,
    );
  }
  return AppErrorState(message: cfgErrorMessage(error), onRetry: onRetry);
}

/// The ONE save pattern: the header's primary action, disabled when nothing changed, busy while saving.
Widget cfgSaveButton({required bool dirty, required bool busy, required VoidCallback onSave, bool enabled = true}) =>
    AppButton.primary(
      label: t('حفظ', 'Save'),
      icon: Icons.check_rounded,
      busy: busy,
      onPressed: enabled && dirty && !busy ? onSave : null,
    );

/// A decimal typed by a person ("12,5" or "12.5"); null when it is not a finite number.
double? cfgParseNumber(String s) {
  // "1,000" is a thousand, never 1.0 (parseAmountLoose); Arabic digits read too
  final v = parseAmountLoose(s);
  return v != null && v.isFinite ? v : null;
}

/// A small inline field error under an input (the kit's AppField has no error slot).
class CfgFieldError extends StatelessWidget {
  const CfgFieldError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, bottom: AppSpace.xs),
        child: Semantics(
          liveRegion: true,
          child: Text(text, style: AppType.meta(context).copyWith(color: context.colors.danger)),
        ),
      );
}
