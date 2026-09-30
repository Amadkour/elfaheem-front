/// features/teacher/device_requests/teacher_device_requests_screen.dart
/// Open from the teacher dashboard:
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDeviceRequestsScreen()));
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import 'teacher_device_requests_provider.dart';

class TeacherDeviceRequestsScreen extends StatelessWidget {
  const TeacherDeviceRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => TeacherDeviceRequestsProvider()..load(),
        child: const _View(),
      );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherDeviceRequestsProvider>();
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: const ScreenAppBar(title: 'طلبات تغيير الجهاز'),
      body: RefreshIndicator(
        onRefresh: p.load,
        child: p.isLoading && p.items.isEmpty
            ? const Center(child: AppLoadingIndicator())
            : p.items.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Column(children: [
                      Icon(Icons.phonelink_rounded, size: 48, color: c.textLight),
                      const SizedBox(height: 12),
                      Text('لا توجد طلبات بانتظار المراجعة', style: c.body),
                    ])),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: p.items.length,
                    itemBuilder: (_, i) => _Card(item: p.items[i]),
                  ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final DeviceSwitchItem item;
  const _Card({required this.item});

  void _toast(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _approve(BuildContext context) async {
    final p = context.read<TeacherDeviceRequestsProvider>();
    final ok = await p.approve(item.id);
    if (!context.mounted) return;
    _toast(context, ok ? 'تمت الموافقة، تم نقل الحساب للجهاز الجديد' : (p.errorMessage ?? 'تعذرت الموافقة'));
  }

  Future<void> _reject(BuildContext context) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب الرفض'),
        content: TextField(controller: ctrl, maxLines: 2, decoration: const InputDecoration(hintText: 'اختياري')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('رفض')),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    await context.read<TeacherDeviceRequestsProvider>().reject(item.id, reason);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = context.watch<TeacherDeviceRequestsProvider>().isProcessing(item.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.studentName, style: c.h3.copyWith(fontSize: 15)),
        if (item.studentPhone?.isNotEmpty ?? false) Text(item.studentPhone!, style: c.caption),
        if (item.courseName != null) Text('الكورس: ${item.courseName}', style: c.caption),
        const SizedBox(height: 8),
        Text('الجهاز الجديد: ${item.newDeviceName ?? 'غير معروف'}', style: c.body.copyWith(fontSize: 13)),
        const SizedBox(height: 4),
        Text('ملاحظة: يمكن الموافقة على طلب واحد فقط لكل طالب في الشهر.', style: c.caption),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : () => _reject(context),
              style: OutlinedButton.styleFrom(foregroundColor: c.danger,side: BorderSide(color:  c.danger)),
              child: const Text('رفض'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : () => _approve(context),
              style: FilledButton.styleFrom(backgroundColor: c.success),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: AppLoadingIndicator())
                  : const Text('موافقة'),
            ),
          ),
        ]),
      ]),
    );
  }
}
