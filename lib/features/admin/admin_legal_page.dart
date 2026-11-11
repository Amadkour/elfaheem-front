// lib/features/admin/admin_legal_page.dart
//
// The super admin's Privacy policy and Terms of service (D-308), the "Privacy & terms" tab of the About & terms page
// (admin_content_page.dart).
//
//   AdminLegalPanel        both documents as cards: version · effective date · shipped / customized · sections;
//                          Edit · Preview (the page users read) · Restore default
//   AdminLegalEditorPage   the whole document in Arabic and English: version, effective date, intro, "At a glance"
//                          points, sections (add · move · remove); Save sends it whole
//   LegalDocCard           plain values, pumped by the layout test
//
// Reads : GET    /api/v1/admin/legal/{privacy|terms}   {current, default, customized} (bilingual)
// Writes: PUT    /api/v1/admin/legal/{doc}             the whole document
//         DELETE /api/v1/admin/legal/{doc}             back to the shipped text
// Saving the terms also replaces the older terms sections (the "Terms (older apps)" tab), which installed app
// versions still read. The website's /privacy and /terms pages take the edit at their next build.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/profile/about/about_and_terms_screen.dart' show TermsScreen;

import 'admin_common.dart' as admin show t, asMap;
import 'admin_page.dart';

String _t(String ar, String en) => admin.t(ar, en);

const _base = '/api/v1/admin/legal';
const _docs = ['privacy', 'terms'];

/// A calendar date as midday UTC, so the platform timezone never moves it to the day before.
DateTime _noon(DateTime d) => DateTime.utc(d.year, d.month, d.day, 12);

String _pick(dynamic v) {
  if (v is! Map) return '${v ?? ''}';
  final ar = '${v['ar'] ?? ''}', en = '${v['en'] ?? ''}';
  return _t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The tab: both documents
// ═════════════════════════════════════════════════════════════════════════════

class AdminLegalPanel extends StatefulWidget {
  const AdminLegalPanel({super.key});

  @override
  State<AdminLegalPanel> createState() => _AdminLegalPanelState();
}

class _AdminLegalPanelState extends State<AdminLegalPanel> {
  final _api = ApiClient();
  final _data = <String, Map<String, dynamic>>{};
  Object? _error;
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final got = await Future.wait([for (final d in _docs) _api.get('$_base/$d')]);
      for (var i = 0; i < _docs.length; i++) {
        _data[_docs[i]] = admin.asMap(got[i]);
      }
      _error = null;
    } catch (e) {
      if (_data.isEmpty) {
        _error = e;
      } else {
        appToast(appErrorMessage(e), error: true);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit(String doc) async {
    final d = _data[doc];
    if (d == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AdminLegalEditorPage(doc: doc, initial: admin.asMap(d['current'])),
    ));
    if (saved == true) await _load();
  }

  Future<void> _restore(String doc) async {
    final ok = await appConfirm(
      context,
      danger: true,
      confirmLabel: _t('استعادة', 'Restore'),
      message: _t('سيُستبدل النص الحالي بالنص الافتراضي المرفق مع التطبيق. لا يمكن التراجع عن ذلك.',
          'The current text is replaced by the text shipped with the app. This cannot be undone.'),
    );
    if (!ok) return;
    setState(() => _busy = doc);
    try {
      await _api.delete('$_base/$doc');
      appToast(_t('تمت استعادة النص الافتراضي', 'Default text restored'));
      await _load();
    } catch (e) {
      appToast(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  void _preview(String doc) => Navigator.of(context).push(MaterialPageRoute(
        settings: RouteSettings(name: doc == 'privacy' ? '/privacy' : '/terms'),
        builder: (_) => TermsScreen(privacy: doc == 'privacy', canAsk: false),
      ));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppListSkeleton();
    if (_error != null) {
      return AppEmpty(
        icon: Icons.wifi_off_rounded,
        title: _t('تعذر التحميل', 'Could not load'),
        message: appErrorMessage(_error!),
        actionLabel: _t('إعادة المحاولة', 'Retry'),
        onAction: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: Icons.public_rounded,
        text: _t(
            'يقرأ الجميع هذين المستندين في التطبيق (حتى قبل تسجيل الدخول) وعلى الموقع nextbrain.site/privacy و nextbrain.site/terms. يظهر تعديلك في التطبيق فورًا، وعلى الموقع عند بنائه التالي.',
            'Everyone reads these two documents in the app (even before signing in) and on the website at nextbrain.site/privacy and nextbrain.site/terms. Your edit shows in the app at once, and on the website at its next build.'),
      ),
      const SizedBox(height: AppSpace.md),
      for (final doc in _docs)
        if (_data[doc] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: LegalDocCard(
              privacy: doc == 'privacy',
              title: _pick(admin.asMap(_data[doc]!['current'])['title']),
              version: '${admin.asMap(_data[doc]!['current'])['version'] ?? ''}',
              effectiveDate: '${admin.asMap(_data[doc]!['current'])['effective_date'] ?? ''}',
              sections: (admin.asMap(_data[doc]!['current'])['sections'] as List?)?.length ?? 0,
              customized: _data[doc]!['customized'] == true,
              busy: _busy == doc,
              onEdit: () => _edit(doc),
              onPreview: () => _preview(doc),
              onRestore: () => _restore(doc),
            ),
          ),
    ]);
  }
}

/// One document's card. Plain values.
class LegalDocCard extends StatelessWidget {
  const LegalDocCard({
    super.key,
    required this.privacy,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.sections,
    required this.customized,
    required this.onEdit,
    required this.onPreview,
    required this.onRestore,
    this.busy = false,
  });

  final bool privacy;
  final String title;
  final String version;
  final String effectiveDate;
  final int sections;
  final bool customized;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = privacy ? c.success : c.primary;
    final when = DateTime.tryParse(effectiveDate);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md + 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.22 : 0.10), borderRadius: BorderRadius.circular(AppRadius.chip + 4)),
            child: Icon(privacy ? Icons.privacy_tip_rounded : Icons.gavel_rounded, color: appInk(context, tone)),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.section(context).copyWith(color: c.textDark, height: 1.3)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppTag(customized ? _t('معدّل', 'Customized') : _t('النص الافتراضي', 'Shipped text'),
                    customized ? c.warning : c.success,
                    icon: customized ? Icons.edit_note_rounded : Icons.verified_rounded),
                if (version.isNotEmpty) AppTag('${_t('الإصدار', 'Version')} $version', c.primary, icon: Icons.tag_rounded),
                if (when != null)
                  AppTag('${_t('سارية منذ', 'Effective')} ${AppTime.date(_noon(when))}', c.textMedium, icon: Icons.event_rounded),
                AppTag(
                    countText(sections, ar1: 'قسم واحد', ar2: 'قسمان', arFew: '{n} أقسام', arMany: '{n} قسمًا', en1: '1 section', en: '{n} sections'),
                    c.textMedium,
                    icon: Icons.view_agenda_rounded),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          AppButton.primary(label: _t('تعديل', 'Edit'), icon: Icons.edit_rounded, onPressed: busy ? null : onEdit),
          AppButton.secondary(label: _t('معاينة', 'Preview'), icon: Icons.visibility_rounded, onPressed: onPreview),
          if (customized)
            AppButton.ghost(
                label: _t('استعادة النص الافتراضي', 'Restore default'),
                icon: Icons.restore_rounded,
                busy: busy,
                onPressed: busy ? null : onRestore),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The editor
// ═════════════════════════════════════════════════════════════════════════════

class _Pair {
  _Pair(dynamic v)
      : ar = TextEditingController(text: v is Map ? '${v['ar'] ?? ''}' : ''),
        en = TextEditingController(text: v is Map ? '${v['en'] ?? ''}' : '');

  final TextEditingController ar;
  final TextEditingController en;

  Map<String, String> get value => {'ar': ar.text.trim(), 'en': en.text.trim()};
  bool get isEmpty => ar.text.trim().isEmpty && en.text.trim().isEmpty;

  void dispose() {
    ar.dispose();
    en.dispose();
  }
}

class _Section {
  _Section(Map<String, dynamic> s)
      : id = '${s['id'] ?? ''}',
        icon = '${s['icon'] ?? 'description'}',
        title = _Pair(s['title']),
        body = _Pair(s['body']);

  final String id;
  final String icon;
  final _Pair title;
  final _Pair body;

  void dispose() {
    title.dispose();
    body.dispose();
  }
}

class AdminLegalEditorPage extends StatefulWidget {
  const AdminLegalEditorPage({super.key, required this.doc, required this.initial});

  final String doc;
  final Map<String, dynamic> initial;

  @override
  State<AdminLegalEditorPage> createState() => _AdminLegalEditorPageState();
}

class _AdminLegalEditorPageState extends State<AdminLegalEditorPage> {
  late final TextEditingController _version;
  late DateTime _effective;
  late final _Pair _title;
  late final _Pair _intro;
  late final List<_Pair> _highlights;
  late final List<_Section> _sections;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _version = TextEditingController(text: '${d['version'] ?? '1.0'}');
    _effective = DateTime.tryParse('${d['effective_date'] ?? ''}') ?? DateTime.now();
    _title = _Pair(d['title']);
    _intro = _Pair(d['intro']);
    _highlights = [for (final h in (d['highlights'] as List? ?? const [])) _Pair(h)];
    _sections = [for (final s in (d['sections'] as List? ?? const [])) if (s is Map) _Section(Map<String, dynamic>.from(s))];
  }

  @override
  void dispose() {
    _version.dispose();
    _title.dispose();
    _intro.dispose();
    for (final h in _highlights) {
      h.dispose();
    }
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String get _iso =>
      '${_effective.year.toString().padLeft(4, '0')}-${_effective.month.toString().padLeft(2, '0')}-${_effective.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final got = await showDatePicker(
      context: context,
      initialDate: _effective,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (got != null) {
      setState(() {
        _effective = got;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (_sections.isEmpty || _sections.every((s) => s.title.isEmpty)) {
      appToast(_t('أضف قسمًا واحدًا على الأقل', 'Add at least one section'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient().put('$_base/${widget.doc}', body: {
        'version': _version.text.trim(),
        'effective_date': _iso,
        'title': _title.value,
        'intro': _intro.value,
        'highlights': [for (final h in _highlights) if (!h.isEmpty) h.value],
        'sections': [
          for (final s in _sections)
            if (!(s.title.isEmpty && s.body.isEmpty)) {'id': s.id, 'icon': s.icon, 'title': s.title.value, 'body': s.body.value},
        ],
      });
      appToast(_t('تم الحفظ', 'Saved'));
      _dirty = false;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      appToast(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= _sections.length) return;
    setState(() {
      final s = _sections.removeAt(i);
      _sections.insert(j, s);
      _dirty = true;
    });
  }

  Future<void> _remove(int i) async {
    final ok = await appConfirm(context, danger: true, confirmLabel: _t('حذف', 'Delete'), message: _t('حذف هذا القسم؟', 'Delete this section?'));
    if (!ok) return;
    setState(() {
      _sections.removeAt(i).dispose();
      _dirty = true;
    });
  }

  Widget _pair(_Pair p, String label, {int lines = 1}) => LayoutBuilder(builder: (context, box) {
        final ar = AppField(controller: p.ar, label: '$label · ${_t('عربي', 'Arabic')}', maxLines: lines, onChanged: (_) => _touch());
        final en = Directionality(
          textDirection: TextDirection.ltr,
          child: AppField(controller: p.en, label: '$label · ${_t('إنجليزي', 'English')}', maxLines: lines, onChanged: (_) => _touch()),
        );
        if (box.maxWidth < 720) {
          return Column(children: [ar, const SizedBox(height: AppSpace.sm), en]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ar),
          const SizedBox(width: AppSpace.md),
          Expanded(child: en),
        ]);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final privacy = widget.doc == 'privacy';
    return AdminPage(
      title: privacy ? _t('تعديل سياسة الخصوصية', 'Edit the privacy policy') : _t('تعديل شروط الاستخدام', 'Edit the terms of service'),
      subtitle: _t('النص بالعربية والإنجليزية؛ يُحفظ المستند كاملًا', 'Arabic and English; the whole document is saved at once'),
      icon: privacy ? Icons.privacy_tip_rounded : Icons.gavel_rounded,
      dirty: _dirty,
      primaryAction: AppButton.primary(label: _t('حفظ', 'Save'), icon: Icons.check_rounded, busy: _saving, onPressed: _saving ? null : _save),
      body: ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSectionTitle(_t('المستند', 'Document')),
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: AppSpace.md, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.end, children: [
                SizedBox(
                  width: 180,
                  child: AppField(controller: _version, label: _t('الإصدار', 'Version'), hint: '2.1', onChanged: (_) => _touch()),
                ),
                AppButton.secondary(
                  label: '${_t('سارية منذ', 'Effective')} ${AppTime.date(_noon(_effective))}',
                  icon: Icons.event_rounded,
                  onPressed: _pickDate,
                ),
              ]),
              const SizedBox(height: AppSpace.md),
              _pair(_title, _t('العنوان', 'Title')),
              const SizedBox(height: AppSpace.sm),
              _pair(_intro, _t('المقدمة', 'Introduction'), lines: 4),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSectionTitle(_t('باختصار', 'At a glance')),
              Text(_t('نقاط قصيرة تظهر في أعلى الصفحة (حتى 8).', 'Short points shown at the top of the page (up to 8).'),
                  style: AppType.label(context).copyWith(color: c.textMedium, height: 1.5)),
              const SizedBox(height: AppSpace.sm),
              for (var i = 0; i < _highlights.length; i++) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _pair(_highlights[i], '${_t('نقطة', 'Point')} ${i + 1}', lines: 2)),
                  IconButton(
                    tooltip: _t('حذف', 'Delete'),
                    icon: Icon(Icons.close_rounded, color: c.textLight),
                    onPressed: () => setState(() {
                      _highlights.removeAt(i).dispose();
                      _dirty = true;
                    }),
                  ),
                ]),
                const SizedBox(height: AppSpace.sm),
              ],
              if (_highlights.length < 8)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton.ghost(
                    label: _t('إضافة نقطة', 'Add a point'),
                    icon: Icons.add_rounded,
                    onPressed: () => setState(() {
                      _highlights.add(_Pair(null));
                      _dirty = true;
                    }),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          AppBanner(
            icon: Icons.format_list_bulleted_rounded,
            text: _t('في نص القسم: سطر فارغ يبدأ فقرة جديدة، والسطر الذي يبدأ بـ «- » نقطة.',
                'In a section body: a blank line starts a new paragraph, and a line starting with "- " is a bullet.'),
          ),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < _sections.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${_t('القسم', 'Section')} ${i + 1}', style: AppType.section(context).copyWith(color: c.textDark)),
                    ),
                    IconButton(
                      tooltip: _t('للأعلى', 'Move up'),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      onPressed: i == 0 ? null : () => _move(i, -1),
                    ),
                    IconButton(
                      tooltip: _t('للأسفل', 'Move down'),
                      icon: const Icon(Icons.arrow_downward_rounded),
                      onPressed: i == _sections.length - 1 ? null : () => _move(i, 1),
                    ),
                    IconButton(
                      tooltip: _t('حذف', 'Delete'),
                      icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                      onPressed: () => _remove(i),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.xs),
                  _pair(_sections[i].title, _t('العنوان', 'Title')),
                  const SizedBox(height: AppSpace.sm),
                  _pair(_sections[i].body, _t('النص', 'Text'), lines: 8),
                ]),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              label: _t('إضافة قسم', 'Add a section'),
              icon: Icons.add_rounded,
              onPressed: () => setState(() {
                _sections.add(_Section(const {'icon': 'description'}));
                _dirty = true;
              }),
            ),
          ),
        ],
      ),
    );
  }
}
