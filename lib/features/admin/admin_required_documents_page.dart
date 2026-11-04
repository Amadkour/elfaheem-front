// features/admin/admin_required_documents_page.dart
// Admin: documents teachers must upload at registration (additional_register_screen).
//
// The admin can add any document a teacher must submit (title in Arabic +
// English, description, icon, required / optional, active), reorder them by
// dragging, flip "required" / "active" with one tap, edit and delete.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart'
    show Breakpoints;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_premium_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
  State<AdminRequiredDocumentsPage> createState() =>
      _AdminRequiredDocumentsPageState();
}

class _AdminRequiredDocumentsPageState
    extends State<AdminRequiredDocumentsPage> {
  static const _base = '/api/v1/admin/required-documents';
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

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
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reorder(int from, int to) async {
    if (to > from) to--;
    final it = _items.removeAt(from);
    _items.insert(to, it);
    setState(() {});
    try {
      await _api.post(
        '$_base/reorder',
        body: {'ids': _items.map((e) => e['id']).toList()},
      );
    } catch (e) {
      toast('$e', error: true);
      _load(silent: true);
    }
  }

  Future<void> _toggle(Map<String, dynamic> d, String key) async {
    final v = !asBool(d[key]);
    try {
      await _api.put('$_base/${d['id']}', body: {key: v});
      if (mounted) setState(() => d[key] = v);
    } catch (e) {
      toast('$e', error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await confirm(
      context,
      message: 'doc_delete_confirm'.tr,
      confirmLabel: 'delete'.tr,
      danger: true,
    );
    if (!ok) return;
    try {
      final r = await _api.delete('$_base/${d['id']}');
      toast(
        r is Map && r['disabled'] == true
            ? 'doc_disabled_instead'.tr
            : 'doc_deleted'.tr,
      );
      await _load(silent: true);
    } catch (e) {
      toast('$e', error: true);
    }
  }

  Future<void> _edit([Map<String, dynamic>? d]) async {
    final body = await showAdminSheet<Map<String, dynamic>>(
      context,
      (ctx) => _DocForm(doc: d),
    );
    if (body == null) return;
    try {
      if (d == null) {
        await _api.post(_base, body: body);
      } else {
        await _api.put('$_base/${d['id']}', body: body);
      }
      toast('doc_saved'.tr);
      await _load(silent: true);
    } catch (e) {
      toast('$e', error: true);
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

  // ── pieces ───────────────────────────────────────────────────────────────
  Widget _header() {
    final requiredActive = _items
        .where((e) => asBool(e['is_required']) && asBool(e['is_active']))
        .length;
    final active = _items.where((e) => asBool(e['is_active'])).length;
    return PremiumHero(
      icon: Icons.folder_shared_rounded,
      colors: AdminPalette.teal,
      title: 'required_documents_title'.tr,
      subtitle: 'doc_intro'.tr,
      footer: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          HeroPill(
            trp('doc_count', {'n': _items.length}),
            icon: Icons.folder_copy_rounded,
          ),
          HeroPill(
            trp('doc_active_count', {'n': active}),
            icon: Icons.check_circle_rounded,
          ),
          HeroPill(
            trp('doc_required_count', {'n': requiredActive}),
            icon: Icons.priority_high_rounded,
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          ServiceIcon(
            icon: Icons.note_add_rounded,
            colors: AdminPalette.teal,
            size: 62,
          ),
          const SizedBox(height: 14),
          Text(
            'doc_empty'.tr,
            textAlign: TextAlign.center,
            style: adminText(
              context,
              size: 14,
              weight: FontWeight.w600,
              color: c.textMedium,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'doc_add'.tr,
              style: TextStyle(fontFamily: AppFonts.family),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required Color color,
    required bool on,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final fg = on ? color : c.textLight;
    return Material(
      color: on ? color.withValues(alpha: 0.13) : c.inputBg,
      shape: StadiumBorder(
        side: BorderSide(color: on ? color.withValues(alpha: 0.5) : c.divider),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(int i, Map<String, dynamic> d) {
    final c = context.colors;
    final isRequired = asBool(d['is_required']);
    final isActive = asBool(d['is_active']);
    final palette = AdminPalette.all[asInt(d['id']) % AdminPalette.all.length];
    final other = _otherTitle(d);

    return Container(
      key: ValueKey(d['id']),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        color: c.cardBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.divider),
        ),
        child: InkWell(
          onTap: () => _edit(d),
          child: Opacity(
            opacity: isActive ? 1 : 0.62,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ServiceIcon(
                        icon: docIcon(d['icon_name'] as String?),
                        colors: palette,
                        size: 48,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title(d),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: adminText(
                                context,
                                size: 15,
                                weight: FontWeight.w800,
                              ),
                            ),
                            if (other.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                other,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: adminText(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: c.textMedium,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'delete'.tr,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: c.danger,
                        ),
                        onPressed: () => _delete(d),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: c.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _pill(
                        label: isRequired
                            ? 'doc_required'.tr
                            : 'doc_optional'.tr,
                        icon: isRequired
                            ? Icons.priority_high_rounded
                            : Icons.remove_rounded,
                        color: AdminPalette.rose.last,
                        on: isRequired,
                        onTap: () => _toggle(d, 'is_required'),
                      ),
                      _pill(
                        label: isActive ? 'doc_active'.tr : 'doc_hidden'.tr,
                        icon: isActive
                            ? Icons.check_circle_rounded
                            : Icons.visibility_off_rounded,
                        color: AdminPalette.green.last,
                        on: isActive,
                        onTap: () => _toggle(d, 'is_active'),
                      ),
                      StatusChip(
                        trp('doc_uploads_n', {'n': asInt(d['uploads'])}),
                        AdminPalette.blue.last,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context
        .watch<
          LangProvider
        >(); // whole page re-translates when the language changes

    Widget body;
    if (_loading) {
      body = const AppListSkeleton();
    } else if (_error != null) {
      body = ErrorRetry(message: _error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = AppRefresh(onRefresh: () => _load(), child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [_header(), _empty()],
      ));
    } else {
      body = AppRefresh(onRefresh: () => _load(), child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        header: _header(),
        buildDefaultDragHandles: false,
        // our own handle on each card
        itemCount: _items.length,
        onReorder: _reorder,
        itemBuilder: (_, i) => _card(i, _items[i]),
      ));
    }

    return BasePage(
      useWebCard: true,
      appBar: ScreenAppBar(helpPageId: 'admin.teacher_documents', title: 'required_documents_title'.tr),
      floatingActionButton: (_loading || _error != null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.onHero,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'doc_add'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: body,
        ),
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
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titleAr;
  late final TextEditingController _titleEn;
  late final TextEditingController _descAr;
  late final TextEditingController _descEn;
  late String _icon;
  late bool _required;
  late bool _active;

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
    if (!(_form.currentState?.validate() ?? false)) return;
    String? n(TextEditingController t) =>
        t.text.trim().isEmpty ? null : t.text.trim();
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
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      key.tr,
      style: adminText(
        context,
        size: 12.5,
        weight: FontWeight.w700,
        color: context.colors.textMedium,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(_isNew ? 'doc_new'.tr : 'doc_edit'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isNew) ...[
                    _label('doc_quick_add'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _presets)
                          ActionChip(
                            avatar: Icon(
                              docIcon(p.icon),
                              size: 16,
                              color: c.primary,
                            ),
                            label: Text(
                              ar ? p.ar : p.en,
                              style: TextStyle(
                                fontFamily: AppFonts.family,
                                fontSize: 12.5,
                              ),
                            ),
                            backgroundColor: c.inputBg,
                            side: BorderSide(color: c.divider),
                            onPressed: () => _usePreset(p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Field(
                    controller: _titleAr,
                    label: 'doc_title_ar'.tr,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'doc_title_required'.tr
                        : null,
                  ),
                  Field(
                    controller: _titleEn,
                    label: 'doc_title_en'.tr,
                    ltr: true,
                  ),
                  Field(
                    controller: _descAr,
                    label: 'doc_desc_ar'.tr,
                    maxLines: 2,
                  ),
                  Field(
                    controller: _descEn,
                    label: 'doc_desc_en'.tr,
                    maxLines: 2,
                    ltr: true,
                  ),
                  _label('doc_icon'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final e in kDocIcons.entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _icon = e.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _icon == e.key
                                  ? c.primary.withValues(alpha: 0.12)
                                  : c.inputBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _icon == e.key ? c.primary : c.divider,
                                width: _icon == e.key ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              e.value,
                              color: _icon == e.key ? c.primary : c.textMedium,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PremiumSwitchRow(
                    icon: Icons.priority_high_rounded,
                    title: 'doc_required'.tr,
                    subtitle: 'doc_required_hint'.tr,
                    value: _required,
                    onChanged: (v) => setState(() => _required = v),
                  ),
                  PremiumSwitchRow(
                    icon: Icons.check_circle_rounded,
                    title: 'doc_active'.tr,
                    subtitle: 'doc_active_hint'.tr,
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'save'.tr,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: c.onHero,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
