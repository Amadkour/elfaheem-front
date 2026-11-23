// lib/features/games/admin/v4/hadith_picker.dart — the Hadith picker (Games v4 T65, CONTRACT §9, §10).
//
//   showHadithPicker(context, api)   a sheet: collection + number or text search, source and grade shown on every
//                                    hadith, optional matn marking → HadithPick(ref) or null
//   HadithPickerView                 the body over plain values (test/games/v4_admin_test.dart)
//   HadithMatnMarker                 tap a first word and a last word: the matn = words[from:to]
//
// The text is READ-ONLY (Quran role face); only the matn limits can be marked, and that is the reviewer's call
// (`PUT /hadith/{id}/matn`: 403 `review_required` for anyone else). The result is a reference `@hadith:bukhari:1`.
// A hadith feeds a sequence item only when its resolved words are 2..25 (CONTRACT §9): the card says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show quranTextStyle;

class HadithPick {
  const HadithPick({required this.collection, required this.number, required this.label});
  final String collection;
  final int number;
  final String label;

  String get tokens => '@hadith:$collection:$number';
  String get sourceRef => '$collection:$number';
}

String hadithCollectionName(String k) => switch (k) {
      'bukhari' => t('صحيح البخاري', 'Sahih al-Bukhari'),
      'muslim' => t('صحيح مسلم', 'Sahih Muslim'),
      _ => k,
    };

/// Words the item will use: the marked matn, else all of it.
int hadithResolvedWords(Json h) {
  final wc = jint(h['word_count']);
  final a = h['matn_from'], b = h['matn_to'];
  return a is num && b is num ? (b - a).toInt() : wc;
}

Future<HadithPick?> showHadithPicker(BuildContext context, {ItemsV4Api? api}) =>
    showAppSheet<HadithPick>(context, (_) => _HadithPickerSheet(api: api ?? ItemsV4Api()));

class _HadithPickerSheet extends StatefulWidget {
  const _HadithPickerSheet({required this.api});
  final ItemsV4Api api;

  @override
  State<_HadithPickerSheet> createState() => _HadithPickerSheetState();
}

class _HadithPickerSheetState extends State<_HadithPickerSheet> {
  String? _collection;
  int? _number;
  String _q = '';
  List<Json> _items = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.api.hadith(collection: _collection, number: _number, q: _q, limit: 20);
      if (mounted && seq == _seq) setState(() { _items = p.items; _total = p.total; _loading = false; });
    } catch (e) {
      if (mounted && seq == _seq) setState(() { _loading = false; _error = itemErrorText(e); });
    }
  }

  @override
  Widget build(BuildContext context) => HadithPickerView(
        items: _items,
        total: _total,
        collection: _collection,
        number: _number,
        loading: _loading,
        error: _error,
        onCollection: (v) {
          _collection = v;
          _load();
        },
        onNumber: (v) {
          _number = v;
          _load();
        },
        onSearch: (v) {
          _q = v;
          _load();
        },
        onMatn: (h, from, to) async {
          try {
            final saved = await widget.api.setMatn(jint(h['id']), from, to);
            if (!mounted) return;
            setState(() => _items = [for (final x in _items) x['id'] == saved['id'] ? saved : x]);
            showAppNotice(t('حُفظ حدّ المتن', 'Matn limits saved'));
          } catch (e) {
            showAppNotice(itemErrorText(e), error: true);
          }
        },
        onUse: (h) => Navigator.of(context).pop(HadithPick(
          collection: '${h['collection']}',
          number: jint(h['number']),
          label: '${hadithCollectionName('${h['collection']}')} ${h['number']}',
        )),
      );
}

class HadithPickerView extends StatelessWidget {
  const HadithPickerView({
    super.key,
    required this.items,
    required this.total,
    required this.collection,
    required this.number,
    required this.onCollection,
    required this.onNumber,
    required this.onSearch,
    required this.onMatn,
    required this.onUse,
    this.loading = false,
    this.error,
  });

  final List<Json> items;
  final int total;
  final String? collection;
  final int? number;
  final bool loading;
  final String? error;
  final ValueChanged<String?> onCollection;
  final ValueChanged<int?> onNumber;
  final ValueChanged<String> onSearch;
  final void Function(Json hadith, int? from, int? to) onMatn;
  final ValueChanged<Json> onUse;

  @override
  Widget build(BuildContext context) {
    return AppSheetContent(
      title: t('اختيار حديث', 'Pick a hadith'),
      children: [
        Row(children: [
          Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: context.colors.textMedium),
          AppSpace.gapXs,
          Expanded(child: Text(t('النص للقراءة فقط ولا يُعدَّل.', 'The text is read-only and cannot be changed.'), style: AppType.meta(context))),
        ]),
        AppSpace.gapSm,
        EdSelect<String>(
          label: t('الكتاب', 'Collection'),
          value: collection ?? '',
          options: [('', t('الكل', 'All')), ('bukhari', hadithCollectionName('bukhari')), ('muslim', hadithCollectionName('muslim'))],
          onChanged: (v) => onCollection(v.isEmpty ? null : v),
        ),
        AppSpace.gapSm,
        AppNumberField(label: t('رقم الحديث', 'Hadith number'), initialValue: number, min: 1, onChanged: (v) => onNumber(v?.toInt())),
        AppSpace.gapSm,
        AppSearchField(hint: t('ابحث في نص الحديث', 'Search the hadith text'), onChanged: onSearch),
        AppSpace.gapSm,
        if (error != null) AppBanner(icon: Icons.error_outline_rounded, text: error!, color: context.colors.danger),
        if (loading)
          const AppListSkeleton(items: 2)
        else if (items.isEmpty)
          AppEmpty(icon: Icons.menu_book_rounded, title: t('لا نتائج', 'Nothing found'), message: t('جرّب رقماً أو كلمة أخرى.', 'Try another number or word.'))
        else ...[
          Text(t('$total نتيجة', '$total found'), style: AppType.meta(context)),
          AppSpace.gapXs,
          for (final h in items)
            Padding(
              key: ValueKey('h${h['id']}'),
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: HadithCard(hadith: h, onMatn: (a, b) => onMatn(h, a, b), onUse: () => onUse(h)),
            ),
        ],
      ],
    );
  }
}

/// One hadith: source line, grade, the text with the matn marked, and the buttons.
class HadithCard extends StatefulWidget {
  const HadithCard({super.key, required this.hadith, required this.onMatn, required this.onUse});
  final Json hadith;
  final void Function(int? from, int? to) onMatn;
  final VoidCallback onUse;

  @override
  State<HadithCard> createState() => _HadithCardState();
}

class _HadithCardState extends State<HadithCard> {
  bool _marking = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = widget.hadith;
    final words = '${h['text_ar'] ?? ''}'.split(' ').where((w) => w.isNotEmpty).toList();
    final resolved = hadithResolvedWords(h);
    final fits = resolved >= 2 && resolved <= 25;
    final grade = '${h['grade'] ?? ''}';
    final src = '${h['grade_source'] ?? ''}';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${hadithCollectionName('${h['collection']}')} · ${h['number']}', style: AppType.bodyStrong(context)),
          if (grade.isNotEmpty) AppStatusBadge(label: grade, tone: AppTone.success, dense: true),
        ]),
        if ('${h['book'] ?? ''}'.isNotEmpty || '${h['chapter'] ?? ''}'.isNotEmpty)
          Text([if ('${h['book'] ?? ''}'.isNotEmpty) '${h['book']}', if ('${h['chapter'] ?? ''}'.isNotEmpty) '${h['chapter']}'].join(' › '),
              style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (src.isNotEmpty) Text(t('مصدر الدرجة: $src', 'Grade source: $src'), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        AppSpace.gapSm,
        if (_marking)
          HadithMatnMarker(
            words: words,
            from: h['matn_from'] is num ? jint(h['matn_from']) : null,
            to: h['matn_to'] is num ? jint(h['matn_to']) : null,
            onSave: (a, b) {
              setState(() => _marking = false);
              widget.onMatn(a, b);
            },
            onCancel: () => setState(() => _marking = false),
          )
        else
          Text(words.join(' '), textDirection: TextDirection.rtl, style: quranTextStyle(16, color: c.textDark), maxLines: 6, overflow: TextOverflow.ellipsis),
        AppSpace.gapSm,
        Text(
          fits
              ? t('$resolved كلمة تدخل في الترتيب', '$resolved words feed the ordering game')
              : t('$resolved كلمة: يلزم من 2 إلى 25، حدّد المتن', '$resolved words: 2 to 25 needed, mark the matn'),
          style: AppType.meta(context).copyWith(color: fits ? c.textMedium : c.warning),
        ),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(label: t('تحديد المتن', 'Mark the matn'), size: AppButtonSize.sm, onPressed: () => setState(() => _marking = !_marking)),
          AppButton.primary(label: t('استخدام', 'Use'), size: AppButtonSize.sm, onPressed: fits ? widget.onUse : null),
        ]),
      ]),
    );
  }
}

/// Tap the first word of the matn, then the last: [onSave] gets (from, to) as `words[from:to]`; "Whole text" clears.
class HadithMatnMarker extends StatefulWidget {
  const HadithMatnMarker({super.key, required this.words, this.from, this.to, required this.onSave, required this.onCancel});
  final List<String> words;
  final int? from;
  final int? to;
  final void Function(int? from, int? to) onSave;
  final VoidCallback onCancel;

  @override
  State<HadithMatnMarker> createState() => _HadithMatnMarkerState();
}

class _HadithMatnMarkerState extends State<HadithMatnMarker> {
  int? _a;
  int? _b; // inclusive while editing

  @override
  void initState() {
    super.initState();
    _a = widget.from;
    _b = widget.to == null ? null : widget.to! - 1;
  }

  void _tap(int i) => setState(() {
        if (_a == null || (_b != null && _a != _b) || i < _a!) {
          _a = i;
          _b = null;
        } else {
          _b = i;
        }
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lo = _a, hi = _b ?? _a;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('المس أول كلمة في المتن ثم آخر كلمة.', 'Tap the first word of the matn, then the last.'), style: AppType.meta(context)),
      AppSpace.gapXs,
      Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (var i = 0; i < widget.words.length; i++)
            InkWell(
              onTap: () => _tap(i),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Container(
                constraints: const BoxConstraints(minHeight: AppTouch.min / 1.5),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lo != null && hi != null && i >= lo && i <= hi ? c.primary.withValues(alpha: 0.2) : null,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(widget.words[i], style: quranTextStyle(15, color: c.textDark)),
              ),
            ),
        ]),
      ),
      AppSpace.gapSm,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppButton.primary(
          label: t('حفظ المتن', 'Save the matn'),
          size: AppButtonSize.sm,
          onPressed: lo == null ? null : () => widget.onSave(lo, (hi ?? lo) + 1),
        ),
        AppButton.secondary(label: t('النص كله', 'Whole text'), size: AppButtonSize.sm, onPressed: () => widget.onSave(null, null)),
        AppButton.ghost(label: t('إلغاء', 'Cancel'), size: AppButtonSize.sm, onPressed: widget.onCancel),
      ]),
    ]);
  }
}
