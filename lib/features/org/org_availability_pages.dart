// lib/features/org/org_availability_pages.dart
//
//   OrgAvailabilityRequestsPage  timetable office: "send us your available periods" — deadline, min / max periods,
//                                who must answer, live progress (who sent / who didn't)
//   AvailabilityRequestScreen    teachers / assistants: a FROZEN screen (can't be dismissed) until they submit
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_providers.dart';
import 'org_ui.dart';

Map<String, String> _days() => {
      'saturday': t('السبت', 'Sat'), 'sunday': t('الأحد', 'Sun'), 'monday': t('الاثنين', 'Mon'), 'tuesday': t('الثلاثاء', 'Tue'),
      'wednesday': t('الأربعاء', 'Wed'), 'thursday': t('الخميس', 'Thu'), 'friday': t('الجمعة', 'Fri'),
    };

class OrgAvailabilityRequestsPage extends StatefulWidget {
  const OrgAvailabilityRequestsPage({super.key});

  @override
  State<OrgAvailabilityRequestsPage> createState() => _OrgAvailabilityRequestsPageState();
}

class _OrgAvailabilityRequestsPageState extends State<OrgAvailabilityRequestsPage> {
  List<Map<String, dynamic>>? _items;

  String get _base => '${context.read<OrgSession>().base}/availability-requests';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_base);
    if (mounted) setState(() => _items = asMapList(r?['items']));
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final title = TextEditingController(text: '${item?['title'] ?? t('مواعيدك المتاحة للفصل القادم', 'Your availability for next term')}');
    final msg = TextEditingController(text: '${item?['message'] ?? ''}');
    final minC = TextEditingController(text: '${item?['min_cells'] ?? 4}');
    final maxC = TextEditingController(text: '${item?['max_cells'] ?? ''}');
    DateTime deadline = DateTime.tryParse('${item?['deadline'] ?? ''}') ?? DateTime.now().add(const Duration(days: 7));
    final roles = {...((item?['roles'] as List?) ?? const ['teacher', 'teacher_assistant']).map((e) => '$e')};
    bool busy = false;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('طلب المواعيد المتاحة', 'Ask for availability')),
              Field(controller: title, label: t('العنوان', 'Title')),
              Field(controller: msg, label: t('رسالة توضيحية (اختياري)', 'Message (optional)'), maxLines: 3),
              Text(t('مطلوب من', 'Who must answer'), style: orgText(ctx, size: 12.5, color: c.textLight)),
              Wrap(spacing: 8, children: [
                for (final e in {'teacher': t('هيئة التدريس', 'Teaching staff'), 'teacher_assistant': t('الهيئة المعاونة', 'Assistants'),
                  'admin_assistant': t('الإداريون', 'Admin staff')}.entries)
                  FilterChip(label: Text(e.value), selected: roles.contains(e.key),
                      onSelected: (on) => set(() => on ? roles.add(e.key) : roles.remove(e.key))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Field(controller: minC, label: t('أقل عدد فترات', 'Minimum periods'), keyboard: TextInputType.number, ltr: true)),
                const SizedBox(width: 10),
                Expanded(child: Field(controller: maxC, label: t('أقصى عدد (اختياري)', 'Maximum (optional)'), keyboard: TextInputType.number, ltr: true)),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_rounded, color: c.primary),
                title: Text(t('آخر موعد للإرسال', 'Deadline')),
                subtitle: Text(shortDateTime(deadline.toIso8601String())),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: deadline);
                  if (d == null || !ctx.mounted) return;
                  final tm = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 23, minute: 59));
                  set(() => deadline = DateTime(d.year, d.month, d.day, tm?.hour ?? 23, tm?.minute ?? 59));
                },
              ),
              const SizedBox(height: 6),
              PrimaryButton(
                isLoading: busy,
                label: item == null ? t('إرسال الطلب', 'Send the request') : t('حفظ', 'Save'),
                onPressed: () async {
                  set(() => busy = true);
                  final b = {'title': title.text.trim(), 'message': msg.text.trim(), 'roles': roles.toList(),
                    'deadline': deadline.toIso8601String(), 'min_cells': int.tryParse(minC.text) ?? 1,
                    'max_cells': int.tryParse(maxC.text), 'status': item?['status'] ?? 'open'};
                  final r = item == null ? await OrgApi.i.post(_base, b, t('أُرسل الطلب ✉️', 'Request sent ✉️')) : await OrgApi.i.put('$_base/${item['id']}', b, t('تم', 'Done'));
                  if (!ctx.mounted) return;
                  set(() => busy = false);
                  if (r != null) Navigator.pop(ctx);
                },
              ),
            ]),
          );
        }));
    _load();
  }

  Future<void> _status(Map<String, dynamic> item) async {
    final r = await OrgApi.i.getMap('$_base/${item['id']}/status');
    if (r == null || !mounted) return;
    final rows = asMapList(r['items']);
    await showAdminSheet<void>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SheetHeader('${item['title']}'),
          for (final x in rows)
            ListTile(
              leading: Icon(x['submitted'] == true ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                  color: x['submitted'] == true ? ctx.colors.success : ctx.colors.warning),
              title: Text('${asMap(x['user'])['name']}'),
              subtitle: Text(x['submitted'] == true ? t('أرسل ${x['cells']} فترة', 'Sent ${x['cells']} periods') : t('لم يرسل بعد', 'Not yet')),
            ),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(heroTag: 'avreq', onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(t('طلب جديد', 'New request'))),
      body: OrgAsync(
        loading: items == null,
        failed: false,
        onRetry: _load,
        child: (items ?? const []).isEmpty
            ? OrgEmpty(icon: Icons.event_available_rounded, title: t('اطلب المواعيد المتاحة', 'Ask for availability'),
                message: t('يظهر الطلب لهيئة التدريس كشاشة لا تُغلق حتى يرسلوا مواعيدهم قبل الموعد النهائي.',
                    'Staff see it as a screen that stays until they send their periods before the deadline.'),
                actionLabel: t('طلب جديد', 'New request'), onAction: () => _edit())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
                for (final it in items!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RowCard(
                      onTap: () => _status(it),
                      child: Row(children: [
                        IconBadge(Icons.event_available_rounded, it['status'] == 'open' ? c.primary : c.textLight, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${it['title']}', style: orgText(context, w: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              OrgPill('${it['submitted']} / ${it['targeted']}', icon: Icons.how_to_reg_rounded, color: c.success),
                              OrgPill('${t('حتى', 'until')} ${shortDateTime('${it['deadline']}')}', icon: Icons.timer_rounded, color: c.warning),
                              OrgPill('${it['min_cells']}–${it['max_cells'] ?? '∞'}', icon: Icons.grid_view_rounded),
                            ]),
                          ]),
                        ),
                        PopupMenuButton<String>(onSelected: (v) async {
                          if (v == 'edit') await _edit(it);
                          if (v == 'close') { await OrgApi.i.put('$_base/${it['id']}', {...it, 'status': 'closed'}, t('أُغلق', 'Closed')); _load(); }
                          if (v == 'delete' && await confirm(context, message: t('حذف الطلب؟', 'Delete?'), danger: true)) { await OrgApi.i.del('$_base/${it['id']}'); _load(); }
                        }, itemBuilder: (_) => [
                          PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
                          if (it['status'] == 'open') PopupMenuItem(value: 'close', child: Text(t('إغلاق', 'Close'))),
                          PopupMenuItem(value: 'delete', child: Text(t('حذف', 'Delete'))),
                        ]),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}

/// Teachers / assistants: a frozen screen until they send their available periods (or the deadline passes).
class AvailabilityRequestScreen extends StatefulWidget {
  const AvailabilityRequestScreen({super.key, required this.requestId});
  final int requestId;

  @override
  State<AvailabilityRequestScreen> createState() => _AvailabilityRequestScreenState();
}

class _AvailabilityRequestScreenState extends State<AvailabilityRequestScreen> {
  Map<String, dynamic>? _r;
  final _picked = <String>{};
  bool _busy = false, _done = false;

  String _k(String day, int pid) => '$day|$pid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get('$orgBase/public/me/availability-requests');
      final it = asMapList((r as Map)['items']).where((x) => asInt(x['id']) == widget.requestId).toList();
      if (!mounted) return;
      if (it.isEmpty) {
        setState(() => _done = true);       // already sent / closed → release the screen
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _r = it.first;
        for (final c in asMapList(it.first['current'])) {
          _picked.add(_k('${c['day']}', asInt(c['period_id'])));
        }
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ApiClient().post('$orgBase/public/availability-requests/${widget.requestId}/submit', body: {
        'cells': [for (final k in _picked) {'day': k.split('|')[0], 'period_id': int.parse(k.split('|')[1])}],
      });
      if (!mounted) return;
      setState(() => _done = true);
      toast(t('شكراً لك — وصلت مواعيدك 🌿', 'Thank you — your periods were sent 🌿'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _r;
    final minC = asInt(r?['min_cells'], 1);
    final maxC = r?['max_cells'] == null ? null : asInt(r?['max_cells']);
    final ok = _picked.length >= minC && (maxC == null || _picked.length <= maxC);
    return PopScope(
      canPop: _done,                                 // frozen until submitted
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: r == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(colors: [c.primary, c.primaryDark]),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(orgNameOf(asMap(r['organization'])), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white70, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      Text('${r['title']}', style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      if ('${r['message'] ?? ''}'.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 6), child: Text('${r['message']}', style: const TextStyle(fontFamily: 'tajawal', color: Colors.white))),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _chip(Icons.timer_rounded, '${t('قبل', 'Before')} ${shortDateTime('${r['deadline']}')}'),
                        _chip(Icons.grid_view_rounded, maxC == null ? t('$minC فترات على الأقل', 'At least $minC periods') : t('من $minC إلى $maxC فترات', '$minC – $maxC periods')),
                      ]),
                    ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 10,
                          headingRowHeight: 40,
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 50,
                          columns: [
                            DataColumn(label: Text(t('الفترة', 'Period'), style: orgText(context, w: FontWeight.w800))),
                            for (final d in (r['days'] as List)) DataColumn(label: Text(_days()['$d'] ?? '$d', style: orgText(context, w: FontWeight.w800))),
                          ],
                          rows: [
                            for (final p in asMapList(r['periods']))
                              DataRow(cells: [
                                DataCell(Text('${p['label']}\n${p['start_time']}–${p['end_time']}', style: orgText(context, size: 11.5))),
                                for (final d in (r['days'] as List))
                                  DataCell(Center(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => setState(() {
                                        final k = _k('$d', asInt(p['id']));
                                        _picked.contains(k) ? _picked.remove(k) : _picked.add(k);
                                      }),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 160),
                                        width: 40,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: _picked.contains(_k('$d', asInt(p['id']))) ? c.success : c.inputBg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: c.divider),
                                        ),
                                        child: _picked.contains(_k('$d', asInt(p['id']))) ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                                      ),
                                    ),
                                  )),
                              ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(children: [
                      Text(t('اخترت ${_picked.length} فترة', '${_picked.length} periods selected'),
                          style: orgText(context, w: FontWeight.w700, color: ok ? c.success : c.warning)),
                      const SizedBox(height: 8),
                      PrimaryButton(isLoading: _busy, label: t('إرسال مواعيدي', 'Send my periods'), onPressed: ok ? _submit : null),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _chip(IconData i, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontSize: 12)),
        ]),
      );
}
