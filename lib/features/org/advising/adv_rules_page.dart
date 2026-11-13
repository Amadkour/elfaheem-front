// lib/features/org/advising/adv_rules_page.dart — the early-warning rules (docs/advising/PHASE6.md "Rules", #13):
// the engine card (last check, its counts, Run now, the run history) and the rules grouped by kind, each with its
// summary, priority and an on / off switch. The editor sheet is generated from the server's kind catalog (number
// fields with their unit and limits), with priority, cool-down, category, an optional scope, custom names and a
// preview over the last check's facts. Directors edit; advisors see the rules read-only.
//
//   AdvRulesView    the page's content (plain values)          AdvKindPicker   "Add a rule": which kind
//   AdvRulesPage    loads `GET …/rules`, writes through AdvWarningApi; Run now follows the run with JobWatch on
//                   `job_updated{kind: advising_warning, id}`, a slow `GET …/warning/runs/{id}` as the fallback
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart' show JobWatch;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_models.dart';
import 'adv_parts.dart';
import 'adv_warning_api.dart';
import 'adv_warning_models.dart';
import 'adv_warning_parts.dart';

/// The `job_updated` kind of an engine run.
const advWarningJobKind = 'advising_warning';

class AdvRulesView extends StatelessWidget {
  const AdvRulesView({
    super.key,
    required this.load,
    this.bundle,
    this.options = const AdvPolicyOptions(),
    this.errorText,
    this.busyIds = const {},
    this.starting = false,
    this.onRetry,
    this.onAdd,
    this.onOpen,
    this.onToggle,
    this.onRunNow,
    this.onHistory,
  });

  final AdvLoad load;
  final AdvRulesBundle? bundle;

  /// The scope choices, to name a rule's program.
  final AdvPolicyOptions options;
  final String? errorText;

  /// Rules with a write going on (their switch waits).
  final Set<int> busyIds;
  final bool starting;
  final VoidCallback? onRetry, onAdd, onRunNow, onHistory;
  final ValueChanged<AdvRule>? onOpen;
  final void Function(AdvRule rule, bool on)? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = bundle;
    if (load != AdvLoad.ready || b == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 4);
    }
    final edit = b.canEdit;
    final full = b.rules.length >= advRuleLimit;
    final children = <Widget>[
      AdvRunCard(engine: b.engine, starting: starting, onRunNow: edit ? onRunNow : null, onHistory: edit ? onHistory : null),
    ];
    if (!edit) {
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.visibility_outlined, text: t('يضبط هذه القواعد مدير الإرشاد. حين يطابقها أحد طلابك يصلك تنبيه بسببه.', 'The advising director sets these rules. When one of your students matches one, an alert tells you why.')),
      ]);
    }
    if (b.rules.isEmpty) {
      children.addAll([
        const SizedBox(height: AppSpace.lg),
        AppEmpty(
          icon: Icons.rule_rounded,
          title: t('لا قواعد بعد', 'No rules yet'),
          message: edit ? t('أضف قاعدة لتنبيه المرشدين حين يحتاج طالب إلى متابعة.', 'Add a rule to alert advisors when a student needs following up.') : null,
          actionLabel: edit && onAdd != null ? t('إضافة قاعدة', 'Add a rule') : null,
          onAction: edit ? onAdd : null,
        ),
      ]);
    } else {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: Text(
          [
            countText(b.enabledCount,
                ar0: 'لا قاعدة مفعّلة', ar1: 'قاعدة واحدة مفعّلة', ar2: 'قاعدتان مفعّلتان', arFew: '${b.enabledCount} قواعد مفعّلة', arMany: '${b.enabledCount} قاعدة مفعّلة',
                en0: 'No rule on', en1: '1 rule on', en: '${b.enabledCount} rules on'),
            t('من ${b.rules.length}', 'of ${b.rules.length}'),
            if (full) t('بلغت الحد الأقصى ($advRuleLimit)', 'at the limit ($advRuleLimit)'),
          ].join(' '),
          style: AppType.meta(context).copyWith(color: full ? appInk(context, c.warning) : null),
        ),
      ));
      for (final (kind, rules) in b.grouped) {
        final k = b.kindOf(kind);
        children.add(AdvSectionTitle(k?.label ?? kind, subtitle: k?.help));
        for (final r in rules) {
          children.add(AdvRuleCard(
            rule: r,
            kind: k,
            scopeText: advRuleScopeText(r.scope, options),
            busy: busyIds.contains(r.id),
            onToggle: edit && onToggle != null ? (v) => onToggle!(r, v) : null,
            onTap: onOpen == null ? null : () => onOpen!(r),
          ));
        }
      }
    }
    return OrgPageBody(
      primary: edit && onAdd != null && !full && b.kinds.isNotEmpty ? OrgPrimaryAction(id: 'add_rule', icon: Icons.add_rounded, label: t('إضافة قاعدة', 'Add a rule'), onTap: onAdd!) : null,
      child: AdvPageFrame(fab: edit, children: children),
    );
  }
}

/// "Add a rule": one row per kind of the catalog.
class AdvKindPicker extends StatelessWidget {
  const AdvKindPicker({super.key, required this.kinds, required this.onPick});
  final List<AdvRuleKind> kinds;
  final ValueChanged<AdvRuleKind> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('ماذا تراقب القاعدة؟ يمكن أن يكون للنوع الواحد أكثر من قاعدة بحدود وأولويات مختلفة.', 'What should the rule watch? A kind may have several rules with different limits and priorities.'),
          style: AppType.body(context)),
      const SizedBox(height: AppSpace.sm),
      for (final k in kinds)
        AdvRowCard(
          leading: Icon(advRuleKindIcon(k.kind), color: c.primary, size: AppIconSize.lg),
          title: k.label,
          subtitle: k.help,
          trailing: Icon(Icons.chevron_right_rounded, color: c.textLight),
          onTap: () => onPick(k),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

/// What the rule sheet did: the saved rule, or [deleted].
typedef AdvRuleSheetResult = ({AdvRule? saved, bool deleted});

/// Adds (no [rule]) or edits a rule of [kind]; [readOnly] shows it to an advisor.
Future<AdvRuleSheetResult?> showAdvRuleSheet(
  BuildContext context,
  AdvWarningApi api, {
  required AdvRuleKind kind,
  AdvRule? rule,
  List<AdvCategory> categories = const [],
  AdvPolicyOptions options = const AdvPolicyOptions(),
  bool readOnly = false,
}) {
  var draft = rule == null ? AdvRuleDraft.fresh(kind) : AdvRuleDraft.of(rule);
  final nameAr = TextEditingController(text: draft.nameAr), nameEn = TextEditingController(text: draft.nameEn);
  var busy = false, previewing = false;
  String? error, previewError;
  AdvRulePreview? preview;
  return showAppSheet<AdvRuleSheetResult>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        AdvRuleDraft body() => draft.copyWith(nameAr: nameAr.text, nameEn: nameEn.text);

        void change(AdvRuleDraft d) => set(() {
              draft = d;
              error = null;
              preview = null;
              previewError = null;
            });

        Future<void> submit() async {
          final d = body();
          final why = d.error(kind);
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => rule == null ? api.addRule(d, kind) : api.saveRule(rule.id, d, kind), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advWarningErrorText(r.error!, kind: kind);
            });
            return;
          }
          showAppNotice(rule == null ? t('أُضيفت القاعدة — تُطبَّق من الفحص القادم', 'Rule added — it applies from the next check') : t('حُفظت القاعدة', 'Rule saved'));
          Navigator.pop(ctx, (saved: r.data as AdvRule, deleted: false));
        }

        Future<void> runPreview() async {
          final d = body();
          final why = d.error(kind);
          if (why != null) {
            set(() => previewError = why);
            return;
          }
          set(() {
            previewing = true;
            previewError = null;
          });
          final r = await orgCall(() => api.preview(d, kind), quiet: true);
          if (!ctx.mounted) return;
          set(() {
            previewing = false;
            if (r.ok) {
              preview = r.data as AdvRulePreview;
            } else {
              previewError = advWarningErrorText(r.error!, kind: kind);
            }
          });
        }

        Future<void> delete() async {
          final yes = await appConfirm(ctx, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف القاعدة «${rule!.name}»؟ التنبيهات التي أرسلتها تبقى في السجل.', 'Delete the rule "${rule.name}"? The alerts it sent stay on record.'));
          if (!yes || !ctx.mounted) return;
          set(() => busy = true);
          final r = await orgCall(() => api.deleteRule(rule.id), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advWarningErrorText(r.error!, kind: kind);
            });
            return;
          }
          showAppNotice(t('حُذفت القاعدة', 'Rule deleted'));
          Navigator.pop(ctx, (saved: null, deleted: true));
        }

        return AppSheetContent(
          title: readOnly ? t('القاعدة', 'Rule') : (rule == null ? t('قاعدة جديدة', 'New rule') : t('تعديل القاعدة', 'Edit the rule')),
          children: [
            AdvRuleEditorView(
              kind: kind,
              draft: draft,
              nameAr: nameAr,
              nameEn: nameEn,
              categories: categories,
              options: options,
              editing: rule != null,
              system: rule?.system ?? false,
              readOnly: readOnly,
              busy: busy,
              error: error,
              preview: preview,
              previewing: previewing,
              previewError: previewError,
              onParam: (k, v) => change(draft.withParam(k, v)),
              onPriority: (p) => change(draft.copyWith(priority: p)),
              onCooldown: (v) => change(draft.copyWith(cooldownDays: v)),
              onCategory: (id) => change(draft.copyWith(categoryId: () => id)),
              onScope: (s) => change(draft.copyWith(scope: s)),
              onEnabled: (v) => change(draft.copyWith(enabled: v)),
              onPreview: runPreview,
              onSubmit: submit,
              onDelete: rule == null || rule.system ? null : delete,
            ),
          ],
        );
      })).whenComplete(() {
    nameAr.dispose();
    nameEn.dispose();
  });
}

/// The engine's runs, newest first, a page at a time.
Future<void> showAdvRunHistorySheet(BuildContext context, AdvWarningApi api) {
  final runs = <AdvWarningRun>[];
  var page = 0, pages = 1;
  var loading = false, started = false;
  String? error;
  return showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> more() async {
          if (loading) return;
          set(() => loading = true);
          final r = await orgCall(() => api.runs(page: page + 1), quiet: true);
          if (!ctx.mounted) return;
          set(() {
            loading = false;
            if (r.ok) {
              final p = r.data as AdvPage<AdvWarningRun>;
              runs.addAll([for (final x in p.items) if (!runs.any((y) => y.id == x.id)) x]);
              page = p.page;
              pages = p.pages;
              error = null;
            } else {
              error = advWarningErrorText(r.error!);
            }
          });
        }

        if (!started) {
          started = true;
          more();
        }
        return AppSheetContent(tone: AppTone.info, icon: Icons.history_rounded, 
          title: t('سجل الفحوص', 'Run history'),
          children: [
            if (error != null && runs.isEmpty)
              AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!)
            else if (runs.isEmpty && loading)
              const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero)
            else if (runs.isEmpty)
              Text(t('لم يُجرَ أي فحص بعد.', 'No check has run yet.'), style: AppType.body(ctx))
            else ...[
              for (var i = 0; i < runs.length; i++) AdvRunRow(run: runs[i], last: i == runs.length - 1 && page >= pages),
              if (page < pages)
                Align(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                    onPressed: loading ? null : more,
                    icon: loading ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.expand_more_rounded),
                    label: Text(t('فحوص أقدم', 'Older runs')),
                  ),
                ),
            ],
          ],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvRulesPage extends StatelessWidget {
  const AdvRulesPage({super.key, required this.orgId});
  final int orgId;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('قواعد الإنذار المبكر', 'Early-warning rules'),
        helpPageId: 'org.advising',
        maxWidth: 960,
        child: _AdvRulesBody(orgId: orgId),
      );
}

class _AdvRulesBody extends StatefulWidget {
  const _AdvRulesBody({required this.orgId});
  final int orgId;

  @override
  State<_AdvRulesBody> createState() => _AdvRulesBodyState();
}

class _AdvRulesBodyState extends State<_AdvRulesBody> {
  late final AdvWarningApi _api = AdvWarningApi(widget.orgId);
  late final AdvApi _adv = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;

  AdvRulesBundle? _bundle;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  List<AdvCategory> _categories = const [];
  AdvPolicyOptions _options = const AdvPolicyOptions();
  final Set<int> _busy = {};
  bool _starting = false;

  /// The run being followed (its id), so a second watch never starts.
  int? _watching;
  JobWatch? _watch;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.rules(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _bundle = r.data as AdvRulesBundle;
        _load = AdvLoad.ready;
      } else if (_bundle == null) {
        _load = advFailLoad(r);
        _error = advWarningErrorText(r.error!);
      } else {
        showAppNotice(advWarningErrorText(r.error!), error: true);
      }
    });
    if (!r.ok) return;
    OrgPageRefresh.reportUpdated(context);
    final b = _bundle!;
    final running = b.engine.running;
    if (running != null) _follow(running.id);
    if (b.canEdit) {
      // the editor's choices: the categories, and the settings page's programs / levels / cohorts for the scope
      final cats = await orgCall(() => _adv.categories(), quiet: true);
      final pol = await orgCall(() => _adv.policy(), quiet: true);
      if (!mounted) return;
      setState(() {
        if (cats.ok) _categories = cats.data as List<AdvCategory>;
        if (pol.ok) _options = (pol.data as AdvPolicyBundle).options;
      });
    }
  }

  // ── rules ──────────────────────────────────────────────────────────────────

  Future<void> _add() async {
    final b = _bundle;
    if (b == null) return;
    final kind = await showAppSheet<AdvRuleKind>(context, (ctx) => AppSheetContent(
          title: t('قاعدة جديدة', 'New rule'),
          children: [AdvKindPicker(kinds: b.kinds, onPick: (k) => Navigator.pop(ctx, k))],
        ));
    if (kind == null || !mounted) return;
    final r = await showAdvRuleSheet(context, _api, kind: kind, categories: _categories, options: _options);
    final saved = r?.saved;
    if (saved != null && mounted) setState(() => _bundle = _bundle?.withRule(saved));
  }

  Future<void> _open(AdvRule rule) async {
    final b = _bundle;
    if (b == null) return;
    final kind = b.kindOf(rule.kind) ?? AdvRuleKind(kind: rule.kind, labelAr: rule.nameAr, labelEn: rule.nameEn);
    final r = await showAdvRuleSheet(context, _api, kind: kind, rule: rule, categories: _categories, options: _options, readOnly: !b.canEdit);
    if (r == null || !mounted) return;
    setState(() {
      if (r.deleted) _bundle = _bundle?.without(rule.id);
      if (r.saved != null) _bundle = _bundle?.withRule(r.saved!);
    });
  }

  Future<void> _toggle(AdvRule rule, bool on) async {
    final kind = _bundle?.kindOf(rule.kind);
    setState(() {
      _busy.add(rule.id);
      _bundle = _bundle?.withRule(rule.withEnabled(on));
    });
    final r = await orgCall(() => _api.saveRule(rule.id, AdvRuleDraft.of(rule).copyWith(enabled: on), kind), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy.remove(rule.id);
      _bundle = _bundle?.withRule(r.ok ? r.data as AdvRule : rule);
    });
    if (r.ok) {
      showAppNotice(on ? t('شُغّلت القاعدة «${rule.name}»', 'Rule "${rule.name}" is on') : t('أُوقفت القاعدة «${rule.name}»', 'Rule "${rule.name}" is off'));
    } else {
      showAppNotice(advWarningErrorText(r.error!, kind: kind), error: true);
    }
  }

  // ── the engine ─────────────────────────────────────────────────────────────

  Future<void> _runNow() async {
    final yes = await appConfirm(context,
        confirmLabel: t('افحص الآن', 'Run now'),
        message: t('فحص كل الطلاب بكل القواعد المفعّلة الآن؟ التنبيهات الجديدة تصل المرشدين كالمعتاد.', 'Check every student against every rule that is on, now? New alerts reach the advisors as usual.'));
    if (!yes || !mounted) return;
    setState(() => _starting = true);
    final r = await orgCall(() => _api.runNow(), quiet: true);
    if (!mounted) return;
    setState(() => _starting = false);
    if (r.code == 'advising_run_busy') {
      showAppNotice(advWarningErrorText(r.error!));
      final id = asInt(r.detail['run_id']);
      if (id > 0) _follow(id);
      _reload();
      return;
    }
    if (!r.ok) {
      showAppNotice(advWarningErrorText(r.error!), error: true);
      return;
    }
    final run = r.data as AdvWarningRun;
    showAppNotice(t('بدأ الفحص — تظهر النتيجة هنا حين ينتهي', 'The check started — its result shows here when it ends'));
    setState(() => _bundle = _bundle?.withEngine(_bundle!.engine.copyWith(running: () => run)));
    _follow(run.id);
  }

  /// Follows run [id] until it ends: the run's `job_updated` reads it at once, a slow poll is the fallback; gives up
  /// after 15 minutes (the server closes a run older than 30 as stale).
  Future<void> _follow(int id) async {
    if (_watching == id) return;
    _watch?.dispose();
    _watching = id;
    final w = _watch = JobWatch(kind: advWarningJobKind, id: '$id');
    final until = DateTime.now().add(const Duration(minutes: 15));
    AdvWarningRun? run;
    try {
      while (mounted && !w.disposed && DateTime.now().isBefore(until)) {
        await w.next(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20));
        if (!mounted || w.disposed) return;
        final r = await orgCall(() => _api.run(id), quiet: true);
        if (!mounted || w.disposed) return;
        if (!r.ok) continue;
        run = r.data as AdvWarningRun;
        final current = run;
        setState(() => _bundle = _bundle?.withEngine(_bundle!.engine.copyWith(running: () => current.running ? current : null, lastRun: current.running ? null : () => current)));
        if (!current.running) break;
      }
    } finally {
      if (_watch == w) {
        w.dispose();
        _watch = null;
        _watching = null;
      }
    }
    final done = run;
    if (!mounted || done == null || done.running) return;
    if (done.failed) {
      showAppNotice(t('تعذّر إكمال الفحص — ${advWarnRunErrorText(done.error ?? 'failed')}', 'The check could not finish — ${advWarnRunErrorText(done.error ?? 'failed')}'), error: true);
    } else {
      showAppNotice(t('اكتمل الفحص: ${advRunCountsText(done)}', 'Check finished: ${advRunCountsText(done)}'));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) => AdvRulesView(
        load: _load,
        bundle: _bundle,
        options: _options,
        errorText: _error,
        busyIds: _busy,
        starting: _starting,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onAdd: _add,
        onOpen: _open,
        onToggle: _toggle,
        onRunNow: _runNow,
        onHistory: () => showAdvRunHistorySheet(context, _api),
      );
}
