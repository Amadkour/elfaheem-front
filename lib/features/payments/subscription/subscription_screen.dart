// lib/features/subscription/subscription_screen.dart
//
// The student paywall. Opened at '/subscription' — automatically by ApiClient
// when the server answers 402 SUBSCRIPTION_REQUIRED, and from the profile page.
//
// It tells the truth about WHO asks for the subscription (`reason`: the person's
// organization's fee policy, with its name and contact, or the platform) and
// never loops: "Continue" is offered only while the server says the person has
// access, and a Continue that lands straight back here (an older server whose
// status ignores the organization rule, QA H1) shows "access isn't open yet"
// with refresh + log out instead of the "app is free" page again.
library;

import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart' show AppArea;
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'dart:math' as math;

import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppPressScale, AppReveal;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/payments/subscription/subscription_provider.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => SubscriptionProvider()..load(),
    // the money area of the redesign (S-D)
    child: const SdArea(area: AppArea.money, child: _View()),
  );
}

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  String? planCode;
  String method = 'bank_transfer';
  final _sender = TextEditingController();
  final _phone = TextEditingController();
  final _ref = TextEditingController();
  XFile? _proof;
  bool busy = false;

  @override
  void dispose() {
    _sender.dispose();
    _phone.dispose();
    _ref.dispose();
    super.dispose();
  }

  SubPlan? _plan(SubscriptionProvider p) {
    for (final x in p.plans) {
      if (x.code == planCode) return x;
    }
    return null;
  }

  /// When "Continue" was last pressed (static: a 402 rebuilds this page from scratch).
  static DateTime? _continuedAt;

  /// The server answered 402 again right after "Continue": its status and its guard disagree.
  bool get _bouncedBack => _continuedAt != null && DateTime.now().difference(_continuedAt!) < const Duration(seconds: 30);

  void _goHome() {
    _continuedAt = DateTime.now();
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
  }

  Widget _refreshAndLogout(SubscriptionProvider p) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppButton.secondary(
        label: 'sub_refresh_status'.tr,
        icon: Icons.refresh_rounded,
        onPressed: () {
          _continuedAt = null;
          p.load();
        },
      ),
      const SizedBox(height: AppSpace.xs),
      ParentComponent(
        featureKey: 'subscription.logout',
        child: AppButton.ghost(label: 'sub_logout'.tr, onPressed: () => context.read<ProfileProvider>().logout(context)),
      ),
    ]);
  }

  /// "{organization} · contact: …" under an organization's request ('' when the server named none).
  String _orgLine(SubscriptionProvider p, bool isAr) {
    final name = p.orgName(isAr), contact = p.orgContact();
    return [
      if (name.isNotEmpty) name,
      if (contact.isNotEmpty) '${'sub_org_contact'.tr} $contact',
    ].join('\n');
  }

  Future<void> _submit(SubscriptionProvider p) async {
    final plan = _plan(p);
    if (plan == null) {
      toast('sub_choose_plan'.tr, error: true);
      return;
    }
    if (!plan.isFree) {
      if (_sender.text.trim().isEmpty) {
        toast('sub_enter_sender'.tr, error: true);
        return;
      }
      if (_proof == null) {
        toast('sub_attach_receipt_error'.tr, error: true);
        return;
      }
    }
    setState(() => busy = true);
    final bytes = _proof == null ? null : await _proof!.readAsBytes();
    final err = await p.subscribe(
      planCode: plan.code,
      method: plan.isFree ? null : method,
      senderName: _sender.text.trim().isEmpty ? null : _sender.text.trim(),
      senderPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      proofBytes: bytes,
      proofName: _proof?.name,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      toast(err, error: true);
    } else if (p.hasAccess) {
      toast('sub_activated_toast'.tr);
      _goHome();
    } else {
      toast('sub_request_sent'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionProvider>();
    final c = context.colors;
    final plan = _plan(p);
    final isAr = AppConfig.lang == 'ar';

    Widget body;
    var scrollable = false; // the plans list scrolls by itself; the status cards are laid out by AppRefresh
    if (!p.loaded) {
      body = const AppListSkeleton(withAvatar: false);
    } else if (p.error != null && p.plans.isEmpty) {
      body = AppErrorState(message: p.error!, onRetry: p.load);
    } else if (p.hasAccess && p.required && p.active != null) {
      body = _Status(
        icon: Icons.verified_rounded,
        tone: AppBlockTone.emerald,
        accent: c.success,
        title: 'sub_active_title'.tr,
        subtitle: '${'sub_ends_on'.tr} ${shortDate('${p.active!['ends_at']}')}',
        action: AppButton.primary(label: 'sub_continue'.tr, onPressed: _goHome),
      );
    } else if (p.pending != null) {
      body = _Status(
        icon: Icons.hourglass_top_rounded,
        accent: c.warning,
        title: 'sub_under_review'.tr,
        subtitle: 'sub_review_subtitle'.tr,
        action: AppButton.secondary(label: 'sub_refresh_status'.tr, icon: Icons.refresh_rounded, onPressed: p.load),
      );
    } else if (p.hasAccess && _bouncedBack) {
      // the status says "free" but every other call still answers 402 (an older server): never loop
      body = _Status(
        icon: Icons.lock_clock_rounded,
        accent: c.warning,
        title: 'sub_access_paused'.tr,
        subtitle: 'sub_access_paused_hint'.tr,
        action: _refreshAndLogout(p),
      );
    } else if (p.hasAccess) {
      body = _Status(
        icon: Icons.celebration_rounded,
        tone: AppBlockTone.emerald,
        accent: c.success,
        title: p.platformRequired ? 'sub_covered_title'.tr : 'sub_app_free'.tr,
        subtitle: 'sub_no_subscription_needed'.tr,
        action: AppButton.primary(label: 'sub_continue'.tr, onPressed: _goHome),
      );
    } else if (p.plans.isEmpty) {
      // a subscription is needed but none can be bought here: say who to ask
      final org = p.reason == 'organization';
      final line = _orgLine(p, isAr);
      body = _Status(
        icon: org ? Icons.apartment_rounded : Icons.workspace_premium_rounded,
        accent: c.warning,
        title: org ? 'sub_org_requires_title'.tr : 'sub_subscribe_to_continue'.tr,
        subtitle: [org ? 'sub_org_no_plans'.tr : 'sub_no_plans'.tr, if (org && line.isNotEmpty) line].join('\n\n'),
        action: _refreshAndLogout(p),
      );
    } else {
      final transferEnabled = p.transfer['bank_transfer_enabled'] == true || p.transfer['instapay_enabled'] == true;
      final methods = <String, String>{
        if (p.transfer['bank_transfer_enabled'] == true) 'bank_transfer': 'sub_bank_transfer'.tr,
        if (p.transfer['instapay_enabled'] == true) 'instapay': 'InstaPay',
      };
      final shownMethod = method == 'instapay' && p.transfer['instapay_enabled'] != true
          ? 'bank_transfer'
          : (method == 'bank_transfer' && p.transfer['bank_transfer_enabled'] != true ? 'instapay' : method);
      final rejected = p.last != null && '${p.last!['status']}' == 'rejected';
      scrollable = true;
      // ONE entrance (system.md §6): the intro block leads, the plans follow it once; the payment part answers a
      // choice, so it is simply there
      Widget enter(int i, Widget w) => AppReveal(index: i, group: 'subscription', child: w);
      body = ListView(
        padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xl),
        children: [
          AppWidthBox(
            width: AppWidth.form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              enter(
                0,
                _Intro(
                  title: p.reason == 'organization' ? 'sub_org_requires_title'.tr : 'sub_subscribe_to_continue'.tr,
                  hint: p.reason == 'organization'
                      ? ['sub_org_requires_hint'.tr, if (_orgLine(p, isAr).isNotEmpty) _orgLine(p, isAr)].join('\n')
                      : null,
                  rejected: rejected
                      ? '${'sub_prev_rejected'.tr}${p.last!['rejection_reason'] != null ? ': ${p.last!['rejection_reason']}' : ''}'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              for (var i = 0; i < p.plans.length; i++)
                ParentComponent(
                  featureKey: 'subscription.plans',
                  child: enter(
                    1 + i,
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _PlanCard(
                        plan: p.plans[i],
                        isAr: isAr,
                        selected: p.plans[i].code == planCode,
                        onTap: () {
                          setState(() => planCode = p.plans[i].code);
                          p.loadTransferDetails(p.plans[i].code);
                        },
                      ),
                    ),
                  ),
                ),
              if (plan != null && !plan.isFree) ...[
                if (!transferEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Text('sub_no_payment_methods'.tr,
                        style: AppType.body(context).copyWith(color: c.blockAccentInk(c.danger, c.background))),
                  )
                else ...[
                  ParentComponent(
                    featureKey: 'subscription.payment_method',
                    child: AppSection(
                      title: 'sub_payment_method'.tr,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppTabs(
                          items: [for (final v in methods.values) AppTabItem(v)],
                          index: math.max(0, methods.keys.toList().indexOf(shownMethod)),
                          onChanged: (i) => setState(() => method = methods.keys.elementAt(i)),
                        ),
                      ),
                    ),
                  ),
                  ParentComponent(
                    featureKey: 'subscription.transfer_details',
                    child: AppSection(
                      title: 'sub_transfer_to'.tr,
                      child: AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (shownMethod == 'bank_transfer') ...[
                            _Detail('sub_bank'.tr, '${p.transfer['bank_name'] ?? ''}'),
                            _Detail('sub_account'.tr, '${p.transfer['account_name'] ?? ''}'),
                            _Detail('IBAN', '${p.transfer['iban'] ?? ''}', ltr: true),
                            if (p.transfer['bank_instructions'] != null)
                              _Detail('sub_notes'.tr, '${p.transfer['bank_instructions']}'),
                          ] else ...[
                            _Detail('InstaPay', '${p.transfer['instapay_id'] ?? ''}', ltr: true),
                            if (p.transfer['instapay_instructions'] != null)
                              _Detail('sub_notes'.tr, '${p.transfer['instapay_instructions']}'),
                          ],
                          _Detail('sub_amount'.tr, money(plan.price, plan.currency), strong: true, last: true),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  ParentComponent(
                    featureKey: 'subscription.sender_info',
                    child: AppField(controller: _sender, label: 'sub_sender_name'.tr, icon: Icons.person_rounded),
                  ),
                  const SizedBox(height: AppSpace.md),
                  ParentComponent(
                    featureKey: 'subscription.sender_info',
                    child: AppField(
                        controller: _phone,
                        label: 'sub_sender_phone'.tr,
                        icon: Icons.phone_rounded,
                        keyboard: TextInputType.phone,
                        ltr: true),
                  ),
                  const SizedBox(height: AppSpace.md),
                  ParentComponent(
                    featureKey: 'subscription.sender_info',
                    child: AppField(controller: _ref, label: 'sub_reference'.tr, icon: Icons.tag_rounded, ltr: true),
                  ),
                  const SizedBox(height: AppSpace.md),
                  ParentComponent(
                    featureKey: 'subscription.receipt',
                    child: AppButton.secondary(
                      expand: true,
                      label: _proof == null ? 'sub_attach_receipt'.tr : _proof!.name,
                      icon: _proof == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
                      onPressed: () async {
                        final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                        if (f != null) setState(() => _proof = f);
                      },
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpace.lg),
              AppButton.primary(
                expand: true,
                size: AppButtonSize.lg,
                label: plan == null
                    ? 'sub_choose_plan'.tr
                    : (plan.isFree ? 'sub_activate_free'.tr : 'sub_send_request'.tr),
                busy: busy,
                onPressed: plan == null ? null : () => _submit(p),
              ),
              const SizedBox(height: AppSpace.xs),
              ParentComponent(
                featureKey: 'subscription.logout',
                child: Center(
                  child: AppButton.ghost(
                    label: 'sub_logout'.tr,
                    onPressed: () => context.read<ProfileProvider>().logout(context),
                  ),
                ),
              ),
            ]),
          ),
        ],
      );
    }

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppHeader(
          title: 'sub_title'.tr,
          showBack: Navigator.of(context).canPop(),
          actions: [AppRefreshAction(onRefresh: p.load), const HelpInfoButton(pageId: 'account.subscription')],
        ),
        // redesign S-D (Stu2Money `screen=subscribe`): the money hero over the plans and the request's state
        body: SdHeroColumn(
          title: 'sub_title'.tr,
          subtitle: 'sd_sub_sub'.tr,
          icon: Icons.workspace_premium_outlined,
          child: p.loaded ? AppRefresh(onRefresh: p.load, scrollable: scrollable, child: body) : body,
        ),
      ),
    );
  }
}

/// The paywall's opening block: the one tinted surface of the page (peach), the editorial title, who asks for the
/// subscription and, after a rejection, why — in the danger tone made legible on the block.
class _Intro extends StatelessWidget {
  const _Intro({required this.title, this.hint, this.rejected});

  final String title;
  final String? hint, rejected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBlock(
      tone: AppBlockTone.peach,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.workspace_premium_rounded, size: AppIconSize.xl, color: b.accentInk(c.primary)),
          const SizedBox(height: AppSpace.sm),
          Semantics(header: true, child: Text(title, style: AppType.headline(context).copyWith(color: b.ink))),
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(hint!, style: AppType.body(context).copyWith(color: b.muted)),
          ],
          if (rejected != null) ...[
            const SizedBox(height: AppSpace.sm),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_rounded, size: AppIconSize.sm, color: b.accentInk(c.danger)),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(rejected!, style: AppType.label(context).copyWith(color: b.accentInk(c.danger)))),
            ]),
          ],
        ]);
      }),
    );
  }
}

/// One plan as a radio card: paper on a hairline, the chosen one ringed in the primary with a filled mark; the
/// price is the row's figure (tabular, in ink), the length a meta line under the name.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isAr, required this.selected, required this.onTap});

  final SubPlan plan;
  final bool isAr, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: AppPressScale(
        child: AnimatedContainer(
          duration: motion.fast,
          curve: AppEase.out,
          decoration: BoxDecoration(
            color: selected ? appTintOn(context, c.primary, surface: c.cardBg) : c.cardBg,
            borderRadius: AppRadius.cardAll,
            border: Border.all(
              color: selected ? c.primary : c.divider,
              width: selected ? AppBorder.focus : AppBorder.hairline,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.cardAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.primary),
                child: Padding(
                  padding: AppSpace.card,
                  child: Row(children: [
                    Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: AppIconSize.lg, color: selected ? c.primary : c.textLight),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(isAr ? plan.nameAr : plan.nameEn,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                        const SizedBox(height: AppSpace.xxs / 2),
                        Text('${plan.durationDays} ${'sub_days'.tr}', style: AppType.meta(context)),
                      ]),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Text(plan.isFree ? 'sub_free'.tr : money(plan.price, plan.currency),
                        maxLines: 1, style: AppType.figure(context)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of the transfer details: the label in meta, the value in the row face (copyable; IBAN and ids LTR).
class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.ltr = false, this.strong = false, this.last = false});

  final String label, value;
  final bool ltr, strong, last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: Text(label, style: AppType.meta(context))),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            flex: 5,
            child: SelectableText(
              value,
              textDirection: ltr ? TextDirection.ltr : null,
              textAlign: ltr && Directionality.of(context) == TextDirection.rtl ? TextAlign.end : TextAlign.start,
              style: strong ? AppType.bodyStrong(context) : AppType.row(context),
            ),
          ),
        ]),
      ),
      if (!last) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
    ]);
  }
}

/// A full-page state (active, under review, paused, nothing to buy): the drawn plate in the state's tone, an
/// editorial headline, one line of direction and ONE action.
class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.action,
    this.tone = AppBlockTone.peach,
  });
  final IconData icon;
  final Color accent;
  final AppBlockTone tone;
  final String title;
  final String subtitle;
  final Widget action;

  /// The comfortable measure of the state's text.
  static const double _measure = 420;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _measure),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppStatePlate(icon: icon, tone: tone, accent: accent),
            const SizedBox(height: AppSpace.lg),
            Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: AppType.headline(context))),
            const SizedBox(height: AppSpace.xs),
            Text(subtitle, textAlign: TextAlign.center, style: AppType.body(context)),
            const SizedBox(height: AppSpace.lg),
            action,
          ]),
        ),
      ),
    );
  }
}
