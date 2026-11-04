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
import 'cert_engine_presets.dart';

// ── starters ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// The gallery of starting designs. Null when closed without a pick.
Future<CertStarter?> showCertStarterGallery(BuildContext context, List<CertStarter> starters, {required String lang}) {
  final usable = [for (final s in starters) if (s.mode == 'page' || s.mode.isEmpty) s];
  return showAppSheet<CertStarter>(
    context,
    (ctx) => AppSheetContent(
      title: t('اختر تصميمًا للبدء', 'Pick a design to start from'),
      children: [
        if (usable.isEmpty)
          AppEmpty(icon: Icons.dashboard_customize_outlined, title: t('لا توجد تصاميم جاهزة الآن', 'No ready designs right now'))
        else ...[
          Text(
            t('سيحلّ التصميم المختار محلّ التصميم الحالي لهذه اللغة.', 'The design you pick replaces the current design of this language.'),
            style: appText(12.5, c: ctx.colors.textMedium),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final s in usable) _StarterCard(starter: s, lang: lang),
        ],
      ],
    ),
  );
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({required this.starter, required this.lang});
  final CertStarter starter;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = starter.document.designs[lang] ?? (starter.document.designs.values.isEmpty ? null : starter.document.designs.values.first);
    final landscape = d?.page.landscape ?? true;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider)),
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: () => Navigator.pop(context, starter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: .08), borderRadius: BorderRadius.circular(AppRadius.chip)),
                  child: Icon(landscape ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded, color: c.primary),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(starter.name(lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
                    if (starter.description(lang).isNotEmpty)
                      Text(starter.description(lang), maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
  Future<String?> Function(String style, String color)? generateBackground,
}) =>
    showAppSheet<void>(context, (ctx) => _PageSheet(design: design, onChanged: onChanged, pickBackground: pickBackground, generateBackground: generateBackground));

class _PageSheet extends StatefulWidget {
  const _PageSheet({required this.design, required this.onChanged, required this.pickBackground, this.generateBackground});
  final LayoutDesign design;
  final VoidCallback onChanged;
  final Future<String?> Function() pickBackground;
  final Future<String?> Function(String style, String color)? generateBackground;

  @override
  State<_PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<_PageSheet> {
  LayoutPage get p => widget.design.page;
  bool _generating = false;
  String _style = 'classic';
  String _color = kCertGenColors.first;

  Future<void> _generate() async {
    setState(() => _generating = true);
    final url = await widget.generateBackground!(_style, _color);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: t('الصفحة', 'Page'),
      children: [
        StudioPropField(
          label: t('المقاس', 'Size'),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in const ['A4', 'A3', 'A5', 'Letter', 'custom'])
              ChoiceChip(
                label: Text(s == 'custom' ? t('مخصص', 'Custom') : s),
                selected: p.size == s,
                onSelected: (_) => _page(() => p.size = s),
              ),
          ]),
        ),
        if (p.size == 'custom') ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Expanded(child: StudioStepper(label: t('العرض (مم)', 'Width (mm)'), value: p.customWidth, min: 60, max: 600, step: 5, onChanged: (v) => _page(() => p.customWidth = v))),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: StudioStepper(label: t('الارتفاع (مم)', 'Height (mm)'), value: p.customHeight, min: 60, max: 600, step: 5, onChanged: (v) => _page(() => p.customHeight = v))),
          ]),
        ],
        const SizedBox(height: AppSpace.sm),
        StudioPropField(
          label: t('الاتجاه', 'Orientation'),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            ChoiceChip(
              avatar: const Icon(Icons.crop_landscape_rounded, size: 18),
              label: Text(t('أفقي', 'Landscape')),
              selected: p.landscape,
              onSelected: (_) => _page(() => p.orientation = 'landscape'),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.crop_portrait_rounded, size: 18),
              label: Text(t('عمودي', 'Portrait')),
              selected: !p.landscape,
              onSelected: (_) => _page(() => p.orientation = 'portrait'),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        StudioColorField(
          label: t('لون الصفحة', 'Page colour'),
          value: layoutColor(p.background),
          allowNone: true,
          onChanged: (col) => _plain(() => p.background = col == null ? null : layoutHex(col)),
        ),
        const SizedBox(height: AppSpace.sm),
        StudioPropField(
          label: t('صورة الخلفية', 'Background image'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.wallpaper_rounded),
                  label: Text(p.backgroundImage == null ? t('اختيار صورة', 'Choose an image') : t('تغيير الصورة', 'Change the image')),
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
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final (k, ar, en) in const [('cover', 'ملء', 'Cover'), ('contain', 'احتواء', 'Contain'), ('fill', 'تمديد', 'Stretch')])
                  ChoiceChip(label: Text(t(ar, en)), selected: p.backgroundFit == k, onSelected: (_) => _plain(() => p.backgroundFit = k)),
              ]),
              const SizedBox(height: AppSpace.xxs),
              Text(t('تظهر صورة الخلفية في المعاينة وفي الملف النهائي.', 'The background image shows in the preview and in the final file.'), style: appText(12, c: c.textMedium)),
            ],
          ]),
        ),
        if (widget.generateBackground != null) ...[
          const SizedBox(height: AppSpace.sm),
          StudioPropField(
            label: t('إنشاء خلفية', 'Generate a background'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final (k, ar, en) in const [('classic', 'كلاسيكي', 'Classic'), ('modern', 'عصري', 'Modern'), ('dark', 'داكن', 'Dark')])
                  ChoiceChip(key: ValueKey('cert-gen-$k'), label: Text(t(ar, en)), selected: _style == k, onSelected: (_) => setState(() => _style = k)),
              ]),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final hex in kCertGenColors)
                  Semantics(
                    button: true,
                    selected: _color == hex,
                    label: hex,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      onTap: () => setState(() => _color = hex),
                      child: Container(
                        width: AppTouch.min,
                        height: AppTouch.min,
                        alignment: Alignment.center,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(color: layoutColor(hex), shape: BoxShape.circle, border: Border.all(color: _color == hex ? c.textDark : c.divider, width: _color == hex ? 3 : 1)),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: AppSpace.xs),
              FilledButton.icon(
                key: const ValueKey('cert-gen-go'),
                onPressed: _generating ? null : _generate,
                icon: _generating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
                label: Text(t('إنشاء', 'Generate')),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
              ),
              Text(t('تُطبَّق على لغة هذا التبويب فقط.', 'Applied to the language of this tab only.'), style: appText(12, c: c.textMedium)),
            ]),
          ),
        ],
      ],
    );
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
Future<({String? ink, double strength})?> showCertSignatureClean(BuildContext context) => showAppSheet<({String? ink, double strength})>(
      context,
      (ctx) => _SigCleanSheet(),
    );

class _SigCleanSheet extends StatefulWidget {
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
        Text(t('تُعاد المعالجة من الصورة التي رفعتها في هذه الجلسة.', 'It is processed again from the photo you uploaded in this session.'), style: appText(12, c: c.textMedium)),
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
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.xs, 0),
            child: Row(children: [
              Expanded(child: Text(t('معاينة', 'Preview'), style: appText(16, w: FontWeight.w700, c: c.textDark))),
              if (widget.languages.length > 1)
                for (final l in widget.languages)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs),
                    child: ChoiceChip(label: Text(l == 'ar' ? 'العربية' : 'English'), selected: _lang == l, onSelected: (_) => _pick(l)),
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
                if (!snap.hasData) {
                  return const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()));
                }
                return InteractiveViewer(
                  maxScale: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.sm),
                    child: Image.memory(snap.data!, fit: BoxFit.contain, cacheWidth: 1400, gaplessPlayback: true),
                  ),
                );
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

/// The user-facing text of a failed call.
abstract final class ApiMessage {
  static String of(Object? e) => e == null ? '' : certErrorText(e);
}

/// Shows [e] as an error toast.
void certNotifyError(Object e) => showAppNotice(certErrorText(e), error: true);
