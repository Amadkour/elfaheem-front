// lib/features/parent/signup/pa_join_child_fields.dart — the parent's "create your child's account" fields in the join
// flow's last step (Pa2Gate `screen=contact`). The join flow (S-A, lib/features/onboarding/join/) shows this widget
// under the child-code field through its `parentExtra` slot; the grade and the study mode come from the flow's own
// answers. Nothing is sent here: the details wait in [PaChildDraft] until the parent has a session, and the parent
// dashboard sends them and shows the child's sign-in code (pa_child_code_page.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'pa_child_api.dart';

class PaJoinChildFields extends StatefulWidget {
  const PaJoinChildFields({
    super.key,
    required this.country,
    required this.stageId,
    required this.gradeId,
    this.track,
    this.delivery,
  });

  /// The join flow's answers (the child's curriculum country, grade and study mode).
  final String? country;
  final int? stageId, gradeId;
  final String? track, delivery;

  @override
  State<PaJoinChildFields> createState() => _PaJoinChildFieldsState();
}

class _PaJoinChildFieldsState extends State<PaJoinChildFields> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  String? _gender;

  @override
  void initState() {
    super.initState();
    PaChildDraft.load().then((d) {
      if (d == null || !mounted) return;
      setState(() {
        _first.text = d.firstName;
        _last.text = d.lastName;
        _gender = d.gender;
      });
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _save() => PaChildDraft(
        firstName: _first.text,
        lastName: _last.text,
        country: widget.country,
        stageId: widget.stageId,
        gradeId: widget.gradeId,
        track: widget.track,
        delivery: widget.delivery,
        gender: _gender,
      ).save();

  @override
  Widget build(BuildContext context) {
    if (!paCreateChildOn()) return const SizedBox.shrink();
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Container(
      key: const ValueKey('pa.join.child'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: Color.lerp(set.tint, set.a, .3)!, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const AppIconBox(icon: Icons.person_add_alt_1_rounded),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text('pa_join_child_title'.tr, style: AppType.tileTitle(context))),
          AppStatusBadge(label: 'pa_optional'.tr),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text('pa_join_child_hint'.tr, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.sm),
        AppField(
          key: const ValueKey('pa.join.child.first'),
          controller: _first,
          label: 'pa_child_first_name'.tr,
          icon: Icons.person_outline_rounded,
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(
          key: const ValueKey('pa.join.child.last'),
          controller: _last,
          label: 'pa_child_last_name'.tr,
          icon: Icons.badge_outlined,
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final g in const ['m', 'f'])
            AppChip(
              key: ValueKey('pa.join.child.gender.$g'),
              label: 'pa_gender_$g'.tr,
              selected: _gender == g,
              onTap: () {
                setState(() => _gender = _gender == g ? null : g);
                _save();
              },
            ),
        ]),
      ]),
    );
  }
}

