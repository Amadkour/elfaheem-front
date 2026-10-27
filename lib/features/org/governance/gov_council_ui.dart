// lib/features/org/governance/gov_council_ui.dart — what the council screens share (gov_councils_page.dart,
// gov_council_settings.dart, gov_session_screen.dart, gov_my_votes.dart): the organization id of a page that may
// be opened from a deep link, status colours, time texts, the countdown, the council entity's team routes (the
// existing `…/departments/{id}/team` API of org_dept_router) and the org member picker.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart' show AppModeController;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show Debouncer, SheetHeader, asInt, asMap, asMapList, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_providers.dart' show OrgApi, OrgSession, orgBase;
import '../org_ui.dart' show orgText;
import '../org_v3.dart' show orgCall;
import 'gov_models.dart';

// ── organization of the page ─────────────────────────────────────────────────

/// The organization a council page works in: an explicit id (a deep link), else the `OrgSession` above the page
/// (the org dashboard pushes every page under one), else the open organization of the app mode.
int? govOrgId(BuildContext context, [int? explicit]) {
  if (explicit != null) return explicit;
  try {
    final id = Provider.of<OrgSession>(context, listen: false).currentId;
    if (id != null) return id;
  } catch (_) {
    // no OrgSession above this page (opened from a notification)
  }
  return AppModeController.instance.currentOrgId;
}

/// Whether the viewer is the organization's admin (every manage action is also gated by the server's `can`).
bool govIsOrgAdmin(BuildContext context) {
  try {
    return Provider.of<OrgSession>(context, listen: false).isOrgAdmin;
  } catch (_) {
    return false;
  }
}

// ── colours ──────────────────────────────────────────────────────────────────

Color sessionStatusColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'draft' => c.textMedium,
    'published' => c.charcoal,
    'voting' => c.warning,
    'closed' => c.success,
    'cancelled' => c.danger,
    _ => c.primary,
  };
}

Color agendaStatusColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'approved' => c.success,
    'rejected' => c.danger,
    'tied' || 'no_quorum' => c.warning,
    'postponed' => c.purple,
    'withdrawn' => c.textLight,
    'voting' => c.primary,
    _ => c.textMedium,
  };
}

Color voteColor(BuildContext context, String v) {
  final c = context.colors;
  return switch (v) {
    'approve' => c.success,
    'reject' => c.danger,
    _ => c.textMedium,
  };
}

IconData voteIcon(String v) => switch (v) {
      'approve' => Icons.thumb_up_alt_rounded,
      'reject' => Icons.thumb_down_alt_rounded,
      _ => Icons.remove_circle_outline_rounded,
    };

IconData sessionKindIcon(String kind) => kind == 'extraordinary' ? Icons.bolt_rounded : Icons.event_repeat_rounded;

// ── time ─────────────────────────────────────────────────────────────────────

/// A server instant (parsed by `orgParseUtc`, local) → "23 Oct 2026 · 8:30 AM" in the organization's zone.
String govWhen(DateTime? d) => d == null ? '' : AppTime.dateTime(d.toUtc());

String govDay(DateTime? d) => d == null ? '' : AppTime.date(d.toUtc());

/// "2 d 3 h" · "3 h 12 m" · "12 m 05 s" · "ended" — the time left until [until].
String countdownText(DateTime until, {DateTime? now}) {
  final d = until.difference(now ?? DateTime.now());
  if (d.isNegative) return t('انتهى', 'ended');
  if (d.inDays >= 1) return t('${d.inDays} ي ${d.inHours % 24} س', '${d.inDays} d ${d.inHours % 24} h');
  if (d.inHours >= 1) return t('${d.inHours} س ${d.inMinutes % 60} د', '${d.inHours} h ${d.inMinutes % 60} m');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return t('${d.inMinutes} د $s ث', '${d.inMinutes} m $s s');
}

/// The regular session date for [sessionDay] after [from] (the day of month, clamped to the month's length).
DateTime nextRegularDate(int sessionDay, String sessionTime, {DateTime? from}) {
  final now = from ?? DateTime.now();
  final p = sessionTime.split(':');
  final h = int.tryParse(p[0]) ?? 10, m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  DateTime at(int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, sessionDay.clamp(1, last), h, m);
  }

  var d = at(now.year, now.month);
  if (!d.isAfter(now)) d = at(now.year, now.month + 1);
  return d;
}

// ── small widgets ────────────────────────────────────────────────────────────

/// "Label: value" line used in headers (wraps on narrow screens).
class GovInfoLine extends StatelessWidget {
  const GovInfoLine(this.icon, this.label, this.value, {super.key, this.color});
  final IconData icon;
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color ?? c.textLight)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label: ', style: orgText(context, size: 12.5, color: c.textMedium)),
              TextSpan(text: value, style: orgText(context, size: 12.5, w: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// A row of pills that wraps instead of overflowing.
class GovPillRow extends StatelessWidget {
  const GovPillRow(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: children);
}

/// The "needs a server update" state of a page whose route the server lacks.
class GovNeedsServer extends StatelessWidget {
  const GovNeedsServer({super.key});

  @override
  Widget build(BuildContext context) => AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: t('تحتاج هذه الميزة إلى تحديث الخادم', 'This feature needs a server update'),
        message: t('المجالس غير متاحة على هذا الخادم بعد', 'Councils are not available on this server yet'),
      );
}

// ── the council entity's team (org_dept_router) ──────────────────────────────

/// Team rows of a department entity: `{id, user: {id, name, email, image_url}, title, is_head}`.
class GovTeamApi {
  GovTeamApi(this.orgId);
  final int orgId;

  String get _base => '$orgBase/orgs/$orgId';

  Future<List<Map<String, dynamic>>?> team(int deptId) async {
    final r = await OrgApi.i.getMap('$_base/departments/$deptId/team');
    return r == null ? null : asMapList(r['items']);
  }

  Future<bool> add(int deptId, {required int userId, String? title, bool isHead = false}) async {
    final r = await orgCall(
        () => ApiClient().post('$_base/departments/$deptId/team', body: {'user_id': userId, 'title': title ?? '', 'is_head': isHead}),
        ok: t('انضم إلى المجلس', 'Joined the council'));
    return r.ok;
  }

  Future<bool> remove(int deptId, int rowId) async {
    final r = await orgCall(() => ApiClient().delete('$_base/departments/$deptId/team/$rowId'), ok: t('تمت الإزالة', 'Removed'));
    return r.ok;
  }

  /// Members of the organization (`GET …/members?q=`): `{id, user: {...}, role}` rows.
  Future<List<Map<String, dynamic>>> members({String q = '', String? roles, int size = 50}) async {
    final r = await OrgApi.i.getMap('$_base/members', {
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'role': ?roles,
      'status': 'active',
      'size': size,
    });
    return r == null ? const [] : asMapList(r['items']);
  }
}

/// Picks one member of the organization (search as you type). Returns the user, or null when dismissed.
Future<GovUser?> pickOrgMember(BuildContext context, int orgId, {String? title, Set<int> exclude = const {}, String? roles}) async {
  final api = GovTeamApi(orgId);
  final debounce = Debouncer(const Duration(milliseconds: 350));
  List<Map<String, dynamic>>? rows;
  var query = '';
  final picked = await showAppSheet<GovUser>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> load() async {
          final r = await api.members(q: query, roles: roles);
          if (!ctx.mounted) return;
          set(() => rows = r);
        }

        if (rows == null) {
          rows = const [];
          load();
        }
        final shown = [
          for (final m in rows!)
            if (!exclude.contains(asInt(asMap(m['user'])['id']))) m,
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(title ?? t('اختر عضواً', 'Choose a member')),
            TextField(
              onChanged: (q) {
                query = q;
                debounce.run(load);
              },
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('ابحث بالاسم أو البريد…', 'Search by name or e-mail…'), isDense: true),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(t('لا نتائج', 'No results'), textAlign: TextAlign.center, style: orgText(ctx, color: c.textMedium)),
                    )
                  : ListView(shrinkWrap: true, children: [
                      for (final m in shown)
                        Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            onTap: () => Navigator.pop(ctx, GovUser(id: asInt(asMap(m['user'])['id']), name: '${asMap(m['user'])['name'] ?? ''}', email: asMap(m['user'])['email'] as String?, avatar: asMap(m['user'])['image_url'] as String?)),
                            leading: AdminAvatar(name: '${asMap(m['user'])['name'] ?? ''}', url: asMap(m['user'])['image_url'] as String?, size: 38),
                            title: Text('${asMap(m['user'])['name'] ?? ''}', style: orgText(ctx, w: FontWeight.w700)),
                            subtitle: Text('${asMap(m['user'])['email'] ?? ''}', textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ]),
            ),
          ]),
        );
      }));
  debounce.dispose();
  return picked;
}
