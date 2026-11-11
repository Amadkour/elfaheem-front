// Flows (ordered steps over pages) of the help catalogue: the editor form. A flow is one how-to ("How to enroll"):
// step = page id (picked from GET /admin/help/page-ids), the action, the narration and a duration in seconds.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../shared/help/help_models.dart';
import 'admin_help_editor.dart';

class FlowStepDraft {
  FlowStepDraft([HelpFlowStep? s])
      : pageId = s?.pageId,
        action = BiCtl(s?.action),
        narration = BiCtl(s?.narration),
        duration = TextEditingController(text: '${s?.durationS ?? 5}');
  String? pageId;
  final BiCtl action, narration;
  final TextEditingController duration;

  int get seconds => int.tryParse(duration.text.trim()) ?? 5;

  void dispose() {
    action.dispose();
    narration.dispose();
    duration.dispose();
  }
}

final _flowKeyRe = RegExp(r'^[a-z0-9_]+$');

class FlowDraft {
  FlowDraft(HelpFlow f, {this.isNew = false})
      : role = f.role,
        key = TextEditingController(text: f.key),
        title = BiCtl(f.title),
        steps = [for (final s in f.steps) FlowStepDraft(s)];

  final bool isNew;
  final String role;
  final TextEditingController key;
  final BiCtl title;
  final List<FlowStepDraft> steps;

  HelpFlow toFlow() => HelpFlow(
        key: key.text.trim(),
        role: role,
        title: title.value,
        steps: [
          for (final s in steps)
            HelpFlowStep(
                pageId: s.pageId ?? '', action: s.action.value, narration: s.narration.value, durationS: s.seconds.clamp(1, 600)),
        ],
      );

  /// The first problem the server would reject; null = valid.
  String? validate() {
    final ar = AppConfig.lang == 'ar';
    if (!_flowKeyRe.hasMatch(key.text.trim())) {
      return ar ? 'مفتاح المسار: حروف إنجليزية صغيرة وأرقام و _' : 'Flow key: lowercase letters, digits and _';
    }
    final t = title.value;
    if (t.ar.isEmpty || t.en.isEmpty) return ar ? 'العنوان بالعربية والإنجليزية مطلوب' : 'The title is required in both languages';
    if (steps.isEmpty || steps.length > 60) return ar ? 'المسار من 1 إلى 60 خطوة' : 'A flow has 1 to 60 steps';
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      if (s.pageId == null || s.pageId!.isEmpty) return ar ? 'الخطوة ${i + 1}: اختر الصفحة' : 'Step ${i + 1}: pick a page';
      final a = s.action.value, n = s.narration.value;
      if (a.ar.isEmpty || a.en.isEmpty || n.ar.isEmpty || n.en.isEmpty) {
        return ar ? 'الخطوة ${i + 1}: الإجراء والشرح بالعربية والإنجليزية' : 'Step ${i + 1}: action and narration in both languages';
      }
    }
    return null;
  }

  void dispose() {
    key.dispose();
    title.dispose();
    for (final s in steps) {
      s.dispose();
    }
  }
}

class HelpFlowForm extends StatefulWidget {
  const HelpFlowForm({super.key, required this.draft, required this.pageIds, this.onChanged});
  final FlowDraft draft;

  /// The ids a step may name (`GET /admin/help/page-ids`).
  final List<String> pageIds;
  final VoidCallback? onChanged;

  @override
  State<HelpFlowForm> createState() => _HelpFlowFormState();
}

class _HelpFlowFormState extends State<HelpFlowForm> {
  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  void _touch(VoidCallback f) {
    setState(f);
    widget.onChanged?.call();
  }

  Widget _icon(IconData i, String tip, VoidCallback? f) => IconButton(
        tooltip: tip,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        onPressed: f,
        icon: Icon(i, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // the key names the flow on the server: read-only when editing an existing one
      IgnorePointer(
        ignoring: !d.isNew,
        child: ExcludeFocus(excluding: !d.isNew, child: Opacity(opacity: d.isNew ? 1 : 0.6, child: AppField(controller: d.key, label: _t('مفتاح المسار', 'Flow key'), ltr: true))),
      ),
      AppSpace.gapXs,
      AppField(controller: d.title.ar, label: '${_t('العنوان', 'Title')} · العربية'),
      AppSpace.gapXs,
      AppField(controller: d.title.en, label: '${_t('العنوان', 'Title')} · English', ltr: true),
      AppSpace.gapMd,
      Semantics(header: true, child: Text(_t('الخطوات', 'Steps'), style: AppType.section(context).copyWith(color: c.textDark))),
      AppSpace.gapXs,
      for (var i = 0; i < d.steps.length; i++) _step(d, i),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
          onPressed: () => _touch(() => d.steps.add(FlowStepDraft())),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(_t('إضافة خطوة', 'Add step')),
        ),
      ),
    ]);
  }

  Widget _step(FlowDraft d, int i) {
    final s = d.steps[i];
    final c = context.colors;
    final ids = widget.pageIds;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${_t('الخطوة', 'Step')} ${i + 1}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium))),
          _icon(Icons.arrow_upward_rounded, _t('أعلى', 'Move up'), i == 0 ? null : () => _touch(() => d.steps.insert(i - 1, d.steps.removeAt(i)))),
          _icon(Icons.arrow_downward_rounded, _t('أسفل', 'Move down'),
              i == d.steps.length - 1 ? null : () => _touch(() => d.steps.insert(i + 1, d.steps.removeAt(i)))),
          _icon(Icons.delete_outline_rounded, _t('حذف', 'Delete'), () => _touch(() => d.steps.removeAt(i).dispose())),
        ]),
        AppDropdown<String>(
          value: ids.contains(s.pageId) ? s.pageId : null,
          decoration: InputDecoration(labelText: _t('الصفحة', 'Page')),
          items: [for (final id in ids) DropdownMenuItem(value: id, child: Text(id, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _touch(() => s.pageId = v),
        ),
        AppSpace.gapXs,
        AppField(controller: s.action.ar, label: '${_t('الإجراء', 'Action')} · العربية', maxLines: 2),
        AppSpace.gapXs,
        AppField(controller: s.action.en, label: '${_t('الإجراء', 'Action')} · English', maxLines: 2, ltr: true),
        AppSpace.gapXs,
        AppField(controller: s.narration.ar, label: '${_t('التعليق الصوتي', 'Narration')} · العربية', maxLines: 3),
        AppSpace.gapXs,
        AppField(controller: s.narration.en, label: '${_t('التعليق الصوتي', 'Narration')} · English', maxLines: 3, ltr: true),
        AppSpace.gapXs,
        AppNumberField(controller: s.duration, label: _t('المدة (ثوانٍ)', 'Duration (seconds)'), min: 0),
      ]),
    );
  }
}
