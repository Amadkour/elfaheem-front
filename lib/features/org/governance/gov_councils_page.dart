// lib/features/org/governance/gov_councils_page.dart — the councils of an organization (the Faculty Council first,
// then the department councils) and ONE council: hero, Sessions · Members · Settings · Rules (spec §3, §5).
//
//   GovCouncilCard         one council in the list (plain values)
//   GovSessionCard         one session in the council's Sessions tab (plain values)
//   NewSessionSheetBody    regular (next regular date) or extraordinary with date/time, title and items
//   GovCouncilsPage        the list (+ "Create Faculty Council" for admins when none exists)
//   GovCouncilPage         the council
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show Field, SheetHeader, asInt, asMap, askText, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_v3.dart' show orgCall;
import 'gov_api.dart';
import 'gov_council_settings.dart';
import 'gov_council_ui.dart';
import 'gov_models.dart';
import 'gov_session_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Cards
// ═════════════════════════════════════════════════════════════════════════════

/// Name · level · chair · members · session day/time · next session · open votes for me.
class GovCouncilCard extends StatelessWidget {
  const GovCouncilCard({super.key, required this.council, this.openVotes = 0, this.onTap});
  final Council council;
  final int openVotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = council;
    final faculty = k.level == 'faculty';
    final col = faculty ? c.purple : c.primary;
    final next = k.nextSession;
    final s = k.settings;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(faculty ? Icons.account_balance_rounded : Icons.groups_2_rounded, color: col),
          ),
          if (openVotes > 0)
            PositionedDirectional(
              top: -6,
              end: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 1),
                decoration: BoxDecoration(color: c.dangerBase, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text(openVotes > 99 ? '99+' : '$openVotes', style: AppType.meta(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.name, style: AppType.section(context)),
            const SizedBox(height: AppSpace.xs),
            GovPillRow([
              AppBadgePill(councilLevelLabel(k.level), color: col, icon: faculty ? Icons.account_balance_rounded : Icons.apartment_rounded),
              AppBadgePill(t('${k.members} أعضاء', '${k.members} members'), color: c.textMedium, icon: Icons.groups_rounded),
              if (openVotes > 0) AppBadgePill(t('$openVotes بانتظار صوتك', '$openVotes waiting for your vote'), color: c.danger, icon: Icons.how_to_vote_rounded),
            ]),
            const SizedBox(height: AppSpace.xs),
            if (k.chair != null) AppInfoRow(Icons.person_pin_rounded, t('الرئيس: ${k.chair!.name}', 'Chair: ${k.chair!.name}')),
            if (s != null && s.sessionDay != null)
              AppInfoRow(Icons.event_repeat_rounded, t('الجلسة الدورية: يوم ${s.sessionDay} من كل شهر · ${AppTime.clock(s.sessionTime)}', 'Regular session: day ${s.sessionDay} of every month · ${AppTime.clock(s.sessionTime)}'))
            else
              AppInfoRow(Icons.event_busy_rounded, t('لا جلسة دورية مجدولة', 'No regular session scheduled')),
            if (next != null) ...[
              const SizedBox(height: AppSpace.xxs),
              GovPillRow([
                Text(t('الجلسة القادمة:', 'Next session:'), style: AppType.meta(context).copyWith(color: c.textMedium)),
                AppBadgePill(sessionStatusLabel(next.status), color: sessionStatusColor(context, next.status)),
                if (next.scheduledAt != null) Text(govWhen(next.scheduledAt), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
              ]),
            ],
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textLight),
      ]),
    );
  }
}

/// Kind · status · date · agenda count · my pending votes.
class GovSessionCard extends StatelessWidget {
  const GovSessionCard({super.key, required this.session, this.onTap});
  final CouncilSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = session;
    final col = sessionStatusColor(context, s.status);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Icon(sessionKindIcon(s.kind), color: col),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((s.title ?? '').trim().isNotEmpty ? s.title!.trim() : sessionKindLabel(s.kind), style: AppType.bodyStrong(context)),
            const SizedBox(height: AppSpace.xxs),
            GovPillRow([
              AppBadgePill(sessionStatusLabel(s.status), color: col),
              if ((s.title ?? '').trim().isNotEmpty) AppBadgePill(sessionKindLabel(s.kind), color: s.kind == 'extraordinary' ? c.purple : c.primary),
              AppBadgePill(t('${s.agenda.length} بنود', '${s.agenda.length} items'), color: c.textMedium, icon: Icons.list_alt_rounded),
              if (s.pendingMyVotes > 0) AppBadgePill(t('${s.pendingMyVotes} بانتظار صوتك', '${s.pendingMyVotes} waiting for your vote'), color: c.danger, icon: Icons.how_to_vote_rounded),
            ]),
            const SizedBox(height: AppSpace.xxs),
            if (s.scheduledAt != null) AppInfoRow(Icons.event_rounded, govWhen(s.scheduledAt)),
            if (s.isVoting && s.votingClosesAt != null) AppInfoRow(Icons.timer_rounded, t('يُغلق التصويت ${govWhen(s.votingClosesAt)}', 'Voting closes ${govWhen(s.votingClosesAt)}')),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textLight),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  New session
// ═════════════════════════════════════════════════════════════════════════════

/// Regular (the next regular date from the settings) or extraordinary (a chosen date/time), a title and the
/// items to put on the agenda from [candidates].
class NewSessionSheetBody extends StatefulWidget {
  const NewSessionSheetBody({super.key, required this.council, required this.candidates, required this.onCreate, this.busy = false});
  final Council council;
  final List<WorkItem> candidates;
  final bool busy;
  final void Function({required String kind, required DateTime scheduledAt, String? title, required List<int> itemIds}) onCreate;

  @override
  State<NewSessionSheetBody> createState() => _NewSessionSheetBodyState();
}

class _NewSessionSheetBodyState extends State<NewSessionSheetBody> {
  late String _kind = widget.council.settings?.sessionDay == null ? 'extraordinary' : 'regular';
  final _title = TextEditingController();
  DateTime? _at;
  final Set<int> _items = {};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime? get _regularAt {
    final s = widget.council.settings;
    if (s?.sessionDay == null) return null;
    return nextRegularDate(s!.sessionDay!, s.sessionTime);
  }

  DateTime? get _effectiveAt => _kind == 'regular' ? _regularAt : _at;

  Future<void> _pick() async {
    final base = _at ?? DateTime.now().add(const Duration(days: 1));
    final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100), initialDate: base);
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null || !mounted) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final regular = _regularAt;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: sessionKindLabel('regular'), icon: Icons.event_repeat_rounded, selected: _kind == 'regular', onTap: regular == null ? () {} : () => setState(() => _kind = 'regular')),
        AppChoiceChip(label: sessionKindLabel('extraordinary'), icon: Icons.bolt_rounded, selected: _kind == 'extraordinary', onTap: () => setState(() => _kind = 'extraordinary')),
      ]),
      const SizedBox(height: AppSpace.sm),
      if (_kind == 'regular')
        AppBanner(
          icon: Icons.event_available_rounded,
          text: regular == null
              ? t('لا يوم جلسة دورية في الإعدادات — اختر جلسة طارئة أو اضبط الإعدادات أولاً', 'No regular session day in the settings — choose an extraordinary session or set it first')
              : t('الموعد الدوري القادم: ${govWhen(regular)}', 'Next regular date: ${govWhen(regular)}'),
        )
      else
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: _pick,
          child: InputDecorator(
            isEmpty: _at == null,
            decoration: InputDecoration(labelText: t('موعد الجلسة', 'Session date & time'), prefixIcon: Icon(Icons.event_rounded, color: c.textLight), suffixIcon: Icon(Icons.edit_calendar_rounded, color: c.textLight, size: AppIconSize.md)),
            child: Text(_at == null ? '' : govWhen(_at), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
          ),
        ),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: _title, label: t('عنوان الجلسة (اختياري)', 'Session title (optional)')),
      Text(t('بنود جدول الأعمال (${_items.length})', 'Agenda items (${_items.length})'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
      const SizedBox(height: AppSpace.xxs),
      if (widget.candidates.isEmpty)
        Text(t('لا معاملات بانتظار المجلس الآن — يمكن إضافتها لاحقاً من الجلسة', 'No items wait for the council now — they can be added later from the session'), style: AppType.meta(context).copyWith(color: c.textMedium))
      else
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final it in widget.candidates)
              CheckboxListTile(
                value: _items.contains(it.id),
                onChanged: (v) => setState(() => v == true ? _items.add(it.id) : _items.remove(it.id)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(it.title, style: AppType.bodyStrong(context)),
                subtitle: Text([it.ref, itemTypeLabel(it.type), itemStatusLabel(it.status)].where((x) => x.isNotEmpty).join(' · '), style: AppType.meta(context).copyWith(color: c.textMedium)),
              ),
          ]),
        ),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(
        label: t('إنشاء الجلسة', 'Create the session'),
        icon: Icons.add_rounded,
        busy: widget.busy,
        onPressed: widget.busy || _effectiveAt == null
            ? null
            : () => widget.onCreate(kind: _kind, scheduledAt: _effectiveAt!, title: _title.text.trim().isEmpty ? null : _title.text.trim(), itemIds: _items.toList()),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Councils list
// ═════════════════════════════════════════════════════════════════════════════

class GovCouncilsPage extends StatefulWidget {
  const GovCouncilsPage({super.key, this.orgId, this.onOpenItem, this.onExport});
  final int? orgId;
  final void Function(WorkItem item)? onOpenItem;
  final void Function(CouncilSession session)? onExport;

  @override
  State<GovCouncilsPage> createState() => _GovCouncilsPageState();
}

class _GovCouncilsPageState extends State<GovCouncilsPage> {
  List<Council>? _rows;
  Map<int, int> _openVotes = const {}; // council dept id → agenda items waiting for my vote
  bool _failed = false, _missing = false, _busy = false;

  int? get _orgId => govOrgId(context, widget.orgId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final oid = _orgId;
    if (oid == null) {
      setState(() => _failed = true);
      return;
    }
    final api = GovApi(oid);
    final r = await orgCall(() => api.councils(), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _failed = _rows == null;
        _missing = r.endpointMissing;
      });
      return;
    }
    final rows = (r.data as List).cast<Council>()
      ..sort((a, b) {
        if (a.level != b.level) return a.level == 'faculty' ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final votes = await orgCall(() => api.myVotes(), quiet: true);
    if (!mounted) return;
    final open = <int, int>{};
    if (votes.ok) {
      // an agenda item of /me/votes carries the item; its owner is the council entity while it is in council
      for (final a in (votes.data as List).cast<AgendaItem>()) {
        final dept = a.item.ownerDept?.id;
        if (dept != null) open[dept] = (open[dept] ?? 0) + 1;
      }
    }
    setState(() {
      _rows = rows;
      _openVotes = open;
      _failed = false;
    });
  }

  Future<void> _createFaculty() async {
    final oid = _orgId;
    if (oid == null) return;
    final nameAr = TextEditingController(text: 'مجلس الكلية'), nameEn = TextEditingController(text: 'Faculty Council');
    GovUser? head;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SheetHeader(t('إنشاء مجلس الكلية', 'Create the Faculty Council')),
                Field(controller: nameAr, label: t('الاسم بالعربية', 'Arabic name')),
                Field(controller: nameEn, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () async {
                    final u = await pickOrgMember(ctx, oid, title: t('رئيس المجلس', 'Council head'));
                    if (u != null) set(() => head = u);
                  },
                  child: InputDecorator(
                    isEmpty: head == null,
                    decoration: InputDecoration(labelText: t('رئيس المجلس (العميد)', 'Council head (the dean)'), prefixIcon: Icon(Icons.person_search_rounded, color: c.textLight)),
                    child: Text(head?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(ctx)),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                AppPrimaryButton(
                  label: t('إنشاء', 'Create'),
                  icon: Icons.account_balance_rounded,
                  busy: _busy,
                  onPressed: _busy
                      ? null
                      : () async {
                          set(() => _busy = true);
                          final r = await orgCall(
                              () => GovApi(oid).createFacultyCouncil(nameAr: nameAr.text.trim(), nameEn: nameEn.text.trim(), headUserId: head?.id),
                              ok: t('أُنشئ مجلس الكلية', 'Faculty Council created'));
                          if (!ctx.mounted) return;
                          set(() => _busy = false);
                          if (r.ok) Navigator.pop(ctx);
                        },
                ),
              ]),
            ),
          );
        }));
    nameAr.dispose();
    nameEn.dispose();
    _load();
  }

  Future<void> _open(Council k) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GovCouncilPage(k.id, orgId: _orgId, onOpenItem: widget.onOpenItem, onExport: widget.onExport)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final admin = govIsOrgAdmin(context);
    final hasFaculty = rows?.any((k) => k.level == 'faculty') ?? true;
    final Widget body;
    if (_missing) {
      body = const GovNeedsServer();
    } else if (rows == null) {
      body = _failed
          ? AppEmpty(icon: Icons.error_outline_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 4);
    } else {
      final waiting = _openVotes.values.fold(0, (a, b) => a + b);
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xl), children: [
          AppHero(
            title: t('المجالس', 'Councils'),
            subtitle: t('مجلس الكلية ومجالس الأقسام: الجلسات والتصويت والمحاضر', 'The Faculty Council and the department councils: sessions, voting and minutes'),
            icon: Icons.account_balance_rounded,
            stats: [
              AppHeroStat(icon: Icons.groups_2_rounded, value: '${rows.length}', label: t('مجالس', 'councils')),
              AppHeroStat(icon: Icons.how_to_vote_rounded, value: '$waiting', label: t('بانتظار صوتي', 'waiting for me')),
            ],
          ),
          if (admin && !hasFaculty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
              child: AppBanner(
                icon: Icons.account_balance_rounded,
                text: t('لا يوجد مجلس كلية بعد — إليه تُصعَّد بنود مجالس الأقسام', 'There is no Faculty Council yet — department councils escalate to it'),
                action: TextButton(onPressed: _createFaculty, child: Text(t('إنشاء', 'Create'), style: AppType.bodyStrong(context).copyWith(color: context.colors.primary))),
              ),
            ),
          if (rows.isEmpty)
            AppEmpty(
              icon: Icons.groups_2_rounded,
              title: t('لا مجالس بعد', 'No councils yet'),
              message: t('يُنشأ مجلس لكل قسم علمي تلقائياً عند إنشائه', 'A council is created for every scientific department automatically'),
              actionLabel: admin ? t('إنشاء مجلس الكلية', 'Create the Faculty Council') : null,
              onAction: admin ? _createFaculty : null,
            ),
          for (final k in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
              child: GovCouncilCard(council: k, openVotes: _openVotes[k.dept.id] ?? 0, onTap: () => _open(k)),
            ),
        ]),
      );
    }
    // a sub-page of the dashboard's Services section: the section's header (title · Refresh · switcher) is above it
    if (OrgPageRefresh.maybeOf(context, listen: false) != null) return body;
    // opened on its own (staff only): the dashboard's header, Back first
    return OrgPushedPage(helpPageId: 'org.governance', title: t('المجالس', 'Councils'), child: body);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One council
// ═════════════════════════════════════════════════════════════════════════════

/// Hero (chair · members · next session) and the tabs Sessions · Members · Settings · Rules. Opened from the
/// councils list and from a scientific department's "Council" tab (the coordinator passes its `council_id`).
class GovCouncilPage extends StatefulWidget {
  const GovCouncilPage(this.councilId, {super.key, this.orgId, this.onOpenItem, this.onExport, this.initialTab = 0});
  final int councilId;
  final int? orgId;
  final void Function(WorkItem item)? onOpenItem;
  final void Function(CouncilSession session)? onExport;
  final int initialTab;

  @override
  State<GovCouncilPage> createState() => _GovCouncilPageState();
}

class _GovCouncilPageState extends State<GovCouncilPage> {
  Council? _k;
  List<CouncilSession>? _sessions;
  bool _failed = false, _missing = false, _busy = false;

  int? get _orgId => govOrgId(context, widget.orgId);
  GovApi? get _api => _orgId == null ? null : GovApi(_orgId!);
  bool get _manager => (_k?.can['manage'] ?? false) || govIsOrgAdmin(context);

  /// The header's Refresh reloads the council; "Updated" is when it answered.
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) {
      setState(() => _failed = true);
      return;
    }
    final r = await orgCall(() => api.council(widget.councilId), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _failed = _k == null;
        _missing = r.endpointMissing;
      });
      return;
    }
    setState(() {
      _k = r.data as Council;
      _failed = false;
    });
    final sr = await orgCall(() => api.sessions(widget.councilId), quiet: true);
    if (!mounted) return;
    setState(() {
      _sessions = sr.ok
          ? ((sr.data as List).cast<CouncilSession>()..sort((a, b) => (b.scheduledAt ?? DateTime(2000)).compareTo(a.scheduledAt ?? DateTime(2000))))
          : (_sessions ?? const []);
    });
    _refresh.markUpdated();
  }

  Future<void> _openSession(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GovSessionScreen(id, orgId: _orgId, onOpenItem: widget.onOpenItem, onExport: widget.onExport)));
    if (mounted) _load();
  }

  Future<void> _newSession() async {
    final api = _api, k = _k;
    if (api == null || k == null) return;
    final onAgenda = <int>{
      for (final s in _sessions ?? const <CouncilSession>[])
        if (!s.isClosed && s.status != 'cancelled')
          for (final a in s.agenda) a.item.id,
    };
    final candidates = await fetchAgendaCandidates(api, k, exclude: onAgenda);
    if (!mounted) return;
    int? created;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetHeader(t('جلسة جديدة', 'New session')),
              Flexible(
                child: NewSessionSheetBody(
                  council: k,
                  candidates: candidates,
                  busy: _busy,
                  onCreate: ({required kind, required scheduledAt, title, required itemIds}) async {
                    set(() => _busy = true);
                    final r = await orgCall(() => api.createSession(k.id, kind: kind, scheduledAt: scheduledAt, title: title, itemIds: itemIds), ok: t('أُنشئت الجلسة', 'Session created'));
                    if (!ctx.mounted) return;
                    set(() => _busy = false);
                    if (r.ok) {
                      created = r.map['id'] == null ? null : asInt(r.map['id']);
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ),
            ]),
          );
        }));
    if (!mounted) return;
    _busy = false;
    await _load();
    if (created != null && mounted) _openSession(created!);
  }

  Widget _sessionsTab(Council k) {
    final c = context.colors;
    final rows = _sessions;
    return ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xl), children: [
      if (_manager)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppPill(icon: Icons.add_rounded, label: t('جلسة جديدة', 'New session'), color: c.success, onTap: _busy ? null : _newSession),
          ]),
        ),
      if (rows == null)
        const AppListSkeleton(items: 3, withAvatar: false)
      else if (rows.isEmpty)
        AppEmpty(
          icon: Icons.event_note_rounded,
          title: t('لا جلسات بعد', 'No sessions yet'),
          message: k.settings?.sessionDay != null
              ? t('تُنشأ الجلسة الدورية تلقائياً كل شهر، أو أنشئ جلسة الآن', 'The regular session is created every month by itself, or create one now')
              : t('اضبط يوم الجلسة الدورية في الإعدادات، أو أنشئ جلسة طارئة', 'Set the regular session day in Settings, or create an extraordinary session'),
          actionLabel: _manager ? t('جلسة جديدة', 'New session') : null,
          onAction: _manager ? _newSession : null,
        )
      else
        for (final s in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
            child: GovSessionCard(session: s, onTap: () => _openSession(s.id)),
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = _k;
    final Widget body;
    if (_missing) {
      body = const GovNeedsServer();
    } else if (k == null) {
      body = _failed
          ? AppEmpty(icon: Icons.error_outline_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 4, withAvatar: false);
    } else {
      final next = k.nextSession;
      body = DefaultTabController(
        length: 4,
        initialIndex: widget.initialTab.clamp(0, 3),
        child: Column(children: [
          AppHero(
            title: k.name,
            subtitle: [councilLevelLabel(k.level), if (k.parentDept != null) k.parentDept!.name].join(' · '),
            icon: k.level == 'faculty' ? Icons.account_balance_rounded : Icons.groups_2_rounded,
            stats: [
              AppHeroStat(icon: Icons.person_pin_rounded, value: k.chair == null ? '—' : k.chair!.name.split(' ').take(2).join(' '), label: t('الرئيس', 'chair')),
              AppHeroStat(icon: Icons.groups_rounded, value: '${k.members}', label: t('أعضاء', 'members')),
              AppHeroStat(
                icon: Icons.event_rounded,
                value: next == null ? t('لا شيء', 'none') : (next.scheduledAt == null ? sessionStatusLabel(next.status) : govDay(next.scheduledAt)),
                label: t('الجلسة القادمة', 'next session'),
              ),
            ],
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: c.primary,
            unselectedLabelColor: c.textMedium,
            indicatorColor: c.primary,
            labelStyle: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark),
            tabs: [
              Tab(text: t('الجلسات', 'Sessions')),
              Tab(text: t('الأعضاء', 'Members')),
              Tab(text: t('الإعدادات', 'Settings')),
              Tab(text: t('القواعد', 'Rules')),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _sessionsTab(k),
              _CouncilTeam(orgId: _orgId!, deptId: k.dept.id, canEdit: _manager, onChanged: _load),
              GovCouncilSettingsPage(councilId: k.id, section: GovSettingsSection.session, orgId: _orgId, embedded: true),
              GovCouncilSettingsPage(councilId: k.id, section: GovSettingsSection.rules, orgId: _orgId, embedded: true),
            ]),
          ),
        ]),
      );
    }
    // staff only (the councils list, a department's quick action): the dashboard's header — Back · the council ·
    // its level line · Refresh (reloads the council in place) · calendar · bell · switcher
    return OrgPushedPage(helpPageId: 'org.governance', 
      title: k?.name ?? t('المجلس', 'Council'),
      subtitle: k == null ? null : [councilLevelLabel(k.level), if (k.parentDept != null) k.parentDept!.name].join(' · '),
      refresh: _refresh,
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Members (the council entity's team)
// ═════════════════════════════════════════════════════════════════════════════

class _CouncilTeam extends StatefulWidget {
  const _CouncilTeam({required this.orgId, required this.deptId, required this.canEdit, required this.onChanged});
  final int orgId, deptId;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<_CouncilTeam> createState() => _CouncilTeamState();
}

class _CouncilTeamState extends State<_CouncilTeam> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  GovTeamApi get _api => GovTeamApi(widget.orgId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await _api.team(widget.deptId);
    if (!mounted) return;
    setState(() {
      _rows = r ?? _rows;
      _failed = r == null && _rows == null;
    });
  }

  Future<void> _add() async {
    final taken = {for (final x in _rows ?? const <Map<String, dynamic>>[]) asInt(asMap(x['user'])['id'])};
    final u = await pickOrgMember(context, widget.orgId, title: t('إضافة عضو إلى المجلس', 'Add a council member'), exclude: taken);
    if (u == null || !mounted) return;
    final title = await askText(context, title: t('الصفة في المجلس (اختياري)', 'Role in the council (optional)'), hint: t('مثلاً: ممثل الهيئة المعاونة', 'e.g. Teaching assistants representative'));
    if (!mounted) return;
    if (await _api.add(widget.deptId, userId: u.id, title: title)) {
      _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    if (rows == null) {
      return _failed
          ? AppEmpty(icon: Icons.error_outline_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 4);
    }
    return ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xl), children: [
      if (widget.canEdit)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
          child: Wrap(spacing: AppSpace.xs, children: [AppPill(icon: Icons.person_add_alt_1_rounded, label: t('إضافة عضو', 'Add a member'), color: c.success, onTap: _add)]),
        ),
      if (rows.isEmpty)
        AppEmpty(
          icon: Icons.groups_rounded,
          title: t('لا أعضاء بعد', 'No members yet'),
          message: t('أعضاء المجلس هم من يصوّتون على بنود جدول الأعمال', 'Council members are the people who vote on the agenda'),
        ),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(children: [
              AdminAvatar(name: '${asMap(r['user'])['name'] ?? ''}', url: asMap(r['user'])['image_url'] as String?),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GovPillRow([
                    Text('${asMap(r['user'])['name'] ?? ''}', style: AppType.bodyStrong(context)),
                    if (r['is_head'] == true) AppBadgePill(t('الرئيس', 'Chair'), color: c.warning, icon: Icons.star_rounded),
                  ]),
                  Text('${(r['title'] ?? '').toString().isEmpty ? t('عضو المجلس', 'Council member') : r['title']}', style: AppType.meta(context).copyWith(color: c.textMedium)),
                ]),
              ),
              if (widget.canEdit && r['is_head'] != true)
                IconButton(
                  tooltip: t('إزالة', 'Remove'),
                  onPressed: () async {
                    if (await appConfirm(context, message: t('إزالة العضو من المجلس؟ لن يصوّت بعدها.', 'Remove this member from the council? They will no longer vote.'), danger: true)) {
                      if (await _api.remove(widget.deptId, asInt(r['id']))) {
                        _load();
                        widget.onChanged();
                      }
                    }
                  },
                  icon: Icon(Icons.person_remove_rounded, color: c.danger),
                ),
            ]),
          ),
        ),
    ]);
  }
}
