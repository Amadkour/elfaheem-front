// "Use your own sheet" (D-302): any bubble sheet a teacher already has (round or square bubbles, no NextBrain
// marks) or a table where students WRITE the number / letter of their answer. One photo, scan or PDF of it →
// `POST /omr/auto-templates/detect` finds the questions, the options, the student-ID block (or a QR / barcode) →
// the teacher checks it once on the picture (each block coloured by what it is, its question numbers on it) and
// fixes what is off (a block's role, the numbering direction, where numbering starts, numbers or letters, how many
// options) → `POST /omr/auto-templates` saves it as their own template, chosen in the exam wizard like any sheet.
// Behind the Super Admin's switch `exam.auto_correct`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart' show OmrTemplateItem;
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart' show omrDigitsText, omrOptionsText, omrQuestionsText;

/// The Super Admin's switch for automatic correction (detection, reading own sheets).
const kOwnSheetFeatureKey = 'exam.auto_correct';

// ── the detected layout ───────────────────────────────────────────────────────────────────────────────────────

enum OwnSheetKind { bubbles, table }

/// One question in sheet order: its number, the block and the row it sits on.
typedef OwnSheetQuestion = ({int n, int block, int row, int options});

/// What `/detect` found, edited in place by the review screen and sent back on save.
class OwnSheetDraft {
  OwnSheetDraft({
    required this.kind,
    required this.blankKey,
    required this.layout,
    this.imageW = 1240,
    this.imageH = 1754,
    this.image,
    this.warnings = const [],
  });

  final OwnSheetKind kind;
  final String blankKey;
  final Map<String, dynamic> layout;
  final int imageW, imageH;

  /// The deskewed sheet the layout is drawn on (JPEG), null from a server that does not send it.
  final Uint8List? image;
  final List<String> warnings;

  static OwnSheetDraft fromJson(Map<String, dynamic> j) {
    final img = asMap(j['image']);
    final b64 = j['image_b64'];
    Uint8List? bytes;
    if (b64 is String && b64.isNotEmpty) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {
        bytes = null;
      }
    }
    final layout = asMap(j['layout']);
    final kind = j['kind'] == 'written_table' ? OwnSheetKind.table : OwnSheetKind.bubbles;
    if (kind == OwnSheetKind.table) {
      layout['options'] ??= 4;
      layout['answer'] ??= 'digit';
    }
    return OwnSheetDraft(
      kind: kind,
      blankKey: '${j['blank_key'] ?? ''}',
      layout: layout,
      imageW: asInt(img['w'], 1240),
      imageH: asInt(img['h'], 1754),
      image: bytes,
      warnings: [for (final w in (j['warnings'] is List ? j['warnings'] as List : const [])) '$w'],
    );
  }

  String get serverKind => kind == OwnSheetKind.table ? 'written_table' : 'auto_bubble';

  List<Map<String, dynamic>> get blocks => [for (final b in (layout['blocks'] is List ? layout['blocks'] as List : const [])) if (b is Map<String, dynamic>) b];
  List<Map<String, dynamic>> get rows => [for (final r in (layout['rows'] is List ? layout['rows'] as List : const [])) if (r is Map<String, dynamic>) r];

  Map<String, dynamic> get _numbering => (layout['numbering'] is Map<String, dynamic>) ? layout['numbering'] as Map<String, dynamic> : (layout['numbering'] = <String, dynamic>{});
  bool get rtl => _numbering['direction'] == 'rtl';
  set rtl(bool v) => _numbering['direction'] = v ? 'rtl' : 'ltr';
  bool get across => _numbering['order'] == 'across';
  set across(bool v) => _numbering['order'] = v ? 'across' : 'down';
  int get start => asInt(_numbering['start'], 1);
  set start(int v) => _numbering['start'] = v.clamp(1, 999);

  String roleOf(Map<String, dynamic> b) => '${b['role'] ?? 'answers'}';

  /// Sets a block's role; a second ID block turns the first one back into answers (one ID per sheet).
  void setRole(int id, String role) {
    for (final b in blocks) {
      if (asInt(b['id']) == id) {
        b['role'] = role;
      } else if (role == 'identifier' && roleOf(b) == 'identifier') {
        b['role'] = 'answers';
      }
    }
  }

  int get options => kind == OwnSheetKind.table ? asInt(layout['options'], 4) : questions.fold(0, (m, q) => q.options > m ? q.options : m);
  set options(int v) => layout['options'] = v.clamp(2, 8);
  bool get letters => layout['answer'] == 'letter';
  set letters(bool v) => layout['answer'] = v ? 'letter' : 'digit';

  /// The questions in sheet order (the server's numbering, mlkit/omr/autolayout.questions_of).
  List<OwnSheetQuestion> get questions {
    if (kind == OwnSheetKind.table) {
      return [for (final (i, r) in rows.indexed) (n: asInt(r['n'], i + 1), block: 0, row: i, options: asInt(layout['options'], 4))];
    }
    final bub = asMap(layout['bubble']);
    final bw = (bub['w'] is num) ? (bub['w'] as num).toDouble() : 0.01;
    final bh = (bub['h'] is num) ? (bub['h'] as num).toDouble() : 0.01;
    final ans = [for (final b in blocks) if (roleOf(b) == 'answers') b];
    final out = <(Map<String, dynamic>, int)>[];
    if (across) {
      final all = [for (final b in ans) for (var r = 0; r < asInt(b['rows']); r++) (b, r)];
      for (final g in _cluster([for (final (b, r) in all) _cell(b, r, 0).dy], 0.5 * bh)) {
        final line = [for (final i in g) all[i]]..sort((a, b) => _cell(a.$1, a.$2, 0).dx.compareTo(_cell(b.$1, b.$2, 0).dx));
        out.addAll(rtl ? line.reversed : line);
      }
    } else {
      final xs = [for (final b in ans) _box(b).left];
      final groups = _cluster(xs, 2 * bw)..sort((a, b) => xs[a.first].compareTo(xs[b.first]));
      for (final g in rtl ? groups.reversed : groups) {
        final col = [for (final i in g) ans[i]]..sort((a, b) => _box(a).top.compareTo(_box(b).top));
        for (final b in col) {
          for (var r = 0; r < asInt(b['rows']); r++) {
            out.add((b, r));
          }
        }
      }
    }
    return [for (final (i, (b, r)) in out.indexed) (n: start + i, block: asInt(b['id']), row: r, options: asInt(b['cols']))];
  }

  /// "Q1–25" per answer block, "ID" for the identifier block.
  Map<int, String> get blockLabels {
    final out = <int, String>{};
    final byBlock = <int, List<int>>{};
    for (final q in questions) {
      (byBlock[q.block] ??= []).add(q.n);
    }
    for (final b in blocks) {
      final id = asInt(b['id']);
      final ns = byBlock[id];
      if (roleOf(b) == 'identifier') {
        out[id] = t('رقم الطالب', 'Student ID');
      } else if (ns != null && ns.isNotEmpty) {
        final lo = ns.reduce((a, b) => a < b ? a : b), hi = ns.reduce((a, b) => a > b ? a : b);
        // the range in an LTR isolate: "س 1–20" must not come out as "20–1" in an Arabic line
        final range = lo == hi ? '$lo' : '$lo–$hi';
        out[id] = t('س ${_ltr(range)}', 'Q$range');
      }
    }
    return out;
  }

  /// Digits of the shaded ID (0: none).
  int get idDigits {
    for (final b in blocks) {
      if (roleOf(b) != 'identifier') continue;
      if (asInt(b['rows']) == 10) return asInt(b['cols']);
      if (asInt(b['cols']) == 10) return asInt(b['rows']);
    }
    return 0;
  }

  /// qr | barcode | none when there is no shaded ID block.
  String get codeKind => '${asMap(layout['identifier'])['kind'] ?? 'none'}';
  String get shape => '${layout['shape'] ?? 'circle'}';

  static Offset _cell(Map<String, dynamic> b, int r, int c) {
    final cells = b['cells'] is List ? b['cells'] as List : const [];
    final row = r < cells.length && cells[r] is List ? cells[r] as List : const [];
    final p = c < row.length && row[c] is List ? row[c] as List : const [0, 0];
    return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
  }

  static Rect _box(Map<String, dynamic> b) => ownSheetRect(b['box']);
}

String _ltr(String s) => '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}';

Rect ownSheetRect(Object? v) {
  final l = v is List ? v : const [0, 0, 0, 0];
  double at(int i) => i < l.length && l[i] is num ? (l[i] as num).toDouble() : 0;
  return Rect.fromLTWH(at(0), at(1), at(2), at(3));
}

List<List<int>> _cluster(List<double> vals, double tol) {
  final idx = List<int>.generate(vals.length, (i) => i)..sort((a, b) => vals[a].compareTo(vals[b]));
  final groups = <List<int>>[];
  for (final i in idx) {
    if (groups.isNotEmpty && vals[i] - vals[groups.last.last] <= tol) {
      groups.last.add(i);
    } else {
      groups.add([i]);
    }
  }
  return groups;
}

// ── API ───────────────────────────────────────────────────────────────────────────────────────────────────────

class OwnSheetApi {
  OwnSheetApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam/omr/auto-templates';

  Future<EngineResult> detect((String, Uint8List) file, {int? orgId, String kind = 'auto'}) {
    final form = FormData();
    if (orgId != null) form.fields.add(MapEntry('org_id', '$orgId'));
    form.fields.add(MapEntry('kind', kind));
    form.files.add(MapEntry('image', MultipartFile.fromBytes(file.$2, filename: file.$1, contentType: MediaType.parse(_mime(file.$1)))));
    return engineCall(() => _api.post('$_b/detect', body: form));
  }

  Future<EngineResult> create({int? orgId, required String name, required OwnSheetDraft draft}) => engineCall(() => _api.post(_b, body: {
        'org_id': ?orgId,
        'name': name,
        'kind': draft.serverKind,
        'blank_key': draft.blankKey,
        'layout': draft.layout,
        if (draft.kind == OwnSheetKind.table) ...{'options': draft.options, 'answer': draft.letters ? 'letter' : 'digit'},
      }));
}

String _mime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.pdf')) return 'application/pdf';
  return 'image/jpeg';
}

/// The server's refusal in the app's language.
String ownSheetErrorText(EngineResult r) {
  switch (r.code) {
    case 'sheet_not_detected':
      return t('لم نتعرف على فقاعات أو جدول إجابات في هذه الصورة. صوّر الورقة كاملة ومعتدلة بإضاءة جيدة.',
          "We couldn't find bubbles or an answer table in this picture. Photograph the whole sheet, upright, in good light.");
    case 'feature_disabled':
      return t('التصحيح التلقائي متوقف حاليًا من إدارة المنصة.', 'Automatic correction is switched off by the platform admin.');
    case 'server_busy':
      return t('الخادم مشغول، حاول بعد لحظات.', 'The server is busy. Try again in a moment.');
    case 'unsupported_file':
      return t('ارفع صورة (JPEG أو PNG أو WebP) أو ملف PDF.', 'Send an image (JPEG, PNG or WebP) or a PDF.');
    case 'layout_invalid':
      return t('ما زال في التخطيط شيء غير صحيح. تأكد من وجود قسم إجابات واحد على الأقل.', 'Something in the layout is still off. Keep at least one answers block.');
  }
  final en = r.detail['message_en'];
  if (en != null && AppConfig.lang == 'en') return '$en';
  return r.message.isNotEmpty && r.message != 'Not Found' ? r.message : t('تعذّر ذلك، أعد المحاولة.', "That didn't work. Try again.");
}

/// Picks the sheet: (name, bytes) or null. [camera]: take a photo (phones).
typedef OwnSheetPicker = Future<(String, Uint8List)?> Function({required bool camera});

Future<(String, Uint8List)?> defaultOwnSheetPicker({required bool camera}) async {
  try {
    if (camera) {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 3000, imageQuality: 92);
      if (x == null) return null;
      return (x.name.isEmpty ? 'sheet.jpg' : x.name, await x.readAsBytes());
    }
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf']);
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  } catch (_) {
    return null;
  }
}

bool get _phone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

// ── the page ──────────────────────────────────────────────────────────────────────────────────────────────────

/// Opens the flow; the saved template (ready to pick in the wizard) or null.
Future<OmrTemplateItem?> openOwnSheet(BuildContext context, {int? orgId, OwnSheetApi? api, OwnSheetPicker? picker}) =>
    Navigator.of(context).push<OmrTemplateItem>(MaterialPageRoute(builder: (_) => OwnSheetPage(orgId: orgId, api: api, picker: picker)));

class OwnSheetPage extends StatefulWidget {
  const OwnSheetPage({super.key, this.orgId, this.api, this.picker, this.camera});
  final int? orgId;
  final OwnSheetApi? api;
  final OwnSheetPicker? picker;

  /// Offer "Take a photo" (default: on phones).
  final bool? camera;

  @override
  State<OwnSheetPage> createState() => _OwnSheetPageState();
}

class _OwnSheetPageState extends State<OwnSheetPage> {
  late final OwnSheetApi _api = widget.api ?? OwnSheetApi();
  final _name = TextEditingController();
  OwnSheetDraft? _draft;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool camera}) async {
    final f = await (widget.picker ?? defaultOwnSheetPicker)(camera: camera);
    if (f == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.detect(f, orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _draft = OwnSheetDraft.fromJson(r.map);
        if (_name.text.trim().isEmpty) {
          _name.text = _draft!.kind == OwnSheetKind.table ? t('جدول إجابات', 'Answer table') : t('ورقة التظليل الخاصة بي', 'My bubble sheet');
        }
      } else {
        _error = ownSheetErrorText(r);
      }
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null || _busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = t('اكتب اسمًا للورقة', 'Give the sheet a name'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.create(orgId: widget.orgId, name: name, draft: d);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = ownSheetErrorText(r);
      });
      return;
    }
    showAppNotice(t('تم حفظ الورقة — اخترها للاختبار', 'Sheet saved — pick it for the exam'));
    Navigator.of(context).pop(OmrTemplateItem.fromJson(r.map));
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return BasePage(
      key: const ValueKey(kOwnSheetFeatureKey),
      appBar: ScreenAppBar(title: t('استخدم ورقتك الخاصة', 'Use your own sheet')),
      child: d == null
          ? OwnSheetIntro(
              busy: _busy,
              error: _error,
              onCamera: (widget.camera ?? _phone) ? () => _pick(camera: true) : null,
              onUpload: () => _pick(camera: false),
            )
          : OwnSheetReview(
              draft: d,
              name: _name,
              busy: _busy,
              error: _error,
              onChanged: () => setState(() {}),
              onSave: _save,
              onRetake: () => setState(() {
                _draft = null;
                _error = null;
              }),
            ),
    );
  }
}

// ── step 1: the picture ───────────────────────────────────────────────────────────────────────────────────────

class OwnSheetIntro extends StatelessWidget {
  const OwnSheetIntro({super.key, required this.onUpload, this.onCamera, this.busy = false, this.error});
  final VoidCallback onUpload;
  final VoidCallback? onCamera;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (busy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)),
            AppSpace.gapMd,
            Text(t('نبحث عن الأسئلة والخيارات ورقم الطالب…', 'Finding the questions, options and student ID…'),
                style: AppType.section(context), textAlign: TextAlign.center),
            AppSpace.gapXs,
            Text(t('يستغرق ذلك بضع ثوانٍ', 'This takes a few seconds'), style: AppType.meta(context), textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.document_scanner_outlined, size: 36, color: c.primary),
                ),
              ),
              AppSpace.gapMd,
              Text(t('صحّح على ورقتك أنت', 'Mark papers on your own sheet'), style: AppType.pageTitle(context), textAlign: TextAlign.center),
              AppSpace.gapXs,
              Text(
                t('أي ورقة تظليل لديك — فقاعات دائرية أو مستطيلة — أو جدول يكتب فيه الطالب رقم الإجابة أو حرفها. صوّرها مرة واحدة ونتعرف عليها.',
                    'Any bubble sheet you already use — round or square bubbles — or a table where students write the number or letter of their answer. Photograph it once and we work it out.'),
                style: AppType.body(context).copyWith(color: c.textMedium),
                textAlign: TextAlign.center,
              ),
              AppSpace.gapLg,
              _Step(n: 1, icon: Icons.photo_camera_outlined, title: t('صوّر الورقة', 'Photograph the sheet'),
                  text: t('فارغة أو مظللة، كاملة ومعتدلة', 'Blank or filled in, whole and upright')),
              _Step(n: 2, icon: Icons.fact_check_outlined, title: t('راجع ما وجدناه', 'Check what we found'),
                  text: t('الأسئلة والخيارات ورقم الطالب ملوّنة على الصورة', 'Questions, options and the student ID, coloured on the picture')),
              _Step(n: 3, icon: Icons.task_alt_rounded, title: t('استخدمها لأي اختبار', 'Use it for any exam'),
                  text: t('تُحفظ مع أوراقك وتختارها عند إعداد الاختبار', 'It is saved with your sheets for any exam you set up'), last: true),
              AppSpace.gapLg,
              if (error != null) ...[
                AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
                AppSpace.gapSm,
              ],
              if (onCamera != null) ...[
                AppButton.primary(key: const ValueKey('own.camera'), label: t('صوّر الورقة', 'Take a photo'), icon: Icons.photo_camera_outlined, expand: true, onPressed: onCamera),
                AppSpace.gapSm,
              ],
              onCamera == null
                  ? AppButton.primary(key: const ValueKey('own.upload'), label: t('ارفع صورة أو PDF', 'Upload a picture or PDF'), icon: Icons.upload_file_rounded, expand: true, onPressed: onUpload)
                  : AppButton.secondary(key: const ValueKey('own.upload'), label: t('ارفع صورة أو PDF', 'Upload a picture or PDF'), icon: Icons.upload_file_rounded, expand: true, onPressed: onUpload),
            ]),
          ),
          AppSpace.gapSm,
          AppBanner(
            icon: Icons.lightbulb_outline_rounded,
            text: t('أوراق NextBrain المطبوعة لا تحتاج هذا: اخترها مباشرة من القائمة.', "NextBrain's printed sheets don't need this: pick them straight from the list."),
          ),
        ]),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.icon, required this.title, required this.text, this.last = false});
  final int n;
  final IconData icon;
  final String title, text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: AppRadius.chipAll),
          child: Icon(icon, size: 20, color: c.primary),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n · $title', style: AppType.row(context)),
            Text(text, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

// ── step 2: check what was found ──────────────────────────────────────────────────────────────────────────────

/// Plain values only (the layout harness and the renders pump it): the picture with its overlay, what was found,
/// what the teacher can change, Save.
class OwnSheetReview extends StatelessWidget {
  const OwnSheetReview({
    super.key,
    required this.draft,
    required this.name,
    required this.onChanged,
    required this.onSave,
    required this.onRetake,
    this.busy = false,
    this.error,
  });

  final OwnSheetDraft draft;
  final TextEditingController name;
  final VoidCallback onChanged, onSave, onRetake;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final tall = box.maxHeight.isFinite ? box.maxHeight : 900.0;
      final panel = _Panel(draft: draft, name: name, onChanged: onChanged, onSave: onSave, onRetake: onRetake, busy: busy, error: error);
      if (wide) {
        // the whole sheet in view next to the settings: the picture fits the height it is given
        return Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: _SheetPicture(draft: draft, maxHeight: tall - 2 * AppSpace.lg)),
            const SizedBox(width: AppSpace.lg),
            Expanded(flex: 4, child: SingleChildScrollView(child: panel)),
          ]),
        );
      }
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        _SheetPicture(draft: draft, maxHeight: tall * 0.62),
        AppSpace.gapMd,
        panel,
      ]);
    });
  }
}

class _SheetPicture extends StatelessWidget {
  const _SheetPicture({required this.draft, required this.maxHeight});
  final OwnSheetDraft draft;

  /// The card's tallest height: the whole sheet stays in view, the card hugs it.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final aspect = draft.imageW / (draft.imageH == 0 ? 1 : draft.imageH);
    return LayoutBuilder(builder: (context, box) {
      const pad = 2 * AppSpace.xs;
      var w = box.maxWidth - pad;
      var h = w / aspect;
      if (h > maxHeight - pad) {
        h = (maxHeight - pad).clamp(120.0, double.infinity);
        w = h * aspect;
      }
      return AppCard(
        padding: const EdgeInsets.all(AppSpace.xs),
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            width: w,
            height: h,
            child: ClipRRect(
              borderRadius: AppRadius.chipAll,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(color: c.surface),
                if (draft.image != null) Image.memory(draft.image!, fit: BoxFit.fill, gaplessPlayback: true),
                CustomPaint(
                  painter: OwnSheetOverlayPainter(
                    draft: draft,
                    labels: draft.blockLabels,
                    answers: c.primary,
                    identifier: c.purple,
                    ignored: c.textLight,
                    question: c.success,
                    ink: c.surface,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/// Draws what was found on the sheet: answer blocks in the primary colour, the ID block in purple, ignored blocks
/// grey and dashed; each block's question range on a label. Tables: the question cells green, the answer cells blue
/// with the question number.
class OwnSheetOverlayPainter extends CustomPainter {
  OwnSheetOverlayPainter({
    required this.draft,
    required this.labels,
    required this.answers,
    required this.identifier,
    required this.ignored,
    required this.question,
    required this.ink,
  });

  final OwnSheetDraft draft;
  final Map<int, String> labels;
  final Color answers, identifier, ignored, question, ink;

  @override
  void paint(Canvas canvas, Size size) {
    Rect px(Rect r) => Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width, r.height * size.height);
    final scale = size.width / 400;
    if (draft.kind == OwnSheetKind.table) {
      for (final (i, r) in draft.rows.indexed) {
        final q = px(ownSheetRect(r['q']));
        final a = px(ownSheetRect(r['a']));
        canvas.drawRect(q, Paint()..color = question.withValues(alpha: 0.16));
        canvas.drawRect(a, Paint()..color = answers.withValues(alpha: 0.16));
        canvas.drawRect(a, Paint()
          ..color = answers
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
        if (i == 0 || i == draft.rows.length - 1 || i % 5 == 4) _label(canvas, '${r['n']}', a.topRight + Offset(-2 * scale, 1), answers, scale, end: true);
      }
      return;
    }
    final bub = asMap(draft.layout['bubble']);
    final bw = (bub['w'] is num ? (bub['w'] as num).toDouble() : 0.02) * size.width;
    final bh = (bub['h'] is num ? (bub['h'] as num).toDouble() : 0.015) * size.height;
    for (final b in draft.blocks) {
      final role = draft.roleOf(b);
      final col = role == 'identifier' ? identifier : (role == 'ignore' ? ignored : answers);
      final r = px(ownSheetRect(b['box'])).inflate(3);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = col.withValues(alpha: role == 'ignore' ? 0.06 : 0.12));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()
            ..color = col.withValues(alpha: role == 'ignore' ? 0.5 : 0.95)
            ..style = PaintingStyle.stroke
            ..strokeWidth = role == 'ignore' ? 1 : 1.6);
      if (role != 'ignore') {
        final dot = Paint()..color = col.withValues(alpha: 0.45);
        for (final row in (b['cells'] is List ? b['cells'] as List : const [])) {
          for (final p in (row is List ? row : const [])) {
            if (p is List && p.length == 2) {
              final o = Offset((p[0] as num).toDouble() * size.width, (p[1] as num).toDouble() * size.height);
              canvas.drawOval(Rect.fromCenter(center: o, width: bw * 0.36, height: bh * 0.36), dot);
            }
          }
        }
      }
      final text = labels[asInt(b['id'])];
      if (text != null) _label(canvas, text, r.topLeft + Offset(0, -2 * scale), col, scale, above: true);
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color bg, double scale, {bool above = false, bool end = false}) {
    final fs = (9 * scale).clamp(8.0, 14.0);
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: AppFonts.family, fontSize: fs, fontWeight: FontWeight.w700, color: ink)),
      textDirection: AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    final pad = Offset(fs * 0.45, fs * 0.2);
    var o = at;
    if (above) o = Offset(at.dx, at.dy - tp.height - pad.dy * 2);
    if (end) o = Offset(at.dx - tp.width - pad.dx * 2, at.dy);
    if (o.dy < 0) o = Offset(o.dx, 0);
    final rect = Rect.fromLTWH(o.dx, o.dy, tp.width + pad.dx * 2, tp.height + pad.dy * 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(fs * 0.4)), Paint()..color = bg);
    tp.paint(canvas, o + pad);
  }

  @override
  bool shouldRepaint(covariant OwnSheetOverlayPainter old) => true;
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.draft,
    required this.name,
    required this.onChanged,
    required this.onSave,
    required this.onRetake,
    required this.busy,
    this.error,
  });

  final OwnSheetDraft draft;
  final TextEditingController name;
  final VoidCallback onChanged, onSave, onRetake;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final table = draft.kind == OwnSheetKind.table;
    final qs = draft.questions;
    final ok = qs.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ok ? c.success : c.warning, size: 22),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(table ? t('وجدنا جدول إجابات', 'We found an answer table') : t('وجدنا ورقة تظليل', 'We found a bubble sheet'), style: AppType.section(context))),
          ]),
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppTag(omrQuestionsText(qs.length), c.primary, icon: Icons.format_list_numbered_rounded),
            if (draft.options > 0) AppTag(omrOptionsText(draft.options), c.primary, icon: Icons.radio_button_checked_rounded),
            if (!table && draft.idDigits > 0)
              AppTag(t('رقم طالب من ${omrDigitsText(draft.idDigits)}', '${draft.idDigits}-digit student ID'), c.purple, icon: Icons.badge_outlined),
            if (!table && draft.idDigits == 0 && draft.codeKind == 'qr') AppTag(t('رمز QR للطالب', 'Student QR code'), c.purple, icon: Icons.qr_code_2_rounded),
            if (!table && draft.idDigits == 0 && draft.codeKind == 'barcode') AppTag(t('باركود للطالب', 'Student barcode'), c.purple, icon: Icons.barcode_reader),
            if (!table)
              AppTag(draft.shape == 'rect' ? t('فقاعات مستطيلة', 'Square bubbles') : t('فقاعات دائرية', 'Round bubbles'), c.textMedium,
                  icon: draft.shape == 'rect' ? Icons.crop_square_rounded : Icons.circle_outlined),
          ]),
          if (draft.warnings.contains('bubbles_filled_in')) ...[
            AppSpace.gapSm,
            Text(t('بعض الفقاعات مظللة في هذه الصورة؛ أكملنا الشبكة من حولها. تأكد من الأقسام على الصورة.',
                'Some bubbles are shaded in this picture; we completed the grid around them. Check the blocks on the picture.'), style: AppType.meta(context)),
          ],
          if (!table && draft.idDigits == 0 && draft.codeKind == 'none') ...[
            AppSpace.gapSm,
            Text(t('لا يوجد رقم طالب على الورقة: ستختار الطالب لكل ورقة عند المراجعة.', "No student ID on the sheet: you'll pick the student for each paper in review."),
                style: AppType.meta(context)),
          ],
        ]),
      ),
      AppSpace.gapSm,
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: name, label: t('اسم الورقة', 'Sheet name')),
          if (table) ..._tableControls(context) else ..._bubbleControls(context),
        ]),
      ),
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      AppSpace.gapMd,
      AppButton.primary(key: const ValueKey('own.save'), label: t('حفظ واستخدام هذه الورقة', 'Save and use this sheet'), icon: Icons.check_rounded, expand: true, busy: busy, onPressed: ok && !busy ? onSave : null),
      AppSpace.gapXs,
      AppButton.ghost(key: const ValueKey('own.retake'), label: t('جرّب صورة أخرى', 'Try another picture'), icon: Icons.refresh_rounded, expand: true, onPressed: busy ? null : onRetake),
    ]);
  }

  List<Widget> _bubbleControls(BuildContext context) {
    final labels = draft.blockLabels;
    return [
      Text(t('ترقيم الأسئلة', 'Question numbering'), style: AppType.label(context)),
      AppSpace.gapXs,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('العمود الأيسر أولًا', 'Left column first'), selected: !draft.rtl, onTap: () => _set(() => draft.rtl = false)),
        AppChoiceChip(label: t('العمود الأيمن أولًا', 'Right column first'), selected: draft.rtl, onTap: () => _set(() => draft.rtl = true)),
      ]),
      AppSpace.gapXs,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('نزولًا في كل عمود', 'Down each column'), selected: !draft.across, onTap: () => _set(() => draft.across = false)),
        AppChoiceChip(label: t('عبر الصفوف', 'Across the rows'), selected: draft.across, onTap: () => _set(() => draft.across = true)),
      ]),
      AppSpace.gapXs,
      Text(t('الأرقام الملوّنة على الصورة تتبع اختيارك؛ والخيار أ هو أول فقاعة من جهة البداية.',
          'The numbers on the picture follow your choice; option A is the first bubble on that side.'), style: AppType.meta(context)),
      AppSpace.gapSm,
      _StartStepper(value: draft.start, onChanged: (v) => _set(() => draft.start = v)),
      AppSpace.gapMd,
      Text(t('الأقسام على الورقة', 'Blocks on the sheet'), style: AppType.label(context)),
      AppSpace.gapXs,
      for (final b in draft.blocks)
        _BlockRow(
          key: ValueKey('own.block.${b['id']}'),
          title: labels[asInt(b['id'])] ?? t('قسم متجاهَل', 'Ignored block'),
          shape: '${asInt(b['rows'])} × ${asInt(b['cols'])}',
          role: draft.roleOf(b),
          onRole: (r) => _set(() => draft.setRole(asInt(b['id']), r)),
        ),
    ];
  }

  List<Widget> _tableControls(BuildContext context) => [
        Text(t('يكتب الطالب', 'Students write'), style: AppType.label(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(label: t('رقم الإجابة (1، 2، 3)', 'The number (1, 2, 3)'), selected: !draft.letters, onTap: () => _set(() => draft.letters = false)),
          AppChoiceChip(label: t('حرف الإجابة (أ، ب، ج)', 'The letter (A, B, C)'), selected: draft.letters, onTap: () => _set(() => draft.letters = true)),
        ]),
        AppSpace.gapMd,
        Text(t('عدد الخيارات لكل سؤال', 'Options per question'), style: AppType.label(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final n in const [2, 3, 4, 5, 6]) AppChoiceChip(label: '$n', selected: draft.options == n, onTap: () => _set(() => draft.options = n)),
        ]),
        AppSpace.gapSm,
        Text(
            t('أي خانة غير واضحة أو خارج الخيارات تذهب إليك للمراجعة مع صورتها، ولا نخمّن أبدًا.',
                'Any cell that is unclear or not one of the options comes to you for review with its picture: we never guess.'),
            style: AppType.meta(context)),
      ];

  void _set(VoidCallback f) {
    f();
    onChanged();
  }
}

class _StartStepper extends StatelessWidget {
  const _StartStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(t('يبدأ الترقيم من', 'Numbering starts at'), style: AppType.row(context))),
      AppIconButton(icon: Icons.remove_rounded, tooltip: t('أقل', 'Less'), onPressed: value > 1 ? () => onChanged(value - 1) : null),
      SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: AppType.figure(context))),
      AppIconButton(icon: Icons.add_rounded, tooltip: t('أكثر', 'More'), onPressed: value < 999 ? () => onChanged(value + 1) : null),
    ]);
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({super.key, required this.title, required this.shape, required this.role, required this.onRole});
  final String title, shape, role;
  final ValueChanged<String> onRole;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = role == 'identifier' ? c.purple : (role == 'ignore' ? c.textLight : c.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(children: [
        Container(width: 6, height: 40, decoration: BoxDecoration(color: col, borderRadius: AppRadius.chipAll)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(t('$shape فقاعة', '$shape bubbles'), style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        SizedBox(
          width: 150,
          child: AppDropdown<String>(
            value: role,
            items: [
              DropdownMenuItem(value: 'answers', child: Text(t('إجابات', 'Answers'))),
              DropdownMenuItem(value: 'identifier', child: Text(t('رقم الطالب', 'Student ID'))),
              DropdownMenuItem(value: 'ignore', child: Text(t('تجاهُل', 'Ignore'))),
            ],
            onChanged: (v) {
              if (v != null) onRole(v);
            },
          ),
        ),
      ]),
    );
  }
}
