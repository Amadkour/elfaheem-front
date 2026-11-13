// lib/features/shared/records/studio_panels.dart — the inspector of the Studio's edit tools (D-590 … D-593): Edit
// (split, mark, remove, keep, trim by the frame, speed), Text and Picture (add, style, place, time, animate) and
// History (every step in plain words; tap one to go back). Plain values in, callbacks out: the page commits steps.
//
// Exact numbers everywhere: every time shows hundredths and has ◀ ▶ to move it by one frame (1/30 s).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart' show speedLabel;
import 'studio_project.dart';

/// The text colours offered (the overlay's own content colours, not the app's chrome).
const studioTextColors = <int>[0xFFFFFFFF, 0xFF111827, 0xFFFACC15, 0xFFF97316, 0xFFEF4444, 0xFF22C55E, 0xFF38BDF8, 0xFFA78BFA];

/// The pill colours behind a text (null: none).
const studioTextBackgrounds = <int?>[null, 0xCC000000, 0xE6FFFFFF, 0xE61D4ED8, 0xE6B91C1C, 0xE6047857, 0xE6FACC15];

const _frame = 1 / 30;

TextStyle _tab(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// A small caption over a group of controls.
class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(children: [
        Expanded(child: Text(text, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600))),
        ?trailing,
      ]),
    );
  }
}

/// A time with its label and one-frame nudges: ◀ 01:23.45 ▶.
class StudioTimeField extends StatelessWidget {
  const StudioTimeField({super.key, required this.label, required this.value, this.onNudge, this.lit = false, this.idKey});
  final String label;
  final double value;
  final ValueChanged<double>? onNudge;
  final bool lit;
  final String? idKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget nudge(double by, IconData icon, String tip) => SizedBox(
          width: 36,
          height: AppTouch.min,
          child: IconButton(
            key: idKey == null ? null : ValueKey('studio.nudge.$idKey.${by > 0 ? 'fwd' : 'back'}'),
            tooltip: tip,
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: AppIconSize.md, color: onNudge == null ? c.textLight : c.textDark),
            onPressed: onNudge == null ? null : () => onNudge!(by),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: lit ? c.primaryTint : c.inputBg, borderRadius: AppRadius.chipAll),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (onNudge != null) nudge(-_frame, Icons.chevron_left_rounded, t('إطار للخلف', 'One frame earlier')),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(studioTimecode(value),
                    key: idKey == null ? null : ValueKey('studio.time.$idKey'), style: _tab(AppType.bodyStrong(context).copyWith(color: c.textDark))),
              ),
            ),
            if (onNudge != null) nudge(_frame, Icons.chevron_right_rounded, t('إطار للأمام', 'One frame later')),
          ]),
        ),
      ]),
    );
  }
}

/// Equal cells in a row (LTR when [ltr]: in / out stand where their flags stand).
Widget _cells(List<Widget> cells, {bool ltr = false}) {
  final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (final (i, w) in cells.indexed) ...[
      if (i > 0) const SizedBox(width: AppSpace.xs),
      Expanded(child: w),
    ],
  ]);
  return ltr ? Directionality(textDirection: TextDirection.ltr, child: row) : row;
}

Widget _action(String key, String label, IconData icon, VoidCallback? onTap, {String? tip, bool danger = false, bool primary = false}) => Builder(
      builder: (context) => AppButton(
        key: ValueKey('studio.$key'),
        label: label,
        icon: icon,
        tooltip: tip,
        variant: primary ? AppButtonVariant.primary : (danger ? AppButtonVariant.secondary : AppButtonVariant.secondary),
        size: AppButtonSize.sm,
        expand: true,
        dangerOutline: danger,
        onPressed: onTap,
      ),
    );

/// One choice among equals (speed, an animation, a place).
class _Pick extends StatelessWidget {
  const _Pick({super.key, required this.label, required this.selected, this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? (c.isDark ? c.textDark : c.primary) : c.textDark;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: c.isDark ? 0.3 : 0.1) : c.inputBg,
            borderRadius: AppRadius.chipAll,
            border: Border.all(color: selected ? (c.isDark ? c.textMedium : c.primary) : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: AppIconSize.sm, color: ink), const SizedBox(width: 4)],
            Flexible(
              child: Text(label,
                  maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: _tab(appText(12.5, w: selected ? FontWeight.w700 : FontWeight.w500, c: ink, h: 1.2))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A short note in the panel.
Widget _note(String text, {Key? key}) => Builder(builder: (context) => Text(text, key: key, style: AppType.meta(context).copyWith(color: context.colors.textMedium)));

// ─────────────────────────────────────────────────────────────────────────────
// Edit
// ─────────────────────────────────────────────────────────────────────────────

class StudioEditPanel extends StatelessWidget {
  const StudioEditPanel({
    super.key,
    required this.edit,
    required this.position,
    this.markIn,
    this.markOut,
    this.selectedClip,
    this.enabled = true,
    this.onSplit,
    this.onMarkIn,
    this.onMarkOut,
    this.onNudgeMark,
    this.onClearMarks,
    this.onRemoveMarked,
    this.onKeepMarked,
    this.onDeleteClip,
    this.onNudgeClip,
    this.onSpeed,
  });

  final StudioEdit edit;
  final double position;
  final double? markIn;
  final double? markOut;
  final int? selectedClip;
  final bool enabled;
  final VoidCallback? onSplit;
  final VoidCallback? onMarkIn;
  final VoidCallback? onMarkOut;

  /// (in?, seconds): moves a mark by a frame.
  final void Function(bool isIn, double by)? onNudgeMark;
  final VoidCallback? onClearMarks;
  final VoidCallback? onRemoveMarked;
  final VoidCallback? onKeepMarked;
  final VoidCallback? onDeleteClip;

  /// (start?, seconds): moves the selected part's edge by a frame (source time).
  final void Function(bool start, double by)? onNudgeClip;

  /// The speed for the marked period, else the selected part, else everything.
  final ValueChanged<double>? onSpeed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final marked = markIn != null && markOut != null && markOut! > markIn!;
    final sel = selectedClip != null && selectedClip! < edit.clips.length ? edit.clips[selectedClip!] : null;
    final speedNow = sel?.speed ?? (edit.clips.length == 1 ? edit.clips.first.speed : null);
    final on = enabled;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Caption(t('عند المؤشر', 'At the playhead'),
          trailing: Text(studioTimecode(position), textDirection: TextDirection.ltr, style: _tab(AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)))),
      _cells([
        _action('split', t('تقسيم', 'Split'), Icons.call_split_rounded, on ? onSplit : null, tip: t('تقسيم عند المؤشر (S)', 'Split at the playhead (S)'), primary: true),
      ]),
      const SizedBox(height: AppSpace.xs),
      _cells([
        _action('mark_in', t('بداية الفترة', 'Mark in'), Icons.first_page_rounded, on ? onMarkIn : null, tip: t('بداية الفترة عند المؤشر (I)', 'Mark in at the playhead (I)')),
        _action('mark_out', t('نهاية الفترة', 'Mark out'), Icons.last_page_rounded, on ? onMarkOut : null, tip: t('نهاية الفترة عند المؤشر (O)', 'Mark out at the playhead (O)')),
      ], ltr: true),
      const SizedBox(height: AppSpace.md),
      if (markIn != null || markOut != null) ...[
        _Caption(t('الفترة المحددة', 'The marked period'),
            trailing: TextButton(
              key: const ValueKey('studio.marks.clear'),
              onPressed: on ? onClearMarks : null,
              style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              child: Text(t('مسح', 'Clear')),
            )),
        _cells([
          StudioTimeField(label: t('من', 'From'), value: markIn ?? 0, idKey: 'in', onNudge: on && markIn != null ? (b) => onNudgeMark?.call(true, b) : null),
          StudioTimeField(label: t('إلى', 'To'), value: markOut ?? edit.duration, idKey: 'out', onNudge: on && markOut != null ? (b) => onNudgeMark?.call(false, b) : null),
        ], ltr: true),
        const SizedBox(height: AppSpace.xxs),
        if (marked)
          Text(t('المدة ${studioTimecode(markOut! - markIn!)}', 'Length ${studioTimecode(markOut! - markIn!)}'),
              key: const ValueKey('studio.marks.length'), style: _tab(AppType.meta(context).copyWith(color: c.textMedium))),
        const SizedBox(height: AppSpace.xs),
        _cells([
          _action('remove_marked', t('حذف الفترة', 'Remove it'), Icons.content_cut_rounded, on && marked ? onRemoveMarked : null,
              tip: t('حذف الفترة المحددة وضم ما قبلها بما بعدها (Delete)', 'Remove the marked period and join the rest (Delete)'), danger: true),
          _action('keep_marked', t('الإبقاء عليها فقط', 'Keep only it'), Icons.crop_rounded, on && marked ? onKeepMarked : null,
              tip: t('حذف كل ما قبلها وما بعدها', 'Remove everything before and after it')),
        ]),
        const SizedBox(height: AppSpace.md),
      ],
      if (sel != null) ...[
        _Caption(t('الجزء المحدد', 'The selected part'),
            trailing: Text(t('الجزء ${selectedClip! + 1} من ${edit.clips.length}', 'Part ${selectedClip! + 1} of ${edit.clips.length}'),
                style: AppType.meta(context).copyWith(color: c.textMedium))),
        _cells([
          StudioTimeField(label: t('يبدأ من الأصل', 'Starts at (original)'), value: sel.start, idKey: 'clip_start', onNudge: on ? (b) => onNudgeClip?.call(true, b) : null),
          StudioTimeField(label: t('ينتهي عند', 'Ends at'), value: sel.end, idKey: 'clip_end', onNudge: on ? (b) => onNudgeClip?.call(false, b) : null),
        ], ltr: true),
        const SizedBox(height: AppSpace.xxs),
        Text(t('المدة ${studioTimecode(sel.length)}', 'Length ${studioTimecode(sel.length)}'), style: _tab(AppType.meta(context).copyWith(color: c.textMedium))),
        const SizedBox(height: AppSpace.xs),
        _action('delete_clip', t('حذف هذا الجزء', 'Delete this part'), Icons.delete_outline_rounded, on && edit.clips.length > 1 ? onDeleteClip : null,
            tip: t('حذف الجزء وضم ما حوله (Delete)', 'Delete the part and join what is around it (Delete)'), danger: true),
        const SizedBox(height: AppSpace.md),
      ],
      if (sel == null && markIn == null && markOut == null) ...[
        Container(
          key: const ValueKey('studio.edit.hint'),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.touch_app_outlined, size: AppIconSize.md, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _note(t('اضغط جزءاً في الخط الزمني لتحديده واسحب طرفيه، أو حدّد فترة ببداية ونهاية ثم احذفها. كل خطوة يمكن التراجع عنها.',
                  'Tap a part on the timeline to select it and drag its edges, or mark a period with Mark in / out and remove it. Every step can be undone.')),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      _Caption(marked
          ? t('سرعة الفترة المحددة', 'Speed of the marked period')
          : sel != null
              ? t('سرعة هذا الجزء', 'Speed of this part')
              : t('السرعة', 'Speed')),
      Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(builder: (context, box) {
          // one row of six when it fits (a 48 px target each), else two rows of three
          final perRow = box.maxWidth >= 6 * 62 + 5 * 6 ? 6 : 3;
          final rows = <Widget>[];
          for (var i = 0; i < studioClipSpeeds.length; i += perRow) {
            rows.add(Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.xs),
              child: Row(children: [
                for (final (k, s) in studioClipSpeeds.skip(i).take(perRow).indexed) ...[
                  if (k > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Pick(
                      key: ValueKey('studio.speed.$s'),
                      label: speedLabel(s),
                      selected: !marked && speedNow == s,
                      onTap: on ? () => onSpeed?.call(s) : null,
                    ),
                  ),
                ],
              ]),
            ));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: rows);
        }),
      ),
      const SizedBox(height: AppSpace.xs),
      _note(t('تبقى الأصوات بطبقتها الطبيعية؛ المعاينة تعمل بالسرعة نفسها.', 'Voices keep their natural pitch; the preview plays at that speed.')),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text · Picture
// ─────────────────────────────────────────────────────────────────────────────

/// What an overlay panel reports: the new overlay, whether it is final (a slider let go, a tap) and the step kind.
typedef StudioOverlayChange = void Function(StudioOverlay o, {required bool commit, required StudioStepKind kind});

class StudioOverlayPanel extends StatefulWidget {
  const StudioOverlayPanel({
    super.key,
    required this.kind,
    required this.edit,
    required this.position,
    this.selected,
    this.images = const {},
    this.enabled = true,
    this.canAdd = true,
    this.onAdd,
    this.onSelect,
    this.onChange,
    this.onDelete,
    this.onDuplicate,
  });

  final StudioOverlayKind kind;
  final StudioEdit edit;
  final double position;

  /// The selected overlay of this kind (null: the list and Add).
  final StudioOverlay? selected;
  final Map<String, Uint8List> images;
  final bool enabled;

  /// Video only (an audio file has no picture to put things on).
  final bool canAdd;

  /// Add one ([place]: where on the frame; a text preset's words come with it).
  final void Function(StudioPlace place, {String? text, int? background, double? size})? onAdd;
  final ValueChanged<String?>? onSelect;
  final StudioOverlayChange? onChange;
  final ValueChanged<String>? onDelete;
  final ValueChanged<String>? onDuplicate;

  @override
  State<StudioOverlayPanel> createState() => _StudioOverlayPanelState();
}

class _StudioOverlayPanelState extends State<StudioOverlayPanel> {
  late final TextEditingController _text = TextEditingController(text: widget.selected?.text ?? '');
  String? _editingId;

  @override
  void didUpdateWidget(covariant StudioOverlayPanel old) {
    super.didUpdateWidget(old);
    final s = widget.selected;
    if (s?.id != _editingId) {
      _editingId = s?.id;
      if (s != null && _text.text != s.text) _text.text = s.text;
    } else if (s != null && s.text != _text.text && !_focus.hasFocus) {
      _text.text = s.text; // undo / redo changed it
    }
  }

  final _focus = FocusNode(debugLabel: 'studio-text');

  @override
  void initState() {
    super.initState();
    _editingId = widget.selected?.id;
    _focus.addListener(() {
      final s = widget.selected;
      if (!_focus.hasFocus && s != null && s.text != _text.text && _text.text.trim().isNotEmpty) {
        widget.onChange?.call(s.copyWith(text: _text.text), commit: true, kind: StudioStepKind.overlayStyle);
      }
    });
  }

  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isText => widget.kind == StudioOverlayKind.text;

  Widget _list(BuildContext context) {
    final c = context.colors;
    final mine = [for (final o in widget.edit.overlays) if (o.kind == widget.kind) o];
    final on = widget.enabled && widget.canAdd;
    final add = <Widget>[];
    if (_isText) {
      add.add(_cells([
        _action('text.add', t('إضافة نص', 'Add text'), Icons.add_rounded, on ? () => widget.onAdd?.call(StudioPlace.lowerThird) : null, primary: true),
      ]));
      add.add(const SizedBox(height: AppSpace.xs));
      add.add(Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        _Pick(
            key: const ValueKey('studio.text.preset.title'),
            label: t('عنوان', 'Title'),
            icon: Icons.title_rounded,
            selected: false,
            onTap: on ? () => widget.onAdd?.call(StudioPlace.center, text: t('العنوان', 'Title'), size: 0.1) : null),
        _Pick(
            key: const ValueKey('studio.text.preset.lower'),
            label: t('شريط سفلي', 'Lower third'),
            icon: Icons.short_text_rounded,
            selected: false,
            onTap: on ? () => widget.onAdd?.call(StudioPlace.lowerThird, text: t('الاسم · الدور', 'Name · Role'), background: 0xCC000000, size: 0.055) : null),
        _Pick(
            key: const ValueKey('studio.text.preset.caption'),
            label: t('ملاحظة', 'Note'),
            icon: Icons.sticky_note_2_outlined,
            selected: false,
            onTap: on ? () => widget.onAdd?.call(StudioPlace.top, text: t('ملاحظة مهمة', 'An important note'), background: 0xE6FACC15, size: 0.05) : null),
      ]));
    } else {
      add.add(_cells([
        _action('image.add', t('إضافة صورة من جهازك', 'Add a picture from your device'), Icons.add_photo_alternate_outlined,
            on ? () => widget.onAdd?.call(StudioPlace.topStart) : null,
            primary: true),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ...add,
      const SizedBox(height: AppSpace.xs),
      _note(widget.canAdd
          ? t('يُضاف عند المؤشر لخمس ثوانٍ؛ اسحبه على الصورة لتغيير مكانه وعلى الخط الزمني لتغيير وقته.',
              'It is added at the playhead for five seconds; drag it on the picture to place it and on the timeline to change when it shows.')
          : t('لا توجد صورة في ملف صوتي لإضافة شيء فوقها.', 'An audio file has no picture to put things on.')),
      if (mine.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        _Caption(_isText ? t('النصوص', 'Texts') : t('الصور', 'Pictures')),
        for (final o in mine) ...[
          InkWell(
            key: ValueKey('studio.overlay.item.${o.id}'),
            borderRadius: AppRadius.chipAll,
            onTap: widget.enabled ? () => widget.onSelect?.call(o.id) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
              decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
              child: Row(children: [
                if (!o.isText && o.asset != null && widget.images[o.asset] != null)
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(widget.images[o.asset]!, width: 36, height: 28, fit: BoxFit.cover))
                else
                  Icon(o.isText ? Icons.title_rounded : Icons.image_outlined, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600))),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: widget.edit.overlayOut(o) != null
                      ? Text('${mmssShort(widget.edit.overlayOut(o)!.$1)} – ${mmssShort(widget.edit.overlayOut(o)!.$2)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: _tab(AppType.meta(context).copyWith(color: c.textMedium)))
                      : Text(t('في جزء محذوف', 'In a removed part'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.warning)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: AppSpace.xxs + 2),
        ],
      ],
    ]);
  }

  Widget _animRow(BuildContext context, StudioOverlay o, bool isIn) {
    final anim = isIn ? o.inAnim : o.outAnim;
    final dur = isIn ? o.inDur : o.outDur;
    final on = widget.enabled;
    void set(StudioAnim a) => widget.onChange?.call(isIn ? o.copyWith(inAnim: a) : o.copyWith(outAnim: a), commit: true, kind: StudioStepKind.overlayAnim);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Caption(isIn ? t('الظهور', 'Comes in') : t('الاختفاء', 'Goes out'),
          trailing: anim == StudioAnim.none ? null : Text('${dur.toStringAsFixed(1)} s', textDirection: TextDirection.ltr, style: _tab(AppType.meta(context).copyWith(color: context.colors.textMedium)))),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final a in StudioAnim.values)
          if (a.fits(o.kind))
            _Pick(
              key: ValueKey('studio.anim.${isIn ? 'in' : 'out'}.${a.wire}'),
              label: a.label,
              selected: anim == a,
              onTap: on ? () => set(a) : null,
            ),
      ]),
      if (anim != StudioAnim.none)
        Slider(
          key: ValueKey('studio.anim.${isIn ? 'in' : 'out'}.d'),
          min: 0.2,
          max: 3,
          divisions: 28,
          value: dur.clamp(0.2, 3.0),
          label: '${dur.toStringAsFixed(1)} s',
          onChanged: on
              ? (v) => widget.onChange?.call(isIn ? o.copyWith(inDur: v) : o.copyWith(outDur: v), commit: false, kind: StudioStepKind.overlayAnim)
              : null,
          onChangeEnd: on
              ? (v) => widget.onChange?.call(isIn ? o.copyWith(inDur: v) : o.copyWith(outDur: v), commit: true, kind: StudioStepKind.overlayAnim)
              : null,
        ),
    ]);
  }

  Widget _editor(BuildContext context, StudioOverlay o) {
    final c = context.colors;
    final on = widget.enabled;
    final span = widget.edit.overlayOut(o);
    void change(StudioOverlay n, {bool commit = true, StudioStepKind kind = StudioStepKind.overlayStyle}) =>
        widget.onChange?.call(n, commit: commit, kind: kind);
    final body = <Widget>[
      Row(children: [
        IconButton(
          key: const ValueKey('studio.overlay.back'),
          tooltip: t('كل العناصر', 'All of them'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: () => widget.onSelect?.call(null),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(child: Text(o.isText ? t('تعديل النص', 'Edit the text') : t('تعديل الصورة', 'Edit the picture'), style: AppType.bodyStrong(context).copyWith(color: c.textDark))),
        IconButton(
          key: const ValueKey('studio.overlay.duplicate'),
          tooltip: t('نسخة', 'Duplicate'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: on ? () => widget.onDuplicate?.call(o.id) : null,
          icon: const Icon(Icons.copy_rounded),
        ),
        IconButton(
          key: const ValueKey('studio.overlay.delete'),
          tooltip: t('حذف', 'Delete'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: on ? () => widget.onDelete?.call(o.id) : null,
          icon: Icon(Icons.delete_outline_rounded, color: c.danger),
        ),
      ]),
      const SizedBox(height: AppSpace.xs),
    ];
    if (o.isText) {
      final fonts = AppFonts.optionsFor(o.rtl ? 'ar' : 'en');
      body.addAll([
        TextField(
          key: const ValueKey('studio.text.field'),
          controller: _text,
          focusNode: _focus,
          enabled: on,
          minLines: 1,
          maxLines: 4,
          maxLength: 200,
          textDirection: RegExp(r'[؀-ۿ]').hasMatch(_text.text) ? TextDirection.rtl : null,
          decoration: InputDecoration(labelText: t('النص', 'Text')),
          onChanged: (v) {
            if (v.trim().isEmpty) return;
            change(o.copyWith(text: v), commit: false);
            // a pause in typing makes the words a step (a drag or another change never loses them)
            _typing?.cancel();
            _typing = Timer(const Duration(milliseconds: 700), () {
              final cur = widget.selected;
              if (mounted && cur != null && cur.id == o.id && _text.text.trim().isNotEmpty) {
                widget.onChange?.call(cur.copyWith(text: _text.text), commit: true, kind: StudioStepKind.overlayStyle);
              }
            });
          },
        ),
        const SizedBox(height: AppSpace.sm),
        _Caption(t('الخط', 'Font')),
        AppDropdown<String>(
          key: const ValueKey('studio.text.font'),
          value: fonts.any((f) => f.id == o.fontId) ? o.fontId : fonts.first.id,
          enabled: on,
          items: [
            for (final f in fonts)
              DropdownMenuItem(value: f.id, child: Text(f.name(o.rtl ? 'ar' : 'en'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (id) {
            if (id != null) change(o.copyWith(fontId: id));
          },
        ),
        const SizedBox(height: AppSpace.sm),
        _Caption(t('الحجم', 'Size'), trailing: Text('${(o.size * 100).round()}', style: _tab(AppType.meta(context).copyWith(color: c.textMedium)))),
        Slider(
          key: const ValueKey('studio.text.size'),
          min: 0.025,
          max: 0.2,
          value: o.size.clamp(0.025, 0.2),
          onChanged: on ? (v) => change(o.copyWith(size: v), commit: false) : null,
          onChangeEnd: on ? (v) => change(o.copyWith(size: v)) : null,
        ),
        AppSwitchTile(
          key: const ValueKey('studio.text.bold'),
          title: t('عريض', 'Bold'),
          value: o.bold,
          onChanged: on ? (v) => change(o.copyWith(bold: v)) : null,
        ),
        const SizedBox(height: AppSpace.xs),
        _Caption(t('اللون', 'Colour')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final col in studioTextColors)
            _Swatch(key: ValueKey('studio.text.color.$col'), color: Color(col), selected: o.color == col, onTap: on ? () => change(o.copyWith(color: col)) : null),
        ]),
        const SizedBox(height: AppSpace.sm),
        _Caption(t('الخلفية', 'Background')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final bg in studioTextBackgrounds)
            _Swatch(
              key: ValueKey('studio.text.bg.$bg'),
              color: bg == null ? null : Color(bg),
              selected: o.background == bg,
              onTap: on ? () => change(o.copyWith(background: () => bg)) : null,
            ),
        ]),
      ]);
    } else {
      body.addAll([
        _Caption(t('الحجم', 'Size'), trailing: Text('${(o.w * 100).round()}%', style: _tab(AppType.meta(context).copyWith(color: c.textMedium)))),
        Slider(
          key: const ValueKey('studio.image.size'),
          min: 0.05,
          max: 1,
          value: o.w.clamp(0.05, 1.0),
          onChanged: on ? (v) => change(o.copyWith(w: v), commit: false) : null,
          onChangeEnd: on ? (v) => change(o.copyWith(w: v)) : null,
        ),
      ]);
    }
    body.addAll([
      const SizedBox(height: AppSpace.sm),
      _Caption(t('الشفافية', 'Opacity'), trailing: Text('${(o.opacity * 100).round()}%', style: _tab(AppType.meta(context).copyWith(color: c.textMedium)))),
      Slider(
        key: const ValueKey('studio.overlay.opacity'),
        min: 0.1,
        max: 1,
        value: o.opacity.clamp(0.1, 1.0),
        onChanged: on ? (v) => change(o.copyWith(opacity: v), commit: false) : null,
        onChangeEnd: on ? (v) => change(o.copyWith(opacity: v)) : null,
      ),
      _Caption(t('المكان', 'Place')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final (p, label, icon) in [
          (StudioPlace.top, t('أعلى', 'Top'), Icons.vertical_align_top_rounded),
          (StudioPlace.center, t('الوسط', 'Centre'), Icons.vertical_align_center_rounded),
          (StudioPlace.lowerThird, t('أسفل', 'Bottom'), Icons.vertical_align_bottom_rounded),
          (StudioPlace.topStart, t('زاوية', 'Corner'), Icons.north_west_rounded),
        ])
          _Pick(
            key: ValueKey('studio.place.${p.name}'),
            label: label,
            icon: icon,
            selected: (o.x - p.x).abs() < 0.01 && (o.y - p.y).abs() < 0.01,
            onTap: on ? () => change(o.copyWith(x: p.x, y: p.y), kind: StudioStepKind.overlayMove) : null,
          ),
      ]),
      const SizedBox(height: AppSpace.md),
      _Caption(t('متى يظهر', 'When it shows')),
      if (span == null)
        _note(t('كل ما يغطيه هذا العنصر حُذف من الفيديو.', 'Everything this covers was removed from the video.'))
      else ...[
        _cells([
          StudioTimeField(label: t('من', 'From'), value: span.$1, idKey: 'ov_start',
              onNudge: on ? (b) => _retime(o, span.$1 + b, span.$2) : null),
          StudioTimeField(label: t('إلى', 'To'), value: span.$2, idKey: 'ov_end',
              onNudge: on ? (b) => _retime(o, span.$1, span.$2 + b) : null),
        ], ltr: true),
        const SizedBox(height: AppSpace.xs),
        _cells([
          _action('overlay.start_here', t('يبدأ هنا', 'Starts here'), Icons.first_page_rounded,
              on && widget.position < span.$2 - 0.3 ? () => _retime(o, widget.position, span.$2) : null),
          _action('overlay.end_here', t('ينتهي هنا', 'Ends here'), Icons.last_page_rounded,
              on && widget.position > span.$1 + 0.3 ? () => _retime(o, span.$1, widget.position) : null),
        ], ltr: true),
      ],
      const SizedBox(height: AppSpace.md),
      _animRow(context, o, true),
      const SizedBox(height: AppSpace.sm),
      _animRow(context, o, false),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body);
  }

  void _retime(StudioOverlay o, double a, double b) {
    final e = widget.edit;
    final lo = a.clamp(0.0, e.duration), hi = b.clamp(0.0, e.duration);
    if (hi - lo < 0.3) return;
    widget.onChange?.call(o.copyWith(start: e.anchor(lo), end: e.anchor(hi, end: true)), commit: true, kind: StudioStepKind.overlayTime);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selected;
    return AnimatedSwitcher(
      duration: AppMotion.of(context).fast,
      child: KeyedSubtree(key: ValueKey(s?.id ?? 'list'), child: s == null ? _list(context) : _editor(context, s)),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.color, required this.selected, this.onTap});
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: color == null ? t('بلا خلفية', 'No background') : t('لون', 'Colour'),
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: AppTouch.min,
          height: AppTouch.min,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? c.inputBg,
                border: Border.all(color: selected ? (c.isDark ? c.textDark : c.primary) : c.divider, width: selected ? 3 : 1),
              ),
              child: color == null ? Icon(Icons.block_rounded, size: AppIconSize.sm, color: c.textMedium) : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History
// ─────────────────────────────────────────────────────────────────────────────

IconData studioStepIcon(StudioStepKind k) => switch (k) {
      StudioStepKind.open => Icons.movie_outlined,
      StudioStepKind.split => Icons.call_split_rounded,
      StudioStepKind.remove || StudioStepKind.deleteClip => Icons.content_cut_rounded,
      StudioStepKind.keep => Icons.crop_rounded,
      StudioStepKind.trimStart || StudioStepKind.trimEnd => Icons.swap_horiz_rounded,
      StudioStepKind.speed => Icons.speed_rounded,
      StudioStepKind.textAdd => Icons.title_rounded,
      StudioStepKind.imageAdd => Icons.add_photo_alternate_outlined,
      StudioStepKind.overlayMove => Icons.open_with_rounded,
      StudioStepKind.overlayTime => Icons.schedule_rounded,
      StudioStepKind.overlayStyle => Icons.palette_outlined,
      StudioStepKind.overlayAnim => Icons.animation_rounded,
      StudioStepKind.overlayRemove => Icons.delete_outline_rounded,
      StudioStepKind.quality => Icons.high_quality_rounded,
      StudioStepKind.reset => Icons.restart_alt_rounded,
      StudioStepKind.moveClip => Icons.swap_calls_rounded,
      StudioStepKind.restore => Icons.settings_backup_restore_rounded,
    };

class StudioHistoryPanel extends StatelessWidget {
  const StudioHistoryPanel({super.key, required this.history, this.enabled = true, this.onRestore, this.onReset, this.clock});

  final StudioHistory history;
  final bool enabled;
  final ValueChanged<int>? onRestore;
  final VoidCallback? onReset;

  /// The time of a step (AppTime in the app; tests pass their own).
  final String Function(DateTime at)? clock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = history;
    final rows = <Widget>[];
    for (var i = h.steps.length - 1; i >= 0; i--) {
      final s = h.steps[i];
      final current = i == h.head;
      final undone = i > h.head;
      final tone = current ? (c.isDark ? c.textDark : c.primary) : (undone ? c.textLight : c.textDark);
      rows.add(Semantics(
        button: true,
        selected: current,
        label: '${studioStepLabel(s)}${undone ? ' — ${t('متراجَع عنها', 'undone')}' : ''}',
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('studio.history.$i'),
          borderRadius: AppRadius.chipAll,
          onTap: enabled && !current ? () => onRestore?.call(i) : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
            decoration: BoxDecoration(
              color: current ? c.primaryTint : null,
              borderRadius: AppRadius.chipAll,
              border: Border.all(color: current ? c.primary.withValues(alpha: 0.4) : c.divider.withValues(alpha: 0.6)),
            ),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(shape: BoxShape.circle, color: (undone ? c.inputBg : tone.withValues(alpha: 0.12))),
                child: Icon(studioStepIcon(s.kind), size: AppIconSize.sm, color: tone),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(studioStepLabel(s),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(13, w: current ? FontWeight.w700 : FontWeight.w500, c: tone, h: 1.3)
                          .copyWith(decoration: undone ? TextDecoration.lineThrough : null, decorationColor: c.textLight)),
                  Text(
                    [
                      clock?.call(s.at) ?? '',
                      '${t('الطول', 'length')} ${mmssShort(s.edit.duration)}',
                      if (current) t('الحالي', 'current'),
                      if (undone) t('متراجَع عنها — اضغط لاستعادتها', 'undone — tap to bring it back'),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _tab(AppType.meta(context).copyWith(color: c.textMedium)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ));
      rows.add(const SizedBox(height: AppSpace.xxs + 2));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        t('${h.steps.length - 1} خطوة · ${h.undone > 0 ? '${h.undone} متراجَع عنها' : 'كلها مطبقة'}',
            '${h.steps.length - 1} steps · ${h.undone > 0 ? '${h.undone} undone' : 'all applied'}'),
        key: const ValueKey('studio.history.count'),
        style: AppType.meta(context).copyWith(color: c.textMedium),
      ),
      const SizedBox(height: AppSpace.xs),
      ...rows,
      const SizedBox(height: AppSpace.xs),
      AppButton(
        key: const ValueKey('studio.history.reset'),
        label: t('العودة إلى الأصل', 'Back to the original'),
        icon: Icons.restart_alt_rounded,
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.sm,
        expand: true,
        onPressed: enabled && !h.current.isOriginal(h.steps.first.edit.duration) ? onReset : null,
      ),
      const SizedBox(height: AppSpace.xs),
      _note(t('العودة إلى الأصل خطوة جديدة أيضاً: يمكنك التراجع عنها.', 'Going back to the original is a step too: you can undo it.')),
    ]);
  }
}

/// "1:23" (a history row's length).
String mmssShort(double s) {
  final v = math.max(0, s.floor());
  final h = v ~/ 3600, m = (v % 3600) ~/ 60, sec = v % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
}
