// lib/design/app_area.dart
//
// The area / role scope of the redesign kit (KIT_SPEC §2.5). A page (or a shell tab) sets ONE scope; the hero,
// buttons, selected states, empty plates, the bottom-bar blob and the motion budget read it:
//
//   AppAreaScope(area: AppArea.learn, child: ...)        a student area (the playful motion is allowed under it)
//   AppAreaScope.role(role: AppRoleAccent.teacher, ...)  a role accent (teacher, parent, admin, super admin)
//   AppAreaScope.of(context)                              the nearest scope's KitSet; no scope -> the home area
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'motion/motion_budget.dart';

export 'package:flutter_education_app/config/theme/kit_palette.dart'
    show AppAccent, AppArea, AppRoleAccent, AppRoleAccentKey, KitColors, KitSet, KitTone;

/// Set once per page (or once per shell tab).
class AppAreaScope extends StatelessWidget {
  const AppAreaScope({super.key, required AppArea this.area, required this.child, this.budget = true}) : role = null;

  const AppAreaScope.role({super.key, required AppRoleAccent this.role, required this.child, this.budget = true})
      : area = null;

  final AppArea? area;
  final AppRoleAccent? role;
  final Widget child;

  /// Wraps [child] in an [AppMotionBudget].
  final bool budget;

  static _AreaData? _data(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_AreaData>();

  /// The nearest scope's set; no scope -> `kit.area(AppArea.home)`.
  static KitSet of(BuildContext context) {
    final d = _data(context);
    final kit = context.colors.kit;
    if (d?.role != null) return kit.role(d!.role!);
    return kit.area(d?.area ?? AppArea.home);
  }

  /// Null under a role scope or with no scope.
  static AppArea? areaOf(BuildContext context) => _data(context)?.area;

  /// The nearest role accent, null under an area scope or with no scope.
  static AppRoleAccent? roleOf(BuildContext context) => _data(context)?.role;

  /// True only under an AREA scope (student): M1–M8, M11, M12, M15, M16 are allowed.
  static bool playful(BuildContext context) => _data(context)?.area != null;

  @override
  Widget build(BuildContext context) {
    final inner = budget ? AppMotionBudget(child: child) : child;
    return _AreaData(area: area, role: role, child: inner);
  }
}

class _AreaData extends InheritedWidget {
  const _AreaData({required this.area, required this.role, required super.child});

  final AppArea? area;
  final AppRoleAccent? role;

  @override
  bool updateShouldNotify(_AreaData old) => old.area != area || old.role != role;
}

/// teacher -> teacher · parent -> parent · admin, org-admin, org-staff -> admin · super-admin, developer ->
/// superAdmin · anything else -> null (student).
AppRoleAccent? appRoleAccentFor(String? role) => switch (role?.trim().toLowerCase()) {
      'teacher' => AppRoleAccent.teacher,
      'parent' => AppRoleAccent.parent,
      'admin' || 'org-admin' || 'org-staff' => AppRoleAccent.admin,
      'super-admin' || 'developer' => AppRoleAccent.superAdmin,
      _ => null,
    };
