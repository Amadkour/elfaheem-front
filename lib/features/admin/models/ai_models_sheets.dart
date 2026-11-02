// lib/features/admin/models/ai_models_sheets.dart
//
// The AI Models page's sheets (D-152), all opened with showAppSheet:
//   ActivatePrompt   "Activate this model for <Role>?" with the health test's result; for Embedding the index
//                    warning, the server's estimate (what is missing, the measured time) and Rebuild now / Later
//                    (example 9), or "already built" and a plain Activate when every vector exists (B6 round 2)
//   ActivateFailure  why an activation stopped (failed checks or health test) — the old model keeps serving
//   LimitsSheet      a role's threads, RAM, max concurrency, priority, idle unload
//   AddModelSheet    a registry entry, a Hugging Face repo + files, an Ollama name, or a file URL + sha256
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/models_hub/models_hub_api.dart';
import '../../../core/plural.dart';
import '../../../design/app_bidi.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_tokens.dart';
import '../admin_common.dart' show t;
import 'models_hub_text.dart';

/// What the person chose in [ActivatePrompt].
enum ActivateChoice { cancel, activate, reindexNow, reindexLater }

/// The embedding warning (example 9), one place for the prompt and the tests. [partial]: some of the new model's
/// vectors are already built (it was used before), only the rest is built.
String embeddingWarningText({bool partial = false}) => partial
    ? t('هذا يغيّر طريقة فهرسة المستندات. بعض متجهات هذا النموذج مبنية مسبقاً ويجب بناء الباقي. البناء الآن في الخلفية أم لاحقاً؟',
        'This changes how documents are indexed. Part of this model\'s vectors are already built; the rest must be built. Build them now in the background or later?')
    : t('هذا يغيّر طريقة فهرسة المستندات. يجب إعادة بناء فهرس المستندات (RAG). إعادة البناء الآن في الخلفية أم لاحقاً؟',
        'This changes how documents are indexed. The RAG index must be rebuilt. Rebuild now in the background or later?');

String _items(int n) => countText(n, ar1: 'عنصر واحد', ar2: 'عنصران', arFew: '{n} عناصر', arMany: '{n} عنصرًا', en1: '1 item', en: '{n} items');
String _chunks(int n) => countText(n, ar1: 'مقطع واحد', ar2: 'مقطعان', arFew: '{n} مقاطع', arMany: '{n} مقطعًا', en1: '1 chunk', en: '{n} chunks');
String _answers(int n) => countText(n,
    ar1: 'إجابة محفوظة واحدة', ar2: 'إجابتان محفوظتان', arFew: '{n} إجابات محفوظة', arMany: '{n} إجابة محفوظة', en1: '1 saved answer', en: '{n} saved answers');

/// What a rebuild embeds and how long it takes: "1230 items (1200 chunks + 30 saved answers) · about 3 min (…)", or
/// for a model whose vectors are partly built "200 items of 1230 still need vectors (200 chunks + 0 saved answers) · …".
String reindexEstimateText(HubReindex r) {
  final total = r.chunks + r.qa;
  final parts = '${_chunks(r.missingChunks)} + ${_answers(r.missingQa)}';
  final what = r.items < total
      ? t('يلزم بناء ${_items(r.items)} من أصل $total ($parts)', '${_items(r.items)} of $total still need vectors ($parts)')
      : '${_items(total)} ($parts)';
  final time = reindexTimeText(r);
  return time.isEmpty ? what : '$what · $time';
}

/// The rebuild time, from measured rebuilds only (the hub's `estimate`, B6 round 2): this model's own last rebuild → a
/// figure; only other models measured here → their range; nothing measured → no number. A hub without `estimate`
/// (older) → its `estimated_seconds`.
String reindexTimeText(HubReindex r) {
  final e = r.estimate;
  if (e == null) return hubDuration(r.estimatedSeconds);
  switch (e.basis) {
    case 'nothing_to_build':
      return '';
    case 'this_model' when e.seconds != null:
      return t('${hubDuration(e.seconds)} (حسب آخر إعادة بناء لهذا النموذج هنا)', '${hubDuration(e.seconds)} (measured on this model\'s last rebuild here)');
    case 'cached' when e.seconds != null:
      return t('${hubDuration(e.seconds)} (متجهاته كلها محفوظة مسبقاً في ذاكرة المتجهات)', '${hubDuration(e.seconds)} (every vector is already in the vector cache)');
    case 'other_models' when e.lowSeconds != null && e.highSeconds != null:
      // the hub's range: each measured model's per-item time as is and scaled by the two health-test speeds
      final lo = e.lowSeconds!, hi = e.highSeconds!;
      final one = e.models.length == 1;
      return hubSpan(lo) == hubSpan(hi)
          ? (one
              ? t('${hubDuration(lo)} (حسب نموذج آخر أُعيد البناء به هنا)', '${hubDuration(lo)} (going by another model rebuilt here)')
              : t('${hubDuration(lo)} (حسب نماذج أخرى أُعيد البناء بها هنا)', '${hubDuration(lo)} (going by other models rebuilt here)'))
          : (one
              ? t('بين ${hubSpan(lo)} و${hubSpan(hi)} (حسب نموذج آخر أُعيد البناء به هنا وسرعة اختبار كلٍّ منهما)',
                  'between ${hubSpan(lo)} and ${hubSpan(hi)} (going by another model rebuilt here and both models\' test speeds)')
              : t('بين ${hubSpan(lo)} و${hubSpan(hi)} (حسب نماذج أخرى أُعيد البناء بها هنا)',
                  'between ${hubSpan(lo)} and ${hubSpan(hi)} (going by other models rebuilt here)'));
    default:
      return t('المدة غير معروفة بعد: تُقاس عند أول إعادة بناء بهذا النموذج هنا', 'time not known yet — measured on this model\'s first rebuild here');
  }
}

/// Every vector of the new embedder is already built (B6 round 2): the switch needs no rebuild.
String vectorsReadyText(HubReindex r) => t(
    'متجهات هذا النموذج مبنية مسبقاً لكل المستندات (${_chunks(r.chunks)} + ${_answers(r.qa)})، فالتفعيل يبدّل الفهرس فوراً دون إعادة بناء.',
    'This model\'s vectors are already built for every document (${_chunks(r.chunks)} + ${_answers(r.qa)}), so activating switches the index at once — no rebuild.');

Widget _sheetBody(BuildContext context, {required String title, required List<Widget> children, required List<Widget> buttons}) {
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    AppSheetHeader(title),
    Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg - 4, 0, AppSpace.lg - 4, AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
      child: Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: buttons),
    ),
  ]);
}

Widget _testBlock(BuildContext context, HubTest test) {
  final c = context.colors;
  final col = test.ok ? c.success : c.danger;
  return Container(
    padding: const EdgeInsets.all(AppSpace.sm),
    decoration: BoxDecoration(
      color: col.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: col.withValues(alpha: 0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(test.ok ? Icons.verified_rounded : Icons.error_outline_rounded, color: col, size: 20),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text('${t('اختبار السلامة', 'Health test')}: ${hubTestLine(test)}',
              style: appText(13, w: FontWeight.w700, c: c.textDark)),
        ),
      ]),
      for (final ch in test.checks)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 28, top: 2),
          child: Text('${ch.ok ? '✓' : '✗'} ${ch.name}${ch.raw['text'] == null ? '' : ' — “${bidiIsolate('${ch.raw['text']}')}”'}',
              style: appText(12, c: ch.ok ? c.textMedium : c.danger)),
        ),
      if (test.error != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 28, top: 2),
          child: AutoDirText(test.error!, style: appText(12, c: c.danger)),
        ),
    ]),
  );
}

/// "Activate this model for (role)?" from plain values; the buttons pop the sheet with an [ActivateChoice].
class ActivatePrompt extends StatelessWidget {
  const ActivatePrompt({super.key, required this.role, required this.model, this.current, this.test, this.reindex});

  final String role;
  final String model;

  /// The model serving now (kept as the rollback).
  final String? current;
  final HubTest? test;

  /// Embedding only: the server's estimate; the warning and now / later show when it says a rebuild is required.
  final HubReindex? reindex;

  bool get _rebuild => role == 'embedding' && (reindex?.required ?? false);

  /// Embedding: the new model's vectors are all built already — a plain switch, no warning.
  bool get _ready => role == 'embedding' && !_rebuild && (reindex?.vectorsReady ?? false);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void pop(ActivateChoice v) => Navigator.of(context).pop(v);
    return _sheetBody(
      context,
      title: t('تفعيل هذا النموذج لدور ${hubRoleName(role)}؟', 'Activate this model for ${hubRoleName(role)}?'),
      children: [
        Text(model, style: appText(15, w: FontWeight.w800, c: c.textDark)),
        if (current != null) ...[
          const SizedBox(height: 2),
          Text(t('المُفعّل الآن: $current — يبقى متاحاً للرجوع إليه.', 'Active now: $current — kept so you can roll back.'),
              style: AppType.meta(context)),
        ],
        if (test != null) ...[const SizedBox(height: AppSpace.sm), _testBlock(context, test!)],
        if (_rebuild) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            key: const ValueKey('embedding_warning'),
            icon: Icons.warning_amber_rounded,
            color: c.warning,
            text: embeddingWarningText(partial: reindex!.items < reindex!.chunks + reindex!.qa),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(reindexEstimateText(reindex!), key: const ValueKey('reindex_estimate'), style: appText(12, w: FontWeight.w600, c: c.textMedium)),
          const SizedBox(height: 2),
          Text(
              t('يبقى البحث على النموذج الحالي حتى تكتمل المتجهات الجديدة، ثم يتحوّل الفهرس دفعة واحدة.',
                  'Search keeps the current model until the new vectors are all built; then the index switches at once.'),
              style: AppType.meta(context)),
        ] else if (_ready) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(key: const ValueKey('vectors_ready'), icon: Icons.check_circle_outline_rounded, color: c.success, text: vectorsReadyText(reindex!)),
        ] else if (role == 'embedding' && reindex != null && !reindex!.known) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.info_outline_rounded, text: t('تعذّر سؤال فهرس المستندات عن حجمه الآن.', 'The document index could not be asked for its size now.')),
        ],
      ],
      buttons: _rebuild
          ? [
              TextButton(onPressed: () => pop(ActivateChoice.cancel), child: Text(t('ليس الآن', 'Not now'))),
              OutlinedButton(key: const ValueKey('reindex_later'), onPressed: () => pop(ActivateChoice.reindexLater), child: Text(t('لاحقاً', 'Later'))),
              FilledButton(key: const ValueKey('reindex_now'), onPressed: () => pop(ActivateChoice.reindexNow), child: Text(t('إعادة البناء الآن', 'Rebuild now'))),
            ]
          : [
              OutlinedButton(onPressed: () => pop(ActivateChoice.cancel), child: Text(t('ليس الآن', 'Not now'))),
              FilledButton(key: const ValueKey('confirm_activate'), onPressed: () => pop(ActivateChoice.activate), child: Text(t('تفعيل', 'Activate'))),
            ],
    );
  }
}

/// Why an activation stopped; the old model keeps serving.
class ActivateFailure extends StatelessWidget {
  const ActivateFailure({super.key, required this.role, required this.model, this.current, this.test, this.checks = const [], this.message});

  final String role, model;
  final String? current;
  final HubTest? test;
  final List<HubCheck> checks;

  /// The server's own text (a 409 checks_failed / embedding_dim_unsupported …).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final failing = checks.where((x) => !x.ok).toList();
    return _sheetBody(
      context,
      title: t('لم يُفعَّل النموذج', 'The model was not activated'),
      children: [
        Text(model, style: appText(15, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: AppSpace.sm),
        if (message != null) ...[
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: bidiIsolate(message!)),
          const SizedBox(height: AppSpace.sm),
        ],
        for (final ch in failing)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('✗ ${hubCheckLine(ch)}', style: appText(13, c: c.danger))),
        if (test != null) _testBlock(context, test!),
        const SizedBox(height: AppSpace.sm),
        Text(
            current == null
                ? t('لم يتغيّر شيء في دور ${hubRoleName(role)}.', 'Nothing changed for ${hubRoleName(role)}.')
                : t('$current يبقى مُفعّلاً لدور ${hubRoleName(role)}.', '$current stays active for ${hubRoleName(role)}.'),
            style: appText(13, w: FontWeight.w600, c: c.textMedium)),
      ],
      buttons: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('حسناً', 'OK')))],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: appText(14, w: FontWeight.w700, c: c.textDark)),
            if (hint != null) Text(hint!, style: AppType.meta(context)),
          ]),
        ),
        IconButton(
          tooltip: t('أقل', 'Less'),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center, style: appText(16, w: FontWeight.w800, c: c.textDark))),
        IconButton(
          tooltip: t('أكثر', 'More'),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ]),
    );
  }
}

/// A role's resource limits; pops with the body of `PUT /roles/{role}/limits` (every field).
class LimitsSheet extends StatefulWidget {
  const LimitsSheet({super.key, required this.role, required this.limits, this.cpuCount});

  final String role;
  final HubLimits limits;

  /// The server's cores (threads go up to it; 16 when unknown).
  final int? cpuCount;

  @override
  State<LimitsSheet> createState() => _LimitsSheetState();
}

class _LimitsSheetState extends State<LimitsSheet> {
  late int _threads = widget.limits.threads.clamp(1, _maxThreads);
  late int _concurrency = widget.limits.maxConcurrency.clamp(1, 16);
  late String _priority = widget.limits.priority;
  late final _ram = TextEditingController(text: '${widget.limits.ramMb}');
  late final _idle = TextEditingController(text: '${widget.limits.idleUnloadS}');

  int get _maxThreads => (widget.cpuCount ?? 16).clamp(1, 256);

  @override
  void dispose() {
    _ram.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _sheetBody(
      context,
      title: t('موارد ${hubRoleName(widget.role)}', '${hubRoleName(widget.role)} limits'),
      children: [
        _Stepper(
          label: t('الخيوط', 'Threads'),
          hint: t('أنوية المعالج لكل استدعاء (حتى $_maxThreads)', 'CPU cores per call (up to $_maxThreads)'),
          value: _threads,
          min: 1,
          max: _maxThreads,
          onChanged: (v) => setState(() => _threads = v),
        ),
        _Stepper(
          label: t('الحد الأقصى للتزامن', 'Max concurrency'),
          hint: t('الطلبات التي تُخدم في الوقت نفسه', 'Requests served at the same time'),
          value: _concurrency,
          min: 1,
          max: 16,
          onChanged: (v) => setState(() => _concurrency = v),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<String>(
            value: _priority,
            decoration: InputDecoration(labelText: t('الأولوية', 'Priority')),
            items: [
              for (final p in const ['interactive', 'batch', 'grading']) DropdownMenuItem(value: p, child: Text(hubPriorityLabel(p))),
            ],
            onChanged: (v) => setState(() => _priority = v ?? _priority),
          ),
        ),
        AppField(controller: _ram, label: t('حد الذاكرة (ميغابايت، 0 = بلا حد)', 'RAM limit (MB, 0 = none)'), keyboard: TextInputType.number, ltr: true),
        AppField(controller: _idle, label: t('التفريغ بعد الخمول (ثوانٍ، 0 = أبداً)', 'Unload when idle (seconds, 0 = never)'), keyboard: TextInputType.number, ltr: true),
      ],
      buttons: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('إلغاء', 'Cancel'))),
        FilledButton(
          key: const ValueKey('limits_save'),
          onPressed: () => Navigator.of(context).pop(<String, dynamic>{
            'threads': _threads,
            'max_concurrency': _concurrency,
            'priority': _priority,
            'ram_mb': int.tryParse(_ram.text.trim()) ?? widget.limits.ramMb,
            'idle_unload_s': int.tryParse(_idle.text.trim()) ?? widget.limits.idleUnloadS,
          }),
          child: Text(t('حفظ', 'Save')),
        ),
      ],
    );
  }
}

/// Add a model; pops with the body of `POST /api/v1/models`.
class AddModelSheet extends StatefulWidget {
  const AddModelSheet({super.key, this.role = 'generation', this.roles = kHubRoles});

  final String role;
  final List<String> roles;

  @override
  State<AddModelSheet> createState() => _AddModelSheetState();
}

class _AddModelSheetState extends State<AddModelSheet> {
  String _source = 'registry';
  late String _role = widget.role;
  final _ref = TextEditingController();
  final _repo = TextEditingController();
  final _revision = TextEditingController();
  final _files = TextEditingController();
  final _ollama = TextEditingController();
  final _url = TextEditingController();
  final _sha = TextEditingController();
  final _name = TextEditingController();
  final _version = TextEditingController();
  final _prefix = TextEditingController();
  final _dim = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    for (final c in [_ref, _repo, _revision, _files, _ollama, _url, _sha, _name, _version, _prefix, _dim]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "onnx/model_quantized.onnx model" per line → [{remote, role?}] (no role: the server names it after the file).
  static List<Map<String, String>> parseFiles(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty)
            {
              'remote': line.trim().split(RegExp(r'\s+')).first,
              if (line.trim().split(RegExp(r'\s+')).length > 1) 'role': line.trim().split(RegExp(r'\s+'))[1],
            },
      ];

  Map<String, dynamic>? _body() {
    String v(TextEditingController c) => c.text.trim();
    final meta = <String, dynamic>{
      if (_role == 'embedding' && v(_prefix).isNotEmpty) 'prefix': _prefix.text,
      if (_role == 'embedding' && int.tryParse(v(_dim)) != null) 'dim': int.parse(v(_dim)),
    };
    final extra = <String, dynamic>{if (v(_name).isNotEmpty) 'name': v(_name), if (v(_version).isNotEmpty) 'version': v(_version), if (meta.isNotEmpty) 'meta': meta};
    switch (_source) {
      case 'registry':
        if (v(_ref).isEmpty) return _fail(t('اكتب مرجع النموذج كما في السجل', 'Type the model’s registry ref'));
        return {'source': 'registry', 'role': _role, 'ref': v(_ref)};
      case 'hf':
        final files = parseFiles(_files.text);
        if (!v(_repo).contains('/') || v(_revision).isEmpty || files.isEmpty) {
          return _fail(t('المستودع (owner/name) والمراجعة (commit) والملفات مطلوبة', 'The repo (owner/name), the revision (a commit) and the files are needed'));
        }
        return {'source': 'hf', 'role': _role, 'repo': v(_repo), 'revision': v(_revision), 'files': files, ...extra};
      case 'ollama':
        if (v(_ollama).isEmpty) return _fail(t('اكتب اسم نموذج Ollama', 'Type the Ollama model name'));
        return {'source': 'ollama', 'role': _role, 'ollama_name': v(_ollama)};
      default:
        if (!v(_url).startsWith('https://') || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(v(_sha))) {
          return _fail(t('رابط https وبصمة sha256 (64 حرفاً) مطلوبان', 'An https URL and its sha256 (64 hex characters) are needed'));
        }
        return {'source': 'url', 'role': _role, 'url': v(_url), 'sha256': v(_sha).toLowerCase(), ...extra};
    }
  }

  Map<String, dynamic>? _fail(String s) {
    setState(() => _problem = s);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _sheetBody(
      context,
      title: t('إضافة نموذج', 'Add model'),
      children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in const ['registry', 'hf', 'ollama', 'url'])
            AppChoiceChip(label: hubSourceLabel(s), selected: _source == s, onTap: () => setState(() => _source = s)),
        ]),
        const SizedBox(height: AppSpace.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<String>(
            value: _role,
            decoration: InputDecoration(labelText: t('الدور', 'Role')),
            items: [for (final r in widget.roles) DropdownMenuItem(value: r, child: Text(hubRoleName(r)))],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
        ),
        if (_source == 'registry')
          AppField(controller: _ref, label: t('المرجع في السجل', 'Registry ref'), hint: 'qwen3-0.6b@int4-58ca03a', ltr: true),
        if (_source == 'hf') ...[
          AppField(controller: _repo, label: t('المستودع', 'Repository'), hint: 'owner/name', ltr: true),
          AppField(controller: _revision, label: t('المراجعة (commit)', 'Revision (commit)'), ltr: true),
          AppField(
            controller: _files,
            label: t('الملفات — ملف في كل سطر، ثم دوره اختيارياً', 'Files — one per line, then its role (optional)'),
            hint: 'onnx/model_quantized.onnx model\ntokenizer.json tokenizer',
            maxLines: 4,
            ltr: true,
          ),
          Text(t('الأحجام والبصمات تُقرأ من Hugging Face.', 'Sizes and checksums are read from Hugging Face.'), style: AppType.meta(context)),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_source == 'ollama') AppField(controller: _ollama, label: t('اسم النموذج في Ollama', 'Ollama model name'), hint: 'qwen3:1.7b', ltr: true),
        if (_source == 'url') ...[
          AppField(controller: _url, label: t('رابط الملف (https)', 'File URL (https)'), hint: 'https://…/model.onnx', ltr: true),
          AppField(controller: _sha, label: 'sha256', ltr: true),
        ],
        if (_source == 'hf' || _source == 'url') ...[
          AppField(controller: _name, label: t('الاسم (اختياري)', 'Name (optional)'), ltr: true),
          AppField(controller: _version, label: t('الإصدار (اختياري)', 'Version (optional)'), ltr: true),
          if (_role == 'embedding') ...[
            AppField(controller: _prefix, label: t('بادئة الاستعلام (اختياري)', 'Query prefix (optional)'), hint: 'query: ', ltr: true),
            AppField(controller: _dim, label: t('حجم المتجه (اختياري)', 'Vector size (optional)'), hint: '384', keyboard: TextInputType.number, ltr: true),
          ],
        ],
        if (_problem != null) Text(_problem!, style: appText(12, w: FontWeight.w600, c: c.danger)),
      ],
      buttons: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('إلغاء', 'Cancel'))),
        FilledButton(
          key: const ValueKey('add_model_submit'),
          onPressed: () {
            final b = _body();
            if (b != null) Navigator.of(context).pop(b);
          },
          child: Text(t('إضافة', 'Add')),
        ),
      ],
    );
  }
}
