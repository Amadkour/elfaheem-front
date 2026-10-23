// lib/features/admin/admin_features_page.dart — hide / unhide app features per platform.
// Features are grouped into classes (tabs); 20 are loaded at a time and the next page is appended on scroll.
// Super-admin: sees everything, can let admins manage a feature and can add new features.
// Admin: the backend only sends the features that were granted to admins.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/paged_progress.dart';
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

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Near the bottom → append the next page automatically.
  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 320) {
      context.read<AdminFeaturesProvider>().loadMore();
    }
  }

  /// Too few rows to scroll yet → keep loading until the list fills the screen.
  void _fillViewport(AdminFeaturesProvider p) {
    if (p.loadMoreFailed || !p.hasMore || p.loadingMore || p.isLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) p.loadMore();
    });
  }

  Future<void> _selectTab(AdminFeaturesProvider p, int i) async {
    await p.selectTab(i);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFeaturesProvider>();
    final c = context.colors;
    final isAr = AppConfig.lang == 'ar';

    final items = p.currentItems;
    Widget body;
    if (p.tabs.isEmpty && (p.isLoading || !p.loaded)) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.tabs.isEmpty) {
      body = ErrorRetry(
        message: p.error ?? 'admin_could_not_load_data'.tr,
        onRetry: p.refresh,
      );
    } else {
      _fillViewport(p);
      body = Column(
        children: [
          // pinned: class tabs + "Showing 40 of 134" progress card
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: _TabsBar(
              p: p,
              onSelect: (i) {
                if (i != p.selectedTabIndex) _selectTab(p, i);
              },
            ),
          ),
          if ((items.isNotEmpty || p.total > 0) && p.total > 20)
            PagedCountCard(
              loaded: items.length,
              total: p.total,
              loadingMore: p.loadingMore,
              done: !p.hasMore,
              icon: Icons.toggle_on_rounded,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: p.refresh,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
                children: [
                  if (p.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  Text(
                    'admin_hide_a_feature_on_a_platform_the_app'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12.5,
                      color: c.textMedium,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty && !p.isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          isAr ? 'لا توجد ميزات' : 'No features',
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            color: c.textMedium,
                          ),
                        ),
                      ),
                    ),
                  for (final f in items) _FeatureRow(f, platforms: p.platforms),
                  if (items.isNotEmpty)
                    PagedListFooter(
                      loadingMore: p.loadingMore,
                      hasMore: p.hasMore,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'app_feature'.tr),
      // adding features is a super-admin-only tool
      floatingActionButton: p.canAddCustom
          ? FloatingActionButton.extended(
              heroTag: "features_float",
              key: ValueKey("features_float"),
              backgroundColor: c.primary,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _AddFeatureDialog(provider: p),
              ),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(
                isAr ? 'ميزة جديدة' : 'New feature',
                style: const TextStyle(
                  fontFamily: 'tajawal',
                  color: Colors.white,
                ),
              ),
            )
          : null,
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Tabs bar: scrollable on web (arrows + scrollbar + mouse drag)
// ═════════════════════════════════════════════════════════════════════════════

class _TabsBar extends StatefulWidget {
  const _TabsBar({required this.p, required this.onSelect});

  final AdminFeaturesProvider p;
  final void Function(int index) onSelect;

  @override
  State<_TabsBar> createState() => _TabsBarState();
}

class _TabsBarState extends State<_TabsBar> {
  final _ctrl = ScrollController();
  bool _canBack = false; // can scroll toward the start
  bool _canForward = false; // can scroll toward the end

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_update);
    _lastIndex = widget.p.selectedTabIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  int _lastIndex = -1;

  @override
  void didUpdateWidget(covariant _TabsBar old) {
    super.didUpdateWidget(old);
    // Rebuilds happen on every page append — only follow the selection when the TAB changed,
    // otherwise the bar would keep jumping while the user scrolls it by hand.
    final changed = widget.p.selectedTabIndex != _lastIndex;
    _lastIndex = widget.p.selectedTabIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _update();
      if (changed) _revealSelected();
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_update);
    _ctrl.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final back = pos.pixels > 2;
    final fwd = pos.pixels < pos.maxScrollExtent - 2;
    if (back != _canBack || fwd != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
    }
  }

  /// Keeps the selected pill in view after a tab change.
  void _revealSelected() {
    final n = widget.p.tabs.length;
    if (!_ctrl.hasClients || n < 2) return;
    final frac = widget.p.selectedTabIndex / (n - 1);
    _ctrl.animateTo(
      (_ctrl.position.maxScrollExtent * frac).clamp(
        0.0,
        _ctrl.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollBy(double delta) {
    if (!_ctrl.hasClients) return;
    _ctrl.animateTo(
      (_ctrl.offset + delta).clamp(0.0, _ctrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    final c = context.colors;
    return SizedBox(
      width: 38,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Center(
            child: Material(
              color: c.cardBg,
              elevation: 1.5,
              shadowColor: Colors.black26,
              shape: CircleBorder(side: BorderSide(color: c.divider)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(icon, size: 20, color: c.textMedium),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // ShaderMask works in physical left→right space, so swap the sides in RTL.
    final fadeLeft = rtl ? _canForward : _canBack;
    final fadeRight = rtl ? _canBack : _canForward;

    final pills = Row(
      children: [
        for (int i = 0; i < p.tabs.length; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: _TabPill(
              label: p.tabs[i].label(context),
              count: p.tabs[i].count,
              selected: i == p.selectedTabIndex,
              onTap: () => widget.onSelect(i),
            ),
          ),
      ],
    );

    return SizedBox(
      height: 46,
      child: Row(
        children: [
          _arrow(
            rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            _canBack,
            () => _scrollBy(-240),
          ),
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _update());
                return false;
              },
              child: ScrollConfiguration(
                // allow dragging with the mouse / trackpad on web + desktop
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => LinearGradient(
                    colors: [
                      fadeLeft ? Colors.transparent : Colors.black,
                      Colors.black,
                      Colors.black,
                      fadeRight ? Colors.transparent : Colors.black,
                    ],
                    stops: const [0, 0.08, 0.92, 1],
                  ).createShader(r),
                  child: SingleChildScrollView(
                    controller: _ctrl,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    child: pills,
                  ),
                ),
              ),
            ),
          ),
          _arrow(
            rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            _canForward,
            () => _scrollBy(240),
          ),
        ],
      ),
    );
  }
}

/// One class (tab): gradient pill when selected, with the number of features in a small badge.
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [c.primary, c.primaryDark])
                : null,
            color: selected ? null : c.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? Colors.transparent : c.divider,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : c.textMedium,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : c.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : c.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One feature
// ═════════════════════════════════════════════════════════════════════════════

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.f, {required this.platforms});

  final FeatureItem f;
  final List<String> platforms;

  static String _platformName(String p) {
    switch (p.toLowerCase()) {
      case 'ios':
        return 'iOS';
      case 'android':
        return 'Android';
      case 'web':
        return 'Web';
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminFeaturesProvider>();
    final busy = context.select<AdminFeaturesProvider, bool>(
      (x) => x.isLoading,
    );
    final isAr = AppConfig.lang == 'ar';
    final hiddenAnywhere = f.isHiddenAnywhere;
    final allowed = f.allowToAdmin;
    // second-language name, shown small under the main label
    final other = isAr ? f.labelEn : f.labelAr;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hiddenAnywhere
            ? Color.alphaBlend(c.warning.withValues(alpha: 0.06), c.cardBg)
            : c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hiddenAnywhere ? c.warning.withValues(alpha: 0.6) : c.divider,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.label,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontWeight: FontWeight.w800,
                        color: c.textDark,
                      ),
                    ),
                    if (other.isNotEmpty && other != f.label && other != f.key)
                      Text(
                        other,
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 12,
                          color: c.textMedium,
                        ),
                      ),
                    Text(
                      f.key,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11.5, color: c.textLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppSwitch(
                // ON = visible everywhere, OFF = hidden on at least one platform
                value: !hiddenAnywhere,
                activeColor: c.success,
                onChanged: busy ? null : (visible) => p.set(f.key, !visible),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final pl in platforms)
                FilterChip(
                  label: Text(
                    _platformName(pl),
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: f.isHiddenOn(pl),
                  selectedColor: c.warning.withValues(alpha: 0.3),
                  avatar: Icon(
                    f.isHiddenOn(pl)
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 16,
                  ),
                  onSelected: busy
                      ? null
                      : (hide) => p.set(f.key, hide, platforms: [pl]),
                ),
            ],
          ),
          // Super-admin only: grant this feature to admins.
          if (p.isSuperAdmin) ...[
            Divider(height: 18, color: c.divider),
            Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 16,
                  color: allowed ? c.success : c.textLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr ? 'يمكن للمدير التحكم بها' : 'Admins can manage this',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      color: allowed ? c.success : c.textMedium,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppSwitch(
                  value: allowed,
                  activeColor: c.success,
                  onChanged: busy ? null : (v) => p.setAllowToAdmin(f.key, v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Add a feature (super-admin)
//  Needs: class (existing or new) · key · Arabic name · English name
// ═════════════════════════════════════════════════════════════════════════════

class _AddFeatureDialog extends StatefulWidget {
  const _AddFeatureDialog({required this.provider});

  final AdminFeaturesProvider provider;

  @override
  State<_AddFeatureDialog> createState() => _AddFeatureDialogState();
}

class _AddFeatureDialogState extends State<_AddFeatureDialog> {
  static final _keyRe = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.\-]*$');

  final _key = TextEditingController();
  final _titleAr = TextEditingController();
  final _titleEn = TextEditingController();
  final _tabAr = TextEditingController();
  final _tabEn = TextEditingController();

  String? _tabId; // chosen existing class
  late bool _newTab; // true = create a new class
  bool _allow = false;
  bool _hideNow = false;
  bool _saving = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final tabs = widget.provider.tabs;
    _newTab = tabs.isEmpty;
    final i = widget.provider.selectedTabIndex;
    if (tabs.isNotEmpty && i >= 0 && i < tabs.length) _tabId = tabs[i].id;
  }

  @override
  void dispose() {
    for (final x in [_key, _titleAr, _titleEn, _tabAr, _tabEn]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final isAr = AppConfig.lang == 'ar';
    final required = isAr ? 'كل الحقول مطلوبة' : 'All fields are required';
    final key = _key.text.trim();
    final ar = _titleAr.text.trim();
    final en = _titleEn.text.trim();
    final tAr = _tabAr.text.trim();
    final tEn = _tabEn.text.trim();

    String? err;
    if (key.isEmpty || ar.isEmpty || en.isEmpty) {
      err = required;
    } else if (!_keyRe.hasMatch(key)) {
      err = isAr
          ? 'المفتاح: حروف إنجليزية وأرقام و _ . - فقط'
          : 'Key: letters, digits and _ . - only';
    } else if (_newTab && (tAr.isEmpty || tEn.isEmpty)) {
      err = isAr
          ? 'اكتب اسم التصنيف بالعربية والإنجليزية'
          : 'Enter the class name in Arabic and English';
    } else if (!_newTab && _tabId == null) {
      err = isAr ? 'اختر تصنيفًا' : 'Choose a class';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }

    setState(() {
      _saving = true;
      _err = null;
    });
    final ok = await widget.provider.createFeature(
      key: key,
      titleAr: ar,
      titleEn: en,
      tabId: _newTab ? null : _tabId,
      tabAr: _newTab ? tAr : null,
      tabEn: _newTab ? tEn : null,
      allowToAdmin: _allow,
      hidden: _hideNow,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(
        () => _saving = false,
      ); // the server's message was already toasted
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = widget.provider.tabs;
    final isAr = AppConfig.lang == 'ar';
    TextStyle label([Color? color]) => TextStyle(
      fontFamily: 'tajawal',
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: color ?? c.textMedium,
    );

    return AlertDialog(
      title: Text(
        AppConfig.lang == 'ar' ? 'إضافة ميزة جديدة' : 'Add a new feature',
        style: const TextStyle(
          fontFamily: 'tajawal',
          fontWeight: FontWeight.w800,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAr ? 'التصنيف' : 'Class (tab)', style: label()),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in tabs)
                    ChoiceChip(
                      label: Text(
                        t.label(context),
                        style: const TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 12,
                        ),
                      ),
                      selected: !_newTab && _tabId == t.id,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _newTab = false;
                              _tabId = t.id;
                            }),
                    ),
                  ChoiceChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      isAr ? 'تصنيف جديد' : 'New class',
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 12,
                      ),
                    ),
                    selected: _newTab,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _newTab = true),
                  ),
                ],
              ),
              if (_newTab) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _tabAr,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: isAr
                        ? 'اسم التصنيف بالعربية'
                        : 'Class name (Arabic)',
                  ),
                ),
                TextField(
                  controller: _tabEn,
                  enabled: !_saving,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: isAr
                        ? 'اسم التصنيف بالإنجليزية'
                        : 'Class name (English)',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _key,
                enabled: !_saving,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: isAr ? 'مفتاح الميزة (Key)' : 'Feature key',
                  hintText: 'profile.delete_account',
                ),
              ),
              TextField(
                controller: _titleAr,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: isAr ? 'الاسم بالعربية' : 'Name (Arabic)',
                ),
              ),
              TextField(
                controller: _titleEn,
                enabled: !_saving,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: isAr ? 'الاسم بالإنجليزية' : 'Name (English)',
                ),
              ),
              const SizedBox(height: 6),
              AppSwitchTile(
                dense: true,
                value: _allow,
                activeColor: c.success,
                onChanged: _saving ? null : (v) => setState(() => _allow = v),
                title: isAr ? 'السماح للمدير بالتحكم بها' : 'Let admins manage it',
              ),
              AppSwitchTile(
                dense: true,
                value: _hideNow,
                activeColor: c.warning,
                onChanged: _saving ? null : (v) => setState(() => _hideNow = v),
                title: isAr
                    ? 'إخفاؤها الآن على كل المنصات'
                    : 'Hide it now on all platforms',
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _err!,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      color: c.warning,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            isAr ? 'إلغاء' : 'Cancel',
            style: const TextStyle(fontFamily: 'tajawal'),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: c.primary),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppLoadingIndicator(showLogo: false,),
                )
              : Text(
                  isAr ? 'إضافة' : 'Add',
                  style: const TextStyle(
                    fontFamily: 'tajawal',
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }
}
