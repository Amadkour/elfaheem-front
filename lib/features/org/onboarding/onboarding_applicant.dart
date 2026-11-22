// lib/features/org/onboarding/onboarding_applicant.dart — the applicant's side of member onboarding (Phase C, D-1200).
//
//   OnbApplicantCard     "My application": my open cases (`GET /org/me/onboarding`), drawn on "My organizations" next
//                        to the invitations card; nothing while there are none or the feature is off.
//   OnbApplicantPage     one of my cases: its status, due date, the corrections the reviewers asked for (per field and
//                        per document) and, while it can be edited, the wizard in applicant mode (fields the staff
//                        filled are locked). Otherwise a read-only summary with "Withdraw".
//   OnbIntakeLandingPage `/onboard/<code>`: a public preview of the organization and the type, then sign in and start.
//
// The views take plain values so the layout harness pumps them without a server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart' show SignInReturn;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../admin/admin_common.dart' show t, asMapList;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_models.dart';
import 'onboarding_review.dart' show onbStatusTone;
import 'onboarding_wizard.dart';

/// The route of an intake link.
String onbIntakeRoute(String code) => '/onboard/$code';

/// The cases the applicant still has something to do with (or wait for).
bool onbApplicantOpen(OnbCase c) => c.isOpen || (c.status == 'approved' && c.conditional);

/// What the applicant is asked to do next, one line.
String onbApplicantNext(OnbCase c) => switch (c.status) {
      'draft' => t('استكمل بياناتك ثم قدّم الطلب', 'Finish your details, then submit'),
      'needs_correction' => t('طلب المراجعون تعديلاً', 'The reviewers asked for a correction'),
      'submitted' || 'under_review' => t('طلبك قيد المراجعة', 'Your application is being reviewed'),
      'approved' when c.conditional => c.dueAt == null ? t('قُبلت بشرط استكمال مستندات', 'Accepted on condition: bring the missing documents') : t('أحضر المستندات قبل ${AppTime.date(c.dueAt!)}', 'Bring the documents before ${AppTime.date(c.dueAt!)}'),
      'approved' || 'active' => t('تم قبولك', 'You are accepted'),
      'rejected' => t('لم يُقبل الطلب', 'The application was not accepted'),
      _ => '',
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The card
// ═════════════════════════════════════════════════════════════════════════════

class OnbApplicantCard extends StatefulWidget {
  const OnbApplicantCard({super.key, this.api});
  final OnboardingApi? api;

  @override
  State<OnbApplicantCard> createState() => _OnbApplicantCardState();
}

class _OnbApplicantCardState extends State<OnbApplicantCard> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi.forApplicant();
  List<OnbCase> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.myCases();
    if (!mounted || !r.ok) return;
    final raw = r.data is List ? r.data as List : r.map['items'];
    setState(() => _items = [for (final m in asMapList(raw)) OnbCase.fromJson(m)].where(onbApplicantOpen).toList());
  }

  Future<void> _open(OnbCase c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnbApplicantPage(caseId: c.id, orgId: c.orgId ?? 0, initial: c, api: _api)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => ParentComponent(featureKey: onboardingFeatureKey, child: OnbApplicantCardView(items: _items, onOpen: _open));
}

class OnbApplicantCardView extends StatelessWidget {
  const OnbApplicantCardView({super.key, required this.items, this.onOpen});
  final List<OnbCase> items;
  final void Function(OnbCase)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppCard(
      key: const ValueKey('onb.applicant.card'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.how_to_reg_rounded, size: AppIconSize.md, color: c.primary),
          AppSpace.gapSm,
          Expanded(child: Text(t('طلبي', 'My application'), style: AppType.section(context))),
        ]),
        for (final x in items) ...[
          AppSpace.gapSm,
          InkWell(
            key: ValueKey('onb.applicant.open.${x.id}'),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: onOpen == null ? null : () => onOpen!(x),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Row(children: [
                AppAvatar(name: x.orgName.isEmpty ? x.typeLabel : x.orgName, url: x.orgLogo.isEmpty ? null : x.orgLogo),
                AppSpace.gapSm,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.orgName.isEmpty ? x.typeLabel : '${x.orgName} · ${x.typeLabel}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                    Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: AppStatusBadge(label: onbStatusLabel(x.status), tone: onbStatusTone(x.status), dense: true)),
                    Text(onbApplicantNext(x), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ]),
    ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OnbApplicantPage extends StatefulWidget {
  const OnbApplicantPage({super.key, required this.caseId, this.orgId = 0, this.initial, this.api});
  final int caseId, orgId;
  final OnbCase? initial;
  final OnboardingApi? api;

  @override
  State<OnbApplicantPage> createState() => _OnbApplicantPageState();
}

class _OnbApplicantPageState extends State<OnbApplicantPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi.forApplicant();
  OnbCase? _case;
  bool _loading = true, _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getCase(widget.orgId, widget.caseId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _case = OnbCase.fromJson(r.map);
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _withdraw() async {
    if (!await appConfirm(context, danger: true, message: t('سحب الطلب؟ لن يُراجَع بعد ذلك.', 'Withdraw the application? It will no longer be reviewed.'))) return;
    setState(() => _busy = true);
    final r = await _api.withdraw(widget.orgId, widget.caseId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(t('سُحب الطلب', 'Application withdrawn'));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _case ?? widget.initial;
    return BasePage(
      useWebCard: true,
      maxWith: 700,
      appBar: ScreenAppBar(title: t('طلبي', 'My application'), helpPageId: 'me.onboarding'),
      child: ParentComponent(
        featureKey: onboardingFeatureKey,
        child: AppStateView<OnbCase>(
          loading: _loading && c == null,
          error: c == null ? _error : null,
          data: c,
          onRetry: _load,
          isEmpty: (_) => false,
          builder: (context, x) {
            final type = x.type;
            final orgId = x.orgId ?? widget.orgId;
            if (x.can.edit && type != null) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OnbApplicantStatus(item: x, compact: true),
                Expanded(
                  child: OnbWizard(
                    key: ValueKey('onb.applicant.wizard.${x.id}.${x.status}'),
                    orgId: orgId,
                    type: type,
                    mode: OnbMode.applicant,
                    initial: x,
                    api: _api,
                    places: const OnbPlaces(),
                    onDone: (_) => _load(),
                  ),
                ),
              ]);
            }
            return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl), children: [
              OnbApplicantStatus(item: x),
              if (x.can.withdraw) ...[
                AppSpace.gapMd,
                AppButton.secondary(key: const ValueKey('onb.applicant.withdraw'), label: t('سحب الطلب', 'Withdraw'), icon: Icons.undo_rounded, busy: _busy, onPressed: _busy ? null : _withdraw),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

/// The status block of one case: status, step, due date, the decision reason and the corrections asked for.
class OnbApplicantStatus extends StatelessWidget {
  const OnbApplicantStatus({super.key, required this.item, this.compact = false});
  final OnbCase item;

  /// Above the wizard: the corrections scroll inside a short box.
  final bool compact;

  String _fieldLabel(String key) {
    final f = item.type?.field(key);
    return f == null || f.label.isEmpty ? key : f.label;
  }

  String _docLabel(String key) {
    final d = item.type?.documents.where((e) => e.key == key).firstOrNull;
    return d == null || d.label.isEmpty ? key : d.label;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    final notes = <(String, String)>[
      for (final n in x.correctionFields) (_fieldLabel(n.key), n.note),
      for (final n in x.correctionDocs) (_docLabel(n.key), n.note),
    ];
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppStatusBadge(key: const ValueKey('onb.applicant.status'), label: onbStatusLabel(x.status), tone: onbStatusTone(x.status), dense: true),
        if (x.typeLabel.isNotEmpty) AppStatusBadge(label: x.typeLabel, tone: AppTone.brand, dense: true),
        if (x.stepLabel.isNotEmpty && (x.status == 'submitted' || x.status == 'under_review')) AppStatusBadge(label: x.stepLabel, tone: AppTone.info, dense: true),
        if (x.dueAt != null) AppStatusBadge(key: const ValueKey('onb.applicant.due'), label: t('الموعد ${AppTime.date(x.dueAt!)}', 'Due ${AppTime.date(x.dueAt!)}'), tone: x.overdue ? AppTone.danger : AppTone.warning, dense: true),
      ]),
      if (x.orgName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(x.orgName, style: AppType.meta(context))),
      Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(onbApplicantNext(x), style: AppType.bodyStrong(context))),
      if (x.status == 'rejected' && x.decisionReason.isNotEmpty) ...[
        AppSpace.gapXs,
        AppBanner(icon: Icons.block_rounded, color: c.danger, text: x.decisionReason),
      ],
      if (x.status == 'needs_correction' && x.decisionReason.isNotEmpty) ...[
        AppSpace.gapXs,
        AppBanner(icon: Icons.edit_note_rounded, color: c.warning, text: x.decisionReason),
      ],
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.subdirectory_arrow_right_rounded, size: AppIconSize.sm, color: c.warning),
            AppSpace.gapXs,
            Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '${n.$1}: ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: n.$2)]), style: AppType.meta(context))),
          ]),
        ),
      if (!compact) ..._documents(context),
    ]);
    return Padding(
      padding: compact ? const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0) : EdgeInsets.zero,
      child: compact ? ConstrainedBox(constraints: const BoxConstraints(maxHeight: 180), child: SingleChildScrollView(child: body)) : AppCard(padding: const EdgeInsets.all(AppSpace.sm), child: body),
    );
  }

  List<Widget> _documents(BuildContext context) => [
        if (item.documents.isNotEmpty) ...[
          AppSpace.gapSm,
          AppSectionTitle(t('المستندات', 'Documents')),
          for (final d in item.documents)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Row(children: [
                Expanded(child: Text(_docLabel(d.reqKey), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context))),
                AppSpace.gapXs,
                AppStatusBadge(label: onbDocStatusLabel(d.status), tone: switch (d.status) { 'verified' => AppTone.success, 'rejected' => AppTone.danger, _ => AppTone.brand }, dense: true),
              ]),
            ),
        ],
      ];
}

// ═════════════════════════════════════════════════════════════════════════════
//  The intake landing page
// ═════════════════════════════════════════════════════════════════════════════

class OnbIntakeLandingPage extends StatefulWidget {
  const OnbIntakeLandingPage({super.key, required this.code, this.signedIn, this.api});
  final String code;

  /// null: ask the session (tests pass it).
  final bool? signedIn;
  final OnboardingApi? api;

  @override
  State<OnbIntakeLandingPage> createState() => _OnbIntakeLandingPageState();
}

class _OnbIntakeLandingPageState extends State<OnbIntakeLandingPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi.forApplicant();
  OnbIntakePreview? _preview;
  String? _error;
  bool _loading = true, _busy = false;

  bool get _signedIn => widget.signedIn ?? ApiClient().hasSession;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.intakePreview(widget.code);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _preview = OnbIntakePreview.fromJson(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  void _signIn(String route) {
    SignInReturn.pending = onbIntakeRoute(widget.code);
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.startIntake(widget.code);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = orgErrorText(r.error!);
      });
      return;
    }
    final c = OnbCase.fromJson(r.map);
    setState(() => _busy = false);
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OnbApplicantPage(caseId: c.id, orgId: c.orgId ?? _preview?.orgId ?? 0, initial: c, api: _api)));
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      maxWith: 560,
      appBar: ScreenAppBar(title: t('التقديم', 'Apply'), helpPageId: 'me.onboarding'),
      child: ParentComponent(
        featureKey: onboardingFeatureKey,
        child: OnbIntakeLandingView(
          preview: _preview,
          loading: _loading,
          error: _error,
          signedIn: _signedIn,
          busy: _busy,
          onStart: _start,
          onSignIn: () => _signIn('/login'),
          onRegister: () => _signIn('/register'),
          onRetry: _load,
        ),
      ),
    );
  }
}

class OnbIntakeLandingView extends StatelessWidget {
  const OnbIntakeLandingView({super.key, this.preview, this.loading = false, this.error, this.signedIn = true, this.busy = false, this.onStart, this.onSignIn, this.onRegister, this.onRetry});
  final OnbIntakePreview? preview;
  final bool loading, signedIn, busy;
  final String? error;
  final VoidCallback? onStart, onSignIn, onRegister, onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    if (loading) return const AppListSkeleton();
    if (p == null) {
      return AppEmpty(icon: Icons.link_off_rounded, title: error ?? t('تعذر فتح الرابط', 'Could not open the link'), actionLabel: t('إعادة المحاولة', 'Try again'), onAction: onRetry);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxxl), children: [
      Center(child: AppAvatar(name: p.orgName, url: p.orgLogo.isEmpty ? null : p.orgLogo, size: AppIconSize.hero + AppSpace.md)),
      AppSpace.gapSm,
      Text(p.orgName, key: const ValueKey('onb.intake.org'), textAlign: TextAlign.center, style: AppType.section(context)),
      Text(p.typeLabel, textAlign: TextAlign.center, style: AppType.bodyStrong(context)),
      AppSpace.gapXs,
      Text(t('قدّم طلبك بنفسك: أدخل بياناتك وارفع مستنداتك ثم أرسل الطلب.', 'Apply yourself: enter your details, upload your documents and submit.'), textAlign: TextAlign.center, style: AppType.meta(context)),
      if (!p.open) ...[
        AppSpace.gapMd,
        AppBanner(icon: Icons.lock_outline_rounded, color: c.warning, text: t('باب التقديم مغلق حالياً.', 'Applications are closed right now.')),
      ] else ...[
        if (error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
        ],
        AppSpace.gapMd,
        if (signedIn)
          AppButton.primary(key: const ValueKey('onb.intake.start'), label: t('ابدأ التقديم', 'Start the application'), icon: Icons.play_arrow_rounded, busy: busy, onPressed: busy ? null : onStart)
        else ...[
          Text(t('سجّل الدخول أو أنشئ حساباً للمتابعة.', 'Sign in or create an account to continue.'), textAlign: TextAlign.center, style: AppType.meta(context)),
          AppSpace.gapSm,
          Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppButton.primary(key: const ValueKey('onb.intake.signin'), label: t('تسجيل الدخول', 'Sign in'), onPressed: onSignIn),
            AppButton.secondary(key: const ValueKey('onb.intake.register'), label: t('إنشاء حساب', 'Create an account'), onPressed: onRegister),
          ]),
        ],
      ],
    ]);
  }
}
