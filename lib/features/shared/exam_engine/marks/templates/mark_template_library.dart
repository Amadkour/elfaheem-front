// The library: the organization's saved templates for its own paper sheets (or the teacher's personal ones when there
// is no organization), a card each, and "New template". Entry point for every other screen: [openMarkTemplates].
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show asMapList, t;
import '../mark_templates_api.dart';
import 'mark_template_common.dart';
import 'mark_template_editor.dart';
import 'mark_template_new.dart';

/// Opens the template library. With [pick] a tap on a card closes it and returns that template; otherwise a tap edits
/// it and the result is null. [orgId] null = the teacher's personal space; [kind] filters (and fixes the kind of a new one).
Future<MarkTemplate?> openMarkTemplates(BuildContext context, {int? orgId, String? kind, bool pick = false}) =>
    Navigator.of(context).push<MarkTemplate>(MaterialPageRoute(
      settings: const RouteSettings(name: MarkTemplatesPage.routeName),
      builder: (_) => MarkTemplatesPage(orgId: orgId, kind: kind, pick: pick),
    ));

class MarkTemplatesPage extends StatefulWidget {
  const MarkTemplatesPage({super.key, this.orgId, this.kind, this.pick = false, this.api, this.picker});
  static const routeName = '/exam/mark-templates';

  final int? orgId;
  final String? kind;
  final bool pick;
  final MarkTemplatesApi? api;
  final MarkImagePicker? picker;

  @override
  State<MarkTemplatesPage> createState() => _MarkTemplatesPageState();
}

class _MarkTemplatesPageState extends State<MarkTemplatesPage> {
  late final MarkTemplatesApi _api = widget.api ?? MarkTemplatesApi();
  List<MarkTemplate>? _items;
  String? _error;
  bool _loading = true;
  MarkKind? _filter;

  MarkKind? get _fixedKind => MarkKind.parse(widget.kind);

  @override
  void initState() {
    super.initState();
    _filter = _fixedKind;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items == null;
      _error = null;
    });
    final r = await _api.list(orgId: widget.orgId, kind: widget.kind);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _items = [for (final m in asMapList(r.map['items'])) MarkTemplate.fromJson(m)].where((x) => !x.retired).toList();
      } else {
        _error = markErrorText(r);
      }
    });
  }

  Future<void> _new() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MarkTemplateNewPage(orgId: widget.orgId, kind: _fixedKind, api: _api, picker: widget.picker)));
    if (mounted) _load();
  }

  Future<void> _edit(MarkTemplate tpl) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MarkTemplateEditorPage(api: _api, picker: widget.picker, orgId: widget.orgId, template: tpl)));
    if (mounted) _load();
  }

  Future<void> _retire(MarkTemplate tpl) async {
    final ok = await appConfirm(context, message: t('حذف القالب "${tpl.name}"؟ الجلسات التي استخدمته تبقى كما هي.', 'Delete the template "${tpl.name}"? Sessions that used it are not changed.'), danger: true, confirmLabel: t('حذف', 'Delete'));
    if (!ok || !mounted) return;
    final r = await _api.retire(tpl.id);
    if (!mounted) return;
    if (r.ok) {
      showAppNotice(t('تم حذف القالب', 'Template deleted'));
      _load();
    } else {
      showAppNotice(markErrorText(r), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey(kMarkTemplatesFeatureKey),
      appBar: ScreenAppBar(
        title: widget.pick ? t('اختيار قالب ورقة', 'Choose a sheet template') : t('قوالب أوراقي', 'My sheet templates'),
        actions: [AppRefreshAction(onRefresh: _load)],
      ),
      floatingActionButton: _items == null ? null : FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_rounded), label: Text(t('قالب جديد', 'New template'))),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const AppListSkeleton(items: 4);
    if (_items == null) {
      return AppEmpty(icon: Icons.error_outline_rounded, title: _error ?? t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load);
    }
    final shown = [for (final x in _items!) if (_filter == null || x.kind == _filter) x];
    return AppRefresh(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppTouch.primary + AppSpace.xxl),
        children: [
          Text(
            widget.orgId == null
                ? t('قوالبك الشخصية: لا يراها غيرك.', 'Your personal templates: only you see them.')
                : t('قوالب المؤسسة: يراها كل معلمي المؤسسة.', 'The organization\'s templates: every teacher of the organization sees them.'),
            style: AppType.meta(context),
          ),
          AppSpace.gapSm,
          if (_fixedKind == null)
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppChoiceChip(label: t('الكل', 'All'), selected: _filter == null, onTap: () => setState(() => _filter = null)),
              for (final k in MarkKind.values) AppChoiceChip(label: k.label, selected: _filter == k, onTap: () => setState(() => _filter = k)),
            ]),
          AppSpace.gapSm,
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: AppEmpty(
                icon: Icons.description_outlined,
                title: t('لا توجد قوالب بعد', 'No templates yet'),
                message: t('صوّر ورقة فارغة وسنقترح عليك أماكن الحقول.', 'Photograph a blank sheet and we propose where the fields are.'),
                actionLabel: t('قالب جديد', 'New template'),
                onAction: _new,
              ),
            )
          else
            for (final (i, x) in shown.indexed)
              AppReveal(index: i, group: 'mark.templates', child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: MarkTemplateCard(
                  item: x,
                  onTap: () => widget.pick ? Navigator.of(context).pop(x) : _edit(x),
                  onDelete: widget.pick ? null : () => _retire(x),
                ),
              )),
        ],
      ),
    );
  }
}

class MarkTemplateCard extends StatelessWidget {
  const MarkTemplateCard({super.key, required this.item, this.onTap, this.onDelete});
  final MarkTemplate item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Each sheet kind keeps its block tone everywhere: a stable tint behind its icon.
        _KindTile(kind: item.kind),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              if (item.kind != null) AppBadgePill(item.kind!.label),
              AppBadgePill(t('${item.fieldsCount} حقول', '${item.fieldsCount} fields'), color: c.textMedium),
              if (item.totalMax != null) AppBadgePill(t('المجموع ${numText(item.totalMax!)}', 'Total ${numText(item.totalMax!)}'), color: appInk(context, c.warning)),
              AppBadgePill(t('الإصدار ${item.version}', 'Version ${item.version}'), color: c.textMedium),
            ]),
            AppSpace.gapXs,
            Text(
              [
                if (item.ownerName.isNotEmpty) item.ownerName,
                if (item.updatedAt != null) AppTime.dateTime(item.updatedAt!),
              ].join(' · '),
              style: AppType.meta(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        if (onDelete != null)
          IconButton(
            tooltip: t('حذف القالب', 'Delete template'),
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: c.textMedium),
          ),
      ]),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind});
  final MarkKind? kind;

  @override
  Widget build(BuildContext context) {
    final b = AppBlockColors.of(context, switch (kind) {
      MarkKind.answerTable => AppBlockTone.sky,
      MarkKind.markSheet => AppBlockTone.peach,
      MarkKind.cover => AppBlockTone.emerald,
      null => AppBlockTone.paper,
    });
    return Container(
      width: AppTouch.min,
      height: AppTouch.min,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: b.surface, borderRadius: AppRadius.controlAll),
      child: Icon(kindIcon(kind), color: b.ink, size: AppIconSize.lg),
    );
  }
}
