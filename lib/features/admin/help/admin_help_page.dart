// Help management (Super Admin, kill switch `admin.help`): the pages of the in-app Help by role with search, an editor
// per entry (both languages), the flows editor, and the export sheet (Word user guide / video script).
// Opened from the admin More page. Calls: lib/features/admin/help/admin_help_api.dart.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../core/api_client.dart';
import '../../../design/app_kit.dart';
import '../../../utils/widget/base_page.dart';
import 'package:flutter_education_app/features/help/help_models.dart';
import 'package:flutter_education_app/features/help/help_service.dart';
import 'admin_help_api.dart';
import 'admin_help_editor.dart';
import 'admin_help_export.dart';
import 'admin_help_flows.dart';

const adminHelpFeatureKey = 'admin.help';

class AdminHelpPage extends StatefulWidget {
  const AdminHelpPage({super.key, this.api = const AdminHelpApi()});
  final AdminHelpApi api;

  @override
  State<AdminHelpPage> createState() => _AdminHelpPageState();
}

class _AdminHelpPageState extends State<AdminHelpPage> {
  bool _flowsTab = false;
  String? _role; // null = every role
  String _q = '';
  final _search = TextEditingController();
  List<HelpPageRow> _pages = const [];
  List<HelpFlow> _flows = const [];
  bool _loading = true;
  String? _error;

  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([widget.api.pages(), widget.api.flows()]);
      if (!mounted) return;
      setState(() {
        _pages = r[0] as List<HelpPageRow>;
        _flows = r[1] as List<HelpFlow>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(e).message;
        _loading = false;
      });
    }
  }

  List<HelpPageRow> get _shownPages {
    final q = _q.trim().toLowerCase();
    return [
      for (final p in _pages)
        if ((_role == null || p.role == _role) &&
            (q.isEmpty || p.pageId.toLowerCase().contains(q) || p.title.ar.toLowerCase().contains(q) || p.title.en.toLowerCase().contains(q)))
          p,
    ];
  }

  List<HelpFlow> get _shownFlows {
    final q = _q.trim().toLowerCase();
    return [
      for (final f in _flows)
        if ((_role == null || f.role == _role) &&
            (q.isEmpty || f.key.toLowerCase().contains(q) || f.title.ar.toLowerCase().contains(q) || f.title.en.toLowerCase().contains(q)))
          f,
    ];
  }

  Future<void> _openPage(String pageId, String role, {bool isNew = false}) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => AdminHelpEditPage(api: widget.api, pageId: pageId, role: role, isNew: isNew)));
    if (changed == true) {
      HelpService.instance.reset(); // the person's own cached help is stale now
      _load();
    }
  }

  Future<void> _openFlow(HelpFlow f, {bool isNew = false}) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => AdminHelpFlowPage(api: widget.api, flow: f, isNew: isNew)));
    if (changed == true) _load();
  }

  Future<void> _addPage() async {
    final r = await showAppSheet<(String, String)>(context, (_) => _NewEntrySheet(api: widget.api, role: _role));
    if (r != null) _openPage(r.$1, r.$2, isNew: true);
  }

  void _addFlow() {
    _openFlow(HelpFlow(key: '', role: _role ?? 'student', title: HelpText.empty, steps: [const HelpFlowStep(pageId: '', action: HelpText.empty, narration: HelpText.empty)]),
        isNew: true);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _shownPages, flows = _shownFlows;
    return BasePage(
      key: const ValueKey(adminHelpFeatureKey),
      useWebCard: true,
      width: AppWidth.wide,
      appBar: ScreenAppBar(
        helpPageId: 'admin.help',
        title: _t('إدارة المساعدة', 'Help management'),
        actions: [
          IconButton(
            tooltip: _t('تصدير', 'Export'),
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: () => showHelpExportSheet(context, api: widget.api, flows: _flows),
            icon: const Icon(Icons.file_download_outlined),
          ),
          AppRefreshAction(onRefresh: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _flowsTab ? _addFlow : _addPage,
        icon: const Icon(Icons.add_rounded),
        label: Text(_flowsTab ? _t('مسار جديد', 'New flow') : _t('مدخل جديد', 'New entry')),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl * 2),
        children: [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(label: _t('الصفحات', 'Pages'), selected: !_flowsTab, onTap: () => setState(() => _flowsTab = false)),
            AppChoiceChip(label: _t('المسارات', 'Flows'), selected: _flowsTab, onTap: () => setState(() => _flowsTab = true)),
          ]),
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(label: _t('كل الأدوار', 'All roles'), selected: _role == null, onTap: () => setState(() => _role = null)),
            for (final r in helpRoles) AppChoiceChip(label: helpRoleLabel(r, _ar), selected: _role == r, onTap: () => setState(() => _role = r)),
          ]),
          AppSpace.gapSm,
          AppField(controller: _search, label: _t('بحث', 'Search'), onChanged: (v) => setState(() => _q = v)),
          AppSpace.gapMd,
          if (_loading)
            const AppListSkeleton(items: 6, padding: EdgeInsets.zero)
          else if (_error != null)
            AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: _t('إعادة المحاولة', 'Retry'), onAction: _load)
          else if (!_flowsTab && pages.isEmpty)
            AppEmpty(icon: Icons.info_outline_rounded, title: _t('لا توجد مداخل', 'No entries'))
          else if (_flowsTab && flows.isEmpty)
            AppEmpty(icon: Icons.route_outlined, title: _t('لا توجد مسارات', 'No flows'))
          else if (!_flowsTab)
            for (final p in pages)
              _Row(
                title: p.title.of(AppConfig.lang).isEmpty ? p.pageId : p.title.of(AppConfig.lang),
                subtitle: '${p.pageId} · ${helpRoleLabel(p.role, _ar)}',
                onTap: () => _openPage(p.pageId, p.role),
              )
          else
            for (final f in flows)
              _Row(
                title: f.title.of(AppConfig.lang),
                subtitle: '${f.key} · ${helpRoleLabel(f.role, _ar)} · ${f.steps.length} ${_t('خطوات', 'steps')}',
                onTap: () => _openFlow(f),
              ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, required this.onTap});
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Picks the page id and role of a new entry.
class _NewEntrySheet extends StatefulWidget {
  const _NewEntrySheet({required this.api, this.role});
  final AdminHelpApi api;
  final String? role;

  @override
  State<_NewEntrySheet> createState() => _NewEntrySheetState();
}

class _NewEntrySheetState extends State<_NewEntrySheet> {
  List<String> _ids = const [];
  String? _id;
  late String _role = widget.role ?? 'student';

  @override
  void initState() {
    super.initState();
    widget.api.pageIds().then((v) {
      if (mounted) setState(() => _ids = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    return AppSheetContent(
      title: ar ? 'مدخل مساعدة جديد' : 'New help entry',
      children: [
        AppDropdown<String>(
          value: _ids.contains(_id) ? _id : null,
          decoration: InputDecoration(labelText: ar ? 'الصفحة' : 'Page'),
          items: [for (final i in _ids) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _id = v),
        ),
        AppSpace.gapSm,
        AppDropdown<String>(
          value: _role,
          decoration: InputDecoration(labelText: ar ? 'الدور' : 'Role'),
          items: [for (final r in helpRoles) DropdownMenuItem(value: r, child: Text(helpRoleLabel(r, ar)))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        AppSpace.gapLg,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.primary(
            label: ar ? 'متابعة' : 'Continue',
            onPressed: _id == null ? null : () => Navigator.pop(context, (_id!, _role)),
          ),
        ),
      ],
    );
  }
}

/// Edit one entry (or create it when [isNew]).
class AdminHelpEditPage extends StatefulWidget {
  const AdminHelpEditPage({super.key, required this.api, required this.pageId, required this.role, this.isNew = false});
  final AdminHelpApi api;
  final String pageId, role;
  final bool isNew;

  @override
  State<AdminHelpEditPage> createState() => _AdminHelpEditPageState();
}

class _AdminHelpEditPageState extends State<AdminHelpEditPage> {
  HelpDraft? _draft;
  String? _error;
  bool _saving = false;

  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.isNew) {
      setState(() => _draft = HelpDraft(HelpEntry(pageId: widget.pageId, role: widget.role, title: HelpText.empty, summary: HelpText.empty)));
      return;
    }
    try {
      final e = await widget.api.page(widget.pageId, widget.role);
      if (mounted) setState(() => _draft = HelpDraft(HelpEntry.fromJson({...e.toJson(), 'page_id': widget.pageId, 'role': widget.role})));
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    final bad = d.validate();
    if (bad != null) {
      showAppNotice(bad, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.savePage(widget.pageId, widget.role, d.toEntry());
      if (!mounted) return;
      showAppNotice(_t('تم الحفظ', 'Saved'));
      Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await appConfirm(context, message: _t('حذف هذا المدخل؟', 'Delete this entry?'), danger: true);
    if (!ok) return;
    try {
      await widget.api.deletePage(widget.pageId, widget.role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return BasePage(
      useWebCard: true,
      width: AppWidth.reading,
      appBar: ScreenAppBar(
        title: widget.pageId,
        actions: [
          IconButton(
            tooltip: _t('تصدير', 'Export'),
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: () => showHelpExportSheet(context, api: widget.api, pageId: widget.pageId, role: widget.role),
            icon: const Icon(Icons.file_download_outlined),
          ),
          if (!widget.isNew)
            IconButton(
              tooltip: _t('حذف', 'Delete'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      child: _error != null
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: _t('إعادة المحاولة', 'Retry'), onAction: _load)
          : d == null
              ? const AppListSkeleton(items: 4, withAvatar: false)
              : ListView(
                  padding: const EdgeInsets.all(AppSpace.md),
                  children: [
                    Text('${helpRoleLabel(widget.role, _ar)} · ${widget.pageId}', style: AppType.body(context).copyWith(color: context.colors.textLight)),
                    AppSpace.gapSm,
                    HelpEntryForm(draft: d),
                    AppSpace.gapLg,
                    AppButton.primary(label: _t('حفظ', 'Save'), icon: Icons.check_rounded, busy: _saving, expand: true, onPressed: _saving ? null : _save),
                  ],
                ),
    );
  }
}

/// Edit one flow (or create it when [isNew]).
class AdminHelpFlowPage extends StatefulWidget {
  const AdminHelpFlowPage({super.key, required this.api, required this.flow, this.isNew = false});
  final AdminHelpApi api;
  final HelpFlow flow;
  final bool isNew;

  @override
  State<AdminHelpFlowPage> createState() => _AdminHelpFlowPageState();
}

class _AdminHelpFlowPageState extends State<AdminHelpFlowPage> {
  late final FlowDraft _draft = FlowDraft(widget.flow, isNew: widget.isNew);
  List<String> _ids = const [];
  bool _saving = false;

  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    widget.api.pageIds().then((v) {
      if (mounted) setState(() => _ids = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bad = _draft.validate();
    if (bad != null) {
      showAppNotice(bad, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final f = _draft.toFlow();
      await widget.api.saveFlow(f.role, f.key, f);
      if (!mounted) return;
      showAppNotice(_t('تم الحفظ', 'Saved'));
      Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await appConfirm(context, message: _t('حذف هذا المسار؟', 'Delete this flow?'), danger: true);
    if (!ok) return;
    try {
      await widget.api.deleteFlow(widget.flow.role, widget.flow.key);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      width: AppWidth.reading,
      appBar: ScreenAppBar(
        title: widget.isNew ? _t('مسار جديد', 'New flow') : widget.flow.key,
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: _t('حذف', 'Delete'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          Text(helpRoleLabel(widget.flow.role, _ar), style: AppType.body(context).copyWith(color: context.colors.textLight)),
          AppSpace.gapSm,
          HelpFlowForm(draft: _draft, pageIds: _ids),
          AppSpace.gapLg,
          AppButton.primary(label: _t('حفظ', 'Save'), icon: Icons.check_rounded, busy: _saving, expand: true, onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}
