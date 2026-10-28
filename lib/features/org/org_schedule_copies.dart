// lib/features/org/org_schedule_copies.dart — full timetable copies and per-member copies.
//
// A full copy is a stored revision (POST …/schedules/{sid}/revisions {label, expected_version}): append-only, so a
// copy is never rewritten — a newer copy is a new revision. Its summary records the timetable version it was taken
// at, so a copy is "outdated" as soon as the live timetable has a newer version. Member copies (a teacher's, an
// assistant's, a student group's, a room's) are the copy's own sessions filtered by that member — they are always
// consistent with the copy they come from and carry its number and version.
// Export: the live timetable as the server's Excel (GET /orgs/{id}/export/schedule); a copy or a member copy through the table export sheet.
// Members themselves see their own sessions of PUBLISHED timetables (GET /org/public/schedule/me); sending a copy of
// another version to them needs the server (docs/backend/scheduling-spec.md G5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart' show dayLabels, downloadExcel;
import 'org_providers.dart';
import 'org_schedule_export.dart' show showTimetableExport;
import 'org_schedule_versions.dart';
import 'org_timetable_parts.dart' show courseName;
import 'org_table_export.dart' show showTimetableTableExport;
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppDropdown, AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;

TimetableNames timetableNamesOf(OrgScheduleProvider p) => TimetableNames(
      courses: {for (final l in p.loads) asInt(l['course_id']): courseName(l)},
      people: {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name'] ?? ''}'},
      rooms: {for (final r in p.rooms) asInt(r['id']): '${r['name'] ?? ''}'},
      periods: {for (final x in p.periods) asInt(x['id']): x},
    );

String memberLabel(TimetableMember m, TimetableNames n) => switch (m.kind) {
      'teacher' || 'assistant' => n.person(m.id),
      'room' => n.room(m.id),
      _ => '${n.course(m.id)} · ${m.sessionKind == 'lab' ? t('سكشن', 'Lab') : t('محاضرة', 'Lecture')} G${m.groupNo ?? 1}',
    };

Future<void> openTimetableCopies(BuildContext context, OrgScheduleProvider p, {required bool canEdit}) => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BasePage(
          useWebCard: true,
          maxWith: 1000,
          appBar: ScreenAppBar(title: t('نسخ الجدول', 'Timetable copies'), actions: const [ContextExitButton()]),
          child: _CopiesPage(p: p, canEdit: canEdit),
        )));

class _CopiesPage extends StatefulWidget {
  const _CopiesPage({required this.p, required this.canEdit});
  final OrgScheduleProvider p;
  final bool canEdit;

  @override
  State<_CopiesPage> createState() => _CopiesPageState();
}

class _CopiesPageState extends State<_CopiesPage> {
  List<TimetableCopy>? copies;
  String? error;
  bool saving = false;

  OrgScheduleProvider get p => widget.p;
  int get sid => asInt(p.schedule?['id']);
  int? get version => p.schedule?['version'] == null ? null : asInt(p.schedule!['version']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    final r = await orgCall(() => p.api.get('${p.base}/schedules/$sid/revisions'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        copies = asMapList(r.map['items']).map(TimetableCopy.fromJson).toList();
      } else {
        error = orgErrorText(r.error!);
      }
    });
  }

  Future<void> _save() async {
    final label = TextEditingController(text: t('نسخة كاملة', 'Full copy'));
    final ok = await showAdminSheet<bool>(context, (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('حفظ نسخة كاملة', 'Save a full copy')),
            Text(t('تُحفظ الحصص الحالية كما هي (الإصدار $version). النسخ السابقة لا تتغير.', 'The current sessions are kept exactly as they are (version $version). Earlier copies do not change.'),
                style: orgText(ctx, size: 12, color: ctx.colors.textMedium)),
            TextField(controller: label, maxLength: 80, decoration: InputDecoration(labelText: t('الاسم', 'Name'))),
            PrimaryButton(isLoading: false, label: t('حفظ', 'Save'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    if (ok != true || saving) return;
    setState(() => saving = true);
    // expected_version: the copy is of the version on screen, or the server refuses (stale_version) — never another one
    final r = await orgCall(
        () => p.api.post('${p.base}/schedules/$sid/revisions', body: {'label': label.text.trim().isEmpty ? null : label.text.trim(), 'expected_version': version}),
        quiet: true);
    if (!mounted) return;
    setState(() => saving = false);
    if (!r.ok) {
      toast(orgErrorText(r.error!), error: true);
      if (r.error!.code == 'stale_version') await p.open(sid);
    } else {
      toast(t('حُفظت النسخة', 'Copy saved'));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: p, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.colors;
    final sch = p.schedule ?? const {};
    final list = copies;
    return AppRefresh(
      onRefresh: () async {
        await p.open(sid);
        await _load();
      },
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        OrgSectionTitle(t('الجدول الحالي', 'Live timetable'),
            subtitle: '${sch['name'] ?? ''} · ${t('الإصدار', 'version')} ${version ?? '—'} · ${sch['status'] == 'active' ? t('منشور', 'published') : t('مسودة', 'draft')}'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            ActionChip(
                avatar: Icon(Icons.download_rounded, size: 18, color: c.success),
                label: Text(t('تصدير Excel (الخادم)', 'Export Excel (server)')),
                onPressed: () => downloadExcel(context, 'export/schedule', {'schedule_id': sid})),
            ActionChip(
                avatar: Icon(Icons.groups_rounded, size: 18, color: c.primary),
                label: Text(t('نسخ الأعضاء من الجدول الحالي', 'Member copies of the live timetable')),
                onPressed: () => _openCopy(TimetableCopy(id: 0, label: t('الجدول الحالي', 'Live timetable'), createdAt: null, source: 'live', version: version, slots: p.slots), live: true)),
            if (widget.canEdit)
              ActionChip(
                  avatar: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.library_add_rounded, size: 18, color: c.primary),
                  label: Text(t('حفظ نسخة كاملة', 'Save a full copy')),
                  onPressed: saving ? null : _save),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
              t('يرى كل مدرس ومعيد وطالب حصصه فقط من الجدول المنشور. إرسال نسخة من إصدار آخر إليهم يحتاج تحديثاً في الخادم.',
                  'Each teacher, assistant and student sees only their own sessions of the published timetable. Sending them a copy of another version needs a server update.'),
              style: orgText(context, size: 11.5, color: c.textLight)),
        ),
        OrgSectionTitle(t('النسخ المحفوظة', 'Saved copies')),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [Expanded(child: Text(error!, style: orgText(context, color: c.danger))), TextButton(onPressed: _load, child: Text(t('إعادة المحاولة', 'Retry')))])),
        if (list == null && error == null) const AppListSkeleton(items: 3),
        if (list != null && list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(t('لا توجد نسخ بعد.', 'No copies yet.'), style: orgText(context, color: c.textMedium)))),
        for (final cp in list ?? const <TimetableCopy>[])
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: RowCard(
              onTap: () => _openCopy(cp),
              child: Row(children: [
                Icon(Icons.content_copy_rounded, color: c.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cp.label.isEmpty ? '${t('نسخة', 'Copy')} #${cp.id}' : cp.label, style: orgText(context, w: FontWeight.w800)),
                    Text(
                        [
                          sourceLabel(cp.source),
                          if (cp.version != null) '${t('الإصدار', 'version')} ${cp.version}',
                          if (cp.createdAt != null) AppTime.dateTime(cp.createdAt!),
                        ].join(' · '),
                        style: orgText(context, size: 12, color: c.textMedium)),
                  ]),
                ),
                _freshPill(context, cp.outdated(liveVersion: version, liveSlots: p.slots, detailLoaded: false)),
              ]),
            ),
          ),
      ]),
    );
  }

  Future<void> _openCopy(TimetableCopy cp, {bool live = false}) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BasePage(
            useWebCard: true,
            maxWith: 1000,
            appBar: ScreenAppBar(title: cp.label.isEmpty ? '${t('نسخة', 'Copy')} #${cp.id}' : cp.label, actions: const [ContextExitButton()]),
            child: _CopyDetail(p: p, copy: cp, live: live, canEdit: widget.canEdit, onSaveNew: _save),
          )));
}

String sourceLabel(String s) => switch (s) {
      'generate' => t('توليد', 'Generated'),
      'manual' => t('محفوظة يدوياً', 'Saved by hand'),
      'restore' => t('استرجاع', 'Restore'),
      'publish' => t('عند النشر', 'At publishing'),
      'suggest' => t('اقتراح مطبّق', 'Applied suggestion'),
      'live' => t('مباشر', 'Live'),
      _ => s,
    };

Widget _freshPill(BuildContext context, bool? outdated) {
  final c = context.colors;
  return switch (outdated) {
    false => OrgPill(t('مطابقة للجدول الحالي', 'Matches the live timetable'), color: c.success, icon: Icons.check_circle_rounded),
    true => OrgPill(t('قديمة', 'Outdated'), color: c.warning, icon: Icons.update_rounded),
    null => OrgPill(t('غير معروف', 'Unknown'), color: c.textMedium),
  };
}

class _CopyDetail extends StatefulWidget {
  const _CopyDetail({required this.p, required this.copy, required this.live, required this.canEdit, required this.onSaveNew});
  final OrgScheduleProvider p;
  final TimetableCopy copy;
  final bool live, canEdit;
  final Future<void> Function() onSaveNew;

  @override
  State<_CopyDetail> createState() => _CopyDetailState();
}

class _CopyDetailState extends State<_CopyDetail> {
  late TimetableCopy copy = widget.copy;
  bool loaded = false;
  String? error;
  String kind = 'full';
  TimetableMember? member;

  OrgScheduleProvider get p => widget.p;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final r = await orgCall(() => p.api.get('${p.base}/schedules/${p.schedule!['id']}/revisions/${copy.id}'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        copy = copy.withDetail(r.map);
        loaded = true;
      } else {
        error = orgErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (error != null) return OrgEmpty(icon: Icons.error_outline_rounded, title: t('تعذر فتح النسخة', 'Could not open the copy'), message: error);
    if (!loaded) return const AppListSkeleton();
    final n = timetableNamesOf(p);
    final order = {for (final x in p.periods) asInt(x['id']): asInt(x['order'] ?? x['id'])};
    final liveVersion = p.schedule?['version'] == null ? null : asInt(p.schedule!['version']);
    final outdated = widget.live ? false : copy.outdated(liveVersion: liveVersion, liveSlots: p.slots);
    final members = [for (final m in timetableMembers(copy.slots)) if (m.kind == kind) m]..sort((a, b) => memberLabel(a, n).compareTo(memberLabel(b, n)));
    final m = members.contains(member) ? member : null;
    final shown = kind == 'full' ? sortSlots(copy.slots, periodOrder: order) : (m == null ? const <Map<String, dynamic>>[] : memberTimetable(copy.slots, m, periodOrder: order));
    final head = [
      '${p.schedule?['name'] ?? ''}',
      '${t('النسخة', 'Copy')}: ${widget.live ? t('الجدول الحالي', 'live timetable') : '#${copy.id} ${copy.label}'}',
      '${t('الإصدار', 'Version')}: ${copy.version ?? '—'}',
      if (copy.createdAt != null) '${t('أُنشئت', 'Created')}: ${AppTime.dateTime(copy.createdAt!)}',
      if (m != null) '${memberKindLabel(m.kind)}: ${memberLabel(m, n)}',
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      Wrap(spacing: 6, runSpacing: 4, children: [
        OrgPill(sourceLabel(copy.source), color: c.textMedium),
        if (copy.version != null) OrgPill('${t('الإصدار', 'Version')} ${copy.version}', color: c.primary),
        OrgPill(t('${copy.slots.length} حصة', '${copy.slots.length} sessions'), color: c.accent2),
        _freshPill(context, outdated),
      ]),
      if (outdated == true) ...[
        const SizedBox(height: 8),
        RowCard(
          accent: c.warning,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('تغيّر الجدول بعد هذه النسخة (الإصدار الحالي ${liveVersion ?? '—'}). نسخ الأعضاء أدناه تعكس هذه النسخة لا الجدول الحالي.',
                'The timetable changed after this copy (live version ${liveVersion ?? '—'}). The member copies below reflect this copy, not the live timetable.')),
            if (widget.canEdit)
              Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(onPressed: widget.onSaveNew, icon: const Icon(Icons.library_add_rounded), label: Text(t('حفظ نسخة جديدة من الجدول الحالي', 'Save a new copy of the live timetable')))),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final k in ['full', ...memberKinds])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                  label: Text(k == 'full' ? t('الجدول كاملاً', 'Full timetable') : memberKindLabel(k)),
                  selected: kind == k,
                  onSelected: (_) => setState(() {
                        kind = k;
                        member = null;
                      })),
            ),
        ]),
      ),
      if (kind != 'full') ...[
        const SizedBox(height: 8),
        if (members.isEmpty)
          Text(t('لا يوجد ${memberKindLabel(kind)} في هذه النسخة.', 'No ${memberKindLabel(kind).toLowerCase()} in this copy.'), style: orgText(context, color: c.textMedium))
        else
          AppDropdown<TimetableMember>(
            initialValue: m,
            isExpanded: true,
            decoration: InputDecoration(labelText: memberKindLabel(kind)),
            items: [for (final x in members) DropdownMenuItem(value: x, child: Text(memberLabel(x, n), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => member = v),
          ),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        FilledButton.icon(
          onPressed: copy.slots.isEmpty
              ? null
              : () => showTimetableExport(context,
                  slots: copy.slots,
                  names: n,
                  periods: p.periods,
                  title: '${p.schedule?['name'] ?? t('الجدول', 'Timetable')}',
                  sourceLabel: copy.id == 0
                      ? t('الجدول الحالي · الإصدار ${copy.version ?? '—'}', 'Live timetable · version ${copy.version ?? '—'}')
                      : t('النسخة #${copy.id}${copy.label.isEmpty ? '' : ' «${copy.label}»'} · الإصدار ${copy.version ?? '—'}', 'Copy #${copy.id}${copy.label.isEmpty ? '' : ' “${copy.label}”'} · version ${copy.version ?? '—'}'),
                  days: ScheduleDraft.fromJson(p.schedule ?? const {}).days,
                  member: m),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(t('تصدير احترافي: إكسل · وورد · PDF', 'Premium export: Excel · Word · PDF')),
        ),
        if (kind == 'full' || m != null)
          OutlinedButton.icon(
            onPressed: shown.isEmpty
                ? null
                : () => showTimetableTableExport(context,
                    id: 'org.schedule.copy.sessions',
                    title: '${p.schedule?['name'] ?? t('الجدول', 'Timetable')} · ${m == null ? t('كامل', 'Full') : memberLabel(m, n)} · v${copy.version ?? copy.id}',
                    slots: shown,
                    names: n,
                    meta: head),
            icon: const Icon(Icons.table_view_rounded),
            label: Text(t('تصدير قائمة الحصص', 'Export the session list')),
          ),
        if (kind != 'full' && members.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _exportAll(members, n, order, head.take(4).toList()),
            icon: const Icon(Icons.file_download_done_rounded),
            label: Text(t('تصدير نسخ كل ${memberKindLabel(kind)} (${members.length})', 'Export every ${memberKindLabel(kind).toLowerCase()} copy (${members.length})')),
          ),
      ]),
      const SizedBox(height: 8),
      if (kind != 'full' && m == null && members.isNotEmpty) Text(t('اختر عضواً لعرض حصصه فقط.', 'Pick a member to see only their sessions.'), style: orgText(context, color: c.textMedium)),
      if ((kind == 'full' || m != null) && shown.isEmpty) Text(t('لا حصص.', 'No sessions.'), style: orgText(context, color: c.textMedium)),
      for (final s in shown) _slotLine(context, s, n),
    ]);
  }

  /// One file, one block per member: each row carries its member, so no member's rows can mix with another's.
  void _exportAll(List<TimetableMember> members, TimetableNames n, Map<int, int> order, List<String> head) {
    final rows = <Map<String, dynamic>>[];
    for (final m in members) {
      for (final s in memberTimetable(copy.slots, m, periodOrder: order)) {
        rows.add({...s, '_member': memberLabel(m, n)});
      }
    }
    showTimetableTableExport(context,
        id: 'org.schedule.copy.members',
        title: '${p.schedule?['name'] ?? t('الجدول', 'Timetable')} · ${memberKindLabel(kind)} · v${copy.version ?? copy.id}',
        slots: rows,
        names: n,
        meta: head,
        memberKey: '_member',
        memberLabel: memberKindLabel(kind));
  }

  Widget _slotLine(BuildContext context, Map<String, dynamic> s, TimetableNames n) {
    final c = context.colors;
    final per = n.periods[asInt(s['period_id'])] ?? const {};
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RowCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${dayLabels()['${s['day']}'] ?? s['day']} · ${per['label'] ?? '#${s['period_id']}'} ${periodRange(asMap(per))}',
              style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.primary)),
          Text('${n.course(s['course_id'])} · ${s['kind'] == 'lab' ? t('سكشن', 'Lab') : t('محاضرة', 'Lecture')} G${s['group_no'] ?? 1}', style: orgText(context, w: FontWeight.w700)),
          Text(
              [
                if (s['room_id'] != null) n.room(s['room_id']),
                if (s['teacher_id'] != null) n.person(s['teacher_id']),
                if ((s['assistant_id'] ?? s['admin_assistant_id']) != null) n.person(s['assistant_id'] ?? s['admin_assistant_id']),
              ].join(' · '),
              style: orgText(context, size: 12, color: c.textMedium)),
        ]),
      ),
    );
  }
}
