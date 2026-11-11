// lib/features/org/governance/gov_member_pages.dart — the member side (spec §6, `/api/v1/org/public/governance`):
//
//   GovSubmitPage(orgId)      submit a complaint / request to an entity: entity → for whom (me · a member · someone
//                             outside the system, with the "create for others" right, D-140) → category → type → title · body ·
//                             (a department's team member may send a request straight to its Department Council:
//                             `to_council`, the item lands on the next agenda and the member does not vote on it)
//                             priority · anonymous · attachments (real uploads, type / size checked by the server);
//                             the entity's approval chain (D-141) is shown before sending
//   GovSubmitForm             the presentational form (layout-tested)
//   GovMyItemsPage            what I submitted + what was routed to me personally → GovItemScreen(member: true)
//   GovMyAssignmentsPage      forms I must answer, with due dates → the existing form-filling screen
// (GovMyVotesPage belongs to the councils files.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asMap, t;
import '../org_member_space.dart' show OrgFormFillScreen;
import '../org_page_header.dart' show OrgHeaderButton, OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_item_screen.dart';
import 'gov_items_page.dart' show GovItemCard;
import 'gov_models.dart';
import 'gov_request_parts.dart';
import 'gov_ui.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Submit
// ═════════════════════════════════════════════════════════════════════════════

class GovSubmitForm extends StatelessWidget {
  const GovSubmitForm({
    super.key,
    required this.entities,
    required this.entity,
    required this.category,
    required this.type,
    required this.title,
    required this.body,
    required this.priority,
    required this.anonymous,
    required this.attachments,
    required this.onEntity,
    required this.onCategory,
    required this.onType,
    required this.onPriority,
    required this.onAnonymous,
    required this.onAddAttachment,
    required this.onRemoveAttachment,
    required this.onSubmit,
    this.toCouncil = false,
    this.onToCouncil,
    this.busy = false,
    this.uploading = false,
    this.error,
    this.forWho,
    this.forOthers = false,
  });

  final List<Entity> entities;
  final Entity? entity;
  final Category? category;
  final String type, priority;
  final TextEditingController title, body;
  final bool anonymous, busy, uploading;

  /// "Put it before the Department Council": shown only when the entity's `canSubmitToCouncil` and the type is a request.
  final bool toCouncil;
  final ValueChanged<bool>? onToCouncil;
  final List<GovAttachment> attachments;
  final ValueChanged<Entity?> onEntity;
  final ValueChanged<Category?> onCategory;
  final ValueChanged<String> onType, onPriority;
  final ValueChanged<bool> onAnonymous;
  final VoidCallback onAddAttachment;
  final ValueChanged<GovAttachment> onRemoveAttachment;
  final VoidCallback? onSubmit;
  final String? error;

  /// The "For: Me / A member / Someone outside the system" section (GovForSection), given when the person may file
  /// for others in the chosen entity (D-140).
  final Widget? forWho;

  /// Filing for someone else: the "hide my identity" switch goes (the server refuses anonymity then).
  final bool forOthers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entity;
    final cats = e?.categories.where((x) => x.isActive).toList() ?? const <Category>[];
    final types = <String>[if (e == null || e.acceptsComplaints) 'complaint', 'request'];
    final complaintOnly = category?.kind == 'complaint';
    final councilOffer = e != null && e.canSubmitToCouncil && !complaintOnly && type == 'request';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('إلى أي جهة؟', 'To which entity?'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      AppDropdown<int>(
        value: e?.id,
        hint: Text(t('اختر الجهة', 'Choose an entity')),
        decoration: InputDecoration(labelText: t('الجهة', 'Entity'), prefixIcon: Icon(e == null ? Icons.apartment_rounded : govKindIcon(e.kind))),
        items: [for (final x in entities) DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => onEntity(entities.where((x) => x.id == v).firstOrNull),
      ),
      if (e != null && (e.description ?? '').isNotEmpty) ...[const SizedBox(height: AppSpace.xs), Text(e.description!, style: appText(12, c: c.textMedium, h: 1.4))],
      if (forWho != null) ...[const SizedBox(height: AppSpace.sm), forWho!],
      if (cats.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('ما موضوعها؟', 'What is it about?'), style: appText(12, c: c.textLight)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final cat in cats)
            AppChoiceChip(
              label: cat.name,
              icon: cat.kind == 'complaint' ? Icons.support_agent_rounded : (cat.formId != null ? Icons.assignment_rounded : Icons.inbox_rounded),
              selected: category?.id == cat.id,
              onTap: () => onCategory(category?.id == cat.id ? null : cat),
            ),
        ]),
        if (category?.formId != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.assignment_rounded, text: t('هذا التصنيف له نموذج خاص؛ ستُفتح استمارته بعد الإرسال', 'This category has its own form; it opens after sending')),
        ],
      ],
      const SizedBox(height: AppSpace.sm),
      Text(t('النوع', 'Type'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in types)
          AppChoiceChip(
            label: itemTypeLabel(x),
            icon: govTypeIcon(x),
            selected: (complaintOnly ? 'complaint' : type) == x,
            onTap: complaintOnly ? () {} : () => onType(x),
          ),
      ]),
      if (councilOffer) ...[
        const SizedBox(height: AppSpace.xs),
        AppSwitchTile(
          icon: Icons.gavel_rounded,
          title: t('عرضه على مجلس القسم', 'Put it before the Department Council'),
          subtitle: t('يُدرج في جدول أعمال الجلسة القادمة ويصوّت عليه الأعضاء — ما عداك', 'Goes on the next session\'s agenda; the members vote on it — all but you'),
          value: toCouncil,
          onChanged: onToCouncil ?? (_) {},
        ),
        if (toCouncil) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.how_to_vote_outlined, color: c.purple, text: t('بصفتك مقدّم الطلب لا تصوّت عليه، ويُحسب النصاب من دونك', 'As the submitter you do not vote on it, and the quorum is counted without you')),
        ],
      ],
      const SizedBox(height: AppSpace.sm),
      AppField(controller: title, label: t('العنوان', 'Title')),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: body, label: t('التفاصيل', 'Details'), maxLines: 5),
      const SizedBox(height: AppSpace.sm),
      Text(t('الأولوية', 'Priority'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in priorities) AppChoiceChip(label: priorityLabelOf(p), selected: priority == p, onTap: () => onPriority(p)),
      ]),
      if (!forOthers) ...[
        const SizedBox(height: AppSpace.xs),
        AppSwitchTile(
          icon: Icons.visibility_off_rounded,
          title: t('إخفاء هويتي', 'Hide my identity'),
          subtitle: t('يرى الموظف المعاملة دون اسمك؛ ما زال بإمكانك متابعتها', 'Staff see the item without your name; you can still follow it'),
          value: anonymous,
          onChanged: onAnonymous,
        ),
      ],
      const SizedBox(height: AppSpace.xs),
      Text(t('مرفقات', 'Attachments'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xxs / 2),
      Text(t('PDF أو صور أو مستندات Office — حتى 10 ميجابايت للملف', 'PDF, images or Office documents — up to 10 MB each'), style: appText(11.5, c: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      if (attachments.isNotEmpty) ...[GovAttachmentChips(attachments: attachments, onRemove: onRemoveAttachment), const SizedBox(height: AppSpace.xs)],
      Wrap(spacing: 6, runSpacing: 6, children: [
        ActionChip(
          avatar: uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_rounded, size: AppIconSize.sm, color: appInk(context, c.primary)),
          label: Text(t('إضافة ملف', 'Add file'), style: appText(12, w: FontWeight.w700, c: appInk(context, c.primary))),
          onPressed: uploading || attachments.length >= 10 ? null : onAddAttachment,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        ),
      ]),
      if (e != null && e.chain.isNotEmpty && !(councilOffer && toCouncil)) ...[const SizedBox(height: AppSpace.sm), GovChainPreview(steps: e.chain)],
      if (error != null) ...[const SizedBox(height: AppSpace.sm), AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('إرسال', 'Send'), icon: Icons.send_rounded, busy: busy, onPressed: e == null ? null : onSubmit),
    ]);
  }
}

class GovSubmitPage extends StatefulWidget {
  const GovSubmitPage(this.orgId, {super.key, this.deptId, this.type = 'request'});
  final int orgId;
  final int? deptId;
  final String type;

  @override
  State<GovSubmitPage> createState() => _GovSubmitPageState();
}

class _GovSubmitPageState extends State<GovSubmitPage> {
  List<Entity>? _entities;
  Entity? _entity;
  Category? _category;
  late String _type = widget.type;
  final _title = TextEditingController(), _body = TextEditingController();
  var _priority = 'medium';
  var _anonymous = false, _busy = false, _uploading = false, _failed = false, _missing = false, _toCouncil = false;
  final _attachments = <GovAttachment>[];
  String? _error;

  // for whom (D-140)
  var _forKind = 'self';
  GovPerson? _forMember;
  final _forCtl = GovForControllers();
  Map<String, String> _forErrors = const {};

  /// Staff in this organization see the dashboard's header: its Refresh reloads the entities in place (what was
  /// typed stays; a re-key would lose it).
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_reloadKeepingPick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _forCtl.dispose();
    _refresh.dispose();
    super.dispose();
  }

  /// The header's Refresh: the entities again, keeping the entity and category already picked when still there.
  Future<void> _reloadKeepingPick() async {
    final keep = _entity?.id, category = _category;
    await _load();
    if (!mounted || keep == null) return;
    final e = _entities?.where((x) => x.id == keep).firstOrNull;
    if (e != null) {
      setState(() {
        _entity = e;
        _category = category;
      });
    } else if (_forMember != null) {
      setState(() => _forMember = null); // the entity is gone: so is the member picked for it
    }
  }

  Future<void> _load() async {
    final r = await orgCall(() => GovApi.memberEntities(widget.orgId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _entities = r.data as List<Entity>;
        _entity = _entities!.where((e) => e.id == widget.deptId).firstOrNull ?? (_entities!.length == 1 ? _entities!.first : null);
        _failed = false;
      } else {
        _failed = true;
        _missing = r.endpointMissing;
      }
    });
    if (r.ok) _refresh.markUpdated();
  }

  Future<void> _addAttachment() async {
    setState(() => _uploading = true);
    final a = await uploadGovAttachment(widget.orgId);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (a != null) _attachments.add(a);
    });
  }

  bool get _forOthers => _forKind != 'self' && (_entity?.canSubmitForOthers ?? false);

  Future<void> _pickMember() async {
    final p = await pickGovBeneficiary(context, widget.orgId, deptId: _entity?.id, selectedId: _forMember?.id);
    if (p != null && mounted) {
      setState(() {
        _forMember = p;
        _forErrors = const {};
      });
    }
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = t('اكتب العنوان', 'Enter a title'));
      return;
    }
    Map<String, dynamic>? beneficiary;
    if (_forOthers) {
      final draft = BeneficiaryDraft(kind: _forKind, member: _forMember);
      _forCtl.fill(draft);
      final errors = draft.validate();
      if (errors.isNotEmpty) {
        setState(() {
          _forErrors = errors;
          _error = t('راجع بيانات صاحب الطلب', 'Check the details of the person it is for');
        });
        return;
      }
      beneficiary = draft.toJson();
    }
    setState(() {
      _busy = true;
      _error = null;
      _forErrors = const {};
    });
    final type = _category?.kind == 'complaint' ? 'complaint' : _type;
    final r = await orgCall(
        () => GovApi.memberSubmit(widget.orgId, {
              'dept_id': _entity!.id,
              'category_id': ?_category?.id,
              'type': type,
              'title': _title.text.trim(),
              'body': _body.text.trim(),
              'priority': _priority,
              'is_anonymous': _anonymous && beneficiary == null,
              'beneficiary': ?beneficiary,
              if (_toCouncil && type == 'request' && (_entity?.canSubmitToCouncil ?? false)) 'to_council': true,
              if (_attachments.isNotEmpty) 'attachments': [for (final a in _attachments) a.toJson()],
            }),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() {
        _error = govCodeTexts()[r.code] ?? orgErrorText(r.error!);
        final field = r.detail['field'];
        if (r.code == 'beneficiary_invalid' && field != null) _forErrors = {'$field': _error!};
      });
      return;
    }
    final m = asMap(r.data);
    final ref = '${m['ref'] ?? ''}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.block)),
        icon: Icon(Icons.check_circle_rounded, color: ctx.colors.success, size: AppIconSize.hero),
        title: Text(t('أُرسلت', 'Sent'), style: appText(16, w: FontWeight.w800)),
        content: Text('${m['message'] ?? t('استلمت الجهة معاملتك وسيصلك إشعار بكل تحديث', 'The entity received your item; you will be notified of every update')}\n\n${t('رقم المرجع', 'Reference')}: $ref',
            textAlign: TextAlign.center, style: appText(13.5, h: 1.5)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('حسناً', 'OK')))],
      ),
    );
    if (!mounted) return;
    final formId = _category?.formId;
    Navigator.of(context).pop(m);
    if (formId != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: formId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_entities == null && !_failed) {
      child = const AppListSkeleton(items: 4);
    } else if (_missing) {
      child = const GovNeedsServer();
    } else if (_entities == null) {
      child = AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else if (_entities!.isEmpty) {
      child = AppEmpty(icon: Icons.apartment_rounded, title: t('لا جهات تستقبل المعاملات بعد', 'No entity receives items yet'));
    } else {
      child = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl),
        child: GovSubmitForm(
          entities: _entities!,
          entity: _entity,
          category: _category,
          type: _type,
          title: _title,
          body: _body,
          priority: _priority,
          anonymous: _anonymous,
          attachments: _attachments,
          busy: _busy,
          uploading: _uploading,
          error: _error,
          toCouncil: _toCouncil,
          onToCouncil: (v) => setState(() => _toCouncil = v),
          forOthers: _forOthers,
          forWho: (_entity?.canSubmitForOthers ?? false)
              ? GovForSection(
                  kind: _forKind,
                  member: _forMember,
                  controllers: _forCtl,
                  errors: _forErrors,
                  onKind: (k) => setState(() {
                    _forKind = k;
                    _forErrors = const {};
                  }),
                  onPickMember: _pickMember,
                  onClearMember: () => setState(() => _forMember = null),
                )
              : null,
          onEntity: (e) => setState(() {
            // the member list is per entity: a member picked for another one is not kept
            if (e?.id != _entity?.id) {
              _forMember = null;
              _forErrors = const {};
            }
            _entity = e;
            _category = null;
            _toCouncil = false;
            if (!(e?.canSubmitForOthers ?? false)) _forKind = 'self';
            if (e != null && !e.acceptsComplaints && _type == 'complaint') _type = 'request';
          }),
          onCategory: (c) => setState(() => _category = c),
          onType: (v) => setState(() => _type = v),
          onPriority: (v) => setState(() => _priority = v),
          onAnonymous: (v) => setState(() => _anonymous = v),
          onAddAttachment: _addAttachment,
          onRemoveAttachment: (a) => setState(() => _attachments.remove(a)),
          onSubmit: _submit,
        ),
      );
    }
    // staff of this organization: the dashboard's header (Back first; Send stays at the end of the form); a student /
    // member keeps the screen's own app bar
    if (orgUsesDashboardHeader(context, widget.orgId)) {
      return OrgPushedPage(helpPageId: 'org.governance', title: t('معاملة جديدة', 'New request'), refresh: _refresh, maxWidth: 760, child: child);
    }
    return BasePage(
      useWebCard: true,
      maxWith: 760,
      appBar: ScreenAppBar(title: t('معاملة جديدة', 'New request')),
      child: child,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  My items
// ═════════════════════════════════════════════════════════════════════════════

class GovMyItemsPage extends StatefulWidget {
  const GovMyItemsPage({super.key, this.orgId, this.embedded = false, this.onSubmit});
  final int? orgId;
  final bool embedded;

  /// Opens the submit page (given when the organization is known).
  final VoidCallback? onSubmit;

  @override
  State<GovMyItemsPage> createState() => _GovMyItemsPageState();
}

class _GovMyItemsPageState extends State<GovMyItemsPage> {
  final _items = <WorkItem>[];
  String _status = '';
  int _page = 1, _pages = 1, _req = 0;
  bool _loading = true, _more = false, _failed = false, _missing = false;

  /// On its own page under the dashboard's header, Refresh reloads the list in place (the status filter stays).
  final _refresh = OrgPageRefresh();

  Future<void> _reload() => _load(reset: true);

  @override
  void initState() {
    super.initState();
    _refresh.attach(_reload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final req = ++_req;
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _failed = false;
      });
    } else {
      setState(() => _more = true);
    }
    final r = await orgCall(() => GovApi.memberItems(orgId: widget.orgId, status: _status.isEmpty ? null : _status, page: _page), quiet: true);
    if (!mounted || req != _req) return;
    setState(() {
      _loading = false;
      _more = false;
      if (!r.ok) {
        _failed = true;
        _missing = r.endpointMissing;
        return;
      }
      final page = r.data as GovPage<WorkItem>;
      if (reset) _items.clear();
      _items.addAll(page.items);
      _pages = page.pages;
    });
    if (r.ok) _refresh.markUpdated();
  }

  Future<void> _open(WorkItem it) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GovItemScreen(it.id, member: true)));
    if (mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final filters = {
      '': t('الكل', 'All'),
      'open': t('مفتوحة', 'Open'),
      'in_review,pending_approval,in_council': t('قيد المعالجة', 'In progress'),
      'approved': t('معتمدة', 'Approved'),
      'rejected': t('مرفوضة', 'Rejected'),
      'closed,withdrawn': t('منتهية', 'Finished'),
    };
    // staff of this organization on the page of its own: the dashboard's header, "New request" its primary action
    final pushed = !widget.embedded && orgUsesDashboardHeader(context, widget.orgId);
    final body = Column(children: [
      const SizedBox(height: AppSpace.xs),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), children: [
          for (final e in filters.entries) ...[
            AppChoiceChip(
              label: e.value,
              selected: _status == e.key,
              onTap: () {
                setState(() => _status = e.key);
                _load(reset: true);
              },
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ]),
      ),
      if (widget.onSubmit != null && !pushed)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          child: Align(alignment: AlignmentDirectional.centerEnd, child: AppPill(icon: Icons.add_rounded, label: t('معاملة جديدة', 'New request'), onTap: widget.onSubmit)),
        ),
      Expanded(child: _list()),
    ]);
    if (widget.embedded) return body;
    if (pushed) {
      final submit = widget.onSubmit;
      return OrgPushedPage(helpPageId: 'org.governance', 
        title: t('معاملاتي', 'My requests'),
        refresh: _refresh,
        primaryAction: submit == null ? null : OrgHeaderButton(icon: Icons.add_rounded, label: t('معاملة جديدة', 'New request'), onTap: submit),
        child: body,
      );
    }
    return BasePage(useWebCard: true, maxWith: 900, appBar: ScreenAppBar(title: t('معاملاتي', 'My requests')), child: body);
  }

  Widget _list() {
    if (_loading && _items.isEmpty) return const AppListSkeleton(items: 5);
    if (_missing) return const GovNeedsServer();
    if (_failed && _items.isEmpty) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return AppEmpty(icon: Icons.inbox_rounded, title: t('لا معاملات', 'No requests'), message: t('ما تقدّمه وما يُحال إليك يظهر هنا', 'What you submit and what is routed to you shows here'));
    }
    return AppRefresh(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xxl),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == _items.length) {
            if (_page >= _pages) return const SizedBox(height: AppSpace.xs);
            return Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Center(
                child: _more
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton.icon(
                        onPressed: () {
                          _page++;
                          _load();
                        },
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(t('تحميل المزيد', 'Load more'))),
              ),
            );
          }
          final it = _items[i];
          return GovItemCard(item: it, member: true, onTap: () => _open(it));
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  My form assignments
// ═════════════════════════════════════════════════════════════════════════════

class GovMyAssignmentsPage extends StatefulWidget {
  const GovMyAssignmentsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<GovMyAssignmentsPage> createState() => _GovMyAssignmentsPageState();
}

class _GovMyAssignmentsPageState extends State<GovMyAssignmentsPage> {
  List<FormAssignment>? _rows;
  bool _failed = false, _missing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await orgCall(() => GovApi.memberAssignments(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = r.data as List<FormAssignment>;
        _failed = false;
      } else {
        _failed = _rows == null;
        _missing = r.endpointMissing;
      }
    });
  }

  Future<void> _open(FormAssignment a) async {
    if (a.formId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: a.formId!)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_rows == null && !_failed) {
      body = const AppListSkeleton(items: 4);
    } else if (_missing) {
      body = const GovNeedsServer();
    } else if (_rows == null) {
      body = AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else if (_rows!.isEmpty) {
      body = AppEmpty(icon: Icons.assignment_turned_in_rounded, title: t('لا نماذج مطلوبة منك', 'No forms waiting for you'), message: t('كل ما طُلب منك إجابته مكتمل 🌿', 'Everything you were asked to answer is done 🌿'));
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxl), children: [
          for (final a in _rows!)
            AppCard(
              margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
              padding: const EdgeInsets.all(AppSpace.sm),
              onTap: a.formId == null ? null : () => _open(a),
              child: Row(children: [
                Icon(Icons.assignment_rounded, color: a.overdue ? c.danger : c.primary),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.formTitle ?? '${t('نموذج', 'Form')} #${a.formId}', style: appText(14, w: FontWeight.w800, c: c.textDark)),
                    if (a.dueAt != null)
                      Text('${t('قبل', 'By')} ${govWhen(a.dueAt)} · ${govDueText(a.dueAt)}', style: appText(12, c: a.overdue ? c.danger : c.textMedium)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textLight),
              ]),
            ),
        ]),
      );
    }
    if (widget.embedded) return body;
    // staff with an organization open: the dashboard's header, Back first; a student keeps the screen's own app bar
    if (orgUsesDashboardHeader(context, null)) {
      return OrgPushedPage(helpPageId: 'org.governance', title: t('نماذج مطلوبة مني', 'Forms to answer'), maxWidth: 900, child: body);
    }
    return BasePage(useWebCard: true, maxWith: 900, appBar: ScreenAppBar(title: t('نماذج مطلوبة مني', 'Forms to answer')), child: body);
  }
}
