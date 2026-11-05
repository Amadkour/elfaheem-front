// lib/features/org/advising/adv_setup_page.dart — the Academic Advising page of the org dashboard (Services →
// Academic advising) for org admins and advising directors (Phase 2, docs/advising/PHASE2.md):
//   not eligible  → why ("available to universities, faculties and the units under them")
//   off           → what it brings + Enable (org admin): pick the department that leads it, or create one
//   on            → the leading department, the director(s), my role, the counts (admins / directors), the way
//                   into the pages (manage: Workspace · Settings · Advisors · Distribute · Students · Categories; an
//                   advisor: My students · My profile · Handovers; the workspace tile carries the urgent / overdue
//                   flag counts) and Turn off in More (org admin, `appConfirm`; every record is kept)
// `AdvSetupView` and `AdvEnableForm` take plain values (test/ui/adv_layout_test.dart); `AdvSetupPage` loads and
// calls `AdvApi`. Refresh comes from the dashboard header (the page is re-keyed).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall, orgErrorText;
import 'adv_advisors_page.dart';
import 'adv_api.dart';
import 'adv_categories_page.dart';
import 'adv_config_page.dart';
import 'adv_distribute_page.dart';
import 'adv_handovers_page.dart';
import 'adv_models.dart';
import 'adv_students_page.dart';
import 'adv_workspace_page.dart';

/// What the page shows.
enum AdvSetupState { loading, failed, unavailable, off, on }

/// The state of the page from what it holds (pure).
AdvSetupState advSetupState({AdvStatus? status, bool failed = false}) {
  if (status == null) return failed ? AdvSetupState.failed : AdvSetupState.loading;
  if (status.enabled) return AdvSetupState.on;
  return status.eligible ? AdvSetupState.off : AdvSetupState.unavailable;
}

/// The page's content (plain values).
class AdvSetupView extends StatelessWidget {
  const AdvSetupView({
    super.key,
    required this.state,
    this.status,
    this.deptName,
    this.errorText,
    this.busy = false,
    this.onRetry,
    this.onEnable,
    this.onDisable,
    this.onOpen,
  });

  final AdvSetupState state;
  final AdvStatus? status;

  /// The name of the department that leads advising (null: not known yet).
  final String? deptName;
  final String? errorText;

  /// A switch-on / switch-off call is running.
  final bool busy;
  final VoidCallback? onRetry, onEnable, onDisable;

  /// Opens a Phase 3 page: `settings` · `advisors` · `distribute` · `rebalance` · `students` · `students_away` ·
  /// `profile` · `handovers` (null: the links are left out).
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = status;
    switch (state) {
      case AdvSetupState.loading:
        return Semantics(
          label: t('جارٍ التحميل', 'Loading'),
          child: const Align(alignment: Alignment.topCenter, child: AppListSkeleton(items: 4, withAvatar: false)),
        );
      case AdvSetupState.failed:
        return AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: t('تعذّر تحميل الإرشاد الأكاديمي', 'Could not load academic advising'),
          message: errorText,
          actionLabel: onRetry == null ? null : t('إعادة المحاولة', 'Retry'),
          onAction: onRetry,
        );
      case AdvSetupState.unavailable:
        return AppEmpty(
          icon: Icons.domain_disabled_rounded,
          title: t('الإرشاد الأكاديمي غير متاح هنا', 'Academic advising isn\'t available here'),
          message: s?.reasonText ?? advReasonText(null),
        );
      case AdvSetupState.off:
      case AdvSetupState.on:
        break;
    }
    final st = s ?? const AdvStatus();
    final on = state == AdvSetupState.on;
    final manage = st.canManage && !busy;
    return OrgPageBody(
      primary: !on && manage && onEnable != null
          ? OrgPrimaryAction(icon: Icons.power_settings_new_rounded, label: t('تفعيل الإرشاد الأكاديمي', 'Turn on academic advising'), onTap: onEnable!)
          : null,
      more: [
        if (on && manage && onDisable != null)
          OrgMenuItem(icon: Icons.pause_circle_outline_rounded, label: t('إيقاف الإرشاد الأكاديمي', 'Turn off academic advising'), danger: true, onTap: onDisable!),
      ],
      child: LayoutBuilder(builder: (context, box) {
        // phones: room under the content for the floating primary action
        final fab = !on && manage && onEnable != null && box.maxWidth < orgPageWideFrom;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, fab ? AppSpace.xxl + AppTouch.primary : AppSpace.xl),
              children: on ? _onContent(context, st) : _offContent(context, st),
            ),
          ),
        );
      }),
    );
  }

  List<Widget> _offContent(BuildContext context, AdvStatus st) {
    final c = context.colors;
    return [
      if (busy) const _BusyStrip(),
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Medallion(icon: Icons.co_present_rounded, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(header: true, child: Text(t('الإرشاد الأكاديمي', 'Academic advising'), style: AppType.section(context))),
                const SizedBox(height: AppSpace.xxs),
                AppBadgePill(t('غير مفعّل', 'Off'), color: c.textMedium, icon: Icons.pause_rounded),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          Text(
            t('لكل طالب مرشد أكاديمي يتابعه، وسجلات الإرشاد كلها في مكان واحد.',
                'Every student gets an academic advisor who follows them, with every advising record in one place.'),
            style: AppType.body(context),
          ),
          const SizedBox(height: AppSpace.md),
          _Benefit(
            icon: Icons.account_tree_rounded,
            text: t('إدارة الإرشاد الأكاديمي تقود العمل، ورئيسها هو مدير الإرشاد.',
                'An Academic Advising department leads the work; its head is the advising director.'),
          ),
          _Benefit(
            icon: Icons.how_to_reg_rounded,
            text: t('المرشدون المختارون في التسجيل يبقون مرشدين لطلابهم.',
                'Advisors already chosen in the registrar stay their students\' advisors.'),
          ),
          _Benefit(
            icon: Icons.history_rounded,
            text: t('الإيقاف لاحقاً يحتفظ بكل السجلات.', 'Turning it off later keeps every record.'),
          ),
        ]),
      ),
      if (!st.canManage) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.info_outline_rounded, text: t('يفعّل مدير المؤسسة الإرشاد الأكاديمي.', 'The organization admin switches academic advising on.')),
      ],
    ];
  }

  List<Widget> _onContent(BuildContext context, AdvStatus st) {
    final c = context.colors;
    final counts = st.counts;
    final me = st.me;
    final dept = deptName ?? t('إدارة الإرشاد الأكاديمي', 'Academic Advising department');
    return [
      if (busy) const _BusyStrip(),
      AppCard(
        padding: AppSpace.card,
        child: Row(children: [
          _Medallion(icon: Icons.co_present_rounded, color: c.success),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(t('الإرشاد الأكاديمي مفعّل', 'Academic advising is on'), style: AppType.section(context))),
              const SizedBox(height: AppSpace.xxs),
              Text(t('تقوده: $dept', 'Led by: $dept'), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppBadgePill(t('مفعّل', 'On'), color: c.success, icon: Icons.check_rounded),
                if (me.role != 'none') AppBadgePill(me.roleLabel, color: c.primary, icon: Icons.badge_outlined),
              ]),
            ]),
          ),
        ]),
      ),
      if (me.advisor) ...[
        const SizedBox(height: AppSpace.sm),
        AppCard(
          padding: AppSpace.card,
          child: Row(children: [
            Icon(Icons.groups_rounded, color: c.primary, size: AppIconSize.md),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                me.advisees == 0
                    ? t('لم يُسند إليك طلاب بعد.', 'No students are assigned to you yet.')
                    : countText(me.advisees,
                        ar1: 'ترشد طالباً واحداً', ar2: 'ترشد طالبين', arFew: 'ترشد ${me.advisees} طلاب', arMany: 'ترشد ${me.advisees} طالباً',
                        en1: 'You advise 1 student', en: 'You advise ${me.advisees} students'),
                style: AppType.row(context),
              ),
            ),
          ]),
        ),
      ],
      if (counts != null) ...[
        _SectionTitle(t('نظرة سريعة', 'At a glance')),
        // four tiles: one row of 4 when there is room, else 2 × 2 (never 3 + 1 or a gap at the end)
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 560 ? 4 : 2;
          return AppGrid(
            minTile: (box.maxWidth - AppSpace.sm * (cols - 1)) / cols,
            spacing: AppSpace.sm,
            padding: EdgeInsets.zero,
            children: [
              _Stat(icon: Icons.school_rounded, label: t('الطلاب', 'Students'), value: counts.students, color: c.primary),
              _Stat(icon: Icons.how_to_reg_rounded, label: t('لهم مرشد', 'With an advisor'), value: counts.assigned, color: c.success),
              _Stat(icon: Icons.person_search_rounded, label: t('بلا مرشد', 'Without an advisor'), value: counts.unassigned,
                  color: counts.unassigned > 0 ? c.warning : c.textMedium),
              _Stat(icon: Icons.supervisor_account_rounded, label: t('المرشدون', 'Advisors'), value: counts.advisors, color: c.primary),
            ],
          );
        }),
        const SizedBox(height: AppSpace.sm),
        _Coverage(counts: counts),
        if (counts.unassigned > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.person_search_rounded,
            color: c.warning,
            text: countText(counts.unassigned,
                ar1: 'طالب واحد بلا مرشد أكاديمي بعد', ar2: 'طالبان بلا مرشد أكاديمي بعد',
                arFew: '${counts.unassigned} طلاب بلا مرشد أكاديمي بعد', arMany: '${counts.unassigned} طالباً بلا مرشد أكاديمي بعد',
                en1: '1 student has no academic advisor yet', en: '${counts.unassigned} students have no academic advisor yet'),
            action: _bannerAction(t('توزيع', 'Distribute'), 'distribute'),
          ),
        ],
        if (counts.away > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.person_off_rounded,
            color: c.warning,
            text: countText(counts.away,
                ar1: 'طالب واحد مرشده غائب', ar2: 'طالبان مرشدهما غائب', arFew: '${counts.away} طلاب مرشدوهم غائبون', arMany: '${counts.away} طالباً مرشدوهم غائبون',
                en1: '1 student\'s advisor is away', en: '${counts.away} students\' advisors are away'),
            action: _bannerAction(t('عرض', 'View'), 'students_away'),
          ),
        ],
        if (counts.over > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.balance_rounded,
            color: c.danger,
            text: countText(counts.over,
                ar1: 'مرشد واحد فوق حده الأقصى', ar2: 'مرشدان فوق حدهما الأقصى', arFew: '${counts.over} مرشدين فوق حدهم الأقصى', arMany: '${counts.over} مرشداً فوق حدهم الأقصى',
                en1: '1 advisor is over their maximum', en: '${counts.over} advisors are over their maximum'),
            action: _bannerAction(t('موازنة', 'Rebalance'), 'rebalance'),
          ),
        ],
      ],
      if (onOpen != null && (me.leads || me.advisor)) ..._links(context, st),
      _SectionTitle(
        st.directors.length > 1 ? t('مديرو الإرشاد', 'Advising directors') : t('مدير الإرشاد', 'Advising director'),
        subtitle: t('رئيس إدارة الإرشاد الأكاديمي ومن مُنح دور مدير الإرشاد', 'The head of the Academic Advising department and anyone given the advising director role'),
      ),
      AppCard(
        padding: AppSpace.card,
        child: st.directors.isEmpty
            ? Row(children: [
                Icon(Icons.person_add_alt_rounded, color: c.textMedium, size: AppIconSize.md),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(t('لا يوجد مدير بعد — عيّن رئيساً لـ $dept.', 'No director yet — choose a head for the $dept.'), style: AppType.body(context)),
                ),
              ])
            : Column(children: [
                for (var i = 0; i < st.directors.length; i++) ...[
                  if (i > 0) Divider(height: AppSpace.md, color: c.divider),
                  MergeSemantics(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppTouch.min),
                      child: Row(children: [
                        AppAvatar(name: st.directors[i].name, size: 40),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(st.directors[i].name.isEmpty ? '—' : st.directors[i].name, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(t('مدير الإرشاد', 'Advising director'), style: AppType.meta(context)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ],
              ]),
      ),
    ];
  }
}

extension _AdvSetupLinks on AdvSetupView {
  /// "Distribute" / "View" at the end of a banner (null without [AdvSetupView.onOpen]).
  Widget? _bannerAction(String label, String key) => onOpen == null
      ? null
      : TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: () => onOpen!(key), child: Text(label));

  /// The way into the Phase 3 pages: what an admin / director manages, then what an advisor uses.
  List<Widget> _links(BuildContext context, AdvStatus st) {
    final c = context.colors;
    final me = st.me;
    final open = onOpen!;
    final pending = me.handoversPending;
    final urgent = me.flagsUrgent, overdue = me.flagsOverdue;
    final attention = [
      if (urgent > 0)
        countText(urgent, ar1: 'تنبيه عاجل', ar2: 'تنبيهان عاجلان', arFew: '$urgent تنبيهات عاجلة', arMany: '$urgent تنبيهاً عاجلاً', en1: '1 urgent flag', en: '$urgent urgent flags'),
      if (overdue > 0)
        countText(overdue, ar1: 'مراجعة متأخرة', ar2: 'مراجعتان متأخرتان', arFew: '$overdue مراجعات متأخرة', arMany: '$overdue مراجعة متأخرة', en1: '1 review overdue', en: '$overdue reviews overdue'),
    ].join(' · ');
    final workspace = AppActionCard(
      icon: Icons.groups_rounded,
      title: me.leads ? t('مساحة الإرشاد', 'Advising workspace') : t('طلابي', 'My students'),
      subtitle: attention.isNotEmpty
          ? attention
          : (me.leads ? t('كل الطلاب مرتبين حسب الخطر، والتنبيهات والملاحظات', 'Every student by risk, with flags and notes') : t('طلابك مرتبين حسب الخطر، والتنبيهات والملاحظات', 'Your students by risk, with flags and notes')),
      badge: urgent + overdue,
      color: urgent > 0 ? c.danger : (overdue > 0 ? c.warning : c.primary),
      onTap: () => open('workspace'),
    );
    final tiles = <Widget>[
      if (me.leads || me.advisor) workspace,
      if (me.leads) ...[
        AppActionCard(
          icon: Icons.tune_rounded,
          title: t('الإعدادات', 'Settings'),
          subtitle: t('من يرشد، الحد الأقصى، طريقة التوزيع', 'Who advises, the maximum, the strategy'),
          onTap: () => open('settings'),
        ),
        AppActionCard(
          icon: Icons.supervisor_account_rounded,
          title: t('المرشدون', 'Advisors'),
          subtitle: t('الأحمال والحالات والإجازات', 'Loads, statuses and leave'),
          onTap: () => open('advisors'),
        ),
        AppActionCard(
          icon: Icons.call_split_rounded,
          title: t('التوزيع', 'Distribute'),
          subtitle: t('معاينة ثم تطبيق: توزيع، موازنة، نقل', 'Preview, then apply: distribute, rebalance, reassign'),
          color: c.success,
          onTap: () => open('distribute'),
        ),
        AppActionCard(
          icon: Icons.school_rounded,
          title: t('الطلاب', 'Students'),
          subtitle: t('مرشد كل طالب، الإقفال، تعارض المصالح', 'Each student\'s advisor, locks, conflicts'),
          onTap: () => open('students'),
        ),
        AppActionCard(
          icon: Icons.label_outline_rounded,
          title: t('التصنيفات', 'Categories'),
          subtitle: t('تصنيفات التنبيهات والملاحظات والتسهيلات', 'Flag and note categories, accommodations'),
          onTap: () => open('categories'),
        ),
      ],
      if (me.advisor) ...[
        AppActionCard(
          icon: Icons.badge_outlined,
          title: t('ملفي كمرشد', 'My advisor profile'),
          subtitle: t('مكتبك وطريقة التواصل معك', 'Your office and how to reach you'),
          onTap: () => open('profile'),
        ),
        AppActionCard(
          icon: Icons.handshake_outlined,
          title: t('ملفات التسليم', 'Handovers'),
          subtitle: pending > 0
              ? countText(pending,
                  ar1: 'ملف واحد بانتظارك', ar2: 'ملفان بانتظارك', arFew: '$pending ملفات بانتظارك', arMany: '$pending ملفاً بانتظارك',
                  en1: '1 waiting for you', en: '$pending waiting for you')
              : t('ملخص حالة كل طالب ينتقل إليك', 'A case summary for each student who moves to you'),
          badge: pending,
          color: pending > 0 ? c.warning : null,
          onTap: () => open('handovers'),
        ),
      ],
    ];
    return [
      _SectionTitle(t('العمل', 'Work')),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 560 ? 2 : 1;
        return AppGrid(minTile: (box.maxWidth - AppSpace.sm * (cols - 1)) / cols, spacing: AppSpace.sm, padding: EdgeInsets.zero, children: tiles);
      }),
    ];
  }
}

/// A section title inside the page's padded list (the list already insets its content).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(title, style: AppType.section(context))),
        if (sub != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(sub, style: AppType.meta(context)),
        ],
      ]),
    );
  }
}

class _BusyStrip extends StatelessWidget {
  const _BusyStrip();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Semantics(
          label: t('جارٍ الحفظ', 'Saving'),
          child: ClipRRect(borderRadius: AppRadius.chipAll, child: LinearProgressIndicator(minHeight: 3, color: context.colors.primary)),
        ),
      );
}

/// The tinted round icon at the start of the status card.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: AppTouch.primary,
          height: AppTouch.primary,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
          child: Icon(icon, color: color, size: AppIconSize.lg),
        ),
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Icon(icon, size: AppIconSize.md, color: context.colors.primary)),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: AppType.body(context))),
        ]),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: AppStatTile(icon: icon, label: label, value: value, color: color),
      );
}

/// "82 % of students have an advisor" with its bar.
class _Coverage extends StatelessWidget {
  const _Coverage({required this.counts});
  final AdvCounts counts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = counts.coveragePct;
    final text = counts.students == 0
        ? t('لا يوجد طلاب في المؤسسة بعد.', 'There are no students in the organization yet.')
        : t('${pct.round()}% من الطلاب لهم مرشد أكاديمي', '${pct.round()}% of students have an academic advisor');
    return AppCard(
      padding: AppSpace.card,
      child: Semantics(
        label: text,
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: AppType.row(context)),
          if (counts.students > 0) ...[
            const SizedBox(height: AppSpace.xs),
            AppProgressBar(value: pct, color: pct >= 100 ? c.success : c.primary),
            if (counts.advisors > 0) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(t('نحو ${counts.perAdvisor} طالباً لكل مرشد', 'About ${counts.perAdvisor} students per advisor'), style: AppType.meta(context)),
            ],
          ],
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Enable sheet
// ═════════════════════════════════════════════════════════════════════════════

/// The department picker of the Enable sheet (plain values). [selected] null = create a new Academic Advising
/// department; that choice is offered only while the organization has none ([choices] lists the existing one first).
class AdvEnableForm extends StatelessWidget {
  const AdvEnableForm({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelect,
    required this.onSubmit,
    this.loading = false,
    this.busy = false,
  });

  final List<AdvDeptOption> choices;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final VoidCallback onSubmit;

  /// The departments are still loading.
  final bool loading;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final hasAdvising = choices.any((d) => d.isAdvising);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('أي إدارة تقود الإرشاد الأكاديمي؟', 'Which department leads academic advising?'), style: AppType.bodyStrong(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(t('يصبح رئيسها مدير الإرشاد.', 'Its head becomes the advising director.'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      if (loading)
        const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
      else ...[
        if (!hasAdvising)
          _DeptChoice(
            icon: Icons.add_business_rounded,
            title: t('إنشاء إدارة جديدة', 'Create a new department'),
            subtitle: t('«الإرشاد الأكاديمي» — إدارة خدمية', '"Academic Advising" — a service department'),
            selected: selected == null,
            onTap: busy ? null : () => onSelect(null),
          ),
        for (final d in choices)
          _DeptChoice(
            icon: d.isAdvising ? Icons.co_present_rounded : Icons.apartment_rounded,
            title: d.name,
            subtitle: d.isAdvising ? t('إدارة الإرشاد الأكاديمي الحالية', 'The existing Academic Advising department') : null,
            selected: selected == d.id,
            onTap: busy ? null : () => onSelect(d.id),
          ),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        icon: Icons.power_settings_new_rounded,
        label: t('تفعيل الإرشاد الأكاديمي', 'Turn on academic advising'),
        busy: busy,
        onPressed: loading ? null : onSubmit,
      ),
    ]);
  }
}

class _DeptChoice extends StatelessWidget {
  const _DeptChoice({required this.icon, required this.title, required this.selected, required this.onTap, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? c.primary.withValues(alpha: 0.06) : c.cardBg,
          borderRadius: AppRadius.cardAll,
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(
                borderRadius: AppRadius.cardAll,
                border: Border.all(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
              ),
              child: Row(children: [
                ExcludeSemantics(child: Icon(icon, size: AppIconSize.md, color: selected ? c.primary : c.textMedium)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (sub != null) Text(sub, style: AppType.meta(context)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                ExcludeSemantics(
                  child: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      size: AppIconSize.md, color: selected ? c.primary : c.textLight),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvSetupPage extends StatefulWidget {
  const AdvSetupPage({super.key, required this.orgId});
  final int orgId;

  @override
  State<AdvSetupPage> createState() => _AdvSetupPageState();
}

class _AdvSetupPageState extends State<AdvSetupPage> {
  AdvStatus? _status;
  String? _error;
  bool _busy = false;

  /// The departments (the leading one's name, the Enable sheet's choices); null until loaded. A notifier, so an
  /// open Enable sheet fills in when they arrive.
  final _depts = ValueNotifier<List<AdvDeptOption>?>(null);

  AdvApi get _api => AdvApi(widget.orgId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _depts.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
      _error = null;
    });
    final r = await orgCall(() => _api.status(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _status = r.data as AdvStatus;
      } else {
        _error = r.endpointMissing
            ? t('الإرشاد الأكاديمي يحتاج تحديث الخادم.', 'Academic advising needs a server update.')
            : orgErrorText(r.error!);
      }
    });
    final s = _status;
    if (s != null && s.enabled && s.deptId != null && s.me.leads) await _loadDepts();
  }

  /// Quiet: the page works without them (a generic department name, "create one" in the sheet).
  Future<void> _loadDepts() async {
    final r = await orgCall(() => _api.departmentChoices(), quiet: true);
    if (!mounted) return;
    _depts.value = r.ok ? r.data as List<AdvDeptOption> : (_depts.value ?? const []);
    setState(() {});
  }

  String? get _deptName {
    final id = _status?.deptId;
    if (id == null) return null;
    return _depts.value?.where((d) => d.id == id).firstOrNull?.name;
  }

  Future<void> _enable() async {
    if (_depts.value == null) _loadDepts();
    int? selected;
    var picked = false;
    var busy = false;
    await showAppSheet<void>(
      context,
      (ctx) => ValueListenableBuilder<List<AdvDeptOption>?>(
        valueListenable: _depts,
        builder: (ctx, choices, _) => StatefulBuilder(builder: (ctx, set) {
          if (choices != null && !picked) {
            picked = true;
            selected = advDefaultDept(choices);
          }
          Future<void> submit() async {
            set(() => busy = true);
            final ok = await _apply(() => _api.enable(deptId: selected), t('فُعّل الإرشاد الأكاديمي', 'Academic advising is on'));
            if (!ctx.mounted) return;
            if (ok) {
              Navigator.pop(ctx);
            } else {
              set(() => busy = false);
            }
          }

          return AppSheetContent(
            title: t('تفعيل الإرشاد الأكاديمي', 'Turn on academic advising'),
            children: [
              AdvEnableForm(
                choices: choices ?? const [],
                loading: choices == null,
                selected: selected,
                busy: busy,
                onSelect: (v) => set(() => selected = v),
                onSubmit: submit,
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _disable() async {
    final yes = await appConfirm(
      context,
      danger: true,
      confirmLabel: t('إيقاف', 'Turn off'),
      message: t('إيقاف الإرشاد الأكاديمي؟ تبقى كل السجلات وتعود عند التفعيل من جديد.',
          'Turn academic advising off? Every record is kept and comes back when you turn it on again.'),
    );
    if (!yes || !mounted) return;
    await _apply(() => _api.disable(), t('أُوقف الإرشاد الأكاديمي', 'Academic advising is off'));
  }

  Future<bool> _apply(Future<AdvStatus> Function() call, String ok) async {
    setState(() => _busy = true);
    final r = await orgCall(call, ok: ok);
    if (!mounted) return r.ok;
    setState(() {
      _busy = false;
      if (r.ok) _status = r.data as AdvStatus;
    });
    if (r.ok && _status!.enabled) await _loadDepts();
    return r.ok;
  }

  /// Pushes a Phase 3 page; back here, the counts are read again (quietly).
  Future<void> _open(String key) async {
    final s = _status;
    if (s == null) return;
    final id = widget.orgId, lead = s.me.leads;
    final Widget page = switch (key) {
      'settings' => AdvConfigPage(orgId: id),
      'advisors' => AdvAdvisorsPage(orgId: id, manage: true),
      'profile' => AdvAdvisorsPage(orgId: id, manage: false),
      'distribute' => AdvDistributePage(orgId: id),
      'rebalance' => AdvDistributePage(orgId: id, initial: const AdvPlanRequest(mode: 'rebalance')),
      'students_away' => AdvStudentsPage(orgId: id, manage: lead, filter: 'away'),
      'handovers' => AdvHandoversPage(orgId: id, manage: false),
      'workspace' => AdvWorkspacePage(orgId: id, manage: lead),
      'categories' => AdvCategoriesPage(orgId: id),
      _ => AdvStudentsPage(orgId: id, manage: lead),
    };
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    final r = await orgCall(() => _api.status(), quiet: true);
    if (mounted && r.ok) setState(() => _status = r.data as AdvStatus);
  }

  @override
  Widget build(BuildContext context) => AdvSetupView(
        state: advSetupState(status: _status, failed: _error != null),
        status: _status,
        deptName: _deptName,
        errorText: _error,
        busy: _busy,
        onRetry: _load,
        onEnable: _enable,
        onDisable: _disable,
        onOpen: _open,
      );
}
