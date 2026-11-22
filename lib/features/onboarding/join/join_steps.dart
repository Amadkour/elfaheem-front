// lib/features/onboarding/join/join_steps.dart — the join flow's look (Learning Hub F5, D-1323): ONE calm page per
// question, the step's headline in the editorial role, a thin progress rule, Back and Next at the bottom.
//
//   JoinStep       role → country → levels → delivery → area → contact → confirm
//   JoinFlowView   plain values in (the draft, the countries, the catalog, an area loader), callbacks out; no
//                  provider and no request, so the layout harness pumps every step with fake data
//   JoinOptionCard a large selectable card (role, delivery)
//
// The levels reuse `EduStageGradePicker` (a student, a parent's child) and `TeachingLevelsStep` (a teacher); the area
// reuses `EduAreaPicker` with its optional street address.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:flutter_education_app/features/auth/register_levels_step.dart' show ContactOnlyNote, TeachingLevelsStep;

import 'join_draft.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

enum JoinStep { role, country, levels, delivery, area, contact, confirm }

/// The steps a draft walks through: an online-only learner has no area to pick.
List<JoinStep> joinStepsFor(JoinDraft d) => [
      for (final s in JoinStep.values)
        if (s != JoinStep.area || d.delivery != 'online') s,
    ];

String joinRoleName(String role) => switch (role) {
      'teacher' => _t('معلم', 'Teacher'),
      'parent' => _t('ولي أمر', 'Parent'),
      _ => _t('طالب', 'Student'),
    };

String joinDeliveryName(String? d) => switch (d) {
      'online' => _t('أونلاين', 'Online'),
      'in_person' => _t('حضوري في مركز', 'In person, at a centre'),
      _ => _t('أيهما', 'Either'),
    };

/// A large selectable card: an icon well, a title and one line, a check when chosen. 48 px+ target.
class JoinOptionCard extends StatelessWidget {
  const JoinOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: [title, ?subtitle].join('. '),
      child: ExcludeSemantics(
        child: Material(
          color: selected ? c.primaryTint : c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(
                color: selected ? c.primary : c.controlEdge, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(
                  children: [
                    Container(
                      width: AppTouch.min,
                      height: AppTouch.min,
                      decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.controlAll),
                      child: Icon(icon, size: AppIconSize.lg, color: c.primary),
                    ),
                    AppSpace.gapMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: AppType.section(context)),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpace.xxs),
                            Text(subtitle!, style: AppType.meta(context)),
                          ],
                        ],
                      ),
                    ),
                    AppSpace.gapSm,
                    Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: AppIconSize.lg, color: selected ? c.primary : c.textLight),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One step on screen. Every value comes in; [onEdit] runs a change on the draft and repaints.
class JoinFlowView extends StatelessWidget {
  const JoinFlowView({
    super.key,
    required this.step,
    required this.draft,
    required this.onEdit,
    required this.onBack,
    required this.onNext,
    required this.loadAreas,
    required this.address,
    required this.name,
    required this.phone,
    required this.childCode,
    this.countries = const [],
    this.catalog,
    this.catalogLoading = false,
    this.busy = false,
    this.onSkip,
    this.onGoTo,
    this.onSecondary,
    this.onLinkChild,
  });

  final JoinStep step;
  final JoinDraft draft;
  final void Function(void Function() change) onEdit;
  final VoidCallback? onBack;

  /// Next; on the confirm step, the flow's main action.
  final VoidCallback? onNext;

  /// "Skip" under an optional step (area, contact).
  final VoidCallback? onSkip;

  /// The confirm step's "Edit" on one answer.
  final ValueChanged<JoinStep>? onGoTo;

  /// The confirm step's second action (create an account / browse).
  final VoidCallback? onSecondary;

  /// A signed-in parent's "Link my child" on the confirm step.
  final VoidCallback? onLinkChild;

  final List<EduCountry> countries;
  final EduCountryCatalog? catalog;
  final bool catalogLoading, busy;
  final EduAreaLoader loadAreas;
  final TextEditingController address, name, phone, childCode;

  List<JoinStep> get _steps => joinStepsFor(draft);

  bool get canNext => switch (step) {
        JoinStep.country => countries.isEmpty || draft.country != null,
        JoinStep.levels => catalogLoading ? false : ((catalog?.isEmpty ?? true) || draft.hasLevels),
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = _steps;
    final at = steps.indexOf(step).clamp(0, steps.length - 1);
    final (title, subtitle) = _heading();
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
              child: Row(
                children: [
                  if (onBack != null) AppBackButton(onPressed: onBack) else const SizedBox(width: AppTouch.min),
                  AppSpace.gapSm,
                  Expanded(
                    child: Semantics(
                      label: _t('الخطوة ${at + 1} من ${steps.length}', 'Step ${at + 1} of ${steps.length}'),
                      child: ClipRRect(
                        borderRadius: AppRadius.chipAll,
                        child: LinearProgressIndicator(
                          value: (at + 1) / steps.length,
                          minHeight: AppSpace.xxs,
                          color: c.primary,
                          backgroundColor: c.divider,
                        ),
                      ),
                    ),
                  ),
                  AppSpace.gapSm,
                  Text('${at + 1}/${steps.length}', style: AppType.meta(context)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSpace.gapSm,
                        Semantics(header: true, child: Text(title, style: AppType.display(context))),
                        AppSpace.gapXs,
                        Text(subtitle, style: AppType.body(context)),
                        AppSpace.gapLg,
                        _body(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                    child: _actions(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, String) _heading() {
    final d = draft;
    return switch (step) {
      JoinStep.role => (
          _t('أهلًا بك! من أنت؟', 'Welcome! Who are you?'),
          _t('نجهّز لك ما يناسبك في أقل من دقيقة.', 'We set things up for you in under a minute.'),
        ),
      JoinStep.country => (
          d.isTeacher ? _t('أين تدرّس؟', 'Where do you teach?') : _t('في أي دولة؟', 'Which country?'),
          _t('المراحل والمناطق تختلف من دولة لأخرى.', 'Stages and areas differ from one country to another.'),
        ),
      JoinStep.levels => d.isTeacher
          ? (
              _t('ماذا تدرّس؟', 'What do you teach?'),
              _t('اختر المراحل، أو صفوفًا بعينها منها.', 'Pick the stages, or particular grades in them.'),
            )
          : d.isParent
              ? (
                  _t('في أي صف ابنك أو ابنتك؟', "Your child's stage and grade"),
                  _t('نعرض الدورات المناسبة لهذا الصف.', 'We show the courses for that grade.'),
                )
              : (
                  _t('في أي صف أنت؟', 'Your stage and grade'),
                  _t('نعرض الدورات المناسبة لصفّك.', 'We show the courses for your grade.'),
                ),
      JoinStep.delivery => (
          d.isTeacher ? _t('كيف تدرّس؟', 'How do you teach?') : _t('كيف تفضّل الدراسة؟', 'How do you want to learn?'),
          _t('يمكنك تغيير ذلك لاحقًا من الفلاتر.', 'You can change this later in the filters.'),
        ),
      JoinStep.area => (
          _t('أين أنت؟', 'Where are you?'),
          _t('لنعرض المراكز والدورات القريبة منك. العنوان اختياري.',
              'So we can show centres and courses near you. The address is optional.'),
        ),
      JoinStep.contact => (
          _t('كيف نناديك؟', 'What should we call you?'),
          _t('اختياري: نملأ بها حسابك عند إنشائه.', 'Optional: we fill your account with it when you create it.'),
        ),
      JoinStep.confirm => (
          _t('كل شيء جاهز', 'All set'),
          _t('راجع اختياراتك، ويمكنك تعديل أي منها.', 'Check your choices; you can change any of them.'),
        ),
    };
  }

  Widget _body(BuildContext context) => switch (step) {
        JoinStep.role => _roleBody(),
        JoinStep.country => _countryBody(context),
        JoinStep.levels => _levelsBody(context),
        JoinStep.delivery => _deliveryBody(),
        JoinStep.area => _areaBody(),
        JoinStep.contact => _contactBody(),
        JoinStep.confirm => _confirmBody(context),
      };

  Widget _column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) AppSpace.gapSm, children[i]],
        ],
      );

  Widget _roleBody() => _column([
        for (final (role, icon, sub) in [
          ('student', Icons.school_rounded, _t('أبحث عن دورات لصفّي', 'I look for courses for my grade')),
          ('parent', Icons.family_restroom_rounded, _t('أتابع ابني أو ابنتي', 'I follow my child')),
          ('teacher', Icons.co_present_rounded, _t('أدرّس وأنشر دوراتي', 'I teach and publish my courses')),
        ])
          JoinOptionCard(
            key: ValueKey('join.role.$role'),
            icon: icon,
            title: joinRoleName(role),
            subtitle: sub,
            selected: draft.role == role,
            onTap: () => onEdit(() => draft.role = role),
          ),
      ]);

  Widget _countryBody(BuildContext context) {
    if (countries.isEmpty) {
      return Text(_t('سنستخدم دولتك الافتراضية.', 'We use your default country.'), style: AppType.meta(context));
    }
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        for (final e in countries)
          AppChoiceChip(
            key: ValueKey('join.country.${e.code}'),
            label: e.name,
            selected: draft.country == e.code,
            onTap: () => onEdit(() => draft.setCountry(e.code)),
          ),
      ],
    );
  }

  Widget _levelsBody(BuildContext context) {
    if (catalogLoading) return const AppListSkeleton(items: 3, withAvatar: false);
    final stages = catalog?.stages ?? const <EduStage>[];
    if (draft.isTeacher) {
      return TeachingLevelsStep(
        stages: stages,
        selected: draft.teachingLevels,
        onChanged: (v) => onEdit(() => draft.teachingLevels = [...v]),
      );
    }
    final stage = catalog?.stage(draft.stageId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EduStageGradePicker(
          stages: stages,
          stageId: draft.stageId,
          gradeId: draft.gradeId,
          trackKey: draft.trackKey,
          onChanged: (s, g, tr) => onEdit(() {
            draft.stageId = s;
            draft.gradeId = g;
            draft.trackKey = tr;
          }),
        ),
        if (stage != null && stage.contactOnly) ...[AppSpace.gapMd, const ContactOnlyNote()],
      ],
    );
  }

  Widget _deliveryBody() => _column([
        for (final (d, icon, sub) in [
          ('online', Icons.laptop_chromebook_rounded, _t('مباشر أو مسجّل، من أي مكان', 'Live or recorded, from anywhere')),
          ('in_person', Icons.location_city_rounded, _t('في مركز قريب منك', 'At a centre near you')),
          (null, Icons.all_inclusive_rounded, _t('أرني كل شيء', 'Show me everything')),
        ])
          JoinOptionCard(
            key: ValueKey('join.delivery.${d ?? 'any'}'),
            icon: icon,
            title: joinDeliveryName(d),
            subtitle: sub,
            selected: draft.delivery == d,
            onTap: () => onEdit(() {
              draft.delivery = d;
              if (d == 'online') draft.area1 = draft.area2 = null;
            }),
          ),
      ]);

  Widget _areaBody() => EduAreaPicker(
        loadAreas: loadAreas,
        level1: draft.area1,
        level2: draft.area2,
        labels: catalog?.geoLabels ?? const EduGeoLabels(),
        address: address,
        onChanged: (a1, a2) => onEdit(() {
          draft.area1 = a1;
          draft.area2 = a2;
        }),
      );

  Widget _contactBody() => _column([
        AppField(
          key: const ValueKey('join.name'),
          controller: name,
          label: _t('الاسم', 'Name'),
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
        AppField(
          key: const ValueKey('join.phone'),
          controller: phone,
          label: _t('رقم الهاتف', 'Phone number'),
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          ltr: true,
        ),
        if (draft.isParent)
          AppField(
            key: const ValueKey('join.child_code'),
            controller: childCode,
            label: _t('كود ابنك أو ابنتك (اختياري)', "Your child's code (optional)"),
            helper: _t('تجده في تطبيق الطالب: الملف الشخصي ‹ ولي الأمر.', "In the student's app: Profile › Parent."),
            icon: Icons.link_rounded,
            ltr: true,
          ),
      ]);

  String _levelsText() {
    final cat = catalog;
    if (draft.isTeacher) {
      if (draft.teachingLevels.isEmpty) return '—';
      return [
        for (final l in draft.teachingLevels)
          l.gradeId == null
              ? (cat?.stage(l.stageId)?.name ?? '')
              : (cat?.grade(l.gradeId)?.name ?? ''),
      ].where((s) => s.isNotEmpty).join(_t('، ', ', '));
    }
    final parts = [cat?.stage(draft.stageId)?.name, cat?.grade(draft.gradeId)?.name].whereType<String>();
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  String _countryText() {
    for (final e in countries) {
      if (e.code == draft.country) return e.name;
    }
    return draft.country ?? '—';
  }

  String _areaText() {
    final a = [draft.area2?.name, draft.area1?.name].whereType<String>().join(_t('، ', ', '));
    final addr = address.text.trim();
    final text = [if (a.isNotEmpty) a, if (addr.isNotEmpty) addr].join(' — ');
    return text.isEmpty ? '—' : text;
  }

  Widget _confirmBody(BuildContext context) {
    final contact = [name.text.trim(), phone.text.trim()].where((s) => s.isNotEmpty).join(' · ');
    final steps = _steps;
    final rows = <(JoinStep, IconData, String, String)>[
      (JoinStep.role, Icons.badge_outlined, _t('أنا', 'I am'), joinRoleName(draft.role)),
      (JoinStep.country, Icons.public_rounded, _t('الدولة', 'Country'), _countryText()),
      (
        JoinStep.levels,
        Icons.stairs_outlined,
        draft.isTeacher ? _t('أدرّس', 'I teach') : _t('الصف', 'Grade'),
        _levelsText()
      ),
      (JoinStep.delivery, Icons.laptop_chromebook_rounded, _t('طريقة الدراسة', 'How'), joinDeliveryName(draft.delivery)),
      if (steps.contains(JoinStep.area)) (JoinStep.area, Icons.location_on_outlined, _t('المنطقة', 'Area'), _areaText()),
      (JoinStep.contact, Icons.person_outline_rounded, _t('الاسم والهاتف', 'Name and phone'), contact.isEmpty ? '—' : contact),
    ];
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            _SummaryRow(
              icon: rows[i].$2,
              label: rows[i].$3,
              value: rows[i].$4,
              onEdit: onGoTo == null ? null : () => onGoTo!(rows[i].$1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    if (step == JoinStep.confirm) {
      final primaryLabel = draft.isTeacher
          ? _t('أنشئ حساب المعلم', 'Create my teacher account')
          : _t('اعرض الدورات المناسبة', 'Show my courses');
      final secondaryLabel = draft.isTeacher
          ? _t('تصفّح الدورات', 'Browse courses')
          : _t('أنشئ حسابًا', 'Create an account');
      return AppButtonRow(
        primary: AppButton.primary(
          key: const ValueKey('join.finish'),
          label: primaryLabel,
          icon: draft.isTeacher ? Icons.person_add_alt_1_rounded : Icons.search_rounded,
          busy: busy,
          onPressed: busy ? null : onNext,
        ),
        secondary: [
          if (onLinkChild != null)
            AppButton.tonal(
                key: const ValueKey('join.link_child'),
                label: _t('اربط ابني', 'Link my child'),
                icon: Icons.link_rounded,
                onPressed: busy ? null : onLinkChild),
          if (onSecondary != null)
            AppButton.ghost(key: const ValueKey('join.secondary'), label: secondaryLabel, onPressed: busy ? null : onSecondary),
        ],
      );
    }
    final optional = step == JoinStep.area || step == JoinStep.contact;
    return AppButtonRow(
      primary: AppButton.primary(
        key: const ValueKey('join.next'),
        label: _t('التالي', 'Next'),
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: canNext ? onNext : null,
      ),
      secondary: [
        if (optional && onSkip != null)
          AppButton.ghost(key: const ValueKey('join.skip'), label: _t('تخطَّ', 'Skip'), onPressed: onSkip),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label, required this.value, this.onEdit});

  final IconData icon;
  final String label, value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.md, color: c.textMedium),
            AppSpace.gapSm,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppType.meta(context)),
                    Text(value, style: AppType.row(context), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: _t('تعديل: $label', 'Edit: $label'),
                icon: Icon(Icons.edit_outlined, size: AppIconSize.md, color: c.primary),
                onPressed: onEdit,
              ),
          ],
        ),
      ),
    );
  }
}
