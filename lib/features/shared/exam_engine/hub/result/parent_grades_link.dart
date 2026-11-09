// A parent's notice "a new result for your child" (module `parent_grades`, data `{exam_id}`, D-350) → the child's report, where
// the grades are. The server's notice goes to the parents of every student it covers and does not name the child, so one child
// opens directly and a parent of several chooses. Deferred from AppNavigator (the parent screens stay out of the first download).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../parent/parent_widgets.dart' show plList;
import '../../../../parent/parent_reports_page.dart' show ParentChildReportScreen;

/// The child the link means, or null while it is open: [wanted] when that child is linked, else the only child.
Map<String, dynamic>? parentGradesChild(List<Map<String, dynamic>> children, int? wanted) {
  if (wanted != null) {
    for (final c in children) {
      if ((c['id'] as num?)?.toInt() == wanted) return c;
    }
  }
  return children.length == 1 ? children.first : null;
}

/// False when there is no child to show (the caller falls back to the notifications).
Future<bool> openParentGradesLink(NavigatorState nav, BuildContext context, Map<String, dynamic> data, {ApiClient? api}) async {
  final List<Map<String, dynamic>> children;
  try {
    children = plList(await (api ?? ApiClient()).get('/api/v1/parent/children'));
  } catch (_) {
    return false;
  }
  if (children.isEmpty || !context.mounted) return false;
  var child = parentGradesChild(children, int.tryParse('${data['student_id'] ?? ''}'));
  child ??= await showAppSheet<Map<String, dynamic>>(
      context,
      (ctx) => AppSheetContent(title: t('نتيجة أي ابن؟', 'Whose result?'), children: [
            for (final c in children)
              ListTile(
                key: ValueKey('parent.grades.${c['id']}'),
                contentPadding: EdgeInsets.zero,
                leading: AppAvatar(name: '${c['name'] ?? ''}', size: 38),
                title: Text('${c['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(ctx).pop(c),
              ),
          ]));
  if (child == null) return true; // the parent dismissed the choice: stay where they are
  final picked = child;
  await nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/parent-child-report'),
      builder: (_) => ParentChildReportScreen(studentId: (picked['id'] as num).toInt(), studentName: '${picked['name'] ?? ''}')));
  return true;
}
