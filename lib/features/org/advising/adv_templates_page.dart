// lib/features/org/advising/adv_templates_page.dart — advising templates (docs/advising/PHASE5.md "Templates", #15):
// meeting notes, outreach, support requests and messages, each in Arabic and English with the placeholders
// {student_name} {advisor_name} {date} {time} {org_name} (filled on the device before the person edits the text).
// Manage adds, edits, switches off and deletes; a built-in template keeps its kind and names (only its texts and
// on / off change) and is never deleted.
//
//   AdvTemplatesView · AdvTemplateForm   plain values        AdvTemplatesPage   loads / writes through AdvCommApi
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_appt_models.dart';
import 'adv_case_parts.dart' show AdvTypedField, AdvTypedText;
import 'adv_comm_api.dart';
import 'adv_comm_parts.dart';
import 'adv_parts.dart';

class AdvTemplatesView extends StatelessWidget {
  const AdvTemplatesView({super.key, required this.load, this.templates = const [], this.kind = '', this.manage = false, this.errorText, this.onRetry, this.onKind, this.onAdd, this.onEdit});
  final AdvLoad load;
  final List<AdvTemplate> templates;

  /// '' = every kind.
  final String kind;
  final bool manage;
  final String? errorText;
  final VoidCallback? onRetry, onAdd;
  final ValueChanged<String>? onKind;
  final ValueChanged<AdvTemplate>? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (load != AdvLoad.ready) {
      body = AdvLoadState(state: load, errorText: errorText, onRetry: onRetry);
    } else {
      final shown = [for (final x in templates) if (kind.isEmpty || x.kind == kind) x];
      body = shown.isEmpty
          ? AppEmpty(icon: Icons.description_outlined, title: t('لا قوالب من هذا النوع', 'No templates of this kind'), actionLabel: onAdd == null ? null : t('قالب جديد', 'New template'), onAction: onAdd)
          : AdvPageFrame(fab: onAdd != null, maxWidth: 880, children: [
              for (final k in advTemplateKinds)
                if ([for (final x in shown) if (x.kind == k) x] case final group when group.isNotEmpty) ...[
                  AdvSectionTitle(advTemplateKindLabel(k), first: k == advTemplateKinds.firstWhere((x) => shown.any((y) => y.kind == x))),
                  for (final x in group)
                    AdvRowCard(
                      leading: CircleAvatar(
                        backgroundColor: (x.active ? c.primary : c.textMedium).withValues(alpha: 0.12),
                        child: Icon(x.system ? Icons.verified_outlined : Icons.description_outlined, color: appInk(context, x.active ? c.primary : c.textMedium), size: AppIconSize.md),
                      ),
                      title: x.name,
                      subtitle: x.body.replaceAll('\n', ' '),
                      trailing: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                        if (x.system) AppBadgePill(t('أساسي', 'Built-in'), color: c.textMedium),
                        if (!x.active) AppBadgePill(t('متوقف', 'Off'), color: c.warning, icon: Icons.pause_circle_outline_rounded),
                      ]),
                      onTap: onEdit == null ? null : () => onEdit!(x),
                    ),
                ],
            ]);
    }
    return OrgPageBody(
      primary: onAdd == null ? null : OrgPrimaryAction(icon: Icons.add_rounded, label: t('قالب جديد', 'New template'), onTap: onAdd!),
      filter: onKind == null
          ? null
          : OrgFilterButton<String>(
              value: kind,
              defaultValue: '',
              label: t('النوع', 'Kind'),
              options: {'': t('كل الأنواع', 'Every kind'), for (final k in advTemplateKinds) k: advTemplateKindLabel(k)},
              onChanged: onKind!,
            ),
      child: body,
    );
  }
}

/// The edit form: kind (a new template), names, the two texts with placeholder chips, on / off.
class AdvTemplateForm extends StatelessWidget {
  const AdvTemplateForm({
    super.key,
    required this.draft,
    required this.nameAr,
    required this.nameEn,
    required this.bodyAr,
    required this.bodyEn,
    this.system = false,
    this.creating = true,
    this.busy = false,
    this.error,
    this.onKind,
    this.onActive,
    this.onPlaceholder,
    this.onSubmit,
    this.onDelete,
  });

  final AdvTemplateDraft draft;
  final TextEditingController nameAr, nameEn, bodyAr, bodyEn;
  final bool system, creating, busy;
  final String? error;
  final ValueChanged<String>? onKind;
  final ValueChanged<bool>? onActive;

  /// Inserts a placeholder into the text being edited ([bool] = the Arabic text).
  final void Function(String placeholder, bool arabic)? onPlaceholder;
  final VoidCallback? onSubmit, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget chips(bool arabic) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final p in advPlaceholders)
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: AppIconSize.sm),
              label: Text(advPlaceholderLabel(p)),
              tooltip: '{$p}',
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onPressed: busy || onPlaceholder == null ? null : () => onPlaceholder!(p, arabic),
            ),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (creating) ...[
        AdvFieldLabel(t('النوع', 'Kind')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in advTemplateKinds) AppChoiceChip(label: advTemplateKindLabel(k), selected: draft.kind == k, onTap: busy || onKind == null ? () {} : () => onKind!(k)),
        ]),
        const SizedBox(height: AppSpace.md),
      ] else
        AdvInfoLine(icon: Icons.category_outlined, text: system ? '${advTemplateKindLabel(draft.kind)} · ${t('قالب أساسي: يُعدَّل نصه فقط', 'Built-in: only its text can change')}' : advTemplateKindLabel(draft.kind)),
      if (!system) ...[
        const SizedBox(height: AppSpace.xs),
        Directionality(textDirection: TextDirection.rtl, child: AppField(controller: nameAr, label: 'الاسم بالعربية')),
        const SizedBox(height: AppSpace.sm),
        Directionality(textDirection: TextDirection.ltr, child: AppField(controller: nameEn, label: 'Name in English')),
      ],
      const SizedBox(height: AppSpace.md),
      AdvTypedField(controller: bodyAr, label: t('النص بالعربية', 'Arabic text'), minLines: 4, maxLines: 10, maxLength: 10000, enabled: !busy),
      const SizedBox(height: AppSpace.xs),
      chips(true),
      const SizedBox(height: AppSpace.md),
      AdvTypedField(controller: bodyEn, label: t('النص بالإنجليزية', 'English text'), minLines: 4, maxLines: 10, maxLength: 10000, enabled: !busy),
      const SizedBox(height: AppSpace.xs),
      chips(false),
      const SizedBox(height: AppSpace.xs),
      Text(t('تُستبدل هذه الحقول تلقائياً عند استخدام القالب، ويمكن تعديل النص بعدها.', 'These fields are filled in when the template is used; the text can be edited after.'), style: AppType.meta(context)),
      AppSwitchTile(
        icon: Icons.toggle_on_outlined,
        title: t('مفعّل', 'On'),
        subtitle: t('القوالب المتوقفة لا تظهر للمرشدين', 'Advisors do not see templates that are off'),
        value: draft.active,
        onChanged: busy ? null : onActive,
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.check_rounded, label: creating ? t('إضافة القالب', 'Add the template') : t('حفظ', 'Save'), busy: busy, onPressed: onSubmit),
      if (onDelete != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppButton.ghost(label: t('حذف القالب', 'Delete the template'), icon: Icons.delete_outline_rounded, expand: true, onPressed: busy ? null : onDelete),
      ],
    ]);
  }
}

/// A preview of a template with sample values (the editor shows how it reads).
class AdvTemplatePreview extends StatelessWidget {
  const AdvTemplatePreview({super.key, required this.template});
  final AdvTemplate template;

  @override
  Widget build(BuildContext context) => AdvTypedText(advFillTemplate(template.body, {
        'student_name': t('سارة أحمد', 'Sara Ahmed'),
        'advisor_name': t('د. منى خليل', 'Dr Mona Khalil'),
        'date': AppTime.date(DateTime.now().toUtc()),
        'time': AppTime.time(DateTime.now().toUtc()),
      }));
}

Future<bool> _showTemplateSheet(BuildContext context, AdvCommApi api, {AdvTemplate? template}) async {
  final x = template;
  var draft = x == null ? const AdvTemplateDraft() : AdvTemplateDraft.of(x);
  final nameAr = TextEditingController(text: draft.nameAr);
  final nameEn = TextEditingController(text: draft.nameEn);
  final bodyAr = TextEditingController(text: draft.bodyAr);
  final bodyEn = TextEditingController(text: draft.bodyEn);
  var busy = false;
  String? error;
  final done = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        AdvTemplateDraft current() => draft.copyWith(nameAr: nameAr.text, nameEn: nameEn.text, bodyAr: bodyAr.text, bodyEn: bodyEn.text);

        Future<void> submit() async {
          final d = current();
          final why = d.error();
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => x == null ? api.addTemplate(d) : api.saveTemplate(x.id, d), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advCommErrorText(r.error!);
            });
            return;
          }
          showAppNotice(x == null ? t('أُضيف القالب', 'Template added') : t('حُفظ القالب', 'Template saved'));
          Navigator.pop(ctx, true);
        }

        Future<void> delete() async {
          final yes = await appConfirm(ctx, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف القالب «${x!.name}»؟', 'Delete the template "${x.name}"?'));
          if (!yes || !ctx.mounted) return;
          set(() => busy = true);
          final r = await orgCall(() => api.deleteTemplate(x.id), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advCommErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('حُذف القالب', 'Template deleted'));
          Navigator.pop(ctx, true);
        }

        void insert(String p, bool arabic) {
          final ctl = arabic ? bodyAr : bodyEn;
          final sel = ctl.selection;
          final at = sel.isValid ? sel.start : ctl.text.length;
          final end = sel.isValid ? sel.end : ctl.text.length;
          final token = '{$p}';
          ctl.value = TextEditingValue(text: ctl.text.replaceRange(at, end, token), selection: TextSelection.collapsed(offset: at + token.length));
        }

        return AppSheetContent(
          title: x == null ? t('قالب جديد', 'New template') : x.name,
          children: [
            AdvTemplateForm(
              draft: draft,
              nameAr: nameAr,
              nameEn: nameEn,
              bodyAr: bodyAr,
              bodyEn: bodyEn,
              system: x?.system ?? false,
              creating: x == null,
              busy: busy,
              error: error,
              onKind: (k) => set(() => draft = current().copyWith(kind: k)),
              onActive: (v) => set(() => draft = current().copyWith(active: v)),
              onPlaceholder: insert,
              onSubmit: submit,
              onDelete: x == null || x.system ? null : delete,
            ),
          ],
        );
      }));
  return done ?? false;
}

class AdvTemplatesPage extends StatelessWidget {
  const AdvTemplatesPage({super.key, required this.orgId, this.manage = true});
  final int orgId;
  final bool manage;

  @override
  Widget build(BuildContext context) => AdvCommScaffold(
        orgId: orgId,
        title: t('قوالب الإرشاد', 'Advising templates'),
        maxWidth: 880,
        child: _AdvTemplatesBody(orgId: orgId, manage: manage),
      );
}

class _AdvTemplatesBody extends StatefulWidget {
  const _AdvTemplatesBody({required this.orgId, required this.manage});
  final int orgId;
  final bool manage;

  @override
  State<_AdvTemplatesBody> createState() => _AdvTemplatesBodyState();
}

class _AdvTemplatesBodyState extends State<_AdvTemplatesBody> {
  late final AdvCommApi _api = AdvCommApi(widget.orgId);
  OrgPageRefresh? _refresh;
  List<AdvTemplate> _items = const [];
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  String _kind = '';

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.templates(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _items = r.data as List<AdvTemplate>;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(r);
        _error = advCommErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _edit([AdvTemplate? x]) async {
    if (await _showTemplateSheet(context, _api, template: x) && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => AdvTemplatesView(
        load: _load,
        templates: _items,
        kind: _kind,
        manage: widget.manage,
        errorText: _error,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onKind: (k) => setState(() => _kind = k),
        onAdd: widget.manage ? () => _edit() : null,
        onEdit: widget.manage ? _edit : (x) => showAppSheet<void>(context, (ctx) => AppSheetContent(title: x.name, children: [AdvTemplatePreview(template: x)])),
      );
}
