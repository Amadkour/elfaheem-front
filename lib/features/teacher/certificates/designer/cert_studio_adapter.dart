// features/teacher/certificates/designer/cert_studio_adapter.dart
//
// The certificate designer's bridge to the studio engine (lib/design/studio/studio.dart, "How the two studios
// plug in"). One adapter per LANGUAGE: the Arabic and the English design each have their own StudioController, so
// selection, zoom and undo history never cross from one language to the other.
//
//   item      = CertField, rect in logical page units (1000 × 707 / 707 × 1000, or the design's page size)
//   text      h = 0 is stored (height follows the text): readItems reports the renderer's box height
//             (cert_text_layout.dart: 2 × padding + lines × advance), writeRects writes x, y, w and keeps h = 0;
//             resize horizontal
//   line      rect height = its thickness; writeRects never changes the thickness; resize horizontal
//   logo / signature  w × h box, resize keeping the aspect unless the person unlocked it (`aspect_lock: false`)
//   photo / qr        squares of side w, resize keeping the aspect
//   every kind        `locked` → a locked item, `rotation` → the item's rotation
//   snapshot  the language's CertLangSlice (fields + that language's page settings) — immutable
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_education_app/design/studio/studio.dart';

import 'cert_text_layout.dart';
import 'certificate_design_models.dart';

final RegExp certArabicChars = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

/// The line height of an EMPTY text box (× the font size): a box with no text still has a line to select.
const double kCertLineHeight = 1.15;

/// The text a field shows in [arabic] / English, as the renderer picks it: Arabic uses `text_ar` when it is set.
String certFieldRawText(CertField f, {required bool arabic}) =>
    (arabic && (f.textAr ?? '').isNotEmpty) ? f.textAr! : (f.text ?? '');

/// The cert-font TextStyle of a field at [scale] screen pixels per unit (canvas and measurement share it).
TextStyle certTextStyle(CertField f, {double scale = 1, double? size, Color? color, double opacityFactor = 1}) {
  final cf = certFont(f.font);
  return TextStyle(
    fontFamily: cf.family,
    fontFamilyFallback: cf.arabicFallback == null ? null : [cf.arabicFallback!], // same as the server
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
    fontSize: (size ?? f.size) * scale,
    color: (color ?? hexToColor(f.color)).withValues(alpha: (f.opacity * opacityFactor).clamp(0.0, 1.0)),
    letterSpacing: f.letterSpacing * scale,
    height: kCertLineHeight,
  );
}

/// The renderer's layout of a text field with the sample values (null when it has no text).
CertTextLayout? certFieldLayout(CertField f, {required bool arabic, double? width, Map<String, String> samples = const {}}) {
  final text = resolveSample(certFieldRawText(f, arabic: arabic), arabic: arabic, custom: samples);
  return certTextLayout(width == null ? f : f.copyWith(w: width), text);
}

/// Height (page units) of a text field's box: what the renderer draws (2 × padding + lines × advance); an empty
/// box keeps one line of the font size so it can still be selected.
double certTextHeight(CertField f, {required bool arabic, double? width, Map<String, String> samples = const {}}) {
  final l = certFieldLayout(f, arabic: arabic, width: width, samples: samples);
  return l?.boxHeight ?? f.size * kCertLineHeight + 2 * f.padding.clamp(0, 100);
}

/// The page rect of a field (see the header for each kind).
Rect certFieldRect(CertField f, {required bool arabic, Map<String, String> samples = const {}}) {
  switch (f.kind) {
    case CertFieldKind.text:
      return Rect.fromLTWH(f.x, f.y, f.w, certTextHeight(f, arabic: arabic, samples: samples));
    case CertFieldKind.line:
      return Rect.fromLTWH(f.x, f.y, f.w, math.max(f.h, 1));
    case CertFieldKind.photo:
    case CertFieldKind.qr:
      return Rect.fromLTWH(f.x, f.y, f.w, f.w);
    case CertFieldKind.logo:
    case CertFieldKind.signature:
      return Rect.fromLTWH(f.x, f.y, f.w, f.h > 0 ? f.h : f.w * 0.5);
  }
}

StudioResize certResizeOf(CertFieldKind k) => switch (k) {
      CertFieldKind.text || CertFieldKind.line => StudioResize.horizontal,
      _ => StudioResize.aspect,
    };

/// How [f] resizes: per kind, and a logo / signature freely once the person turned its aspect lock off.
StudioResize certResizeOfField(CertField f) =>
    f.isImage && !f.keepsAspect ? StudioResize.free : certResizeOf(f.kind);

Size certMinSizeOf(CertFieldKind k) => switch (k) {
      CertFieldKind.text => const Size(40, 1),
      CertFieldKind.line => const Size(20, 1),
      CertFieldKind.qr => const Size(40, 40),
      _ => const Size(16, 16),
    };

double _r1(double v) => (v * 10).roundToDouble() / 10;

/// Writes a page rect back into a field, by kind (text keeps h = 0, a line keeps its thickness).
CertField certApplyRect(CertField f, Rect r) {
  final x = _r1(r.left), y = _r1(r.top), w = _r1(r.width);
  switch (f.kind) {
    case CertFieldKind.text:
      return f.copyWith(x: x, y: y, w: w, h: 0);
    case CertFieldKind.line:
      return f.copyWith(x: x, y: y, w: w);
    case CertFieldKind.photo:
      return f.copyWith(x: x, y: y, w: w, h: w);
    case CertFieldKind.qr:
      return f.copyWith(x: x, y: y, w: w);
    case CertFieldKind.logo:
    case CertFieldKind.signature:
      return f.copyWith(x: x, y: y, w: w, h: _r1(r.height));
  }
}

int _idSeq = 0;

/// A fresh field id (unique in a layout; the server only needs uniqueness per layout).
String certNewFieldId() => 'f${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++).toRadixString(36)}';

/// The canvas's in-place editor over text field [f] at [scale] screen pixels per unit: the field's font, size (the
/// laid-out one, after any shrink to fit), colour, alignment, direction, fill and padding. Shift+Enter adds a line.
StudioInlineStyle certInlineStyle(CertField f, {required bool arabic, required double scale, Map<String, String> samples = const {}}) {
  final l = certFieldLayout(f, arabic: arabic, samples: samples);
  final raw = certFieldRawText(f, arabic: arabic);
  final rtl = f.direction == 'rtl' || (f.direction == 'auto' && (certArabicChars.hasMatch(raw) || (raw.isEmpty && arabic)));
  final base = certTextStyle(f, scale: scale, size: l?.fontSize ?? f.size, opacityFactor: 1);
  return StudioInlineStyle(
    style: base.copyWith(
      color: hexToColor(f.color),
      fontWeight: f.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: f.italic ? FontStyle.italic : FontStyle.normal,
    ),
    textAlign: f.align == 'left' ? TextAlign.left : (f.align == 'right' ? TextAlign.right : TextAlign.center),
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    multiline: true,
    padding: EdgeInsets.all(f.padding.clamp(0, 100) * scale),
    background: f.bgColor == null ? null : hexToColor(f.bgColor!).withValues(alpha: f.bgOpacity.clamp(0.0, 1.0)),
  );
}

class CertStudioAdapter implements StudioAdapter<CertField>, StudioLockAdapter {
  CertStudioAdapter({
    required this.lang,
    required this.read,
    required this.write,
    this.readOnly = false,
    this.samples = const {},
  });

  /// 'ar' | 'en'.
  final String lang;

  /// The language's current stored settings, and how to store new ones (the provider).
  final CertLangSlice Function() read;
  final void Function(CertLangSlice slice) write;

  /// A design I may not edit: items are locked and every write is ignored.
  bool readOnly;

  /// Sample values of custom placeholders (they change a text's measured height).
  Map<String, String> samples;

  bool get arabic => lang == 'ar';

  List<CertField> get _fields => read().fields;

  @override
  List<StudioItem<CertField>> readItems() => [
        for (final f in _fields)
          if (f.id != kCertBlankFieldId)
            StudioItem<CertField>(
              id: f.id,
              rect: certFieldRect(f, arabic: arabic, samples: samples),
              payload: f,
              visible: f.visible,
              locked: readOnly || f.locked,
              rotation: f.rotation,
              resize: certResizeOfField(f),
              minSize: certMinSizeOf(f.kind),
            ),
      ];

  void _setFields(List<CertField> fields) {
    if (readOnly) return;
    write(read().withFields(fields));
  }

  @override
  void writeRects(Map<String, Rect> rects) {
    if (rects.isEmpty) return;
    _setFields([
      for (final f in _fields) rects[f.id] == null ? f : certApplyRect(f, rects[f.id]!),
    ]);
  }

  /// Appends [items] up to [kCertMaxFields] per language (the server refuses a save with more, 400): a duplicate of
  /// a big selection near the limit adds only the copies that fit.
  @override
  void addItems(List<StudioItem<CertField>> items) {
    if (items.isEmpty) return;
    final room = kCertMaxFields - _fields.where((f) => f.id != kCertBlankFieldId).length;
    if (room <= 0) return;
    _setFields([
      ..._fields,
      for (final i in items.take(room)) certApplyRect(i.payload.copyWith(id: i.id), i.rect),
    ]);
  }

  @override
  void removeItems(Set<String> ids) => _setFields(_fields.where((f) => !ids.contains(f.id)).toList());

  @override
  void reorder(List<String> ids) {
    final byId = {for (final f in _fields) f.id: f};
    final next = [for (final id in ids) if (byId[id] != null) byId[id]!];
    for (final f in _fields) {
      if (!ids.contains(f.id)) next.add(f);
    }
    _setFields(next);
  }

  @override
  StudioItem<CertField> cloneItem(StudioItem<CertField> item) {
    final id = certNewFieldId();
    // a copy is never locked (the engine unlocks it too) and drops the layer name's uniqueness worries
    return item.copyWith(id: id, payload: item.payload.copyWithNewId(id).copyWith(locked: false));
  }

  @override
  bool get canLock => !readOnly;

  @override
  void setLocked(Set<String> ids, bool locked) =>
      _setFields([for (final f in _fields) ids.contains(f.id) ? f.copyWith(locked: locked) : f]);

  @override
  Object snapshot() => read();

  @override
  void restore(Object snapshot) {
    if (snapshot is CertLangSlice) write(snapshot);
  }
}
