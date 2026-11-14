// Open-ended answers, drawn (D-686): the kind chips (Number · One word · Short · Long), the quiet strip of what the server
// derived from the model answer (alternatives, keywords, points, each marked "auto" or "yours"), and the ONE Advanced
// sheet (keywords, points with weights, exact vs meaning; a number's margin and units). The model answer stays the only
// required input. Used by the quick builder's card (also the wizard's questions step) and the classic question editor.
//
// Plain-value widgets (the layout harness pumps them): OpenKindChips · DerivedKeyStrip · OpenKeyAdvancedBody ·
// NumericAdvancedBody. OpenKeyAutoPanel owns the debounced preview call.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show NumericUnit, QuestionDraft, RubricKeyword, fmtPoints, keywordsText, parseKeywords, parseNum;
import 'package:flutter_education_app/features/exams/exam_open_key.dart';

/// The kinds to offer: a number only where the question can change type (the quick builder).
class OpenKindChips extends StatelessWidget {
  const OpenKindChips({super.key, required this.value, required this.onPick, this.kinds = OpenKind.values, this.auto = false});
  final OpenKind value;
  final List<OpenKind> kinds;

  /// The kind was not chosen by the teacher: inferred from the model answer.
  final bool auto;
  final ValueChanged<OpenKind> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final k in kinds)
        AppChoiceChip(
          key: ValueKey('open.kind.${k.name}'),
          label: k == value && auto ? '${openKindLabel(k)} · ${t('تلقائي', 'auto')}' : openKindLabel(k),
          selected: k == value,
          onTap: () => onPick(k),
        ),
    ]);
  }
}

/// A quiet chip: what the key holds, never a control.
class _KeyChip extends StatelessWidget {
  const _KeyChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textDark)),
    );
  }
}

/// "auto" (derived by the server) or "yours" (the teacher's override), beside each group.
class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.teacher});
  final bool teacher;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBadgePill(teacher ? t('من إعدادك', 'yours') : t('تلقائي', 'auto'),
        color: teacher ? c.primary : c.textMedium, icon: teacher ? Icons.edit_rounded : Icons.auto_awesome_rounded);
  }
}

/// What the grader will use, under the model answer: quiet, read-only, with one way into Advanced.
class DerivedKeyStrip extends StatelessWidget {
  const DerivedKeyStrip({super.key, required this.phase, required this.kind, this.preview, this.error, this.onAdvanced, this.overridden = false});
  final DerivePhase phase;
  final OpenKind kind;
  final DeriveKeyPreview? preview;
  final String? error;
  final VoidCallback? onAdvanced;

  /// The teacher changed something in Advanced (shown on the button).
  final bool overridden;

  Widget _group(BuildContext context, String label, bool teacher, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
          _SourceTag(teacher: teacher),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [for (final x in items) _KeyChip(x)]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    final body = <Widget>[];
    switch (phase) {
      case DerivePhase.loading:
        body.add(Text(t('نقرأ إجابتك النموذجية…', 'Reading your model answer…'), style: AppType.meta(context)));
      case DerivePhase.failed:
        body.add(Text(error ?? '', style: AppType.meta(context).copyWith(color: appInkOn(context, c.warning, c.cardBg))));
      case DerivePhase.ready when p != null:
        final words = p.otherWordings;
        if (words.isNotEmpty) body.add(_group(context, t('صيغ مقبولة', 'Also accepted'), false, words.take(4).toList()));
        if (kind != OpenKind.long && p.keywords.isNotEmpty) {
          body.add(_group(context, t('الكلمات المفتاحية', 'Keywords'), p.keywordsAreTeachers, [
            for (final k in p.keywords.take(8)) k.weight != 1 ? '${k.term} ×${fmtPoints(k.weight)}' : k.term,
          ]));
        }
        if (kind == OpenKind.long && p.points.isNotEmpty) {
          final total = p.points.fold<double>(0, (s, x) => s + x.weight);
          body.add(_group(context, t('النقاط المطلوبة', 'Points to cover'), p.pointsAreTeachers, [
            for (var i = 0; i < p.points.length && i < 8; i++)
              '${i + 1}. ${p.points[i].text}${total > 0 && p.points.any((x) => x.weight != p.points.first.weight) ? ' · ${(p.points[i].weight / total * 100).round()}%' : ''}',
          ]));
        }
      default:
        break;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ...body,
      if (onAdvanced != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('open.advanced'),
            onPressed: onAdvanced,
            icon: Icon(overridden ? Icons.tune_rounded : Icons.tune_outlined, size: AppIconSize.sm),
            label: Text(overridden ? t('متقدم · معدّل', 'Advanced · changed') : t('متقدم', 'Advanced')),
          ),
        ),
    ]);
  }
}

/// The preview, asked after a pause in typing; shown by [DerivedKeyStrip].
class OpenKeyAutoPanel extends StatefulWidget {
  const OpenKeyAutoPanel({
    super.key,
    required this.type,
    required this.prompt,
    required this.answer,
    required this.kind,
    this.orgId,
    this.courseId,
    this.onAdvanced,
    this.overridden = false,
    this.api,
    this.onPreview,
  });

  final String type, prompt;

  /// The answer key as it stands (model, alternatives, the overrides).
  final Map<String, dynamic> answer;
  final OpenKind kind;
  final int? orgId, courseId;
  final VoidCallback? onAdvanced;
  final bool overridden;

  /// Tests pass a fake.
  final DeriveKeyApi? api;

  /// Hears each new preview (the Advanced sheet opens on it).
  final ValueChanged<DeriveKeyPreview?>? onPreview;

  @override
  State<OpenKeyAutoPanel> createState() => _OpenKeyAutoPanelState();
}

class _OpenKeyAutoPanelState extends State<OpenKeyAutoPanel> {
  late final DeriveKeyApi _api = widget.api ?? DeriveKeyApi();
  late final DeriveKeyDebouncer _d = DeriveKeyDebouncer(
    call: _api.preview,
    onChange: () {
      if (!mounted) return;
      setState(() {});
      widget.onPreview?.call(_d.preview);
    },
  );

  Map<String, dynamic> get _body =>
      deriveKeyBody(orgId: widget.orgId, courseId: widget.courseId, type: widget.type, prompt: widget.prompt, answer: widget.answer);

  @override
  void initState() {
    super.initState();
    if (AppConfig.disableList.contains(kExamAutoGradeFeatureKey)) {
      _d.phase = DerivePhase.hidden;
    } else {
      _d.update(_body);
    }
  }

  @override
  void didUpdateWidget(covariant OpenKeyAutoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _d.update(_body);
  }

  @override
  void dispose() {
    _d.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DerivedKeyStrip(
        phase: _d.phase,
        kind: widget.kind,
        preview: _d.preview,
        error: _d.error,
        onAdvanced: widget.onAdvanced,
        overridden: widget.overridden,
      );
}

// ── Advanced ────────────────────────────────────────────────────────────────────────────────────────────────────

/// Keywords, points and how the answer is matched. Each field opens on what the grader uses now; leaving it as it was
/// keeps it automatic, and "Back to automatic" drops an override.
class OpenKeyAdvancedBody extends StatefulWidget {
  const OpenKeyAdvancedBody({super.key, required this.kind, required this.extras, this.preview, required this.onDone});
  final OpenKind kind;
  final OpenKeyExtras extras;
  final DeriveKeyPreview? preview;
  final ValueChanged<OpenKeyExtras> onDone;

  @override
  State<OpenKeyAdvancedBody> createState() => _OpenKeyAdvancedBodyState();
}

class _OpenKeyAdvancedBodyState extends State<OpenKeyAdvancedBody> {
  late final OpenKeyExtras _x = widget.extras.copy();
  List<RubricKeyword> get _autoKeywords => widget.preview?.derived.keywords ?? const [];
  List<KeyPoint> get _autoPoints => widget.preview?.derived.points ?? const [];
  late final _kw = TextEditingController(text: keywordsText(_x.keywords ?? _autoKeywords));
  late final _pts = TextEditingController(text: keyPointsText(_x.points ?? _autoPoints));

  @override
  void dispose() {
    _kw.dispose();
    _pts.dispose();
    super.dispose();
  }

  void _done() {
    final kws = parseKeywords(_kw.text);
    _x.keywords = kws.isEmpty || sameKeywords(kws, _autoKeywords) ? null : kws;
    if (widget.kind == OpenKind.long) {
      final pts = parseKeyPoints(_pts.text);
      _x.points = pts.isEmpty || keyPointsText(pts) == keyPointsText(_autoPoints) ? null : pts.take(kMaxKeyPoints).toList();
    }
    widget.onDone(_x);
  }

  @override
  Widget build(BuildContext context) {
    final long = widget.kind == OpenKind.long;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('كيف تُقبل الإجابة', 'How an answer is accepted'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(
            key: const ValueKey('open.match.meaning'),
            label: t('بالمعنى', 'By meaning'),
            icon: Icons.psychology_alt_outlined,
            selected: _x.matchBy == MatchBy.meaning,
            onTap: () => setState(() => _x.matchBy = MatchBy.meaning)),
        AppChoiceChip(
            key: const ValueKey('open.match.exact'),
            label: t('بالنص فقط', 'Exact wording'),
            icon: Icons.spellcheck_rounded,
            selected: _x.matchBy == MatchBy.exact,
            onTap: () => setState(() => _x.matchBy = MatchBy.exact)),
      ]),
      const SizedBox(height: AppSpace.xxs),
      Text(
          _x.matchBy == MatchBy.exact
              ? t('تُقبل الإجابة النموذجية وصيغها المقبولة فقط، مع التسامح في الأخطاء الإملائية البسيطة', 'Only the model answer and its accepted wordings, small spelling slips forgiven')
              : t('تُقبل أي صياغة تحمل المعنى نفسه', 'Any wording that says the same thing'),
          style: AppType.meta(context)),
      const SizedBox(height: AppSpace.md),
      AppField(
        key: const ValueKey('open.keywords'),
        controller: _kw,
        label: t('الكلمات المفتاحية (سطر لكل كلمة)', 'Keywords (one per line)'),
        hint: t('الكلمة = مرادف، مرادف  ·  ×2 لمضاعفة الوزن', 'term = synonym, synonym  ·  ×2 doubles its weight'),
        maxLines: 5,
      ),
      if (long)
        AppField(
          key: const ValueKey('open.points'),
          controller: _pts,
          label: t('النقاط المطلوبة (سطر لكل نقطة)', 'Points to cover (one per line)'),
          hint: t('×2 بعد النقطة يضاعف نصيبها من الدرجة', '×2 after a point doubles its share of the marks'),
          maxLines: 6,
        ),
      if (_x.keywords != null || _x.points != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _x.keywords = null;
              _x.points = null;
              _kw.text = keywordsText(_autoKeywords);
              _pts.text = keyPointsText(_autoPoints);
            }),
            icon: const Icon(Icons.auto_awesome_rounded, size: AppIconSize.sm),
            label: Text(t('العودة إلى التلقائي', 'Back to automatic')),
          ),
        ),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(key: const ValueKey('open.advanced.done'), label: t('تم', 'Done'), icon: Icons.check_rounded, onPressed: _done),
    ]);
  }
}

Future<OpenKeyExtras?> showOpenKeyAdvanced(BuildContext context, {required OpenKind kind, required OpenKeyExtras extras, DeriveKeyPreview? preview}) =>
    showAppSheet<OpenKeyExtras>(
      context,
      (ctx) => AppSheetContent(title: t('إعدادات التصحيح المتقدمة', 'Advanced marking'), children: [
        OpenKeyAdvancedBody(kind: kind, extras: extras, preview: preview, onDone: (x) => Navigator.of(ctx).pop(x)),
      ]),
    );

/// "cm = 0.01" lines ⇄ units.
String unitsText(List<NumericUnit> units) => units.map((u) => '${u.name} = ${u.factor}').join('\n');

List<NumericUnit> parseUnits(String text) => [
      for (final raw in text.split('\n'))
        if (raw.trim().isNotEmpty)
          NumericUnit(raw.split('=').first.trim(), raw.contains('=') ? raw.substring(raw.indexOf('=') + 1).trim() : '1'),
    ];

/// A number's margin and units: written into the draft on Done.
class NumericAdvancedBody extends StatefulWidget {
  const NumericAdvancedBody({super.key, required this.draft, required this.onDone});
  final QuestionDraft draft;
  final VoidCallback onDone;

  @override
  State<NumericAdvancedBody> createState() => _NumericAdvancedBodyState();
}

class _NumericAdvancedBodyState extends State<NumericAdvancedBody> {
  QuestionDraft get d => widget.draft;
  late final _tol = TextEditingController(text: d.numTolerance);
  late final _units = TextEditingController(text: unitsText(d.units));
  late String _kind = d.toleranceKind;

  @override
  void dispose() {
    _tol.dispose();
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppField(
        key: const ValueKey('open.tolerance'),
        controller: _tol,
        label: t('الهامش المقبول (اختياري)', 'Accepted margin (optional)'),
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        ltr: true,
      ),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('قيمة ±', 'Value ±'), selected: _kind == 'abs', onTap: () => setState(() => _kind = 'abs')),
        AppChoiceChip(label: t('نسبة ٪', 'Percent %'), selected: _kind == 'pct', onTap: () => setState(() => _kind = 'pct')),
      ]),
      const SizedBox(height: AppSpace.md),
      AppField(
        key: const ValueKey('open.units'),
        controller: _units,
        label: t('الوحدات (اختياري، سطر لكل وحدة)', 'Units (optional, one per line)'),
        hint: t('m = 1  ·  cm = 0.01 (وحدة الإجابة معاملها 1)', 'm = 1  ·  cm = 0.01 (the answer\'s unit has factor 1)'),
        maxLines: 4,
        ltr: true,
      ),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(
        key: const ValueKey('open.advanced.done'),
        label: t('تم', 'Done'),
        icon: Icons.check_rounded,
        onPressed: () {
          final tol = _tol.text.trim();
          d.numTolerance = tol.isEmpty || parseNum(tol) != null ? tol : d.numTolerance;
          d.toleranceKind = _kind;
          d.units = parseUnits(_units.text);
          widget.onDone();
        },
      ),
    ]);
  }
}

Future<bool?> showNumericAdvanced(BuildContext context, QuestionDraft draft) => showAppSheet<bool>(
      context,
      (ctx) => AppSheetContent(title: t('إعدادات الرقم المتقدمة', 'Advanced: the number'), children: [
        NumericAdvancedBody(draft: draft, onDone: () => Navigator.of(ctx).pop(true)),
      ]),
    );
