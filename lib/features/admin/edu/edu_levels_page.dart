// lib/features/admin/edu/edu_levels_page.dart
//
// The super admin's "Education levels" page (learning hub phase 2, D-1304, kill switch `admin.edu_levels`).
//
//   Country     a picker at the top, "Add country" (optionally copied from an existing one)
//   Stages      stages (reorder, rename, deactivate) and their grades; master-detail on wide screens, an inline
//               expansion on phones
//   Subjects    the subject list (CRUD) and, per grade, which subjects it teaches
//   Areas       level 1 -> level 2 with CRUD, and what each level is called in this country
//
// Reordering is the row menu's Move up / Move down (works the same with a finger and a mouse).
// [EduLevelsBody] takes plain values and an [EduActions] (the layout harness pumps it); the page owns the calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';

import '../admin_common.dart' show t;
import '../admin_page.dart';
import 'edu_admin_api.dart';

enum EduKind { stage, grade, subject, area }

enum EduTab { stages, subjects, areas }

/// What the body asks the page to do.
abstract class EduActions {
  void selectCountry(String code);
  void addCountry();
  void editLabels();
  void add(EduKind kind, {EduRow? parent});
  void edit(EduKind kind, EduRow row);
  void toggleActive(EduKind kind, EduRow row);
  void delete(EduKind kind, EduRow row);
  void move(EduKind kind, EduRow row, int dir);
  void pickGradeSubjects(EduRow grade);

  /// The country's currency and VAT rule (D-1336).
  void editTax();
}

/// The whole page body from plain values.
class EduLevelsBody extends StatefulWidget {
  const EduLevelsBody({super.key, required this.countries, required this.country, required this.tree, required this.actions});

  final List<EduCountryRow> countries;
  final String country;
  final EduTree? tree;
  final EduActions actions;

  @override
  State<EduLevelsBody> createState() => _EduLevelsBodyState();
}

class _EduLevelsBodyState extends State<EduLevelsBody> {
  EduTab _tab = EduTab.stages;
  int? _stageId;

  bool get _ar => AppConfig.lang == 'ar';

  @override
  Widget build(BuildContext context) {
    final tree = widget.tree;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _CountryBar(countries: widget.countries, value: widget.country, actions: widget.actions),
      if (tree != null) ...[AppSpace.gapSm, EduTaxCard(country: tree.country, onEdit: widget.actions.editTax)],
      AppSpace.gapSm,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final tb in EduTab.values)
          _tab == tb
              ? AppButton.tonal(label: _tabLabel(tb), onPressed: () {}, size: AppButtonSize.sm)
              : AppButton.ghost(label: _tabLabel(tb), onPressed: () => setState(() => _tab = tb), size: AppButtonSize.sm),
      ]),
      AppSpace.gapMd,
      if (tree == null)
        const AppListSkeleton(items: 4)
      else
        switch (_tab) {
          EduTab.stages => _stages(context, tree),
          EduTab.subjects => _subjects(context, tree),
          EduTab.areas => _areas(context, tree),
        },
    ]);
  }

  String _tabLabel(EduTab tb) => switch (tb) {
        EduTab.stages => t('المراحل والصفوف', 'Stages & grades'),
        EduTab.subjects => t('المواد', 'Subjects'),
        EduTab.areas => t('المناطق', 'Areas'),
      };

  // ── stages ────────────────────────────────────────────────────────────────
  Widget _stages(BuildContext context, EduTree tree) {
    final a = widget.actions;
    final selected = tree.stages.where((s) => s.id == _stageId).firstOrNull ?? (tree.stages.isEmpty ? null : tree.stages.first);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      Widget list() => AppSectionCard(
            title: t('المراحل', 'Stages'),
            actions: [AppButton.tonal(label: t('إضافة مرحلة', 'Add stage'), icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: () => a.add(EduKind.stage))],
            child: tree.stages.isEmpty
                ? Text(t('لا توجد مراحل بعد.', 'No stages yet.'), style: AppType.body(context))
                : Column(children: [
                    for (final s in tree.stages) ...[
                      _RowCard(
                        row: s,
                        ar: _ar,
                        kind: EduKind.stage,
                        actions: a,
                        selected: selected?.id == s.id,
                        subtitle: t('${s.children.length} صفوف', '${s.children.length} grades'),
                        onTap: () => setState(() => _stageId = (!wide && _stageId == s.id) ? -1 : s.id),
                      ),
                      if (!wide && selected?.id == s.id && _stageId != -1) _grades(context, s, indent: true),
                      AppSpace.gapXs,
                    ],
                  ]),
          );
      if (!wide) return list();
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: list()),
        AppSpace.gapMd,
        Expanded(
          flex: 3,
          child: selected == null ? const SizedBox() : AppSectionCard(title: selected.name(_ar), child: _grades(context, selected)),
        ),
      ]);
    });
  }

  Widget _grades(BuildContext context, EduRow stage, {bool indent = false}) {
    final a = widget.actions;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent ? AppSpace.md : 0, top: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final g in stage.children) ...[
          _RowCard(row: g, ar: _ar, kind: EduKind.grade, actions: a, subtitle: t('${g.subjectIds.length} مواد', '${g.subjectIds.length} subjects')),
          AppSpace.gapXs,
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(label: t('إضافة صف', 'Add grade'), icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: () => a.add(EduKind.grade, parent: stage)),
        ),
      ]),
    );
  }

  // ── subjects ──────────────────────────────────────────────────────────────
  Widget _subjects(BuildContext context, EduTree tree) {
    final a = widget.actions;
    final subjects = AppSectionCard(
      title: t('المواد', 'Subjects'),
      subtitle: t('يختار كل صف المواد التي يدرسها في البطاقة الأخرى.', 'Each grade picks the ones it teaches, in the other card.'),
      actions: [AppButton.tonal(label: t('إضافة مادة', 'Add subject'), icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: () => a.add(EduKind.subject))],
      child: tree.subjects.isEmpty
          ? Text(t('لا توجد مواد بعد.', 'No subjects yet.'), style: AppType.body(context))
          : Column(children: [
              for (final s in tree.subjects) ...[_RowCard(row: s, ar: _ar, kind: EduKind.subject, actions: a), AppSpace.gapXs],
            ]),
    );
    final perGrade = AppSectionCard(
      title: t('مواد كل صف', 'Subjects per grade'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in tree.stages) ...[
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(s.name(_ar), style: AppType.bodyStrong(context))),
          for (final g in s.children) ...[
            AppCard(
              onTap: () => a.pickGradeSubjects(g),
              child: Row(children: [
                Expanded(child: Text(g.name(_ar), style: AppType.row(context))),
                Text(t('${g.subjectIds.length} مواد', '${g.subjectIds.length} subjects'), style: AppType.label(context)),
                AppSpace.gapXs,
                const Icon(Icons.edit_rounded, size: AppIconSize.sm),
              ]),
            ),
            AppSpace.gapXs,
          ],
        ],
      ]),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 900
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: subjects), AppSpace.gapMd, Expanded(child: perGrade)])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [subjects, AppSpace.gapMd, perGrade]),
    );
  }

  // ── areas ─────────────────────────────────────────────────────────────────
  Widget _areas(BuildContext context, EduTree tree) {
    final a = widget.actions;
    final l1 = tree.country.labels['1'];
    final l2 = tree.country.labels['2'];
    String label((String, String)? l, String fallbackAr, String fallbackEn) {
      if (l == null) return t(fallbackAr, fallbackEn);
      final v = _ar ? l.$1 : l.$2;
      return v.isEmpty ? t(fallbackAr, fallbackEn) : v;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionCard(
        title: t('أسماء المستويين', 'Level names'),
        subtitle: t('كيف تُسمّى المستويات في هذه الدولة (مثل: محافظة ثم مركز).', 'What the two levels are called in this country (e.g. governorate, then district).'),
        actions: [AppButton.tonal(label: t('تعديل', 'Edit'), icon: Icons.edit_rounded, size: AppButtonSize.sm, onPressed: a.editLabels)],
        child: Text('${label(l1, 'المستوى ١', 'Level 1')}  >  ${label(l2, 'المستوى ٢', 'Level 2')}', style: AppType.row(context)),
      ),
      AppSpace.gapMd,
      AppSectionCard(
        title: label(l1, 'المستوى ١', 'Level 1'),
        actions: [AppButton.tonal(label: t('إضافة', 'Add'), icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: () => a.add(EduKind.area))],
        child: tree.roots.isEmpty
            ? Text(t('لا توجد مناطق بعد.', 'No areas yet.'), style: AppType.body(context))
            : Column(children: [
                for (final r in tree.roots) ...[
                  _RowCard(row: r, ar: _ar, kind: EduKind.area, actions: a, subtitle: t('${tree.childrenOf(r.id).length} داخلها', '${tree.childrenOf(r.id).length} inside')),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.xxs),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final c in tree.childrenOf(r.id)) ...[
                        _RowCard(row: c, ar: _ar, kind: EduKind.area, actions: a),
                        AppSpace.gapXs,
                      ],
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppButton.ghost(label: t('إضافة إلى ${r.nameAr}', 'Add to ${r.nameEn}'), icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: () => a.add(EduKind.area, parent: r)),
                      ),
                    ]),
                  ),
                  AppSpace.gapXs,
                ],
              ]),
      ),
    ]);
  }
}

class _CountryBar extends StatelessWidget {
  const _CountryBar({required this.countries, required this.value, required this.actions});
  final List<EduCountryRow> countries;
  final String value;
  final EduActions actions;

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    final picker = AppDropdown<String>(
      value: countries.any((c) => c.code == value) ? value : null,
      hint: Text(t('الدولة', 'Country')),
      items: [
        for (final c in countries)
          DropdownMenuItem(value: c.code, child: Text('${c.name(ar)}${c.active ? '' : ' (${t('متوقفة', 'off')})'}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) actions.selectCountry(v);
      },
    );
    final add = AppButton.secondary(label: t('إضافة دولة', 'Add country'), icon: Icons.add_rounded, onPressed: actions.addCountry);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 520
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [picker, AppSpace.gapXs, add])
          : Row(children: [Expanded(child: picker), AppSpace.gapSm, add]),
    );
  }
}

/// One row (stage, grade, subject or area): name, state, and a menu with move / rename / deactivate / delete.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.ar, required this.kind, required this.actions, this.subtitle, this.selected = false, this.onTap});

  final EduRow row;
  final bool ar;
  final EduKind kind;
  final EduActions actions;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = [if (subtitle != null) subtitle!, if (!row.active) t('متوقف', 'Inactive')].join(' · ');
    return AppCard(
      highlight: selected,
      onTap: onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name(ar), style: AppType.row(context).copyWith(color: row.active ? null : c.textLight), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (sub.isNotEmpty) Text(sub, style: AppType.label(context).copyWith(color: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: t('المزيد', 'More'),
          onSelected: (v) {
            switch (v) {
              case 'up':
                actions.move(kind, row, -1);
              case 'down':
                actions.move(kind, row, 1);
              case 'edit':
                actions.edit(kind, row);
              case 'active':
                actions.toggleActive(kind, row);
              case 'delete':
                actions.delete(kind, row);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'up', child: Text(t('تحريك لأعلى', 'Move up'))),
            PopupMenuItem(value: 'down', child: Text(t('تحريك لأسفل', 'Move down'))),
            PopupMenuItem(value: 'edit', child: Text(t('تعديل الاسم', 'Rename'))),
            PopupMenuItem(value: 'active', child: Text(row.active ? t('إيقاف', 'Deactivate') : t('تفعيل', 'Activate'))),
            PopupMenuItem(value: 'delete', child: Text(t('حذف', 'Delete'))),
          ],
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class AdminEduLevelsPage extends StatefulWidget {
  const AdminEduLevelsPage({super.key});

  @override
  State<AdminEduLevelsPage> createState() => _AdminEduLevelsPageState();
}

class _AdminEduLevelsPageState extends State<AdminEduLevelsPage> implements EduActions {
  static const _api = EduAdminApi();
  List<EduCountryRow> _countries = const [];
  String _country = 'EG';
  EduTree? _tree;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool countries = true}) async {
    if (countries) {
      final cs = await _api.countries();
      if (!mounted) return;
      if (cs == null) {
        setState(() => _failed = true);
        return;
      }
      _countries = cs;
      if (cs.isNotEmpty && !cs.any((c) => c.code == _country)) _country = cs.first.code;
    }
    final tr = await _api.tree(_country);
    if (!mounted) return;
    setState(() {
      _failed = tr == null && _tree == null;
      if (tr != null) _tree = tr;
    });
  }

  static String _entity(EduKind k) => switch (k) {
        EduKind.stage => 'stages',
        EduKind.grade => 'grades',
        EduKind.subject => 'subjects',
        EduKind.area => 'areas',
      };

  static String _slug(String en) {
    final s = en.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    final tail = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${s.length > 24 ? s.substring(0, 24) : s}_$tail';
  }

  Future<void> _after(EduWrite w, {bool reloadCountries = false}) async {
    if (w.ok) await _load(countries: reloadCountries);
  }

  @override
  void selectCountry(String code) {
    setState(() {
      _country = code;
      _tree = null;
    });
    _load(countries: false);
  }

  @override
  Future<void> addCountry() async {
    final ar = AppConfig.lang == 'ar';
    final r = await _showForm(context,
        title: t('إضافة دولة', 'Add country'),
        fields: [
          _F(t('رمز الدولة (حرفان)', 'Country code (2 letters)'), ltr: true, maxLength: 2),
          _F(t('الاسم بالعربية', 'Name (Arabic)')),
          _F(t('الاسم بالإنجليزية', 'Name (English)'), ltr: true),
        ],
        pick: _Pick(t('نسخ المراحل من دولة', 'Copy the levels from'), {for (final c in _countries) c.code: c.name(ar)}));
    if (r == null) return;
    final code = r.values[0].trim().toUpperCase();
    final w = await _api.addCountry({
      'code': code,
      'name_ar': r.values[1].trim(),
      'name_en': r.values[2].trim(),
      if (r.pick != null) 'copy_from': r.pick,
    }, t('أُضيفت الدولة', 'Country added'));
    if (w.ok) _country = code;
    await _after(w, reloadCountries: true);
  }

  @override
  Future<void> editLabels() async {
    final tr = _tree;
    if (tr == null) return;
    final l1 = tr.country.labels['1'] ?? ('', ''), l2 = tr.country.labels['2'] ?? ('', '');
    final r = await _showForm(context, title: t('أسماء المستويين', 'Level names'), fields: [
      _F(t('المستوى ١ بالعربية', 'Level 1 (Arabic)'), initial: l1.$1),
      _F(t('المستوى ١ بالإنجليزية', 'Level 1 (English)'), initial: l1.$2, ltr: true),
      _F(t('المستوى ٢ بالعربية', 'Level 2 (Arabic)'), initial: l2.$1),
      _F(t('المستوى ٢ بالإنجليزية', 'Level 2 (English)'), initial: l2.$2, ltr: true),
    ]);
    if (r == null) return;
    final v = r.values;
    await _after(await _api.editCountry(_country, {
      'geo_labels': {
        '1': {'ar': v[0].trim(), 'en': v[1].trim()},
        '2': {'ar': v[2].trim(), 'en': v[3].trim()},
      }
    }, t('حُفظت الأسماء', 'Names saved')));
  }

  @override
  Future<void> add(EduKind kind, {EduRow? parent}) async {
    final r = await _showForm(context, title: t('إضافة', 'Add'), fields: [_F(t('الاسم بالعربية', 'Name (Arabic)')), _F(t('الاسم بالإنجليزية', 'Name (English)'), ltr: true)]);
    if (r == null) return;
    final en = r.values[1].trim();
    final body = <String, dynamic>{
      'key': _slug(en),
      'name_ar': r.values[0].trim(),
      'name_en': en,
      if (kind == EduKind.grade) 'stage_id': parent!.id else 'country_code': _country,
      if (kind == EduKind.area && parent != null) 'parent_id': parent.id,
    };
    await _after(await _api.add(_entity(kind), body, t('تمت الإضافة', 'Added')));
  }

  @override
  Future<void> edit(EduKind kind, EduRow row) async {
    final r = await _showForm(context,
        title: t('تعديل الاسم', 'Rename'), fields: [_F(t('الاسم بالعربية', 'Name (Arabic)'), initial: row.nameAr), _F(t('الاسم بالإنجليزية', 'Name (English)'), initial: row.nameEn, ltr: true)]);
    if (r == null) return;
    await _after(await _api.edit(_entity(kind), row.id, {'name_ar': r.values[0].trim(), 'name_en': r.values[1].trim()}, t('حُفظ', 'Saved')));
  }

  @override
  Future<void> toggleActive(EduKind kind, EduRow row) async {
    if (row.active &&
        !await appConfirm(context,
            danger: true, confirmLabel: t('إيقاف', 'Deactivate'), message: t('إيقاف «${row.nameAr}»؟ يختفي من الاختيارات الجديدة.', 'Deactivate "${row.nameEn}"? It disappears from new choices.'))) {
      return;
    }
    await _after(await _api.edit(_entity(kind), row.id, {'active': !row.active}, row.active ? t('أُوقف', 'Deactivated') : t('فُعّل', 'Activated')));
  }

  @override
  Future<void> delete(EduKind kind, EduRow row) async {
    if (!await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف «${row.nameAr}»؟ إن كان مستخدماً يُوقف بدل أن يُحذف.', 'Delete "${row.nameEn}"? If it is in use it is deactivated instead.'))) {
      return;
    }
    final w = await _api.remove(_entity(kind), row.id);
    if (w.ok) {
      showAppNotice(w.deactivated
          ? t('مستخدم (${w.inUse}) فأُوقف بدل الحذف', 'In use (${w.inUse}), so it was deactivated instead of deleted')
          : t('حُذف', 'Deleted'));
    }
    await _after(w);
  }

  @override
  Future<void> move(EduKind kind, EduRow row, int dir) async {
    final tr = _tree;
    if (tr == null) return;
    final List<EduRow> sib = switch (kind) {
      EduKind.stage => tr.stages,
      EduKind.subject => tr.subjects,
      EduKind.grade => tr.stages.firstWhere((s) => s.children.any((g) => g.id == row.id)).children,
      EduKind.area => [for (final a in tr.areas) if (a.parentId == row.parentId) a],
    };
    final ids = [for (final s in sib) s.id];
    final i = ids.indexOf(row.id), j = i + dir;
    if (i < 0 || j < 0 || j >= ids.length) return;
    ids.insert(j, ids.removeAt(i));
    await _after(await _api.reorder(_entity(kind), ids));
  }

  @override
  Future<void> pickGradeSubjects(EduRow grade) async {
    final tr = _tree;
    if (tr == null) return;
    final ar = AppConfig.lang == 'ar';
    final r = await showAppSheet<Set<int>>(context, (ctx) => EduSubjectPicker(title: grade.name(ar), subjects: tr.subjects, selected: grade.subjectIds.toSet(), ar: ar));
    if (r == null) return;
    await _after(await _api.setGradeSubjects(grade.id, r.toList(), t('حُفظت المواد', 'Subjects saved')));
  }

  @override
  Future<void> editTax() async {
    final tr = _tree;
    if (tr == null) return;
    final r = await showAppSheet<EduTaxValues>(context, (ctx) => EduTaxSheet(country: tr.country));
    if (r == null) return;
    await _after(await _api.editCountry(_country, {
      'currency': r.currency,
      'vat_percent': r.vatPercent,
      'prices_include_vat': r.pricesIncludeVat,
    }, t('حُفظت إعدادات الضريبة', 'VAT settings saved')), reloadCountries: true);
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.content,
      title: t('المراحل الدراسية', 'Education levels'),
      subtitle: t('المراحل والصفوف والمواد والمناطق لكل دولة.', 'Stages, grades, subjects and areas for each country.'),
      icon: Icons.school_rounded,
      helpPageId: 'admin.edu_levels',
      onRefresh: _load,
      body: _failed
          ? AppEmpty(
              icon: Icons.cloud_off_rounded,
              title: t('تعذّر التحميل', 'Could not load'),
              actionLabel: t('إعادة المحاولة', 'Retry'),
              onAction: () {
                setState(() => _failed = false);
                _load();
              })
          : AppRefresh(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
                EduLevelsBody(countries: _countries, country: _country, tree: _tree, actions: this),
              ]),
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

class _F {
  const _F(this.label, {this.initial = '', this.ltr = false, this.maxLength});
  final String label;
  final String initial;
  final bool ltr;
  final int? maxLength;
}

class _Pick {
  const _Pick(this.label, this.options);
  final String label;
  final Map<String, String> options;
}

class _FormResult {
  const _FormResult(this.values, this.pick);
  final List<String> values;
  final String? pick;
}

Future<_FormResult?> _showForm(BuildContext context, {required String title, required List<_F> fields, _Pick? pick}) =>
    showAppSheet<_FormResult>(context, (ctx) => _FormSheet(title: title, fields: fields, pick: pick));

class _FormSheet extends StatefulWidget {
  const _FormSheet({required this.title, required this.fields, this.pick});
  final String title;
  final List<_F> fields;
  final _Pick? pick;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final _ctl = [for (final f in widget.fields) TextEditingController(text: f.initial)];
  String? _pick;

  @override
  void dispose() {
    for (final c in _ctl) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctl.every((c) => c.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: AppType.section(context)),
          AppSpace.gapMd,
          for (var i = 0; i < _ctl.length; i++) ...[
            AppField(controller: _ctl[i], label: widget.fields[i].label, ltr: widget.fields[i].ltr, maxLength: widget.fields[i].maxLength, onChanged: (_) => setState(() {})),
            AppSpace.gapSm,
          ],
          if (widget.pick != null) ...[
            Text(widget.pick!.label, style: AppType.label(context)),
            AppSpace.gapXs,
            AppDropdown<String>(
              value: _pick,
              hint: Text(t('بدون', 'None')),
              items: [for (final e in widget.pick!.options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _pick = v),
            ),
            AppSpace.gapSm,
          ],
          Row(children: [
            Expanded(child: AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop())),
            AppSpace.gapSm,
            Expanded(
              child: AppButton.primary(
                label: t('حفظ', 'Save'),
                onPressed: ready ? () => Navigator.of(context).pop(_FormResult([for (final c in _ctl) c.text], _pick)) : null,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The multi-select of subjects for one grade (plain values: the layout harness pumps it).
class EduSubjectPicker extends StatefulWidget {
  const EduSubjectPicker({super.key, required this.title, required this.subjects, required this.selected, required this.ar});
  final String title;
  final List<EduRow> subjects;
  final Set<int> selected;
  final bool ar;

  @override
  State<EduSubjectPicker> createState() => _EduSubjectPickerState();
}

class _EduSubjectPickerState extends State<EduSubjectPicker> {
  late final Set<int> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: AppType.section(context)),
        AppSpace.gapSm,
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final s in widget.subjects)
              CheckboxListTile(
                value: _sel.contains(s.id),
                title: Text(s.name(widget.ar), style: AppType.row(context)),
                onChanged: (v) => setState(() => v == true ? _sel.add(s.id) : _sel.remove(s.id)),
              ),
          ]),
        ),
        AppSpace.gapSm,
        Row(children: [
          Expanded(child: AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop())),
          AppSpace.gapSm,
          Expanded(child: AppButton.primary(label: t('حفظ', 'Save'), onPressed: () => Navigator.of(context).pop(_sel))),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Money: currency + VAT (learning hub phase 5, D-1336)
// ═════════════════════════════════════════════════════════════════════════════

/// "EGP · VAT 14 % · prices include VAT" with an Edit button (plain values).
class EduTaxCard extends StatelessWidget {
  const EduTaxCard({super.key, required this.country, required this.onEdit});
  final EduCountryRow country;
  final VoidCallback onEdit;

  static String pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cur = country.currency ?? t('بلا عملة', 'No currency');
    final vat = country.vatPercent <= 0
        ? t('بلا ضريبة قيمة مضافة', 'No VAT')
        : '${t('ضريبة', 'VAT')} ${pct(country.vatPercent)}% · ${country.pricesIncludeVat ? t('الأسعار شاملة الضريبة', 'prices include VAT') : t('الضريبة تُضاف على السعر', 'VAT added on top')}';
    return AppSectionCard(
      title: t('العملة والضريبة', 'Currency & VAT'),
      subtitle: t('يستخدمها المتجر لحساب السعر النهائي في هذه الدولة.', 'The store uses them to work out final prices in this country.'),
      actions: [AppButton.tonal(label: t('تعديل', 'Edit'), icon: Icons.edit_rounded, size: AppButtonSize.sm, onPressed: onEdit)],
      child: Text('$cur · $vat', style: AppType.row(context)),
    );
  }
}

/// What [EduTaxSheet] pops.
class EduTaxValues {
  const EduTaxValues(this.currency, this.vatPercent, this.pricesIncludeVat);
  final String? currency;
  final double vatPercent;
  final bool pricesIncludeVat;
}

class EduTaxSheet extends StatefulWidget {
  const EduTaxSheet({super.key, required this.country});
  final EduCountryRow country;

  @override
  State<EduTaxSheet> createState() => _EduTaxSheetState();
}

class _EduTaxSheetState extends State<EduTaxSheet> {
  late final _cur = TextEditingController(text: widget.country.currency ?? '');
  late final _vat = TextEditingController(text: EduTaxCard.pct(widget.country.vatPercent));
  late bool _incl = widget.country.pricesIncludeVat;

  @override
  void dispose() {
    _cur.dispose();
    _vat.dispose();
    super.dispose();
  }

  double? get _vatValue {
    final v = double.tryParse(_vat.text.trim().replaceAll(',', '.'));
    return v == null || v < 0 || v > 100 ? null : v;
  }

  bool get _curOk => _cur.text.trim().isEmpty || RegExp(r'^[A-Za-z]{3}$').hasMatch(_cur.text.trim());

  @override
  Widget build(BuildContext context) {
    final ready = _vatValue != null && _curOk;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('العملة والضريبة', 'Currency & VAT'), style: AppType.section(context)),
          AppSpace.gapMd,
          AppField(
            controller: _cur,
            label: t('العملة (3 أحرف، مثل EGP)', 'Currency (3 letters, e.g. EGP)'),
            ltr: true,
            maxLength: 3,
            textCapitalization: TextCapitalization.characters,
            errorText: _curOk ? null : t('3 أحرف لاتينية', '3 Latin letters'),
            onChanged: (_) => setState(() {}),
          ),
          AppSpace.gapSm,
          AppField(
            controller: _vat,
            label: t('نسبة ضريبة القيمة المضافة ٪', 'VAT rate %'),
            ltr: true,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            errorText: _vatValue == null ? t('من 0 إلى 100', 'From 0 to 100') : null,
            onChanged: (_) => setState(() {}),
          ),
          AppSwitchTile(
            title: t('الأسعار شاملة الضريبة', 'Prices include VAT'),
            subtitle: _incl
                ? t('السعر المكتوب هو ما يدفعه الطالب.', 'The price entered is what the student pays.')
                : t('تُضاف الضريبة فوق السعر المكتوب.', 'VAT is added on top of the price entered.'),
            value: _incl,
            onChanged: (v) => setState(() => _incl = v),
          ),
          AppSpace.gapMd,
          Row(children: [
            Expanded(child: AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop())),
            AppSpace.gapSm,
            Expanded(
              child: AppButton.primary(
                label: t('حفظ', 'Save'),
                onPressed: ready
                    ? () => Navigator.of(context).pop(EduTaxValues(_cur.text.trim().isEmpty ? null : _cur.text.trim().toUpperCase(), _vatValue!, _incl))
                    : null,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
