// lib/features/org/org_schedule_ladder_ui.dart — the relaxation ladder's screens (docs/backend/ladder-spec.md, D-013).
//
// Every piece takes plain values (the models of org_schedule_ladder.dart) and callbacks, so the layout harness pumps
// it (test/ui/ladder_layout_test.dart); the thin wrappers at the end connect them to OrgScheduleProvider.
//
//   LadderEditor · showLadderSheet          the rungs in priority order (drag handle + up / down arrows, a mode per rung:
//                                           Auto · Ask me · Locked), the rules that are never broken, the numeric options,
//                                           presets, Save / Save & generate (+ "Fully automatic")
//   LadderOverlay · LadderLivePanel · LadderVeil · showLadderOverlay
//                                           the live run: what happens now, placed / remaining / conflicts, the rung being
//                                           relaxed and why, elapsed of budget, the step log, Cancel — and, while the run
//                                           waits, the decision inline (or a "Choose…" button that opens the dialog)
//   LadderDecisionCard · showLadderDecisionDialog
//                                           the fork: the situation, one card per option (impact, rules bent, the
//                                           recommended one marked), "stop" last, "Let the system decide"
//   LadderResultCard                        after the run: the summary, the rung table, structural additions, the proof
//                                           line, blocked-by advice (opens the ladder), the decisions log, Accept all
library;

import 'package:flutter_education_app/design/app_mesh.dart';
import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppDropdown, AppField, AppPrimaryButton, AppSwitchTile, appConfirm, showAppSheet;

import '../admin/admin_common.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_schedule_generate.dart' show LiveStep, liveClock, showRulesSheet, unplacedReasonText;
import 'org_schedule_ladder.dart';
import 'org_ui.dart' show orgText;
import 'org_v3.dart' show runIsOpen;

// ═════════════════════════════════════════════════════════════════════════════
//  Small shared pieces
// ═════════════════════════════════════════════════════════════════════════════

/// A rung mode in the current language.
String ladderModeLabel(String mode) => switch (mode) {
      'auto' => t('تلقائي', 'Auto'),
      'ask' => t('اسألني', 'Ask me'),
      'locked' => t('مقفلة', 'Locked'),
      _ => mode,
    };

IconData ladderModeIcon(String mode) => switch (mode) {
      'auto' => Icons.bolt_rounded,
      'ask' => Icons.help_outline_rounded,
      'locked' => Icons.lock_rounded,
      _ => Icons.circle_outlined,
    };

Color _modeColor(BuildContext context, String mode) {
  final c = context.colors;
  return switch (mode) { 'auto' => c.primary, 'ask' => c.warning, 'locked' => c.textMedium, _ => c.textMedium };
}

Widget _pill(BuildContext context, String text, Color col, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: col), const SizedBox(width: 4)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 11, w: FontWeight.w700, color: col))),
      ]),
    );

Widget _sectionTitle(BuildContext context, String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      // the trailing button shares the width (its label wraps) so a long label never pushes the title out
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text(text, style: orgText(context, size: 12.5, w: FontWeight.w800, color: context.colors.textMedium))),
        if (trailing != null) Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing)),
      ]),
    );

/// The three modes as chips (a Wrap: never wider than the phone).
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.value, required this.modes, this.onChanged});
  final String value;
  final List<String> modes;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final m in modes)
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onChanged == null ? null : () => onChanged!(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: m == value ? _modeColor(context, m).withValues(alpha: 0.14) : c.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: m == value ? _modeColor(context, m) : c.divider, width: m == value ? 1.4 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ladderModeIcon(m), size: 15, color: m == value ? _modeColor(context, m) : c.textMedium),
                const SizedBox(width: 4),
                Text(ladderModeLabel(m), style: orgText(context, size: 11.5, w: FontWeight.w700, color: m == value ? _modeColor(context, m) : c.textMedium)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// A whole-number field that keeps its own controller and follows the value when it changes from outside (a preset,
/// a reset) without losing the caret while typing.
class _IntField extends StatefulWidget {
  const _IntField({required this.label, required this.value, required this.onChanged, this.min = 0, this.max = 1 << 30, this.enabled = true});
  final String label;
  final int value;
  final int min, max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _ctrl = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _IntField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && int.tryParse(_ctrl.text.trim()) != widget.value) _ctrl.text = '${widget.value}';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !widget.enabled,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.55,
          child: AppField(
            controller: _ctrl,
            label: widget.label,
            keyboard: TextInputType.number,
            ltr: true,
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null) widget.onChanged(n.clamp(widget.min, widget.max));
            },
          ),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  1. The editor
// ═════════════════════════════════════════════════════════════════════════════

class _RungTile extends StatelessWidget {
  const _RungTile({super.key, required this.index, required this.rung, required this.catalog, required this.modes, this.onMode, this.onUp, this.onDown, this.enabled = true});
  final int index;
  final LadderRung rung;
  final LadderCatalogRung? catalog;
  final List<String> modes;
  final ValueChanged<String>? onMode;
  final VoidCallback? onUp, onDown;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pinned = rung.key == 'free_moves';
    final name = catalog?.name ?? rung.name;
    final why = catalog?.why ?? rung.why;
    final col = pinned ? c.success : _modeColor(context, rung.mode);
    Widget arrow(IconData icon, VoidCallback? on, String tip) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          iconSize: 20,
          onPressed: enabled ? on : null,
          icon: Icon(icon),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rung.locked ? c.divider : col.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (pinned || !enabled)
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(pinned ? Icons.push_pin_rounded : Icons.drag_indicator_rounded, size: 20, color: c.textLight))
        else
          ReorderableDragStartListener(
            index: index,
            child: Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.drag_indicator_rounded, size: 20, color: c.textMedium)),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 11, backgroundColor: col.withValues(alpha: 0.14), child: Text('${index + 1}', style: orgText(context, size: 11, w: FontWeight.w800, color: col))),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: orgText(context, size: 13.5, w: FontWeight.w800, color: rung.locked ? c.textMedium : c.textDark))),
            ]),
            if (why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(why, style: orgText(context, size: 12, color: c.textMedium))),
            const SizedBox(height: 7),
            if (pinned)
              _pill(context, t('دائماً أولاً — لا يُكسر شيء', 'Always first — nothing is broken'), c.success, icon: Icons.check_rounded)
            else
              _ModePicker(value: rung.mode, modes: modes, onChanged: enabled ? onMode : null),
          ]),
        ),
        if (!pinned)
          Column(mainAxisSize: MainAxisSize.min, children: [
            arrow(Icons.keyboard_arrow_up_rounded, onUp, t('أعلى (أرخص)', 'Up (cheaper)')),
            arrow(Icons.keyboard_arrow_down_rounded, onDown, t('أسفل (أغلى)', 'Down (costlier)')),
          ]),
      ]),
    );
  }
}

/// The ladder editor. [config] is the single source of truth: every change goes out through [onChanged] with a new
/// config (the models are immutable), so the caller keeps it and feeds it back.
class LadderEditor extends StatefulWidget {
  const LadderEditor({
    super.key,
    required this.config,
    required this.onChanged,
    this.onSave,
    this.onSaveAndGenerate,
    this.onSavePreset,
    this.onDeletePreset,
    this.onApplyPreset,
    this.onLegacyRules,
    this.canEdit = true,
    this.busy = false,
  });
  final LadderConfig config;
  final ValueChanged<LadderConfig> onChanged;
  final VoidCallback? onSave;
  /// `auto` true: the run never asks (every "Ask me" rung is decided by the system).
  final void Function(bool auto)? onSaveAndGenerate;
  final ValueChanged<String>? onSavePreset; // the name
  final ValueChanged<String>? onDeletePreset; // the preset id
  final ValueChanged<LadderPreset>? onApplyPreset;
  /// The legacy Locked / Flexible rules sheet (settings.rules, still used by the quick actions).
  final VoidCallback? onLegacyRules;
  final bool canEdit, busy;

  @override
  State<LadderEditor> createState() => _LadderEditorState();
}

class _LadderEditorState extends State<LadderEditor> {
  bool _auto = false;
  bool _options = false;

  LadderConfig get cfg => widget.config;
  bool get _on => widget.canEdit && !widget.busy;

  void _reorder(int from, int to) {
    if (from == 0) return;
    var target = to > from ? to - 1 : to;
    if (target < 1) target = 1;
    if (target == from) return;
    widget.onChanged(cfg.moveRung(cfg.ladder[from].key, target - from));
  }

  Future<void> _savePreset() async {
    final name = await askText(context, title: t('اسم الإعداد', 'Preset name'), hint: t('مثل: أسبوع الامتحانات', 'e.g. Exams week'));
    if (name == null || name.trim().isEmpty) return;
    widget.onSavePreset?.call(name.trim());
  }

  Future<void> _deletePreset(LadderPreset p) async {
    final ok = await appConfirm(context, message: t('حذف الإعداد «${p.name}»؟', 'Delete the preset "${p.name}"?'), danger: true, confirmLabel: t('حذف', 'Delete'));
    if (ok) widget.onDeletePreset?.call(p.id);
  }

  Widget _options_(BuildContext context) {
    final c = context.colors;
    final o = cfg.options;
    void set(LadderOptions n) => widget.onChanged(cfg.copyWith(options: n));
    Widget two(Widget a, Widget b) => LayoutBuilder(builder: (ctx, box) {
          if (box.maxWidth < 420) return Column(children: [a, const SizedBox(height: 8), b]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      two(
        _IntField(label: t('ميزانية التشغيل (دقائق)', 'Run budget (minutes)'), value: (o.budgetS / 60).round(), min: 1, max: 120, enabled: _on, onChanged: (v) => set(o.copyWith(budgetS: v * 60))),
        _IntField(label: t('مهلة القرار (دقائق)', 'Decision timeout (minutes)'), value: (o.decisionTimeoutS / 60).round(), min: 1, max: 240, enabled: _on, onChanged: (v) => set(o.copyWith(decisionTimeoutS: v * 60))),
      ),
      const SizedBox(height: 4),
      AppSwitchTile(
        title: t('زمن الحل حسب حجم الجدول', 'Solve time by size'),
        subtitle: o.solveS == null
            ? t('كل محاولة تأخذ وقتاً يناسب عدد الحصص (10 ث إلى دقيقتين)', 'Each solve gets a time that fits the number of sessions (10 s to 2 min)')
            : t('كل محاولة تأخذ ${o.solveS} ثانية بالضبط', 'Each solve gets exactly ${o.solveS} seconds'),
        value: o.solveS == null,
        dense: true,
        onChanged: _on ? (v) => set(v ? o.copyWith(clearSolveS: true) : o.copyWith(solveS: 60)) : null,
      ),
      if (o.solveS != null) ...[
        _IntField(label: t('زمن المحاولة الواحدة (ثوانٍ)', 'One solve (seconds)'), value: o.solveS!, min: 3, max: 600, enabled: _on, onChanged: (v) => set(o.copyWith(solveS: v))),
        const SizedBox(height: 8),
      ],
      two(
        _IntField(label: t('تجاوز السعة (%)', 'Over capacity (%)'), value: o.overflowPct, min: 0, max: 50, enabled: _on, onChanged: (v) => set(o.copyWith(overflowPct: v))),
        _IntField(label: t('أقصى قاعات جديدة', 'Max new rooms'), value: o.maxNewRooms, min: 0, max: 50, enabled: _on, onChanged: (v) => set(o.copyWith(maxNewRooms: v))),
      ),
      const SizedBox(height: 8),
      two(
        _IntField(label: t('أقصى فترات جديدة', 'Max new periods'), value: o.maxNewPeriods, min: 0, max: 10, enabled: _on, onChanged: (v) => set(o.copyWith(maxNewPeriods: v))),
        _IntField(label: t('أقصى أيام جديدة', 'Max new days'), value: o.maxNewDays, min: 0, max: 7, enabled: _on, onChanged: (v) => set(o.copyWith(maxNewDays: v))),
      ),
      const SizedBox(height: 8),
      Text(t('خيارات كل قرار', 'Options per decision'), style: orgText(context, size: 12, color: c.textMedium)),
      const SizedBox(height: 4),
      AppDropdown<int>(
        value: o.forkOptions.clamp(1, 4),
        enabled: _on,
        items: [for (var n = 1; n <= 4; n++) DropdownMenuItem(value: n, child: Text('$n'))],
        onChanged: (v) => set(o.copyWith(forkOptions: v ?? o.forkOptions)),
      ),
      const SizedBox(height: 4),
      AppSwitchTile(
        title: t('نتيجة قابلة للتكرار', 'Reproducible result'),
        subtitle: t('نفس البيانات ونفس البذرة يعطيان الجدول نفسه (أبطأ)', 'The same data and seed give the same timetable (slower)'),
        value: o.deterministic,
        onChanged: _on ? (v) => set(o.copyWith(deterministic: v)) : null,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ladder = cfg.ladder;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        t('السلّم هو ترتيب ما يُسمح بكسره عندما لا تجد حصة مكاناً: الأعلى أرخص ويُجرَّب أولاً. «تلقائي» يُكسر ويُسجَّل، «اسألني» يوقف التشغيل ويسألك، «مقفلة» لا تُكسر أبداً.',
            'The ladder is the order of what may give way when a session does not fit: the top is the cheapest and is tried first. "Auto" breaks and logs, "Ask me" pauses the run and asks you, "Locked" is never broken.'),
        style: orgText(context, size: 12, color: c.textMedium),
      ),
      _sectionTitle(
        context,
        t('الدرجات — بترتيب الأولوية', 'Rungs — in priority order'),
        trailing: TextButton(
          onPressed: _on && !cfg.isDefault ? () => widget.onChanged(cfg.resetToDefault()) : null,
          child: Text(t('استعادة الافتراضي', 'Reset to default')),
        ),
      ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: ladder.length,
        onReorder: _reorder,
        proxyDecorator: (child, _, _) => Material(color: Colors.transparent, elevation: 6, borderRadius: BorderRadius.circular(14), child: child),
        itemBuilder: (ctx, i) => _RungTile(
          key: ValueKey(ladder[i].key),
          index: i,
          rung: ladder[i],
          catalog: cfg.catalogRung(ladder[i].key),
          modes: cfg.modes,
          enabled: _on,
          onMode: (m) => widget.onChanged(cfg.setMode(ladder[i].key, m)),
          onUp: i > 1 ? () => widget.onChanged(cfg.moveRung(ladder[i].key, -1)) : null,
          onDown: i < ladder.length - 1 ? () => widget.onChanged(cfg.moveRung(ladder[i].key, 1)) : null,
        ),
      ),
      _sectionTitle(context, t('لا تُكسر أبداً', 'Never broken')),
      for (final f in cfg.fixed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_rounded, size: 16, color: c.textLight),
            const SizedBox(width: 8),
            Expanded(child: Text(f.text, style: orgText(context, size: 12.5, color: c.textMedium))),
          ]),
        ),
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _options = !_options),
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(children: [
            Expanded(child: Text(t('الخيارات', 'Options'), style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.textMedium))),
            Icon(_options ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: c.textMedium),
          ]),
        ),
      ),
      if (_options) _options_(context),
      _sectionTitle(context, t('إعدادات محفوظة', 'Presets')),
      if (cfg.presets.isEmpty && !widget.canEdit)
        Text(t('لا إعدادات محفوظة', 'No presets yet'), style: orgText(context, size: 12, color: c.textLight)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in cfg.presets)
          InputChip(
            avatar: Icon(Icons.bookmark_rounded, size: 16, color: c.primary),
            label: Text(p.name, overflow: TextOverflow.ellipsis),
            tooltip: t('تطبيق هذا الإعداد', 'Apply this preset'),
            onPressed: _on && widget.onApplyPreset != null ? () => widget.onApplyPreset!(p) : null,
            onDeleted: _on && widget.onDeletePreset != null ? () => _deletePreset(p) : null,
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            deleteButtonTooltipMessage: t('حذف', 'Delete'),
          ),
        if (widget.canEdit && widget.onSavePreset != null)
          ActionChip(
            avatar: Icon(Icons.bookmark_add_outlined, size: 16, color: c.primary),
            label: Text(t('حفظ كإعداد…', 'Save as preset…')),
            onPressed: _on ? _savePreset : null,
          ),
      ]),
      if (widget.canEdit) ...[
        const SizedBox(height: 14),
        AppSwitchTile(
          title: t('تلقائي بالكامل (لا تسألني)', 'Fully automatic (never ask me)'),
          subtitle: t('كل درجة «اسألني» يقررها النظام بنفسه ويُسجَّل القرار', 'Every "Ask me" rung is decided by the system and the decision is logged'),
          icon: Icons.auto_mode_rounded,
          value: _auto,
          dense: true,
          onChanged: _on ? (v) => setState(() => _auto = v) : null,
        ),
        const SizedBox(height: 8),
        if (widget.onSaveAndGenerate != null)
          AppPrimaryButton(
            label: t('حفظ وتوليد الجدول', 'Save & generate'),
            icon: Icons.auto_awesome_rounded,
            busy: widget.busy,
            onPressed: _on ? () => widget.onSaveAndGenerate!(_auto) : null,
          ),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (widget.onSave != null) TextButton(onPressed: _on ? widget.onSave : null, child: Text(t('حفظ السلّم فقط', 'Save the ladder'))),
          if (widget.onLegacyRules != null)
            TextButton.icon(
              onPressed: widget.busy ? null : widget.onLegacyRules,
              icon: const Icon(Icons.rule_rounded, size: 16),
              label: Text(t('القواعد القديمة…', 'Legacy rules…')),
            ),
        ]),
      ] else if (widget.onLegacyRules != null)
        Center(child: TextButton(onPressed: widget.onLegacyRules, child: Text(t('القواعد القديمة…', 'Legacy rules…')))),
    ]);
  }
}

/// The ladder sheet of timetable [sid]: load → edit → save / save & generate. An older server without the ladder
/// route (or a failed load) gets the legacy rules sheet instead.
Future<void> showLadderSheet(BuildContext context, OrgScheduleProvider p, int sid, {bool canEdit = true}) async {
  final loaded = await p.loadLadder(sid);
  if (!context.mounted) return;
  if (loaded == null) {
    toast(t('سلّم التوليد يحتاج تحديث الخادم — تُعرض القواعد القديمة', 'The generation ladder needs a server update — showing the legacy rules'), error: true);
    return showRulesSheet(context, p, canEdit: canEdit);
  }
  var cfg = loaded;
  var busy = false;
  await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<LadderConfig?> save() async {
          set(() => busy = true);
          final saved = await p.saveLadder(sid, cfg);
          if (!ctx.mounted) return null;
          set(() {
            busy = false;
            if (saved != null) cfg = saved;
          });
          return saved;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('سلّم التوليد', 'Generation ladder')),
            LadderEditor(
              config: cfg,
              canEdit: canEdit,
              busy: busy,
              onChanged: (n) => set(() => cfg = n),
              onSave: () async {
                if (await save() != null && ctx.mounted) Navigator.pop(ctx);
              },
              onSaveAndGenerate: (auto) async {
                if (await save() == null || !ctx.mounted) return;
                set(() => busy = true);
                final r = await p.startLadder(sid, auto: auto);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r.ok || r.code == 'generation_running') Navigator.pop(ctx);
              },
              onSavePreset: (name) async {
                final saved = await p.savePreset(name, cfg);
                if (saved != null && ctx.mounted) set(() => cfg = cfg.copyWith(presets: [...cfg.presets.where((x) => x.id != saved.id), saved]));
              },
              onDeletePreset: (id) async {
                if (await p.deletePreset(id) && ctx.mounted) set(() => cfg = cfg.copyWith(presets: [...cfg.presets.where((x) => x.id != id)]));
              },
              onApplyPreset: (preset) => set(() => cfg = cfg.applyPreset(preset)),
              onLegacyRules: () {
                Navigator.pop(ctx);
                showRulesSheet(context, p, canEdit: canEdit);
              },
            ),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  3. The decision
// ═════════════════════════════════════════════════════════════════════════════

/// The fork a waiting run asks about. [onChoose] gets an option id, or `auto` for "let the system decide".
class LadderDecisionCard extends StatelessWidget {
  const LadderDecisionCard({super.key, required this.decision, required this.onChoose, this.busy = false});
  final LadderDecision decision;
  final ValueChanged<String> onChoose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = decision;
    final rec = d.recommendedOption;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warning.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.alt_route_rounded, color: c.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(t('قرارك مطلوب', 'Your decision'), style: orgText(context, size: 14, w: FontWeight.w800, color: c.textDark))),
        ]),
        const SizedBox(height: 4),
        if (d.required > 0)
          Text(t('وُضعت ${d.placed} من ${d.required} حصة · ${d.unplaced} بلا موعد', '${d.placed} of ${d.required} placed · ${d.unplaced} unplaced'),
              style: orgText(context, size: 12, w: FontWeight.w700, color: c.textMedium)),
        if (d.situation.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d.situation, style: orgText(context, size: 12.5, color: c.textDark))),
        if (d.top.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final (reason, n) in d.top) _pill(context, '$n × ${unplacedReasonText(reason)}', c.textMedium)]),
          ),
        const SizedBox(height: 10),
        for (final o in orderedOptions(d)) _OptionCard(option: o, onChoose: busy || !o.possible ? null : () => onChoose(o.id)),
        if (busy) const Padding(padding: EdgeInsets.only(top: 4, bottom: 8), child: LinearProgressIndicator(minHeight: 3)),
        AppPrimaryButton(
          label: t('دع النظام يقرر', 'Let the system decide'),
          icon: Icons.auto_mode_rounded,
          busy: busy,
          onPressed: () => onChoose('auto'),
        ),
        if (rec != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('يطبّق التوصية: ${rec.name}', 'Applies the recommendation: ${rec.name}'),
                textAlign: TextAlign.center, style: orgText(context, size: 11.5, color: c.textMedium)),
          ),
      ]),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, this.onChoose});
  final LadderOption option;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = option;
    final impact = o.impact;
    final border = o.recommended ? c.primary : (o.isStop ? c.textLight : c.divider);
    final dim = !o.possible;
    final label = o.isStop ? t('التوقف هنا', 'Stop here') : t('اختر: ${o.name}', 'Choose: ${o.name}');
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: o.recommended ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(o.isStop ? Icons.stop_circle_outlined : Icons.stairs_rounded, size: 18, color: o.isStop ? c.textMedium : c.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(o.name, style: orgText(context, size: 13, w: FontWeight.w800, color: c.textDark))),
            if (o.recommended) ...[const SizedBox(width: 6), _pill(context, t('موصى به', 'Recommended'), c.primary, icon: Icons.star_rounded)],
          ]),
          if (o.why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(o.why, style: orgText(context, size: 12, color: c.textMedium))),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(impactText(o), style: orgText(context, size: 12.5, w: FontWeight.w700, color: impact?.complete == true ? c.success : c.textDark)),
          ),
          if (impact != null && impact.brokenByRung.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in impact.brokenByRung.entries) _pill(context, '${rungName(e.key)} ×${e.value}', c.warning, icon: Icons.rule_rounded),
              ]),
            ),
          if (o.recommended && o.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline_rounded, size: 14, color: c.primary),
                const SizedBox(width: 4),
                Expanded(child: Text(o.reason, style: orgText(context, size: 11.5, color: c.primary))),
              ]),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: o.recommended
                ? FilledButton.tonalIcon(onPressed: onChoose, icon: const Icon(Icons.check_rounded, size: 18), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))
                : OutlinedButton(onPressed: onChoose, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ),
        ]),
      ),
    );
  }
}

/// The decision as a dialog, for when the overlay is not open (the studio is open and the run turns `waiting`). It
/// closes by itself when the run moves on (someone else answered, or the timeout applied the recommendation).
Future<void> showLadderDecisionDialog(BuildContext context, OrgScheduleProvider p, LadderDecision decision) => showDialog<void>(
      context: context,
      builder: (_) => Directionality(textDirection: dir, child: _DecisionDialog(p: p, decision: decision)),
    );

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.p, required this.decision});
  final OrgScheduleProvider p;
  final LadderDecision decision;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  bool _busy = false, _popped = false;

  @override
  void initState() {
    super.initState();
    widget.p.addListener(_check);
  }

  @override
  void dispose() {
    widget.p.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final live = LadderLive.of(widget.p.genRun);
    final gone = live == null || !live.isWaiting || live.decision?.id != widget.decision.id;
    if (gone && !_busy) _close();
  }

  void _close() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  Future<void> _choose(String id) async {
    setState(() => _busy = true);
    final r = await widget.p.decide(widget.decision.id, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) _close();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t('التوليد يسألك', 'The generation asks you'), style: orgText(context, size: 15, w: FontWeight.w800, color: c.textDark))),
              IconButton(tooltip: t('إزالة', 'Remove'), onPressed: _busy ? null : _close, icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20)),
            ]),
            LadderDecisionCard(decision: widget.decision, busy: _busy, onChoose: _choose),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  2. The live overlay
// ═════════════════════════════════════════════════════════════════════════════

/// The live state of a ladder run. With [onDecide] the decision is rendered inline (LadderDecisionCard); without it
/// a waiting run shows a "Choose…" button that calls [onOpenDecision]. [compact] is the veil over the grid.
class LadderOverlay extends StatefulWidget {
  const LadderOverlay({
    super.key,
    required this.live,
    this.onCancel,
    this.onDecide,
    this.onOpenDecision,
    this.compact = false,
    this.busy = false,
    this.error,
    this.progress,
  });
  final LadderLive live;
  final VoidCallback? onCancel;
  final void Function(String decisionId, String optionId)? onDecide;
  final VoidCallback? onOpenDecision;
  final bool compact, busy;
  final String? error; // run.error when the run failed
  final int? progress; // run.progress (0..100), used while the ladder counters are still empty

  @override
  State<LadderOverlay> createState() => _LadderOverlayState();
}

class _LadderOverlayState extends State<LadderOverlay> {
  Timer? _tick;
  DateTime _received = DateTime.now();
  bool _all = false;

  bool get _open => ladderStatusOpen(widget.live.status);

  @override
  void initState() {
    super.initState();
    _ensureTick();
  }

  @override
  void didUpdateWidget(covariant LadderOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.live, widget.live)) _received = DateTime.now();
    _ensureTick();
  }

  void _ensureTick() {
    if (_open && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_open && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = widget.live;
    final open = _open;
    final failed = live.status == 'failed';
    final waiting = live.isWaiting && live.decision != null;
    final accent = failed ? c.danger : (live.isWaiting ? c.warning : c.primary);
    final elapsed = Duration(seconds: live.elapsedS) + (open && !live.isWaiting ? DateTime.now().difference(_received) : Duration.zero);
    final budget = live.budgetS;
    final steps = live.steps;
    final current = live.current;
    final shown = _all || steps.length <= 6 ? steps : steps.sublist(steps.length - 6);
    final bar = live.required > 0 ? live.pct / 100 : (widget.progress == null ? null : widget.progress!.clamp(0, 100) / 100);

    Widget counter(String label, String value, Color col) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: col.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: orgText(context, size: 15, w: FontWeight.w800, color: col)),
            Text(label, style: orgText(context, size: 10.5, color: c.textMedium)),
          ]),
        );

    Widget stepRow(LiveStep s) {
      final now = !s.done;
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 18,
            height: 18,
            child: now
                ? (open ? const Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.remove_rounded, size: 16, color: c.textLight))
                : Icon(s.kind == 'decision' || s.kind == 'decided' ? Icons.alt_route_rounded : Icons.check_circle_rounded, size: 16, color: now ? c.textDark : c.textLight),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.elapsedS != null && s.elapsedS! >= 1 ? '${s.text} · ${liveClock(Duration(seconds: s.elapsedS!.round()))}' : s.text,
              style: orgText(context, size: 12.5, w: now ? FontWeight.w700 : FontWeight.w400, color: now ? c.textDark : c.textLight),
            ),
          ),
        ]),
      );
    }

    final header = Row(children: [
      SizedBox(
        width: 24,
        height: 24,
        child: failed
            ? Icon(Icons.error_rounded, color: accent)
            : live.isWaiting
                ? Icon(Icons.pan_tool_rounded, color: accent, size: 22)
                : open
                    ? Padding(padding: const EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.4, color: accent))
                    : Icon(Icons.check_circle_rounded, color: c.success),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(ladderHeadline(live), style: orgText(context, w: FontWeight.w800))),
      if (widget.onCancel != null && open)
        TextButton(onPressed: widget.busy ? null : widget.onCancel, child: Text(t('إلغاء', 'Cancel'), style: TextStyle(color: c.danger))),
    ]);

    final clock = Wrap(spacing: 10, runSpacing: 2, children: [
      Text(
        budget != null && budget > 0
            ? t('المدة ${liveClock(elapsed)} من ${liveClock(Duration(seconds: budget))} كحد أقصى', 'Elapsed ${liveClock(elapsed)} of up to ${liveClock(Duration(seconds: budget))}')
            : t('المدة ${liveClock(elapsed)}', 'Elapsed ${liveClock(elapsed)}'),
        style: orgText(context, size: 12, color: c.textMedium),
      ),
      if (live.solves > 0) Text(t('${live.solves} محاولة حل', '${live.solves} solve(s)'), style: orgText(context, size: 12, color: c.textMedium)),
    ]);

    Widget waitingBanner() => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.warning.withValues(alpha: 0.4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(live.decision!.situation.isEmpty ? t('التوليد متوقف بانتظار قرارك.', 'The run is paused for your decision.') : live.decision!.situation,
                style: orgText(context, size: 12, color: c.textDark)),
            if (widget.onOpenDecision != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonalIcon(
                  onPressed: widget.busy ? null : widget.onOpenDecision,
                  icon: const Icon(Icons.alt_route_rounded, size: 18),
                  label: Text(t('اختر…', 'Choose…')),
                ),
              ),
          ]),
        );

    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      if (failed && (widget.error ?? '').isNotEmpty) Text(widget.error!, style: orgText(context, size: 12, color: c.textMedium)),
      if (!failed) ...[
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: open ? bar : (bar ?? 1), minHeight: 6, color: accent, backgroundColor: accent.withValues(alpha: 0.12)),
        ),
        const SizedBox(height: 8),
        if (live.hasBest)
          Wrap(spacing: 6, runSpacing: 6, children: [
            counter(t('وُضعت', 'placed'), '${live.placed} / ${live.required}', c.success),
            counter(t('متبقية', 'remaining'), '${live.unplaced}', live.unplaced > 0 ? c.warning : c.success),
            counter(t('قواعد مكسورة', 'rules bent'), '${live.broken}', live.broken > 0 ? c.danger : c.success),
          ]),
        if (live.hasBest) const SizedBox(height: 6),
        clock,
        if (budget != null && budget > 0 && open) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: (elapsed.inSeconds / budget).clamp(0.0, 1.0), minHeight: 3, color: c.purple, backgroundColor: c.purple.withValues(alpha: 0.15)),
          ),
        ],
        if (!widget.compact && live.rung != null && live.rung != 'free_moves' && open && !live.isWaiting)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: c.purple.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.stairs_rounded, size: 16, color: c.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('الدرجة الآن: ${live.rungLabel}', 'Relaxing now: ${live.rungLabel}'), style: orgText(context, size: 12.5, w: FontWeight.w700, color: c.textDark)),
                  if (rungWhy(live.rung).isNotEmpty) Text(rungWhy(live.rung), style: orgText(context, size: 11.5, color: c.textMedium)),
                ]),
              ),
            ]),
          ),
      ],
      if (widget.compact && current != null && !live.isWaiting) stepRow(current),
      if (!widget.compact && steps.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(t('ما الذي يحدث', 'What is happening'), style: orgText(context, size: 12, w: FontWeight.w800, color: c.textMedium))),
          if (steps.length > 6)
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(_all ? t('الأخيرة فقط', 'Last few') : t('كل الخطوات (${steps.length})', 'Every step (${steps.length})'), style: orgText(context, size: 11.5, color: c.primary)),
              ),
            ),
        ]),
        for (final s in shown) stepRow(s),
      ],
      if (waiting)
        widget.onDecide != null && !widget.compact
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: LadderDecisionCard(decision: live.decision!, busy: widget.busy, onChoose: (id) => widget.onDecide!(live.decision!.id, id)),
              )
            : waitingBanner(),
    ]);

    if (widget.compact) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: body,
      );
    }
    return Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: 0.25))), child: AppMeshSurface(color: accent, style: AppMeshStyle.wash, radius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: body)));
  }
}

/// [LadderOverlay] bound to the provider's run: the studio embeds it where it showed GenerationLivePanel for ladder
/// runs. [inlineDecision] renders the decision in place (the wide side panel); otherwise a waiting run offers
/// "Choose…", which opens [showLadderDecisionDialog]. Nothing is drawn when the run is not a ladder run.
class LadderLivePanel extends StatefulWidget {
  const LadderLivePanel({super.key, required this.p, this.inlineDecision = false, this.compact = false});
  final OrgScheduleProvider p;
  final bool inlineDecision, compact;

  @override
  State<LadderLivePanel> createState() => _LadderLivePanelState();
}

class _LadderLivePanelState extends State<LadderLivePanel> {
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await appConfirm(context, message: t('إلغاء التوليد؟ لا يتغير شيء في الجدول.', 'Cancel the generation? Nothing in the timetable changes.'), danger: true, confirmLabel: t('إلغاء التوليد', 'Cancel it'));
    if (ok) await widget.p.cancelGeneration();
  }

  Future<void> _decide(String decisionId, String optionId) async {
    setState(() => _busy = true);
    await widget.p.decide(decisionId, optionId);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.p,
        builder: (context, _) {
          final run = widget.p.genRun;
          final live = LadderLive.of(run);
          if (live == null) return const SizedBox.shrink();
          final open = runIsOpen(run);
          return LadderOverlay(
            live: live,
            compact: widget.compact,
            busy: _busy,
            error: run?['error']?.toString(),
            progress: run?['progress'] == null ? null : asInt(run?['progress']),
            onCancel: open ? _cancel : null,
            onDecide: widget.inlineDecision ? _decide : null,
            onOpenDecision: live.decision == null ? null : () => showLadderDecisionDialog(context, widget.p, live.decision!),
          );
        },
      );
}

/// Over the grid while a ladder run writes a new version: the old version stays visible but dimmed and untouchable;
/// the compact panel (Cancel, Choose…) stays live.
class LadderVeil extends StatelessWidget {
  const LadderVeil({super.key, required this.p});
  final OrgScheduleProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: Stack(children: [
        Positioned.fill(child: AbsorbPointer(child: Container(color: c.surface.withValues(alpha: 0.72)))),
        Center(child: Padding(padding: const EdgeInsets.all(16), child: SingleChildScrollView(child: LadderLivePanel(p: p, compact: true)))),
      ]),
    );
  }
}

/// The run as a modal sheet: it cannot be dismissed while the run is open (back, barrier and drag are refused),
/// shows the decision inline, and offers Close once the run ended.
Future<void> showLadderOverlay(BuildContext context, OrgScheduleProvider p) => showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => Directionality(textDirection: dir, child: _LadderOverlaySheet(p: p)),
    );

class _LadderOverlaySheet extends StatelessWidget {
  const _LadderOverlaySheet({required this.p});
  final OrgScheduleProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final run = p.genRun;
        final open = runIsOpen(run);
        final ladder = LadderLive.of(run) != null;
        return PopScope(
          canPop: !open,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
            child: Material(
              color: c.cardBg,
              surfaceTintColor: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 4),
                  child: Row(children: [
                    Expanded(child: Text(open ? t('جارٍ توليد الجدول', 'Generating the timetable') : t('انتهى التوليد', 'Generation finished'), style: orgText(context, size: 17, w: FontWeight.w800, color: c.textDark))),
                    IconButton(tooltip: t('إغلاق', 'Close'), 
                      style: IconButton.styleFrom(backgroundColor: c.inputBg),
                      onPressed: open ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20),
                    ),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (ladder)
                        LadderLivePanel(p: p, inlineDecision: true)
                      else
                        Text(t('لا تشغيل جارٍ', 'No run in progress'), style: orgText(context, size: 12.5, color: c.textMedium)),
                      if (!open) ...[
                        const SizedBox(height: 12),
                        AppPrimaryButton(label: t('إغلاق', 'Close'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(context)),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  4. The result
// ═════════════════════════════════════════════════════════════════════════════

/// What the ladder run did, shown at the top of the Quick Actions panel after a run.
class LadderResultCard extends StatelessWidget {
  const LadderResultCard({
    super.key,
    required this.report,
    this.pending = 0,
    this.onAcceptAll,
    this.onOpenProposals,
    this.onOpenLadder,
    this.names = const {},
    this.limitDecisions = 4,
  });
  final LadderReport report;
  /// Proposals (result.broken blocks) still waiting for a decision — what "Accept all" accepts.
  final int pending;
  final VoidCallback? onAcceptAll, onOpenProposals, onOpenLadder;
  final Map<int, String> names; // course id → name (the splits)
  final int limitDecisions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final col = r.complete ? c.success : (r.status == 'invalid' || r.status == 'cancelled' ? c.danger : c.warning);
    final labels = dayLabels();
    final best = r.bestBlocked;

    Widget line(IconData icon, String text, {Color? color, FontWeight w = FontWeight.w400}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 15, color: color ?? c.textMedium),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: orgText(context, size: 12, w: w, color: color ?? c.textMedium))),
          ]),
        );

    Widget rungRow(LadderRungResult x) {
      final (icon, ic) = x.applied
          ? (Icons.check_circle_rounded, c.success)
          : x.mode == 'locked'
              ? (Icons.lock_rounded, c.textLight)
              : x.tried
                  ? (Icons.remove_circle_outline_rounded, c.textLight)
                  : (Icons.radio_button_unchecked_rounded, c.textLight);
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: ic),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(x.name, style: orgText(context, size: 12.5, w: FontWeight.w700, color: x.applied ? c.textDark : c.textMedium))),
                const SizedBox(width: 6),
                _pill(context, ladderModeLabel(x.mode), _modeColor(context, x.mode), icon: ladderModeIcon(x.mode)),
              ]),
              Text(rungResultText(x), style: orgText(context, size: 11.5, color: c.textMedium)),
            ]),
          ),
        ]),
      );
    }

    final structural = <String>[
      for (final m in r.structural.rooms)
        t('قاعة مقترحة: ${m['kind'] ?? ''} · ${m['capacity'] ?? ''} مقعداً · ${m['sessions'] ?? 0} حصة', 'Proposed room: ${m['kind'] ?? ''} · ${m['capacity'] ?? ''} seats · ${m['sessions'] ?? 0} session(s)'),
      for (final m in r.structural.periods)
        t('فترة جديدة ${m['label'] ?? ''} · ${m['sessions'] ?? 0} حصة', 'New period ${m['label'] ?? ''} · ${m['sessions'] ?? 0} session(s)'),
      for (final m in r.structural.days) t('يوم جديد: ${labels['${m['day']}'] ?? m['day']} · ${m['sessions'] ?? 0} حصة', 'New day: ${labels['${m['day']}'] ?? m['day']} · ${m['sessions'] ?? 0} session(s)'),
      for (final m in r.structural.splits)
        t('${names[asInt(m['course_id'])] ?? '${t('مقرر', 'course')} ${m['course_id']}'}: ${m['groups'] ?? ''} مجموعات بدل ${m['from'] ?? 1}', '${names[asInt(m['course_id'])] ?? 'course ${m['course_id']}'}: ${m['groups'] ?? ''} groups instead of ${m['from'] ?? 1}'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: col.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(r.complete ? Icons.verified_rounded : Icons.stairs_rounded, color: col),
          const SizedBox(width: 8),
          Expanded(child: Text(ladderStatusText(r.status), style: orgText(context, size: 14, w: FontWeight.w800, color: col))),
          const SizedBox(width: 6),
          Text(
            [if (r.elapsedS > 0) liveClock(Duration(seconds: r.elapsedS.round())), if (r.solves > 0) t('${r.solves} حل', '${r.solves} solves')].join(' · '),
            style: orgText(context, size: 11.5, color: c.textMedium),
          ),
        ]),
        const SizedBox(height: 4),
        Text(r.summaryText(), style: orgText(context, size: 12.5, color: c.textDark)),
        if (r.rungs.isNotEmpty) ...[
          _sectionTitle(context, t('الدرجات', 'Rungs')),
          for (final x in r.rungs) rungRow(x),
        ],
        if (structural.isNotEmpty) ...[
          _sectionTitle(context, t('إضافات على البنية', 'Structural additions')),
          for (final s in structural) line(Icons.add_circle_outline_rounded, s, color: c.purple),
        ],
        const SizedBox(height: 8),
        line(
          r.provenClean ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
          r.provenClean
              ? t('فحص مستقل: ${r.proof.hardVsRelaxed} تعارض · ${r.proof.hardVsOriginal} كسر مقصود مُسجَّل', 'Independent check: ${r.proof.hardVsRelaxed} conflicts · ${r.proof.hardVsOriginal} deliberate break(s) listed')
              : t('الفحص المستقل وجد ${r.proof.hardVsRelaxed} تعارضاً و${r.proof.neverBrokenViolations} خرقاً لقاعدة ثابتة', 'The independent check found ${r.proof.hardVsRelaxed} conflict(s) and ${r.proof.neverBrokenViolations} fixed-rule violation(s)'),
          color: r.provenClean ? c.success : c.danger,
          w: FontWeight.w700,
        ),
        if (!r.complete && r.status != 'cancelled' && r.status != 'invalid')
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.warning.withValues(alpha: 0.4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('ما يمنع الاكتمال', 'What blocks completion'), style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.textDark)),
              if (r.blockedBy.isEmpty)
                line(Icons.info_outline_rounded, t('لا درجة مقفلة تُكمل الجدول — راجع البيانات (الفترات، القاعات، الإتاحة).', 'No locked rung would complete it — check the data (periods, rooms, availability).'))
              else
                for (final b in r.blockedBy)
                  line(
                    b.wouldComplete ? Icons.lock_open_rounded : Icons.lock_rounded,
                    b.wouldComplete
                        ? t('فتح «${b.name}» يُكمل الجدول', 'Unlocking "${b.name}" would complete the timetable')
                        : t('فتح «${b.name}» يضع ${b.placedAfter} من ${b.required}', 'Unlocking "${b.name}" would place ${b.placedAfter} of ${b.required}'),
                    color: b == best ? c.warning : c.textMedium,
                    w: b == best ? FontWeight.w700 : FontWeight.w400,
                  ),
              if (onOpenLadder != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(onPressed: onOpenLadder, icon: const Icon(Icons.stairs_rounded, size: 16), label: Text(t('افتح السلّم', 'Open the ladder'))),
                ),
            ]),
          ),
        if (r.decisions.isNotEmpty) ...[
          _sectionTitle(context, t('القرارات (${r.decisions.length})', 'Decisions (${r.decisions.length})')),
          for (final d in r.decisions.take(limitDecisions))
            line(
              Icons.alt_route_rounded,
              '${liveClock(Duration(seconds: d.atS.round()))} · ${t('اختير', 'chose')} «${d.chosenName}» ${decisionByText(d.by)}'
              '${d.followedRecommendation || d.recommended.isEmpty ? '' : ' (${t('الموصى به', 'recommended')}: ${rungName(d.recommended)})'}',
            ),
          if (r.decisions.length > limitDecisions) Text(t('+${r.decisions.length - limitDecisions} أخرى', '+${r.decisions.length - limitDecisions} more'), style: orgText(context, size: 11.5, color: c.textLight)),
        ],
        if (pending > 0 && (onAcceptAll != null || onOpenProposals != null)) ...[
          const SizedBox(height: 10),
          Text(t('$pending اقتراح بانتظار قرارك — النشر ينتظرها.', '$pending proposal(s) wait for your decision — publishing waits for them.'), style: orgText(context, size: 12, color: c.textMedium)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (onAcceptAll != null)
              FilledButton.tonalIcon(onPressed: onAcceptAll, icon: const Icon(Icons.done_all_rounded, size: 18), label: Text(t('قبول الكل ($pending)', 'Accept all ($pending)'))),
            if (onOpenProposals != null) OutlinedButton(onPressed: onOpenProposals, child: Text(t('راجع الاقتراحات', 'Review the proposals'))),
          ]),
        ],
      ]),
    );
  }
}
