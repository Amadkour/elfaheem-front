// shared/session/material/components/material_file_style.dart
//
// Brand-style icon for common attachment types (Word / Excel / CSV /
// PowerPoint / Python). Drawn as a coloured badge with letters so it needs no
// extra icon package. The extension comes from SessionMaterialModel.fileExtension.

import 'package:flutter/material.dart';

class MaterialFileStyle {
  final String label; // shown in the type pill
  final String badge; // letters drawn inside the icon box
  final Color color;
  final Color badgeTextColor;

  const MaterialFileStyle({
    required this.label,
    required this.badge,
    required this.color,
    this.badgeTextColor = Colors.white,
  });

  static const word = MaterialFileStyle(
    label: 'Word',
    badge: 'W',
    color: Color(0xFF2B579A),
  );
  static const excel = MaterialFileStyle(
    label: 'Excel',
    badge: 'X',
    color: Color(0xFF217346),
  );
  static const csv = MaterialFileStyle(
    label: 'CSV',
    badge: 'CSV',
    color: Color(0xFF00897B),
  );
  static const powerPoint = MaterialFileStyle(
    label: 'PowerPoint',
    badge: 'P',
    color: Color(0xFFD24726),
  );
  static const python = MaterialFileStyle(
    label: 'Python',
    badge: 'PY',
    color: Color(0xFF3776AB),
    badgeTextColor: Color(0xFFFFD43B), // Python yellow
  );

  /// null → no special style (caller falls back to the generic type icon).
  static MaterialFileStyle? forExtension(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'doc':
      case 'docx':
        return word;
      case 'xls':
      case 'xlsx':
        return excel;
      case 'csv':
        return csv;
      case 'ppt':
      case 'pptx':
        return powerPoint;
      case 'py':
        return python;
      default:
        return null;
    }
  }
}
