// lib/design/master_detail/entity_navigator.dart — where a mention of a student / course / teacher / category opens
// (D-290).
//
//   EntityNavigator.open(context, ref)
//     inside a MasterDetailScaffold's panel   the panel drills in (the trail grows, breadcrumbs show the way back)
//     inside its list                         the panel opens on that entity (a new trail)
//     anywhere else                           the full page `/view/<kind>/<id>` is pushed (a notification, a mention
//                                             on any page)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';

import 'entity_panel_controller.dart';

/// The nearest master-detail host: its controller, and whether [context] is inside its panel.
class MasterDetailScope extends InheritedWidget {
  const MasterDetailScope({super.key, required this.controller, this.inPanel = false, required super.child});

  final EntityPanelController controller;
  final bool inPanel;

  static MasterDetailScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MasterDetailScope>();

  @override
  bool updateShouldNotify(MasterDetailScope oldWidget) =>
      oldWidget.controller != controller || oldWidget.inPanel != inPanel;
}

abstract final class EntityNavigator {
  /// The full page's URL of [ref].
  static String location(EntityRef ref) =>
      AppRoutes.location(AppRoutes.entityView.id, {'kind': ref.kind.name, 'id': ref.id});

  /// Opens [ref] where it belongs (see the file header).
  static void open(BuildContext context, EntityRef ref) {
    final scope = MasterDetailScope.maybeOf(context);
    if (scope != null) {
      if (scope.inPanel) {
        scope.controller.push(ref);
      } else {
        scope.controller.open(ref);
      }
      return;
    }
    openFullPage(context, ref);
  }

  /// Pushes the full page of [ref] (its own URL, refresh-safe).
  static Future<void> openFullPage(BuildContext context, EntityRef ref) =>
      Navigator.of(context).pushNamed(location(ref), arguments: ref);
}
