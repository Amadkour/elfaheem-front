// lib/features/admin/admin_devices_page.dart
// Admin settings for devices allowed per student, device-switch interval,
// monthly video views, and resubscription permission.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_premium_widgets.dart';
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
  int _devices = 1;
  int _videos = 1;
  int _days = 30;
  bool _filled = false;
  bool _allowResub = true;
  bool _busy = false;

  void _fill(AdminSettingsProvider s) {
    if (_filled || s.values.isEmpty) return;
    _filled = true;
    _devices = s.maxDevices.clamp(1, 10);
    _videos = s.maxVideos.clamp(1, 1000);
    _days = s.switchDays.clamp(1, 365);
    _allowResub = s.allowResubscribe;
  }

  Future<void> _save(AdminSettingsProvider s) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await s.save({
        'max_devices': _devices.clamp(1, 10),
        'device_switch_days': _days.clamp(1, 365),
        'max_monthly_view': _videos.clamp(1, 1000),
        'allow_resubscribe': _allowResub,
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final s = context.watch<AdminSettingsProvider>();
    final c = context.colors;
    _fill(s);

    Widget body;
    if (s.values.isEmpty && s.isLoading) {
      body = const Center(child: AppLoadingIndicator());
    } else if (s.values.isEmpty) {
      body = ErrorRetry(
        message: s.error ?? 'admin_could_not_load_data'.tr,
        onRetry: s.load,
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PremiumHero(
            icon: Icons.devices_other_rounded,
            colors: AdminPalette.violet,
            title: 'admin_devices'.tr,
            subtitle: 'svc_devices_d'.tr,
            footer: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                HeroPill(
                  trp('dev_pill_devices', {'n': _devices}),
                  icon: Icons.smartphone_rounded,
                ),
                HeroPill(
                  trp('dev_pill_days', {'n': _days}),
                  icon: Icons.event_repeat_rounded,
                ),
                HeroPill(
                  trp('dev_pill_videos', {'n': _videos}),
                  icon: Icons.play_circle_rounded,
                ),
              ],
            ),
          ),
          Section(
            icon: Icons.phonelink_lock_rounded,
            colors: AdminPalette.blue,
            title: 'admin_student_devices'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PremiumCounter(
                  label: 'admin_devices_allowed_per_student'.tr,
                  value: _devices,
                  minValue: 1,
                  maxValue: 10,
                  enabled: true,
                  onChanged: (v) => setState(() => _devices = v),
                ),
                _PremiumCounter(
                  label: 'admin_days_between_device_switches_default'.tr,
                  value: _days,
                  minValue: 1,
                  maxValue: 365,
                  enabled: true,
                  onChanged: (v) => setState(() => _days = v),
                  suffix: 'days',
                ),
                _PremiumCounter(
                  label: 'max_monthly_view'.tr,
                  value: _videos,
                  minValue: 1,
                  maxValue: 1000,
                  enabled: true,
                  onChanged: (v) => setState(() => _videos = v),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'admin_a_student_may_request_one_device'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      color: c.textLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Section(
            icon: Icons.autorenew_rounded,
            colors: AdminPalette.green,
            title: 'admin_resubscribe_section'.tr,
            child: PremiumSwitchRow(
              title: 'admin_global_allow_resubscribe'.tr,
              subtitle: 'admin_global_allow_resubscribe_hint'.tr,
              value: _allowResub,
              onChanged: (v) => setState(() => _allowResub = v),
            ),
          ),
        ],
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: 'admin_devices'.tr),
      bottomNavigationBar: s.values.isEmpty
          ? null
          : PremiumSaveBar(
              label: 'admin_save_settings'.tr,
              loading: _busy,
              onPressed: () => _save(s),
            ),
      child: body,
    );
  }
}

class _PremiumCounter extends StatelessWidget {
  final String label;
  final int value;
  final int minValue;
  final int maxValue;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final String? suffix;

  const _PremiumCounter({
    required this.label,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.enabled,
    required this.onChanged,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canDecrease = enabled && value > minValue;
    final canIncrease = enabled && value < maxValue;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? colors.primary.withValues(alpha: 0.20) : context.colors.textLight.withValues(alpha: 0.15),
          ),
          boxShadow: colors.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontWeight: FontWeight.w700,
                      color: enabled ? colors.textDark: colors.textLight,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Min $minValue • Max $maxValue',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 11,
                      color: colors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CounterButton(
              icon: Icons.remove_rounded,
              enabled: canDecrease,
              onTap: () => onChanged((value - 1).clamp(minValue, maxValue)),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 54),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: enabled ? colors.primary : colors.textLight,
                    ),
                  ),
                  if (suffix != null)
                    Text(
                      suffix!,
                      style: TextStyle(fontSize: 10, color: colors.textLight),
                    ),
                ],
              ),
            ),
            _CounterButton(
              icon: Icons.add_rounded,
              enabled: canIncrease,
              onTap: () => onChanged((value + 1).clamp(minValue, maxValue)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _CounterButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: enabled ? colors.primary.withValues(alpha: 0.10) : context.colors.textLight.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: enabled ? colors.primary : context.colors.textLight,
            size: 21,
          ),
        ),
      ),
    );
  }
}
