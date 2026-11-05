// The editor of ONE help entry (title, summary, sections with items, tour), both languages. [HelpDraft] holds the
// text controllers and validates exactly like the server's `clean_page` (both languages required, unique lowercase
// section keys, a tour target on every step, the size limits); [HelpEntryForm] is the form over it.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../shared/help/help_models.dart';

const helpMaxSections = 40, helpMaxItems = 60, helpMaxTour = 40, helpMaxText = 6000;
final _keyRe = RegExp(r'^[a-z0-9_]+$');

/// A bilingual text field pair.
class BiCtl {
  BiCtl([HelpText? v])
      : ar = TextEditingController(text: v?.ar ?? ''),
        en = TextEditingController(text: v?.en ?? '');
  final TextEditingController ar, en;

  HelpText get value => HelpText(ar.text.trim(), en.text.trim());

  void dispose() {
    ar.dispose();
    en.dispose();
  }
}

class ItemDraft {
  ItemDraft([HelpItem? i])
      : label = BiCtl(i?.label),
        text = BiCtl(i?.text);
  final BiCtl label, text;
  void dispose() {
    label.dispose();
    text.dispose();
  }
}

class SectionDraft {
  SectionDraft([HelpSection? s])
      : key = TextEditingController(text: s?.key ?? ''),
        title = BiCtl(s?.title),
        body = BiCtl(s?.body),
        items = [for (final i in s?.items ?? const <HelpItem>[]) ItemDraft(i)];
  final TextEditingController key;
  final BiCtl title, body;
  final List<ItemDraft> items;
  void dispose() {
    key.dispose();
    title.dispose();
    body.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

class TourDraft {
  TourDraft([HelpTourStep? s])
      : target = TextEditingController(text: s?.target ?? ''),
        text = BiCtl(s?.text);
  final TextEditingController target;
  final BiCtl text;
  void dispose() {
    target.dispose();
    text.dispose();
  }
}

class HelpDraft {
  HelpDraft(HelpEntry e)
      : pageId = e.pageId,
        role = e.role,
        title = BiCtl(e.title),
        summary = BiCtl(e.summary),
        sections = [for (final s in e.sections) SectionDraft(s)],
        tour = [for (final s in e.tour) TourDraft(s)];

  final String pageId, role;
  final BiCtl title, summary;
  final List<SectionDraft> sections;
  final List<TourDraft> tour;

  HelpEntry toEntry() => HelpEntry(
        pageId: pageId,
        role: role,
        title: title.value,
        summary: summary.value,
        sections: [
          for (final s in sections)
            HelpSection(
              key: s.key.text.trim(),
              title: s.title.value,
              body: s.body.value,
              items: [for (final i in s.items) HelpItem(label: i.label.value, text: i.text.value)],
            ),
        ],
        tour: [for (final s in tour) HelpTourStep(target: s.target.text.trim(), text: s.text.value)],
      );

  /// The first problem the server would reject, as text in the app language; null = valid.
  String? validate() {
    final ar = AppConfig.lang == 'ar';
    String both(String where) => ar ? 'العربية والإنجليزية مطلوبتان: $where' : 'Both Arabic and English are required: $where';
    String? bi(BiCtl c, String where, {bool required = true}) {
      final v = c.value;
      if (required && (v.ar.isEmpty || v.en.isEmpty)) return both(where);
      if (v.ar.length > helpMaxText || v.en.length > helpMaxText) {
        return ar ? 'النص طويل جداً: $where' : 'Text too long: $where';
      }
      return null;
    }

    final top = bi(title, ar ? 'العنوان' : 'Title') ?? bi(summary, ar ? 'الملخص' : 'Summary');
    if (top != null) return top;
    if (sections.length > helpMaxSections || tour.length > helpMaxTour) {
      return ar ? 'أقسام أو خطوات جولة كثيرة' : 'Too many sections or tour steps';
    }
    final seen = <String>{};
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final n = i + 1;
      final key = s.key.text.trim();
      if (!_keyRe.hasMatch(key) || !seen.add(key)) {
        return ar ? 'القسم $n: مفتاح فريد بحروف إنجليزية صغيرة وأرقام و _' : 'Section $n: key must be unique lowercase letters / digits / _';
      }
      final e = bi(s.title, ar ? 'عنوان القسم $n' : 'Section $n title') ?? bi(s.body, ar ? 'نص القسم $n' : 'Section $n body', required: false);
      if (e != null) return e;
      if (s.items.length > helpMaxItems) return ar ? 'عناصر كثيرة في القسم $n' : 'Too many items in section $n';
      for (var j = 0; j < s.items.length; j++) {
        final it = s.items[j];
        final e2 = bi(it.label, ar ? 'اسم العنصر ${j + 1} في القسم $n' : 'Section $n item ${j + 1} label') ??
            bi(it.text, ar ? 'شرح العنصر ${j + 1} في القسم $n' : 'Section $n item ${j + 1} text');
        if (e2 != null) return e2;
      }
    }
    for (var i = 0; i < tour.length; i++) {
      final s = tour[i];
      if (s.target.text.trim().isEmpty) return ar ? 'خطوة الجولة ${i + 1}: الهدف مطلوب' : 'Tour step ${i + 1}: a target is required';
      final e = bi(s.text, ar ? 'نص خطوة الجولة ${i + 1}' : 'Tour step ${i + 1} text');
      if (e != null) return e;
    }
    return null;
  }

  void dispose() {
    title.dispose();
    summary.dispose();
    for (final s in sections) {
      s.dispose();
    }
    for (final s in tour) {
      s.dispose();
    }
  }
}

/// The form over a [HelpDraft]; [onChanged] fires after a list changes shape (add / remove / move).
class HelpEntryForm extends StatefulWidget {
  const HelpEntryForm({super.key, required this.draft, this.onChanged});
  final HelpDraft draft;
  final VoidCallback? onChanged;

  @override
  State<HelpEntryForm> createState() => _HelpEntryFormState();
}

class _HelpEntryFormState extends State<HelpEntryForm> {
  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  void _touch(VoidCallback f) {
    setState(f);
    widget.onChanged?.call();
  }

  Widget _bi(BiCtl c, String label, {int lines = 1}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(controller: c.ar, label: '$label · العربية', maxLines: lines),
        AppSpace.gapXs,
        AppField(controller: c.en, label: '$label · English', maxLines: lines, ltr: true),
      ]);

  Widget _head(String text, {Widget? trailing}) {
    final c = context.colors;
    return Row(children: [
      Expanded(child: Semantics(header: true, child: Text(text, style: appText(16, w: FontWeight.w700, c: c.textDark)))),
      ?trailing,
    ]);
  }

  Widget _box(List<Widget> children) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _icon(IconData i, String tip, VoidCallback? f) => IconButton(
        tooltip: tip,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        onPressed: f,
        icon: Icon(i, size: 20),
      );

  Widget _add(String label, VoidCallback f) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
          onPressed: f,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bi(d.title, _t('العنوان', 'Title')),
      AppSpace.gapSm,
      _bi(d.summary, _t('الملخص', 'Summary'), lines: 3),
      AppSpace.gapMd,
      _head(_t('الأقسام', 'Sections')),
      AppSpace.gapXs,
      for (var si = 0; si < d.sections.length; si++) _section(d, si),
      _add(_t('إضافة قسم', 'Add section'), () => _touch(() => d.sections.add(SectionDraft()))),
      AppSpace.gapMd,
      _head(_t('الجولة التعريفية', 'Guided tour')),
      AppSpace.gapXs,
      for (var ti = 0; ti < d.tour.length; ti++)
        _box([
          Row(children: [
            Expanded(child: Text('${_t('الخطوة', 'Step')} ${ti + 1}', style: appText(13, w: FontWeight.w700, c: context.colors.textMedium))),
            _icon(Icons.arrow_upward_rounded, _t('أعلى', 'Move up'), ti == 0 ? null : () => _touch(() => d.tour.insert(ti - 1, d.tour.removeAt(ti)))),
            _icon(Icons.arrow_downward_rounded, _t('أسفل', 'Move down'),
                ti == d.tour.length - 1 ? null : () => _touch(() => d.tour.insert(ti + 1, d.tour.removeAt(ti)))),
            _icon(Icons.delete_outline_rounded, _t('حذف', 'Delete'), () => _touch(() => d.tour.removeAt(ti).dispose())),
          ]),
          AppField(controller: d.tour[ti].target, label: _t('الهدف (معرّف العنصر)', 'Target (widget id)'), ltr: true),
          AppSpace.gapXs,
          _bi(d.tour[ti].text, _t('النص', 'Text'), lines: 2),
        ]),
      _add(_t('إضافة خطوة', 'Add tour step'), () => _touch(() => d.tour.add(TourDraft()))),
    ]);
  }

  Widget _section(HelpDraft d, int si) {
    final s = d.sections[si];
    return _box([
      Row(children: [
        Expanded(child: Text('${_t('القسم', 'Section')} ${si + 1}', style: appText(13, w: FontWeight.w700, c: context.colors.textMedium))),
        _icon(Icons.arrow_upward_rounded, _t('أعلى', 'Move up'), si == 0 ? null : () => _touch(() => d.sections.insert(si - 1, d.sections.removeAt(si)))),
        _icon(Icons.arrow_downward_rounded, _t('أسفل', 'Move down'),
            si == d.sections.length - 1 ? null : () => _touch(() => d.sections.insert(si + 1, d.sections.removeAt(si)))),
        _icon(Icons.delete_outline_rounded, _t('حذف', 'Delete'), () => _touch(() => d.sections.removeAt(si).dispose())),
      ]),
      AppField(controller: s.key, label: _t('المفتاح (a-z و 0-9 و _)', 'Key (a-z, 0-9, _)'), ltr: true),
      AppSpace.gapXs,
      _bi(s.title, _t('العنوان', 'Title')),
      AppSpace.gapXs,
      _bi(s.body, _t('الوصف (اختياري)', 'Body (optional)'), lines: 2),
      AppSpace.gapSm,
      for (var ii = 0; ii < s.items.length; ii++)
        Container(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.xs),
          decoration: BoxDecoration(color: context.colors.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('${_t('عنصر', 'Item')} ${ii + 1}', style: appText(12.5, w: FontWeight.w700, c: context.colors.textMedium))),
              _icon(Icons.arrow_upward_rounded, _t('أعلى', 'Move up'), ii == 0 ? null : () => _touch(() => s.items.insert(ii - 1, s.items.removeAt(ii)))),
              _icon(Icons.arrow_downward_rounded, _t('أسفل', 'Move down'),
                  ii == s.items.length - 1 ? null : () => _touch(() => s.items.insert(ii + 1, s.items.removeAt(ii)))),
              _icon(Icons.delete_outline_rounded, _t('حذف', 'Delete'), () => _touch(() => s.items.removeAt(ii).dispose())),
            ]),
            _bi(s.items[ii].label, _t('الاسم', 'Label')),
            AppSpace.gapXs,
            _bi(s.items[ii].text, _t('الشرح', 'Text'), lines: 2),
          ]),
        ),
      _add(_t('إضافة عنصر', 'Add item'), () => _touch(() => s.items.add(ItemDraft()))),
    ]);
  }
}
