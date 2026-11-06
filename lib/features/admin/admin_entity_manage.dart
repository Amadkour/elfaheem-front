// lib/features/admin/admin_entity_manage.dart — what an admin does on an entity, inside its connected detail (D-290).
//
// The detail (any list's panel, the full page) draws this block for a viewer the server lets manage the entity. It is
// a deferred library (deferred_screens.dart), so only those viewers download the admin screens behind it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart' show EntitySummary;
import 'package:flutter_education_app/core/entities/entity_ref.dart' show EntityKind;

import 'admin_categories_page.dart' show AdminCategoryManage;
import 'admin_users_page.dart' show AdminTeacherManage;

/// The management block of [summary]. [onChanged]: something was saved, the detail loads again. [onRemoved]: the
/// entity is gone.
Widget adminEntityManage(EntitySummary summary, {VoidCallback? onChanged, VoidCallback? onRemoved}) =>
    switch (summary.kind) {
      EntityKind.teacher => AdminTeacherManage(summary: summary, onChanged: onChanged, onRemoved: onRemoved),
      EntityKind.category => AdminCategoryManage(summary: summary, onChanged: onChanged, onRemoved: onRemoved),
      _ => const SizedBox.shrink(),
    };
