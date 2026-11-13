// lib/features/admin/admin_ai_controls.dart
//
// The super admin's AI controls (D-780): one switch per AI feature for the whole platform, at the top of the Features
// page. Each control is an existing kill-switch key (exam.auto_create, exam.auto_grade, exam.auto_correct,
// rag.app_assistant, rag.assistant, rag.learning, image.background); OFF hides it on every platform AND the services
// refuse it (403 feature_disabled {feature}, worded by featureDisabledText). Under each switch: one line on what OFF does.
//
// GET /api/v1/admin/ai-controls · PUT /api/v1/admin/ai-controls/{key} {on}
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../org/org_v3.dart';
import 'admin_common.dart' show asMapList, t;

const _aiControls = '/api/v1/admin/ai-controls';

/// One AI control as the server lists it.
class AiControl {
  const AiControl({
    required this.key,
    required this.title,
    required this.offText,
    required this.on,
    this.partial = false,
    this.onDevice = false,
  });

  final String key;
  final String title;
  final String offText;
  final bool on;
  final bool partial;
  final bool onDevice;

  static AiControl from(Map<String, dynamic> m) => AiControl(
        key: '${m['key']}',
        title: t('${m['title_ar'] ?? m['key']}', '${m['title_en'] ?? m['key']}'),
        offText: t('${m['off_ar'] ?? ''}', '${m['off_en'] ?? ''}'),
        on: m['on'] != false,
        partial: m['partial'] == true,
        onDevice: m['enforced'] == 'app',
      );
}

IconData aiControlIcon(String key) => switch (key) {
      'exam.auto_create' => Icons.auto_awesome_rounded,
      'exam.auto_grade' => Icons.rate_review_rounded,
      'exam.auto_correct' => Icons.document_scanner_rounded,
      'rag.app_assistant' => Icons.support_agent_rounded,
      'rag.assistant' => Icons.forum_rounded,
      'rag.learning' => Icons.psychology_rounded,
      'image.background' => Icons.wallpaper_rounded,
      _ => Icons.smart_toy_rounded,
    };

/// The section, plain values only (the layout harness draws this one): [busy] keys show a disabled switch.
class AiControlsCard extends StatelessWidget {
  const AiControlsCard({super.key, required this.items, required this.onToggle, this.busy = const {}});

  final List<AiControl> items;
  final Set<String> busy;
  final void Function(AiControl control, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final offCount = items.where((i) => !i.on).length;
    return AppSectionCard(
      title: t('التحكم في الذكاء الاصطناعي', 'AI controls'),
      subtitle: t('مفتاح لكل ميزة على المنصة كلها؛ الخادم يطبّق الإيقاف أيضاً ولا يُحذف شيء.',
          'One switch per feature for the whole platform; the server enforces an OFF too and nothing is deleted.'),
      actions: [
        if (offCount > 0)
          AppStatusBadge(
              label: t('$offCount متوقفة', '$offCount off'), tone: AppTone.warning, icon: Icons.power_settings_new_rounded),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in items)
          AppSwitchTile(
            icon: aiControlIcon(c.key),
            title: c.title,
            subtitle: c.offText.isEmpty ? null : t('عند الإيقاف: ${c.offText}', 'When off: ${c.offText}'),
            subtitleWidget: c.partial || c.onDevice
                ? Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                    if (c.partial)
                      AppStatusBadge(
                          label: t('مخفية على بعض المنصات فقط', 'Hidden on some platforms only'),
                          tone: AppTone.warning,
                          icon: Icons.devices_rounded,
                          dense: true),
                    if (c.onDevice)
                      AppStatusBadge(
                          label: t('تعمل على الجهاز', 'Runs on the device'), icon: Icons.phone_android_rounded, dense: true),
                  ])
                : null,
            value: c.on,
            onChanged: busy.contains(c.key) ? null : (v) => onToggle(c, v),
          ),
      ]),
    );
  }
}

/// Loads and saves the controls; [onChanged] runs after a save (the Features page reloads its list: same keys).
class AiControlsSection extends StatefulWidget {
  const AiControlsSection({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<AiControlsSection> createState() => _AiControlsSectionState();
}

class _AiControlsSectionState extends State<AiControlsSection> {
  List<AiControl>? _items;
  bool _failed = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(_aiControls), quiet: true);
    if (!mounted) return;
    setState(() {
      _failed = !r.ok && _items == null;
      if (r.ok) _items = [for (final m in asMapList(r.map['items'])) AiControl.from(m)];
    });
  }

  Future<void> _toggle(AiControl c, bool on) async {
    if (!on) {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('إيقاف', 'Switch off'),
          message: t('إيقاف «${c.title}» على المنصة كلها؟\n${c.offText}', 'Switch off "${c.title}" for the whole platform?\n${c.offText}'));
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(c.key));
    final r = await orgCall(() => ApiClient().put('$_aiControls/${Uri.encodeComponent(c.key)}', body: {'on': on}),
        ok: on ? t('تم تشغيل «${c.title}»', '"${c.title}" is on') : t('تم إيقاف «${c.title}»', '"${c.title}" is off'));
    if (!mounted) return;
    setState(() {
      _busy.remove(c.key);
      if (r.ok) _items = [for (final m in asMapList(r.map['items'])) AiControl.from(m)];
    });
    if (r.ok) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      if (!_failed) return const AppListSkeleton(items: 3);
      return AppCard(
        child: AppEmpty(
          icon: Icons.smart_toy_rounded,
          title: t('تعذّر تحميل التحكم في الذكاء الاصطناعي', 'Could not load the AI controls'),
          actionLabel: t('إعادة المحاولة', 'Try again'),
          onAction: () {
            setState(() => _failed = false);
            _load();
          },
        ),
      );
    }
    return AiControlsCard(items: items, busy: _busy, onToggle: _toggle);
  }
}
