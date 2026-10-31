// features/teacher/certificates/designer/certificate_designer_provider.dart
//
// State + API for the certificate designer:
//   • create a design: AI-free "draft" from the app theme + logo + signature, an uploaded template
//     image, or a blank page
//   • TWO independent designs, Arabic and English (v2): each has its own layout, orientation, background, theme
//     and default logo / signature; English settings may follow the Arabic ones ("Same as Arabic") until the
//     teacher customizes them. `langs` = the languages certificates are issued in.
//   • editing runs on the studio engine (lib/design/studio/): one StudioController per language
//     ([studioFor]) over a [CertStudioAdapter], so selection, drag / resize with snap guides, align, nudge,
//     duplicate, delete, z order, zoom and undo / redo are the engine's, and an undo in one language never touches
//     the other. Property edits go through `controller.record` ([updateField] and the page setters).
//   • any number of logos and signatures (each with its own image `src`, a signature with name / title captions),
//     a verification QR, custom {placeholders} with preview samples
//   • signature upload with automatic background removal (server side, re-run with another ink / strength)
//   • exact server preview, save, and "use for this course certificate"
//
// Only ApiClient.get / post are used (images travel as base64 JSON), so this works with the existing ApiClient.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/design/studio/studio.dart';

import '../../../../config/app_config.dart' show Trans;
import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import 'cert_studio_adapter.dart';
import 'certificate_design_models.dart';

/// What the default ink of a new element is on a page of [dark] theme.
String certDefaultInk(bool dark) => dark ? '#F5F1E6' : '#1C1C24';

/// Builds the save body. [d] is the designer's design (English layout and orientation resolved).
///
/// Both languages are always sent in full, so a save can never move or change the language the teacher did not
/// edit: the server would otherwise re-derive an English design that still followed the Arabic one. English
/// settings that are null follow the Arabic design ("Same as Arabic") and are listed in `inherit_en`, which sets
/// them back to NULL on the server ("Reset to Arabic"; a no-op for a value that was already null).
Map<String, dynamic> buildCertSavePayload(CertDesign d) {
  List<Map<String, dynamic>> js(List<CertField> l) => [
        for (final f in l)
          if (f.id != kCertBlankFieldId) f.toJson(),
      ];
  final en = js(d.fieldsEn);
  final out = <String, dynamic>{
    'name': d.name,
    'orientation': d.orientation,
    'theme': d.theme,
    'langs': d.langs,
    'fields': js(d.fields),
    'fields_en': en.isEmpty ? [kCertBlankField.toJson()] : en,
    'orientation_en': (d.orientationEn ?? '').isNotEmpty ? d.orientationEn : d.orientation,
  };
  if (d.backgroundUrl != null) {
    out['background_url'] = d.backgroundUrl;
    out['background_kind'] = d.backgroundKind;
  } else {
    out['clear_background'] = true;
  }
  if (d.signatureUrl != null) {
    out['signature_url'] = d.signatureUrl;
  } else {
    out['clear_signature'] = true;
  }
  if (d.logoUrl != null) {
    out['logo_url'] = d.logoUrl;
  } else {
    out['clear_logo'] = true;
  }

  final inherit = <String>[];
  void img(String name, String key, String clearKey, String? v, {String? kindKey, String? kind}) {
    if (v == null) {
      inherit.add(name); // follows the Arabic design
    } else if (v.isEmpty) {
      out[clearKey] = true; // none in English
    } else {
      out[key] = v;
      if (kindKey != null) out[kindKey] = kind ?? 'upload';
    }
  }

  img('background', 'background_url_en', 'clear_background_en', d.backgroundUrlEn,
      kindKey: 'background_kind_en', kind: d.backgroundKindEn);
  img('logo', 'logo_url_en', 'clear_logo_en', d.logoUrlEn);
  img('signature', 'signature_url_en', 'clear_signature_en', d.signatureUrlEn);
  if (d.themeEn == null) {
    inherit.add('theme');
  } else {
    out['theme_en'] = d.themeEn;
  }
  if (inherit.isNotEmpty) out['inherit_en'] = inherit;
  return out;
}

/// The designer's working copy of a server design: the English layout is ALWAYS its own (a copy of the Arabic one
/// when the server has none yet — from then on the two are independent), the English orientation is explicit, and
/// the invisible marker of an empty English layout is removed.
CertDesign normalizeCertDesign(CertDesign d) {
  final raw = d.fieldsEn;
  final own = raw.where((f) => f.id != kCertBlankFieldId).toList();
  return d.copyWith(
    fieldsEn: raw.isEmpty ? [for (final f in d.fields) f.copyWith()] : own,
    orientationEn: (d.orientationEn ?? '').isNotEmpty ? d.orientationEn : d.orientation,
  );
}

/// Every field of [fields] rescaled from page [from] to page [to] (orientation switch), like the server does.
List<CertField> rescaleCertFields(List<CertField> fields, String from, String to) {
  double w(String o) => o == 'portrait' ? kLogicalShort : kLogicalLong;
  double h(String o) => o == 'portrait' ? kLogicalLong : kLogicalShort;
  final sx = w(to) / w(from), sy = h(to) / h(from);
  final m = sx < sy ? sx : sy;
  double r(double v) => (v * 10).roundToDouble() / 10;
  return [
    for (final f in fields)
      f.copyWith(
        x: r(f.x * sx),
        y: r(f.y * sy),
        w: r(f.w * (f.kind == CertFieldKind.qr ? m : sx)),
        h: f.isImage ? r(f.h * m) : (f.kind == CertFieldKind.photo ? r(f.w * sx) : f.h),
      ),
  ];
}

/// Sample values of the custom placeholders [fields] use (the preview's `variables`, at most 40).
Map<String, String> certPreviewVariables(List<CertField> fields, Map<String, String> samples) {
  final out = <String, String>{};
  for (final k in customPlaceholdersOf(fields)) {
    final v = samples[k]?.trim() ?? '';
    if (v.isNotEmpty && out.length < 40) out[k] = v;
  }
  return out;
}

class CertificateDesignerProvider extends BaseProvider {
  final ApiClient _api;

  CertificateDesignerProvider({ApiClient? api, String initialLang = 'ar'})
      : _api = api ?? ApiClient(),
        lang = initialLang == 'en' ? 'en' : 'ar';

  // ── editing state ────────────────────────────────────────────────────────

  /// The working copy (see [normalizeCertDesign]); null while the wizard is shown.
  CertDesign? design;

  /// The server copy as last loaded / saved.
  CertDesign? loaded;

  /// The language being edited: 'ar' | 'en'.
  String lang;

  bool dirty = false;

  /// Counts the edits (every change that makes the design dirty): [save] keeps edits made while it was in flight.
  int _edits = 0;

  void _markDirty() {
    dirty = true;
    _edits++;
  }

  bool saving = false;
  bool busy = false; // an upload / generation is running
  bool failed = false; // last action failed (screen shows a message)

  bool get editArabic => lang == 'ar';
  bool get canEdit => design?.canEdit ?? false;

  /// Sample values of custom placeholders, for the canvas and the server preview (not saved: the issuing flow
  /// supplies the real values).
  final Map<String, String> customSamples = {};

  // New-design wizard (before a design exists)
  String wizardOrientation = 'landscape';
  String wizardStyle = 'classic'; // classic | modern | dark
  String? pendingLogoUrl;
  String? pendingSignatureUrl;

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

  // ── studio controllers (one per language) ────────────────────────────────

  final Map<String, StudioController<CertField>> _studios = {};

  StudioPage _pageOf(String l) {
    final v = design!.view(l);
    return StudioPage(v.logicalW, v.logicalH);
  }

  /// The studio controller of language [l] (created on first use; needs a design).
  StudioController<CertField> studioFor(String l) => _studios[l] ??= StudioController<CertField>(
        adapter: CertStudioAdapter(
          lang: l,
          read: () => design!.slice(l),
          write: (s) => _writeSlice(l, s),
          readOnly: !canEdit,
          samples: customSamples,
        ),
        page: _pageOf(l),
      );

  /// The controller of the language being edited.
  StudioController<CertField> get studio => studioFor(lang);

  void _syncStudios({bool clearHistory = false}) {
    if (design == null) return;
    for (final e in _studios.entries) {
      final a = e.value.adapter as CertStudioAdapter;
      a.readOnly = !canEdit;
      e.value.page = _pageOf(e.key);
      e.value.refresh();
      if (clearHistory) e.value.clearHistory();
    }
  }

  void _writeSlice(String l, CertLangSlice s) {
    final d = design;
    if (d == null) return;
    design = d.withSlice(l, s);
    _markDirty();
    final st = _studios[l];
    if (st != null) {
      final p = _pageOf(l);
      if (p != st.page) st.page = p;
    }
    notifyListeners();
  }

  /// Runs a change of language [forLang] (default: the one being edited) as one undo step of its controller.
  void _edit(String label, VoidCallback change, {String? forLang, bool coalesce = false}) {
    if (design == null || !canEdit) return;
    studioFor(forLang ?? lang).record(label, change, coalesce: coalesce);
  }

  List<CertField> fieldsOf(String l) {
    final d = design;
    if (d == null) return const [];
    return (l == 'ar' ? d.fields : d.fieldsEn).where((f) => f.id != kCertBlankFieldId).toList();
  }

  void _setFields(String l, List<CertField> f) => _writeSlice(l, design!.slice(l).withFields(f));

  /// The language view being edited (orientation, background, theme, defaults resolved).
  CertLangView get view => design!.view(lang);

  CertField? get selected {
    if (design == null) return null;
    final s = studio.single;
    if (s == null) return null;
    for (final f in fieldsOf(lang)) {
      if (f.id == s.id) return f;
    }
    return null;
  }

  // ── load ─────────────────────────────────────────────────────────────────

  /// Takes a server design as the working copy (load, save answer, new design).
  void adopt(CertDesign d, {bool resetHistory = true}) {
    loaded = d;
    design = normalizeCertDesign(d);
    if (!design!.hasLang(lang)) lang = design!.langs.first;
    _syncStudios(clearHistory: resetHistory);
  }

  /// The open design is read-only for me (an organization's / someone else's design): make MY editable copy —
  /// positions, alignment, fonts, sizes, colours and all — and attach it to [certificateId] when given.
  Future<bool> customizeCopy({int? certificateId}) async {
    final id = design?.id;
    if (id == null) return false;
    final q = certificateId == null ? '' : '?certificate_id=$certificateId';
    final r = await run(() => _api.post('/api/v1/certificate-designs/$id/duplicate$q'));
    if (r is Map<String, dynamic>) {
      adopt(CertDesign.fromJson(r));
      dirty = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> loadDesign(int designId) async {
    final r = await run(() => _api.get('/api/v1/certificate-designs/$designId'));
    if (r is Map<String, dynamic>) {
      adopt(CertDesign.fromJson(r));
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
      adopt(CertDesign.fromJson(r));
      dirty = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── create ───────────────────────────────────────────────────────────────

  Future<bool> _create(Future<dynamic> Function() call) async {
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(call);
    busy = false;
    if (r is Map<String, dynamic>) {
      adopt(CertDesign.fromJson(r));
      dirty = false;
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  /// Draft from the current app theme colour (+ dark mode), logo and signature.
  Future<bool> createDraft({required String themeColorHex, required bool dark, int? orgId, String? name}) =>
      _create(() => _api.post('/api/v1/certificate-designs/draft', body: {
            'org_id': orgId,
            'name': name ?? 'certd_default_name'.tr,
            'orientation': wizardOrientation,
            'style': wizardStyle,
            'theme_color': themeColorHex,
            'dark': dark,
            'logo_url': pendingLogoUrl,
            'signature_url': pendingSignatureUrl,
          }));

  /// A page with no fields (the teacher builds everything).
  Future<bool> createBlank({int? orgId, String? name}) => _create(() => _api.post('/api/v1/certificate-designs', body: {
        'org_id': orgId,
        'name': name ?? 'certd_default_name'.tr,
        'orientation': wizardOrientation,
        'signature_url': pendingSignatureUrl,
        'logo_url': pendingLogoUrl,
        'theme': {'style': wizardStyle},
        'fields': <dynamic>[],
      }));

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
    return _create(() => _api.post('/api/v1/certificate-designs', body: {
          'org_id': orgId,
          'name': name ?? 'certd_default_name'.tr,
          'orientation': wizardOrientation,
          'background_url': up['url'],
          'background_kind': 'upload',
          'signature_url': pendingSignatureUrl,
          'logo_url': pendingLogoUrl,
          'theme': {'style': wizardStyle},
          'fields': <dynamic>[],
        }));
  }

  // ── uploads ──────────────────────────────────────────────────────────────

  // Signature re-processing (ink colour / strength) needs the original picture, per signature ("target").
  final Map<String, Uint8List> _sigBytes = {};
  final Map<String, String?> _sigInk = {};
  final Map<String, double> _sigStrength = {};

  /// Targets: 'pending' (the wizard), 'default:ar' / 'default:en' (a language's default signature),
  /// `field:<lang>:<id>` (one signature element).
  static String fieldTarget(String l, String id) => 'field:$l:$id';
  static String defaultTarget(String l) => 'default:$l';

  bool canReprocess(String target) => _sigBytes.containsKey(target);
  String? sigInk(String target) => _sigInk[target];
  double sigStrength(String target) => _sigStrength[target] ?? 0.5;

  Future<String?> _upload(String path, Map<String, dynamic> body) async {
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post(path, body: body));
    busy = false;
    if (r is Map<String, dynamic> && r['url'] is String) {
      notifyListeners();
      return r['url'] as String;
    }
    failed = true;
    notifyListeners();
    return null;
  }

  /// Signature photo → transparent PNG (background removed on the server). Returns the URL; [target] remembers
  /// the photo so another ink / strength can be applied later ([reprocessSignature]).
  Future<String?> uploadSignatureBytes(Uint8List bytes, {required String target, String? inkColor, double? strength}) {
    _sigBytes[target] = bytes;
    _sigInk[target] = inkColor;
    if (strength != null) _sigStrength[target] = strength;
    return _upload('/api/v1/certificate-designs/signature', {
      'image_base64': base64Encode(bytes),
      'ink_color': inkColor,
      'strength': sigStrength(target),
    });
  }

  Future<String?> uploadLogoBytes(Uint8List bytes) =>
      _upload('/api/v1/certificate-designs/logo', {'image_base64': base64Encode(bytes)});

  Future<String?> uploadBackgroundBytes(Uint8List bytes, {required String orientation}) =>
      _upload('/api/v1/certificate-designs/background?orientation=$orientation', {'image_base64': base64Encode(bytes)});

  /// Re-runs the background removal of [target]'s last photo with another ink / strength and puts the new image
  /// where the old one was.
  Future<bool> reprocessSignature(String target, {String? inkColor, bool keepInk = false, double? strength}) async {
    final bytes = _sigBytes[target];
    if (bytes == null) return false;
    final url = await uploadSignatureBytes(bytes,
        target: target, inkColor: keepInk ? _sigInk[target] : inkColor, strength: strength);
    if (url == null) return false;
    _applySignature(target, url);
    return true;
  }

  void _applySignature(String target, String url) {
    if (target == 'pending') {
      pendingSignatureUrl = url;
      notifyListeners();
    } else if (target.startsWith('default:')) {
      setDefaultSignature(target.substring(8), url);
    } else if (target.startsWith('field:')) {
      final parts = target.split(':');
      if (parts.length >= 3) {
        final l = parts[1], id = parts.sublist(2).join(':');
        _edit('image', () => _setFields(l, [for (final f in fieldsOf(l)) f.id == id ? f.copyWith(src: url) : f]),
            forLang: l);
      }
    }
  }

  /// Wizard: the signature every new design starts with.
  Future<bool> uploadSignature(Uint8List bytes) async {
    final url = await uploadSignatureBytes(bytes, target: 'pending');
    if (url == null) return false;
    pendingSignatureUrl = url;
    notifyListeners();
    return true;
  }

  /// Wizard: the logo every new design starts with.
  Future<bool> uploadLogo(Uint8List bytes) async {
    final url = await uploadLogoBytes(bytes);
    if (url == null) return false;
    pendingLogoUrl = url;
    notifyListeners();
    return true;
  }

  void removePendingLogo() {
    pendingLogoUrl = null;
    notifyListeners();
  }

  void removePendingSignature() {
    pendingSignatureUrl = null;
    _sigBytes.remove('pending');
    notifyListeners();
  }

  // ── page settings, per language ──────────────────────────────────────────

  void _page(String l, String label, CertLangSlice Function(CertLangSlice s) change, {bool coalesce = false}) =>
      _edit(label, () => _writeSlice(l, change(design!.slice(l))), forLang: l, coalesce: coalesce);

  void rename(String name) {
    if (design == null || name.trim().isEmpty || !canEdit) return;
    design = design!.copyWith(name: name.trim());
    _markDirty();
    notifyListeners();
  }

  /// The languages certificates are issued in (["ar"], ["en"] or both). The other language's design is kept.
  void setLangs(List<String> langs) {
    final d = design;
    if (d == null || !canEdit) return;
    final next = [for (final l in CertDesign.allLangs) if (langs.contains(l)) l];
    if (next.isEmpty) return;
    design = d.copyWith(langs: next);
    if (!next.contains(lang)) lang = next.first;
    _markDirty();
    notifyListeners();
  }

  void setLang(String l) {
    if (l == lang || (design != null && !design!.hasLang(l))) return;
    lang = l;
    notifyListeners();
  }

  /// The English theme's state: the same as Arabic only while it is unset.
  CertInherit get themeInheritEn {
    final d = design;
    return d == null ? CertInherit.same : certThemeInherit(d.themeEn, d.theme);
  }

  /// Whether language [l] holds anything the teacher made (elements, or English settings of its own) — turning
  /// it off then asks first.
  bool langHasContent(String l) {
    final d = design;
    if (d == null) return false;
    if (fieldsOf(l).isNotEmpty) return true;
    if (l == 'ar') return d.backgroundUrl != null || d.logoUrl != null || d.signatureUrl != null;
    return [d.backgroundUrlEn, d.logoUrlEn, d.signatureUrlEn].any((v) => v != null) || d.themeEn != null;
  }

  /// Portrait ⇄ landscape for language [l] only: its elements keep their relative places.
  Future<void> setOrientation(String l, String orientation) async {
    final d = design;
    if (d == null || !canEdit) return;
    final from = d.view(l).orientation;
    if (from == orientation) return;
    _page(l, 'orientation', (s) => s.copyWith(
          orientation: orientation,
          fields: rescaleCertFields(s.fields, from, orientation),
        ));
    // A generated background of that language has to be redrawn for the new page shape (an English one that
    // follows the Arabic background is left alone).
    final generated = l == 'ar' ? d.backgroundKind == 'draft' : (d.backgroundUrlEn ?? '').isNotEmpty && d.backgroundKindEn == 'draft';
    if (generated) {
      final t = d.view(l).theme;
      await regenerateBackground(
        lang: l,
        themeColorHex: (t['color'] as String?) ?? '#C49A47',
        dark: (t['dark'] as bool?) ?? false,
        style: (t['style'] as String?) ?? 'classic',
        resetFields: false,
      );
    }
  }

  /// Background of [l]: an uploaded image ([url]) or none (null). English: [inherit] follows the Arabic one.
  void setBackground(String l, String? url, {String kind = 'upload', bool inherit = false}) {
    if (l == 'ar') {
      _page(l, 'background', (s) => s.copyWith(backgroundUrl: url, backgroundKind: url == null ? 'none' : kind));
    } else {
      _page(l, 'background', (s) => inherit
          ? s.copyWith(backgroundUrl: null, backgroundKind: null)
          : s.copyWith(backgroundUrl: url ?? '', backgroundKind: url == null ? 'none' : kind));
    }
  }

  /// Default logo of [l] (used by logo boxes without their own image). English: [inherit] = same as Arabic,
  /// null = none.
  void setDefaultLogo(String l, String? url, {bool inherit = false}) => _page(
      l, 'logo', (s) => s.copyWith(logoUrl: l == 'ar' ? url : (inherit ? null : (url ?? ''))));

  void setDefaultSignature(String l, String? url, {bool inherit = false}) => _page(
      l, 'signature', (s) => s.copyWith(signatureUrl: l == 'ar' ? url : (inherit ? null : (url ?? ''))));

  /// Theme of [l] ({color, dark, style}). English: null = same as Arabic.
  void setTheme(String l, Map<String, dynamic>? theme, {bool coalesce = false}) =>
      _page(l, 'theme', (s) => s.copyWith(theme: l == 'ar' ? (theme ?? const <String, dynamic>{}) : theme),
          coalesce: coalesce);

  /// Regenerate the decorative background of language [lang] from its theme (`lang: "en"` writes only the English
  /// background / theme, and with [resetFields] the English layout; the Arabic design is not touched).
  Future<bool> regenerateBackground({
    required String themeColorHex,
    required bool dark,
    required String style,
    bool resetFields = false,
    String lang = 'ar',
  }) async {
    final d = design;
    if (d == null || !canEdit) return false;
    final v = d.view(lang);
    busy = true;
    failed = false;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/draft', body: {
          'design_id': d.id,
          'org_id': d.orgId,
          'lang': lang,
          'orientation': v.orientation,
          'style': style,
          'theme_color': themeColorHex,
          'dark': dark,
          'logo_url': v.logoUrl,
          'signature_url': v.signatureUrl,
          'reset_fields': resetFields,
        }));
    busy = false;
    if (r is Map<String, dynamic>) {
      final fresh = CertDesign.fromJson(r);
      if (lang == 'ar') {
        _page('ar', 'regenerate', (s) => s.copyWith(
              backgroundUrl: fresh.backgroundUrl,
              backgroundKind: 'draft',
              theme: fresh.theme,
              fields: resetFields ? fresh.fields : null,
            ));
      } else {
        final en = fresh.fieldsEn.where((f) => f.id != kCertBlankFieldId).toList();
        _page('en', 'regenerate', (s) => s.copyWith(
              backgroundUrl: fresh.backgroundUrlEn,
              backgroundKind: 'draft',
              theme: fresh.themeEn,
              orientation: (fresh.orientationEn ?? '').isNotEmpty ? fresh.orientationEn : s.orientation,
              fields: resetFields && en.isNotEmpty ? en : null,
            ));
      }
      notifyListeners();
      return true;
    }
    failed = true;
    notifyListeners();
    return false;
  }

  // ── elements ─────────────────────────────────────────────────────────────

  String get _ink => certDefaultInk(view.dark);

  /// Whether one more element fits in the language's layout (the server's limit).
  bool get canAddField => fieldsOf(lang).length < kCertMaxFields;

  CertField? _add(CertField f) {
    if (design == null || !canEdit || !canAddField) return null;
    final l = lang;
    _edit('add', () => _setFields(l, [...fieldsOf(l), f]));
    studio.select(f.id);
    return f;
  }

  CertField? addText() {
    final v = view;
    const w = 320.0;
    final ar = editArabic;
    return _add(CertField(
      id: certNewFieldId(),
      text: ar ? null : 'New text',
      textAr: ar ? 'نص جديد' : null,
      x: (v.logicalW - w) / 2,
      y: v.logicalH * 0.45,
      w: w,
      size: 28,
      color: _ink,
      font: ar ? 'tajawal' : 'playfair',
    ));
  }

  /// Adds a field that prints a dynamic value, e.g. key = "student_name" or a custom "grade".
  CertField? addPlaceholder(String key) {
    final v = view;
    const w = 420.0;
    final token = '{${normalizePlaceholderKey(key)}}';
    return _add(CertField(
      id: certNewFieldId(),
      text: token,
      textAr: editArabic ? token : null,
      x: (v.logicalW - w) / 2,
      y: v.logicalH * 0.45,
      w: w,
      size: 32,
      color: _ink,
      font: editArabic ? 'tajawal_bold' : 'playfair_bold',
      maxLines: 1,
    ));
  }

  /// Remembers a custom placeholder's preview sample ([key] already validated).
  void setCustomSample(String key, String sample) {
    final k = normalizePlaceholderKey(key);
    if (sample.trim().isEmpty) {
      customSamples.remove(k);
    } else {
      customSamples[k] = sample.trim();
    }
    _syncStudios();
    notifyListeners();
  }

  /// A logo box with its own image [src] (null = the language's default logo). Any number of them.
  CertField? addLogo({String? src}) {
    final v = view;
    final n = fieldsOf(lang).where((f) => f.kind == CertFieldKind.logo).length;
    const s = 90.0;
    return _add(CertField(
      id: certNewFieldId(),
      kind: CertFieldKind.logo,
      src: src,
      x: ((v.logicalW - s) / 2 + n * (s + 16)).clamp(0, v.logicalW - s).toDouble(),
      y: v.logicalH * 0.06,
      w: s,
      h: s,
      shrink: false,
    ));
  }

  /// A signature box with its own image [src] (null = the default signature) and its caption lines.
  CertField? addSignature({String? src, String? name, String? title}) {
    final v = view;
    final n = fieldsOf(lang).where((f) => f.kind == CertFieldKind.signature).length;
    const w = 220.0, h = 80.0;
    final x = editArabic ? v.logicalW * 0.1 + n * (w + 24) : v.logicalW * 0.9 - w - n * (w + 24);
    return _add(CertField(
      id: certNewFieldId(),
      kind: CertFieldKind.signature,
      src: src,
      sigName: name,
      sigTitle: title,
      x: x.clamp(0, v.logicalW - w).toDouble(),
      y: v.logicalH * 0.7,
      w: w,
      h: h,
      size: 20,
      color: _ink,
      font: editArabic ? 'tajawal_bold' : 'playfair',
      shrink: false,
    ));
  }

  /// The student's profile photo (circle by default) — filled per student when the certificate is issued.
  CertField? addPhoto() {
    final v = view;
    const s = 130.0;
    return _add(CertField(
        id: certNewFieldId(), kind: CertFieldKind.photo, x: v.logicalW * 0.08, y: (v.logicalH - s) / 2, w: s, h: s, shrink: false));
  }

  CertField? addLine() {
    final v = view;
    const w = 240.0;
    return _add(CertField(
      id: certNewFieldId(),
      kind: CertFieldKind.line,
      x: (v.logicalW - w) / 2,
      y: v.logicalH * 0.5,
      w: w,
      h: 2,
      color: _ink,
      shrink: false,
    ));
  }

  /// "Add logo": uploads [bytes] and adds a logo box showing it. Null when the upload failed.
  Future<CertField?> addLogoImage(Uint8List bytes) async {
    if (!canAddField) return null;
    final url = await uploadLogoBytes(bytes);
    return url == null ? null : addLogo(src: url);
  }

  /// "Add signature": uploads [bytes] (background removed on the server) and adds a signature box showing it; the
  /// photo is kept so its ink / strength can be tuned later. Null when the upload failed.
  Future<CertField?> addSignatureImage(Uint8List bytes) async {
    if (!canAddField) return null;
    const temp = 'new';
    final url = await uploadSignatureBytes(bytes, target: temp);
    if (url == null) return null;
    final f = addSignature(src: url);
    if (f != null) _retarget(temp, fieldTarget(lang, f.id));
    return f;
  }

  void _retarget(String from, String to) {
    final b = _sigBytes.remove(from);
    if (b == null) return;
    _sigBytes[to] = b;
    _sigInk[to] = _sigInk.remove(from);
    final s = _sigStrength.remove(from);
    if (s != null) _sigStrength[to] = s;
  }

  /// Gives element [id] (logo / signature) its own image from [bytes].
  Future<bool> replaceFieldImage(String id, Uint8List bytes) async {
    final l = lang;
    final f = fieldsOf(l).where((x) => x.id == id).firstOrNull;
    if (f == null) return false;
    final url = f.kind == CertFieldKind.signature
        ? await uploadSignatureBytes(bytes, target: fieldTarget(l, id))
        : await uploadLogoBytes(bytes);
    if (url == null) return false;
    _edit('image', () => _setFields(l, [for (final x in fieldsOf(l)) x.id == id ? x.copyWith(src: url) : x]), forLang: l);
    return true;
  }

  /// Element [id] shows the language's default logo / signature again.
  void useDefaultImage(String id) => updateField(id, (f) => f.copyWith(clearSrc: true), label: 'image', coalesce: false);

  /// Uploads a default (page-level) logo of [l] from [bytes].
  Future<bool> uploadDefaultLogo(String l, Uint8List bytes) async {
    final url = await uploadLogoBytes(bytes);
    if (url == null) return false;
    setDefaultLogo(l, url);
    return true;
  }

  /// Uploads a default (page-level) signature of [l] from [bytes] (background removed on the server).
  Future<bool> uploadDefaultSignature(String l, Uint8List bytes) async {
    final url = await uploadSignatureBytes(bytes, target: defaultTarget(l));
    if (url == null) return false;
    setDefaultSignature(l, url);
    return true;
  }

  /// Uploads a background image of [l] from [bytes] (cropped to that language's page shape on the server).
  Future<bool> uploadBackground(String l, Uint8List bytes) async {
    final d = design;
    if (d == null) return false;
    final url = await uploadBackgroundBytes(bytes, orientation: d.view(l).orientation);
    if (url == null) return false;
    setBackground(l, url);
    return true;
  }

  /// "Verification QR": each issued certificate's own verification link (or a custom text).
  CertField? addQr() {
    final v = view;
    const s = 110.0;
    return _add(CertField(
      id: certNewFieldId(),
      kind: CertFieldKind.qr,
      x: editArabic ? v.logicalW - s - 40 : 40,
      y: v.logicalH - s - 40,
      w: s,
      color: '#1C1C24',
      shrink: false,
    ));
  }

  /// One property change of element [id] in the language being edited, as an undo step ([coalesce]: a slider or
  /// typing within a second is one step).
  void updateField(String id, CertField Function(CertField f) change, {String label = 'edit', bool coalesce = true}) {
    final l = lang;
    _edit(label, () => _setFields(l, [for (final f in fieldsOf(l)) f.id == id ? change(f) : f]), coalesce: coalesce);
  }

  /// The element's wording in the language being edited. Arabic writes `text_ar` (an empty box clears both, so the
  /// English wording never shows through on the Arabic certificate); English writes `text`.
  void setText(String id, String value) => updateField(id, (f) {
        if (!editArabic) return f.copyWith(text: value);
        if (value.trim().isEmpty) return f.copyWith(clearText: true, clearTextAr: true);
        return f.copyWith(textAr: value);
      }, label: 'text');

  /// Layers panel: the element at [from] ends at [to] (later in the list = drawn on top).
  void reorderLayer(int from, int to) {
    final l = lang;
    final list = [...fieldsOf(l)];
    if (from < 0 || from >= list.length || from == to) return;
    list.insert(to.clamp(0, list.length - 1), list.removeAt(from));
    _edit('arrange', () => _setFields(l, list));
  }

  void removeField(String id) {
    final l = lang;
    _edit('delete', () => _setFields(l, fieldsOf(l).where((f) => f.id != id).toList()));
  }

  // ── preview / save / use ─────────────────────────────────────────────────

  /// Exact server render (real fonts, real Arabic shaping) of language [l] with sample data and unsaved edits.
  Future<bool> preview(String l) async {
    final d = design;
    if (d == null) return false;
    previewing = true;
    failed = false;
    notifyListeners();
    final v = d.view(l);
    final fields = fieldsOf(l);
    final vars = certPreviewVariables(fields, customSamples);
    final r = await run(() => _api.post('/api/v1/certificate-designs/${d.id}/preview', body: {
          'lang': l,
          'orientation': v.orientation,
          'background_url': v.backgroundUrl ?? '',
          'signature_url': v.signatureUrl ?? '',
          'logo_url': v.logoUrl ?? '',
          'theme': v.theme, // the language's unsaved theme (a dark page without a background)
          'fields': fields.map((f) => f.toJson()).toList(),
          if (vars.isNotEmpty) 'variables': vars,
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

  /// The body [save] sends (both languages, see [buildCertSavePayload]).
  Map<String, dynamic>? get savePayload => design == null ? null : buildCertSavePayload(design!);

  Future<bool> save() async {
    final d = design;
    final body = savePayload;
    if (d == null || body == null) return false;
    saving = true;
    failed = false;
    notifyListeners();
    final edits = _edits;
    final r = await run(() => _api.post('/api/v1/certificate-designs/${d.id}/save', body: body));
    saving = false;
    if (r is Map<String, dynamic>) {
      if (_edits == edits) {
        adopt(CertDesign.fromJson(r), resetHistory: false); // the server copy is the source of truth after saving
        dirty = false;
      } else {
        // edited while the save was in flight: keep the working copy (it holds those edits) and stay dirty
        loaded = CertDesign.fromJson(r);
      }
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
    final r = await run(() => _api.post('/api/v1/certificates/$certificateId/design', body: {'design_id': id}));
    return r is Map<String, dynamic>;
  }

  @override
  void dispose() {
    for (final s in _studios.values) {
      s.dispose();
    }
    super.dispose();
  }
}
