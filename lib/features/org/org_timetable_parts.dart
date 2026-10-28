// lib/features/org/org_timetable_parts.dart — the building blocks of the timetable studio and wizard
// (API: org_schedule_router.py). The server owns the scheduling algorithm; these screens only edit its inputs and
// show its answers.
//
//   showRoomForm          a room / lab / office (full replacement on save)
//   showFacilityTypes     the organization's own facility types
//   showOfficeMembers     who sits in an office
//   showLoadForm          one course's needs: lecture & lab sessions, staff, room type, capabilities, group sizes
//   showStaffCandidates   eligible teachers / assistants for a course (ranked by the server) with "why not"
//   showStaffPrefs        hard unavailability vs soft prefer / avoid + preferred courses
//   ScheduleResultView    the solver's verdict: status · unscheduled sessions · relaxed preferences · suggestions
//   ConflictList          validate() conflicts in plain words (hard errors first)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/design/app_hscroll.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';

Widget _errorBox(BuildContext context, String text) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: context.colors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: orgText(context, size: 12.5, color: context.colors.danger)),
    );

String courseName(Map l) {
  final c = asMap(l['course']);
  return t('${c['name_ar'] ?? c['name_en'] ?? ''}', '${c['name_en'] ?? c['name_ar'] ?? ''}');
}

/// Capabilities chips with a free-text "add".
class _CapabilityPicker extends StatefulWidget {
  const _CapabilityPicker({required this.value, required this.suggestions, required this.onChanged, required this.label});
  final Set<String> value;
  final Set<String> suggestions;
  final VoidCallback onChanged;
  final String label;

  @override
  State<_CapabilityPicker> createState() => _CapabilityPickerState();
}

class _CapabilityPickerState extends State<_CapabilityPicker> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final v = _ctrl.text.trim().toLowerCase();
    if (v.isEmpty) return;
    widget.value.add(v);
    _ctrl.clear();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final all = {...widget.suggestions, ...widget.value}.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: orgText(context, size: 12.5, w: FontWeight.w800, color: context.colors.textMedium)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in all)
          FilterChip(
              label: Text(x),
              selected: widget.value.contains(x),
              onSelected: (on) {
                on ? widget.value.add(x) : widget.value.remove(x);
                widget.onChanged();
              }),
      ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(hintText: t('مثلاً projector أو computers', 'e.g. projector or computers'), isDense: true),
          ),
        ),
        IconButton(tooltip: t('إضافة', 'Add'), onPressed: _add, icon: const Icon(Icons.add_rounded)),
      ]),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rooms & facilities
// ═════════════════════════════════════════════════════════════════════════════

/// Add or edit a facility. The PUT replaces the room, so every field is sent. Returns true when saved.
Future<bool> showRoomForm(BuildContext context, OrgScheduleProvider p, Map<String, dynamic>? e) async {
  final name = TextEditingController(text: '${e?['name'] ?? ''}');
  final code = TextEditingController(text: '${e?['code'] ?? ''}');
  final cap = TextEditingController(text: '${e?['capacity'] ?? 30}');
  final building = TextEditingController(text: '${e?['building'] ?? ''}');
  final location = TextEditingController(text: '${e?['location'] ?? ''}');
  final image = TextEditingController(text: '${e?['image_url'] ?? ''}');
  final maxM = TextEditingController(text: e?['max_members'] == null ? '' : '${e!['max_members']}');
  final caps = <String>{...((e?['capabilities'] as List?) ?? const []).map((x) => '$x')};
  final allCaps = {for (final r in p.rooms) ...((r['capabilities'] as List?) ?? const []).map((x) => '$x')};
  String kind = '${e?['kind'] ?? 'lecture'}';
  bool exclusive = e?['exclusive'] != false, active = e?['is_active'] != false, busy = false, saved = false;
  String? err;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final kinds = p.kindLabels;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(e == null ? t('مكان جديد', 'New facility') : t('تعديل المكان', 'Edit facility')),
            Row(children: [
              SizedBox(width: 120, child: Field(controller: code, label: t('الكود', 'Code'), ltr: true)),
              const SizedBox(width: 8),
              Expanded(child: Field(controller: name, label: t('الاسم', 'Name'))),
            ]),
            Text(t('النوع', 'Type'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final k in kinds.entries) ChoiceChip(label: Text(k.value), selected: kind == k.key, onSelected: (_) => set(() => kind = k.key)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Field(controller: cap, label: t('السعة', 'Capacity'), keyboard: TextInputType.number, ltr: true)),
              const SizedBox(width: 8),
              Expanded(child: Field(controller: building, label: t('المبنى', 'Building'))),
            ]),
            Field(controller: location, label: t('المكان بالتفصيل (الدور، الجناح…)', 'Location (floor, wing…)')),
            Row(children: [
              if (image.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(image.text.trim(), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 48, height: 48)),
                  ),
                ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final r = await orgPickAndUpload('/api/v1/org/logo', extensions: const ['png', 'jpg', 'jpeg', 'webp'], context: ctx);
                    if (r != null) set(() => image.text = '${r['url']}');
                  },
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text(image.text.trim().isEmpty ? t('صورة المكان', 'Facility photo') : t('تغيير الصورة', 'Change photo')),
                ),
              ),
              if (image.text.trim().isNotEmpty) IconButton(tooltip: t('مسح', 'Clear'), onPressed: () => set(image.clear), icon: Icon(Icons.close_rounded, color: c.textLight)),
            ]),
            const SizedBox(height: 10),
            _CapabilityPicker(label: t('الإمكانات (أجهزة، معدات…)', 'Capabilities (equipment…)'), value: caps, suggestions: allCaps, onChanged: () => set(() {})),
            OrgSwitchRow(
                title: t('حصري', 'Exclusive'),
                subtitle: exclusive ? t('حصة واحدة في الوقت نفسه', 'One session at a time') : t('يمكن مشاركته بين أكثر من حصة', 'Can be shared by several sessions'),
                value: exclusive,
                onChanged: (v) => set(() => exclusive = v)),
            if (kind == 'office')
              Field(controller: maxM, label: t('أقصى عدد للموجودين بالمكتب', 'Maximum occupants'), keyboard: TextInputType.number, ltr: true),
            OrgSwitchRow(
                title: t('متاح', 'Active'),
                subtitle: active ? null : t('لن يستخدمه التوليد', 'The generator won\'t use it'),
                value: active,
                onChanged: (v) => set(() => active = v)),
            if (err != null) _errorBox(ctx, err!),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (name.text.trim().isEmpty) return set(() => err = t('اكتب الاسم', 'Enter a name'));
                String? txt(TextEditingController x) => x.text.trim().isEmpty ? null : x.text.trim();
                final body = {
                  'name': name.text.trim(),
                  'kind': kind,
                  'capacity': int.tryParse(cap.text.trim()) ?? 30,
                  'building': txt(building),
                  'is_active': active,
                  'code': txt(code),
                  'location': txt(location),
                  'image_url': txt(image),
                  'capabilities': caps.toList(),
                  'exclusive': exclusive,
                  'max_members': kind == 'office' ? int.tryParse(maxM.text.trim()) : null,
                };
                set(() {
                  busy = true;
                  err = null;
                });
                final r = await orgCall(() => e == null ? p.api.post('${p.base}/rooms', body: body) : p.api.put('${p.base}/rooms/${e['id']}', body: body), quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) return set(() => err = orgErrorText(r.error!));
                saved = true;
                Navigator.pop(ctx);
                toast(t('تم الحفظ', 'Saved'));
              },
            ),
          ]),
        );
      }));
  if (saved) await p.loadSetup();
  return saved;
}

/// Delete a room; a room used by a published timetable can't be deleted — offer to deactivate it.
Future<void> deleteRoom(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> room) async {
  if (!await confirm(context, message: t('حذف المكان؟', 'Delete this facility?'), danger: true)) return;
  final r = await orgCall(() => p.api.delete('${p.base}/rooms/${room['id']}'), ok: t('تم الحذف', 'Deleted'), quiet: true);
  if (r.ok) return p.loadSetup();
  if (r.code == 'room_in_use' && context.mounted) {
    if (await confirm(context, message: '${orgErrorText(r.error!)}\n${t('إيقافه الآن؟', 'Deactivate it now?')}')) {
      final body = {...room, 'is_active': false}..remove('id');
      final u = await orgCall(() => p.api.put('${p.base}/rooms/${room['id']}', body: body), ok: t('أُوقف المكان', 'Facility deactivated'));
      if (u.ok) await p.loadSetup();
    }
    return;
  }
  toast(orgErrorText(r.error!), error: true);
}

Future<void> showFacilityTypes(BuildContext context, OrgScheduleProvider p) async {
  final items = [for (final f in p.facilityTypes) Map<String, dynamic>.from(f)];
  bool busy = false;
  String? err;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> edit([int? i]) async {
          final key = TextEditingController(text: i == null ? '' : '${items[i]['key']}');
          final ar = TextEditingController(text: i == null ? '' : '${items[i]['label_ar'] ?? ''}');
          final en = TextEditingController(text: i == null ? '' : '${items[i]['label_en'] ?? ''}');
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (d) => AlertDialog(
              title: Text(i == null ? t('نوع جديد', 'New type') : t('تعديل النوع', 'Edit type')),
              scrollable: true,
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Field(controller: key, label: t('المفتاح (حروف إنجليزية صغيرة)', 'Key (lowercase letters)'), ltr: true, enabled: i == null),
                Field(controller: ar, label: t('الاسم بالعربية', 'Arabic label')),
                Field(controller: en, label: t('الاسم بالإنجليزية', 'English label'), ltr: true),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('إلغاء', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(t('تم', 'Done'))),
              ],
            ),
          );
          if (ok != true) return;
          final k = key.text.trim().toLowerCase();
          if (!RegExp(r'^[a-z][a-z0-9_]{1,19}$').hasMatch(k)) return set(() => err = t('المفتاح: حروف إنجليزية صغيرة وأرقام (2–20)', 'Key: lowercase letters and digits (2–20)'));
          set(() {
            err = null;
            final v = {'key': k, 'label_ar': ar.text.trim(), 'label_en': en.text.trim()};
            i == null ? items.add(v) : items[i] = v;
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('أنواع الأماكن', 'Facility types')),
            Text('${t('الأنواع الأساسية', 'Built-in')}: ${p.builtinKinds.map(roomKindLabel).join('، ')}', style: orgText(ctx, size: 12, color: c.textMedium)),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('${items[i]['label_ar'] ?? items[i]['key']}', '${items[i]['label_en'] ?? items[i]['key']}')),
                subtitle: Text('${items[i]['key']}', textDirection: TextDirection.ltr),
                onTap: () => edit(i),
                trailing: IconButton(tooltip: t('حذف', 'Delete'), onPressed: () => set(() => items.removeAt(i)), icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
              ),
            TextButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add_rounded), label: Text(t('نوع جديد', 'New type'))),
            if (err != null) _errorBox(ctx, err!),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                set(() => busy = true);
                final r = await orgCall(() => p.api.put('${p.base}/facility-types', body: {'items': items}), quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) {
                  final kinds = (r.detail['kinds'] as List?)?.join('، ');
                  return set(() => err = '${orgErrorText(r.error!)}${kinds == null ? '' : ' ($kinds)'}');
                }
                Navigator.pop(ctx);
                toast(t('تم الحفظ', 'Saved'));
              },
            ),
          ]),
        );
      }));
  await p.loadSetup();
}

/// Office occupants (several people may share an office, up to its limit).
Future<void> showOfficeMembers(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> room) async {
  final url = '${p.base}/rooms/${room['id']}/members';
  final cur = await orgCall(() => p.api.get(url));
  if (!cur.ok || !context.mounted) return;
  final picked = <int, String>{
    for (final m in asMapList(cur.map['items'])) asInt(asMap(m['user'])['id']): '${m['title'] ?? ''}',
  };
  final people = {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']}'};
  for (final m in asMapList(cur.map['items'])) {
    people.putIfAbsent(asInt(asMap(m['user'])['id']), () => '${asMap(m['user'])['name']}');
  }
  bool busy = false;
  String? err;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final max = room['max_members'] == null ? null : asInt(room['max_members']);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${t('الموجودون في', 'Occupants of')} ${room['name']}'),
            Text(max == null ? t('${picked.length} شخص', '${picked.length} people') : '${picked.length} / $max', style: orgText(ctx, color: c.textMedium)),
            const SizedBox(height: 8),
            if (people.isEmpty) Text(t('أضف أعضاء هيئة أولاً', 'Add staff members first'), style: orgText(ctx, color: c.textLight)),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in people.entries)
                FilterChip(
                    label: Text(e.value),
                    selected: picked.containsKey(e.key),
                    onSelected: (on) => set(() => on ? picked[e.key] = '' : picked.remove(e.key))),
            ]),
            const SizedBox(height: 10),
            if (err != null) _errorBox(ctx, err!),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                set(() => busy = true);
                final r = await orgCall(
                    () => p.api.put(url, body: {
                          'members': [for (final e in picked.entries) {'user_id': e.key, if (e.value.isNotEmpty) 'title': e.value}]
                        }),
                    quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) return set(() => err = orgErrorText(r.error!));
                Navigator.pop(ctx);
                toast(t('تم الحفظ', 'Saved'));
              },
            ),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff candidates & preferences
// ═════════════════════════════════════════════════════════════════════════════

/// Eligible staff for a course (the server ranks them). Returns the picked user id, or null.
Future<int?> showStaffCandidates(BuildContext context, OrgScheduleProvider p, int courseId, String kind, {Set<int> current = const {}}) async {
  final r = await orgCall(() => p.api.get('${p.base}/courses/$courseId/staff-candidates', queryParams: {'kind': kind}));
  if (!r.ok || !context.mounted) return null;
  final eligible = asMapList(r.map['eligible']), not = asMapList(r.map['not_eligible']);
  final pol = asMap(r.map['policy']);
  return showAdminSheet<int>(context, (ctx) {
    final c = ctx.colors;
    Widget row(Map<String, dynamic> x, {bool ok = true}) {
      final u = asMap(x['user']);
      final id = asInt(u['id']);
      final avail = x['available_periods'];
      return ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: ok,
        onTap: ok ? () => Navigator.pop(ctx, id) : null,
        leading: AdminAvatar(name: '${u['name']}', url: u['image_url'] as String?, size: 38),
        title: Text('${u['name']}', style: orgText(ctx, w: FontWeight.w700)),
        subtitle: Text(
            ok
                ? [
                    '${x['role']}' == 'teacher' ? t('مدرس', 'Teacher') : t('معيد', 'Teaching assistant'),
                    if (x['wants_course'] == true) t('يفضّل هذا المقرر ★', 'prefers this course ★'),
                    t('${x['weekly_sessions']} حصة أسبوعياً', '${x['weekly_sessions']} sessions / week'),
                    avail == null ? t('متاح كل الأوقات', 'available any time') : t('$avail فترة متاحة', '$avail periods available'),
                    if (asInt(x['unavailable_periods']) > 0) t('${x['unavailable_periods']} غير متاح', '${x['unavailable_periods']} unavailable'),
                    if (x['experience_level'] != null) t('خبرة ${x['experience_level']} سنة', '${x['experience_level']} yrs'),
                  ].join(' · ')
                : '${x['reason_text'] ?? x['reason']}',
            style: orgText(ctx, size: 12, color: ok ? c.textMedium : c.danger)),
        trailing: current.contains(id) ? Icon(Icons.check_circle_rounded, color: c.success) : null,
      );
    }

    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SheetHeader(kind == 'lab' ? t('مرشحون للسكشن', 'Lab candidates') : t('مرشحون للمحاضرة', 'Lecture candidates')),
      Text(
          kind == 'lab'
              ? (pol['teacher_may_teach_lab'] == false
                  ? t('السكشن للمعيدين فقط (حسب إعدادات المؤسسة).', 'Labs are for teaching assistants only (institution settings).')
                  : t('يُقترح معيد، ويُسمح للمدرس بتدريس السكشن حسب الإعدادات.', 'A teaching assistant is suggested; teachers may teach labs by the settings.'))
              : t('مرتبون حسب الأنسب: من يفضّل المقرر، ثم الأقل حملاً والأكثر إتاحة.', 'Best first: who prefers the course, then lighter load and more availability.'),
          style: orgText(ctx, size: 12, color: c.textMedium)),
      const SizedBox(height: 6),
      if (eligible.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(t('لا يوجد مرشح مؤهل. أضف عضو هيئة للقسم أو راجع إعداد المدرسين العامين.', 'No eligible candidate. Add a staff member to the department or check the general-teacher setting.'),
              style: orgText(ctx, color: c.warning)),
        ),
      for (final x in eligible) row(x),
      if (not.isNotEmpty) ...[
        const Divider(),
        Text(t('غير مؤهلين', 'Not eligible'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
        for (final x in not) row(x, ok: false),
      ],
    ]);
  });
}

/// Hard unavailability vs soft preferences, per staff member.
Future<void> showStaffPrefs(BuildContext context, OrgScheduleProvider p, int userId, String name) async {
  if (p.periods.isEmpty) return toast(t('أضف الفترات أولاً', 'Add periods first'), error: true);
  final url = '${p.base}/staff-prefs/$userId';
  final r = await orgCall(() => p.api.get(url));
  if (!r.ok || !context.mounted) return;
  // cell key 'day|period' → mode; cells that came from their availability reply are read-only here
  final mode = <String, String>{}, fromRequest = <String>{};
  for (final m in const ['unavailable', 'prefer', 'avoid']) {
    for (final x in asMapList(r.map[m])) {
      final k = '${x['day']}|${x['period_id']}';
      if (x['source'] == 'request') {
        fromRequest.add(k);
      }
      mode[k] = m;
    }
  }
  final courses = <int>{...((r.map['course_ids'] as List?) ?? const []).map((e) => asInt(e))};
  String brush = 'unavailable';
  bool busy = false;
  String? err;
  final days = scheduleDays.toList();
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Color col(String? m) => switch (m) { 'unavailable' => c.danger, 'prefer' => c.success, 'avoid' => c.warning, _ => c.inputBg };
        final brushes = {
          'unavailable': t('غير متاح (إلزامي)', 'Unavailable (hard)'),
          'prefer': t('مفضّل (مرن)', 'Preferred (soft)'),
          'avoid': t('يتجنّبه (مرن)', 'Avoid (soft)'),
        };
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${t('تفضيلات', 'Preferences of')} $name'),
            Text(
                t('"غير متاح" قيد إلزامي لا يُكسر إلا باستثناء معتمد. "مفضّل" و"يتجنّبه" تفضيلات قد تُخفَّف عند الضرورة.',
                    '"Unavailable" is a hard rule, broken only by an approved override. "Preferred" and "Avoid" are preferences the generator may relax when needed.'),
                style: orgText(ctx, size: 12, color: c.textMedium)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final b in brushes.entries)
                ChoiceChip(
                  avatar: CircleAvatar(radius: 6, backgroundColor: col(b.key)),
                  label: Text(b.value),
                  selected: brush == b.key,
                  onSelected: (_) => set(() => brush = b.key),
                ),
            ]),
            const SizedBox(height: 8),
            AppHScroll(
              child: Table(defaultColumnWidth: const FixedColumnWidth(62), children: [
                TableRow(children: [
                  const SizedBox(),
                  for (final d in days)
                    Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(dayLabels()[d] ?? d, textAlign: TextAlign.center, style: orgText(ctx, size: 11.5, w: FontWeight.w800))),
                ]),
                for (final per in p.periods)
                  TableRow(children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text('${per['label']}', textAlign: TextAlign.center, style: orgText(ctx, size: 11.5, color: c.textMedium))),
                    for (final d in days)
                      Builder(builder: (_) {
                        final k = '$d|${per['id']}';
                        final locked = fromRequest.contains(k);
                        return GestureDetector(
                          onTap: locked ? null : () => set(() => mode[k] == brush ? mode.remove(k) : mode[k] = brush),
                          child: Container(
                            height: 36,
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: mode[k] == null ? c.inputBg : col(mode[k]).withValues(alpha: locked ? 0.45 : 0.9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: locked ? Icon(Icons.lock_rounded, size: 14, color: c.onHero) : null,
                          ),
                        );
                      }),
                  ]),
              ]),
            ),
            if (fromRequest.isNotEmpty)
              Text(t('🔒 من رد طلب المواعيد — يُعدَّل من هناك', '🔒 From their availability reply — edited there'), style: orgText(ctx, size: 11.5, color: c.textLight)),
            const SizedBox(height: 10),
            Text(t('المقررات المفضّلة', 'Preferred courses'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in p.loads)
                FilterChip(
                    label: Text(courseName(l)),
                    selected: courses.contains(asInt(l['course_id'])),
                    onSelected: (on) => set(() => on ? courses.add(asInt(l['course_id'])) : courses.remove(asInt(l['course_id'])))),
            ]),
            const SizedBox(height: 10),
            if (err != null) _errorBox(ctx, err!),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                List<Map<String, dynamic>> cells(String m) => [
                      for (final e in mode.entries)
                        if (e.value == m && !fromRequest.contains(e.key)) {'day': e.key.split('|')[0], 'period_id': int.parse(e.key.split('|')[1])}
                    ];
                set(() {
                  busy = true;
                  err = null;
                });
                final res = await orgCall(
                    () => p.api.put(url, body: {
                          'unavailable': cells('unavailable'),
                          'prefer': cells('prefer'),
                          'avoid': cells('avoid'),
                          'course_ids': courses.toList(),
                        }),
                    quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!res.ok) return set(() => err = orgErrorText(res.error!));
                Navigator.pop(ctx);
                toast(t('حُفظت التفضيلات', 'Preferences saved'));
              },
            ),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Course needs (load)
// ═════════════════════════════════════════════════════════════════════════════

/// One course's requirements and staff. Returns true when the server saved it.
Future<bool> showLoadForm(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> l, {VoidCallback? onStudentAvailability}) async {
  int? teacher = l['teacher_id'] == null ? null : asInt(l['teacher_id']);
  int? adm = l['admin_assistant_id'] == null ? null : asInt(l['admin_assistant_id']);
  final assistants = <int>{...((l['assistant_ids'] as List?) ?? const []).map(asInt)};
  int sessions = asInt(l['sessions_per_week'], 1), span = asInt(l['periods_per_session'], 1);
  int labSessions = asInt(l['lab_sessions_per_week'], 0), labSpan = asInt(l['lab_periods_per_session'], 1);
  String labRoom = (l['lab_room_kind'] as String?) ?? 'lab';
  String? room = l['room_kind'] as String?;
  final caps = <String>{...((l['required_capabilities'] as List?) ?? const []).map((e) => '$e')};
  final labCaps = <String>{...((l['lab_required_capabilities'] as List?) ?? const []).map((e) => '$e')};
  final allCaps = {for (final r in p.rooms) ...((r['capabilities'] as List?) ?? const []).map((x) => '$x')};
  final cid = asInt(l['course_id']);
  bool practical = l['practical_based'] == true;
  String num(dynamic v) => v == null ? '' : '$v';
  final expected = TextEditingController(text: num(asMap(l['course'])['expected_enrollment']));
  final lecMax = TextEditingController(text: num(l['lecture_max_group'])), labMax = TextEditingController(text: num(l['lab_max_group']));
  int? parsed(TextEditingController x) => int.tryParse(x.text.trim());
  final people = {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']}'};
  bool busy = false, saved = false;
  String? err;
  const roomKinds = ['lecture', 'lab', 'hall', 'other'];      // what a load accepts
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget stepper(String label, int v, int min, int max, ValueChanged<int> on) => Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark))),
              IconButton(tooltip: t('تقليل', 'Decrease'), onPressed: v > min ? () => set(() => on(v - 1)) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
              Text('$v', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              IconButton(tooltip: t('زيادة', 'Increase'), onPressed: v < max ? () => set(() => on(v + 1)) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
            ]);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(courseName(l)),
            // ── lecture ──
            Row(children: [
              Expanded(
                child: OrgPickField<int>(
                  label: t('المدرس', 'Teacher'),
                  icon: Icons.person_rounded,
                  value: teacher,
                  allowNone: true,
                  options: {for (final u in p.staffOf('teacher')) asInt(u['id']): '${u['name']}'},
                  onChanged: (v) => set(() => teacher = v),
                ),
              ),
              IconButton(
                tooltip: t('مرشحون مؤهلون', 'Eligible candidates'),
                icon: Icon(Icons.auto_awesome_rounded, color: c.primary),
                onPressed: () async {
                  final id = await showStaffCandidates(ctx, p, cid, 'lecture', current: {?teacher});
                  if (id != null) set(() => teacher = id);
                },
              ),
            ]),
            stepper(t('عدد المحاضرات أسبوعياً', 'Lectures per week'), sessions, 1, 14, (v) => sessions = v),
            stepper(t('فترات المحاضرة الواحدة', 'Periods per lecture'), span, 1, 6, (v) => span = v),
            ChoiceRow<String>(
              label: t('نوع القاعة', 'Room type'),
              options: {'any': t('أي قاعة', 'Any'), for (final k in roomKinds) k: roomKindLabel(k)},
              value: room ?? 'any',
              onChanged: (v) => set(() => room = v == 'any' ? null : v),
            ),
            const SizedBox(height: 8),
            _CapabilityPicker(label: t('إمكانات مطلوبة للمحاضرة', 'Capabilities the lecture needs'), value: caps, suggestions: allCaps, onChanged: () => set(() {})),
            // ── sizes: group size = the smaller of the course maximum and the room capacity ──
            Row(children: [
              Expanded(child: Field(controller: expected, label: t('العدد المتوقع للطلاب', 'Expected enrolment'), keyboard: TextInputType.number, ltr: true)),
              const SizedBox(width: 8),
              Expanded(child: Field(controller: lecMax, label: t('أقصى حجم لمجموعة النظري', 'Max theory group'), keyboard: TextInputType.number, ltr: true)),
            ]),
            OrgSwitchRow(
              title: t('مقرر عملي أساساً', 'Practical-based course'),
              subtitle: t('يُدرّس الجزء الأساسي في المعامل فقط', 'Its main part is taught in labs only'),
              value: practical,
              onChanged: (v) => set(() => practical = v),
            ),
            const SizedBox(height: 12),
            // ── lab ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: c.purple.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.purple.withValues(alpha: 0.25))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.science_rounded, color: c.purple, size: 20),
                  const SizedBox(width: 6),
                  Flexible(child: Text(t('السكشن / المعمل', 'Section / lab'), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark))),
                ]),
                stepper(t('عدد السكاشن أسبوعياً (0 = لا يوجد)', 'Labs per week (0 = none)'), labSessions, 0, 14, (v) => labSessions = v),
                if (labSessions > 0) ...[
                  stepper(t('فترات السكشن الواحد', 'Periods per lab'), labSpan, 1, 6, (v) => labSpan = v),
                  Field(
                      controller: labMax,
                      label: t('أقصى حجم لمجموعة المعمل (فارغ = الافتراضي ${asInt(asMap(p.schedule?['settings'])['lab_group_default'], 25)})',
                          'Max lab group (empty = default ${asInt(asMap(p.schedule?['settings'])['lab_group_default'], 25)})'),
                      keyboard: TextInputType.number,
                      ltr: true),
                  ChoiceRow<String>(
                    label: t('مكان السكشن', 'Lab room'),
                    options: {for (final k in roomKinds) k: roomKindLabel(k)},
                    value: labRoom,
                    onChanged: (v) => set(() => labRoom = v),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text(t('المعيدون', 'Teaching assistants'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium))),
                    TextButton.icon(
                      onPressed: () async {
                        final id = await showStaffCandidates(ctx, p, cid, 'lab', current: assistants);
                        if (id == null) return;
                        final isTeacher = p.staff.any((m) => asInt(asMap(m['user'])['id']) == id && m['role'] == 'teacher');
                        set(() => isTeacher ? teacher = id : assistants.add(id));
                      },
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(t('اقتراح', 'Suggest')),
                    ),
                  ]),
                  Wrap(spacing: 8, children: [
                    for (final u in p.staffOf('teacher_assistant'))
                      FilterChip(
                        label: Text('${u['name']}'),
                        selected: assistants.contains(asInt(u['id'])),
                        onSelected: (on) => set(() => on ? assistants.add(asInt(u['id'])) : assistants.remove(asInt(u['id']))),
                      ),
                    for (final id in assistants.where((i) => !p.staffOf('teacher_assistant').any((u) => asInt(u['id']) == i)))
                      InputChip(label: Text(people[id] ?? '#$id'), onDeleted: () => set(() => assistants.remove(id))),
                  ]),
                  Text(
                      assistants.isEmpty
                          ? t('بدون معيد يدرّسه المدرس إن سمحت الإعدادات، وإلا يرفض الخادم الحفظ.', 'Without an assistant the teacher teaches it if the settings allow; otherwise the server refuses.')
                          : t('يدرّسه المعيد في وقت منفصل عن المحاضرة.', 'Taught by the assistant, at a different time from the lecture.'),
                      style: orgText(ctx, size: 11.5, color: c.textMedium)),
                  const SizedBox(height: 8),
                  _CapabilityPicker(label: t('إمكانات مطلوبة للسكشن', 'Capabilities the lab needs'), value: labCaps, suggestions: allCaps, onChanged: () => set(() {})),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            OrgPickField<int>(
              label: t('مساعد إداري (اختياري)', 'Admin assistant (optional)'),
              icon: Icons.badge_rounded,
              value: adm,
              allowNone: true,
              options: {for (final u in p.staffOf('admin_assistant')) asInt(u['id']): '${u['name']}'},
              onChanged: (v) => set(() => adm = v),
            ),
            if (onStudentAvailability != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: onStudentAvailability, icon: const Icon(Icons.groups_rounded), label: Text(t('أوقات حضور الطلاب', 'Student availability'))),
            ],
            const SizedBox(height: 12),
            if (err != null) _errorBox(ctx, err!),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                set(() {
                  busy = true;
                  err = null;
                });
                final r = await orgCall(
                    () => p.api.put('${p.base}/loads/$cid', body: {
                          'teacher_id': teacher,
                          'assistant_ids': assistants.toList(),
                          'admin_assistant_id': adm,
                          'sessions_per_week': sessions,
                          'periods_per_session': span,
                          'room_kind': room,
                          'lab_sessions_per_week': labSessions,
                          'lab_periods_per_session': labSpan,
                          'lab_room_kind': labRoom,
                          'required_capabilities': caps.toList(),
                          'lab_required_capabilities': labSessions > 0 ? labCaps.toList() : <String>[],
                          'lecture_max_group': parsed(lecMax),
                          'lab_max_group': labSessions > 0 ? parsed(labMax) : null,
                          'practical_based': practical,
                          'expected_enrollment': parsed(expected),
                        }),
                    quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) {
                  final who = r.detail['user_id'] == null ? '' : ' — ${people[asInt(r.detail['user_id'])] ?? '#${r.detail['user_id']}'}';
                  final why = r.detail['message'] == null ? '' : ': ${r.detail['message']}';
                  return set(() => err = '${orgErrorText(r.error!)}$who$why');
                }
                saved = true;
                Navigator.pop(ctx);
                toast(t('تم الحفظ', 'Saved'));
              },
            ),
          ]),
        );
      }));
  if (saved) await p.loadSetup();
  return saved;
}

/// Problems a load has before generating (local hints; the server decides).
List<String> loadHints(Map<String, dynamic> l) => [
      if (l['teacher_id'] == null) t('بلا مدرس', 'no teacher'),
      if (asInt(l['lab_sessions_per_week']) > 0 && ((l['assistant_ids'] as List?) ?? const []).isEmpty) t('السكشن بلا معيد', 'lab without an assistant'),
    ];

// ═════════════════════════════════════════════════════════════════════════════
//  Results & conflicts
// ═════════════════════════════════════════════════════════════════════════════

class ScheduleResultView extends StatelessWidget {
  const ScheduleResultView({super.key, required this.result, required this.courseNames, required this.people});
  final Map<String, dynamic> result;
  final Map<int, String> courseNames, people;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final st = '${result['status']}';
    final stats = asMap(result['stats']);
    final unscheduled = asMapList(result['unscheduled']);
    final relaxed = asMapList(result['relaxed']);
    final suggestions = asMapList(result['suggestions']);
    final col = switch (st) { 'feasible' => c.success, 'feasible_relaxed' => c.primary, 'partial' => c.warning, _ => c.danger };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: col.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: col.withValues(alpha: 0.35))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(st == 'feasible' || st == 'feasible_relaxed' ? Icons.verified_rounded : Icons.report_rounded, color: col, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(resultStatusLabels()[st] ?? st, style: orgText(context, size: 15, w: FontWeight.w800, color: col)),
              const SizedBox(height: 2),
              Text(resultStatusHelp(st), style: orgText(context, size: 12.5, color: c.textMedium)),
              if (stats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    OrgPill(t('${stats['sessions_placed']} من ${stats['sessions_required']} حصة', '${stats['sessions_placed']} of ${stats['sessions_required']} sessions'),
                        icon: Icons.event_available_rounded, color: col),
                    if (stats['soft_cost'] != null)
                      OrgPill('${t('تكلفة التفضيلات', 'Preference cost')}: ${asDouble(stats['soft_cost']).toStringAsFixed(1)}', icon: Icons.tune_rounded),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      if (unscheduled.isNotEmpty) ...[
        OrgSectionTitle(t('حصص لم تُجدول (${unscheduled.length})', 'Sessions not placed (${unscheduled.length})'), padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
        for (final u in unscheduled)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(u['kind'] == 'lab' ? Icons.science_rounded : Icons.menu_book_rounded, color: c.warning),
            title: Text(
                '${courseNames[asInt(u['course_id'])] ?? '#${u['course_id']}'}${u['kind'] == 'lab' ? ' · ${t('سكشن', 'lab')}' : ''} — ${t('${u['missing']} ناقصة', '${u['missing']} missing')}',
                style: orgText(context, w: FontWeight.w700)),
            subtitle: Text(
                [
                  scheduleReasonText('${u['reason'] ?? u['type']}'),
                  if (asMap(u['blocking']).isNotEmpty)
                    '${t('الأسباب', 'Blocked by')}: ${asMap(u['blocking']).entries.map((e) => '${scheduleReasonText(e.key)} ×${e.value}').join('، ')}',
                ].where((x) => x.isNotEmpty).join('\n'),
                style: orgText(context, size: 12, color: c.textMedium)),
          ),
      ],
      if (relaxed.isNotEmpty) ...[
        OrgSectionTitle(t('تفضيلات خُففت', 'Preferences relaxed'), padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
        for (final x in relaxed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune_rounded, color: c.primary),
            title: Text(people[asInt(x['user_id'])] ?? '#${x['user_id']}', style: orgText(context, w: FontWeight.w700)),
            subtitle: Text(
                [
                  if (asInt(x['avoided_cell_used']) > 0) t('${x['avoided_cell_used']} حصة في وقت يتجنّبه', '${x['avoided_cell_used']} in avoided times'),
                  if (asInt(x['outside_preferred']) > 0) t('${x['outside_preferred']} خارج أوقاته المفضّلة', '${x['outside_preferred']} outside preferred times'),
                  if (x['experience_level'] != null) t('الخبرة المسجّلة: ${x['experience_level']} سنة', 'Recorded experience: ${x['experience_level']} yrs'),
                ].join(' · '),
                style: orgText(context, size: 12, color: c.textMedium)),
          ),
      ],
      if (suggestions.isNotEmpty) ...[
        OrgSectionTitle(t('اقتراحات', 'Suggestions'), padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
        for (final x in suggestions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lightbulb_rounded, color: c.accent2),
            title: Text(scheduleReasonText('${x['reason']}'), style: orgText(context, w: FontWeight.w700)),
            subtitle: Text('${x['text'] ?? ''}', textDirection: TextDirection.ltr, style: orgText(context, size: 12, color: c.textMedium)),
          ),
      ],
    ]);
  }
}

class ConflictList extends StatelessWidget {
  const ConflictList({super.key, required this.conflicts, required this.courseNames});
  final List<Map<String, dynamic>> conflicts;
  final Map<int, String> courseNames;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = [...conflicts]..sort((a, b) => (a['severity'] == 'error' ? 0 : 1).compareTo(b['severity'] == 'error' ? 0 : 1));
    return Column(children: [
      for (final x in sorted)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(x['severity'] == 'error' ? Icons.error_rounded : Icons.warning_amber_rounded, color: x['severity'] == 'error' ? c.danger : c.warning),
          title: Text(x['text_ar'] != null ? t('${x['text_ar']}', '${x['text_en'] ?? x['text_ar']}') : conflictTypeText('${x['type']}'),
              style: orgText(context, w: FontWeight.w700)),
          subtitle: Text(
              [
                if (x['day'] != null) dayLabels()['${x['day']}'] ?? '${x['day']}',
                ((x['course_ids'] as List?) ?? const []).map((i) => courseNames[asInt(i)] ?? '#$i').join(' / '),
                if (x['severity'] == 'error') t('قيد إلزامي', 'hard rule') else t('تنبيه', 'warning'),
              ].where((s) => s.isNotEmpty).join(' · '),
              style: orgText(context, size: 12, color: c.textMedium)),
        ),
    ]);
  }
}
