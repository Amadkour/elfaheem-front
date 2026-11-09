// lib/features/org/advising/adv_outreach.dart — group outreach of the Academic Advising (#19, Phase 8,
// docs/advising/PHASE8.md): a director messages any group of the organization's students, an advisor only the
// students they advise; delivery and reading are tracked per recipient.
//
//   showAdvOutreachComposer   the composer sheet: who receives it (the preview: count, left out, a few names), a
//                             template, placeholder chips, subject, message, e-mail switch, "Send to N students"
//   AdvOutreachComposerForm   its content (plain values)
//   AdvOutreachListPage       the messages sent (a director: everyone's, or mine)
//   AdvOutreachTrackingPage   one message: delivered / read figures, the recipients by state, "Message those who
//                             have not read it"
//   AdvOutreachTrackingView   its content (plain values)
//   showAdvStudentMessage     the student's sheet for one message (marks it read)
//   AdvHubOutreachSection     the student hub's block: unread count and the latest messages (placed by the hub)
//   AdvStudentMessagesPage    every message the student received; [openId] (a push tap) opens that message's sheet
//                             over the list (Phase 9)
//   advOutreachOn             the kill switch `org.advising.outreach` (with the module's)
library;

import 'package:flutter_education_app/design/app_header.dart' show AppHeader;
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_analytics_api.dart';
import 'adv_analytics_models.dart';
import 'adv_analytics_parts.dart';
import 'adv_case_parts.dart' show AdvMiniStat, AdvTypedField, AdvTypedText;
import 'adv_models.dart' show AdvPage;
import 'adv_parts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Composer
// ═════════════════════════════════════════════════════════════════════════════

/// Group messages are on (`org.advising.outreach` and the module's switch `org.advising`); hidden features disappear.
bool advOutreachOn() => !AppConfig.disableList.contains('org.advising') && !AppConfig.disableList.contains('org.advising.outreach');

/// A fresh draft id: one per opened composer, so a retried send never sends twice.
String advOutreachClientId() {
  final r = math.Random.secure();
  return 'o${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
}

/// The composer's content (plain values). [presets] non-null: the person picks who receives it (no chart behind
/// the message); [audienceTitle] names a given audience instead.
class AdvOutreachComposerForm extends StatelessWidget {
  const AdvOutreachComposerForm({
    super.key,
    required this.subject,
    required this.body,
    this.preview,
    this.previewLoading = false,
    this.previewError,
    this.audienceTitle,
    this.explicitAudience = false,
    this.presets,
    this.preset = 0,
    this.onPreset,
    this.templates = const [],
    this.templateId,
    this.onTemplate,
    this.onToken,
    this.email = false,
    this.onEmail,
    this.busy = false,
    this.error,
    this.onSend,
    this.onChanged,
  });

  final TextEditingController subject, body;
  final AdvOutreachPreview? preview;
  final bool previewLoading;
  final String? previewError;
  final String? audienceTitle;

  /// The audience is a list of chosen students: [audienceTitle] names it, not the server's label.
  final bool explicitAudience;
  final List<(String, String?, String)>? presets;
  final int preset;
  final ValueChanged<int>? onPreset;
  final List<AdvOutreachTemplate> templates;
  final int? templateId;
  final ValueChanged<AdvOutreachTemplate?>? onTemplate;
  final ValueChanged<String>? onToken;
  final bool email;
  final ValueChanged<bool>? onEmail;
  final bool busy;
  final String? error;
  final VoidCallback? onSend;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    final count = p?.count ?? 0;
    final ps = presets;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('المستلمون', 'Who receives it')),
      if (ps != null) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (var i = 0; i < ps.length; i++) AppChoiceChip(label: ps[i].$3, selected: preset == i, onTap: () => onPreset?.call(i)),
        ]),
        const SizedBox(height: AppSpace.sm),
      ],
      _AudienceBox(preview: p, loading: previewLoading, error: previewError, title: audienceTitle, titleFirst: explicitAudience),
      const SizedBox(height: AppSpace.md),
      if (templates.isNotEmpty) ...[
        AppDropdown<int?>(
          value: templateId,
          decoration: InputDecoration(labelText: t('قالب', 'Template')),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(t('بلا قالب', 'No template'))),
            for (final tp in templates) DropdownMenuItem<int?>(value: tp.id, child: Text(tp.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: busy || onTemplate == null ? null : (id) => onTemplate!(templates.where((x) => x.id == id).firstOrNull),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      AppField(controller: subject, label: t('العنوان', 'Subject'), hint: t('يظهر وحده على شاشة القفل', 'The only part shown on a lock screen'), onChanged: onChanged),
      AdvTypedField(controller: body, label: t('الرسالة', 'Message'), minLines: 5, maxLines: 12, maxLength: advOutreachBodyMax, enabled: !busy, onChanged: onChanged),
      const SizedBox(height: AppSpace.xs),
      Text(t('يُستبدل لكل طالب:', 'Filled in for each student:'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final tok in advOutreachPlaceholders)
          ActionChip(
            avatar: Icon(Icons.add_rounded, size: AppIconSize.xs, color: c.primary),
            label: Text(advPlaceholderLabel(tok)),
            onPressed: busy || onToken == null ? null : () => onToken!(tok),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppSwitchTile(
        icon: Icons.mail_outline_rounded,
        title: t('أرسلها بالبريد الإلكتروني أيضاً', 'Also send it by e-mail'),
        subtitle: t('عبر بريد المؤسسة، إضافة إلى الإشعار داخل التطبيق', 'Through the organization\'s e-mail, besides the in-app notice'),
        value: email,
        onChanged: busy ? null : onEmail,
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        icon: Icons.send_rounded,
        label: count > 0
            ? countText(count, ar1: 'أرسل إلى طالب واحد', ar2: 'أرسل إلى طالبين', arFew: 'أرسل إلى $count طلاب', arMany: 'أرسل إلى $count طالباً', en1: 'Send to 1 student', en: 'Send to $count students')
            : t('أرسل', 'Send'),
        busy: busy,
        onPressed: count > 0 && !previewLoading && !(p?.tooLarge ?? false) ? onSend : null,
      ),
    ]);
  }
}

class _AudienceBox extends StatelessWidget {
  const _AudienceBox({this.preview, this.loading = false, this.error, this.title, this.titleFirst = false});
  final AdvOutreachPreview? preview;
  final bool loading, titleFirst;
  final String? error, title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    Widget inner;
    if (loading && p == null) {
      inner = const AppListSkeleton(items: 1, withAvatar: false, padding: EdgeInsets.zero);
    } else if (p == null) {
      inner = Text(error ?? t('تعذّر معرفة المستلمين.', 'The recipients could not be worked out.'), style: AppType.meta(context).copyWith(color: c.danger));
    } else {
      final label = titleFirst && (title ?? '').isNotEmpty ? title! : (p.label.isNotEmpty ? p.label : (title ?? ''));
      final names = [for (final s in p.sample.take(5)) s.shown].join('، ');
      inner = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.groups_rounded, color: c.primary, size: AppIconSize.md),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(advStudentsText(p.count), style: AppType.row(context).copyWith(fontWeight: FontWeight.w700))),
          if (loading) SizedBox(width: AppIconSize.xs, height: AppIconSize.xs, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
        ]),
        if (label.isNotEmpty) Text(label, style: AppType.meta(context)),
        if (names.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(p.count > p.sample.length ? t('$names وغيرهم', '$names and others') : names, style: AppType.meta(context).copyWith(color: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (p.capped > 0)
          AdvChartNote(
            countText(p.capped,
                ar1: 'طالب واحد بلغ حد الرسائل الأسبوعي ولن تصله', ar2: 'طالبان بلغا حد الرسائل الأسبوعي ولن تصلهما', arFew: '${p.capped} طلاب بلغوا حد الرسائل الأسبوعي ولن تصلهم',
                arMany: '${p.capped} طالباً بلغوا حد الرسائل الأسبوعي ولن تصلهم', en1: '1 student reached the weekly message limit and is left out', en: '${p.capped} students reached the weekly message limit and are left out'),
            icon: Icons.do_not_disturb_on_outlined,
          ),
        if (p.outOfScope > 0)
          AdvChartNote(
            countText(p.outOfScope,
                ar1: 'استُبعد طالب واحد لا ترشده', ar2: 'استُبعد طالبان لا ترشدهما', arFew: 'استُبعد ${p.outOfScope} طلاب لا ترشدهم', arMany: 'استُبعد ${p.outOfScope} طالباً لا ترشدهم',
                en1: '1 student you do not advise is left out', en: '${p.outOfScope} students you do not advise are left out'),
            icon: Icons.person_remove_outlined,
          ),
        if (p.count == 0) AdvChartNote(t('لا أحد يستلمها — اختر مجموعة أخرى.', 'Nobody would receive it — choose another group.'), icon: Icons.info_outline_rounded),
        if (p.tooLarge)
          AdvChartNote(t('الحد الأقصى $advOutreachMaxRecipients طالب في الرسالة — اختر مجموعة أصغر.', 'At most $advOutreachMaxRecipients students per message — choose a smaller group.'), icon: Icons.warning_amber_rounded),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: inner,
    );
  }
}

/// The composer. [audience] null: the person picks one of [advAudiencePresets]. Answers the message sent.
Future<AdvOutreach?> showAdvOutreachComposer(BuildContext context, {required int orgId, AdvAudience? audience, String? audienceTitle}) =>
    showAppSheet<AdvOutreach>(context, (_) => _ComposerSheet(orgId: orgId, audience: audience, audienceTitle: audienceTitle));

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({required this.orgId, this.audience, this.audienceTitle});
  final int orgId;
  final AdvAudience? audience;
  final String? audienceTitle;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  final _subject = TextEditingController(), _body = TextEditingController();
  late AdvOutreachDraft _draft = AdvOutreachDraft(clientId: advOutreachClientId());
  final _presets = advAudiencePresets();
  int _preset = 0;
  AdvOutreachPreview? _preview;
  bool _loading = true, _busy = false;
  String? _previewError, _error;
  List<AdvOutreachTemplate> _templates = const [];
  int _seq = 0;

  AdvAudience get _audience {
    final a = widget.audience;
    if (a != null) return a;
    final (metric, key, _) = _presets[_preset];
    return AdvAudience(metric: metric, key: key);
  }

  @override
  void initState() {
    super.initState();
    _loadPreview();
    _loadTemplates();
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await orgCall(() => _api.preview(_audience), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _preview = r.data as AdvOutreachPreview;
        _previewError = null;
      } else {
        _preview = null;
        _previewError = r.endpointMissing ? t('الرسائل الجماعية تحتاج تحديث الخادم.', 'Group messages need a server update.') : advErrorText(r.error!);
      }
    });
  }

  Future<void> _loadTemplates() async {
    final r = await orgCall(() => _api.templates(), quiet: true);
    if (mounted && r.ok) setState(() => _templates = r.data as List<AdvOutreachTemplate>);
  }

  void _template(AdvOutreachTemplate? tp) {
    setState(() {
      _draft = _draft.copyWith(templateId: () => tp?.id);
      if (tp != null) {
        _body.text = tp.body;
        if (_subject.text.trim().isEmpty) _subject.text = tp.name;
      }
    });
  }

  void _token(String tok) {
    final sel = _body.selection;
    final (text, at) = advInsertToken(_body.text, tok, sel.isValid ? sel.end : _body.text.length);
    _body.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
  }

  Future<void> _send() async {
    final p = _preview;
    if (p == null) return;
    final draft = _draft.copyWith(subject: _subject.text, body: _body.text);
    final err = draft.error;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final yes = await appConfirm(
      context,
      confirmLabel: t('أرسل', 'Send'),
      message: countText(p.count,
          ar1: 'إرسال «${draft.subject.trim()}» إلى طالب واحد؟', ar2: 'إرسال «${draft.subject.trim()}» إلى طالبين؟', arFew: 'إرسال «${draft.subject.trim()}» إلى ${p.count} طلاب؟',
          arMany: 'إرسال «${draft.subject.trim()}» إلى ${p.count} طالباً؟', en1: 'Send "${draft.subject.trim()}" to 1 student?', en: 'Send "${draft.subject.trim()}" to ${p.count} students?'),
    );
    if (!yes || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(() => _api.send(_audience, p.audienceHash, draft), quiet: true);
    if (!mounted) return;
    if (r.ok) {
      final o = r.data as AdvOutreach;
      showAppNotice(countText(o.recipients == 0 ? p.count : o.recipients,
          ar1: 'يجري الإرسال إلى طالب واحد', ar2: 'يجري الإرسال إلى طالبين', arFew: 'يجري الإرسال إلى ${p.count} طلاب', arMany: 'يجري الإرسال إلى ${p.count} طالباً',
          en1: 'Sending to 1 student', en: 'Sending to ${p.count} students'));
      Navigator.of(context).pop(o);
      return;
    }
    setState(() => _busy = false);
    if (r.code == 'advising_audience_changed') {
      final n = asInt(r.detail['count']);
      showAppNotice(t('تغيّرت القائمة منذ المعاينة — صار عدد المستلمين $n. راجعها ثم أرسل.', 'The list changed since the preview — now $n recipients. Check it, then send.'), error: true);
      _loadPreview();
      return;
    }
    final msg = advErrorText(r.error!);
    setState(() => _error = msg);
    showAppNotice(msg, error: true);
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('رسالة إلى مجموعة طلاب', 'Message a group of students'),
        children: [
          AdvOutreachComposerForm(
            subject: _subject,
            body: _body,
            preview: _preview,
            previewLoading: _loading,
            previewError: _previewError,
            audienceTitle: widget.audienceTitle,
            explicitAudience: widget.audience?.explicit ?? false,
            presets: widget.audience == null ? _presets : null,
            preset: _preset,
            onPreset: (i) {
              setState(() => _preset = i);
              _loadPreview();
            },
            templates: _templates,
            templateId: _draft.templateId,
            onTemplate: _template,
            onToken: _token,
            email: _draft.email,
            onEmail: (v) => setState(() => _draft = _draft.copyWith(email: v)),
            busy: _busy,
            error: _error,
            onSend: _send,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sent messages
// ═════════════════════════════════════════════════════════════════════════════

class AdvOutreachListPage extends StatelessWidget {
  const AdvOutreachListPage({super.key, required this.orgId, required this.manage});
  final int orgId;

  /// A director (everyone's messages); else an advisor's own.
  final bool manage;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('الرسائل الجماعية', 'Group messages'),
        helpPageId: 'org.advising',
        maxWidth: 960,
        child: _ListBody(orgId: orgId, manage: manage),
      );
}

class _ListBody extends StatefulWidget {
  const _ListBody({required this.orgId, required this.manage});
  final int orgId;
  final bool manage;

  @override
  State<_ListBody> createState() => _ListBodyState();
}

class _ListBodyState extends State<_ListBody> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvLoad _load = AdvLoad.loading;
  AdvPage<AdvOutreach>? _page;
  String? _error;
  bool _mine = false;
  int _pageNo = 1, _seq = 0;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    final r = await orgCall(() => _api.outreachList(mine: _mine, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _page = r.data as AdvPage<AdvOutreach>;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _compose() async {
    final o = await showAdvOutreachComposer(context, orgId: widget.orgId);
    if (o == null || !mounted) return;
    await _openTracking(o.id);
  }

  Future<void> _openTracking(int id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvOutreachTrackingPage(orgId: widget.orgId, outreachId: id)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    Widget body;
    if (_load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: _load == AdvLoad.ready ? AdvLoad.loading : _load, errorText: _error, onRetry: _reload);
    } else if (p.items.isEmpty) {
      body = AppEmpty(
        icon: Icons.campaign_outlined,
        title: t('لم تُرسل رسائل جماعية بعد', 'No group messages yet'),
        message: t('راسل مجموعة من الطلاب دفعة واحدة، وتابع من وصلته ومن قرأها.', 'Message a group of students at once, and follow who received and read it.'),
        actionLabel: t('رسالة جديدة', 'New message'),
        onAction: _compose,
      );
    } else {
      body = AdvPageFrame(maxWidth: 960, fab: true, children: [
        for (final o in p.items) AdvOutreachCard(outreach: o, showSender: widget.manage && !_mine, onTap: () => _openTracking(o.id)),
        if (p.pages > 1) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: (n) {
            setState(() {
              _pageNo = n;
              _load = AdvLoad.loading;
            });
            _reload();
          }),
        ],
      ]);
    }
    return OrgPageBody(
      primary: OrgPrimaryAction(icon: Icons.edit_outlined, label: t('رسالة جديدة', 'New message'), onTap: _compose),
      filter: widget.manage
          ? OrgFilterButton<bool>(
              value: _mine,
              defaultValue: false,
              label: t('المرسل', 'Sender'),
              icon: Icons.person_outline_rounded,
              options: {false: t('الكل', 'Everyone'), true: t('رسائلي', 'Mine')},
              onChanged: (v) {
                setState(() {
                  _mine = v;
                  _pageNo = 1;
                  _load = AdvLoad.loading;
                });
                _reload();
              },
            )
          : null,
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Tracking
// ═════════════════════════════════════════════════════════════════════════════

class AdvOutreachTrackingView extends StatelessWidget {
  const AdvOutreachTrackingView({
    super.key,
    required this.load,
    this.outreach,
    this.recipients,
    this.state = 'all',
    this.errorText,
    this.onRetry,
    this.onState,
    this.onSearch,
    this.onPage,
    this.onMessageUnread,
  });

  final AdvLoad load;
  final AdvOutreach? outreach;
  final AdvPage<AdvOutreachRecipient>? recipients;
  final String state;
  final String? errorText;
  final VoidCallback? onRetry, onMessageUnread;
  final ValueChanged<String>? onState, onSearch;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = outreach;
    if (load != AdvLoad.ready || o == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 4);
    }
    final rp = recipients;
    final unread = o.unread;
    return OrgPageBody(
      primary: onMessageUnread != null && unread > 0 && !o.inFlight
          ? OrgPrimaryAction(icon: Icons.mark_email_unread_outlined, label: t('راسل من لم يقرأها', 'Message those who did not read it'), onTap: onMessageUnread!)
          : null,
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث عن طالب', 'Search for a student'), onChanged: onSearch!),
      filter: onState == null
          ? null
          : OrgFilterButton<String>(
              value: state,
              defaultValue: 'all',
              label: t('الحالة', 'State'),
              icon: Icons.mark_email_read_outlined,
              options: {for (final s in advRecipientStates) s: advRecipientStateLabel(s)},
              onChanged: onState!,
            ),
      child: AdvPageFrame(maxWidth: 960, fab: onMessageUnread != null && unread > 0, children: [
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: AdvTypedText(o.subject.isEmpty ? '—' : o.subject, style: AppType.section(context))),
              const SizedBox(width: AppSpace.xs),
              AppBadgePill(advOutreachStatusLabel(o.status), color: advOutreachStatusColor(context, o.status)),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(
              [if (o.sender != null) o.sender!.shown, if (o.createdAt != null) AppTime.dateTime(o.createdAt!), if (o.label.isNotEmpty) o.label].join(' · '),
              style: AppType.meta(context),
            ),
            if ((o.body ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Container(
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
                child: AdvTypedText(o.body!.trim()),
              ),
            ],
            if (o.inFlight) ...[
              const SizedBox(height: AppSpace.sm),
              const AdvBusyStrip(),
              Text(t('يجري الإرسال — تتحدث الأرقام وحدها.', 'Sending — the figures update by themselves.'), style: AppType.meta(context)),
            ],
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t('نسبة القراءة', 'Read rate'), style: AppType.bodyStrong(context))),
              Text(o.readRate == null ? '—' : advRate(o.readRate), textDirection: TextDirection.ltr, style: AppType.figure(context)),
            ]),
            const SizedBox(height: AppSpace.xs),
            AppProgressBar(value: o.readRate ?? 0, height: 8, color: appChartPalette(context).first),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AdvMiniStat(label: t('المستلمون', 'Recipients'), value: '${o.recipients}'),
              AdvMiniStat(label: t('وصلتهم', 'Delivered'), value: '${o.delivered}'),
              AdvMiniStat(label: t('وصلهم إشعار', 'Notified'), value: '${o.pushed}'),
              AdvMiniStat(label: t('قرؤوها', 'Read'), value: '${o.read}', tone: c.success),
              if (o.failed > 0) AdvMiniStat(label: t('لم تصل', 'Not delivered'), value: '${o.failed}', tone: c.danger),
              if (o.capped > 0) AdvMiniStat(label: t('فوق الحد الأسبوعي', 'Over the weekly limit'), value: '${o.capped}'),
              if (o.outOfScope > 0) AdvMiniStat(label: t('خارج نطاقك', 'Outside your students'), value: '${o.outOfScope}'),
            ]),
          ]),
        ),
        AdvSectionTitle(
          t('المستلمون', 'Recipients'),
          subtitle: rp == null ? null : '${advRecipientStateLabel(state)} · ${advStudentsText(rp.total)}',
        ),
        if (rp == null)
          const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
        else if (rp.items.isEmpty)
          AdvChartNote(t('لا أحد في هذه الحالة.', 'Nobody in this state.'), icon: Icons.check_circle_outline_rounded)
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
            child: Column(children: [
              for (var i = 0; i < rp.items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.divider),
                _RecipientRow(r: rp.items[i]),
              ],
            ]),
          ),
        if (rp != null && rp.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: rp.page, pageCount: rp.pages, total: rp.total, pageSize: rp.size, onPage: onPage!),
        ],
      ]),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.r});
  final AdvOutreachRecipient r;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, color, icon) = r.read
        ? (t('قرأها ${AppTime.dateTime(r.readAt!)}', 'Read ${AppTime.dateTime(r.readAt!)}'), c.success, Icons.done_all_rounded)
        : switch (r.status) {
            'delivered' => (t('وصلته، لم يقرأها بعد', 'Delivered, not read yet'), c.primary, Icons.done_rounded),
            'failed' => (t('لم تصل', 'Not delivered'), c.danger, Icons.error_outline_rounded),
            _ => (t('في الانتظار', 'Queued'), c.textMedium, Icons.schedule_rounded),
          };
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            ExcludeSemantics(child: AppAvatar(name: r.shown, size: 32)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.shown, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text([?r.code, label].join(' · '), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            if (r.pushed) Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs), child: Tooltip(message: t('وصله إشعار', 'Notified'), child: Icon(Icons.notifications_active_outlined, size: AppIconSize.sm, color: c.textLight))),
            Icon(icon, size: AppIconSize.md, color: appInk(context, color)),
          ]),
        ),
      ),
    );
  }
}

class AdvOutreachTrackingPage extends StatelessWidget {
  const AdvOutreachTrackingPage({super.key, required this.orgId, required this.outreachId});
  final int orgId, outreachId;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('متابعة الرسالة', 'Message tracking'),
        helpPageId: 'org.advising',
        maxWidth: 960,
        child: _TrackingBody(orgId: orgId, id: outreachId),
      );
}

class _TrackingBody extends StatefulWidget {
  const _TrackingBody({required this.orgId, required this.id});
  final int orgId, id;

  @override
  State<_TrackingBody> createState() => _TrackingBodyState();
}

class _TrackingBodyState extends State<_TrackingBody> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  OrgPageRefresh? _refresh;
  JobWatch? _watch;
  AdvLoad _load = AdvLoad.loading;
  AdvOutreach? _o;
  AdvPage<AdvOutreachRecipient>? _rp;
  String? _error;
  String _state = 'all', _q = '';
  int _pageNo = 1, _seq = 0;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _watch = JobWatch(kind: 'advising_outreach', id: '${widget.id}', onEvent: (_) {
      if (mounted) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    final r = await orgCall(() => _api.outreach(widget.id), quiet: true);
    if (!mounted || seq != _seq) return;
    if (!r.ok) {
      setState(() {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
      });
      return;
    }
    setState(() {
      _o = r.data as AdvOutreach;
      _load = AdvLoad.ready;
    });
    OrgPageRefresh.reportUpdated(context);
    await _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    final seq = _seq;
    final r = await orgCall(() => _api.recipients(widget.id, state: _state, q: _q, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    if (r.ok) {
      setState(() => _rp = r.data as AdvPage<AdvOutreachRecipient>);
    } else {
      showAppNotice(advErrorText(r.error!), error: true);
    }
  }

  void _set({String? state, String? q, int page = 1}) {
    setState(() {
      _state = state ?? _state;
      _q = q ?? _q;
      _pageNo = page;
      _rp = null;
    });
    _loadRecipients();
  }

  Future<void> _messageUnread() async {
    final o = _o;
    if (o == null) return;
    final sent = await showAdvOutreachComposer(
      context,
      orgId: widget.orgId,
      audience: AdvAudience(metric: 'outreach', key: '${o.id}', state: 'unread'),
      audienceTitle: t('من لم يقرأ «${o.subject}»', 'Those who did not read "${o.subject}"'),
    );
    if (sent != null && mounted) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => AdvOutreachTrackingPage(orgId: widget.orgId, outreachId: sent.id)));
    }
  }

  @override
  Widget build(BuildContext context) => AdvOutreachTrackingView(
        load: _load,
        outreach: _o,
        recipients: _rp,
        state: _state,
        errorText: _error,
        onRetry: _reload,
        onState: (s) => _set(state: s),
        onSearch: (q) => _set(q: q),
        onPage: (p) => _set(page: p),
        onMessageUnread: _messageUnread,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The student's side
// ═════════════════════════════════════════════════════════════════════════════

/// One message as the student reads it (plain values).
class AdvStudentMessageView extends StatelessWidget {
  const AdvStudentMessageView({super.key, required this.message});
  final AdvStudentMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvTypedText(m.subject.isEmpty ? '—' : m.subject, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Row(children: [
        ExcludeSemantics(child: Icon(Icons.co_present_outlined, size: AppIconSize.sm, color: c.textMedium)),
        const SizedBox(width: AppSpace.xxs),
        Expanded(
          child: Text(
            [m.senderName.isEmpty ? t('الإرشاد الأكاديمي', 'Academic advising') : m.senderName, if (m.sentAt != null) AppTime.dateTime(m.sentAt!)].join(' · '),
            style: AppType.meta(context),
          ),
        ),
      ]),
      const SizedBox(height: AppSpace.md),
      if ((m.body ?? '').trim().isNotEmpty) AdvTypedText(m.body!.trim(), style: AppType.body(context).copyWith(color: c.textDark, height: 1.6)),
    ]);
  }
}

/// Opens one message for the student and marks it read; answers it as read (null when it could not be opened).
Future<AdvStudentMessage?> showAdvStudentMessage(BuildContext context, {required int orgId, required AdvStudentMessage message}) async {
  var m = message;
  if (m.unread) {
    final r = await orgCall(() => AdvAnalyticsApi.markOutreachRead(orgId, m.id), quiet: true);
    if (r.ok) m = m.markedRead((r.data as DateTime?) ?? DateTime.now().toUtc());
  }
  if (!context.mounted) return m;
  await showAppSheet<void>(context, (_) => AppSheetContent(title: t('رسالة من الإرشاد الأكاديمي', 'Message from academic advising'), children: [AdvStudentMessageView(message: m)]));
  return m;
}

/// The student hub's block: the unread count and the latest messages; [onOpen] one, [onAll] the whole list.
class AdvHubOutreachSection extends StatelessWidget {
  const AdvHubOutreachSection({super.key, required this.hub, this.onOpen, this.onAll});
  final AdvHubOutreach hub;
  final ValueChanged<AdvStudentMessage>? onOpen;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (hub.latest.isEmpty) return const SizedBox.shrink();
    return AdvAnCard(
      icon: Icons.campaign_outlined,
      title: t('رسائل الإرشاد', 'Advising messages'),
      subtitle: hub.unread > 0
          ? countText(hub.unread, ar1: 'رسالة لم تُقرأ', ar2: 'رسالتان لم تُقرآ', arFew: '${hub.unread} رسائل لم تُقرأ', arMany: '${hub.unread} رسالة لم تُقرأ', en1: '1 unread message', en: '${hub.unread} unread messages')
          : t('قرأت كل الرسائل', 'You have read every message'),
      trailing: onAll == null ? null : TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: onAll, child: Text(t('الكل', 'All'))),
      children: [
        for (var i = 0; i < hub.latest.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.divider),
          _MessageRow(m: hub.latest[i], onTap: onOpen == null ? null : () => onOpen!(hub.latest[i])),
        ],
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.m, this.onTap});
  final AdvStudentMessage m;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      label: '${m.unread ? t('غير مقروءة', 'Unread') : ''} ${m.subject}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chipAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: m.unread ? c.primary : Colors.transparent)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AdvTypedText(m.subject.isEmpty ? '—' : m.subject, maxLines: 1, style: AppType.row(context).copyWith(fontWeight: m.unread ? FontWeight.w700 : FontWeight.w500)),
                  Text([if (m.senderName.isNotEmpty) m.senderName, if (m.sentAt != null) AppTime.dateTime(m.sentAt!)].join(' · '), style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Every message the student received. [openId] (the push of one message): that message's sheet opens over the
/// list once it is found; the list is looked through page by page (newest first, so a fresh message is on the first).
class AdvStudentMessagesPage extends StatefulWidget {
  const AdvStudentMessagesPage({super.key, required this.orgId, this.openId});
  final int orgId;
  final int? openId;

  @override
  State<AdvStudentMessagesPage> createState() => _AdvStudentMessagesPageState();
}

class _AdvStudentMessagesPageState extends State<AdvStudentMessagesPage> {
  AdvLoad _load = AdvLoad.loading;
  List<AdvStudentMessage> _items = const [];
  String? _error;
  int _page = 1, _pages = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_reload().then((_) => _openFromLink()));
  }

  /// Answers whether the page loaded.
  Future<bool> _reload({bool more = false}) async {
    final page = more ? _page + 1 : 1;
    final r = await orgCall(() => AdvAnalyticsApi.memberOutreach(widget.orgId, page: page), quiet: true);
    if (!mounted) return false;
    setState(() {
      if (r.ok) {
        final (p, _) = r.data as (AdvPage<AdvStudentMessage>, int);
        _items = more ? [..._items, ...p.items] : p.items;
        _page = p.page;
        _pages = p.pages;
        _load = AdvLoad.ready;
      } else if (!more) {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
      }
    });
    return r.ok;
  }

  /// The message a push named: found in the pages → its sheet over the list; not there (no longer delivered to me)
  /// → a notice, and the list stays.
  Future<void> _openFromLink() async {
    final id = widget.openId;
    if (id == null || !mounted || _load != AdvLoad.ready) return;
    AdvStudentMessage? hit() => _items.where((m) => m.id == id).firstOrNull;
    while (hit() == null && _page < _pages) {
      if (!await _reload(more: true)) return;
    }
    if (!mounted) return;
    final m = hit();
    if (m == null) {
      showAppNotice(t('لم تعد هذه الرسالة متاحة.', 'This message is no longer available.'), error: true);
      return;
    }
    await _open(m);
  }

  Future<void> _open(AdvStudentMessage m) async {
    final read = await showAdvStudentMessage(context, orgId: widget.orgId, message: m);
    if (read != null && mounted) setState(() => _items = [for (final x in _items) x.id == read.id ? read : x]);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_load != AdvLoad.ready) {
      body = AdvLoadState(state: _load, errorText: _error, onRetry: _reload);
    } else if (_items.isEmpty) {
      body = AppEmpty(icon: Icons.mark_email_read_outlined, title: t('لا رسائل بعد', 'No messages yet'), message: t('تظهر هنا رسائل الإرشاد الأكاديمي إليك.', 'Messages from academic advising show here.'));
    } else {
      body = AdvPageFrame(children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
          child: Column(children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: context.colors.divider),
              _MessageRow(m: _items[i], onTap: () => _open(_items[i])),
            ],
          ]),
        ),
        if (_page < _pages)
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: () => _reload(more: true), child: Text(t('المزيد', 'More'))),
      ]);
    }
    final title = t('رسائل الإرشاد', 'Advising messages');
    // a student opens it from the hub: the plain app bar; staff on the dashboard: the org header
    if (orgUsesDashboardHeader(context, widget.orgId)) return OrgPushedPage(title: title, maxWidth: 880, child: body);
    return Scaffold(appBar: AppHeader(title: title), body: body);
  }
}
