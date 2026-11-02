// lib/design/studio/studio.dart
//
// THE visual design engine: one canvas, one controller, one toolbar and one set of property controls for every
// "place things on a page" studio (the certificate designer, the Export Hub designer, later others). Import this
// file only:
//
//     import 'package:flutter_education_app/design/studio/studio.dart';
//
//   studio_model.dart        StudioPage(width, height, unitPx) · StudioItem<P>(id, rect, payload, locked, visible,
//                            resize, minSize) · StudioHandle · StudioGuide · StudioAlign · StudioBorder ·
//                            StudioAdapter<P> · StudioLockAdapter (optional) · StudioInlineStyle ·
//                            StudioMemoryAdapter<P>
//   studio_controller.dart   StudioController<P> (pure, ChangeNotifier): selection, gestures with snapping, align /
//                            distribute, nudge, duplicate, delete, z order, copy / cut / paste, lock, the in-place
//                            text edit (startTextEdit / commitText), undo / redo, zoom
//   studio_canvas.dart       StudioCanvas<P>(controller, itemBuilder, inlineText, inlineStyle, onInlineCommit,
//                            contextMenu) · StudioBorderBox · StudioCanvas.scaleOf
//   studio_dock.dart         StudioDockPanel: the phone's non-modal properties panel under the page
//   studio_toolbar.dart      StudioToolbar(controller, leading, trailing) · StudioToolButton
//   studio_props.dart        property-panel primitives (section, font, stepper, weight, colour, align, border,
//                            opacity)
//   studio_small_screen.dart StudioSmallScreenNotice · StudioSmallScreenGate
//
// ── The host adapter contract ────────────────────────────────────────────────────────────────────────────────
// The engine never owns the design. A studio keeps its own model and implements [StudioAdapter]:
//   readItems()        its elements as StudioItems, bottom first (list order = z order), rects in PAGE units,
//                      physical (x from the left in Arabic too); payload = the element itself
//   writeRects(map)    store new positions / sizes
//   addItems / removeItems / reorder(ids)       structure
//   cloneItem(item)    a copy with a new id (duplicate)
//   snapshot() / restore(s)                     the whole design as an opaque value, for undo / redo
// Everything else the studio changes (text, font, colour, …) goes through `controller.record(label, () => …)`,
// so it is undoable; `controller.refresh()` after replacing the design from outside (load, server answer), and
// `clearHistory()` after loading another design.
//
// ── How the two studios plug in ──────────────────────────────────────────────────────────────────────────────
// Certificate designer (certificate_designer_*): StudioPage(d.logicalW, d.logicalH) — 1000 × 707 or 707 × 1000,
//   unitPx 1. Item = CertField: rect (x, y, w, h); a text field stores h = 0 (height follows the text), so the
//   adapter reports an estimated height (size × lines × line height) and writeRects keeps h = 0 for text,
//   resize = horizontal for text and line fields, aspect for logo / signature / photo. snapshot = the immutable
//   CertDesign itself. The provider's moveField / resizeField / centre snap are replaced by the controller
//   (page-centre snap is one of its guides); bringForward / sendBackward / duplicate / delete map 1:1;
//   field.visible → item.visible.
// Export Hub designer (export_hub/export_designer.dart): StudioPage(content width mm, content height mm,
//   unitPx: 96 / 25.4) from ExportPage. Blocks are FRACTIONS of the content box with x from the PHYSICAL left
//   (like the PDF / Word writers): readItems maps x_mm = x × width, writeRects maps back. grid =
//   Size(width × .02, height × .02) keeps the 2 % grid; minSize per kind from ExportBlock.clamp (w .06, h .02,
//   line .002 → mm); resize = aspect for logo / signature, horizontal for line, free otherwise. snapshot =
//   design.toJson(), restore = ExportDesign.fromJson. The page's own 40-step `_history` becomes the
//   controller's history. The margins, header / footer, frame and watermark are drawn around the page through
//   StudioCanvas(paperInsets:, paperBuilder:) (ExportStudioAdapter in export_designer.dart).
library;

export 'studio_canvas.dart';
export 'studio_controller.dart';
export 'studio_dock.dart';
export 'studio_model.dart';
export 'studio_props.dart';
export 'studio_small_screen.dart';
export 'studio_toolbar.dart';
