// Small pieces the template screens share: the colour of a field type, the confidence colour, the picture picker.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart';

/// Picks one picture: (name, bytes), or null when the person cancelled. [camera]: take a photo (phones only).
typedef MarkImagePicker = Future<(String, Uint8List)?> Function({required bool camera});

Future<(String, Uint8List)?> defaultMarkImagePicker({required bool camera}) async {
  try {
    if (camera) {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 3000, imageQuality: 92);
      if (x == null) return null;
      return (x.name.isEmpty ? 'sheet.jpg' : x.name, await x.readAsBytes());
    }
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp']);
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// A phone can take the photo itself; the web and desktop upload a file.
bool get canUseCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// The colour a box of [type] is drawn with.
Color fieldColor(BuildContext context, FieldType type) {
  final c = context.colors;
  return switch (type) {
    FieldType.identifier => c.primary,
    FieldType.questionMark => c.success,
    FieldType.total => c.warning,
    FieldType.answerRow => c.purple,
    FieldType.unset => c.textMedium,
  };
}

IconData fieldIcon(FieldType type) => switch (type) {
      FieldType.identifier => Icons.badge_outlined,
      FieldType.questionMark => Icons.edit_note_rounded,
      FieldType.total => Icons.functions_rounded,
      FieldType.answerRow => Icons.view_week_outlined,
      FieldType.unset => Icons.help_outline_rounded,
    };

IconData kindIcon(MarkKind? k) => switch (k) {
      MarkKind.cover => Icons.description_outlined,
      MarkKind.markSheet => Icons.grading_rounded,
      MarkKind.answerTable => Icons.grid_view_rounded,
      null => Icons.insert_drive_file_outlined,
    };

/// Traffic light of a read confidence: green from 0.9, amber from 0.7, red below.
Color confColor(BuildContext context, double conf, {bool ok = true}) {
  final c = context.colors;
  if (!ok) return c.danger;
  if (conf >= 0.9) return c.success;
  if (conf >= 0.7) return c.warning;
  return c.danger;
}

/// "92 %" for 0.92.
String pct(double v) => '${(v * 100).round()}%';

/// A typed number: Latin or Arabic-Indic digits, "," or "٫" as the decimal mark. Null when it is not a number.
double? parseNumber(String s) {
  var x = s.trim();
  if (x.isEmpty) return null;
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in x.runes) {
    final ch = String.fromCharCode(r);
    final i = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : (ch == ',' || ch == '٫' ? '.' : ch));
  }
  x = b.toString();
  return double.tryParse(x);
}
