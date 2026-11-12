// The paper exam's steps, drawn (D-697): the four answer-sheet layouts as large cards with a small schematic of each, the
// three ways to a bubble form, Copies, the attributes as chips with their coverage and a live header preview, the
// custom attribute form, the paper design card and the review. Plain values only: the layout harness pumps each one
// (test/org/offline_flow_test.dart); what loads and saves lives in the wizard and attributes_step.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../paper/exam_setup_wizard.dart' show SetupChoiceTile;
import 'exam_create_logic.dart';

const _gap = SizedBox(height: AppSpace.sm);

// the schematic's drawing sizes (a page is A4-shaped)
const _pageW = 40.0;
const _pageH = 56.0;
const _barH = 3.0;
const _dot = 5.0;

// ═══════════════════════════════════════ answer sheet ══════════════════════════════════════════════════════════

/// A small drawing of what a layout prints: the question paper, with answer lines or without, and the bubble sheet beside
/// it when there is one (true / false rows on it in option 3).
class LayoutSchematic extends StatelessWidget {
  const LayoutSchematic({super.key, required this.layout, this.active = true});
  final PaperLayout layout;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = active ? c.primary : c.textLight;
    final line = c.divider;
    Widget bar(double f, Color color) => FractionallySizedBox(
          widthFactor: f,
          alignment: AlignmentDirectional.centerStart,
          child: Container(height: _barH, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_barH))),
        );
    Widget page(List<Widget> rows) => Container(
          width: _pageW,
          height: _pageH,
          padding: const EdgeInsets.all(AppSpace.xxs),
          decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppSpace.xxs), border: Border.all(color: line)),
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        );
    final answers = layout != PaperLayout.questionsOnly;
    final paper = page([
      for (var i = 0; i < 3; i++) ...[
        bar(.85, ink.withValues(alpha: .7)),
        if (answers) bar(.6, line) else const SizedBox(height: _barH),
      ],
    ]);
    if (!layout.usesBubble) return paper;
    Widget bubbles(int n, {bool tf = false}) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < n; i++)
            Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(shape: BoxShape.circle, color: i == 1 ? (tf ? c.success : ink) : null, border: Border.all(color: tf ? c.success : ink, width: AppBorder.hairline)),
            ),
        ]);
    final sheet = page([
      for (var i = 0; i < 3; i++) bubbles(4),
      if (layout == PaperLayout.bubbleObjective) ...[bubbles(2, tf: true), bubbles(2, tf: true)] else ...[const SizedBox(height: _dot), const SizedBox(height: _dot)],
    ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [paper, const SizedBox(width: AppSpace.xxs), sheet]);
  }
}

/// "Answer sheet": one large card per layout, the best fit marked, a layout that does not fit the questions greyed with
/// the reason.
class CreateLayoutBody extends StatelessWidget {
  const CreateLayoutBody({super.key, required this.options, required this.value, required this.recommended, required this.mix, required this.onPick, this.lastUsed});
  final List<LayoutOption> options;
  final PaperLayout? value;
  final PaperLayout recommended;
  final PaperLayout? lastUsed;
  final QuestionMix mix;
  final ValueChanged<PaperLayout> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_mixText(mix), key: const ValueKey('create.layout.mix'), style: AppType.meta(context)),
      _gap,
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) _gap,
        _LayoutCard(
          number: PaperLayout.values.indexOf(options[i].layout) + 1,
          option: options[i],
          selected: value == options[i].layout,
          badge: options[i].layout == recommended && options[i].available
              ? AppBadgePill(t('الأنسب لأسئلتك', 'Best fit for your questions'), color: c.success)
              : (options[i].layout == lastUsed && options[i].available ? AppBadgePill(t('آخر اختيار', 'Last used'), color: c.primary) : null),
          onTap: options[i].available ? () => onPick(options[i].layout) : null,
        ),
      ],
    ]);
  }

  static String _mixText(QuestionMix m) {
    if (m.isFile) return t('ملف امتحان مرفوع', 'An uploaded exam file');
    final parts = [
      if (m.mcq > 0) t('${m.mcq} اختيار من متعدد', '${m.mcq} multiple choice'),
      if (m.trueFalse > 0) t('${m.trueFalse} صح وخطأ', '${m.trueFalse} true / false'),
      if (m.written > 0) t('${m.written} كتابي', '${m.written} written'),
    ];
    return parts.isEmpty ? t('لا أسئلة بعد', 'No questions yet') : t('أسئلتك: ${parts.join('، ')}', 'Your questions: ${parts.join(', ')}');
  }
}

class _LayoutCard extends StatelessWidget {
  const _LayoutCard({required this.number, required this.option, required this.selected, required this.onTap, this.badge});
  final int number;
  final LayoutOption option;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = option.layout;
    final on = option.available;
    final r = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      selected: selected,
      enabled: on,
      child: Opacity(
        opacity: on ? 1 : .6,
        child: Material(
          key: ValueKey('create.layout.${paperLayoutKey(l)}'),
          color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ExcludeSemantics(child: LayoutSchematic(layout: l, active: on)),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (badge != null) ...[badge!, const SizedBox(height: AppSpace.xxs)],
                      Text('$number. ${paperLayoutLabel(l)}', style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                      const SizedBox(height: AppSpace.xxs),
                      Text(on ? paperLayoutHint(l) : option.why ?? '', style: AppType.meta(context)),
                    ]),
                  ),
                  if (selected) ...[const SizedBox(width: AppSpace.xs), Icon(Icons.check_circle_rounded, color: c.primary, size: AppIconSize.md)],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════ bubble form ═══════════════════════════════════════════════════════════

/// The two ways to a bubble form other than a ready one: a photo of an example sheet (D-340 / D-500), or a new layout
/// learned from an upload. Above the ready sheets.
class CreateBubbleWays extends StatelessWidget {
  const CreateBubbleWays({super.key, required this.onImport, required this.onDesign});
  final VoidCallback? onImport, onDesign;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (onImport != null)
          AppPill(key: const ValueKey('create.bubble.import'), icon: Icons.photo_camera_outlined, label: t('استورد ورقة نموذجية', 'Import an example sheet'), onTap: onImport!),
        if (onDesign != null)
          AppPill(key: const ValueKey('create.bubble.design'), icon: Icons.draw_outlined, label: t('صمّم ورقة جديدة', 'Design a new sheet'), onTap: onDesign!),
      ]);
}

// ═══════════════════════════════════════ copies ════════════════════════════════════════════════════════════════

/// One generic copy (with the versions under it) or one copy per student.
class CreateCopiesBody extends StatelessWidget {
  const CreateCopiesBody({
    super.key,
    required this.copies,
    required this.hasCourse,
    required this.personalAllowed,
    required this.onCopies,
    this.whyNotPersonal,
    this.lastUsed,
    this.versions,
  });
  final SheetCopies copies;
  final bool hasCourse, personalAllowed;
  final String? whyNotPersonal;
  final SheetCopies? lastUsed;
  final ValueChanged<SheetCopies> onCopies;

  /// The versions panel, under the generic choice while it is chosen.
  final Widget? versions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tile(SheetCopies v) {
      final off = v == SheetCopies.personal && !personalAllowed;
      return Opacity(
        opacity: off ? .6 : 1,
        child: SetupChoiceTile(
          key: ValueKey('create.copies.${sheetCopiesKey(v)}'),
          icon: v == SheetCopies.personal ? Icons.badge_outlined : Icons.copy_all_rounded,
          title: v == SheetCopies.personal ? t('نسخة لكل طالب', 'One copy per student') : t('نسخة عامة واحدة', 'One generic copy'),
          subtitle: off
              ? whyNotPersonal
              : (v == SheetCopies.personal
                  ? (hasCourse
                      ? t('باسم كل طالب وبياناته من طلاب المقرر، فتُطابق كل ورقة وحدها', 'Named for each student from the course, so each paper matches by itself')
                      : t('من قائمة طلاب ترفعها (Excel أو CSV)', 'From a student list you upload (Excel or CSV)'))
                  : t('تُطبع بعدد الحاضرين، ويكتب الطالب اسمه ورقمه', 'Printed for those attending; students write their name and number')),
          selected: copies == v,
          badge: v == lastUsed && !off ? AppBadgePill(t('آخر اختيار', 'Last used'), color: c.primary) : null,
          onTap: off ? null : () => onCopies(v),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tile(SheetCopies.personal),
      _gap,
      tile(SheetCopies.generic),
      if (copies == SheetCopies.generic && versions != null) ...[const SizedBox(height: AppSpace.xs), versions!],
    ]);
  }
}

// ═══════════════════════════════════════ attributes ════════════════════════════════════════════════════════════

/// One attribute a copy can carry: its label, its coverage (unknown when [total] is 0) and a sample value.
class AttributeItem {
  const AttributeItem({required this.id, required this.label, this.filled = 0, this.total = 0, this.sample = '', this.fixed = false});
  final String id;
  final String label;
  final int filled, total;

  /// The first student's value, as it will print (masked sources show their shape).
  final String sample;

  /// Always printed (the name): cannot be taken off.
  final bool fixed;

  bool get complete => total > 0 && filled >= total;
}

/// The attributes step: the chosen attributes in their printed order (drag to reorder, tap to take off), every other one
/// to add, the coverage on each, "+ Custom attribute", and one student's header as it will print.
class CreateAttributesBody extends StatelessWidget {
  const CreateAttributesBody({
    super.key,
    required this.chosen,
    required this.available,
    required this.onToggle,
    required this.onReorder,
    required this.onCustom,
    this.studentName = '',
    this.max,
    this.saving = false,
    this.note,
  });

  final List<AttributeItem> chosen;
  final List<AttributeItem> available;
  final ValueChanged<AttributeItem> onToggle;
  final void Function(int from, int to) onReorder;
  final VoidCallback? onCustom;
  final String studentName;

  /// At most this many on a copy (null = no limit).
  final int? max;
  final bool saving;

  /// A line under the title (e.g. where the values come from).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final full = max != null && chosen.length >= max!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (note != null) ...[Text(note!, style: AppType.meta(context)), _gap],
      Text(t('على كل نسخة، بهذا الترتيب', 'On each copy, in this order'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(t('اسحب لتغيير الترتيب، واضغط لإزالة', 'Drag to reorder, tap to remove'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      ReorderableListView(
        key: const ValueKey('create.attr.chosen'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (a, b) => onReorder(a, b),
        children: [
          for (var i = 0; i < chosen.length; i++)
            Padding(
              key: ValueKey('create.attr.on.${chosen[i].id}'),
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: _AttributeRow(item: chosen[i], index: i, onRemove: chosen[i].fixed ? null : () => onToggle(chosen[i])),
            ),
        ],
      ),
      if (chosen.isEmpty) Text(t('لا شيء غير الاسم', 'Nothing but the name'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.md),
      Text(t('أضف إلى النسخة', 'Add to the copy'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final a in available)
          _AttributeChip(key: ValueKey('create.attr.off.${a.id}'), item: a, onTap: full ? null : () => onToggle(a)),
        if (onCustom != null)
          AppPill(key: const ValueKey('create.attr.custom'), icon: Icons.add_rounded, label: t('بيان مخصص', 'Custom attribute'), onTap: onCustom!),
      ]),
      if (full) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('وصلت إلى الحد الأقصى ($max). أزل بيانًا لتضيف غيره.', 'That is the most a copy holds ($max). Remove one to add another.'), style: AppType.meta(context).copyWith(color: c.warning)),
      ],
      const SizedBox(height: AppSpace.md),
      AttributeHeaderPreview(name: studentName, lines: [for (final a in chosen) if (!a.fixed) (a.label, a.sample)], saving: saving),
    ]);
  }
}

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({required this.item, required this.index, required this.onRemove});
  final AttributeItem item;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cov = attributeCoverageText(item.filled, item.total);
    return Container(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, end: AppSpace.xxs),
      decoration: BoxDecoration(color: c.primary.withValues(alpha: .06), borderRadius: AppRadius.controlAll, border: Border.all(color: c.primary.withValues(alpha: .4))),
      child: Row(children: [
        ReorderableDragStartListener(
          index: index,
          child: Tooltip(
            message: t('اسحب لتغيير الترتيب', 'Drag to reorder'),
            child: SizedBox(width: AppTouch.min, height: AppTouch.min, child: Icon(Icons.drag_indicator_rounded, color: c.textLight, size: AppIconSize.md)),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(item.label, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (cov.isNotEmpty) Text(cov, style: AppType.meta(context).copyWith(color: item.complete ? c.success : c.warning)),
          ]),
        ),
        if (onRemove != null)
          IconButton(tooltip: t('إزالة', 'Remove'), onPressed: onRemove, icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight))
        else
          Padding(padding: const EdgeInsets.all(AppSpace.sm), child: Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: c.textLight)),
      ]),
    );
  }
}

class _AttributeChip extends StatelessWidget {
  const _AttributeChip({super.key, required this.item, required this.onTap});
  final AttributeItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cov = attributeCoverageText(item.filled, item.total);
    return Semantics(
      button: true,
      label: cov.isEmpty ? item.label : '${item.label}, $cov',
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
              child: ExcludeSemantics(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: AppIconSize.sm, color: onTap == null ? c.textLight : c.primary),
                    const SizedBox(width: AppSpace.xxs),
                    Flexible(child: Text(item.label, style: AppType.label(context).copyWith(color: c.textDark), overflow: TextOverflow.ellipsis)),
                  ]),
                  if (cov.isNotEmpty) Text(cov, style: AppType.meta(context)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One student's copy header as it will print: the name, then each attribute with its value.
class AttributeHeaderPreview extends StatelessWidget {
  const AttributeHeaderPreview({super.key, required this.name, required this.lines, this.saving = false});
  final String name;
  final List<(String, String)> lines;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Flexible(child: Text('$label:', style: AppType.meta(context).copyWith(color: c.textLight))),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              flex: 2,
              child: Text(value.isEmpty ? '…………' : value, style: AppType.label(context).copyWith(color: c.textDark), overflow: TextOverflow.ellipsis),
            ),
          ]),
        );
    return AppCard(
      key: const ValueKey('create.attr.preview'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.visibility_outlined, size: AppIconSize.sm, color: c.textLight),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(t('معاينة رأس نسخة طالب', 'Preview of one student\'s header'), style: AppType.meta(context))),
          if (saving) Text(t('يُحفظ ...', 'Saving ...'), style: AppType.meta(context)),
        ]),
        const SizedBox(height: AppSpace.xs),
        row(t('الاسم', 'Name'), name),
        for (final (l, v) in lines) row(l, v),
      ]),
    );
  }
}

/// How a custom attribute gets its values.
enum CustomAttributeWay { typed, fileColumn, upload }

/// The answer of the custom attribute form.
typedef CustomAttribute = ({String labelAr, String labelEn, CustomAttributeWay way});

/// "+ Custom attribute": its name in Arabic and English, and where the values come from. [ways]: the ones on offer
/// (a column of the student list only for an exam whose students came from a file).
class CustomAttributeForm extends StatefulWidget {
  const CustomAttributeForm({super.key, required this.onDone, this.ways = const [CustomAttributeWay.typed, CustomAttributeWay.upload]});
  final ValueChanged<CustomAttribute> onDone;
  final List<CustomAttributeWay> ways;

  @override
  State<CustomAttributeForm> createState() => _CustomAttributeFormState();
}

class _CustomAttributeFormState extends State<CustomAttributeForm> {
  final _ar = TextEditingController();
  final _en = TextEditingController();
  late CustomAttributeWay _way = widget.ways.first;
  bool _tried = false;

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  void _done() {
    final ar = _ar.text.trim(), en = _en.text.trim();
    if (ar.isEmpty && en.isEmpty) return setState(() => _tried = true);
    widget.onDone((labelAr: ar.isEmpty ? en : ar, labelEn: en.isEmpty ? ar : en, way: _way));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String label(CustomAttributeWay w) => switch (w) {
          CustomAttributeWay.typed => t('أكتب القيم', 'Type the values'),
          CustomAttributeWay.fileColumn => t('من عمود في قائمة الطلاب', 'From a column of the student list'),
          CustomAttributeWay.upload => t('من ملف Excel أو CSV', 'From an Excel or CSV file'),
        };
    IconData icon(CustomAttributeWay w) => switch (w) {
          CustomAttributeWay.typed => Icons.keyboard_outlined,
          CustomAttributeWay.fileColumn => Icons.view_column_outlined,
          CustomAttributeWay.upload => Icons.upload_file_rounded,
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(key: const ValueKey('create.attr.new.ar'), controller: _ar, label: t('الاسم بالعربية', 'Name in Arabic'), hint: t('مثال: رقم المقعد', 'e.g. رقم المقعد')),
      const SizedBox(height: AppSpace.xs),
      AppField(key: const ValueKey('create.attr.new.en'), controller: _en, label: t('الاسم بالإنجليزية', 'Name in English'), hint: t('مثال: Seat number', 'e.g. Seat number')),
      if (_tried) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(t('اكتب اسمًا واحدًا على الأقل', 'Write at least one name'), style: AppType.meta(context).copyWith(color: c.danger)),
      ],
      const SizedBox(height: AppSpace.md),
      Text(t('من أين تأتي القيم؟', 'Where do the values come from?'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xs),
      for (final w in widget.ways) ...[
        SetupChoiceTile(key: ValueKey('create.attr.way.${w.name}'), icon: icon(w), title: label(w), selected: _way == w, onTap: () => setState(() => _way = w)),
        const SizedBox(height: AppSpace.xs),
      ],
      const SizedBox(height: AppSpace.xs),
      AppButton.primary(key: const ValueKey('create.attr.new.done'), label: t('أضف البيان', 'Add the attribute'), onPressed: _done, expand: true),
    ]);
  }
}

// ═══════════════════════════════════════ paper design ══════════════════════════════════════════════════════════

/// The paper design step: what the header will carry, and the one button into the design engine.
class CreatePaperDesignBody extends StatelessWidget {
  const CreatePaperDesignBody({super.key, required this.designed, required this.attributes, required this.onDesign, this.busy = false});
  final bool designed;

  /// The labels the header prints, in order (the name first).
  final List<String> attributes;
  final VoidCallback? onDesign;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        key: const ValueKey('create.design.card'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(designed ? Icons.check_circle_rounded : Icons.design_services_outlined, color: designed ? c.success : c.primary, size: AppIconSize.lg),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(designed ? t('صمّمت ورقة هذا الاختبار', 'This exam\'s paper is designed') : t('التصميم الافتراضي', 'The default design'),
                  style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text(
              designed
                  ? t('يمكنك تعديله الآن أو لاحقًا من صفحة الطباعة', 'You can change it now, or later from the printing page')
                  : t('الشعار والرأس وترتيب بيانات الطالب. يمكنك المتابعة بالتصميم الافتراضي', 'The logo, the header and where the student details go. You can continue with the default'),
              style: AppType.meta(context)),
          if (attributes.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(t('في رأس كل نسخة', 'In each copy\'s header'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [for (final a in attributes) AppBadgePill(a, color: c.primary)]),
          ],
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              key: const ValueKey('create.design.open'),
              label: designed ? t('عدّل التصميم', 'Edit the design') : t('صمّم الورقة', 'Design the paper'),
              icon: Icons.brush_outlined,
              busy: busy,
              onPressed: onDesign,
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ═══════════════════════════════════════ review ════════════════════════════════════════════════════════════════

/// One line of the review: the step it belongs to, so a tap goes back there.
typedef ReviewLine = ({CreateStep step, String label, String value});

class CreateReviewBody extends StatelessWidget {
  const CreateReviewBody({super.key, required this.lines, required this.onEdit, this.notes = const []});
  final List<ReviewLine> lines;
  final ValueChanged<CreateStep>? onEdit;

  /// What still deserves a look (e.g. students missing a value).
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        key: const ValueKey('create.review'),
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, color: c.divider),
            InkWell(
              key: ValueKey('create.review.${lines[i].step.name}'),
              onTap: onEdit == null ? null : () => onEdit!(lines[i].step),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(lines[i].label, style: AppType.meta(context)),
                        Text(lines[i].value, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (onEdit != null) Icon(Icons.edit_outlined, size: AppIconSize.sm, color: c.textLight),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
      for (final n in notes) ...[const SizedBox(height: AppSpace.sm), AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: n)],
    ]);
  }
}
