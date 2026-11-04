// Who may upload where (the scope picker of the RAG library upload) and the widget that draws it.
//
// The server decides (`POST /documents`: app / global = platform admins only, org / staff = the organization's
// library managers, course = the course's staff); this file only keeps the picker honest, so nobody is offered a
// choice the server would refuse. The caller's kind comes from the screen's context and the server's own `manager`
// flag of the list call, never from a guess about the account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../admin/admin_common.dart' show t;

/// What the person uploading is, for the library they opened.
enum RagUploaderRole { platformAdmin, orgAdmin, courseStaff, none }

/// The caller's kind from the screen it opened: [app] = the app library (platform admins), a [courseId] = a course's
/// library (its staff), an [orgId] = the organization's library (its managers). [manager] is the server's flag.
RagUploaderRole ragUploaderRole({required bool manager, bool app = false, int? orgId, int? courseId}) {
  if (!manager) return RagUploaderRole.none;
  if (app) return RagUploaderRole.platformAdmin;
  if (courseId != null) return RagUploaderRole.courseStaff;
  if (orgId != null) return RagUploaderRole.orgAdmin;
  return RagUploaderRole.none;
}

/// The scopes the caller may pick, in display order. `app` and `global` are never offered to anyone else.
List<String> ragScopeOptions(RagUploaderRole role) => switch (role) {
      RagUploaderRole.platformAdmin => const ['app', 'global'],
      RagUploaderRole.orgAdmin => const ['org', 'staff', 'course'],
      RagUploaderRole.courseStaff => const ['course'],
      RagUploaderRole.none => const [],
    };

/// The org roles a document of the whole-organization scope may be limited to (the server's `ORG_ROLES`).
const ragOrgRoles = ['student', 'teacher', 'teacher_assistant', 'admin_assistant', 'org_admin', 'staff'];

String ragOrgRoleText(String r) => switch (r) {
      'student' => t('الطلاب', 'Students'),
      'teacher' => t('المعلمون', 'Teachers'),
      'teacher_assistant' => t('مساعدو المعلمين', 'Teaching assistants'),
      'admin_assistant' => t('المساعدون الإداريون', 'Admin assistants'),
      'org_admin' => t('مديرو المؤسسة', 'Organization admins'),
      'staff' => t('الموظفون', 'Staff'),
      _ => r,
    };

/// The picker's label of a scope (short: it sits on a chip). The document card keeps `ragScopeText`.
String ragScopePickText(String s) => switch (s) {
      'app' => t('كيف يعمل التطبيق (للجميع)', 'How the app works (everyone)'),
      'global' => t('كل الطلاب', 'All students'),
      'org' => t('المؤسسة كلها', 'Whole organization'),
      'staff' => t('الهيئة فقط', 'Staff only'),
      'course' => t('مقرر', 'A course'),
      _ => s,
    };

/// The `roles` form field: a comma list, only for the whole-organization scope and only when something is picked.
String? ragRolesField(String scope, Iterable<String> roles) {
  if (scope != 'org') return null;
  final r = [for (final x in ragOrgRoles) if (roles.contains(x)) x];
  return r.isEmpty ? null : r.join(',');
}

/// A course the organization admin may pick (id + the name in the app language).
class RagCourseChoice {
  const RagCourseChoice(this.id, this.name);
  final int id;
  final String name;
}

/// Scope chips · (org scope) optional role chips · (course scope) the course picker or a manual id.
/// Presentational: the parent owns the values.
class RagScopePicker extends StatelessWidget {
  const RagScopePicker({
    super.key,
    required this.options,
    required this.scope,
    required this.onScope,
    this.roles = const {},
    this.onRoles,
    this.courses = const [],
    this.courseId,
    this.onCourse,
    this.courseField,
    this.fixedCourse = false,
    this.busy = false,
  });
  final List<String> options;
  final String scope;
  final ValueChanged<String> onScope;
  final Set<String> roles;
  final ValueChanged<String>? onRoles;

  /// The organization's courses; empty = [courseField] (a manual id) is shown instead.
  final List<RagCourseChoice> courses;
  final int? courseId;
  final ValueChanged<int?>? onCourse;
  final Widget? courseField;

  /// the course is fixed by the screen (a course's own library): no picker
  final bool fixedCourse;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (options.length > 1) ...[
        Text(t('من يرى هذه المستندات؟', 'Who sees these documents?'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in options) AppChoiceChip(label: ragScopePickText(s), selected: scope == s, onTap: busy ? () {} : () => onScope(s)),
        ]),
        const SizedBox(height: 12),
      ],
      if (scope == 'org' && onRoles != null) ...[
        Text(t('اقتصر على أدوار (اختياري — الكل إن لم تختر)', 'Only these roles (optional — everyone if none)'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in ragOrgRoles) AppChoiceChip(label: ragOrgRoleText(r), selected: roles.contains(r), onTap: busy ? () {} : () => onRoles!(r)),
        ]),
        const SizedBox(height: 12),
      ],
      if (scope == 'course' && !fixedCourse) ...[
        if (courses.isNotEmpty && onCourse != null)
          AppDropdown<int>(
            value: courses.any((x) => x.id == courseId) ? courseId! : 0,
            decoration: InputDecoration(labelText: t('المقرر', 'Course')),
            items: [
              DropdownMenuItem(value: 0, child: Text(t('اختر مقرراً', 'Choose a course'))),
              for (final x in courses) DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: busy ? null : (v) => onCourse!(v == null || v == 0 ? null : v),
          )
        else if (courseField != null)
          courseField!,
        const SizedBox(height: 12),
      ],
    ]);
  }
}
