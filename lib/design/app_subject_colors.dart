// lib/design/app_subject_colors.dart
//
// A subject's colour (KIT_SPEC §2.1): the server's subject slug or name (Arabic or English) -> one of the 11 kit
// subject keys, through one map; anything else is `other`. A server `color_key` on the subject wins when present.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show KitTone;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

/// The 11 keys of `kit.subjects`.
const List<String> kSubjectKeys = [
  'math', 'physics', 'chem', 'bio', 'english', 'arabic', 'qudurat', 'code', 'quran', 'islamic', 'other', //
];

const Map<String, String> _subjectAliases = {
  'math': 'math',
  'maths': 'math',
  'mathematics': 'math',
  'رياضيات': 'math',
  'الرياضيات': 'math',
  'physics': 'physics',
  'فيزياء': 'physics',
  'الفيزياء': 'physics',
  'chem': 'chem',
  'chemistry': 'chem',
  'كيمياء': 'chem',
  'الكيمياء': 'chem',
  'bio': 'bio',
  'biology': 'bio',
  'أحياء': 'bio',
  'الأحياء': 'bio',
  'احياء': 'bio',
  'english': 'english',
  'إنجليزي': 'english',
  'انجليزي': 'english',
  'اللغة الإنجليزية': 'english',
  'اللغة الانجليزية': 'english',
  'arabic': 'arabic',
  'عربي': 'arabic',
  'اللغة العربية': 'arabic',
  'nahw': 'arabic',
  'نحو': 'arabic',
  'qudurat': 'qudurat',
  'قدرات': 'qudurat',
  'القدرات': 'qudurat',
  'code': 'code',
  'coding': 'code',
  'programming': 'code',
  'computer': 'code',
  'برمجة': 'code',
  'البرمجة': 'code',
  'حاسب': 'code',
  'quran': 'quran',
  'قرآن': 'quran',
  'القرآن': 'quran',
  'القرآن الكريم': 'quran',
  'islamic': 'islamic',
  'islamic studies': 'islamic',
  'religion': 'islamic',
  'دين': 'islamic',
  'تربية إسلامية': 'islamic',
  'التربية الإسلامية': 'islamic',
  'دراسات إسلامية': 'islamic',
};

/// [serverSubject] (slug or name, any case, trimmed) -> a kit subject key; unknown -> `other`. [colorKey], when the
/// server sends one and it is a kit key, wins.
String subjectKeyFor(String? serverSubject, {String? colorKey}) {
  if (colorKey != null && kSubjectKeys.contains(colorKey)) return colorKey;
  final k = serverSubject?.trim().toLowerCase();
  if (k == null || k.isEmpty) return 'other';
  return _subjectAliases[k] ?? 'other';
}

/// The subject's tone (colour, tint, ink) and `fg` (the label on the solid colour), for the brightness.
({KitTone tone, Color fg}) subjectColors(BuildContext context, String? subject, {String? colorKey}) =>
    context.colors.kit.subject(subjectKeyFor(subject, colorKey: colorKey));
