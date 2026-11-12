// The Attributes step of the paper exam (D-697 over contract §3): every attribute the exam's students have, with its
// coverage, picked and ordered as chips; "+ Custom attribute" makes a new one (typed, from a column of the student list,
// or from a file); one student's header shows what will print. It owns the calls; the owner hears the chosen keys
// through [onChanged] and saves them with the plan. The drawn part is CreateAttributesBody (offline_steps.dart).
library;

import 'dart:async' show unawaited;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show asInt, asMapList, t;
import '../deliver/identifier_plan_step.dart' show openIdentifierPlanSheet;
import 'answer_sheet_plan.dart';
import 'answer_sheet_widgets.dart' show CreateIdSourceRow;
import 'offline_flow.dart';
import 'offline_plan_api.dart';
import 'offline_steps.dart';

typedef ChosenAttribute = ({String key, String label});

void _say(String m, {bool error = false}) {
  showAppNotice(m, error: error);
}

class AttributesStep extends StatefulWidget {
  const AttributesStep({
    super.key,
    required this.examId,
    required this.courseId,
    required this.initial,
    required this.onChanged,
    this.remembered = const [],
    this.idSource,
    this.onIdSource,
    this.api,
  });

  final int examId;
  final int? courseId;

  /// The keys chosen so far (Back and forward keep them); empty = start from [remembered], else the server's choice.
  final List<String> initial;
  final List<String> remembered;
  final ValueChanged<List<ChosenAttribute>> onChanged;

  /// Generic copies of a course: what the students write in the ID boxes (null = not asked).
  final IdSource? idSource;
  final ValueChanged<IdSource>? onIdSource;

  /// Tests pass a fake.
  final OfflinePlanApi? api;

  @override
  State<AttributesStep> createState() => _AttributesStepState();
}

class _AttributesStepState extends State<AttributesStep> {
  late final OfflinePlanApi _api = widget.api ?? OfflinePlanApi();
  ExamAttributes? _all;
  List<String> _keys = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? add}) async {
    final r = await _api.attributes(widget.examId);
    if (!mounted) return;
    if (!r.ok) return setState(() => _error = offlinePlanErrorText(r));
    final all = ExamAttributes.fromJson(r.map);
    setState(() {
      _error = null;
      _all = all;
      final start = _keys.isEmpty ? startingAttributeKeys(all, plan: widget.initial, remembered: widget.remembered) : _keys;
      _keys = cleanAttributeKeys([...start, ?add], all);
    });
    _report();
  }

  void _report() {
    final all = _all;
    if (all == null) return;
    final out = [for (final k in _keys) (key: k, label: all.byKey(k)?.label ?? k)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(out);
    });
  }

  void _toggle(AttributeItem a) {
    setState(() => _keys = _keys.contains(a.id) ? [for (final k in _keys) if (k != a.id) k] : [..._keys, a.id]);
    _report();
  }

  void _reorder(int from, int to) {
    setState(() => _keys = reorderedList(_keys, from, to));
    _report();
  }

  Future<void> _custom() async {
    final all = _all;
    if (all == null || _busy) return;
    final columns = all.fileColumns;
    final made = await showAppSheet<CustomAttribute>(
        context,
        (ctx) => AppSheetContent(title: t('بيان مخصص', 'Custom attribute'), children: [
              CustomAttributeForm(
                ways: [CustomAttributeWay.typed, if (columns.isNotEmpty) CustomAttributeWay.fileColumn, CustomAttributeWay.upload],
                onDone: (v) => Navigator.of(ctx).pop(v),
              ),
            ]));
    if (made == null || !mounted) return;
    String? from;
    if (made.way == CustomAttributeWay.fileColumn) {
      from = await showAppSheet<String>(
          context,
          (ctx) => AppSheetContent(title: t('أي عمود؟', 'Which column?'), children: [
                for (final c in columns) ...[
                  AppPill(key: ValueKey('create.attr.col.${c.key}'), icon: Icons.view_column_outlined, label: c.label, onTap: () => Navigator.of(ctx).pop(c.key)),
                  const SizedBox(height: AppSpace.xs),
                ],
              ]));
      if (from == null || !mounted) return;
    }
    setState(() => _busy = true);
    final r = await _api.createAttribute(widget.examId, labelAr: made.labelAr, labelEn: made.labelEn, from: from);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return _say(offlinePlanErrorText(r), error: true);
    final key = '${r.map['key'] ?? ''}';
    final label = t(made.labelAr, made.labelEn);
    switch (made.way) {
      case CustomAttributeWay.typed:
        await showAppSheet<bool>(context, (_) => AttributeValuesSheet(examId: widget.examId, attributeKey: key, label: label, api: _api));
      case CustomAttributeWay.upload:
        await _upload(key, label);
      case CustomAttributeWay.fileColumn:
        break;
    }
    if (mounted) await _load(add: key);
  }

  Future<void> _upload(String key, String label) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: kPeopleFileExtensions);
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > kPeopleFileMaxBytes) return _say(t('الملف أكبر من 2 ميجابايت', 'The file is larger than 2 MB'), error: true);
    if (!mounted) return;
    final column = await showAppSheet<String>(context, (ctx) => AppSheetContent(title: label, children: [_ColumnForm(onDone: (v) => Navigator.of(ctx).pop(v))]));
    if (column == null || !mounted) return;
    final r = await _api.attributeFile(widget.examId, key, f.name, bytes, column: column);
    if (!mounted) return;
    if (!r.ok) return _say(offlinePlanErrorText(r), error: true);
    final got = AttributeFileResult.fromJson(r.map);
    showAppNotice(t('كُتبت ${got.written} قيمة من ${got.rows} صفًا', '${got.written} values written from ${got.rows} rows'));
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    if (_error != null) {
      return AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load);
    }
    if (all == null) return const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero);
    AttributeItem item(ExamAttribute a) =>
        AttributeItem(id: a.key, label: a.label, filled: a.filled, total: all.total, sample: all.sample[a.key] ?? '', fixed: a.key == 'name');
    final chosen = [for (final k in _keys) if (all.byKey(k) != null) item(all.byKey(k)!)];
    final available = [for (final a in all.items) if (!_keys.contains(a.key)) item(a)];
    final ids = widget.idSource;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ids != null && widget.onIdSource != null) ...[
        CreateIdSourceRow(value: ids, onPick: widget.onIdSource!),
        if (ids == IdSource.academic && widget.courseId != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              key: const ValueKey('create.attr.matching'),
              label: t('المعرّف الذي تُطابق به الأوراق', 'The identifier papers are matched on'),
              icon: Icons.fingerprint_rounded,
              onPressed: () => unawaited(openIdentifierPlanSheet(context, examId: widget.examId, courseId: widget.courseId)),
            ),
          ),
        const SizedBox(height: AppSpace.md),
      ],
      CreateAttributesBody(
        chosen: chosen,
        available: available,
        studentName: all.sampleName,
        max: kMaxPlanAttributes,
        saving: _busy,
        note: switch (all.studentsSource) {
          'course' => t('من طلاب المقرر (${studentsCountText(all.total)})', 'From the course\'s students (${studentsCountText(all.total)})'),
          'file' => t('من قائمة الطلاب المرفوعة (${studentsCountText(all.total)})', 'From the uploaded student list (${studentsCountText(all.total)})'),
          _ => t('النسخ العامة تحمل سطرًا فارغًا لكل بيان يكتب فيه الطالب', 'Generic copies carry a blank line for each, for the student to fill in'),
        },
        onToggle: _toggle,
        onReorder: _reorder,
        onCustom: _busy || all.studentsSource == 'none' ? null : _custom,
      ),
    ]);
  }
}

/// Which column of the file holds the values: a header as written, or its number.
class _ColumnForm extends StatefulWidget {
  const _ColumnForm({required this.onDone});
  final ValueChanged<String> onDone;

  @override
  State<_ColumnForm> createState() => _ColumnFormState();
}

class _ColumnFormState extends State<_ColumnForm> {
  final _c = TextEditingController(text: '2');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('نطابق كل صف بالطالب من رقمه أو اسمه. في أي عمود القيم؟', 'Each row is matched to its student by number or name. Which column holds the values?'),
            style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xs),
        AppField(key: const ValueKey('create.attr.column'), controller: _c, label: t('اسم العمود أو رقمه', 'The column\'s header or number')),
        const SizedBox(height: AppSpace.md),
        AppButton.primary(label: t('ارفع', 'Upload'), expand: true, onPressed: () => _c.text.trim().isEmpty ? null : widget.onDone(_c.text.trim())),
      ]);
}

/// Typing a custom attribute's value for each student (`GET` then `PUT /exams/{id}/attributes/{key}`).
class AttributeValuesSheet extends StatefulWidget {
  const AttributeValuesSheet({super.key, required this.examId, required this.attributeKey, required this.label, required this.api});
  final int examId;
  final String attributeKey;
  final String label;
  final OfflinePlanApi api;

  @override
  State<AttributeValuesSheet> createState() => _AttributeValuesSheetState();
}

class _AttributeValuesSheetState extends State<AttributeValuesSheet> {
  List<(int, String, TextEditingController)>? _rows;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows ?? const <(int, String, TextEditingController)>[]) {
      r.$3.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await widget.api.attributeValues(widget.examId, widget.attributeKey);
    if (!mounted) return;
    if (!r.ok) return setState(() => _error = offlinePlanErrorText(r));
    setState(() => _rows = [
          for (final x in asMapList(r.map['items'])) (asInt(x['student_id']), '${x['name'] ?? ''}', TextEditingController(text: '${x['value'] ?? ''}')),
        ]);
  }

  Future<void> _save() async {
    final rows = _rows;
    if (rows == null || _busy) return;
    setState(() => _busy = true);
    final r = await widget.api.putAttributeValues(widget.examId, widget.attributeKey, [for (final (id, _, c) in rows) (id, c.text.trim())]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return _say(offlinePlanErrorText(r), error: true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return AppSheetContent(title: widget.label, children: [
      if (_error != null)
        AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!)
      else if (rows == null)
        const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero)
      else ...[
        for (final (id, name, c) in rows) ...[
          AppField(key: ValueKey('create.attr.value.$id'), controller: c, label: name.isEmpty ? '#$id' : name),
          const SizedBox(height: AppSpace.xs),
        ],
        const SizedBox(height: AppSpace.xs),
        AppButton.primary(key: const ValueKey('create.attr.values.save'), label: t('احفظ القيم', 'Save the values'), busy: _busy, expand: true, onPressed: _save),
      ],
    ]);
  }
}
