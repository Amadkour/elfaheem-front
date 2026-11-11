// Exam Hub, the identifiers on each student's copy (D-354). The teacher picks up to four identifiers to print, one of them
// is what a scanned sheet is matched on (`Exam.identifier`), a new one is created in place (asked of the students, typed in a
// roster grid, or imported from Excel), and live coverage says who is missing before the exam is printed. It saves itself:
// the owner of the step only hears `onValid`.
//
// Plain-value widgets (the layout harness pumps them): IdentifierPlanBody · IdentifierPaperPreview · RosterGrid ·
// ImportPreviewCard · NewIdentifierForm.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show asInt, t;
import '../../../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../../exam_paper_bands.dart' show kPaperMaxIdentifiers;
import '../../paper/exam_setup.dart';
import 'deliver_logic.dart';

void _notice(String m, {bool error = false}) => showAppNotice(m, error: error);

/// How a new identifier gets its values.
enum IdFillWay { ask, hand, excel }

class IdentifierPlanStep extends StatefulWidget {
  const IdentifierPlanStep({super.key, required this.examId, required this.courseId, required this.onValid, this.api, this.setupApi});

  final int examId;
  final int? courseId;
  final ValueChanged<bool> onValid;

  /// Tests pass fakes.
  final ExamDeliverApi? api;
  final ExamSetupApi? setupApi;

  @override
  State<IdentifierPlanStep> createState() => _IdentifierPlanStepState();
}

class _IdentifierPlanStepState extends State<IdentifierPlanStep> {
  late final ExamDeliverApi _api = widget.api ?? ExamDeliverApi();
  late final ExamSetupApi _sApi = widget.setupApi ?? ExamSetupApi();

  bool _loading = true, _saving = false;
  String? _error;
  ExamSetup? _setup;
  List<IdentifierOption> _options = const [];
  final Map<String, IdCoverage> _coverage = {};
  List<PrintedIdSpec> _printed = const [];
  IdentifierChoice? _matching;
  IdentifierOption? _recommended;
  bool _acting = false;

  bool get _off => AppConfig.disableList.contains(kExamIdentifiersFeatureKey);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// One action at a time: each of these waits on the server, and a second tap would send the request or open the sheet twice.
  Future<void> _once(Future<void> Function() action) async {
    if (_acting) return;
    _acting = true;
    try {
      await action();
    } finally {
      _acting = false;
    }
  }

  void _valid(bool v) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onValid(v);
      });

  Future<void> _load() async {
    if (_off || widget.courseId == null) {
      setState(() => _loading = false);
      _valid(true);
      return;
    }
    final results = await Future.wait([_sApi.setup(widget.examId), _sApi.identityFields()]);
    final columns = await _sApi.dataLabColumns(widget.courseId!);
    if (!mounted) return;
    if (!results[0].ok) {
      setState(() {
        _loading = false;
        _error = deliverErrorText(results[0]);
      });
      return _valid(false);
    }
    final setup = ExamSetup.fromJson(results[0].map);
    final fields = [for (final f in (results[1].map['items'] as List?) ?? const []) if (f is Map) IdentityFieldDef.fromJson(Map<String, dynamic>.from(f))];
    final options = identifierOptions(fields, dataLabColumns: columns, dataLab: columns.isNotEmpty);
    final saved = printedIdsOfSetup(results[0].map);
    // choosing for the teacher compares every source; once chosen, only what is on the paper is read
    await _readCoverage(options, only: setup.identifier == null ? null : {setup.identifier!.id, for (final p in saved) p.id});
    if (!mounted) return;
    final rec = recommendedMatching(options, _coverage, current: setup.identifier);
    setState(() {
      _setup = setup;
      _options = options;
      _recommended = rec;
      _matching = setup.identifier ?? rec?.choice;
      final match = _specOf(_matching);
      _printed = match == null ? saved : printedWithMatching(saved, match);
      _loading = false;
    });
    // nothing chosen yet: the recommendation is saved so a teacher who only presses Next still gets a working exam
    if (setup.identifier == null || saved.isEmpty) {
      await _save();
    } else {
      _valid(_matching != null);
    }
  }

  PrintedIdSpec? _specOf(IdentifierChoice? c) {
    if (c == null) return null;
    for (final o in _options) {
      if (o.choice == c) return PrintedIdSpec.of(o);
    }
    for (final p in _printed) {
      if (p.choice == c) return p;
    }
    return null;
  }

  Future<void> _readCoverage(List<IdentifierOption> options, {Set<String>? only}) async {
    final wanted = [for (final o in options) if (o.choice.source != 'name' && (only == null || only.contains(o.choice.id))) o];
    final answers = await Future.wait([for (final o in wanted) _api.values(widget.examId, o.choice.source, o.choice.key)]);
    for (var i = 0; i < wanted.length; i++) {
      _coverage[wanted[i].choice.id] = answers[i].ok ? IdCoverage.fromJson(answers[i].map) : const IdCoverage(unreadable: true);
    }
    final total = _coverage.values.fold(0, (m, c) => c.total > m ? c.total : m);
    _coverage['name'] = IdCoverage(filled: total, total: total);
  }

  /// The coverage of something just put on the paper.
  void _readIfNew(IdentifierChoice c) {
    if (c.source != 'name' && !_coverage.containsKey(c.id)) _refreshOne(c);
  }

  Future<void> _refreshOne(IdentifierChoice c) async {
    final r = await _api.values(widget.examId, c.source, c.key);
    if (!mounted) return;
    setState(() => _coverage[c.id] = r.ok ? IdCoverage.fromJson(r.map) : const IdCoverage(unreadable: true));
  }

  Future<void> _save() async {
    final match = _specOf(_matching);
    if (match == null) return _valid(false);
    setState(() => _saving = true);
    final body = {
      if (_setup?.identifier != _matching) 'identifier': _matching!.toJson(),
      'print_identifiers': [for (final p in _printed) p.toJson()],
    };
    final r = await _sApi.putSetup(widget.examId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!r.ok) {
      showAppNotice(deliverErrorText(r), error: true);
      return _valid(false);
    }
    final s = await _sApi.setup(widget.examId);
    if (mounted && s.ok) setState(() => _setup = ExamSetup.fromJson(s.map));
    _valid(true);
  }

  void _toggle(IdentifierOption o) {
    final spec = PrintedIdSpec.of(o);
    final selected = _printed.any((p) => p.id == spec.id);
    if (selected && _matching == o.choice) {
      return _notice(t('هذا هو معرّف المطابقة. اختر معرّفًا آخر للمطابقة أولًا.', 'This one is used for matching. Pick another for matching first.'));
    }
    if (!selected && _printed.length >= kPaperMaxIdentifiers) {
      return _notice(t('أربعة معرّفات على الأكثر على الورقة.', 'At most four identifiers on the paper.'));
    }
    setState(() => _printed = selected ? [for (final p in _printed) if (p.id != spec.id) p] : [..._printed, spec]);
    if (!selected) _readIfNew(o.choice);
    _save();
  }

  void _match(IdentifierOption o) {
    final spec = PrintedIdSpec.of(o);
    setState(() {
      _matching = o.choice;
      _printed = printedWithMatching(_printed, spec);
    });
    _readIfNew(o.choice);
    _save();
  }

  Future<void> _newIdentifier() async {
    final picked = await showAppSheet<(String, IdFillWay)>(context, (ctx) => NewIdentifierForm(onDone: (label, way) => Navigator.of(ctx).pop((label, way))));
    if (picked == null || !mounted) return;
    final (label, way) = picked;
    final r = await _api.createCustom(widget.examId, label, label);
    if (!mounted) return;
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    final option = IdentifierOption(
        choice: IdentifierChoice('datalab', '${r.map['key']}'), labelAr: '${r.map['label_ar'] ?? label}', labelEn: '${r.map['label_en'] ?? label}', kind: 'text', collectable: false, group: 'datalab');
    final spec = PrintedIdSpec.of(option);
    setState(() {
      _options = [..._options, option];
      if (_printed.length >= kPaperMaxIdentifiers) _printed = _printed.sublist(0, kPaperMaxIdentifiers - 1);
      _printed = [..._printed, spec];
      if (way == IdFillWay.ask) _matching = option.choice; // only the matching identifier can be collected
    });
    await _save();
    await _refreshOne(option.choice);
    if (!mounted) return;
    switch (way) {
      case IdFillWay.ask:
        await _askStudents(option);
      case IdFillWay.hand:
        await _editRoster(option);
      case IdFillWay.excel:
        await _openImport(option);
    }
  }

  Future<void> _askStudents(IdentifierOption o) async {
    final r = await _sApi.requestIdentifiers(widget.examId);
    if (!mounted) return;
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    showAppNotice(t('أرسلنا الطلب إلى الطلاب، وستظهر إجاباتهم هنا.', 'The students have been asked. Their answers will show up here.'));
    await _refreshOne(o.choice);
  }

  Future<void> _editRoster(IdentifierOption o) async {
    final r = await _api.values(widget.examId, o.choice.source, o.choice.key);
    if (!mounted) return;
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    final current = IdCoverage.fromJson(r.map);
    if (current.masked) return _notice(t('قيم هذا المعرّف لا تُعدَّل من هنا.', 'The values of this identifier cannot be edited here.'), error: true);
    final saved = await showAppSheet<bool>(context, (ctx) => _RosterSheet(examId: widget.examId, option: o, api: _api, rows: current.items));
    if (saved == true && mounted) await _refreshOne(o.choice);
  }

  Future<void> _openImport(IdentifierOption o) async {
    final done = await showAppSheet<bool>(context, (ctx) => _ImportSheet(examId: widget.examId, option: o, api: _api));
    if (done == true && mounted) await _refreshOne(o.choice);
  }

  @override
  Widget build(BuildContext context) {
    if (_off) return const SizedBox.shrink();
    if (widget.courseId == null) {
      return AppBanner(
          icon: Icons.link_off_rounded,
          text: t('هذا الاختبار غير مرتبط بمقرر، فلا يوجد طلاب لنطبع أسماءهم. يمكنك المتابعة والطباعة بنسخ فارغة.',
              'This exam is not linked to a course, so there are no students to print names for. You can continue and print blank copies.'));
    }
    if (_loading) return const AppListSkeleton(items: 4, withAvatar: false);
    if (_error != null) return AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger);
    return IdentifierPlanBody(
      options: _options,
      printed: _printed,
      matching: _matching,
      coverage: _coverage,
      recommended: _recommended?.choice,
      saving: _saving,
      onToggle: _toggle,
      onMatch: _match,
      onNew: () => _once(_newIdentifier),
      onHand: (o) => _once(() => _editRoster(o)),
      onExcel: (o) => _once(() => _openImport(o)),
      onAsk: (o) => _once(() => _askStudents(o)),
    );
  }
}

/// What sits on the paper, with sample values from the first student who has one. The server masks most sources, and a mask
/// is not what prints: those lines draw a sample of the paper's real shape instead.
List<(String, String)> plannedPaperLines(List<PrintedIdSpec> printed, Map<String, IdCoverage> coverage) => [
      for (final p in printed)
        if (p.source != 'name')
          (
            p.label,
            (() {
              final cov = coverage[p.id];
              if (cov != null && cov.masked) return cov.filled > 0 ? maskedPaperSample(p.source) : '';
              final row = cov == null ? const <IdValueRow>[] : cov.items.where((x) => x.filled).toList();
              return row.isEmpty ? '' : printedValuePreview(p.source, row.first.value);
            })(),
          ),
    ];

class IdentifierPlanBody extends StatelessWidget {
  const IdentifierPlanBody({
    super.key,
    required this.options,
    required this.printed,
    required this.matching,
    required this.coverage,
    required this.onToggle,
    required this.onMatch,
    required this.onNew,
    required this.onHand,
    required this.onExcel,
    required this.onAsk,
    this.recommended,
    this.saving = false,
  });

  final List<IdentifierOption> options;
  final List<PrintedIdSpec> printed;
  final IdentifierChoice? matching;
  final IdentifierChoice? recommended;
  final Map<String, IdCoverage> coverage;
  final bool saving;
  final ValueChanged<IdentifierOption> onToggle, onMatch, onHand, onExcel, onAsk;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = {for (final p in printed) p.id};
    final on = [for (final p in printed) for (final o in options) if (o.choice.id == p.id) o];
    final off = [for (final o in options) if (!selected.contains(o.choice.id)) o];
    bool fillable(IdentifierOption o) => o.choice.source == 'datalab' && o.choice.key != '__identifier';
    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('ماذا يُطبع على ورقة كل طالب؟', 'What is printed on each student\'s copy?'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(t('اختر حتى أربعة. واحد منها هو الذي نطابق به الورقة الممسوحة مع صاحبها، لذا يجب أن يختلف من طالب إلى آخر.',
          'Pick up to four. One of them is how a scanned sheet is matched to its owner, so it must differ from student to student.'), style: AppType.meta(context).copyWith(height: 1.45)),
      const SizedBox(height: AppSpace.sm),
      for (final o in on)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: IdentifierSelectedTile(
            option: o,
            matching: o.choice == matching,
            recommended: o.choice == recommended,
            coverage: coverage[o.choice.id],
            onToggle: () => onToggle(o),
            onMatch: () => onMatch(o),
            onHand: fillable(o) && coverage[o.choice.id]?.masked != true ? () => onHand(o) : null,
            onExcel: fillable(o) ? () => onExcel(o) : null,
            onAsk: o.choice == matching && (o.collectable || fillable(o)) ? () => onAsk(o) : null,
          ),
        ),
      if (off.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('أضف إلى الورقة', 'Add to the paper'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final o in off) AppChoiceChip(label: _chipLabel(o), selected: false, onTap: () => onToggle(o)),
        ]),
      ],
      const SizedBox(height: AppSpace.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.tonal(key: const ValueKey('ident.new'), label: t('معرّف جديد', 'New identifier'), icon: Icons.add_rounded, onPressed: onNew),
      ),
      if (saving) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(t('جارٍ الحفظ ...', 'Saving ...'), style: AppType.meta(context).copyWith(color: c.textLight))),
    ]);
    final preview = IdentifierPaperPreview(lines: plannedPaperLines(printed, coverage));
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 720) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: list),
          const SizedBox(width: AppSpace.lg),
          Expanded(flex: 2, child: preview),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, const SizedBox(height: AppSpace.md), list]);
    });
  }

  String _chipLabel(IdentifierOption o) {
    final cov = coverage[o.choice.id];
    if (cov == null || cov.unreadable || cov.total == 0 || o.choice.source == 'name') return o.label;
    return '${o.label} · ${cov.filled}/${cov.total}';
  }
}

class IdentifierSelectedTile extends StatelessWidget {
  const IdentifierSelectedTile(
      {super.key, required this.option, required this.matching, required this.recommended, required this.coverage, required this.onToggle, required this.onMatch, this.onHand, this.onExcel, this.onAsk});
  final IdentifierOption option;
  final bool matching, recommended;
  final IdCoverage? coverage;
  final VoidCallback onToggle, onMatch;
  final VoidCallback? onHand, onExcel, onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cov = coverage;
    final isName = option.choice.source == 'name';
    final missing = cov == null || cov.unreadable || isName ? 0 : cov.missingCount;
    final tone = cov == null || cov.unreadable || isName ? c.textLight : (missing == 0 ? c.success : c.warning);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(matching ? Icons.verified_rounded : Icons.badge_outlined, size: AppIconSize.lg, color: matching ? c.primary : c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(option.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: 2),
              Text(
                  matching
                      ? t('نطابق به الورقة مع صاحبها', 'Sheets are matched on this')
                      : (recommended ? t('الأنسب للمطابقة', 'Best for matching') : t('يُطبع فقط', 'Printed only')),
                  style: AppType.meta(context).copyWith(color: matching ? appInk(context, c.primary) : c.textLight)),
              if (!matching)
                InkWell(
                  key: ValueKey('ident.match.${option.choice.id}'),
                  onTap: onMatch,
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs), child: Text(t('استخدمه للمطابقة', 'Match on this'), style: AppType.meta(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w600))),
                ),
            ]),
          ),
          IconButton(icon: const Icon(Icons.close_rounded, size: 18), tooltip: t('إزالة', 'Remove'), onPressed: onToggle),
        ]),
        if (cov != null && !isName) ...[
          const SizedBox(height: AppSpace.xs),
          if (cov.unreadable)
            Text(t('لا نستطيع عرض التغطية بصلاحياتك الحالية.', 'Coverage is not available with your permissions.'), style: AppType.meta(context).copyWith(color: c.textLight))
          else ...[
            Row(children: [
              Expanded(child: AppProgressBar(value: cov.filled.toDouble(), max: cov.total == 0 ? 1 : cov.total.toDouble(), color: tone, height: 6)),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text(coverageText(cov.filled, cov.total), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: tone, fontWeight: FontWeight.w600))),
            ]),
            if (missing > 0 && cov.missingNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(t('ينقص: ${namesText(cov.missingNames)}', 'Missing: ${namesText(cov.missingNames)}'), style: AppType.meta(context).copyWith(height: 1.4)),
              ),
          ],
        ],
        if (missing > 0 && (onHand != null || onExcel != null || onAsk != null)) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            if (onAsk != null) AppButton.tonal(size: AppButtonSize.sm, label: t('اطلب من الطلاب', 'Ask the students'), icon: Icons.campaign_rounded, onPressed: onAsk),
            if (onHand != null) AppButton.ghost(size: AppButtonSize.sm, label: t('إدخال يدوي', 'Enter by hand'), icon: Icons.edit_note_rounded, onPressed: onHand),
            if (onExcel != null) AppButton.ghost(size: AppButtonSize.sm, label: t('من Excel', 'From Excel'), icon: Icons.table_chart_rounded, onPressed: onExcel),
          ]),
        ],
      ]),
    );
  }
}

/// A tiny drawing of the student box as it will print.
class IdentifierPaperPreview extends StatelessWidget {
  const IdentifierPaperPreview({super.key, required this.lines, this.name});
  final List<(String, String)> lines;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 6),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label: ', style: AppType.meta(context).copyWith(color: PaperInk.muted)),
            TextSpan(text: value.isEmpty ? '________' : value, style: AppType.meta(context).copyWith(color: PaperInk.text, fontWeight: FontWeight.w600)),
          ]), maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    final cells = <Widget>[cell(t('اسم الطالب', 'Student name'), name ?? t('أحمد محمود', 'Ahmed Mahmoud')), for (final (l, v) in lines) cell(l, v)];
    final rows = <TableRow>[];
    for (var i = 0; i < cells.length; i += 2) {
      rows.add(TableRow(children: [cells[i], i + 1 < cells.length ? cells[i + 1] : const SizedBox.shrink()]));
    }
    Widget bar(double end, double h) => Container(height: h, margin: EdgeInsetsDirectional.only(end: end), decoration: BoxDecoration(color: PaperInk.placeholder, borderRadius: BorderRadius.circular(3)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('كما سيظهر على الورقة', 'How it will look on the paper'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xs),
      Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: PaperInk.sheet, borderRadius: BorderRadius.circular(AppRadius.chip), boxShadow: AppShadow.card(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bar(90, 6),
          const SizedBox(height: AppSpace.xs),
          Table(border: TableBorder.all(color: PaperInk.rule, width: .7), columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)}, children: rows),
          const SizedBox(height: AppSpace.xs),
          bar(0, 5),
          const SizedBox(height: 5),
          bar(40, 5),
        ]),
      ),
      const SizedBox(height: AppSpace.xxs),
      Text(t('الرقم القومي والهاتف والبريد يظهر منها آخر 4 خانات فقط.', 'National ID, phone and email show their last 4 characters only.'), style: AppType.meta(context).copyWith(color: c.textLight)),
    ]);
  }
}

/// Naming a new identifier and choosing how it gets its values.
class NewIdentifierForm extends StatefulWidget {
  const NewIdentifierForm({super.key, required this.onDone});
  final void Function(String label, IdFillWay way) onDone;

  @override
  State<NewIdentifierForm> createState() => _NewIdentifierFormState();
}

class _NewIdentifierFormState extends State<NewIdentifierForm> {
  final _label = TextEditingController();
  IdFillWay _way = IdFillWay.hand;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget way(IdFillWay w, IconData icon, String title, String body) {
      final on = _way == w;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: InkWell(
          key: ValueKey('ident.way.${w.name}'),
          borderRadius: AppRadius.cardAll,
          onTap: () => setState(() => _way = w),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
                borderRadius: AppRadius.cardAll, border: Border.all(color: on ? c.primary : c.divider, width: on ? 1.5 : 1), color: on ? c.primary.withValues(alpha: .06) : null),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: on ? c.primary : c.textMedium, size: 20),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.bodyStrong(context)),
                  const SizedBox(height: 2),
                  Text(body, style: AppType.meta(context).copyWith(height: 1.4)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    return AppSheetContent(title: t('معرّف جديد', 'New identifier'), children: [
      AppField(controller: _label, label: t('الاسم الظاهر على الورقة', 'Name shown on the paper'), hint: t('مثال: رقم الجلوس', 'For example: Seat number'), onChanged: (_) => setState(() {})),
      const SizedBox(height: AppSpace.md),
      way(IdFillWay.ask, Icons.campaign_rounded, t('اطلب من الطلاب', 'Ask the students'),
          t('يصل الطلاب طلب داخل التطبيق. لا يُجمع من الطلاب إلا معرّف المطابقة، لذلك سيصبح هذا هو معرّف المطابقة.',
              'Students get a request in the app. Only the matching identifier can be collected, so this one becomes the matching identifier.')),
      way(IdFillWay.hand, Icons.edit_note_rounded, t('أدخله بيدك', 'Enter it by hand'), t('قائمة سريعة بأسماء الطلاب.', 'A fast list of the students.')),
      way(IdFillWay.excel, Icons.table_chart_rounded, t('استورد من Excel', 'Import from Excel'), t('نزّل القالب، املأه، ثم ارفعه.', 'Download the template, fill it in, upload it.')),
      const SizedBox(height: AppSpace.xs),
      AppPrimaryButton(key: const ValueKey('ident.create'), label: t('متابعة', 'Continue'), onPressed: _label.text.trim().isEmpty ? null : () => widget.onDone(_label.text.trim(), _way)),
    ]);
  }
}

/// The roster: a name and a value on each row, the keyboard walks down the column.
class RosterGrid extends StatelessWidget {
  const RosterGrid({super.key, required this.rows, required this.controllers, this.height = 420});
  final List<IdValueRow> rows;
  final List<TextEditingController> controllers;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: height,
      child: ListView.builder(
        itemCount: rows.length,
        itemExtent: 56,
        itemBuilder: (_, i) => Row(children: [
          SizedBox(width: 30, child: Text('${i + 1}', style: AppType.meta(context).copyWith(color: c.textLight))),
          Expanded(flex: 3, child: Text(rows[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('roster.$i'),
              controller: controllers[i],
              textInputAction: i == rows.length - 1 ? TextInputAction.done : TextInputAction.next,
              style: AppType.body(context).copyWith(color: c.textDark),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RosterSheet extends StatefulWidget {
  const _RosterSheet({required this.examId, required this.option, required this.api, required this.rows});
  final int examId;
  final IdentifierOption option;
  final ExamDeliverApi api;
  final List<IdValueRow> rows;

  @override
  State<_RosterSheet> createState() => _RosterSheetState();
}

class _RosterSheetState extends State<_RosterSheet> {
  late final _controllers = [for (final r in widget.rows) TextEditingController(text: r.value)];
  bool _busy = false;

  @override
  void dispose() {
    for (final x in _controllers) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final changed = [
      for (var i = 0; i < widget.rows.length; i++)
        if (_controllers[i].text.trim() != widget.rows[i].value.trim()) IdValueRow(widget.rows[i].studentId, widget.rows[i].name, _controllers[i].text.trim()),
    ];
    if (changed.isEmpty) return Navigator.of(context).pop(false);
    setState(() => _busy = true);
    final r = await widget.api.putValues(widget.examId, widget.option.choice.source, widget.option.choice.key, changed);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    showAppNotice(t('حُفظت القيم.', 'Saved.'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return AppSheetContent(title: widget.option.label, children: [
      if (widget.rows.isEmpty)
        AppEmpty(icon: Icons.groups_rounded, title: t('لا يوجد طلاب في المقرر بعد', 'There are no students in the course yet'))
      else
        RosterGrid(rows: widget.rows, controllers: _controllers, height: (h * .55).clamp(240.0, 560.0)),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(label: t('حفظ', 'Save'), busy: _busy, onPressed: _busy ? null : _save),
    ]);
  }
}

class ImportPreviewCard extends StatelessWidget {
  const ImportPreviewCard({super.key, required this.preview});
  final IdImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget stat(String label, int n, Color tone) => Expanded(
          child: Column(children: [
            Text('$n', style: AppType.figure(context).copyWith(color: tone)),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        );
    Widget issues(String title, List<IdImportIssue> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      final shown = list.take(5).map((x) => '${t('سطر', 'Row')} ${x.row}: ${x.value}${x.reasonText.isEmpty ? '' : ' (${x.reasonText})'}').join('\n');
      return Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: AppType.meta(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
          Text(shown, style: AppType.meta(context).copyWith(height: 1.4)),
          if (list.length > 5) Text(t('و${list.length - 5} غيرها', 'and ${list.length - 5} more'), style: AppType.meta(context).copyWith(color: c.textLight)),
        ]),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          stat(t('مطابق', 'Matched'), preview.matched, c.success),
          stat(t('غير معروف', 'Unmatched'), preview.unmatched.length, preview.unmatched.isEmpty ? c.textLight : c.warning),
          stat(t('مكرر', 'Duplicates'), preview.duplicates.length, preview.duplicates.isEmpty ? c.textLight : c.warning),
          stat(t('غير صالح', 'Invalid'), preview.invalid.length, preview.invalid.isEmpty ? c.textLight : c.danger),
        ]),
        issues(t('لم نعرف هؤلاء', 'We could not place these'), preview.unmatched),
        issues(t('مكررة', 'Duplicates'), preview.duplicates),
        issues(t('قيم غير صالحة', 'Invalid values'), preview.invalid),
      ]),
    );
  }
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.examId, required this.option, required this.api});
  final int examId;
  final IdentifierOption option;
  final ExamDeliverApi api;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  IdImportPreview? _preview;
  String? _busy;

  String get _source => widget.option.choice.source;
  String? get _key => widget.option.choice.key;

  Future<void> _template() async {
    setState(() => _busy = 'template');
    final b = await widget.api.template(widget.examId, _source, _key);
    if (!mounted) return;
    setState(() => _busy = null);
    if (b == null) return _notice(t('تعذّر تنزيل القالب.', 'Could not download the template.'), error: true);
    final path = await saver.dlSaveBytes(b, 'identifiers-${widget.examId}.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    if (mounted) showAppNotice(path == null ? t('القالب جاهز.', 'The template is ready.') : '${t('حُفظ في', 'Saved to')} $path');
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (f == null || !mounted) return;
    setState(() => _busy = 'upload');
    final r = await widget.api.importPreview(widget.examId, _source, _key, await f.readAsBytes(), f.name);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    setState(() => _preview = IdImportPreview.fromJson(r.map));
  }

  Future<void> _commit() async {
    setState(() => _busy = 'commit');
    final r = await widget.api.importCommit(widget.examId, _preview!.importKey);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    showAppNotice(countText(asInt(r.map['written']), ar1: 'تم استيراد قيمة واحدة.', ar2: 'تم استيراد قيمتين.', arFew: 'تم استيراد {n} قيم.', arMany: 'تم استيراد {n} قيمة.', en1: 'Imported 1 value.', en: 'Imported {n} values.', ar0: 'لم تُستورد أي قيمة.', en0: 'Nothing was imported.'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return AppSheetContent(title: t('استيراد من Excel', 'Import from Excel'), children: [
      Text(t('1. نزّل القالب (فيه أسماء طلاب المقرر). 2. اكتب القيم في العمود الأخير. 3. ارفع الملف وراجع النتيجة قبل الحفظ.',
          '1. Download the template (it holds the course\'s students). 2. Type the values in the last column. 3. Upload it and check the result before saving.'), style: AppType.label(context).copyWith(height: 1.5)),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppButton.secondary(label: t('تنزيل القالب', 'Download the template'), icon: Icons.download_rounded, busy: _busy == 'template', onPressed: _busy != null ? null : _template),
        AppButton.tonal(label: p == null ? t('رفع الملف', 'Upload the file') : t('ملف آخر', 'Another file'), icon: Icons.upload_file_rounded, busy: _busy == 'upload', onPressed: _busy != null ? null : _pick),
      ]),
      if (p != null) ...[
        const SizedBox(height: AppSpace.sm),
        ImportPreviewCard(preview: p),
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(
            label: countText(p.matched, ar1: 'حفظ قيمة واحدة', ar2: 'حفظ قيمتين', arFew: 'حفظ {n} قيم', arMany: 'حفظ {n} قيمة', en1: 'Save 1 value', en: 'Save {n} values', ar0: 'لا توجد قيم للحفظ', en0: 'Nothing to save'), busy: _busy == 'commit', onPressed: _busy != null || p.matched == 0 || p.importKey.isEmpty ? null : _commit),
      ],
    ]);
  }
}

/// Opens the identifier plan as a sheet (the delivery screen's "Change").
Future<void> openIdentifierPlanSheet(BuildContext context, {required int examId, required int? courseId}) =>
    showAppSheet<void>(context, (ctx) => AppSheetContent(title: t('المعرّفات المطبوعة', 'Printed identifiers'), children: [
          IdentifierPlanStep(examId: examId, courseId: courseId, onValid: (_) {}),
          const SizedBox(height: AppSpace.sm),
          AppPrimaryButton(label: t('تم', 'Done'), onPressed: () => Navigator.of(ctx).pop()),
        ]));
