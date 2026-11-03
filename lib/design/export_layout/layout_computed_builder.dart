// TEMP stub (replaced by de/fa): the computed-columns editor. Same signature as the real one.
library;

import 'package:flutter/widgets.dart';

import 'layout_model.dart';

/// Opens the computed columns editor for [doc]. True when the document's computed fields changed.
Future<bool> showComputedFieldsEditor(
  BuildContext context, {
  required LayoutDocument doc,
  required List<LayoutField> fields,
  required List<Map<String, Object?>> sampleRows,
  required String lang,
}) async =>
    false;
