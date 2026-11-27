// features/courses/teacher/wizard/step_panels.dart — the body of each wizard step (Tea1Wizard.dc.html): the cards that
// ride up over the hero. Every field, kill switch and provider call of the old long form is here, grouped by step; the
// shell (course_form_screen.dart) owns the actions that need the screen (cover removal, saving, the Path editor).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart' show recurrenceDayName, recurrenceWeekOrder;
import 'package:flutter_education_app/features/courses/teacher/component/add_item_dialog.dart';
import 'package:flutter_education_app/features/courses/teacher/component/course_progress_status_card.dart';
import 'package:flutter_education_app/features/courses/teacher/component/currency_selector.dart';
import 'package:flutter_education_app/features/courses/teacher/component/section_card.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_reel_field.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/course_form_draft.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/form_parts.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/form_sections.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/weekly_slot_sheet.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_steps.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show AppCurrencyX, CourseStatus;
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_provider.dart' show kDayOrder;
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// What the steps ask the screen to do.
class WizardActions {
  const WizardActions({
    required this.removeCover,
    required this.openPath,
    required this.goTo,
    required this.toggleStatus,
    required this.changeProgress,
    required this.addSlot,
    required this.editSlot,
    required this.deleteSlot,
  });

  final Future<void> Function() removeCover;
  final VoidCallback openPath;
  final ValueChanged<CourseWizardStep> goTo;
  final VoidCallback toggleStatus;
  final ValueChanged<CourseStatus> changeProgress;
  final VoidCallback addSlot;
  final ValueChanged<int> editSlot;
  final ValueChanged<int> deleteSlot;
}

/// The weekly slots in the order the form keeps them: the saved ones, then the new ones.
List<WeeklySlotValue> wizardSlots(CourseFormProvider p) => [
      for (final s in p.form.schedules) (day: s.day, start: s.startTime, end: s.endTime),
      for (final s in p.pendingSchedules) (day: s.day, start: s.startTime, end: s.endTime),
    ];

/// The cards of [step].
class WizardStepBody extends StatelessWidget {
  const WizardStepBody({super.key, required this.step, required this.draft, required this.actions});

  final CourseWizardStep step;
  final CourseFormDraft draft;
  final WizardActions actions;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseFormProvider>();
    final cards = switch (step) {
      CourseWizardStep.basics => _basics(context),
      CourseWizardStep.pricing => _pricing(context, p),
      CourseWizardStep.audience => _audience(context),
      CourseWizardStep.privacy => _privacy(context),
      CourseWizardStep.schedule => _schedule(context, p),
      CourseWizardStep.extras => _extras(context, p),
      CourseWizardStep.review => _review(context, p),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.md), cards[i]],
    ]);
  }

  Widget _card(Widget head, List<Widget> body) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          head,
          const SizedBox(height: AppSpace.md),
          ...body,
        ]),
      );

  // ── 1 · basics ─────────────────────────────────────────────────────────────

  List<Widget> _basics(BuildContext context) => [
        ParentComponent(
          featureKey: 'course_form.basic_info',
          child: _card(WzHead(icon: Icons.image_outlined, title: 't1_wz_cover'.tr), [
            Center(
              child: EditableImage(
                onChange: (XFile file) async {
                  draft.logoBytes = await file.readAsBytes();
                  draft.logoFile = file;
                  draft.touch();
                },
                imageUrl: draft.coverUrl,
                imageByte: draft.logoBytes,
                imageFile: draft.logoFile,
                size: MediaQuery.sizeOf(context).height / 6,
                onRemove: actions.removeCover,
                removeMessage: 'cover_remove_confirm'.tr,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text('t1_wz_cover_hint'.tr, style: AppType.meta(context)),
          ]),
        ),
        ParentComponent(
          featureKey: 'course_form.basic_info',
          child: _card(WzHead(icon: Icons.notes_rounded, title: 't1_wz_basics'.tr), [
            CfBasicsFields(draft: draft),
            const SizedBox(height: AppSpace.xs),
            Text('t1_wz_title_hint'.tr, style: AppType.meta(context)),
          ]),
        ),
      ];

  // ── 2 · pricing and plans ──────────────────────────────────────────────────

  Widget _plan(BuildContext context, CourseFormProvider p, int index, String title, String labelKey, TextEditingController ctrl, int months) {
    final sym = p.selectedCurrency.symbol;
    final per = wizardPerMonth(ctrl.text, months);
    final hint = months == 1
        ? 't1_wz_monthly_note'.tr
        : per.isEmpty
            ? ''
            : '${'t1_wz_means'.tr} $per $sym ${'t1_wz_per_month'.tr}${months == 6 ? ' ${'t1_wz_approx'.tr}' : ''}';
    return WzPlan(
      key: ValueKey('wizard.plan.$index'),
      title: title,
      tag: index == 0 ? 't1_wz_main'.tr : 't1_wz_optional'.tr,
      main: index == 0,
      field: AppNumberField(controller: ctrl, label: labelKey.tr, min: 0, step: 10, decimals: 2),
      hint: hint,
      isDefault: p.defaultPlanIndex == index,
      onDefault: () => p.onChangeDefaultPlan(index),
    );
  }

  List<Widget> _pricing(BuildContext context, CourseFormProvider p) => [
        ParentComponent(
          featureKey: 'course_form.basic_info',
          child: _card(WzHead(icon: Icons.account_balance_wallet_outlined, title: 't1_wz_plans'.tr), [
            CurrencySelector(label: 'currency_label'.tr, selected: p.selectedCurrency, onChanged: p.onChangeCurrency),
            const SizedBox(height: AppSpace.md),
            // Yearly = the existing price field; the other two plans are optional (empty = not offered).
            _plan(context, p, 0, 't1_wz_plan_year'.tr, 'price_yearly_label', draft.price, 12),
            const SizedBox(height: AppSpace.sm),
            _plan(context, p, 1, 't1_wz_plan_six'.tr, 'price_six_months_label', draft.priceSixMonths, 6),
            const SizedBox(height: AppSpace.sm),
            _plan(context, p, 2, 't1_wz_plan_month'.tr, 'price_monthly_label', draft.priceMonthly, 1),
            const SizedBox(height: AppSpace.sm),
            Text('price_plans_hint'.tr, style: AppType.meta(context)),
          ]),
        ),
        ParentComponent(
          featureKey: 'course_form.advanced',
          child: _card(WzHead(icon: Icons.local_offer_outlined, title: 'discount_section_title'.tr), [CfDiscountFields(draft: draft)]),
        ),
      ];

  // ── 3 · audience and place ─────────────────────────────────────────────────

  List<Widget> _audience(BuildContext context) => [
        ParentComponent(
          featureKey: 'course_form.audience',
          child: _card(WzHead(icon: Icons.school_outlined, title: 't1_wz_audience_q'.tr), [CfAudienceFields(draft: draft)]),
        ),
      ];

  // ── 4 · privacy and path ───────────────────────────────────────────────────

  List<Widget> _privacy(BuildContext context) => [
        ParentComponent(
          featureKey: 'course_form.advanced',
          child: _card(WzHead(icon: Icons.shield_outlined, title: 't1_wz_privacy'.tr), [CfPrivacyField(draft: draft)]),
        ),
        ParentComponent(
          featureKey: 'course_form.advanced',
          child: _card(WzHead(icon: Icons.schedule_rounded, title: 't1_wz_hours'.tr), [
            Text('t1_wz_hours_q'.tr, style: AppType.meta(context)),
            const SizedBox(height: AppSpace.sm),
            CfHoursField(draft: draft),
          ]),
        ),
        ParentComponent(
          featureKey: 'course_form.advanced',
          child: ParentComponent(
            featureKey: 'course_form.relations',
            child: _card(WzHead(icon: Icons.route_rounded, title: 'course_relations_title'.tr), [
              CfRelationsFields(draft: draft, onOpenPath: actions.openPath),
            ]),
          ),
        ),
      ];

  // ── 5 · weekly schedule ────────────────────────────────────────────────────

  List<Widget> _schedule(BuildContext context, CourseFormProvider p) {
    final slots = wizardSlots(p);
    final days = <(String, String?)>[
      for (final w in recurrenceWeekOrder())
        (
          recurrenceDayName(w),
          () {
            for (final s in slots) {
              if (s.day == kDayOrder[w]) return AppTime.clock(s.start);
            }
            return null;
          }(),
        ),
    ];
    final c = context.colors;
    return [
      ParentComponent(
        featureKey: 'course_form.advanced',
        child: ParentComponent(
          featureKey: 'course_details.schedule',
          child: _card(
            WzHead(
              icon: Icons.calendar_month_outlined,
              title: 't1_wz_weekly'.tr,
              trailing: AppButton.primary(key: const ValueKey('wizard.slot.new'), label: 't1_wz_add_slot'.tr, icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: actions.addSlot),
            ),
            [
              DlBannerNote(text: 't1_wz_repeat_note'.tr),
              const SizedBox(height: AppSpace.md),
              WzWeekStrip(days: days),
              const SizedBox(height: AppSpace.lg),
              Row(children: [
                Icon(Icons.format_list_bulleted_rounded, size: AppIconSize.md, color: AppAreaScope.of(context).ink),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: Text('${'t1_wz_slots'.tr} (${slots.length})', style: AppType.section(context))),
              ]),
              const SizedBox(height: AppSpace.sm),
              if (slots.isEmpty)
                Container(
                  padding: AppSpace.card,
                  decoration: BoxDecoration(
                    color: c.inputBg,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    border: Border.all(color: c.kit.line, width: AppBorder.strong),
                  ),
                  child: Text('t1_wz_no_slots'.tr, style: AppType.meta(context)),
                )
              else
                for (var i = 0; i < slots.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpace.sm),
                  WzSlotRow(
                    key: ValueKey('wizard.slot.$i'),
                    day: wizardDayName(slots[i].day),
                    range: wizardRange(slots[i].start, slots[i].end),
                    length: '${'t1_wz_class'.tr} ${weeklySlotMinutesText(wizardMinutes(slots[i].start, slots[i].end))}',
                    onEdit: () => actions.editSlot(i),
                    onDelete: () => actions.deleteSlot(i),
                  ),
                ],
            ],
          ),
        ),
      ),
    ];
  }

  // ── 6 · video, certificate and extras ──────────────────────────────────────

  List<Widget> _extras(BuildContext context, CourseFormProvider p) => [
        ParentComponent(
          featureKey: 'course_form.optional',
          child: _card(WzHead(icon: Icons.play_arrow_rounded, title: 't1_wz_video'.tr), [
            // Course reel (عرض أولي): an optional intro video shown instead of the course image on the course profile.
            CourseReelField(controller: draft.reelCtrl, posterUrl: draft.logoBytes != null ? null : draft.coverUrl),
          ]),
        ),
        ParentComponent(
          featureKey: 'course_form.optional',
          child: _card(
            WzHead(
              icon: Icons.workspace_premium_outlined,
              title: 't1_wz_cert'.tr,
              trailing: Text('t1_wz_optional'.tr, textAlign: TextAlign.end, style: AppType.meta(context)),
            ),
            [
              const ParentComponent(featureKey: 'course_form.certificate_template', child: CfCertificateDesignsLink()),
              const SizedBox(height: AppSpace.sm),
              SectionCard(
                featureKey: 'course_details.certificates',
                icon: Icons.workspace_premium_rounded,
                title: 'certificates_section'.tr,
                items: p.form.certificates,
                onAdd: () => addItemDialog('add_certificate'.tr, p.addFormCertificate, context),
                onRemove: p.removeFormCertificate,
              ),
            ],
          ),
        ),
        ParentComponent(
          featureKey: 'course_form.optional',
          child: _card(WzHead(icon: Icons.checklist_rounded, title: 't1_wz_more'.tr), [
            SectionCard(
              featureKey: 'course_details.tools',
              icon: Icons.build_rounded,
              title: 'tools_section'.tr,
              items: p.form.tools,
              onAdd: () => addItemDialog('add_tool'.tr, p.addFormTool, context),
              onRemove: p.removeFormTool,
            ),
            const SizedBox(height: AppSpace.sm),
            SectionCard(
              featureKey: 'course_details.prerequisites',
              icon: Icons.checklist_rounded,
              title: 'prerequisites_section'.tr,
              items: p.form.prerequisites,
              onAdd: () => addItemDialog('add_prerequisite'.tr, p.addFormPrerequisite, context),
              onRemove: p.removeFormPrerequisite,
            ),
          ]),
        ),
      ];

  // ── 7 · review and publish ─────────────────────────────────────────────────

  List<Widget> _review(BuildContext context, CourseFormProvider p) {
    final ready = wizardReadiness(draft, p);
    final n = ready.where((e) => e).length;
    final oks = <CourseWizardStep, bool>{
      CourseWizardStep.basics: ready[0],
      CourseWizardStep.pricing: ready[1],
      CourseWizardStep.audience: ready[2],
      CourseWizardStep.privacy: ready[3],
      CourseWizardStep.schedule: ready[4],
    };
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Semantics(header: true, child: Text('t1_wz_review_title'.tr, style: AppType.section(context)))),
            const SizedBox(width: AppSpace.xs),
            AppStatusBadge(
              key: const ValueKey('wizard.ready'),
              label: '${'t1_wz_ready'.tr} $n ${'t1_wz_of'.tr} ${ready.length}',
              tone: n == ready.length ? AppTone.success : AppTone.warning,
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          for (final s in CourseWizardStep.values.where((s) => s != CourseWizardStep.review)) ...[
            if (s != CourseWizardStep.basics) const SizedBox(height: AppSpace.sm),
            WzSummaryRow(
              key: ValueKey('wizard.review.${s.name}'),
              step: s,
              text: () {
                final t = wizardSummary(s, draft, p);
                return t.isEmpty ? 't1_wz_none'.tr : t;
              }(),
              ok: oks[s],
              onEdit: () => actions.goTo(s),
            ),
          ],
        ]),
      ),
      // edit mode: publish / progress status stay visible
      if (draft.isEdit) ...[
        ParentComponent(
          featureKey: 'course_form.publish_status',
          child: CfStatusCard(isPublished: draft.isPublished, isLoading: draft.statusLoading, onToggle: actions.toggleStatus),
        ),
        CourseProgressStatusCard(status: draft.progressStatus, isLoading: draft.progressStatusLoading, onChanged: actions.changeProgress),
      ],
    ];
  }
}

/// The soft note under a card head (the schedule's "repeats every week").
class DlBannerNote extends StatelessWidget {
  const DlBannerNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(color: set.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.sync_rounded, size: AppIconSize.md, color: set.ink),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(text, style: AppType.body(context).copyWith(color: set.ink))),
      ]),
    );
  }
}
