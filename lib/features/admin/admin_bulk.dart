// lib/features/admin/admin_bulk.dart — bulk actions of the admin tables (D-290, phase 8).
//
//   runAdminBulk(ids, (id) => api.put(…), refresh: p.reloadPage)
//
// Runs the single-row call the row menu already uses for every selected id, a few at a time, with no toast per row;
// then ONE refresh of the table and ONE notice: "12 updated" or "10 updated · 2 failed".
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart' show mdText;

/// Requests in flight at once.
const adminBulkParallel = 4;

/// Runs [one] for each of [ids]; returns how many failed.
Future<int> runAdminBulk(List<int> ids, Future<void> Function(int id) one, {required Future<void> Function() refresh}) async {
  var failed = 0;
  for (var i = 0; i < ids.length; i += adminBulkParallel) {
    final chunk = ids.skip(i).take(adminBulkParallel);
    await Future.wait(chunk.map((id) async {
      try {
        await one(id);
      } catch (_) {
        failed++;
      }
    }));
  }
  try {
    await refresh();
  } catch (_) {}
  final done = ids.length - failed;
  showAppNotice(
    failed == 0
        ? mdText('md_p8_bulk_done', {'n': '$done'})
        : mdText('md_p8_bulk_partial', {'n': '$done', 'failed': '$failed'}),
    error: failed > 0 && done == 0,
  );
  return failed;
}

/// Asks before a bulk change of [n] rows ([danger]: the red confirm).
Future<bool> confirmAdminBulk(BuildContext context, String actionLabel, int n, {bool danger = false}) => appConfirm(
      context,
      message: mdText('md_p8_bulk_confirm', {'action': actionLabel, 'n': '$n'}),
      danger: danger,
      confirmLabel: actionLabel,
    );

/// The bulk bar's button.
AppButton adminBulkButton(String label, IconData icon, VoidCallback onPressed) =>
    AppButton.tonal(label: label, icon: icon, size: AppButtonSize.sm, onPressed: onPressed);

