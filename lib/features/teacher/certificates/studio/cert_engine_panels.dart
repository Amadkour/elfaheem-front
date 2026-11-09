// features/teacher/certificates/studio/cert_engine_panels.dart
//
// The certificate studio's dialogs and sheets: the starters gallery, the page settings, the languages, how a missing
// language starts, the save conflict, the draft prompt, a custom variable and the server preview. Plain values in,
// plain values out: nothing here reads a provider.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../design/app_kit.dart';
import '../../../../design/app_notice.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/export_layout/layout_element_view.dart' show layoutColor, layoutHex;
import '../../../../design/export_layout/layout_model.dart';
import '../../../../design/studio/studio.dart';
import '../../../admin/admin_common.dart' show t;
import 'cert_engine_api.dart';
import 'cert_engine_inspector.dart' show CertColorWell, CertInspectorSection;
import 'cert_engine_presets.dart';

export 'cert_template_gallery.dart' show CertGalleryPick, CertTemplatePreviewCache, showCertGallery;

/// The theme colour as "#RRGGBB" (the legacy wizard's default).
String certThemeHex(BuildContext context) => layoutHex(context.colors.primary);

/// The swatches of the colour pickers: the app's theme colour first, then the generator's palette.
List<Color> certSwatches(BuildContext context) => [context.colors.primary, for (final h in kCertGenColors) layoutColor(h)!];

/// A theme colour field: swatches + a hex box for a custom colour. Plain values in, plain values out.
class CertThemeColorField extends StatelessWidget {
  const CertThemeColorField({super.key, required this.hex, required this.onChanged, this.label});
  final String hex;
  final String? label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => StudioColorField(
        value: layoutColor(hex),
        label: label,
        swatches: certSwatches(context),
        onChanged: (c) {
          if (c != null) onChanged(layoutHex(c));
        },
      );
}

// ── how a language starts ────────────────────────────────────────────────────────────────────────────────────────

enum CertStart { mirror, blank, starter }

/// A language has no design yet: never an implicit fallback — the person picks how it starts. Null = cancel.
Future<CertStart?> showCertStartChoice(BuildContext context, {required String lang, required bool canMirror}) {
  final name = lang == 'ar' ? t('العربي', 'Arabic') : t('الإنجليزي', 'English');
  final from = lang == 'ar' ? t('الإنجليزي', 'English') : t('العربي', 'Arabic');
  return showAppSheet<CertStart>(
    context,
    (ctx) => AppSheetContent(
      title: t('كيف يبدأ التصميم $name؟', 'How should the $name design start?'),
      children: [
        if (canMirror)
          _Choice(
            icon: Icons.flip_rounded,
            title: t('نسخة معكوسة من التصميم $from', 'A mirrored copy of the $from design'),
            sub: t('نفس العناصر مع قلب المواضع واتجاه الكتابة', 'The same elements with the places and the direction flipped'),
            onTap: () => Navigator.pop(ctx, CertStart.mirror),
          ),
        _Choice(
          icon: Icons.dashboard_customize_outlined,
          title: t('من تصميم جاهز', 'From a ready design'),
          sub: t('اختر من المعرض', 'Pick one from the gallery'),
          onTap: () => Navigator.pop(ctx, CertStart.starter),
        ),
        _Choice(
          icon: Icons.crop_landscape_rounded,
          title: t('صفحة فارغة', 'A blank page'),
          sub: t('ابدأ من الصفر', 'Start from scratch'),
          onTap: () => Navigator.pop(ctx, CertStart.blank),
        ),
      ],
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      minTileHeight: AppTouch.min,
      leading: Icon(icon, color: c.primary),
      title: Text(title, style: appText(14.5, w: FontWeight.w600, c: c.textDark)),
      subtitle: Text(sub, style: appText(12.5, c: c.textMedium)),
      onTap: onTap,
    );
  }
}

// ── languages ────────────────────────────────────────────────────────────────────────────────────────────────────

/// 'ar' | 'en' | 'both' (null = closed).
Future<String?> showCertLanguagesSheet(BuildContext context, String current) => showAppSheet<String>(
      context,
      (ctx) => AppSheetContent(
        title: t('لغات الشهادة', 'Certificate languages'),
        children: [
          for (final (k, ar, en) in const [('ar', 'العربية فقط', 'Arabic only'), ('en', 'الإنجليزية فقط', 'English only'), ('both', 'العربية والإنجليزية', 'Arabic and English')])
            ListTile(
              minTileHeight: AppTouch.min,
              leading: Icon(current == k ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: ctx.colors.primary),
              title: Text(t(ar, en), style: appText(14.5, w: FontWeight.w600, c: ctx.colors.textDark)),
              onTap: () => Navigator.pop(ctx, k),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.xs),
            child: Text(
              t('لكل لغة تصميمها الخاص: تعديل أحدهما لا يمسّ الآخر.', 'Each language has its own design: editing one never touches the other.'),
              style: appText(12.5, c: ctx.colors.textMedium),
            ),
          ),
        ],
      ),
    );

// ── page ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/// The page of one design: size, orientation, colour, background image. [onChanged] runs after every change (the
/// studio redraws and marks the design unsaved); [pickBackground] picks + uploads and returns the URL.
Future<void> showCertPageSheet(
  BuildContext context, {
  required LayoutDesign design,
  required VoidCallback onChanged,
  required Future<String?> Function() pickBackground,
  Future<String?> Function(String style, String color, bool dark)? generateBackground,
}) =>
    showAppSheet<void>(context, (ctx) => _PageSheet(design: design, onChanged: onChanged, pickBackground: pickBackground, generateBackground: generateBackground));

class _PageSheet extends StatefulWidget {
  const _PageSheet({required this.design, required this.onChanged, required this.pickBackground, this.generateBackground});
  final LayoutDesign design;
  final VoidCallback onChanged;
  final Future<String?> Function() pickBackground;
  final Future<String?> Function(String style, String color, bool dark)? generateBackground;

  @override
  State<_PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<_PageSheet> {
  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('الصفحة', 'Page'),
        children: [
          CertPageControls(design: widget.design, onChanged: widget.onChanged, pickBackground: widget.pickBackground, generateBackground: widget.generateBackground, memory: const {}, framed: false),
        ],
      );
}

/// The page of one design: size, orientation, colour, background image, a generated background. The inspector's
/// "nothing selected" state and the page sheet draw this one. [onChanged] runs after every change (the studio redraws
/// and marks the design unsaved); [pickBackground] picks + uploads and returns the URL.
class CertPageControls extends StatefulWidget {
  const CertPageControls({super.key, required this.design, required this.onChanged, required this.pickBackground, this.generateBackground, required this.memory, this.framed = true, this.templateColours});
  final LayoutDesign design;
  final VoidCallback onChanged;
  final Future<String?> Function() pickBackground;
  final Future<String?> Function(String style, String color, bool dark)? generateBackground;

  /// Which sections are open.
  final Map<String, bool> memory;

  /// In the inspector (a scrolling list with folding sections); false = inside a sheet that scrolls itself.
  final bool framed;

  /// The "Template colours" section, when this page was made from a template (D-401).
  final Widget? templateColours;

  @override
  State<CertPageControls> createState() => _CertPageControlsState();
}

class _CertPageControlsState extends State<CertPageControls> {
  LayoutPage get p => widget.design.page;
  bool _generating = false;
  String _style = 'classic';
  /// Null = the app's theme colour (the legacy wizard's default).
  String? _color;
  bool _dark = false;
  late final Map<String, bool> _memory = widget.framed ? widget.memory : <String, bool>{};

  Future<void> _generate() async {
    setState(() => _generating = true);
    final url = await widget.generateBackground!(_style, _color ?? certThemeHex(context), _dark);
    if (!mounted) return;
    setState(() => _generating = false);
    if (url != null) _plain(() => p.backgroundImage = url);
  }

  /// Changes the page and keeps the elements at their relative places.
  void _page(VoidCallback mutate) {
    final ow = p.contentWidth, oh = p.contentHeight;
    setState(mutate);
    certRescaleElements(widget.design, ow, oh);
    widget.onChanged();
  }

  void _plain(VoidCallback mutate) {
    setState(mutate);
    widget.onChanged();
  }

  CertInspectorSection _section(String id, String title, List<Widget> children, {bool open = true, bool first = false}) =>
      CertInspectorSection(id: id, title: title, memory: _memory, initiallyOpen: open, first: first, children: children);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = StudioPropField(
      label: t('المقاس', 'Size'),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final s in const ['A4', 'A3', 'A5', 'Letter', 'custom'])
          ChoiceChip(
            label: Text(s == 'custom' ? t('مخصص', 'Custom') : s),
            selected: p.size == s,
            onSelected: (_) => _page(() => p.size = s),
          ),
      ]),
    );
    final orientation = StudioSegmented<bool>(
      segments: [
        StudioSegment(value: true, label: t('أفقي', 'Landscape'), icon: Icons.crop_landscape_rounded),
        StudioSegment(value: false, label: t('عمودي', 'Portrait'), icon: Icons.crop_portrait_rounded),
      ],
      value: p.landscape,
      onChanged: (v) => _page(() => p.orientation = v ? 'landscape' : 'portrait'),
    );
    final background = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.wallpaper_rounded),
            label: Text(p.backgroundImage == null ? t('اختيار صورة', 'Choose an image') : t('تغيير الصورة', 'Change the image')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
            onPressed: () async {
              final url = await widget.pickBackground();
              if (url != null) _plain(() => p.backgroundImage = url);
            },
          ),
        ),
        if (p.backgroundImage != null)
          IconButton(
            tooltip: t('إزالة', 'Remove'),
            icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            onPressed: () => _plain(() => p.backgroundImage = null),
          ),
      ]),
      if (p.backgroundImage != null) ...[
        const SizedBox(height: AppSpace.xs),
        StudioSegmented<String>(
          segments: [StudioSegment(value: 'cover', label: t('ملء', 'Cover')), StudioSegment(value: 'contain', label: t('احتواء', 'Contain')), StudioSegment(value: 'fill', label: t('تمديد', 'Stretch'))],
          value: p.backgroundFit,
          onChanged: (k) => _plain(() => p.backgroundFit = k),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(t('تظهر صورة الخلفية في المعاينة وفي الملف النهائي.', 'The background image shows in the preview and in the final file.'), style: appText(12, c: c.textMedium)),
      ],
    ]);
    final generator = [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final (k, ar, en) in const [('classic', 'كلاسيكي', 'Classic'), ('modern', 'عصري', 'Modern'), ('dark', 'داكن', 'Dark')])
          ChoiceChip(key: ValueKey('cert-gen-$k'), label: Text(t(ar, en)), selected: _style == k, onSelected: (_) => setState(() => _style = k)),
      ]),
      CertThemeColorField(label: t('لون السمة', 'Theme colour'), hex: _color ?? certThemeHex(context), onChanged: (h) => setState(() => _color = h)),
      AppSwitchTile(
        key: const ValueKey('cert-gen-dark'),
        title: t('ألوان داكنة', 'Dark colours'),
        subtitle: t('خلفية بدرجات داكنة بدل الفاتحة.', 'A background in dark tones instead of light ones.'),
        value: _dark,
        onChanged: (v) => setState(() => _dark = v),
      ),
      FilledButton.icon(
        key: const ValueKey('cert-gen-go'),
        onPressed: _generating ? null : _generate,
        icon: _generating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
        label: Text(t('إنشاء', 'Generate')),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
      Text(t('تُطبَّق على لغة هذا التبويب فقط.', 'Applied to the language of this tab only.'), style: appText(12, c: c.textMedium)),
    ];
    final sections = <Widget>[
      _section('page', t('الورقة', 'Paper'), [
        size,
        if (p.size == 'custom')
          Row(children: [
            Expanded(child: StudioStepper(label: t('العرض (مم)', 'Width (mm)'), value: p.customWidth, min: 60, max: 600, step: 5, onChanged: (v) => _page(() => p.customWidth = v))),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: StudioStepper(label: t('الارتفاع (مم)', 'Height (mm)'), value: p.customHeight, min: 60, max: 600, step: 5, onChanged: (v) => _page(() => p.customHeight = v))),
          ]),
        orientation,
      ], first: true),
      if (widget.templateColours != null) _section('template', t('ألوان القالب', 'Template colours'), [widget.templateColours!]),
      _section('colour', t('اللون', 'Colour'), [
        CertColorWell(
          label: t('لون الصفحة', 'Page colour'),
          value: layoutColor(p.background),
          allowNone: true,
          onChanged: (col) => _plain(() => p.background = col == null ? null : layoutHex(col)),
        ),
      ]),
      _section('background', t('صورة الخلفية', 'Background image'), [background]),
      if (widget.generateBackground != null) _section('generate', t('إنشاء خلفية', 'Generate a background'), generator, open: !widget.framed),
    ];
    if (!widget.framed) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections);
    return ListView(padding: const EdgeInsets.only(bottom: AppSpace.lg), children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
        child: Text(t('الصفحة', 'Page'), style: AppType.row(context)),
      ),
      ...sections,
    ]);
  }
}

/// The colours the background generator offers.
const kCertGenColors = ['#1F4E8C', '#0F766E', '#7C3AED', '#B45309', '#BE123C', '#374151'];

/// A dialog that owns its text controller: disposed with the dialog's state, after the exit animation — never on the
/// dialog's future (the closing dialog still draws its field one more frame).
class _ControllerDialog extends StatefulWidget {
  const _ControllerDialog({required this.initial, required this.builder});
  final String initial;
  final Widget Function(BuildContext context, TextEditingController ctl, StateSetter setState) builder;

  @override
  State<_ControllerDialog> createState() => _ControllerDialogState();
}

class _ControllerDialogState extends State<_ControllerDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ctl, setState);
}

/// The new name of the design (null = cancelled).
Future<String?> showCertRenameDialog(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _ControllerDialog(
      initial: current,
      builder: (ctx, ctl, setState) => AlertDialog(
        title: Text(t('إعادة تسمية التصميم', 'Rename the design')),
        content: TextField(
          key: const ValueKey('cert-rename-field'),
          controller: ctl,
          autofocus: true,
          maxLength: 120,
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(key: const ValueKey('cert-rename-ok'), onPressed: ctl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, ctl.text.trim()), child: Text(t('حفظ', 'Save'))),
        ],
      ),
    ),
  );
}

/// Clean a signature again: ink colour (null = keep the original ink) and strength. Null = cancelled.
/// [fromSaved]: the original photo is not at hand, so it works on the cleaned image saved in the design.
Future<({String? ink, double strength})?> showCertSignatureClean(BuildContext context, {bool fromSaved = false}) => showAppSheet<({String? ink, double strength})>(
      context,
      (ctx) => _SigCleanSheet(fromSaved: fromSaved),
    );

class _SigCleanSheet extends StatefulWidget {
  const _SigCleanSheet({required this.fromSaved});
  final bool fromSaved;

  @override
  State<_SigCleanSheet> createState() => _SigCleanSheetState();
}

class _SigCleanSheetState extends State<_SigCleanSheet> {
  String? _ink = '#000000';
  double _strength = .5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: t('تنظيف التوقيع', 'Clean the signature'),
      children: [
        StudioPropField(
          label: t('لون الحبر', 'Ink colour'),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final (v, ar, en) in const [(null, 'الأصلي', 'Original'), ('#000000', 'أسود', 'Black'), ('#1F3A8A', 'أزرق داكن', 'Dark blue'), ('#374151', 'رمادي', 'Grey')])
              ChoiceChip(key: ValueKey('cert-ink-${v ?? 'none'}'), label: Text(t(ar, en)), selected: _ink == v, onSelected: (_) => setState(() => _ink = v)),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        StudioPropField(
          label: t('قوة إزالة الخلفية', 'Background removal strength'),
          child: Slider(value: _strength, onChanged: (v) => setState(() => _strength = v)),
        ),
        Text(
          widget.fromSaved
              ? t('الخادم يحتفظ بالصورة المنظَّفة فقط، فتُعاد المعالجة من الصورة المحفوظة في التصميم (وهي منظَّفة أصلًا).', 'The server keeps only the cleaned image, so this works on the image saved in the design (already cleaned).')
              : t('تُعاد المعالجة من الصورة التي رفعتها في هذه الجلسة.', 'It is processed again from the photo you uploaded in this session.'),
          key: const ValueKey('cert-sig-hint'),
          style: appText(12, c: c.textMedium),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton(
          key: const ValueKey('cert-ink-go'),
          onPressed: () => Navigator.pop(context, (ink: _ink, strength: _strength)),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          child: Text(t('تطبيق', 'Apply')),
        ),
      ],
    );
  }
}

// ── conflicts, drafts, variables ─────────────────────────────────────────────────────────────────────────────────

enum CertConflictChoice { reload, keepMine }

Future<CertConflictChoice?> showCertConflictDialog(BuildContext context) => showDialog<CertConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.sync_problem_rounded, color: ctx.colors.warning),
        title: Text(t('حُفظ هذا التصميم في مكان آخر', 'This design was saved elsewhere meanwhile')),
        content: Text(t(
          'عُدّل التصميم من تبويب أو جهاز آخر. يمكنك تحميل النسخة المحفوظة (وتجاهل تعديلاتك)، أو الإبقاء على تعديلاتك وحفظها فوقها.',
          'It was changed from another tab or device. Reload the saved copy (your edits are discarded), or keep your edits and save them over it.',
        )),
        actions: [
          TextButton(key: const ValueKey('cert-conflict-cancel'), onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
          TextButton(key: const ValueKey('cert-conflict-reload'), onPressed: () => Navigator.pop(ctx, CertConflictChoice.reload), child: Text(t('تحميل (تجاهل تعديلاتي)', 'Reload (discard mine)'))),
          FilledButton(key: const ValueKey('cert-conflict-keep'), onPressed: () => Navigator.pop(ctx, CertConflictChoice.keepMine), child: Text(t('الإبقاء على تعديلاتي', 'Keep mine'))),
        ],
      ),
    );

/// True = restore the draft, false = discard it, null = decide later (kept).
Future<bool?> showCertDraftPrompt(BuildContext context, {required bool outdated}) => showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.restore_page_outlined, color: ctx.colors.primary),
        title: Text(t('تعديلات غير محفوظة على هذا الجهاز', 'Unsaved edits on this device')),
        content: Text(outdated
            ? t('وجدنا مسودة قديمة لهذا التصميم، وقد حُفظ التصميم بعدها في مكان آخر. استعادتها ستكتب فوق النسخة المحفوظة عند الحفظ.',
                'We found an older draft of this design, and it was saved elsewhere since. Restoring it overwrites the saved copy when you save.')
            : t('وجدنا مسودة بتعديلاتك الأخيرة لم تُحفظ. هل تريد استعادتها؟', 'We found a draft with your last edits that was never saved. Restore it?')),
        actions: [
          TextButton(key: const ValueKey('cert-draft-later'), onPressed: () => Navigator.pop(ctx), child: Text(t('لاحقًا', 'Later'))),
          TextButton(key: const ValueKey('cert-draft-discard'), onPressed: () => Navigator.pop(ctx, false), child: Text(t('تجاهل المسودة', 'Discard the draft'))),
          FilledButton(key: const ValueKey('cert-draft-restore'), onPressed: () => Navigator.pop(ctx, true), child: Text(t('استعادة', 'Restore'))),
        ],
      ),
    );

/// Unsaved edits on leaving: 'save' | 'discard' | null (stay).
Future<String?> showCertLeaveDialog(BuildContext context) => showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('تعديلات غير محفوظة', 'Unsaved changes')),
        content: Text(t('تُحفظ مسودتك على هذا الجهاز، لكن الشهادات لن تتغيّر قبل الحفظ.', 'Your draft stays on this device, but issued certificates do not change until you save.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('البقاء', 'Stay'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(t('خروج دون حفظ', 'Leave without saving'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t('حفظ وخروج', 'Save and leave'))),
        ],
      ),
    );

/// A new custom variable: its key (validated), null when cancelled.
Future<String?> showCertVariableDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _ControllerDialog(
      initial: '',
      builder: (ctx, ctl, setState) => AlertDialog(
        title: Text(t('متغيّر جديد', 'New variable')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctl,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: 'honors_level', errorText: ctl.text.isEmpty ? null : certCustomKeyError(ctl.text.trim())),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(t('قيمته تأتي مع كل شهادة تُصدَر (مثل {{honors_level}}).', 'Its value comes with each certificate you issue (like {{honors_level}}).'), style: appText(12.5, c: ctx.colors.textMedium)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: certCustomKeyError(ctl.text.trim()) == null ? () => Navigator.pop(ctx, ctl.text.trim()) : null, child: Text(t('إضافة', 'Add'))),
        ],
      ),
    ),
  );
}

// ── preview ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The server preview of the design: one page per language, fetched through [fetch] (the studio caches by document).
Future<void> showCertPreview(
  BuildContext context, {
  required List<String> languages,
  required String initial,
  required Future<Uint8List> Function(String lang) fetch,
  List<String> customKeys = const [],
  Map<String, String> samples = const {},
  ValueChanged<Map<String, String>>? onSamples,
}) =>
    showDialog<void>(context: context, builder: (_) => _PreviewDialog(languages: languages, initial: initial, fetch: fetch, customKeys: customKeys, samples: samples, onSamples: onSamples));

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.languages, required this.initial, required this.fetch, this.customKeys = const [], this.samples = const {}, this.onSamples});
  final List<String> languages;
  final String initial;
  final Future<Uint8List> Function(String lang) fetch;
  final List<String> customKeys;
  final Map<String, String> samples;
  final ValueChanged<Map<String, String>>? onSamples;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late String _lang = widget.initial;
  late Future<Uint8List> _png = widget.fetch(_lang);
  late final Map<String, TextEditingController> _ctls = {
    for (final k in widget.customKeys) k: TextEditingController(text: widget.samples[k] ?? ''),
  };

  @override
  void dispose() {
    for (final c in _ctls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    widget.onSamples?.call({
      for (final e in _ctls.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    });
    _pick(_lang);
  }

  void _pick(String l) => setState(() {
        _lang = l;
        _png = widget.fetch(l);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final desk = Color.alphaBlend(c.textDark.withValues(alpha: c.isDark ? .03 : .07), c.background);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.sm),
      backgroundColor: desk,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 780),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xxs, 0),
            child: Row(children: [
              Expanded(child: Text(t('معاينة', 'Preview'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w600, c: c.textDark))),
              if (widget.languages.length > 1)
                for (final l in widget.languages)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs),
                    child: ChoiceChip(label: Text(l == 'ar' ? t('العربية', 'Arabic') : 'English'), selected: _lang == l, onSelected: (_) => _pick(l)),
                  ),
              IconButton(tooltip: t('إغلاق', 'Close'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(
            child: FutureBuilder<Uint8List>(
              future: _png,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(ApiMessage.of(snap.error), textAlign: TextAlign.center, style: appText(13.5, c: c.danger)),
                      const SizedBox(height: AppSpace.sm),
                      OutlinedButton(onPressed: () => _pick(_lang), child: Text(t('إعادة المحاولة', 'Retry'))),
                    ]),
                  );
                }
                return CertDeskPreview(png: snap.data);
              },
            ),
          ),
          if (_ctls.isNotEmpty)
            ExpansionTile(
              key: const ValueKey('cert-sample-values'),
              title: Text(t('قيم المتغيّرات التجريبية', 'Sample values of the variables'), style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
              childrenPadding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(children: [
                      for (final e in _ctls.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.xs),
                          child: TextField(
                            key: ValueKey('cert-sample-${e.key}'),
                            controller: e.value,
                            decoration: InputDecoration(labelText: e.key, isDense: true),
                            onSubmitted: (_) => _apply(),
                          ),
                        ),
                    ]),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(key: const ValueKey('cert-sample-apply'), onPressed: _apply, child: Text(t('تحديث المعاينة', 'Refresh the preview'))),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.xs),
            child: Text(t('بقيم تجريبية — لا يُحفظ شيء.', 'With sample values — nothing is saved.'), style: appText(12, c: c.textMedium)),
          ),
        ]),
      ),
    );
  }
}

/// The certificate as it will look: a sheet lying on a desk, lit from above, with a real shadow under it. [png] null
/// draws the sheet's outline while the server renders it.
class CertDeskPreview extends StatelessWidget {
  const CertDeskPreview({super.key, required this.png});
  final Uint8List? png;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final png = this.png;
    final shadow = [
      ...AppElevation.of(context, 4),
      BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? .5 : .22), blurRadius: 3, offset: const Offset(0, 1)),
    ];
    final sheet = png == null
        ? AspectRatio(
            aspectRatio: 1.414,
            child: Container(
              key: const ValueKey('cert-preview-skeleton'),
              decoration: BoxDecoration(color: c.cardBg, boxShadow: shadow),
              padding: const EdgeInsets.all(AppSpace.md),
              child: const AppShimmer(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppSkeletonBox(width: 240, height: 22),
                    SizedBox(height: AppSpace.lg),
                    AppSkeletonBox(width: 300, height: 30),
                    SizedBox(height: AppSpace.lg),
                    AppSkeletonBox(width: 320, height: 12),
                    SizedBox(height: AppSpace.xs),
                    AppSkeletonBox(width: 260, height: 12),
                  ]),
                ),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(boxShadow: shadow),
            child: Image.memory(png, fit: BoxFit.contain, cacheWidth: 1400, gaplessPlayback: true),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        // the light falls from the top of the desk
        gradient: RadialGradient(
          center: const Alignment(0, -1.1),
          radius: 1.5,
          colors: [c.cardBg.withValues(alpha: c.isDark ? .35 : .7), c.cardBg.withValues(alpha: 0)],
        ),
      ),
      child: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xl),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(png == null),
              tween: Tween(begin: motion.off ? 1 : .985, end: 1),
              duration: motion.slow,
              curve: AppMotion.curve,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: sheet,
            ),
          ),
        ),
      ),
    );
  }
}

/// The user-facing text of a failed call.
abstract final class ApiMessage {
  static String of(Object? e) => e == null ? '' : certErrorText(e);
}

/// Shows [e] as an error toast.
void certNotifyError(Object e) => showAppNotice(certErrorText(e), error: true);
