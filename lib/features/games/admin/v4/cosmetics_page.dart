// lib/features/games/admin/v4/cosmetics_page.dart — SUPER ADMIN: the learner's outfits (Games v4 T71, CONTRACT §8, §10).
// `GET / POST /admin/games/v4/cosmetics`, `PUT …/cosmetics/{key}` with `{key, slot, name_ar, name_en, price_coins,
// unlock_rule?, enabled, sort}`. An item is bought with coins (`unlock_rule` null) or opened by an achievement
// (`{type: stars | levels | champion, count}`). Nothing here costs real money. Kill switch `games.cosmetics` (learner side).
//
//   GamesCosmeticsPage   loads the items, the on / off switch, the add / edit sheet
//   GamesCosmeticsBody   plain values: one card per item
//   CosmeticForm         the sheet's form: plain values in, the server's body out
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/admin_grid.dart';
import 'package:flutter_education_app/features/games/admin/v4/admin_more_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

const List<String> kCosmeticSlots = ['hat', 'outfit', 'vehicle', 'trail'];
const List<String> kCosmeticRules = ['stars', 'levels', 'champion'];

String cosmeticSlotName(String k) => switch (k) {
      'hat' => t('قبعة', 'Hat'),
      'outfit' => t('ملابس', 'Outfit'),
      'vehicle' => t('مركبة', 'Vehicle'),
      'trail' => t('أثر', 'Trail'),
      _ => k,
    };

String cosmeticRuleName(String k) => switch (k) {
      'stars' => t('نجوم', 'Stars'),
      'levels' => t('مستويات مكتملة', 'Levels finished'),
      'champion' => t('مرات بطل اليوم', 'Champion wins'),
      _ => k,
    };

/// How an item is got, in one line.
String cosmeticHow(Json c) {
  final rule = c['unlock_rule'];
  if (rule is Map && rule['type'] != null) {
    final n = rule['count'] ?? 1;
    return switch ('${rule['type']}') {
      'stars' => t('يُفتح عند جمع $n نجمة', 'Opens at $n stars'),
      'levels' => t('يُفتح بعد إنهاء $n مستوى', 'Opens after $n finished levels'),
      'champion' => t('يُفتح بعد الفوز ببطل اليوم $n مرة', 'Opens after $n champion wins'),
      _ => t('يُفتح بـ $n ${cosmeticRuleName('${rule['type']}')}', 'Opens with $n ${cosmeticRuleName('${rule['type']}')}'),
    };
  }
  final p = c['price_coins'] is num ? (c['price_coins'] as num).toInt() : 0;
  return p == 0 ? t('مجاني', 'Free') : t('$p عملة', '$p coins');
}

class GamesCosmeticsPage extends StatefulWidget {
  const GamesCosmeticsPage({super.key, this.api});
  final GamesAdminMoreApi? api;

  @override
  State<GamesCosmeticsPage> createState() => _GamesCosmeticsPageState();
}

class _GamesCosmeticsPageState extends State<GamesCosmeticsPage> {
  late final GamesAdminMoreApi _api = widget.api ?? GamesAdminMoreApi();
  List<Json>? _items;
  String? _error, _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.cosmetics();
      if (mounted) setState(() { _items = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = adminMoreErrorText(e));
    }
  }

  Future<void> _toggle(Json c, bool on) async {
    final key = '${c['key']}';
    setState(() => _busy = key);
    try {
      final saved = await _api.updateCosmetic(key, {'enabled': on});
      if (mounted) setState(() => _items = [for (final x in _items!) x['key'] == key ? saved : x]);
    } catch (e) {
      showAppNotice(adminMoreErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _edit([Json? c]) async {
    final saved = await showAppSheet<Json>(
      context,
      (ctx) => AppSheetContent(
        title: c == null ? t('عنصر جديد', 'New item') : t('تعديل العنصر', 'Edit item'),
        children: [CosmeticForm(initial: c, onSubmit: (body) => c == null ? _api.createCosmetic(body) : _api.updateCosmetic('${c['key']}', body))],
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final list = [..._items!];
      final i = list.indexWhere((x) => x['key'] == saved['key']);
      if (i < 0) {
        list.add(saved);
      } else {
        list[i] = saved;
      }
      _items = list;
    });
  }

  @override
  Widget build(BuildContext context) => AdminPage(
      helpPageId: 'admin.games.cosmetics',
        width: AppWidth.content,
        title: t('ملابس اللاعب', 'Outfits'),
        subtitle: t('قبعات وملابس ومركبات يشتريها الطلاب بالعملات', 'Hats, outfits and vehicles learners buy with coins'),
        icon: Icons.checkroom_rounded,
        onRefresh: _load,
        primaryAction: AppButton.primary(key: const ValueKey('games.cosmetics.add'), label: t('أضف عنصراً', 'Add item'), icon: Icons.add_rounded, onPressed: () => _edit()),
        body: _error != null && _items == null
            ? AppErrorState(message: _error!, onRetry: _load)
            : GamesCosmeticsBody(items: _items, busyKey: _busy, onToggle: _toggle, onEdit: _edit),
      );
}

class GamesCosmeticsBody extends StatelessWidget {
  const GamesCosmeticsBody({super.key, required this.items, this.busyKey, this.onToggle, this.onEdit});
  final List<Json>? items;
  final String? busyKey;
  final void Function(Json item, bool on)? onToggle;
  final ValueChanged<Json>? onEdit;

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null) return const AppListSkeleton(items: 4);
    if (list.isEmpty) return AppEmpty(icon: Icons.checkroom_rounded, title: t('لا عناصر بعد', 'No items yet'), message: t('أضف أول قبعة أو ملابس.', 'Add the first hat or outfit.'));
    final ar = AppConfig.lang == 'ar';
    return ListView(padding: AdminPage.bodyPadding(context), children: [
      GamesCardGrid(children: [
      for (final c in list)
        AppCard(
          onTap: onEdit == null ? null : () => onEdit!(c),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${ar ? c['name_ar'] : c['name_en']}', style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                AppSpace.gapXs,
                Text('${cosmeticSlotName('${c['slot']}')} · ${cosmeticHow(c)}', style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            AppSpace.gapSm,
            AppSwitch(
              value: c['enabled'] != false,
              semanticLabel: t('تشغيل العنصر', 'Item on'),
              onChanged: busyKey == '${c['key']}' || onToggle == null ? null : (v) => onToggle!(c, v),
            ),
          ]),
        ),
      ]),
    ]);
  }
}

class CosmeticForm extends StatefulWidget {
  const CosmeticForm({super.key, this.initial, required this.onSubmit});
  final Json? initial;
  final Future<Json> Function(Json body) onSubmit;

  @override
  State<CosmeticForm> createState() => _CosmeticFormState();
}

class _CosmeticFormState extends State<CosmeticForm> {
  late final Json _c = widget.initial ?? <String, dynamic>{};
  late final _key = TextEditingController(text: '${_c['key'] ?? ''}');
  late final _nameAr = TextEditingController(text: '${_c['name_ar'] ?? ''}');
  late final _nameEn = TextEditingController(text: '${_c['name_en'] ?? ''}');
  late final _price = TextEditingController(text: '${_c['price_coins'] ?? 0}');
  late final _count = TextEditingController(text: '${(_c['unlock_rule'] is Map ? (_c['unlock_rule'] as Map)['count'] : null) ?? 1}');
  late String _slot = kCosmeticSlots.contains(_c['slot']) ? '${_c['slot']}' : 'hat';
  late bool _byRule = _c['unlock_rule'] is Map && (_c['unlock_rule'] as Map)['type'] != null;
  late String _ruleType = _byRule ? '${(_c['unlock_rule'] as Map)['type']}' : 'stars';
  late bool _enabled = _c['enabled'] != false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_key, _nameAr, _nameEn, _price, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final isNew = widget.initial == null;
    if (_nameAr.text.trim().isEmpty || _nameEn.text.trim().isEmpty || (isNew && _key.text.trim().length < 2)) {
      setState(() => _error = t('اكتب الاسم بالعربية والإنجليزية والمفتاح', 'Enter the Arabic and English names and the key'));
      return;
    }
    final body = <String, dynamic>{
      if (isNew) 'key': _key.text.trim().toLowerCase(),
      'slot': _slot,
      'name_ar': _nameAr.text.trim(),
      'name_en': _nameEn.text.trim(),
      'price_coins': _byRule ? 0 : (int.tryParse(_price.text.trim()) ?? 0),
      'unlock_rule': _byRule ? {'type': _ruleType, 'count': int.tryParse(_count.text.trim()) ?? 1} : null,
      'enabled': _enabled,
    };
    setState(() { _busy = true; _error = null; });
    try {
      final saved = await widget.onSubmit(body);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = adminMoreErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.initial == null) ...[
          AppField(controller: _key, label: t('المفتاح (حروف لاتينية صغيرة وأرقام و _)', 'Key (lowercase letters, numbers, _)'), ltr: true),
          AppSpace.gapSm,
        ],
        AppField(controller: _nameAr, label: t('الاسم بالعربية', 'Arabic name')),
        AppSpace.gapSm,
        AppField(controller: _nameEn, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
        AppSpace.gapSm,
        AppDropdown<String>(
          decoration: InputDecoration(labelText: t('الخانة', 'Slot')),
          value: _slot,
          items: [for (final s in kCosmeticSlots) DropdownMenuItem(value: s, child: Text(cosmeticSlotName(s), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _slot = v ?? _slot),
        ),
        AppSpace.gapSm,
        AppDropdown<bool>(
          decoration: InputDecoration(labelText: t('كيف يحصل عليه الطالب', 'How a learner gets it')),
          value: _byRule,
          items: [
            DropdownMenuItem(value: false, child: Text(t('يشتريه بالعملات', 'Buys it with coins'), overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: true, child: Text(t('يفتحه بإنجاز', 'Opens it by an achievement'), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _byRule = v ?? false),
        ),
        AppSpace.gapSm,
        if (_byRule) ...[
          AppDropdown<String>(
            decoration: InputDecoration(labelText: t('الإنجاز', 'Achievement')),
            value: _ruleType,
            items: [for (final r in kCosmeticRules) DropdownMenuItem(value: r, child: Text(cosmeticRuleName(r), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _ruleType = v ?? _ruleType),
          ),
          AppSpace.gapSm,
          AppNumberField(controller: _count, label: t('العدد المطلوب', 'How many'), min: 1, max: 100000),
        ] else
          AppNumberField(controller: _price, label: t('السعر بالعملات (0 = مجاني)', 'Price in coins (0 = free)'), min: 0, max: 100000),
        AppSpace.gapSm,
        AppSwitchTile(title: t('يظهر للطلاب', 'Shown to learners'), icon: Icons.visibility_rounded, value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
        if (_error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger),
        ],
        AppSpace.gapMd,
        AppButton.primary(
            key: const ValueKey('games.cosmetics.save'), label: t('حفظ', 'Save'), icon: Icons.check_rounded, expand: true, busy: _busy, onPressed: _busy ? null : _save),
      ]);
}
