// lib/features/org/org_sections_page.dart
//
// "My sections" — for teaching assistants: the courses they assist and the SECTION sessions they run
// (create / edit / delete; the backend allows assistants to touch section sessions only).
library;

import 'org_page_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart' show OrgApi, orgBase;
import 'org_ui.dart';
import '../admin/admin_list.dart' show IconBadge;
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/design/app_tokens.dart';

class OrgSectionsPage extends StatefulWidget {
  const OrgSectionsPage({super.key});

  @override
  State<OrgSectionsPage> createState() => _OrgSectionsPageState();
}

class _OrgSectionsPageState extends State<OrgSectionsPage> {
  List<Map<String, dynamic>>? _courses;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap('$orgBase/public/me/assisting');
    if (mounted) setState(() => _courses = asMapList(r?['items']));
  }

  Future<void> _edit(Map<String, dynamic> course, [Map<String, dynamic>? s]) async {
    final name = TextEditingController(text: '${s?['name'] ?? ''}');
    final desc = TextEditingController(text: '${s?['description'] ?? ''}');
    final dur = TextEditingController(text: '${s?['duration_minutes'] ?? 90}');
    String type = '${s?['type'] ?? 'live'}';
    DateTime? when = DateTime.tryParse('${s?['scheduled_at'] ?? ''}')?.toLocal();
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(s == null ? t('سكشن جديد', 'New section') : t('تعديل السكشن', 'Edit section')),
            Field(controller: name, label: t('العنوان — مثلاً: سكشن 3: الدوال', 'Title — e.g. Section 3: functions')),
            Field(controller: desc, label: t('الوصف (اختياري)', 'Description (optional)'), maxLines: 3),
            ChoiceRow<String>(label: t('النوع', 'Type'), options: {'live': t('مباشر', 'Live'), 'pre-recorded': t('مسجّل', 'Recorded')},
                value: type, onChanged: (v) => set(() => type = v)),
            if (type == 'live')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text(when == null ? t('الموعد', 'When') : shortDateTime(when!.toIso8601String())),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime(2100), initialDate: when ?? DateTime.now());
                  if (d == null || !ctx.mounted) return;
                  final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when ?? DateTime.now()));
                  set(() => when = DateTime(d.year, d.month, d.day, tm?.hour ?? 10, tm?.minute ?? 0));
                },
              ),
            OrgNumberField(controller: dur, label: t('المدة بالدقائق', 'Duration (minutes)')),
            PrimaryButton(isLoading: false, label: t('حفظ', 'Save'), onPressed: () async {
              if (name.text.trim().isEmpty) return toast(t('اكتب عنواناً', 'Add a title'), error: true);
              final b = {'course_id': course['id'], 'name': name.text.trim(), 'description': desc.text.trim(), 'type': type,
                'track': 'section', 'duration_minutes': int.tryParse(dur.text) ?? 90,
                if (when != null) 'scheduled_at': when!.toUtc().toIso8601String()};
              final r = s == null
                  ? await OrgApi.i.post('/api/v1/sessions', b, t('أُضيف السكشن', 'Section added'))
                  : await OrgApi.i.put('/api/v1/sessions/${s['id']}', b..remove('course_id'), t('تم', 'Saved'));
              if (r != null && ctx.mounted) Navigator.pop(ctx);
            }),
          ]),
        )));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final courses = _courses;
    if (courses == null) return const AppListSkeleton();
    if (courses.isEmpty) {
      return OrgEmpty(icon: Icons.science_rounded, title: t('لا مقررات تعاون فيها بعد', 'No courses you assist yet'),
          message: t('يظهر هنا كل مقرر عيّنك فيه مكتب الجداول كمعيد.', 'Every course the timetable office assigns you to appears here.'));
    }
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
        for (final co in courses)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpace.md),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.block), border: Border.all(color: c.divider)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconBadge(Icons.science_rounded, c.purple, size: 42),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(t('${co['name_ar'] ?? co['name_en']}', '${co['name_en'] ?? co['name_ar']}'), style: AppType.section(context))),
                FilledButton.tonalIcon(onPressed: () => _edit(co), icon: const Icon(Icons.add_rounded), label: Text(t('سكشن', 'Section'))),
              ]),
              const SizedBox(height: AppSpace.xs),
              if (asMapList(co['sections']).isEmpty)
                Text(t('لا سكاشن بعد', 'No sections yet'), style: AppType.row(context).copyWith(color: c.textMedium))
              else
                for (final (i, s) in asMapList(co['sections']).indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: c.purple.withValues(alpha: 0.12),
                        child: Text('${i + 1}', style: AppType.bodyStrong(context).copyWith(color: c.purple))),
                    title: Text('${s['name']}', style: AppType.bodyStrong(context)),
                    subtitle: Text([
                      s['type'] == 'live' ? t('مباشر', 'Live') : t('مسجّل', 'Recorded'),
                      if (s['scheduled_at'] != null) shortDateTime('${s['scheduled_at']}'),
                      '${s['duration_minutes'] ?? 0} ${t('د', 'min')}',
                    ].join(' · ')),
                    onTap: () => _edit(co, s),
                    trailing: IconButton(tooltip: t('حذف', 'Delete'), icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () async {
                      if (await confirm(context, message: t('حذف السكشن؟', 'Delete this section?'), danger: true)) {
                        await OrgApi.i.del('/api/v1/sessions/${s['id']}', t('حُذف', 'Deleted'));
                        _load();
                      }
                    }),
                  ),
            ]),
          ),
      ]),
    );
  }
}
