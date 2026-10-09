// lib/features/admin/admin_devices_page.dart  (NEW FILE)
//  • devices allowed per student
//  • days between device switches (default 30)
//  • max monthly video views
// Payments live in admin_payments_page.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_providers.dart';

class AdminDevicesPage extends StatelessWidget {
  const AdminDevicesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminSettingsProvider()..load(),
    child: const _View(),
  );
}

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _devices = TextEditingController();
  final _videos = TextEditingController();
  final _days = TextEditingController();
  bool _filled = false;
  bool _allowResub = true;
  bool _busy = false;

  @override
  void dispose() {
    _devices.dispose();
    _videos.dispose();
    _days.dispose();
    super.dispose();
  }

  void _fill(AdminSettingsProvider s) {
    if (_filled || s.values.isEmpty) return;
    _filled = true;
    _devices.text = '${s.maxDevices}';
    _videos.text = '${s.maxVideos}';
    _days.text = '${s.switchDays}';
    _allowResub = s.allowResubscribe;
  }

  Future<void> _save(AdminSettingsProvider s) async {
    final dev = int.tryParse(_devices.text.trim());
    final videos = int.tryParse(_videos.text.trim());
    final days = int.tryParse(_days.text.trim());
    if (dev == null || dev < 1 || dev > 10) {
      toast('admin_devices_must_be_1_10'.tr, error: true);
      return;
    }
    if (videos == null || videos < 1 || videos > 1000) {
      toast('admin_videos_must_be_1_1000'.tr, error: true);
      return;
    }
    if (days == null || days < 1 || days > 365) {
      toast('admin_period_must_be_1_365_days'.tr, error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await s.save({
      'max_devices': dev,
      'device_switch_days': days,
      'max_monthly_view': videos,
      'allow_resubscribe': _allowResub,
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AdminSettingsProvider>();
    final c = context.colors;
    _fill(s);

    Widget body;
    if (s.values.isEmpty && s.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.values.isEmpty) {
      body = ErrorRetry(message: s.error ?? 'admin_could_not_load_data'.tr, onRetry: s.load);
    } else {
      body = ListView(padding: const EdgeInsets.all(14), children: [
        Section(
          title: 'admin_student_devices'.tr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Field(
                controller: _devices,
                label: 'admin_devices_allowed_per_student'.tr,
                keyboard: TextInputType.number),
            Field(
                controller: _days,
                label: 'admin_days_between_device_switches_default'.tr,
                keyboard: TextInputType.number),
            Field(
                controller: _videos,
                label: 'max_monthly_view'.tr,
                keyboard: TextInputType.number),
            Text(
              'admin_a_student_may_request_one_device'.tr,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight),
            ),
          ]),
        ),
        Section(
          title: 'admin_resubscribe_section'.tr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('admin_global_allow_resubscribe'.tr,
                  style: const TextStyle(fontFamily: 'tajawal')),
              subtitle: Text('admin_global_allow_resubscribe_hint'.tr,
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 11.5)),
              value: _allowResub,
              activeTrackColor: c.primary,
              onChanged: (v) => setState(() => _allowResub = v),
            ),
          ]),
        ),
        PrimaryButton(label: 'admin_save_settings'.tr, isLoading: _busy, onPressed: () => _save(s)),
      ]);
    }

    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: 'admin_devices'.tr),
      child: body,
    );
  }
}