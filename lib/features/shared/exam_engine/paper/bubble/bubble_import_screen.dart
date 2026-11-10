// "Import a new sheet" (D-340): four checked pictures, in order, then the detection reviewed on the sheet itself.
// Each picture is judged by the server the moment it is sent and says how to fix it; the wizard can be left and resumed
// (a draft on the server). Nothing is usable before Confirm detection; a confirmed sheet is in the library for reuse.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show t;
import '../exam_setup.dart' show OmrTemplateItem;
import '../templates/own_sheet.dart' show OwnSheetPicker, defaultOwnSheetPicker, openOwnSheet;
import 'bubble_flow.dart';
import 'bubble_one_photo.dart';
import 'bubble_widgets.dart';

/// Opens the wizard (a new draft, or [resumeId]). The confirmed template id, or null.
Future<int?> openBubbleImport(BuildContext context, {int? orgId, int? resumeId, BubbleApi? api, OwnSheetPicker? picker}) =>
    Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => BubbleImportScreen(orgId: orgId, resumeId: resumeId, api: api, picker: picker)));

/// D-500, the way a teacher adds any sheet: one picture, no corner marks. The saved sheet, ready to pick, or null.
Future<OmrTemplateItem?> openBubbleSheetFinder(BuildContext context, {int? orgId, BubbleApi? api}) async {
  final client = api ?? BubbleApi();
  final id = await openBubbleImport(context, orgId: orgId, api: client);
  if (id == null) return null;
  final r = await client.templates(orgId: orgId);
  if (!r.ok) return null;
  for (final m in (r.map['items'] is List ? r.map['items'] as List : const [])) {
    if (m is Map<String, dynamic> && m['id'] == id) return OmrTemplateItem.fromJson(m);
  }
  return null;
}

class BubbleImportScreen extends StatefulWidget {
  const BubbleImportScreen({super.key, this.orgId, this.resumeId, this.api, this.picker, this.camera});
  final int? orgId, resumeId;
  final BubbleApi? api;
  final OwnSheetPicker? picker;

  /// Offer "Take a photo" (default: on phones).
  final bool? camera;

  @override
  State<BubbleImportScreen> createState() => _BubbleImportScreenState();
}

class _BubbleImportScreenState extends State<BubbleImportScreen> {
  late final BubbleApi _api = widget.api ?? BubbleApi();
  final _note = TextEditingController();
  final _name = TextEditingController();
  BubbleImport? _data;
  final Map<BubbleStep, Uint8List> _previews = {};
  Uint8List? _sheet;
  BubbleStep _step = BubbleStep.question;
  bool _busy = false;
  String? _error;
  bool _loading = true;
  BubbleTapMode? _mode;
  final List<BubbleTap> _taps = [];
  BubbleBlock? _picked;

  /// One picture (D-500) for anything new; an older four-picture draft finishes the way it began.
  bool get _onePhoto => widget.resumeId == null || (_data?.onePhoto ?? false);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _note.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final r = widget.resumeId != null ? await _api.getImport(widget.resumeId!) : await _api.createImport(orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _apply(BubbleImport.fromJson(r.map));
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (_data != null && _data!.detected) await _loadSheet();
    if (_data != null && !_data!.detected && widget.resumeId != null) await _loadPreviews();
  }

  void _apply(BubbleImport d) {
    _data = d;
    if (d.name != null && _name.text.isEmpty) _name.text = d.name!;
    final nextName = d.nextStep;
    if (nextName != null) _step = BubbleStep.values.byName(nextName);
    _taps.clear();
  }

  Future<void> _loadPreviews() async {
    final d = _data;
    if (d == null) return;
    for (final s in BubbleStep.values) {
      if (d.steps[s.wire]?.ok ?? false) {
        final b = await _api.sheetImage(d.id, s.wire);
        if (!mounted) return;
        if (b != null) setState(() => _previews[s] = b);
      }
    }
  }

  Future<void> _loadSheet() async {
    final d = _data;
    if (d == null) return;
    final b = await _api.sheetImage(d.id, 'sheet');
    if (mounted) setState(() => _sheet = b);
  }

  Future<void> _pick({required bool camera}) async {
    final f = await (widget.picker ?? defaultOwnSheetPicker)(camera: camera);
    if (f == null || !mounted) return;
    if (_onePhoto) {
      await _sendSheet(f.$1, f.$2);
    } else {
      await _send(f.$1, f.$2);
    }
  }

  void _defaultName(BubbleImport d) {
    if (_name.text.isEmpty && d.questions > 0) _name.text = t('ورقة ${d.questions} سؤال', 'Sheet of ${d.questions} questions');
  }

  Future<void> _sendSheet(String name, Uint8List bytes) async {
    final d = _data;
    if (d == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _sheet = null;
      _picked = null;
      _mode = null;
    });
    final r = await _api.sendSheet(d.id, (name, bytes));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        final next = BubbleImport.fromJson(r.map);
        _data = next;
        _defaultName(next);
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (r.ok && _data!.detected) await _loadSheet();
  }

  /// A one-tap fix: applied at once, the sheet redrawn.
  Future<void> _fix({List<BubbleTap> taps = const [], Map<String, dynamic>? set}) async {
    final d = _data;
    if (d == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.quickFix(d.id, taps: taps, set: set);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _data = BubbleImport.fromJson(r.map);
        _picked = null;
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (r.ok) await _loadSheet();
  }

  void _tapResult(Offset o) {
    final m = _mode;
    final d = _data;
    if (m == null || d == null) return;
    if (m == BubbleTapMode.fixOptions) {
      final hit = d.blocks.where((b) => b.role == 'answers' && b.box.length == 4 && o.dx >= b.box[0] && o.dx <= b.box[0] + b.box[2] && o.dy >= b.box[1] && o.dy <= b.box[1] + b.box[3]);
      setState(() => _picked = hit.isEmpty ? null : hit.first);
      return;
    }
    setState(() => _mode = null);
    _fix(taps: [BubbleTap(m, o.dx, o.dy)]);
  }

  Future<void> _written() async {
    final made = await openOwnSheet(context, orgId: widget.orgId);
    if (made != null && mounted) Navigator.of(context).pop(made.id);
  }

  void _retake() => setState(() {
        _data = BubbleImport.fromJson({'id': _data!.id, 'one_photo': true});
        _sheet = null;
        _mode = null;
        _picked = null;
        _name.clear();
      });

  Future<void> _crop() async {
    final raw = _previews[_step];
    if (raw == null) return;
    final bytes = await showAppImageCropper(context, raw, shape: CropShape.square, allowOriginal: false, allowBackground: false);
    if (bytes == null || !mounted) return;
    await _send('crop.png', bytes);
  }

  Future<void> _send(String name, Uint8List bytes) async {
    final d = _data;
    if (d == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _previews[_step] = bytes;
    });
    final r = await _api.sendStep(d.id, _step, (name, bytes));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        final next = BubbleImport.fromJson(r.map);
        _data = next;
        if (next.detected) _sheet = null;
      } else {
        _error = bubbleErrorText(r);
      }
    });
  }

  Future<void> _continue() async {
    final d = _data;
    if (d == null) return;
    final i = BubbleStep.values.indexOf(_step);
    if (i < BubbleStep.values.length - 1) {
      setState(() => _step = BubbleStep.values[i + 1]);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.detect(d.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _apply(BubbleImport.fromJson(r.map));
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (r.ok) await _loadSheet();
  }

  Future<void> _reDetect() async {
    final d = _data;
    if (d == null || (_taps.isEmpty && _note.text.trim().isEmpty)) {
      setState(() => _error = t('انقر على الورقة أو اكتب ملاحظة أولًا', 'Tap the sheet or write a note first'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.feedback(d.id, taps: List.of(_taps), note: _note.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _note.clear();
        _mode = null;
        _apply(BubbleImport.fromJson(r.map));
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (r.ok) await _loadSheet();
  }

  Future<void> _shape(String shape) async {
    final d = _data;
    if (d == null || d.shape == shape) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.feedback(d.id, shape: shape);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _apply(BubbleImport.fromJson(r.map));
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (r.ok) await _loadSheet();
  }

  Future<void> _undo() async {
    final d = _data;
    if (d == null) return;
    setState(() => _busy = true);
    final r = await _api.undo(d.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _apply(BubbleImport.fromJson(r.map));
      } else {
        _error = bubbleErrorText(r);
      }
    });
    if (r.ok) await _loadSheet();
  }

  Future<void> _confirm() async {
    final d = _data;
    if (d == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = t('اكتب اسمًا للورقة', 'Give the sheet a name'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.confirm(d.id, name);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = bubbleErrorText(r);
      });
      return;
    }
    Navigator.of(context).pop(BubbleImport.fromJson(r.map).templateId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _data;
    final Widget body;
    if (_loading) {
      body = const AppListSkeleton(items: 4, withAvatar: false);
    } else if (d == null) {
      body = AppEmpty(icon: Icons.document_scanner_rounded, title: _error ?? t('تعذّر بدء الاستيراد', "Couldn't start the import"));
    } else if (_onePhoto) {
      body = LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final child = d.detected
            ? BubbleResultPanel(
                data: d,
                image: _sheet,
                wide: wide,
                mode: _mode,
                busy: _busy,
                error: _error,
                name: _name,
                selectedBlock: _picked,
                onMode: (m) => setState(() {
                  _mode = m;
                  _picked = null;
                }),
                onTapSheet: _tapResult,
                onIdBox: (r) {
                  setState(() => _mode = null);
                  _fix(set: {
                    'id_box': {'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height}
                  });
                },
                onRotate: () => _fix(set: {'rotate': 90}),
                onDirection: () => _fix(set: {'direction': d.isRtl ? 'ltr' : 'rtl'}),
                onOrder: () => _fix(set: {'order': d.isAcross ? 'down' : 'across'}),
                onBlockOptions: (b, n) => _fix(set: {
                  'block_options': {'block': b.id, 'value': n}
                }),
                onUndo: _undo,
                onRetake: _retake,
                onConfirm: _confirm,
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: BubbleCaptureCard(
                    busy: _busy,
                    error: _error,
                    issues: d.issues,
                    onCamera: (widget.camera ?? _phoneLike(context)) ? () => _pick(camera: true) : null,
                    onFiles: () => _pick(camera: false),
                    onWrittenTable: _written,
                  ),
                ),
              );
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? AppSpace.lg : AppSpace.md),
          child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.wide.max), child: child)),
        );
      });
    } else if (d.detected) {
      body = LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? AppSpace.lg : AppSpace.md),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t('راجع ما اكتشفناه', 'Check what was detected'), style: AppType.headline(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(t('كل منطقة ملوّنة حسب نوعها. كرّر حتى تصبح صحيحة، ثم أكّد.', 'Each region is coloured by what it is. Repeat until it\'s right, then confirm.'), style: AppType.body(context).copyWith(color: c.textMedium)),
                const SizedBox(height: AppSpace.md),
                BubbleReviewPanel(
                  data: d,
                  image: _sheet,
                  wide: wide,
                  tapMode: _mode,
                  taps: _taps,
                  busy: _busy,
                  error: _error,
                  name: _name,
                  note: _note,
                  onMode: (m) => setState(() => _mode = m),
                  onTapSheet: (o) => setState(() => _taps.add(BubbleTap(_mode!, o.dx, o.dy))),
                  onRemoveTaps: () => setState(_taps.clear),
                  onShape: _shape,
                  onDetect: _reDetect,
                  onUndo: _undo,
                  onConfirm: _confirm,
                ),
              ]),
            ),
          ),
        );
      });
    } else {
      final done = {for (final s in BubbleStep.values) if (d.steps[s.wire]?.ok ?? false) s};
      body = LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final card = AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: BubbleStepCard(
            step: _step,
            result: d.steps[_step.wire],
            preview: _previews[_step],
            busy: _busy,
            error: _error,
            onCamera: (widget.camera ?? _phoneLike(context)) ? () => _pick(camera: true) : null,
            onFiles: () => _pick(camera: false),
            onCrop: _step == BubbleStep.question || _step == BubbleStep.identifier ? _crop : null,
            onContinue: _continue,
          ),
        );
        final guide = AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: BubbleStepIllustration(step: _step)),
            const SizedBox(height: AppSpace.md),
            Text(t('لماذا نحتاج هذه الصور؟', 'Why these pictures?'), style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(t('الفارغة تعطينا مكان كل فقاعة، والمظلّلة تعلّمنا شكل التظليل. لن نخمّن أبدًا: أي شك يأتيك للمراجعة.', 'The empty sheet gives us where every bubble is, the filled one how a mark looks. We never guess: anything unsure comes to you.'), style: AppType.body(context).copyWith(color: c.textMedium)),
          ]),
        );
        final progress = BubbleWizardProgress(current: _step, done: done, onTap: (s) {
          if (BubbleStep.values.indexOf(s) <= (d.doneSteps.length).clamp(0, 3)) setState(() => _step = s);
        });
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? AppSpace.lg : AppSpace.md),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.content.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                progress,
                const SizedBox(height: AppSpace.md),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: card), const SizedBox(width: AppSpace.md), Expanded(flex: 2, child: guide)])
                else
                  card,
              ]),
            ),
          ),
        );
      });
    }
    return BasePage(
      key: const ValueKey(kBubbleTeachFeature),
      appBar: ScreenAppBar(title: t('إضافة ورقة إجابة', 'Add an answer sheet')),
      child: body,
    );
  }

  bool _phoneLike(BuildContext context) => MediaQuery.of(context).size.width < 900;
}
