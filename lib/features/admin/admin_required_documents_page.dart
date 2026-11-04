// features/admin/admin_required_documents_page.dart
// Admin: documents teachers must upload at registration (additional_register_screen).
//
// The admin can add any document a teacher must submit (title in Arabic +
// English, description, icon, required / optional, active), reorder them
// (move up / down), flip "required" / "active" with one tap, edit and delete.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_page.dart';
import 'package:flutter_education_app/design/app_kit.dart';

/// icon_name (stored in the DB) → icon. Use the same map in
/// additional_register_screen so the teacher sees the icon the admin picked.
const Map<String, IconData> kDocIcons = {
  'description': Icons.description_rounded,
  'badge': Icons.badge_rounded,
  'school': Icons.school_rounded,
  'assignment': Icons.assignment_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'credit_card': Icons.credit_card_rounded,
  'verified_user': Icons.verified_user_rounded,
  'folder': Icons.folder_rounded,
  'article': Icons.article_rounded,
  'history_edu': Icons.history_edu_rounded,
  'contact_page': Icons.contact_page_rounded,
  'work': Icons.work_rounded,
  'photo_camera': Icons.photo_camera_rounded,
  'language': Icons.language_rounded,
};

IconData docIcon(String? name) => kDocIcons[name] ?? Icons.description_rounded;

/// One-tap starting points when adding a document (stored in both languages,
/// so these are data, not translation keys).
const _presets = [
  _Preset('الهوية الشخصية', 'National ID', 'badge'),
  _Preset('المؤهل الدراسي', 'University degree', 'school'),
  _Preset('السيرة الذاتية', 'CV / Resume', 'contact_page'),
  _Preset('شهادة خبرة', 'Experience certificate', 'work'),
  _Preset('رخصة مزاولة التدريس', 'Teaching license', 'workspace_premium'),
  _Preset('صورة شخصية', 'Personal photo', 'photo_camera'),
];

class _Preset {
  const _Preset(this.ar, this.en, this.icon);

  final String ar, en, icon;
}

class AdminRequiredDocumentsPage extends StatefulWidget {
  const AdminRequiredDocumentsPage({super.key});

  @override
  State<AdminRequiredDocumentsPage> createState() => _AdminRequiredDocumentsPageState();
}

class _AdminRequiredDocumentsPageState extends State<AdminRequiredDocumentsPage> {
  static const _base = '/api/v1/admin/required-documents';
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Object? _error;
  DateTime? _loadedAt;
  final Set<Object> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final r = await _api.get(_base);
      _items = asMapList(r);
      _error = null;
      _loadedAt = DateTime.now();
    } catch (e) {
      // a failed refresh keeps the rows on screen
      if (_items.isEmpty || !silent) {
        if (_items.isEmpty) _error = e;
      }
      if (_items.isNotEmpty) showAppNotice(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _move(int from, int to) async {
    if (to < 0 || to >= _items.length) return;
    final it = _items.removeAt(from);
    _items.insert(to, it);
    setState(() {});
    try {
      await _api.post('$_base/reorder', body: {'ids': _items.map((e) => e['id']).toList()});
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
      _load(silent: true);
    }
  }

  Future<void> _toggle(Map<String, dynamic> d, String key) async {
    final id = d['id'] as Object;
    if (_busyIds.contains(id)) return;
    final v = !asBool(d[key]);
    setState(() => _busyIds.add(id));
    try {
      await _api.put('$_base/${d['id']}', body: {key: v});
      if (mounted) {
        // replace the row with a copy: the response map is never mutated in place
        final i = _items.indexWhere((e) => e['id'] == id);
        if (i >= 0) _items[i] = {..._items[i], key: v};
      }
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _busyIds.remove(id));
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await appConfirm(
      context,
      message: '${_title(d)}\n${'doc_delete_confirm'.tr}',
      confirmLabel: 'delete'.tr,
      danger: true,
    );
    if (!ok) return;
    try {
      final r = await _api.delete('$_base/${d['id']}');
      showAppNotice(r is Map && r['disabled'] == true ? 'doc_disabled_instead'.tr : 'doc_deleted'.tr);
      await _load(silent: true);
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
  }

  Future<void> _edit([Map<String, dynamic>? d]) async {
    final body = await showAppSheet<Map<String, dynamic>>(context, (ctx) => _DocForm(doc: d));
    if (body == null) return;
    try {
      if (d == null) {
        await _api.post(_base, body: body);
      } else {
        await _api.put('$_base/${d['id']}', body: body);
      }
      showAppNotice('doc_saved'.tr);
      await _load(silent: true);
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  bool get _ar => AppConfig.lang == 'ar';

  String _title(Map<String, dynamic> d) {
    final ar = asStr(d['title_ar']);
    final en = asStr(d['title_en']);
    return _ar ? ar : (en.isEmpty ? ar : en);
  }

  String _otherTitle(Map<String, dynamic> d) {
    final ar = asStr(d['title_ar']);
    final en = asStr(d['title_en']);
    return _ar ? en : ar;
  }

  /// A switch with a 48 px hit area (the track alone is 28 px high).
  Widget _toggleCell(Map<String, dynamic> d, String key, String label) => Semantics(
        label: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          child: Center(
            child: AppSwitch(
              value: asBool(d[key]),
              semanticLabel: label,
              onChanged: _busyIds.contains(d['id']) ? null : (_) => _toggle(d, key),
            ),
          ),
        ),
      );

  Widget _summary() {
    final requiredActive = _items.where((e) => asBool(e['is_required']) && asBool(e['is_active'])).length;
    final active = _items.where((e) => asBool(e['is_active'])).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('doc_intro'.tr, style: AppType.meta(context)),
        AppStatusBadge(label: trp('doc_count', {'n': _items.length}), tone: AppTone.neutral),
        AppStatusBadge(label: trp('doc_active_count', {'n': active}), tone: AppTone.success),
        AppStatusBadge(label: trp('doc_required_count', {'n': requiredActive}), tone: AppTone.warning),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // whole page re-translates when the language changes
    final c = context.colors;
    return AdminPage(
      title: 'required_documents_title'.tr,
      icon: Icons.folder_shared_rounded,
      onRefresh: _loading ? null : () => _load(silent: true),
      updatedAt: _loadedAt,
      // ONE "add" button: the header's (the empty state only explains)
      primaryAction: AppButton.primary(
        label: 'doc_add'.tr,
        icon: Icons.add_rounded,
        onPressed: _loading || _error != null ? null : () => _edit(),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_loading && _error == null && _items.isNotEmpty) _summary(),
          Expanded(
            child: AppDataTable<Map<String, dynamic>>(
              state: _loading
                  ? AppTableState.loading
                  : _error != null
                      ? AppTableState.error
                      : AppTableState.ready,
              errorText: appErrorMessage(_error),
              onRetry: _load,
              rows: _items,
              empty: AppEmpty(icon: Icons.note_add_rounded, title: 'doc_empty'.tr),
              onRowTap: _edit,
              columns: [
                AppTableColumn<Map<String, dynamic>>(
                  key: 'title',
                  label: t('المستند', 'Document'),
                  primary: true,
                  flex: 3,
                  cell: (context, d) {
                    final other = _otherTitle(d);
                    return Row(children: [
                      Icon(docIcon(d['icon_name'] as String?), color: c.primary, size: AppIconSize.lg),
                      AppSpace.gapSm,
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(_title(d), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                          if (other.isNotEmpty) Text(other, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                        ]),
                      ),
                    ]);
                  },
                ),
                AppTableColumn<Map<String, dynamic>>(
                  key: 'required',
                  label: 'doc_required'.tr,
                  cell: (context, d) => _toggleCell(d, 'is_required', 'doc_required'.tr),
                ),
                AppTableColumn<Map<String, dynamic>>(
                  key: 'active',
                  label: 'doc_active'.tr,
                  cell: (context, d) => _toggleCell(d, 'is_active', 'doc_active'.tr),
                ),
                AppTableColumn<Map<String, dynamic>>.text(
                  key: 'uploads',
                  label: t('المرفوعات', 'Uploads'),
                  numeric: true,
                  text: (d) => '${asInt(d['uploads'])}',
                ),
              ],
              rowActions: (d) {
                final i = _items.indexOf(d);
                return [
                  AppRowAction(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _edit(d)),
                  AppRowAction(icon: Icons.delete_outline_rounded, label: 'delete'.tr, danger: true, onTap: () => _delete(d)),
                  if (i > 0) AppRowAction(icon: Icons.arrow_upward_rounded, label: t('تحريك لأعلى', 'Move up'), onTap: () => _move(i, i - 1)),
                  if (i >= 0 && i < _items.length - 1)
                    AppRowAction(icon: Icons.arrow_downward_rounded, label: t('تحريك لأسفل', 'Move down'), onTap: () => _move(i, i + 1)),
                ];
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── add / edit form (bottom sheet) ───────────────────────────────────────────
/// Owns its controllers, so they are disposed only after the sheet's closing
/// animation (no "used after being disposed" errors).
class _DocForm extends StatefulWidget {
  const _DocForm({this.doc});

  final Map<String, dynamic>? doc;

  @override
  State<_DocForm> createState() => _DocFormState();
}

class _DocFormState extends State<_DocForm> {
  late final TextEditingController _titleAr;
  late final TextEditingController _titleEn;
  late final TextEditingController _descAr;
  late final TextEditingController _descEn;
  late String _icon;
  late bool _required;
  late bool _active;
  bool _tried = false;

  bool get _isNew => widget.doc == null;

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    _titleAr = TextEditingController(text: asStr(d?['title_ar']));
    _titleEn = TextEditingController(text: asStr(d?['title_en']));
    _descAr = TextEditingController(text: asStr(d?['description_ar']));
    _descEn = TextEditingController(text: asStr(d?['description_en']));
    _icon = asStr(d?['icon_name'], 'description');
    _required = d?['is_required'] ?? true;
    _active = d?['is_active'] ?? true;
  }

  @override
  void dispose() {
    _titleAr.dispose();
    _titleEn.dispose();
    _descAr.dispose();
    _descEn.dispose();
    super.dispose();
  }

  void _usePreset(_Preset p) => setState(() {
        _titleAr.text = p.ar;
        _titleEn.text = p.en;
        _icon = p.icon;
      });

  void _submit() {
    if (_titleAr.text.trim().isEmpty) {
      setState(() => _tried = true);
      return;
    }
    String? n(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();
    Navigator.pop(context, <String, dynamic>{
      'title_ar': _titleAr.text.trim(),
      'title_en': n(_titleEn),
      'description_ar': n(_descAr),
      'description_en': n(_descEn),
      'icon_name': _icon.isEmpty ? 'description' : _icon,
      'is_required': _required,
      'is_active': _active,
    });
  }

  Widget _label(String key) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs, top: AppSpace.xxs),
        child: Text(key.tr, style: AppType.label(context)),
      );

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';

    return AppSheetContent(
      title: _isNew ? 'doc_new'.tr : 'doc_edit'.tr,
      children: [
        if (_isNew) ...[
          _label('doc_quick_add'),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final p in _presets) AppChoiceChip(label: ar ? p.ar : p.en, icon: docIcon(p.icon), selected: false, onTap: () => _usePreset(p)),
            ],
          ),
          AppSpace.gapMd,
        ],
        AppField(controller: _titleAr, label: 'doc_title_ar'.tr, onChanged: (_) => setState(() {})),
        if (_tried && _titleAr.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text('doc_title_required'.tr, style: AppType.meta(context).copyWith(color: c.danger)),
          ),
        AppField(controller: _titleEn, label: 'doc_title_en'.tr, ltr: true),
        AppField(controller: _descAr, label: 'doc_desc_ar'.tr, maxLines: 2),
        AppField(controller: _descEn, label: 'doc_desc_en'.tr, maxLines: 2, ltr: true),
        _label('doc_icon'),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final e in kDocIcons.entries)
              InkWell(
                borderRadius: AppRadius.cardAll,
                onTap: () => setState(() => _icon = e.key),
                child: AnimatedContainer(
                  duration: AppMotion.of(context).fast,
                  width: AppTouch.min,
                  height: AppTouch.min,
                  decoration: BoxDecoration(
                    color: _icon == e.key ? c.primary.withValues(alpha: 0.12) : c.inputBg,
                    borderRadius: AppRadius.cardAll,
                    border: Border.all(
                      color: _icon == e.key ? c.primary : c.divider,
                      width: _icon == e.key ? AppBorder.focus : AppBorder.hairline,
                    ),
                  ),
                  child: Icon(e.value, color: _icon == e.key ? c.primary : c.textMedium, size: AppIconSize.lg),
                ),
              ),
          ],
        ),
        AppSpace.gapMd,
        AppSwitchTile(
          icon: Icons.priority_high_rounded,
          title: 'doc_required'.tr,
          subtitle: 'doc_required_hint'.tr,
          value: _required,
          onChanged: (v) => setState(() => _required = v),
        ),
        AppSwitchTile(
          icon: Icons.check_circle_rounded,
          title: 'doc_active'.tr,
          subtitle: 'doc_active_hint'.tr,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        AppSpace.gapXs,
        AppButton.primary(label: 'save'.tr, expand: true, onPressed: _submit),
      ],
    );
  }
}
