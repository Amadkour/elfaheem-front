// features/teacher/certificates/designer/certificate_designer_provider.dart
//
// State + API for the certificate designer:
//   • create a design: AI-free "draft" from the app theme + logo + signature, an uploaded template
//     image, or a blank page
//   • edit: add / delete / duplicate / move / resize / reorder fields, per-field font, size, colour
//   • signature upload with automatic background removal (server side)
//   • exact server preview, save, and "use for this course certificate"
//
// Only ApiClient.get / post / delete are used (images travel as base64 JSON), so this works with
// the existing ApiClient unchanged.

import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import 'certificate_design_models.dart';

class CertificateDesignerProvider extends BaseProvider {
  final ApiClient _api;

  CertificateDesignerProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── editing state ────────────────────────────────────────────────────────

  CertDesign? design;
  String? selectedId;
  bool dirty = false;
  bool saving = false;
  bool busy = false; // an upload / generation is running
  bool failed = false; // last action failed (screen shows a generic message)

  /// Language used to show text on the canvas ('en' | 'ar'): switches between text / text_ar.
  bool editArabic = false;

  // New-design wizard (before a design exists)
  String wizardOrientation = 'landscape';
  String wizardStyle = 'classic'; // classic | modern | dark
  String? pendingLogoUrl;
  String? pendingSignatureUrl;

  // Signature re-processing (ink colour / strength) needs the original picture
  Uint8List? _lastSignatureBytes;
  String? signatureInk; // null = keep the original ink colour
  double signatureStrength = 0.5;

  Uint8List? previewBytes;
  bool previewing = false;

  void setWizardOrientation(String o) {
    wizardOrientation = o;
    notifyListeners();
  }

  void setWizardStyle(String s) {
    wizardStyle = s;
    notifyListeners();
  }

  CertField? get selected {
    final d = design;
    if (d == null || selectedId == null) return null;
    for (final f in d.fields) {
      if (f.id == selectedId) return f;
    }
    return null;
  }

  bool get hasSignatureImage => (design?.signatureUrl ?? pendingSignatureUrl) != null;

  void _touch({bool markDirty = true}) {
    if (markDirty) dirty = true;
    notifyListeners();
  }

  // ── load ─────────────────────────────────────────────────────────────────

  /// The open design is read-only for me (an organization's / someone else's design): make MY editable copy —
  /// positions, alignment, fonts, sizes, colours and all — and attach it to [certificateId] when given.
  Future<bool> customizeCopy({int? certificateId}) async {
    final id = design?.id;
    if (id == null) return false;
    final q = certificateId == null ? '' : '?certificate_id=$certificateId';
    final r = await run(() => _api.post('/api/v1/certificate-designs/$id/duplicate$q'));
    if (r is Map<String, dynamic>) {
      design = CertDesign.fromJson(r);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> loadDesign(int designId) async {
    final r = await run(() => _api.get('/api/v1/certificate-designs/$designId'));
    if (r is Map<String, dynamic>) {
      design = CertDesign.fromJson(r);
      selectedId = null;
      dirty = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// The design attached to a course certificate (null → it still uses the default template).
  Future<bool> loadForCertificate(int certificateId) async {
    final r = await run(() => _api.get('/api/v1/certificates/$certificateId/design'));
    if (r is Map<String, dynamic>) {
      design = CertDesign.fromJson(r);
      selectedId = null;
      dirty = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── create ───────────────────────────────────────────────────────────────

  /// Draft from the current app theme colour (+ dark mode), logo and signature.
  Future<bool> createDraft({
    required String themeColorHex,
    required bool dark,
    int? orgId,
    String? name,
  }) async {
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/draft', body: {
          'org_id': orgId,
          'name': name,
          'orientation': wizardOrientation,
          'style': wizardStyle,
          'theme_color': themeColorHex,
          'dark': dark,
          'logo_url': pendingLogoUrl,
          'signature_url': pendingSignatureUrl,
        }));
    busy = false;
    if (r is Map<String, dynamic>) {
      design = CertDesign.fromJson(r);
      selectedId = null;
      dirty = false;
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  /// A page with no fields (the teacher builds everything).
  Future<bool> createBlank({int? orgId, String? name}) async {
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs', body: {
          'org_id': orgId,
          'name': name ?? 'Certificate design',
          'orientation': wizardOrientation,
          'signature_url': pendingSignatureUrl,
          'logo_url': pendingLogoUrl,
          'theme': {'style': wizardStyle},
          'fields': <dynamic>[],
        }));
    busy = false;
    if (r is Map<String, dynamic>) {
      design = CertDesign.fromJson(r);
      dirty = false;
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  /// "Insert template": the teacher's own certificate image becomes the background; the standard
  /// fields are laid on top of it and can be moved / deleted freely.
  Future<bool> createFromTemplateImage(Uint8List bytes, {int? orgId, String? name}) async {
    busy = true;
    failed = false;
    notifyListeners();
    final up = await run(() => _api.post(
          '/api/v1/certificate-designs/background?orientation=$wizardOrientation',
          body: {'image_base64': base64Encode(bytes)},
        ));
    if (up is! Map<String, dynamic>) {
      busy = false;
      failed = true;
      notifyListeners();
      return false;
    }
    final r = await run(() => _api.post('/api/v1/certificate-designs', body: {
          'org_id': orgId,
          'name': name ?? 'Certificate design',
          'orientation': wizardOrientation,
          'background_url': up['url'],
          'background_kind': 'upload',
          'signature_url': pendingSignatureUrl,
          'logo_url': pendingLogoUrl,
          'theme': {'style': wizardStyle},
          'fields': <dynamic>[],
        }));
    busy = false;
    if (r is Map<String, dynamic>) {
      design = CertDesign.fromJson(r);
      dirty = false;
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  // ── uploads ──────────────────────────────────────────────────────────────

  /// Signature photo → transparent PNG. Works before a design exists (wizard) and while editing.
  Future<bool> uploadSignature(Uint8List bytes, {String? inkColor, double? strength}) async {
    _lastSignatureBytes = bytes;
    signatureInk = inkColor;
    if (strength != null) signatureStrength = strength;
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/signature', body: {
          'image_base64': base64Encode(bytes),
          'ink_color': inkColor,
          'strength': signatureStrength,
        }));
    busy = false;
    if (r is Map<String, dynamic>) {
      final url = r['url'] as String;
      if (design != null) {
        design = design!.copyWith(signatureUrl: url);
        _touch();
      } else {
        pendingSignatureUrl = url;
        notifyListeners();
      }
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  /// Re-run the background removal on the last picked photo (ink colour / strength changed).
  Future<bool> reprocessSignature({String? inkColor, bool keepInk = false, double? strength}) {
    final bytes = _lastSignatureBytes;
    if (bytes == null) return Future.value(false);
    return uploadSignature(bytes, inkColor: keepInk ? signatureInk : inkColor, strength: strength);
  }

  bool get canReprocessSignature => _lastSignatureBytes != null;

  Future<bool> uploadLogo(Uint8List bytes) async {
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/logo',
        body: {'image_base64': base64Encode(bytes)}));
    busy = false;
    if (r is Map<String, dynamic>) {
      final url = r['url'] as String;
      if (design != null) {
        design = design!.copyWith(logoUrl: url);
        _touch();
      } else {
        pendingLogoUrl = url;
        notifyListeners();
      }
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  Future<bool> uploadBackground(Uint8List bytes) async {
    final d = design;
    if (d == null) return false;
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post(
          '/api/v1/certificate-designs/background?orientation=${d.orientation}',
          body: {'image_base64': base64Encode(bytes)},
        ));
    busy = false;
    if (r is Map<String, dynamic>) {
      design = design!.copyWith(backgroundUrl: r['url'] as String, backgroundKind: 'upload');
      _touch();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  void removeBackground() {
    if (design == null) return;
    design = design!.copyWith(clearBackground: true);
    _touch();
  }

  void removeSignatureImage() {
    if (design == null) {
      pendingSignatureUrl = null;
      notifyListeners();
      return;
    }
    design = design!.copyWith(clearSignature: true);
    _touch();
  }

  void removeLogoImage() {
    if (design == null) {
      pendingLogoUrl = null;
      notifyListeners();
      return;
    }
    design = design!.copyWith(clearLogo: true);
    _touch();
  }

  /// Regenerate the decorative background from the theme (keeps all fields in place).
  Future<bool> regenerateBackground({
    required String themeColorHex,
    required bool dark,
    required String style,
    bool resetFields = false,
  }) async {
    final d = design;
    if (d == null) return false;
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/draft', body: {
          'design_id': d.id,
          'org_id': d.orgId,
          'orientation': d.orientation,
          'style': style,
          'theme_color': themeColorHex,
          'dark': dark,
          'logo_url': d.logoUrl,
          'signature_url': d.signatureUrl,
          'reset_fields': resetFields,
        }));
    busy = false;
    if (r is Map<String, dynamic>) {
      final fresh = CertDesign.fromJson(r);
      design = d.copyWith(
        backgroundUrl: fresh.backgroundUrl,
        backgroundKind: 'draft',
        theme: fresh.theme,
        fields: resetFields ? fresh.fields : null,
      );
      _touch();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  // ── page settings ────────────────────────────────────────────────────────

  void rename(String name) {
    if (design == null || name.trim().isEmpty) return;
    design = design!.copyWith(name: name.trim());
    _touch();
  }

  /// Portrait ⇄ landscape: every field keeps its relative place on the page.
  Future<void> setOrientation(String orientation, {String? themeColorHex, bool dark = false}) async {
    final d = design;
    if (d == null || d.orientation == orientation) return;
    final newW = orientation == 'portrait' ? kLogicalShort : kLogicalLong;
    final newH = orientation == 'portrait' ? kLogicalLong : kLogicalShort;
    final sx = newW / d.logicalW, sy = newH / d.logicalH;
    final moved = d.fields
        .map((f) => f.copyWith(
              x: f.x * sx,
              w: f.w * sx,
              y: f.y * sy,
              h: f.isImage ? f.h * (sx < sy ? sx : sy) : f.h,
            ))
        .toList();
    design = d.copyWith(orientation: orientation, fields: moved);
    _touch();
    // A generated background has to be redrawn for the new page shape.
    if (d.backgroundKind == 'draft') {
      await regenerateBackground(
        themeColorHex: (d.theme['color'] as String?) ?? themeColorHex ?? '#C49A47',
        dark: (d.theme['dark'] as bool?) ?? dark,
        style: (d.theme['style'] as String?) ?? 'classic',
      );
    }
  }

  // ── fields ───────────────────────────────────────────────────────────────

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void setEditArabic(bool v) {
    editArabic = v;
    notifyListeners();
  }

  String _newId() => 'f${DateTime.now().microsecondsSinceEpoch}';

  String get _defaultInk => (design?.theme['dark'] == true) ? '#F5F1E6' : '#1C1C24';

  void _add(CertField f) {
    final d = design;
    if (d == null) return;
    design = d.copyWith(fields: [...d.fields, f]);
    selectedId = f.id;
    _touch();
  }

  void addText({String text = 'New text'}) {
    final d = design;
    if (d == null) return;
    const w = 320.0;
    _add(CertField(
      id: _newId(),
      text: text,
      x: (d.logicalW - w) / 2,
      y: d.logicalH * 0.45,
      w: w,
      size: 28,
      color: _defaultInk,
      font: 'tajawal',
    ));
  }

  /// Adds a field that prints a dynamic value, e.g. key = "student_name".
  void addPlaceholder(String key) {
    final p = kCertPlaceholders.firstWhere((e) => e.key == key);
    final d = design;
    if (d == null) return;
    const w = 420.0;
    _add(CertField(
      id: _newId(),
      text: '{${p.key}}',
      x: (d.logicalW - w) / 2,
      y: d.logicalH * 0.45,
      w: w,
      size: 32,
      color: _defaultInk,
      font: 'tajawal_bold',
      maxLines: 1,
    ));
  }

  void addSignature() {
    final d = design;
    if (d == null) return;
    const w = 220.0, h = 80.0;
    _add(CertField(
      id: _newId(),
      kind: CertFieldKind.signature,
      x: d.logicalW * 0.62,
      y: d.logicalH * 0.72,
      w: w,
      h: h,
      shrink: false,
    ));
  }

  void addLogo() {
    final d = design;
    if (d == null) return;
    const s = 80.0;
    _add(CertField(
      id: _newId(),
      kind: CertFieldKind.logo,
      x: (d.logicalW - s) / 2,
      y: d.logicalH * 0.06,
      w: s,
      h: s,
      shrink: false,
    ));
  }

  /// The student's profile photo (circle by default) — filled per student when the certificate is issued.
  void addPhoto() {
    final d = design;
    if (d == null) return;
    const s = 130.0;
    _add(CertField(id: _newId(), kind: CertFieldKind.photo, x: d.logicalW * 0.08, y: (d.logicalH - s) / 2, w: s, h: s, shrink: false));
  }

  void addLine() {
    final d = design;
    if (d == null) return;
    const w = 240.0;
    _add(CertField(
      id: _newId(),
      kind: CertFieldKind.line,
      x: (d.logicalW - w) / 2,
      y: d.logicalH * 0.5,
      w: w,
      h: 2,
      color: _defaultInk,
      shrink: false,
    ));
  }

  void updateField(String id, CertField Function(CertField f) change) {
    final d = design;
    if (d == null) return;
    design = d.copyWith(fields: [for (final f in d.fields) f.id == id ? change(f) : f]);
    _touch();
  }

  /// Drag. (dx, dy) are LOGICAL units. Snaps the box centre to the page centre.
  void moveField(String id, double dx, double dy, {double snap = 6}) {
    final d = design;
    if (d == null) return;
    updateField(id, (f) {
      var nx = f.x + dx;
      final ny = f.y + dy;
      final centre = (d.logicalW - f.w) / 2;
      if ((nx - centre).abs() < snap) nx = centre;
      return f.copyWith(x: nx, y: ny);
    });
  }

  void resizeField(String id, double dw, double dh) {
    updateField(id, (f) {
      final nw = (f.w + dw).clamp(20.0, 1200.0);
      final nh = f.isImage ? (f.h + dh).clamp(10.0, 800.0) : f.h;
      return f.copyWith(w: nw, h: nh);
    });
  }

  void centerHorizontally(String id) {
    final d = design;
    if (d == null) return;
    updateField(id, (f) => f.copyWith(x: (d.logicalW - f.w) / 2));
  }

  void removeField(String id) {
    final d = design;
    if (d == null) return;
    design = d.copyWith(fields: d.fields.where((f) => f.id != id).toList());
    if (selectedId == id) selectedId = null;
    _touch();
  }

  void duplicateField(String id) {
    final d = design;
    if (d == null) return;
    final src = d.fields.firstWhere((f) => f.id == id);
    final copy = src.copyWithNewId(_newId()).copyWith(x: src.x + 16, y: src.y + 16);
    _add(copy);
  }

  /// Layers panel: drag to rearrange (later in the list = drawn on top).
  void reorder(int oldIndex, int newIndex) {
    final d = design;
    if (d == null) return;
    final list = [...d.fields];
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    design = d.copyWith(fields: list);
    _touch();
  }

  void bringForward(String id) => _step(id, 1);
  void sendBackward(String id) => _step(id, -1);

  void _step(String id, int delta) {
    final d = design;
    if (d == null) return;
    final i = d.fields.indexWhere((f) => f.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= d.fields.length) return;
    final list = [...d.fields];
    list.insert(j, list.removeAt(i));
    design = d.copyWith(fields: list);
    _touch();
  }

  // ── preview / save / use ─────────────────────────────────────────────────

  /// Exact server render (real fonts, real Arabic shaping) with sample data and unsaved edits.
  Future<bool> preview({required bool arabic}) async {
    final d = design;
    if (d == null) return false;
    previewing = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/${d.id}/preview', body: {
          'lang': arabic ? 'ar' : 'en',
          'orientation': d.orientation,
          'background_url': d.backgroundUrl ?? '',
          'signature_url': d.signatureUrl ?? '',
          'logo_url': d.logoUrl ?? '',
          'fields': d.fields.map((f) => f.toJson()).toList(),
        }));
    previewing = false;
    if (r is Map<String, dynamic> && r['image_base64'] is String) {
      previewBytes = base64Decode(r['image_base64'] as String);
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  Future<bool> save() async {
    final d = design;
    if (d == null) return false;
    saving = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/${d.id}/save', body: {
          'name': d.name,
          'orientation': d.orientation,
          'theme': d.theme,
          'fields': d.fields.map((f) => f.toJson()).toList(),
          if (d.backgroundUrl != null) ...{
            'background_url': d.backgroundUrl,
            'background_kind': d.backgroundKind,
          } else
            'clear_background': true,
          if (d.signatureUrl != null) 'signature_url': d.signatureUrl else 'clear_signature': true,
          if (d.logoUrl != null) 'logo_url': d.logoUrl else 'clear_logo': true,
        }));
    saving = false;
    if (r is Map<String, dynamic>) {
      final saved = CertDesign.fromJson(r);
      design = saved.copyWith(); // server copy is the source of truth after saving
      dirty = false;
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  /// Make a course certificate render with this design (all later issuances use it).
  Future<bool> attachToCertificate(int certificateId, {int? designId}) async {
    final id = designId ?? design?.id;
    if (id == null) return false;
    final r = await run(() => _api.post('/api/v1/certificates/$certificateId/design',
        body: {'design_id': id}));
    return r is Map<String, dynamic>;
  }
}
