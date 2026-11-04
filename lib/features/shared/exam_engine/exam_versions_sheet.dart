// "How many versions?" — the teacher's sheet for paper versions: 1–10 versions, shuffle the questions, shuffle the
// choices, copies per version; Generate calls POST /exams/{id}/versions and lists the versions made.
// VersionsForm is the plain-values part (the layout harness pumps it); ExamVersionsSheet wires it to the server.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../admin/admin_common.dart' show t;
import 'exam_versions.dart';
import 'paper/exam_setup.dart' show versionsBubbleText;

/// Opens the sheet; the versions after it (null when closed without generating).
Future<ExamVersions?> openExamVersions(BuildContext context, {required int examId, ExamVersions? current, ExamVersionsApi? api, bool bubble = false}) =>
    showAppSheet<ExamVersions>(context, (_) => ExamVersionsSheet(examId: examId, current: current, api: api, bubble: bubble));

class VersionsForm extends StatelessWidget {
  const VersionsForm({
    super.key,
    required this.count,
    required this.shuffleQuestions,
    required this.shuffleOptions,
    required this.copies,
    required this.onCount,
    required this.onShuffleQuestions,
    required this.onShuffleOptions,
    required this.onCopies,
    this.versions = const [],
    this.warnings = const [],
    this.error,
    this.busy = false,
    this.bubble = false,
    required this.onGenerate,
  });
  final int count, copies;
  final bool shuffleQuestions, shuffleOptions, busy;

  /// The exam uses a bubble sheet: the question order cannot be shuffled (the switch is off and says why).
  final bool bubble;
  final ValueChanged<int> onCount, onCopies;
  final ValueChanged<bool> onShuffleQuestions, onShuffleOptions;
  final List<ExamVersion> versions;
  final List<String> warnings;
  final String? error;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget stepper(int value, int min, int max, ValueChanged<int> on, {Key? k}) => Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: value > min ? () => on(value - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: t('أقل', 'Less')),
          SizedBox(width: 36, child: Text('$value', key: k, textAlign: TextAlign.center, style: appText(17, w: FontWeight.w800, c: c.textDark))),
          IconButton(onPressed: value < max ? () => on(value + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded), tooltip: t('أكثر', 'More')),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(t('كم نموذجًا؟', 'How many versions?'), style: appText(14, w: FontWeight.w700, c: c.textDark))),
        stepper(count, 1, kMaxVersions, onCount, k: const ValueKey('versions.count')),
      ]),
      AppSwitchTile(
          key: const ValueKey('versions.shuffleQuestions'),
          title: t('اخلط ترتيب الأسئلة', 'Shuffle the questions'),
          subtitle: bubble ? versionsBubbleText : null,
          value: shuffleQuestions && !bubble,
          dense: true,
          onChanged: bubble ? null : onShuffleQuestions),
      AppSwitchTile(title: t('اخلط ترتيب الاختيارات', 'Shuffle the choices'), value: shuffleOptions, dense: true, onChanged: onShuffleOptions),
      Row(children: [
        Expanded(child: Text(t('عدد النسخ لكل نموذج', 'Copies per version'), style: appText(14, w: FontWeight.w700, c: c.textDark))),
        stepper(copies, 1, 500, onCopies, k: const ValueKey('versions.copies')),
      ]),
      if (error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(error!, style: appText(12.5, c: c.danger))),
      for (final w in warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text(w, style: appText(12, c: c.textMedium))),
      if (versions.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in versions)
            Chip(
              label: Text('${t('نموذج', 'Version')} ${v.code}${v.copies == null ? '' : ' · ${v.copies}'}', overflow: TextOverflow.ellipsis),
              avatar: Icon(versionShuffled(v, versions.first) ? Icons.shuffle_rounded : Icons.format_list_numbered_rounded, size: 16),
            ),
        ]),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('إنشاء النماذج', 'Generate versions'), icon: Icons.auto_awesome_rounded, busy: busy, onPressed: onGenerate),
    ]);
  }
}

class ExamVersionsSheet extends StatefulWidget {
  const ExamVersionsSheet({super.key, required this.examId, this.current, this.api, this.bubble = false});
  final bool bubble;
  final int examId;
  final ExamVersions? current;
  final ExamVersionsApi? api;

  @override
  State<ExamVersionsSheet> createState() => _ExamVersionsSheetState();
}

class _ExamVersionsSheetState extends State<ExamVersionsSheet> {
  late final ExamVersionsApi _api = widget.api ?? ExamVersionsApi();
  late int _count = (widget.current?.items.length ?? 2).clamp(1, kMaxVersions);
  late bool _q = !widget.bubble && (widget.current?.shuffleQuestions ?? true), _o = widget.current?.shuffleOptions ?? true;
  late int _copies = widget.current?.items.isNotEmpty == true ? (widget.current!.items.first.copies ?? 1) : 1;
  List<ExamVersion> _made = const [];
  ExamVersions? _result;
  List<String> _warnings = const [];
  String? _error;
  bool _busy = false;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.generate(widget.examId, versionBody(count: _count, shuffleQuestions: _q && !widget.bubble, shuffleOptions: _o, copies: _copies));
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = versionsErrorText(r);
      });
      return;
    }
    final v = ExamVersions.fromJson({...r.map, 'shuffle_questions': _q, 'shuffle_options': _o});
    setState(() {
      _busy = false;
      _result = v;
      _made = v.items;
      _warnings = [for (final w in (r.map['warnings'] as List?) ?? const []) versionWarningText(w is Map ? '${w['message'] ?? w['code'] ?? ''}' : '$w')];
    });
    if (_warnings.isEmpty) {
      appToast(t('أُنشئت النماذج', 'Versions created'));
      if (mounted) Navigator.of(context).pop(v);
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(title: t('نماذج الاختبار', 'Exam versions'), children: [
        VersionsForm(
          count: _count,
          shuffleQuestions: _q,
          shuffleOptions: _o,
          copies: _copies,
          onCount: (v) => setState(() => _count = v),
          onShuffleQuestions: (v) => setState(() => _q = v),
          onShuffleOptions: (v) => setState(() => _o = v),
          onCopies: (v) => setState(() => _copies = v),
          versions: _made,
          warnings: _warnings,
          error: _error,
          busy: _busy,
          bubble: widget.bubble,
          onGenerate: _busy ? null : _generate,
        ),
        if (_result != null && _warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: OutlinedButton(onPressed: () => Navigator.of(context).pop(_result), child: Text(t('تم', 'Done'))),
          ),
      ]);
}
