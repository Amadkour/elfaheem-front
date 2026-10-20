// lib/features/org/org_schedule_pages.dart — the physical timetable studio.
//
//   Timetable tab   schedules list → studio (weekly grid, generate, edit by hand, conflicts, publish)
//   Setup tab       periods + rooms (positions)
//   Planning tab    per course: teacher · assistants · admin assistant · sessions/week · periods/session · room type,
//                   student-group availability; per staff member: availability (days × periods)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_availability_pages.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';

class OrgSchedulePage extends StatelessWidget {
  const OrgSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    if (!s.can('schedule')) return OrgEmpty(icon: Icons.lock_rounded, title: t('لا تملك صلاحية عرض الجدول', 'You cannot view the timetable'));
    return ChangeNotifierProvider(create: (_) => OrgScheduleProvider(s)..loadSetup(), child: const _ScheduleView());
  }
}

class _ScheduleView extends StatelessWidget {
  const _ScheduleView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final c = context.colors;
    if (!p.loaded) return const Center(child: AppLoadingIndicator(size: 64));
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16)),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(14)),
            labelColor: Colors.white,
            unselectedLabelColor: c.textMedium,
            labelStyle: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 13),
            tabs: [Tab(text: t('الجداول', 'Timetables'), height: 40), Tab(text: t('التخطيط', 'Planning'), height: 40), Tab(text: t('الإعداد', 'Setup'), height: 40)],
          ),
        ),
        const Expanded(child: TabBarView(children: [_TimetablesTab(), _PlanningTab(), _SetupTab()])),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Setup: periods + rooms
// ═════════════════════════════════════════════════════════════════════════════

class _SetupTab extends StatelessWidget {
  const _SetupTab();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      Section(
        title: t('الفترات الدراسية', 'Periods'),
        icon: Icons.schedule_rounded,
        trailing: s.can('schedule', 'insert') ? IconButton(onPressed: () => _periodForm(context, p, null), icon: Icon(Icons.add_circle_rounded, color: c.primary)) : null,
        child: p.periods.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text(t('أضف فترات اليوم الدراسي (مثال: 08:30 – 10:00).', 'Add the teaching periods of the day (e.g. 08:30 – 10:00).')))
            : Column(children: [
                for (final x in p.periods)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 16, backgroundColor: c.primary.withValues(alpha: 0.12), child: Text('${x['order']}', style: TextStyle(color: c.primary, fontWeight: FontWeight.w800))),
                    title: Text('${x['label']}', style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
                    subtitle: Text('${x['start_time']} – ${x['end_time']}', textDirection: TextDirection.ltr),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (s.can('schedule', 'update')) IconButton(icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => _periodForm(context, p, x)),
                      if (s.can('schedule', 'delete')) IconButton(icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger), onPressed: () async {
                        if (await confirm(context, message: t('حذف الفترة؟', 'Delete this period?'), danger: true)) p.deletePeriod(asInt(x['id']));
                      }),
                    ]),
                  ),
              ]),
      ),
      const SizedBox(height: 16),
      Section(
        title: t('القاعات والأماكن', 'Rooms & places'),
        icon: Icons.meeting_room_rounded,
        trailing: s.can('schedule', 'insert') ? IconButton(onPressed: () => _roomForm(context, p, null), icon: Icon(Icons.add_circle_rounded, color: c.primary)) : null,
        child: p.rooms.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text(t('أضف القاعات والمعامل وسعة كل منها.', 'Add halls, labs and their capacity.')))
            : Column(children: [
                for (final r in p.rooms)
                  ListTile(
                    dense: true,
                    leading: IconBadge(r['kind'] == 'lab' ? Icons.science_rounded : Icons.meeting_room_rounded, c.primary, size: 36),
                    title: Text('${r['name']}', style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
                    subtitle: Text('${_kindLabel('${r['kind']}')} · ${r['capacity']}${(r['building'] ?? '').toString().isEmpty ? '' : ' · ${r['building']}'}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (s.can('schedule', 'update'))
                        IconButton(
                          tooltip: t('الفترات المتاحة لهذا المكان', 'When this place is available'),
                          icon: const Icon(Icons.event_available_rounded, size: 20),
                          onPressed: () => _availabilitySheet(context, p, 'room', asInt(r['id']), '${t('أوقات إتاحة', 'Available periods of')} ${r['name']}'),
                        ),
                      if (s.can('schedule', 'update')) IconButton(icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => _roomForm(context, p, r)),
                      if (s.can('schedule', 'delete')) IconButton(icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger), onPressed: () async {
                        if (await confirm(context, message: t('حذف القاعة؟', 'Delete this room?'), danger: true)) p.deleteRoom(asInt(r['id']));
                      }),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

String _kindLabel(String k) => {'lecture': t('قاعة محاضرات', 'Lecture room'), 'lab': t('معمل', 'Lab'), 'hall': t('مدرج', 'Hall'), 'other': t('أخرى', 'Other')}[k] ?? k;

Future<void> _periodForm(BuildContext context, OrgScheduleProvider p, Map<String, dynamic>? e) async {
  final label = TextEditingController(text: '${e?['label'] ?? ''}');
  final from = TextEditingController(text: '${e?['start_time'] ?? '08:30'}');
  final to = TextEditingController(text: '${e?['end_time'] ?? '10:00'}');
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(children: [
          SheetHeader(e == null ? t('فترة جديدة', 'New period') : t('تعديل الفترة', 'Edit period')),
          Field(controller: label, label: t('الاسم (مثال: الأولى)', 'Name (e.g. First)')),
          Row(children: [
            Expanded(child: Field(controller: from, label: t('من (HH:MM)', 'From (HH:MM)'), ltr: true, keyboard: TextInputType.datetime)),
            const SizedBox(width: 10),
            Expanded(child: Field(controller: to, label: t('إلى (HH:MM)', 'To (HH:MM)'), ltr: true, keyboard: TextInputType.datetime)),
          ]),
          PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
            set(() => busy = true);
            final ok = await p.savePeriod(e == null ? null : asInt(e['id']), {'label': label.text.trim(), 'start_time': from.text.trim(), 'end_time': to.text.trim()});
            if (ctx.mounted) {
              set(() => busy = false);
              if (ok) Navigator.pop(ctx);
            }
          }),
        ]),
      )));
}

Future<void> _roomForm(BuildContext context, OrgScheduleProvider p, Map<String, dynamic>? e) async {
  final name = TextEditingController(text: '${e?['name'] ?? ''}');
  final cap = TextEditingController(text: '${e?['capacity'] ?? 40}');
  final building = TextEditingController(text: '${e?['building'] ?? ''}');
  String kind = '${e?['kind'] ?? 'lecture'}';
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetHeader(e == null ? t('قاعة جديدة', 'New room') : t('تعديل القاعة', 'Edit room')),
          Field(controller: name, label: t('الاسم', 'Name')),
          ChoiceRow<String>(options: {'lecture': _kindLabel('lecture'), 'lab': _kindLabel('lab'), 'hall': _kindLabel('hall'), 'other': _kindLabel('other')}, value: kind, onChanged: (v) => set(() => kind = v)),
          const SizedBox(height: 12),
          Field(controller: cap, label: t('السعة', 'Capacity'), keyboard: TextInputType.number, ltr: true),
          Field(controller: building, label: t('المبنى (اختياري)', 'Building (optional)')),
          PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
            if (name.text.trim().isEmpty) return;
            set(() => busy = true);
            final ok = await p.saveRoom(e == null ? null : asInt(e['id']), {
              'name': name.text.trim(), 'kind': kind, 'capacity': int.tryParse(cap.text) ?? 30,
              if (building.text.trim().isNotEmpty) 'building': building.text.trim(),
            });
            if (ctx.mounted) {
              set(() => busy = false);
              if (ok) Navigator.pop(ctx);
            }
          }),
        ]),
      )));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Planning: loads + availability
// ═════════════════════════════════════════════════════════════════════════════

class _PlanningTab extends StatelessWidget {
  const _PlanningTab();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final canEdit = s.can('schedule', 'update');
    String nameOf(int? id) {
      if (id == null) return '—';
      for (final m in p.staff) {
        final u = m['user'] as Map;
        if (asInt(u['id']) == id) return '${u['name']}';
      }
      return '#$id';
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      if (p.periods.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RowCard(accent: c.warning, child: Text(t('أضف الفترات أولاً من تبويب "الإعداد" ليظهر التخطيط كاملاً.', 'Add periods in the "Setup" tab first.'))),
        ),
      Section(
        title: t('متطلبات الكورسات', 'Course requirements'),
        icon: Icons.fact_check_rounded,
        child: p.loads.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text(t('لا توجد كورسات في المؤسسة.', 'No courses in this organization.')))
            : Column(children: [
                for (final l in p.loads)
                  ListTile(
                    onTap: canEdit ? () => _loadForm(context, p, l) : null,
                    title: Text(t('${(l['course'] as Map)['name_ar'] ?? (l['course'] as Map)['name_en']}', '${(l['course'] as Map)['name_en'] ?? (l['course'] as Map)['name_ar']}'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
                    subtitle: Text('${nameOf(l['teacher_id'] == null ? null : asInt(l['teacher_id']))} · ${l['sessions_per_week']}× ${t('أسبوعياً', 'per week')} · ${l['periods_per_session']} ${t('فترة', 'period(s)')}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
              ]),
      ),
      const SizedBox(height: 16),
      Section(
        title: t('أوقات التواجد (الهيئة التدريسية والمعاونة)', 'Staff availability'),
        trailing: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                  value: context.read<OrgSession>(),
                  child: BasePage(useWebCard: true, maxWith: 900,
                      appBar: ScreenAppBar(title: t('طلبات المواعيد المتاحة', 'Availability requests')),
                      child: const OrgAvailabilityRequestsPage())))),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text(t('اطلبها منهم', 'Ask them')),
        ),
        icon: Icons.event_available_rounded,
        child: p.staff.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text(t('أضف مدرسين وهيئة معاونة أولاً.', 'Add teachers and staff first.')))
            : Column(children: [
                for (final m in p.staff)
                  ListTile(
                    onTap: canEdit ? () => _availabilitySheet(context, p, 'user', asInt((m['user'] as Map)['id']), '${(m['user'] as Map)['name']}') : null,
                    leading: AdminAvatar(name: '${(m['user'] as Map)['name']}', url: (m['user'] as Map)['image_url'] as String?, size: 36),
                    title: Text('${(m['user'] as Map)['name']}', style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
                    subtitle: Text({'teacher': t('مدرس', 'Teacher'), 'teacher_assistant': t('معيد', 'Teaching assistant'), 'admin_assistant': t('مساعد إداري', 'Admin assistant')}['${m['role']}'] ?? ''),
                    trailing: const Icon(Icons.event_rounded),
                  ),
              ]),
      ),
    ]);
  }
}

Future<void> _loadForm(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> l) async {
  final teachers = p.staffOf('teacher'), tas = p.staffOf('teacher_assistant'), adms = p.staffOf('admin_assistant');
  int? teacher = l['teacher_id'] == null ? null : asInt(l['teacher_id']);
  int? adm = l['admin_assistant_id'] == null ? null : asInt(l['admin_assistant_id']);
  final assistants = <int>{...((l['assistant_ids'] as List?) ?? const []).map(asInt)};
  int sessions = asInt(l['sessions_per_week'], 1), span = asInt(l['periods_per_session'], 1);
  String? room = l['room_kind'] as String?;
  bool busy = false;
  final cid = asInt(l['course_id']);
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget stepper(String label, int v, int min, int max, ValueChanged<int> on) => Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark))),
              IconButton(onPressed: v > min ? () => set(() => on(v - 1)) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
              Text('$v', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              IconButton(onPressed: v < max ? () => set(() => on(v + 1)) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
            ]);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${t((l['course'] as Map)['name_ar'] ?? (l['course'] as Map)['name_en'], (l['course'] as Map)['name_en'] ?? (l['course'] as Map)['name_ar'])}'),
            OrgPickField<int>(
              label: t('المدرس', 'Teacher'),
              icon: Icons.person_rounded,
              value: teacher,
              allowNone: true,
              options: {for (final u in teachers) asInt(u['id']): '${u['name']}'},
              onChanged: (v) => set(() => teacher = v),
            ),
            const SizedBox(height: 12),
            Text(t('المعيدون (اختياري)', 'Teaching assistants (optional)'), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
            Wrap(spacing: 8, children: [
              for (final u in tas)
                FilterChip(
                  label: Text('${u['name']}'),
                  selected: assistants.contains(asInt(u['id'])),
                  onSelected: (on) => set(() => on ? assistants.add(asInt(u['id'])) : assistants.remove(asInt(u['id']))),
                ),
              if (tas.isEmpty) Text(t('لا يوجد معيدون', 'No assistants'), style: TextStyle(color: c.textLight)),
            ]),
            const SizedBox(height: 12),
            OrgPickField<int>(
              label: t('مساعد إداري (اختياري)', 'Admin assistant (optional)'),
              icon: Icons.badge_rounded,
              value: adm,
              allowNone: true,
              options: {for (final u in adms) asInt(u['id']): '${u['name']}'},
              onChanged: (v) => set(() => adm = v),
            ),
            const SizedBox(height: 8),
            stepper(t('عدد المحاضرات أسبوعياً', 'Sessions per week'), sessions, 1, 14, (v) => sessions = v),
            stepper(t('فترات المحاضرة الواحدة', 'Periods per session'), span, 1, 6, (v) => span = v),
            ChoiceRow<String>(
              label: t('نوع القاعة', 'Room type'),
              options: {'any': t('أي قاعة', 'Any'), 'lecture': _kindLabel('lecture'), 'lab': _kindLabel('lab'), 'hall': _kindLabel('hall')},
              value: room ?? 'any',
              onChanged: (v) => set(() => room = v == 'any' ? null : v),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _availabilitySheet(context, p, 'course', cid, t('أوقات حضور طلاب الكورس', 'When this course\'s students can attend')),
              icon: const Icon(Icons.groups_rounded),
              label: Text(t('أوقات حضور الطلاب', 'Student availability')),
            ),
            const SizedBox(height: 12),
            PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
              set(() => busy = true);
              final ok = await p.saveLoad(cid, {
                'teacher_id': teacher, 'assistant_ids': assistants.toList(), 'admin_assistant_id': adm,
                'sessions_per_week': sessions, 'periods_per_session': span, 'room_kind': room,
              });
              if (ctx.mounted) {
                set(() => busy = false);
                if (ok) Navigator.pop(ctx);
              }
            }),
          ]),
        );
      }));
}

/// Days × periods grid. Empty selection = "available at any time".
/// Conflict preview: what clashes, in plain words — remove the clashing slots of THIS timetable, add anyway, or cancel.
Future<String?> showConflictPreview(BuildContext context, List<Map<String, dynamic>> conflicts, {bool canReplace = true}) {
  final removable = conflicts.any((x) => (x['removable_slot_ids'] as List? ?? const []).isNotEmpty);
  final elsewhere = conflicts.any((x) => x['elsewhere'] == true);
  return showAdminSheet<String>(context, (ctx) {
    final c = ctx.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(t('يوجد تعارض في هذا الموعد', 'This time clashes')),
        for (final x in conflicts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.danger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.danger.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(x['elsewhere'] == true ? Icons.link_rounded : Icons.warning_amber_rounded, color: c.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('${x['text_ar'] ?? x['type']}', '${x['text_en'] ?? x['type']}'), style: orgText(ctx, w: FontWeight.w800)),
                  if ((x['courses'] as List? ?? const []).isNotEmpty)
                    Text((x['courses'] as List).join(' · '), style: orgText(ctx, size: 12, color: c.textMedium)),
                ]),
              ),
            ]),
          ),
        if (elsewhere)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(t('بعض التعارضات في جداول أخرى مفعّلة ولا يمكن حذفها من هنا.', 'Some clashes are in other active timetables and can\'t be removed from here.'),
                style: orgText(ctx, size: 12, color: c.textMedium)),
          ),
        if (canReplace && removable)
          PrimaryButton(isLoading: false, label: t('حذف الحصص المتعارضة وإضافة هذه', 'Remove the clashing slots & add'),
              icon: Icons.swap_horiz_rounded, iconBefore: true, onPressed: () => Navigator.pop(ctx, 'replace')),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.danger),
          onPressed: () => Navigator.pop(ctx, 'force'),
          child: Text(t('إضافة رغم التعارض', 'Add anyway')),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
      ]),
    );
  });
}

Future<void> _availabilitySheet(BuildContext context, OrgScheduleProvider p, String type, int id, String title) async {
  if (p.periods.isEmpty) {
    toast(t('أضف الفترات أولاً', 'Add periods first'), error: true);
    return;
  }
  final cells = await p.getAvailability(type, id);
  if (cells == null || !context.mounted) return;
  final sel = {...cells};
  bool busy = false;
  final days = orgDays.take(6).toList();
  final labels = dayLabels();
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(title),
            Text(sel.isEmpty ? t('غير محدد: متاح في كل الأوقات', 'Not set: available at any time') : t('المحدد فقط هو المتاح', 'Only the highlighted cells are available'),
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: sel.isEmpty ? c.success : c.textMedium)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(defaultColumnWidth: const FixedColumnWidth(64), children: [
                TableRow(children: [
                  const SizedBox(),
                  for (final d in days) Padding(padding: const EdgeInsets.all(4), child: Text(labels[d]!, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, fontWeight: FontWeight.w800, color: c.textDark))),
                ]),
                for (final per in p.periods)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('${per['label']}', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.textMedium))),
                    for (final d in days)
                      GestureDetector(
                        onTap: () => set(() {
                          final k = '$d|${per['id']}';
                          sel.contains(k) ? sel.remove(k) : sel.add(k);
                        }),
                        child: Container(
                          height: 38,
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: sel.contains('$d|${per['id']}') ? c.primary : c.inputBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: sel.contains('$d|${per['id']}') ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                        ),
                      ),
                  ]),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: () => set(sel.clear), child: Text(t('متاح دائماً', 'Always available'))),
              TextButton(onPressed: () => set(() {
                    for (final d in days) {
                      for (final per in p.periods) {
                        sel.add('$d|${per['id']}');
                      }
                    }
                  }), child: Text(t('تحديد الكل', 'Select all'))),
            ]),
            PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
              set(() => busy = true);
              final ok = await p.setAvailability(type, id, sel);
              if (ctx.mounted) {
                set(() => busy = false);
                if (ok) Navigator.pop(ctx);
              }
            }),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Timetables + studio
// ═════════════════════════════════════════════════════════════════════════════

class _TimetablesTab extends StatelessWidget {
  const _TimetablesTab();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    if (p.schedule != null) return const _Studio();
    return Stack(children: [
      p.schedules.isEmpty
          ? OrgEmpty(icon: Icons.calendar_month_rounded, title: t('لم تنشئ أي جدول بعد', 'No timetable yet'))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
              for (final x in p.schedules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RowCard(
                    accent: x['status'] == 'active' ? c.success : null,
                    onTap: () => p.open(asInt(x['id'])),
                    child: Row(children: [
                      IconBadge(Icons.calendar_month_rounded, x['status'] == 'active' ? c.success : c.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${x['name']}', style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                          Text('${x['term_label'] ?? ''} · ${x['slots'] ?? 0} ${t('حصة', 'slots')}', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
                        ]),
                      ),
                      StatusChip({'active': t('منشور', 'Published'), 'draft': t('مسودة', 'Draft'), 'archived': t('مؤرشف', 'Archived')}['${x['status']}'] ?? '${x['status']}',
                          x['status'] == 'active' ? c.success : x['status'] == 'draft' ? c.warning : c.textLight),
                      if (s.can('schedule', 'delete') && x['status'] != 'active')
                        IconButton(icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () async {
                          if (await confirm(context, message: t('حذف الجدول؟', 'Delete this timetable?'), danger: true)) p.deleteSchedule(asInt(x['id']));
                        }),
                    ]),
                  ),
                ),
            ]),
      if (s.can('schedule', 'insert'))
        PositionedDirectional(
          bottom: 16,
          end: 16,
          child: FloatingActionButton.extended(
            heroTag: 'org_add_schedule',
            backgroundColor: c.primary,
            onPressed: () async {
              final name = await askText(context, title: t('اسم الجدول (مثال: الفصل الأول 2026)', 'Timetable name (e.g. Fall 2026)'));
              if (name == null || name.trim().isEmpty) return;
              final r = await p.createSchedule(name.trim(), null);
              if (r != null) await p.open(asInt(r['id']));
            },
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text(t('جدول جديد', 'New timetable'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
          ),
        ),
    ]);
  }
}

class _Studio extends StatefulWidget {
  const _Studio();

  @override
  State<_Studio> createState() => _StudioState();
}

class _StudioState extends State<_Studio> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final sch = p.schedule!;
    final active = sch['status'] == 'active';
    final days = [for (final d in orgDays) if (p.slots.any((x) => x['day'] == d) || orgDays.indexOf(d) < 6) d];
    final labels = dayLabels();
    final errors = p.conflicts.where((x) => x['severity'] == 'error').length;
    final warns = p.conflicts.length - errors;

    final courseNames = {
      for (final l in p.loads) asInt(l['course_id']): t('${(l['course'] as Map)['name_ar'] ?? (l['course'] as Map)['name_en']}', '${(l['course'] as Map)['name_en'] ?? (l['course'] as Map)['name_ar']}'),
    };
    final people = {for (final m in p.staff) asInt((m['user'] as Map)['id']): '${(m['user'] as Map)['name']}'};
    final rooms = {for (final r in p.rooms) asInt(r['id']): '${r['name']}'};

    bool hasConflict(String day, int period) => p.conflicts.any((x) => x['day'] == day && (x['period_id'] == period || x['period_id'] == null));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(onPressed: p.closeSchedule, icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(child: Text('${sch['name']}', style: c.h2.copyWith(fontSize: 16))),
          StatusChip(active ? t('منشور', 'Published') : t('مسودة', 'Draft'), active ? c.success : c.warning),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          if (s.can('schedule', 'update') && !active)
            ActionChip(
              avatar: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.auto_awesome_rounded, size: 18, color: c.primary),
              label: Text(t('توليد تلقائي', 'Auto-generate'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
              onPressed: _busy ? null : () => _generate(context, p),
            ),
          if (s.can('schedule', 'insert') && !active)
            ActionChip(avatar: Icon(Icons.add_rounded, size: 18, color: c.primary), label: Text(t('إضافة حصة', 'Add a slot')), onPressed: () => _slotSheet(context, p, null, null, null)),
          if (s.can('schedule', 'update'))
            ActionChip(
              avatar: Icon(active ? Icons.unpublished_rounded : Icons.publish_rounded, size: 18, color: active ? c.warning : c.success),
              label: Text(active ? t('إيقاف النشر', 'Unpublish') : t('نشر للجميع', 'Publish')),
              onPressed: () async {
                if (!active && errors > 0) {
                  toast(t('عالج التعارضات الحمراء قبل النشر', 'Fix the red conflicts before publishing'), error: true);
                  return;
                }
                await p.setActive(!active);
              },
            ),
          ActionChip(avatar: Icon(Icons.download_rounded, size: 18, color: c.success), label: Text(t('تصدير Excel', 'Export Excel')), onPressed: () => downloadExcel(context, 'export/schedule', {'schedule_id': sch['id']})),
        ]),
      ),
      if (errors + warns > 0 || p.warnings.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: RowCard(
            accent: errors > 0 ? c.danger : c.warning,
            onTap: () => _issuesSheet(context, p, courseNames),
            child: Row(children: [
              Icon(errors > 0 ? Icons.error_rounded : Icons.warning_amber_rounded, color: errors > 0 ? c.danger : c.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(t('$errors تعارض · $warns تنبيه · ${p.warnings.length} لم يُجدول', '$errors conflicts · $warns warnings · ${p.warnings.length} not placed'), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark))),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      Expanded(
        child: p.periods.isEmpty
            ? OrgEmpty(icon: Icons.inbox_rounded, title: t('أضف الفترات أولاً', 'Add periods first'))
            : SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(150),
                    columnWidths: const {0: FixedColumnWidth(78)},
                    children: [
                      TableRow(children: [
                        const SizedBox(),
                        for (final d in days.take(6)) Padding(padding: const EdgeInsets.all(6), child: Text(labels[d]!, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark))),
                      ]),
                      for (final per in p.periods)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: Column(children: [
                              Text('${per['label']}', style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 12, color: c.textDark)),
                              Text('${per['start_time']}', style: TextStyle(fontSize: 10.5, color: c.textLight)),
                            ]),
                          ),
                          for (final d in days.take(6))
                            _Cell(
                              slots: [for (final x in p.slots) if (x['day'] == d && x['period_id'] == per['id']) x],
                              conflict: hasConflict(d, asInt(per['id'])),
                              courseNames: courseNames,
                              rooms: rooms,
                              people: people,
                              onTap: active || !s.can('schedule', 'update') ? null : (slot) => _slotSheet(context, p, slot, d, asInt(per['id'])),
                            ),
                        ]),
                    ],
                  ),
                ),
              ),
      ),
    ]);
  }

  Future<void> _generate(BuildContext context, OrgScheduleProvider p) async {
    setState(() => _busy = true);
    final ok = await p.generate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      toast(p.warnings.isEmpty ? t('تم توليد الجدول بدون تعارضات', 'Timetable generated with no conflicts') : t('تم التوليد — بعض الحصص لم تُجدول', 'Generated — some sessions could not be placed'));
    }
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.slots, required this.conflict, required this.courseNames, required this.rooms, required this.people, this.onTap});
  final List<Map<String, dynamic>> slots;
  final bool conflict;
  final Map<int, String> courseNames, people, rooms;
  final void Function(Map<String, dynamic>? slot)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(null),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: slots.isEmpty ? c.inputBg.withValues(alpha: 0.6) : c.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: conflict ? c.danger : (slots.isEmpty ? Colors.transparent : c.primary.withValues(alpha: 0.35)), width: conflict ? 1.8 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final x in slots)
            GestureDetector(
              onTap: onTap == null ? null : () => onTap!(x),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (x['locked'] == true) Icon(Icons.push_pin_rounded, size: 11, color: c.primary),
                    Expanded(child: Text(courseNames[asInt(x['course_id'])] ?? '#${x['course_id']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 11.5, color: c.textDark))),
                  ]),
                  Text('${people[asInt(x['teacher_id'])] ?? ''}${x['room_id'] == null ? '' : ' · ${rooms[asInt(x['room_id'])] ?? ''}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontSize: 10.5, color: c.textMedium)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

String _issueText(Map<String, dynamic> x) => {
      'teacher_double_booked': t('مدرس لديه حصتان في نفس الوقت', 'Teacher double-booked'),
      'assistant_double_booked': t('معيد لديه حصتان في نفس الوقت', 'Assistant double-booked'),
      'admin_assistant_double_booked': t('مساعد إداري لديه حصتان في نفس الوقت', 'Admin assistant double-booked'),
      'room_double_booked': t('قاعة محجوزة مرتين', 'Room double-booked'),
      'students_clash': t('كورسان بنفس الطلاب في نفس الوقت', 'Two courses share students at the same time'),
      'teacher_unavailable': t('المدرس غير متاح في هذا الوقت', 'Teacher unavailable'),
      'staff_unavailable': t('أحد الهيئة المعاونة غير متاح', 'Staff member unavailable'),
      'students_unavailable': t('الطلاب غير متاحين في هذا الوقت', 'Students unavailable'),
      'room_too_small': t('القاعة أصغر من عدد الطلاب', 'Room too small'),
      'teacher_overloaded': t('حمل المدرس اليومي أكبر من الحد', 'Teacher daily load too high'),
      'no_teacher': t('الكورس بلا مدرس', 'Course has no teacher'),
      'no_slot': t('لا يوجد موعد مناسب', 'No suitable slot'),
      'no_assistant_slot': t('لم يتوفر وقت لمعيد', 'No time found for an assistant'),
    }['${x['type']}'] ??
    '${x['type']}';

String _reasonText(String? r) => {
      'teacher_unavailable': t('المدرس غير متاح', 'teacher unavailable'),
      'students_unavailable': t('الطلاب غير متاحين', 'students unavailable'),
      'teacher_busy': t('المدرس مشغول', 'teacher busy'),
      'students_clash': t('تعارض طلاب مع كورس آخر', 'students clash with another course'),
      'teacher_day_limit': t('حد الحمل اليومي للمدرس', 'teacher daily limit'),
      'no_room_fits': t('لا توجد قاعة بسعة/نوع مناسب', 'no room with enough capacity / right type'),
      'rooms_busy': t('القاعات مشغولة', 'rooms are busy'),
      'course_already_there': t('الكورس موجود في هذا الوقت', 'course already scheduled then'),
      'no_free_cell': t('لا توجد خلية فارغة', 'no free cell'),
    }[r] ??
    '';

Future<void> _issuesSheet(BuildContext context, OrgScheduleProvider p, Map<int, String> names) async {
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SheetHeader(t('التعارضات والتنبيهات', 'Conflicts & warnings')),
      for (final w in p.warnings)
        ListTile(
          dense: true,
          leading: Icon(Icons.info_rounded, color: c.warning),
          title: Text('${names[asInt(w['course_id'])] ?? '#${w['course_id']}'} — ${_issueText(w)}'),
          subtitle: _reasonText(w['reason'] as String?).isEmpty ? null : Text(_reasonText(w['reason'] as String?)),
        ),
      for (final x in p.conflicts)
        ListTile(
          dense: true,
          leading: Icon(x['severity'] == 'error' ? Icons.error_rounded : Icons.warning_amber_rounded, color: x['severity'] == 'error' ? c.danger : c.warning),
          title: Text(_issueText(x)),
          subtitle: Text('${dayLabels()[x['day']] ?? x['day'] ?? ''} · ${((x['course_ids'] as List?) ?? const []).map((i) => names[asInt(i)] ?? '#$i').join(' / ')}'),
        ),
    ]);
  });
}

/// Add a slot (slot == null) or edit / move / delete one. Hard conflicts ask before forcing.
Future<void> _slotSheet(BuildContext context, OrgScheduleProvider p, Map<String, dynamic>? slot, String? day0, int? period0) async {
  final courses = p.loads;
  if (courses.isEmpty || p.periods.isEmpty) {
    toast(t('أضف الفترات والكورسات أولاً', 'Add periods and courses first'), error: true);
    return;
  }
  int course = asInt(slot?['course_id'], asInt(courses.first['course_id']));
  String day = (slot?['day'] ?? day0 ?? orgDays.first) as String;
  int period = asInt(slot?['period_id'], period0 ?? asInt(p.periods.first['id']));
  int? room = slot?['room_id'] == null ? null : asInt(slot!['room_id']);
  int? teacher = slot?['teacher_id'] == null ? null : asInt(slot!['teacher_id']);
  int? assistant = slot?['assistant_id'] == null ? null : asInt(slot!['assistant_id']);
  int? adm = slot?['admin_assistant_id'] == null ? null : asInt(slot!['admin_assistant_id']);
  bool busy = false;
  if (slot == null) {
    final l = courses.firstWhere((x) => asInt(x['course_id']) == course);
    teacher = l['teacher_id'] == null ? null : asInt(l['teacher_id']);
  }
  final labels = dayLabels();
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget pick(String label, int? v, List<Map<String, dynamic>> items, ValueChanged<int?> on, {bool allowNone = true}) =>
            OrgPickField<int>(
              label: label,
              value: v,
              allowNone: allowNone,
              options: {for (final u in items) asInt(u['id']): '${u['name']}'},
              onChanged: (x) => set(() => on(x)),
            );
        Future<void> save({bool force = false, bool replace = false}) async {
          set(() => busy = true);
          final body = {'day': day, 'period_id': period, 'room_id': room, 'teacher_id': teacher, 'assistant_id': assistant, 'admin_assistant_id': adm};
          final res = slot == null
              ? await p.addSlot({...body, 'course_id': course}, force: force, replace: replace)
              : await p.editSlot(asInt(slot['id']), body, force: force);
          if (!ctx.mounted) return;
          set(() => busy = false);
          if (res == null) {
            Navigator.pop(ctx);
          } else if (res.isNotEmpty && res.first['type'] != 'error') {
            final choice = await showConflictPreview(ctx, res, canReplace: slot == null);
            if (choice == 'replace' && ctx.mounted) await save(replace: true);
            if (choice == 'force' && ctx.mounted) await save(force: true);
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(slot == null ? t('حصة جديدة', 'New slot') : t('تعديل الحصة', 'Edit slot')),
            if (slot == null)
              OrgPickField<int>(
                label: t('المقرر', 'Course'),
                icon: Icons.menu_book_rounded,
                value: course,
                options: {
                  for (final l in courses)
                    asInt(l['course_id']): t('${(l['course'] as Map)['name_ar'] ?? (l['course'] as Map)['name_en']}',
                        '${(l['course'] as Map)['name_en'] ?? (l['course'] as Map)['name_ar']}')
                },
                onChanged: (v) => set(() {
                  course = v ?? course;
                  final l = courses.firstWhere((x) => asInt(x['course_id']) == course);
                  teacher = l['teacher_id'] == null ? null : asInt(l['teacher_id']);
                }),
              ),
            const SizedBox(height: 12),
            ChoiceRow<String>(options: {for (final d in orgDays.take(6)) d: labels[d]!}, value: day, onChanged: (v) => set(() => day = v)),
            const SizedBox(height: 12),
            OrgPickField<int>(
              label: t('الفترة', 'Period'),
              icon: Icons.schedule_rounded,
              value: period,
              options: {for (final x in p.periods) asInt(x['id']): '${x['label']}  (${x['start_time']}–${x['end_time']})'},
              onChanged: (v) => set(() => period = v ?? period),
            ),
            const SizedBox(height: 12),
            pick(t('القاعة', 'Room'), room, [for (final r in p.rooms) {'id': r['id'], 'name': '${r['name']} (${r['capacity']})'}], (v) => room = v),
            const SizedBox(height: 12),
            pick(t('المدرس', 'Teacher'), teacher, [for (final u in p.staffOf('teacher')) u], (v) => teacher = v),
            const SizedBox(height: 12),
            pick(t('المعيد', 'Assistant'), assistant, p.staffOf('teacher_assistant'), (v) => assistant = v),
            const SizedBox(height: 12),
            pick(t('المساعد الإداري', 'Admin assistant'), adm, p.staffOf('admin_assistant'), (v) => adm = v),
            const SizedBox(height: 16),
            PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () => save()),
            if (slot != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  if (await confirm(ctx, message: t('حذف هذه الحصة؟', 'Delete this slot?'), danger: true)) {
                    await p.deleteSlot(asInt(slot['id']));
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                label: Text(t('حذف الحصة', 'Delete slot'), style: TextStyle(color: c.danger)),
              ),
            ],
          ]),
        );
      }));
}
