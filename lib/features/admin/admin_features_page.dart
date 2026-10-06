// lib/features/admin/admin_features_page.dart — hide / unhide app features per platform.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

class AdminFeaturesPage extends StatelessWidget {
  const AdminFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminFeaturesProvider()..load(),
        child: const _View(),
      );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFeaturesProvider>();
    final c = context.colors;

    Widget body;
    if (p.items.isEmpty && p.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.items.isEmpty) {
      body = ErrorRetry(message: p.error ?? 'admin_could_not_load_data'.tr, onRetry: p.load);
    } else {
      body = RefreshIndicator(
        onRefresh: p.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
          Text(
            'admin_hide_a_feature_on_a_platform_the_app'.tr,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textMedium),
          ),
          const SizedBox(height: 10),
          for (final f in p.items) _FeatureRow(f, platforms: p.platforms),
        ]),
      );
    }

    return BasePage(

      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'app_feature'.tr),floatingActionButton: FloatingActionButton.extended(
          backgroundColor: c.primary,
          onPressed: () async {
            final key = await askText(context,
                title: 'admin_new_feature_key'.tr, hint: 'profile.delete_account');
            if (key != null && key.isNotEmpty) await p.set(key, true);
          },
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text('admin_hide_custom_key'.tr, style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
        ),
        child: body,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.f, {required this.platforms});
  final FeatureItem f;
  final List<String> platforms;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminFeaturesProvider>();
    final hidden = f.hiddenOn;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hidden.isEmpty ? c.divider : c.warning),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.label, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
              Text(f.key, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: c.textLight)),
            ]),
          ),
          Switch(
            // ON = visible everywhere, OFF = hidden on at least one platform
            value: hidden.isEmpty,
            activeTrackColor: c.success,
            onChanged: (visible) => p.set(f.key, !visible),
          ),
        ]),
        Wrap(spacing: 8, children: [
          for (final pl in platforms)
            FilterChip(
              label: Text(pl, style: const TextStyle(fontSize: 12)),
              selected: hidden.contains(pl),
              selectedColor: c.warning.withValues(alpha: 0.3),
              avatar: Icon(hidden.contains(pl) ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 16),
              onSelected: (s) => p.set(f.key, s, platforms: [pl]),
            ),
        ]),
      ]),
    );
  }
}
