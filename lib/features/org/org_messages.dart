// lib/features/org/org_messages.dart
//
// Institutions S4, the sender's side (contract docs/institutions/CONTRACT_S4.md, back D-975 – D-978):
//   msgServiceSubs(s)          the org dashboard's Services → "Messages" sub-page (kill switch org.messages)
//   OrgMessagesPage            the messages I sent: one primary action (New message), cards with read /
//                              acknowledged / pending counts; a card opens the names sheet. Reloads on
//                              `org_message_ack`.
//   SentMessageCard            one sent message (plain values)
//   SentNamesView              the names sheet: All · Acknowledged · Pending (· Unread), with AppTime times
//   openMessageComposer        the composer as a pushed page; with complaintId / workItemId it writes to that
//                              item's submitter only (the server picks them, its team only)
//   MessageComposerView        recipients (students by name · a department's audience · a course's students),
//                              the three delivery cards (Must acknowledge only when GET …/options says I may),
//                              reason + expiry (3 days by default, 7 at most), the "N recipients" dry run
//   msgSubmitterAction         the "Message the submitter" button for a complaint / request screen
// The views take plain values (test/org/institutions_s4_test.dart pumps them through expectNoLayoutErrors).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show daysText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMapList, t;
import 'governance/gov_ui.dart' show pickGovPerson;
import 'org_messages_models.dart';
import 'org_page_header.dart' show OrgPushedPage;
import 'org_page_kit.dart';
import 'org_providers.dart';
import 'org_ui.dart' show OrgAsync, orgNameOf;

/// Services → "Messages" (every non-student org role may send; the server checks again).
List<(String, String, IconData, Widget)> msgServiceSubs(OrgSession s) {
  if (!orgMessagesEnabled() || s.currentId == null) return const [];
  return [('messages', t('الرسائل', 'Messages'), Icons.forward_to_inbox_rounded, OrgMessagesPage(orgId: s.currentId!))];
}

/// The "Message the submitter" button of a complaint / request screen (null when the switch is off).
Widget? msgSubmitterAction(BuildContext context, {required int orgId, int? complaintId, int? workItemId}) {
  if (!orgMessagesEnabled() || (complaintId == null && workItemId == null)) return null;
  return AppButton.tonal(
    key: const ValueKey('msg.submitter'),
    label: t('مراسلة مقدّم الطلب', 'Message the submitter'),
    icon: Icons.forward_to_inbox_rounded,
    onPressed: () => openMessageComposer(context, orgId: orgId, complaintId: complaintId, workItemId: workItemId),
  );
}

Future<bool?> openMessageComposer(BuildContext context, {required int orgId, int? complaintId, int? workItemId}) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: const RouteSettings(name: '/org_message_compose'),
      builder: (_) => MessageComposerPage(orgId: orgId, complaintId: complaintId, workItemId: workItemId),
    ));

// ═════════════════════════════════════════════════════════════════════════════
//  Sent list
// ═════════════════════════════════════════════════════════════════════════════

class OrgMessagesPage extends StatefulWidget {
  const OrgMessagesPage({super.key, required this.orgId});
  final int orgId;

  @override
  State<OrgMessagesPage> createState() => _OrgMessagesPageState();
}

class _OrgMessagesPageState extends State<OrgMessagesPage> {
  late final MsgApi _api = MsgApi(widget.orgId);
  List<OrgMessage>? _items;
  bool _failed = false;
  StreamSubscription<LiveEvent>? _live;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _live = LiveEvents.instance.listen({LiveEvents.orgMessageAck}, (e) {
      if (e.orgId != null && e.orgId != widget.orgId) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), _load);      // a wave of acknowledgements → one reload
    });
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.sent();
    if (!mounted) return;
    setState(() {
      _failed = !r.ok;
      if (r.ok) _items = [for (final j in asMapList(r.map['items'])) OrgMessage.fromJson(j)];
    });
  }

  Future<void> _compose() async {
    final sent = await openMessageComposer(context, orgId: widget.orgId);
    if (sent == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return OrgPageBody(
      primary: OrgPrimaryAction(id: 'msg.new', icon: Icons.edit_rounded, label: t('رسالة جديدة', 'New message'), onTap: _compose),
      child: items == null
          ? OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink())
          : items.isEmpty
              ? AppEmpty(
                  icon: Icons.forward_to_inbox_rounded,
                  title: t('لم ترسل رسائل بعد', 'No messages sent yet'),
                  message: t('راسل طالباً أو جمهور إدارة أو طلاب مقرر.', 'Write to a student, a department\'s audience or a course\'s students.'),
                  actionLabel: t('رسالة جديدة', 'New message'),
                  onAction: _compose,
                )
              : AppRefresh(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxl + AppSpace.xl),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => AppSpace.gapSm,
                    itemBuilder: (_, i) => SentMessageCard(message: items[i], onTap: () => showSentNamesSheet(context, _api, items[i])),
                  ),
                ),
    );
  }
}

/// "3 of 5 acknowledged · 2 pending" / "4 of 5 read".
String msgStatsLine(OrgMessage m) {
  final s = m.stats ?? const MsgStats();
  if (m.mustAck) {
    return '${t('أقرّ', 'Acknowledged')} ${s.acknowledged}/${s.recipients} · ${t('بانتظار', 'Pending')} ${s.pending}';
  }
  return '${t('قرأها', 'Read')} ${s.read}/${s.recipients}';
}

class SentMessageCard extends StatelessWidget {
  const SentMessageCard({super.key, required this.message, required this.onTap});
  final OrgMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final s = m.stats ?? const MsgStats();
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          AppSpace.gapXs,
          Flexible(child: _DeliveryBadge(m.delivery)),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(msgRecipientsText(s.recipients), style: AppType.label(context)),
          Text(msgStatsLine(m), style: AppType.label(context)),
          if (m.createdAt != null) Text(AppTime.dateTime(m.createdAt!.toUtc()), style: AppType.meta(context)),
          if (m.mustAck && m.expired) AppStatusBadge(label: t('انتهت', 'Expired'), dense: true),
          if (m.linked) AppStatusBadge(label: m.workItemId != null ? t('عن طلب', 'About a request') : t('عن شكوى', 'About a complaint'), tone: AppTone.info, dense: true),
        ]),
      ]),
    );
  }
}

class _DeliveryBadge extends StatelessWidget {
  const _DeliveryBadge(this.d);
  final MsgDelivery d;

  @override
  Widget build(BuildContext context) => AppStatusBadge(
        label: msgDeliveryLabel(d),
        dense: true,
        tone: switch (d) {
          MsgDelivery.normal => AppTone.neutral,
          MsgDelivery.push => AppTone.info,
          MsgDelivery.mustAck => AppTone.warning,
        },
      );
}

// ── the names sheet ──

Future<void> showSentNamesSheet(BuildContext context, MsgApi api, OrgMessage m) =>
    showAppSheet<void>(context, (_) => _NamesSheet(api: api, message: m));

class _NamesSheet extends StatefulWidget {
  const _NamesSheet({required this.api, required this.message});
  final MsgApi api;
  final OrgMessage message;

  @override
  State<_NamesSheet> createState() => _NamesSheetState();
}

class _NamesSheetState extends State<_NamesSheet> {
  MsgRecipientFilter _filter = MsgRecipientFilter.all;
  MsgDetail? _detail;
  bool _loading = true;
  StreamSubscription<LiveEvent>? _live;

  @override
  void initState() {
    super.initState();
    _live = LiveEvents.instance.listen({LiveEvents.orgMessageAck}, (e) {
      if (asInt(e.data['message_id']) == widget.message.id) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.api.detail(widget.message.id, filter: _filter);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _detail = MsgDetail.fromJson(r.map);
    });
  }

  @override
  Widget build(BuildContext context) => SentNamesView(
        message: _detail?.message ?? widget.message,
        recipients: _detail?.recipients ?? const [],
        total: _detail?.total ?? 0,
        filter: _filter,
        loading: _loading,
        onFilter: (f) {
          _filter = f;
          _load();
        },
      );
}

/// The filters the sheet offers for a message (Pending only for must-acknowledge).
List<MsgRecipientFilter> msgFiltersFor(OrgMessage m) =>
    m.mustAck ? const [MsgRecipientFilter.all, MsgRecipientFilter.acknowledged, MsgRecipientFilter.pending] : const [MsgRecipientFilter.all, MsgRecipientFilter.unread];

String msgFilterLabel(MsgRecipientFilter f) => switch (f) {
      MsgRecipientFilter.all => t('الكل', 'All'),
      MsgRecipientFilter.acknowledged => t('أقرّوا', 'Acknowledged'),
      MsgRecipientFilter.pending => t('بانتظار', 'Pending'),
      MsgRecipientFilter.unread => t('لم يقرؤوا', 'Unread'),
    };

class SentNamesView extends StatelessWidget {
  const SentNamesView({
    super.key,
    required this.message,
    required this.recipients,
    required this.total,
    required this.filter,
    required this.onFilter,
    this.loading = false,
  });

  final OrgMessage message;
  final List<MsgRecipient> recipients;
  final int total;
  final MsgRecipientFilter filter;
  final ValueChanged<MsgRecipientFilter> onFilter;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    final s = m.stats ?? const MsgStats();
    final filters = msgFiltersFor(m);
    int? countOf(MsgRecipientFilter f) => switch (f) {
          MsgRecipientFilter.all => s.recipients,
          MsgRecipientFilter.acknowledged => s.acknowledged,
          MsgRecipientFilter.pending => s.pending,
          MsgRecipientFilter.unread => (s.recipients - s.read).clamp(0, s.recipients),
        };
    return AppSheetContent(
      title: m.title,
      icon: Icons.people_alt_rounded,
      tone: AppTone.info,
      subtitle: msgStatsLine(m),
      children: [
        AppTabs(
          hug: true,
          items: [for (final f in filters) AppTabItem(msgFilterLabel(f), count: countOf(f))],
          index: filters.indexOf(filter).clamp(0, filters.length - 1),
          onChanged: (i) => onFilter(filters[i]),
        ),
        AppSpace.gapSm,
        if (loading && recipients.isEmpty)
          const AppListSkeleton(items: 4)
        else if (recipients.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text(t('لا أحد هنا', 'No one here'), textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium)),
          )
        else ...[
          for (final r in recipients) _NameRow(r: r, mustAck: m.mustAck),
          if (total > recipients.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(t('و${total - recipients.length} آخرون', 'and ${total - recipients.length} more'), style: AppType.meta(context)),
            ),
        ],
      ],
    );
  }
}

class _NameRow extends StatelessWidget {
  const _NameRow({required this.r, required this.mustAck});
  final MsgRecipient r;
  final bool mustAck;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = mustAck ? r.ackedAt : r.readAt;
    final String when;
    if (done != null) {
      when = '${mustAck ? t('أقرّ', 'Acknowledged') : t('قرأها', 'Read')} ${AppTime.dateTime(done.toUtc())}';
    } else if (mustAck && r.readAt != null) {
      when = '${t('فتحها', 'Opened')} ${AppTime.dateTime(r.readAt!.toUtc())} · ${t('لم يقرّ بعد', 'not acknowledged yet')}';
    } else {
      when = mustAck ? t('بانتظار الإقرار', 'Pending') : t('لم يقرأها بعد', 'Not read yet');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Icon(done != null ? Icons.check_circle_rounded : Icons.schedule_rounded, color: done != null ? c.success : c.textLight, size: AppIconSize.md),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.user.shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              Text(when, style: AppType.meta(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Composer
// ═════════════════════════════════════════════════════════════════════════════

class MessageComposerPage extends StatefulWidget {
  const MessageComposerPage({super.key, required this.orgId, this.complaintId, this.workItemId});
  final int orgId;
  final int? complaintId, workItemId;

  @override
  State<MessageComposerPage> createState() => _MessageComposerPageState();
}

class _MessageComposerPageState extends State<MessageComposerPage> {
  late final MsgApi _api = MsgApi(widget.orgId);
  late final MsgDraft _draft = MsgDraft(complaintId: widget.complaintId, workItemId: widget.workItemId);
  final _title = TextEditingController(), _body = TextEditingController(), _reason = TextEditingController();
  MsgOptions? _options;
  bool _failed = false, _busy = false;
  int? _count, _queued;
  String? _error;
  Timer? _dry;
  int _dryEpoch = 0;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    if (_draft.linked) _dryRun();
  }

  @override
  void dispose() {
    _dry?.cancel();
    _title.dispose();
    _body.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() => _failed = false);
    final r = await _api.options();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _options = MsgOptions.fromJson(r.map);
        _draft.expiryDays = msgAckDefaultDays.clamp(1, _options!.ackMaxDays);
      } else {
        _failed = true;
        _error = msgErrorText(r.error!);
      }
    });
  }

  /// The "N recipients" line: a dry run after the audience changes (it never counts toward the daily limit).
  void _audienceChanged() {
    setState(() {
      _count = null;
      _queued = null;
      _error = null;
    });
    _dry?.cancel();
    if (!_draft.hasAudience) return;
    _dry = Timer(const Duration(milliseconds: 400), _dryRun);
  }

  Future<void> _dryRun() async {
    final epoch = ++_dryEpoch;
    final r = await _api.send(_draft.dryRunBody());
    if (!mounted || epoch != _dryEpoch) return;
    setState(() {
      if (r.ok) {
        _count = asInt(r.map['recipients']);
        _queued = asInt(r.map['queued']);
      } else {
        _count = null;
        _error = msgErrorText(r.error!);
      }
    });
  }

  Future<void> _addStudents() async {
    final p = await pickGovPerson(context, widget.orgId,
        title: t('أضف طالباً', 'Add a student'), roles: const ['student'], excludeIds: {for (final s in _draft.students) s.id});
    if (p == null || !mounted) return;
    _draft.students.add(MsgPick(p.id, p.name));
    _audienceChanged();
  }

  Future<MsgPick?> _pickFrom(String title, String path, Map<String, dynamic> query) async {
    final s = context.read<OrgSession>();
    final r = await OrgApi.i.getMap('${s.base}/$path', query);
    if (!mounted || r == null) return null;
    final rows = asMapList(r['items']);
    if (rows.isEmpty) {
      showAppNotice(t('لا شيء للاختيار', 'Nothing to choose'), error: true);
      return null;
    }
    return showAppSheet<MsgPick>(
        context,
        (ctx) => AppSheetContent(title: title, icon: Icons.groups_rounded, children: [
              for (final m in rows)
                ListTile(
                  minTileHeight: AppTouch.min,
                  title: Text(orgNameOf(m).isEmpty ? '${m['title'] ?? m['name'] ?? '#${m['id']}'}' : orgNameOf(m), style: AppType.row(ctx)),
                  onTap: () => Navigator.pop(ctx, MsgPick(asInt(m['id']), orgNameOf(m).isEmpty ? '${m['title'] ?? m['name'] ?? ''}' : orgNameOf(m))),
                ),
            ]));
  }

  Future<void> _pickDept() async {
    final p = await _pickFrom(t('جمهور إدارة', 'A department\'s audience'), 'departments', const {});
    if (p == null) return;
    _draft.dept = p;
    _audienceChanged();
  }

  Future<void> _pickCourse() async {
    final p = await _pickFrom(t('طلاب مقرر', 'A course\'s students'), 'courses', const {'size': 100, 'scope': 'tree'});
    if (p == null) return;
    _draft.course = p;
    _audienceChanged();
  }

  Future<void> _send() async {
    final o = _options ?? const MsgOptions();
    _draft
      ..title = _title.text
      ..body = _body.text
      ..reason = _reason.text;
    final p = _draft.problem(o);
    if (p != null) {
      setState(() => _error = msgCodeText(p));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.send(_draft.toBody());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = msgErrorText(r.error!));
      return;
    }
    final n = asInt(r.map['recipients']);
    showAppNotice('${t('أُرسلت إلى', 'Sent to')} ${msgRecipientsText(n)}');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    return OrgPushedPage(
      title: _draft.linked ? t('مراسلة مقدّم الطلب', 'Message the submitter') : t('رسالة جديدة', 'New message'),
      width: AppWidth.form,
      child: o == null
          ? OrgAsync(loading: !_failed, failed: _failed, onRetry: _loadOptions, child: const SizedBox.shrink())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.md),
              child: MessageComposerView(
                draft: _draft,
                options: o,
                title: _title,
                body: _body,
                reason: _reason,
                count: _count,
                queued: _queued,
                busy: _busy,
                error: _error,
                onDelivery: (d) => setState(() {
                  _draft.delivery = d;
                  _error = null;
                }),
                onExpiry: (d) => setState(() => _draft.expiryDays = d),
                onAddStudents: _addStudents,
                onPickDept: _pickDept,
                onPickCourse: _pickCourse,
                onRemoveStudent: (p) {
                  _draft.students.remove(p);
                  _audienceChanged();
                },
                onClearDept: () {
                  _draft.dept = null;
                  _audienceChanged();
                },
                onClearCourse: () {
                  _draft.course = null;
                  _audienceChanged();
                },
                onSend: _send,
              ),
            ),
    );
  }
}

/// The composer, plain values: recipients · title and text · delivery (three cards) · reason + expiry · send.
class MessageComposerView extends StatelessWidget {
  const MessageComposerView({
    super.key,
    required this.draft,
    required this.options,
    required this.title,
    required this.body,
    required this.reason,
    required this.onDelivery,
    required this.onExpiry,
    required this.onSend,
    this.onAddStudents,
    this.onPickDept,
    this.onPickCourse,
    this.onRemoveStudent,
    this.onClearDept,
    this.onClearCourse,
    this.count,
    this.queued,
    this.busy = false,
    this.error,
  });

  final MsgDraft draft;
  final MsgOptions options;
  final TextEditingController title, body, reason;
  final ValueChanged<MsgDelivery> onDelivery;
  final ValueChanged<int> onExpiry;
  final VoidCallback onSend;
  final VoidCallback? onAddStudents, onPickDept, onPickCourse, onClearDept, onClearCourse;
  final ValueChanged<MsgPick>? onRemoveStudent;
  final int? count, queued;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ack = draft.delivery == MsgDelivery.mustAck;
    final deliveries = [MsgDelivery.normal, MsgDelivery.push, if (options.showMustAck) MsgDelivery.mustAck];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── recipients ──
      AppSection(
        spaceAbove: false,
        title: t('إلى', 'To'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (draft.linked)
            AppCard(
              child: Row(children: [
                Icon(Icons.person_rounded, color: c.primary, size: AppIconSize.lg),
                AppSpace.gapSm,
                Expanded(
                  child: Text(
                    draft.workItemId != null ? t('مقدّم هذا الطلب', 'The submitter of this request') : t('مقدّم هذه الشكوى', 'The submitter of this complaint'),
                    style: AppType.bodyStrong(context),
                  ),
                ),
              ]),
            )
          else ...[
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final s in draft.students)
                InputChip(
                  avatar: const Icon(Icons.person_rounded, size: AppIconSize.sm),
                  label: Text(s.name, overflow: TextOverflow.ellipsis),
                  onDeleted: onRemoveStudent == null ? null : () => onRemoveStudent!(s),
                  deleteButtonTooltipMessage: t('إزالة', 'Remove'),
                ),
              if (draft.dept != null)
                InputChip(
                  avatar: const Icon(Icons.apartment_rounded, size: AppIconSize.sm),
                  label: Text('${t('جمهور', 'Audience of')} ${draft.dept!.name}', overflow: TextOverflow.ellipsis),
                  onDeleted: onClearDept,
                  deleteButtonTooltipMessage: t('إزالة', 'Remove'),
                ),
              if (draft.course != null)
                InputChip(
                  avatar: const Icon(Icons.menu_book_rounded, size: AppIconSize.sm),
                  label: Text('${t('طلاب', 'Students of')} ${draft.course!.name}', overflow: TextOverflow.ellipsis),
                  onDeleted: onClearCourse,
                  deleteButtonTooltipMessage: t('إزالة', 'Remove'),
                ),
            ]),
            if (draft.hasAudience) AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppButton.secondary(label: t('طلاب بالاسم', 'Students by name'), icon: Icons.person_add_alt_rounded, onPressed: onAddStudents),
              if (draft.dept == null)
                AppButton.secondary(label: t('جمهور إدارة', 'A department\'s audience'), icon: Icons.apartment_rounded, onPressed: onPickDept),
              if (draft.course == null)
                AppButton.secondary(label: t('طلاب مقرر', 'A course\'s students'), icon: Icons.menu_book_rounded, onPressed: onPickCourse),
            ]),
          ],
          if (draft.hasAudience) ...[
            AppSpace.gapXs,
            Text(
              count == null
                  ? t('جارٍ حساب المستلمين…', 'Counting the recipients…')
                  : '${t('ستصل إلى', 'Reaches')} ${msgRecipientsText(count!)}'
                      '${ack && (queued ?? 0) > 0 ? ' · ${t('لدى ${queued!} منهم إقرار ينتظر، تظهر رسالتك لهم بعده', '${queued!} of them already have one waiting; yours shows after it')}' : ''}',
              style: AppType.label(context).copyWith(color: c.textMedium),
            ),
          ],
        ]),
      ),
      // ── the message ──
      AppSection(
        title: t('الرسالة', 'Message'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(controller: title, label: t('العنوان', 'Title'), maxLength: 160, icon: Icons.title_rounded),
          AppSpace.gapSm,
          AppField(controller: body, label: t('النص', 'Text'), maxLines: 6, maxLength: 4000),
        ]),
      ),
      // ── delivery ──
      AppSection(
        title: t('طريقة التسليم', 'Delivery'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in deliveries) ...[
            _DeliveryCard(
              delivery: d,
              selected: draft.delivery == d,
              enabled: d != MsgDelivery.mustAck || options.ackLeft > 0,
              note: d == MsgDelivery.mustAck
                  ? '${t('المتبقي اليوم', 'Left today')}: ${options.ackLeft}/${options.ackLimit}'
                      '${options.headOnly ? ' · ${t('لطلاب أقسامك فقط', 'your departments\' students only')}' : ''}'
                  : null,
              onTap: () => onDelivery(d),
            ),
            AppSpace.gapXs,
          ],
        ]),
      ),
      if (ack) ...[
        AppSpace.gapXs,
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: appToneTint(context, AppTone.warning), borderRadius: AppRadius.cardAll),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: appToneInk(context, AppTone.warning), size: AppIconSize.md),
            AppSpace.gapXs,
            Expanded(
              child: Text(
                t('ستغطي هذه الرسالة شاشة الطالب ولن يستطيع استخدام التطبيق حتى يقرّ بقراءتها.',
                    'This message blocks the student\'s screen until they confirm they have read it.'),
                style: AppType.body(context).copyWith(color: appToneInk(context, AppTone.warning)),
              ),
            ),
          ]),
        ),
        AppSpace.gapSm,
        AppField(controller: reason, label: t('السبب (يراه الطالب)', 'Reason (the student sees it)'), maxLength: 500, maxLines: 2, required: true),
        AppSpace.gapSm,
        Text(t('تنتهي بعد', 'Expires after'), style: AppType.label(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (var d = 1; d <= options.ackMaxDays; d++)
            ChoiceChip(
              label: Text(daysText(d)),
              selected: draft.expiryDays == d,
              onSelected: (_) => onExpiry(d),
            ),
        ]),
      ],
      if (error != null) ...[
        AppSpace.gapMd,
        Text(error!, style: AppType.body(context).copyWith(color: c.danger)),
      ],
      AppSpace.gapLg,
      AppButton.primary(
        key: const ValueKey('msg.send'),
        label: t('إرسال', 'Send'),
        icon: Icons.send_rounded,
        expand: true,
        busy: busy,
        onPressed: busy ? null : onSend,
      ),
    ]);
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.delivery, required this.selected, required this.onTap, this.enabled = true, this.note});
  final MsgDelivery delivery;
  final bool selected, enabled;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (delivery) {
      MsgDelivery.normal => Icons.mail_outline_rounded,
      MsgDelivery.push => Icons.notifications_active_rounded,
      MsgDelivery.mustAck => Icons.mark_email_unread_rounded,
    };
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: selected ? c.primaryWash : c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
          ),
          child: InkWell(
            key: ValueKey('msg.delivery.${msgDeliveryWire(delivery)}'),
            borderRadius: AppRadius.cardAll,
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(children: [
                  Icon(icon, color: selected ? c.primary : c.textMedium, size: AppIconSize.lg),
                  AppSpace.gapSm,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(msgDeliveryLabel(delivery), style: AppType.bodyStrong(context)),
                      Text(msgDeliverySentence(delivery), style: AppType.meta(context)),
                      if (note != null) Text(note!, style: AppType.meta(context)),
                    ]),
                  ),
                  Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? c.primary : c.textLight),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
