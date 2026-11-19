// lib/features/org/onboarding/onboarding_invite.dart — "Invite to complete" (Phase C, D-1200).
//
//   OnbDraftPickerPage   multi-select over the draft cases (of one type, or all) → `POST cases/invite`; the guided path
//                        of the Add dialog's "Invite people" and the Drafts tab's bulk action. Only drafts with an
//                        e-mail or a phone can be invited; the rest come back as `skipped` with a reason.
//   OnbDraftPickerView   the list over plain values (layout harness)
//   OnbInviteResultView  invited and skipped with reasons
//
// Gate: kill switch `org.onboarding.invite` + the module's update right (checked by the caller).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t, asMapList;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_models.dart';

class OnbDraftPickerPage extends StatefulWidget {
  const OnbDraftPickerPage({super.key, required this.orgId, this.type, this.api, this.preselect = const {}});
  final int orgId;

  /// null: the drafts of every type.
  final OnbType? type;
  final OnboardingApi? api;
  final Set<int> preselect;

  @override
  State<OnbDraftPickerPage> createState() => _OnbDraftPickerPageState();
}

class _OnbDraftPickerPageState extends State<OnbDraftPickerPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  final _items = <OnbCase>[];
  late final Set<int> _picked = {...widget.preselect};
  bool _loading = true, _busy = false;
  ApiException? _error;
  OnbInviteResult? _result;

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
    final r = await _api.cases(widget.orgId, status: 'draft', type: widget.type?.key ?? '', pageSize: 200);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = r.error;
        return;
      }
      _items
        ..clear()
        ..addAll(asMapList(r.map['items']).map(OnbCase.fromJson));
    });
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    final r = await _api.inviteCases(widget.orgId, _picked.toList());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    setState(() => _result = OnbInviteResult.fromJson(r.map));
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    return OrgPushedPage(
      title: t('دعوة لاستكمال البيانات', 'Invite to complete'),
      subtitle: widget.type?.label ?? t('الالتحاق والتعيين', 'Admissions & appointments'),
      helpPageId: 'org.onboarding',
      width: AppWidth.reading,
      child: res != null
          ? OnbInviteResultView(result: res, names: {for (final c in _items) c.id: c.fullName}, onClose: () => Navigator.of(context).maybePop(true))
          : OnbDraftPickerView(
              items: _items,
              picked: _picked,
              loading: _loading,
              error: _error,
              busy: _busy,
              onRetry: _load,
              onToggle: (id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id)),
              onAll: () => setState(() => _picked.length == _items.length ? _picked.clear() : _picked.addAll(_items.map((e) => e.id))),
              onInvite: _invite,
            ),
    );
  }
}

class OnbDraftPickerView extends StatelessWidget {
  const OnbDraftPickerView({super.key, required this.items, required this.picked, this.loading = false, this.error, this.busy = false, this.onRetry, this.onToggle, this.onAll, this.onInvite});
  final List<OnbCase> items;
  final Set<int> picked;
  final bool loading, busy;
  final Object? error;
  final VoidCallback? onRetry, onAll, onInvite;
  final void Function(int)? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: AppStateView<List<OnbCase>>(
          loading: loading,
          error: error,
          data: loading || error != null ? null : items,
          onRetry: onRetry,
          isEmpty: (l) => l.isEmpty,
          empty: AppEmpty(icon: Icons.drafts_outlined, title: t('لا مسودات للدعوة', 'No drafts to invite'), message: t('أضف مسودات أو استورد قائمة أولاً.', 'Add drafts or import a list first.')),
          builder: (context, list) => ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md), children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(key: const ValueKey('onb.invite.all'), label: picked.length == list.length ? t('إلغاء تحديد الكل', 'Clear selection') : t('تحديد الكل', 'Select all'), size: AppButtonSize.sm, onPressed: onAll),
            ),
            for (final x in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: AppCard(
                  key: ValueKey('onb.invite.case.${x.id}'),
                  highlight: picked.contains(x.id),
                  padding: const EdgeInsets.all(AppSpace.sm),
                  onTap: () => onToggle?.call(x.id),
                  child: Row(children: [
                    Icon(picked.contains(x.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: picked.contains(x.id) ? c.primary : c.textMedium),
                    AppSpace.gapSm,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.fullName.isEmpty ? t('بدون اسم', 'No name yet') : x.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                        Text([x.phone, x.email].where((e) => e.isNotEmpty).join(' · ').isEmpty ? t('بلا وسيلة اتصال', 'No contact') : [x.phone, x.email].where((e) => e.isNotEmpty).join(' · '),
                            maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppButton.primary(
          key: const ValueKey('onb.invite.send'),
          label: t('دعوة ${picked.length}', 'Invite ${picked.length}'),
          icon: Icons.mail_outline_rounded,
          busy: busy,
          onPressed: picked.isEmpty || busy ? null : onInvite,
        ),
      ),
    ]);
  }
}

class OnbInviteResultView extends StatelessWidget {
  const OnbInviteResultView({super.key, required this.result, this.names = const {}, this.onClose});
  final OnbInviteResult result;
  final Map<int, String> names;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxxl), children: [
      Icon(result.invited > 0 ? Icons.mark_email_read_rounded : Icons.info_outline_rounded, size: AppIconSize.xl, color: result.invited > 0 ? c.success : c.warning),
      AppSpace.gapSm,
      Text(t('أُرسلت ${result.invited} دعوة', '${result.invited} invitation(s) sent'), key: const ValueKey('onb.invite.done'), textAlign: TextAlign.center, style: AppType.section(context)),
      if (result.skipped.isNotEmpty) ...[
        AppSpace.gapMd,
        AppSectionTitle(t('تم تخطي ${result.skipped.length}', 'Skipped ${result.skipped.length}')),
        for (final s in result.skipped)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              key: ValueKey('onb.invite.skipped.${s.id}'),
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((names[s.id] ?? '').isEmpty ? '#${s.id}' : names[s.id]!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                AppSpace.gapXs,
                AppStatusBadge(label: onbSkipReason(s.reason), tone: AppTone.warning, dense: true),
              ]),
            ),
          ),
      ],
      AppSpace.gapMd,
      Align(child: AppButton.primary(key: const ValueKey('onb.invite.close'), label: t('تم', 'Done'), onPressed: onClose)),
    ]);
  }
}
