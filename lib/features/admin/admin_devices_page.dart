// lib/features/admin/admin_devices_page.dart
// Admin settings for devices allowed per student, device-switch interval,
// monthly video views, and resubscription permission.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/design/app_kit.dart';
import 'admin_common.dart' show t;
import 'admin_page.dart';
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
  // null = the field holds something that is not a valid number in range (Save stays off)
  int? _devices = 1;
  int? _videos = 1;
  int? _days = 30;
  bool _filled = false;
  bool _allowResub = true;
  bool _busy = false;
  // what the server holds (the unsaved-changes guard)
  int _sDevices = 1, _sVideos = 1, _sDays = 30;
  bool _sResub = true;
  DateTime? _loadedAt;

  void _fill(AdminSettingsProvider s) {
    if (_filled || s.values.isEmpty) return;
    _filled = true;
    _loadedAt = DateTime.now();
    _devices = _sDevices = s.maxDevices.clamp(1, 10);
    _videos = _sVideos = s.maxVideos.clamp(1, 1000);
    _days = _sDays = s.switchDays.clamp(1, 365);
    _allowResub = _sResub = s.allowResubscribe;
  }

  bool get _valid => _devices != null && _videos != null && _days != null;
  bool get _dirty =>
      _filled && (_devices != _sDevices || _videos != _sVideos || _days != _sDays || _allowResub != _sResub);

  Future<void> _save(AdminSettingsProvider s) async {
    if (_busy || !_valid) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final ok = await s.save({
        'max_devices': _devices!.clamp(1, 10),
        'device_switch_days': _days!.clamp(1, 365),
        'max_monthly_view': _videos!.clamp(1, 1000),
        'allow_resubscribe': _allowResub,
      });
      if (ok) {
        _sDevices = _devices!;
        _sVideos = _videos!;
        _sDays = _days!;
        _sResub = _allowResub;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload(AdminSettingsProvider s) async {
    await s.load();
    if (!mounted) return;
    setState(() {
      _filled = false;
      _fill(s);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final s = context.watch<AdminSettingsProvider>();
    _fill(s);

    final empty = s.values.isEmpty;
    Widget body;
    if (empty && s.isLoading) {
      body = const AppListSkeleton();
    } else if (empty) {
      body = Center(
        child: AppErrorState(message: s.error ?? 'admin_could_not_load_data'.tr, onRetry: () => _reload(s)),
      );
    } else {
      body = ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          AppSection(
            title: 'admin_student_devices'.tr,
            subtitle: 'admin_a_student_may_request_one_device'.tr,
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _NumberRow(
                  label: 'admin_devices_allowed_per_student'.tr,
                  value: _devices,
                  min: 1,
                  max: 10,
                  unit: (n) => countText(n,
                      ar1: 'جهاز واحد', ar2: 'جهازان', arFew: '{n} أجهزة', arMany: '{n} جهازًا', en1: '1 device', en: '{n} devices'),
                  onChanged: (v) => setState(() => _devices = v),
                ),
                const Divider(),
                _NumberRow(
                  label: 'admin_days_between_device_switches_default'.tr,
                  value: _days,
                  min: 1,
                  max: 365,
                  unit: daysText,
                  onChanged: (v) => setState(() => _days = v),
                ),
                const Divider(),
                _NumberRow(
                  label: 'max_monthly_view'.tr,
                  value: _videos,
                  min: 1,
                  max: 1000,
                  unit: (n) => countText(n,
                      ar1: 'مشاهدة واحدة', ar2: 'مشاهدتان', arFew: '{n} مشاهدات', arMany: '{n} مشاهدة', en1: '1 view', en: '{n} views'),
                  onChanged: (v) => setState(() => _videos = v),
                ),
              ]),
            ),
          ),
          AppSpace.gapLg,
          AppSection(
            title: 'admin_resubscribe_section'.tr,
            child: AppCard(
              child: AppSwitchTile(
                icon: Icons.autorenew_rounded,
                title: 'admin_global_allow_resubscribe'.tr,
                subtitle: 'admin_global_allow_resubscribe_hint'.tr,
                value: _allowResub,
                onChanged: (v) => setState(() => _allowResub = v),
              ),
            ),
          ),
        ],
      );
    }

    return AdminPage(
      title: 'admin_devices'.tr,
      subtitle: 'svc_devices_d'.tr,
      icon: Icons.devices_other_rounded,
      onRefresh: s.isLoading || _busy ? null : () => _reload(s),
      updatedAt: _loadedAt,
      dirty: _dirty,
      primaryAction: empty
          ? null
          : AppButton.primary(
              label: 'admin_save_settings'.tr,
              busy: _busy,
              onPressed: _dirty && _valid ? () => _save(s) : null,
            ),
      body: body,
    );
  }
}

/// A label, a typed number (digits only, range checked) and +/- as helpers. [onChanged] gets null while the text is
/// empty or out of range.
class _NumberRow extends StatefulWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final int min, max;
  final String Function(int n) unit;
  final ValueChanged<int?> onChanged;

  @override
  State<_NumberRow> createState() => _NumberRowState();
}

class _NumberRowState extends State<_NumberRow> {
  late final TextEditingController _ctl = TextEditingController(text: '${widget.value ?? ''}');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_NumberRow old) {
    super.didUpdateWidget(old);
    // a stepper tap or a reload moved the value: show it (a half-typed invalid text is left alone)
    if (widget.value != null && widget.value != int.tryParse(_ctl.text)) {
      _ctl.text = '${widget.value}';
    }
  }

  void _typed(String text) {
    final n = int.tryParse(text);
    widget.onChanged(n != null && n >= widget.min && n <= widget.max ? n : null);
  }

  void _step(int d) {
    final base = widget.value ?? int.tryParse(_ctl.text) ?? widget.min;
    widget.onChanged((base + d).clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final invalid = v == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.md,
        runSpacing: AppSpace.xs,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, minWidth: 160),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label, style: AppType.row(context)),
              Text(
                invalid
                    ? t('أدخل رقمًا من ${widget.min} إلى ${widget.max}', 'Enter a number from ${widget.min} to ${widget.max}')
                    : '${t('الأدنى', 'Min')} ${widget.min} • ${t('الأقصى', 'Max')} ${widget.max} — ${widget.unit(v)}',
                style: AppType.meta(context).copyWith(color: invalid ? context.colors.danger : null),
              ),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            AppIconButton(
              icon: Icons.remove_rounded,
              tooltip: t('إنقاص', 'Decrease'),
              onPressed: (v ?? widget.min) > widget.min ? () => _step(-1) : null,
            ),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _ctl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                decoration: InputDecoration(
                  isDense: true,
                  errorText: invalid ? '' : null,
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
                onChanged: _typed,
              ),
            ),
            AppIconButton(
              icon: Icons.add_rounded,
              tooltip: t('زيادة', 'Increase'),
              onPressed: (v ?? widget.min - 1) < widget.max ? () => _step(1) : null,
            ),
          ]),
        ],
      ),
    );
  }
}
