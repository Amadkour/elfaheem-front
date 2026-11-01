// lib/features/org/governance/gov_request_parts.dart — requests for someone else, real attachments and the approval
// chain (D-140 / D-141; server routes in docs/backend/governance-spec.md §6 and ../back/FLUTTER_API_CHANGES.md).
//
//   GovForSection          the submit form's "For: Me / A member / Someone outside the system" (plain values; the
//                          page owns the controllers and the BeneficiaryDraft, layout-tested)
//   pickGovBeneficiary     the searchable member list (`GET …/{org}/people`, names only) → GovPerson
//   GovBeneficiaryRows     who an item is for, on the item page (contact rows only when the server sent them)
//   GovChainPreview        the entity's steps on the submit form ("Manager → Finance → Department council")
//   GovChainCard           an item's chain: the current step, who / when / why of every step, earlier rounds
//   GovChainEditor         the org admin's step list for one entity (add · reorder · remove), + GovChainEditorPage
//   openGovAttachment      an uploaded file: a fresh 10-minute link, images previewed in the app, PDFs in the
//                          browser's / system viewer, other files downloaded; older URL entries open as before
//   showGovResubmitSheet   the requester edits a rejected item and sends it again (a new round of its chain)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../admin/admin_common.dart' show Debouncer, SheetHeader, asInt, asMap, t;
import '../org_common.dart' show openFileUrl;
import '../org_page_header.dart' show OrgPushedPage, orgUsesDashboardHeader;
import '../org_ui.dart' show orgPickAndUpload;
import '../org_v3.dart' show OrgCall, orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_ui.dart';

String _codeText(OrgCall r) => govCodeTexts()[r.code] ?? orgErrorText(r.error!);

// ═════════════════════════════════════════════════════════════════════════════
//  For whom (D-140)
// ═════════════════════════════════════════════════════════════════════════════

/// The controllers of the "someone outside the system" fields, owned by the page.
class GovForControllers {
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final nationalId = TextEditingController();
  final studentNumber = TextEditingController();
  final relation = TextEditingController();

  /// Copies the typed values into [d] (before validating / sending).
  void fill(BeneficiaryDraft d) {
    d
      ..name = name.text
      ..phone = phone.text
      ..email = email.text
      ..nationalId = nationalId.text
      ..studentNumber = studentNumber.text
      ..relation = relation.text;
  }

  void dispose() {
    for (final x in [name, phone, email, nationalId, studentNumber, relation]) {
      x.dispose();
    }
  }
}

class GovForSection extends StatelessWidget {
  const GovForSection({
    super.key,
    required this.kind,
    required this.controllers,
    required this.onKind,
    required this.onPickMember,
    this.member,
    this.onClearMember,
    this.errors = const {},
  });

  /// self · member · external
  final String kind;
  final GovPerson? member;
  final GovForControllers controllers;
  final ValueChanged<String> onKind;
  final VoidCallback onPickMember;
  final VoidCallback? onClearMember;

  /// field → message (BeneficiaryDraft.validate or the server's `beneficiary_invalid {field}`).
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = controllers;
    Widget field(TextEditingController ctrl, String key, String label, IconData icon, {bool ltr = false, TextInputType? keyboard, String? hint}) =>
        _GovTextField(controller: ctrl, label: label, icon: icon, ltr: ltr, keyboard: keyboard, hint: hint, error: errors[key]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('لصالح من؟', 'Who is it for?'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xs - 2),
      Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, children: [
        AppChoiceChip(label: t('أنا', 'Me'), icon: Icons.person_rounded, selected: kind == 'self', onTap: () => onKind('self')),
        AppChoiceChip(label: t('عضو في المؤسسة', 'A member'), icon: Icons.group_rounded, selected: kind == 'member', onTap: () => onKind('member')),
        AppChoiceChip(label: t('شخص من خارج النظام', 'Someone outside the system'), icon: Icons.person_outline_rounded, selected: kind == 'external', onTap: () => onKind('external')),
      ]),
      if (kind == 'member') ...[
        const SizedBox(height: AppSpace.sm),
        GovPersonField(
          label: t('العضو', 'Member'),
          person: member == null ? null : GovUser(id: member!.id, name: member!.name),
          onPick: onPickMember,
          onClear: onClearMember,
        ),
        if (errors['user_id'] != null) _FieldError(errors['user_id']!),
        const SizedBox(height: AppSpace.sm),
        field(k.relation, 'relation', t('الصلة (اختياري)', 'Relation (optional)'), Icons.link_rounded, hint: t('مثل: طالب أرشده', 'e.g. my advisee')),
      ],
      if (kind == 'external') ...[
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          final two = box.maxWidth >= 560;
          Widget pair(Widget a, Widget b) => two
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: AppSpace.sm), Expanded(child: b)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, b]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            pair(field(k.name, 'name', t('الاسم الكامل *', 'Full name *'), Icons.badge_rounded),
                field(k.relation, 'relation', t('الصلة (اختياري)', 'Relation (optional)'), Icons.link_rounded, hint: t('مثل: ولي أمر', 'e.g. parent'))),
            pair(field(k.phone, 'phone', t('الهاتف (اختياري)', 'Phone (optional)'), Icons.phone_rounded, ltr: true, keyboard: TextInputType.phone, hint: '+20 100 123 4567'),
                field(k.email, 'email', t('البريد (اختياري)', 'E-mail (optional)'), Icons.alternate_email_rounded, ltr: true, keyboard: TextInputType.emailAddress, hint: 'name@example.com')),
            pair(field(k.nationalId, 'national_id', t('رقم الهوية (اختياري)', 'National id (optional)'), Icons.credit_card_rounded, ltr: true),
                field(k.studentNumber, 'student_number', t('الرقم الجامعي (اختياري)', 'Student number (optional)'), Icons.numbers_rounded, ltr: true)),
          ]);
        }),
      ],
      if (kind != 'self') ...[
        const SizedBox(height: AppSpace.xxs),
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: kind == 'member'
              ? t('يرى العضو الطلب ويتابعه وتصله إشعاراته؛ تبقى أنت مقدّم الطلب', 'The member sees and follows the request and gets its notices; you stay the one who filed it')
              : t('تظهر هذه البيانات لمن يعالج الطلب فقط', 'Only the people who handle the request see these details'),
        ),
      ],
    ]);
  }
}

class _GovTextField extends StatelessWidget {
  const _GovTextField({required this.controller, required this.label, required this.icon, this.ltr = false, this.keyboard, this.hint, this.error});
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool ltr;
  final TextInputType? keyboard;
  final String? hint, error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: col, width: w));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        textDirection: ltr ? TextDirection.ltr : null,
        style: appText(14, c: c.textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          errorMaxLines: 2,
          prefixIcon: Icon(icon, size: 20, color: c.textLight),
          labelStyle: appText(13, c: c.textMedium),
          hintStyle: appText(13, c: c.textLight),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: b(c.divider),
          enabledBorder: b(c.divider),
          focusedBorder: b(c.primary, 1.6),
          errorBorder: b(c.danger),
          focusedErrorBorder: b(c.danger, 1.6),
        ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.sm, top: AppSpace.xxs),
        child: Text(text, style: appText(12, c: context.colors.danger)),
      );
}

/// The member search sheet of the "for a member" choice (names only; the server checks the right).
Future<GovPerson?> pickGovBeneficiary(BuildContext context, int orgId, {int? deptId, int? selectedId}) =>
    showAppSheet<GovPerson>(context, (_) => _BeneficiarySheet(orgId: orgId, deptId: deptId, selectedId: selectedId));

class _BeneficiarySheet extends StatefulWidget {
  const _BeneficiarySheet({required this.orgId, this.deptId, this.selectedId});
  final int orgId;
  final int? deptId, selectedId;
  @override
  State<_BeneficiarySheet> createState() => _BeneficiarySheetState();
}

class _BeneficiarySheetState extends State<_BeneficiarySheet> {
  final _debounce = Debouncer(const Duration(milliseconds: 350));
  List<GovPerson> _people = const [];
  bool _loading = true;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await orgCall(() => GovApi.memberPeople(widget.orgId, q: _q, deptId: widget.deptId), quiet: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _people = r.ok ? r.data as List<GovPerson> : const [];
      _error = r.ok ? null : _codeText(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(t('لصالح عضو', 'For a member')),
        TextField(
          onChanged: (v) {
            _q = v;
            _debounce.run(_load);
          },
          style: appText(14, c: c.textDark),
          decoration: InputDecoration(
            hintText: t('ابحث بالاسم أو اسم المستخدم…', 'Search by name or username…'),
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            filled: true,
            fillColor: c.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.divider)),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        if (_error != null)
          AppBanner(icon: Icons.lock_outline_rounded, color: c.warning, text: _error!)
        else
          Flexible(
            child: GovPeopleList(
              people: [for (final p in _people) GovUser(id: p.id, name: p.name, email: p.username == null ? null : '@${p.username}')],
              loading: _loading,
              query: _q,
              selectedId: widget.selectedId,
              onPick: (u) => Navigator.pop(context, _people.firstWhere((p) => p.id == u.id)),
            ),
          ),
      ]),
    );
  }
}

/// Who the item is for, as rows of the item page's header card.
class GovBeneficiaryRows extends StatelessWidget {
  const GovBeneficiaryRows(this.beneficiary, {super.key});
  final Beneficiary beneficiary;

  @override
  Widget build(BuildContext context) {
    final b = beneficiary;
    final who = [
      b.name.isEmpty ? t('—', '—') : b.name,
      if ((b.relation ?? '').isNotEmpty) '(${b.relation})',
      b.isExternal ? t('· من خارج النظام', '· outside the system') : t('· عضو', '· member'),
    ].join(' ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GovKV(b.isExternal ? Icons.person_outline_rounded : Icons.group_rounded, t('لصالح', 'For'), who),
      if (b.phone != null) GovKV(Icons.phone_rounded, t('الهاتف', 'Phone'), b.phone!),
      if (b.email != null) GovKV(Icons.alternate_email_rounded, t('البريد', 'E-mail'), b.email!),
      if (b.nationalId != null) GovKV(Icons.credit_card_rounded, t('رقم الهوية', 'National id'), b.nationalId!),
      if (b.studentNumber != null) GovKV(Icons.numbers_rounded, t('الرقم الجامعي', 'Student number'), b.studentNumber!),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Approval chain (D-141)
// ═════════════════════════════════════════════════════════════════════════════

/// The entity's steps, shown on the submit form before sending.
class GovChainPreview extends StatelessWidget {
  const GovChainPreview({super.key, required this.steps});
  final List<ChainStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.primary.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_tree_rounded, size: 18, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('مراحل الاعتماد', 'Approval steps'), style: appText(12.5, w: FontWeight.w800, c: c.textDark))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < steps.length; i++) ...[
            AppBadgePill('${i + 1}. ${steps[i].label}', color: c.primary),
            if (i < steps.length - 1) Icon(Icons.arrow_forward_rounded, size: 14, color: c.textLight),
          ],
        ]),
      ]),
    );
  }
}

/// An item's chain: every step with its status and record; the current one highlighted; earlier rounds folded.
class GovChainCard extends StatelessWidget {
  const GovChainCard({super.key, required this.chain});
  final ItemChain chain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.account_tree_rounded, size: 18, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('مراحل الاعتماد', 'Approval steps'), style: appText(14, w: FontWeight.w800, c: c.textDark))),
          if (chain.round > 1) AppBadgePill('${t('الجولة', 'Round')} ${chain.round}', color: c.purple, icon: Icons.replay_rounded),
        ]),
        const SizedBox(height: AppSpace.sm),
        for (var i = 0; i < chain.steps.length; i++) GovChainStepRow(step: chain.steps[i], index: i, last: i == chain.steps.length - 1, current: chain.current == i),
        if (chain.rounds.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(t('الجولات السابقة (${chain.rounds.length})', 'Earlier rounds (${chain.rounds.length})'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
              children: [
                for (final r in chain.rounds) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                      child: Text('${t('الجولة', 'Round')} ${r.$1}', style: appText(12, w: FontWeight.w800, c: c.textLight)),
                    ),
                  ),
                  for (var i = 0; i < r.$2.length; i++) GovChainStepRow(step: r.$2[i], index: i, last: i == r.$2.length - 1, current: false),
                ],
              ],
            ),
          ),
      ]),
    );
  }
}

class GovChainStepRow extends StatelessWidget {
  const GovChainStepRow({super.key, required this.step, required this.index, required this.last, required this.current});
  final ChainStep step;
  final int index;
  final bool last, current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, Color color, String state) = switch (step.status) {
      'approved' => (Icons.check_circle_rounded, c.success, t('اعتُمدت', 'Approved')),
      'rejected' => (Icons.cancel_rounded, c.danger, t('رُفضت', 'Rejected')),
      'skipped' => (Icons.redo_rounded, c.textLight, t('تُجووزت', 'Skipped')),
      'current' => (Icons.radio_button_checked_rounded, c.primary, t('الخطوة الحالية', 'Current step')),
      _ => (Icons.radio_button_unchecked_rounded, c.textLight, t('بالانتظار', 'Waiting')),
    };
    final who = [
      if (step.by != null) step.by!.name,
      if (step.via == 'council') t('بتصويت المجلس', 'by council vote'),
      if (step.at != null && step.isDone) govWhen(step.at),
    ].join(' · ');
    final note = (step.note ?? '').startsWith('council:') ? null : step.note;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            Icon(icon, size: 22, color: color),
            if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: c.divider)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : AppSpace.sm),
            child: Container(
              padding: current ? const EdgeInsets.all(AppSpace.xs) : EdgeInsets.zero,
              decoration: current ? BoxDecoration(color: c.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.chip)) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpace.xs, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${index + 1}. ${step.label}', style: appText(13.5, w: FontWeight.w800, c: c.textDark)),
                  Text(state, style: appText(11.5, w: FontWeight.w700, c: color)),
                ]),
                if (who.isNotEmpty) Text(who, style: appText(12, c: c.textMedium)),
                if ((note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('«$note»', style: appText(12.5, c: step.status == 'rejected' ? c.danger : c.textDark, h: 1.4)),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The org admin's editor for one entity's chain (plain values; the page saves).
class GovChainEditor extends StatelessWidget {
  const GovChainEditor({
    super.key,
    required this.steps,
    required this.entities,
    required this.onChanged,
    this.hasCouncil = false,
    this.errorIndex,
    this.canEdit = true,
  });
  final List<ChainStep> steps;

  /// Entities an `entity` step may point at (never a council, never the entity itself).
  final List<Entity> entities;
  final ValueChanged<List<ChainStep>> onChanged;
  final bool hasCouncil, canEdit;
  final int? errorIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void set(List<ChainStep> v) => onChanged(v);
    final kinds = [
      if (steps.isEmpty) 'manager',
      'entity',
      if (hasCouncil) 'council',
      'faculty_council',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (steps.isEmpty)
        AppBanner(icon: Icons.info_outline_rounded, text: t('بلا خطوات: يبتّ مدير الجهة في الطلب مرة واحدة كما هو الحال الآن', 'No steps: the entity\'s manager decides once, as today')),
      for (var i = 0; i < steps.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: errorIndex == i ? c.danger : c.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(radius: 13, backgroundColor: c.primary.withValues(alpha: 0.12), child: Text('${i + 1}', style: appText(12, w: FontWeight.w800, c: c.primary))),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(chainKindLabel(steps[i].kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark))),
              if (canEdit) ...[
                IconButton(
                  tooltip: t('لأعلى', 'Move up'),
                  onPressed: i == 0 ? null : () => set([...steps]..insert(i - 1, steps[i])..removeAt(i + 1)),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
                IconButton(
                  tooltip: t('لأسفل', 'Move down'),
                  onPressed: i == steps.length - 1 ? null : () => set([...steps]..insert(i + 2, steps[i])..removeAt(i)),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                ),
                IconButton(tooltip: t('حذف', 'Remove'), onPressed: () => set([...steps]..removeAt(i)), icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger)),
              ],
            ]),
            if (steps[i].kind == 'entity') ...[
              const SizedBox(height: AppSpace.xs),
              AppDropdown<int>(
                value: entities.any((e) => e.id == steps[i].deptId) ? steps[i].deptId : null,
                hint: Text(t('اختر الجهة', 'Choose the entity')),
                decoration: InputDecoration(labelText: t('الجهة', 'Entity'), prefixIcon: const Icon(Icons.apartment_rounded)),
                items: [for (final e in entities) DropdownMenuItem(value: e.id, child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis))],
                onChanged: canEdit ? (v) => set([...steps]..[i] = ChainStep(kind: 'entity', deptId: v)) : null,
              ),
            ],
          ]),
        ),
      if (canEdit) ...[
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, children: [
          for (final k in kinds)
            AppPill(icon: Icons.add_rounded, label: chainKindLabel(k), color: c.textMedium, onTap: () => set([...steps, ChainStep(kind: k)])),
        ]),
      ],
    ]);
  }
}

/// One entity's chain, loaded / saved through `GET|PUT …/entities/{id}/chain` (saving: the org admin).
class GovChainEditorPage extends StatefulWidget {
  const GovChainEditorPage({super.key, required this.orgId, required this.entity, this.entities, this.embedded = false});
  final int orgId;
  final Entity entity;

  /// The targets of an "another entity" step; loaded here when not given.
  final List<Entity>? entities;

  /// A tab of the entity page: the body only.
  final bool embedded;
  @override
  State<GovChainEditorPage> createState() => _GovChainEditorPageState();
}

class _GovChainEditorPageState extends State<GovChainEditorPage> {
  late final _api = GovApi(widget.orgId);
  List<ChainStep>? _steps;
  late List<Entity> _entities = widget.entities ?? const [];
  bool _canEdit = false, _busy = false, _failed = false;
  int? _errorIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (widget.entities == null) {
      final er = await orgCall(() => _api.entities(), quiet: true);
      if (er.ok && mounted) _entities = er.data as List<Entity>;
    }
    final r = await orgCall(() => _api.chain(widget.entity.id), quiet: true);
    if (!mounted) return;
    setState(() {
      _failed = !r.ok;
      if (r.ok) {
        final (steps, canEdit) = r.data as (List<ChainStep>, bool);
        _steps = steps;
        _canEdit = canEdit;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errorIndex = null;
    });
    final r = await orgCall(() => _api.saveChain(widget.entity.id, _steps!), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _errorIndex = r.detail['index'] == null ? null : asInt(r.detail['index']));
      showAppNotice(_codeText(r), error: true);
      return;
    }
    setState(() => _steps = r.data as List<ChainStep>);
    showAppNotice(t('حُفظت سلسلة الاعتماد — تتبعها الطلبات الجديدة', 'Saved — new requests follow these steps'));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entity;
    Widget child;
    if (_steps == null && !_failed) {
      child = const AppListSkeleton(items: 3);
    } else if (_steps == null) {
      child = AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else {
      child = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('ترتيب من يعتمد طلبات «${e.name}»: موافقة كل خطوة تنقل الطلب إلى التالية، والرفض في أي خطوة يحتاج سبباً.',
                  'Who approves requests of “${e.name}”, in order: each step\'s approval moves it on; a rejection at any step needs a reason.'),
              style: appText(13, c: context.colors.textMedium, h: 1.5)),
          const SizedBox(height: AppSpace.sm),
          GovChainEditor(
            steps: _steps!,
            entities: [for (final x in _entities) if (x.id != e.id && !x.isCouncil) x],
            hasCouncil: e.isScientific && e.councilId != null,
            canEdit: _canEdit,
            errorIndex: _errorIndex,
            onChanged: (v) => setState(() {
              _steps = v;
              _errorIndex = null;
            }),
          ),
          if (_canEdit) ...[
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
          ] else ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(icon: Icons.lock_outline_rounded, text: t('يعدّل الخطوات مدير المؤسسة', 'The organization admin edits the steps')),
          ],
        ]),
      );
    }
    final title = t('سلسلة الاعتماد', 'Approval chain');
    if (widget.embedded) return child;
    if (orgUsesDashboardHeader(context, widget.orgId)) {
      return OrgPushedPage(title: title, subtitle: e.name, maxWidth: 760, child: child);
    }
    return BasePage(useWebCard: true, maxWith: 760, appBar: ScreenAppBar(title: title), child: child);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Attachments (D-140)
// ═════════════════════════════════════════════════════════════════════════════

/// Picks a file and uploads it to the request attachment route; null when cancelled or refused (toasted).
Future<GovAttachment?> uploadGovAttachment(int orgId) async {
  final f = await orgPickAndUpload(GovApi.uploadPath(orgId));
  if (f == null || f['id'] == null) return null;
  return GovAttachment.fromJson(asMap(f)..remove('url'));
}

/// Opens an attachment: an uploaded file gets a fresh link first (the server checks that you may see the item);
/// images preview in the app, PDFs open in the browser's / system viewer, other files download.
Future<void> openGovAttachment(BuildContext context, GovAttachment a) async {
  if (!a.isFile) return openFileUrl(a.url);
  final r = await orgCall(() => GovApi.attachmentLink(a.id!, inline: a.preview), quiet: true);
  if (!r.ok) {
    showAppNotice(_codeText(r), error: true);
    return;
  }
  final url = r.data as String;
  if (a.isImage && context.mounted) {
    await showDialog<void>(context: context, builder: (_) => GovImagePreview(attachment: a, url: url));
    return;
  }
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok) showAppNotice(t('تعذّر فتح الملف', 'Could not open the file'), error: true);
}

/// An image attachment in a dialog (zoomable), with a download button.
class GovImagePreview extends StatelessWidget {
  const GovImagePreview({super.key, required this.attachment, required this.url});
  final GovAttachment attachment;
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
            child: Row(children: [
              Expanded(child: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark))),
              IconButton(
                tooltip: t('تنزيل', 'Download'),
                icon: const Icon(Icons.download_rounded),
                onPressed: () async {
                  final r = await orgCall(() => GovApi.attachmentLink(attachment.id!), quiet: true);
                  if (r.ok) await launchUrl(Uri.parse(r.data as String), mode: LaunchMode.externalApplication);
                },
              ),
              IconButton(tooltip: t('إغلاق', 'Close'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(t('تعذّرت المعاينة — استخدم التنزيل', 'Preview failed — use Download'), textAlign: TextAlign.center, style: appText(13, c: c.textMedium)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The attachment chips of a header / composer: file-type icon, name, size; a tap opens it.
class GovAttachmentChips extends StatelessWidget {
  const GovAttachmentChips({super.key, required this.attachments, this.onOpen, this.onRemove});
  final List<GovAttachment> attachments;
  final ValueChanged<GovAttachment>? onOpen, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, children: [
      for (final a in attachments)
        InputChip(
          avatar: Icon(a.isImage ? Icons.image_rounded : (a.isPdf ? Icons.picture_as_pdf_rounded : Icons.attach_file_rounded), size: 16, color: c.primary),
          label: Text(
            [a.name.isEmpty ? t('مرفق', 'Attachment') : a.name, if ((a.size ?? 0) > 0) fileSizeLabel(a.size)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(12, w: FontWeight.w600, c: c.textDark),
          ),
          onPressed: onOpen == null ? null : () => onOpen!(a),
          onDeleted: onRemove == null ? null : () => onRemove!(a),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Resubmit (D-141)
// ═════════════════════════════════════════════════════════════════════════════

/// The requester edits a rejected item (title · details · files · a note to the decider) and sends it again.
/// Returns the reopened item, or null.
Future<WorkItem?> showGovResubmitSheet(BuildContext context, WorkItem item) =>
    showAppSheet<WorkItem>(context, (_) => _ResubmitSheet(item: item));

class _ResubmitSheet extends StatefulWidget {
  const _ResubmitSheet({required this.item});
  final WorkItem item;
  @override
  State<_ResubmitSheet> createState() => _ResubmitSheetState();
}

class _ResubmitSheetState extends State<_ResubmitSheet> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _body = TextEditingController(text: widget.item.body ?? '');
  final _note = TextEditingController();
  late final _files = [...widget.item.attachments];
  bool _busy = false, _uploading = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() => _uploading = true);
    final a = await uploadGovAttachment(asInt(widget.item.raw['org_id']));
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (a != null) _files.add(a);
    });
  }

  Future<void> _send() async {
    if (_title.text.trim().length < 3) {
      showAppNotice(t('اكتب العنوان', 'Enter a title'), error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await orgCall(
        () => GovApi.memberResubmit(widget.item.id, {
              'title': _title.text.trim(),
              'body': _body.text.trim(),
              'attachments': [for (final a in _files) a.toJson()],
              if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
            }),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(_codeText(r), error: true);
      return;
    }
    showAppNotice(t('أُعيد تقديم الطلب', 'Resubmitted'));
    Navigator.pop(context, WorkItem.fromJson(asMap(r.data)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.item.decision;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeader(t('تعديل وإعادة تقديم ${widget.item.ref}', 'Edit and resubmit ${widget.item.ref}')),
        if ((d?.note ?? '').isNotEmpty) ...[
          AppBanner(icon: Icons.feedback_outlined, color: c.danger, text: '${t('سبب الرفض', 'Reason for rejecting')}: ${d!.note}'),
          const SizedBox(height: AppSpace.sm),
        ],
        AppField(controller: _title, label: t('العنوان', 'Title')),
        AppField(controller: _body, label: t('التفاصيل', 'Details'), maxLines: 5),
        Text(t('مرفقات', 'Attachments'), style: appText(12, c: c.textLight)),
        const SizedBox(height: AppSpace.xs - 2),
        GovAttachmentChips(attachments: _files, onRemove: (a) => setState(() => _files.remove(a))),
        const SizedBox(height: AppSpace.xs - 2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionChip(
            avatar: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_rounded, size: 16, color: c.primary),
            label: Text(t('إضافة ملف', 'Add file'), style: appText(12, w: FontWeight.w700, c: c.primary)),
            onPressed: _uploading || _files.length >= 10 ? null : _add,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: _note, label: t('ملاحظة لمن يراجع (اختياري)', 'A note for the reviewer (optional)'), maxLines: 2),
        AppPrimaryButton(label: t('إعادة التقديم', 'Resubmit'), icon: Icons.replay_rounded, busy: _busy, onPressed: _send),
      ]),
    );
  }
}
