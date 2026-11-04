// features/teacher/certificates/studio/cert_engine_studio.dart
//
// The Certificate Studio on the design engine (D-165, docs/design_engine/ENGINE.md): ONE v4 document per certificate
// design, mode 'page', one LayoutDesign per language (Arabic and English side by side as tabs, each with its own
// canvas controller kept alive, so undo survives switching). The canvas is the shared LayoutCanvasEditor.
//
//   • Languages: Arabic only / English only / both. A missing language never falls back to the other one: the person
//     picks "a mirrored copy" (x' = width − x − w, rtl flipped), a ready design or a blank page.
//   • Save is explicit (PUT with the version; 409 → "saved elsewhere": reload or keep mine). The unsaved state is a
//     notifier read by the title and the save button only — an edit or a drag never rebuilds this screen. The local
//     draft is written after 2 s without edits, keyed by user and design, and offered back (never dropped silently).
//   • Preview: the server draws one page per language with sample values, cached by the document's content.
//
// `certificateDesignerPage` is the one switch between this studio and the legacy designer (kill switch
// `certificates.engine`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/app_config.dart';
import '../../../../config/storage_service.dart';
import '../../../../core/api_client.dart';
import '../../../../design/app_kit.dart';
import '../../../../design/app_notice.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/export_layout/layout_canvas.dart';
import '../../../../design/export_layout/layout_element_view.dart' show LayoutAssets;
import '../../../../design/export_layout/layout_model.dart';
import '../../../../design/studio/studio.dart' show StudioController;
import '../../../admin/admin_common.dart' show t;
import '../designer/certificate_designer_screen.dart' show CertificateDesignerScreen;
import 'cert_engine_api.dart';
import 'cert_engine_panels.dart';
import 'cert_engine_presets.dart';

/// The kill switch that sends everyone back to the legacy designer.
const kCertEngineKillSwitch = 'certificates.engine';

/// The designer page for a design: this studio, or the legacy designer while `certificates.engine` is switched off.
Widget certificateDesignerPage({int? designId, int? certificateId, int? orgId}) =>
    AppConfig.disableList.contains(kCertEngineKillSwitch)
        ? CertificateDesignerScreen(designId: designId, certificateId: certificateId, orgId: orgId)
        : CertEngineStudio(designId: designId, certificateId: certificateId, orgId: orgId);

Future<void> openCertificateStudio(BuildContext context, {int? designId, int? certificateId, int? orgId}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => certificateDesignerPage(designId: designId, certificateId: certificateId, orgId: orgId)));

/// Where the local drafts live (device storage); tests pass [CertEngineMemoryDrafts].
class CertEngineDrafts {
  const CertEngineDrafts();
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);
  Future<void> write(String key, String json) async => (await SharedPreferences.getInstance()).setString(key, json);
  Future<void> remove(String key) async => (await SharedPreferences.getInstance()).remove(key);
}

class CertEngineMemoryDrafts extends CertEngineDrafts {
  CertEngineMemoryDrafts([Map<String, String>? seed]) : data = seed ?? {};
  final Map<String, String> data;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String json) async => data[key] = json;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// Loads the bytes of an image URL (the canvas draws what [LayoutAssets] holds). Null when it cannot be loaded.
typedef CertImageLoader = Future<Uint8List?> Function(String url);

Future<Uint8List?> _defaultImageLoader(String url) async {
  try {
    final r = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 20)));
    final data = r.data;
    if (data == null || data.isEmpty) return null;
    // decoded once at canvas size (never the full-size image), kept as PNG bytes
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(data), targetWidth: 640);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

class CertEngineStudio extends StatefulWidget {
  const CertEngineStudio({super.key, this.designId, this.certificateId, this.orgId, this.api, this.drafts, this.userId, this.imageLoader});

  /// The design to edit; null creates a new one (inside [orgId] when given).
  final int? designId;

  /// The course certificate the design is for: saving attaches the design to it.
  final int? certificateId;
  final int? orgId;
  final CertEngineApi? api;
  final CertEngineDrafts? drafts;

  /// The signed-in user (draft keys); read from the saved user when null.
  final String? userId;
  final CertImageLoader? imageLoader;

  @override
  State<CertEngineStudio> createState() => _CertEngineStudioState();
}

class _CertEngineStudioState extends State<CertEngineStudio> {
  late final CertEngineApi _api = widget.api ?? CertEngineApi();
  late final CertEngineDrafts _drafts = widget.drafts ?? const CertEngineDrafts();
  late final CertImageLoader _loadImage = widget.imageLoader ?? _defaultImageLoader;

  int? _id;
  bool _loading = true;
  String? _error;
  bool _forbidden = false;
  bool _fresh = false;

  LayoutDocument? _doc;
  int _version = 0;
  bool _converted = false;
  String _savedSig = '';

  /// Bumped when the whole document is replaced (reload, draft): every canvas is rebuilt on the new lists.
  int _gen = 0;
  String _lang = 'ar';
  int _seq = 0;
  bool _attached = false;
  String _userId = '0';
  List<CertStarter>? _starters;
  List<CertServerTemplate>? _templates;

  /// Read by the title / save button only.
  final _dirty = ValueNotifier<bool>(false);
  final _saving = ValueNotifier<bool>(false);
  Timer? _draftTimer;
  final Map<String, Uint8List> _previews = {};

  /// The photo a signature element was uploaded from (this session): "Clean signature again" re-runs from it.
  final Map<String, Uint8List> _sigOrig = {};

  /// Sample values the person typed for the custom variables (memory only).
  Map<String, String> _samples = {};

  LayoutDocument get doc => _doc!;
  LayoutDesign get _design => doc.designs[_lang]!;
  String get _draftKey => 'cert_engine_draft_${_userId}_$_id';

  @override
  void initState() {
    super.initState();
    _id = widget.designId;
    unawaited(_boot());
  }

  @override
  void dispose() {
    final pending = _draftTimer?.isActive ?? false;
    _draftTimer?.cancel();
    // closing within the debounce still keeps the last edits
    if (pending && _doc != null && _dirty.value) unawaited(_flushDraft());
    _dirty.dispose();
    _saving.dispose();
    super.dispose();
  }

  // ── loading ─────────────────────────────────────────────────────────────────────────────────────────────────

  String _sigNow() => jsonEncode(doc.toJson(withSource: false));

  Future<String> _readUserId() async {
    if (widget.userId != null) return widget.userId!;
    try {
      final s = await StorageService.getInstance();
      return '${s.savedUser?['id'] ?? 0}';
    } catch (_) {
      return '0';
    }
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    try {
      _userId = await _readUserId();
      if (_id == null) {
        _id = await _api.createBlank(orgId: widget.orgId);
        _fresh = true;
      }
      final r = await _api.load(_id!);
      if (!mounted) return;
      _adopt(r);
      setState(() => _loading = false);
      unawaited(_prefetchImages());
      await _checkDraft();
      if (_fresh && mounted) {
        _fresh = false;
        await _pickStarter(confirm: false);
      }
    } catch (e) {
      if (!mounted) return;
      final x = ApiException.from(e);
      setState(() {
        _loading = false;
        _error = x.message;
        _forbidden = x.statusCode == 403;
      });
    }
  }

  /// Takes a server document as the working copy (nothing is dirty).
  void _adopt(CertDocLoad r) {
    final d = r.document..purpose = 'certificate';
    d.languages.removeWhere((l) => l != 'ar' && l != 'en');
    if (d.languages.isEmpty) d.languages.add('ar');
    for (final l in d.languages) {
      final design = d.designs.putIfAbsent(l, () => certBlankDesign(l));
      design.mode = 'page';
    }
    _doc = d;
    _version = r.version;
    _converted = r.converted;
    _savedSig = _sigNow();
    if (!d.languages.contains(_lang)) _lang = d.languages.first;
    _dirty.value = false;
    _gen++;
  }

  Future<void> _prefetchImages() async {
    final urls = <String>{};
    for (final d in doc.designs.values) {
      if (d.page.backgroundImage != null) urls.add(d.page.backgroundImage!);
      for (final e in d.row.elements) {
        if (e.isImage && e.value != null) urls.add(e.value!);
      }
    }
    for (final u in urls) {
      if (!u.startsWith('http') || LayoutAssets.of(u) != null) continue;
      final bytes = await _loadImage(u);
      if (!mounted) return;
      if (bytes != null) LayoutAssets.put(u, bytes);
    }
  }

  Future<void> _checkDraft() async {
    final raw = await _drafts.read(_draftKey);
    if (raw == null || !mounted) return;
    LayoutDocument? saved;
    int base = 0;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      base = (j['base_version'] as num?)?.toInt() ?? 0;
      saved = LayoutDocument.fromJson((j['document'] as Map).cast<String, dynamic>());
    } catch (_) {
      await _drafts.remove(_draftKey);
      return;
    }
    if (jsonEncode(saved.toJson(withSource: false)) == _savedSig) {
      await _drafts.remove(_draftKey);
      return;
    }
    if (!mounted) return;
    final choice = await showCertDraftPrompt(context, outdated: base != _version);
    if (!mounted || choice == null) return;
    if (!choice) {
      await _drafts.remove(_draftKey);
      return;
    }
    setState(() {
      final d = saved!..purpose = 'certificate';
      for (final l in d.languages) {
        d.designs.putIfAbsent(l, () => certBlankDesign(l)).mode = 'page';
      }
      _doc = d;
      if (!d.languages.contains(_lang)) _lang = d.languages.first;
      _gen++;
    });
    _touch();
    unawaited(_prefetchImages());
  }

  // ── dirty + draft ────────────────────────────────────────────────────────────────────────────────────────────

  /// Something changed: mark it, and (re)start the 2 s draft timer. Cheap — runs on every drag frame.
  void _touch() {
    if (!_dirty.value) _dirty.value = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), () => unawaited(_flushDraft()));
  }

  Future<void> _flushDraft() async {
    if (_doc == null || _id == null) return;
    final s = _sigNow();
    if (s == _savedSig) {
      _dirty.value = false;
      await _drafts.remove(_draftKey);
      return;
    }
    await _drafts.write(_draftKey, '{"base_version":$_version,"saved_at":"${DateTime.now().toUtc().toIso8601String()}","document":$s}');
  }

  // ── save ─────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<bool> _save() async {
    if (_saving.value || _doc == null) return false;
    final id = _id!;
    final payload = doc.toJson(withSource: false);
    final sig = jsonEncode(payload);
    _saving.value = true;
    try {
      final v = await _api.save(id, payload, _version);
      _saving.value = false;
      await _onSaved(v, sig);
      return true;
    } on CertConflict {
      _saving.value = false;
      return _resolveConflict();
    } catch (e) {
      _saving.value = false;
      if (mounted) certNotifyError(e);
      return false;
    }
  }

  Future<void> _onSaved(int v, String sig) async {
    if (!mounted) return;
    _version = v;
    _savedSig = sig;
    setState(() => _converted = false);
    if (_sigNow() == sig) {
      _draftTimer?.cancel();
      _dirty.value = false;
      await _drafts.remove(_draftKey);
    } else {
      _touch(); // edited while the save was in flight: still unsaved
    }
    showAppNotice(t('تم حفظ التصميم', 'Design saved'));
    final cert = widget.certificateId;
    if (cert != null && !_attached) {
      try {
        await _api.attach(cert, _id!);
        _attached = true;
      } catch (e) {
        if (mounted) certNotifyError(e);
      }
    }
  }

  Future<bool> _resolveConflict() async {
    if (!mounted) return false;
    final choice = await showCertConflictDialog(context);
    if (choice == null || !mounted) return false;
    try {
      final r = await _api.load(_id!);
      if (!mounted) return false;
      if (choice == CertConflictChoice.reload) {
        _draftTimer?.cancel();
        setState(() => _adopt(r));
        await _drafts.remove(_draftKey);
        unawaited(_prefetchImages());
        return false;
      }
      _version = r.version; // keep mine: saved over the newer version
      return await _save();
    } catch (e) {
      if (mounted) certNotifyError(e);
      return false;
    }
  }

  // ── languages and designs ────────────────────────────────────────────────────────────────────────────────────

  String _newId() => 'e${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}';

  String _langName(String l) => l == 'ar' ? t('العربية', 'Arabic') : 'English';

  Future<List<CertStarter>> _loadStarters() async {
    try {
      return _starters ??= await _api.starters();
    } catch (e) {
      if (mounted) certNotifyError(e);
      return const [];
    }
  }

  /// The server's ready-made designs; a failed or old server just shows the starters.
  Future<List<CertServerTemplate>> _loadTemplates() async {
    try {
      return _templates ??= await _api.templates();
    } catch (_) {
      return const [];
    }
  }

  /// A server template always becomes a NEW design on the server (both languages, backgrounds uploaded). The studio
  /// keeps ITS design id and version: the template's copy is created, its [lang] page is read through the document
  /// endpoint and adopted here (like a starter), and the copy is deleted again. Null when it failed (the error is shown).
  Future<LayoutDesign?> _designFromTemplate(CertServerTemplate tp, String colorHex, String lang) async {
    int? copy;
    try {
      copy = await _api.createFromTemplate(tp.key, orgId: widget.orgId, themeColor: colorHex);
      final r = await _api.load(copy);
      final own = r.document.designs[lang];
      if (own != null) return own;
      final other = r.document.designs.values.isEmpty ? null : r.document.designs.values.first;
      return other == null ? certBlankDesign(lang) : certMirrorDesign(other, toRtl: lang == 'ar');
    } catch (e) {
      if (mounted) certNotifyError(e);
      return null;
    } finally {
      // the images stay on the server (they are referenced by url); only the throw-away design goes
      if (copy != null) unawaited(_api.delete(copy).catchError((Object _) {}));
    }
  }

  /// Opens the gallery (starters + templates) and resolves the pick to a design for [lang]; null = cancelled.
  Future<LayoutDesign?> _pickDesign(String lang) async {
    final starters = await _loadStarters();
    final templates = await _loadTemplates();
    if (!mounted || (starters.isEmpty && templates.isEmpty)) return null;
    final pick = await showCertGallery(context, starters: starters, templates: templates, lang: lang);
    if (pick == null || !mounted) return null;
    if (pick.starter != null) return _designFromStarter(pick.starter!, lang);
    return _designFromTemplate(pick.template!, pick.colorHex, lang);
  }

  LayoutDesign _designFromStarter(CertStarter s, String lang) {
    final own = s.document.designs[lang];
    if (own != null) return own.copy();
    final other = s.document.designs.values.isEmpty ? null : s.document.designs.values.first;
    return other == null ? certBlankDesign(lang) : certMirrorDesign(other, toRtl: lang == 'ar');
  }

  /// The starters gallery for the current language: replaces its design in place.
  Future<void> _pickStarter({bool confirm = true}) async {
    if (confirm && _design.row.elements.isNotEmpty) {
      final ok = await appConfirm(context, message: t('سيحلّ التصميم الجاهز محلّ تصميم ${_langName(_lang)} الحالي. المتابعة؟', 'The ready design replaces the current ${_langName(_lang)} design. Continue?'), confirmLabel: t('استبدال', 'Replace'));
      if (!ok || !mounted) return;
    }
    final made = await _pickDesign(_lang);
    if (made == null || !mounted) return;
    setState(() => certAdoptDesign(_design, made));
    _touch();
    unawaited(_prefetchImages());
  }

  /// Gives [lang] a design the person chose (never an implicit fallback). False when cancelled.
  Future<bool> _startLanguage(String lang) async {
    final otherKey = lang == 'ar' ? 'en' : 'ar';
    final other = doc.designs[otherKey];
    final how = await showCertStartChoice(context, lang: lang, canMirror: other != null);
    if (how == null || !mounted) return false;
    LayoutDesign? made;
    switch (how) {
      case CertStart.mirror:
        made = certMirrorDesign(other!, toRtl: lang == 'ar');
      case CertStart.blank:
        made = certBlankDesign(lang);
        if (other != null) {
          made.page
            ..size = other.page.size
            ..orientation = other.page.orientation
            ..customWidth = other.page.customWidth
            ..customHeight = other.page.customHeight;
        }
      case CertStart.starter:
        made = await _pickDesign(lang);
        if (made == null || !mounted) return false;
    }
    doc.designs[lang] = made;
    return true;
  }

  Future<void> _chooseLanguages() async {
    final current = doc.languages.length > 1 ? 'both' : doc.languages.first;
    final pick = await showCertLanguagesSheet(context, current);
    if (pick == null || !mounted || pick == current) return;
    final next = pick == 'both' ? ['ar', 'en'] : [pick];
    for (final l in next) {
      if (doc.designs[l] == null && !await _startLanguage(l)) return;
      if (!mounted) return;
    }
    setState(() {
      doc.languages
        ..clear()
        ..addAll(next);
      if (!next.contains(_lang)) _lang = next.first;
    });
    _touch();
    unawaited(_prefetchImages());
  }

  /// "Start English from the Arabic design": an explicit mirrored copy into the current tab.
  Future<void> _mirrorIntoCurrent() async {
    final from = _lang == 'ar' ? 'en' : 'ar';
    final src = doc.designs[from];
    if (src == null) return;
    if (_design.row.elements.isNotEmpty) {
      final ok = await appConfirm(
        context,
        message: t('سيُستبدل تصميم ${_langName(_lang)} بنسخة معكوسة من تصميم ${_langName(from)}. المتابعة؟', 'The ${_langName(_lang)} design is replaced by a mirrored copy of the ${_langName(from)} design. Continue?'),
        confirmLabel: t('استبدال', 'Replace'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => certAdoptDesign(_design, certMirrorDesign(src, toRtl: _lang == 'ar')));
    _touch();
  }

  Future<void> _newVariable() async {
    final key = await showCertVariableDialog(context);
    if (key == null || !mounted) return;
    final d = _design;
    final e = LayoutElement(id: _newId(), kind: 'text', w: 100, h: 12, value: '{{$key}}', name: key, style: LayoutStyle(size: 18, align: 'center', padding: 0));
    e
      ..x = mm((d.page.contentWidth - e.w) / 2)
      ..y = mm((d.page.contentHeight - e.h) / 2);
    setState(() => d.row.elements.add(e));
    _touch();
  }

  // ── images ───────────────────────────────────────────────────────────────────────────────────────────────────

  /// A signature goes through the signature endpoint (the server removes its background), the rest as before.
  Future<String?> _uploadFor(LayoutElement el, Uint8List bytes, String name) async {
    if (el.kind != 'signature') return _upload(bytes, name);
    try {
      final url = await _api.uploadSignature(bytes, ink: '#000000');
      _sigOrig[el.id] = bytes;
      LayoutAssets.put(url, bytes);
      // the canvas then stores the picked photo under the URL: show the cleaned image over it
      unawaited(Future<void>(() async {
        final clean = await _loadImage(url);
        if (clean != null && mounted) LayoutAssets.put(url, clean);
      }));
      return url;
    } catch (e) {
      if (mounted) certNotifyError(e);
      return null;
    }
  }

  Widget? _extraFor(BuildContext context, LayoutElement el, StudioController<LayoutElement> ctl) {
    if (el.kind != 'signature' || el.value == null) return null;
    return OutlinedButton.icon(
      key: const ValueKey('cert-sig-clean'),
      onPressed: () => unawaited(_cleanSignature(context, el, ctl)),
      icon: const Icon(Icons.auto_fix_high_rounded),
      label: Text(t('تنظيف التوقيع مجددًا', 'Clean signature again')),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
    );
  }

  Future<void> _cleanSignature(BuildContext context, LayoutElement el, StudioController<LayoutElement> ctl) async {
    // this session's photo when there is one; else the image saved in the design (the server keeps the cleaned PNG only)
    final fromSaved = !_sigOrig.containsKey(el.id);
    final r = await showCertSignatureClean(context, fromSaved: fromSaved);
    if (r == null || !mounted) return;
    try {
      var bytes = _sigOrig[el.id];
      if (bytes == null) {
        final src = el.value!;
        bytes = (src.startsWith('http') ? await _loadImage(src) : null) ?? LayoutAssets.of(src);
        if (bytes == null) throw ApiException(statusCode: 0, message: t('تعذّر تحميل صورة التوقيع. تحقق من الاتصال وحاول مجددًا.', 'The signature image could not be loaded. Check the connection and try again.'));
      }
      final url = await _api.uploadSignature(bytes, ink: r.ink, strength: r.strength);
      final clean = await _loadImage(url);
      LayoutAssets.put(url, clean ?? bytes);
      if (mounted) ctl.record('signature', () => el.value = url);
    } catch (e) {
      if (mounted) certNotifyError(e);
    }
  }

  /// A generated background for the current language (the server returns it; nothing else changes).
  Future<String?> _generateBackground(String style, String color, bool dark) async {
    final p = _design.page;
    Map<String, dynamic>? page;
    switch (p.size) {
      case 'Letter':
        page = {'size': 'letter'};
      case 'A3':
        page = {'size': 'custom', 'w_mm': 297.0, 'h_mm': 420.0};
      case 'A5':
        page = {'size': 'custom', 'w_mm': 148.0, 'h_mm': 210.0};
      case 'custom':
        page = {'size': 'custom', 'w_mm': p.customWidth, 'h_mm': p.customHeight};
      default:
        page = {'size': 'a4'};
    }
    try {
      final url = await _api.generateBackground(_id!, lang: _lang, landscape: p.landscape, style: style, themeColor: color, dark: dark, page: page);
      final bytes = await _loadImage(url);
      if (bytes != null) LayoutAssets.put(url, bytes);
      return url;
    } catch (e) {
      if (mounted) certNotifyError(e);
      return null;
    }
  }

  Future<void> _rename() async {
    final name = await showCertRenameDialog(context, doc.name ?? '');
    if (name == null || !mounted || name == doc.name) return;
    try {
      await _api.rename(_id!, name);
    } catch (e) {
      if (mounted) certNotifyError(e);
      return;
    }
    if (!mounted) return;
    final clean = !_dirty.value;
    setState(() => doc.name = name);
    // the server already has the name: a clean design stays clean, an edited one is saved with the name anyway
    if (clean) _savedSig = _sigNow();
    showAppNotice(t('تمت إعادة التسمية', 'Renamed'));
  }

  Future<String?> _upload(Uint8List bytes, String name) async {
    try {
      final url = await _api.uploadLogo(bytes);
      LayoutAssets.put(url, bytes);
      return url;
    } catch (e) {
      if (mounted) certNotifyError(e);
      return null;
    }
  }

  Future<String?> _pickBackground() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
      if (f == null) return null;
      final bytes = await f.readAsBytes();
      final p = _design.page;
      final url = await _api.uploadBackground(bytes, landscape: p.landscape, size: p.size, wMm: p.customWidth, hMm: p.customHeight);
      final small = await _defaultShrink(bytes);
      LayoutAssets.put(url, small ?? bytes);
      return url;
    } catch (e) {
      if (mounted) certNotifyError(e);
      return null;
    }
  }

  Future<Uint8List?> _defaultShrink(Uint8List b) async {
    try {
      final codec = await ui.instantiateImageCodec(b, targetWidth: 640);
      final frame = await codec.getNextFrame();
      return (await frame.image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ── preview ──────────────────────────────────────────────────────────────────────────────────────────────────

  /// Cached by the document's content: opening it again without an edit makes no call.
  Future<Uint8List> _fetchPreview(String lang) async {
    final map = doc.toJson(withSource: false);
    final s = jsonEncode(map);
    final vals = _valuesFor(lang);
    final key = '$lang/${s.length}/${s.hashCode}/${jsonEncode(vals).hashCode}';
    final hit = _previews[key];
    if (hit != null) return hit;
    final png = await _api.preview(map, lang, _valuesFor(lang));
    _previews[key] = png;
    while (_previews.length > 6) {
      _previews.remove(_previews.keys.first);
    }
    return png;
  }

  /// The sample values of [lang]: the built-in ones, the custom ones, then what the person typed.
  Map<String, String> _valuesFor(String lang) => {...certSampleValues(lang, certCustomKeysOf(doc)), ..._samples};

  void _preview() => unawaited(showCertPreview(
        context,
        languages: doc.languages,
        initial: _lang,
        fetch: _fetchPreview,
        customKeys: certCustomKeysOf(doc),
        samples: _samples,
        onSamples: (v) => setState(() => _samples = v),
      ));

  // ── build ────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _copyForMe() async {
    try {
      final id = await _api.duplicate(_id!, certificateId: widget.certificateId);
      if (!mounted) return;
      _id = id;
      await _boot();
    } catch (e) {
      if (mounted) certNotifyError(e);
    }
  }

  Future<void> _onPopAttempt(bool didPop) async {
    if (didPop) return;
    final choice = await showCertLeaveDialog(context);
    if (!mounted) return;
    if (choice == 'save') {
      if (await _save() && mounted) Navigator.of(context).pop();
    } else if (choice == 'discard') {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading || _error != null || _doc == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('استوديو الشهادات', 'Certificate studio'))),
        body: _loading
            ? const AppListSkeleton(withAvatar: false)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error ?? '', textAlign: TextAlign.center, style: appText(14, c: c.textDark)),
                    const SizedBox(height: AppSpace.md),
                    FilledButton(onPressed: _boot, child: Text(t('إعادة المحاولة', 'Retry'))),
                    if (_forbidden) ...[
                      const SizedBox(height: AppSpace.xs),
                      OutlinedButton(onPressed: _copyForMe, child: Text(t('إنشاء نسخة قابلة للتعديل', 'Make an editable copy'))),
                    ],
                  ]),
                ),
              ),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _dirty,
      builder: (context, dirty, child) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) => unawaited(_onPopAttempt(didPop)),
        child: child!,
      ),
      child: Scaffold(
        appBar: _appBar(context),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_converted) _banner(context),
          if (doc.languages.length > 1) _tabs(context),
          Expanded(child: _editors()),
        ]),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final c = context.colors;
    return AppBar(
      titleSpacing: 0,
      title: ValueListenableBuilder<bool>(
        valueListenable: _dirty,
        builder: (context, dirty, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            key: const ValueKey('cert-title'),
            onTap: () => unawaited(_rename()),
            child: Text(doc.name ?? t('تصميم الشهادة', 'Certificate design'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w700, c: c.textDark)),
          ),
          Text(
            dirty ? t('تعديلات غير محفوظة', 'Unsaved changes') : t('كل التعديلات محفوظة', 'All changes saved'),
            key: const ValueKey('cert-save-state'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(12, c: dirty ? c.danger : c.textMedium),
          ),
        ]),
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: _saving,
          builder: (context, saving, _) => ValueListenableBuilder<bool>(
            valueListenable: _dirty,
            builder: (context, dirty, _) => saving
                ? const Padding(padding: EdgeInsets.all(AppSpace.sm), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                : IconButton(
                    key: const ValueKey('cert-save'),
                    tooltip: t('حفظ', 'Save'),
                    onPressed: dirty ? () => unawaited(_save()) : null,
                    icon: Badge(isLabelVisible: dirty, smallSize: 9, child: const Icon(Icons.save_rounded)),
                  ),
          ),
        ),
        IconButton(key: const ValueKey('cert-preview'), tooltip: t('معاينة', 'Preview'), onPressed: _preview, icon: const Icon(Icons.visibility_outlined)),
        PopupMenuButton<String>(
          key: const ValueKey('cert-menu'),
          tooltip: t('المزيد', 'More'),
          onSelected: (v) {
            switch (v) {
              case 'page':
                unawaited(showCertPageSheet(context, design: _design, pickBackground: _pickBackground, generateBackground: _generateBackground, onChanged: () {
                  setState(() {});
                  _touch();
                }));
              case 'rename':
                unawaited(_rename());
              case 'langs':
                unawaited(_chooseLanguages());
              case 'starter':
                unawaited(_pickStarter());
              case 'mirror':
                unawaited(_mirrorIntoCurrent());
              case 'variable':
                unawaited(_newVariable());
              case 'classic':
                unawaited(_openClassic());
            }
          },
          itemBuilder: (_) => [
            _item('page', Icons.crop_landscape_rounded, t('الصفحة والخلفية', 'Page and background')),
            _item('rename', Icons.drive_file_rename_outline_rounded, t('إعادة تسمية', 'Rename')),
            _item('langs', Icons.translate_rounded, t('اللغات', 'Languages')),
            _item('starter', Icons.dashboard_customize_outlined, t('تصاميم جاهزة', 'Ready designs')),
            if (doc.languages.length > 1)
              _item('mirror', Icons.flip_rounded, _lang == 'en' ? t('ابدأ الإنجليزي من العربي', 'Start English from the Arabic design') : t('ابدأ العربي من الإنجليزي', 'Start Arabic from the English design')),
            _item('variable', Icons.data_object_rounded, t('متغيّر جديد', 'New variable')),
            if (_id != null) _item('classic', Icons.history_edu_outlined, t('المصمم الكلاسيكي', 'Classic designer')),
          ],
        ),
      ],
    );
  }

  /// The legacy designer stays reachable (its draft wizard, signature cleanup, watermark… have no studio equivalent
  /// yet, D-165). It edits the design's older layout, and saving there makes that layout the one that renders.
  Future<void> _openClassic() async {
    final id = _id;
    if (id == null) return;
    final ok = await appConfirm(
      context,
      message: t('يفتح المصمم الكلاسيكي التخطيط القديم لهذا التصميم. الحفظ هناك يجعل ذلك التخطيط هو المستخدم بدلاً من تصميم الاستوديو، وتبقى تعديلاتك غير المحفوظة هنا مسودة.',
          'The classic designer opens this design\'s older layout. Saving there makes that layout the one used instead of the studio design; your unsaved changes here stay as a draft.'),
      confirmLabel: t('فتح', 'Open'),
    );
    if (!ok || !mounted) return;
    if (_dirty.value) await _flushDraft();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => CertificateDesignerScreen(designId: id, certificateId: widget.certificateId, orgId: widget.orgId)));
  }

  PopupMenuItem<String> _item(String v, IconData icon, String label) => PopupMenuItem(
        value: v,
        height: AppTouch.min,
        child: Row(children: [Icon(icon, size: 20), const SizedBox(width: AppSpace.sm), Flexible(child: Text(label))]),
      );

  Widget _banner(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('cert-converted-banner'),
      color: c.primary.withValues(alpha: .08),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 18, color: c.primary),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(t('انتقل تصميمك إلى الاستوديو الجديد — لا شيء يتغيّر حتى تحفظ.', 'Moved to the new studio — nothing changes until you save.'), style: appText(12.5, c: c.textDark))),
      ]),
    );
  }

  Widget _tabs(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
      child: Row(children: [
        for (final l in doc.languages)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              child: Material(
                color: _lang == l ? c.primary.withValues(alpha: .12) : c.cardBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip), side: BorderSide(color: _lang == l ? c.primary : c.divider)),
                child: InkWell(
                  key: ValueKey('cert-tab-$l'),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  onTap: () => setState(() => _lang = l),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min),
                    child: Center(child: Text(_langName(l), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: _lang == l ? FontWeight.w700 : FontWeight.w500, c: _lang == l ? c.primary : c.textDark))),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  /// One canvas per language, all alive (an IndexedStack): switching keeps each one's selection and undo history.
  /// The page's margins (mm): the canvas draws the whole paper, its background image included, around the content box.
  static EdgeInsets _marginsOf(LayoutPage p) => EdgeInsets.fromLTRB(p.margins.left, p.margins.top, p.margins.right, p.margins.bottom);

  Widget _editors() {
    final custom = certCustomKeysOf(doc);
    return LayoutBuilder(
      builder: (context, box) => IndexedStack(
        sizing: StackFit.expand,
        index: doc.languages.indexOf(_lang).clamp(0, doc.languages.length - 1),
        children: [
          for (final l in doc.languages)
            LayoutCanvasEditor(
              key: ValueKey('$_gen/$l'),
              elements: doc.designs[l]!.row.elements,
              width: doc.designs[l]!.page.contentWidth,
              height: doc.designs[l]!.page.contentHeight,
              rtl: doc.designs[l]!.page.rtl,
              pageFont: doc.designs[l]!.page.font,
              pageFontSize: doc.designs[l]!.page.fontSize,
              lang: l,
              fields: certFieldOptions(l, custom),
              addOptions: certAddOptions(l, custom),
              newId: _newId,
              onChanged: _touch,
              upload: _upload,
              uploadFor: _uploadFor,
              extraFor: _extraFor,
              vars: {...certSampleValues(l, custom), ..._samples},
              fieldOf: (k) => certFieldOf(l, k),
              background: doc.designs[l]!.page.background,
              backgroundImage: doc.designs[l]!.page.backgroundImage,
              backgroundFit: doc.designs[l]!.page.backgroundFit,
              pageMargins: _marginsOf(doc.designs[l]!.page),
              wide: box.maxWidth >= 900,
            ),
        ],
      ),
    );
  }
}
