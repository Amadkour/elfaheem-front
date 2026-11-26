// lib/features/parent/student_link_code_screen.dart
// Student: generate the temporary single-use code a parent needs, share / copy it, see the parents already linked
// (and unlink one). Redesign S-D (Stu2Profile `screen=parent`): the hero "اربط ولي أمرك", the code as six boxes that
// pop in (M3), the time left as two rolling boxes (M10), ONE filled button "أرسله له" beside "رمز جديد", three icon
// rows of what the parent does, and the linked parents card.
//
//   StudentLinkCodeScreen   the page (opened from the student's profile, kill switch `profile.parent_link`)
//   StudentLinkCodeView     the body with plain values (test/ui/sd_link_code_layout_test.dart)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';
import 'package:flutter_education_app/features/parent/parent_widgets.dart' show plToast;
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class StudentLinkCodeScreen extends StatelessWidget {
  const StudentLinkCodeScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => StudentLinkProvider()..load(),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // the code hides itself when its time is up
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StudentLinkProvider>();
    Future<void> generate() async {
      final ok = await p.generate();
      if (!ok) plToast(p.errorMessage);
    }

    return SdArea(
      area: AppArea.me,
      child: BasePage(
        appBar: ScreenAppBar(title: 'sd_profile_parent_link'.tr),
        child: AppRefresh(
          onRefresh: p.load,
          child: StudentLinkCodeView(
            code: p.codeVisible ? p.code : null,
            secondsLeft: p.secondsLeft,
            hasActive: p.hasActive,
            busy: p.isLoading,
            parents: [for (final e in p.parents) (id: e['link_id'] as int, name: '${e['name'] ?? ''}')],
            onGenerate: generate,
            onShare: () => SharePlus.instance.share(ShareParams(text: '${'pl_share_text'.tr}\n${p.code!}')),
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: p.code!));
              showAppNotice('pl_copied'.tr);
            },
            onUnlink: (id) async {
              final ok = await appConfirm(context, message: 'sd_link_unlink_ask'.tr, danger: true, confirmLabel: 'pl_unlink'.tr);
              if (ok && context.mounted) {
                final done = await p.unlink(id);
                if (!done) plToast(p.errorMessage);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// A linked parent: the link's id and the parent's name.
typedef LinkedParent = ({int id, String name});

class StudentLinkCodeView extends StatelessWidget {
  const StudentLinkCodeView({
    super.key,
    required this.code,
    required this.secondsLeft,
    required this.parents,
    this.hasActive = false,
    this.busy = false,
    this.onGenerate,
    this.onShare,
    this.onCopy,
    this.onUnlink,
  });

  /// The code while it can still be used; null = no code shown.
  final String? code;
  final int secondsLeft;

  /// A code exists but is hidden (made on another device).
  final bool hasActive;
  final bool busy;
  final List<LinkedParent> parents;
  final VoidCallback? onGenerate, onShare, onCopy;
  final ValueChanged<int>? onUnlink;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final shown = code;
    final card = AppCard(
      key: const ValueKey('link.card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (shown != null) ...[
          Text('sd_link_give'.tr, textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: c.textMedium)),
          const SizedBox(height: AppSpace.sm),
          Semantics(
            label: shown.split('').join(' '),
            excludeSemantics: true,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final (i, ch) in shown.split('').indexed)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                      child: AppPop(
                        delay: Duration(milliseconds: 200 + 70 * i),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: AppTouch.primary),
                          height: AppTouch.primary,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: set.tint,
                            borderRadius: BorderRadius.circular(AppRadius.tile),
                            border: Border.all(color: Color.lerp(set.tint, set.a, .25)!, width: AppBorder.strong),
                          ),
                          child: FittedBox(
                            child: Text(appDigits(ch), style: AppType.headline(context).copyWith(color: set.ink)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              Text('sd_link_ends_in'.tr, style: AppType.label(context).copyWith(color: c.textMedium)),
              AppCountdown(until: DateTime.now().toUtc().add(Duration(seconds: secondsLeft))),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(alignment: WrapAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            AppButton.primary(
              key: const ValueKey('link.share'),
              label: 'sd_link_send'.tr,
              icon: Icons.share_outlined,
              onPressed: onShare,
            ),
            AppButton.secondary(
              key: const ValueKey('link.new'),
              label: 'pl_new_code'.tr,
              busy: busy,
              onPressed: busy ? null : onGenerate,
            ),
            AppButton.ghost(key: const ValueKey('link.copy'), label: 'pl_copy'.tr, icon: Icons.copy_rounded, onPressed: onCopy),
          ]),
        ] else ...[
          AppEmpty(
            icon: hasActive ? Icons.hourglass_bottom_rounded : Icons.key_outlined,
            title: hasActive ? 'pl_code_hidden'.tr : 'pl_no_active_code'.tr,
            actionLabel: 'pl_generate_code'.tr,
            onAction: busy ? null : onGenerate,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        AppRules(items: [
          (icon: Icons.phone_iphone_rounded, text: 'sd_link_step1'.tr),
          (icon: Icons.link_rounded, text: 'sd_link_step2'.tr),
          (icon: Icons.vpn_key_outlined, text: 'sd_link_step3'.tr),
        ]),
      ]),
    );
    final linked = AppCard(
      key: const ValueKey('link.parents'),
      title: 'sd_link_linked'.tr,
      child: parents.isEmpty
          ? Text('pl_no_parents'.tr, style: AppType.body(context).copyWith(color: c.textMedium))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, e) in parents.indexed) ...[
                if (i > 0) Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: c.kit.line),
                Row(children: [
                  _Initial(name: e.name, index: i),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context))),
                  AppButton.ghost(
                    key: ValueKey('link.unlink.${e.id}'),
                    label: 'sd_link_unlink'.tr,
                    size: AppButtonSize.sm,
                    onPressed: onUnlink == null ? null : () => onUnlink!(e.id),
                  ),
                ]),
              ],
            ]),
    );
    return SdHeroList(
      hero: AppHero(title: 'sd_link_title'.tr, subtitle: 'sd_link_sub'.tr, icon: Icons.family_restroom_rounded),
      width: AppWidth.form,
      children: [card, const SizedBox(height: AppSpace.md), linked],
    );
  }
}

/// A parent's initial on a soft accent circle (never a photo).
class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.index});

  final String name;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.kit.accent(index.isEven ? AppAccent.sky : AppAccent.grape);
    final n = name.trim();
    return ExcludeSemantics(
      child: Container(
        width: AppDashSize.glyph,
        height: AppDashSize.glyph,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle),
        child: Text(n.isEmpty ? '؟' : n.characters.first, style: AppType.section(context).copyWith(color: context.colors.onHero)),
      ),
    );
  }
}
