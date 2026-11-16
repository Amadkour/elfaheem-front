// lib/features/org/home/org_setup_checklist.dart
//
// C5: the org admin's first-run "Set up your organization" card on the Home (kill switch `org.setup_checklist`).
//   GET  /api/v1/org/orgs/{id}/setup           {dismissed, steps: [{key, done, count}]}
//   POST /api/v1/org/orgs/{id}/setup/dismiss   {dismissed: true}
// Steps in the server's order: profile · departments · join_method · people · term · courses · timetable. Each step's
// button opens the page that does it (orgSetupTarget); the card shows the progress, can be dismissed and is hidden when
// dismissed or when every step is done. An older server (no route) or a failed load draws nothing: it is a nicety,
// never a blocker.
//   OrgSetupData / orgSetupTarget / orgSetupShow   pure (test/org/of_f3_setup_test.dart)
//   OrgSetupCard                                    presentational, plain values (test/ui/of_f3_layout_test.dart)
//   OrgSetupChecklist                               the live widget
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../org_institution_wizard.dart' show OrgInstitutionSetupCard, institutionWizardAllowed;
import '../org_v3.dart' show OrgCall, orgCall;

const orgSetupFeatureKey = 'org.setup_checklist';

/// Whether the checklist may ask the server at all: organizations are on and its kill switch is not in the disable list.
bool orgSetupAllowed() => AppConfig.orgsEnabled && !AppConfig.disableList.contains(orgSetupFeatureKey);

/// `GET …/setup` started by the home IN PARALLEL with the dashboard call (no waterfall); the widget takes the answer
/// once (D-287: the checklist is one extra request on open, none on pull-to-refresh).
abstract final class OrgSetupPrefetch {
  static const maxAge = Duration(seconds: 30);
  static final Map<int, (DateTime, Future<OrgCall>)> _inflight = {};

  static Future<OrgCall> _get(int orgId) => orgCall(() => ApiClient().get('/api/v1/org/orgs/$orgId/setup'), quiet: true);

  static void start(int orgId) {
    if (!orgSetupAllowed()) return;
    final have = _inflight[orgId];
    if (have != null && DateTime.now().difference(have.$1) < maxAge) return;
    _inflight[orgId] = (DateTime.now(), _get(orgId));
  }

  /// The prefetched answer (taken once), else a new call.
  static Future<OrgCall> take(int orgId) {
    final hit = _inflight.remove(orgId);
    if (hit != null && DateTime.now().difference(hit.$1) < maxAge) return hit.$2;
    return _get(orgId);
  }

  @visibleForTesting
  static void reset() => _inflight.clear();
}

/// The server's step order; a key not in this list is not drawn (an unknown future step has no label yet).
const orgSetupOrder = ['profile', 'departments', 'join_method', 'people', 'term', 'courses', 'timetable'];

class OrgSetupStep {
  const OrgSetupStep({required this.key, required this.done, this.count});
  final String key;
  final bool done;
  final int? count;
}

class OrgSetupData {
  const OrgSetupData({required this.dismissed, required this.steps, this.wizardApplicable = false, this.wizardLaunched = false});
  final bool dismissed;
  final List<OrgSetupStep> steps;

  /// Institutions v2 phase 4: `wizard: {applicable, launched}`: a university / faculty gets the setup wizard card.
  final bool wizardApplicable, wizardLaunched;

  /// The wizard card replaces this checklist (even a dismissed one) until the institution is launched.
  bool get wizardCard => wizardApplicable && !wizardLaunched;

  /// The payload of `GET …/setup`; unknown keys are dropped, the rest follow [orgSetupOrder].
  factory OrgSetupData.fromJson(Map<String, dynamic> j) {
    final byKey = {
      for (final s in asMapList(j['steps']))
        '${s['key']}': OrgSetupStep(key: '${s['key']}', done: s['done'] == true, count: s['count'] == null ? null : asInt(s['count'])),
    };
    final w = asMap(j['wizard']);
    return OrgSetupData(
      dismissed: j['dismissed'] == true,
      steps: [for (final k in orgSetupOrder) ?byKey[k]],
      wizardApplicable: w['applicable'] == true,
      wizardLaunched: w['launched'] == true || (w['launched_at'] != null && '${w['launched_at']}'.isNotEmpty),
    );
  }

  int get doneCount => steps.where((s) => s.done).length;
  bool get allDone => steps.isNotEmpty && doneCount == steps.length;
  double get progress => steps.isEmpty ? 0 : doneCount / steps.length;

  /// The first step still to do (the card highlights it).
  OrgSetupStep? get next {
    for (final s in steps) {
      if (!s.done) return s;
    }
    return null;
  }

  OrgSetupData dismissedCopy() =>
      OrgSetupData(dismissed: true, steps: steps, wizardApplicable: wizardApplicable, wizardLaunched: wizardLaunched);
}

/// Whether the card is drawn: not dismissed, something to do, and the person is an org admin.
bool orgSetupShow(OrgSetupData? d, {required bool isAdmin}) => isAdmin && d != null && !d.dismissed && d.steps.isNotEmpty && !d.allDone;

/// Where a step's button goes: a dashboard section (+ sub-page) for `orgJump`, or a named action the home opens itself.
({String? section, String? sub, String? action}) orgSetupTarget(String key) => switch (key) {
      'profile' => (section: null, sub: null, action: 'edit_profile'),
      'join_method' => (section: null, sub: null, action: 'join_code'),
      'departments' => (section: 'people', sub: 'departments', action: null),
      'people' => (section: 'people', sub: 'members', action: null),
      'term' => (section: 'academics', sub: 'structure', action: null),
      'courses' => (section: 'academics', sub: 'courses', action: null),
      'timetable' => (section: 'timetable', sub: null, action: null),
      _ => (section: null, sub: null, action: null),
    };

String orgSetupTitle(String key) => switch (key) {
      'profile' => t('أكمل ملف المؤسسة', 'Complete the profile'),
      'departments' => t('أنشئ أول قسم', 'Create your first department'),
      'join_method' => t('حدّد طريقة الانضمام', 'Set how people join'),
      'people' => t('ادعُ الأعضاء', 'Invite people'),
      'term' => t('أضف فصلاً دراسياً', 'Add a term'),
      'courses' => t('أضف المقررات', 'Add courses'),
      'timetable' => t('ابنِ الجدول', 'Build the timetable'),
      _ => key,
    };

String orgSetupHint(String key) => switch (key) {
      'profile' => t('الشعار والنبذة تظهران لكل أعضائك', 'The logo and the about text are what your members see'),
      'departments' => t('الكليات والأقسام التي ينتمي إليها الأعضاء', 'The faculties and departments your members belong to'),
      'join_method' => t('كود انضمام أو سياسة قبول', 'A join code or an approval policy'),
      'people' => t('أضف طلاباً ومدرسين أو شارك كود الانضمام', 'Add students and teachers, or share the join code'),
      'term' => t('الفترة التي تُبنى عليها المقررات والجداول', 'The period courses and timetables are built on'),
      'courses' => t('المقررات التي يدرسها طلابك', 'The courses your students take'),
      'timetable' => t('يمكن توليده تلقائياً بعد المقررات', 'It can be generated for you once courses exist'),
      _ => '',
    };

String orgSetupActionLabel(String key) => switch (key) {
      'profile' => t('عدّل الملف', 'Edit profile'),
      'join_method' => t('كود الانضمام', 'Join code'),
      'departments' => t('افتح الأقسام', 'Open departments'),
      'people' => t('افتح الأعضاء', 'Open members'),
      'term' => t('افتح الهيكل', 'Open structure'),
      'courses' => t('افتح المقررات', 'Open courses'),
      'timetable' => t('افتح الجدول', 'Open timetable'),
      _ => t('فتح', 'Open'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The card (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class OrgSetupCard extends StatelessWidget {
  const OrgSetupCard({super.key, required this.data, required this.onOpen, required this.onDismiss, this.dismissing = false});
  final OrgSetupData data;
  final void Function(OrgSetupStep step) onOpen;
  final VoidCallback onDismiss;
  final bool dismissing;

  @override
  Widget build(BuildContext context) {
    final next = data.next;
    // a sky block (information, first-run): the headline in the editorial face, the progress filling in once
    return AppBlock(
      tone: AppBlockTone.sky,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg, AppSpace.md, AppSpace.md),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('جهّز مؤسستك', 'Set up your organization'), style: AppType.headline(context).copyWith(color: b.ink)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(
                  t('${data.doneCount} من ${data.steps.length} خطوات مكتملة', '${data.doneCount} of ${data.steps.length} steps done'),
                  style: AppType.meta(context).copyWith(color: b.muted)),
            ]),
          ),
          AppButton.ghost(
            key: const ValueKey('setup.dismiss'),
            label: t('إخفاء', 'Dismiss'),
            icon: Icons.close_rounded,
            busy: dismissing,
            onPressed: dismissing ? null : onDismiss,
          ),
        ]),
        AppSpace.gapSm,
        AppFill(
          value: data.progress,
          builder: (context, v) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              key: const ValueKey('setup.progress'),
              value: v,
              minHeight: AppSpace.xs * 0.75,
              backgroundColor: context.colors.cardBg,
              color: context.colors.success,
            ),
          ),
        ),
        AppSpace.gapSm,
        for (final s in data.steps) _StepRow(step: s, highlight: s.key == next?.key, onOpen: () => onOpen(s)),
      ]);
      }),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.highlight, required this.onOpen});
  final OrgSetupStep step;
  final bool highlight;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final hint = orgSetupHint(step.key);
    return Padding(
      key: ValueKey('setup.step.${step.key}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        Icon(step.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: AppIconSize.lg, color: step.done ? b.accentInk(c.success) : (highlight ? b.accentInk(c.primary) : b.faint)),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                step.count != null && step.count! > 0 && step.done ? '${orgSetupTitle(step.key)} · ${step.count}' : orgSetupTitle(step.key),
                style: step.done
                    ? AppType.row(context).copyWith(color: b.muted, decoration: TextDecoration.lineThrough)
                    : AppType.row(context).copyWith(color: b.ink)),
            if (!step.done && hint.isNotEmpty)
              Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
            if (!step.done)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: highlight
                    ? AppButton.tonal(label: orgSetupActionLabel(step.key), onPressed: onOpen, size: AppButtonSize.sm)
                    : AppButton.ghost(label: orgSetupActionLabel(step.key), onPressed: onOpen, size: AppButtonSize.sm),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The live widget
// ═════════════════════════════════════════════════════════════════════════════

class OrgSetupChecklist extends StatefulWidget {
  const OrgSetupChecklist({super.key, required this.orgId, required this.onOpen, this.reloadToken, this.onOpenWizard});
  final int? orgId;

  /// Opens the institution setup wizard (the card that replaces this checklist for a university / faculty).
  final Future<void> Function()? onOpenWizard;

  /// Opens the page of a step (the home maps [orgSetupTarget] onto its navigation).
  final void Function(OrgSetupStep step) onOpen;

  /// Changes whenever the home reloaded. The checklist asks again only if a step's page was opened meanwhile (a step
  /// done there flips here); a plain pull-to-refresh costs no request.
  final Object? reloadToken;

  @override
  State<OrgSetupChecklist> createState() => _OrgSetupChecklistState();
}

class _OrgSetupChecklistState extends State<OrgSetupChecklist> {
  OrgSetupData? _data;
  bool _dismissing = false;
  bool _stepOpened = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrgSetupChecklist old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _data = null;
      _dismissing = false;
      _stepOpened = false;
      _load();
    } else if (old.reloadToken != widget.reloadToken && _stepOpened) {
      _stepOpened = false;
      _load(fresh: true);
    }
  }

  String get _base => '/api/v1/org/orgs/${widget.orgId}/setup';

  Future<void> _load({bool fresh = false}) async {
    final id = widget.orgId;
    if (id == null || !orgSetupAllowed()) return;
    final r = fresh ? await orgCall(() => ApiClient().get(_base), quiet: true) : await OrgSetupPrefetch.take(id);
    if (!mounted || id != widget.orgId) return;
    // an older server (no route), a 403 (also orgs_disabled) or a failure: draw nothing, never an error on the Home
    setState(() => _data = r.ok ? OrgSetupData.fromJson(asMap(r.data)) : null);
  }

  Future<void> _dismiss() async {
    final id = widget.orgId;
    setState(() => _dismissing = true);
    final r = await orgCall(() => ApiClient().post('$_base/dismiss'), quiet: true);
    // the admin switched to another organization meanwhile: the answer is not for this card any more
    if (!mounted || id != widget.orgId) return;
    setState(() {
      _dismissing = false;
      if (r.ok) _data = _data?.dismissedCopy();
    });
    if (!r.ok) showAppNotice(t('تعذّر إخفاء القائمة الآن', 'Could not hide the checklist right now'), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final wizard = widget.onOpenWizard;
    // the card's own admin check is the caller's (the home passes it only to org admins)
    Widget checklist() {
      if (!orgSetupShow(d, isAdmin: true)) return const SizedBox.shrink();
      return ParentComponent(
        featureKey: orgSetupFeatureKey,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: OrgSetupCard(data: d!, onOpen: (x) {
            _stepOpened = true;
            widget.onOpen(x);
          }, onDismiss: _dismiss, dismissing: _dismissing),
        ),
      );
    }

    // a university / faculty: the wizard card until the launch; after it (phase 5) the institution's health card
    // while a roadmap stage warns, else the old checklist (the server dismisses it at the launch)
    if (d != null && d.wizardApplicable && wizard != null && widget.orgId != null && institutionWizardAllowed()) {
      return OrgInstitutionSetupCard(
          orgId: widget.orgId!,
          fallback: d.wizardLaunched ? checklist() : null,
          onOpen: () async {
            await wizard();
            if (mounted) _load(fresh: true);
          });
    }
    return checklist();
  }
}
