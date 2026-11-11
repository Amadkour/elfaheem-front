// lib/features/org/governance/gov_ui.dart — the small shared pieces of the governance screens: status / type /
// kind icons and colours, pills, date helpers (every displayed time goes through AppTime, in UTC), the date
// pickers, and the organization-member search sheet (`pickGovPerson`) used by routing, assignment, delegation and
// form assignment. Presentational widgets take plain values so the layout harness can pump them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show Debouncer, SheetHeader, asInt, asMap, asMapList, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show orgCall;
import 'gov_models.dart';

// ── dates ───────────────────────────────────────────────────────────────────

/// `orgParseUtc` gives local time; AppTime wants the UTC instant.
String govWhen(DateTime? d) => d == null ? '' : AppTime.dateTime(d.toUtc());

String govDay(DateTime? d) => d == null ? '' : AppTime.date(d.toUtc());

/// "in 3 h" / "2 d ago" for a due date; empty without one.
String govDueText(DateTime? due) {
  if (due == null) return '';
  final diff = due.difference(DateTime.now());
  if (diff.isNegative) {
    final a = diff.abs();
    if (a.inHours < 1) return t('تأخر منذ ${a.inMinutes} د', '${a.inMinutes} min late');
    if (a.inHours < 48) return t('تأخر منذ ${a.inHours} س', '${a.inHours} h late');
    return t('تأخر منذ ${a.inDays} يوم', '${a.inDays} d late');
  }
  if (diff.inHours < 1) return t('خلال ${diff.inMinutes} د', 'in ${diff.inMinutes} min');
  if (diff.inHours < 48) return t('خلال ${diff.inHours} س', 'in ${diff.inHours} h');
  return t('خلال ${diff.inDays} يوم', 'in ${diff.inDays} d');
}

/// A calendar day (local midnight) — returns null when dismissed.
Future<DateTime?> pickGovDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(now.year - 2),
    lastDate: last ?? DateTime(now.year + 3),
  );
}

/// Date then time; the result is the UTC instant to send with `orgUtc`.
Future<DateTime?> pickGovDateTime(BuildContext context, {DateTime? initial, DateTime? first}) async {
  final now = DateTime.now();
  final local = initial?.toLocal() ?? now.add(const Duration(days: 1));
  final d = await showDatePicker(
    context: context,
    initialDate: local.isBefore(first ?? now) ? (first ?? now) : local,
    firstDate: first ?? DateTime(now.year - 1),
    lastDate: DateTime(now.year + 3),
  );
  if (d == null || !context.mounted) return null;
  final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(local));
  if (tm == null) return null;
  return DateTime(d.year, d.month, d.day, tm.hour, tm.minute).toUtc();
}

// ── colours & icons ─────────────────────────────────────────────────────────

Color govStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'open' => c.primary,
    'in_review' || 'pending_approval' => c.warning,
    'in_council' => c.purple,
    'approved' => c.success,
    'rejected' => c.danger,
    'postponed' => c.textMedium,
    _ => c.textLight,
  };
}

Color govPriorityColor(BuildContext context, String p) => switch (p) {
      'urgent' => context.colors.danger,
      'high' => context.colors.warning,
      'low' => context.colors.textLight,
      _ => context.colors.primary,
    };

Color govOutcomeColor(BuildContext context, String o) {
  final c = context.colors;
  return switch (o) {
    'approved' => c.success,
    'rejected' => c.danger,
    'tied' || 'no_quorum' => c.warning,
    _ => c.textMedium,
  };
}

IconData govTypeIcon(String type) => switch (type) {
      'complaint' => Icons.support_agent_rounded,
      'request' => Icons.inbox_rounded,
      'form' => Icons.assignment_rounded,
      'memo' => Icons.sticky_note_2_rounded,
      'agenda' => Icons.gavel_rounded,
      _ => Icons.widgets_rounded,
    };

IconData govKindIcon(String kind) => switch (kind) {
      'service' => Icons.apartment_rounded,
      'scientific' => Icons.school_rounded,
      'council' => Icons.groups_2_rounded,
      'office' => Icons.business_center_rounded,
      _ => Icons.category_rounded,
    };

IconData govActionIcon(String action) => switch (action) {
      'info' => Icons.info_outline_rounded,
      'review' => Icons.rate_review_rounded,
      'approval' => Icons.verified_rounded,
      'vote' => Icons.how_to_vote_rounded,
      _ => Icons.alt_route_rounded,
    };

IconData govEventIcon(String kind) => switch (kind) {
      'created' => Icons.add_circle_outline_rounded,
      'updated' => Icons.edit_rounded,
      'routed' || 'forwarded' => Icons.alt_route_rounded,
      'escalated' => Icons.trending_up_rounded,
      'assigned' => Icons.person_add_alt_1_rounded,
      'decided' => Icons.gavel_rounded,
      'locked_out' => Icons.lock_outline_rounded,
      'status' => Icons.flag_rounded,
      'comment' => Icons.chat_bubble_outline_rounded,
      'attachment' => Icons.attach_file_rounded,
      'agenda' => Icons.event_note_rounded,
      'vote_opened' || 'vote_closed' || 'voted' => Icons.how_to_vote_rounded,
      'exported' => Icons.file_download_rounded,
      'delegation' => Icons.swap_horiz_rounded,
      'reminder' => Icons.alarm_rounded,
      'withdrawn' => Icons.undo_rounded,
      'reopened' => Icons.refresh_rounded,
      _ => Icons.circle_outlined,
    };

/// What a route action asks of the target (shown under the choice).
String routeActionHelp(String action) => switch (action) {
      'info' => t('يطّلع المستلم فقط؛ تبقى المعاملة عندك', 'The target just takes note; the item stays with you'),
      'review' => t('يراجع المستلم ويرد برأيه؛ تبقى المعاملة عندك', 'The target reviews and answers; the item stays with you'),
      'approval' => t('تنتقل المعاملة إلى الجهة المستلمة ليعتمدها رئيسها أو من فوّضه', 'The item moves to the target entity for its head (or a delegate) to decide'),
      'vote' => t('تنتقل المعاملة إلى المجلس لتُطرح للتصويت في جلسته القادمة', 'The item moves to the council for a vote at its next session'),
      _ => '',
    };

// ── pills ───────────────────────────────────────────────────────────────────

class GovStatusPill extends StatelessWidget {
  const GovStatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => AppBadgePill(itemStatusLabel(status), color: govStatusColor(context, status));
}

class GovTypePill extends StatelessWidget {
  const GovTypePill(this.type, {super.key});
  final String type;
  @override
  Widget build(BuildContext context) => AppBadgePill(itemTypeLabel(type), color: context.colors.textMedium, icon: govTypeIcon(type));
}

class GovPriorityPill extends StatelessWidget {
  const GovPriorityPill(this.priority, {super.key});
  final String priority;
  @override
  Widget build(BuildContext context) =>
      AppBadgePill(priorityLabelOf(priority), color: govPriorityColor(context, priority), icon: priority == 'urgent' ? Icons.bolt_rounded : null);
}

class GovOutcomePill extends StatelessWidget {
  const GovOutcomePill(this.outcome, {super.key});
  final String outcome;
  @override
  Widget build(BuildContext context) =>
      AppBadgePill('${t('المجلس', 'Council')}: ${voteOutcomeLabel(outcome)}', color: govOutcomeColor(context, outcome), icon: Icons.how_to_vote_rounded);
}

/// "Overdue" (danger) or "due in …" (muted); nothing without a due date.
class GovDuePill extends StatelessWidget {
  const GovDuePill({super.key, required this.dueAt, required this.overdue});
  final DateTime? dueAt;
  final bool overdue;
  @override
  Widget build(BuildContext context) {
    if (dueAt == null) return const SizedBox.shrink();
    final c = context.colors;
    if (overdue || dueAt!.isBefore(DateTime.now())) {
      return AppBadgePill('${t('متأخر', 'Overdue')} · ${govDueText(dueAt)}', color: c.danger, icon: Icons.timer_off_rounded);
    }
    return AppBadgePill(govDueText(dueAt), color: c.textMedium, icon: Icons.timer_rounded);
  }
}

/// A small "label: value" line used in headers.
class GovKV extends StatelessWidget {
  const GovKV(this.icon, this.label, this.value, {super.key, this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: AppIconSize.sm, color: c.textLight),
          const SizedBox(width: AppSpace.xs),
          Text('$label: ', style: AppType.label(context).copyWith(color: c.textLight)),
          Expanded(child: Text(value, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
        ]),
      ),
    );
  }
}

/// A multi-select row of chips over a vocabulary (types, statuses, outcomes …).
class GovChipSelect extends StatelessWidget {
  const GovChipSelect({super.key, required this.options, required this.selected, required this.onChanged, required this.label, this.icon});
  final Map<String, String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: c.textLight), const SizedBox(width: AppSpace.xs)],
        Flexible(child: Text(label, style: AppType.meta(context).copyWith(color: c.textLight))),
      ]),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final e in options.entries)
          AppChoiceChip(
            label: e.value,
            selected: selected.contains(e.key),
            onTap: () {
              final n = [...selected];
              selected.contains(e.key) ? n.remove(e.key) : n.add(e.key);
              onChanged(n);
            },
          ),
      ]),
    ]);
  }
}

/// A tappable "field" showing a picked date (or a placeholder) with a clear button.
class GovDateField extends StatelessWidget {
  const GovDateField({super.key, required this.label, required this.value, required this.onPick, required this.onClear, this.withTime = false, this.icon = Icons.event_rounded});
  final String label;
  final DateTime? value;
  final VoidCallback onPick, onClear;
  final bool withTime;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = value == null ? '' : (withTime ? govWhen(value) : govDay(value));
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onPick,
      child: InputDecorator(
        isEmpty: text.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: c.textLight),
          suffixIcon: value == null ? null : IconButton(tooltip: t('مسح', 'Clear'), icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight), onPressed: onClear),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
      ),
    );
  }
}

// ── people ──────────────────────────────────────────────────────────────────

/// One row of the organization's member list (`GET …/members`) as a GovUser.
GovUser? govUserOfMember(Map<String, dynamic> row) {
  final u = asMap(row['user']);
  if (u['id'] == null) return null;
  return GovUser(id: asInt(u['id']), name: '${u['name'] ?? ''}', email: u['email'] as String?, avatar: u['image_url'] as String?);
}

/// Loads up to [size] live members of [orgId] matching [query] (name / e-mail), any role.
Future<List<GovUser>> searchGovPeople(int orgId, String query, {List<String>? roles, int size = 30, ApiClient? client}) async {
  final q = query.trim();
  final r = await orgCall(
      () => (client ?? ApiClient()).get('$orgBase/orgs/$orgId/members', queryParams: {
            if (q.isNotEmpty) 'search': q,
            if (q.isNotEmpty) 'q': q,
            'role': ?roles?.join(','),
            'status': 'active',
            'size': size,
          }),
      quiet: true);
  if (!r.ok) return const [];
  return [for (final m in asMapList(r.map['items'])) ?govUserOfMember(m)];
}

/// The people search body: a search box + results; presentational (the sheet feeds it).
class GovPeopleList extends StatelessWidget {
  const GovPeopleList({super.key, required this.people, required this.onPick, this.loading = false, this.selectedId, this.query = '', this.excludeIds = const {}});
  final List<GovUser> people;
  final ValueChanged<GovUser> onPick;
  final bool loading;
  final int? selectedId;
  final String query;
  final Set<int> excludeIds;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = people.where((p) => !excludeIds.contains(p.id)).toList();
    if (loading) return const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Text(query.isEmpty ? t('اكتب اسماً للبحث', 'Type a name to search') : t('لا نتائج', 'No results'),
            textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: c.textMedium)),
      );
    }
    return ListView(shrinkWrap: true, children: [
      for (final p in shown)
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            onTap: () => onPick(p),
            leading: AdminAvatar(name: p.name, url: p.avatar, size: 38),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
            subtitle: p.email == null ? null : Text(p.email!, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
            trailing: selectedId == p.id ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            tileColor: selectedId == p.id ? c.primary.withValues(alpha: 0.07) : null,
          ),
        ),
    ]);
  }
}

/// Opens the member search sheet of [orgId]; returns the picked person or null.
Future<GovUser?> pickGovPerson(BuildContext context, int orgId, {String? title, List<String>? roles, Set<int> excludeIds = const {}, int? selectedId}) {
  return showAppSheet<GovUser>(context, (ctx) => _PeopleSheet(orgId: orgId, title: title, roles: roles, excludeIds: excludeIds, selectedId: selectedId));
}

class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({required this.orgId, this.title, this.roles, this.excludeIds = const {}, this.selectedId});
  final int orgId;
  final String? title;
  final List<String>? roles;
  final Set<int> excludeIds;
  final int? selectedId;
  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  final _debounce = Debouncer(const Duration(milliseconds: 400));
  List<GovUser> _people = const [];
  bool _loading = true;
  String _q = '';

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
    final r = await searchGovPeople(widget.orgId, _q, roles: widget.roles);
    if (!mounted) return;
    setState(() {
      _people = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(widget.title ?? t('اختر شخصاً', 'Pick a person')),
        TextField(
          autofocus: false,
          onChanged: (v) {
            _q = v;
            _debounce.run(_load);
          },
          style: AppType.row(context).copyWith(color: c.textDark),
          decoration: InputDecoration(
            hintText: t('ابحث بالاسم أو البريد…', 'Search by name or e-mail…'),
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            filled: true,
            fillColor: c.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Flexible(
          child: GovPeopleList(
            people: _people,
            loading: _loading,
            query: _q,
            selectedId: widget.selectedId,
            excludeIds: widget.excludeIds,
            onPick: (p) => Navigator.pop(context, p),
          ),
        ),
      ]),
    );
  }
}

/// A picked person shown as a field: tap → [onPick]; clear → [onClear].
class GovPersonField extends StatelessWidget {
  const GovPersonField({super.key, required this.label, required this.person, required this.onPick, this.onClear});
  final String label;
  final GovUser? person;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onPick,
      child: InputDecorator(
        isEmpty: person == null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.person_search_rounded, color: c.textLight),
          suffixIcon: person == null || onClear == null
              ? Icon(Icons.unfold_more_rounded, color: c.textLight)
              : IconButton(tooltip: t('مسح', 'Clear'), icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight), onPressed: onClear),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
        ),
        child: Text(person?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
      ),
    );
  }
}

/// A bottom-sheet note box + confirm used by decide / answer / escalate / status.
/// [required] / [minLength]: a missing or too short note keeps the sheet open (with what was typed) and says why
/// under the field ([tooShort], or a generic text).
Future<String?> askGovNote(BuildContext context,
    {required String title, String? hint, String? confirmLabel, bool danger = false, bool required = false, int minLength = 0, String? tooShort}) async {
  final ctrl = TextEditingController();
  String? error;
  final r = await showAppSheet<String>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(title),
            AppField(
              controller: ctrl,
              label: hint ?? t('ملاحظة (اختياري)', 'Note (optional)'),
              maxLines: 3,
              onChanged: (_) {
                if (error != null) set(() => error = null);
              },
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, bottom: AppSpace.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, size: AppIconSize.sm, color: c.danger),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(error!, style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w600, color: c.danger))),
                ]),
              ),
            const SizedBox(height: AppSpace.sm),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger ? c.danger : c.primary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
              onPressed: () {
                final v = ctrl.text.trim();
                if (required && v.isEmpty) {
                  set(() => error = tooShort ?? t('اكتب السبب', 'Write the reason'));
                  return;
                }
                if (v.isNotEmpty && v.length < minLength) {
                  set(() => error = tooShort ?? t('السبب قصير جدًا', 'The reason is too short'));
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(confirmLabel ?? t('تأكيد', 'Confirm'), style: AppType.bodyStrong(ctx).copyWith(color: c.onHero)),
            ),
          ]),
        );
      }));
  return r;
}

/// "Needs a server update" banner for an older backend without the governance routes.
class GovNeedsServer extends StatelessWidget {
  const GovNeedsServer({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppBanner(
          icon: Icons.cloud_off_rounded,
          color: context.colors.warning,
          text: t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update'),
        ),
      );
}
