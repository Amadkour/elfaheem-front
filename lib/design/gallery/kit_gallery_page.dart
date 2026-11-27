// lib/design/gallery/kit_gallery_page.dart
//
// The redesign kit's component gallery (KIT_SPEC §7.1): every colour role, type role, component and motion of the
// kit under switchable area, role accent, dark mode, direction, Reduce motion, text scale and width. A developer
// tool: route `/kit_gallery` (super admin / developer; every signed-in role in debug builds), kill switch
// `admin.kit_gallery`, no help id.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../app_area.dart';
import '../app_kit.dart';
import 'kit_gallery_sections.dart';

/// The kill-switch id of the gallery page.
const String kKitGalleryKey = 'admin.kit_gallery';

class KitGalleryPage extends StatefulWidget {
  const KitGalleryPage({super.key, this.initialSection = 0});

  /// The section open first (tests and goldens).
  final int initialSection;

  @override
  State<KitGalleryPage> createState() => _KitGalleryPageState();
}

class _KitGalleryPageState extends State<KitGalleryPage> {
  AppArea? _area = AppArea.home;
  AppRoleAccent? _role;
  bool _dark = false;
  late String _lang = AppConfig.lang;
  late final String _langBefore = AppConfig.lang;
  bool _reduce = false;
  bool _scale = false;
  bool _narrow = false;
  late int _section = widget.initialSection;

  @override
  void dispose() {
    AppConfig.lang = _langBefore;
    super.dispose();
  }

  Widget _controls(BuildContext context) {
    final c = context.colors;
    Widget group(String label, List<Widget> chips) => Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.overline(context)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: chips),
          ]),
        );
    return AppCard(
      variant: AppCardVariant.flat,
      title: 'kit_gallery_controls'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        group('kit_gallery_area'.tr, [
          AppChip(
              label: 'kit_gallery_none'.tr,
              selected: _area == null,
              onTap: () => setState(() => _area = null)),
          for (final a in AppArea.values)
            AppChip(
                label: a.name,
                selected: _area == a,
                onTap: () => setState(() {
                      _area = a;
                      _role = null;
                    })),
        ]),
        group('kit_gallery_role'.tr, [
          AppChip(
              label: 'kit_gallery_none'.tr,
              selected: _role == null,
              onTap: () => setState(() => _role = null)),
          for (final r in AppRoleAccent.values)
            AppChip(
                label: r.key,
                selected: _role == r,
                onTap: () => setState(() {
                      _role = r;
                      _area = null;
                    })),
        ]),
        group('kit_gallery_view'.tr, [
          AppChip(label: 'kit_gallery_dark'.tr, selected: _dark, onTap: () => setState(() => _dark = !_dark)),
          AppChip(
              label: _lang == 'ar' ? 'العربية' : 'English',
              icon: Icons.translate_rounded,
              onTap: () => setState(() {
                    _lang = _lang == 'ar' ? 'en' : 'ar';
                    AppConfig.lang = _lang;
                  })),
          AppChip(
              label: 'kit_gallery_reduce'.tr, selected: _reduce, onTap: () => setState(() => _reduce = !_reduce)),
          AppChip(label: '1.3×', selected: _scale, onTap: () => setState(() => _scale = !_scale)),
          AppChip(label: '390', selected: _narrow, onTap: () => setState(() => _narrow = !_narrow)),
        ]),
        Text('kit_gallery_rule'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors;
    final sections = kitGallerySections();
    Widget body = Builder(builder: (context) {
      return ListView(
        padding: EdgeInsets.all(AppSpace.gutter(MediaQuery.sizeOf(context).width)),
        children: [
          _controls(context),
          const SizedBox(height: AppSpace.md),
          AppTabs(
            items: [for (final s in sections) AppTabItem(s.title)],
            index: _section,
            onChanged: (i) => setState(() => _section = i),
          ),
          const SizedBox(height: AppSpace.md),
          KeyedSubtree(key: ValueKey('kit-section-$_section-$_lang'), child: sections[_section].build(context)),
        ],
      );
    });
    if (_area != null) body = AppAreaScope(area: _area!, child: body);
    if (_role != null) body = AppAreaScope.role(role: _role!, child: body);
    body = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: _reduce || MediaQuery.of(context).disableAnimations,
        textScaler: _scale ? const TextScaler.linear(1.3) : MediaQuery.textScalerOf(context),
      ),
      child: Directionality(textDirection: _lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: body),
    );
    if (_narrow) {
      body = Center(
        child: SizedBox(
          width: kKitGalleryNarrow,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(kKitGalleryNarrow, MediaQuery.sizeOf(context).height)),
            child: body,
          ),
        ),
      );
    }
    if (_dark != base.isDark) {
      final preview = ThemeConfigProvider.preview(base, dark: _dark);
      body = ThemeConfigScope(
        provider: preview,
        child: ColoredBox(color: preview.background, child: body),
      );
    }
    return BasePage(
      key: const ValueKey(kKitGalleryKey),
      appBar: AppHeader(title: 'kit_gallery_title'.tr),
      child: body,
    );
  }
}

/// The phone preview width.
const double kKitGalleryNarrow = 390;
