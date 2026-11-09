// lib/features/org/org_schedule_pages.dart — the physical timetable studio.
//
//   Timetable tab   schedules list → studio (weekly grid, generate, edit by hand, conflicts, publish)
//   Setup tab       periods + rooms (positions)
//   Planning tab    per course: teacher · assistants · admin assistant · sessions/week · periods/session · room type,
//                   student-group availability; per staff member: availability (days × periods)
library;

import 'package:flutter_education_app/design/app_back_button.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppBanner, AppField, AppListSkeleton, AppPrimaryButton, AppSectionTitle, showAppSheet;
import 'package:flutter_education_app/design/app_refresh.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_availability_pages.dart';
import 'org_schedule_copies.dart' show openTimetableCopies, timetableNamesOf;
import 'org_schedule_export.dart' show showTimetableExport;
import 'org_schedule_planning.dart' show openCoursePlans, TimetableCoursesView;
import 'org_schedule_board.dart';
import 'org_timetable_parts.dart';
import 'org_timetable_wizard.dart';
import 'org_timetable_time.dart';
import 'org_schedule_hub.dart';
import 'org_schedule_generate.dart';
import 'org_schedule_ladder.dart' show LadderLive;
import 'org_schedule_ladder_ui.dart' show LadderLivePanel, LadderVeil, showLadderDecisionDialog, showLadderSheet;
import 'org_schedule_autopilot.dart';
import 'org_schedule_grid.dart';
import 'org_schedule_reassign.dart';
import 'org_schedule_groups.dart' show openStudentGroups;
import 'org_schedule_exams.dart' show openExamTimetables;
import 'org_my_exams.dart' show examPauseBanner, examPausesOf;
import 'package:flutter_education_app/design/app_kit.dart' show AppHero, AppHeroStat, AppBanner, AppActionCard;
import 'org_schedule_versions.dart' show calendarDate, clockOf, periodRange, stampOf;
import 'package:flutter_education_app/core/app_time.dart';
import 'org_v3.dart';
import 'org_page_header.dart' show OrgPageRefresh;
import 'package:flutter_education_app/core/display/app_fonts.dart';

class OrgSchedulePage extends StatelessWidget {
  const OrgSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    if (!s.can('schedule')) return OrgEmpty(icon: Icons.lock_rounded, title: t('لا تملك صلاحية عرض الجدول', 'You cannot view the timetable'));
    return ChangeNotifierProvider(create: (_) => OrgScheduleProvider(s)..loadSetup(), child: const _ScheduleRefresh(child: _ScheduleView()));
  }
}

/// The page header's Refresh reloads the timetable data in place (the open timetable stays open, a running
/// generation keeps being followed) instead of re-keying the page, which would drop both.
class _ScheduleRefresh extends StatefulWidget {
  const _ScheduleRefresh({required this.child});
  final Widget child;

  @override
  State<_ScheduleRefresh> createState() => _ScheduleRefreshState();
}

class _ScheduleRefreshState extends State<_ScheduleRefresh> {
  OrgPageRefresh? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final p = context.read<OrgScheduleProvider>();
    await p.loadSetup();
    final id = p.schedule?['id'];
    if (id != null) await p.open(asInt(id));
    if (mounted) _refresh?.markUpdated();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ScheduleView extends StatelessWidget {
  const _ScheduleView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final c = context.colors;
    if (!p.loaded) return const AppListSkeleton();
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16)),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(14)),
              labelColor: c.onHero,
              unselectedLabelColor: c.textMedium,
              labelStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 13),
              tabs: [
                Tab(text: t('الجداول', 'Timetables'), height: 40),
                Tab(text: t('المقررات والهيئة', 'Courses & staff'), height: 40),
                Tab(text: t('الفترات والأماكن', 'Periods & rooms'), height: 40),
              ],
            ),
          ),
          const Expanded(child: TabBarView(children: [_TimetablesTab(), _PlanningTab(), _SetupTab()])),
        ],
      ),
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
    return AppRefresh(onRefresh: p.loadSetup, child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Section(
          title: t('الفترات الدراسية', 'Periods'),
          icon: Icons.schedule_rounded,
          trailing: s.can('schedule', 'insert')
              ? IconButton(tooltip: t('إضافة فترة', 'Add a period'), 
                  onPressed: () => showPeriodForm(context, p, null),
                  icon: Icon(Icons.add_circle_rounded, color: c.primary),
                )
              : null,
          child: p.periods.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(t('أضف فترات اليوم الدراسي (مثال: ${AppTime.clockRange('08:30', '10:00')}).', 'Add the teaching periods of the day (e.g. ${AppTime.clockRange('08:30', '10:00')}).')),
                )
              : Column(
                  children: [
                    for (final x in p.periods)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: c.primary.withValues(alpha: 0.12),
                          child: Text(
                            '${x['order']}',
                            style: TextStyle(color: c.primary, fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(
                          '${x['label']}',
                          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(periodRange(asMap(x))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.can('schedule', 'update')) IconButton(tooltip: t('تعديل', 'Edit'), icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => showPeriodForm(context, p, x)),
                            if (s.can('schedule', 'delete'))
                              IconButton(tooltip: t('حذف', 'Delete'), 
                                icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger),
                                onPressed: () async {
                                  if (await confirm(context, message: t('حذف الفترة؟', 'Delete this period?'), danger: true)) p.deletePeriod(asInt(x['id']));
                                },
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Section(
          title: t('القاعات والمعامل والمكاتب', 'Rooms, labs & offices'),
          icon: Icons.meeting_room_rounded,
          trailing: s.can('schedule', 'insert')
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: t('أنواع الأماكن', 'Facility types'), onPressed: () => showFacilityTypes(context, p), icon: const Icon(Icons.category_rounded)),
                    IconButton(tooltip: t('إضافة قاعة', 'Add a room'), 
                      onPressed: () => showRoomForm(context, p, null),
                      icon: Icon(Icons.add_circle_rounded, color: c.primary),
                    ),
                  ],
                )
              : null,
          child: p.rooms.isEmpty
              ? Padding(padding: const EdgeInsets.all(12), child: Text(t('أضف القاعات والمعامل والمكاتب وسعة كل منها.', 'Add halls, labs, offices and their capacity.')))
              : Column(
                  children: [
                    for (final r in p.rooms)
                      ListTile(
                        dense: true,
                        leading: IconBadge(
                          r['kind'] == 'lab'
                              ? Icons.science_rounded
                              : r['kind'] == 'office'
                              ? Icons.chair_rounded
                              : Icons.meeting_room_rounded,
                          r['is_active'] == false ? c.textLight : c.primary,
                          size: 36,
                        ),
                        title: Text(
                          '${'${r['code'] ?? ''}'.isEmpty ? '' : '${r['code']} · '}${r['name']}',
                          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            p.kindLabels['${r['kind']}'] ?? '${r['kind']}',
                            '${r['capacity']}',
                            if ('${r['building'] ?? ''}'.isNotEmpty) '${r['building']}',
                            if ('${r['location'] ?? ''}'.isNotEmpty) '${r['location']}',
                            if (r['exclusive'] == false) t('مشترك', 'shared'),
                            if (((r['capabilities'] as List?) ?? const []).isNotEmpty) (r['capabilities'] as List).join(', '),
                            if (r['is_active'] == false) t('موقوف', 'inactive'),
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.can('schedule', 'update') && r['kind'] == 'office')
                              IconButton(tooltip: t('الموجودون بالمكتب', 'Office occupants'), icon: const Icon(Icons.groups_rounded, size: 20), onPressed: () => showOfficeMembers(context, p, r)),
                            if (s.can('schedule', 'update'))
                              IconButton(
                                tooltip: t('الفترات المتاحة لهذا المكان', 'When this place is available'),
                                icon: const Icon(Icons.event_available_rounded, size: 20),
                                onPressed: () => showAvailabilitySheet(context, p, 'room', asInt(r['id']), '${t('أوقات إتاحة', 'Available periods of')} ${r['name']}'),
                              ),
                            if (s.can('schedule', 'update')) IconButton(tooltip: t('تعديل', 'Edit'), icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => showRoomForm(context, p, r)),
                            if (s.can('schedule', 'delete'))
                              IconButton(tooltip: t('حذف', 'Delete'), 
                                icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger),
                                onPressed: () => deleteRoom(context, p, r),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ));
  }
}

Future<void> showPeriodForm(BuildContext context, OrgScheduleProvider p, Map<String, dynamic>? e) async {
  final label = TextEditingController(text: '${e?['label'] ?? ''}');
  String from = '${e?['start_time'] ?? '08:30'}', to = '${e?['end_time'] ?? '10:00'}';
  bool busy = false;
  await showAdminSheet<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          children: [
            SheetHeader(e == null ? t('فترة جديدة', 'New period') : t('تعديل الفترة', 'Edit period')),
            Field(controller: label, label: t('الاسم (مثال: الأولى)', 'Name (e.g. First)')),
            Row(
              children: [
                Expanded(
                  child: ClockField(label: t('يبدأ', 'Starts'), value: from, onChanged: (v) => set(() => from = v)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClockField(label: t('ينتهي', 'Ends'), value: to, onChanged: (v) => set(() => to = v)),
                ),
              ],
            ),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                set(() => busy = true);
                final ok = await p.savePeriod(e == null ? null : asInt(e['id']), {'label': label.text.trim(), 'start_time': from, 'end_time': to});
                if (ctx.mounted) {
                  set(() => busy = false);
                  if (ok) Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
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
    final people = {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']}'};

    return AppRefresh(onRefresh: p.loadSetup, child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        if (p.periods.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RowCard(accent: c.warning, child: Text(t('أضف الفترات أولاً من تبويب "الفترات والأماكن" ليظهر التخطيط كاملاً.', 'Add periods in the "Periods & rooms" tab first.'))),
          ),
        Section(
          title: t('متطلبات المقررات', 'Course requirements'),
          icon: Icons.fact_check_rounded,
          child: p.loads.isEmpty
              ? Padding(padding: const EdgeInsets.all(12), child: Text(t('لا توجد مقررات في المؤسسة.', 'No courses in this organization.')))
              : Column(
                  children: [
                    for (final l in p.loads)
                      ListTile(
                        onTap: canEdit
                            ? () => showLoadForm(
                                context,
                                p,
                                l,
                                onStudentAvailability: () => showAvailabilitySheet(context, p, 'course', asInt(l['course_id']), t('أوقات حضور طلاب المقرر', 'When this course\'s students can attend')),
                              )
                            : null,
                        title: Text(
                          courseName(l),
                          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            l['teacher_id'] == null ? t('بلا مدرس', 'no teacher') : (people[asInt(l['teacher_id'])] ?? '#${l['teacher_id']}'),
                            '${asInt(l['sessions_per_week'], 1)}× ${t('أسبوعياً', 'per week')}',
                            '${asInt(l['periods_per_session'], 1)} ${t('فترة', 'period(s)')}',
                            if (asInt(l['lab_sessions_per_week']) > 0) t('${l['lab_sessions_per_week']} سكشن', '${l['lab_sessions_per_week']} lab(s)'),
                          ].join(' · '),
                          style: TextStyle(color: loadHints(l).isEmpty ? null : c.warning),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Section(
          title: t('أوقات التواجد والتفضيلات', 'Staff availability & preferences'),
          trailing: TextButton.icon(
            onPressed: () => openAvailabilityRequests(context),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(t('اطلبها منهم', 'Ask them')),
          ),
          icon: Icons.event_available_rounded,
          child: p.staff.isEmpty
              ? Padding(padding: const EdgeInsets.all(12), child: Text(t('أضف مدرسين وهيئة معاونة أولاً.', 'Add teachers and staff first.')))
              : Column(
                  children: [
                    Text(
                      t('"أوقات التواجد" و"غير متاح" قيود إلزامية؛ "مفضّل" و"يتجنبه" تفضيلات مرنة.', '"Available periods" and "unavailable" are hard rules; "preferred" and "avoid" are soft.'),
                      style: orgText(context, size: 12, color: c.textMedium),
                    ),
                    for (final m in p.staff)
                      ListTile(
                        leading: AdminAvatar(name: '${asMap(m['user'])['name']}', url: asMap(m['user'])['image_url'] as String?, size: 36),
                        title: Text(
                          '${asMap(m['user'])['name']}',
                          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          {'teacher': t('مدرس', 'Teacher'), 'teacher_assistant': t('معيد', 'Teaching assistant'), 'admin_assistant': t('مساعد إداري', 'Admin assistant')}['${m['role']}'] ?? '',
                        ),
                        trailing: canEdit
                            ? Wrap(
                                children: [
                                  IconButton(
                                    tooltip: t('أوقات التواجد', 'Available periods'),
                                    icon: const Icon(Icons.event_rounded),
                                    onPressed: () => showAvailabilitySheet(context, p, 'user', asInt(asMap(m['user'])['id']), '${asMap(m['user'])['name']}'),
                                  ),
                                  IconButton(
                                    tooltip: t('التفضيلات', 'Preferences'),
                                    icon: Icon(Icons.tune_rounded, color: c.primary),
                                    onPressed: () => showStaffPrefs(context, p, asInt(asMap(m['user'])['id']), '${asMap(m['user'])['name']}'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    ));
  }
}

/// Days × periods grid. Empty selection = "available at any time".
/// Conflict preview: what clashes, in plain words — remove the clashing slots of THIS timetable, add anyway, or cancel.
Future<String?> showConflictPreview(BuildContext context, List<Map<String, dynamic>> conflicts, {bool canReplace = true, bool canRebuild = true, bool canOverride = false}) {
  final removable = conflicts.any((x) => (x['removable_slot_ids'] as List? ?? const []).isNotEmpty);
  final elsewhere = conflicts.any((x) => x['elsewhere'] == true);
  return showAdminSheet<String>(context, (ctx) {
    final c = ctx.colors;
    Widget option(String key, IconData icon, Color col, String title, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OrgActionCard(icon: icon, color: col, title: title, subtitle: sub, onTap: () => Navigator.pop(ctx, key)),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(x['elsewhere'] == true ? Icons.link_rounded : Icons.warning_amber_rounded, color: c.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('${x['text_ar'] ?? x['type']}', '${x['text_en'] ?? x['type']}'), style: orgText(ctx, w: FontWeight.w800)),
                        if ((x['courses'] as List? ?? const []).isNotEmpty) Text((x['courses'] as List).join(' · '), style: orgText(ctx, size: 12, color: c.textMedium)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (elsewhere)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t('بعض التعارضات في جداول أخرى مفعّلة ولا يمكن حذفها من هنا.', 'Some clashes are in other active timetables and can\'t be removed from here.'),
                style: orgText(ctx, size: 12, color: c.textMedium),
              ),
            ),
          Text(t('كيف نحافظ على استقرار الجدول؟', 'How should the timetable stay stable?'), style: orgText(ctx, w: FontWeight.w800)),
          const SizedBox(height: 8),
          if (canReplace && removable)
            option(
              'shift',
              Icons.low_priority_rounded,
              c.success,
              t('تغيير بسيط (مقترح)', 'Small change (recommended)'),
              t('ننقل الحصص المتعارضة فقط لأقرب وقت فارغ — باقي الجدول كما هو', 'Only the clashing sessions move to the nearest free time — the rest stays'),
            ),
          if (canRebuild)
            option(
              'regenerate',
              Icons.auto_awesome_rounded,
              c.primary,
              t('إعادة التوليد بدون أي تعارض', 'Regenerate with no conflicts'),
              t('نثبّت هذه الحصة ونعيد ترتيب كل الحصص غير المثبّتة', 'This session is locked; every unlocked session is rearranged'),
            ),
          if (canReplace && removable)
            option('replace', Icons.swap_horiz_rounded, c.warning, t('استبدال', 'Replace'), t('نحذف الحصص المتعارضة ونضيف هذه', 'The clashing sessions are removed and this one is added')),
          // only a hard UNAVAILABILITY can be overridden (by someone with approval rights) — never a double booking
          if (canOverride && conflicts.every((x) => const {'teacher_unavailable', 'staff_unavailable'}.contains(x['type'])))
            option(
              'override',
              Icons.verified_user_rounded,
              c.purple,
              t('استثناء معتمد', 'Approved override'),
              t('تسمح بعدم الإتاحة مع سبب مكتوب، وتبقى ظاهرة كتنبيه', 'Allows the unavailability with a written reason; it stays visible as a warning'),
            ),
          option(
            'force',
            Icons.lock_clock_rounded,
            c.danger,
            t('إضافتها مع التعارض', 'Add it with the clash'),
            t('تُحفظ في المسودة وتبقى ظاهرة — والنشر يُرفض حتى يُحل التعارض', 'Saved in the draft and flagged — publishing is refused until it is solved'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
        ],
      ),
    );
  });
}

Future<void> showAvailabilitySheet(BuildContext context, OrgScheduleProvider p, String type, int id, String title) async {
  if (p.periods.isEmpty) {
    toast(t('أضف الفترات أولاً', 'Add periods first'), error: true);
    return;
  }
  final cells = await p.getAvailability(type, id);
  if (cells == null || !context.mounted) return;
  final sel = {...cells};
  bool busy = false;
  final days = orgDays.toList();
  final labels = dayLabels();
  await showAdminSheet<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(title),
              Text(
                sel.isEmpty ? t('غير محدد: متاح في كل الأوقات', 'Not set: available at any time') : t('المحدد فقط هو المتاح', 'Only the highlighted cells are available'),
                style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, color: sel.isEmpty ? c.success : c.textMedium),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(64),
                  children: [
                    TableRow(
                      children: [
                        const SizedBox(),
                        for (final d in days)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              labels[d]!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, fontWeight: FontWeight.w800, color: c.textDark),
                            ),
                          ),
                      ],
                    ),
                    for (final per in p.periods)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              '${per['label']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: c.textMedium),
                            ),
                          ),
                          for (final d in days)
                            GestureDetector(
                              onTap: () => set(() {
                                final k = '$d|${per['id']}';
                                sel.contains(k) ? sel.remove(k) : sel.add(k);
                              }),
                              child: Container(
                                height: 38,
                                margin: const EdgeInsets.all(3),
                                decoration: BoxDecoration(color: sel.contains('$d|${per['id']}') ? c.primary : c.inputBg, borderRadius: BorderRadius.circular(10)),
                                child: sel.contains('$d|${per['id']}') ? Icon(Icons.check_rounded, color: c.onHero, size: 18) : null,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  TextButton(onPressed: () => set(sel.clear), child: Text(t('متاح دائماً', 'Always available'))),
                  TextButton(
                    onPressed: () => set(() {
                      for (final d in days) {
                        for (final per in p.periods) {
                          sel.add('$d|${per['id']}');
                        }
                      }
                    }),
                    child: Text(t('تحديد الكل', 'Select all')),
                  ),
                ],
              ),
              PrimaryButton(
                isLoading: busy,
                label: t('حفظ', 'Save'),
                onPressed: () async {
                  set(() => busy = true);
                  final ok = await p.setAvailability(type, id, sel);
                  if (ctx.mounted) {
                    set(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Timetables + studio
// ═════════════════════════════════════════════════════════════════════════════

class _TimetablesTab extends StatelessWidget {
  const _TimetablesTab();

  Future<void> _wizard(BuildContext context, OrgScheduleProvider p, {int? id}) async {
    final saved = await TimetableWizard.open(context, p, scheduleId: id);
    if (saved != null) await p.open(saved);
  }

  /// One tap: the term's draft is created and the autopilot generates and fixes it; the studio follows the run.
  Future<void> _generateTerm(BuildContext context, OrgScheduleProvider p, TermNeed n) async {
    final r = await p.generateForTerm(n.id);
    if (!r.ok && context.mounted) toast(orgErrorText(r.error!), error: true);
  }

  /// The current / next term without a timetable, with what the app already knows blocks the generation.
  List<TermNeed> _needs(OrgScheduleProvider p) {
    final blocked = [
      if (p.periods.isEmpty) {'code': 'no_periods', 'text_ar': 'لا توجد فترات زمنية', 'text_en': 'No time periods'},
      if (p.rooms.isEmpty) {'code': 'no_rooms', 'text_ar': 'لا توجد قاعات مفعّلة', 'text_en': 'No active rooms'},
    ];
    if (p.termNeedsLoaded) return [for (final x in p.termNeeds) TermNeed.of(x)];    // the server's full reasons
    return [for (final n in termsNeedingTimetable(p.terms, p.schedules, AppTime.toZone(DateTime.now().toUtc()))) n.withBlocked(blocked)];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    // a deep link (notification, attention item): open that timetable / show the term cards
    final req = timetableRequest.value;
    if (req != null) {
      timetableRequest.value = null;
      final id = req.startsWith('open:') ? int.tryParse(req.substring(5)) : null;
      if (id != null && p.schedule?['id'] != id) WidgetsBinding.instance.addPostFrameCallback((_) => p.open(id));
    }
    if (p.schedule != null) return _Studio(onSetup: (id) => _wizard(context, p, id: id), sidePanel: studioQuickActions);
    final needs = _needs(p);
    final intro = [
      AppHero(
        icon: Icons.calendar_month_rounded,
        title: t('الجداول الدراسية', 'Timetables'),
        subtitle: t(
          'أربع خطوات: 1) الإعداد — الفترات والأماكن والمدرسون · 2) التوليد التلقائي · 3) المراجعة والإصلاح · 4) النشر والمشاركة. افتح أي جدول لترى خطوته التالية.',
          'Four steps: 1) Set up — periods, rooms and teachers · 2) Generate automatically · 3) Review & fix · 4) Publish & share. Open any timetable to see its next step.',
        ),
        stats: [
          AppHeroStat(icon: Icons.table_chart_rounded, value: '${p.schedules.length}', label: t('جداول', 'timetables')),
          AppHeroStat(icon: Icons.verified_rounded, value: '${p.schedules.where((x) => x['status'] == 'active').length}', label: t('منشور', 'published')),
          AppHeroStat(icon: Icons.schedule_rounded, value: '${p.periods.length}', label: t('فترات', 'periods')),
        ],
      ),
      const SizedBox(height: 12),
      for (final n in needs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TermTimetableCard(
            need: n,
            onGenerate: s.can('schedule', 'update') ? () => _generateTerm(context, p, n) : null,
            onSetup: () => DefaultTabController.maybeOf(context)?.animateTo(2),
          ),
        ),
      if (p.periods.isEmpty || p.rooms.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppBanner(
            icon: Icons.flag_rounded,
            color: c.warning,
            text: p.periods.isEmpty
                ? t('ابدأ من تبويب "الفترات والأماكن": أضف فترات اليوم الدراسي.', 'Start in "Periods & rooms": add the periods of the day.')
                : t('أضف القاعات والمعامل من تبويب "الفترات والأماكن".', 'Add your rooms and labs in "Periods & rooms".'),
            action: TextButton(onPressed: () => DefaultTabController.maybeOf(context)?.animateTo(2), child: Text(t('اذهب', 'Go'))),
          ),
        ),
      AppActionCard(
        icon: Icons.assignment_rounded,
        color: c.purple,
        title: t('جداول الامتحانات (منتصف الفصل والنهائية)', 'Exam timetables (midterm & final)'),
        subtitle: t(
          'فترة مقترحة من تواريخ الفصل، بلا امتحانين لنفس الطلاب في وقت واحد، مع الأماكن والمراقبين.',
          'A window suggested from the term dates, no two exams at once for the same students, with rooms and invigilators.',
        ),
        onTap: () => openExamTimetables(context, p, canEdit: s.can('schedule', 'update'), canApprove: s.can('schedule', 'approve'), canExport: s.can('schedule', 'export')),
      ),
      const SizedBox(height: 12),
    ];
    return Stack(
      children: [
        AppRefresh(onRefresh: p.loadSetup, child: p.schedules.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  ...intro,
                  OrgEmpty(
                    icon: Icons.calendar_month_rounded,
                    title: t('لم تنشئ أي جدول بعد', 'No timetable yet'),
                    message: t('أنشئ جدولاً جديداً وسيرشدك المعالج خطوة بخطوة.', 'Create a timetable and the wizard guides you step by step.'),
                    actionLabel: s.can('schedule', 'insert') ? t('جدول جديد', 'New timetable') : null,
                    onAction: () => _wizard(context, p),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  ...intro,
                  for (final x in p.schedules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RowCard(
                        accent: x['status'] == 'active' ? c.success : null,
                        onTap: () => p.open(asInt(x['id'])),
                        child: Row(
                          children: [
                            IconBadge(Icons.calendar_month_rounded, x['status'] == 'active' ? c.success : c.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${x['name']}',
                                    style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, color: c.textDark),
                                  ),
                                  Text(
                                    [
                                      if ('${x['term_label'] ?? ''}'.isNotEmpty) '${x['term_label']}',
                                      '${x['slots'] ?? 0} ${t('حصة', 'slots')}',
                                      if (asMap(x['result'])['status'] != null) resultStatusLabels()['${asMap(x['result'])['status']}'] ?? '',
                                    ].join(' · '),
                                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium),
                                  ),
                                ],
                              ),
                            ),
                            StatusChip(
                              {'active': t('منشور', 'Published'), 'draft': t('مسودة', 'Draft'), 'archived': t('مؤرشف', 'Archived')}['${x['status']}'] ?? '${x['status']}',
                              x['status'] == 'active'
                                  ? c.success
                                  : x['status'] == 'draft'
                                  ? c.warning
                                  : c.textLight,
                            ),
                            if (s.can('schedule', 'update') && x['status'] != 'active')
                              IconButton(
                                tooltip: t('الإعداد خطوة بخطوة', 'Step-by-step setup'),
                                icon: const Icon(Icons.tune_rounded),
                                onPressed: () => _wizard(context, p, id: asInt(x['id'])),
                              ),
                            if (s.can('schedule', 'delete') && x['status'] != 'active')
                              IconButton(tooltip: t('حذف', 'Delete'), 
                                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                                onPressed: () async {
                                  if (await confirm(context, message: t('حذف الجدول؟', 'Delete this timetable?'), danger: true)) p.deleteSchedule(asInt(x['id']));
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              )),
        if (s.can('schedule', 'insert'))
          PositionedDirectional(
            bottom: 16,
            end: 16,
            child: FloatingActionButton.extended(
              heroTag: 'org_add_schedule',
              backgroundColor: c.primary,
              onPressed: () => _wizard(context, p),
              icon: Icon(Icons.add_rounded, color: c.onHero),
              label: Text(
                t('جدول جديد', 'New timetable'),
                style: TextStyle(fontFamily: AppFonts.family, color: c.onHero),
              ),
            ),
          ),
      ],
    );
  }
}

/// The Quick Actions panel shown beside the studio grid (sheet on narrow screens). Wire the generation result /
/// one-rule-relaxation panel here; null = no panel.
const Widget Function(BuildContext context, OrgScheduleProvider p) studioQuickActions = quickActionsSide;

class _Studio extends StatefulWidget {
  const _Studio({required this.onSetup, this.sidePanel});
  final void Function(int id) onSetup;

  /// The Quick Actions panel (generation result, problems, one-rule relaxations): a side column beside the grid on
  /// wide screens, a "Quick actions" button that opens it as a sheet on narrow ones. null = no panel.
  final Widget Function(BuildContext context, OrgScheduleProvider p)? sidePanel;

  @override
  State<_Studio> createState() => _StudioState();
}

class _StudioState extends State<_Studio> {
  int? _followed;
  GridFilter _filter = GridFilter.none;
  List<Map<String, dynamic>> _studentGroups = const [];
  String? _studentName;
  int _view = 0; // 0 grid · 1 the courses that enter the timetable
  String? _askedDecision; // the ladder decision id the dialog was opened for (once per decision)

  // drag & drop preview: the cell under the pointer asks the server (dry run) whether the move is valid
  String? _previewKey;
  bool? _previewOk;
  String? _previewText;

  Future<void> _hover(OrgScheduleProvider p, Map<String, dynamic>? slot, String day, int period) async {
    if (slot == null) {
      if (_previewKey != null) setState(() => _previewKey = null);
      return;
    }
    final key = '${slot['id']}|$day|$period';
    if (key == _previewKey) return;
    setState(() {
      _previewKey = key;
      _previewOk = null;
      _previewText = null;
    });
    final r = await p.previewSlot({'day': day, 'period_id': period}, slotId: asInt(slot['id']));
    if (!mounted || _previewKey != key) return;
    final conflicts = asMapList(r?['conflicts']);
    final hard = conflicts.where((x) => x['severity'] == 'error').toList();
    setState(() {
      _previewOk = r == null ? null : (r['valid'] == true || hard.isEmpty);
      _previewText = hard.isEmpty ? (conflicts.isEmpty ? null : conflictLine(conflicts.first)) : conflictLine(hard.first);
    });
  }

  /// Student filter: search the organization's students, then their group in every course of the term.
  Future<void> _pickStudent(BuildContext context, OrgScheduleProvider p) async {
    final term = p.schedule?['term_id'];
    if (term == null) {
      toast(t('اربط الجدول بفصل دراسي لتصفية حسب الطالب.', 'Link the timetable to a term to filter by student.'), error: true);
      return;
    }
    final q = await askText(context, title: t('ابحث عن طالب (الاسم أو البريد)', 'Find a student (name or e-mail)'));
    if (q == null || q.trim().isEmpty || !context.mounted) return;
    final r = await orgCall(() => p.api.get('${p.base}/members', queryParams: {'role': 'student', 'search': q.trim(), 'size': 20}));
    final found = asMapList(r.map['items']);
    if (!r.ok || !context.mounted) return;
    if (found.isEmpty) return toast(t('لا نتائج', 'No match'), error: true);
    final pick = await showAdminSheet<Map<String, dynamic>>(
      context,
      (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SheetHeader(t('اختر الطالب', 'Choose the student')),
          for (final m in found) ListTile(title: Text('${asMap(m['user'])['name']}'), subtitle: Text('${m['student_code'] ?? asMap(m['user'])['gmail'] ?? ''}'), onTap: () => Navigator.pop(ctx, m)),
        ],
      ),
    );
    if (pick == null || !context.mounted) return;
    final uid = asMap(pick['user'])['id'];
    final g = await orgCall(() => p.api.get('${p.base}/registrar/terms/$term/students/$uid/groups'));
    if (!g.ok || !mounted) return;
    setState(() {
      _studentGroups = asMapList(g.map['items']);
      _studentName = '${asMap(pick['user'])['name']}';
      _filter = GridFilter(GridFilterKind.student, '$uid');
    });
  }

  Future<void> _publish(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> result, int errors, Map<int, String> courseNames) async {
    if (errors > 0) {
      toast(t('عالج التعارضات الإلزامية قبل النشر', 'Fix the hard clashes before publishing'), error: true);
      return showGenerationResult(context, p, courseNames, canEdit: true);
    }
    final st = '${result['status'] ?? ''}';
    if ((st == 'partial' || st == 'infeasible') &&
        !await confirm(context, message: t('النتيجة: ${resultStatusLabels()[st]}. النشر رغم الحصص غير المجدولة؟', 'Result: ${resultStatusLabels()[st]}. Publish with sessions still unplaced?'))) {
      return;
    }
    if (!context.mounted) return;
    final res = await publishWithConsent(context, p);
    if (res != null && res.isNotEmpty && context.mounted) await showPublishConflicts(context, res, courseNames);
  }

  /// The autopilot on the open timetable (POST …/autopilot): the run is followed like a generation.
  Future<void> _autopilot(BuildContext context, OrgScheduleProvider p) => runAutopilotWithPlan(context, p);

  void _export(BuildContext context, OrgScheduleProvider p) => showTimetableExport(
    context,
    slots: p.slots,
    names: timetableNamesOf(p),
    periods: p.periods,
    title: '${p.schedule?['name'] ?? t('الجدول', 'Timetable')}',
    sourceLabel: t('الجدول الحالي · الإصدار ${p.schedule?['version'] ?? 0}', 'Live timetable · version ${p.schedule?['version'] ?? 0}'),
    days: ScheduleDraft.fromJson(p.schedule ?? const {}).days,
    from: ScheduleDraft.fromJson(p.schedule ?? const {}).start,
    to: ScheduleDraft.fromJson(p.schedule ?? const {}).end,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.read<OrgScheduleProvider>();
    final id = p.schedule?['id'];
    if (id != null && id != _followed) {
      _followed = asInt(id);
      // a generation started earlier (or by someone else) is picked up again
      WidgetsBinding.instance.addPostFrameCallback((_) => p.resumeRunIfAny());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final sch = p.schedule!;
    final active = sch['status'] == 'active';
    // the timetable's own teaching days (all seven when configured), plus any day that already holds a session
    final own = ScheduleDraft.fromJson(sch).days;
    final days = [
      for (final d in orgDays)
        if (own.contains(d) || p.slots.any((x) => x['day'] == d)) d,
    ];
    final labels = dayLabels();
    final errors = p.conflicts.where((x) => x['severity'] == 'error').length;
    final run = p.genRun;
    final running = runIsOpen(run);
    final result = asMap(sch['result']);
    final editable = !active && !running && s.can('schedule', 'update');
    // a ladder run (D-013): the live panel / veil are the ladder's; a decision the run waits for is asked in place —
    // the wide side panel shows it inline, a narrow screen opens the dialog once per decision
    final ladderLive = running ? LadderLive.of(run) : null;
    final decision = ladderLive?.isWaiting == true ? ladderLive!.decision : null;
    if (decision != null && decision.id != _askedDecision && MediaQuery.sizeOf(context).width < 1100) {
      _askedDecision = decision.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showLadderDecisionDialog(context, p, decision);
      });
    }

    final courseNames = {for (final l in p.loads) asInt(l['course_id']): courseName(l)};
    final people = {for (final m in p.staff) asInt((m['user'] as Map)['id']): '${(m['user'] as Map)['name']}'};
    final rooms = {for (final r in p.rooms) asInt(r['id']): '${r['name']}'};

    final scoped = {for (final x in (sch['course_ids'] as List?) ?? const []) asInt(x)};
    final noTeacher = p.loads.where((l) => (scoped.isEmpty || scoped.contains(asInt(l['course_id']))) && l['teacher_id'] == null).length;
    final stats = asMap(result['stats']);
    final unplaced = stats['sessions_required'] == null ? 0 : (asInt(stats['sessions_required']) - asInt(stats['sessions_placed'])).clamp(0, 1 << 30);
    final journey = TimetableJourney.of(periods: p.periods.length, rooms: p.rooms.length, noTeacher: noTeacher, slots: p.slots.length, result: result, hard: errors, active: active, running: running);
    final nextText = nextStepText(journey.next, unplaced: unplaced, hard: errors, pending: GenerationOutcome.of(result).pending.length, noTeacher: noTeacher);
    final canEdit = s.can('schedule', 'update') && !active;
    final VoidCallback? nextAction = switch (journey.next) {
      NextAction.addPeriods => s.can('schedule', 'insert') ? () => showPeriodForm(context, p, null) : null,
      NextAction.addRooms => s.can('schedule', 'insert') ? () => showRoomForm(context, p, null) : null,
      NextAction.assignTeachers => () => DefaultTabController.maybeOf(context)?.animateTo(1),
      NextAction.generate => canEdit ? () => createTimetable(context, p) : null,
      NextAction.reviewResult || NextAction.fixClashes => () => showGenerationResult(context, p, courseNames, canEdit: canEdit),
      NextAction.publish => s.can('schedule', 'approve') ? () => _publish(context, p, result, errors, courseNames) : null,
      NextAction.share => s.can('schedule', 'export') ? () => _export(context, p) : () => openTimetableCopies(context, p, canEdit: false),
      NextAction.wait => null,
    };

    // one index per build: cells never scan every slot; one conflict marker per covered cell
    final cohorts = <int, Set<String>>{
      for (final l in p.loads) asInt(l['course_id']): {for (final x in asMapList(asMap(l['course'])['cohorts'])) '${x['program_id']}|${x['level']}'},
    };
    String programName(dynamic v, dynamic id) => v is List && v.length == 2 ? t('${v[0] ?? v[1]}', '${v[1] ?? v[0]}') : '#$id';
    final cohortNames = <String, String>{
      for (final l in p.loads)
        for (final x in asMapList(asMap(l['course'])['cohorts'])) '${x['program_id']}|${x['level']}': '${programName(x['program'], x['program_id'])}${x['level'] == null ? '' : ' · ${x['level']}'}',
    };
    final index = indexSlots(p.slots.where((x) => _filter.keeps(x, cohorts: cohorts, studentGroups: _studentGroups)));
    final clash = conflictCells(p.conflicts, [for (final x in p.periods) asInt(x['id'])]);
    final marks = conflictSlots(p.conflicts);
    final today = orgDays[(AppTime.toZone(DateTime.now().toUtc()).weekday + 1) % 7]; // Mon=1 → index 2 (saturday first)
    final groupNames = <String, String>{
      for (final x in p.slots)
        if (x['group_no'] != null) '${x['kind'] ?? 'lecture'}|${x['group_no']}': '${x['kind'] == 'lab' ? t('معمل', 'Lab') : t('نظري', 'Theory')} ${x['group_no']}',
    };
    Map<String, String> staffOptions(String key) => {
      for (final id in {
        for (final x in p.slots)
          if (x[key] != null) asInt(x[key]),
      })
        '$id': people[id] ?? '#$id',
    };
    final more = <(IconData, String, VoidCallback)>[
      if (s.can('schedule', 'update') && !active) (Icons.tune_rounded, t('إعدادات الجدول (الأيام والمقررات)', 'Timetable settings (days & courses)'), () => widget.onSetup(asInt(sch['id']))),
      (Icons.groups_rounded, t('الأعداد وتقسيم المجموعات', 'Enrollment & group sizes'), () => openCoursePlans(context, p, canEdit: canEdit)),
      (Icons.diversity_3_rounded, t('مجموعات الطلاب', 'Student groups'), () => openStudentGroups(context, p)),
      if (s.can('schedule', 'insert')) (Icons.event_available_rounded, t('فترات خاصة (تعويضية)', 'Special periods (make-up)'), () => _extrasSheet(context, p, courseNames, p.rooms)),
      (Icons.history_rounded, t('النسخ السابقة', 'Versions'), () => _revisionsSheet(context, p)),
      if (s.can('schedule', 'export')) (Icons.file_download_rounded, t('تصدير: إكسل · وورد · PDF', 'Export: Excel · Word · PDF'), () => _export(context, p)),
      (Icons.content_copy_rounded, t('نسخ لكل مدرس ومجموعة', 'Copies for each teacher & group'), () => openTimetableCopies(context, p, canEdit: s.can('schedule', 'update'))),
      if (active && s.can('schedule', 'update'))
        (
          Icons.unpublished_rounded,
          t('إيقاف النشر', 'Unpublish'),
          () async {
            if (await confirm(context, message: t('إيقاف نشر الجدول؟ يعود مسودة ولا يراه الطلاب.', 'Unpublish? It becomes a draft and students stop seeing it.'))) {
              await p.setActive(false);
            }
          },
        ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              AppBackButton(onPressed: p.closeSchedule),
              Expanded(
                child: Text('${sch['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.h2.copyWith(fontSize: 16)),
              ),
              StatusChip(
                {'active': t('منشور', 'Published'), 'draft': t('مسودة', 'Draft'), 'archived': t('مؤرشف', 'Archived')}['${sch['status']}'] ?? '${sch['status']}',
                active ? c.success : c.warning,
              ),
              PopupMenuButton<int>(
                tooltip: t('المزيد', 'More'),
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (i) => more[i].$3(),
                itemBuilder: (_) => [
                  for (var i = 0; i < more.length; i++)
                    PopupMenuItem<int>(
                      value: i,
                      child: Row(
                        children: [
                          Icon(more[i].$1, size: 18),
                          const SizedBox(width: 10),
                          Flexible(child: Text(more[i].$2)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // published exam windows of this term pause these weekly sessions on their dates (exam timetable: pause_weekly)
        if (examPausesOf(sch).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: examPauseBanner(context, examPausesOf(sch), padding: const EdgeInsets.only(bottom: 4), myExamsAction: false),
          ),
        if ((s.can('schedule', 'update') || active) && journey.next != NextAction.wait)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: NextStepBanner(
              title: nextText.$1,
              body: nextText.$2,
              action: nextText.$3,
              tone: journey.tone,
              onAction: nextAction,
              // the AI way out of the review stage: every automatic fix applied and re-solved, nothing forced
              secondary: canEdit && (journey.next == NextAction.reviewResult || journey.next == NextAction.fixClashes) ? t('أصلح تلقائياً', 'Fix automatically') : null,
              onSecondary: canEdit ? () => _autopilot(context, p) : null,
            ),
          ),
        // one toolbar: Create timetable (the ONE generation action, no questions) · its rules · add · publish; rest under ⋮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canEdit)
                ActionChip(
                  avatar: running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.auto_awesome_rounded, size: 18, color: c.primary),
                  label: Text(running ? t('جارٍ الإنشاء…', 'Creating…') : t('إنشاء الجدول', 'Create timetable')),
                  onPressed: running ? null : () => createTimetable(context, p),
                ),
              if (canEdit && !running && (errors > 0 || unplaced > 0))
                ActionChip(
                  avatar: Icon(Icons.auto_fix_high_rounded, size: 18, color: c.primary),
                  label: Text(t('إصلاح تلقائي', 'AI fix')),
                  tooltip: t('يطبّق أفضل حل تلقائي لكل تعارض ويعيد حل ما يلزم، ثم يعرض ما بقي لقرارك', 'Applies the best automatic fix of every clash, re-solves what it must, then shows what is left for you'),
                  onPressed: () => _autopilot(context, p),
                ),
              IconButton(
                tooltip: t('سلّم التوليد', 'Generation ladder'),
                icon: Icon(Icons.stairs_rounded, color: c.primary),
                // the ladder (D-013); an older server without it gets the legacy rules sheet, also linked from inside
                onPressed: () => showLadderSheet(context, p, asInt(sch['id']), canEdit: canEdit && !running),
              ),
              if (s.can('schedule', 'insert') && !active)
                ActionChip(
                  avatar: Icon(Icons.add_rounded, size: 18, color: c.primary),
                  label: Text(t('إضافة حصة', 'Add session')),
                  onPressed: editable ? () => _slotSheet(context, p, null, null, null) : null,
                ),
              if (!active && s.can('schedule', 'approve'))
                Tooltip(
                  message: errors > 0 ? t('النشر ممنوع حتى تُحل التعارضات الإلزامية', 'Publishing is blocked until the hard clashes are fixed') : '',
                  child: ActionChip(
                    avatar: Icon(errors > 0 ? Icons.block_rounded : Icons.publish_rounded, size: 18, color: errors > 0 ? c.textLight : c.success),
                    label: Text(errors > 0 ? t('النشر ممنوع ($errors)', 'Publish blocked ($errors)') : t('نشر', 'Publish')),
                    onPressed: running ? null : () => _publish(context, p, result, errors, courseNames),
                  ),
                ),
            ],
          ),
        ),
        if (run != null && (running || run['schedule_id'] == null || asInt(run['schedule_id']) == asInt(sch['id'])) && (running || run['status'] == 'failed'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            // a ladder run: the live overlay; a waiting run offers "Choose…" here (the dialog), the wide side panel
            // shows the decision inline
            child: ladderLive != null ? LadderLivePanel(p: p) : GenerationLivePanel(run: run, onCancel: running ? () => p.cancelGeneration() : null),
          )
        else if (p.slots.isNotEmpty || result.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConflictsPanel(
                conflicts: p.conflicts,
                onTap: () => showGenerationResult(context, p, courseNames, canEdit: canEdit),
              ),
            ),
          ),
        // one line: the filter bar (grid only) + the grid / courses switch; the colour key under it
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              if (_view == 0)
                Expanded(
                  child: TimetableFilterBar(
                    filter: _filter,
                    studentLabel: _filter.kind == GridFilterKind.student ? _studentName : null,
                    options: {
                      GridFilterKind.cohort: cohortNames,
                      GridFilterKind.teacher: staffOptions('teacher_id'),
                      GridFilterKind.assistant: staffOptions('assistant_id'),
                      GridFilterKind.room: {for (final e in rooms.entries) '${e.key}': e.value},
                      GridFilterKind.group: groupNames,
                    },
                    onChanged: (f) => f.kind == GridFilterKind.student && f.value == null ? _pickStudent(context, p) : setState(() => _filter = f),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.grid_view_rounded, size: 18), tooltip: t('الجدول', 'Grid')),
                  ButtonSegment(value: 1, icon: const Icon(Icons.menu_book_rounded, size: 18), tooltip: t('المقررات', 'Courses')),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
            ],
          ),
        ),
        if (_view == 0 && p.slots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TimetableLegend(kinds: {for (final x in p.slots) '${x['kind'] ?? 'lecture'}'}, conflicts: errors),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              Widget main = _view == 1
                  ? TimetableCoursesView(p: p, canEdit: canEdit)
                  : p.periods.isEmpty
                  ? OrgEmpty(icon: Icons.inbox_rounded, title: t('أضف الفترات أولاً', 'Add periods first'))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TimetableBoard(
                        days: days,
                        periods: p.periods,
                        today: today,
                        dayLabel: (d) => labels[d] ?? d,
                        periodLabel: (per) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${per['label']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 12, color: c.textDark),
                            ),
                            Text(
                              clockOf(per['start_time']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: c.textLight),
                            ),
                          ],
                        ),
                        rowSessions: (pid) => days.fold(0, (m, d) => (index[(d, pid)]?.length ?? 0) > m ? index[(d, pid)]!.length : m),
                        cell: (d, per, h) => _Cell(
                          day: d,
                          periodId: asInt(per['id']),
                          slots: index[(d, asInt(per['id']))] ?? const [],
                          conflict: clash.contains((d, asInt(per['id']))),
                          marks: marks,
                          courseNames: courseNames,
                          rooms: rooms,
                          people: people,
                          onTap: editable ? (_) => _slotSheet(context, p, null, d, asInt(per['id'])) : null,
                          onOpen: (slot) =>
                              showSessionDetails(context, p, slot, courseNames: courseNames, people: people, onEdit: editable ? () => _slotSheet(context, p, slot, d, asInt(per['id'])) : null),
                          onDrop: editable ? (slot) => _moveSlot(context, p, slot, d, asInt(per['id'])) : null,
                          onHover: editable ? (slot) => _hover(p, slot, d, asInt(per['id'])) : null,
                          preview: _previewKey != null && _previewKey!.endsWith('|$d|${per['id']}') ? _previewOk : null,
                          previewText: _previewKey != null && _previewKey!.endsWith('|$d|${per['id']}') ? _previewText : null,
                        ),
                      ),
                    );
              // a new version is being generated: the current one stays visible, dimmed, with the live step in the middle
              if (running && run != null && _view == 0 && p.slots.isNotEmpty) {
                main = Stack(children: [main, ladderLive != null ? LadderVeil(p: p) : GenerationVeil(run: run, onCancel: () => p.cancelGeneration())]);
              }
              final panel = widget.sidePanel;
              if (panel == null) return main;
              // wide: the Quick Actions panel stays beside the grid · narrow: one button opens it as a sheet
              if (box.maxWidth >= 1100) {
                final c = context.colors;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: main),
                    Container(
                      width: 360,
                      margin: const EdgeInsetsDirectional.only(end: 12, bottom: 12),
                      decoration: BoxDecoration(
                        color: c.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.divider),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: panel(context, p),
                    ),
                  ],
                );
              }
              return Stack(
                children: [
                  Positioned.fill(child: main),
                  PositionedDirectional(
                    end: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      heroTag: null,
                      onPressed: () => showAppSheet<void>(context, (ctx) => panel(ctx, p)),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(errors > 0 ? t('إجراءات سريعة ($errors)', 'Quick actions ($errors)') : t('إجراءات سريعة', 'Quick actions')),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _revisionsSheet(BuildContext context, OrgScheduleProvider p) async {
  final items = await p.revisions();
  if (!context.mounted) return;
  final draft = p.schedule?['status'] != 'active';
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    final src = {'generate': t('توليد', 'Generated'), 'restore': t('استعادة', 'Restored'), 'publish': t('نشر', 'Published'), 'manual': t('حفظ يدوي', 'Saved by hand')};
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SheetHeader(t('نسخ الجدول', 'Timetable versions')),
        if (draft && context.read<OrgSession>().can('schedule', 'update'))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.save_rounded),
              label: Text(t('حفظ الوضع الحالي كنسخة', 'Save the current state as a version')),
              onPressed: () async {
                final r = await p.saveSnapshot(null);
                if (r.ok) {
                  toast(t('حُفظت النسخة', 'Version saved'));
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  toast(r.endpointMissing ? t('حفظ النسخ يدوياً يحتاج تحديثاً في الخادم.', 'Saving versions by hand needs a server update.') : orgErrorText(r.error!), error: true);
                }
              },
            ),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t('لا نسخ محفوظة بعد', 'No saved versions yet'), style: orgText(ctx, color: c.textMedium)),
          ),
        for (final r in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text('${r['number']}')),
            title: Text('${src['${r['source']}'] ?? r['source']} · ${t('${r['slots']} حصة', '${r['slots']} slots')}', style: orgText(ctx, w: FontWeight.w700)),
            subtitle: Text(
              [if (r['label'] != null) '${r['label']}', stampOf(r['created_at']), if (r['result_status'] != null) resultStatusLabels()['${r['result_status']}'] ?? ''].join(' · '),
              style: orgText(ctx, size: 12, color: c.textMedium),
            ),
            trailing: draft
                ? TextButton(
                    onPressed: () async {
                      if (!await confirm(ctx, message: t('استعادة هذه النسخة؟ تحل محل الحصص الحالية للمسودة.', 'Restore this version? It replaces the draft\'s current slots.'))) return;
                      if (await p.restoreRevision(asInt(r['id'])) && ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(t('استعادة', 'Restore')),
                  )
                : null,
          ),
        if (!draft) Text(t('الاستعادة متاحة للمسودات فقط.', 'Restoring is for drafts only.'), style: orgText(ctx, size: 12, color: c.textLight)),
      ],
    );
  });
}

/// The server refused to publish: these hard clashes must be fixed first.
Future<void> showPublishConflicts(BuildContext context, List<Map<String, dynamic>> conflicts, Map<int, String> courseNames) => showAdminSheet<void>(
  context,
  (ctx) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader(t('لم يُنشر الجدول', 'Not published')),
        Text(
          t('رفض الخادم النشر لوجود تعارضات إلزامية. عالجها ثم أعد المحاولة.', 'The server refused to publish because of hard clashes. Fix them and try again.'),
          style: orgText(ctx, color: ctx.colors.textMedium),
        ),
        ConflictList(conflicts: conflicts, courseNames: courseNames),
      ],
    ),
  ),
);

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.periodId,
    required this.slots,
    required this.conflict,
    required this.courseNames,
    required this.rooms,
    required this.people,
    this.marks = const {},
    this.onTap,
    this.onDrop,
    this.onOpen,
    this.onHover,
    this.preview,
    this.previewText,
  });
  final String day;
  final int periodId;
  final List<Map<String, dynamic>> slots;
  final bool conflict;

  /// a dragged session entered (slot) / left (null) this cell — the studio runs a dry-run check
  final void Function(Map<String, dynamic>? slot)? onHover;

  /// the dry-run verdict for the session hovering here: true = green, false = red (+ [previewText]), null = unknown
  final bool? preview;
  final String? previewText;

  /// slot id → 'error' | 'warning': the sessions a conflict names (conflictSlots)
  final Map<int, String> marks;
  final Map<int, String> courseNames, people, rooms;
  final void Function(Map<String, dynamic>? slot)? onTap;

  /// a session was tapped: its details (everyone with view rights)
  final void Function(Map<String, dynamic> slot)? onOpen;

  /// a session from another cell was dropped here
  final void Function(Map<String, dynamic> slot)? onDrop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // a mouse drags straight away; on touch a plain drag would fight the grid's scrolling, so it needs a long press
    final platform = Theme.of(context).platform;
    final mouse = kIsWeb || platform == TargetPlatform.windows || platform == TargetPlatform.macOS || platform == TargetPlatform.linux;
    // while a session hovers here the target is green (valid), red (a hard rule, with its reason) or neutral (checking)
    final hoverCol = preview == true ? c.success : (preview == false ? c.danger : c.primary);
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) {
        final ok = onDrop != null && (d.data['day'] != day || asInt(d.data['period_id']) != periodId);
        if (ok) onHover?.call(d.data);
        return ok;
      },
      onLeave: (_) => onHover?.call(null),
      onAcceptWithDetails: (d) {
        onHover?.call(null);
        onDrop!(d.data);
      },
      builder: (context, hovering, _) => GestureDetector(
        onTap: onTap == null ? null : () => onTap!(null),
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: hovering.isNotEmpty
                ? hoverCol.withValues(alpha: 0.16)
                : conflict
                ? c.danger.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hovering.isNotEmpty ? hoverCol : (conflict ? c.danger.withValues(alpha: 0.7) : Colors.transparent), width: conflict || hovering.isNotEmpty ? 1.5 : 1),
          ),
          // the row height comes from the fullest cell of the row; a larger text scale scrolls inside the cell
          child: hovering.isNotEmpty && preview == false && previewText != null
              ? Center(
                  child: Text(previewText!, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 10.5, fontWeight: FontWeight.w800, color: c.danger)),
                )
              : slots.isEmpty
              ? (onTap == null || hovering.isNotEmpty ? const SizedBox.expand() : Center(child: Icon(Icons.add_rounded, size: 18, color: c.textLight.withValues(alpha: 0.45))))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final x in slots)
                        if (onDrop == null)
                          _item(context, x)
                        else if (mouse)
                          Draggable<Map<String, dynamic>>(
                            data: x,
                            feedback: _feedback(context, x),
                            childWhenDragging: Opacity(opacity: 0.35, child: _item(context, x)),
                            child: _item(context, x),
                          )
                        else
                          LongPressDraggable<Map<String, dynamic>>(
                            data: x,
                            feedback: _feedback(context, x),
                            childWhenDragging: Opacity(opacity: 0.35, child: _item(context, x)),
                            child: _item(context, x),
                          ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// what follows the finger / pointer while dragging
  Widget _feedback(BuildContext context, Map<String, dynamic> x) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 144,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Text(
          courseNames[asInt(x['course_id'])] ?? '#${x['course_id']}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 11.5, color: c.onHero),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, Map<String, dynamic> x) {
    final c = context.colors;
    final col = sessionKindColor(c, x['kind']); // one colour per session type
    final mark = marks[asInt(x['id'])];
    final markCol = mark == 'error' ? c.danger : c.warning;
    final sub = [people[asInt(x['teacher_id'])], if (x['room_id'] != null) rooms[asInt(x['room_id'])]].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Tooltip(
      message: '${courseNames[asInt(x['course_id'])] ?? ''} · ${sessionKindLabel(x['kind'])}',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onOpen != null ? () => onOpen!(x) : (onTap == null ? null : () => onTap!(x)),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsetsDirectional.fromSTEB(7, 4, 5, 4),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: mark != null ? Border.all(color: markCol, width: 1.5) : BorderDirectional(start: BorderSide(color: col, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        courseNames[asInt(x['course_id'])] ?? '#${x['course_id']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 11.5, height: 1.25, color: c.textDark),
                      ),
                    ),
                    if (mark != null) Icon(mark == 'error' ? Icons.error_rounded : Icons.warning_amber_rounded, size: 13, color: markCol),
                    if (x['locked'] == true) Icon(Icons.push_pin_rounded, size: 11, color: c.textMedium),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      x['group_no'] == null ? sessionKindLabel(x['kind']) : '${sessionKindLabel(x['kind'])} ${x['group_no']}',
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 9.5, fontWeight: FontWeight.w800, color: col),
                    ),
                    if (sub.isNotEmpty)
                      Expanded(
                        child: Text(
                          ' · $sub',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 10, color: c.textMedium),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag & drop: a move that breaks a hard rule is refused with one line (the slot goes back); a move that only
/// breaks a soft rule is saved and the warning is shown.
Future<void> _moveSlot(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> slot, String day, int period) async {
  final res = await p.moveSlot(slot, day, period);
  if (res == null) {
    final soft = p.conflicts.where((x) => x['severity'] != 'error' && ((x['slot_ids'] as List?) ?? const []).map(asInt).contains(asInt(slot['id'])));
    soft.isEmpty ? toast(t('نُقلت الحصة وثُبّتت', 'Session moved and locked')) : toast('${t('نُقلت مع تنبيه', 'Moved with a warning')}: ${conflictLine(soft.first)}');
    return;
  }
  if (res.isEmpty || res.first['type'] == 'error') return;
  final hard = res.firstWhere((x) => x['severity'] == 'error', orElse: () => res.first);
  toast('${t('لا يمكن النقل', 'Cannot move')}: ${conflictLine(hard)}', error: true);
}

/// One short line for a described conflict (server text_ar / text_en, else its type).
String conflictLine(Map<String, dynamic> x) =>
    t('${x['text_ar'] ?? x['type']}', '${x['text_en'] ?? x['type']}') + (((x['courses'] as List?) ?? const []).isEmpty ? '' : ' — ${(x['courses'] as List).join('، ')}');

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
  String kind = '${slot?['kind'] ?? 'lecture'}';
  int? group = slot?['group_no'] == null ? null : asInt(slot!['group_no']);
  Map<String, dynamic>? check; // the server's instant verdict (dry_run) on the form as it is
  Timer? debounce;
  bool busy = false;
  if (slot == null) {
    final l = courses.firstWhere((x) => asInt(x['course_id']) == course);
    teacher = l['teacher_id'] == null ? null : asInt(l['teacher_id']);
  }
  final labels = dayLabels();
  final canApprove = context.read<OrgSession>().can('schedule', 'approve');
  await showAdminSheet<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.colors;
        Map<String, dynamic> form() => {
          'day': day,
          'period_id': period,
          'room_id': room,
          'teacher_id': teacher,
          'assistant_id': assistant,
          'admin_assistant_id': adm,
          'group_no': group,
          if (slot == null) ...{'course_id': course, 'kind': kind},
        };
        // every change is checked on the server (nothing written), so conflicts show while the form is filled in
        void recheck() {
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 350), () async {
            final r = await p.previewSlot(form(), slotId: slot == null ? null : asInt(slot['id']));
            if (ctx.mounted) set(() => check = r);
          });
        }

        if (check == null && debounce == null) recheck();
        Widget pick(String label, int? v, List<Map<String, dynamic>> items, ValueChanged<int?> on, {bool allowNone = true}) => OrgPickField<int>(
          label: label,
          value: v,
          allowNone: allowNone,
          options: {for (final u in items) asInt(u['id']): '${u['name']}'},
          onChanged: (x) {
            set(() => on(x));
            recheck();
          },
        );
        // the staff fields of an existing session: a scoped change with a before / after comparison (reassign)
        final staffBefore = {'teacher_id': slot?['teacher_id'] == null ? null : asInt(slot!['teacher_id']), 'assistant_id': slot?['assistant_id'] == null ? null : asInt(slot!['assistant_id'])};
        Map<String, int?> staffChanged() => {
              if (slot != null && teacher != staffBefore['teacher_id']) 'teacher_id': teacher,
              if (slot != null && assistant != staffBefore['assistant_id']) 'assistant_id': assistant,
            };
        Future<bool> reassign(String field, int? uid) async {
          final who = uid == null ? t('بلا أحد', 'nobody') : (p.staffOf(field == 'teacher_id' ? 'teacher' : 'teacher_assistant').where((u) => asInt(u['id']) == uid).firstOrNull?['name']?.toString() ?? '#$uid');
          final scope = await askReassignScope(ctx, who: who, fieldLabel: field == 'teacher_id' ? t('المدرس', 'the teacher') : t('المعيد', 'the assistant'));
          if (scope == null || !ctx.mounted) return false;
          DateTime? date;
          if (scope == 'once') {
            date = await pickSlotDate(ctx, day);
            if (date == null || !ctx.mounted) return false;
          }
          final body = {'field': field, 'user_id': uid, 'scope': scope, if (date != null) 'date': isoDate(date)};
          final dry = await p.reassignSlot(asInt(slot!['id']), body, dryRun: true);
          if (!ctx.mounted) return false;
          if (!dry.ok) {
            toast(orgErrorText(dry.error!), error: true);
            return false;
          }
          final plan = ReassignPlan.of(dry.map);
          final people = {for (final u in [...p.staffOf('teacher'), ...p.staffOf('teacher_assistant')]) asInt(u['id']): '${u['name']}'};
          final go = await showReassignCompare(ctx, plan,
              names: {for (final l in p.loads) asInt(l['course_id']): t('${asMap(l['course'])['name_ar'] ?? asMap(l['course'])['name_en']}', '${asMap(l['course'])['name_en'] ?? asMap(l['course'])['name_ar']}')},
              people: people,
              periods: {for (final x in p.periods) asInt(x['id']): '${x['label']}'},
              rooms: {for (final r in p.rooms) asInt(r['id']): '${r['name']}'});
          if (go != true || !ctx.mounted) return false;
          final r = await p.reassignSlot(asInt(slot['id']), {...body, if (!plan.afterWins) 'force': true});
          if (!ctx.mounted) return false;
          if (!r.ok) {
            toast(orgErrorText(r.error!), error: true);
            return false;
          }
          toast(scope == 'once' ? t('حُفظ التغيير لهذا التاريخ وأُبلغ المعنيون', 'Saved for that date — everyone concerned was told') : t('طُبّقت النسخة بعد التغيير (يمكن استرجاع ما قبلها من النسخ)', 'The after version was applied (the before one is kept in versions)'));
          return true;
        }
        Future<void> save({bool force = false, bool replace = false, String? strategy, String? overrideReason}) async {
          set(() => busy = true);
          final body = {...form()}
            ..remove('course_id')
            ..remove('kind');
          final staff = staffChanged();
          if (staff.isNotEmpty) {
            for (final k in staff.keys) {
              body.remove(k);
            }
            final same = body.entries.every((e) => (slot![e.key] == null ? null : '${slot[e.key]}') == (e.value == null ? null : '${e.value}'));
            if (!same) {
              final r0 = await p.editSlot(asInt(slot!['id']), body, force: force);
              if (!ctx.mounted) return;
              if (r0 != null) {
                set(() => busy = false);
                if (r0.isNotEmpty && r0.first['type'] != 'error') {
                  final choice = await showConflictPreview(ctx, r0, canReplace: false, canRebuild: false, canOverride: false);
                  if (choice == 'force' && ctx.mounted) await save(force: true);
                }
                return;
              }
            }
            var done = true;
            for (final e in staff.entries) {
              if (!await reassign(e.key, e.value)) {
                done = false;
                break;
              }
              if (!ctx.mounted) return;
            }
            set(() => busy = false);
            if (done && ctx.mounted) Navigator.pop(ctx);
            return;
          }
          final res = slot == null
              ? await p.addSlot({...body, 'course_id': course, 'kind': kind}, force: force, replace: replace, strategy: strategy, overrideReason: overrideReason)
              : await p.editSlot(asInt(slot['id']), body, force: force);
          if (!ctx.mounted) return;
          set(() => busy = false);
          if (res == null) {
            Navigator.pop(ctx);
          } else if (res.isNotEmpty && res.first['type'] != 'error') {
            final choice = await showConflictPreview(ctx, res, canReplace: slot == null, canRebuild: slot == null, canOverride: slot == null && canApprove);
            if (!ctx.mounted) return;
            switch (choice) {
              case 'replace':
                await save(replace: true);
              case 'force':
                await save(force: true);
              case 'shift' || 'regenerate':
                await save(strategy: choice);
              case 'override':
                final why = await askText(ctx, title: t('سبب الاستثناء (يظهر في السجل)', 'Reason for the override (kept in the log)'), multiline: true);
                if (why != null && why.trim().length >= 3 && ctx.mounted) await save(overrideReason: why.trim());
            }
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(slot == null ? t('حصة جديدة', 'New slot') : t('تعديل الحصة', 'Edit slot')),
              if (slot == null)
                OrgPickField<int>(
                  label: t('المقرر', 'Course'),
                  icon: Icons.menu_book_rounded,
                  value: course,
                  options: {
                    for (final l in courses)
                      asInt(l['course_id']): t('${(l['course'] as Map)['name_ar'] ?? (l['course'] as Map)['name_en']}', '${(l['course'] as Map)['name_en'] ?? (l['course'] as Map)['name_ar']}'),
                  },
                  onChanged: (v) {
                    set(() {
                      course = v ?? course;
                      final l = courses.firstWhere((x) => asInt(x['course_id']) == course);
                      teacher = l['teacher_id'] == null ? null : asInt(l['teacher_id']);
                    });
                    recheck();
                  },
                ),
              if (slot == null) ...[
                const SizedBox(height: 12),
                ChoiceRow<String>(
                  label: t('النوع', 'Type'),
                  options: {'lecture': t('محاضرة', 'Lecture'), 'lab': t('معمل / سكشن', 'Lab / section')},
                  value: kind,
                  onChanged: (v) {
                    set(() => kind = v);
                    recheck();
                  },
                ),
              ],
              const SizedBox(height: 12),
              ChoiceRow<String>(
                options: {for (final d in orgDays) d: labels[d]!},
                value: day,
                onChanged: (v) {
                  set(() => day = v);
                  recheck();
                },
              ),
              const SizedBox(height: 12),
              OrgPickField<int>(
                label: t('الفترة', 'Period'),
                icon: Icons.schedule_rounded,
                value: period,
                options: {for (final x in p.periods) asInt(x['id']): '${x['label']}  (${periodRange(asMap(x))})'},
                onChanged: (v) {
                  set(() => period = v ?? period);
                  recheck();
                },
              ),
              const SizedBox(height: 12),
              pick(t('المجموعة (فارغ = مجموعة واحدة)', 'Group (empty = one group)'), group, [
                for (var g = 1; g <= 12; g++) {'id': g, 'name': '$g'},
              ], (v) => group = v),
              const SizedBox(height: 12),
              pick(t('القاعة', 'Room'), room, [
                for (final r in p.rooms) {'id': r['id'], 'name': '${r['name']} (${r['capacity']})'},
              ], (v) => room = v),
              const SizedBox(height: 12),
              pick(t('المدرس', 'Teacher'), teacher, [for (final u in p.staffOf('teacher')) u], (v) => teacher = v),
              const SizedBox(height: 12),
              pick(t('المعيد', 'Assistant'), assistant, p.staffOf('teacher_assistant'), (v) => assistant = v),
              const SizedBox(height: 12),
              pick(t('المساعد الإداري', 'Admin assistant'), adm, p.staffOf('admin_assistant'), (v) => adm = v),
              const SizedBox(height: 12),
              // instant validation in plain language: hard rules block (red), soft ones warn (amber)
              if (check != null)
                for (final x in asMapList(check!['conflicts']).take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(x['severity'] == 'error' ? Icons.block_rounded : Icons.warning_amber_rounded, size: 16, color: x['severity'] == 'error' ? c.danger : c.warning),
                        const SizedBox(width: 6),
                        Expanded(child: Text(conflictLine(x), style: orgText(ctx, size: 12.5))),
                      ],
                    ),
                  ),
              if (check != null && asMapList(check!['conflicts']).isEmpty)
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: c.success),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(t('لا تعارض', 'No conflict'), style: orgText(ctx, size: 12.5, color: c.success)),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () => save()),
              if (slot != null) ...[
                const SizedBox(height: 4),
                Text(
                  t('تغيير المدرس أو المعيد يسألك عن النطاق (كل المقرر · هذه الحصة أسبوعياً · تاريخ واحد) ويعرض الجدول قبل وبعد.',
                      'Changing the teacher or assistant asks for the scope (whole course · this weekly session · one date) and shows the timetable before and after.'),
                  style: orgText(ctx, size: 11.5, color: c.textLight),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final pinned = slot['locked'] == true;
                          set(() => busy = true);
                          final ok = await p.setLocked(asInt(slot['id']), !pinned);
                          if (!ctx.mounted) return;
                          set(() => busy = false);
                          if (ok) {
                            toast(pinned ? t('أُلغي التثبيت — قد يحرّكها التوليد', 'Unpinned — the generator may move it') : t('ثُبّتت الحصة — لن يحرّكها التوليد', 'Pinned — the generator never moves it'));
                            Navigator.pop(ctx);
                          }
                        },
                  icon: Icon(slot['locked'] == true ? Icons.push_pin_outlined : Icons.push_pin_rounded, color: c.primary),
                  label: Text(slot['locked'] == true ? t('إلغاء تثبيت الحصة', 'Unpin the session') : t('تثبيت الحصة', 'Pin the session'), style: TextStyle(color: c.primary)),
                ),
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
            ],
          ),
        );
      },
    ),
  );
}

/// Special periods: one-off sessions on real dates (make-up / extra lecture or lab). Students + teacher are notified.
Future<void> _extrasSheet(BuildContext context, OrgScheduleProvider p, Map<int, String> courseNames, List<Map<String, dynamic>> rooms) async {
  await p.loadExtras();
  if (!context.mounted) return;
  await showAdminSheet<void>(
    context,
    (ctx) => ChangeNotifierProvider.value(
      value: p,
      child: Consumer<OrgScheduleProvider>(
        builder: (ctx, p, _) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SheetHeader(t('الفترات الخاصة', 'Special periods')),
                Text(
                  t('محاضرة أو سكشن إضافي في تاريخ محدد — يُبلَّغ الطلاب والمدرس فوراً.', 'An extra lecture or section on a specific date — students and the teacher are told right away.'),
                  style: orgText(ctx, size: 12.5, color: c.textMedium),
                ),
                const SizedBox(height: 10),
                for (final e in p.extras)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.divider),
                    ),
                    child: Row(
                      children: [
                        IconBadge(e['kind'] == 'lab' ? Icons.science_rounded : Icons.event_available_rounded, e['kind'] == 'lab' ? c.purple : c.primary, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e['title'] ?? courseNames[asInt(e['course_id'])] ?? ''}', style: orgText(ctx, w: FontWeight.w800)),
                              Text(
                                '${courseNames[asInt(e['course_id'])] ?? ''} · ${calendarDate(e['date'])} · ${AppTime.clockRange('${e['start_time']}', '${e['end_time']}')}',
                                style: orgText(ctx, size: 12, color: c.textMedium),
                              ),
                            ],
                          ),
                        ),
                        IconButton(tooltip: t('إلغاء هذه الفترة', 'Cancel this period'), 
                          icon: Icon(Icons.event_busy_rounded, color: c.danger),
                          onPressed: () async {
                            if (await confirm(ctx, message: t('إلغاء هذه الفترة وإبلاغ الطلاب؟', 'Cancel it and tell the students?'), danger: true)) {
                              await p.deleteExtra(asInt(e['id']));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                PrimaryButton(isLoading: false, label: t('فترة خاصة جديدة', 'New special period'), icon: Icons.add_rounded, iconBefore: true, onPressed: () => _newExtra(ctx, p, courseNames, rooms)),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _newExtra(BuildContext context, OrgScheduleProvider p, Map<int, String> courseNames, List<Map<String, dynamic>> rooms) async {
  int? course = courseNames.keys.isEmpty ? null : courseNames.keys.first;
  String kind = 'lecture';
  DateTime? date;
  TimeOfDay? from, to;
  int? room;
  final title = TextEditingController();
  List<Map<String, dynamic>> clashes = const [];
  await showAdminSheet<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.colors;
        String hm(TimeOfDay x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(t('فترة خاصة جديدة', 'New special period')),
              OrgPickField<int>(label: t('المقرر', 'Course'), icon: Icons.menu_book_rounded, value: course, options: courseNames, onChanged: (v) => set(() => course = v)),
              ChoiceRow<String>(label: t('النوع', 'Type'), options: {'lecture': t('محاضرة', 'Lecture'), 'lab': t('سكشن / معمل', 'Section / lab')}, value: kind, onChanged: (v) => set(() => kind = v)),
              Field(controller: title, label: t('العنوان (مثل: محاضرة تعويضية)', 'Title (e.g. make-up lecture)')),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded),
                      label: Text(date == null ? t('التاريخ', 'Date') : calendarDate(date!.toIso8601String())),
                      onPressed: () async {
                        final d = await showDatePicker(context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100), initialDate: date ?? DateTime.now());
                        if (d != null) set(() => date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      child: Text(from == null ? t('من', 'From') : AppTime.clock(hm(from!)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () async {
                        final x = timeOfDayOf(await pickClock(ctx, from == null ? '10:00' : hm(from!)));
                        if (x != null) set(() => from = x);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      child: Text(to == null ? t('إلى', 'To') : AppTime.clock(hm(to!)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () async {
                        final x = timeOfDayOf(await pickClock(ctx, to == null ? '11:30' : hm(to!)));
                        if (x != null) set(() => to = x);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OrgPickField<int>(
                label: t('المكان (اختياري)', 'Place (optional)'),
                icon: Icons.meeting_room_rounded,
                value: room,
                allowNone: true,
                options: {for (final r in rooms) asInt(r['id']): '${r['name']}'},
                onChanged: (v) => set(() => room = v),
              ),
              for (final x in clashes)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: c.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t('${x['text_ar'] ?? ''}', '${x['text_en'] ?? ''}'), style: orgText(ctx, size: 12.5))),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              PrimaryButton(
                isLoading: false,
                label: t('إضافة وإبلاغ الطلاب', 'Add & notify students'),
                onPressed: () async {
                  if (course == null || date == null || from == null || to == null) {
                    return toast(t('اختر المقرر والتاريخ والوقت', 'Choose the course, date and time'), error: true);
                  }
                  final r = await p.addExtra({
                    'course_id': course,
                    'kind': kind,
                    'date': date!.toIso8601String().substring(0, 10),
                    'start_time': hm(from!),
                    'end_time': hm(to!),
                    'room_id': room,
                    if (title.text.trim().isNotEmpty) 'title': title.text.trim(),
                  });
                  if (r == null) {
                    if (ctx.mounted) Navigator.pop(ctx);
                  } else {
                    set(() => clashes = r.where((x) => x['type'] != 'error').toList());
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Publish; when staff placed in their unavailable time have not agreed yet, say who and offer an audited
/// "publish anyway" with a reason. Same result as [OrgScheduleProvider.publish].
Future<List<Map<String, dynamic>>?> publishWithConsent(BuildContext context, OrgScheduleProvider p) async {
  final res = await p.publish();
  final wait = p.consentWait;
  if (wait == null || !context.mounted) return res;
  final names = {for (final m in p.staff) asInt(m['user_id'] ?? asMap(m['user'])['id']): '${asMap(m['user'])['name'] ?? ''}'};
  String list(String k) => [for (final u in (wait[k] as List? ?? const [])) names[asInt(u)] ?? '#$u'].join('، ');
  final reason = TextEditingController();
  // showAppSheet already keeps the sheet above the keyboard
  final go = await showAppSheet<bool>(
    context,
    (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionTitle(
            t('بانتظار موافقة أعضاء', 'Waiting for staff consent'),
            subtitle: t('الجدول يضعهم في أوقات قالوا إنهم غير متاحين فيها — أُرسل لهم طلب موافقة', 'The timetable puts them in times they marked unavailable — they were asked to agree'),
          ),
          if ((wait['pending'] as List? ?? const []).isNotEmpty) AppBanner(icon: Icons.hourglass_top_rounded, text: '${t('لم يردوا', 'No answer yet')}: ${list('pending')}'),
          if ((wait['declined'] as List? ?? const []).isNotEmpty) ...[
            const SizedBox(height: 8),
            AppBanner(icon: Icons.block_rounded, color: context.colors.danger, text: '${t('اعتذروا', 'Declined')}: ${list('declined')}'),
          ],
          const SizedBox(height: 12),
          AppField(controller: reason, label: t('سبب النشر دون موافقتهم (يُسجَّل)', 'Reason to publish without it (audited)'), maxLines: 2),
          const SizedBox(height: 12),
          AppPrimaryButton(label: t('النشر على أي حال', 'Publish anyway'), icon: Icons.publish_rounded, onPressed: () => Navigator.pop(ctx, reason.text.trim().isNotEmpty)),
        ],
      ),
    ),
  );
  if (go != true) return const [];
  return p.publish(force: true, reason: reason.text.trim());
}
