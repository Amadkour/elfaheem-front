// lib/core/display/display_settings.dart
//
// The person's display and reading preferences, kept on the device (SharedPreferences, one JSON value):
//
//   arabicFont · latinFont   AppFonts catalog ids, one per language
//   textScale               text size on top of the system's (0.85 – 1.6)
//   zoom                    the whole interface — text, icons, spacing, touch targets (0.9 – 1.4)
//   boldText                every Text drawn bold (MediaQuery.boldText)
//   highContrast            muted / faint text and dividers pulled toward the main ink (ThemeConfigProvider)
//   reduceMotion            no page transitions, MediaQuery.disableAnimations for widgets that honour it
//   largeTargets            padded tap targets and roomier density for buttons, chips and list tiles
//
// `presets` are one-tap bundles ("Young learners", "Easy reading") of the same fields. AppDisplayScope
// (lib/design/app_display.dart, in MaterialApp.builder) applies everything; this file holds no widgets.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_fonts.dart';

@immutable
class DisplayPrefs {
  const DisplayPrefs({
    this.arabicFont = AppFonts.arabicDefault,
    this.latinFont = AppFonts.latinDefault,
    this.textScale = 1.0,
    this.zoom = 1.0,
    this.boldText = false,
    this.highContrast = false,
    this.reduceMotion = false,
    this.largeTargets = false,
  });

  static const minText = 0.85, maxText = 1.6, minZoom = 0.9, maxZoom = 1.4;

  final String arabicFont, latinFont;
  final double textScale, zoom;
  final bool boldText, highContrast, reduceMotion, largeTargets;

  bool get isDefault => this == const DisplayPrefs();

  DisplayPrefs copyWith({
    String? arabicFont,
    String? latinFont,
    double? textScale,
    double? zoom,
    bool? boldText,
    bool? highContrast,
    bool? reduceMotion,
    bool? largeTargets,
  }) =>
      DisplayPrefs(
        arabicFont: arabicFont ?? this.arabicFont,
        latinFont: latinFont ?? this.latinFont,
        textScale: (textScale ?? this.textScale).clamp(minText, maxText).toDouble(),
        zoom: (zoom ?? this.zoom).clamp(minZoom, maxZoom).toDouble(),
        boldText: boldText ?? this.boldText,
        highContrast: highContrast ?? this.highContrast,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        largeTargets: largeTargets ?? this.largeTargets,
      );

  Map<String, dynamic> toJson() => {
        'ar': arabicFont,
        'en': latinFont,
        'text': textScale,
        'zoom': zoom,
        'bold': boldText,
        'contrast': highContrast,
        'motion': reduceMotion,
        'targets': largeTargets,
      };

  /// Unknown or broken values fall back to the defaults field by field.
  factory DisplayPrefs.fromJson(Map<String, dynamic> j) {
    double num_(Object? v, double d) => v is num ? v.toDouble() : d;
    bool bool_(Object? v) => v == true;
    return const DisplayPrefs().copyWith(
      arabicFont: AppFonts.byId('${j['ar']}', arabic: true).id,
      latinFont: AppFonts.catalog.any((f) => f.id == j['en']) ? '${j['en']}' : AppFonts.latinDefault,
      textScale: num_(j['text'], 1.0),
      zoom: num_(j['zoom'], 1.0),
      boldText: bool_(j['bold']),
      highContrast: bool_(j['contrast']),
      reduceMotion: bool_(j['motion']),
      largeTargets: bool_(j['targets']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayPrefs &&
      other.arabicFont == arabicFont &&
      other.latinFont == latinFont &&
      other.textScale == textScale &&
      other.zoom == zoom &&
      other.boldText == boldText &&
      other.highContrast == highContrast &&
      other.reduceMotion == reduceMotion &&
      other.largeTargets == largeTargets;

  @override
  int get hashCode => Object.hash(arabicFont, latinFont, textScale, zoom, boldText, highContrast, reduceMotion, largeTargets);
}

/// A one-tap bundle of preferences.
@immutable
class DisplayPreset {
  const DisplayPreset(this.id, this.icon, this.nameAr, this.nameEn, this.noteAr, this.noteEn, this.prefs);
  final String id;
  final IconData icon;
  final String nameAr, nameEn, noteAr, noteEn;
  final DisplayPrefs prefs;
}

class DisplaySettings extends ChangeNotifier {
  DisplaySettings._();
  static final DisplaySettings instance = DisplaySettings._();

  static const _key = 'display_prefs_v1';

  static const presets = <DisplayPreset>[
    DisplayPreset('standard', Icons.tune_rounded, 'قياسي', 'Standard',
        'الإعدادات الافتراضية', 'The default look', DisplayPrefs()),
    DisplayPreset('young', Icons.child_care_rounded, 'للمتعلمين الصغار', 'Young learners',
        'خط ودود، نص أكبر قليلاً، أزرار أوسع', 'Friendly fonts, slightly bigger text, roomier buttons',
        DisplayPrefs(arabicFont: 'almarai', latinFont: 'lexend', textScale: 1.1, zoom: 1.05, largeTargets: true)),
    DisplayPreset('easy', Icons.visibility_rounded, 'قراءة مريحة', 'Easy reading',
        'لكبار السن وضعاف البصر: نص وواجهة أكبر، تباين أعلى، حركة أقل',
        'For older eyes: bigger text and interface, stronger contrast, less motion',
        DisplayPrefs(
            arabicFont: 'readex',
            latinFont: 'atkinson',
            textScale: 1.25,
            zoom: 1.1,
            boldText: true,
            highContrast: true,
            reduceMotion: true,
            largeTargets: true)),
  ];

  DisplayPrefs _prefs = const DisplayPrefs();
  DisplayPrefs get prefs => _prefs;

  /// The id of the preset the current preferences equal, null = custom.
  String? get presetId => presets.where((p) => p.prefs == _prefs).firstOrNull?.id;

  /// Reads the saved preferences and loads the chosen fonts (start-up; never throws).
  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null && raw.isNotEmpty) _prefs = DisplayPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[DisplaySettings] load failed: $e');
    }
    AppFonts.setChoices(arabic: _prefs.arabicFont, latin: _prefs.latinFont);
    await AppFonts.select(arabic: _prefs.arabicFont, latin: _prefs.latinFont);
    notifyListeners();
  }

  /// Applies and saves. A font change loads the files first; a font or contrast change then rebuilds every
  /// mounted widget (TextStyles read AppFonts.family and colours read the palette in their build, without
  /// depending on anything that would tell them).
  Future<void> update(DisplayPrefs next) async {
    if (next == _prefs) return;
    final fontChanged = next.arabicFont != _prefs.arabicFont || next.latinFont != _prefs.latinFont;
    final contrastChanged = next.highContrast != _prefs.highContrast;
    _prefs = next;
    if (fontChanged) {
      await AppFonts.select(arabic: next.arabicFont, latin: next.latinFont);
    }
    notifyListeners();
    if (fontChanged || contrastChanged) rebuildAll();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(next.toJson()));
    } catch (e) {
      debugPrint('[DisplaySettings] save failed: $e');
    }
  }

  Future<void> reset() => update(const DisplayPrefs());

  /// Marks every mounted element dirty (state and navigation kept, like a hot reload) — TextStyles built with
  /// AppFonts.family deep in the tree do not depend on any InheritedWidget. Also used after a language switch.
  static void rebuildAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void visit(Element el) {
      el.markNeedsBuild();
      el.visitChildren(visit);
    }

    try {
      visit(root);
    } catch (e) {
      debugPrint('[DisplaySettings] rebuild failed: $e');
    }
  }
}
