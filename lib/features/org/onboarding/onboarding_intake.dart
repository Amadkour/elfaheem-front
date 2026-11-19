// lib/features/org/onboarding/onboarding_intake.dart — the intake link panel of the types editor (Phase C, D-1200).
//
// One public link per type: people open it, sign in and start their own application. The panel holds the enable
// switch, "valid until" (AppTime date), a capacity and how many used it. The CODE and link are returned once, when
// the settings are saved or rotated, and are shown here with Copy and a QR code (the app's share sheet) until the
// page is left. Gate: kill switch `org.onboarding.intake` + `onboarding:update` (the types editor itself).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart' show showAppShareSheet;

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_models.dart';

class OnbIntakePanel extends StatefulWidget {
  const OnbIntakePanel({super.key, required this.orgId, required this.type, this.api, this.onShare});
  final int orgId;
  final OnbType type;
  final OnboardingApi? api;

  /// Opens the share sheet (QR); tests pass their own.
  final void Function(BuildContext context, String url, String title)? onShare;

  @override
  State<OnbIntakePanel> createState() => _OnbIntakePanelState();
}

class _OnbIntakePanelState extends State<OnbIntakePanel> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  late bool _enabled = widget.type.intake.enabled;
  late DateTime? _until = widget.type.intake.validUntil;
  late final _cap = TextEditingController(text: widget.type.intake.capacity?.toString() ?? '');
  late final int _used = widget.type.intake.used;
  OnbIntakeLink? _link;
  bool _busy = false;

  @override
  void dispose() {
    _cap.dispose();
    super.dispose();
  }

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _until?.toLocal() ?? now.add(const Duration(days: 30)), firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 5));
    if (d != null && mounted) setState(() => _until = DateTime(d.year, d.month, d.day, 23, 59).toUtc());
  }

  Future<void> _save({bool rotate = false}) async {
    final cap = int.tryParse(_cap.text.trim());
    setState(() => _busy = true);
    final r = await _api.saveIntake(widget.orgId, widget.type.key, enabled: _enabled, validUntil: _until, capacity: cap, rotate: rotate);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final link = OnbIntakeLink.fromJson(r.map);
    setState(() {
      if (link.hasCode) _link = link;
      if (!_enabled) _link = null;
    });
    showAppNotice(t('حُفظ رابط التقديم', 'Intake link saved'));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppNotice(t('تم النسخ', 'Copied'));
  }

  void _share(String url) {
    final share = widget.onShare;
    final title = widget.type.label.isEmpty ? widget.type.key : widget.type.label;
    if (share != null) {
      share(context, url, title);
    } else {
      showAppShareSheet(context, url: url, title: title, subtitle: t('رابط التقديم', 'Intake link'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnbIntakeView(
      enabled: _enabled,
      validUntil: _until,
      capacity: _cap,
      used: _used,
      link: _link,
      busy: _busy,
      onEnabled: (v) => setState(() => _enabled = v),
      onPickUntil: _pickUntil,
      onClearUntil: () => setState(() => _until = null),
      onSave: () => _save(),
      onRotate: () => _save(rotate: true),
      onCopy: _copy,
      onShare: _share,
    );
  }
}

/// The panel over plain values.
class OnbIntakeView extends StatelessWidget {
  const OnbIntakeView({
    super.key,
    required this.enabled,
    required this.capacity,
    this.validUntil,
    this.used = 0,
    this.link,
    this.busy = false,
    this.onEnabled,
    this.onPickUntil,
    this.onClearUntil,
    this.onSave,
    this.onRotate,
    this.onCopy,
    this.onShare,
  });

  final bool enabled, busy;
  final DateTime? validUntil;
  final TextEditingController capacity;
  final int used;
  final OnbIntakeLink? link;
  final void Function(bool)? onEnabled;
  final VoidCallback? onPickUntil, onClearUntil, onSave, onRotate;
  final void Function(String)? onCopy, onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = link;
    return AppCard(
      key: const ValueKey('onb.intake'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.link_rounded, color: c.primary),
          AppSpace.gapSm,
          Expanded(child: Text(t('رابط تقديم عام', 'Public intake link'), style: AppType.section(context))),
        ]),
        AppSpace.gapXs,
        Text(t('يفتحه الناس ويسجّلون الدخول ثم يبدؤون طلبهم بأنفسهم.', 'People open it, sign in and start their own application.'), style: AppType.meta(context)),
        AppSwitchTile(key: const ValueKey('onb.intake.enabled'), title: t('تفعيل الرابط', 'Link is on'), value: enabled, onChanged: onEnabled),
        if (enabled) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppButton.secondary(
              key: const ValueKey('onb.intake.until'),
              label: validUntil == null ? t('صالح حتى: بلا حد', 'Valid until: no limit') : t('صالح حتى ${AppTime.date(validUntil!)}', 'Valid until ${AppTime.date(validUntil!)}'),
              icon: Icons.event_outlined,
              size: AppButtonSize.sm,
              onPressed: onPickUntil,
            ),
            if (validUntil != null) AppButton.ghost(key: const ValueKey('onb.intake.until_clear'), label: t('بلا حد', 'No limit'), size: AppButtonSize.sm, onPressed: onClearUntil),
          ]),
          AppSpace.gapXs,
          AppField(key: const ValueKey('onb.intake.capacity'), controller: capacity, label: t('السعة (اتركه فارغاً لبلا حد)', 'Capacity (empty for no limit)'), keyboard: TextInputType.number, ltr: true),
          Text(t('استُخدم $used', 'Used $used'), key: const ValueKey('onb.intake.used'), style: AppType.meta(context)),
        ],
        if (l != null && l.hasCode) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.info_outline_rounded, color: c.primary, text: t('انسخ الرمز والرابط الآن: لا يظهران مرة أخرى.', 'Copy the code and link now: they are not shown again.')),
          AppSpace.gapXs,
          Row(children: [
            Expanded(child: SelectableText(l.code, key: const ValueKey('onb.intake.code'), textDirection: TextDirection.ltr, style: AppType.bodyStrong(context))),
            AppIconButton(icon: Icons.copy_rounded, tooltip: t('نسخ الرمز', 'Copy the code'), onPressed: () => onCopy?.call(l.code)),
          ]),
          if (l.link.isNotEmpty)
            Row(children: [
              Expanded(child: Text(l.link, key: const ValueKey('onb.intake.link'), maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context))),
              AppIconButton(icon: Icons.copy_rounded, tooltip: t('نسخ الرابط', 'Copy the link'), onPressed: () => onCopy?.call(l.link)),
              AppIconButton(icon: Icons.qr_code_2_rounded, tooltip: t('رمز QR', 'QR code'), onPressed: () => onShare?.call(l.link)),
            ]),
        ],
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.primary(key: const ValueKey('onb.intake.save'), label: t('حفظ الرابط', 'Save the link'), busy: busy, onPressed: busy ? null : onSave),
          if (enabled) AppButton.secondary(key: const ValueKey('onb.intake.rotate'), label: t('رمز جديد', 'New code'), icon: Icons.autorenew_rounded, onPressed: busy ? null : onRotate),
        ]),
      ]),
    );
  }
}
